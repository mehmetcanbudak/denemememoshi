import CryptoKit
import Foundation
import MemoshiMLS
import MemoshiProtocol

/// A genuine native seal plus its durable transport order. Construction/decoding is not proof
/// of sender authority: authenticate the complete routing metadata before accepting a feed.
public struct DeviceSealedApplication: Codable, Hashable, Sendable {
  /// Selects the host dispatch contract; both kinds occupy the same native sender feed.
  public enum Kind: String, Codable, Hashable, Sendable {
    /// Host-defined ordered transport envelope, with host-validated routing AAD.
    case orderedTransport
    /// Native application payload, including DeviceNode's authenticated addressed messages.
    case rawNative
  }

  /// Exact native ciphertext and its declared MLS membership epoch.
  public var message: MLSSealedMessage
  /// Positive device-local seal number, monotonic across epochs rather than a replica rseq.
  public var ordinal: UInt64
  /// Zero starts a native epoch; otherwise names the exact preceding seal by this sender.
  public var previousOrdinal: UInt64
  /// Public MLS AAD that the authenticated native open must recover byte-for-byte.
  public var authenticatedData: Data
  /// Dispatch contract bound by the publication signature and prefix digest.
  public var kind: Kind
  /// Raw DeviceNode messages carry their source-validated recipient. Unknown raw AAD has none
  /// and requires an explicit host consumer; it must never become an implicit no-op.
  public var recipient: DeviceAddress?

  /// Stores a feed packet without authenticating its sender, ciphertext, or routing fields.
  public init(
    message: MLSSealedMessage, ordinal: UInt64, previousOrdinal: UInt64,
    authenticatedData: Data, kind: Kind, recipient: DeviceAddress? = nil
  ) {
    self.message = message
    self.ordinal = ordinal
    self.previousOrdinal = previousOrdinal
    self.authenticatedData = authenticatedData
    self.kind = kind
    self.recipient = recipient
  }
}

/// Claimed sender and full native feed packet; readers still verify membership and MLS binding.
public struct DeviceApplicationFeedDelivery: Codable, Hashable, Sendable {
  /// Exact device keys expected to match the authenticated native sender for this epoch.
  public var sender: DevicePeer
  /// Ciphertext plus complete sender-order and dispatch metadata, without recipient filtering.
  public var application: DeviceSealedApplication

  /// Pairs transport-supplied values; construction does not establish sender authority.
  public init(sender: DevicePeer, application: DeviceSealedApplication) {
    self.sender = sender
    self.application = application
  }
}

/// An authority's accepted-prefix snapshot, not a producer's optimistic tail. Once closed,
/// its cutoffs and digests are immutable; readers must checkpoint the full feed before retirement.
public struct DeviceApplicationEpochBoundary: Codable, Hashable, Sendable {
  /// Authority group whose accepted application prefix is described.
  public var groupID: String
  /// Native MLS membership epoch, not a conversation lease epoch or replication sequence.
  public var epoch: UInt64
  /// Exact authenticated native context; nil is accepted only for an empty-feed boundary.
  public var groupContext: Data?
  /// Last accepted seal ordinal for each sender; a missing sender has cutoff zero.
  public var cutoffs: [DeviceID: UInt64]
  /// Accepted length-framed prefix checksum per sender; absence denotes the initial checksum.
  public var digests: [DeviceID: Data]

  /// Whether membership ordering has closed this epoch against new publications.
  public var isClosed: Bool
  /// Stores a boundary claim. Callers must authenticate its authority and validate context,
  /// sender set, cutoffs and digests before treating it as a retirement boundary.
  public init(
    groupID: String, epoch: UInt64, groupContext: Data?, cutoffs: [DeviceID: UInt64],
    digests: [DeviceID: Data] = [:], isClosed: Bool = true
  ) {
    self.groupID = groupID
    self.epoch = epoch
    self.groupContext = groupContext
    self.cutoffs = cutoffs
    self.digests = digests
    self.isClosed = isClosed
  }
}

