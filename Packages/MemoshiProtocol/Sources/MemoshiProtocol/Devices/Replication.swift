/// `replica.subscribe`, a replica → the runner or the log: send the conversation's changes
/// after `afterRseq`, in order (protocol.md §12.7).
public struct ReplicaSubscribe: DeviceMessagePayload {
  /// `replica.subscribe`.
  public static let messageType = "replica.subscribe"

  /// The conversation.
  public var conversationId: ConversationID
  /// The last replication sequence the replica applied.
  public var afterRseq: Int64

  /// Creates the payload.
  public init(conversationId: ConversationID, afterRseq: Int64) {
    self.conversationId = conversationId
    self.afterRseq = afterRseq
  }

  /// `.replicaSubscribe(self)`.
  public var asBody: DeviceMessageBody { .replicaSubscribe(self) }
}

/// `replica.change`, runner → replicas, live and through the log: one committed change to the
/// conversation's records and Pi store. A replica applies it in one transaction, in `rseq`
/// order, writes its events into its own log with a local `seq`, and rejects a change from an
/// epoch older than one it has applied.
public struct ReplicaChange: DeviceMessagePayload {
  /// `replica.change`.
  public static let messageType = "replica.change"

  /// The conversation.
  public var conversationId: ConversationID
  /// The lease epoch that wrote the change.
  public var epoch: Int64
  /// The replication sequence: gapless per conversation, rising across epochs.
  public var rseq: Int64
  /// The conversation's records the change wrote.
  public var records: [ReplicatedRecord]
  /// The events the change wrote, with the runner's `deviceId` and `cseq`. The replica assigns
  /// its own `seq`.
  public var events: [EventEnvelope]
  /// Pi_Swift's change-feed entries for the conversation's store.
  public var piChanges: [Base64Bytes]

  /// Creates the payload.
  public init(
    conversationId: ConversationID, epoch: Int64, rseq: Int64, records: [ReplicatedRecord],
    events: [EventEnvelope], piChanges: [Base64Bytes]
  ) {
    self.conversationId = conversationId
    self.epoch = epoch
    self.rseq = rseq
    self.records = records
    self.events = events
    self.piChanges = piChanges
  }

  /// `.replicaChange(self)`.
  public var asBody: DeviceMessageBody { .replicaChange(self) }
}

/// `replica.snapshot`, runner → a replica whose cursor the log no longer reaches: the
/// conversation's whole state at `rseq`; the changes after it follow.
public struct ReplicaSnapshot: DeviceMessagePayload {
  /// `replica.snapshot`.
  public static let messageType = "replica.snapshot"

  /// The conversation.
  public var conversationId: ConversationID
  /// The lease epoch of the snapshot.
  public var epoch: Int64
  /// The replication sequence the snapshot includes.
  public var rseq: Int64
  /// Every record of the conversation.
  public var records: [ReplicatedRecord]
  /// Pi_Swift's snapshot of the conversation's store.
  public var piSnapshot: Base64Bytes

  /// Creates the payload.
  public init(
    conversationId: ConversationID, epoch: Int64, rseq: Int64, records: [ReplicatedRecord],
    piSnapshot: Base64Bytes
  ) {
    self.conversationId = conversationId
    self.epoch = epoch
    self.rseq = rseq
    self.records = records
    self.piSnapshot = piSnapshot
  }

  /// `.replicaSnapshot(self)`.
  public var asBody: DeviceMessageBody { .replicaSnapshot(self) }
}

/// `replica.ack`, a replica → runner: every change up to `rseq` is applied.
public struct ReplicaAck: DeviceMessagePayload {
  /// `replica.ack`.
  public static let messageType = "replica.ack"

  /// The conversation.
  public var conversationId: ConversationID
  /// The last replication sequence applied.
  public var rseq: Int64

  /// Creates the payload.
  public init(conversationId: ConversationID, rseq: Int64) {
    self.conversationId = conversationId
    self.rseq = rseq
  }

  /// `.replicaAck(self)`.
  public var asBody: DeviceMessageBody { .replicaAck(self) }
}

/// One record a replicated change writes or deletes.
public struct ReplicatedRecord: Codable, Hashable, Sendable {
  /// The object's kind, an object name from object-model.md such as `task` or `card`.
  public var kind: String
  /// The object's ID.
  public var id: String
  /// Whether the record is written or deleted.
  public var op: RecordOperation
  /// The record as written; absent for a delete.
  public var value: JSONValue?

  /// Creates a replicated record.
  public init(kind: String, id: String, op: RecordOperation, value: JSONValue? = nil) {
    self.kind = kind
    self.id = id
    self.op = op
    self.value = value
  }
}

/// What a replicated change does to a record.
public enum RecordOperation: OpenEnum {
  case upsert
  case delete
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.upsert: "upsert", .delete: "delete"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
