import CloudKit
import CryptoKit
import Foundation
import MemoshiDevice
import MemoshiProtocol
import Synchronization

/// Pure authority transition rules: an exact expected epoch, no active-holder stealing, no
/// renewal after expiry, no released-epoch resurrection. CloudKit's change tag orders the save.
public enum CloudLeaseRules {
  /// Computes a new fencing epoch only for the exact observed epoch and a free or expired lease.
  /// `now` and `expiresAt` are Unix milliseconds; `maximumTTL` is a positive millisecond duration.
  /// Invalid deadlines/epochs or an active holder throw without persisting or granting authority.
  public static func claim(
    conversation: ConversationID, current: LeaseRecord?, expectedEpoch: Int64?,
    claimant: DeviceID, expiresAt: Int64, now: Int64, maximumTTL: Int64
  ) throws -> LeaseRecord {
    guard current == nil || current?.conversationID == conversation else {
      throw AppleDeviceError.invalidState("lease conversation")
    }
    guard expiresAt > now, maximumTTL > 0,
      expiresAt.subtractingReportingOverflow(now).overflow == false,
      expiresAt - now <= maximumTTL
    else { throw AppleDeviceError.invalidState("lease deadline") }
    guard current?.epoch == expectedEpoch else { throw AppleDeviceError.authorityConflict }
    if let current, current.runner != nil, (current.expiresAt ?? Int64.max) > now {
      throw AppleDeviceError.authorityConflict
    }
    let epoch = (expectedEpoch ?? 0).addingReportingOverflow(1)
    guard !epoch.overflow, epoch.partialValue > 0 else {
      throw AppleDeviceError.invalidState("lease epoch")
    }
    return LeaseRecord(
      conversationID: conversation, epoch: epoch.partialValue, runner: claimant,
      expiresAt: expiresAt)
  }

  /// Extends an unexpired lease held by this runner at this exact epoch without shortening it.
  /// Times are Unix milliseconds and the positive TTL bound is milliseconds from `now`;
  /// a mismatched holder, expired lease, or invalid deadline throws an authority conflict.
  public static func renew(
    current: LeaseRecord, epoch: Int64, runner: DeviceID, expiresAt: Int64,
    now: Int64, maximumTTL: Int64
  ) throws -> LeaseRecord {
    guard LeaseRules.holds(current, epoch: epoch, device: runner, at: now),
      expiresAt > now, expiresAt >= (current.expiresAt ?? Int64.max), maximumTTL > 0,
      !expiresAt.subtractingReportingOverflow(now).overflow, expiresAt - now <= maximumTTL
    else { throw AppleDeviceError.authorityConflict }
    return LeaseRecord(
      conversationID: current.conversationID, epoch: epoch, runner: runner, expiresAt: expiresAt)
  }

  /// Clears the exact holder while retaining its fencing epoch, even if the lease has expired.
  /// A holder or epoch mismatch throws; this pure transition performs no durable save.
  public static func release(current: LeaseRecord, epoch: Int64, runner: DeviceID) throws
    -> LeaseRecord
  {
    guard current.epoch == epoch, current.runner == runner else {
      throw AppleDeviceError.authorityConflict
    }
    return LeaseRecord(
      conversationID: current.conversationID, epoch: epoch, runner: nil, expiresAt: nil)
  }
}

/// CloudKit operation helper, deliberately not a mockable last-write-wins abstraction.
/// Every mutable save uses the exact fetched CKRecord/change tag and one conditional operation.
enum CloudConditionalSave {
  static func save(_ records: [CKRecord], in database: CKDatabase) async throws -> [CKRecord] {
    let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
    operation.savePolicy = .ifServerRecordUnchanged
    operation.isAtomic = true
    let results = Mutex<[CKRecord.ID: Result<CKRecord, any Error>]>([:])
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
          return
        }
        operation.perRecordSaveBlock = { id, result in results.withLock { $0[id] = result } }
        operation.modifyRecordsResultBlock = { result in
          do {
            // Item errors preserve serverRecordChanged even if the operation reports partialFailure.
            let saved = try results.withLock { values in
              for value in values.values {
                if case .failure(let error) = value, let cloudError = error as? CKError,
                  cloudError.code == .serverRecordChanged
                {
                  throw cloudError
                }
              }
              return try records.map { record in
                guard let value = values[record.recordID] else {
                  try result.get()
                  throw AppleDeviceError.authorityUnavailable
                }
                return try value.get()
              }
            }
            try result.get()
            continuation.resume(returning: saved)
          } catch { continuation.resume(throwing: error) }
        }
        database.add(operation)
      }
    } onCancel: {
      operation.cancel()
    }
  }

  static func read(_ id: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord? {
    do { return try await database.record(for: id) } catch let error as CKError
      where error.code == .unknownItem
    { return nil }
  }
}

