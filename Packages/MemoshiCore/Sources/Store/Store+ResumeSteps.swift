import Foundation
import MemoshiProtocol

/// The user's answer on a Resume card that the runtime must still give Pi.
public struct ResumeDecision: Hashable, Sendable {
  /// The card the user answered.
  public let cardId: CardID
  /// Run again, Skip or Mark as done.
  public let action: ResumeAction
}

/// D51: a held tool step gets a Resume card; the user's answer on it is recorded here first, so
/// the hold clears before Pi is told. The runtime then answers Pi's decision wait, and Memoshi's
/// dispatch gate lets one Run again through exactly once.
extension Store {
  /// The user's answer, in one transaction with its card, its audit facts and the release of
  /// the step's hold. A retry returns the original receipt. Run again is refused once Pi has
  /// ended the call, since nothing is left to run again.
  public func respondToResume(
    _ params: CardsRespondParams, paramsHash: String, actor: Actor,
    fence: ConversationFence, at now: Int64
  ) throws -> CardsRespondResult {
    try requireOpen()
    guard actor.kind == .user, params.surface == nil || params.surface == .ui else {
      throw ApprovalError.forbidden
    }
    let action = ResumeAction(rawValue: params.action)
    guard action.isKnown, params.deviceAuth == nil,
      params.payload == nil || params.payload == .object([:])
    else { throw ApprovalError.invalidRequest }
    var events: [EventEnvelope] = []
    var released: Set<String> = []
    let receipt: CardsRespondResult = try writer.transaction(write: true) {
      if var previous = try requestResult(
        params.requestId, method: CardsRespond.name, paramsHash: paramsHash,
        as: CardsRespondResult.self)
      {
        previous.replayed = true
        return previous
      }
      try checkFence(fence, at: now)
      guard
        let step = try writer.query(
          "SELECT conversation_id, runtime_task_key, state FROM resume_steps WHERE card_id = ?",
          [.text(params.cardId.rawValue)],
          row: { (try $0.requiredText(0), try $0.requiredText(1), try $0.requiredText(2)) }
        ).first,
        var card = try writer.query(
          "SELECT record FROM cards WHERE id = ?", [.text(params.cardId.rawValue)],
          row: { try decoder.decode(Card.self, from: $0.requiredData(0)) }
        ).first
      else { throw ApprovalError.notFound }
      guard step.0 == fence.conversationID.rawValue, card.conversationId == fence.conversationID,
        card.kind == .resume
      else { throw ApprovalError.bindingConflict }
      guard card.status == .pending, step.2 == "open" else {
        throw ApprovalError.resolved(
          cardID: card.id, action: card.outcome?.action ?? card.status.rawValue)
      }
      let key = step.1
      guard
        let call = try writer.query(
          """
          SELECT task_id, tool_call_id, tool, completion_seq IS NULL FROM policy_tool_calls
          WHERE conversation_id = ? AND runtime_task_key = ?
          """, [.text(fence.conversationID.rawValue), .text(key)],
          row: {
            (
              try TaskID($0.requiredText(0)), try $0.requiredText(1), try $0.requiredText(2),
              $0.integer(3) == 1
            )
          }
        ).first
      else { throw ApprovalError.bindingConflict }
      let callOpen = call.3
      guard Self.resumeActions(card).contains(params.action), action != .runAgain || callOpen
      else { throw ApprovalError.invalidRequest }
      card.status = .resolved
      card.outcome = CardOutcome(action: params.action)
      card.inbox = false
      card.needsYou = false
      card.resolvedBy = actor
      card.resolvedAt = now
      try writeRecord(.card(card))
      try writer.execute(
        "UPDATE resume_steps SET action = ?, state = ?, decided_at = ? WHERE card_id = ?",
        [
          .text(params.action), .text(callOpen ? "decided" : "noted"), .integer(now),
          .text(card.id.rawValue),
        ])
      // The answer settles Memoshi's uncertainty about this dispatch; the dispatch gate now
      // reads the answer instead (`beginUnsafeToolDispatch`).
      try writer.execute(
        "DELETE FROM unsafe_tool_dispatches WHERE conversation_id = ? AND runtime_task_key = ?",
        [.text(fence.conversationID.rawValue), .text(key)])
      released.insert(key)
      guard
        let task = try writer.query(
          "SELECT record FROM tasks WHERE id = ?", [.text(call.0.rawValue)],
          row: { try decoder.decode(MemoshiTask.self, from: $0.requiredData(0)) }
        ).first
      else { throw StoreError.invalidSchema("Recovery task is missing") }
      let scope = EventScope(
        botId: task.botId, conversationId: task.conversationId, taskId: task.id)
      events.append(
        try append(
          EventDraft(
            ts: now, actor: actor, subject: ObjectRef(kind: "tool_call", id: call.1),
            scope: scope, origin: task.origin,
            event: .toolInterruptionResolved(
              .init(
                toolCallId: call.1, tool: call.2, action: action, cardId: card.id,
                by: actor.kind)))))
      events.append(
        try append(
          EventDraft(
            ts: now, actor: actor, subject: ObjectRef(kind: "card", id: card.id.rawValue),
            scope: scope, origin: task.origin,
            event: .cardResolved(
              .init(cardId: card.id, outcome: CardOutcome(action: params.action), by: .user)))))
      events += try releaseResumedTask(task, at: now)
      guard let writtenSeq = events.last?.seq else { throw ApprovalError.bindingConflict }
      let receipt = CardsRespondResult(card: card, writtenSeq: writtenSeq, replayed: false)
      try saveRequest(
        params.requestId, method: CardsRespond.name, paramsHash: paramsHash, result: receipt,
        at: now)
      return receipt
    }
    for key in released { releaseUnsafeDispatchOwner(fence.conversationID, task: key) }
    eventBus.publish(events)
    return receipt
  }

