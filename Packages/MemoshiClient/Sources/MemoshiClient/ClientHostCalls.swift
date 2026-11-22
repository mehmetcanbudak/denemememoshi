import Foundation
import MemoshiProtocol
import MemoshiTransport

/// Both tasks remain owned until they actually finish. A canceled, noncooperative handler
/// still occupies its worker; cancellation must not turn repeated calls into unbounded work.
struct HostCall: Sendable {
  let id: JSONRPCID
  let generation: UInt64
  let work: Task<Void, Never>
  let timeout: Task<Void, Never>
  var workFinished = false
  var timeoutFinished = false
  /// The app's own deadline passed: answered `timeout` once its handler has ended (D131).
  var expired = false
  /// The daemon sent `system.cancel`: answered `canceled` once its handler has ended, and the
  /// daemon holds the slot until that answer arrives (D130).
  var canceled = false
  /// The worker: false while the broker handler may still be running for this call.
  var handlerEnded: Bool
  /// Its one answer was handed to the carrier.
  var answered = false
}

enum HostCallWork: Sendable {
  case keychain(HostKeychainGetParams)
  case refusal(RPCErrorDetails)
}

extension MemoshiClient {
  /// Decoding/admission do not suspend the sole receiver. OS checks, Keychain reads and sends
  /// belong to the bounded owned tasks, so ordinary responses/events/cancel keep flowing.
  func receiveHostRequest(
    _ frame: Data, id rawID: String, method: String, generation expected: UInt64
  ) throws {
    guard generation == expected, let opened = connection, let hello = statusValue.hello else {
      throw ClientError.protocolViolation("Host request received before successful negotiation")
    }
    guard isDaemonRequestID(rawID) else {
      throw ClientError.protocolViolation("Invalid daemon host request ID")
    }
    guard hostRequestIDs[rawID] == nil else {
      throw ClientError.protocolViolation("Duplicate in-flight host request ID")
    }
    // The daemon holds a slot until it has this app's answer (D130), so a ninth unanswered
    // request on one connection is the daemon's error, never a late local release.
    guard hostCalls.values.count(where: { $0.generation == expected && !$0.answered }) < 8 else {
      throw ClientError.protocolViolation("Host request work limit exceeded")
    }
    let id = try JSONRPCID(rawID)
    let work: HostCallWork
    if method != HostKeychainGet.name {
      work = .refusal(.methodNotFound)
    } else if configuration.client.role != .app || keychainHostHandler == nil {
      work = .refusal(.methodNotFound)
    } else if !hello.capabilities.contains(where: { $0.rawValue == "host.keychain.v1" }) {
      work = .refusal(.capabilityMissing)
    } else if frame.count > 8 * 1024 {
      work = .refusal(.payloadTooLarge)
    } else {
      do {
        let request = try hostDecoder.decode(JSONRPCRequest<HostKeychainGet>.self, from: frame)
        guard request.id == id, !request.params.secretRef.isEmpty, !request.params.purpose.isEmpty
        else {
          throw ClientError.protocolViolation("Empty host keychain reference or purpose")
        }
        // Handlers of an earlier connection that ignore cancellation still hold their workers,
        // and this connection's daemon cannot know: unavailable, not a protocol violation.
        work =
          hostCalls.values.count(where: { !$0.handlerEnded }) < 8
          ? .keychain(request.params) : .refusal(.hostUnavailable)
      } catch {
        work = .refusal(.invalidParams(InvalidParamsDetails(issues: [])))
      }
    }

    let token = UUID()
    let task = Task<Void, Never> { [weak self, opened] in
      await self?.performHostCall(work, id: id, token: token, on: opened, generation: expected)
      await self?.finishHostWork(token, on: opened)
    }
    let timeout = Task<Void, Never> { [weak self, sleep] in
      do {
        try await sleep(.seconds(10))
        try Task.checkCancellation()
        await self?.expireHostCall(id, token: token, generation: expected)
      } catch {}
      await self?.finishHostTimeout(token)
    }
    hostRequestIDs[rawID] = token
    var handlerEnded = true
    if case .keychain = work { handlerEnded = false }
    hostCalls[token] = HostCall(
      id: id, generation: expected, work: task, timeout: timeout, handlerEnded: handlerEnded)
  }

