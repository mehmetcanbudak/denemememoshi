import Foundation
import MemoshiProtocol

extension Store {
  /// Called only after verifying the immutable Pi ownership and identity entry. Reconciliation
  /// uses the same path, including a crash between Pi's spawn commit and this projection.
  public func ensureRuntimeSubagent(
    _ binding: RuntimeSubagentBinding, fence: ConversationFence, at now: Int64
  ) throws -> MemoshiTask {
    try requireOpen()
    var events: [EventEnvelope] = []
    let result = try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      guard binding.conversationId == fence.conversationID,
        binding.piOwnerTaskId > 0, binding.piConversationId > 0,
        binding.sourceToolTaskId > 0, !binding.requestId.isEmpty
      else { throw ApprovalError.bindingConflict }
      if let existing = try readRuntimeSubagent(binding.taskId, database: writer) {
        guard existing == binding,
          let task: MemoshiTask = try readRecord(table: "tasks", id: binding.taskId.rawValue)
        else { throw ApprovalError.bindingConflict }
        return task
      }
      guard
        let original: MemoshiTask = try readRecord(
          table: "tasks", id: binding.originalTaskId.rawValue),
        original.conversationId == binding.conversationId, original.kind == .turn,
        try writer.integer(
          "SELECT COUNT(*) FROM chat_turns WHERE conversation_id = ? AND json_extract(record, '$.taskId') = ?",
          [.text(binding.conversationId.rawValue), .text(original.id.rawValue)]) == 1
      else { throw ApprovalError.bindingConflict }
      let task = MemoshiTask(
        id: binding.taskId, conversationId: binding.conversationId, parentTaskId: original.id,
        botId: original.botId, kind: .subagent, origin: original.origin, regime: original.regime,
        title: try Title(binding.background ? "Background subagent" : "Foreground subagent"),
        status: .queued, requestId: binding.requestId, budgetIds: original.budgetIds,
        usage: Usage(
          inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
          costMicroUsd: 0, costKnown: false), resumeMode: .auto, createdAt: binding.createdAt)
      try writeRecord(.task(task))
      try writer.execute(
        """
        INSERT INTO runtime_subagents
          (task_id, conversation_id, original_task_id, pi_owner_task_id, pi_conversation_id, record)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
          .text(task.id.rawValue), .text(binding.conversationId.rawValue),
          .text(original.id.rawValue), .integer(Int64(binding.piOwnerTaskId)),
          .integer(Int64(binding.piConversationId)), .json(try encoder.encode(binding)),
        ])
      events.append(
        try append(
          runtimeTaskEvent(
            task, at: now,
            event: .taskCreated(
              .init(
                taskId: task.id, kind: task.kind, title: task.title, origin: task.origin,
                regime: task.regime, parentTaskId: original.id)))))
      return task
    }
    eventBus.publish(events)
    return result
  }

  /// Returns immutable ownership for one application child task, if it exists.
  public func runtimeSubagent(_ id: TaskID) throws -> RuntimeSubagentBinding? {
    try requireOpen()
    return try readRuntimeSubagent(id, database: reader)
  }

  /// Lists one conversation's child bindings, optionally limited to nonterminal tasks.
  public func runtimeSubagents(
    _ conversation: ConversationID, activeOnly: Bool = false
  ) throws -> [RuntimeSubagentBinding] {
    try requireOpen()
    let filter = activeOnly ? " AND t.status IN ('queued', 'running', 'waiting')" : ""
    return try reader.query(
      "SELECT s.record FROM runtime_subagents s JOIN tasks t ON t.id = s.task_id WHERE s.conversation_id = ?\(filter) ORDER BY s.pi_owner_task_id",
      [.text(conversation.rawValue)]
    ) {
      try decoder.decode(RuntimeSubagentBinding.self, from: $0.requiredData(0))
    }
  }

  /// The actual Pi task graph supplies nonterminal states; immutable task/submission receipts
  /// supply terminal states (Pi removes terminal nodes from its live graph).
  public func projectRuntimeSubagent(
    _ id: TaskID, status: TaskStatus, cancelRequested: Bool,
    fence: ConversationFence, at now: Int64
  ) throws {
    try requireOpen()
    var events: [EventEnvelope] = []
    try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      guard let binding = try readRuntimeSubagent(id, database: writer),
        binding.conversationId == fence.conversationID,
        var task: MemoshiTask = try readRecord(table: "tasks", id: id.rawValue),
        [.queued, .running, .waiting, .done, .failed, .canceled].contains(status)
      else { throw ApprovalError.bindingConflict }
      guard [.queued, .running, .waiting].contains(task.status), task.resumeMode != .explicit else {
        return
      }
      let previousTask = task
      let previous = task.status
      if cancelRequested && task.cancelRequestedAt == nil {
        task.cancelRequestedAt = now
        events.append(
          try append(
            runtimeTaskEvent(
              task, at: now,
              event: .taskCancelRequested(.init(taskId: task.id, by: .system)))))
      }
      // A pending approval is more specific than Pi's generic state, the pending one included
      // that a close or a restart writes a waiting call back as: the child still waits on the
      // user's answer, which the same Card asks for after the next open (D139).
      let approval =
        try writer.integer(
          "SELECT COUNT(*) FROM approvals WHERE task_id = ? AND status = 'pending'",
          [.text(id.rawValue)]) ?? 0
      let desired: TaskStatus =
        approval > 0 && [.queued, .running, .waiting].contains(status) ? .waiting : status
      if task.startedAt == nil && desired != .queued {
        task.startedAt = now
        events.append(
          try append(
            runtimeTaskEvent(
              task, at: now,
              event: .taskStarted(.init(taskId: task.id)))))
      }
      task.status = desired
      task.waitingOn = desired == .waiting ? (approval > 0 ? .approval : .childTasks) : nil
      if [.done, .failed, .canceled].contains(desired) {
        task.endedAt = now
        let outcome: TaskOutcome =
          desired == .done ? .answered : (desired == .canceled ? .canceled : .failed)
        task.outcome = outcome
        if desired == .failed {
          task.error = TaskError(
            code: "subagent_failed", message: "The child could not complete.", retryable: false)
        }
        // Stored first, so ending its decisions cannot project the finished task as running.
        try writeRecord(.task(task))
        events += try cancelTaskApprovals(task.id, at: now)
        events.append(
          try append(
            runtimeTaskEvent(
              task, at: now,
              event: .taskFinished(
                .init(
                  taskId: task.id,
                  status: desired == .done ? .done : (desired == .canceled ? .canceled : .failed),
                  outcome: outcome, error: task.error, usage: task.usage,
                  durationMs: max(0, now - (task.startedAt ?? task.createdAt)))))))
      } else {
        if desired != .queued
          && (previous != desired || previousTask.waitingOn != task.waitingOn)
        {
          events.append(
            try append(
              runtimeTaskEvent(
                task, at: now,
                event: .taskStatusChanged(
                  .init(
                    taskId: task.id, status: desired == .waiting ? .waiting : .running,
                    waitingOn: task.waitingOn,
                    previous: previous == .waiting ? .waiting : .running)))
            ))
        }
        if task != previousTask { try writeRecord(.task(task)) }
      }
    }
    eventBus.publish(events)
  }

  /// Captures a fixed task, never whichever turn happens to be active on replay.
  public func prepareTaskAbort(
    _ params: TasksAbortParams, paramsHash: String, fence: ConversationFence, at now: Int64
  ) throws -> TasksAbortResult {
    try requireOpen()
    var events: [EventEnvelope] = []
    let result = try writer.transaction(write: true) {
      if var previous = try requestResult(
        params.requestId, method: TasksAbort.name,
        paramsHash: paramsHash, as: TasksAbortResult.self)
      {
        previous.replayed = true
        return previous
      }
      try checkFence(fence, at: now)
      guard var task: MemoshiTask = try readRecord(table: "tasks", id: params.taskId.rawValue),
        task.conversationId == fence.conversationID
      else { throw ApprovalError.notFound }
      events += try markStopped(&task, at: now)
      let writtenSeq = try events.last?.seq ?? position(conversationID: task.conversationId).seq
      let result = TasksAbortResult(task: task, writtenSeq: writtenSeq, replayed: false)
      try saveRequest(
        params.requestId, method: TasksAbort.name, paramsHash: paramsHash,
        result: result, at: now)
      return result
    }
    eventBus.publish(events)
    return result
  }

  /// Records that the user stopped this task, for a Stop that is stopping its actual Pi work
  /// (`chats.abort`): a kill that overtakes the stopped execution leaves a step that never
  /// offers Run again (D138), and the next open applies the Stop again.
  public func recordStop(_ taskID: TaskID, fence: ConversationFence, at now: Int64) throws {
    try requireOpen()
    let events = try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      guard var task: MemoshiTask = try readRecord(table: "tasks", id: taskID.rawValue),
        task.conversationId == fence.conversationID
      else { throw ApprovalError.notFound }
      return try markStopped(&task, at: now)
    }
    eventBus.publish(events)
  }

  /// Records that Pi continues this admitted turn by itself after a restart cut it off
  /// (`task.resumed` by `system`, events.md §5.5), once per Store instance: another open in the
  /// same process continues the same interruption. Its reply then reads as continued in
  /// history. A turn that ended, waits on a Resume card or was stopped does not continue by
  /// itself, so nothing is recorded for it.
  public func recordTurnResumed(_ requestID: ULID, fence: ConversationFence, at now: Int64)
    throws
  {
    try requireOpen()
    guard !resumedTurns.contains(requestID) else { return }
    let events = try writer.transaction(write: true) { () throws -> [EventEnvelope] in
      guard var turn = try readTurn(requestID, database: writer),
        turn.chatId.rawValue == fence.conversationID.rawValue,
        let chat = try readConversation(turn.chatId, database: writer)
      else { throw StoreError.chatNotFound }
      try checkFence(fence, at: now)
      let stopped =
        try writer.query(
          "SELECT json_extract(record, '$.cancelRequestedAt') FROM tasks WHERE id = ?",
          [.text(turn.taskId.rawValue)], row: { $0.optionalInteger(0) }
        ).first ?? nil
      guard !turn.isTerminal, turn.recoveryStep == nil, turn.userEntryId != nil, stopped == nil
      else { return [] }
      turn.resumedAfterInterruption = true
      try writeTurn(turn)
      return [
        try append(
          turnEvent(
            turn, chat: chat, at: now, subject: ObjectRef(kind: "task", id: turn.taskId.rawValue),
            event: .taskResumed(TaskResumedPayload(taskId: turn.taskId, by: .system))))
      ]
    }
    if !events.isEmpty { resumedTurns.insert(requestID) }
    eventBus.publish(events)
  }

  /// Records that Pi continues a live subagent child task after a restart cut it off
  /// (`task.resumed` by `system`, events.md §5.5), once per Store instance.
  public func recordSubagentResumed(_ taskID: TaskID, fence: ConversationFence, at now: Int64)
    throws
  {
    try requireOpen()
    guard !resumedSubagents.contains(taskID) else { return }
    let events = try writer.transaction(write: true) { () throws -> [EventEnvelope] in
      try checkFence(fence, at: now)
      guard let task: MemoshiTask = try readRecord(table: "tasks", id: taskID.rawValue),
        task.conversationId == fence.conversationID,
        [.queued, .running, .waiting].contains(task.status),
        task.resumeMode != .explicit,
        task.cancelRequestedAt == nil
      else { return [] }
      return [
        try append(
          runtimeTaskEvent(
            task, at: now, event: .taskResumed(TaskResumedPayload(taskId: task.id, by: .system))))
      ]
    }
    if !events.isEmpty { resumedSubagents.insert(taskID) }
    eventBus.publish(events)
  }

  /// A live task's first Stop, in the caller's transaction.
  private func markStopped(_ task: inout MemoshiTask, at now: Int64) throws -> [EventEnvelope] {
    guard [.queued, .running, .waiting].contains(task.status), task.cancelRequestedAt == nil
    else { return [] }
    task.cancelRequestedAt = now
    try writeRecord(.task(task))
    return [
      try append(
        runtimeTaskEvent(
          task, at: now, event: .taskCancelRequested(.init(taskId: task.id, by: .user))))
    ]
  }

  /// Reads persisted root and child tasks with a watermark from the same metadata snapshot.
  public func taskGraph(_ conversation: ConversationID) throws -> StoreSnapshot<[MemoshiTask]> {
    try requireOpen()
    return try reader.transaction(write: false) {
      let tasks = try reader.query(
        "SELECT record FROM tasks WHERE conversation_id = ? ORDER BY id",
        [.text(conversation.rawValue)]
      ) {
        try decoder.decode(MemoshiTask.self, from: $0.requiredData(0))
      }
      return StoreSnapshot(value: tasks, asOf: try position(conversationID: conversation))
    }
  }

  func readRuntimeSubagent(_ id: TaskID, database: SQLiteConnection) throws
    -> RuntimeSubagentBinding?
  {
    try database.query(
      "SELECT record FROM runtime_subagents WHERE task_id = ?", [.text(id.rawValue)]
    ) {
      try decoder.decode(RuntimeSubagentBinding.self, from: $0.requiredData(0))
    }.first
  }

  private func runtimeTaskEvent(_ task: MemoshiTask, at now: Int64, event: Event) -> EventDraft {
    EventDraft(
      ts: now, actor: Actor(kind: .system), subject: ObjectRef(kind: "task", id: task.id.rawValue),
      scope: EventScope(botId: task.botId, conversationId: task.conversationId, taskId: task.id),
      origin: task.origin, event: event)
  }
}
