import Foundation
import MemoshiProtocol
import MemoshiStore
import PiDurable

extension RuntimeAdapter {
  /// A child attachment watches the actual Pi conversation, not the parent's text stream.
  /// Its content-free refresh hint cannot masquerade as a root message delta.
  func ensureChildEvents(_ binding: RuntimeSubagentBinding, thread: RuntimeThread) async throws {
    let child = PiDurable.ConversationId(binding.piConversationId)
    guard let engine = thread.engine, thread.childEvents[child] == nil,
      thread.childEventOpenings.insert(child).inserted
    else { return }
    defer { thread.childEventOpenings.remove(child) }
    let watcher = try await engine.harness.watchEvents(child)
    guard !closing, threads[thread.conversationID] === thread else {
      _ = await watcher.stop()
      return
    }
    thread.childEvents[child] = watcher
    let conversation = thread.conversationID
    let identity = ObjectIdentifier(thread)
    try watcher.start { [weak self] events, _ in
      guard let self else { return }
      do {
        try await self.receiveChildEvents(
          events, binding: binding, conversation: conversation,
          identity: identity)
      } catch {
        await self.failThread(conversation)
      }
    }
  }

  private func receiveChildEvents(
    _ events: [PiDurable.AgentEvent], binding: RuntimeSubagentBinding,
    conversation: ConversationID, identity: ObjectIdentifier
  ) async throws {
    guard !closing, let thread = threads[conversation], ObjectIdentifier(thread) == identity,
      !thread.failed, thread.childEvents[PiDurable.ConversationId(binding.piConversationId)] != nil
    else { return }
    thread.lastUsed = .now
    var changed = false
    for event in events {
      switch event.type {
      case "message_end", "tool_execution_end", "task_failed":
        try await drainToolOutcomes(thread)
        changed = true
      case "message_start", "message_update", "submission", "snapshot":
        changed = true
      default: break
      }
    }
    if changed { try await scheduleChildProgress(binding, thread: thread) }
  }

  /// Leading + trailing coalescing at task.progress's 1 Hz limit. The timer only coalesces
  /// observed committed changes; it never manufactures a task state, percentage or answer.
  private func scheduleChildProgress(_ binding: RuntimeSubagentBinding, thread: RuntimeThread)
    async throws
  {
    let child = PiDurable.ConversationId(binding.piConversationId)
    guard thread.childProgressJobs[child] == nil else { return }
    let elapsed = thread.childProgressAt[child].map { ContinuousClock.now - $0 } ?? .seconds(1)
    if elapsed >= .seconds(1) {
      try await publishChildProgress(binding, thread: thread)
      return
    }
    let delay = Duration.seconds(1) - elapsed
    let conversation = thread.conversationID
    let identity = ObjectIdentifier(thread)
    thread.childProgressJobs[child] = Task { [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      guard let self else { return }
      await self.flushChildProgress(binding, conversation: conversation, identity: identity)
    }
  }

  private func flushChildProgress(
    _ binding: RuntimeSubagentBinding, conversation: ConversationID, identity: ObjectIdentifier
  ) async {
    guard !closing, let thread = threads[conversation], ObjectIdentifier(thread) == identity,
      !thread.failed
    else { return }
    let child = PiDurable.ConversationId(binding.piConversationId)
    thread.childProgressJobs[child] = nil
    guard thread.childEvents[child] != nil else { return }
    do { try await publishChildProgress(binding, thread: thread) } catch {
      await failThread(conversation)
    }
  }

  private func publishChildProgress(_ binding: RuntimeSubagentBinding, thread: RuntimeThread)
    async throws
  {
    thread.childProgressAt[PiDurable.ConversationId(binding.piConversationId)] = .now
    try await publishLive(
      EventEnvelope(
        seq: nil, ts: IDGenerator.nowMilliseconds(), deviceId: store.deviceID,
        actor: Actor(kind: .system), subject: ObjectRef(kind: "task", id: binding.taskId.rawValue),
        scope: EventScope(
          botId: thread.botID, conversationId: binding.conversationId, taskId: binding.taskId),
        event: .taskProgress(.init(taskId: binding.taskId, message: "Child response updated."))))
  }

  func stopChildEvents(_ child: PiDurable.ConversationId, thread: RuntimeThread) async {
    thread.childProgressJobs.removeValue(forKey: child)?.cancel()
    thread.childProgressAt.removeValue(forKey: child)
    if let events = thread.childEvents.removeValue(forKey: child) { _ = await events.stop() }
  }

  func stopChildEvents(_ thread: RuntimeThread) async {
    for child in Array(thread.childEvents.keys) { await stopChildEvents(child, thread: thread) }
  }
}