  func receiveHostCancellation(_ frame: Data, generation expected: UInt64) throws {
    guard generation == expected, connection != nil, statusValue.hello != nil else {
      throw ClientError.protocolViolation(
        "Host cancellation received before successful negotiation")
    }
    let id: String
    do {
      guard frame.count <= 1024 else {
        throw ClientError.protocolViolation("Host cancellation exceeds protocol limit")
      }
      id = try hostDecoder.decode(SystemCancelNotification.self, from: frame).id.rawValue
      guard isDaemonRequestID(id) else {
        throw ClientError.protocolViolation("Invalid host cancellation ID")
      }
    } catch {
      throw ClientError.protocolViolation("Malformed host cancellation")
    }
    guard let token = hostRequestIDs.removeValue(forKey: id), let call = hostCalls[token] else {
      return
    }
    // The ID is gone first, so no success can follow; `finishHostWork` answers `canceled`.
    hostCalls[token]?.canceled = true
    call.work.cancel()
    call.timeout.cancel()
  }

  func performHostCall(
    _ work: HostCallWork, id: JSONRPCID, token: UUID, on opened: any ClientConnection,
    generation expected: UInt64
  ) async {
    guard hostCallIsCurrent(token, generation: expected) else { return }
    switch work {
    case .refusal(let details):
      await sendHostRefusal(details, id: id, token: token, on: opened, generation: expected)
    case .keychain(let params):
      guard let keychainHostHandler else { return }
      guard await revalidateHostPeer(on: opened, token: token, generation: expected),
        hostCallIsCurrent(token, generation: expected)
      else { return }
      let result: HostKeychainGetResult
      do {
        result = try await keychainHostHandler(params)
        hostCalls[token]?.handlerEnded = true
      } catch {
        hostCalls[token]?.handlerEnded = true
        guard hostCallIsCurrent(token, generation: expected) else { return }
        await sendHostRefusal(
          sanitizedHostFailure(error), id: id, token: token, on: opened, generation: expected)
        return
      }
      guard hostCallIsCurrent(token, generation: expected) else { return }
      // The daemon rejects a lifetime outside 1...600000 ms; never release a key it will discard.
      guard !result.value.isEmpty, result.value.utf8.count <= 16 * 1024,
        result.ttlMs > 0, result.ttlMs <= 600_000
      else {
        await sendHostRefusal(
          .hostUnavailable, id: id, token: token, on: opened, generation: expected)
        return
      }
      let response: Data
      do {
        response = try hostEncoder.encode(
          JSONRPCSuccessResponse<HostKeychainGet>(id: id, result: result))
      } catch {
        await sendHostRefusal(
          .hostUnavailable, id: id, token: token, on: opened, generation: expected)
        return
      }
      // Recheck the same actual carrier after every suspension, and authenticate again only
      // once the bytes are ready to send. Never look up a possibly replaced connection here.
      guard await revalidateHostPeer(on: opened, token: token, generation: expected),
        hostCallIsCurrent(token, generation: expected)
      else { return }
      await sendHostFrame(response, token: token, on: opened, generation: expected)
    }
  }

  func revalidateHostPeer(
    on opened: any ClientConnection, token: UUID, generation expected: UInt64
  ) async -> Bool {
    guard hostCallIsCurrent(token, generation: expected) else { return false }
    do {
      let current = try await opened.revalidatePeer(policy: configuration.peerPolicy)
      guard hostCallIsCurrent(token, generation: expected) else { return false }
      guard current == opened.peer else {
        throw IPCError.authenticationFailed(status: -25293)
      }
      return true
    } catch {
      guard hostCallIsCurrent(token, generation: expected) else { return false }
      // A failed fresh peer check is not a connection on which even an error should be sent.
      await connectionLost(IPCError.authenticationFailed(status: -25293), generation: expected)
      return false
    }
  }

  func sendHostRefusal(
    _ details: RPCErrorDetails, id: JSONRPCID, token: UUID, on opened: any ClientConnection,
    generation expected: UInt64
  ) async {
    guard hostCallIsCurrent(token, generation: expected) else { return }
    do {
      let response = try hostEncoder.encode(hostRefusal(details, id: id))
      await sendHostFrame(response, token: token, on: opened, generation: expected)
    } catch {
      guard hostCallIsCurrent(token, generation: expected) else { return }
      await connectionLost(
        ClientError.protocolViolation("Cannot encode host refusal"), generation: expected)
    }
  }

  func sendHostFrame(
    _ response: Data, token: UUID, on opened: any ClientConnection, generation expected: UInt64
  ) async {
    guard hostCallIsCurrent(token, generation: expected) else { return }
    guard response.count <= min(statusValue.hello?.limits.maxInboundBytes ?? 0, 1_048_576) else {
      await connectionLost(
        ClientError.protocolViolation("Host response exceeds negotiated limit"),
        generation: expected)
      return
    }
    do {
      // Counted as answered before the bytes leave: the daemon's next request can then never
      // find the slot this answer frees still taken.
      hostCalls[token]?.answered = true
      try await opened.send(response)
    } catch {
      guard hostCallIsCurrent(token, generation: expected) else {
        // The daemon's cancellation or the app's own deadline revoked the queued write, so
        // the `canceled` or `timeout` answer is still owed once the work has ended.
        if let call = hostCalls[token], call.canceled || call.expired {
          hostCalls[token]?.answered = false
        }
        return
      }
      await connectionLost(
        ClientError.connectionClosed(code: 1006, reason: "Host response failed"),
        generation: expected)
    }
  }

