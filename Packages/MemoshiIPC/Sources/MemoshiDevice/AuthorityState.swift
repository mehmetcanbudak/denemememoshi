import CryptoKit
import Foundation
import MemoshiMLS
import MemoshiProtocol

/// Public authority metadata and exact ordered MLS commits, never MLS secret state.
public struct AuthorityGroup: Codable, Hashable, Sendable {
  /// The trusted host-enrolled group identity.
  public var groupID: String
  /// The latest committed membership epoch.
  public var epoch: Int64
  /// Current authoritative public members.
  public var members: [DeviceListEntry]
  /// Authority-ordered commits needed to advance a replica from its durable group epoch.
  public var commits: [MLSOrderedCommit]
  /// Exact authenticated native head context; nil only for a single-member relay epoch-zero root.
  public var groupContext: Data?
  /// Permanent identity tombstones authenticated by this authority, never inferred from absence.
  public var revoked: [DeviceID]

  /// Stores public authority metadata without validating its source or applying any MLS commit.
  public init(
    groupID: String, epoch: Int64, members: [DeviceListEntry], commits: [MLSOrderedCommit] = [],
    groupContext: Data? = nil, revoked: [DeviceID] = []
  ) {
    self.groupID = groupID
    self.epoch = epoch
    self.members = members
    self.commits = commits
    self.groupContext = groupContext
    self.revoked = revoked
  }
}

/// Content-free identity of one reserved or committed replication sequence.
public struct CommittedIdentity: Codable, Hashable, Sendable {
  /// The reserved or committed replication sequence.
  public var rseq: Int64
  /// The writer's fenced conversation epoch.
  public var epoch: Int64
  /// The enrolled device authorized for that epoch.
  public var writer: DeviceID
  /// The immutable operation identity bound to this sequence.
  public var operationID: ULID
  /// Nil until the writer has committed locally and published the exact payload digest.
  public var digest: String?
}

/// Authority-reported lease metadata and committed high-water, not standalone write permission.
/// Persisting this snapshot does not replace a fresh authority check or an unexpired owner/epoch
/// lease. An unresolved reservation blocks successor claims; metadata cannot recover plaintext.
public struct AuthorityConversation: Codable, Hashable, Sendable {
  /// The latest authority-issued conversation epoch.
  public var epoch: Int64
  /// The recorded holder; lease expiry still determines whether it may write.
  public var runner: DeviceID?
  /// The recorded lease deadline in Unix milliseconds, absent after release.
  public var expiresAt: Int64?
  /// The highest sequence whose exact payload digest was published.
  public var committedRseq: Int64
  /// Identity of the last published sequence, absent before the first commit.
  public var lastIdentity: CommittedIdentity?
  /// An unresolved reservation that blocks successor claims until publication.
  public var pending: CommittedIdentity?
  /// `revoked` while the epoch is one a removal moved the lease to and no device has held it
  /// yet (§12.5): the next claim is granted this same epoch. Absent in older replies.
  public var reason: LeaseGrantReason?
}

// These control frames are private to the S2 loopback relay. Remote clients cannot enroll.
struct AuthorityControlRequest: Codable, Sendable {
  var id: UUID
  var operation: Operation

  enum Operation: Codable, Sendable {
    case group(String, afterEpoch: Int64)
    case conversation(ConversationID)
    case identity(ConversationID, Int64)
    case reserve(ConversationID, epoch: Int64, after: Int64, operationID: ULID)
    case publish(ConversationID, operationID: ULID, digest: String)
    /// Ends the sender's own unpublished reservation, recorded by the authority or not; only
    /// for a commit that wrote nothing.
    case cancelReservation(ConversationID, operationID: ULID)
    case applicationUpload(transfer: UUID, index: Int, count: Int, bytes: Data)
    case applicationPage(
      DeviceApplicationEpochRequest, boundary: DeviceApplicationEpochBoundary?,
      after: AuthorityApplicationFeedPosition?)
    case applicationChunk(
      groupID: String, epoch: UInt64, sender: DeviceID, ordinal: UInt64, offset: Int)
  }
}

struct AuthorityControlReply: Codable, Sendable {
  var id: UUID
  var accepted = false
  var group: AuthorityGroup?
  var conversation: AuthorityConversation?
  var identity: CommittedIdentity?
  var applicationPage: AuthorityApplicationFeedPage?
  var applicationChunk: Data?
  var applicationError: DeviceApplicationFeedError?
  var applicationPublished: AuthorityApplicationFeedNotice?
}

struct AuthorityApplicationFeedPosition: Codable, Sendable {
  var sender: DeviceID
  var ordinal: UInt64
}

struct AuthorityApplicationFeedLocator: Codable, Sendable {
  var sender: DeviceID
  var ordinal: UInt64
  var byteCount: Int
  var digest: Data
}

struct AuthorityApplicationFeedPage: Codable, Sendable {
  var boundary: DeviceApplicationEpochBoundary
  var locators: [AuthorityApplicationFeedLocator]
  var next: AuthorityApplicationFeedPosition?
}

