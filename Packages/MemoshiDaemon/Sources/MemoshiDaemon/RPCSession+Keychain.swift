import Foundation
import MemoshiProtocol
import MemoshiTransport

struct PendingHostCall: Sendable {
  let continuation: CheckedContinuation<HostKeychainGetResult, any Error>
  let timeout: Task<Void, Never>
  /// Whether the request frame was written; a send canceled while queued reports false.
  let send: Task<Bool, Never>
}

extension RPCSession {
  /// Runs outside the sole receive loop: the app's reply must remain readable while this waits.
  func requestKeychain(_ params: HostKeychainGetParams) async throws -> HostKeychainGetResult {
    try Task.checkCancellation()
    guard !closed, hostReady,
      negotiated.contains(where: { $0.rawValue == "host.keychain.v1" }),
      hostCalls.count + canceledHostCalls.count < 8, nextHostID < UInt64.max
    else { throw unavailableHost() }
    nextHostID += 1
    let id = try JSONRPCID("d:\(nextHostID)")
    let data = try encoder.encode(JSONRPCRequest<HostKeychainGet>(id: id, params: params))
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard !Task.isCancelled, !closed else {
          continuation.resume(throwing: unavailableHost())
          return
        }
        let timeout = Task { [weak self, hostCallSleep] in
          do { try await hostCallSleep(.seconds(10)) } catch { return }
          await self?.cancelHostCall(id.rawValue, notify: true)
        }
        let send = Task { [weak self, connection] () -> Bool in
          do {
            try Task.checkCancellation()
            try await connection.send(data)
            return true
          } catch {
            await self?.cancelHostCall(id.rawValue, notify: false)
            return false
          }
        }
        hostCalls[id.rawValue] = PendingHostCall(
          continuation: continuation, timeout: timeout, send: send)
      }
    } onCancel: {
      Task { await self.cancelHostCall(id.rawValue, notify: true) }
    }
  }

  func receiveHostResponse(_ data: Data, id: String?) async throws {
    guard authenticated, let id, id.hasPrefix("d:") else {
      await close(code: 4400, reason: "invalid_host_response")
      return
    }
    // D130: the answer to a canceled call frees its slot. Its content is never used.
    if canceledHostCalls.remove(id) != nil { return }
    // Late results belong to the old request only. They cannot authorize a new model use.
    guard let pending = hostCalls.removeValue(forKey: id) else { return }
    pending.timeout.cancel()
    pending.send.cancel()
    do {
      let response = try decoder.decode(JSONRPCResponse<HostKeychainGet>.self, from: data)
      guard response.id?.rawValue == id else { throw unavailableHost() }
      let result = try response.get()
      guard !result.value.isEmpty, result.value.utf8.count <= 16 * 1024,
        result.ttlMs > 0, result.ttlMs <= 600_000
      else { throw unavailableHost() }
      pending.continuation.resume(returning: result)
    } catch {
      // Never forward a host's free-form error message into Pi errors or durable state.
      pending.continuation.resume(throwing: unavailableHost())
    }
  }

  func cancelHostCall(_ id: String, notify: Bool) async {
    guard let pending = hostCalls.removeValue(forKey: id) else { return }
    // The deadline's own task runs this: canceling it before the send below would refuse it.
    defer { pending.timeout.cancel() }
    pending.send.cancel()
    pending.continuation.resume(throwing: unavailableHost())
    guard notify, !closed else { return }
    // D130: the app answers `canceled` once its handler has ended. That worker is taken until
    // then, so the slot stays occupied here too, from before the wait for the request's own
    // write: a call must never be in neither set while its frame can still reach the app.
    canceledHostCalls.insert(id)
    // A request that never left is not canceled on the wire and gets no answer. An answer
    // that arrived during the wait has already freed the slot.
    guard await pending.send.value, !closed, canceledHostCalls.contains(id) else {
      canceledHostCalls.remove(id)
      return
    }
    do {
      try await connection.send(
        encoder.encode(SystemCancelNotification(id: try JSONRPCID(id))))
    } catch {
      await close(code: 4500, reason: "host_cancellation_failed")
    }
  }

  func failHostCalls() {
    for pending in hostCalls.values {
      pending.timeout.cancel()
      pending.send.cancel()
      pending.continuation.resume(throwing: unavailableHost())
    }
    hostCalls.removeAll()
    canceledHostCalls.removeAll()
  }

  func stopHostWork() {
    hostReady = false
    failHostCalls()
  }
}

private func unavailableHost() -> RPCError {
  RPCError(
    message: "The authenticated app host is unavailable.",
    data: RPCErrorData(details: .hostUnavailable))
}
