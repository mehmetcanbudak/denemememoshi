import Foundation
import MemoshiProtocol
import MemoshiStore

extension RuntimeAdapter {
  /// Closes an idle Session's real Harness before retaining its store in local Trash. Active
  /// turns, background children, approvals and uncertain effects must be settled first.
  public func deleteSession(_ params: SessionsDeleteParams) async throws -> LifecycleReceipt {
    try requireReady()
    let id = try ConversationID(params.sessionId.rawValue)
    let hash = try Self.paramsHash(params)
    if let admission = lifecycleAdmissions[id] {
      guard admission.requestID == params.requestId, admission.hash == hash else {
        throw RuntimeError.busy
      }
      var receipt = try await admission.task.value
      receipt.replayed = true
      return receipt
    }
    let task = Task { try await self.retireSession(params, hash: hash) }
    lifecycleAdmissions[id] = LifecycleAdmission(
      requestID: params.requestId, hash: hash, task: task)
    defer { lifecycleAdmissions[id] = nil }
    return try await task.value
  }

  private func retireSession(_ params: SessionsDeleteParams, hash: String) async throws
    -> LifecycleReceipt
  {
    let id = try ConversationID(params.sessionId.rawValue)
    if var receipt = try await store.requestReceipt(
      params.requestId, method: SessionsDelete.name, paramsHash: hash, as: LifecycleReceipt.self)
    {
      receipt.replayed = true
      return receipt
    }
    if let opening = openings[id] { try await opening.value }
    if let closing = threadClosings[id] { await closing.value }
    guard try await store.conversationIsIdle(id) else { throw RuntimeError.busy }
    if let thread = threads[id] {
      guard await isIdle(thread, for: .zero), thread.users == 0, thread.activation == nil else {
        throw RuntimeError.busy
      }
      try await closeThread(thread, quiescing: false)
    }
    return try await store.deleteSession(
      params, paramsHash: hash, at: IDGenerator.nowMilliseconds())
  }

  /// Returns a position-tagged snapshot of local Session Trash while the runtime is ready.
  /// Pending and completed purges are excluded; an expired item may remain until maintenance.
  public func listTrash() async throws -> TrashListResult {
    try requireReady()
    let snapshot = try await store.sessionTrash()
    return TrashListResult(items: snapshot.value, asOf: snapshot.asOf)
  }

  /// Restores an unexpired local Session's metadata without opening its retained Pi Harness.
  /// Only `session` is accepted. Reusing the original request returns its stored result;
  /// expired, missing or purge-pending Sessions cannot be newly restored.
  public func restoreSession(_ params: TrashRestoreParams) async throws -> TrashRestoreResult {
    try requireReady()
    guard params.kind == "session" else { throw RuntimeError.invalidParams }
    return try await store.restoreSession(
      params, paramsHash: Self.paramsHash(params), at: IDGenerator.nowMilliseconds())
  }

  /// Empty Trash is explicit user authority; the stored selection and stable locks make its
  /// filesystem phase resumable. Only already-retired Session stores may be unlinked.
  public func emptyTrash(_ params: TrashEmptyParams) async throws -> LifecycleReceipt {
    try requireReady()
    let hash = try Self.paramsHash(params)
    guard
      let job = try await store.prepareSessionPurge(
        params, paramsHash: hash, at: IDGenerator.nowMilliseconds())
    else {
      guard let receipt = try await store.sessionPurgeReceipt(params, paramsHash: hash) else {
        throw RuntimeError.projectionFailed
      }
      return receipt
    }
    return try await store.finishSessionPurge(job, at: IDGenerator.nowMilliseconds())
  }

  /// Called before opening any Pi store, then by bounded periodic maintenance. A crash between
  /// unlink and the audited receipt resumes the same job; no Session can be restored mid-purge.
  func resumeSessionPurges() async throws {
    for job in try await store.pendingSessionPurges() {
      _ = try await store.finishSessionPurge(job, at: IDGenerator.nowMilliseconds())
    }
    let expired = Array(
      try await store.expiredSessionIDs(at: IDGenerator.nowMilliseconds()).prefix(1_000))
    if !expired.isEmpty {
      let params = TrashEmptyParams(requestId: try IDGenerator.shared.next(), ids: expired)
      if let job = try await store.prepareSessionPurge(
        params, paramsHash: Self.paramsHash(params), by: "system", at: IDGenerator.nowMilliseconds()
      ) {
        _ = try await store.finishSessionPurge(job, at: IDGenerator.nowMilliseconds())
      }
    }
    lifecycleMaintenanceFailed = false
  }

  func maintainSessionTrash() async {
    guard !closing else { return }
    do { try await resumeSessionPurges() } catch { lifecycleMaintenanceFailed = true }
  }
}