struct AuthorityApplicationFeedNotice: Codable, Sendable {
  var groupID: String
  var epoch: UInt64
}

/// An enrolled device signs the exact native MLS transition and its prospective roster.
/// The authority orders this public envelope; only a device with MLS state can validate/apply
/// the cryptographic transition. A signature alone never substitutes for native MLS processing.
public struct AuthenticatedGroupCommit: Codable, Hashable, Sendable {
  /// Group identity bound into the device's signed statement.
  public var groupID: String
  /// Base membership epoch, expressed as a nonnegative MLS epoch number.
  public var fromEpoch: Int64
  /// Successor membership epoch; a valid ordered transition advances by exactly one.
  public var toEpoch: Int64
  /// The single add/remove operation described by this envelope.
  public var change: GroupChange
  /// Exact device keys and leaf assignment being added or removed.
  public var subject: DeviceListEntry
  /// Native MLS commit bytes, which replicas must independently process.
  public var mlsCommit: Data
  /// Serialized authenticated MLS group context expected after the transition.
  public var groupContext: Data
  /// Complete prospective public roster, including native leaf indices.
  public var members: [DeviceListEntry]
  /// Cumulative permanent identity tombstones; absence from the roster is not a tombstone.
  public var revoked: [DeviceID]
  /// Device signature over the canonical, domain-separated statement, excluding this field.
  public var signature: Data

  /// Stores an envelope without authenticating it; decoding/verification and native MLS
  /// processing remain separate acceptance boundaries.
  public init(
    groupID: String, fromEpoch: Int64, toEpoch: Int64, change: GroupChange,
    subject: DeviceListEntry, mlsCommit: Data, groupContext: Data,
    members: [DeviceListEntry], revoked: [DeviceID] = [], signature: Data
  ) {
    self.groupID = groupID
    self.fromEpoch = fromEpoch
    self.toEpoch = toEpoch
    self.change = change
    self.subject = subject
    self.mlsCommit = mlsCommit
    self.groupContext = groupContext
    self.members = members
    self.revoked = revoked
    self.signature = signature
  }

  /// Decodes and verifies the complete signed inner/outer binding, never repairing a roster.
  public static func decode(_ commit: GroupCommit, committer: DevicePeer) throws -> Self {
    guard let data = Data(base64Encoded: commit.commit.rawValue) else {
      throw DeviceLayerError.invalid("group commit encoding")
    }
    let envelope = try ProtocolCoding.makeDecoder().decode(Self.self, from: data)
    guard envelope.groupID == commit.groupId, envelope.fromEpoch == commit.fromEpoch,
      envelope.change == commit.change, envelope.subject.deviceId == commit.subjectDeviceId,
      envelope.verify(commit, committer: committer)
    else { throw DeviceLayerError.invalid("authenticated group commit") }
    _ = try envelope.orderedCommit
    guard envelope.subject.deviceId != committer.deviceID else {
      throw DeviceLayerError.invalid("group commit subject")
    }
    return envelope
  }

  /// Checks the outer operation binding and device signature. Does not validate the native
  /// commit, the roster transition, or the committer's current authority membership.
  public func verify(_ commit: GroupCommit, committer: DevicePeer) -> Bool {
    guard groupID == commit.groupId, fromEpoch == commit.fromEpoch,
      change == commit.change, subject.deviceId == commit.subjectDeviceId,
      let statement = try? statement()
    else { return false }
    return committer.verify(signature, over: statement)
  }

  /// Validates epoch, roster, leaf and tombstone shape and converts to the native MLS input.
  /// Throws for malformed metadata; conversion alone does not authenticate or apply the commit.
  public var orderedCommit: MLSOrderedCommit {
    get throws {
      let tombstones = Set(revoked)
      guard tombstones.count == revoked.count,
        !members.contains(where: { tombstones.contains($0.deviceId) })
      else { throw DeviceLayerError.invalid("MLS identity tombstones") }
      guard fromEpoch >= 0, fromEpoch < Int64.max, toEpoch == fromEpoch + 1,
        !mlsCommit.isEmpty, !groupContext.isEmpty,
        Set(members.map(\.deviceId)).count == members.count,
        Set(members.map(\.leafIndex)).count == members.count,
        members.allSatisfy({ $0.leafIndex >= 0 && UInt64($0.leafIndex) <= UInt64(UInt32.max) })
      else { throw DeviceLayerError.invalid("MLS ordered group transition") }
      let credentials = try members.map {
        try DevicePeer(deviceID: $0.deviceId, publicKeys: $0.publicKeys).mlsCredential
      }
      return MLSOrderedCommit(
        baseEpoch: UInt64(fromEpoch), targetEpoch: UInt64(toEpoch), commit: mlsCommit,
        members: credentials,
        memberLeafIndices: Dictionary(
          uniqueKeysWithValues: members.map {
            ($0.deviceId.rawValue, UInt32($0.leafIndex))
          }), groupContext: groupContext)
    }
  }

