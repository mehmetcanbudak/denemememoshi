import Foundation
import MemoshiProtocol

/// A lease as this device records it: the authority's epoch and runner, so local writes are
/// fenced by the authority's decision. A nil runner is a released or unknown holder.
public struct LeaseRecord: Hashable, Sendable, Codable {
  /// The conversation.
  public var conversationID: ConversationID
  /// The fencing epoch.
  public var epoch: Int64
  /// The runner at that epoch, if known and still holding it.
  public var runner: DeviceID?
  /// When the runner's lease lapses; nil when the runner is nil.
  public var expiresAt: Int64?

  /// Creates a record.
  public init(conversationID: ConversationID, epoch: Int64, runner: DeviceID?, expiresAt: Int64?) {
    self.conversationID = conversationID
    self.epoch = epoch
    self.runner = runner
    self.expiresAt = runner == nil ? nil : expiresAt
  }
}

/// One change a runner wants to commit.
public struct PendingChange: Hashable, Sendable {
  /// The conversation.
  public var conversationID: ConversationID
  /// The epoch the runner believes it holds; the store checks it.
  public var epoch: Int64
  /// A short description of the change (a task title in the Store-backed implementation).
  public var label: String
  /// The client's idempotency key, for an admitted forwarded message.
  public var requestID: ULID?

  /// Creates a pending change.
  public init(conversationID: ConversationID, epoch: Int64, label: String, requestID: ULID? = nil) {
    self.conversationID = conversationID
    self.epoch = epoch
    self.label = label
    self.requestID = requestID
  }
}

/// What a committed change wrote, for replication.
public struct CommittedChange: Hashable, Sendable {
  /// The records the change wrote.
  public var records: [ReplicatedRecord]
  /// The events the change appended, with this device's `deviceId` and sequence numbers.
  public var events: [EventEnvelope]

  /// Creates a committed change.
  public init(records: [ReplicatedRecord], events: [EventEnvelope]) {
    self.records = records
    self.events = events
  }
}

/// Why a store refused a write: the epoch is not this device's current, unexpired lease.
public enum FenceError: Error, Equatable, Sendable {
  /// The write's epoch is stale, expired or not held by this device.
  case fenced(currentEpoch: Int64?)
  /// The authority reported two runners at one epoch.
  case conflictingRunner
}

/// The device's conversation stores seen through their fences. The qualification harness backs
/// this with `MemoshiStore`; ``MemoryConversationStore`` mirrors the same rules in memory.
public protocol ConversationStore: Sendable {
  /// Records an authority-decided lease. Epochs only move forward: an older epoch throws
  /// ``FenceError/fenced(currentEpoch:)``; at the same epoch a released lease stays released and
  /// the same runner's expiry only extends.
  func adoptLease(_ lease: LeaseRecord, at now: Int64) async throws
  /// Commits one change, only while this device holds `change.epoch`, unexpired. A
  /// ``FenceError`` means the store refused before writing anything; the node releases the
  /// sequence it reserved for the change on that error and on no other.
  func commit(_ change: PendingChange, at now: Int64) async throws -> CommittedChange
  /// Gives up this device's lease at `epoch` before a hand-over; the epoch stays fenced.
  func releaseLease(_ conversationID: ConversationID, epoch: Int64, at now: Int64) async throws
}

/// The fence rules of ``ConversationStore`` over in-memory records.
public actor MemoryConversationStore: ConversationStore {
  private let deviceID: DeviceID
  private var leases: [ConversationID: LeaseRecord] = [:]
  /// Every accepted commit, in order.
  public private(set) var accepted: [PendingChange] = []
  /// Commits refused by the fence.
  public private(set) var refused = 0
  private var erased = false

  /// A store for one device.
  public init(deviceID: DeviceID) { self.deviceID = deviceID }

  /// The local record for a conversation.
  public func lease(_ conversationID: ConversationID) -> LeaseRecord? { leases[conversationID] }

  /// D133: after this device's verified removal from its group, drops every lease and accepted
  /// change; every later write throws ``DeviceLayerError/closed``.
  public func erase() {
    leases.removeAll()
    accepted.removeAll()
    erased = true
  }

  /// See ``ConversationStore/adoptLease(_:at:)``.
  public func adoptLease(_ lease: LeaseRecord, at now: Int64) throws {
    guard !erased else { throw DeviceLayerError.closed }
    leases[lease.conversationID] = try LeaseRules.adopt(lease, over: leases[lease.conversationID])
  }

  /// See ``ConversationStore/commit(_:at:)``.
  public func commit(_ change: PendingChange, at now: Int64) throws -> CommittedChange {
    guard !erased else { throw DeviceLayerError.closed }
    let current = leases[change.conversationID]
    guard LeaseRules.holds(current, epoch: change.epoch, device: deviceID, at: now) else {
      refused += 1
      throw FenceError.fenced(currentEpoch: current?.epoch)
    }
    accepted.append(change)
    var value: [String: JSONValue] = ["label": .string(change.label)]
    if let requestID = change.requestID { value["requestId"] = .string(requestID.rawValue) }
    return CommittedChange(
      records: [
        ReplicatedRecord(
          kind: "note", id: "\(change.conversationID.rawValue)/\(accepted.count)", op: .upsert,
          value: .object(value))
      ], events: [])
  }

  /// See ``ConversationStore/releaseLease(_:epoch:at:)``.
  public func releaseLease(_ conversationID: ConversationID, epoch: Int64, at now: Int64) throws {
    guard !erased else { throw DeviceLayerError.closed }
    let current = leases[conversationID]
    guard LeaseRules.holds(current, epoch: epoch, device: deviceID, at: now) else {
      throw FenceError.fenced(currentEpoch: current?.epoch)
    }
    leases[conversationID] = LeaseRecord(
      conversationID: conversationID, epoch: epoch, runner: nil, expiresAt: nil)
  }
}

/// The shared adopt and fence rules.
public enum LeaseRules {
  /// The record after adopting `lease` over `current`.
  public static func adopt(_ lease: LeaseRecord, over current: LeaseRecord?) throws -> LeaseRecord {
    guard let current else { return lease }
    if lease.epoch < current.epoch { throw FenceError.fenced(currentEpoch: current.epoch) }
    guard lease.epoch == current.epoch else { return lease }
    // A released epoch never comes back.
    guard let runner = current.runner else { return current }
    guard let newRunner = lease.runner else {
      return LeaseRecord(
        conversationID: current.conversationID, epoch: current.epoch, runner: nil, expiresAt: nil)
    }
    guard newRunner == runner else { throw FenceError.conflictingRunner }
    return LeaseRecord(
      conversationID: current.conversationID, epoch: current.epoch, runner: runner,
      expiresAt: max(current.expiresAt ?? 0, lease.expiresAt ?? 0))
  }

  /// Whether `device` may write at `epoch` now.
  public static func holds(_ current: LeaseRecord?, epoch: Int64, device: DeviceID, at now: Int64)
    -> Bool
  {
    guard let current, current.epoch == epoch, current.runner == device,
      let expiresAt = current.expiresAt
    else { return false }
    return expiresAt > now
  }
}
