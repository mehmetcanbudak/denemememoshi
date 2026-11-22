import Foundation
import MemoshiProtocol

/// What the host knows before Pi has committed the final tool result.
public enum ToolDispatchOutcome: Sendable {
  /// A known returned result, not yet proof that Pi committed that result.
  case returned(ok: Bool)
  /// Execution may have changed the outside world; an error is not rollback evidence.
  case unknown
}

/// What Memoshi recorded about dispatching one replay-unsafe tool task. Its dispatch record is
/// written before any effect and is kept until committed Pi evidence agrees or the user's answer
/// replaces it; Pi's result is projected in the commit that retires it.
public enum ToolDispatchEvidence: Sendable {
  /// Nothing: Memoshi never dispatched it.
  case absent
  /// A dispatch record, or a Resume card (answered or not), governs it.
  case recorded
  /// Only Pi's committed result, which Memoshi projected: the call ran. A Pi that reports it
  /// still open lost that result (its commits survive a process kill only).
  case completed
}

extension Store {
  /// Commits intent before an unsafe host callback can perform an effect. Existing intent
  /// is never permission to execute again, even after a normal runtime or Store reopen. The
  /// commit is durable: its absence is how the runtime knows a call never dispatched, so it
  /// must survive power loss once the effect may start (RuntimeAdapter+InterruptedSteps). A
  /// commit the device does not confirm (`DeviceDrain.refused`) fails the dispatch.
  public func beginUnsafeToolDispatch(
    _ call: PolicyToolIdentity, fence: ConversationFence, at now: Int64
  ) throws {
    try requireOpen()
    let values: [SQLiteConnection.Value] = [
      .text(fence.conversationID.rawValue), .text(call.runtimeTaskKey),
    ]
    do {
      try writer.transaction(write: true, durable: true) {
        try checkFence(fence, at: now)
        guard parkedDispatchEpochs[fence.conversationID] != fence.epoch else {
          throw StoreError.chatRecoveryRequired
        }
        guard try readChatRecovery(fence.conversationID, database: writer) == nil
        else {
          throw StoreError.chatRecoveryRequired
        }
        _ = try dispatchTask(call, fence: fence)
        try admitResumedDispatch(fence.conversationID, runtimeTaskKey: call.runtimeTaskKey)
        guard
          try writer.integer(
            "SELECT COUNT(*) FROM unsafe_tool_dispatches WHERE conversation_id = ? AND runtime_task_key = ?",
            values) == 0
        else { throw StoreError.chatRecoveryRequired }
        try writer.execute(
          "INSERT INTO unsafe_tool_dispatches (conversation_id, runtime_task_key, state, started_at) VALUES (?, ?, 'started', ?)",
          values + [.integer(now)])
      }
    } catch let error as StoreError where error == DeviceDrain.refused {
      // The record committed, but may not survive power loss, so the effect never starts. The
      // record goes too, or it would later read as a call that may have run. Should removing it
      // fail as well, the record stays and the call is held as uncertain: safe, if untrue.
      try? writer.transaction(write: true) {
        try writer.execute(
          """
          DELETE FROM unsafe_tool_dispatches
          WHERE conversation_id = ? AND runtime_task_key = ? AND state = 'started'
          """, values)
      }
      throw error
    }
    currentUnsafeDispatches[fence.conversationID, default: []].insert(call.runtimeTaskKey)
  }

