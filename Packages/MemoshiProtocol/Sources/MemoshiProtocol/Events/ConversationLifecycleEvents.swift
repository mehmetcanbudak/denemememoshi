/// A Session entered 30-day Trash. No title, prompt or transcript is copied into the log.
public struct SessionDeletedPayload: EventPayload {
  /// The wire discriminator for a Session entering Trash.
  public static let eventType = "session.deleted"
  /// Version of the encoded retention-deadline payload.
  public static let typeVersion = 1
  /// Persisted and mirrored to the audit log.
  public static let eventClass = EventClass.audited
  /// The restoration deadline in milliseconds since the Unix epoch, not a retention duration.
  public var purgeAfter: Int64
  /// Carries the committed deletion's deadline without copying Session content.
  public init(purgeAfter: Int64) { self.purgeAfter = purgeAfter }
  /// Wraps the payload; Session identity and occurrence time belong to the event envelope.
  public var asEvent: Event { .sessionDeleted(self) }
}

/// The retained Session is active again with the same identity and transcript.
public struct SessionRestoredPayload: EventPayload {
  private enum CodingKeys: CodingKey {}

  /// The wire discriminator for a retained Session becoming active again.
  public static let eventType = "session.restored"
  /// Version of this fieldless payload's wire contract.
  public static let typeVersion = 1
  /// Persisted and replayable without a class-A audit mirror requirement.
  public static let eventClass = EventClass.durable
  /// Creates a content-free fact; the envelope identifies the restored Session.
  public init() {}
  /// Requires an object, like every event payload, even though this fact has no fields.
  public init(from decoder: any Decoder) throws {
    _ = try decoder.container(keyedBy: CodingKeys.self)
  }
  /// Encodes the content-free payload as `{}`.
  public func encode(to encoder: any Encoder) throws {
    _ = encoder.container(keyedBy: CodingKeys.self)
  }
  /// Wraps the payload without loading or embedding the retained transcript.
  public var asEvent: Event { .sessionRestored(self) }
}

/// The local Session's Pi filenames were unlinked and live projections cleared. Audit facts,
/// request receipts and its tombstone survive; this is not a secure-erase attestation.
public struct SessionPurgedPayload: EventPayload {
  /// The wire discriminator for completed local Session purging.
  public static let eventType = "session.purged"
  /// Version of the encoded purge-attribution payload.
  public static let typeVersion = 1
  /// Persisted and mirrored to the audit log.
  public static let eventClass = EventClass.audited
  /// Who purged it: the user's Empty Trash, or retention-expiry maintenance.
  public var by: PurgedBy
  /// Records the purge's authority attribution, not a user name or credential.
  public init(by: PurgedBy) { self.by = by }
  /// Wraps the payload; the envelope supplies the purged Session identity.
  public var asEvent: Event { .sessionPurged(self) }
}

/// Who purged a Session or emptied Trash: `user` (Empty Trash) or `system` (retention expiry)
/// (events.md §5.3).
public enum PurgedBy: OpenEnum {
  case user
  case system
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.user: "user", .system: "system"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// One frozen selection finished purging. It never names a user folder or contains content.
public struct TrashEmptiedPayload: EventPayload {
  /// The wire discriminator for completion of one frozen Trash selection.
  public static let eventType = "trash.emptied"
  /// Version of the encoded selection-summary payload.
  public static let typeVersion = 1
  /// Persisted and mirrored to the audit log.
  public static let eventClass = EventClass.audited
  /// The number of Sessions in the completed selection, including zero for an empty selection.
  public var count: Int
  /// Distinct object kinds represented; the local Store emits `["session"]` or an empty array.
  public var kinds: [String]
  /// Who emptied it: the user's explicit selection, or retention-expiry maintenance.
  public var by: PurgedBy
  /// Summarizes the completed selection without its item identifiers or user content.
  public init(count: Int, kinds: [String], by: PurgedBy) {
    self.count = count
    self.kinds = kinds
    self.by = by
  }
  /// Wraps the summary; the Store uses the system Trash subject in its event envelope.
  public var asEvent: Event { .trashEmptied(self) }
}
