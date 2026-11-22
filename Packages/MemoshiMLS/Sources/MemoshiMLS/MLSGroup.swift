import Foundation
import MemoshiMLSNativeBindings

/// A genuine RFC 9420 client/group backed by pinned mls-rs and its CryptoKit provider.
///
/// Cipher suite 0x0001: DHKEM(X25519, HKDF-SHA256), AES-128-GCM, SHA-256, Ed25519.
/// A newly created group starts at MLS epoch 0. Commits are private MLS messages;
/// every membership change includes a fresh update path. Three prior epochs are
/// retained for delayed delivery, with replay ratchets retained across restart.
///
/// This actor serializes mutations; the native object also uses a poison-aware mutex.
/// It performs no filesystem, Keychain, relay, CloudKit, or lease-authority access.
/// The host must authenticate pairing and authority results, then encrypt and fsync
/// each resulting secret snapshot atomically with its outbox/inbox/commit record.
/// Never persist a raw snapshot, print one, or send it to another device.
public actor MLSGroup {
  /// RFC 9420 cipher-suite identifier shared by every native session in this wrapper.
  public static let cipherSuite: UInt16 = 0x0001
  /// Maximum number of prior native membership epochs retained for delayed application opens.
  public static let retainedEpochLimit = 3
  private var native: NativeSession?

  private init(native: NativeSession) { self.native = native }

  /// Creates and snapshots before actor escape, so a synchronous host initializer
  /// can encrypt/fsync the first epoch's secrets before publishing the group.
  public nonisolated static func createAndSnapshot(
    credential: MLSCredential, groupID: Data, signIdentityBinding: (Data) throws -> Data
  ) throws -> MLSStateTransition<MLSGroup> {
    let session = try makeSession(credential: credential, signIdentityBinding: signIdentityBinding)
    _ = try call { try session.createGroup(groupId: groupID) }
    let state = try call { try session.snapshot() }
    return MLSStateTransition(value: MLSGroup(native: session), secretState: state)
  }

  /// The same pre-escape checkpoint for a not-yet-joined client.
  public nonisolated static func clientAndSnapshot(
    credential: MLSCredential, signIdentityBinding: (Data) throws -> Data
  ) throws -> MLSStateTransition<MLSGroup> {
    let session = try makeSession(credential: credential, signIdentityBinding: signIdentityBinding)
    let state = try call { try session.snapshot() }
    return MLSStateTransition(value: MLSGroup(native: session), secretState: state)
  }

  /// Creates a joining client. Generate and durably checkpoint its one-use KeyPackage
  /// before publishing it. The closure signs with the host's device-only Ed25519 key;
  /// no Noise/device private key crosses into the MLS native library.
  /// The synchronous signer crosses the actor initializer boundary and must be Sendable.
  public init(
    credential: MLSCredential, signIdentityBinding: @Sendable (Data) throws -> Data
  ) throws {
    native = try Self.makeSession(credential: credential, signIdentityBinding: signIdentityBinding)
  }

  /// Creates the user's first device group at epoch 0.
  /// The synchronous signer crosses the actor initializer boundary and must be Sendable.
  public init(
    creating credential: MLSCredential, groupID: Data,
    signIdentityBinding: @Sendable (Data) throws -> Data
  ) throws {
    let session = try Self.makeSession(
      credential: credential, signIdentityBinding: signIdentityBinding)
    _ = try Self.call { try session.createGroup(groupId: groupID) }
    native = session
  }

  /// Restores client keys, unused KeyPackage private keys, current/retained ratchets,
  /// pending commit secrets and its exact prospective public roster. The host must
  /// decrypt an authenticated local checkpoint and bind it to its current identity.
  public init(restoring secretState: Data, expectedCredential: MLSCredential) throws {
    native = try Self.call {
      try NativeSession.restore(
        secretState: secretState, expectedCredential: expectedCredential.native)
    }
  }

  private static func makeSession(
    credential: MLSCredential, signIdentityBinding: (Data) throws -> Data
  ) throws -> NativeSession {
    let session = try call { try NativeSession(credential: credential.native) }
    let payload = try call { try session.bindingPayload() }
    // Host errors are intentionally not stringified or converted into diagnostics.
    let signature = try signIdentityBinding(payload)
    try call { try session.certify(identitySignature: signature) }
    return session
  }

  private static func call<Value>(_ body: () throws -> Value) throws -> Value {
    do {
      return try body()
    } catch let error as MLSError {
      throw error
    } catch let error as NativeError {
      switch error {
      case .InvalidInput: throw MLSError.invalidInput
      case .InvalidState: throw MLSError.invalidState
      case .AuthenticationFailed: throw MLSError.authenticationFailed
      case .EpochMismatch: throw MLSError.epochMismatch
      case .InvalidMessage: throw MLSError.invalidMessage
      case .StorageFailure: throw MLSError.storageFailure
      case .NativeFailure: throw MLSError.nativeFailure
      }
    } catch {
      // UniFFI decoding/ABI failures expose no native error text to callers.
      throw MLSError.nativeFailure
    }
  }

  private func session() throws -> NativeSession {
    guard let native else { throw MLSError.closed }
    return native
  }

  /// Returns the native public roster, context and active/removal status without reading
  /// host authority state. Throws when this session has no group or is closed.
  public func info() throws -> MLSGroupInfo {
    try MLSGroupInfo(Self.call { try session().info() })
  }

  /// Generates a one-use public KeyPackage and retains its private material in native state.
  /// The host must checkpoint that state before publishing the bytes; this call persists nothing.
  public func generateKeyPackage() throws -> Data {
    try Self.call { try session().generateKeyPackage() }
  }

  /// Generates a KeyPackage and captures its corresponding secret state in one actor turn.
  /// The host must encrypt and durably save the transition before advertising the package.
  public func generateKeyPackageAndSnapshot() throws -> MLSStateTransition<Data> {
    let value = try generateKeyPackage()
    return MLSStateTransition(value: value, secretState: try snapshot())
  }

  /// Processes a pairing-authenticated Welcome, binding it to the expected group bytes and
  /// native epoch and consuming the matching private KeyPackage. Throws on native validation
  /// failure; the host must checkpoint the joined state before confirming or using membership.
  public func join(
    welcome: Data, expectedGroupID: Data, expectedEpoch: UInt64
  ) throws -> MLSGroupInfo {
    try MLSGroupInfo(
      Self.call {
        try session().join(
          welcome: welcome, expectedGroupId: expectedGroupID, expectedEpoch: expectedEpoch)
      })
  }

  /// Stage, then persist snapshot+operation identity BEFORE the authority CAS.
  /// The live group stays at `expectedEpoch` until acceptPendingCommit succeeds.
  public func stageAdd(
    keyPackage: Data, authenticatedCredential: MLSCredential, expectedEpoch: UInt64
  ) throws -> MLSStagedCommit {
    try MLSStagedCommit(
      Self.call {
        try session().stageAdd(
          keyPackage: keyPackage, authenticatedCredential: authenticatedCredential.native,
          expectedEpoch: expectedEpoch)
      })
  }

  /// A different current member removes a device. RFC 9420 does not permit the
  /// committer to remove itself; do not translate that into a pretend local revoke.
  public func stageRemove(deviceID: String, expectedEpoch: UInt64) throws -> MLSStagedCommit {
    try MLSStagedCommit(
      Self.call {
        try session().stageRemove(deviceId: deviceID, expectedEpoch: expectedEpoch)
      })
  }

  /// A real update-path commit without changing membership (epoch/key refresh).
  public func stageUpdate(expectedEpoch: UInt64) throws -> MLSStagedCommit {
    try MLSStagedCommit(Self.call { try session().stageUpdate(expectedEpoch: expectedEpoch) })
  }

  /// Returns the exact native staged commit, if any, without accepting it or reading authority.
  public func pendingCommit() throws -> MLSStagedCommit? {
    try Self.call { try session().pendingCommit() }.map(MLSStagedCommit.init)
  }

  /// Call only after an authenticated CAS has ordered these exact bytes and roster.
  public func acceptPendingCommit(_ commit: MLSOrderedCommit) throws -> MLSGroupInfo {
    try MLSGroupInfo(Self.call { try session().acceptPendingCommit(ordered: commit.native) })
  }

  /// Apply one authenticated authority-ordered commit; gaps, replays and competing
  /// commits at an already advanced epoch fail. A losing staged commit is discarded
  /// only after the winning commit validates completely.
  public func apply(_ commit: MLSOrderedCommit) throws -> MLSGroupInfo {
    try MLSGroupInfo(Self.call { try session().apply(ordered: commit.native) })
  }

  /// Drops the local staged proposal without changing external authority state.
  /// Checkpoint afterward; an uncertain authority result must be reconciled before discarding.
  public func discardPendingCommit() throws {
    try Self.call { try session().discardPendingCommit() }
  }

  /// `authenticatedData` is authenticated but NOT encrypted MLS AAD. Keep all
  /// private envelope fields inside plaintext, not in this parameter.
  public func seal(
    _ plaintext: Data, authenticatedData: Data = Data()
  ) throws -> MLSSealedMessage {
    try MLSSealedMessage(
      Self.call {
        try session().seal(plaintext: plaintext, authenticatedData: authenticatedData)
      })
  }

  /// Authenticates/decrypts native application bytes and advances the receive ratchet on success.
  /// Invalid messages, unavailable epochs and native replays throw; this call has no durable
  /// inbox cache. Persist an open-and-snapshot result before domain delivery or acknowledgement.
  public func open(_ ciphertext: Data) throws -> MLSOpenedMessage {
    try MLSOpenedMessage(Self.call { try session().open(ciphertext: ciphertext) })
  }

  /// Prefer this for the host outbox: no other group call can intervene between
  /// advancing the send ratchet and capturing its durable checkpoint.
  public func sealAndSnapshot(
    _ plaintext: Data, authenticatedData: Data = Data()
  ) throws -> MLSStateTransition<MLSSealedMessage> {
    let value = try seal(plaintext, authenticatedData: authenticatedData)
    return MLSStateTransition(value: value, secretState: try snapshot())
  }

  /// Persist value+secretState before delivering/acknowledging the application item.
  /// After restart, a persisted inbox item is replayed locally, never MLS-opened twice.
  public func openAndSnapshot(_ ciphertext: Data) throws -> MLSStateTransition<MLSOpenedMessage> {
    let value = try open(ciphertext)
    return MLSStateTransition(value: value, secretState: try snapshot())
  }

  /// Secret-bearing bytes. The host must encrypt under its device-owned storage key before
  /// persistence; this includes native pending commit and KeyPackage secrets.
  public func snapshot() throws -> Data {
    try Self.call { try session().snapshot() }
  }

  /// RFC 9420 exporter; changes on every epoch and never grants a revoked member
  /// access to a later epoch. Do not use it as a persistent replacement for MLS.
  public func exportSecret(label: String, context: Data = Data(), length: Int) throws -> Data {
    guard let length = UInt32(exactly: length) else { throw MLSError.invalidInput }
    return try Self.call {
      try session().exportSecret(label: Data(label.utf8), context: context, length: length)
    }
  }

  /// Erases the current native exporter secret; checkpoint afterward.
  public func deleteExporter() throws {
    try Self.call { try session().deleteExporter() }
  }

  /// Releases the native Arc/handle and secret group state. Generated UniFFI
  /// ownership also releases it automatically when the actor is deallocated.
  public func close() { native = nil }
}