  /// Answers the runtime has not given Pi yet, by Pi tool-task key: the latest for each. A Skip
  /// or Mark as done given on a call Memoshi had seen end (`noted`) is one: should Pi still wait
  /// on that call, it lost the result Memoshi saw (`ToolDispatchEvidence.completed`), and Pi
  /// needs the user's answer. Neither runs anything; the runtime gives an answer only to a step
  /// that waits on one.
  public func pendingResumeDecisions(_ conversation: ConversationID) throws
    -> [String: ResumeDecision]
  {
    try requireOpen()
    return try reader.transaction(write: false) {
      let rows = try reader.query(
        """
        SELECT runtime_task_key, card_id, action FROM resume_steps
        WHERE conversation_id = ? AND (state = 'decided'
          OR (state = 'noted' AND action IN ('skip', 'mark_done')))
        ORDER BY decided_at DESC, card_id DESC
        """, [.text(conversation.rawValue)]
      ) { row in
        (
          try row.requiredText(0),
          ResumeDecision(
            cardId: try CardID(row.requiredText(1)),
            action: ResumeAction(rawValue: try row.requiredText(2)))
        )
      }
      return Dictionary(rows, uniquingKeysWith: { latest, _ in latest })
    }
  }

  /// Answers the model must read, by Pi tool-task key, with the card each answered: a Skip or
  /// Mark as done, and a Run again that may have found no wait. An answer on a call Pi had
  /// already ended (`noted`) never reaches Pi. An answer recorded as `decided` may still have
  /// found Pi's call ended: Memoshi projects Pi's result after Pi commits it, so the answer can
  /// land in between, and Pi then has no wait to give it to; a Run again then runs nothing. The
  /// runtime therefore adds the note to every such result unless Pi's committed result records
  /// this very card's answer (`PolicyHooks.resumeNotes`), as a Run again's rerun does; a later
  /// rerun carries an earlier card's answer instead.
  public func notedResumeDecisions(_ conversation: ConversationID) throws
    -> [String: ResumeDecision]
  {
    try requireOpen()
    return try reader.transaction(write: false) {
      let rows = try reader.query(
        """
        SELECT runtime_task_key, card_id, action FROM resume_steps
        WHERE conversation_id = ? AND action IN ('run_again', 'skip', 'mark_done')
          AND state IN ('decided', 'noted', 'settled')
        ORDER BY decided_at, card_id
        """, [.text(conversation.rawValue)]
      ) { row in
        (
          try row.requiredText(0),
          ResumeDecision(
            cardId: try CardID(row.requiredText(1)),
            action: ResumeAction(rawValue: try row.requiredText(2)))
        )
      }
      return Dictionary(rows, uniquingKeysWith: { _, latest in latest })
    }
  }

  /// Whether a Resume card exists for this Pi tool task, answered or not.
  func hasResumeStep(_ conversation: ConversationID, runtimeTaskKey: String) throws -> Bool {
    try writer.integer(
      "SELECT COUNT(*) FROM resume_steps WHERE conversation_id = ? AND runtime_task_key = ?",
      [.text(conversation.rawValue), .text(runtimeTaskKey)]) ?? 0 > 0
  }

  /// Memoshi's dispatch gate for a step with a Resume card: only an unapplied Run again admits
  /// one new execution, and is used up by it. Skip and Mark as done never admit one.
  func admitResumedDispatch(_ conversation: ConversationID, runtimeTaskKey: String) throws {
    guard try hasResumeStep(conversation, runtimeTaskKey: runtimeTaskKey) else { return }
    guard
      let card = try writer.text(
        """
        SELECT card_id FROM resume_steps WHERE conversation_id = ? AND runtime_task_key = ?
          AND state = 'decided' AND action = 'run_again'
        """, [.text(conversation.rawValue), .text(runtimeTaskKey)])
    else { throw StoreError.chatRecoveryRequired }
    try writer.execute(
      "UPDATE resume_steps SET state = 'dispatched' WHERE card_id = ?", [.text(card)])
  }

