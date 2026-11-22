import CryptoKit
import Foundation
import MemoshiDevice
import MemoshiProtocol

/// Random-access encrypted state, NOT an MLS application message. Key material comes from the
/// genuine RFC 9420 exporter at the exact native GroupContext; CryptoKit supplies HKDF/AES-GCM.
/// DeviceGroup alone retains a bounded, device-only-encrypted exporter epoch window.
public struct MLSStateRecordHeader: Codable, Hashable, Sendable {
  /// Envelope schema version; the decoder currently accepts only version one.
  public let version: Int
  /// Native group's identifier, bound into the AEAD key derivation and authenticated header.
  public let groupID: String
  /// Exact MLS epoch whose retained exporter material protects this record.
  public let groupEpoch: UInt64
  /// Native GroupContext bytes distinguishing the exact exporter context at that epoch.
  public let groupContext: Data
  /// Caller-chosen object identity bound into authenticated data and the derived object key.
  public let objectID: String
  /// Domain-separation label required to match when opening the object.
  public let purpose: String
  /// Device whose epoch-membership signing key must verify the envelope.
  public let writer: DeviceID
}

struct MLSStateRecordEnvelope: Codable, Sendable {
  let header: MLSStateRecordHeader
  let sealed: Data
  let signature: Data
}

/// Decrypted state plus authenticated context, not proof that a mutable authority still endorses it.
/// Plaintext access is explicit; string descriptions redact the contents.
public struct MLSStateRecordValue: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  /// Sensitive decrypted object bytes; the caller owns their handling and any durable storage.
  public let plaintext: Data
  /// Header verified by the epoch writer's signature and the exporter-derived AEAD.
  public let header: MLSStateRecordHeader
  /// Redacted summary that omits object contents.
  public var description: String { "MLSStateRecordValue(<redacted>)" }
  /// The same redacted summary used for normal descriptions.
  public var debugDescription: String { description }
}

/// Signs and exporter-encrypts random-access state without consuming an MLS application ratchet.
/// Opening requires the matching retained epoch/context; cryptographic validity alone does not
/// establish current authority, freshness, or CloudKit persistence.
public struct MLSStateRecordCodec: Sendable {
  private let identity: DeviceIdentity
  private let group: DeviceGroup

  /// Retains the signing identity and group-key owner without deriving keys or performing I/O.
  public init(identity: DeviceIdentity, group: DeviceGroup) {
    self.identity = identity
    self.group = group
  }

  /// Encrypts and signs object bytes under the current group's exporter context and this member's
  /// identity. The encoded envelope is limited to 1,048,576 bytes; membership, key, encryption,
  /// and size failures throw. No cloud save or local persistence is performed.
  public func seal(_ plaintext: Data, objectID: String, purpose: String) async throws -> Data {
    let material = try await group.currentStateRecordKey()
    let header = MLSStateRecordHeader(
      version: 1, groupID: material.groupID, groupEpoch: material.epoch,
      groupContext: material.groupContext, objectID: objectID, purpose: purpose,
      writer: identity.deviceID)
    guard material.members.contains(identity.peer) else { throw AppleDeviceError.revoked }
    let aad = try Self.canonical(header)
    let key = Self.objectKey(material.secret, header: header, aad: aad)
    guard let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad).combined else {
      throw AppleDeviceError.invalidState("state record encryption")
    }
    let signature = try identity.sign(Self.signatureStatement(aad: aad, sealed: sealed))
    let encoded = try Self.canonical(
      MLSStateRecordEnvelope(header: header, sealed: sealed, signature: signature))
    guard encoded.count <= 1_048_576 else {
      throw AppleDeviceError.invalidState("state record size")
    }
    return encoded
  }

  /// Repeated own/peer reads and restart do not consume a ratchet or require plaintext receipts.
  /// An old-epoch value is cryptographic evidence only: the authority's pinned/current signed
  /// manifest must independently endorse its exact digest before it may be rewrapped or used.
  public func open(_ bytes: Data, objectID: String, purpose: String) async throws
    -> MLSStateRecordValue
  {
    let envelope = try Self.decode(bytes)
    let header = envelope.header
    let groupID = await group.groupID
    guard header.objectID == objectID, header.purpose == purpose,
      header.groupID == groupID
    else { throw AppleDeviceError.conflictingReplay }
    let material: GroupStateRecordKey
    do {
      material = try await group.stateRecordKey(
        epoch: header.groupEpoch, groupContext: header.groupContext)
    } catch GroupStateRecordKeyError.unavailable {
      throw AppleDeviceError.stateRecoveryRequired
    } catch GroupStateRecordKeyError.contextMismatch { throw AppleDeviceError.conflictingReplay }
    guard material.groupID == header.groupID, material.epoch == header.groupEpoch,
      material.groupContext == header.groupContext,
      let writer = material.members.first(where: { $0.deviceID == header.writer })
    else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    let aad = try Self.canonical(header)
    guard
      writer.verify(
        envelope.signature, over: Self.signatureStatement(aad: aad, sealed: envelope.sealed))
    else {
      throw AppleDeviceError.conflictingReplay
    }
    let key = Self.objectKey(material.secret, header: header, aad: aad)
    let box = try AES.GCM.SealedBox(combined: envelope.sealed)
    let plaintext = try AES.GCM.open(box, using: key, authenticating: aad)
    return MLSStateRecordValue(plaintext: plaintext, header: header)
  }

  /// Parses a size/schema-checked header without authenticating its signature or ciphertext.
  /// Use `open` plus the authority's current digest endorsement before trusting the state.
  public static func header(of bytes: Data) throws -> MLSStateRecordHeader {
    try decode(bytes).header
  }

  /// Returns the 32-byte SHA-256 digest of the exact supplied bytes; it does not authenticate them.
  public static func digest(_ bytes: Data) -> Data { Data(SHA256.hash(data: bytes)) }

  private static func decode(_ bytes: Data) throws -> MLSStateRecordEnvelope {
    guard !bytes.isEmpty, bytes.count <= 1_048_576 else {
      throw AppleDeviceError.invalidState("state record size")
    }
    let value = try JSONDecoder().decode(MLSStateRecordEnvelope.self, from: bytes)
    guard value.header.version == 1, !value.header.groupID.isEmpty,
      !value.header.groupContext.isEmpty, !value.header.objectID.isEmpty,
      !value.header.purpose.isEmpty, value.signature.count == 64
    else {
      throw AppleDeviceError.invalidState("state record envelope")
    }
    return value
  }

  private static func objectKey(_ secret: Data, header: MLSStateRecordHeader, aad: Data)
    -> SymmetricKey
  {
    HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: secret), salt: Data(header.groupID.utf8),
      info: Data("memoshi.cloudkit-state.object.v1".utf8) + aad, outputByteCount: 32)
  }

  private static func signatureStatement(aad: Data, sealed: Data) -> Data {
    var bytes = Data("memoshi.cloudkit-state.signature.v1".utf8)
    withUnsafeBytes(of: UInt64(aad.count).bigEndian) { bytes.append(contentsOf: $0) }
    bytes.append(aad)
    bytes.append(sealed)
    return bytes
  }

  private static func canonical<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }
}
