import CryptoKit
import Darwin
import Foundation
import MemoshiMLS
import MemoshiProtocol

/// Established locally or by the QR-authenticated real MLS Welcome, never by a fetched root.
public struct GroupAuthorityAnchor: Codable, Hashable, Sendable {
  /// Trust-root group identity established locally or through authenticated pairing.
  public var groupID: String
  /// Membership epoch at anchoring, not necessarily the group's latest local or remote head.
  public var epoch: Int64
  /// Local creator or authenticated inviter whose device list established this anchor.
  public var signer: DevicePeer
  /// Exact public roster at the anchor epoch, not a fresh membership lookup.
  public var members: [DeviceListEntry]
  /// Native GroupContext at the trusted anchor epoch, checkpointed before use.
  public var groupContext: Data
}

/// Checkpointed plaintext from a native open or local seal, not a second decryption, transport
/// delivery acknowledgement, or proof that the domain's effects have been consumed.
public struct GroupApplicationReceipt: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// Lowercase SHA-256 hex identity of the exact ciphertext, independent of domain operation IDs.
  public let id: String
  /// Retained plaintext, native sender/epoch and AAD; never log or expose as UI state.
  public let opened: MLSOpenedMessage
  /// Checkpointed full-feed routing, or nil for a low-level open without ordered routing.
  public let routing: DeviceApplicationRouting?
  init(id: String, opened: MLSOpenedMessage, routing: DeviceApplicationRouting? = nil) {
    self.id = id
    self.opened = opened
    self.routing = routing
  }
  /// Content-free rendering that hides receipt identity and plaintext.
  public var description: String { "GroupApplicationReceipt(<redacted>)" }
  /// Uses the same redaction as the ordinary description.
  public var debugDescription: String { description }
}

/// Failures when resolving checkpointed exporter material for an exact native epoch/context.
public enum GroupStateRecordKeyError: Error, Equatable, Sendable {
  /// Required active/retained epoch material is unavailable; old keys are never regenerated.
  case unavailable
  /// Caller-supplied context differs from the checkpointed context for that epoch.
  case contextMismatch
}

/// Host-transport-only exporter material. Never place it in UI state, logs or a wire record.
/// Persistent objects use separately labeled standard AEAD; this is not an MLS message.
public struct GroupStateRecordKey: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  /// Group identity under which this exporter material was checkpointed.
  public let groupID: String
  /// Native membership epoch that produced the exporter, not a conversation lease epoch.
  public let epoch: UInt64
  /// Exact authenticated native context to bind host record encryption to this epoch.
  public let groupContext: Data
  /// Secret 32-byte native exporter output for host record-key derivation; never transmit raw.
  public let secret: Data
  /// Full credential roster authenticated for this exporter epoch, including the local member.
  public let members: [DevicePeer]
  /// Content-free rendering that excludes exporter material and metadata.
  public var description: String { "GroupStateRecordKey(<redacted>)" }
  /// Uses the same redaction as the ordinary description.
  public var debugDescription: String { description }
}