/// Created by DeviceGroup while its mutation gate is held. Readers may fetch/verify remote
/// records and use already-checkpointed key/anchor fast paths, but must not reenter that gate.
public struct DeviceApplicationEpochRequest: Codable, Sendable {
  /// Group identity whose native state is held by the requesting DeviceGroup.
  public let groupID: String
  /// Native membership epoch whose complete sender feeds are requested.
  public let epoch: UInt64
  /// Exact current native context to bind the authority's returned boundary.
  public let groupContext: Data
  /// Full epoch roster, including peers whose messages target another recipient.
  public let members: [DevicePeer]
  /// Last checkpointed seal ordinal per sender in this epoch; missing entries start at zero.
  public let after: [DeviceID: UInt64]
  /// Checkpointed prefix digests corresponding to `after`, for detecting changed history.
  public let afterDigests: [DeviceID: Data]
  /// Requires an immutable closed cutoff before a membership transition can retire old keys.
  public let requiresClosed: Bool

  /// Captures the requester's checkpointed cursor and roster; does not perform a remote read.
  public init(
    groupID: String, epoch: UInt64, groupContext: Data, members: [DevicePeer],
    after: [DeviceID: UInt64], afterDigests: [DeviceID: Data], requiresClosed: Bool
  ) {
    self.groupID = groupID
    self.epoch = epoch
    self.groupContext = groupContext
    self.members = members
    self.after = after
    self.afterDigests = afterDigests
    self.requiresClosed = requiresClosed
  }
}

/// Complete requested sender-feed suffix and one accepted boundary, still subject to native
/// authentication and exact cursor/digest checks by DeviceGroup.
public struct DeviceApplicationEpochFeed: Sendable {
  /// Authority-accepted prefix shared by all deliveries in this result.
  public var boundary: DeviceApplicationEpochBoundary
  /// Full native packets after the request cursors and at or below each sender's cutoff.
  public var deliveries: [DeviceApplicationFeedDelivery]

  /// Bundles a boundary with its deliveries without opening or consuming any application.
  public init(
    boundary: DeviceApplicationEpochBoundary, deliveries: [DeviceApplicationFeedDelivery]
  ) {
    self.boundary = boundary
    self.deliveries = deliveries
  }
}

/// Fetches an authenticated boundary and complete sender suffix while DeviceGroup holds its
/// mutation gate. Must not reenter that gate or dispatch domain consumers from the callback.
public typealias DeviceApplicationEpochReader =
  @Sendable (DeviceApplicationEpochRequest) async throws
  -> DeviceApplicationEpochFeed

/// Must durably publish the complete ciphertext feed under the same head CAS before any live
/// carrier emits it. A rejected/unaccepted old-epoch seal is held, never silently discarded.
/// This callback only publishes/acknowledges feed state: it must not await Node domain
/// dispatch or another Node send while its caller holds the serial outbound gate.
public typealias DeviceApplicationSender = @Sendable (DeviceSealedApplication) async throws -> Void

/// Failures of durable sender ordering or authority publication; none is a domain receipt.
public enum DeviceApplicationFeedError: Error, Codable, Equatable, Sendable {
  /// The retained consumption evidence already covers this ciphertext.
  case alreadyConsumed
  /// Packet is retained for recovery but its preceding sender cursor has not been reached.
  case missingPredecessor(sender: DeviceID, epoch: UInt64, expected: UInt64, actual: UInt64)
  /// Returned feed does not reach the exact required cutoff and prefix digests.
  case incompleteBoundary
  /// Required authority feed, roster or retained epoch material is unavailable.
  case unavailable
  /// Publication bytes, sender binding, routing or prefix history conflict with accepted data.
  case conflictingPublication
  /// A publication was not accepted before its native membership epoch closed.
  case unacceptedOldEpoch
}

/// Domain-consumer outcome after native authentication/checkpointing, not a transport send ACK.
public enum DeviceApplicationDisposition: Equatable, Sendable {
  /// Native checkpoint and the domain's definitive consumption are durable.
  case consumed
  /// Native plaintext remains durable, but current policy/history/authority cannot consume it.
  case pendingRecovery
}

