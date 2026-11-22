import CloudKit
import Foundation
import MemoshiDevice
import MemoshiMLS
import MemoshiProtocol

/// The signed MLS commit and its authenticated committer are retained, not merely an epoch.
struct CloudGroupHead: Codable, Hashable, Sendable {
  let groupID: String
  let epoch: Int64
  let members: [DeviceListEntry]
  let revoked: [DeviceID]
  let groupContext: Data
  let committer: DevicePeer
  let commit: GroupCommit?
  let bootstrapSignature: Data?
  let previousFeed: CloudEpochFeedCutoff?
  let feedSignature: Data

  func feedStatement() throws -> Data {
    struct Statement: Encodable {
      let domain: String
      let groupID: String
      let epoch: Int64
      let groupContext: Data
      let previousFeed: CloudEpochFeedCutoff?
    }
    return Data(
      try ProtocolCoding.canonicalText(
        of: Statement(
          domain: "memoshi.cloudkit.epoch-feed-boundary.v1", groupID: groupID,
          epoch: epoch, groupContext: groupContext, previousFeed: previousFeed)
      ).utf8)
  }

  func signedFeed(identity: DeviceIdentity) throws -> Self {
    Self(
      groupID: groupID, epoch: epoch, members: members, revoked: revoked,
      groupContext: groupContext, committer: committer, commit: commit,
      bootstrapSignature: bootstrapSignature, previousFeed: previousFeed,
      feedSignature: try identity.sign(feedStatement()))
  }
}

