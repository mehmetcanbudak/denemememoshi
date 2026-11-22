import CloudKit
import Foundation
import MemoshiDevice
import MemoshiProtocol

/// An observed logical state revision, not a permission to execute. nil plaintext is possible
/// ONLY when the authenticated current-head index and the actual database both say absent.
public struct CloudStateRecordObservation: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// Logical record identity in this group's private zone, reused for conditional updates.
  public let recordName: String
  /// Expected CloudKit schema type, checked against the current authenticated state index.
  public let recordType: String
  /// Exporter-record domain label binding the object to its lease or snapshot namespace.
  public let purpose: String
  /// Sensitive decrypted object bytes, or `nil` only for authenticated absence.
  /// Reading them grants no execution permission; callers own plaintext handling.
  public let plaintext: Data?
  let digest: Data?
  let changeTag: String?
  /// Redacted summary that does not disclose the observed plaintext.
  public var description: String { "CloudStateRecordObservation(<redacted>)" }
  /// The same redacted summary used for normal descriptions.
  public var debugDescription: String { description }
}

/// Mutable lease/log snapshots use exporter AEAD, not application-message ratchets. A signed,
/// current-context encrypted manifest in the CAS head endorses each record's exact ciphertext.
/// This prevents old-key AEAD alone from authorizing a rollback or a revoked writer's new state.
public actor CloudKitStateAuthority {
  struct Reference: Codable, Hashable, Sendable {
    let recordType: String
    let purpose: String
    let digest: Data
    let epoch: UInt64
    let contextDigest: Data
  }
  struct Manifest: Codable, Hashable, Sendable {
    var counter: UInt64
    var objects: [String: Reference]
  }
  struct RekeyWork: Codable, Sendable {
    let operation: String
    let targetEpoch: UInt64
    let targetContext: Data
    let oldEnvelopeDigest: Data
    let manifest: Manifest
    let plaintext: [String: Data]

    /// Both inputs must come from the authenticated current head: immutable accepted membership
    /// history, and the opened/pinned current index. No remote completion is inferred from time.
    func validateSupersededCompletion(
      _ commit: GroupCommit, accepted: (commit: GroupCommit, context: Data),
      current: Manifest, header: MLSStateRecordHeader, material: GroupStateRecordKey
    ) throws {
      let contextDigest = MLSStateRecordCodec.digest(material.groupContext)
      guard operation == (try CloudKitStateAuthority.operationID(commit)),
        accepted.commit == commit, commit.groupId == material.groupID,
        commit.fromEpoch >= 0, UInt64(commit.fromEpoch) + 1 == targetEpoch,
        accepted.context == targetContext, material.epoch > targetEpoch,
        header.groupID == material.groupID, header.groupEpoch == material.epoch,
        header.groupContext == material.groupContext,
        material.members.contains(where: { $0.deviceID == header.writer }),
        current.counter > manifest.counter,
        current.objects.values.allSatisfy({
          $0.epoch == material.epoch && $0.contextDigest == contextDigest
        })
      else { throw AppleDeviceError.stateRecoveryRequired }
      // Later legitimate logical edits may change ciphertext digests, not silently drop an
      // earlier authoritative object or change its namespace/purpose during reconciliation.
      for (name, original) in manifest.objects {
        guard let retained = current.objects[name],
          retained.recordType == original.recordType, retained.purpose == original.purpose
        else {
          throw AppleDeviceError.stateRecoveryRequired
        }
      }
    }
  }
  private struct Checkpoint: Codable {
    var pins: [String: CloudStateIndexPin] = [:]
    var pending: [String: RekeyWork] = [:]
    /// Set only by ``CloudKitStateAuthority/eraseRemovedState(directory:identity:)``, in a
    /// checkpoint that holds nothing else.
    var erased: Bool?
  }

  private static let journalName = "state-authority.jsonl"
  private static let journalPurpose = "com.memoshi.cloudkit-state-authority.v1"

  private weak var groups: CloudKitGroupAuthority?
  private let mailbox: CloudKitMailbox
  private let group: DeviceGroup
  private let codec: MLSStateRecordCodec
  private let journal: DeviceStateJournal
  private let maximumRecords: Int
  private var checkpoint = Checkpoint()
  private var failed = false
  private let indexPurpose = "memoshi.cloudkit-state.index.v1"

  init(
    groups: CloudKitGroupAuthority, mailbox: CloudKitMailbox, group: DeviceGroup,
    identity: DeviceIdentity, directory: URL, maximumRecords: Int = 2_048
  ) throws {
    self.groups = groups
    self.mailbox = mailbox
    self.group = group
    codec = MLSStateRecordCodec(identity: identity, group: group)
    self.maximumRecords = maximumRecords
    journal = try DeviceStateJournal(
      url: directory.appendingPathComponent(Self.journalName),
      key: identity.derivedStateEncryptionKey(purpose: Self.journalPurpose),
      purpose: Self.journalPurpose)
    if let bytes = journal.takeRecovered().last {
      checkpoint = try JSONDecoder().decode(Checkpoint.self, from: bytes)
    }
    // A removed device's erased checkpoint (D133) opens nothing: nothing is re-keyed, pinned or
    // saved for that group again.
    if checkpoint.erased == true {
      journal.close()
      throw AppleDeviceError.revoked
    }
  }

  /// D133: after this device's verified removal, deletes this authority's local checkpoint for
  /// the group. While a membership change this device committed re-keys the group's protected
  /// state records (lease and log snapshots), the checkpoint holds their plaintext
  /// (`RekeyWork.plaintext`, kept from `prepareMembershipChange` until `didCommit` re-sealed
  /// them under the new epoch); it also holds index pins (epoch, counter, digest). A removed
  /// device can never finish that work. The journal is replaced by one checkpoint that says only
  /// that it was erased (written beside it, synchronized, renamed over it, directory
  /// synchronized), so no byte of an earlier record is in the file when this returns, and an
  /// authority never opens from it again. It is written without reading the checkpoint first,
  /// so one that can no longer be read is erased as well. Call with no authority open on
  /// `directory`.
  static func eraseRemovedState(directory: URL, identity: DeviceIdentity) throws {
    let url = directory.appendingPathComponent(journalName)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let journal = try DeviceStateJournal(
      url: url, key: identity.derivedStateEncryptionKey(purpose: journalPurpose),
      purpose: journalPurpose, discardingHistory: true)
    defer { journal.close() }
    try journal.replace(Checkpoint(erased: true))
  }

  /// Only used in the explicit, first-device epoch-zero head creation transaction.
  func initialIndex(headID: CKRecord.ID) async throws -> Data {
    try requireOpen()
    let material = try await group.currentStateRecordKey()
    guard material.epoch == 0 else { throw AppleDeviceError.stateRecoveryRequired }
    return try await codec.seal(
      encode(Manifest(counter: 0, objects: [:])), objectID: objectID(headID, field: "stateIndex"),
      purpose: indexPurpose)
  }

  /// Called BEFORE membership CAS while the old Native context is still active. Cached exporter
  /// access is gate-free. Every exact index-endorsed plaintext is encrypted/fsynced locally before
  /// a membership commit can drop its old key. No unknown/unreadable record becomes an empty one.
  func prepareMembershipChange(
    head: CKRecord, commit: GroupCommit, target: UInt64, context: Data, baseContext: Data
  ) async throws {
    try requireOpen()
    let operation = try Self.operationID(commit)
    let loaded = try await loadManifest(head)
    if let existing = checkpoint.pending[operation] {
      guard existing.targetEpoch == target, existing.targetContext == context else {
        throw AppleDeviceError.conflictingReplay
      }
      // Revalidate/pin even an identical prepared envelope: a later durable high-water mark
      // must not be bypassed by resuming an older pending work item.
      if MLSStateRecordCodec.digest(loaded.encoded) == existing.oldEnvelopeDigest { return }
    }
    let material = try await group.currentStateRecordKey()
    guard loaded.header.groupEpoch == material.epoch,
      loaded.header.groupContext == material.groupContext,
      material.groupContext == baseContext,
      commit.fromEpoch >= 0, UInt64(commit.fromEpoch) == material.epoch
    else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    let connection = try await mailbox.authorityContext()
    var plaintext: [String: Data] = [:]
    var bytes = 0
    for (name, reference) in loaded.manifest.objects.sorted(by: { $0.key < $1.key }) {
      guard
        let record = try await CloudConditionalSave.read(
          CKRecord.ID(recordName: name, zoneID: connection.zone), in: connection.database),
        record.recordType == reference.recordType,
        let encoded = record.encryptedValues["value"] as? Data,
        MLSStateRecordCodec.digest(encoded) == reference.digest
      else { throw AppleDeviceError.stateRecoveryRequired }
      let opened = try await codec.open(
        encoded, objectID: objectID(record.recordID), purpose: reference.purpose)
      guard opened.header.groupEpoch == reference.epoch,
        MLSStateRecordCodec.digest(opened.header.groupContext) == reference.contextDigest
      else {
        throw AppleDeviceError.stateRecoveryRequired
      }
      bytes += opened.plaintext.count
      guard bytes <= 16 * 1_024 * 1_024 else {
        throw AppleDeviceError.invalidState("state rekey checkpoint capacity")
      }
      plaintext[name] = opened.plaintext
    }
    checkpoint.pending[operation] = RekeyWork(
      operation: operation, targetEpoch: target, targetContext: context,
      oldEnvelopeDigest: MLSStateRecordCodec.digest(loaded.encoded),
      manifest: loaded.manifest, plaintext: plaintext)
    try persist()
  }

  func discardMembershipChange(_ commit: GroupCommit) throws {
    let id = try Self.operationID(commit)
    if checkpoint.pending.removeValue(forKey: id) != nil { try persist() }
  }

  /// Native accept/checkpoint and gate release MUST precede this callback; the final pairing
  /// hello MUST follow it. A crash resumes the same pinned work, without changing logical data.
  public func didCommit(_ commit: GroupCommit) async throws {
    try requireOpen()
    guard let groups else { throw AppleDeviceError.closed }
    let operation = try Self.operationID(commit)
    let material = try await group.currentStateRecordKey()
    let currentContextDigest = MLSStateRecordCodec.digest(material.groupContext)
    guard let work = checkpoint.pending[operation] else {
      let head = try await groups.membershipFence()
      _ = try await groups.acceptedMembership(commit)
      let current = try await loadManifest(head)
      guard current.header.groupEpoch == material.epoch,
        current.header.groupContext == material.groupContext,
        current.manifest.objects.values.allSatisfy({
          $0.epoch == material.epoch && $0.contextDigest == currentContextDigest
        })
      else { throw AppleDeviceError.stateRecoveryRequired }
      return  // Exact completed rekey is idempotent; this is not a missing-state fallback.
    }
    if material.epoch > work.targetEpoch {
      let head = try await groups.membershipFence()
      let accepted = try await groups.acceptedMembership(commit)
      let current = try await loadManifest(head)
      try work.validateSupersededCompletion(
        commit, accepted: accepted, current: current.manifest, header: current.header,
        material: material)
      checkpoint.pending[operation] = nil
      try persist()
      return
    }
    guard material.epoch == work.targetEpoch, material.groupContext == work.targetContext else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    while true {
      let head = try await groups.membershipFence()
      guard let encodedIndex = head.encryptedValues["stateIndex"] as? Data else {
        throw AppleDeviceError.stateRecoveryRequired
      }
      let manifest: Manifest
      if MLSStateRecordCodec.digest(encodedIndex) == work.oldEnvelopeDigest {
        // Only this fsynced, pre-CAS exact digest authorizes an old manifest after revocation.
        manifest = work.manifest
      } else {
        manifest = try await loadManifest(head).manifest
      }
      var next = manifest
      var records: [CKRecord] = []
      var encodedBytes = 0
      let connection = try await mailbox.authorityContext()
      for (name, original) in work.manifest.objects.sorted(by: { $0.key < $1.key }) {
        guard let current = next.objects[name] else { throw AppleDeviceError.stateRecoveryRequired }
        if current.epoch == material.epoch, current.contextDigest == currentContextDigest {
          continue
        }
        guard current.digest == original.digest, let plaintext = work.plaintext[name],
          let record = try await CloudConditionalSave.read(
            CKRecord.ID(recordName: name, zoneID: connection.zone), in: connection.database),
          let existing = record.encryptedValues["value"] as? Data,
          MLSStateRecordCodec.digest(existing) == original.digest
        else { throw AppleDeviceError.stateRecoveryRequired }
        let sealed = try await codec.seal(
          plaintext, objectID: objectID(record.recordID), purpose: original.purpose)
        if !records.isEmpty, records.count >= 50 || encodedBytes + sealed.count > 2 * 1_024 * 1_024
        {
          break
        }
        record.encryptedValues["value"] = sealed as NSData
        records.append(record)
        encodedBytes += sealed.count
        next.objects[name] = Reference(
          recordType: original.recordType, purpose: original.purpose,
          digest: MLSStateRecordCodec.digest(sealed),
          epoch: material.epoch, contextDigest: currentContextDigest)
      }
      let allCurrent = next.objects.values.allSatisfy {
        $0.epoch == material.epoch && $0.contextDigest == currentContextDigest
      }
      let currentHeader = try MLSStateRecordCodec.header(of: encodedIndex)
      if records.isEmpty, allCurrent, currentHeader.groupEpoch == material.epoch,
        currentHeader.groupContext == material.groupContext
      {
        checkpoint.pending[operation] = nil
        try persist()
        return
      }
      let counter = next.counter.addingReportingOverflow(1)
      guard !counter.overflow else { throw AppleDeviceError.invalidState("state index counter") }
      next.counter = counter.partialValue
      let index = try await codec.seal(
        encode(next), objectID: objectID(head.recordID, field: "stateIndex"), purpose: indexPurpose)
      head.encryptedValues["stateIndex"] = index as NSData
      do {
        _ = try await CloudConditionalSave.save([head] + records, in: connection.database)
      } catch let error as CKError where error.code == .serverRecordChanged {
        throw AppleDeviceError.authorityConflict
      }
      try pin(next, header: MLSStateRecordCodec.header(of: index))
      if allCurrent {
        checkpoint.pending[operation] = nil
        try persist()
        return
      }
    }
  }

  /// Public log-snapshot interface. Snapshot bytes may contain fencing/high-water/intent state;
  /// they are preserved byte-for-byte during rekey, never guessed, merged or reset here.
  public func readSnapshot(snapshotID: String) async throws -> CloudStateRecordObservation {
    let name =
      "snapshot."
      + MLSStateRecordCodec.digest(Data(snapshotID.utf8)).map { String(format: "%02x", $0) }
      .joined()
    return try await read(
      recordName: name, recordType: "MemoshiMLSSnapshot", purpose: "memoshi.log-snapshot.v1")
  }

  /// Replaces the exact observed snapshot revision using exporter encryption and an atomic
  /// record/current-head-index conditional save, then durably pins the returned index revision.
  /// Wrong namespace, stale observation, bounded-index capacity, or cloud/local persistence failure
  /// throws; an uncertain save is not retried or treated as an empty snapshot.
  public func saveSnapshot(_ observed: CloudStateRecordObservation, plaintext: Data) async throws
    -> CloudStateRecordObservation
  {
    guard observed.recordName.hasPrefix("snapshot."), observed.recordType == "MemoshiMLSSnapshot",
      observed.purpose == "memoshi.log-snapshot.v1"
    else { throw AppleDeviceError.invalidState("snapshot observation") }
    return try await save(observed, plaintext: plaintext)
  }

  /// Classifies a save whose caller observed `observed` while the current index holds `indexed`.
  /// A difference means another device saved first: an ordinary lost race, never lost state.
  static func staleObservation(observed: Data?, indexed: Data?) -> AppleDeviceError? {
    observed == indexed ? nil : .authorityConflict
  }

  /// Classifies a record that disagrees with the index entry read just before it, given that
  /// entry read again. A changed entry is another device's save between the two reads; an
  /// unchanged one means the record itself is missing, foreign or damaged.
  static func unendorsedRecord(indexed: Data?, reindexed: Data?) -> AppleDeviceError {
    indexed == reindexed ? .stateRecoveryRequired : .authorityConflict
  }

  /// The head and the record are two reads, so a concurrent lease or snapshot save leaves a
  /// record that the first read's index does not endorse. Reads the entry again to tell them apart.
  private func unendorsed(_ recordName: String, indexed: Data?) async throws -> AppleDeviceError {
    guard let groups else { return .closed }
    let current = try await loadManifest(try await groups.membershipFence())
    return Self.unendorsedRecord(
      indexed: indexed, reindexed: current.manifest.objects[recordName]?.digest)
  }

  func read(recordName: String, recordType: String, purpose: String) async throws
    -> CloudStateRecordObservation
  {
    try requireOpen()
    guard let groups else { throw AppleDeviceError.closed }
    let head = try await groups.membershipFence()
    let index = try await loadManifest(head)
    let material = try await group.currentStateRecordKey()
    guard index.header.groupEpoch == material.epoch,
      index.header.groupContext == material.groupContext
    else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    let connection = try await mailbox.authorityContext()
    let id = CKRecord.ID(recordName: recordName, zoneID: connection.zone)
    let record = try await CloudConditionalSave.read(id, in: connection.database)
    guard let reference = index.manifest.objects[recordName] else {
      guard record == nil else { throw try await unendorsed(recordName, indexed: nil) }
      return CloudStateRecordObservation(
        recordName: recordName, recordType: recordType, purpose: purpose, plaintext: nil,
        digest: nil, changeTag: nil)
    }
    guard reference.recordType == recordType, reference.purpose == purpose,
      let record, record.recordType == recordType,
      let encoded = record.encryptedValues["value"] as? Data,
      MLSStateRecordCodec.digest(encoded) == reference.digest
    else { throw try await unendorsed(recordName, indexed: reference.digest) }
    let opened = try await codec.open(encoded, objectID: objectID(id), purpose: purpose)
    guard opened.header.groupEpoch == reference.epoch,
      MLSStateRecordCodec.digest(opened.header.groupContext) == reference.contextDigest
    else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    let observed = CloudStateRecordObservation(
      recordName: recordName, recordType: recordType, purpose: purpose, plaintext: opened.plaintext,
      digest: reference.digest, changeTag: record.recordChangeTag)
    if opened.header.groupEpoch != material.epoch
      || opened.header.groupContext != material.groupContext
    {
      return try await save(observed, plaintext: opened.plaintext)
    }
    return observed
  }

  func save(_ observed: CloudStateRecordObservation, plaintext: Data) async throws
    -> CloudStateRecordObservation
  {
    try requireOpen()
    guard observed.recordName.hasPrefix("lease.") || observed.recordName.hasPrefix("snapshot.")
    else {
      throw AppleDeviceError.invalidState("state record namespace")
    }
    guard let groups else { throw AppleDeviceError.closed }
    let head = try await groups.membershipFence()
    var index = try await loadManifest(head)
    let material = try await group.currentStateRecordKey()
    guard index.header.groupEpoch == material.epoch,
      index.header.groupContext == material.groupContext
    else { throw AppleDeviceError.stateRecoveryRequired }
    if let failure = Self.staleObservation(
      observed: observed.digest, indexed: index.manifest.objects[observed.recordName]?.digest)
    {
      throw failure
    }
    let connection = try await mailbox.authorityContext()
    let id = CKRecord.ID(recordName: observed.recordName, zoneID: connection.zone)
    let existing = try await CloudConditionalSave.read(id, in: connection.database)
    guard existing?.recordChangeTag == observed.changeTag else {
      throw AppleDeviceError.authorityConflict
    }
    if let existing {
      guard existing.recordType == observed.recordType,
        let bytes = existing.encryptedValues["value"] as? Data,
        MLSStateRecordCodec.digest(bytes) == observed.digest
      else { throw AppleDeviceError.stateRecoveryRequired }
    } else if observed.digest != nil {
      throw AppleDeviceError.stateRecoveryRequired
    }
    guard
      index.manifest.objects[observed.recordName] != nil
        || index.manifest.objects.count < maximumRecords
    else {
      throw AppleDeviceError.invalidState("state index capacity")
    }
    let record = existing ?? CKRecord(recordType: observed.recordType, recordID: id)
    let encoded = try await codec.seal(plaintext, objectID: objectID(id), purpose: observed.purpose)
    record.encryptedValues["value"] = encoded as NSData
    let digest = MLSStateRecordCodec.digest(encoded)
    index.manifest.objects[observed.recordName] = Reference(
      recordType: observed.recordType, purpose: observed.purpose, digest: digest,
      epoch: material.epoch, contextDigest: MLSStateRecordCodec.digest(material.groupContext))
    let counter = index.manifest.counter.addingReportingOverflow(1)
    guard !counter.overflow else { throw AppleDeviceError.invalidState("state index counter") }
    index.manifest.counter = counter.partialValue
    let encryptedIndex = try await codec.seal(
      encode(index.manifest), objectID: objectID(head.recordID, field: "stateIndex"),
      purpose: indexPurpose)
    head.encryptedValues["stateIndex"] = encryptedIndex as NSData
    let saved: [CKRecord]
    do {
      saved = try await CloudConditionalSave.save([head, record], in: connection.database)
    } catch let error as CKError where error.code == .serverRecordChanged {
      throw AppleDeviceError.authorityConflict
    }
    try pin(index.manifest, header: MLSStateRecordCodec.header(of: encryptedIndex))
    guard let actual = saved.first(where: { $0.recordID == id }) else {
      throw AppleDeviceError.authorityUnavailable
    }
    return CloudStateRecordObservation(
      recordName: observed.recordName, recordType: observed.recordType, purpose: observed.purpose,
      plaintext: plaintext, digest: digest, changeTag: actual.recordChangeTag)
  }

  private func loadManifest(_ head: CKRecord) async throws -> (
    manifest: Manifest, header: MLSStateRecordHeader, encoded: Data
  ) {
    guard let encoded = head.encryptedValues["stateIndex"] as? Data else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    let value = try await codec.open(
      encoded, objectID: objectID(head.recordID, field: "stateIndex"), purpose: indexPurpose)
    let material = try await group.currentStateRecordKey()
    guard value.header.groupEpoch == material.epoch,
      value.header.groupContext == material.groupContext,
      material.members.contains(where: { $0.deviceID == value.header.writer })
    else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    let manifest = try JSONDecoder().decode(Manifest.self, from: value.plaintext)
    guard manifest.objects.count <= maximumRecords else {
      throw AppleDeviceError.invalidState("state index capacity")
    }
    for (name, reference) in manifest.objects {
      let lease =
        name.hasPrefix("lease.") && reference.recordType == "MemoshiMLSLease"
        && reference.purpose == "memoshi.lease.v1"
      let snapshot =
        name.hasPrefix("snapshot.") && reference.recordType == "MemoshiMLSSnapshot"
        && reference.purpose == "memoshi.log-snapshot.v1"
      guard lease || snapshot else { throw AppleDeviceError.invalidState("state index namespace") }
    }
    try pin(manifest, header: value.header)
    return (manifest, value.header, encoded)
  }

  private func pin(_ manifest: Manifest, header: MLSStateRecordHeader) throws {
    let key = MLSStateRecordCodec.digest(header.groupContext).base64EncodedString()
    let digest = MLSStateRecordCodec.digest(try encode(manifest))
    let candidate = CloudStateIndexPin(
      epoch: header.groupEpoch, counter: manifest.counter, digest: digest)
    let latest = checkpoint.pins.values.max { $0.counter < $1.counter }
    _ = try CloudStateIndexPin.accept(candidate, over: latest)
    let accepted = try CloudStateIndexPin.accept(candidate, over: checkpoint.pins[key])
    if checkpoint.pins[key] == accepted { return }
    checkpoint.pins[key] = accepted
    if header.groupEpoch >= 3 {
      checkpoint.pins = checkpoint.pins.filter { $0.value.epoch >= header.groupEpoch - 3 }
    }
    try persist()
  }

  private func persist() throws {
    do { try journal.replace(checkpoint) } catch {
      failed = true
      throw error
    }
  }

  private static func operationID(_ commit: GroupCommit) throws -> String {
    MLSStateRecordCodec.digest(Data(try ProtocolCoding.canonicalText(of: commit).utf8))
      .base64EncodedString()
  }

  private func objectID(_ id: CKRecord.ID, field: String = "value") -> String {
    CloudDeviceConfiguration.containerIdentifier + "/private/" + id.zoneID.ownerName + "/"
      + id.zoneID.zoneName + "/" + id.recordName + "/" + field
  }

  private func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }

  private func requireOpen() throws { if failed { throw AppleDeviceError.persistenceFailed } }
  /// Closes the encrypted local pin/rekey journal and makes future operations fail closed.
  /// Does not delete protected cloud records or reset durable recovery work.
  public func close() {
    failed = true
    journal.close()
  }
}
