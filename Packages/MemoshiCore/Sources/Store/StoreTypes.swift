import Foundation
import MemoshiProtocol

/// Failures at the durable store seam. SQL and SQLite handles never leave the implementation.
public enum StoreError: Error, Equatable, Sendable {
  case alreadyRunning
  case alreadyOpen
  case conversationInUse(ConversationID)
  case closed
  case schemaTooNew(found: Int, supported: Int)
  case invalidSchema(String)
  case integrityFailed(String)
  case storage(code: Int32, operation: String)
  case unsafePath(String)
  case deviceIdentityMismatch
  case leaseFenced(conversationID: ConversationID, currentEpoch: Int64?)
  case invalidCommit(String)
  case invalidIDPrefix(String)
  case invalidRetentionDays
  case invalidReplayCursor
  case requestConflict
  case chatBusy
  case chatQueueFull
  case chatRecoveryRequired
  case chatNotFound
  case cursorExpired(minRetainedSeq: Int64)
  case sequenceExhausted
}

/// A local checked write capability, not a cross-device lease-authority grant.
public struct ConversationFence: Hashable, Sendable {
  /// The conversation whose writes this capability fences.
  public let conversationID: ConversationID
  /// The exact current local ownership epoch.
  public let epoch: Int64

  /// Captures a conversation and the epoch to validate at write admission.
  public init(conversationID: ConversationID, epoch: Int64) {
    self.conversationID = conversationID
    self.epoch = epoch
  }
}

/// Local ownership bookkeeping. S2's CloudKit/relay authority is deliberately not implemented here.
public struct ConversationLease: Hashable, Sendable {
  /// The conversation governed by this local lease.
  public let conversationID: ConversationID
  /// The monotonically increasing ownership epoch, retained after release.
  public let epoch: Int64
  /// The current local owner; absent after release.
  public let runnerDeviceID: DeviceID?
  /// The exclusive expiration time in Unix milliseconds.
  public let expiresAt: Int64?

  /// The write capability corresponding to this epoch.
  public var fence: ConversationFence {
    ConversationFence(conversationID: conversationID, epoch: epoch)
  }
}

/// Current-state records use the protocol's types, rather than a parallel storage domain model.
public enum RecordChange: Hashable, Sendable {
  case task(MemoshiTask)
  case card(Card)
  case approval(Approval)

  var conversationID: ConversationID {
    switch self {
    case .task(let value): value.conversationId
    case .card(let value): value.conversationId
    case .approval(let value): value.conversationId
    }
  }

  var subject: ObjectRef {
    switch self {
    case .task(let value): ObjectRef(kind: "task", id: value.id.rawValue)
    case .card(let value): ObjectRef(kind: "card", id: value.id.rawValue)
    case .approval(let value): ObjectRef(kind: "approval", id: value.id.rawValue)
    }
  }
}

/// Unnumbered facts. The store supplies device identity and both sequence numbers.
/// Callers must provide already-redacted metadata, never transcript text or secret values.
public struct EventDraft: Hashable, Sendable {
  /// When the fact occurred, in Unix milliseconds.
  public var ts: Int64
  /// The principal responsible for the change.
  public var actor: Actor
  /// The record or system component the fact describes.
  public var subject: ObjectRef
  /// Its routing scope; conversation scopes require a current fence.
  public var scope: EventScope
  /// The originating user, routine or other source, when applicable.
  public var origin: Origin?
  /// The typed fact; unknown and UI-only facts cannot be persisted.
  public var event: Event

  /// Creates unnumbered metadata for an atomic store commit.
  public init(
    ts: Int64, actor: Actor, subject: ObjectRef, scope: EventScope = EventScope(),
    origin: Origin? = nil, event: Event
  ) {
    self.ts = ts
    self.actor = actor
    self.subject = subject
    self.scope = scope
    self.origin = origin
    self.event = event
  }
}

/// One atomic change: record upserts and their facts. Every changed record needs a matching
/// subject event, and every affected conversation needs its current, unexpired fence.
public struct StoreCommit: Hashable, Sendable {
  /// Current-state records to upsert with their matching subject events.
  public var records: [RecordChange]
  /// Facts to append in order in this transaction.
  public var events: [EventDraft]
  /// Current capabilities for every conversation touched by the transaction.
  public var fences: [ConversationFence]

  /// Groups record changes, their facts and required conversation fences.
  public init(
    records: [RecordChange] = [], events: [EventDraft], fences: [ConversationFence] = []
  ) {
    self.records = records
    self.events = events
    self.fences = fences
  }
}

/// The value and its position come from one read transaction.
public struct StoreSnapshot<Value: Sendable>: Sendable {
  /// The current state read by the snapshot.
  public let value: Value
  /// The global and optional conversation position of that same snapshot.
  public let asOf: AsOf
}

/// The current head and oldest retained position of the durable event log.
public struct ReplayBounds: Hashable, Sendable {
  /// The highest committed global sequence, including previously pruned rows.
  public let head: Int64
  /// The oldest retained sequence; one past the head when the log is empty.
  public let minRetainedSeq: Int64

  /// `nil` always means resync; future cursors are not valid replay positions.
  public func canReplay(after: Int64?) -> Bool {
    guard let after else { return false }
    return after >= minRetainedSeq - 1 && after <= head
  }
}

/// One contiguous, bounded page toward a previously captured replay head.
public struct ReplayPage: Hashable, Sendable {
  /// Persisted envelopes ordered by global sequence.
  public let events: [EventEnvelope]
  /// Retention bounds rechecked while reading this page.
  public let bounds: ReplayBounds
  /// The fixed head this replay is catching up to.
  public let through: Int64
  /// The cursor to pass for the next page.
  public let nextAfter: Int64
  /// Whether more events remain before the captured head.
  public let hasMore: Bool
}

/// The committed outcome of one bounded retention batch.
public struct PruneResult: Hashable, Sendable {
  /// The number of old prefix rows removed.
  public let deleted: Int
  /// The log bounds after pruning and its change event commit.
  public let bounds: ReplayBounds
  /// The actual system.pruned fact, returned only after its transaction commits.
  public let events: [EventEnvelope]
}

/// The actual schema transition performed while opening a store.
public struct MigrationReport: Hashable, Sendable {
  /// The schema found before applying migrations.
  public let fromVersion: Int
  /// The schema installed after the migration transaction.
  public let toVersion: Int
  /// The verified pre-upgrade backup; absent for a fresh or already-current store.
  public let backupURL: URL?
}
