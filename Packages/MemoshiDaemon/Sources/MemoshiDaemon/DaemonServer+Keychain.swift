import Foundation
import MemoshiProtocol
import MemoshiStore

extension DaemonServer {
  func claimKeychainHost(_ id: UUID) -> Bool {
    guard configuration.enableTextChat, state == .ready, !isStopped else { return false }
    guard hostSessionID == nil || hostSessionID == id else { return false }
    hostSessionID = id
    return true
  }

  func openKeychainHost(_ id: UUID, version: String, capabilities: [Capability]) async throws {
    guard hostSessionID == id, sessions[id] != nil, state == .ready, !isStopped else {
      throw DaemonError.notRunning
    }
    keychainHostReady = true
    let event = EventDraft(
      ts: IDGenerator.nowMilliseconds(), actor: Actor(kind: .system),
      subject: ObjectRef(kind: "system", id: "memoshid"),
      event: .systemAppConnected(
        SystemAppConnectedPayload(appVersion: version, capabilities: capabilities)))
    _ = try await store.commit(StoreCommit(events: [event]), at: event.ts)
  }

  func dropKeychainHost(_ id: UUID) async throws {
    guard hostSessionID == id else { return }
    let wasReady = keychainHostReady
    hostSessionID = nil
    keychainHostReady = false
    guard wasReady, state == .ready, !isStopped else { return }
    let event = EventDraft(
      ts: IDGenerator.nowMilliseconds(), actor: Actor(kind: .system),
      subject: ObjectRef(kind: "system", id: "memoshid"),
      event: .systemAppDisconnected(SystemAppDisconnectedPayload(reason: "connection_closed")))
    _ = try await store.commit(StoreCommit(events: [event]), at: event.ts)
  }

  func requestCredential(_ params: HostKeychainGetParams) async throws -> HostKeychainGetResult {
    guard state == .ready, !isStopped, keychainHostReady,
      let id = hostSessionID, let session = sessions[id]
    else {
      throw RPCError(
        message: "The authenticated app host is unavailable.",
        data: RPCErrorData(details: .hostUnavailable))
    }
    return try await session.requestKeychain(params)
  }
}
