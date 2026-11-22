import Foundation
import MemoshiProtocol

extension Store {
  /// Reads the hold and its watermark without opening or scheduling Pi work.
  public func chatRecovery(_ chatID: ConversationID) throws -> StoreSnapshot<ChatRecoveryHold?> {
    try requireOpen()
    return try reader.transaction(write: false) {
      StoreSnapshot(
        value: try readChatRecovery(chatID, database: reader),
        asOf: try position(conversationID: chatID))
    }
  }

  func readChatRecovery(_ chatID: ConversationID, database: SQLiteConnection) throws
    -> ChatRecoveryHold?
  {
    struct Key: Hashable {
      let task: TaskID
      let call: String?
    }
    var steps: [Key: HeldChatStep] = [:]
    let tasks = try database.query(
      """
      SELECT record FROM tasks WHERE conversation_id = ? AND status IN ('queued', 'running', 'waiting')
        AND json_extract(record, '$.resumeMode') = 'explicit'
      """, [.text(chatID.rawValue)]
    ) { try decoder.decode(MemoshiTask.self, from: $0.requiredData(0)) }
    for task in tasks {
      let key = Key(task: task.id, call: task.interruptedStep?.toolCallId)
      steps[key] = HeldChatStep(taskId: task.id, step: task.interruptedStep)
    }
    for held in try heldToolSteps(chatID, database: database) {
      steps[Key(task: held.taskId, call: held.step.toolCallId)] = HeldChatStep(
        taskId: held.taskId, step: held.step)
    }
    guard !steps.isEmpty else { return nil }
    return ChatRecoveryHold(
      steps: steps.values.sorted {
        $0.taskId == $1.taskId
          ? ($0.step?.toolCallId ?? "") < ($1.step?.toolCallId ?? "")
          : $0.taskId.rawValue < $1.taskId.rawValue
      })
  }

  /// One held tool step with its Pi tool task's key and, once it has one, its open Resume card.
  struct HeldToolStep {
    let runtimeTaskKey: String
    let taskId: TaskID
    let step: InterruptedStep
  }

  /// The held tool steps: an export whose effect is unknown or unsettled, and a dispatch whose
  /// record is not owned by an execution of this process or whose outcome is unknown. A step
  /// the user answered on its Resume card is no longer held.
  func heldToolSteps(_ chatID: ConversationID, database: SQLiteConnection) throws
    -> [HeldToolStep]
  {
    var held: [String: HeldToolStep] = [:]
    let exports = try database.query(
      """
      SELECT e.runtime_task_key, p.task_id, p.tool_call_id, p.tool, e.created_at, r.card_id
      FROM working_copy_exports e JOIN working_copies c ON c.id = e.copy_id
      JOIN policy_tool_calls p
        ON p.conversation_id = e.conversation_id AND p.runtime_task_key = e.runtime_task_key
      LEFT JOIN resume_steps r ON r.conversation_id = e.conversation_id
        AND r.runtime_task_key = e.runtime_task_key AND r.state = 'open'
      WHERE c.chat_id = ? AND (e.state = 'unknown' OR
        (c.phase IN ('interrupted', 'closed') AND (\(Self.unsettledCopyExport))))
        AND NOT \(Self.answeredCopyExport)
      """, [.text(chatID.rawValue)]
    ) { row in try Self.heldToolStep(row) }
    for entry in exports { held[entry.runtimeTaskKey] = entry }
    let conversation = chatID
    let dispatches = try database.query(
      """
      SELECT d.runtime_task_key, p.task_id, p.tool_call_id, p.tool, d.started_at, r.card_id,
        d.state
      FROM unsafe_tool_dispatches d JOIN policy_tool_calls p
        ON p.conversation_id = d.conversation_id AND p.runtime_task_key = d.runtime_task_key
      LEFT JOIN resume_steps r ON r.conversation_id = d.conversation_id
        AND r.runtime_task_key = d.runtime_task_key AND r.state = 'open'
      WHERE d.conversation_id = ?
      """, [.text(chatID.rawValue)]
    ) { row in (try Self.heldToolStep(row), try row.requiredText(6)) }
    for (entry, state) in dispatches {
      if state != "unknown",
        currentUnsafeDispatches[conversation]?.contains(entry.runtimeTaskKey) == true
      {
        continue
      }
      held[entry.runtimeTaskKey] = entry
    }
    return held.values.sorted { $0.runtimeTaskKey < $1.runtimeTaskKey }
  }

  private static func heldToolStep(_ row: SQLiteRow) throws -> HeldToolStep {
    try HeldToolStep(
      runtimeTaskKey: row.requiredText(0), taskId: TaskID(row.requiredText(1)),
      step: InterruptedStep(
        toolCallId: row.requiredText(2), tool: row.requiredText(3), check: .inconclusive,
        cardId: row.text(5).map { try CardID($0) }, since: row.integer(4)))
  }

  func readQueuedChatMessages(_ chatID: ConversationID, database: SQLiteConnection) throws
    -> [QueuedChatMessage]
  {
    try database.query(
      """
      SELECT r.record, q.record FROM chat_queued_inputs q
      JOIN chat_turns r ON r.request_id = q.request_id
      WHERE q.conversation_id = ? ORDER BY q.rowid
      """, [.text(chatID.rawValue)]
    ) { row in
      let turn = try decoder.decode(StoredChatTurn.self, from: row.requiredData(0))
      let params = try decoder.decode(ChatsSendParams.self, from: row.requiredData(1))
      return QueuedChatMessage(
        requestId: turn.requestId, messageId: turn.messageId, taskId: turn.taskId,
        model: turn.model, content: params.content, createdAt: turn.createdAt)
    }
  }

  func retainQueuedChatInput(_ turn: StoredChatTurn, params: ChatsSendParams) throws {
    guard !params.content.isEmpty,
      params.content.allSatisfy({ if case .text = $0 { true } else { false } })
    else {
      throw StoreError.invalidCommit("Only text inputs can wait in this development queue")
    }
    let bytes = try encoder.encode(params)
    let usage = try writer.query(
      "SELECT COUNT(*), COALESCE(SUM(length(CAST(record AS BLOB))), 0) FROM chat_queued_inputs WHERE conversation_id = ?",
      [.text(turn.chatId.rawValue)], row: { ($0.integer(0), $0.integer(1)) }
    ).first
    guard let usage, usage.0 < 32, bytes.count <= 262_144,
      usage.1 <= 262_144 - Int64(bytes.count)
    else { throw StoreError.chatQueueFull }
    try writer.execute(
      "INSERT INTO chat_queued_inputs (request_id, conversation_id, record) VALUES (?, ?, ?)",
      [.text(turn.requestId.rawValue), .text(turn.chatId.rawValue), .json(bytes)])
  }
}
