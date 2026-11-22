import CryptoKit
import Foundation
import MemoshiDevice
import MemoshiProtocol

/// Ordering belongs to the authenticated sender/recipient stream, never CloudKit callback order.
public struct DeviceDelivery: Codable, Hashable, Sendable {
  /// Stable deduplication identity bound to the complete delivery by replay tracking.
  public let messageID: String
  /// Authenticated originating device, forming part of the ordered stream identity.
  public let sender: DeviceID
  /// Intended device, forming part of the ordered stream identity.
  public let recipient: DeviceID
  /// Sender/recipient-local ordering namespace, limited to 128 UTF-8 bytes by replay admission.
  public let stream: String
  /// Positive, contiguous application sequence within this sender/recipient/stream.
  public let sequence: UInt64
  /// MLS epoch in which the application delivery was created.
  public let groupEpoch: UInt64
  /// Optional expiry in Unix milliseconds, enforced by the host before effects.
  public let expiresAt: Int64?
  /// Original application bytes supplied to the host; these are plaintext after MLS opening.
  public let message: Data

  /// Stores delivery metadata and plaintext without validating or applying it.
  /// Authentication, replay admission, and current-policy checks remain receiver responsibilities.
  public init(
    messageID: String, sender: DeviceID, recipient: DeviceID, stream: String,
    sequence: UInt64, groupEpoch: UInt64, expiresAt: Int64?, message: Data
  ) {
    self.messageID = messageID
    self.sender = sender
    self.recipient = recipient
    self.stream = stream
    self.sequence = sequence
    self.groupEpoch = groupEpoch
    self.expiresAt = expiresAt
    self.message = message
  }

  /// SHA-256 of only the original message bytes, used to match a host-apply receipt.
  public var digest: Data { Data(SHA256.hash(data: message)) }
  var streamKey: String { sender.rawValue + ":" + recipient.rawValue + ":" + stream }
}

/// Returned only after the host atomically applied or explicitly expired/refused the original
/// message under current policy/lease/revocation state. The host MUST deduplicate messageID
/// in the same transaction as its mutation: a crash before transport acknowledgement replays it.
public struct DeviceApplyReceipt: Hashable, Sendable {
  /// Exact delivery identifier that the host durably applied or explicitly refused.
  public let messageID: String
  /// SHA-256 of that delivery's original message bytes, not a transport ciphertext digest.
  public let digest: Data

  /// Records the host's acknowledgement evidence; constructing this value alone neither applies
  /// a message nor proves a durable host transaction.
  public init(messageID: String, digest: Data) {
    self.messageID = messageID
    self.digest = digest
  }
}

/// Current-policy reasons for recording a visible refusal without dispatching application effects.
public enum DeviceDeliveryRejection: String, Sendable {
  case expired, staleEpoch, revoked
}

/// Host-owned transactional application boundary. Implementations must deduplicate the delivery ID
/// atomically with effects/refusals before returning a receipt; throws leave transport replay pending.
public protocol DeviceMessageApplying: Sendable {
  /// Applies the original message under current host authority/policy and returns its durable receipt.
  func apply(_ delivery: DeviceDelivery) async throws -> DeviceApplyReceipt
  /// Persist a visible refusal/expiry without dispatching the message or granting an effect.
  func reject(_ delivery: DeviceDelivery, reason: DeviceDeliveryRejection) async throws
    -> DeviceApplyReceipt
}

/// Fail-closed lifecycle, replay, membership, authority, and durable-state failures at Apple boundaries.
public enum AppleDeviceError: Error, Equatable, Sendable {
  case disabled
  case closed
  case invalidState(String)
  case conflictingReplay
  case cursorGap(expected: UInt64, actual: UInt64)
  case staleEpoch
  case revoked
  case authorityConflict
  case authorityUnavailable
  case accountChanged
  case persistenceFailed
  case stateRecoveryRequired
  /// A send's message ID is unknown to this device and at or below the greatest ID whose send
  /// history was retired. It may name a message that was already sent, so it is refused and
  /// never given a second sequence. Mint IDs with `DeviceApplicationTransport.nextMessageID()`.
  case retiredMessageIdentifier
}

