import Foundation
import MemoshiProtocol

extension Store {
  /// Reads the current head and oldest retained sequence in one snapshot.
  public func replayBounds() throws -> ReplayBounds {
    try requireOpen()
    return try reader.transaction(write: false) { try readBounds(reader) }
  }

  /// The caller captures `through` once before replay, then hands off to its ordered live queue.
  /// Each page rechecks retention: a slow reader gets an explicit resync requirement, not a gap.
  public func replay(
    after: Int64, through: Int64? = nil, limit: Int = 256
  ) throws -> ReplayPage {
    try requireOpen()
    guard (1...256).contains(limit), after >= 0 else { throw StoreError.invalidReplayCursor }
    return try reader.transaction(write: false) {
      let bounds = try readBounds(reader)
      guard after >= bounds.minRetainedSeq - 1 else {
        throw StoreError.cursorExpired(minRetainedSeq: bounds.minRetainedSeq)
      }
      let through = through ?? bounds.head
      guard after <= through, through <= bounds.head else { throw StoreError.invalidReplayCursor }
      let events = try reader.query(
        """
        SELECT seq, cseq, ts, type, type_version, device_id, actor_kind, actor_id,
          subject_kind, subject_id, bot_id, conversation_id, project_id, task_id, origin, payload
        FROM events WHERE seq > ? AND seq <= ? ORDER BY seq LIMIT ?
        """, [.integer(after), .integer(through), .integer(Int64(limit))], row: readEvent)
      var expected = after
      for event in events {
        guard expected < Int64.max, event.seq == expected + 1 else {
          throw StoreError.integrityFailed("Replay contains a sequence gap")
        }
        expected += 1
      }
      guard events.isEmpty == false || after == through else {
        throw StoreError.integrityFailed("Replay is missing retained events")
      }
      return ReplayPage(
        events: events, bounds: bounds, through: through, nextAfter: expected,
        hasMore: expected < through)
    }
  }

  /// The `ts` (Unix milliseconds) of the event the log retains at `seq`; nil when it holds
  /// none there: never written, beyond the head, or pruned by retention. Together with
  /// `logID` this lets a caller tell whether a cursor was taken from this history.
  public func eventTimestamp(seq: Int64) throws -> Int64? {
    try requireOpen()
    return try reader.integer("SELECT ts FROM events WHERE seq = ?", [.integer(seq)])
  }

  /// Reads the configured retention window in days.
  public func eventRetentionDays() throws -> Int {
    try requireOpen()
    return try readRetentionDays(reader)
  }

  /// The only settings seam in this slice. Domain records cannot be hidden in key/value blobs.
  public func setEventRetentionDays(_ days: Int, at now: Int64) throws -> [EventEnvelope] {
    try requireOpen()
    guard (7...365).contains(days) else { throw StoreError.invalidRetentionDays }
    let committed: [EventEnvelope] = try writer.transaction(write: true) {
      let current = try readRetentionDays(writer)
      guard current != days else { return [] }
      try writer.execute(
        "UPDATE settings SET value = ? WHERE key = 'event_retention_days'", [.integer(Int64(days))])
      let event = try append(
        EventDraft(
          ts: now, actor: Actor(kind: .system), subject: ObjectRef(kind: "system", id: "memoshi"),
          event: .systemSettingsChanged(
            SystemSettingsChangedPayload(
              keys: ["eventRetentionDays"], values: ["eventRetentionDays": .integer(Int64(days))])))
      )
      return [event]
    }
    eventBus.publish(committed)
    return committed
  }

