import Foundation
import MemoshiProtocol
import MemoshiStore
import PiDurable

extension RuntimeAdapter {
  /// No recovery decision is invented here. The durable hold must already be absent, the
  /// original Pi run idle, and the selected model available before any input is claimed.
  /// Concurrent new sends do not defer a release: the Store refuses their reservations while
  /// queued input remains, so each new admission drains it first instead of overtaking it.
  func drainQueuedInputs(_ thread: RuntimeThread, join: Bool = true) async throws {
    while true {
      if let current = thread.queueAdmission {
        if join { _ = try await waitForQueuedAdmission(current) }
        return
      }
      guard !closing, !configuring, !thread.failed, thread.activeRequest == nil,
        let engine = thread.engine
      else { return }
      guard let params = try await store.nextQueuedChatInput(thread.conversationID) else { return }
      guard try await store.chatRecovery(thread.conversationID).value == nil else { return }
      if let live = try await engine.harness.snapshot(
        PiDurable.liveDoc, owner: PiDurable.ConversationId.root.rawValue), live.run != nil
      {
        return
      }
      // Metadata reads above suspend this actor. Join another winner, or recheck all
      // admission preconditions before installing the single-flight task without suspension.
      if thread.queueAdmission != nil { continue }
      // A send of this same request owns its admission key; that send drains again afterward.
      guard !closing, !configuring, !thread.failed, thread.activeRequest == nil,
        admissions[params.requestId] == nil
      else { return }
      let hash = try Self.paramsHash(params)
      let conversationID = thread.conversationID
      let task = Task {
        guard let current = self.threads[conversationID] else { throw RuntimeError.busy }
        return try await self.admit(params, hash: hash, thread: current, releasingQueued: true)
      }
      thread.queueAdmission = task
      admissions[params.requestId] = Admission(hash: hash, task: task)
      do {
        defer {
          thread.queueAdmission = nil
          admissions.removeValue(forKey: params.requestId)
        }
        let admitted = try await waitForQueuedAdmission(task)
        if !admitted { return }
      }
    }
  }

  private func waitForQueuedAdmission(_ task: Task<ChatsSendResult, any Error>) async throws -> Bool
  {
    do {
      _ = try await task.value
      return true
    } catch StoreError.chatBusy {
      return false
    } catch StoreError.chatRecoveryRequired {
      return false
    } catch let error as RuntimeError {
      switch error {
      case .busy, .modelUnavailable, .providerUnavailable:
        // A parked admission retains its original text, ID and model; discovery cannot
        // select a fallback or start inference. Explicit resume/send can try it later.
        return false
      case .stopping where closing:
        return false
      default:
        throw error
      }
    }
  }
}