  /// Pi committed the call's result: an answer given before it is settled, and an unanswered
  /// card no longer offers Run again (`card.updated`, so every client shows the new choices).
  func projectResumeCompletion(_ task: MemoshiTask, runtimeTaskKey: String, at now: Int64) throws
    -> [EventEnvelope]
  {
    let conversation = task.conversationId
    try writer.execute(
      """
      UPDATE resume_steps SET state = 'settled' WHERE conversation_id = ? AND runtime_task_key = ?
        AND state IN ('decided', 'dispatched')
      """, [.text(conversation.rawValue), .text(runtimeTaskKey)])
    let open = try writer.query(
      """
      SELECT c.record FROM resume_steps r JOIN cards c ON c.id = r.card_id
      WHERE r.conversation_id = ? AND r.runtime_task_key = ? AND r.state = 'open'
      """, [.text(conversation.rawValue), .text(runtimeTaskKey)],
      row: { try decoder.decode(Card.self, from: $0.requiredData(0)) })
    var events: [EventEnvelope] = []
    for var card in open where Self.resumeActions(card).contains("run_again") {
      card.payload = Self.resumePayload(card.payload, actions: ["skip", "mark_done"])
      try writeRecord(.card(card))
      events.append(
        try append(
          EventDraft(
            ts: now, actor: Actor(kind: .system),
            subject: ObjectRef(kind: "card", id: card.id.rawValue),
            scope: EventScope(
              botId: task.botId, conversationId: task.conversationId, taskId: card.taskId),
            origin: task.origin,
            event: .cardUpdated(.init(cardId: card.id, payload: card.payload)))))
    }
    return events
  }

  /// Creates a Resume card, in the caller's transaction, for every held step without one.
  /// `callMayContinue` is false where the execution itself just returned or was stopped: Pi
  /// then commits a result for the call, so Run again is not offered. After a restart Pi's
  /// call is still open, and Run again is offered unless Pi has already committed a result.
  func ensureResumeCards(
    _ conversation: ConversationID, callMayContinue: Bool, at now: Int64
  ) throws -> [EventEnvelope] {
    var events: [EventEnvelope] = []
    for held in try heldToolSteps(conversation, database: writer) where held.step.cardId == nil {
      events += try createResumeCard(
        held, conversation: conversation, callMayContinue: callMayContinue, at: now)
    }
    return events
  }