/// An actual private-CloudKit authority. No local fake and no last-write-wins fallback exists.
/// Head + immutable signed commit are atomically saved under the fetched head's change tag.
public actor CloudKitGroupAuthority {
  private let mailbox: CloudKitMailbox
  private let group: DeviceGroup
  private let identity: DeviceIdentity
  private let groupID: String
  private var verifiedEpoch: Int64 = 0
  private var verifiedMembers: [DeviceListEntry]?
  private var verifiedValue: CloudGroupHead?
  private var verificationFloor: Int64 = 0
  private var verifiedCommits: [Int64: MLSOrderedCommit] = [:]
  private var verifiedRequests: [Int64: GroupCommit] = [:]
  private var verifiedHeads: [Int64: CloudGroupHead] = [:]
  private let stateDirectory: URL
  private var states: CloudKitStateAuthority?
  private var feeds: CloudKitFeedAuthority?
  private let spool: CloudMailboxStore
  private var closed = false

  /// Trust comes from DeviceGroup's durable native/QR Welcome anchor, never a fetched genesis.
  /// Construction performs no network operation or account setup.
  public init(
    mailbox: CloudKitMailbox, group: DeviceGroup, identity: DeviceIdentity,
    groupID: String, stateDirectory: URL, spool: CloudMailboxStore
  ) {
    self.mailbox = mailbox
    self.group = group
    self.identity = identity
    self.groupID = groupID
    self.stateDirectory = stateDirectory
    self.spool = spool
  }

  /// Returns the shared state authority, opening/recovering its encrypted local journal on first
  /// use. Closed owners throw; this accessor itself performs no CloudKit operation.
  public func stateRecords() throws -> CloudKitStateAuthority {
    guard !closed else { throw AppleDeviceError.closed }
    if let states { return states }
    let created = try CloudKitStateAuthority(
      groups: self, mailbox: mailbox, group: group, identity: identity, directory: stateDirectory)
    states = created
    return created
  }

  /// Returns the shared sender-feed authority without starting synchronization or publication.
  /// The group authority owns its lifecycle and refuses access after closure.
  public func applicationFeeds() throws -> CloudKitFeedAuthority {
    guard !closed else { throw AppleDeviceError.closed }
    if let feeds { return feeds }
    let created = CloudKitFeedAuthority(
      groups: self, mailbox: mailbox, spool: spool, group: group, identity: identity)
    feeds = created
    return created
  }

  /// Completes/resumes protected-state rekeying for this group's accepted membership commit.
  /// Call only after Native checkpoint/gate release and before the final pairing hello;
  /// persistence or authority failures propagate without resetting logical state.
  public func didCommit(_ commit: GroupCommit) async throws {
    guard commit.groupId == groupID else { throw AppleDeviceError.staleEpoch }
    try await stateRecords().didCommit(commit)
  }

  /// Permanently closes owned feed/state authorities and their local state journal.
  /// The caller-owned mailbox, spool, and Native group remain separate lifecycle owners.
  public func close() async {
    closed = true
    await feeds?.close()
    await states?.close()
    feeds = nil
    states = nil
  }

  /// Explicit first-device enrollment only. An existing head is verified, never overwritten.
  public func bootstrapIfAbsent() async throws {
    let context = try await mailbox.authorityContext()
    if try await CloudConditionalSave.read(headID(zone: context.zone), in: context.database) != nil
    {
      _ = try await verifiedHead()
      return
    }
    let anchor = try await group.authorityAnchor()
    let members = anchor.members
    guard anchor.groupID == groupID, anchor.epoch == 0, await group.epoch == 0,
      anchor.signer == identity.peer, members.count == 1,
      members[0].deviceId == identity.deviceID, !anchor.groupContext.isEmpty,
      try DevicePeer(deviceID: members[0].deviceId, publicKeys: members[0].publicKeys)
        == identity.peer
    else { throw AppleDeviceError.invalidState("CloudKit group bootstrap") }
    let signature = try identity.sign(
      Self.bootstrapStatement(
        groupID: groupID, members: members, groupContext: anchor.groupContext))
    let head = try CloudGroupHead(
      groupID: groupID, epoch: 0, members: members, revoked: [], groupContext: anchor.groupContext,
      committer: identity.peer, commit: nil, bootstrapSignature: signature,
      previousFeed: nil, feedSignature: Data()
    ).signedFeed(identity: identity)
    let record = CKRecord(recordType: "MemoshiMLSGroupHead", recordID: headID(zone: context.zone))
    let bytes = try JSONEncoder().encode(head)
    record.encryptedValues["state"] = bytes as NSData
    let initialIndex = try await stateRecords().initialIndex(headID: record.recordID)
    record.encryptedValues["stateIndex"] = initialIndex as NSData
    let root = CKRecord(
      recordType: "MemoshiMLSGroupCommit", recordID: commitID(0, zone: context.zone))
    root.encryptedValues["state"] = bytes as NSData
    let assignment = CKRecord(
      recordType: "MemoshiMLSIdentity", recordID: identityID(identity.deviceID, zone: context.zone))
    assignment.encryptedValues["admission"] = bytes as NSData
    do {
      _ = try await CloudConditionalSave.save([record, root, assignment], in: context.database)
    } catch let error as CKError where error.code == .serverRecordChanged {
      _ = try await verifiedHead()
      return
    }
    verifiedMembers = members
    verifiedValue = head
    verifiedHeads[0] = head
  }

  /// Authenticates a proposed transition and conditionally saves the membership head, immutable
  /// commit, and any identity assignment. The caller holds the Native mutation gate; local rekey
  /// intent is durable before the cloud CAS. A competing head returns `accepted == false`;
  /// exact already-accepted history is reconciled, while other authority/persistence errors throw.
  public func compareAndSwap(commit: GroupCommit) async throws -> GroupCommitResult {
    let context = try await mailbox.authorityContext()
    let (record, current) = try await verifiedHead()
    let authenticated = try AuthenticatedGroupCommit.decode(commit, committer: identity.peer)
    let ordered = try authenticated.orderedCommit
    // Reconcile an uncertain save against immutable authenticated history, even if a later
    // accepted membership change has already moved the head beyond this exact operation.
    if commit.groupId == groupID, verifiedRequests[authenticated.toEpoch] == commit {
      return GroupCommitResult(groupId: groupID, accepted: true, epoch: authenticated.toEpoch)
    }
    guard commit.groupId == groupID, commit.fromEpoch == current.epoch else {
      if verifiedCommits[authenticated.toEpoch] != nil {
        try await stateRecords().discardMembershipChange(commit)
      }
      return GroupCommitResult(groupId: groupID, accepted: false, epoch: current.epoch)
    }
    guard let enrolled = current.members.first(where: { $0.deviceId == identity.deviceID }),
      try DevicePeer(deviceID: enrolled.deviceId, publicKeys: enrolled.publicKeys) == identity.peer
    else { throw AppleDeviceError.revoked }
    try authenticated.validateTransition(from: current.members, revoked: current.revoked)
    let previousFeed = try await applicationFeeds().capture(record: record, head: current)
    let next = try CloudGroupHead(
      groupID: groupID, epoch: authenticated.toEpoch, members: authenticated.members,
      revoked: authenticated.revoked, groupContext: ordered.groupContext,
      committer: identity.peer, commit: commit, bootstrapSignature: nil,
      previousFeed: previousFeed, feedSignature: Data()
    ).signedFeed(identity: identity)
    // The Native mutation gate is held by the caller: only gate-free cached exporter/anchor
    // material is consulted here. Plaintext rekey work is fsynced BEFORE the membership CAS.
    try await stateRecords().prepareMembershipChange(
      head: record, commit: commit, target: UInt64(next.epoch), context: next.groupContext,
      baseContext: current.groupContext)
    let bytes = try JSONEncoder().encode(next)
    record.encryptedValues["state"] = bytes as NSData
    let immutable = CKRecord(
      recordType: "MemoshiMLSGroupCommit",
      recordID: commitID(next.epoch, zone: context.zone))
    immutable.encryptedValues["state"] = bytes as NSData
    var records = [record, immutable]
    if commit.change == .add {
      let id = identityID(commit.subjectDeviceId, zone: context.zone)
      guard try await CloudConditionalSave.read(id, in: context.database) == nil else {
        throw AppleDeviceError.invalidState("device identity already assigned or revoked")
      }
      let assignment = CKRecord(recordType: "MemoshiMLSIdentity", recordID: id)
      assignment.encryptedValues["admission"] = bytes as NSData
      // Never deleted, even after removal: revoked IDs cannot be reassigned by a later QR.
      records.append(assignment)
    }
    do {
      _ = try await CloudConditionalSave.save(records, in: context.database)
    } catch let error as CKError where error.code == .serverRecordChanged {
      let (_, winner) = try await verifiedHead()
      if verifiedRequests[authenticated.toEpoch] == commit {
        return GroupCommitResult(groupId: groupID, accepted: true, epoch: authenticated.toEpoch)
      }
      try await stateRecords().discardMembershipChange(commit)
      return GroupCommitResult(groupId: groupID, accepted: false, epoch: winner.epoch)
    }
    verifiedEpoch = next.epoch
    verifiedMembers = next.members
    verifiedValue = next
    verifiedCommits[next.epoch] = try authenticated.orderedCommit
    verifiedRequests[next.epoch] = commit
    verifiedHeads[next.epoch] = next
    return GroupCommitResult(groupId: groupID, accepted: true, epoch: next.epoch)
  }

  /// Returns authenticated full MLS records in strict epoch order. Callers apply them to the
  /// DeviceGroup before opening application messages from a newer epoch. A hole fails closed.
  public func orderedCommits(after epoch: UInt64, through target: UInt64? = nil) async throws
    -> [MLSOrderedCommit]
  {
    let (_, head) = try await verifiedHead()
    return try collectCommits(after: epoch, through: target ?? UInt64(head.epoch), head: head)
  }

  /// Returns the authenticated head plus contiguous commits strictly after `minimumEpoch`.
  /// The requested group/epoch must lie within the anchored verified chain; gaps, unavailable
  /// history, or a head older than the requested epoch throw. Callers apply commits themselves.
  public func snapshot(groupID: String, minimumEpoch: Int64) async throws -> AuthorityGroup {
    guard groupID == self.groupID, minimumEpoch >= 0 else { throw AppleDeviceError.staleEpoch }
    let (_, head) = try await verifiedHead()
    let commits = try collectCommits(
      after: UInt64(minimumEpoch), through: UInt64(head.epoch), head: head)
    return AuthorityGroup(
      groupID: groupID, epoch: head.epoch, members: head.members,
      commits: commits, groupContext: head.groupContext, revoked: head.revoked)
  }

  private func collectCommits(
    after epoch: UInt64, through target: UInt64, head: CloudGroupHead
  ) throws -> [MLSOrderedCommit] {
    guard epoch <= UInt64(Int64.max), target <= UInt64(head.epoch), target >= epoch,
      Int64(epoch) >= verificationFloor
    else { throw AppleDeviceError.staleEpoch }
    if epoch == target { return [] }
    var result: [MLSOrderedCommit] = []
    for nextEpoch in (Int64(epoch) + 1)...Int64(target) {
      guard let ordered = verifiedCommits[nextEpoch] else {
        throw AppleDeviceError.invalidState("CloudKit verified MLS commit gap")
      }
      result.append(ordered)
    }
    return result
  }

  func feedHead() async throws -> (CKRecord, CloudGroupHead) { try await verifiedHead() }

  func closedFeedBoundary(epoch: UInt64) async throws -> CloudEpochFeedCutoff {
    guard epoch < UInt64(Int64.max) else { throw AppleDeviceError.stateRecoveryRequired }
    if verifiedHeads[Int64(epoch) + 1] == nil { _ = try await verifiedHead() }
    guard epoch >= UInt64(verificationFloor),
      let next = verifiedHeads[Int64(epoch) + 1], let boundary = next.previousFeed,
      boundary.groupID == groupID, boundary.epoch == epoch
    else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    return boundary
  }

  /// Public historical credentials come only from the QR/native-anchored signed epoch chain.
  /// This authenticates routing order before a ciphertext can consume a Native sender ratchet.
  func signer(_ deviceID: DeviceID, at epoch: UInt64) async throws -> DevicePeer {
    guard epoch <= UInt64(Int64.max) else { throw AppleDeviceError.staleEpoch }
    if verifiedHeads[Int64(epoch)] == nil { _ = try await verifiedHead() }
    guard let head = verifiedHeads[Int64(epoch)],
      let member = head.members.first(where: { $0.deviceId == deviceID })
    else {
      throw AppleDeviceError.revoked
    }
    return try DevicePeer(deviceID: member.deviceId, publicKeys: member.publicKeys)
  }

  /// The lease CAS includes this exact, unchanged head as an atomic membership fence. Without
  /// it, a remote revocation could race a successful per-conversation lease grant at an old epoch.
  func membershipFence() async throws -> CKRecord {
    let (record, head) = try await verifiedHead()
    let native = try await group.groupInfo()
    guard native.isActive, native.epoch == UInt64(head.epoch),
      native.groupContext == head.groupContext,
      let member = head.members.first(where: { $0.deviceId == identity.deviceID }),
      try DevicePeer(deviceID: member.deviceId, publicKeys: member.publicKeys) == identity.peer
    else { throw AppleDeviceError.revoked }
    return record
  }

  /// Consult only after membershipFence has authenticated the current contiguous history.
  /// A newer Native epoch alone never proves that this exact request won its membership CAS.
  func acceptedMembership(_ commit: GroupCommit) throws -> (commit: GroupCommit, context: Data) {
    guard !closed, commit.groupId == groupID, commit.fromEpoch >= 0, commit.fromEpoch < Int64.max
    else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    let target = commit.fromEpoch + 1
    guard target >= verificationFloor, target <= verifiedEpoch, let head = verifiedHeads[target],
      let accepted = head.commit, accepted == commit
    else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    return (accepted, head.groupContext)
  }

  private func verifiedHead() async throws -> (CKRecord, CloudGroupHead) {
    let context = try await mailbox.authorityContext()
    guard
      let record = try await CloudConditionalSave.read(
        headID(zone: context.zone), in: context.database)
    else {
      throw AppleDeviceError.authorityUnavailable
    }
    let head = try decode(record)
    guard head.epoch >= verifiedEpoch else { throw AppleDeviceError.staleEpoch }
    if verifiedMembers == nil {
      let anchor = try await group.authorityAnchor()
      guard anchor.groupID == groupID, head.epoch >= anchor.epoch,
        let retained = try await CloudConditionalSave.read(
          commitID(anchor.epoch, zone: context.zone), in: context.database)
      else { throw AppleDeviceError.invalidState("CloudKit native authority anchor missing") }
      let anchored = try decode(retained)
      try verifyAnchor(anchored, anchor: anchor)
      // Awaited reads may interleave. Retain immutable per-epoch proofs and never move the
      // verification high-water mark backwards when a concurrent read already advanced it.
      if let previous = verifiedHeads[anchor.epoch], previous != anchored {
        throw AppleDeviceError.conflictingReplay
      }
      verifiedHeads[anchor.epoch] = anchored
      if verifiedMembers == nil {
        verifiedEpoch = anchor.epoch
        verificationFloor = anchor.epoch
        verifiedMembers = anchor.members
        verifiedValue = anchored
      }
    }
    if head.epoch > verifiedEpoch {
      for target in (verifiedEpoch + 1)...head.epoch {
        guard
          let item = try await CloudConditionalSave.read(
            commitID(target, zone: context.zone), in: context.database)
        else { throw AppleDeviceError.invalidState("CloudKit signed commit gap") }
        let step = try decode(item)
        guard step.epoch == target, let commit = step.commit,
          let previous = verifiedHeads[target - 1],
          let signer = previous.members.first(where: { $0.deviceId == step.committer.deviceID }),
          try DevicePeer(deviceID: signer.deviceId, publicKeys: signer.publicKeys) == step.committer
        else { throw AppleDeviceError.revoked }
        let authenticated = try AuthenticatedGroupCommit.decode(commit, committer: step.committer)
        try authenticated.validateTransition(from: previous.members, revoked: previous.revoked)
        try verifyFeedBoundary(step, previous: previous)
        let ordered = try authenticated.orderedCommit
        guard step.members == authenticated.members, step.revoked == authenticated.revoked,
          ordered.groupContext == step.groupContext
        else {
          throw AppleDeviceError.conflictingReplay
        }
        if let retained = verifiedHeads[target], retained != step {
          throw AppleDeviceError.conflictingReplay
        }
        verifiedHeads[target] = step
        verifiedRequests[target] = commit
        verifiedCommits[target] = ordered
        if target > verifiedEpoch {
          verifiedMembers = step.members
          verifiedEpoch = target
          verifiedValue = step
        }
      }
    }
    guard head.epoch >= verifiedEpoch else { throw AppleDeviceError.staleEpoch }
    guard head == verifiedHeads[head.epoch] else {
      throw AppleDeviceError.conflictingReplay
    }
    if let commit = head.commit {
      let authenticated = try AuthenticatedGroupCommit.decode(commit, committer: head.committer)
      guard authenticated.toEpoch == head.epoch, authenticated.members == head.members,
        authenticated.revoked == head.revoked,
        try authenticated.orderedCommit.groupContext == head.groupContext
      else {
        throw AppleDeviceError.conflictingReplay
      }
    } else if head.epoch != 0 {
      throw AppleDeviceError.invalidState("missing CloudKit MLS commit")
    }
    return (record, head)
  }

  private func verifyAnchor(_ head: CloudGroupHead, anchor: GroupAuthorityAnchor) throws {
    guard head.epoch == anchor.epoch, head.members == anchor.members,
      head.groupContext == anchor.groupContext, head.committer == anchor.signer
    else {
      throw AppleDeviceError.conflictingReplay
    }
    if anchor.epoch == 0 {
      guard head.revoked.isEmpty, head.commit == nil, let signature = head.bootstrapSignature,
        anchor.signer.verify(
          signature,
          over: try Self.bootstrapStatement(
            groupID: groupID, members: head.members, groupContext: head.groupContext))
      else { throw AppleDeviceError.invalidState("CloudKit bootstrap signature") }
    } else {
      guard let commit = head.commit, commit.change == .add,
        commit.subjectDeviceId == identity.deviceID
      else { throw AppleDeviceError.conflictingReplay }
      let authenticated = try AuthenticatedGroupCommit.decode(commit, committer: anchor.signer)
      guard try authenticated.orderedCommit.groupContext == anchor.groupContext,
        authenticated.members == anchor.members, authenticated.revoked == head.revoked
      else {
        throw AppleDeviceError.conflictingReplay
      }
    }
  }

  private func verifyFeedBoundary(_ next: CloudGroupHead, previous: CloudGroupHead) throws {
    guard let boundary = next.previousFeed, boundary.groupID == groupID,
      previous.epoch < Int64.max, next.epoch == previous.epoch + 1,
      boundary.epoch == UInt64(previous.epoch), boundary.groupContext == previous.groupContext,
      Set(boundary.senders.map(\.sender)) == Set(previous.members.map(\.deviceId)),
      Set(boundary.senders.map(\.sender)).count == boundary.senders.count
    else {
      throw AppleDeviceError.conflictingReplay
    }
  }

  private static func bootstrapStatement(
    groupID: String, members: [DeviceListEntry], groupContext: Data
  ) throws -> Data {
    struct Statement: Encodable {
      let purpose = "memoshi.cloudkit-bootstrap.v1"
      let groupID: String
      let members: [DeviceListEntry]
      let groupContext: Data
    }
    return Data(
      try ProtocolCoding.canonicalText(
        of: Statement(
          groupID: groupID, members: members, groupContext: groupContext)
      ).utf8)
  }

  private func decode(_ record: CKRecord) throws -> CloudGroupHead {
    guard let bytes = record.encryptedValues["state"] as? Data else {
      throw AppleDeviceError.invalidState("CloudKit encrypted group record")
    }
    let head = try JSONDecoder().decode(CloudGroupHead.self, from: bytes)
    guard head.groupID == groupID, head.epoch >= 0 else { throw AppleDeviceError.staleEpoch }
    guard head.committer.verify(head.feedSignature, over: try head.feedStatement()),
      (head.epoch == 0) == (head.previousFeed == nil)
    else { throw AppleDeviceError.conflictingReplay }
    return head
  }

  private func headID(zone: CKRecordZone.ID) -> CKRecord.ID {
    CKRecord.ID(recordName: "group.head", zoneID: zone)
  }
  private func identityID(_ device: DeviceID, zone: CKRecordZone.ID) -> CKRecord.ID {
    CKRecord.ID(recordName: "identity." + device.rawValue, zoneID: zone)
  }
  private func commitID(_ epoch: Int64, zone: CKRecordZone.ID) -> CKRecord.ID {
    CKRecord.ID(recordName: "g.\(epoch)", zoneID: zone)
  }
}
