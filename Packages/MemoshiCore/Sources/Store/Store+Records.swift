import Foundation
import MemoshiProtocol

extension Store {
  /// Reads one current task and its snapshot position.
  public func task(_ id: TaskID) throws -> StoreSnapshot<MemoshiTask?> {
    try requireOpen()
    return try reader.transaction(write: false) {
      let value: MemoshiTask? = try readRecord(table: "tasks", id: id.rawValue)
      return StoreSnapshot(value: value, asOf: try position(conversationID: value?.conversationId))
    }
  }

  /// Reads one current card and its snapshot position.
  public func card(_ id: CardID) throws -> StoreSnapshot<Card?> {
    try requireOpen()
    return try reader.transaction(write: false) {
      let value: Card? = try readRecord(table: "cards", id: id.rawValue)
      return StoreSnapshot(value: value, asOf: try position(conversationID: value?.conversationId))
    }
  }

  /// Reads matching current approvals and their common snapshot position.
  public func approvals(
    status: ApprovalStatus? = nil, conversationID: ConversationID? = nil
  ) throws -> StoreSnapshot<[Approval]> {
    try requireOpen()
    guard status?.isKnown != false else {
      throw StoreError.invalidCommit("Unknown approval status")
    }
    return try reader.transaction(write: false) {
      var clauses: [String] = []
      var values: [SQLiteConnection.Value] = []
      if let status {
        clauses.append("status = ?")
        values.append(.text(status.rawValue))
      }
      if let conversationID {
        clauses.append("conversation_id = ?")
        values.append(.text(conversationID.rawValue))
      }
      let predicate = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
      let approvals = try reader.query(
        "SELECT record FROM approvals\(predicate) ORDER BY id", values
      ) {
        try decoder.decode(Approval.self, from: $0.requiredData(0))
      }
      return StoreSnapshot(value: approvals, asOf: try position(conversationID: conversationID))
    }
  }

  func readRecord<Value: Decodable>(table: String, id: String) throws -> Value? {
    try reader.query("SELECT record FROM \(table) WHERE id = ?", [.text(id)]) {
      try decoder.decode(Value.self, from: $0.requiredData(0))
    }.first
  }

  func position(conversationID: ConversationID?) throws -> AsOf {
    let head = try reader.integer("SELECT seq FROM sqlite_sequence WHERE name = 'events'") ?? 0
    let cseq = try conversationID.map {
      try reader.integer(
        "SELECT cseq FROM conversation_cursors WHERE conversation_id = ?", [.text($0.rawValue)])
        ?? 0
    }
    return AsOf(seq: head, cseq: cseq)
  }

  func writeRecord(_ change: RecordChange) throws {
    let table: String
    let id: String
    let conversationID: ConversationID
    let botID: BotID
    let taskID: TaskID?
    let status: String
    let body: Data
    var parentTaskID: TaskID?
    switch change {
    case .task(let value):
      table = "tasks"
      id = value.id.rawValue
      conversationID = value.conversationId
      botID = value.botId
      taskID = nil
      status = value.status.rawValue
      body = try validatedRecord(value)
      parentTaskID = value.parentTaskId
    case .card(let value):
      if let bytes = try writer.query(
        "SELECT record FROM cards WHERE id = ?", [.text(value.id.rawValue)],
        row: { try $0.requiredData(0) }
      ).first {
        let previous = try decoder.decode(Card.self, from: bytes)
        if previous.kind == .approval && previous.status != .pending {
          var decision = value
          decision.seenAt = previous.seenAt
          guard decision == previous else {
            throw StoreError.invalidCommit(
              "A terminal approval card cannot change or return to pending")
          }
        }
      }
      table = "cards"
      id = value.id.rawValue
      conversationID = value.conversationId
      botID = value.botId
      taskID = value.taskId
      status = value.status.rawValue
      body = try validatedRecord(value)
    case .approval(let value):
      if let bytes = try writer.query(
        "SELECT record FROM approvals WHERE id = ?", [.text(value.id.rawValue)],
        row: { try $0.requiredData(0) }
      ).first {
        let previous = try decoder.decode(Approval.self, from: bytes)
        guard previous.status == .pending || previous == value else {
          throw StoreError.invalidCommit("A terminal approval cannot change or return to pending")
        }
      }
      table = "approvals"
      id = value.id.rawValue
      conversationID = value.conversationId
      botID = value.botId
      taskID = value.taskId
      status = value.status.rawValue
      body = try validatedRecord(value)
    }
    let existing = try writer.query(
      "SELECT conversation_id, bot_id FROM \(table) WHERE id = ?", [.text(id)]
    ) { (try $0.requiredText(0), try $0.requiredText(1)) }.first
    if let existing {
      guard existing.0 == conversationID.rawValue, existing.1 == botID.rawValue else {
        throw StoreError.invalidCommit("A record cannot change its owning conversation or bot")
      }
    }
    if table == "tasks" {
      try writer.execute(
        """
        INSERT INTO tasks (id, conversation_id, bot_id, parent_task_id, status, record)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET parent_task_id = excluded.parent_task_id,
          status = excluded.status, record = excluded.record
        """,
        [
          .text(id), .text(conversationID.rawValue), .text(botID.rawValue),
          SQLiteConnection.Value(parentTaskID?.rawValue), .text(status), .json(body),
        ])
    } else {
      try writer.execute(
        """
        INSERT INTO \(table) (id, conversation_id, bot_id, task_id, status, record)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET task_id = excluded.task_id,
          status = excluded.status, record = excluded.record
        """,
        [
          .text(id), .text(conversationID.rawValue), .text(botID.rawValue),
          SQLiteConnection.Value(taskID?.rawValue), .text(status), .json(body),
        ])
    }
  }
}
