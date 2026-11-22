import Foundation
import MemoshiProtocol

/// Used inside the caller's write transaction, including the numbered migration transaction.
/// Never publishes and never commits on its own.
enum EventPersistence {
  static func append(
    _ draft: EventDraft, deviceID: DeviceID, database: SQLiteConnection,
    encoder: JSONEncoder, decoder: JSONDecoder
  ) throws -> EventEnvelope {
    guard let payloadType = EventRegistry.payloadType(for: draft.event.type),
      draft.event.payload != nil, payloadType.typeVersion == draft.event.typeVersion,
      payloadType.eventClass != .uiOnly
    else { throw StoreError.invalidCommit("Only known durable or audited events may be persisted") }
    if let grantID = grantSubject(of: draft.event) {
      // Grant lifecycle facts are bot-wide and unfenced: they name exactly their bot and grant.
      guard draft.scope.botId != nil, draft.scope.conversationId == nil,
        draft.scope.projectId == nil, draft.scope.taskId == nil, draft.origin == nil,
        draft.subject == ObjectRef(kind: "grant", id: grantID.rawValue)
      else { throw StoreError.invalidCommit("A grant fact must name only its bot and grant") }
    } else if draft.event.type.hasPrefix("bot.") {
      guard let botID = draft.scope.botId, draft.scope.conversationId == nil,
        draft.scope.projectId == nil, draft.scope.taskId == nil, draft.origin == nil,
        draft.subject == ObjectRef(kind: "bot", id: botID.rawValue)
      else { throw StoreError.invalidCommit("A bot fact must name only its bot") }
    } else if case .trashEmptied(let payload) = draft.event {
      // The aggregate receipt is global; each purged Session already emitted its own fact.
      guard draft.scope == EventScope(), draft.origin == nil,
        draft.subject == ObjectRef(kind: "system", id: "trash"),
        draft.actor.kind == .user || draft.actor.kind == .system,
        payload.by.rawValue == draft.actor.kind.rawValue
      else {
        throw StoreError.invalidCommit("A Trash receipt must name only its actor and global Trash")
      }
    } else {
      guard draft.event.type.hasPrefix("system.") || draft.scope.conversationId != nil else {
        throw StoreError.invalidCommit("A conversation fact must name its fenced conversation")
      }
    }
    let stripped = draft.event.strippingLiveOnlyFields()
    guard let payload = stripped.payload else {
      throw StoreError.invalidCommit("Unknown event payload")
    }
    let payloadBytes = try encoder.encode(payload)
    guard payloadBytes.count <= 64 * 1_024 else {
      throw StoreError.invalidCommit("Event payload exceeds 64 KiB")
    }
    // Strict decoding rejects programmatically constructed unknown payload enum values.
    _ = try decodePayload(payloadType, data: payloadBytes, decoder: decoder)
    guard draft.actor.kind.isKnown, draft.origin?.kind.isKnown != false,
      draft.origin?.rootKind.isKnown != false
    else { throw StoreError.invalidCommit("Unknown actor or origin") }
    let origin = try draft.origin.map { try encoder.encode($0) }

    let previous =
      try database.integer("SELECT seq FROM sqlite_sequence WHERE name = 'events'") ?? 0
    guard previous < Int64.max else { throw StoreError.sequenceExhausted }
    var cseq: Int64?
    if let conversation = draft.scope.conversationId {
      let current =
        try database.integer(
          "SELECT cseq FROM conversation_cursors WHERE conversation_id = ?",
          [.text(conversation.rawValue)]) ?? 0
      guard current < Int64.max else { throw StoreError.sequenceExhausted }
      cseq = current + 1
      try database.execute(
        """
        INSERT INTO conversation_cursors (conversation_id, cseq) VALUES (?, ?)
        ON CONFLICT (conversation_id) DO UPDATE SET cseq = excluded.cseq
        """, [.text(conversation.rawValue), .integer(current + 1)])
    }
    try database.execute(
      """
      INSERT INTO events (cseq, ts, type, type_version, device_id, actor_kind, actor_id,
        subject_kind, subject_id, bot_id, conversation_id, project_id, task_id, origin, payload)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        cseq.map(SQLiteConnection.Value.integer) ?? .null, .integer(draft.ts),
        .text(stripped.type), .integer(Int64(stripped.typeVersion)), .text(deviceID.rawValue),
        .text(draft.actor.kind.rawValue), SQLiteConnection.Value(draft.actor.id),
        .text(draft.subject.kind), .text(draft.subject.id),
        SQLiteConnection.Value(draft.scope.botId?.rawValue),
        SQLiteConnection.Value(draft.scope.conversationId?.rawValue),
        SQLiteConnection.Value(draft.scope.projectId?.rawValue),
        SQLiteConnection.Value(draft.scope.taskId?.rawValue),
        origin.map(SQLiteConnection.Value.json) ?? .null, .json(payloadBytes),
      ])
    let seq = try database.lastInsertID
    guard seq == previous + 1 else {
      throw StoreError.invalidSchema("The event log would contain a sequence gap")
    }
    let envelope = EventEnvelope(
      seq: seq, cseq: cseq, ts: draft.ts, deviceId: deviceID, actor: draft.actor,
      subject: draft.subject, scope: draft.scope, origin: draft.origin, event: stripped)
    if payloadType.eventClass == .audited {
      try database.execute(
        "INSERT INTO audit_events (seq, type, created_at, envelope) VALUES (?, ?, ?, ?)",
        [
          .integer(seq), .text(stripped.type), .integer(draft.ts),
          .json(try encoder.encode(envelope)),
        ])
    }
    return envelope
  }

  static func decodePayload<Payload: EventPayload>(
    _ type: Payload.Type, data: Data, decoder: JSONDecoder
  ) throws -> Event {
    try decoder.decode(type, from: data).asEvent
  }

  /// The grant a bot-scoped grant lifecycle fact is about; `nil` for every other event.
  private static func grantSubject(of event: Event) -> GrantID? {
    switch event {
    case .grantGranted(let payload): payload.grantId
    case .grantRevoked(let payload): payload.grantId
    case .grantExpired(let payload): payload.grantId
    default: nil
    }
  }
}