/// A deterministic state machine used by the durable MLS host. It does not simulate CloudKit.
/// Receipt means host-applied, not fetched, decrypted, displayed or socket-written.
/// Message identities are kept for buffered deliveries and for the delivery at each stream's
/// cursor. Once the cursor has moved past a delivery its identity is retired: the cursor alone
/// then refuses that ID, like every other unknown ID at or below it.
public struct DeviceReplayState: Codable, Sendable {
  private struct Applied: Codable, Sendable {
    var sequence: UInt64
    var messageID: String
    var digest: Data
  }

  private var pending: [String: [UInt64: DeviceDelivery]] = [:]
  private var applied: [String: Applied] = [:]
  private var identities: [String: Data] = [:]

  /// Starts an empty in-memory replay machine with zero cursors; construction persists nothing.
  public init() {}

  /// Buffers gaps without advancing a cursor; conflicting reuse always fails closed.
  public mutating func receive(_ delivery: DeviceDelivery) throws {
    guard delivery.sequence > 0, !delivery.stream.isEmpty,
      delivery.stream.utf8.count <= 128, delivery.message.count <= 1_048_576,
      !delivery.messageID.isEmpty
    else { throw AppleDeviceError.invalidState("delivery") }
    let identity = try Self.identity(delivery)
    if let known = identities[delivery.messageID] {
      guard known == identity else { throw AppleDeviceError.conflictingReplay }
      return
    }
    let key = delivery.streamKey
    let cursor = applied[key]?.sequence ?? 0
    if delivery.sequence <= cursor {
      // Unknown IDs below the retained cursor are not accepted as a second history.
      throw AppleDeviceError.conflictingReplay
    }
    if let existing = pending[key]?[delivery.sequence] {
      guard existing == delivery else { throw AppleDeviceError.conflictingReplay }
      return
    }
    identities[delivery.messageID] = identity
    pending[key, default: [:]][delivery.sequence] = delivery
  }

  /// Returns only the next contiguous pending delivery per stream, sorted by stream identity.
  /// Buffered gaps remain pending; reading ready values does not advance any cursor.
  public func ready() -> [DeviceDelivery] {
    pending.compactMap { key, values in
      values[(applied[key]?.sequence ?? 0) + 1]
    }.sorted { $0.streamKey < $1.streamKey }
  }

  /// Returns the last host-receipted sequence for this exact stream, or zero before acknowledgement.
  public func cursor(sender: DeviceID, recipient: DeviceID, stream: String) -> UInt64 {
    applied[sender.rawValue + ":" + recipient.rawValue + ":" + stream]?.sequence ?? 0
  }

  /// A receipt for N+1 is never allowed to skip unapplied N, even if it arrived first.
  public mutating func acknowledge(_ delivery: DeviceDelivery, receipt: DeviceApplyReceipt) throws {
    let key = delivery.streamKey
    guard receipt.messageID == delivery.messageID, receipt.digest == delivery.digest,
      pending[key]?[delivery.sequence] == delivery
    else { throw AppleDeviceError.conflictingReplay }
    let expected = (applied[key]?.sequence ?? 0) + 1
    guard delivery.sequence == expected else {
      throw AppleDeviceError.cursorGap(expected: expected, actual: delivery.sequence)
    }
    if let previous = applied[key] { identities[previous.messageID] = nil }
    applied[key] = Applied(
      sequence: delivery.sequence, messageID: delivery.messageID, digest: delivery.digest)
    pending[key]?[delivery.sequence] = nil
  }

  /// The message at this stream's cursor: the last one the host applied, if any.
  func appliedMessageID(streamKey: String) -> String? { applied[streamKey]?.messageID }

  /// Whether taking this delivery in needs room in a bounded inbox. It needs none when the
  /// stream's cursor already covers its sequence, because nothing is buffered then, and none
  /// when it is the delivery the cursor waits for and that sequence is not buffered yet:
  /// applying it is what makes room, so a full inbox must never refuse it.
  func needsRoom(_ delivery: DeviceDelivery) -> Bool {
    let key = delivery.streamKey
    let cursor = applied[key]?.sequence ?? 0
    guard delivery.sequence > cursor else { return false }
    return delivery.sequence - 1 != cursor || pending[key]?[delivery.sequence] != nil
  }

