import CloudKit
import CryptoKit
import Foundation
import MemoshiDevice
import MemoshiMLS
import MemoshiProtocol

struct CloudSenderFeedCutoff: Codable, Hashable, Sendable {
  let sender: DeviceID
  let firstOrdinal: UInt64
  let lastOrdinal: UInt64
  let lastIdentifier: String?
  let chainDigest: Data
  let signature: Data?
}

/// This exact prior-epoch prefix is signed into the immutable NEXT membership head. Every
/// append conditionally changes the same group head, so a late upload cannot extend it.
struct CloudEpochFeedCutoff: Codable, Hashable, Sendable {
  let groupID: String
  let epoch: UInt64
  let groupContext: Data
  let senders: [CloudSenderFeedCutoff]
}

/// CloudKit writes here are real conditional transactions, not a mock store or a CKSyncEngine
/// last-write-wins retry. CKSyncEngine remains the mailbox's genuine fetch/state/token engine.
public actor CloudKitFeedAuthority {
  private weak var groups: CloudKitGroupAuthority?
  private let mailbox: CloudKitMailbox
  private let spool: CloudMailboxStore
  private let group: DeviceGroup
  private let identity: DeviceIdentity
  /// The in-flight flush that concurrent callers join. Its value names the outbox frames the
  /// authority will never accept.
  struct Flush: Sendable {
    let id: UUID
    let task: Task<Set<String>, any Error>
    /// Callers other than the first that wait for this flush.
    var joiners = 0
    /// Its only caller was cancelled and the task with it. Later callers wait for it to
    /// unwind and then flush afresh instead of sharing its cancellation.
    var abandoned = false
  }
  private(set) var flushing: Flush?
  private var closed = false
  private let maximumEpochRecords: UInt64 = 16_384

  /// The authority's answer for one frame of this device's own feed.
  enum Append: Equatable, Sendable {
    /// The record is in the feed: appended now, or found there as the same seal.
    case accepted
    /// The frame's epoch closed with this device's cutoff below its ordinal. The authority
    /// never accepted the frame and never will.
    case unaccepted
  }
  /// Replaces the CloudKit append, for tests that run the real outbox and flush against
  /// another real feed authority. Never set by the app.
  private let appender: (@Sendable (Data) async throws -> Append)?

  init(
    groups: CloudKitGroupAuthority?, mailbox: CloudKitMailbox, spool: CloudMailboxStore,
    group: DeviceGroup, identity: DeviceIdentity,
    append: (@Sendable (Data) async throws -> Append)? = nil
  ) {
    self.groups = groups
    self.mailbox = mailbox
    self.spool = spool
    self.group = group
    self.identity = identity
    appender = append
  }

  /// Node invokes this after its Native checkpoint and BEFORE any identical Noise fanout.
  /// A seal whose epoch closed before the authority accepted it is never rebased or uploaded
  /// here, and never reported as published: it is refused with
  /// `DeviceApplicationFeedError.unacceptedOldEpoch`, the answer on which the Node and
  /// DeviceGroup retire the seal and seal its message again in the installed epoch (D131).
  public func publish(_ application: DeviceSealedApplication) async throws {
    try requireOpen()
    let identifier = try await retainedFrame(application, groupID: await group.groupID).identifier
    var unaccepted = try await flushOutbox()
    if !unaccepted.contains(identifier), try await spool.containsOutgoing(identifier: identifier) {
      // The joined task may have captured both snapshots before this enqueue. Once it has
      // finished, one covering flush suffices; never retry a failed authority append here.
      try Task.checkCancellation()
      unaccepted = try await flushOutbox()
      let retained = try await spool.containsOutgoing(identifier: identifier)
      guard unaccepted.contains(identifier) || !retained else {
        throw AppleDeviceError.stateRecoveryRequired
      }
    }
    if unaccepted.contains(identifier) { throw DeviceApplicationFeedError.unacceptedOldEpoch }
  }

  /// Publishes snapshots of Native pending feed/spooled ciphertext in epoch and ordinal order,
  /// joining any in-flight flush. Appends use conditional cloud transactions, retain original bytes,
  /// and cap each sender/epoch at 16,384 records. Conflicts/capacity/save failures propagate;
  /// only successful appends clear their local outbox entries, not peer application cursors.
  ///
  /// A frame whose epoch closed without the authority accepting it does not fail the flush
  /// and does not hold back the frames behind it. It is never uploaded. It stays in the
  /// outbox while DeviceGroup still lists its seal as pending, because the group has not read
  /// that closed boundary yet, and is removed for good once the group has retired the seal.
  public func flush() async throws { _ = try await flushOutbox() }

  private func flushOutbox() async throws -> Set<String> {
    try requireOpen()
    if let running = flushing {
      if running.abandoned {
        _ = await running.task.result
        if flushing?.id == running.id { flushing = nil }
        return try await flushOutbox()
      }
      flushing?.joiners += 1
      defer { if flushing?.id == running.id { flushing = nil } }
      return try await running.task.value
    }
    let id = UUID()
    let task = Task { try await self.performFlush() }
    flushing = Flush(id: id, task: task)
    defer { if flushing?.id == id { flushing = nil } }
    // Other callers may join this task. Its first caller's cancellation therefore cancels it
    // only while nobody has joined; once shared it runs to its own outcome for every caller,
    // and otherwise only `close()` cancels it.
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      Task { await self.abandonFlush(id) }
    }
  }

  private func abandonFlush(_ id: UUID) {
    guard let running = flushing, running.id == id, running.joiners == 0 else { return }
    flushing?.abandoned = true
    running.task.cancel()
  }

  private func performFlush() async throws -> Set<String> {
    let pending = try await group.pendingApplicationFeed()
    let groupID = await group.groupID
    for application in pending { _ = try await retainedFrame(application, groupID: groupID) }
    // Ciphertext hashes are NOT sender-ratchet order. Publish every sender's exact predecessor
    // first; a crash leaves both the native pending feed and encrypted spool available.
    let outgoing = try await spool.outgoing().map { frame in
      (frame: frame, packet: try DeviceTransportPacket(decoding: frame.bytes))
    }.sorted {
      if $0.packet.groupEpoch != $1.packet.groupEpoch {
        return $0.packet.groupEpoch < $1.packet.groupEpoch
      }
      return $0.packet.header.ordinal < $1.packet.header.ordinal
    }
    var unaccepted: Set<String> = []
    var unacceptedOrdinals: Set<UInt64> = []
    for item in outgoing {
      try Task.checkCancellation()
      let outcome: Append
      if let appender {
        outcome = try await appender(item.frame.bytes)
      } else {
        outcome = try await append(item.frame.bytes)
      }
      switch outcome {
      case .accepted: try await spool.uploaded([item.frame.identifier])
      case .unaccepted:
        unaccepted.insert(item.frame.identifier)
        unacceptedOrdinals.insert(item.packet.header.ordinal)
        // The group is asked now, not from the snapshot above: it may have read the closed
        // boundary and retired the seal since. A retired seal's ordinal is never used again.
        if try await !group.pendingApplicationFeed().contains(item.packet.application()) {
          try await spool.discard([item.frame.identifier])
        }
      }
    }
    // Only an accepted prefix of the feed is acknowledged, never a seal the authority refused
    // or one after it.
    for application in pending {
      if unacceptedOrdinals.contains(application.ordinal) { break }
      try await group.acknowledgeApplicationFeed(throughOrdinal: application.ordinal)
    }
    return unaccepted
  }

  /// Device signatures are randomized, so signing a seal again yields a byte-different frame
  /// for the same immutable feed record. A seal keeps the first signed frame the durable outbox
  /// retains for its feed position; every later publish and flush reuses that frame.
  private func retainedFrame(_ application: DeviceSealedApplication, groupID: String) async throws
    -> DeviceCiphertext
  {
    let identity = identity
    let frame = try await spool.outgoing(
      groupID: groupID, epoch: application.message.groupEpoch, sender: identity.deviceID,
      ordinal: application.ordinal
    ) {
      DeviceCiphertext(
        bytes: try Self.packet(application, groupID: groupID, identity: identity).encoded())
    }
    guard try DeviceTransportPacket(decoding: frame.bytes).application() == application else {
      throw AppleDeviceError.conflictingReplay
    }
    return frame
  }

  static func packet(
    _ application: DeviceSealedApplication, groupID: String, identity: DeviceIdentity
  ) throws -> DeviceTransportPacket {
    let header: DeviceTransportHeader
    switch application.kind {
    case .orderedTransport:
      header = try DeviceTransportHeader(authenticatedData: application.authenticatedData)
      guard header.groupID == groupID, header.groupEpoch == application.message.groupEpoch,
        header.sender == identity.deviceID, header.ordinal == application.ordinal,
        header.kind == .orderedTransport
      else { throw AppleDeviceError.conflictingReplay }
    case .rawNative:
      header = DeviceTransportHeader(
        groupID: groupID, groupEpoch: application.message.groupEpoch, sender: identity.deviceID,
        recipient: nil, ordinal: application.ordinal, kind: .rawNative)
    }
    return try DeviceTransportPacket(
      header: header, previousOrdinal: application.previousOrdinal,
      ciphertext: application.message.ciphertext, authenticatedData: application.authenticatedData,
      nativeRecipient: application.recipient, identity: identity)
  }

  /// Whether the record stored at a packet's feed position is that same seal. Device signatures
  /// are randomized, so this compares the stored record's verified signature and every signed
  /// field, never raw bytes: a second signature over one seal is not a conflicting record.
  static func isAccepted(
    _ stored: Data?, as packet: DeviceTransportPacket, signer: DevicePeer
  ) -> Bool {
    guard let stored, let accepted = try? DeviceTransportPacket(decoding: stored),
      (try? accepted.verify(signer: signer)) != nil
    else { return false }
    return accepted.sealsSameContent(as: packet)
  }

  /// Whether a closed epoch left this ordinal unaccepted: its sender has a cutoff there and
  /// the ordinal is above it. A sender without a cutoff was no member of that epoch, which is
  /// not this case.
  static func isBeyondClosedCutoff(ordinal: UInt64, cutoff: UInt64?) -> Bool {
    cutoff.map { ordinal > $0 } ?? false
  }

  private func append(_ bytes: Data) async throws -> Append {
    try requireOpen()
    guard let groups else { throw AppleDeviceError.closed }
    let packet = try DeviceTransportPacket(decoding: bytes)
    try packet.verify(signer: identity.peer)
    let connection = try await mailbox.authorityContext()
    let (headRecord, head) = try await groups.feedHead()
    guard packet.header.groupID == head.groupID else { throw AppleDeviceError.conflictingReplay }
    let id = Self.recordID(packet.position, zone: connection.zone)
    if packet.groupEpoch < UInt64(head.epoch) {
      let boundary = try await groups.closedFeedBoundary(epoch: packet.groupEpoch)
      let cutoff = boundary.senders.first(where: { $0.sender == packet.header.sender })
      if Self.isBeyondClosedCutoff(ordinal: packet.header.ordinal, cutoff: cutoff?.lastOrdinal) {
        return .unaccepted
      }
      guard let cutoff, cutoff.firstOrdinal > 0, packet.header.ordinal >= cutoff.firstOrdinal,
        let accepted = try await CloudConditionalSave.read(id, in: connection.database),
        accepted.recordType == "MemoshiMLSMessage",
        Self.isAccepted(
          accepted.encryptedValues["mls"] as? Data, as: packet, signer: identity.peer)
      else {
        throw AppleDeviceError.stateRecoveryRequired
      }
      return .accepted  // Reconcile exact already-accepted data; never extend a closed epoch.
    }
    guard packet.groupEpoch == UInt64(head.epoch),
      let enrolled = head.members.first(where: { $0.deviceId == identity.deviceID }),
      try DevicePeer(deviceID: enrolled.deviceId, publicKeys: enrolled.publicKeys) == identity.peer
    else {
      throw AppleDeviceError.revoked
    }
    let feedID = Self.headID(
      groupID: head.groupID, epoch: packet.groupEpoch, sender: identity.deviceID,
      zone: connection.zone)
    let feedRecord = try await CloudConditionalSave.read(feedID, in: connection.database)
    let previous = try feedRecord.map {
      try decodeHead(
        $0, groupID: head.groupID, epoch: packet.groupEpoch, signer: identity.peer,
        context: head.groupContext)
    }
    if let existing = try await CloudConditionalSave.read(id, in: connection.database) {
      guard existing.recordType == "MemoshiMLSMessage",
        Self.isAccepted(
          existing.encryptedValues["mls"] as? Data, as: packet, signer: identity.peer),
        let previous, packet.header.ordinal >= previous.firstOrdinal,
        packet.header.ordinal <= previous.lastOrdinal
      else { throw AppleDeviceError.conflictingReplay }
      return .accepted
    }
    guard packet.previousOrdinal == (previous?.lastOrdinal ?? 0),
      packet.previousOrdinal == 0 || packet.header.ordinal - packet.previousOrdinal == 1
    else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    let first = previous?.firstOrdinal ?? packet.header.ordinal
    guard packet.header.ordinal >= first, packet.header.ordinal - first < maximumEpochRecords else {
      throw AppleDeviceError.invalidState("CloudKit native epoch feed capacity")
    }
    let unsigned = CloudSenderFeedCutoff(
      sender: identity.deviceID, firstOrdinal: first, lastOrdinal: packet.header.ordinal,
      lastIdentifier: DeviceCiphertext(bytes: bytes).identifier,
      chainDigest: try DeviceApplicationFeedDigest.advancing(
        previous?.chainDigest ?? DeviceApplicationFeedDigest.initial,
        sender: identity.peer, application: packet.application()), signature: nil)
    let signature = try identity.sign(
      Self.headStatement(
        unsigned, groupID: head.groupID, epoch: packet.groupEpoch, context: head.groupContext))
    let cutoff = CloudSenderFeedCutoff(
      sender: unsigned.sender, firstOrdinal: first, lastOrdinal: unsigned.lastOrdinal,
      lastIdentifier: unsigned.lastIdentifier, chainDigest: unsigned.chainDigest,
      signature: signature)
    let next = feedRecord ?? CKRecord(recordType: "MemoshiMLSFeedHead", recordID: feedID)
    next.encryptedValues["state"] = try JSONEncoder().encode(cutoff) as NSData
    let record = CKRecord(recordType: "MemoshiMLSMessage", recordID: id)
    record.encryptedValues["mls"] = bytes as NSData
    // A genuinely changed field is REQUIRED: an unchanged head may otherwise be omitted.
    headRecord.encryptedValues["feedFence"] = Data(UUID().uuidString.utf8) as NSData
    _ = try await CloudConditionalSave.save([headRecord, next, record], in: connection.database)
    return .accepted
  }

  func capture(record: CKRecord, head: CloudGroupHead) async throws -> CloudEpochFeedCutoff {
    try requireOpen()
    let connection = try await mailbox.authorityContext()
    var senders: [CloudSenderFeedCutoff] = []
    for member in head.members.sorted(by: { $0.deviceId.rawValue < $1.deviceId.rawValue }) {
      let signer = try DevicePeer(deviceID: member.deviceId, publicKeys: member.publicKeys)
      let id = Self.headID(
        groupID: head.groupID, epoch: UInt64(head.epoch), sender: member.deviceId,
        zone: connection.zone)
      if let item = try await CloudConditionalSave.read(id, in: connection.database) {
        senders.append(
          try decodeHead(
            item, groupID: head.groupID, epoch: UInt64(head.epoch), signer: signer,
            context: head.groupContext))
      } else {
        senders.append(
          CloudSenderFeedCutoff(
            sender: member.deviceId, firstOrdinal: 0, lastOrdinal: 0, lastIdentifier: nil,
            chainDigest: Data(), signature: nil))
      }
    }
    // The caller saves THIS head's changeTag atomically with the signed next head. An append,
    // even for a different sender, changes that tag and makes the membership transaction fail.
    return CloudEpochFeedCutoff(
      groupID: head.groupID, epoch: UInt64(head.epoch), groupContext: head.groupContext,
      senders: senders)
  }

  /// Safe while DeviceGroup's gate is held: only public signed chain/record data is consulted.
  public func read(_ request: DeviceApplicationEpochRequest) async throws
    -> DeviceApplicationEpochFeed
  {
    try requireOpen()
    if !request.requiresClosed { return try await readLive(request) }
    guard let groups else { throw AppleDeviceError.closed }
    let boundary = try await groups.closedFeedBoundary(epoch: request.epoch)
    return try await read(request, boundary: boundary, isClosed: true)
  }

  func readLive(_ request: DeviceApplicationEpochRequest) async throws -> DeviceApplicationEpochFeed
  {
    guard let groups else { throw AppleDeviceError.closed }
    let (record, head) = try await groups.feedHead()
    if UInt64(head.epoch) > request.epoch {
      let boundary = try await groups.closedFeedBoundary(epoch: request.epoch)
      return try await read(request, boundary: boundary, isClosed: true)
    }
    guard UInt64(head.epoch) == request.epoch else { throw AppleDeviceError.staleEpoch }
    let boundary = try await capture(record: record, head: head)
    return try await read(request, boundary: boundary, isClosed: false)
  }

  private func read(
    _ request: DeviceApplicationEpochRequest, boundary: CloudEpochFeedCutoff, isClosed: Bool
  ) async throws -> DeviceApplicationEpochFeed {
    guard request.groupID == boundary.groupID, request.epoch == boundary.epoch,
      request.groupContext == boundary.groupContext,
      Set(request.members.map(\.deviceID)) == Set(boundary.senders.map(\.sender))
    else {
      throw AppleDeviceError.conflictingReplay
    }
    let connection = try await mailbox.authorityContext()
    var deliveries: [DeviceApplicationFeedDelivery] = []
    var digests: [DeviceID: Data] = [:]
    var cutoffs: [DeviceID: UInt64] = [:]
    for cutoff in boundary.senders {
      guard let signer = request.members.first(where: { $0.deviceID == cutoff.sender }) else {
        throw AppleDeviceError.revoked
      }
      cutoffs[cutoff.sender] = cutoff.lastOrdinal
      let after = request.after[cutoff.sender] ?? 0
      digests[cutoff.sender] =
        cutoff.lastOrdinal == 0 ? DeviceApplicationFeedDigest.initial : cutoff.chainDigest
      let unacceptedTail = Self.isOwnUnacceptedTail(
        sender: cutoff.sender, after: after, cutoff: cutoff.lastOrdinal, isClosed: isClosed,
        local: identity.deviceID)
      guard after <= cutoff.lastOrdinal || unacceptedTail else {
        throw AppleDeviceError.conflictingReplay
      }
      if cutoff.lastOrdinal == 0 {
        guard cutoff.firstOrdinal == 0, after == 0 || unacceptedTail, cutoff.chainDigest.isEmpty
        else {
          throw AppleDeviceError.conflictingReplay
        }
        guard
          unacceptedTail || request.afterDigests[cutoff.sender] == nil
            || request.afterDigests[cutoff.sender] == DeviceApplicationFeedDigest.initial
        else {
          throw AppleDeviceError.conflictingReplay
        }
        continue
      }
      try verifyHead(
        cutoff, groupID: boundary.groupID, epoch: boundary.epoch, signer: signer,
        context: boundary.groupContext)
      guard cutoff.firstOrdinal > 0, cutoff.lastOrdinal >= cutoff.firstOrdinal,
        cutoff.lastOrdinal - cutoff.firstOrdinal < maximumEpochRecords
      else { throw AppleDeviceError.stateRecoveryRequired }
      // Verify the ENTIRE committed prefix, including already-opened records. The closing
      // committer signature binds this chain; a changed earlier record is not hidden by a tail.
      var chain = DeviceApplicationFeedDigest.initial
      if after == 0, let recorded = request.afterDigests[cutoff.sender], recorded != chain {
        throw AppleDeviceError.conflictingReplay
      }
      for ordinal in cutoff.firstOrdinal...cutoff.lastOrdinal {
        let position = DeviceSenderFeedPosition(
          groupID: boundary.groupID, groupEpoch: boundary.epoch, sender: cutoff.sender,
          ordinal: ordinal, previousOrdinal: 0)
        guard
          let record = try await CloudConditionalSave.read(
            Self.recordID(position, zone: connection.zone), in: connection.database),
          record.recordType == "MemoshiMLSMessage",
          let bytes = record.encryptedValues["mls"] as? Data
        else {
          throw AppleDeviceError.stateRecoveryRequired
        }
        let packet = try DeviceTransportPacket(decoding: bytes)
        try packet.verify(signer: signer)
        guard packet.header.groupID == boundary.groupID, packet.groupEpoch == boundary.epoch,
          packet.header.sender == cutoff.sender, packet.header.ordinal == ordinal,
          packet.previousOrdinal == (ordinal == cutoff.firstOrdinal ? 0 : ordinal - 1)
        else { throw AppleDeviceError.conflictingReplay }
        chain = try DeviceApplicationFeedDigest.advancing(
          chain, sender: signer, application: packet.application())
        if ordinal == after {
          guard request.afterDigests[cutoff.sender] == chain else {
            throw AppleDeviceError.conflictingReplay
          }
        }
        if ordinal == cutoff.lastOrdinal {
          guard DeviceCiphertext(bytes: bytes).identifier == cutoff.lastIdentifier,
            chain == cutoff.chainDigest
          else { throw AppleDeviceError.conflictingReplay }
        }
        if ordinal > after {
          guard deliveries.count < 16_384 else {
            throw AppleDeviceError.invalidState("CloudKit feed recovery capacity")
          }
          deliveries.append(
            DeviceApplicationFeedDelivery(sender: signer, application: packet.application()))
        }
      }
    }
    return DeviceApplicationEpochFeed(
      boundary: DeviceApplicationEpochBoundary(
        groupID: boundary.groupID, epoch: boundary.epoch, groupContext: boundary.groupContext,
        cutoffs: cutoffs, digests: digests, isClosed: isClosed),
      deliveries: deliveries)
  }

  /// A closed boundary proves which of this device's own seals the authority accepted. When
  /// this device's own cursor is above that cutoff, the seals beyond it were never accepted and
  /// never will be. The boundary is then still returned, with the accepted cutoff and digest
  /// and no deliveries for this sender, so that DeviceGroup can verify and retire that tail
  /// and seal it again in the next epoch (D131). A peer above its cutoff, and any cursor above
  /// an open boundary, are refused as before.
  static func isOwnUnacceptedTail(
    sender: DeviceID, after: UInt64, cutoff: UInt64, isClosed: Bool, local: DeviceID
  ) -> Bool {
    isClosed && sender == local && after > cutoff
  }

  private func decodeHead(
    _ record: CKRecord, groupID: String, epoch: UInt64, signer: DevicePeer, context: Data
  ) throws -> CloudSenderFeedCutoff {
    guard record.recordType == "MemoshiMLSFeedHead",
      let bytes = record.encryptedValues["state"] as? Data
    else { throw AppleDeviceError.stateRecoveryRequired }
    let result = try JSONDecoder().decode(CloudSenderFeedCutoff.self, from: bytes)
    try verifyHead(result, groupID: groupID, epoch: epoch, signer: signer, context: context)
    return result
  }

  private func verifyHead(
    _ cutoff: CloudSenderFeedCutoff, groupID: String, epoch: UInt64, signer: DevicePeer,
    context: Data
  ) throws {
    guard cutoff.sender == signer.deviceID, cutoff.firstOrdinal > 0,
      cutoff.lastOrdinal >= cutoff.firstOrdinal,
      cutoff.lastOrdinal - cutoff.firstOrdinal < maximumEpochRecords,
      cutoff.chainDigest.count == 32, cutoff.lastIdentifier != nil,
      let signature = cutoff.signature,
      signer.verify(
        signature,
        over: try Self.headStatement(cutoff, groupID: groupID, epoch: epoch, context: context))
    else {
      throw AppleDeviceError.conflictingReplay
    }
  }

  private static func headStatement(
    _ cutoff: CloudSenderFeedCutoff, groupID: String, epoch: UInt64, context: Data
  ) throws -> Data {
    struct Statement: Encodable {
      let domain: String
      let groupID: String
      let epoch: UInt64
      let context: Data
      let sender: DeviceID
      let first: UInt64
      let last: UInt64
      let identifier: String?
      let chainDigest: Data
    }
    return Data(
      try ProtocolCoding.canonicalText(
        of: Statement(
          domain: "memoshi.cloudkit.sender-feed.v1", groupID: groupID, epoch: epoch,
          context: context,
          sender: cutoff.sender, first: cutoff.firstOrdinal, last: cutoff.lastOrdinal,
          identifier: cutoff.lastIdentifier, chainDigest: cutoff.chainDigest)
      ).utf8)
  }

  static func recordID(_ position: DeviceSenderFeedPosition, zone: CKRecordZone.ID) -> CKRecord.ID {
    let key =
      "memoshi.feed.ordinal.v1\u{0}\(position.groupID)\u{0}\(position.groupEpoch)\u{0}\(position.sender.rawValue)\u{0}\(position.ordinal)"
    return CKRecord.ID(
      recordName: "m."
        + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined(),
      zoneID: zone)
  }

  private static func headID(
    groupID: String, epoch: UInt64, sender: DeviceID, zone: CKRecordZone.ID
  ) -> CKRecord.ID {
    let key = "\(groupID)\u{0}\(epoch)\u{0}\(sender.rawValue)"
    return CKRecord.ID(
      recordName: "feed."
        + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined(),
      zoneID: zone)
  }

  private func requireOpen() throws { guard !closed else { throw AppleDeviceError.closed } }
  /// Refuses future feed operations and cancels an in-flight flush without deleting durable
  /// pending ciphertext or closing the caller-owned mailbox, spool, or Native group.
  public func close() {
    closed = true
    flushing?.task.cancel()
  }
}

extension DeviceTransportPacket {
  func application() -> DeviceSealedApplication {
    DeviceSealedApplication(
      message: MLSSealedMessage(ciphertext: ciphertext, groupEpoch: groupEpoch),
      ordinal: header.ordinal,
      previousOrdinal: previousOrdinal, authenticatedData: nativeAuthenticatedData,
      kind: header.kind == .orderedTransport ? .orderedTransport : .rawNative,
      recipient: nativeRecipient)
  }
}