  /// Makes the exact wire payload for a staged native commit; the stage is not accepted here.
  public static func signed(
    groupID: String, fromEpoch: Int64, change: GroupChange, subject: DeviceListEntry,
    staged: MLSStagedCommit, members: [DeviceListEntry], revoked: [DeviceID] = [],
    identity: DeviceIdentity
  ) throws -> GroupCommit {
    guard staged.baseEpoch == UInt64(exactly: fromEpoch),
      let target = Int64(exactly: staged.targetEpoch)
    else { throw DeviceLayerError.invalid("MLS staged group epoch") }
    var tombstones = Set(revoked)
    if change == .remove { tombstones.insert(subject.deviceId) }
    var envelope = Self(
      groupID: groupID, fromEpoch: fromEpoch, toEpoch: target, change: change,
      subject: subject, mlsCommit: staged.commit, groupContext: staged.groupContext,
      members: members, revoked: tombstones.sorted { $0.rawValue < $1.rawValue }, signature: Data())
    let ordered = try envelope.orderedCommit
    guard Set(ordered.members) == Set(staged.members),
      ordered.memberLeafIndices == staged.memberLeafIndices,
      ordered.groupContext == staged.groupContext
    else {
      throw DeviceLayerError.invalid("MLS staged group roster")
    }
    envelope.signature = try identity.sign(envelope.statement())
    return GroupCommit(
      groupId: groupID, fromEpoch: fromEpoch, change: change, subjectDeviceId: subject.deviceId,
      commit: try Base64Bytes(ProtocolCoding.makeEncoder().encode(envelope).base64EncodedString()))
  }

  /// Encodes the canonical domain-separated bytes signed by the committer, including the
  /// exact commit, context, roster and tombstones. Throws if canonical encoding fails.
  public func statement() throws -> Data {
    struct Statement: Encodable {
      let purpose = "memoshi.group-commit.v2"
      var groupID: String
      var fromEpoch: Int64
      var toEpoch: Int64
      var change: GroupChange
      var subject: DeviceListEntry
      var mlsCommit: Data
      var groupContext: Data
      var members: [DeviceListEntry]
      var revoked: [DeviceID]
    }
    return Data(
      try ProtocolCoding.canonicalText(
        of: Statement(
          groupID: groupID, fromEpoch: fromEpoch, toEpoch: toEpoch, change: change,
          subject: subject, mlsCommit: mlsCommit, groupContext: groupContext,
          members: members, revoked: revoked)
      ).utf8)
  }

  /// A signed add/remove cannot smuggle another membership/key/leaf transition into its MLS
  /// proposal. Native MLS processing independently validates the actual resulting tree.
  public func validateTransition(from current: [DeviceListEntry], revoked previous: [DeviceID] = [])
    throws
  {
    struct MemberIdentity: Equatable {
      var peer: DevicePeer
      var leaf: Int
    }
    func roster(_ entries: [DeviceListEntry]) throws -> [DeviceID: MemberIdentity] {
      guard Set(entries.map(\.deviceId)).count == entries.count else {
        throw DeviceLayerError.invalid("duplicate group identity")
      }
      return try Dictionary(
        uniqueKeysWithValues: entries.map {
          (
            $0.deviceId,
            MemberIdentity(
              peer: try DevicePeer(deviceID: $0.deviceId, publicKeys: $0.publicKeys),
              leaf: $0.leafIndex)
          )
        })
    }
    var expected = try roster(current)
    var tombstones = Set(previous)
    let changed = MemberIdentity(
      peer: try DevicePeer(deviceID: subject.deviceId, publicKeys: subject.publicKeys),
      leaf: subject.leafIndex)
    switch change {
    case .add:
      guard expected[subject.deviceId] == nil, !tombstones.contains(subject.deviceId) else {
        throw DeviceLayerError.invalid("existing group add")
      }
      expected[subject.deviceId] = changed
    case .remove:
      guard expected[subject.deviceId] == changed else {
        throw DeviceLayerError.invalid("unknown group remove")
      }
      expected[subject.deviceId] = nil
      tombstones.insert(subject.deviceId)
    default: throw DeviceLayerError.invalid("unsupported group transition")
    }
    guard try roster(members) == expected else {
      throw DeviceLayerError.invalid("undeclared MLS membership transition")
    }
    guard Set(revoked) == tombstones else {
      throw DeviceLayerError.invalid("undeclared identity tombstone transition")
    }
  }
}

extension DevicePeer {
  /// The native MLS credential is certified by this device's own Ed25519 signing identity.
  public var mlsCredential: MLSCredential {
    MLSCredential(
      deviceID: deviceID.rawValue, signingPublicKey: signingKey, agreementPublicKey: agreementKey)
  }
}

extension ReplicaChange {
  /// Binds every field, including records, events and forwarding receipts, to its sequence.
  func committedDigest() throws -> String {
    let bytes = Data(try ProtocolCoding.canonicalText(of: self).utf8)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