  /// Whether the stream's cursor has moved past this delivery's sequence.
  func hasPassed(_ delivery: DeviceDelivery) -> Bool {
    delivery.sequence < applied[delivery.streamKey]?.sequence ?? 0
  }

  /// How many streams hold, buffered and not yet applied, the delivery their cursor waits for.
  var readyCount: Int {
    pending.reduce(0) { $0 + ($1.value[(applied[$1.key]?.sequence ?? 0) + 1] == nil ? 0 : 1) }
  }

  /// How many message identities are retained: buffered deliveries and one per stream cursor.
  var retainedIdentityCount: Int { identities.count }

  private static func identity(_ delivery: DeviceDelivery) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return Data(SHA256.hash(data: try encoder.encode(delivery)))
  }
}

/// The encrypted body on every direct, relay or CloudKit carrier. Noise is only the pairing
/// authenticator; these application and acknowledgement bodies are sealed by real MLS.
struct DeviceGroupEnvelope: Codable, Sendable {
  enum Body: Codable, Sendable {
    case application(DeviceDelivery)
    case acknowledgement(
      sender: DeviceID, recipient: DeviceID, stream: String, sequence: UInt64,
      messageID: String, digest: Data)
  }
  let version: Int
  let body: Body
}

enum DeviceTransportPayloadKind: String, Codable, Sendable { case orderedTransport, rawNative }

/// Ordering metadata is signed before ratchet consumption and is also genuine MLS AAD.
/// The ordinal is allocated by DeviceGroup inside its Native seal gate, including control seals.
struct DeviceTransportHeader: Codable, Hashable, Sendable {
  let version: Int
  let groupID: String
  let groupEpoch: UInt64
  let sender: DeviceID
  let recipient: DeviceID?
  let ordinal: UInt64
  let kind: DeviceTransportPayloadKind

  init(
    groupID: String, groupEpoch: UInt64, sender: DeviceID, recipient: DeviceID?,
    ordinal: UInt64, kind: DeviceTransportPayloadKind = .orderedTransport
  ) {
    version = 1
    self.groupID = groupID
    self.groupEpoch = groupEpoch
    self.sender = sender
    self.recipient = recipient
    self.ordinal = ordinal
    self.kind = kind
  }

  func authenticatedData() throws -> Data {
    Data(
      ("memoshi.device-transport.aad.v1\u{0}" + (try ProtocolCoding.canonicalText(of: self))).utf8)
  }

  init(authenticatedData: Data) throws {
    let prefix = Data("memoshi.device-transport.aad.v1\u{0}".utf8)
    guard authenticatedData.starts(with: prefix) else {
      throw AppleDeviceError.invalidState("transport AAD domain")
    }
    self = try JSONDecoder().decode(
      Self.self, from: Data(authenticatedData.dropFirst(prefix.count)))
    guard try self.authenticatedData() == authenticatedData else {
      throw AppleDeviceError.conflictingReplay
    }
  }
}

struct DeviceTransportPacket: Codable, Sendable {
  let header: DeviceTransportHeader
  let ciphertext: Data
  let signature: Data
  let previousOrdinal: UInt64
  let nativeAuthenticatedData: Data
  let nativeRecipient: DeviceAddress?

  var position: DeviceSenderFeedPosition {
    DeviceSenderFeedPosition(
      groupID: header.groupID, groupEpoch: groupEpoch, sender: header.sender,
      ordinal: header.ordinal, previousOrdinal: previousOrdinal)
  }

  var groupEpoch: UInt64 { header.groupEpoch }

  init(
    header: DeviceTransportHeader, previousOrdinal: UInt64, ciphertext: Data,
    authenticatedData: Data? = nil, nativeRecipient: DeviceAddress? = nil, signature: Data
  ) throws {
    self.header = header
    self.previousOrdinal = previousOrdinal
    self.ciphertext = ciphertext
    nativeAuthenticatedData = try authenticatedData ?? header.authenticatedData()
    self.nativeRecipient = nativeRecipient
    self.signature = signature
  }