  /// Retains the intent until committed Pi evidence agrees. A failed host receipt leaves the
  /// original intent uncertain; removing its in-memory owner makes the read gate fail closed.
  public func finishUnsafeToolDispatch(
    _ call: PolicyToolIdentity, outcome: ToolDispatchOutcome,
    fence: ConversationFence, at now: Int64
  ) throws {
    try requireOpen()
    var keepOwner = false
    defer {
      if !keepOwner {
        releaseUnsafeDispatchOwner(fence.conversationID, task: call.runtimeTaskKey)
      }
    }
    let events = try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      let task = try dispatchTask(call, fence: fence)
      guard currentUnsafeDispatches[fence.conversationID]?.contains(call.runtimeTaskKey) == true,
        try writer.text(
          "SELECT state FROM unsafe_tool_dispatches WHERE conversation_id = ? AND runtime_task_key = ?",
          [.text(fence.conversationID.rawValue), .text(call.runtimeTaskKey)]) == "started"
      else { throw StoreError.chatRecoveryRequired }
      switch outcome {
      case .returned(let ok):
        try writer.execute(
          "UPDATE unsafe_tool_dispatches SET state = 'returned', expected_ok = ? WHERE conversation_id = ? AND runtime_task_key = ?",
          [.integer(ok ? 1 : 0), .text(fence.conversationID.rawValue), .text(call.runtimeTaskKey)])
        return [EventEnvelope]()
      case .unknown:
        try writer.execute(
          "UPDATE unsafe_tool_dispatches SET state = 'unknown', expected_ok = NULL WHERE conversation_id = ? AND runtime_task_key = ?",
          [.text(fence.conversationID.rawValue), .text(call.runtimeTaskKey)])
        return try holdTask(
          task,
          step: InterruptedStep(
            toolCallId: call.toolCallId, tool: call.tool, check: .inconclusive, since: now), at: now
        ) + ensureResumeCards(fence.conversationID, callMayContinue: false, at: now)
      }
    }
    if case .returned = outcome { keepOwner = true }
    eventBus.publish(events)
  }

  /// What Memoshi recorded about dispatching this tool task (`ToolDispatchEvidence`).
  public func unsafeToolDispatchEvidence(_ conversation: ConversationID, runtimeTaskKey: String)
    throws -> ToolDispatchEvidence
  {
    try requireOpen()
    return try reader.transaction(write: false) {
      let values: [SQLiteConnection.Value] = [.text(conversation.rawValue), .text(runtimeTaskKey)]
      if try reader.integer(
        """
        SELECT (SELECT COUNT(*) FROM unsafe_tool_dispatches
          WHERE conversation_id = ?1 AND runtime_task_key = ?2)
          + (SELECT COUNT(*) FROM resume_steps WHERE conversation_id = ?1 AND runtime_task_key = ?2)
        """, values) ?? 0 > 0
      {
        return .recorded
      }
      return try reader.integer(
        """
        SELECT COUNT(*) FROM policy_tool_calls
        WHERE conversation_id = ? AND runtime_task_key = ? AND completion_seq IS NOT NULL
        """, values) ?? 0 > 0 ? .completed : .absent
    }
  }

  /// Holds an interrupted call as an unknown dispatch: the same durable hold an uncertain
  /// effect gets, kept across reopen. It is one whose dispatch Memoshi cannot account for, or
  /// one Memoshi recorded as ended that Pi reports still open (its result was lost); the Resume
  /// card of the latter offers no Run again, since the call ran.
  public func holdUnaccountedToolDispatch(
    _ call: PolicyToolIdentity, fence: ConversationFence, at now: Int64
  ) throws {
    try requireOpen()
    let events = try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      let task = try dispatchTask(call, fence: fence, completed: true)
      try writer.execute(
        """
        INSERT INTO unsafe_tool_dispatches (conversation_id, runtime_task_key, state, started_at)
        VALUES (?, ?, 'unknown', ?)
        ON CONFLICT (conversation_id, runtime_task_key) DO UPDATE SET state = 'unknown', expected_ok = NULL
        """,
        [.text(fence.conversationID.rawValue), .text(call.runtimeTaskKey), .integer(now)])
      return try holdTask(
        task,
        step: InterruptedStep(
          toolCallId: call.toolCallId, tool: call.tool, check: .inconclusive, since: now), at: now)
        + ensureResumeCards(fence.conversationID, callMayContinue: true, at: now)
    }
    releaseUnsafeDispatchOwner(fence.conversationID, task: call.runtimeTaskKey)
    eventBus.publish(events)
  }

  /// Projects actual durable uncertainty before the host starts or resumes a conversation, with
  /// a Resume card for each held step (D51). It does not run an outcome check, declare an
  /// effect undone, or settle an SDK tool task: only the user's answer on the card does.
  public func projectChatRecovery(
    _ chatID: ConversationID, fence: ConversationFence, at now: Int64
  ) throws {
    try requireOpen()
    let events = try writer.transaction(write: true) {
      guard fence.conversationID == chatID else {
        throw StoreError.invalidCommit("Wrong recovery conversation fence")
      }
      try checkFence(fence, at: now)
      guard let held = try readChatRecovery(chatID, database: writer) else {
        return [EventEnvelope]()
      }
      var events: [EventEnvelope] = []
      for entry in held.steps {
        guard
          let task = try writer.query(
            "SELECT record FROM tasks WHERE id = ? AND conversation_id = ?",
            [.text(entry.taskId.rawValue), .text(chatID.rawValue)],
            row: { try decoder.decode(MemoshiTask.self, from: $0.requiredData(0)) }
          ).first
        else { throw StoreError.invalidSchema("Recovery task is missing") }
        events += try holdTask(task, step: entry.step, at: now)
      }
      return events + (try ensureResumeCards(chatID, callMayContinue: true, at: now))
    }
    eventBus.publish(events)
  }

  /// The runtime drains actual Pi commits first, then parks any intent its closing executor
  /// can no longer own. No unknown effect is converted into a known cancellation.
  public func parkUnsettledToolDispatches(
    fence: ConversationFence, at now: Int64
  ) throws {
    try requireOpen()
    try checkFence(fence, at: now)
    parkedDispatchEpochs[fence.conversationID] = fence.epoch
    currentUnsafeDispatches.removeValue(forKey: fence.conversationID)
    try projectChatRecovery(fence.conversationID, fence: fence, at: now)
  }

  /// Projects actual final Pi metadata, including validation performed after host hooks.
  /// A known return retires only if Pi preserved its meaning; unknown effects never retire here.
  func projectToolDispatchCompletion(
    _ completion: ToolCompletedPayload, call: PolicyToolIdentity,
    task: MemoshiTask, at now: Int64
  ) throws -> [EventEnvelope] {
    let updated = try projectResumeCompletion(task, runtimeTaskKey: call.runtimeTaskKey, at: now)
    let state = try writer.query(
      "SELECT state, expected_ok FROM unsafe_tool_dispatches WHERE conversation_id = ? AND runtime_task_key = ?",
      [.text(task.conversationId.rawValue), .text(call.runtimeTaskKey)],
      row: { (try $0.requiredText(0), $0.optionalInteger(1)) }
    ).first
    guard let state else { return updated }
    let preservedMeaning = completion.errorCode == nil || completion.errorCode == "tool_failed"
    if state.0 == "returned", state.1 == (completion.ok ? 1 : 0), preservedMeaning {
      try writer.execute(
        "DELETE FROM unsafe_tool_dispatches WHERE conversation_id = ? AND runtime_task_key = ?",
        [.text(task.conversationId.rawValue), .text(call.runtimeTaskKey)])
      releaseUnsafeDispatchOwner(task.conversationId, task: call.runtimeTaskKey)
      return try updated + clearKnownDispatchHold(task, call: call, at: now)
    }
    try writer.execute(
      "UPDATE unsafe_tool_dispatches SET state = 'unknown', expected_ok = NULL WHERE conversation_id = ? AND runtime_task_key = ?",
      [.text(task.conversationId.rawValue), .text(call.runtimeTaskKey)])
    releaseUnsafeDispatchOwner(task.conversationId, task: call.runtimeTaskKey)
    return try updated
      + holdTask(
        task,
        step: InterruptedStep(
          toolCallId: call.toolCallId, tool: call.tool, check: .inconclusive, since: now), at: now)
      + ensureResumeCards(task.conversationId, callMayContinue: false, at: now)
  }

  /// Marks an already-owned task as waiting without erasing its earlier usage or evidence.
  private func holdTask(_ initial: MemoshiTask, step: InterruptedStep?, at now: Int64) throws
    -> [EventEnvelope]
  {
    guard [.queued, .running, .waiting].contains(initial.status) else { return [] }
    var task = initial
    task.status = .waiting
    task.waitingOn = .resume
    task.resumeMode = .explicit
    task.interruptedStep = initial.interruptedStep ?? step
    guard task != initial else { return [] }
    if var turn = try writer.query(
      "SELECT record FROM chat_turns WHERE json_extract(record, '$.taskId') = ?",
      [.text(task.id.rawValue)],
      row: { try decoder.decode(StoredChatTurn.self, from: $0.requiredData(0)) }
    ).first {
      turn.recoveryStep = task.interruptedStep
      turn.status = .waiting
      try writeTurn(turn)
    }
    try writeRecord(.task(task))
    return [
      try append(
        EventDraft(
          ts: now, actor: Actor(kind: .system),
          subject: ObjectRef(kind: "task", id: task.id.rawValue),
          scope: EventScope(
            botId: task.botId, conversationId: task.conversationId, taskId: task.id),
          origin: task.origin,
          event: .taskStatusChanged(
            TaskStatusChangedPayload(
              taskId: task.id, status: .waiting, waitingOn: .resume,
              previous: initial.status == .waiting ? .waiting : .running))))
    ]
  }

  private func clearKnownDispatchHold(
    _ initial: MemoshiTask, call: PolicyToolIdentity, at now: Int64
  ) throws -> [EventEnvelope] {
    guard initial.status == .waiting, initial.waitingOn == .resume,
      initial.resumeMode == .explicit,
      initial.interruptedStep?.toolCallId == call.toolCallId
    else { return [] }
    return try releaseHeldTask(initial, at: now)
  }

  /// Ends a task's explicit hold. A decision still pending on this task is what it waits on
  /// once the hold is gone; the task goes there directly and is never recorded as running in
  /// between.
  func releaseHeldTask(_ initial: MemoshiTask, at now: Int64) throws -> [EventEnvelope] {
    let call = initial.interruptedStep
    let pending = try hasPendingApproval(initial.id)
    var task = initial
    task.status = pending ? .waiting : .running
    task.waitingOn = pending ? .approval : nil
    task.resumeMode = .auto
    task.interruptedStep = nil
    try writeRecord(.task(task))
    if var turn = try writer.query(
      "SELECT record FROM chat_turns WHERE json_extract(record, '$.taskId') = ?",
      [.text(task.id.rawValue)],
      row: { try decoder.decode(StoredChatTurn.self, from: $0.requiredData(0)) }
    ).first,
      !turn.isTerminal, turn.recoveryStep?.toolCallId == call?.toolCallId
    {
      turn.recoveryStep = nil
      turn.status = task.status
      try writeTurn(turn)
    }
    return [
      try append(
        EventDraft(
          ts: now, actor: Actor(kind: .system),
          subject: ObjectRef(kind: "task", id: task.id.rawValue),
          scope: EventScope(
            botId: task.botId, conversationId: task.conversationId, taskId: task.id),
          origin: task.origin,
          event: .taskStatusChanged(
            TaskStatusChangedPayload(
              taskId: task.id, status: pending ? .waiting : .running,
              waitingOn: task.waitingOn, previous: .waiting))))
    ]
  }

  func releaseUnsafeDispatchOwner(_ conversation: ConversationID, task: String) {
    currentUnsafeDispatches[conversation]?.remove(task)
    if currentUnsafeDispatches[conversation]?.isEmpty == true {
      currentUnsafeDispatches.removeValue(forKey: conversation)
    }
  }

  /// The call's task, while the call is open; `completed` also takes one Memoshi recorded as
  /// ended.
  private func dispatchTask(
    _ call: PolicyToolIdentity, fence: ConversationFence, completed: Bool = false
  ) throws -> MemoshiTask {
    guard
      let task = try writer.query(
        """
        SELECT t.record FROM policy_tool_calls p JOIN tasks t ON t.id = p.task_id
        WHERE p.conversation_id = ? AND p.runtime_task_key = ? AND p.task_id = ?
          AND p.tool_call_id = ? AND p.tool = ? AND p.parent_tool_call_id IS ?
          AND p.decision_observed = 1 AND (p.completion_seq IS NULL OR ?)
        """,
        [
          .text(fence.conversationID.rawValue), .text(call.runtimeTaskKey),
          .text(call.taskId.rawValue), .text(call.toolCallId), .text(call.tool),
          SQLiteConnection.Value(call.parentToolCallId), .integer(completed ? 1 : 0),
        ],
        row: { try decoder.decode(MemoshiTask.self, from: $0.requiredData(0)) }
      ).first
    else { throw ApprovalError.bindingConflict }
    return task
  }
}
