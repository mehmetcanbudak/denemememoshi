import Foundation
import MemoshiMLSNativeBindings

/// Public device-key credential supplied after host-authenticated pairing. A device Ed25519
/// signature separately certifies the native MLS signing key; this value alone proves neither.
public struct MLSCredential: Codable, Hashable, Sendable {
  /// Host device identity bound to the public keys, distinct from an MLS leaf index.
  public let deviceID: String
  /// Device Ed25519 verification key, not the separately generated native MLS signing key.
  public let signingPublicKey: Data
  /// Device X25519 agreement key used by the host's authenticated pairing transport.
  public let agreementPublicKey: Data

  /// Stores public identity fields without authenticating pairing or validating native state.
  public init(deviceID: String, signingPublicKey: Data, agreementPublicKey: Data) {
    self.deviceID = deviceID
    self.signingPublicKey = signingPublicKey
    self.agreementPublicKey = agreementPublicKey
  }

  var native: NativeCredential {
    NativeCredential(
      deviceId: deviceID, signingPublicKey: signingPublicKey,
      agreementPublicKey: agreementPublicKey)
  }

  init(_ native: NativeCredential) {
    self.init(
      deviceID: native.deviceId, signingPublicKey: native.signingPublicKey,
      agreementPublicKey: native.agreementPublicKey)
  }
}

/// Public native group view, including actual tree positions and whether this client remains
/// active. It carries no group secrets and does not establish a fresh external authority read.
public struct MLSGroupInfo: Codable, Hashable, Sendable {
  /// Opaque MLS group identifier bytes; the host chooses their encoding.
  public let groupID: Data
  /// Native membership epoch, starting at zero and advancing once per applied MLS commit.
  public let epoch: UInt64
  /// Credentials in the native roster, not array-position-derived leaf indices.
  public let members: [MLSCredential]
  /// Actual RFC 9420 leaf indices, including index reuse after a member leaves.
  public let memberLeafIndices: [String: UInt32]
  /// RFC GroupContext bytes encoded by mls-rs. On an active group this is the
  /// validated native context, including tree/transcript hashes. An inactive
  /// removal tombstone only preserves its authenticated authority record; the
  /// removed member has no new-epoch secrets and cannot certify an active anchor.
  public let groupContext: Data
  /// Whether this client has active group state rather than an authenticated removal tombstone.
  public let isActive: Bool

  init(_ native: NativeGroupInfo) {
    groupID = native.groupId
    epoch = native.epoch
    members = native.members.map(MLSCredential.init)
    memberLeafIndices = native.memberLeafIndices
    groupContext = native.groupContext
    isActive = native.isActive
  }
}

/// A real MLS commit staged at the old epoch, not yet authority-accepted.
/// `welcome` is sent only to the authenticated joining device, through pairing.
public struct MLSStagedCommit: Codable, Hashable, Sendable {
  /// Current native membership epoch, unchanged while this proposal remains staged.
  public let baseEpoch: UInt64
  /// Prospective successor membership epoch if these exact commit bytes are accepted.
  public let targetEpoch: UInt64
  /// Exact private MLS commit message to bind into the host's authority-ordering request.
  public let commit: Data
  /// Native Welcome for an added device, or nil when the transition has no new member.
  public let welcome: Data?
  /// Complete native roster expected after acceptance, not current host authority evidence.
  public let members: [MLSCredential]
  /// Prospective RFC 9420 leaf index for every member device identity.
  public let memberLeafIndices: [String: UInt32]
  /// Prospective serialized native GroupContext, bound to this exact staged transition.
  public let groupContext: Data

  init(_ native: NativeStagedCommit) {
    baseEpoch = native.baseEpoch
    targetEpoch = native.targetEpoch
    commit = native.commit
    welcome = native.welcome
    members = native.members.map(MLSCredential.init)
    memberLeafIndices = native.memberLeafIndices
    groupContext = native.groupContext
  }
}

/// The host must authenticate an authority CAS result that binds these exact bytes,
/// base/target epochs and roster BEFORE passing this value to accept/apply. Constructing
/// this record is not itself proof of authority; the crypto library makes no network calls.
public struct MLSOrderedCommit: Codable, Hashable, Sendable {
  /// Native membership epoch at which this ordered transition must be applied.
  public let baseEpoch: UInt64
  /// Successor native membership epoch claimed by the authenticated authority record.
  public let targetEpoch: UInt64
  /// Exact native commit bytes; replacing them changes the transition being authorized.
  public let commit: Data
  /// Complete expected post-commit credentials, independently checked by native processing.
  public let members: [MLSCredential]
  /// Expected post-commit tree positions, keyed by device identity rather than roster order.
  public let memberLeafIndices: [String: UInt32]
  /// Exact expected post-commit GroupContext, independently checked against native state.
  public let groupContext: Data

