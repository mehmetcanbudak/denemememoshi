import MemoshiProtocol

extension Store {
  /// Reads the parent, direct children and position from the same SQLite snapshot.
  public func taskDetails(_ id: TaskID) throws -> TasksGetResult? {
    try requireOpen()
    return try reader.transaction(write: false) {
      guard let task: MemoshiTask = try readRecord(table: "tasks", id: id.rawValue) else {
        return nil
      }
      let children = try reader.query(
        "SELECT record FROM tasks WHERE parent_task_id = ? ORDER BY id", [.text(id.rawValue)]
      ) { try decoder.decode(MemoshiTask.self, from: $0.requiredData(0)) }
      return TasksGetResult(
        task: task, children: children, asOf: try position(conversationID: task.conversationId))
    }
  }

  /// Keyset pagination over a filtered approval snapshot. Cursors are opaque approval IDs.
  public func approvalsPage(
    status: ApprovalStatus? = nil, botID: BotID? = nil, after: ApprovalID? = nil,
    limit: PageLimit
  ) throws -> ApprovalsListResult {
    try requireOpen()
    guard status?.isKnown != false, limit.isWithinLimits else {
      throw StoreError.invalidCommit("Invalid approval-page filter")
    }
    return try reader.transaction(write: false) {
      var clauses: [String] = []
      var values: [SQLiteConnection.Value] = []
      if let status {
        clauses.append("status = ?")
        values.append(.text(status.rawValue))
      }
      if let botID {
        clauses.append("bot_id = ?")
        values.append(.text(botID.rawValue))
      }
      if let after {
        clauses.append("id > ?")
        values.append(.text(after.rawValue))
      }
      let predicate = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
      values.append(.integer(Int64(limit.rawValue + 1)))
      var approvals = try reader.query(
        "SELECT record FROM approvals\(predicate) ORDER BY id LIMIT ?", values
      ) { try decoder.decode(Approval.self, from: $0.requiredData(0)) }
      let hasMore = approvals.count > limit.rawValue
      if hasMore { approvals.removeLast() }
      return ApprovalsListResult(
        items: approvals, nextCursor: hasMore ? approvals.last?.id.rawValue : nil,
        asOf: try position(conversationID: nil))
    }
  }
}