  func hostCallIsCurrent(_ token: UUID, generation expected: UInt64) -> Bool {
    guard !Task.isCancelled, expected == generation, connection != nil, statusValue.hello != nil,
      let call = hostCalls[token], call.generation == expected,
      hostRequestIDs[call.id.rawValue] == token
    else { return false }
    return true
  }

  /// D131: the app's own deadline cancels the handler, and `finishHostWork` answers `timeout`
  /// once the handler has ended. The ID is gone first, so no success can follow.
  func expireHostCall(_ id: JSONRPCID, token: UUID, generation expected: UInt64) {
    guard hostCallIsCurrent(token, generation: expected) else { return }
    hostCalls[token]?.expired = true
    hostRequestIDs.removeValue(forKey: id.rawValue)
    hostCalls[token]?.work.cancel()
  }

  func finishHostWork(_ token: UUID, on opened: any ClientConnection) async {
    guard let call = hostCalls[token] else { return }
    hostCalls[token]?.handlerEnded = true
    if !call.expired { call.timeout.cancel() }
    if hostRequestIDs[call.id.rawValue] == token {
      hostRequestIDs.removeValue(forKey: call.id.rawValue)
    }
    let ending: RPCErrorDetails? = call.canceled ? .canceled : call.expired ? .timeout : nil
    if let ending, !call.answered {
      // This work task is canceled and a canceled task cannot send. The answer goes from a
      // task awaited here, so the call stays owned until it has left.
      await Task { [weak self] in
        await self?.answerEndedHostCall(
          token, id: call.id, with: ending, on: opened, generation: call.generation)
      }.value
    }
    hostCalls[token]?.workFinished = true
    releaseFinishedHostCall(token)
  }

  /// D130, D131: the daemon holds this request's slot until it is answered. The handler has
  /// ended and whatever it returned was discarded; the answer is the bare `canceled` (the
  /// daemon's cancellation) or `timeout` (the app's own deadline) error.
  func answerEndedHostCall(
    _ token: UUID, id: JSONRPCID, with details: RPCErrorDetails,
    on opened: any ClientConnection, generation expected: UInt64
  ) async {
    guard expected == generation, connection != nil, let hello = statusValue.hello else { return }
    do {
      let response = try hostEncoder.encode(hostRefusal(details, id: id))
      guard response.count <= min(hello.limits.maxInboundBytes, 1_048_576) else {
        throw ClientError.protocolViolation("Host refusal exceeds negotiated limit")
      }
      hostCalls[token]?.answered = true
      try await opened.send(response)
    } catch {
      guard expected == generation, connection != nil else { return }
      await connectionLost(
        ClientError.connectionClosed(code: 1006, reason: "Host response failed"),
        generation: expected)
    }
  }

  func finishHostTimeout(_ token: UUID) {
    hostCalls[token]?.timeoutFinished = true
    releaseFinishedHostCall(token)
  }

  func releaseFinishedHostCall(_ token: UUID) {
    guard let call = hostCalls[token], call.workFinished, call.timeoutFinished else { return }
    hostCalls.removeValue(forKey: token)
  }

  func cancelHostCalls() {
    hostRequestIDs.removeAll(keepingCapacity: false)
    for call in hostCalls.values {
      call.work.cancel()
      call.timeout.cancel()
    }
  }
}

private func isDaemonRequestID(_ id: String) -> Bool {
  let bytes = id.utf8
  return bytes.count >= 3 && bytes.count <= 64 && id.hasPrefix("d:")
    && bytes.dropFirst(2).allSatisfy { (48...57).contains($0) }
}

private func sanitizedHostFailure(_ error: any Error) -> RPCErrorDetails {
  if error is CancellationError { return .canceled }
  switch (error as? RPCError)?.kind {
  case .forbidden: return .forbidden
  case .notFound: return .notFound
  case .capabilityMissing: return .capabilityMissing
  case .canceled: return .canceled
  case .timeout: return .timeout
  default: return .hostUnavailable
  }
}

private func hostRefusal(_ details: RPCErrorDetails, id: JSONRPCID) -> JSONRPCErrorResponse {
  JSONRPCErrorResponse(
    id: id,
    error: RPCError(
      message: "Host request could not be completed",
      data: RPCErrorData(details: details)))
}