  /// Stores the proposed ordered record without validating its shape, authority, or native
  /// commit. The host must supply authenticated ordering before accept/apply.
  public init(
    baseEpoch: UInt64, targetEpoch: UInt64, commit: Data, members: [MLSCredential],
    memberLeafIndices: [String: UInt32], groupContext: Data
  ) {
    self.baseEpoch = baseEpoch
    self.targetEpoch = targetEpoch
    self.commit = commit
    self.members = members
    self.memberLeafIndices = memberLeafIndices
    self.groupContext = groupContext
  }

  /// Copies a staged record's exact public fields; does not convert staging into authority
  /// acceptance or mutate the native group.
  public init(staged: MLSStagedCommit) {
    self.init(
      baseEpoch: staged.baseEpoch, targetEpoch: staged.targetEpoch, commit: staged.commit,
      members: staged.members, memberLeafIndices: staged.memberLeafIndices,
      groupContext: staged.groupContext)
  }

  var native: NativeOrderedCommit {
    NativeOrderedCommit(
      baseEpoch: baseEpoch, targetEpoch: targetEpoch, commit: commit,
      members: members.map(\.native), memberLeafIndices: memberLeafIndices,
      groupContext: groupContext)
  }
}

/// Immutable native application ciphertext plus an epoch hint. Only a successful native open
/// authenticates its sender, epoch and AAD; this record is not a domain-delivery receipt.
public struct MLSSealedMessage: Codable, Hashable, Sendable {
  /// Encoded native MLS application bytes; outgoing delivery requires checkpointed send state.
  public let ciphertext: Data
  /// Native membership epoch reported at seal time; untrusted when constructed by a caller.
  public let groupEpoch: UInt64

  /// Restores immutable ciphertext from an authenticated host record. Construction
  /// is not cryptographic authority: MLSGroup.open must verify the native message
  /// and recover its authenticated sender/epoch before any inbound application.
  public init(ciphertext: Data, groupEpoch: UInt64) {
    self.ciphertext = ciphertext
    self.groupEpoch = groupEpoch
  }

  init(_ native: NativeSealedMessage) {
    ciphertext = native.ciphertext
    groupEpoch = native.groupEpoch
  }
}

/// Plaintext and sender returned by native authentication, or restored from a trusted host
/// checkpoint. Not a domain-consumption receipt; never log this value.
public struct MLSOpenedMessage: Codable, Hashable, Sendable,
  CustomStringConvertible, CustomDebugStringConvertible
{
  /// Decrypted application bytes, whose domain authority remains the consumer's responsibility.
  public let plaintext: Data
  /// Authenticated but unencrypted MLS AAD recovered from the native message.
  public let authenticatedData: Data
  /// Credential authenticated by MLS, to be checked against the host's epoch and routing policy.
  public let sender: MLSCredential
  /// Native membership epoch authenticated with this message, not a conversation lease epoch.
  public let groupEpoch: UInt64

  /// Used when restoring a host's already-authenticated inbox receipt or recording
  /// its own successful seal. Construction is not a cryptographic authentication
  /// operation: never use untrusted fields to fabricate an inbound decrypt result.
  public init(
    plaintext: Data, authenticatedData: Data, sender: MLSCredential, groupEpoch: UInt64
  ) {
    self.plaintext = plaintext
    self.authenticatedData = authenticatedData
    self.sender = sender
    self.groupEpoch = groupEpoch
  }

  init(_ native: NativeOpenedMessage) {
    plaintext = native.plaintext
    authenticatedData = native.authenticatedData
    sender = MLSCredential(native.sender)
    groupEpoch = native.groupEpoch
  }

  /// Content-free rendering that never includes plaintext, AAD or credential fields.
  public var description: String { "MLSOpenedMessage(<redacted>)" }
  /// Uses the same redaction as the ordinary description.
  public var debugDescription: String { description }
}

/// A mutation and its exact native checkpoint, captured under one actor turn.
/// The host owns encryption and durable storage: persist `secretState` with the matching
/// outbox/inbox/commit record before sending or acknowledging. This value persists nothing
/// and intentionally has no Codable or reflective secret description.
public struct MLSStateTransition<Value: Sendable>: Sendable,
  CustomStringConvertible, CustomDebugStringConvertible
{
  /// Mutation result that must not escape its host persistence boundary prematurely.
  public let value: Value
  /// Secret native snapshot, including ratchets and pending key material; never log or transmit.
  public let secretState: Data
  /// Content-free rendering that hides both the result and secret snapshot.
  public var description: String { "MLSStateTransition(<redacted>)" }
  /// Uses the same redaction as the ordinary description.
  public var debugDescription: String { description }
}

/// Stable, content-free errors. Upstream error strings and native panic payloads
/// never become public descriptions, logs or diagnostics.
public enum MLSError: String, Error, Codable, Hashable, Sendable {
  case invalidInput, invalidState, authenticationFailed, epochMismatch
  case invalidMessage, storageFailure, nativeFailure, closed
}
