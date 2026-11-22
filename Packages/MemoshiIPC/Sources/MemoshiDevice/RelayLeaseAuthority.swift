import CryptoKit
import Foundation
import MemoshiMLS
import MemoshiProtocol
import Synchronization

/// Trusted-host-enrolled authority for the S2 prototype. Optional synchronized journaling
/// preserves public membership, leases and committed identities, never replica plaintext.
public actor RelayLeaseAuthority {
  /// The latest lease metadata; callers must still validate its deadline.
  public struct Record: Hashable, Sendable, Codable {
    /// The monotonically issued conversation epoch.
    public var epoch: Int64
    /// The recorded holder, absent after release.
    public var runner: DeviceID?
    /// The holder's deadline in Unix milliseconds.
    public var expiresAt: Int64?
    /// `revoked` while this epoch is one a removal moved the lease to and no device has held
    /// it yet (§12.5): the next claim is granted this same epoch. Absent otherwise.
    public var reason: LeaseGrantReason?
  }

  /// Content-free evidence of an issued lease, retained only when configured.
  public struct Grant: Hashable, Sendable, Codable {
    /// The fenced Chat or Session.
    public var conversationID: ConversationID
    /// The issued epoch.
    public var epoch: Int64
    /// The enrolled device receiving authority.
    public var runner: DeviceID
    /// The preceding holder when the grant records a takeover.
    public var previousRunner: DeviceID?
    /// Grant time in Unix milliseconds.
    public var grantedAt: Int64
    /// Lease deadline in Unix milliseconds.
    public var expiresAt: Int64
    /// `revoked` for the grant of an epoch a removal moved the lease to; absent otherwise.
    public var reason: LeaseGrantReason?
  }

  /// Authority outcomes, including ordinary busy-claim refusals during asynchronous release.
  public struct Counters: Hashable, Sendable, Codable {
    /// Granted claim requests.
    public var claimsGranted = 0
    /// Refused claim requests, including retryable busy claims.
    public var claimsDenied = 0
    /// Applied renewal requests.
    public var renewalsApplied = 0
    /// Refused renewal requests.
    public var renewalsDenied = 0
    /// Applied owner/epoch-matching releases.
    public var releases = 0
    /// Releases that did not match the recorded owner and epoch.
    public var releasesIgnored = 0
    /// Applied authenticated membership transitions.
    public var groupCommitsApplied = 0
    /// Refused membership transitions.
    public var groupCommitsDenied = 0
    /// Requests refused because the enrolled sender was revoked.
    public var revokedRefusals = 0
  }

  private struct Group: Codable {
    var epoch: Int64 = 0
    var members: [DeviceID: DeviceListEntry]
    var enrolled: [DeviceID: DevicePeer]
    var initialMembers: [DeviceID: DevicePeer]
    var initialContext: Data?
    var closedFeeds: [UInt64: DeviceApplicationEpochBoundary] = [:]
    var revoked: Set<DeviceID> = []
    var commits: [MLSOrderedCommit] = []
    /// The group as of each removal, by removed device: what that device reads to learn of its
    /// removal. Absent in journals written before removals were kept.
    var removals: [DeviceID: AuthorityGroup]?
  }

  private struct History: Codable {
    var committed: [Int64: CommittedIdentity] = [:]
    var operations: [ULID: Int64] = [:]
    var highWater: Int64 = 0
    var pending: CommittedIdentity?
    /// Operations whose reservation ended without a publication, or that their writer
    /// cancelled before the authority recorded a reservation, by that writer. Such an
    /// operation can never be reserved or published again.
    var cancelled: [ULID: DeviceID] = [:]
  }

  private struct LeaseUpdate: Codable {
    var conversation: ConversationID
    var record: Record
  }

  private enum JournalRecord: Codable {
    case membership(String, Group, [LeaseUpdate])
    case lease(ConversationID, Record, group: String, grant: Grant?)
    case reservation(ConversationID, CommittedIdentity)
    case publication(ConversationID, CommittedIdentity)
    case applicationFeed(DeviceApplicationPublication)
    case cancellation(ConversationID, CommittedIdentity)
    /// A writer's cancel of an operation the authority had no record of.
    case unrecordedCancellation(ConversationID, ULID, DeviceID)
  }

  private struct FeedHead {
    var first: UInt64
    var last: UInt64
    var digest: Data
  }

  private struct FeedEntry {
    var bytes: Data
    var digest: Data
    var prefixDigest: Data
  }

  private struct FeedUpload {
    var id: UUID
    var count: Int
    var next = 0
    var bytes = Data()
  }

  private let journal: DeviceStateJournal?
  private var persistenceFailed = false

  /// Maximum allowed requested lease duration.
  public let maximumLeaseMilliseconds: Int64
  /// The authority's clock; the relay also reads it to stamp each frame's arrival.
  nonisolated let now: @Sendable () -> Int64
  private let keepsGrants: Bool
  private var leases: [ConversationID: Record] = [:]
  private var conversationGroups: [ConversationID: String] = [:]
  private var histories: [ConversationID: History] = [:]
  private var groups: [String: Group] = [:]
  private var deviceGroups: [DeviceID: String] = [:]
  private var feedHeads: [String: [UInt64: [DeviceID: FeedHead]]] = [:]
  private var feedEntries: [String: [UInt64: [DeviceID: [UInt64: FeedEntry]]]] = [:]
  private var feedUploads: [DeviceID: FeedUpload] = [:]
  static let feedChunkSize = 16 * 1024
  static let maximumFeedPublicationBytes = 128 * 1024
  /// Issued grant evidence when retention is enabled; empty when it is disabled.
  public private(set) var grants: [Grant] = []
  /// Accumulated authority outcomes since this in-memory instance started.
  public private(set) var counters = Counters()
  /// Every revoked device, readable without a turn of this actor: a device is in it from the
  /// moment its removal commit is applied, so the relay can refuse it at admission and at
  /// delivery under its own lock, with no window between the commit and its own bookkeeping.
  private nonisolated let revokedDevices = Mutex<Set<DeviceID>>([])

  /// Empty means deny-all. Raw relay hellos cannot enroll; an active signer may admit a QR join.
  public init(
    maximumLeaseMilliseconds: Int64 = 120_000, keepsGrants: Bool = true,
    now: @escaping @Sendable () -> Int64 = { DeviceClock.wallMilliseconds() }
  ) {
    self.maximumLeaseMilliseconds = maximumLeaseMilliseconds
    self.keepsGrants = keepsGrants
    self.now = now
    journal = nil
  }

  /// Opens an exclusive durable authority. A corrupt journal is refused, never reset.
  public init(
    directory: URL, maximumLeaseMilliseconds: Int64 = 120_000, keepsGrants: Bool = true,
    now: @escaping @Sendable () -> Int64 = { DeviceClock.wallMilliseconds() }
  ) throws {
    self.maximumLeaseMilliseconds = maximumLeaseMilliseconds
    self.keepsGrants = keepsGrants
    self.now = now
    let journal = try DeviceStateJournal(
      url: directory.appendingPathComponent("authority.jsonl"), purpose: "memoshi.authority.v1")
    self.journal = journal
    for bytes in journal.takeRecovered() {
      let record = try JSONDecoder().decode(JournalRecord.self, from: bytes)
      switch record {
      case .membership(let id, let group, let updates):
        guard !id.isEmpty, group.epoch >= 0,
          Int64(group.commits.count) == group.epoch,
          Int64(group.closedFeeds.count) == group.epoch,
          !group.initialMembers.isEmpty,
          Set(group.members.keys).isSubset(of: Set(group.enrolled.keys)),
          group.revoked.isDisjoint(with: group.members.keys),
          group.commits.enumerated().allSatisfy({
            $0.element.baseEpoch == UInt64($0.offset)
              && $0.element.targetEpoch == UInt64($0.offset) + 1
          }),
          group.closedFeeds.allSatisfy({
            $0.key < UInt64(group.epoch) && $0.value.isClosed && $0.value.epoch == $0.key
          }),
          (group.removals ?? [:]).allSatisfy({
            group.revoked.contains($0.key) && $0.value.groupID == id && $0.value.epoch > 0
              && $0.value.epoch <= group.epoch && $0.value.commits.isEmpty
          })
        else { throw DeviceLayerError.invalid("authority journal membership") }
        if let previous = groups[id] {
          guard previous.epoch < Int64.max, group.epoch == previous.epoch + 1,
            group.initialMembers == previous.initialMembers,
            group.revoked.isSuperset(of: previous.revoked),
            Array(group.commits.prefix(previous.commits.count)) == previous.commits,
            previous.closedFeeds.allSatisfy({ group.closedFeeds[$0.key] == $0.value }),
            previous.enrolled.allSatisfy({ group.enrolled[$0.key] == $0.value }),
            previous.initialContext == nil || previous.initialContext == group.initialContext,
            (previous.removals ?? [:]).allSatisfy({ group.removals?[$0.key] == $0.value })
          else { throw DeviceLayerError.invalid("authority journal membership rollback") }
        } else if group.epoch != 0 {
          throw DeviceLayerError.invalid("authority journal missing enrollment")
        }
        for device in group.enrolled.keys {
          let enrolledGroup = deviceGroups[device]
          guard enrolledGroup == nil || enrolledGroup == id else {
            throw DeviceLayerError.invalid("authority journal identity reassignment")
          }
        }
        groups[id] = group
        revokedDevices.withLock { $0.formUnion(group.revoked) }
        for peer in group.enrolled.keys { deviceGroups[peer] = id }
        for update in updates { leases[update.conversation] = update.record }
        // The same rule as `endReservations(ofRevokedIn:)`, which an initializer cannot call.
        for (conversation, history) in histories {
          guard conversationGroups[conversation] == id, let pending = history.pending,
            group.revoked.contains(pending.writer)
          else { continue }
          histories[conversation]?.pending = nil
          histories[conversation]?.cancelled[pending.operationID] = pending.writer
        }
      case .lease(let id, let lease, let group, let grant):
        let enrolledGroup = conversationGroups[id]
        guard groups[group] != nil, lease.epoch > 0,
          lease.epoch >= (leases[id]?.epoch ?? 0),
          enrolledGroup == nil || enrolledGroup == group,
          lease.runner == nil ? lease.expiresAt == nil : lease.expiresAt != nil
        else { throw DeviceLayerError.invalid("authority journal lease") }
        if let previous = leases[id], previous.epoch == lease.epoch,
          previous.runner == nil, previous.reason != .revoked, lease.runner != nil
        {
          throw DeviceLayerError.invalid("authority journal released epoch")
        }
        leases[id] = lease
        conversationGroups[id] = group
        if keepsGrants, let grant { grants.append(grant) }
      case .reservation(let id, let reservation):
        let highWater = histories[id]?.highWater ?? 0
        guard highWater < Int64.max, reservation.rseq == highWater + 1,
          histories[id]?.pending == nil, histories[id]?.operations[reservation.operationID] == nil,
          histories[id]?.cancelled[reservation.operationID] == nil,
          reservation.digest == nil
        else { throw DeviceLayerError.invalid("authority journal reservation") }
        histories[id, default: History()].pending = reservation
      case .publication(let id, let identity):
        let highWater = histories[id]?.highWater ?? 0
        guard highWater < Int64.max, identity.rseq == highWater + 1,
          let pending = histories[id]?.pending, pending.rseq == identity.rseq,
          pending.operationID == identity.operationID, pending.writer == identity.writer,
          pending.epoch == identity.epoch, let digest = identity.digest,
          digest.count == 64, digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
        else { throw DeviceLayerError.invalid("authority journal history") }
        histories[id, default: History()].committed[identity.rseq] = identity
        histories[id]?.operations[identity.operationID] = identity.rseq
        histories[id]?.highWater = identity.rseq
        histories[id]?.pending = nil
      case .cancellation(let id, let reservation):
        guard histories[id]?.pending == reservation, reservation.digest == nil else {
          throw DeviceLayerError.invalid("authority journal cancellation")
        }
        histories[id]?.pending = nil
        histories[id]?.cancelled[reservation.operationID] = reservation.writer
      case .unrecordedCancellation(let id, let operationID, let writer):
        guard histories[id]?.pending?.operationID != operationID,
          histories[id]?.operations[operationID] == nil,
          histories[id]?.cancelled[operationID] == nil
        else { throw DeviceLayerError.invalid("authority journal cancellation") }
        histories[id, default: History()].cancelled[operationID] = writer
      case .applicationFeed(let publication):
        guard let group = groups[publication.groupID] else {
          throw DeviceApplicationFeedError.unavailable
        }
        let epoch = publication.application.message.groupEpoch
        let sender = publication.sender.deviceID
        if let head = try Self.validatedFeedHead(
          publication, group: group, head: feedHeads[publication.groupID]?[epoch]?[sender],
          existing: feedEntries[publication.groupID]?[epoch]?[sender]?[
            publication.application.ordinal])
        {
          let data = try ProtocolCoding.makeEncoder().encode(publication)
          feedEntries[publication.groupID, default: [:]][epoch, default: [:]][sender, default: [:]][
            publication.application.ordinal] = FeedEntry(
              bytes: data, digest: Data(SHA256.hash(data: data)), prefixDigest: head.digest)
          feedHeads[publication.groupID, default: [:]][epoch, default: [:]][sender] = head
          if epoch == 0, groups[publication.groupID]?.initialContext == nil {
            groups[publication.groupID]?.initialContext = publication.groupContext
          }
        }
      }
    }
  }

  /// Stops this owner. The journal lock is released, permitting a fresh process to recover it.
  public func close() {
    persistenceFailed = true
    journal?.close()
    feedUploads.removeAll()
  }

  private func persist(_ record: JournalRecord) -> Bool {
    guard !persistenceFailed else { return false }
    do {
      try journal?.append(record)
      return true
    } catch {
      persistenceFailed = true
      return false
    }
  }

  /// Bootstraps one existing group, once, over a trusted host control plane. Candidates have
  /// exact enrolled keys but no membership or lease authority until confirmed pairing adds them.
  public func enroll(groupID: String, members: [DevicePeer], candidates: [DevicePeer] = []) throws {
    guard !persistenceFailed, !groupID.isEmpty, groups[groupID] == nil, !members.isEmpty else {
      throw DeviceLayerError.invalid("group enrollment")
    }
    let peers = members + candidates
    guard Set(peers.map(\.deviceID)).count == peers.count else {
      throw DeviceLayerError.invalid("duplicate enrollment")
    }
    for peer in peers {
      guard peer.signingKey.count == 32, peer.agreementKey.count == 32,
        deviceGroups[peer.deviceID] == nil
      else { throw DeviceLayerError.invalid("conflicting enrollment") }
    }
    let entries = try members.enumerated().map { index, peer in
      try DeviceGroup.entry(for: peer, name: peer.deviceID.rawValue, platform: .mac, leaf: index)
    }
    let group = Group(
      members: Dictionary(uniqueKeysWithValues: entries.map { ($0.deviceId, $0) }),
      enrolled: Dictionary(uniqueKeysWithValues: peers.map { ($0.deviceID, $0) }),
      initialMembers: Dictionary(uniqueKeysWithValues: members.map { ($0.deviceID, $0) }))
    guard persist(.membership(groupID, group, [])) else {
      throw DeviceLayerError.io("authority enrollment durability")
    }
    groups[groupID] = group
    for peer in peers { deviceGroups[peer.deviceID] = groupID }
  }

  /// Returns recorded metadata without asserting that its holder's lease is still live.
  public func record(_ conversationID: ConversationID) -> Record? {
    persistenceFailed ? nil : leases[conversationID]
  }

  /// Whether `deviceID` was revoked in any group; safe from any thread.
  nonisolated func hasRevoked(_ deviceID: DeviceID) -> Bool {
    revokedDevices.withLock { $0.contains(deviceID) }
  }

  /// True only for a removal in the device's enrolled group, not a global arbitrary ID ban.
  public func isRevoked(_ deviceID: DeviceID) -> Bool {
    guard let id = deviceGroups[deviceID] else { return false }
    return groups[id]?.revoked.contains(deviceID) == true
  }

  func enrolledPeer(_ deviceID: DeviceID) -> DevicePeer? {
    guard !persistenceFailed, let id = deviceGroups[deviceID], let group = groups[id],
      !group.revoked.contains(deviceID)
    else { return nil }
    return group.enrolled[deviceID]
  }

  /// The enrolled keys of a removed device whose removal this authority recorded, so the relay
  /// can authenticate it for nothing but reading that removal.
  func removedPeer(_ deviceID: DeviceID) -> DevicePeer? {
    guard !persistenceFailed, let id = deviceGroups[deviceID], let group = groups[id],
      group.revoked.contains(deviceID), group.removals?[deviceID] != nil
    else { return nil }
    return group.enrolled[deviceID]
  }

  /// The group as of `device`'s removal, with the next ordered commit after `afterEpoch` up to
  /// that removal: the proof the device checks with its own group state. Nil for any other
  /// device.
  func removalSnapshot(_ id: String, for device: DeviceID, afterEpoch: Int64) -> AuthorityGroup? {
    guard !persistenceFailed, deviceGroups[device] == id, let group = groups[id],
      group.revoked.contains(device), var removal = group.removals?[device]
    else { return nil }
    removal.commits = Array(
      group.commits.lazy.filter {
        $0.targetEpoch > UInt64(max(0, afterEpoch)) && $0.targetEpoch <= UInt64(removal.epoch)
      }.prefix(1))
    return removal
  }

  private func activeGroup(_ sender: DeviceID) -> String? {
    guard !persistenceFailed, let id = deviceGroups[sender], let group = groups[id],
      !group.revoked.contains(sender), group.members[sender] != nil
    else { return nil }
    return id
  }

  func groupSnapshot(
    _ id: String, for sender: DeviceID, afterEpoch: Int64? = nil
  ) -> AuthorityGroup? {
    guard !persistenceFailed, let group = groups[id], !group.revoked.contains(sender),
      group.members[sender] != nil
    else { return nil }
    return AuthorityGroup(
      groupID: id, epoch: group.epoch,
      members: group.members.values.sorted { $0.leafIndex < $1.leafIndex },
      commits: afterEpoch.map { after in
        Array(group.commits.lazy.filter { $0.targetEpoch > UInt64(max(0, after)) }.prefix(1))
      } ?? [], groupContext: group.commits.last?.groupContext ?? group.initialContext,
      revoked: group.revoked.sorted { $0.rawValue < $1.rawValue })
  }

  /// Appends an immutable, device-signed full-feed packet in the same serialized authority
  /// order as membership. A closed epoch accepts only an exact previously accepted replay.
  public func publishApplication(_ publication: DeviceApplicationPublication) throws {
    guard !persistenceFailed, let group = groups[publication.groupID] else {
      throw DeviceApplicationFeedError.unavailable
    }
    let epoch = publication.application.message.groupEpoch
    let sender = publication.sender.deviceID
    guard
      let head = try Self.validatedFeedHead(
        publication, group: group, head: feedHeads[publication.groupID]?[epoch]?[sender],
        existing: feedEntries[publication.groupID]?[epoch]?[sender]?[
          publication.application.ordinal])
    else { return }
    let bytes = try ProtocolCoding.makeEncoder().encode(publication)
    guard bytes.count <= Self.maximumFeedPublicationBytes else {
      throw DeviceLayerError.invalid("relay application publication limit")
    }
    guard persist(.applicationFeed(publication)) else {
      throw DeviceLayerError.io("relay application publication durability")
    }
    feedEntries[publication.groupID, default: [:]][epoch, default: [:]][sender, default: [:]][
      publication.application.ordinal] = FeedEntry(
        bytes: bytes, digest: Data(SHA256.hash(data: bytes)), prefixDigest: head.digest)
    feedHeads[publication.groupID, default: [:]][epoch, default: [:]][sender] = head
    if epoch == 0, groups[publication.groupID]?.initialContext == nil {
      groups[publication.groupID]?.initialContext = publication.groupContext
    }
  }

  /// Reads a complete sender-feed suffix in one qualification-authority actor turn, validating
  /// the reader's epoch roster, native context and known prefix digests. Old epochs use their
  /// immutable closed boundary; a current open prefix cannot satisfy `requiresClosed`.
  /// Throws for missing/conflicting history; returns ciphertext, not native/domain receipts.
  public func applicationFeed(_ request: DeviceApplicationEpochRequest, reader: DeviceID) throws
    -> DeviceApplicationEpochFeed
  {
    let boundary = try validatedFeedBoundary(request, reader: reader)
    var deliveries: [DeviceApplicationFeedDelivery] = []
    for sender in (feedHeads[request.groupID]?[request.epoch]?.keys.map { $0 } ?? []).sorted(by: {
      $0.rawValue < $1.rawValue
    }) {
      guard let head = feedHeads[request.groupID]?[request.epoch]?[sender] else { continue }
      let after = request.after[sender] ?? 0
      let cutoff = boundary.cutoffs[sender] ?? 0
      guard after < cutoff else { continue }
      var ordinal = max(head.first, after + 1)
      while ordinal <= cutoff {
        guard let entry = feedEntries[request.groupID]?[request.epoch]?[sender]?[ordinal] else {
          throw DeviceApplicationFeedError.incompleteBoundary
        }
        let value = try ProtocolCoding.makeDecoder().decode(
          DeviceApplicationPublication.self, from: entry.bytes)
        deliveries.append(
          DeviceApplicationFeedDelivery(sender: value.sender, application: value.application))
        ordinal += 1
      }
    }
    return DeviceApplicationEpochFeed(boundary: boundary, deliveries: deliveries)
  }

  private static func validatedFeedHead(
    _ publication: DeviceApplicationPublication, group: Group, head: FeedHead?, existing: FeedEntry?
  ) throws -> FeedHead? {
    let packet = publication.application
    let epoch = packet.message.groupEpoch
    guard !publication.groupID.isEmpty, publication.groupID.utf8.count <= 256,
      !publication.groupContext.isEmpty, publication.groupContext.count <= 16 * 1024,
      group.enrolled[publication.sender.deviceID] == publication.sender,
      publication.sender.verify(publication.signature, over: try publication.statement()),
      packet.ordinal > 0, packet.ordinal < UInt64.max, packet.previousOrdinal < packet.ordinal,
      packet.previousOrdinal == 0 || packet.ordinal == packet.previousOrdinal + 1,
      !packet.message.ciphertext.isEmpty, packet.message.ciphertext.count <= 70_000,
      packet.authenticatedData.count <= 4_096
    else { throw DeviceApplicationFeedError.conflictingPublication }
    if let existing {
      // Signatures are randomized, so a republished seal carries a new one over the same signed
      // content. That signature was verified above; the content at this position cannot change.
      let accepted = try ProtocolCoding.makeDecoder().decode(
        DeviceApplicationPublication.self, from: existing.bytes)
      guard accepted.groupID == publication.groupID,
        accepted.groupContext == publication.groupContext,
        accepted.sender == publication.sender, accepted.application == publication.application
      else { throw DeviceApplicationFeedError.conflictingPublication }
      return nil
    }
    guard Int64(exactly: epoch) == group.epoch, group.closedFeeds[epoch] == nil,
      group.members[publication.sender.deviceID] != nil,
      !group.revoked.contains(publication.sender.deviceID)
    else { throw DeviceApplicationFeedError.unacceptedOldEpoch }
    if let context = group.commits.last?.groupContext ?? group.initialContext {
      guard publication.groupContext == context else {
        throw DeviceApplicationFeedError.conflictingPublication
      }
    } else if epoch != 0 {
      throw DeviceApplicationFeedError.incompleteBoundary
    }
    guard packet.previousOrdinal == (head?.last ?? 0) else {
      throw DeviceApplicationFeedError.missingPredecessor(
        sender: publication.sender.deviceID, epoch: epoch,
        expected: head?.last ?? 0, actual: packet.previousOrdinal)
    }
    return FeedHead(
      first: head?.first ?? packet.ordinal, last: packet.ordinal,
      digest: try DeviceApplicationFeedDigest.advancing(
        head?.digest ?? DeviceApplicationFeedDigest.initial,
        sender: publication.sender, application: packet))
  }

  private func currentFeedBoundary(
    _ id: String, group: Group, epoch: UInt64, isClosed: Bool
  ) -> DeviceApplicationEpochBoundary {
    let heads = feedHeads[id]?[epoch] ?? [:]
    return DeviceApplicationEpochBoundary(
      groupID: id, epoch: epoch,
      groupContext: group.commits.last?.groupContext ?? group.initialContext,
      cutoffs: heads.mapValues(\.last), digests: heads.mapValues(\.digest), isClosed: isClosed)
  }

  private static func feedMembers(_ group: Group, epoch: UInt64) throws -> [DevicePeer] {
    if epoch == 0 { return Array(group.initialMembers.values) }
    guard let commit = group.commits.first(where: { $0.targetEpoch == epoch }) else {
      throw DeviceApplicationFeedError.unavailable
    }
    return try commit.members.map {
      DevicePeer(
        deviceID: try DeviceID($0.deviceID), signingKey: $0.signingPublicKey,
        agreementKey: $0.agreementPublicKey)
    }
  }

  private func validatedFeedBoundary(
    _ request: DeviceApplicationEpochRequest, reader: DeviceID
  ) throws -> DeviceApplicationEpochBoundary {
    // A revoked device reads no application message of any epoch (D133): it learns of its
    // removal from the membership commits alone.
    guard !persistenceFailed, let group = groups[request.groupID],
      group.epoch >= 0, request.epoch <= UInt64(group.epoch),
      deviceGroups[reader] == request.groupID, !group.revoked.contains(reader)
    else { throw DeviceApplicationFeedError.unavailable }
    let members = try Self.feedMembers(group, epoch: request.epoch)
    let ids = Set(members.map(\.deviceID))
    guard ids.contains(reader), Set(request.members) == Set(members),
      Set(request.after.keys).isSubset(of: ids), Set(request.afterDigests.keys).isSubset(of: ids)
    else { throw DeviceLayerError.unknownPeer }
    let boundary: DeviceApplicationEpochBoundary
    if request.epoch < UInt64(group.epoch) {
      guard let closed = group.closedFeeds[request.epoch] else {
        throw DeviceApplicationFeedError.incompleteBoundary
      }
      boundary = closed
    } else {
      boundary = currentFeedBoundary(
        request.groupID, group: group, epoch: request.epoch, isClosed: false)
    }
    guard !request.requiresClosed || boundary.isClosed,
      boundary.groupContext == request.groupContext
        || (boundary.groupContext == nil && boundary.cutoffs.isEmpty)
    else { throw DeviceApplicationFeedError.incompleteBoundary }
    for peer in members {
      let ordinal = request.after[peer.deviceID] ?? 0
      // Group diagnoses its private unaccepted tail.
      if ordinal > (boundary.cutoffs[peer.deviceID] ?? 0) { continue }
      let expected: Data?
      if ordinal == 0 {
        expected = DeviceApplicationFeedDigest.initial
      } else {
        expected =
          feedEntries[request.groupID]?[request.epoch]?[peer.deviceID]?[ordinal]?.prefixDigest
      }
      guard let expected,
        expected == (request.afterDigests[peer.deviceID] ?? DeviceApplicationFeedDigest.initial)
      else { throw DeviceApplicationFeedError.conflictingPublication }
    }
    return boundary
  }

  private func applicationPage(
    _ request: DeviceApplicationEpochRequest, reader: DeviceID,
    pinned: DeviceApplicationEpochBoundary?, after: AuthorityApplicationFeedPosition?
  ) throws -> AuthorityApplicationFeedPage {
    let current = try validatedFeedBoundary(request, reader: reader)
    let boundary = pinned ?? current
    guard boundary.groupID == current.groupID, boundary.epoch == current.epoch,
      !request.requiresClosed || boundary.isClosed,
      !boundary.isClosed || boundary == current,
      boundary.groupContext == current.groupContext
        || (boundary.groupContext == nil && boundary.cutoffs.isEmpty),
      Set(boundary.cutoffs.keys).isSubset(of: Set(request.members.map(\.deviceID)))
    else { throw DeviceApplicationFeedError.conflictingPublication }
    for (sender, cutoff) in boundary.cutoffs {
      guard cutoff <= (current.cutoffs[sender] ?? 0),
        (cutoff == 0
          ? DeviceApplicationFeedDigest.initial
          : feedEntries[request.groupID]?[request.epoch]?[sender]?[cutoff]?.prefixDigest)
          == (boundary.digests[sender] ?? DeviceApplicationFeedDigest.initial)
      else { throw DeviceApplicationFeedError.conflictingPublication }
    }
    var locators: [AuthorityApplicationFeedLocator] = []
    for sender in request.members.map(\.deviceID).sorted(by: { $0.rawValue < $1.rawValue }) {
      if let after, sender.rawValue < after.sender.rawValue { continue }
      guard let head = feedHeads[request.groupID]?[request.epoch]?[sender] else { continue }
      let floor = max(
        request.after[sender] ?? 0, after?.sender == sender ? (after?.ordinal ?? 0) : 0)
      let cutoff = boundary.cutoffs[sender] ?? 0
      guard floor < cutoff else { continue }
      var ordinal = max(head.first, floor + 1)
      while ordinal <= cutoff {
        if locators.count == 32, let last = locators.last {
          return AuthorityApplicationFeedPage(
            boundary: boundary, locators: locators,
            next: AuthorityApplicationFeedPosition(sender: last.sender, ordinal: last.ordinal))
        }
        guard let entry = feedEntries[request.groupID]?[request.epoch]?[sender]?[ordinal] else {
          throw DeviceApplicationFeedError.incompleteBoundary
        }
        locators.append(
          AuthorityApplicationFeedLocator(
            sender: sender, ordinal: ordinal, byteCount: entry.bytes.count, digest: entry.digest))
        ordinal += 1
      }
    }
    return AuthorityApplicationFeedPage(boundary: boundary, locators: locators, next: nil)
  }

  private func applicationChunk(
    groupID: String, epoch: UInt64, sender: DeviceID, ordinal: UInt64, offset: Int, reader: DeviceID
  ) throws -> Data {
    guard !persistenceFailed, let group = groups[groupID], !group.revoked.contains(reader),
      try Self.feedMembers(group, epoch: epoch).contains(where: { $0.deviceID == reader }),
      let entry = feedEntries[groupID]?[epoch]?[sender]?[ordinal],
      offset >= 0, offset < entry.bytes.count
    else { throw DeviceApplicationFeedError.unavailable }
    return entry.bytes.subdata(in: offset..<min(entry.bytes.count, offset + Self.feedChunkSize))
  }

  private func uploadApplication(
    transfer: UUID, index: Int, count: Int, bytes: Data, sender: DeviceID
  ) throws -> AuthorityApplicationFeedNotice? {
    guard activeGroup(sender) != nil, count > 0,
      count <= Self.maximumFeedPublicationBytes / Self.feedChunkSize,
      index >= 0, index < count, !bytes.isEmpty, bytes.count <= Self.feedChunkSize,
      index == count - 1 || bytes.count == Self.feedChunkSize
    else { throw DeviceApplicationFeedError.conflictingPublication }
    if index == 0 {
      var upload = FeedUpload(id: transfer, count: count)
      upload.bytes.reserveCapacity(count * Self.feedChunkSize)
      feedUploads[sender] = upload
    }
    guard var upload = feedUploads.removeValue(forKey: sender),
      upload.id == transfer, upload.count == count, upload.next == index
    else { throw DeviceApplicationFeedError.conflictingPublication }
    upload.bytes.append(bytes)
    upload.next += 1
    if upload.next == count {
      let publication = try ProtocolCoding.makeDecoder().decode(
        DeviceApplicationPublication.self, from: upload.bytes)
      guard publication.sender.deviceID == sender else { throw DeviceLayerError.unknownPeer }
      try publishApplication(publication)
      return AuthorityApplicationFeedNotice(
        groupID: publication.groupID, epoch: publication.application.message.groupEpoch)
    } else {
      feedUploads[sender] = upload
    }
    return nil
  }

  func canRoute(from sender: DeviceID, to recipient: DeviceID) -> Bool {
    guard let id = activeGroup(sender), let group = groups[id] else { return false }
    return !group.revoked.contains(recipient)
      && group.members[recipient] != nil
  }

  /// Requests are bound to the relay-authenticated sender and its one trusted group.
  ///
  /// `receivedAt` is this authority's clock when the relay read the frame. Claim and renewal
  /// deadlines are judged at that arrival (never later than now), so relay queueing or a slow
  /// durable write cannot expire a lease whose renewal arrived in time. Arrival does not reorder
  /// anything: the actor still linearizes every decision and the epoch compare-and-swap.
  public func handle(_ message: DeviceMessage, from sender: DeviceID, receivedAt: Int64? = nil)
    -> DeviceMessage?
  {
    guard message.from == .device(sender), message.to == .authority,
      activeGroup(sender) != nil
    else {
      counters.revokedRefusals += 1
      return nil
    }
    let body: DeviceMessageBody?
    switch message.body {
    case .leaseClaim(let claim):
      body = .leaseClaimResult(self.claim(claim, by: sender, receivedAt: receivedAt))
    case .leaseRenew(let renew):
      body = .leaseRenewResult(self.renew(renew, by: sender, receivedAt: receivedAt))
    case .leaseRelease(let release):
      self.release(release, by: sender)
      body = nil
    case .groupCommit(let commit): body = .groupCommitResult(self.commit(commit, by: sender))
    default: body = nil
    }
    guard let body, let msgId = try? DeviceULID.next() else { return nil }
    return DeviceMessage(
      msgId: msgId, from: .authority, to: .device(sender), sentAt: now(), body: body)
  }

  private func authorized(_ conversation: ConversationID, sender: DeviceID) -> Bool {
    guard let group = activeGroup(sender) else { return false }
    return conversationGroups[conversation].map { $0 == group } ?? true
  }

  /// The time a claim or renewal is judged at: its arrival, clamped so it is never in the future.
  private func decisionTime(_ receivedAt: Int64?) -> Int64 {
    let current = now()
    guard let receivedAt else { return current }
    return min(receivedAt, current)
  }

  func claim(_ claim: LeaseClaim, by sender: DeviceID, receivedAt: Int64? = nil)
    -> LeaseClaimResult
  {
    let time = decisionTime(receivedAt)
    let current = leases[claim.conversationId]
    let free = current.map { $0.runner == nil || ($0.expiresAt ?? 0) <= time } ?? true
    // The epoch a removal moved the lease to is held by no device: its first claim gets it.
    let movedByRemoval = current.map { $0.runner == nil && $0.reason == .revoked } ?? false
    guard authorized(claim.conversationId, sender: sender),
      histories[claim.conversationId]?.pending == nil,
      movedByRemoval || (current?.epoch ?? 0) < Int64.max,
      current?.epoch == claim.expectedEpoch, free, claim.expiresAt > time
    else {
      counters.claimsDenied += 1
      let visible = authorized(claim.conversationId, sender: sender) ? current : nil
      return result(claim.conversationId, granted: false, visible ?? Record(epoch: 0))
    }
    let record = Record(
      epoch: (current?.epoch ?? 0) + (movedByRemoval ? 0 : 1), runner: sender,
      expiresAt: min(claim.expiresAt, time + maximumLeaseMilliseconds))
    guard let group = activeGroup(sender) else {
      return result(claim.conversationId, granted: false, current ?? Record(epoch: 0))
    }
    let grant =
      keepsGrants
      ? Grant(
        conversationID: claim.conversationId, epoch: record.epoch, runner: sender,
        previousRunner: current?.runner, grantedAt: time, expiresAt: record.expiresAt ?? time,
        reason: movedByRemoval ? .revoked : nil) : nil
    guard persist(.lease(claim.conversationId, record, group: group, grant: grant)) else {
      return result(claim.conversationId, granted: false, current ?? Record(epoch: 0))
    }
    conversationGroups[claim.conversationId] = group
    leases[claim.conversationId] = record
    counters.claimsGranted += 1
    if let grant { grants.append(grant) }
    return result(claim.conversationId, granted: true, record)
  }

  func renew(_ renew: LeaseRenew, by sender: DeviceID, receivedAt: Int64? = nil)
    -> LeaseRenewResult
  {
    let time = decisionTime(receivedAt)
    guard authorized(renew.conversationId, sender: sender),
      var record = leases[renew.conversationId]
    else {
      counters.renewalsDenied += 1
      return LeaseRenewResult(
        conversationId: renew.conversationId, renewed: false, epoch: 0, expiresAt: 0)
    }
    guard record.epoch == renew.epoch, record.runner == sender,
      let expiry = record.expiresAt, expiry > time, renew.expiresAt > time
    else {
      counters.renewalsDenied += 1
      return LeaseRenewResult(
        conversationId: renew.conversationId, renewed: false, epoch: record.epoch,
        expiresAt: record.expiresAt ?? 0)
    }
    record.expiresAt = min(renew.expiresAt, time + maximumLeaseMilliseconds)
    guard let group = activeGroup(sender),
      persist(.lease(renew.conversationId, record, group: group, grant: nil))
    else {
      return LeaseRenewResult(
        conversationId: renew.conversationId, renewed: false, epoch: record.epoch, expiresAt: 0)
    }
    leases[renew.conversationId] = record
    counters.renewalsApplied += 1
    return LeaseRenewResult(
      conversationId: renew.conversationId, renewed: true, epoch: record.epoch,
      expiresAt: record.expiresAt ?? 0)
  }

  func release(_ release: LeaseRelease, by sender: DeviceID) {
    guard authorized(release.conversationId, sender: sender),
      var record = leases[release.conversationId], record.epoch == release.epoch,
      record.runner == sender, histories[release.conversationId]?.pending == nil,
      release.lastRseq == (histories[release.conversationId]?.highWater ?? 0)
    else {
      counters.releasesIgnored += 1
      return
    }
    record.runner = nil
    record.expiresAt = nil
    guard let group = activeGroup(sender),
      persist(.lease(release.conversationId, record, group: group, grant: nil))
    else { return }
    leases[release.conversationId] = record
    counters.releases += 1
  }

  func commit(_ commit: GroupCommit, by sender: DeviceID) -> GroupCommitResult {
    let current = groups[commit.groupId]?.epoch ?? 0
    guard activeGroup(sender) == commit.groupId, var group = groups[commit.groupId],
      commit.fromEpoch == current, commit.subjectDeviceId != sender,
      let committer = group.enrolled[sender],
      let signed = try? AuthenticatedGroupCommit.decode(commit, committer: committer),
      let subject = try? DevicePeer(
        deviceID: signed.subject.deviceId, publicKeys: signed.subject.publicKeys),
      group.enrolled[subject.deviceID].map({ $0 == subject })
        ?? (deviceGroups[subject.deviceID] == nil),
      (try? signed.validateTransition(
        from: Array(group.members.values), revoked: Array(group.revoked))) != nil,
      let ordered = try? signed.orderedCommit
    else {
      counters.groupCommitsDenied += 1
      return GroupCommitResult(groupId: commit.groupId, accepted: false, epoch: current)
    }
    let closed = currentFeedBoundary(
      commit.groupId, group: group, epoch: UInt64(current), isClosed: true)
    switch commit.change {
    case .add:
      // A full group refuses its next device before anything changes (D132): the members'
      // native rosters could not hold it.
      guard group.members.count < DeviceGroup.maximumMembers,
        !group.revoked.contains(subject.deviceID),
        group.members[subject.deviceID] == nil,
        !group.members.values.contains(where: { $0.leafIndex == signed.subject.leafIndex })
      else {
        counters.groupCommitsDenied += 1
        return GroupCommitResult(groupId: commit.groupId, accepted: false, epoch: current)
      }
      // Admission is part of this same durable membership record. Neither an unauthenticated
      // hello nor a conflicting/tombstoned identity can reserve or replace these keys.
      group.enrolled[subject.deviceID] = subject
      group.members[subject.deviceID] = signed.subject
    case .remove:
      guard group.members[subject.deviceID] == signed.subject else {
        counters.groupCommitsDenied += 1
        return GroupCommitResult(groupId: commit.groupId, accepted: false, epoch: current)
      }
      group.members.removeValue(forKey: subject.deviceID)
      group.revoked.insert(subject.deviceID)
    // The removed runner's leases move only after the combined membership record is synchronized.
    default:
      counters.groupCommitsDenied += 1
      return GroupCommitResult(groupId: commit.groupId, accepted: false, epoch: current)
    }
    group.closedFeeds[UInt64(current)] = closed
    group.members = Dictionary(uniqueKeysWithValues: signed.members.map { ($0.deviceId, $0) })
    group.epoch = signed.toEpoch
    group.commits.append(ordered)
    if commit.change == .remove {
      // Kept in this same membership record: the removed device reads it, with the commits up
      // to it, to learn of its removal from proof it checks itself.
      group.removals = (group.removals ?? [:]).merging(
        [
          subject.deviceID: AuthorityGroup(
            groupID: commit.groupId, epoch: group.epoch,
            members: signed.members.sorted { $0.leafIndex < $1.leafIndex },
            groupContext: ordered.groupContext,
            revoked: group.revoked.sorted { $0.rawValue < $1.rawValue })
        ], uniquingKeysWith: { old, _ in old })
    }
    // Each lease the removed device held moves to a new lease epoch (§12.5), so anything
    // stamped with its epoch is fenced. No device holds the new epoch yet: the next claim is
    // granted it, `reason: revoked`. The record keeps the time of the removal as its deadline.
    // A lease already at the last epoch only loses its runner; it can never be claimed again.
    let moved = leases.compactMap { conversation, record -> LeaseUpdate? in
      guard conversationGroups[conversation] == commit.groupId,
        record.runner == subject.deviceID, commit.change == .remove
      else { return nil }
      let next =
        record.epoch < Int64.max
        ? Record(epoch: record.epoch + 1, runner: nil, expiresAt: now(), reason: .revoked)
        : Record(epoch: record.epoch, runner: nil, expiresAt: now())
      return LeaseUpdate(conversation: conversation, record: next)
    }
    guard persist(.membership(commit.groupId, group, moved)) else {
      return GroupCommitResult(groupId: commit.groupId, accepted: false, epoch: current)
    }
    groups[commit.groupId] = group
    if commit.change == .remove { revokedDevices.withLock { _ = $0.insert(subject.deviceID) } }
    deviceGroups[subject.deviceID] = commit.groupId
    for update in moved { leases[update.conversation] = update.record }
    endReservations(ofRevokedIn: commit.groupId)
    counters.groupCommitsApplied += 1
    return GroupCommitResult(groupId: commit.groupId, accepted: true, epoch: group.epoch)
  }

  func control(_ request: AuthorityControlRequest, from sender: DeviceID) -> AuthorityControlReply {
    var reply = AuthorityControlReply(id: request.id)
    guard !persistenceFailed else { return reply }
    switch request.operation {
    case .group(let id, let after):
      // A removed device reads the group as of its removal, and only that.
      reply.group =
        groupSnapshot(id, for: sender, afterEpoch: after)
        ?? removalSnapshot(id, for: sender, afterEpoch: after)
      reply.accepted = reply.group != nil
    case .conversation(let id):
      guard authorized(id, sender: sender) else { return reply }
      let record = leases[id] ?? Record(epoch: 0)
      let history = histories[id] ?? History()
      reply.conversation = AuthorityConversation(
        epoch: record.epoch, runner: record.runner, expiresAt: record.expiresAt,
        committedRseq: history.highWater, lastIdentity: history.committed[history.highWater],
        pending: history.pending, reason: record.reason)
      reply.accepted = true
    case .identity(let id, let rseq):
      guard authorized(id, sender: sender) else { return reply }
      reply.identity = histories[id]?.committed[rseq]
      reply.accepted = reply.identity != nil
    case .reserve(let id, let epoch, let after, let operationID):
      guard authorized(id, sender: sender), let record = leases[id], record.epoch == epoch,
        record.runner == sender, (record.expiresAt ?? 0) > now()
      else { return reply }
      guard after >= 0, after < Int64.max, histories[id]?.pending == nil,
        histories[id]?.operations[operationID] == nil,
        histories[id]?.cancelled[operationID] == nil,
        (histories[id]?.highWater ?? 0) == after
      else {
        return reply
      }
      let identity = CommittedIdentity(
        rseq: after + 1, epoch: epoch, writer: sender, operationID: operationID)
      guard persist(.reservation(id, identity)) else { return reply }
      histories[id, default: History()].pending = identity
      reply.identity = identity
      reply.accepted = true
    case .cancelReservation(let id, let operationID):
      // Only the reserving writer may end its own unpublished reservation; it does so when its
      // store was not called under it, or refused the commit before writing. A repeat after a
      // lost reply is confirmed.
      guard authorized(id, sender: sender) else { return reply }
      if let canceller = histories[id]?.cancelled[operationID] {
        reply.accepted = canceller == sender
        return reply
      }
      if let pending = histories[id]?.pending, pending.operationID == operationID {
        guard pending.writer == sender, persist(.cancellation(id, pending)) else { return reply }
        histories[id]?.pending = nil
      } else {
        // The authority has no record of the operation: its reserve was lost, or is still on
        // its way. Recording the cancel refuses that reserve when it arrives, so the writer
        // need not wait for it. A published operation is history and is never cancelled.
        guard conversationGroups[id] != nil, histories[id]?.operations[operationID] == nil,
          persist(.unrecordedCancellation(id, operationID, sender))
        else { return reply }
      }
      histories[id, default: History()].cancelled[operationID] = sender
      reply.accepted = true
    case .publish(let id, let operationID, let digest):
      guard authorized(id, sender: sender), digest.count == 64,
        digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
      else { return reply }
      if let rseq = histories[id]?.operations[operationID],
        let existing = histories[id]?.committed[rseq]
      {
        reply.accepted = existing.writer == sender && existing.digest == digest
        reply.identity = reply.accepted ? existing : nil
        return reply
      }
      guard (histories[id]?.highWater ?? 0) < Int64.max,
        var pending = histories[id]?.pending, pending.operationID == operationID,
        pending.writer == sender, pending.rseq == (histories[id]?.highWater ?? 0) + 1
      else { return reply }
      // A reservation survives expiry. No successor can have claimed while it was unresolved.
      pending.digest = digest
      guard persist(.publication(id, pending)) else { return reply }
      histories[id]?.committed[pending.rseq] = pending
      histories[id]?.operations[operationID] = pending.rseq
      histories[id]?.highWater = pending.rseq
      histories[id]?.pending = nil
      reply.identity = pending
      reply.accepted = true
    case .applicationUpload(let transfer, let index, let count, let bytes):
      do {
        reply.applicationPublished = try uploadApplication(
          transfer: transfer, index: index, count: count, bytes: bytes, sender: sender)
        reply.accepted = true
      } catch let error as DeviceApplicationFeedError {
        reply.applicationError = error
      } catch {
        reply.applicationError = .unavailable
      }
    case .applicationPage(let request, let boundary, let after):
      do {
        reply.applicationPage = try applicationPage(
          request, reader: sender, pinned: boundary, after: after)
        reply.accepted = true
      } catch let error as DeviceApplicationFeedError {
        reply.applicationError = error
      } catch {
        reply.applicationError = .unavailable
      }
    case .applicationChunk(let groupID, let epoch, let publisher, let ordinal, let offset):
      do {
        reply.applicationChunk = try applicationChunk(
          groupID: groupID, epoch: epoch, sender: publisher, ordinal: ordinal, offset: offset,
          reader: sender)
        reply.accepted = true
      } catch let error as DeviceApplicationFeedError {
        reply.applicationError = error
      } catch {
        reply.applicationError = .unavailable
      }
    }
    return reply
  }

  /// A removed device's unpublished reservation ends with its leases. It follows from the
  /// membership record alone, so journal replay reaches the same state: the removed writer can
  /// never publish, and its operation can never be reserved again.
  private func endReservations(ofRevokedIn groupID: String) {
    guard let revoked = groups[groupID]?.revoked, !revoked.isEmpty else { return }
    for (conversation, history) in histories {
      guard conversationGroups[conversation] == groupID, let pending = history.pending,
        revoked.contains(pending.writer)
      else { continue }
      histories[conversation]?.pending = nil
      histories[conversation]?.cancelled[pending.operationID] = pending.writer
    }
  }

  private func result(_ conversation: ConversationID, granted: Bool, _ record: Record)
    -> LeaseClaimResult
  {
    LeaseClaimResult(
      conversationId: conversation, granted: granted, epoch: record.epoch,
      runnerDeviceId: record.runner, expiresAt: record.expiresAt)
  }
}