/// Lease data is a signed MLS-exporter AEAD state record. Reads never consume an application
/// ratchet. The state authority conditionally updates the actual group head/index plus lease.
public actor CloudKitLeaseAuthority {
  private struct ProtectedLease: Codable {
    let groupID: String
    let writer: DeviceID
    let operationID: UUID
    let lease: LeaseRecord
  }

  private let group: DeviceGroup
  private let identity: DeviceIdentity
  private let states: CloudKitStateAuthority
  private let maximumTTL: Int64
  private let now: @Sendable () -> Int64

  /// Retains the caller's group, signing identity, and state-record authority without I/O.
  /// Requires a positive lease limit in milliseconds; `now` supplies Unix milliseconds.
  public init(
    group: DeviceGroup, identity: DeviceIdentity, states: CloudKitStateAuthority,
    maximumLeaseMilliseconds: Int64,
    now: @escaping @Sendable () -> Int64 = { DeviceClock.wallMilliseconds() }
  ) throws {
    guard maximumLeaseMilliseconds > 0 else { throw AppleDeviceError.invalidState("lease TTL") }
    self.group = group
    self.identity = identity
    self.states = states
    maximumTTL = maximumLeaseMilliseconds
    self.now = now
  }

  /// Conditionally persists a claim for this identity at the expected fencing epoch.
  /// A revoked holder is cleared without resetting its epoch; save uncertainty, epoch changes,
  /// or expiry throw rather than granting a provisional lease or retrying the claim.
  public func claim(_ claim: LeaseClaim) async throws -> LeaseRecord {
    try await update(claim.conversationId) { current, members in
      let eligible: LeaseRecord?
      if let current, let runner = current.runner, !members.contains(runner) {
        // A revoked holder loses authority, but its fencing epoch is never reset or reused.
        eligible = LeaseRecord(
          conversationID: current.conversationID, epoch: current.epoch, runner: nil, expiresAt: nil)
      } else {
        eligible = current
      }
      return try CloudLeaseRules.claim(
        conversation: claim.conversationId, current: eligible, expectedEpoch: claim.expectedEpoch,
        claimant: self.identity.deviceID, expiresAt: claim.expiresAt, now: self.now(),
        maximumTTL: self.maximumTTL)
    }
  }

  /// Conditionally persists a non-shortening renewal for this identity's current, unexpired
  /// fencing epoch. Deadlines use Unix milliseconds; read/save conflicts propagate to the caller.
  public func renew(_ renew: LeaseRenew) async throws -> LeaseRecord {
    try await update(renew.conversationId) { current, _ in
      guard let current else { throw AppleDeviceError.authorityConflict }
      return try CloudLeaseRules.renew(
        current: current, epoch: renew.epoch, runner: self.identity.deviceID,
        expiresAt: renew.expiresAt, now: self.now(), maximumTTL: self.maximumTTL)
    }
  }

  /// Conditionally clears this identity's exact fencing epoch without resetting the epoch.
  /// Missing records, ownership conflicts, and persistence failures throw.
  public func release(_ release: LeaseRelease) async throws -> LeaseRecord {
    try await update(release.conversationId) { current, _ in
      guard let current else { throw AppleDeviceError.authorityConflict }
      return try CloudLeaseRules.release(
        current: current, epoch: release.epoch, runner: self.identity.deviceID)
    }
  }

  /// Reads and authenticates the conversation's protected lease without consuming an application
  /// ratchet. Absence returns `nil`; malformed, conflicting, or unavailable state throws.
  public func record(_ conversation: ConversationID) async throws -> LeaseRecord? {
    let observed = try await states.read(
      recordName: recordName(conversation), recordType: "MemoshiMLSLease",
      purpose: "memoshi.lease.v1")
    return try await decode(observed.plaintext, conversation: conversation)
  }

  private func update(
    _ conversation: ConversationID,
    transition: (LeaseRecord?, Set<DeviceID>) throws -> LeaseRecord
  ) async throws -> LeaseRecord {
    let epoch = await group.epoch
    let observed = try await states.read(
      recordName: recordName(conversation), recordType: "MemoshiMLSLease",
      purpose: "memoshi.lease.v1")
    let current = try await decode(observed.plaintext, conversation: conversation)
    let members = Set(await group.members.map(\.deviceId))
    guard await group.epoch == epoch else { throw AppleDeviceError.staleEpoch }
    let next = try transition(current, members)
    let value = ProtectedLease(
      groupID: await group.groupID, writer: identity.deviceID, operationID: UUID(), lease: next)
    _ = try await states.save(observed, plaintext: JSONEncoder().encode(value))
    // An uncertain/expired save never grants execution. Reconcile the original fencing state;
    // do not recreate an unreadable record, silently retry a claim, or grant a provisional lease.
    guard await group.epoch == epoch else { throw AppleDeviceError.staleEpoch }
    guard next.runner == nil || (next.expiresAt ?? 0) > now() else {
      throw AppleDeviceError.authorityConflict
    }
    return next
  }

  private func decode(_ bytes: Data?, conversation: ConversationID) async throws -> LeaseRecord? {
    guard let bytes else { return nil }
    let value = try JSONDecoder().decode(ProtectedLease.self, from: bytes)
    let groupID = await group.groupID
    guard value.groupID == groupID, value.lease.conversationID == conversation,
      value.lease.epoch > 0
    else { throw AppleDeviceError.conflictingReplay }
    return value.lease
  }

  private func recordName(_ conversation: ConversationID) -> String {
    "lease."
      + SHA256.hash(data: Data(conversation.rawValue.utf8))
      .map { String(format: "%02x", $0) }.joined()
  }
}