/// Owns the genuine RFC 9420 state and, when a directory is supplied, encrypted local
/// checkpoints. Without a directory, state is memory-only. Signed device lists remain pairing/
/// display metadata; native authentication is separate from domain receipt consumption.
public actor DeviceGroup {
  /// Fixed local device keys; membership and fresh remote authority still require validation.
  public nonisolated let localPeer: DevicePeer
  /// Whether initialization restored a local group checkpoint rather than creating a new root.
  public nonisolated let wasRestored: Bool
  /// Host-owned checkpoint directory, or nil for memory-only state.
  public nonisolated let stateDirectory: URL?
  /// Latest-only local seal-ordinal hints; neither full-feed acceptance nor domain consumption.
  public nonisolated let applicationFeedUpdates: AsyncStream<UInt64>
  private let feedSink: AsyncStream<UInt64>.Continuation
  /// Current local group identity, not evidence of a fresh authority read.
  public var groupID: String { state.groupID }
  /// Latest locally installed native membership epoch.
  public var epoch: Int64 { state.epoch }
  /// Locally installed public roster in native leaf order, potentially behind remote authority.
  public var members: [DeviceListEntry] { state.members }
  /// Cumulative identity tombstones learned from validated membership transitions/authority.
  public var revoked: Set<DeviceID> { state.revoked }

  struct PreparedAdd: Codable, Hashable, Sendable {
    var id: UUID
    var subject: DeviceListEntry
    var staged: MLSStagedCommit
    var devices: SignedDeviceList
  }

  private typealias SavedState = GroupSavedState
  private typealias SentApplication = GroupSavedState.SentApplication
  private typealias RecordKey = GroupSavedState.RecordKey
  private typealias PendingHello = GroupSavedState.PendingHello
  private typealias RetiredSeal = GroupSavedState.RetiredSeal

  private let identity: DeviceIdentity
  /// The saved state's file, or nil for memory-only state.
  private var store: GroupStateStore?
  private let gate = SerialGate()
  private let completionGate = SerialGate()
  private var mls: MLSGroup
  private var state: SavedState
  private var persistenceFailed = false
  private var restoredPending = false
  private var joinCompletionOwner: UUID?
  /// The seal of the final hello an add owed, kept for the epoch it was sealed in. Whichever
  /// path sealed it (the pairing exchange, the owed-hello rule of another seal, recovery), the
  /// exchange gets this same seal: once published and acknowledged, the operation is no longer
  /// in `sent`, and sealing it again would put a second hello after other seals.
  private var sealedOwedHello:
    (operationID: String, packet: DeviceSealedApplication, inputDigest: Data)?
  /// A client prepared for a fresh pairing attempt while an earlier confirmed join is unresolved.
  /// Memory-only: it replaces that join in one checkpoint, or is dropped with its attempt.
  private var replacement: (mls: MLSGroup, keyPackage: Data)?
  private var openedSinks: [UUID: AsyncStream<Void>.Continuation] = [:]
  private var pendingBytes = 0
  private var availableRecordKeys: [UInt64: RecordKey] = [:]
  private var availableAnchor: GroupAuthorityAnchor?
  private var availableOpened: Set<String> = []
  private var availableConsumed: Set<String> = []
  private var availableRoutes: [String: DeviceApplicationRouting] = [:]
  private var availableRetired: Set<String> = []
  private var availableRetiredOrdered: [String] = []
  /// The most devices one group holds: the native MLS layer's own limit (`MAX_MEMBERS` in
  /// `MemoshiMLS`). A further add is refused with ``PairingRefusal/groupFull``.
  public static let maximumMembers = 64
  private static let maximumPendingReceipts = 16_384
  static let nodeApplicationContext = "memoshi.device-message.v2"
  /// Present from before a group's first checkpoint until a node has paired a replica journal
  /// with it. While it exists nothing was ever journaled beside this checkpoint, so a missing
  /// replica journal is an unfinished first launch, not lost history. Its absence proves nothing.
  private static let firstLaunchMarker = "group.jsonl.first-launch"
  private static let maximumPendingBytes = 12 * 1024 * 1024

  /// With a directory, checkpoints initial MLS keys before the group identity can escape.
  /// An existing empty checkpoint is lost history, never permission to create another root.
  public init(
    identity: DeviceIdentity, groupID: String = DeviceULID.make(), directory: URL? = nil
  ) throws {
    self.identity = identity
    localPeer = identity.peer
    stateDirectory = directory
    (applicationFeedUpdates, feedSink) = AsyncStream.makeStream(
      of: UInt64.self, bufferingPolicy: .bufferingNewest(1))
    let checkpointExisted =
      directory.map {
        FileManager.default.fileExists(atPath: $0.appendingPathComponent("group.jsonl").path)
      } ?? false
    // The checkpoint file exists only once a checkpoint was written, so an initialization that
    // stops before its first checkpoint leaves nothing that looks like emptied history.
    var store = try directory.map {
      try GroupStateStore(directory: $0, key: identity.stateEncryptionKey())
    }
    if let saved = try store?.recover() {
      wasRestored = true
      guard saved.version == 3 || saved.version == 4, saved.epoch >= 0, !saved.groupID.isEmpty,
        Set(saved.members.map(\.deviceId)).count == saved.members.count,
        saved.nextApplicationOrdinal > 0,
        saved.previousApplicationOrdinal < saved.nextApplicationOrdinal,
        saved.acceptedApplicationOrdinal < saved.nextApplicationOrdinal,
        saved.receivedDigests.values.allSatisfy({ $0.values.allSatisfy { $0.count == 32 } }),
        saved.consumedHead >= 0, saved.consumedHead <= saved.consumed.count,
        !saved.active
          || saved.members.contains(where: {
            $0.deviceId == identity.deviceID
              && (try? DevicePeer(deviceID: $0.deviceId, publicKeys: $0.publicKeys))
                == identity.peer
          })
      else { throw DeviceLayerError.invalid("durable MLS group state") }
      if !saved.active, !saved.joiningClient, saved.secretState.isEmpty {
        // A removed device's tombstone keeps no native state. This client only stands in for
        // it in memory; a removed group never saves native state again.
        mls = try MLSGroup.clientAndSnapshot(
          credential: identity.peer.mlsCredential, signIdentityBinding: { try identity.sign($0) }
        ).value
      } else {
        mls = try MLSGroup(
          restoring: saved.secretState, expectedCredential: identity.peer.mlsCredential)
      }
      state = saved
      restoredPending = saved.pendingAdd != nil || saved.pendingRequest != nil
      pendingBytes =
        saved.sent.values.reduce(0) {
          $0 + $1.packet.message.ciphertext.count + $1.packet.authenticatedData.count
        }
        + saved.opened.values.reduce(0) {
          $0 + $1.plaintext.count + $1.authenticatedData.count
        }
        + saved.waiting.values.reduce(0) {
          $0 + $1.application.message.ciphertext.count + $1.application.authenticatedData.count
        }
    } else {
      guard !checkpointExisted else {
        store?.close()
        throw DeviceLayerError.invalid("missing durable MLS group checkpoint")
      }
      wasRestored = false
      let created = try MLSGroup.createAndSnapshot(
        credential: identity.peer.mlsCredential, groupID: Data(groupID.utf8),
        signIdentityBinding: { try identity.sign($0) })
      mls = created.value
      let members = [
        try Self.entry(
          for: identity.peer, name: identity.name, platform: identity.platform, leaf: 0)
      ]
      state = SavedState(
        groupID: groupID, epoch: 0, members: members, active: true,
        anchor: GroupAuthorityAnchor(
          groupID: groupID, epoch: 0, signer: identity.peer, members: members, groupContext: Data()),
        secretState: created.secretState)
      if let directory {
        // The checkpoint's directory sync below makes this marker durable with it.
        guard
          FileManager.default.createFile(
            atPath: directory.appendingPathComponent(Self.firstLaunchMarker).path, contents: nil,
            attributes: [.posixPermissions: 0o600])
        else { throw DeviceLayerError.io("device first-launch marker") }
      }
      try store?.save(&state)
    }
    self.store = store
    availableRecordKeys = state.recordKeys
    availableAnchor = state.anchor
    availableOpened = Set(state.opened.keys)
    availableConsumed = Set(state.consumed.dropFirst(state.consumedHead))
    availableRoutes = state.openedRoutes
    availableRetired = Set((state.retired ?? []).map(\.ciphertextID))
    availableRetiredOrdered = Self.orderedOperations(state.retired)
  }

  /// Whether the membership checkpoint in `directory` has never had a replica journal beside it.
  static func isFirstLaunch(in directory: URL) -> Bool {
    FileManager.default.fileExists(
      atPath: directory.appendingPathComponent(firstLaunchMarker).path)
  }

  /// Called once the replica journal exists: from now on a missing half is lost history.
  static func finishFirstLaunch(in directory: URL) throws {
    guard unlink(directory.appendingPathComponent(firstLaunchMarker).path) == 0 else {
      guard errno == ENOENT else { throw DeviceLayerError.io("device first-launch marker") }
      return
    }
    let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard parent >= 0 else { throw DeviceLayerError.io("device first-launch marker") }
    defer { _ = Darwin.close(parent) }
    guard fsync(parent) == 0 else { throw DeviceLayerError.io("device first-launch marker") }
  }

  private func requireAvailable() throws {
    guard !persistenceFailed else { throw DeviceLayerError.io("MLS state unavailable") }
  }

  private func requireActive() throws {
    try requireAvailable()
    guard state.active, !state.joiningClient else { throw DeviceLayerError.unknownPeer }
  }

  /// Makes the current state durable before it returns: one change row appended to the saved
  /// state's file, or the file replaced by a snapshot (`GroupStateStore`). A removed device
  /// (inactive, not joining: its removal was verified and installed) keeps nothing it got
  /// through the group: no native state, which holds its own leaf's signing key, and no
  /// consumed history; its saved state is a tombstone that restores as removed.
  private func checkpoint(_ secret: Data? = nil) async throws {
    guard !persistenceFailed else { throw DeviceLayerError.io("MLS state unavailable") }
    do {
      if !state.active, !state.joiningClient {
        state.secretState = Data()
        state.recordKeys.removeAll()
        state.eraseHistory()
        availableConsumed.removeAll()
      } else if let secret {
        state.secretState = secret
      } else {
        state.secretState = try await mls.snapshot()
      }
      if store != nil { try store?.save(&state) } else { state.markSaved() }
      availableRecordKeys = state.recordKeys
      availableAnchor = state.anchor
      availableRetired = Set((state.retired ?? []).map(\.ciphertextID))
      availableRetiredOrdered = Self.orderedOperations(state.retired)
    } catch {
      persistenceFailed = true
      throw error
    }
  }

  /// Bytes written to the group-state file since this group opened it.
  var checkpointBytesWritten: UInt64 { store?.bytesWritten ?? 0 }

  /// Snapshots written to the group-state file since this group opened it.
  var checkpointSnapshotsWritten: Int { store?.snapshotsWritten ?? 0 }

  /// The state as last checkpointed: what a restart must rebuild.
  var checkpointedState: GroupSavedState { state }

  /// Serializes shutdown with native mutations, closes the journal/native state and finishes
  /// feed updates. Does not delete disk checkpoints or promise secure erasure of retained bytes.
  public func close() async {
    await gate.acquire()
    defer { gate.release() }
    // A clean close leaves one snapshot: nothing a later checkpoint superseded stays in the
    // file. A failure here changes nothing that was saved.
    if !persistenceFailed { try? store?.compact(state) }
    persistenceFailed = true
    store?.close()
    await mls.close()
    await replacement?.mls.close()
    replacement = nil
    state.secretState = Data()
    feedSink.finish()
    for sink in openedSinks.values { sink.finish() }
    openedSinks.removeAll()
    state.sent.removeAll()
    state.operations.removeAll()
    state.opened.removeAll()
    state.recordKeys.removeAll()
    state.waiting.removeAll()
    state.openedRoutes.removeAll()
    availableOpened.removeAll()
    availableConsumed.removeAll()
    availableRoutes.removeAll()
    availableRecordKeys.removeAll()
    availableAnchor = nil
    pendingBytes = 0
  }

  /// Returns active native group metadata under the mutation gate, not a fresh authority
  /// snapshot. Throws for a joining, removed, closed or persistence-failed group.
  public func groupInfo() async throws -> MLSGroupInfo {
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    return try await mls.info()
  }

  /// Returns the locally established trust anchor, checkpointing its initial native context
  /// if needed. A cached anchor is historical evidence, not a fresh authority head or lease.
  public func authorityAnchor() async throws -> GroupAuthorityAnchor {
    try requireActive()
    if let anchor = availableAnchor, anchor.groupID == state.groupID, !anchor.groupContext.isEmpty {
      return anchor
    }
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    try await ensureAnchorContext()
    return state.anchor
  }

  private func ensureAnchorContext() async throws {
    guard state.anchor.groupContext.isEmpty else { return }
    guard state.anchor.epoch == state.epoch else {
      throw DeviceLayerError.invalid("missing native authority anchor")
    }
    let info = try await mls.info()
    try Self.validate(
      info, groupID: state.groupID, epoch: state.epoch, members: state.anchor.members)
    state.anchor.groupContext = info.groupContext
    try await captureRecordKey(info)
    try await checkpoint()
  }

  /// Cached lookups are safe inside a membership CAS callback: only fsynced keys escape.
  /// Missing prior epochs fail closed instead of regenerating unrelated key material.
  public func currentStateRecordKey() async throws -> GroupStateRecordKey {
    try requireActive()
    if let key = availableRecordKeys[UInt64(state.epoch)], key.groupID == state.groupID {
      return key.value
    }
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    try await ensureCurrentRecordKey()
    guard let key = availableRecordKeys[UInt64(state.epoch)] else {
      throw GroupStateRecordKeyError.unavailable
    }
    return key.value
  }

  /// Resolves only checkpointed exporter material matching the exact native epoch/context.
  /// May initialize the current epoch's key; missing prior epochs and context mismatches throw.
  public func stateRecordKey(epoch: UInt64, groupContext: Data) async throws -> GroupStateRecordKey
  {
    try requireActive()
    if let key = availableRecordKeys[epoch] {
      guard key.groupID == state.groupID, key.groupContext == groupContext else {
        throw GroupStateRecordKeyError.contextMismatch
      }
      return key.value
    }
    guard epoch == UInt64(state.epoch) else {
      throw GroupStateRecordKeyError.unavailable
    }
    let key = try await currentStateRecordKey()
    guard key.groupContext == groupContext else {
      throw GroupStateRecordKeyError.contextMismatch
    }
    return key
  }

  private func ensureCurrentRecordKey() async throws {
    guard state.recordKeys[UInt64(state.epoch)] == nil else { return }
    let info = try await mls.info()
    try await captureRecordKey(info)
    try await checkpoint()
  }

  private func captureRecordKey(_ info: MLSGroupInfo) async throws {
    guard info.isActive else { return }
    guard info.groupID == Data(state.groupID.utf8), info.epoch == UInt64(state.epoch) else {
      throw DeviceLayerError.invalid("persistent-state native epoch mismatch")
    }
    if let existing = state.recordKeys[info.epoch] {
      guard existing.groupContext == info.groupContext else {
        persistenceFailed = true
        throw DeviceLayerError.invalid("persistent-state native context changed")
      }
      return
    }
    let secret = try await mls.exportSecret(
      label: "memoshi.cloudkit-state.v1", context: info.groupContext, length: 32)
    guard secret.count == 32 else { throw DeviceLayerError.invalid("persistent-state exporter") }
    let peers = try info.members.map {
      DevicePeer(
        deviceID: try DeviceID($0.deviceID), signingKey: $0.signingPublicKey,
        agreementKey: $0.agreementPublicKey)
    }
    state.recordKeys[info.epoch] = RecordKey(
      groupID: state.groupID, epoch: info.epoch, groupContext: info.groupContext,
      secret: secret, members: peers)
    if info.epoch >= 4 {
      let retired = info.epoch - 4
      state.recordKeys.removeValue(forKey: retired)
      state.received.removeValue(forKey: retired)
      state.receivedDigests.removeValue(forKey: retired)
      state.completedEpochs.removeValue(forKey: retired)
    }
  }

  /// Matches a local active-roster identity and exact agreement key. Does not fetch authority;
  /// unavailable, joining or removed groups return nil.
  public func member(_ deviceID: DeviceID, agreementKey: Data) -> DevicePeer? {
    guard !persistenceFailed, state.active, !state.joiningClient,
      let entry = state.members.first(where: { $0.deviceId == deviceID }),
      let peer = try? DevicePeer(deviceID: entry.deviceId, publicKeys: entry.publicKeys),
      peer.agreementKey == agreementKey
    else { return nil }
    return peer
  }

  /// Other members of the local active roster; empty while unavailable, joining or removed.
  /// Callers needing present authority must refresh before trusting this cached view.
  public var peers: [DevicePeer] {
    guard !persistenceFailed, state.active, !state.joiningClient else { return [] }
    return state.members.compactMap {
      guard $0.deviceId != identity.deviceID else { return nil }
      return try? DevicePeer(deviceID: $0.deviceId, publicKeys: $0.publicKeys)
    }
  }

  /// A joining client and its KeyPackage private material are durable before publication.
  func prepareJoining() async throws -> Data {
    await gate.acquire()
    defer { gate.release() }
    try Task.checkCancellation()
    guard !persistenceFailed else { throw DeviceLayerError.io("MLS state unavailable") }
    if state.pendingJoin && !state.confirmationAttempted {
      try await resetUnconfirmedClient()
    }
    if let stale = replacement {
      replacement = nil
      await stale.mls.close()
    }
    if state.pendingJoin {
      // The earlier confirmation may have reached its inviter, so that join stays durable. A
      // fresh attempt runs on a separate client, and only a Welcome proving the earlier add
      // dead may replace it (see `join`). A retained final hello means that add was accepted.
      guard state.active, try pendingJoinCompletion() == nil else {
        throw DeviceLayerError.invalid("pending pairing needs authority reconciliation")
      }
      let client = try MLSGroup.clientAndSnapshot(
        credential: identity.peer.mlsCredential, signIdentityBinding: { try identity.sign($0) })
      let keyPackage = try await client.value.generateKeyPackage()
      replacement = (client.value, keyPackage)
      return keyPackage
    }
    if !state.joiningClient {
      guard state.epoch == 0, state.members.count == 1,
        state.members.first?.deviceId == identity.deviceID, state.nextApplicationOrdinal == 1,
        state.sent.isEmpty, state.opened.isEmpty, state.waiting.isEmpty
      else { throw DeviceLayerError.invalid("paired devices reconnect instead of joining twice") }
      let client = try MLSGroup.clientAndSnapshot(
        credential: identity.peer.mlsCredential, signIdentityBinding: { try identity.sign($0) })
      let old = mls
      mls = client.value
      state.joiningClient = true
      state.active = false
      state.recordKeys.removeAll()
      try await checkpoint(client.secretState)
      await old.close()
    }
    if let keyPackage = state.keyPackage { return keyPackage }
    let generated = try await mls.generateKeyPackageAndSnapshot()
    state.keyPackage = generated.value
    try await checkpoint(generated.secretState)
    return generated.value
  }

  /// Persists the real Welcome result before sending the handshake-bound confirmation.
  func join(groupID: String, list: SignedDeviceList, inviter: DevicePeer, welcome: Data)
    async throws
  {
    await gate.acquire()
    defer { gate.release() }
    try Task.checkCancellation()
    guard !persistenceFailed, state.joiningClient || replacement != nil,
      list.signerDeviceId == inviter.deviceID, Self.verify(list, groupID: groupID, signer: inviter),
      list.epoch >= 0, list.devices.contains(where: { $0.deviceId == identity.deviceID })
    else { throw PairingRefusal.badSignature }
    let client: MLSGroup
    if let replacement {
      // A confirmed pending join is replaced only when its add can no longer be ordered: its
      // own inviter staged a new add for this device, or the group already passed the epoch
      // that add targeted. Another group, or another member at the same epoch, proves neither;
      // a retained final hello proves the opposite.
      guard state.pendingJoin, state.confirmationAttempted, groupID == state.groupID,
        inviter == state.anchor.signer || list.epoch > state.anchor.epoch,
        try pendingJoinCompletion() == nil
      else {
        self.replacement = nil
        await replacement.mls.close()
        throw DeviceLayerError.invalid("pending pairing needs authority reconciliation")
      }
      client = replacement.mls
    } else {
      client = mls
    }
    let info = try await client.join(
      welcome: welcome, expectedGroupID: Data(groupID.utf8), expectedEpoch: UInt64(list.epoch))
    try Self.validate(info, groupID: groupID, epoch: list.epoch, members: list.devices)
    let members = list.devices.sorted { $0.leafIndex < $1.leafIndex }
    let anchor = GroupAuthorityAnchor(
      groupID: groupID, epoch: list.epoch, signer: inviter, members: members,
      groupContext: info.groupContext)
    if replacement != nil {
      let superseded = mls
      mls = client
      replacement = nil
      state = SavedState(
        groupID: groupID, epoch: list.epoch, members: members, active: info.isActive,
        anchor: anchor, secretState: Data())
      pendingBytes = 0
      availableOpened.removeAll()
      availableConsumed.removeAll()
      availableRoutes.removeAll()
      await superseded.close()
    } else {
      state.groupID = groupID
      state.epoch = list.epoch
      state.members = members
      state.anchor = anchor
      state.active = info.isActive
      state.joiningClient = false
    }
    state.pendingJoin = true
    state.confirmationAttempted = false
    state.keyPackage = nil
    try await captureRecordKey(info)
    try await checkpoint()
  }

  /// Synchronized before the final proof can enter the carrier, preserving uncertain confirms.
  func markConfirmationAttempted() async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    guard state.pendingJoin else { throw DeviceLayerError.invalid("no pending MLS join") }
    state.confirmationAttempted = true
    try await checkpoint()
  }

  func abandonUnconfirmedJoin() async {
    await gate.acquire()
    defer { gate.release() }
    if let abandoned = replacement {
      replacement = nil
      await abandoned.mls.close()
    }
    guard !persistenceFailed, !state.confirmationAttempted,
      state.joiningClient || state.pendingJoin
    else { return }
    do { try await resetUnconfirmedClient() } catch { persistenceFailed = true }
  }

  private func resetUnconfirmedClient() async throws {
    let client = try MLSGroup.clientAndSnapshot(
      credential: identity.peer.mlsCredential, signIdentityBinding: { try identity.sign($0) })
    let old = mls
    mls = client.value
    let namespace = DeviceULID.make()
    let members = [
      try Self.entry(for: identity.peer, name: identity.name, platform: identity.platform, leaf: 0)
    ]
    state = SavedState(
      groupID: namespace, epoch: 0, members: members, active: false, joiningClient: true,
      anchor: GroupAuthorityAnchor(
        groupID: namespace, epoch: 0, signer: identity.peer, members: members, groupContext: Data()),
      secretState: client.secretState)
    pendingBytes = 0
    try await checkpoint(client.secretState)
    await old.close()
  }

  /// The live exchange owns domain completion, not the native mutation gate. Feed readers and
  /// reentrant authority callbacks must remain free to authenticate its final hello.
  func beginJoinExchange() throws -> UUID {
    try requireAvailable()
    try Task.checkCancellation()
    guard joinCompletionOwner == nil else {
      throw DeviceLayerError.invalid("pairing exchange already in progress")
    }
    let owner = UUID()
    joinCompletionOwner = owner
    return owner
  }

  func endJoinExchange(_ owner: UUID) {
    if joinCompletionOwner == owner { joinCompletionOwner = nil }
  }

  /// Ordinary Node dispatch must leave the exact checkpointed completion with its durable
  /// pending-join stage, even when authority adoption has already confirmed membership.
  func ownsJoinCompletion(_ message: DeviceMessage) -> Bool {
    guard case .deviceHello = message.body else { return false }
    return (try? pendingJoinCompletion(matching: message)) != nil
  }

  func finishJoin(_ hello: DeviceMessage, owner: UUID) async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    guard joinCompletionOwner == owner,
      try pendingJoinCompletion(matching: hello) != nil
    else { throw PairingRefusal.invalidMessage("missing authenticated pairing completion") }
    try await finishJoinHoldingGate()
  }

  /// Called only after the Node has reconciled authoritative membership and the full feed.
  /// Reopening never reconstructs a confirmation; the final hello completes the join (see
  /// `pendingJoinCompletion`).
  func recoverJoinCompletion() async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    guard joinCompletionOwner == nil else {
      throw DeviceLayerError.invalid("live pairing exchange owns completion")
    }
    guard state.pendingJoin else { return }
    guard let receipt = try pendingJoinCompletion() else {
      throw DeviceLayerError.invalid("pending pairing requires its authenticated final hello")
    }
    try await finishJoinHoldingGate()
    let retired = retireHoldingGate([receipt.id])
    if retired.changed {
      try await checkpoint(state.secretState)
      publishRetirement(retired)
    }
  }

  private func finishJoinHoldingGate() async throws {
    state.pendingJoin = false
    state.confirmationAttempted = false
    try await checkpoint(state.secretState)
  }

  /// The inviter's authenticated final hello to this device, opened in the epoch its add
  /// created or in a later one. A later one is the same hello sealed again because that epoch
  /// closed before the authority accepted it (D131), or sealed late because it closed before
  /// the inviter sealed it. Either proves the add: this device opens a later epoch's message
  /// only after it applied, to the state its Welcome installed, the commits that followed,
  /// which a group that never accepted the add could not have ordered.
  private func pendingJoinCompletion(matching expected: DeviceMessage? = nil) throws
    -> GroupApplicationReceipt?
  {
    try requireAvailable()
    guard state.pendingJoin, state.confirmationAttempted,
      let epoch = UInt64(exactly: state.anchor.epoch)
    else { return nil }
    for (id, opened) in state.opened {
      guard availableOpened.contains(id),
        opened.sender == state.anchor.signer.mlsCredential, opened.groupEpoch >= epoch,
        let route = state.openedRoutes[id], route.kind == .rawNative,
        route.sender == state.anchor.signer.deviceID,
        route.recipient == .device(identity.deviceID)
      else { continue }
      let receipt = GroupApplicationReceipt(id: id, opened: opened, routing: route)
      guard let message = try Self.nodeMessage(receipt, groupID: state.groupID),
        case .deviceHello = message.body
      else { continue }
      if let expected, message != expected { continue }
      return receipt
    }
    return nil
  }

  func prepareAdding(
    _ peer: DevicePeer, name: String, platform: DevicePlatform, keyPackage: Data
  ) async throws -> PreparedAdd {
    await gate.acquire()
    defer { gate.release() }
    try Task.checkCancellation()
    try requireActive()
    try await ensureAnchorContext()
    try await ensureCurrentRecordKey()
    guard !state.revoked.contains(peer.deviceID) else { throw DeviceLayerError.unknownPeer }
    guard state.pendingAdd == nil, state.pendingRequest == nil, state.pendingCompletion == nil,
      !state.members.contains(where: { $0.deviceId == peer.deviceID })
    else {
      throw DeviceLayerError.invalid("membership change already pending or device already paired")
    }
    guard state.members.count < Self.maximumMembers else { throw PairingRefusal.groupFull }
    let staged = try await mls.stageAdd(
      keyPackage: keyPackage, authenticatedCredential: peer.mlsCredential,
      expectedEpoch: UInt64(state.epoch))
    guard staged.welcome != nil,
      let leaf = staged.memberLeafIndices[peer.deviceID.rawValue],
      let targetEpoch = Int64(exactly: staged.targetEpoch)
    else { throw DeviceLayerError.invalid("native MLS add result") }
    let subject = try Self.entry(for: peer, name: name, platform: platform, leaf: Int(leaf))
    let prospective = try Self.entries(
      staged.members, indices: staged.memberLeafIndices, known: state.members + [subject])
    let prepared = PreparedAdd(
      id: UUID(), subject: subject, staged: staged,
      devices: try sign(prospective, epoch: targetEpoch))
    state.pendingAdd = prepared
    try await checkpoint()
    return prepared
  }

  /// The valid Noise/signing-key confirmation precedes the authority CAS and native acceptance.
  /// The joiner's final `hello` is owed from the same checkpoint as the request, so an add that
  /// the authority accepted is completed by recovery even when this call never returns.
  func confirmAdding(
    _ prepared: PreparedAdd, hello: DeviceMessage, commit: GroupCommitter?,
    applicationFeedReader: DeviceApplicationEpochReader? = nil
  ) async throws -> Int64 {
    await gate.acquire()
    defer { gate.release() }
    try Task.checkCancellation()
    try requireActive()
    guard state.pendingAdd?.id == prepared.id else {
      throw DeviceLayerError.invalid("pairing membership stage no longer current")
    }
    let request = try AuthenticatedGroupCommit.signed(
      groupID: state.groupID, fromEpoch: state.epoch, change: .add, subject: prepared.subject,
      staged: prepared.staged, members: prepared.devices.devices,
      revoked: Array(state.revoked), identity: identity)
    guard let targetEpoch = Int64(exactly: prepared.staged.targetEpoch) else {
      throw DeviceLayerError.invalid("native MLS add result")
    }
    state.pendingRequest = request
    state.pendingHello = PendingHello(message: hello)
    try await checkpoint()
    if let commit {
      let result = try await commit(request)
      guard result.accepted, result.groupId == state.groupID, result.epoch == targetEpoch else {
        try await discardRefused(request, result)
        throw DeviceLayerError.protocolViolation("group add lost at authority")
      }
    }
    if let applicationFeedReader { try await drainApplicationEpoch(using: applicationFeedReader) }
    let info = try await mls.acceptPendingCommit(MLSOrderedCommit(staged: prepared.staged))
    try install(info, metadata: prepared.devices.devices)
    try await captureRecordKey(info)
    if commit != nil { state.pendingCompletion = request }
    state.pendingAdd = nil
    state.pendingRequest = nil
    restoredPending = false
    try await checkpoint()
    return state.epoch
  }

  func discardAdding(_ preparedID: UUID) async {
    await gate.acquire()
    defer { gate.release() }
    guard !persistenceFailed, state.pendingAdd?.id == preparedID,
      state.pendingRequest == nil
    else { return }
    do {
      try await mls.discardPendingCommit()
      state.pendingAdd = nil
      restoredPending = false
      try await checkpoint()
    } catch { persistenceFailed = true }
  }

  /// A reply that refuses the request at its own base epoch is the authority's ordered "no":
  /// these bytes were not applied and nothing submits them again, so the staged commit and its
  /// request are discarded together. A thrown or newer-epoch reply stays uncertain and retained.
  private func discardRefused(_ request: GroupCommit, _ result: GroupCommitResult) async throws {
    guard !result.accepted, result.groupId == request.groupId, result.epoch == request.fromEpoch,
      state.pendingRequest == request
    else { return }
    do {
      try await mls.discardPendingCommit()
    } catch {
      persistenceFailed = true
      throw error
    }
    state.pendingAdd = nil
    state.pendingRequest = nil
    // Only the refused add owed this hello. A refused removal leaves the epoch of an earlier
    // accepted add open, and that add's hello is still owed.
    if request.change == .add { state.pendingHello = nil }
    restoredPending = false
    try await checkpoint()
  }

  /// Stages another member's removal and checkpoints the exact request before optional
  /// authority ordering. A supplied reader must drain the closed base-epoch full feed before
  /// native acceptance. Uncertain replies retain the request; a refusal at its base epoch
  /// discards it. When a committer is supplied, host completion remains separately owned and
  /// blocks another local membership change.
  public func remove(
    _ deviceID: DeviceID, commit: GroupCommitter?,
    applicationFeedReader: DeviceApplicationEpochReader? = nil
  ) async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    try await ensureAnchorContext()
    try await ensureCurrentRecordKey()
    guard state.pendingAdd == nil, state.pendingRequest == nil, state.pendingCompletion == nil,
      deviceID != identity.deviceID,
      let subject = state.members.first(where: { $0.deviceId == deviceID })
    else { throw DeviceLayerError.unknownPeer }
    let staged = try await mls.stageRemove(
      deviceID: deviceID.rawValue, expectedEpoch: UInt64(state.epoch))
    let prospective = try Self.entries(
      staged.members, indices: staged.memberLeafIndices, known: state.members)
    let request = try AuthenticatedGroupCommit.signed(
      groupID: state.groupID, fromEpoch: state.epoch, change: .remove, subject: subject,
      staged: staged, members: prospective, revoked: Array(state.revoked), identity: identity)
    // Native pending commit and its exact bytes survive an uncertain authority reply.
    state.pendingRequest = request
    try await checkpoint()
    if let commit {
      let result = try await commit(request)
      guard result.accepted, result.groupId == state.groupID,
        result.epoch == Int64(exactly: staged.targetEpoch)
      else {
        try await discardRefused(request, result)
        throw DeviceLayerError.protocolViolation("group removal lost at authority")
      }
    }
    if let applicationFeedReader { try await drainApplicationEpoch(using: applicationFeedReader) }
    let info = try await mls.acceptPendingCommit(MLSOrderedCommit(staged: staged))
    try install(info, metadata: prospective)
    try await captureRecordKey(info)
    if commit != nil { state.pendingCompletion = request }
    state.pendingRequest = nil
    try await checkpoint()
  }

  /// Retries only the exact already-confirmed bytes saved with the native pending commit.
  /// A refusal at the request's own base epoch discards them; any other denied or uncertain
  /// reply leaves those bytes intact for a fresh authoritative read.
  func recoverPendingCommit(
    using commit: GroupCommitter, applicationFeedReader: DeviceApplicationEpochReader? = nil
  ) async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    guard let request = state.pendingRequest else { return }
    let authenticated = try AuthenticatedGroupCommit.decode(request, committer: identity.peer)
    let result = try await commit(request)
    guard result.accepted, result.groupId == state.groupID,
      result.epoch == authenticated.toEpoch
    else {
      try await discardRefused(request, result)
      throw DeviceLayerError.protocolViolation("pending membership commit unresolved")
    }
    if let applicationFeedReader { try await drainApplicationEpoch(using: applicationFeedReader) }
    let info = try await mls.acceptPendingCommit(authenticated.orderedCommit)
    try install(info, metadata: authenticated.members)
    try await captureRecordKey(info)
    state.pendingCompletion = request
    state.pendingAdd = nil
    state.pendingRequest = nil
    restoredPending = false
    try await checkpoint()
  }

  /// The membership change whose authority reply is uncertain, if any: its exact request stays
  /// with the native pending commit until ``recoverPendingCommit(using:applicationFeedReader:)``
  /// or an authority read that shows it ordered resolves it.
  var pendingMembershipRequest: GroupCommit? { state.pendingRequest }

  /// The membership change whose host completion is still pending, if any.
  var pendingMembershipCompletion: GroupCommit? { state.pendingCompletion }

  /// The native mutation gate is released during host rewrap. The exact completion survives a
  /// crash/failure and blocks another local membership change until the host finishes it.
  func completeCommittedMembership(using complete: GroupCommitCompletion?) async throws {
    await completionGate.acquire()
    defer { completionGate.release() }
    await gate.acquire()
    let request: GroupCommit?
    do {
      try requireActive()
      request = state.pendingCompletion
      gate.release()
    } catch {
      gate.release()
      throw error
    }
    guard let request else { return }
    if let complete { try await complete(request) }
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    guard state.pendingCompletion == request else {
      throw DeviceLayerError.invalid("membership completion changed")
    }
    state.pendingCompletion = nil
    try await checkpoint()
  }

  /// Only a trusted authority reader calls this. The snapshot may contain one paged commit;
  /// callers continue fetching until this epoch equals the snapshot's authoritative head. A
  /// snapshot older than the installed epoch was read before this device installed a commit
  /// the authority had already ordered (its own add, for example): it has nothing to apply.
  public func adoptAuthority(
    _ snapshot: AuthorityGroup, applicationFeedReader: DeviceApplicationEpochReader? = nil
  ) async throws {
    await gate.acquire()
    defer { gate.release() }
    guard !persistenceFailed, snapshot.groupID == state.groupID else {
      throw DeviceLayerError.unknownPeer
    }
    guard snapshot.epoch >= state.epoch else { return }
    for commit in snapshot.commits where commit.targetEpoch > UInt64(state.epoch) {
      try await applyHoldingGate(
        commit, metadata: snapshot.members, applicationFeedReader: applicationFeedReader)
    }
    if state.epoch == snapshot.epoch {
      let info = try await mls.info()
      try Self.validate(info, groupID: state.groupID, epoch: state.epoch, members: snapshot.members)
      if let context = snapshot.groupContext {
        guard info.groupContext == context else {
          throw DeviceLayerError.invalid("MLS authority head context mismatch")
        }
      } else if state.epoch != 0 || snapshot.members.count != 1 {
        throw DeviceLayerError.invalid("missing MLS authority head context")
      }
      let revoked = state.revoked.union(snapshot.revoked)
      guard !snapshot.members.contains(where: { revoked.contains($0.deviceId) }) else {
        throw DeviceLayerError.invalid("active MLS identity conflicts with revocation tombstone")
      }
      var changed = revoked != state.revoked
      state.revoked = revoked
      if restoredPending, state.pendingAdd != nil, state.pendingRequest == nil {
        try await mls.discardPendingCommit()
        state.pendingAdd = nil
        restoredPending = false
        changed = true
      }
      if changed || state.members != snapshot.members {
        state.members = snapshot.members.sorted { $0.leafIndex < $1.leafIndex }
        restoredPending = state.pendingRequest != nil
        try await checkpoint()
      }
    }
  }

  /// The most pages ``installRemoval(from:reading:)`` reads: one ordered commit each.
  static let maximumRemovalPages = 1_024

  /// Installs this device's removal only if the group's ordered commits, applied in order to a
  /// copy of its own native state, remove it (D133). The copy is made under the gate and read
  /// outside it, so the pages may come over a network; nothing of the group changes until the
  /// proof is complete. No application message of any epoch is read: a removed device gets
  /// no content it did not already hold. With the removal it drops every message it held for
  /// the group (received and own, sealed, retired or waiting) in the one checkpoint that
  /// installs it. `first`, when its commits start at this device's epoch, is the first page;
  /// `next(after)` returns the authority's group with the next commit after `after`. False,
  /// with nothing changed, when the commits do not remove this device.
  public func installRemoval(
    from first: AuthorityGroup? = nil,
    reading next: @Sendable (Int64) async throws -> AuthorityGroup
  ) async throws -> Bool {
    await gate.acquire()
    guard !persistenceFailed else {
      gate.release()
      throw DeviceLayerError.io("MLS state unavailable")
    }
    guard state.active, !state.joiningClient else {
      let removed = !state.joiningClient && !state.active
      gate.release()
      return removed
    }
    let base = state.epoch
    let groupID = state.groupID
    let revoked = state.revoked
    let copy: MLSGroup
    do {
      copy = try MLSGroup(
        restoring: try await mls.snapshot(), expectedCredential: identity.peer.mlsCredential)
    } catch {
      gate.release()
      throw error
    }
    gate.release()
    var epoch = base
    var removal: (info: MLSGroupInfo, members: [DeviceListEntry])?
    var given = first?.commits.first?.baseEpoch == UInt64(base) ? first : nil
    do {
      pages: for _ in 0..<Self.maximumRemovalPages {
        let page: AuthorityGroup
        if let given {
          page = given
        } else {
          page = try await next(epoch)
        }
        given = nil
        guard page.groupID == groupID else { throw DeviceLayerError.unknownPeer }
        var advanced = false
        for commit in page.commits where commit.targetEpoch > UInt64(epoch) {
          guard commit.baseEpoch == UInt64(epoch),
            revoked.allSatisfy({ commit.memberLeafIndices[$0.rawValue] == nil })
          else { throw DeviceLayerError.invalid("MLS authority commit gap") }
          let info: MLSGroupInfo
          if let pending = try await copy.pendingCommit(), pending.commit == commit.commit,
            pending.baseEpoch == commit.baseEpoch, pending.targetEpoch == commit.targetEpoch
          {
            info = try await copy.acceptPendingCommit(commit)
          } else {
            info = try await copy.apply(commit)
          }
          guard let target = Int64(exactly: info.epoch) else {
            throw DeviceLayerError.invalid("MLS group epoch")
          }
          epoch = target
          advanced = true
          if !info.isActive {
            removal = (info, page.members)
            break pages
          }
        }
        guard advanced, epoch < page.epoch else { break }
      }
    } catch {
      await copy.close()
      throw error
    }
    guard let removal else {
      await copy.close()
      return false
    }
    await gate.acquire()
    defer { gate.release() }
    let entries: [DeviceListEntry]
    do {
      guard !persistenceFailed, state.active, !state.joiningClient, state.epoch == base else {
        throw DeviceLayerError.invalid("group state changed while its removal was read")
      }
      entries = try Self.entries(
        removal.info.members, indices: removal.info.memberLeafIndices,
        known: state.members + removal.members)
    } catch {
      await copy.close()
      throw error
    }
    let superseded = mls
    mls = copy
    await superseded.close()
    try install(removal.info, metadata: entries)
    state.pendingAdd = nil
    state.pendingRequest = nil
    state.pendingCompletion = nil
    state.pendingHello = nil
    state.keyPackage = nil
    state.sent.removeAll()
    state.operations.removeAll()
    state.sourceSeals.removeAll()
    state.opened.removeAll()
    state.openedRoutes.removeAll()
    state.deferredConsumption.removeAll()
    state.waiting.removeAll()
    restoredPending = false
    pendingBytes = 0
    availableOpened.removeAll()
    availableRoutes.removeAll()
    try await checkpoint()
    return true
  }

  /// Applies one already-authenticated authority-ordered native commit, optionally draining
  /// the closed base-epoch feed first. Gaps, tombstone conflicts and native validation fail
  /// closed; a matching local proposal is accepted with its host completion still pending.
  public func applyOrderedCommit(
    _ commit: MLSOrderedCommit, applicationFeedReader: DeviceApplicationEpochReader? = nil
  ) async throws {
    await gate.acquire()
    defer { gate.release() }
    guard !persistenceFailed else { throw DeviceLayerError.io("MLS state unavailable") }
    try await applyHoldingGate(
      commit, metadata: state.members, applicationFeedReader: applicationFeedReader)
  }

  private func applyHoldingGate(
    _ commit: MLSOrderedCommit, metadata: [DeviceListEntry],
    applicationFeedReader: DeviceApplicationEpochReader?
  ) async throws {
    try await ensureAnchorContext()
    try await ensureCurrentRecordKey()
    guard commit.baseEpoch == UInt64(state.epoch) else {
      throw DeviceLayerError.invalid("MLS authority commit gap")
    }
    guard state.revoked.allSatisfy({ commit.memberLeafIndices[$0.rawValue] == nil }) else {
      throw DeviceLayerError.unknownPeer
    }
    if let applicationFeedReader { try await drainApplicationEpoch(using: applicationFeedReader) }
    let pending = try await mls.pendingCommit()
    let info: MLSGroupInfo
    if let pending, pending.commit == commit.commit,
      pending.baseEpoch == commit.baseEpoch, pending.targetEpoch == commit.targetEpoch,
      Set(pending.members) == Set(commit.members),
      pending.memberLeafIndices == commit.memberLeafIndices,
      pending.groupContext == commit.groupContext
    {
      info = try await mls.acceptPendingCommit(commit)
      state.pendingCompletion = state.pendingRequest ?? state.pendingCompletion
    } else {
      info = try await mls.apply(commit)
      // Another commit closed the add's epoch before its owed hello was sealed. The hello is
      // still owed: sealed in a later state, it completes the joiner's join all the same.
    }
    let entries = try Self.entries(
      info.members, indices: info.memberLeafIndices, known: state.members + metadata)
    try install(info, metadata: entries)
    try await captureRecordKey(info)
    state.pendingAdd = nil
    state.pendingRequest = nil
    restoredPending = false
    try await checkpoint()
  }

  private func install(_ info: MLSGroupInfo, metadata: [DeviceListEntry]) throws {
    do {
      guard let epoch = Int64(exactly: info.epoch) else {
        throw DeviceLayerError.invalid("MLS group epoch")
      }
      try Self.validate(info, groupID: state.groupID, epoch: epoch, members: metadata)
      let next = Set(metadata.map(\.deviceId))
      guard state.revoked.isDisjoint(with: next) else {
        throw DeviceLayerError.invalid("native group returned a revoked identity")
      }
      state.revoked.formUnion(state.members.lazy.map(\.deviceId).filter { !next.contains($0) })
      if state.epoch != epoch { state.previousApplicationOrdinal = 0 }
      state.epoch = epoch
      state.members = metadata.sorted { $0.leafIndex < $1.leafIndex }
      state.active = info.isActive
      if !info.isActive {
        state.recordKeys.removeAll()
        // Past authenticated inbox/outbox payloads stay encrypted locally until definitive
        // consumption. Revocation retires transport keys, not unapplied historical plaintext.
        // A retired seal is different: no one accepted it and a removed device can never seal
        // it again, so its held plaintext ends with the checkpoint that installs the removal.
        for entry in state.retired ?? [] {
          if let held = state.opened.removeValue(forKey: entry.ciphertextID) {
            pendingBytes -= held.plaintext.count + held.authenticatedData.count
          }
          state.openedRoutes.removeValue(forKey: entry.ciphertextID)
          state.deferredConsumption.remove(entry.ciphertextID)
          availableOpened.remove(entry.ciphertextID)
          availableRoutes.removeValue(forKey: entry.ciphertextID)
        }
        state.retired = nil
      }
    } catch {
      persistenceFailed = true
      throw error
    }
  }

  /// Idempotent seal receipts cover the crash between advancing MLS and persisting a carrier
  /// outbox. AAD is authenticated but public; private fields belong in the plaintext envelope.
  public func sealApplication(
    _ plaintext: Data, authenticatedData: Data = Data(), operationID: String? = nil
  ) async throws -> MLSSealedMessage {
    await gate.acquire()
    defer { gate.release() }
    return
      (try await sealHoldingGate(
        plaintext, operationID: operationID, kind: .rawNative, recipient: nil,
        authenticatedData: { _, _, _ in authenticatedData })).message
  }

  /// Seals/checkpoints one host ordered-transport packet and its idempotent operation receipt.
  /// The AAD builder receives the durable sender seal ordinal and native membership epoch,
  /// not a replication sequence. Exact retries reuse ciphertext; changed input for a retained
  /// operation fails. Caller owns durable full-feed publication and separate carrier receipt ACK.
  public func sealOrderedApplication(
    _ plaintext: Data, operationID: String,
    authenticatedData: @Sendable (_ ordinal: UInt64, _ groupEpoch: UInt64) throws -> Data
  ) async throws -> DeviceSealedApplication {
    await gate.acquire()
    defer { gate.release() }
    return try await sealHoldingGate(
      plaintext, operationID: operationID, kind: .orderedTransport, recipient: nil,
      authenticatedData: { ordinal, epoch, _ in try authenticatedData(ordinal, epoch) })
  }

  /// The immutable source-validated recipient travels with the full feed. A nonrecipient must
  /// consume the same native sender sequence without dispatching the enclosed device message.
  public func sealDeviceMessage(_ message: DeviceMessage) async throws -> DeviceSealedApplication {
    await gate.acquire()
    defer { gate.release() }
    return try await sealDeviceMessageHoldingGate(message)
  }

  /// Seals the final hello a recovered add still owes its joiner. Nil when nothing is owed yet
  /// (its commit is unresolved, or the host has not completed it: the hello follows the
  /// completion) or any more (the joiner left the group). When another member's commit closed
  /// the add's epoch first, the hello is sealed in the current one: the joiner reads it there
  /// once it has applied that commit, and it completes the join as well (D131).
  func sealPendingHello() async throws -> DeviceSealedApplication? {
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    guard let owed = state.pendingHello, state.pendingAdd == nil, state.pendingRequest == nil,
      state.pendingCompletion == nil
    else { return nil }
    guard case .device(let joiner) = owed.message.to,
      state.members.contains(where: { $0.deviceId == joiner })
    else {
      state.pendingHello = nil
      try await checkpoint(state.secretState)
      return nil
    }
    return try await sealDeviceMessageHoldingGate(owed.message)
  }

  private func sealDeviceMessageHoldingGate(_ message: DeviceMessage) async throws
    -> DeviceSealedApplication
  {
    try requireActive()
    guard message.from == .device(identity.deviceID) else { throw DeviceLayerError.unknownPeer }
    switch message.to {
    case .group: break
    case .device(let id):
      guard state.members.contains(where: { $0.deviceId == id }) else {
        throw DeviceLayerError.unknownPeer
      }
    default: throw DeviceLayerError.invalid("device application recipient")
    }
    let groupID = state.groupID
    let sender = identity.deviceID
    return try await sealHoldingGate(
      ProtocolCoding.makeEncoder().encode(message), operationID: message.msgId.rawValue,
      kind: .rawNative, recipient: message.to,
      authenticatedData: { ordinal, epoch, previous in
        try Self.nodeAuthentication(
          groupID: groupID, epoch: epoch, ordinal: ordinal, previous: previous,
          sender: sender, recipient: message.to)
      })
  }

  private func sealHoldingGate(
    _ plaintext: Data, operationID: String?, kind: DeviceSealedApplication.Kind,
    recipient: DeviceAddress?,
    authenticatedData makeAuthentication: @Sendable (UInt64, UInt64, UInt64) throws -> Data
  ) async throws -> DeviceSealedApplication {
    try requireActive()
    try Task.checkCancellation()
    guard state.pendingAdd == nil, state.pendingRequest == nil else {
      throw DeviceLayerError.membershipChangePending
    }
    try await ensureCurrentRecordKey()
    if let operationID, let sealed = sealedOwedHello, sealed.operationID == operationID,
      sealed.packet.message.groupEpoch == UInt64(state.epoch)
    {
      let packet = sealed.packet
      let authenticatedData = try makeAuthentication(
        packet.ordinal, packet.message.groupEpoch, packet.previousOrdinal)
      guard Self.inputDigest(plaintext, authenticatedData: authenticatedData) == sealed.inputDigest,
        packet.kind == kind, packet.recipient == recipient
      else { throw DeviceLayerError.invalid("MLS seal request conflict") }
      return packet
    }
    let known = operationID.flatMap { state.operations[$0] }.flatMap { state.sent[$0] } != nil
    let owedHello =
      operationID != nil && state.pendingHello?.message.msgId.rawValue == operationID
    if !known, !owedHello {
      // The add's owed final hello goes first; then seals retired from a closed epoch, in
      // their order, so sender order is kept.
      guard try await sealOwedHelloFirstHoldingGate() else {
        throw DeviceLayerError.membershipChangePending
      }
      try await resealRetiredHoldingGate(before: operationID)
    }
    return try await performSealHoldingGate(
      plaintext, operationID: operationID, kind: kind, recipient: recipient,
      superseding: operationID.flatMap { id in state.retired?.first { $0.operationID == id } },
      authenticatedData: makeAuthentication)
  }

  /// The final hello an add owes its joiner is the inviter's first seal in the epoch that add
  /// created: the joiner reads this sender from the start of that epoch, and the pairing link
  /// carries the hello alone. So while the hello is owed, no other seal may take a place before
  /// it; in a later epoch, which the joiner reads whole, it still goes first. Until the host
  /// completed the add this returns false and the caller seals nothing, as during the add
  /// itself; afterwards it seals the owed hello, which the pairing exchange or recovery then
  /// publishes and emits as before.
  private func sealOwedHelloFirstHoldingGate() async throws -> Bool {
    guard let owed = state.pendingHello else { return true }
    guard state.pendingCompletion == nil else { return false }
    guard case .device(let joiner) = owed.message.to,
      state.members.contains(where: { $0.deviceId == joiner })
    else {
      state.pendingHello = nil
      try await checkpoint(state.secretState)
      return true
    }
    _ = try await sealDeviceMessageHoldingGate(owed.message)
    return true
  }

  /// Seals again, in the installed epoch and under their operation IDs, the retired seals this
  /// group can rebuild: node messages whose recipient is still a member, and raw seals with a
  /// fixed AAD. A host-ordered seal waits for its host to seal that operation again; a message
  /// whose recipient left the group stays held. Stops before `operationID`, which its caller
  /// seals next.
  private func resealRetiredHoldingGate(before operationID: String?) async throws {
    let current = UInt64(state.epoch)
    for entry in state.retired ?? [] {
      if let operationID, entry.operationID == operationID { break }
      guard entry.epoch < current, entry.kind == .rawNative,
        let held = state.opened[entry.ciphertextID]
      else { continue }
      let authentication: @Sendable (UInt64, UInt64, UInt64) throws -> Data
      if let recipient = entry.recipient {
        if case .device(let id) = recipient,
          !state.members.contains(where: { $0.deviceId == id })
        {
          continue
        }
        let groupID = state.groupID
        let sender = identity.deviceID
        authentication = { ordinal, epoch, previous in
          try Self.nodeAuthentication(
            groupID: groupID, epoch: epoch, ordinal: ordinal, previous: previous,
            sender: sender, recipient: recipient)
        }
      } else {
        let fixed = held.authenticatedData
        authentication = { _, _, _ in fixed }
      }
      _ = try await performSealHoldingGate(
        held.plaintext, operationID: entry.operationID, kind: entry.kind,
        recipient: entry.recipient, superseding: entry, authenticatedData: authentication)
    }
  }

  /// Seals the retired seals this group can rebuild (see `resealRetiredHoldingGate`), so that
  /// the host's next publication of the pending feed carries them. Nothing happens while a
  /// membership change is pending; an owed final hello is sealed before them.
  func resealRetiredApplications() async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireAvailable()
    guard state.active, !state.joiningClient, state.retired?.isEmpty == false,
      state.pendingAdd == nil, state.pendingRequest == nil
    else { return }
    try await ensureCurrentRecordKey()
    guard try await sealOwedHelloFirstHoldingGate() else { return }
    try await resealRetiredHoldingGate(before: nil)
  }

  private func performSealHoldingGate(
    _ plaintext: Data, operationID: String?, kind: DeviceSealedApplication.Kind,
    recipient: DeviceAddress?, superseding: RetiredSeal?,
    authenticatedData makeAuthentication: @Sendable (UInt64, UInt64, UInt64) throws -> Data
  ) async throws -> DeviceSealedApplication {
    guard plaintext.count <= 64 * 1024,
      operationID.map({ !$0.isEmpty && $0.utf8.count <= 256 }) ?? true
    else { throw DeviceLayerError.invalid("MLS application envelope limit") }
    let existing = operationID.flatMap { state.operations[$0] }.flatMap { state.sent[$0] }
    let ordinal = existing?.packet.ordinal ?? state.nextApplicationOrdinal
    let epoch = existing?.packet.message.groupEpoch ?? UInt64(state.epoch)
    let previous = existing?.packet.previousOrdinal ?? state.previousApplicationOrdinal
    let authenticatedData = try makeAuthentication(ordinal, epoch, previous)
    guard authenticatedData.count <= 4_096 else {
      throw DeviceLayerError.invalid("MLS application envelope limit")
    }
    let digest = Self.inputDigest(plaintext, authenticatedData: authenticatedData)
    if let existing {
      guard existing.inputDigest == digest, existing.packet.kind == kind,
        existing.packet.recipient == recipient
      else { throw DeviceLayerError.invalid("MLS seal request conflict") }
      return existing.packet
    }
    if let superseding {
      // The same operation is sealed again only with the plaintext its retired seal holds. A
      // host-ordered envelope may name its epoch, so its host supplies the plaintext for the
      // new one: the retired seal was never accepted or emitted, so nothing can apply both.
      guard let held = state.opened[superseding.ciphertextID],
        held.plaintext == plaintext || kind == .orderedTransport,
        superseding.kind == kind, superseding.recipient == recipient
      else { throw DeviceLayerError.invalid("MLS seal request conflict") }
    }
    guard ordinal < UInt64.max else { throw DeviceLayerError.invalid("MLS send ordinal exhausted") }
    try requireReceiptCapacity(
      addingBytes: 2 * plaintext.count + 3 * authenticatedData.count + 2_048, addingCount: 2)
    let transition: MLSStateTransition<MLSSealedMessage>
    do {
      transition = try await mls.sealAndSnapshot(plaintext, authenticatedData: authenticatedData)
    } catch {
      persistenceFailed = true
      throw error
    }
    let message = transition.value
    guard message.ciphertext.count <= 70_000, message.groupEpoch == epoch else {
      persistenceFailed = true
      throw DeviceLayerError.invalid("MLS ciphertext envelope limit")
    }
    do {
      try requireReceiptCapacity(
        addingBytes: message.ciphertext.count + plaintext.count + 2 * authenticatedData.count,
        addingCount: 2)
    } catch {
      persistenceFailed = true
      throw error
    }
    let key = Self.ciphertextKey(message.ciphertext)
    let packet = DeviceSealedApplication(
      message: message, ordinal: ordinal, previousOrdinal: state.previousApplicationOrdinal,
      authenticatedData: authenticatedData, kind: kind, recipient: recipient)
    state.sent[ordinal] = SentApplication(
      inputDigest: digest, ciphertextID: key, packet: packet,
      operationID: operationID, receiptPending: operationID != nil)
    state.sourceSeals[key] = ordinal
    if let operationID { state.operations[operationID] = ordinal }
    state.nextApplicationOrdinal = ordinal + 1
    state.previousApplicationOrdinal = ordinal
    state.opened[key] = MLSOpenedMessage(
      plaintext: plaintext, authenticatedData: authenticatedData,
      sender: identity.peer.mlsCredential, groupEpoch: message.groupEpoch)
    let route = DeviceApplicationRouting(
      sender: identity.deviceID, epoch: epoch, ordinal: ordinal,
      previousOrdinal: packet.previousOrdinal, kind: kind, recipient: recipient)
    state.openedRoutes[key] = route
    state.received[epoch, default: [:]][identity.deviceID] = ordinal
    do {
      state.receivedDigests[epoch, default: [:]][identity.deviceID] =
        try DeviceApplicationFeedDigest.advancing(
          state.receivedDigests[epoch]?[identity.deviceID] ?? DeviceApplicationFeedDigest.initial,
          sender: identity.peer, application: packet)
    } catch {
      persistenceFailed = true
      throw error
    }
    pendingBytes += message.ciphertext.count + plaintext.count + 2 * authenticatedData.count
    if let operationID, state.pendingHello?.message.msgId.rawValue == operationID {
      state.pendingHello = nil
      sealedOwedHello = (operationID, packet, digest)
    }
    if let superseding {
      // The plaintext now lives under the new seal: the retired receipt ends in this checkpoint.
      state.retired?.removeAll { $0.ciphertextID == superseding.ciphertextID }
      if let old = state.opened.removeValue(forKey: superseding.ciphertextID) {
        pendingBytes -= old.plaintext.count + old.authenticatedData.count
      }
      state.openedRoutes.removeValue(forKey: superseding.ciphertextID)
      if state.deferredConsumption.remove(superseding.ciphertextID) != nil {
        state.deferredConsumption.insert(key)
      }
    }
    try await checkpoint(transition.secretState)
    availableOpened.insert(key)
    availableRoutes[key] = route
    if let superseding {
      availableOpened.remove(superseding.ciphertextID)
      availableRoutes.removeValue(forKey: superseding.ciphertextID)
    }
    feedSink.yield(ordinal)
    return packet
  }

  /// Low-level native open with a durable plaintext receipt. Production carriers use the
  /// ordered feed API; a receipt is not a second decryption or a domain-delivery ACK.
  public func openApplication(_ ciphertext: Data) async throws -> MLSOpenedMessage {
    await gate.acquire()
    defer { gate.release() }
    return try await openHoldingGate(ciphertext)
  }

  private func openHoldingGate(_ ciphertext: Data) async throws -> MLSOpenedMessage {
    try requireActive()
    guard !ciphertext.isEmpty, ciphertext.count <= 70_000 else {
      throw DeviceLayerError.invalid("MLS ciphertext envelope limit")
    }
    let key = Self.ciphertextKey(ciphertext)
    if let existing = state.opened[key] { return existing }
    if availableConsumed.contains(key) { throw DeviceApplicationFeedError.alreadyConsumed }
    try requireReceiptCapacity(addingBytes: ciphertext.count)
    let transition = try await nativeOpenHoldingGate(ciphertext)
    state.opened[key] = transition.value
    pendingBytes += transition.value.plaintext.count + transition.value.authenticatedData.count
    try await checkpoint(transition.secretState)
    availableOpened.insert(key)
    return transition.value
  }

  private func nativeOpenHoldingGate(_ ciphertext: Data) async throws -> MLSStateTransition<
    MLSOpenedMessage
  > {
    do {
      return try await mls.openAndSnapshot(ciphertext)
    } catch let error as MLSError {
      switch error {
      case .invalidInput, .invalidMessage, .authenticationFailed, .epochMismatch:
        break  // Native rejects these on its clone before installing a ratchet.
      default:
        persistenceFailed = true  // A snapshot/ABI/storage failure may follow a successful open.
      }
      throw error
    } catch {
      persistenceFailed = true
      throw error
    }
  }

  /// Every participant opens the complete sender sequence, including packets addressed to
  /// another member. Missing predecessors are retained encrypted and survive process death.
  public func openOrderedApplication(_ delivery: DeviceApplicationFeedDelivery) async throws
    -> GroupApplicationReceipt?
  {
    await gate.acquire()
    defer { gate.release() }
    return try await openOrderedHoldingGate(delivery)
  }

  private func openOrderedHoldingGate(_ delivery: DeviceApplicationFeedDelivery) async throws
    -> GroupApplicationReceipt?
  {
    try requireActive()
    let packet = delivery.application
    let epoch = packet.message.groupEpoch
    let sender = delivery.sender.deviceID
    guard packet.ordinal > 0, packet.previousOrdinal < packet.ordinal,
      packet.previousOrdinal == 0 || packet.ordinal == packet.previousOrdinal + 1,
      !packet.message.ciphertext.isEmpty, packet.message.ciphertext.count <= 70_000,
      packet.authenticatedData.count <= 4_096,
      epoch <= UInt64(state.epoch)
    else { throw DeviceApplicationFeedError.conflictingPublication }
    if packet.kind == .rawNative, let recipient = packet.recipient {
      guard
        packet.authenticatedData
          == (try Self.nodeAuthentication(
            groupID: state.groupID, epoch: epoch, ordinal: packet.ordinal,
            previous: packet.previousOrdinal, sender: sender, recipient: recipient))
      else { throw DeviceApplicationFeedError.conflictingPublication }
    }
    let route = DeviceApplicationRouting(
      sender: sender, epoch: epoch, ordinal: packet.ordinal,
      previousOrdinal: packet.previousOrdinal, kind: packet.kind, recipient: packet.recipient)
    let id = Self.ciphertextKey(packet.message.ciphertext)
    // Opening and routing were checkpointed together. A host may still own this receipt
    // after the epoch's exporter, roster and receive cursor have been deliberately retired.
    if let opened = state.opened[id], let retainedRoute = state.openedRoutes[id] {
      guard retainedRoute == route, opened.sender == delivery.sender.mlsCredential,
        opened.groupEpoch == epoch, opened.authenticatedData == packet.authenticatedData
      else { throw DeviceApplicationFeedError.conflictingPublication }
      return GroupApplicationReceipt(id: id, opened: opened, routing: retainedRoute)
    }
    let peers: [DevicePeer]
    if epoch == UInt64(state.epoch) {
      peers = try state.members.map {
        try DevicePeer(deviceID: $0.deviceId, publicKeys: $0.publicKeys)
      }
    } else if let key = availableRecordKeys[epoch] {
      peers = key.members
    } else {
      throw DeviceApplicationFeedError.unavailable
    }
    guard peers.contains(delivery.sender) else { throw DeviceLayerError.unknownPeer }
    // A closed epoch accepted nothing above its cutoffs. A seal above one was retired by its
    // sender, which seals that operation again in a later epoch: opening it here as well
    // would apply the message twice.
    if let closed = state.completedEpochs[epoch], packet.ordinal > (closed.cutoffs[sender] ?? 0) {
      throw DeviceApplicationFeedError.conflictingPublication
    }
    let cursor = state.received[epoch]?[sender] ?? 0
    if packet.ordinal <= cursor {
      if availableConsumed.contains(id), state.spentRoutes[id] == route { return nil }
      throw DeviceApplicationFeedError.conflictingPublication
    }
    let waitingID = Self.waitingID(epoch: epoch, sender: sender, ordinal: packet.ordinal)
    if packet.previousOrdinal != cursor {
      if let prior = state.waiting[waitingID] {
        guard prior == delivery else { throw DeviceApplicationFeedError.conflictingPublication }
      } else {
        try requireReceiptCapacity(
          addingBytes: packet.message.ciphertext.count + packet.authenticatedData.count)
        state.waiting[waitingID] = delivery
        pendingBytes += packet.message.ciphertext.count + packet.authenticatedData.count
        try await checkpoint(state.secretState)
      }
      throw DeviceApplicationFeedError.missingPredecessor(
        sender: sender, epoch: epoch, expected: cursor, actual: packet.previousOrdinal)
    }
    if let waiting = state.waiting[waitingID], waiting != delivery {
      throw DeviceApplicationFeedError.conflictingPublication
    }
    let opened: MLSOpenedMessage
    let secret: Data
    if let cached = state.opened[id] {
      opened = cached
      secret = state.secretState
    } else {
      let replacingWaiting = state.waiting[waitingID] != nil
      try requireReceiptCapacity(
        addingBytes: replacingWaiting ? 0 : packet.message.ciphertext.count,
        addingCount: replacingWaiting ? 0 : 1)
      let transition = try await nativeOpenHoldingGate(packet.message.ciphertext)
      opened = transition.value
      secret = transition.secretState
    }
    guard opened.sender == delivery.sender.mlsCredential, opened.groupEpoch == epoch,
      opened.authenticatedData == packet.authenticatedData
    else {
      // The native clone may already be installed. No payload escaped; only reopening the
      // last durable checkpoint may resume after a sender/header binding violation.
      persistenceFailed = true
      throw DeviceApplicationFeedError.conflictingPublication
    }
    if state.opened[id] == nil {
      state.opened[id] = opened
      pendingBytes += opened.plaintext.count + opened.authenticatedData.count
    }
    state.openedRoutes[id] = route
    state.received[epoch, default: [:]][sender] = packet.ordinal
    do {
      state.receivedDigests[epoch, default: [:]][sender] =
        try DeviceApplicationFeedDigest.advancing(
          state.receivedDigests[epoch]?[sender] ?? DeviceApplicationFeedDigest.initial,
          sender: delivery.sender, application: packet)
    } catch {
      persistenceFailed = true
      throw error
    }
    if let waiting = state.waiting.removeValue(forKey: waitingID) {
      pendingBytes -=
        waiting.application.message.ciphertext.count + waiting.application.authenticatedData.count
    }
    try await checkpoint(secret)
    availableOpened.insert(id)
    availableRoutes[id] = route
    for sink in openedSinks.values { sink.yield() }
    return GroupApplicationReceipt(id: id, opened: opened, routing: route)
  }

  /// Wake-ups for a host that retains a carrier frame whose predecessor was missing. Each call
  /// returns its own latest-only stream. A value arrives after this group has checkpointed a
  /// newly opened ordered application from any path (a live link, feed catch-up or another
  /// host); the stream ends when the group closes. A wake-up names no position and is not a
  /// receipt: the host offers its retained frames again, and every ordering and replay check
  /// runs on them as on first arrival.
  public func openedApplicationUpdates() -> AsyncStream<Void> {
    let (updates, sink) = AsyncStream.makeStream(
      of: Void.self, bufferingPolicy: .bufferingNewest(1))
    guard !persistenceFailed else {
      sink.finish()
      return updates
    }
    let id = UUID()
    openedSinks[id] = sink
    sink.onTermination = { [weak self] _ in Task { await self?.removeOpenedSink(id) } }
    return updates
  }

  private func removeOpenedSink(_ id: UUID) { openedSinks[id] = nil }

  /// Opens/checkpoints the current epoch's complete accepted prefix without requiring closure.
  /// Exact cutoffs/digests must match; opened plaintext remains pending for its domain consumer.
  /// The reader runs under the mutation gate and must not reenter it or dispatch consumers.
  public func catchUpApplicationFeed(using reader: DeviceApplicationEpochReader) async throws {
    await gate.acquire()
    defer { gate.release() }
    try await drainApplicationEpoch(using: reader, requiresClosed: false)
  }

  /// Whether this device's seals of `epoch` above an open `cutoff` are exactly its seals not
  /// yet published, each following the one before from the cutoff on, and whether they extend
  /// the boundary's own `digest` to this device's own: then the authority simply has not
  /// accepted them yet.
  private func ownSealsAwaitPublication(epoch: UInt64, cutoff: UInt64, digest: Data) throws
    -> Bool
  {
    let tail = state.sent.values.lazy
      .filter {
        $0.feedPending && $0.packet.message.groupEpoch == epoch && $0.packet.ordinal > cutoff
      }
      .map(\.packet).sorted { $0.ordinal < $1.ordinal }
    var last = cutoff
    var running = digest
    for packet in tail {
      guard packet.previousOrdinal == last else { return false }
      running = try DeviceApplicationFeedDigest.advancing(
        running, sender: identity.peer, application: packet)
      last = packet.ordinal
    }
    return !tail.isEmpty && last == (state.received[epoch]?[identity.deviceID] ?? 0)
      && running
        == (state.receivedDigests[epoch]?[identity.deviceID] ?? DeviceApplicationFeedDigest.initial)
  }

  private func drainApplicationEpoch(
    using reader: DeviceApplicationEpochReader, requiresClosed: Bool = true
  ) async throws {
    try requireActive()
    let info = try await mls.info()
    guard info.epoch == UInt64(state.epoch), info.groupID == Data(state.groupID.utf8) else {
      persistenceFailed = true
      throw DeviceApplicationFeedError.incompleteBoundary
    }
    let peers = try state.members.map {
      try DevicePeer(deviceID: $0.deviceId, publicKeys: $0.publicKeys)
    }
    let request = DeviceApplicationEpochRequest(
      groupID: state.groupID, epoch: info.epoch, groupContext: info.groupContext,
      members: peers, after: state.received[info.epoch] ?? [:],
      afterDigests: state.receivedDigests[info.epoch] ?? [:], requiresClosed: requiresClosed)
    let feed = try await reader(request)
    let boundary = feed.boundary
    let memberIDs = Set(peers.map(\.deviceID))
    guard boundary.groupID == state.groupID, boundary.epoch == info.epoch,
      !requiresClosed || boundary.isClosed,
      Set(boundary.cutoffs.keys).isSubset(of: memberIDs),
      Set(boundary.digests.keys).isSubset(of: memberIDs),
      boundary.groupContext == info.groupContext
        || (boundary.groupContext == nil && boundary.cutoffs.values.allSatisfy { $0 == 0 })
    else { throw DeviceApplicationFeedError.incompleteBoundary }
    if let completed = state.completedEpochs[info.epoch], completed != boundary {
      throw DeviceApplicationFeedError.conflictingPublication
    }
    // This device's own seals above an open cutoff are on their way to the authority: another
    // sealer of this device (a host transport) publishes them after its seal. That is no
    // recovery: the others' feeds are read as usual and ours is left as it is, once the seals
    // above the cutoff are exactly this device's unpublished ones, chained from the boundary's
    // own digest. Anything else means the authority lost a seal it had accepted.
    var ownAheadOfOpenCutoff = false
    for peer in peers {
      let cursor = state.received[info.epoch]?[peer.deviceID] ?? 0
      let cutoff = boundary.cutoffs[peer.deviceID] ?? 0
      if cursor > cutoff {
        if peer.deviceID == identity.deviceID {
          // An open boundary only says "not accepted yet"; a closed one says "never".
          guard boundary.isClosed else {
            guard
              try ownSealsAwaitPublication(
                epoch: info.epoch, cutoff: cutoff,
                digest: boundary.digests[peer.deviceID] ?? DeviceApplicationFeedDigest.initial)
            else { throw DeviceApplicationFeedError.incompleteBoundary }
            ownAheadOfOpenCutoff = true
            continue
          }
          try await retireUnaccepted(
            epoch: info.epoch, cutoff: cutoff,
            digest: boundary.digests[peer.deviceID] ?? DeviceApplicationFeedDigest.initial)
          continue
        }
        throw DeviceApplicationFeedError.conflictingPublication
      }
    }
    let deliveries = feed.deliveries.sorted {
      if $0.sender.deviceID != $1.sender.deviceID {
        return $0.sender.deviceID.rawValue < $1.sender.deviceID.rawValue
      }
      return $0.application.ordinal < $1.application.ordinal
    }
    for delivery in deliveries {
      guard delivery.application.message.groupEpoch == info.epoch,
        delivery.application.ordinal <= (boundary.cutoffs[delivery.sender.deviceID] ?? 0)
      else { throw DeviceApplicationFeedError.incompleteBoundary }
      _ = try await openOrderedHoldingGate(delivery)
    }
    for peer in peers {
      if ownAheadOfOpenCutoff, peer.deviceID == identity.deviceID { continue }
      let cursor = state.received[info.epoch]?[peer.deviceID] ?? 0
      let expected = boundary.cutoffs[peer.deviceID] ?? 0
      guard cursor == expected,
        (state.receivedDigests[info.epoch]?[peer.deviceID] ?? DeviceApplicationFeedDigest.initial)
          == (boundary.digests[peer.deviceID] ?? DeviceApplicationFeedDigest.initial)
      else { throw DeviceApplicationFeedError.incompleteBoundary }
    }
    guard !state.waiting.values.contains(where: { $0.application.message.groupEpoch == info.epoch })
    else {
      throw DeviceApplicationFeedError.incompleteBoundary
    }
    if boundary.isClosed {
      let own = boundary.cutoffs[identity.deviceID] ?? 0
      if own > state.acceptedApplicationOrdinal { try await acknowledgeFeedHoldingGate(own) }
    }
    if boundary.isClosed, state.completedEpochs[info.epoch] == nil {
      state.completedEpochs[info.epoch] = boundary
      try await checkpoint(state.secretState)
    }
  }

  /// The closed boundary of `epoch` proves which own seals the authority accepted. Those above
  /// its cutoff can never be accepted there and were never emitted, so they leave the feed and
  /// this device's own cursor and digest return to the boundary, in one checkpoint. Their
  /// plaintext receipts stay until the same operations are sealed again. The boundary digest
  /// extended by the retired packets must reproduce this device's own digest, else nothing
  /// changes.
  private func retireUnaccepted(epoch: UInt64, cutoff: UInt64, digest boundaryDigest: Data)
    async throws
  {
    let tail = state.sent.values.filter {
      $0.feedPending && $0.packet.message.groupEpoch == epoch && $0.packet.ordinal > cutoff
    }.sorted { $0.packet.ordinal < $1.packet.ordinal }
    var digest = boundaryDigest
    for seal in tail {
      digest = try DeviceApplicationFeedDigest.advancing(
        digest, sender: identity.peer, application: seal.packet)
    }
    guard let last = tail.last?.packet.ordinal,
      last == state.received[epoch]?[identity.deviceID],
      digest == state.receivedDigests[epoch]?[identity.deviceID],
      tail.allSatisfy({ state.opened[$0.ciphertextID] != nil })
    else { throw DeviceApplicationFeedError.conflictingPublication }
    if cutoff > state.acceptedApplicationOrdinal { try await acknowledgeFeedHoldingGate(cutoff) }
    for seal in tail {
      state.retired =
        (state.retired ?? []) + [
          RetiredSeal(
            ciphertextID: seal.ciphertextID, operationID: seal.operationID,
            kind: seal.packet.kind, recipient: seal.packet.recipient, epoch: epoch)
        ]
      if let id = seal.operationID { state.operations.removeValue(forKey: id) }
      removeSent(seal.packet.ordinal, receipt: seal)
    }
    // Every own ordinal through the retired tail is now settled: accepted or retired.
    state.acceptedApplicationOrdinal = max(state.acceptedApplicationOrdinal, last)
    state.received[epoch, default: [:]][identity.deviceID] = cutoff
    state.receivedDigests[epoch, default: [:]][identity.deviceID] = boundaryDigest
    try await checkpoint(state.secretState)
  }

  /// Whether a consumed receipt belongs to a retired seal that can still be sealed again.
  private func awaitsReseal(_ id: String) -> Bool {
    guard let entry = state.retired?.first(where: { $0.ciphertextID == id }) else { return false }
    if case .device(let recipient)? = entry.recipient {
      return state.members.contains { $0.deviceId == recipient }
    }
    return true
  }

  private static func waitingID(epoch: UInt64, sender: DeviceID, ordinal: UInt64) -> String {
    "\(epoch):\(sender.rawValue):\(ordinal)"
  }

  /// Gate-free, fsynced native-processing evidence for authority cutoff/rekey callbacks.
  /// It says nothing about whether the payload's domain side effects were consumed.
  public func applicationWasProcessed(ciphertext: Data) throws -> Bool {
    try requireAvailable()
    let key = Self.ciphertextKey(ciphertext)
    return availableOpened.contains(key) || availableConsumed.contains(key)
  }

  /// Gate-free, checkpointed: whether this ciphertext is an own seal that a closed epoch left
  /// unaccepted and that still waits to be sealed again under its operation ID. False for an
  /// accepted seal whose receipt is merely unconsumed, and once the operation was sealed again.
  public func applicationAwaitsReseal(ciphertext: Data) throws -> Bool {
    try requireAvailable()
    return availableRetired.contains(Self.ciphertextKey(ciphertext))
  }

  /// Gate-free, checkpointed: the operation IDs of retired host-ordered seals that still wait
  /// for their host, in the order they were retired. Their host either seals each operation
  /// again or ends it with ``abandonRetired(operationID:)``.
  public func retiredOrderedOperations() throws -> [String] {
    try requireAvailable()
    return availableRetiredOrdered
  }

  private static func orderedOperations(_ retired: [RetiredSeal]?) -> [String] {
    (retired ?? []).compactMap { $0.kind == .orderedTransport ? $0.operationID : nil }
  }

  /// Ends a retired host-ordered seal that its host will never seal again: the retired entry
  /// and its held plaintext leave in one checkpoint. The seal was never accepted and never
  /// emitted, so nothing else can hold it. Any other kind of seal, or no such retired
  /// operation, changes nothing.
  public func abandonRetired(operationID: String) async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireAvailable()
    let ended = (state.retired ?? []).filter {
      $0.kind == .orderedTransport && $0.operationID == operationID
    }.map(\.ciphertextID)
    guard !ended.isEmpty else { return }
    state.retired?.removeAll { ended.contains($0.ciphertextID) }
    for id in ended {
      if let held = state.opened.removeValue(forKey: id) {
        pendingBytes -= held.plaintext.count + held.authenticatedData.count
      }
      state.openedRoutes.removeValue(forKey: id)
      state.deferredConsumption.remove(id)
    }
    try await checkpoint(state.secretState)
    for id in ended {
      availableOpened.remove(id)
      availableRoutes.removeValue(forKey: id)
    }
  }

  /// Reports retained checkpointed evidence that the host definitively consumed this item.
  /// Unlike native processing, consumption follows a host ACK; its bounded history may expire.
  public func applicationWasConsumed(ciphertext: Data) throws -> Bool {
    try requireAvailable()
    return availableConsumed.contains(Self.ciphertextKey(ciphertext))
  }

  /// Returns checkpointed routing for an unconsumed native inbox item without taking the
  /// mutation gate. Nil means no retained routing, not permission to discard a payload.
  public func applicationRouting(ciphertext: Data) throws -> DeviceApplicationRouting? {
    try requireAvailable()
    return availableRoutes[Self.ciphertextKey(ciphertext)]
  }

  /// Returns the complete roster for a checkpointed exporter epoch, including the local peer.
  /// Throws when inactive or outside retained key history; never substitutes the current roster.
  public func applicationMembers(epoch: UInt64) throws -> [DevicePeer] {
    try requireActive()
    guard let key = availableRecordKeys[epoch] else { throw DeviceApplicationFeedError.unavailable }
    return key.members
  }

  /// Returns an already-checkpointed unconsumed plaintext receipt without opening MLS again.
  /// Nil means no retained receipt or already consumed; it does not authorize domain effects.
  public func applicationReceipt(ciphertext: Data) throws -> GroupApplicationReceipt? {
    try requireAvailable()
    let id = Self.ciphertextKey(ciphertext)
    if availableConsumed.contains(id) { return nil }
    guard availableOpened.contains(id), let opened = state.opened[id] else { return nil }
    return GroupApplicationReceipt(id: id, opened: opened, routing: availableRoutes[id])
  }

  /// Replays inbox payloads after a kill between native checkpoint and the Node/store journal.
  /// A durable carrier may instead redeliver ciphertext through openApplication's exact cache.
  public func pendingApplicationReceipts() async throws -> [GroupApplicationReceipt] {
    await gate.acquire()
    defer { gate.release() }
    try requireAvailable()
    return state.opened.map {
      GroupApplicationReceipt(id: $0.key, opened: $0.value, routing: state.openedRoutes[$0.key])
    }
  }

  func acknowledgeOpened(receiptIDs: [String]) async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireAvailable()
    let delta = retireHoldingGate(receiptIDs)
    if delta.changed {
      try await checkpoint(state.secretState)
      publishRetirement(delta)
    }
  }

  /// The exact ciphertext is synchronized to the carrier outbox. Keep its full-feed record
  /// independently until the authority accepted it; an outbox write is not that acceptance.
  public func acknowledgeSealed(operationID: String) async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    guard let ordinal = state.operations[operationID] else { return }
    try await acknowledgeSealHoldingGate(ordinal)
  }

  /// Acknowledges a seal's durable carrier receipt by device-local ordinal, not authority feed
  /// acceptance. Removes its operation retry mapping but retains any unpublished full-feed item.
  public func acknowledgeSealed(ordinal: UInt64) async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    try await acknowledgeSealHoldingGate(ordinal)
  }

  private func acknowledgeSealHoldingGate(_ ordinal: UInt64) async throws {
    guard var receipt = state.sent[ordinal] else { return }
    if let id = receipt.operationID { state.operations.removeValue(forKey: id) }
    receipt.receiptPending = false
    if receipt.feedPending {
      state.sent[ordinal] = receipt
    } else {
      removeSent(ordinal, receipt: receipt)
    }
    try await checkpoint(state.secretState)
  }

  /// Recovers a kill after full-feed acceptance but before the raw Node's separate seal ACK.
  /// Ordered/unknown host receipts remain owned by their own durable carrier outboxes.
  func acknowledgePublishedNodeSeals() async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireAvailable()
    let ordinals = state.sent.compactMap { ordinal, receipt in
      !receipt.feedPending && receipt.receiptPending && receipt.packet.kind == .rawNative
        && receipt.packet.recipient != nil ? ordinal : nil
    }
    guard !ordinals.isEmpty else { return }
    for ordinal in ordinals {
      guard let receipt = state.sent[ordinal] else { continue }
      if let id = receipt.operationID { state.operations.removeValue(forKey: id) }
      removeSent(ordinal, receipt: receipt)
    }
    try await checkpoint(state.secretState)
  }

  /// The caller already synchronized the exact plaintext/application result to its own inbox.
  public func acknowledgeOpened(ciphertext: Data) async throws {
    try await acknowledgeOpened(ciphertexts: [ciphertext])
  }

  /// Call only after definitive domain handling is durable for every supplied ciphertext.
  /// Checkpoints receipt retirement and bounded consumed evidence; local seals still awaiting
  /// full-feed acceptance retain their plaintext and defer retirement until that acceptance.
  public func acknowledgeOpened(ciphertexts: [Data]) async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireAvailable()
    let delta = retireHoldingGate(ciphertexts.map(Self.ciphertextKey))
    if delta.changed {
      try await checkpoint(state.secretState)
      publishRetirement(delta)
    }
  }

  /// Returns all local full-feed records still awaiting authority acceptance, in seal order.
  /// Includes old-epoch and differently addressed packets; retrieval does not acknowledge them.
  public func pendingApplicationFeed() async throws -> [DeviceSealedApplication] {
    await gate.acquire()
    defer { gate.release() }
    try requireAvailable()
    var result: [DeviceSealedApplication] = []
    result.reserveCapacity(state.sent.count)
    for receipt in state.sent.values where receipt.feedPending { result.append(receipt.packet) }
    result.sort { $0.ordinal < $1.ordinal }
    return result
  }

  /// Signs an exact retained local seal against its checkpointed native context.
  /// Throws if the packet or epoch key is unavailable; does not publish or imply acceptance.
  public func applicationPublication(_ application: DeviceSealedApplication) async throws
    -> DeviceApplicationPublication
  {
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    guard state.sent[application.ordinal]?.packet == application,
      let key = availableRecordKeys[application.message.groupEpoch]
    else { throw DeviceApplicationFeedError.unavailable }
    return try DeviceApplicationPublication.signed(
      groupID: key.groupID, groupContext: key.groupContext, identity: identity,
      application: application)
  }

  /// Only a durably accepted *complete sender feed prefix* permits this acknowledgement.
  /// No opaque transport enqueue, recipient filter, or optimistic tail qualifies.
  public func acknowledgeApplicationFeed(throughOrdinal through: UInt64) async throws {
    await gate.acquire()
    defer { gate.release() }
    try requireActive()
    try await acknowledgeFeedHoldingGate(through)
  }

  private func acknowledgeFeedHoldingGate(_ through: UInt64) async throws {
    guard through < state.nextApplicationOrdinal else {
      throw DeviceApplicationFeedError.conflictingPublication
    }
    guard through > state.acceptedApplicationOrdinal else { return }
    var delayed: [String] = []
    var ordinal = state.acceptedApplicationOrdinal + 1
    while ordinal <= through {
      guard var receipt = state.sent[ordinal] else {
        throw DeviceApplicationFeedError.conflictingPublication
      }
      receipt.feedPending = false
      if state.deferredConsumption.contains(receipt.ciphertextID) {
        delayed.append(receipt.ciphertextID)
      }
      state.sent[ordinal] = receipt
      if !receipt.receiptPending { removeSent(ordinal, receipt: receipt) }
      ordinal += 1
    }
    state.acceptedApplicationOrdinal = through
    let delta = retireHoldingGate(delayed)
    try await checkpoint(state.secretState)
    publishRetirement(delta)
  }

  private func removeSent(_ ordinal: UInt64, receipt: SentApplication) {
    state.sent.removeValue(forKey: ordinal)
    state.sourceSeals.removeValue(forKey: receipt.ciphertextID)
    pendingBytes -= receipt.packet.message.ciphertext.count + receipt.packet.authenticatedData.count
  }

  private struct Retirement {
    var changed = false
    var added: [String] = []
    var evicted: [String] = []
  }

  private func retireHoldingGate(_ ids: [String]) -> Retirement {
    var delta = Retirement()
    var batch: [SavedState.Consumption] = []
    for id in ids {
      guard let opened = state.opened[id] else { continue }
      let unpublished = state.sourceSeals[id].flatMap { state.sent[$0]?.feedPending } == true
      if unpublished || awaitsReseal(id) {
        delta.changed = state.deferredConsumption.insert(id).inserted || delta.changed
        continue  // Preserve the original plaintext until its seal, or its re-seal, is accepted.
      }
      // A retired seal whose recipient left the group ends with its local consumption.
      state.retired?.removeAll { $0.ciphertextID == id }
      state.opened.removeValue(forKey: id)
      state.deferredConsumption.remove(id)
      batch.append(
        SavedState.Consumption(id: id, route: state.openedRoutes.removeValue(forKey: id)))
      delta.added.append(id)
      delta.changed = true
      pendingBytes -= opened.plaintext.count + opened.authenticatedData.count
    }
    delta.evicted = state.consume(batch)
    return delta
  }

  private func publishRetirement(_ delta: Retirement) {
    for id in delta.added {
      availableOpened.remove(id)
      availableRoutes.removeValue(forKey: id)
      availableConsumed.insert(id)
    }
    for id in delta.evicted { availableConsumed.remove(id) }
  }

  private func requireReceiptCapacity(addingBytes: Int, addingCount: Int = 1) throws {
    guard
      addingCount <= Self.maximumPendingReceipts - state.sent.count - state.opened.count
        - state.waiting.count,
      addingBytes <= Self.maximumPendingBytes - pendingBytes
    else { throw DeviceLayerError.invalid("unacknowledged MLS receipt capacity") }
  }

  private static func ciphertextKey(_ ciphertext: Data) -> String {
    SHA256.hash(data: ciphertext).map { String(format: "%02x", $0) }.joined()
  }

  private struct NodeApplicationAuthentication: Codable {
    var domain = DeviceGroup.nodeApplicationContext
    var groupID: String
    var epoch: UInt64
    var ordinal: UInt64
    var previous: UInt64
    var sender: DeviceID
    var recipient: DeviceAddress
  }

  private static func nodeAuthentication(
    groupID: String, epoch: UInt64, ordinal: UInt64, previous: UInt64,
    sender: DeviceID, recipient: DeviceAddress
  ) throws -> Data {
    switch recipient {
    case .device, .group: break
    default: throw DeviceApplicationFeedError.conflictingPublication
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(
      NodeApplicationAuthentication(
        groupID: groupID, epoch: epoch, ordinal: ordinal, previous: previous,
        sender: sender, recipient: recipient))
  }

  /// Nil denotes an explicit different/unknown host AAD, never permission to discard it.
  static func nodeMessage(_ receipt: GroupApplicationReceipt, groupID: String) throws
    -> DeviceMessage?
  {
    guard let route = receipt.routing, route.kind == .rawNative,
      let recipient = route.recipient
    else { return nil }
    guard receipt.opened.groupEpoch == route.epoch,
      receipt.opened.sender.deviceID == route.sender.rawValue,
      receipt.opened.authenticatedData
        == (try nodeAuthentication(
          groupID: groupID, epoch: route.epoch, ordinal: route.ordinal,
          previous: route.previousOrdinal, sender: route.sender, recipient: recipient))
    else { throw DeviceApplicationFeedError.conflictingPublication }
    let message = try ProtocolCoding.makeDecoder().decode(
      DeviceMessage.self, from: receipt.opened.plaintext)
    guard message.from == .device(route.sender), message.to == recipient else {
      throw DeviceApplicationFeedError.conflictingPublication
    }
    return message
  }

  private static func inputDigest(_ plaintext: Data, authenticatedData: Data) -> Data {
    var hash = SHA256()
    var length = UInt64(authenticatedData.count).bigEndian
    withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
    hash.update(data: authenticatedData)
    hash.update(data: plaintext)
    return Data(hash.finalize())
  }

  private static func validate(
    _ info: MLSGroupInfo, groupID: String, epoch: Int64, members: [DeviceListEntry]
  ) throws {
    let expected = try members.map {
      try DevicePeer(deviceID: $0.deviceId, publicKeys: $0.publicKeys).mlsCredential
    }
    guard info.groupID == Data(groupID.utf8), info.epoch == UInt64(exactly: epoch),
      Set(expected).count == expected.count, Set(info.members) == Set(expected),
      Set(members.map(\.leafIndex)).count == members.count,
      members.allSatisfy({ entry in
        guard let leaf = UInt32(exactly: entry.leafIndex) else { return false }
        return info.memberLeafIndices[entry.deviceId.rawValue] == leaf
      })
    else { throw DeviceLayerError.invalid("MLS authority roster mismatch") }
  }

  private static func entries(
    _ credentials: [MLSCredential], indices: [String: UInt32], known: [DeviceListEntry]
  ) throws -> [DeviceListEntry] {
    try credentials.map { credential in
      let id = try DeviceID(credential.deviceID)
      let peer = DevicePeer(
        deviceID: id, signingKey: credential.signingPublicKey,
        agreementKey: credential.agreementPublicKey)
      guard peer.signingKey.count == 32, peer.agreementKey.count == 32,
        let leaf = indices[credential.deviceID]
      else {
        throw DeviceLayerError.invalid("MLS roster identity")
      }
      if var existing = known.last(where: {
        $0.deviceId == id && (try? DevicePeer(deviceID: id, publicKeys: $0.publicKeys)) == peer
      }) {
        existing.leafIndex = Int(leaf)
        return existing
      }
      // Until signed display metadata arrives, expose only the authenticated opaque device ID,
      // never invent a human device name or platform.
      return try entry(
        for: peer, name: id.rawValue, platform: .unknown("unavailable"), leaf: Int(leaf))
    }.sorted { $0.leafIndex < $1.leafIndex }
  }

  /// Signs the local active roster and epoch for pairing/display metadata.
  /// This is neither a native MLS transition nor a fresh remote authority/lease statement.
  public func signedList() throws -> SignedDeviceList {
    try requireActive()
    return try sign(state.members, epoch: state.epoch)
  }

  private func sign(_ members: [DeviceListEntry], epoch: Int64) throws -> SignedDeviceList {
    let signature = try identity.sign(Self.statement(groupID: state.groupID, epoch: epoch, members))
    return SignedDeviceList(
      epoch: epoch, devices: members, signerDeviceId: identity.deviceID,
      signature: try Base64Bytes(signature.base64EncodedString()))
  }

  static func entry(for peer: DevicePeer, name: String, platform: DevicePlatform, leaf: Int) throws
    -> DeviceListEntry
  {
    DeviceListEntry(
      deviceId: peer.deviceID, name: try DeviceName(String(name.prefix(60))),
      platform: platform, publicKeys: try peer.publicKeys, leafIndex: leaf)
  }

  static func statement(groupID: String, epoch: Int64, _ members: [DeviceListEntry]) throws -> Data
  {
    struct Statement: Encodable {
      let purpose = "memoshi.device-list.v1"
      var groupId: String
      var epoch: Int64
      var devices: [DeviceListEntry]
    }
    return Data(
      try ProtocolCoding.canonicalText(
        of: Statement(groupId: groupID, epoch: epoch, devices: members)
      ).utf8)
  }

  static func verify(_ list: SignedDeviceList, groupID: String, signer: DevicePeer) -> Bool {
    guard let signature = Data(base64Encoded: list.signature.rawValue),
      let statement = try? statement(groupID: groupID, epoch: list.epoch, list.devices)
    else { return false }
    return signer.verify(signature, over: statement)
  }
}