/// Checkpointed routing bound to a native inbox item; it does not itself authorize domain effects.
public struct DeviceApplicationRouting: Codable, Hashable, Sendable {
  /// Device identity recovered and matched to the native sender credential.
  public let sender: DeviceID
  /// Native MLS membership epoch under which the ciphertext was authenticated.
  public let epoch: UInt64
  /// Sender's positive seal ordinal, independent of conversation replication order.
  public let ordinal: UInt64
  /// Previous seal in this sender's epoch feed, or zero for the epoch's first packet.
  public let previousOrdinal: UInt64
  /// Consumer contract validated alongside the native plaintext and AAD.
  public let kind: DeviceSealedApplication.Kind
  /// Authenticated DeviceNode recipient, or nil for a host-owned dispatch contract.
  public let recipient: DeviceAddress?
}

/// A transport accepted-prefix checksum, not an alternative to MLS authentication. Every
/// implementation uses these same length-framed fields so the closed cutoff can detect a
/// changed earlier ciphertext even when a malicious member preserves the final ordinal.
public enum DeviceApplicationFeedDigest {
  /// All-zero 32-byte starting checksum for each sender in each native membership epoch.
  public static let initial = Data(repeating: 0, count: 32)
  private static let domain = Data("memoshi.sender-feed.hash.v1\0".utf8)

  /// Extends a 32-byte prefix with the exact sender keys, epoch, ordinals, routing, AAD and
  /// ciphertext. Throws for an invalid starting digest or recipient encoding; does not verify MLS.
  public static func advancing(
    _ previous: Data, sender: DevicePeer, application: DeviceSealedApplication
  ) throws -> Data {
    guard previous.count == 32 else { throw DeviceApplicationFeedError.conflictingPublication }
    var hash = SHA256()
    hash.update(data: domain)
    hash.update(data: previous)
    func field(_ bytes: Data) {
      var length = UInt64(bytes.count).bigEndian
      withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
      hash.update(data: bytes)
    }
    func number(_ value: UInt64) {
      var bytes = value.bigEndian
      withUnsafeBytes(of: &bytes) { hash.update(data: Data($0)) }
    }
    field(Data(sender.deviceID.rawValue.utf8))
    field(sender.signingKey)
    field(sender.agreementKey)
    number(application.message.groupEpoch)
    number(application.ordinal)
    number(application.previousOrdinal)
    field(Data(application.kind.rawValue.utf8))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    field(try encoder.encode(application.recipient))
    field(application.authenticatedData)
    field(application.message.ciphertext)
    return Data(hash.finalize())
  }
}

/// A replayable immutable publication signed by the device, independently of relay sockets.
public struct DeviceApplicationPublication: Codable, Hashable, Sendable {
  /// Group identity included in the signed publication statement.
  public var groupID: String
  /// Exact native group context binding the publication to its membership epoch.
  public var groupContext: Data
  /// Device keys used to verify the statement; current enrollment is checked separately.
  public var sender: DevicePeer
  /// Complete seal and routing record, replayable only with these exact field values.
  public var application: DeviceSealedApplication
  /// Device signature over the domain-separated group/context and application digest.
  public var signature: Data

  /// Signs the exact supplied record. Does not validate native ciphertext or publish it;
  /// authority acceptance must precede live delivery, and replay must retain the signed bytes.
  public static func signed(
    groupID: String, groupContext: Data, identity: DeviceIdentity,
    application: DeviceSealedApplication
  ) throws -> DeviceApplicationPublication {
    var value = DeviceApplicationPublication(
      groupID: groupID, groupContext: groupContext, sender: identity.peer,
      application: application, signature: Data())
    value.signature = try identity.sign(value.statement())
    return value
  }

  func statement() throws -> Data {
    var hash = SHA256()
    hash.update(data: Data("memoshi.sender-feed.publication.v1\0".utf8))
    for value in [Data(groupID.utf8), groupContext] {
      var size = UInt64(value.count).bigEndian
      withUnsafeBytes(of: &size) { hash.update(data: Data($0)) }
      hash.update(data: value)
    }
    hash.update(
      data: try DeviceApplicationFeedDigest.advancing(
        DeviceApplicationFeedDigest.initial, sender: sender, application: application))
    return Data(hash.finalize())
  }
}
