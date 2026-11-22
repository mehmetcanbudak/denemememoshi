/// The committed position of a lifecycle mutation; replay is a historical receipt.
public struct LifecycleReceipt: Codable, Hashable, Sendable {
  /// The device-global `seq` of the final committed lifecycle fact, not a conversation `cseq`.
  public var writtenSeq: Int64
  /// True for the stored result of the same original request; nil leaves replay status unspecified.
  public var replayed: Bool?

  /// Carries a commit position; constructing this value does not commit or replay a mutation.
  public init(writtenSeq: Int64, replayed: Bool? = nil) {
    self.writtenSeq = writtenSeq
    self.replayed = replayed
  }
}

/// Moves an idle Session to 30-day local Trash; never deletes a bot's home Chat.
public enum SessionsDelete: RPCMethod {
  /// The stable original request and idle Session selected for retirement.
  public typealias Params = SessionsDeleteParams
  /// The deletion's committed log position, or its historical receipt on replay.
  public typealias Result = LifecycleReceipt
  /// The wire routing key also used to bind stored request receipts.
  public static let name = "sessions.delete"
  /// Requires mutation routing and stable request-ID handling.
  public static let isMutating = true
}

/// The Session and the original mutation identity.
public struct SessionsDeleteParams: Codable, Hashable, Sendable, IdempotentParams {
  /// Keep this identity and the same parameters when retrying; conflicting reuse is refused.
  public var requestId: ULID
  /// The Session to retain in local Trash; a bot's home Chat is not a valid deletion target.
  public var sessionId: SessionID

  /// Selects a Session under an original request identity; performs no deletion or admission.
  public init(requestId: ULID, sessionId: SessionID) {
    self.requestId = requestId
    self.sessionId = sessionId
  }
}

/// A Session retained in local Trash; its transcript remains in its original Pi store.
public struct TrashedSession: Codable, Hashable, Sendable {
  /// The Trash discriminator, initialized to `session` by this type's initializer.
  public var kind: String
  /// The retained Session's identity, unchanged by delete/restore.
  public var id: SessionID
  /// Retained display metadata; lifecycle audit payloads do not copy this title.
  public var title: String
  /// The bot that owns this retained Session.
  public var botId: BotID
  /// The deletion time in milliseconds since the Unix epoch.
  public var deletedAt: Int64
  /// The Unix-millisecond deadline at which restoration stops being allowed.
  public var purgeAfter: Int64
  /// Device identity reported by the local Store, not replicated deletion provenance.
  public var deletedOnDeviceId: DeviceID

  /// Captures retained metadata and Unix-millisecond timestamps with the `session` kind.
  /// It does not read, move or validate the retained Pi store.
  public init(
    id: SessionID, title: String, botId: BotID, deletedAt: Int64, purgeAfter: Int64,
    deletedOnDeviceId: DeviceID
  ) {
    self.kind = "session"
    self.id = id
    self.title = title
    self.botId = botId
    self.deletedAt = deletedAt
    self.purgeAfter = purgeAfter
    self.deletedOnDeviceId = deletedOnDeviceId
  }
}

/// Lists the local Session Trash subset; bot/group Trash and replication are later scope.
public enum TrashList: RPCMethod {
  /// No filters or mutation identity are required for this local snapshot.
  public typealias Params = EmptyParams
  /// Retained Session metadata and the snapshot's local log position.
  public typealias Result = TrashListResult
  /// The wire routing key for the local Trash snapshot.
  public static let name = "trash.list"
  /// This method reads Trash without reserving or purging entries.
  public static let isMutating = false
}

/// A local Session Trash snapshot, not a transcript or a cross-device Trash inventory.
public struct TrashListResult: Codable, Hashable, Sendable {
  /// Retained Sessions excluding pending/completed purges; expired entries may await maintenance.
  public var items: [TrashedSession]
  /// The local device-log position described by this snapshot, not a wall-clock timestamp.
  public var asOf: AsOf

  /// Pairs retained metadata with its observed position without performing a storage read.
  public init(items: [TrashedSession], asOf: AsOf) {
    self.items = items
    self.asOf = asOf
  }
}

/// Restores a retained Session without replacing its transcript or lease epoch.
public enum TrashRestore: RPCMethod {
  /// The retained Session kind/identity and original mutation request.
  public typealias Params = TrashRestoreParams
  /// The original restored Session summary, with optional replay attribution.
  public typealias Result = TrashRestoreResult
  /// The wire routing key also used to bind stored restoration receipts.
  public static let name = "trash.restore"
  /// Restoration changes canonical local metadata and requires mutation routing.
  public static let isMutating = true
}

/// A stable restoration intent; the live local Store accepts only the `session` kind.
public struct TrashRestoreParams: Codable, Hashable, Sendable, IdempotentParams {
  /// Keep this identity and the same kind/ID on retry; conflicting reuse is refused.
  public var requestId: ULID
  /// The object-kind discriminator; values other than `session` are not implemented locally.
  public var kind: String
  /// The retained Session to restore before expiry and before a purge selection reserves it.
  public var id: SessionID

  /// Captures the original restoration intent without checking retention or opening a Pi store.
  public init(requestId: ULID, kind: String = "session", id: SessionID) {
    self.requestId = requestId
    self.kind = kind
    self.id = id
  }
}

/// The summary recorded by the restoration; a replay need not describe the Session's current state.
public struct TrashRestoreResult: Codable, Hashable, Sendable {
  /// The Session summary stored when the original restoration committed.
  public var session: Session
  /// True when returning the same original request's stored summary without restoring again.
  public var replayed: Bool?

  /// Carries the original restoration outcome; it does not refresh the Session from storage.
  public init(session: Session, replayed: Bool? = nil) {
    self.session = session
    self.replayed = replayed
  }
}

/// Explicitly purges selected retained Sessions, or the current local Session Trash.
/// A durable purge job freezes that selection before any file is removed.
/// Local Pi filenames and live projections are removed; audit/receipts remain, with no secure erase.
public enum TrashEmpty: RPCMethod {
  /// The stable request and optional explicit retained-Session selection.
  public typealias Params = TrashEmptyParams
  /// The final purge-summary log position, or its original receipt on replay.
  public typealias Result = LifecycleReceipt
  /// The wire routing key also used to reserve durable purge jobs and store receipts.
  public static let name = "trash.empty"
  /// Requires mutation routing; a read/list operation never authorizes Empty Trash.
  public static let isMutating = true
}

/// Explicit Empty Trash intent whose resolved selection is durably frozen before unlinking.
public struct TrashEmptyParams: Codable, Hashable, Sendable, IdempotentParams {
  /// Keep this identity and selection on retry; replay resumes the job or returns its receipt.
  public var requestId: ULID
  /// Absent means everything in the local Session Trash, however much that is: no 1,000 cap
  /// applies. An explicit list purges only those Sessions, and an empty list nothing. The
  /// schema sets no length limit on the list; the engine accepts at most 1,000 unique IDs,
  /// each still in Trash.
  public var ids: [SessionID]?

  /// Captures a selection intent; nil is resolved once when the durable purge job is prepared.
  public init(requestId: ULID, ids: [SessionID]? = nil) {
    self.requestId = requestId
    self.ids = ids
  }
}
