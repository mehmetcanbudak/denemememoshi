import MemoshiProtocol

extension Store {
  /// Reads current authority for the active turn, or an explicit stored task during reconciliation.
  public func policyCallSnapshot(
    chatID: ConversationID, taskID: TaskID? = nil, fence: ConversationFence, at now: Int64
  ) throws
    -> PolicyCallSnapshot
  {
    try requireOpen()
    guard fence.conversationID == chatID else {
      throw ApprovalError.bindingConflict
    }
    try checkFence(fence, at: now)
    return try reader.transaction(write: false) {
      let filter =
        taskID == nil
        ? "r.status IN ('queued', 'running', 'waiting') AND json_extract(r.record, '$.queueReason') IS NULL AND t.id = json_extract(r.record, '$.taskId')"
        : "t.id = ?"
      var values: [SQLiteConnection.Value] = [.text(chatID.rawValue)]
      if let taskID { values.append(.text(taskID.rawValue)) }
      let snapshots = try reader.query(
        """
        SELECT r.record, t.record, b.permission_mode, b.active, p.kill_switch,
          COALESCE(e.untrusted, 0), COALESCE(e.private_data, 0)
        FROM chat_turns r JOIN chats c ON c.id = r.conversation_id
        JOIN tasks t ON (t.id = json_extract(r.record, '$.taskId') OR t.id IN (
          SELECT task_id FROM runtime_subagents
          WHERE original_task_id = json_extract(r.record, '$.taskId') AND conversation_id = c.id))
          AND t.bot_id = c.bot_id AND t.conversation_id = c.id
        JOIN bot_policy b ON b.bot_id = c.bot_id CROSS JOIN policy_control p
        LEFT JOIN conversation_exposure e ON e.conversation_id = c.id
        WHERE r.conversation_id = ? AND \(filter) AND p.singleton = 1
        """, values
      ) { row in
        let turn = try decoder.decode(StoredChatTurn.self, from: row.requiredData(0))
        let task = try decoder.decode(MemoshiTask.self, from: row.requiredData(1))
        let mode = PermissionMode(rawValue: try row.requiredText(2))
        guard mode.isKnown,
          taskID != nil || [.queued, .running, .waiting].contains(task.status)
        else {
          throw ApprovalError.bindingConflict
        }
        return PolicyCallSnapshot(
          turn: turn, task: task,
          policy: BotPolicyState(
            permissionMode: mode, active: row.integer(3) == 1, killSwitch: row.integer(4) == 1),
          exposure: Exposure(untrusted: row.integer(5) == 1, privateData: row.integer(6) == 1))
      }
      guard snapshots.count == 1, let snapshot = snapshots.first else {
        throw ApprovalError.notFound
      }
      return snapshot
    }
  }
}
