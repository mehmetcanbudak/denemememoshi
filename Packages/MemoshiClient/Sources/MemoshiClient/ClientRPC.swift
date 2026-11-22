import Foundation
import MemoshiProtocol
import MemoshiTransport

struct PendingCall: Sendable {
  let continuation: CheckedContinuation<Data, any Error>
  let timeout: Task<Void, Never>
  let send: Task<Void, Never>
  /// A public call: a lost connection is reported to it as `ClientError.connectionClosed`.
  /// Lifecycle requests keep the carrier's error, which decides the connect classification.
  let normalizesLoss: Bool
}

extension MemoshiClient {
  /// Calls are never automatically retried. A timeout/cancellation does not prove a mutating
  /// operation was not applied; any deliberate retry must retain its original requestId.
  public func call<Method: RPCMethod>(
    _ method: Method.Type, _ params: Method.Params
  ) async throws -> Method.Result {
    guard connection != nil, statusValue.hello != nil else { throw ClientError.notConnected }
    guard !Method.isMutating || statusValue.state == .connected else {
      throw ClientError.notSynchronized
    }
    guard Method.name != SystemHello.name, Method.name != EventsSubscribe.name,
      Method.name != EventsUnsubscribe.name, Method.name != EventsFocus.name
    else {
      throw ClientError.protocolViolation("Use the client's connection/subscription lifecycle API")
    }
    return try await request(method, params, generation: generation, normalizesLoss: true)
  }

  func request<Method: RPCMethod>(
    _ method: Method.Type, _ params: Method.Params, generation expected: UInt64,
    normalizesLoss: Bool = false
  ) async throws -> Method.Result {
    try Task.checkCancellation()
    guard generation == expected, let connection else { throw ClientError.disconnected }
    let limit = min(statusValue.hello?.limits.maxInFlightRequests ?? 64, 64)
    guard pending.count < limit else { throw ClientError.inFlightLimit(limit) }
    guard nextRequestID < UInt64.max else {
      throw ClientError.protocolViolation("Request ID space exhausted")
    }
    nextRequestID += 1
    let id = try JSONRPCID("c:\(nextRequestID)")
    let frame = try codec.encodeRequest(method, id: id, params: params)
    let maximum = min(statusValue.hello?.limits.maxInboundBytes ?? 1_048_576, 1_048_576)
    guard frame.count <= maximum else {
      throw ClientError.protocolViolation("Request exceeds negotiated inbound limit")
    }
    let data: Data = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume(throwing: CancellationError())
          return
        }
        let timeout = Task { [sleep, weak self] in
          do {
            try await sleep(self?.configuration.requestTimeout ?? .seconds(30))
            try Task.checkCancellation()
            await self?.expireCall(id.rawValue, method: Method.name, generation: expected)
          } catch {}
        }
        let send = Task { [weak self, connection] in
          do {
            try Task.checkCancellation()
            try await connection.send(frame)
          } catch {
            await self?.sendFailed(error, id: id.rawValue, generation: expected)
          }
        }
        pending[id.rawValue] = PendingCall(
          continuation: continuation, timeout: timeout, send: send,
          normalizesLoss: normalizesLoss)
        publishStatus()
      }
    } onCancel: {
      Task { await self.cancelCall(id.rawValue, generation: expected) }
    }
    try Task.checkCancellation()
    do {
      let response = try codec.decodeResponse(method, from: data)
      guard response.id == id else {
        throw ClientError.protocolViolation("Response ID does not match request")
      }
      return try response.get()
    } catch let error as RPCError {
      throw error
    } catch {
      let failure = ClientError.protocolViolation("Malformed typed RPC response")
      await connectionLost(failure, generation: expected)
      throw failure
    }
  }

  func receive(_ frame: Data, generation expected: UInt64) async throws {
    guard expected == generation, connection != nil else { return }
    guard frame.count <= 4 * 1024 * 1024 else {
      throw ClientError.protocolViolation("Inbound frame exceeds protocol limit")
    }
    let kind: JSONRPCFrameKind
    do { kind = try codec.inspect(frame) } catch {
      throw ClientError.protocolViolation("Malformed JSON-RPC frame")
    }
    switch kind {
    case .response(let id):
      guard let id else { throw ClientError.protocolViolation("Uncorrelated JSON-RPC error") }
      // Responses to a canceled or timed-out call are expected and must not resurrect it.
      finishCall(id, result: .success(frame))
    case .notification(let method):
      switch method {
      case EventNotification.method: try receiveEvents(frame)
      case "system.cancel": try receiveHostCancellation(frame, generation: expected)
      default: throw ClientError.protocolViolation("Unknown notification method")
      }
    case .batch(let count):
      let limit = min(statusValue.hello?.limits.maxBatchEvents ?? 256, 256)
      guard count > 0, count <= limit else {
        throw ClientError.protocolViolation("Invalid event batch size")
      }
      try receiveEvents(frame)
    case .request(let id, let method):
      try receiveHostRequest(frame, id: id, method: method, generation: expected)
    }
  }

  func receiveEvents(_ frame: Data) throws {
    guard subscribed || subscriptionPending else {
      throw ClientError.protocolViolation("Events received before subscription")
    }
    let events: [EventEnvelope]
    do { events = try codec.decodeEvents(from: frame) } catch {
      throw ClientError.protocolViolation("Malformed event notification")
    }
    let bytes = max(1, frame.count / max(events.count, 1))
    for envelope in events {
      let entry = EventBuffer.Entry(envelope: envelope, bytes: bytes)
      if subscriptionPending {
        try stage(entry)
      } else {
        try acceptEvent(entry)
      }
    }
  }

  func finishCall(_ id: String, result: Result<Data, any Error>) {
    guard let call = pending.removeValue(forKey: id) else { return }
    call.timeout.cancel()
    call.send.cancel()
    call.continuation.resume(with: result)
    publishStatus()
    startResubscribeIfNeeded()
  }

  func cancelCall(_ id: String, generation expected: UInt64) {
    guard expected == generation else { return }
    finishCall(id, result: .failure(CancellationError()))
  }

  func expireCall(_ id: String, method: String, generation expected: UInt64) {
    guard expected == generation else { return }
    finishCall(id, result: .failure(ClientError.requestTimedOut(method: method)))
  }

  func sendFailed(_ error: any Error, id: String, generation expected: UInt64) async {
    guard expected == generation, pending[id] != nil, !(error is CancellationError) else { return }
    if let failure = error as? IPCError, failure == .outboundOverflow {
      finishCall(id, result: .failure(failure))
      return
    }
    await connectionLost(error, generation: expected)
  }

  func failPending(_ error: any Error) {
    let loss = connectionLoss(error)
    for call in pending.values {
      call.timeout.cancel()
      call.send.cancel()
      call.continuation.resume(throwing: call.normalizesLoss ? loss : error)
    }
    pending.removeAll(keepingCapacity: true)
  }

  /// What a public call is told when its connection is torn down. A plain transport loss is
  /// `ClientError.connectionClosed` whatever error type the carrier used. A cause the client
  /// classifies as more than a loss (signing, authentication, version) keeps its typed error.
  func connectionLoss(_ error: any Error) -> any Error {
    if error is ClientError || error is CancellationError { return error }
    if case .closed(let code, let reason)? = error as? IPCError {
      return ClientError.connectionClosed(code: code, reason: reason)
    }
    guard classify(error).1 == .transport, canReconnect(after: error) else { return error }
    return ClientError.connectionClosed(code: 1006, reason: "Connection lost")
  }
}