  /// One idle-maintenance batch: 30 days by default (7–365), at least 200,000 latest events,
  /// and no more than 5,000 removals. Prunes a prefix even if timestamps arrived out of order.
  /// Conversation cursors and sqlite_sequence are never deleted or reset.
  public func pruneEvents(now: Int64) throws -> PruneResult {
    try requireOpen()
    guard now >= 0 else { throw StoreError.invalidCommit("Negative retention clock") }
    let result = try writer.transaction(write: true) {
      let days = try readRetentionDays(writer)
      let cutoff = now - Int64(days) * 86_400_000
      guard
        let protected = try writer.integer(
          "SELECT seq FROM events ORDER BY seq DESC LIMIT 1 OFFSET 199999")
      else { return PruneResult(deleted: 0, bounds: try readBounds(writer), events: []) }
      let firstYoung = try writer.integer(
        "SELECT MIN(seq) FROM events WHERE ts >= ?", [.integer(cutoff)])
      let before = min(protected, firstYoung ?? protected)
      try writer.execute(
        """
        DELETE FROM events WHERE seq IN (
          SELECT seq FROM events WHERE seq < ? ORDER BY seq LIMIT 5000
        )
        """, [.integer(before)])
      let deleted = try writer.changedRows
      guard deleted > 0 else {
        return PruneResult(deleted: 0, bounds: try readBounds(writer), events: [])
      }
      guard let minimum = try writer.integer("SELECT MIN(seq) FROM events") else {
        throw StoreError.integrityFailed("Retention removed the protected tail")
      }
      try writer.execute(
        "UPDATE meta SET value = ? WHERE key = 'min_retained_seq'", [.text(String(minimum))])
      let event = try append(
        EventDraft(
          ts: now, actor: Actor(kind: .system), subject: ObjectRef(kind: "system", id: "memoshi"),
          event: .systemPruned(SystemPrunedPayload(beforeSeq: minimum, deleted: deleted))))
      return PruneResult(deleted: deleted, bounds: try readBounds(writer), events: [event])
    }
    eventBus.publish(result.events)
    return result
  }

  func readRetentionDays(_ database: SQLiteConnection) throws -> Int {
    guard
      let days = try database.integer(
        "SELECT value FROM settings WHERE key = 'event_retention_days'"),
      (7...365).contains(days)
    else { throw StoreError.invalidSchema("Missing or invalid event retention setting") }
    return Int(days)
  }

  func readBounds(_ database: SQLiteConnection) throws -> ReplayBounds {
    let head = try database.integer("SELECT seq FROM sqlite_sequence WHERE name = 'events'") ?? 0
    guard let raw = try database.text("SELECT value FROM meta WHERE key = 'min_retained_seq'"),
      let minimum = Int64(raw), minimum > 0,
      minimum - 1 <= head
    else { throw StoreError.invalidSchema("Invalid retained-sequence metadata") }
    return ReplayBounds(head: head, minRetainedSeq: minimum)
  }

  func readEvent(_ row: SQLiteRow) throws -> EventEnvelope {
    let type = try row.requiredText(3)
    guard let payloadType = EventRegistry.payloadType(for: type),
      payloadType.typeVersion == Int(row.integer(4)), payloadType.eventClass != .uiOnly
    else { throw StoreError.integrityFailed("Unknown or UI-only event in the durable log") }
    let actorKind = ActorKind(rawValue: try row.requiredText(6))
    guard actorKind.isKnown else { throw StoreError.integrityFailed("Unknown persisted actor") }
    let payload = try decodePayload(payloadType, data: row.requiredData(15))
    let origin = try row.data(14).map { try decoder.decode(Origin.self, from: $0) }
    return try EventEnvelope(
      seq: row.integer(0), cseq: row.optionalInteger(1), ts: row.integer(2),
      deviceId: DeviceID(row.requiredText(5)),
      actor: Actor(kind: actorKind, id: row.text(7)),
      subject: ObjectRef(kind: row.requiredText(8), id: row.requiredText(9)),
      scope: EventScope(
        botId: row.text(10).map(BotID.init),
        conversationId: row.text(11).map(ConversationID.init),
        projectId: row.text(12).map(ProjectID.init), taskId: row.text(13).map(TaskID.init)),
      origin: origin, event: payload)
  }
}
