import Foundation
import MemoshiProtocol

extension Store {
  /// Records a real authorization or dispatch check and binds its immutable Pi task identity.
  /// Each real check remains a separate fact; a completion receipt cannot be reopened.
  public func recordPolicyToolDecision(
    _ decision: PolicyDecidedPayload, call: PolicyToolIdentity,
    fence: ConversationFence, at now: Int64
  ) throws {
    try requireOpen()
    let events = try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      let task = try policyToolTask(call, fence: fence)
      try validatePolicyToolDecision(decision, call: call, task: task)
      let state = try bindPolicyTool(call, task: task)
      guard state.completionSeq == nil else { throw ApprovalError.bindingConflict }
      let event = try append(
        policyToolEvent(.policyDecided(decision), call: call, task: task, at: now))
      try writer.execute(
        "UPDATE policy_tool_calls SET decision_observed = 1 WHERE conversation_id = ? AND runtime_task_key = ?",
        [.text(task.conversationId.rawValue), .text(call.runtimeTaskKey)])
      return [event]
    }
    eventBus.publish(events)
  }

  /// Persists output-free scrub accounting and sticky exposure before Pi commits its result.
  /// Exact hook replay adds neither a second redaction fact nor a completion.
  public func preparePolicyToolResult(
    call: PolicyToolIdentity, redaction: PolicyRedactedPayload?, exposure: Exposure,
    fence: ConversationFence, at now: Int64
  ) throws {
    try requireOpen()
    guard
      redaction == nil
        || (redaction?.toolCallId == call.toolCallId && (redaction?.count ?? -1) >= 0)
    else { throw ApprovalError.bindingConflict }
    let preparation = PolicyToolPreparation(redaction: redaction, exposure: exposure)
    let events = try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      let task = try policyToolTask(call, fence: fence)
      let state = try bindPolicyTool(call, task: task)
      guard state.decisionObserved else { throw ApprovalError.bindingConflict }
      if let previous = state.preparation {
        guard previous == preparation else { throw ApprovalError.bindingConflict }
        return [EventEnvelope]()
      }
      guard state.completionSeq == nil else { throw ApprovalError.bindingConflict }
      try writer.execute(
        "UPDATE policy_tool_calls SET preparation = ? WHERE conversation_id = ? AND runtime_task_key = ?",
        [
          .json(try encoder.encode(preparation)), .text(task.conversationId.rawValue),
          .text(call.runtimeTaskKey),
        ])
      if exposure.untrusted || exposure.privateData {
        try writer.execute(
          """
          INSERT INTO conversation_exposure (conversation_id, untrusted, private_data) VALUES (?, ?, ?)
          ON CONFLICT (conversation_id) DO UPDATE SET
            untrusted = MAX(untrusted, excluded.untrusted), private_data = MAX(private_data, excluded.private_data)
          """,
          [
            .text(task.conversationId.rawValue), .integer(exposure.untrusted ? 1 : 0),
            .integer(exposure.privateData ? 1 : 0),
          ])
      }
      guard let redaction else { return [EventEnvelope]() }
      return [
        try append(policyToolEvent(.policyRedacted(redaction), call: call, task: task, at: now))
      ]
    }
    eventBus.publish(events)
  }

  /// Reads the original final fact before touching Pi documents that terminal tasks may retire.
  /// A legacy read is not a new binding or proof that the old hook observed a Pi commit.
  public func policyToolCompletion(
    call: PolicyToolIdentity, fence: ConversationFence, at now: Int64
  ) throws -> ToolCompletedPayload? {
    try requireOpen()
    return try writer.transaction(write: false) {
      try checkFence(fence, at: now)
      let task = try policyToolTask(call, fence: fence)
      if let state = try readPolicyToolState(call, task: task), let seq = state.completionSeq {
        guard
          let envelope = try writer.query(
            "SELECT envelope FROM audit_events WHERE seq = ?", [.integer(seq)],
            row: { try decoder.decode(EventEnvelope.self, from: $0.requiredData(0)) }
          ).first
        else {
          throw StoreError.integrityFailed("Tool completion receipt lost its audit fact")
        }
        return try policyToolCompletionFact(envelope, call: call, task: task).payload
      }
      return try legacyPolicyToolCompletion(call, task: task)?.payload
    }
  }

  /// Called only after the adapter observes an immutable Pi terminal result.
  /// Completion, its plain class-A mirror and its replay receipt commit atomically.
  public func completePolicyTool(
    _ completion: ToolCompletedPayload, call: PolicyToolIdentity,
    fallbackDecision: PolicyDecidedPayload?, fence: ConversationFence, at now: Int64
  ) throws {
    try requireOpen()
    guard completion.toolCallId == call.toolCallId,
      completion.parentToolCallId == call.parentToolCallId, completion.tool == call.tool,
      completion.durationMs >= 0, completion.outputBytes >= 0, completion.redactions >= 0
    else { throw ApprovalError.bindingConflict }
    let events = try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      let task = try policyToolTask(call, fence: fence)
      let state = try bindPolicyTool(call, task: task)
      if let previous = state.completionInput {
        guard previous == completion else { throw ApprovalError.bindingConflict }
        return try projectToolDispatchCompletion(completion, call: call, task: task, at: now)
          + flushGatewayAudit(conversationID: task.conversationId, taskID: task.id, at: now)
      }
      var settled = completion
      settled.redactions = state.preparation?.redaction?.count ?? 0
      if let legacy = try legacyPolicyToolCompletion(call, task: task) {
        guard legacy.payload.ok == settled.ok,
          try writer.integer(
            "SELECT COUNT(*) FROM policy_tool_calls WHERE completion_seq = ?",
            [.integer(legacy.seq)]) == 0
        else { throw ApprovalError.bindingConflict }
        // Preserve the original fact, including its old hook timing and redaction count.
        // This receipt describes today's observation; no historical Pi proof is fabricated.
        try writePolicyToolCompletion(completion, seq: legacy.seq, call: call, task: task)
        return try projectToolDispatchCompletion(completion, call: call, task: task, at: now)
          + flushGatewayAudit(conversationID: task.conversationId, taskID: task.id, at: now)
      }
      var appended: [EventEnvelope] = []
      if state.decisionObserved == false {
        guard let fallbackDecision, fallbackDecision.decision == .deny, settled.ok == false else {
          throw ApprovalError.bindingConflict
        }
        try validatePolicyToolDecision(fallbackDecision, call: call, task: task)
        appended.append(
          try append(
            policyToolEvent(.policyDecided(fallbackDecision), call: call, task: task, at: now)))
      }
      let event = try append(
        policyToolEvent(.toolCompleted(settled), call: call, task: task, at: now))
      guard let seq = event.seq else {
        throw StoreError.invalidCommit("Tool completion must be durable")
      }
      appended.append(event)
      try writePolicyToolCompletion(completion, seq: seq, call: call, task: task)
      appended += try projectToolDispatchCompletion(completion, call: call, task: task, at: now)
      appended += try flushGatewayAudit(
        conversationID: task.conversationId, taskID: task.id, at: now)
      return appended
    }
    eventBus.publish(events)
  }

  /// Resolves the admitted turn containing a committed root assistant input, never active work.
  public func chatTurn(containingPiEntry entryID: Int, chatID: ConversationID) throws
    -> StoredChatTurn?
  {
    try requireOpen()
    return try reader.query(
      """
      SELECT r.record FROM chat_turns r JOIN chats c ON c.id = r.conversation_id
      JOIN tasks t ON t.id = json_extract(r.record, '$.taskId')
        AND t.conversation_id = c.id AND t.bot_id = c.bot_id
      WHERE r.conversation_id = ? AND json_extract(r.record, '$.userEntryId') IS NOT NULL
        AND json_extract(r.record, '$.userEntryId') <= ?
      ORDER BY json_extract(r.record, '$.userEntryId') DESC LIMIT 1
      """, [.text(chatID.rawValue), .integer(Int64(entryID))]
    ) { try decoder.decode(StoredChatTurn.self, from: $0.requiredData(0)) }.first
  }

  private struct PolicyToolState {
    let decisionObserved: Bool
    let preparation: PolicyToolPreparation?
    let completionInput: ToolCompletedPayload?
    let completionSeq: Int64?
  }

  private func policyToolTask(_ call: PolicyToolIdentity, fence: ConversationFence) throws
    -> MemoshiTask
  {
    guard call.runtimeTaskKey.isEmpty == false, call.toolCallId.isEmpty == false,
      call.tool.isEmpty == false, call.parentToolCallId?.isEmpty != true,
      let task = try writer.query(
        "SELECT record, bot_id FROM tasks WHERE id = ? AND conversation_id = ?",
        [.text(call.taskId.rawValue), .text(fence.conversationID.rawValue)],
        row: { row in
          let task = try decoder.decode(MemoshiTask.self, from: row.requiredData(0))
          guard try row.requiredText(1) == task.botId.rawValue else {
            throw ApprovalError.bindingConflict
          }
          return task
        }
      ).first,
      task.id == call.taskId, task.conversationId == fence.conversationID
    else { throw ApprovalError.bindingConflict }
    return task
  }

  private func readPolicyToolState(_ call: PolicyToolIdentity, task: MemoshiTask) throws
    -> PolicyToolState?
  {
    try writer.query(
      """
      SELECT task_id, bot_id, tool_call_id, parent_tool_call_id, tool, origin,
        decision_observed, preparation, completion_input, completion_seq
      FROM policy_tool_calls WHERE conversation_id = ? AND runtime_task_key = ?
      """, [.text(task.conversationId.rawValue), .text(call.runtimeTaskKey)]
    ) { row in
      guard try row.requiredText(0) == call.taskId.rawValue,
        try row.requiredText(1) == task.botId.rawValue,
        try row.requiredText(2) == call.toolCallId, row.text(3) == call.parentToolCallId,
        try row.requiredText(4) == call.tool,
        try decoder.decode(Origin.self, from: row.requiredData(5)) == task.origin
      else { throw ApprovalError.bindingConflict }
      return try PolicyToolState(
        decisionObserved: row.integer(6) == 1,
        preparation: row.data(7).map { try decoder.decode(PolicyToolPreparation.self, from: $0) },
        completionInput: row.data(8).map {
          try decoder.decode(ToolCompletedPayload.self, from: $0)
        },
        completionSeq: row.optionalInteger(9))
    }.first
  }

  private func bindPolicyTool(_ call: PolicyToolIdentity, task: MemoshiTask) throws
    -> PolicyToolState
  {
    if let state = try readPolicyToolState(call, task: task) { return state }
    try writer.execute(
      """
      INSERT INTO policy_tool_calls
        (conversation_id, runtime_task_key, task_id, bot_id, tool_call_id, parent_tool_call_id, tool, origin)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        .text(task.conversationId.rawValue), .text(call.runtimeTaskKey), .text(task.id.rawValue),
        .text(task.botId.rawValue), .text(call.toolCallId),
        SQLiteConnection.Value(call.parentToolCallId),
        .text(call.tool), .json(try encoder.encode(task.origin)),
      ])
    return PolicyToolState(
      decisionObserved: false, preparation: nil, completionInput: nil, completionSeq: nil)
  }

  private func validatePolicyToolDecision(
    _ decision: PolicyDecidedPayload, call: PolicyToolIdentity, task: MemoshiTask
  ) throws {
    guard decision.toolCallId == call.toolCallId,
      decision.parentToolCallId == call.parentToolCallId, decision.tool == call.tool,
      decision.origin == task.origin, decision.deviceId == deviceID
    else { throw ApprovalError.bindingConflict }
  }

  private func writePolicyToolCompletion(
    _ input: ToolCompletedPayload, seq: Int64,
    call: PolicyToolIdentity, task: MemoshiTask
  ) throws {
    try writer.execute(
      """
      UPDATE policy_tool_calls SET completion_input = ?, completion_seq = ?
      WHERE conversation_id = ? AND runtime_task_key = ?
      """,
      [
        .json(try encoder.encode(input)), .integer(seq),
        .text(task.conversationId.rawValue), .text(call.runtimeTaskKey),
      ])
  }

  private func legacyPolicyToolCompletion(_ call: PolicyToolIdentity, task: MemoshiTask) throws
    -> (seq: Int64, payload: ToolCompletedPayload)?
  {
    guard
      let raw = try writer.text("SELECT value FROM meta WHERE key = 'policy_tool_legacy_cutoff'"),
      let cutoff = Int64(raw), cutoff >= 0
    else { throw StoreError.invalidSchema("Missing tool audit migration boundary") }
    guard cutoff > 0 else { return nil }
    let candidates = try writer.query(
      """
      SELECT envelope FROM audit_events WHERE type = 'tool.completed' AND seq <= ?
        AND json_extract(envelope, '$.scope.conversationId') = ?
        AND json_extract(envelope, '$.scope.taskId') = ?
        AND json_extract(envelope, '$.payload.toolCallId') = ?
      ORDER BY seq LIMIT 2
      """,
      [
        .integer(cutoff), .text(task.conversationId.rawValue), .text(task.id.rawValue),
        .text(call.toolCallId),
      ]
    ) { try decoder.decode(EventEnvelope.self, from: $0.requiredData(0)) }
    guard let legacy = candidates.first else { return nil }
    guard candidates.count == 1 else { throw ApprovalError.bindingConflict }
    return try policyToolCompletionFact(legacy, call: call, task: task)
  }

  private func policyToolCompletionFact(
    _ envelope: EventEnvelope, call: PolicyToolIdentity, task: MemoshiTask
  ) throws -> (seq: Int64, payload: ToolCompletedPayload) {
    guard let seq = envelope.seq,
      envelope.scope.conversationId == task.conversationId, envelope.scope.taskId == task.id,
      envelope.scope.botId == task.botId, envelope.origin == task.origin,
      envelope.subject == ObjectRef(kind: "tool_call", id: call.toolCallId),
      case .toolCompleted(let payload) = envelope.event,
      payload.toolCallId == call.toolCallId, payload.tool == call.tool,
      payload.parentToolCallId == call.parentToolCallId
    else { throw ApprovalError.bindingConflict }
    return (seq, payload)
  }

  private func policyToolEvent(
    _ event: Event, call: PolicyToolIdentity, task: MemoshiTask, at now: Int64
  ) -> EventDraft {
    EventDraft(
      ts: now,
      actor: event.type == ToolCompletedPayload.eventType
        ? Actor(kind: .bot, id: task.botId.rawValue) : Actor(kind: .system),
      subject: ObjectRef(kind: "tool_call", id: call.toolCallId),
      scope: EventScope(botId: task.botId, conversationId: task.conversationId, taskId: task.id),
      origin: task.origin, event: event)
  }
}