  init(
    header: DeviceTransportHeader, previousOrdinal: UInt64, ciphertext: Data,
    authenticatedData: Data? = nil, nativeRecipient: DeviceAddress? = nil, identity: DeviceIdentity
  ) throws {
    guard header.sender == identity.deviceID else { throw AppleDeviceError.conflictingReplay }
    self.header = header
    self.previousOrdinal = previousOrdinal
    self.ciphertext = ciphertext
    nativeAuthenticatedData = try authenticatedData ?? header.authenticatedData()
    self.nativeRecipient = nativeRecipient
    signature = try identity.sign(
      Self.signingData(
        header: header, previousOrdinal: previousOrdinal,
        authenticatedData: nativeAuthenticatedData, ciphertext: ciphertext,
        recipient: nativeRecipient))
  }

  init(decoding bytes: Data) throws {
    guard !bytes.isEmpty, bytes.count <= 1_048_576 else {
      throw AppleDeviceError.invalidState("MLS carrier size")
    }
    self = try JSONDecoder().decode(Self.self, from: bytes)
    guard header.version == 1, !header.groupID.isEmpty, header.groupID.utf8.count <= 128,
      header.recipient != header.sender, header.ordinal > 0, !ciphertext.isEmpty,
      previousOrdinal < header.ordinal, nativeAuthenticatedData.count <= 4_096,
      signature.count == 64
    else { throw AppleDeviceError.invalidState("MLS carrier header") }
    if header.kind == .orderedTransport {
      guard header.recipient != nil, nativeRecipient == nil,
        try header.authenticatedData() == nativeAuthenticatedData
      else {
        throw AppleDeviceError.conflictingReplay
      }
    } else if header.recipient != nil {
      throw AppleDeviceError.invalidState("raw feed routing")
    }
  }

  func verify(signer: DevicePeer) throws {
    guard signer.deviceID == header.sender,
      signer.verify(
        signature,
        over: try Self.signingData(
          header: header, previousOrdinal: previousOrdinal,
          authenticatedData: nativeAuthenticatedData, ciphertext: ciphertext,
          recipient: nativeRecipient))
    else {
      throw AppleDeviceError.conflictingReplay
    }
  }

  /// Whether both packets carry the same seal in every signed field. Device signatures are
  /// randomized, so one seal can exist under several valid signatures; callers that need the
  /// signer authenticated verify the signature separately.
  func sealsSameContent(as other: DeviceTransportPacket) -> Bool {
    header == other.header && previousOrdinal == other.previousOrdinal
      && ciphertext == other.ciphertext
      && nativeAuthenticatedData == other.nativeAuthenticatedData
      && nativeRecipient == other.nativeRecipient
  }

  private static func signingData(
    header: DeviceTransportHeader, previousOrdinal: UInt64, authenticatedData: Data,
    ciphertext: Data,
    recipient: DeviceAddress?
  ) throws -> Data {
    var statement = Data("memoshi.device-transport.signature.v1\u{0}".utf8)
    statement.append(contentsOf: SHA256.hash(data: try header.authenticatedData()))
    var predecessor = previousOrdinal.bigEndian
    withUnsafeBytes(of: &predecessor) { statement.append(contentsOf: $0) }
    statement.append(contentsOf: SHA256.hash(data: authenticatedData))
    struct Routing: Encodable { let recipient: DeviceAddress? }
    let routing = Data(try ProtocolCoding.canonicalText(of: Routing(recipient: recipient)).utf8)
    statement.append(contentsOf: SHA256.hash(data: routing))
    statement.append(contentsOf: SHA256.hash(data: ciphertext))
    return statement
  }

  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bytes = try encoder.encode(self)
    guard bytes.count <= 1_048_576 else { throw AppleDeviceError.invalidState("MLS carrier size") }
    return bytes
  }
}

struct DeviceCiphertext: Codable, Hashable, Sendable {
  let bytes: Data
  var identifier: String {
    "m." + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