  private func createResumeCard(
    _ held: HeldToolStep, conversation: ConversationID, callMayContinue: Bool, at now: Int64
  ) throws -> [EventEnvelope] {
    guard
      var task = try writer.query(
        "SELECT record FROM tasks WHERE id = ?", [.text(held.taskId.rawValue)],
        row: { try decoder.decode(MemoshiTask.self, from: $0.requiredData(0)) }
      ).first,
      var turn = try writer.query(
        """
        SELECT record FROM chat_turns WHERE json_extract(record, '$.taskId') = ?
          OR json_extract(record, '$.taskId') IN (
            SELECT original_task_id FROM runtime_subagents WHERE task_id = ?)
        ORDER BY request_id LIMIT 1
        """, [.text(held.taskId.rawValue), .text(held.taskId.rawValue)],
        row: { try decoder.decode(StoredChatTurn.self, from: $0.requiredData(0)) }
      ).first
    else { throw StoreError.invalidSchema("Recovery task is missing") }
    let open =
      try writer.integer(
        """
        SELECT COUNT(*) FROM policy_tool_calls
        WHERE conversation_id = ? AND runtime_task_key = ? AND completion_seq IS NULL
        """, [.text(conversation.rawValue), .text(held.runtimeTaskKey)]) == 1
    // An export's dispatch record precedes its export record, so the tool name decides too.
    let export =
      try Self.exportTools.contains(held.step.tool)
      || writer.integer(
        "SELECT COUNT(*) FROM working_copy_exports WHERE conversation_id = ? AND runtime_task_key = ?",
        [.text(conversation.rawValue), .text(held.runtimeTaskKey)]) ?? 0 > 0
    // D138: a step the user stopped, in its own task or in the turn that owns it, never offers
    // Run again, also when a kill overtook the stopped execution before it returned.
    let stopped =
      try task.cancelRequestedAt != nil
      || (turn.taskId != task.id
        && writer.query(
          "SELECT record FROM tasks WHERE id = ?", [.text(turn.taskId.rawValue)],
          row: { try decoder.decode(MemoshiTask.self, from: $0.requiredData(0)) }
        ).first?.cancelRequestedAt != nil)
    let actions =
      (callMayContinue && open && !export && !stopped ? ["run_again"] : []) + ["skip", "mark_done"]
    let card = Card(
      id: try IDGenerator.shared.objectID(CardIDKind.self), kind: .resume,
      conversationId: conversation, messageId: turn.assistantMessageId, botId: task.botId,
      taskId: task.id, subject: ObjectRef(kind: "task", id: task.id.rawValue), status: .pending,
      inbox: true, needsYou: true, title: try Title("Interrupted: may have happened"),
      payload: Self.resumePayload(
        ["toolCallId": .string(held.step.toolCallId), "tool": .string(held.step.tool)],
        actions: actions),
      createdAt: now)
    try writeRecord(.card(card))
    try writer.execute(
      """
      INSERT INTO resume_steps (card_id, conversation_id, runtime_task_key, state, created_at)
      VALUES (?, ?, ?, 'open', ?)
      """,
      [
        .text(card.id.rawValue), .text(conversation.rawValue), .text(held.runtimeTaskKey),
        .integer(now),
      ])
    // The held task and its turn name the card of the step they show.
    if task.interruptedStep?.toolCallId == held.step.toolCallId {
      task.interruptedStep?.cardId = card.id
      try writeRecord(.task(task))
    }
    if turn.recoveryStep?.toolCallId == held.step.toolCallId, turn.taskId == held.taskId {
      turn.recoveryStep?.cardId = card.id
      try writeTurn(turn)
    }
    let scope = EventScope(
      botId: task.botId, conversationId: task.conversationId, taskId: task.id)
    return [
      try append(
        EventDraft(
          ts: now, actor: Actor(kind: .system),
          subject: ObjectRef(kind: "tool_call", id: held.step.toolCallId),
          scope: scope, origin: task.origin,
          event: .toolInterrupted(
            .init(
              toolCallId: held.step.toolCallId, tool: held.step.tool, replay: .unsafe,
              effect: .resumeCard)))),
      try append(
        EventDraft(
          ts: now, actor: Actor(kind: .system),
          subject: ObjectRef(kind: "card", id: card.id.rawValue),
          scope: scope, origin: task.origin,
          event: .cardCreated(
            .init(
              cardId: card.id, kind: card.kind, subject: card.subject,
              messageId: card.messageId, title: card.title, inbox: card.inbox,
              needsYou: card.needsYou, payload: card.payload)))),
    ]
  }

  /// Releases the answered step's task once no other step of it is held; otherwise the task
  /// shows its next held step.
  private func releaseResumedTask(_ initial: MemoshiTask, at now: Int64) throws
    -> [EventEnvelope]
  {
    guard [.queued, .running, .waiting].contains(initial.status),
      initial.resumeMode == .explicit
    else { return [] }
    let remaining = try heldToolSteps(initial.conversationId, database: writer)
      .filter { $0.taskId == initial.id }
    guard let next = remaining.first else {
      var events = try releaseHeldTask(initial, at: now)
      events.append(
        try append(
          EventDraft(
            ts: now, actor: Actor(kind: .user),
            subject: ObjectRef(kind: "task", id: initial.id.rawValue),
            scope: EventScope(
              botId: initial.botId, conversationId: initial.conversationId, taskId: initial.id),
            origin: initial.origin,
            event: .taskResumed(TaskResumedPayload(taskId: initial.id, by: .user)))))
      return events
    }
    var task = initial
    task.interruptedStep = next.step
    try writeRecord(.task(task))
    if var turn = try writer.query(
      "SELECT record FROM chat_turns WHERE json_extract(record, '$.taskId') = ?",
      [.text(task.id.rawValue)],
      row: { try decoder.decode(StoredChatTurn.self, from: $0.requiredData(0)) }
    ).first, !turn.isTerminal {
      turn.recoveryStep = next.step
      try writeTurn(turn)
    }
    return []
  }

  /// Tools that export a private working copy to the user's folder. Their copy does not
  /// outlive the process, so their Resume card never offers Run again.
  static let exportTools: Set<String> = [WorkingCopyExportTool.name]

  static func resumeActions(_ card: Card) -> [String] {
    guard case .object(let fields) = card.payload, case .array(let values)? = fields["actions"]
    else { return [] }
    return values.compactMap { if case .string(let text) = $0 { text } else { nil } }
  }

  private static func resumePayload(_ payload: JSONValue, actions: [String]) -> JSONValue {
    guard case .object(var fields) = payload else { return payload }
    fields["actions"] = .array(actions.map { .string($0) })
    return .object(fields)
  }
}
