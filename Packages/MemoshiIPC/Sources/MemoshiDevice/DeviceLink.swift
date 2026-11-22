import CryptoKit
import Foundation
import MemoshiProtocol

/// A live Noise carrier. The independently durable CloudKit/racer carrier lives in
/// MemoshiDeviceApple; all application carriers carry genuine MLS ciphertext.
public enum LinkRoute: String, Codable, Hashable, Sendable {
  /// A direct authenticated TCP, Bonjour or tailnet connection.
  case direct
  /// End-to-end encrypted frames through the relay.
  case relay
}

/// The first byte of every frame on a link or pairing channel.
enum LinkFrameKind: UInt8 {
  case handshakeInitiation = 0x01
  case handshakeResponse = 0x02
  case transport = 0x03
  /// A relay responder gave up waiting for the handshake's last frame; the link never existed.
  case abandoned = 0x04
  case pairingInitiation = 0x11
  case pairingResponse = 0x12
}

/// Genuine group-encrypted application messages inside an authenticated Noise carrier.
/// Pairing alone uses typed Noise-only bootstrap messages before the real MLS Welcome.
public actor DeviceLink {
  /// The device at the other end.
  public nonisolated let peer: DevicePeer
  /// How the link reaches it.
  public nonisolated let route: LinkRoute
  /// The Noise handshake hash, for channel binding.
  public nonisolated let handshakeHash: Data
  private var transport: NoiseTransport
  private let channel: any FrameChannel
  private let encoder = ProtocolCoding.makeEncoder()
  private let decoder = ProtocolCoding.makeDecoder()
  private var isClosed = false
  private let group: DeviceGroup?
  private let beforeApplication: (@Sendable (UInt64) async throws -> Void)?
  private let sending = SerialGate()
  private let receiving = SerialGate()
  private struct ReceivedReceipt {
    var id: String
    var conversation: ConversationID?
    var rseq: Int64?
  }
  private var receipts: [ULID: [ReceivedReceipt]] = [:]
  private struct FragmentAssembly {
    var digest: Data
    var total: Int
    var count: Int
    var next: Int
    var bytes: Data
  }
  private var assembly: FragmentAssembly?

  /// A message sent as several Noise messages, because Noise leaves fragmentation to the
  /// application. Every fragment's plaintext is
  /// `[marker][SHA-256 of the whole message, 32][total length, 4][index, 2][count, 2][chunk]`,
  /// integers big-endian, every chunk but the last `fragmentChunkSize` bytes. The header is
  /// inside the Noise message, so the length is authenticated, and Noise's own counter fixes
  /// the order: a truncated, reordered or spliced sequence is refused and nothing of it is
  /// delivered. A receiver buffers at most `maximum` bytes.
  private struct Fragmented {
    let marker: UInt8
    /// The smallest and the largest whole message this kind carries.
    let minimum: Int
    let maximum: Int
    let noun: String
  }
  /// The first byte of a refusal notice among pairing messages; see ``sendPairingRefusal(_:)``.
  private static let pairingRefusalMarker: UInt8 = 0x23
  private static let fragmentHeaderSize = 41
  private static let fragmentChunkSize = 60 * 1024
  private static let maximumApplicationBytes = 128 * 1024
  private static let applicationFragments = Fragmented(
    marker: 0x21, minimum: 1, maximum: maximumApplicationBytes, noun: "native application")
  /// A pairing message that fits one Noise message is sent as that one message, unchanged; a
  /// larger one (a `pair.welcome` grows with every member of the group) only in this form.
  private static let bootstrapFragments = Fragmented(
    marker: 0x22, minimum: NoiseTransport.maximumPlaintext + 1,
    maximum: PairingExchange.maximumMessageBytes, noun: "pairing")

  /// The prologue every link handshake binds.
  static let prologue = Data("memoshi.device-link.v1".utf8)

  /// The initiator's first transport frame. A recorded IK initiation can be replayed; this frame
  /// needs the handshake's fresh ephemeral key, so only a live initiator can produce it.
  private static let keyConfirmation = Data([0x20])

  init(
    peer: DevicePeer, route: LinkRoute, transport: NoiseTransport, channel: any FrameChannel,
    group: DeviceGroup? = nil,
    beforeApplication: (@Sendable (UInt64) async throws -> Void)? = nil
  ) {
    self.peer = peer
    self.route = route
    self.handshakeHash = transport.handshakeHash
    self.transport = transport
    self.channel = channel
    self.group = group
    self.beforeApplication = beforeApplication
  }

  /// Opens a link to a paired peer: Noise IK, with this device's ID as the first payload.
  public static func initiate(
    identity: DeviceIdentity, peer: DevicePeer, group: DeviceGroup,
    route: LinkRoute, channel: any FrameChannel,
    beforeApplication: (@Sendable (UInt64) async throws -> Void)? = nil
  ) async throws -> DeviceLink {
    do {
      guard group.localPeer == identity.peer,
        await group.member(peer.deviceID, agreementKey: peer.agreementKey) == peer
      else { throw DeviceLayerError.unknownPeer }
      var handshake = try NoiseHandshake(
        pattern: .link, initiator: true, prologue: prologue, localStatic: identity.agreementKey(),
        remoteStatic: peer.agreementPublicKey)
      let first = try handshake.writeMessage(payload: Data(identity.deviceID.rawValue.utf8))
      try channel.send(Data([LinkFrameKind.handshakeInitiation.rawValue]) + first)
      let reply = try await channel.receive()
      guard reply.first == LinkFrameKind.handshakeResponse.rawValue else {
        throw DeviceLayerError.protocolViolation("expected a handshake response")
      }
      _ = try handshake.readMessage(Data(reply.dropFirst()))
      let link = DeviceLink(
        peer: peer, route: route, transport: try handshake.split(), channel: channel,
        group: group, beforeApplication: beforeApplication)
      try await link.sendPlaintext(keyConfirmation)
      return link
    } catch {
      channel.close()
      throw error
    }
  }

  /// The initiator's Noise key and device ID must match a current native group member, and its
  /// key confirmation must decrypt before the link exists for the caller. That last handshake
  /// frame has ten seconds, counted from the arrival of the first one, never from listening.
  /// Closing a relay stream is local, so a relay responder that gives up first sends one
  /// `abandoned` frame: an initiator that reads the stored response later ends its link
  /// instead of keeping a route that goes nowhere. That notice is lost when the responder is
  /// offline at its deadline, or restarts, so it also answers `abandoned` to a transport frame
  /// that opens a relay stream: the frame of a link this device does not have.
  public static func accept(
    identity: DeviceIdentity, group: DeviceGroup, route: LinkRoute, channel: any FrameChannel,
    beforeApplication: (@Sendable (UInt64) async throws -> Void)? = nil
  ) async throws -> DeviceLink {
    try await accept(
      identity: identity, group: group, route: route, channel: channel,
      beforeApplication: beforeApplication, confirmationDeadline: .seconds(10))
  }

  static func accept(
    identity: DeviceIdentity, group: DeviceGroup, route: LinkRoute, channel: any FrameChannel,
    beforeApplication: (@Sendable (UInt64) async throws -> Void)? = nil,
    confirmationDeadline: Duration
  ) async throws -> DeviceLink {
    do {
      guard group.localPeer == identity.peer else { throw DeviceLayerError.unknownPeer }
      let first = try await channel.receive()
      let deadline = ContinuousClock.now + confirmationDeadline
      guard first.first == LinkFrameKind.handshakeInitiation.rawValue else {
        // Only a transport frame is answered, so two devices never answer each other.
        if route == .relay, first.first == LinkFrameKind.transport.rawValue {
          try? channel.send(Data([LinkFrameKind.abandoned.rawValue]))
        }
        throw DeviceLayerError.protocolViolation("expected a handshake initiation")
      }
      var handshake = try NoiseHandshake(
        pattern: .link, initiator: false, prologue: prologue, localStatic: identity.agreementKey())
      let payload = try handshake.readMessage(Data(first.dropFirst()))
      guard let claimed = try? DeviceID(String(decoding: payload, as: UTF8.self)),
        let remote = handshake.remoteStatic,
        let peer = await group.member(claimed, agreementKey: remote.rawRepresentation),
        peer.agreementKey == remote.rawRepresentation
      else { throw DeviceLayerError.unknownPeer }
      let reply = try handshake.writeMessage()
      try channel.send(Data([LinkFrameKind.handshakeResponse.rawValue]) + reply)
      let link = DeviceLink(
        peer: peer, route: route, transport: try handshake.split(), channel: channel,
        group: group, beforeApplication: beforeApplication)
      // A recorded initiation, or one whose confirmation was lost, never confirms.
      let expired = Locked(false)
      let confirmation: Data
      do {
        confirmation = try await withThrowingTaskGroup(of: Data.self) { tasks in
          tasks.addTask { try await link.receivePlaintext() }
          tasks.addTask {
            try await Task.sleep(until: deadline, clock: .continuous)
            expired.withLock { $0 = true }
            if route == .relay {
              try? channel.send(Data([LinkFrameKind.abandoned.rawValue]))
            }
            channel.close()  // Ends the receive even on a carrier that ignores cancellation.
            throw DeviceLayerError.timeout("link key confirmation")
          }
          defer { tasks.cancelAll() }
          guard let first = try await tasks.next() else { throw DeviceLayerError.closed }
          return first
        }
      } catch {
        if expired.withLock({ $0 }) { throw DeviceLayerError.timeout("link key confirmation") }
        throw error
      }
      // The timer may have closed the channel just as the confirmation arrived.
      if expired.withLock({ $0 }) { throw DeviceLayerError.timeout("link key confirmation") }
      guard confirmation == keyConfirmation else {
        throw DeviceLayerError.protocolViolation("expected the initiator's key confirmation")
      }
      return link
    } catch {
      channel.close()
      throw error
    }
  }

  /// Transmits an already checkpointed, full-feed-published seal. The Node publishes once and
  /// fans this identical value to every group peer; this carrier never creates a hidden seal.
  public func sendSealed(_ application: DeviceSealedApplication) async throws {
    await sending.acquire()
    defer { sending.release() }
    guard !isClosed else { throw DeviceLayerError.closed }
    guard let group,
      await group.member(peer.deviceID, agreementKey: peer.agreementKey) == peer,
      try await group.applicationMembers(epoch: application.message.groupEpoch).contains(peer)
    else { throw DeviceLayerError.unknownPeer }
    let bytes = try encoder.encode(application)
    guard !bytes.isEmpty, bytes.count <= Self.maximumApplicationBytes else {
      throw DeviceLayerError.invalid("Noise application envelope limit")
    }
    try sendFragments(bytes, as: Self.applicationFragments)
  }

  /// A carrier that refuses a fragment after the first leaves the peer holding part of the
  /// message and expecting the rest, which no later frame can be: the link ends here, where the
  /// refusal is seen, instead of at the peer's next message.
  private func sendFragments(_ bytes: Data, as kind: Fragmented) throws {
    let digest = Data(SHA256.hash(data: bytes))
    let count = (bytes.count + Self.fragmentChunkSize - 1) / Self.fragmentChunkSize
    for index in 0..<count {
      let offset = index * Self.fragmentChunkSize
      let end = min(bytes.count, offset + Self.fragmentChunkSize)
      var frame = Data()
      frame.reserveCapacity(Self.fragmentHeaderSize + end - offset)
      frame.append(kind.marker)
      frame.append(digest)
      withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { frame.append(contentsOf: $0) }
      withUnsafeBytes(of: UInt16(index).bigEndian) { frame.append(contentsOf: $0) }
      withUnsafeBytes(of: UInt16(count).bigEndian) { frame.append(contentsOf: $0) }
      frame.append(bytes[offset..<end])
      do { try sendPlaintext(frame) } catch {
        if index > 0 { closeNow() }
        throw error
      }
    }
  }

  /// Sends one pairing message. One that fits a Noise message goes as that message; a larger
  /// one as fragments; one over ``PairingExchange/maximumMessageBytes`` is refused before
  /// anything is sent.
  /// Tells the joiner, on the pairing channel it authenticated, why this pairing ends:
  /// plaintext `0x23 | reason`. Only a refusal that has a reason code is sent.
  func sendPairingRefusal(_ refusal: PairingRefusal) async throws {
    await sending.acquire()
    defer { sending.release() }
    guard group == nil, let reason = refusal.noticeCode else {
      throw DeviceLayerError.protocolViolation("only pairing bootstrap may carry a refusal notice")
    }
    try sendPlaintext(Data([Self.pairingRefusalMarker, reason]))
  }

  func sendBootstrap(_ message: DeviceMessage) async throws {
    await sending.acquire()
    defer { sending.release() }
    guard group == nil, Self.isBootstrap(message.body) else {
      throw DeviceLayerError.protocolViolation("only pairing bootstrap may omit MLS")
    }
    let bytes = try encoder.encode(message)
    guard bytes.count <= PairingExchange.maximumMessageBytes else {
      throw PairingRefusal.oversizedMessage
    }
    if bytes.count <= NoiseTransport.maximumPlaintext {
      try sendPlaintext(bytes)
    } else {
      try sendFragments(bytes, as: Self.bootstrapFragments)
    }
  }

  private static func isBootstrap(_ body: DeviceMessageBody) -> Bool {
    switch body {
    case .pairHello, .pairWelcome, .pairConfirm: true
    default: false
    }
  }

  /// A frame the carrier refuses (a relay stream while this device is offline) was not sent
  /// and leaves the link as it was: the next frame is the one the peer expects. For a message
  /// sent in fragments that holds only for its first one (see `sendFragments`).
  func sendPlaintext(_ plaintext: Data) throws {
    do {
      try transport.seal(plaintext) { sealed in
        try channel.send(Data([LinkFrameKind.transport.rawValue]) + sealed)
      }
    } catch let error as NoiseError {
      closeNow()
      throw error
    }
  }

  /// Nonrecipients consume the complete authenticated MLS sequence but never dispatch it.
  /// A missing predecessor is durable and does not close a healthy Noise session.
  public func receive() async throws -> DeviceMessage {
    await receiving.acquire()
    defer { receiving.release() }
    guard let group else { throw DeviceLayerError.invalid("MLS state required") }
    do {
      while true {
        let packet = try await receiveApplicationPacket()
        if packet.message.groupEpoch > UInt64(await group.epoch) {
          guard let beforeApplication else { throw DeviceApplicationFeedError.unavailable }
          try await beforeApplication(packet.message.groupEpoch)
        }
        guard await group.member(peer.deviceID, agreementKey: peer.agreementKey) == peer else {
          throw DeviceLayerError.unknownPeer
        }
        guard
          let receipt = try await group.openOrderedApplication(
            DeviceApplicationFeedDelivery(sender: peer, application: packet))
        else { continue }
        guard let route = receipt.routing, route.kind == .rawNative, let recipient = route.recipient
        else {
          throw DeviceLayerError.invalid("explicit native application host handler required")
        }
        if case .device(let id) = recipient, id != group.localPeer.deviceID {
          try await group.acknowledgeOpened(receiptIDs: [receipt.id])
          continue
        }
        guard let message = try DeviceGroup.nodeMessage(receipt, groupID: await group.groupID)
        else {
          throw DeviceLayerError.invalid("explicit native application host handler required")
        }
        let conversation: ConversationID?
        let rseq: Int64?
        if case .replicaChange(let change) = message.body {
          conversation = change.conversationId
          rseq = change.rseq
        } else {
          conversation = nil
          rseq = nil
        }
        if !(receipts[message.msgId]?.contains(where: { $0.id == receipt.id }) ?? false) {
          receipts[message.msgId, default: []].append(
            ReceivedReceipt(id: receipt.id, conversation: conversation, rseq: rseq))
        }
        return message
      }
    } catch let error as DeviceApplicationFeedError {
      // Waiting cipher/plaintext remains durable; the caller requests a full-feed catch-up.
      throw error
    } catch {
      closeNow()
      throw error
    }
  }

  private func receiveApplicationPacket() async throws -> DeviceSealedApplication {
    while true {
      let frame = try await receivePlaintext()
      if let bytes = try take(frame, as: Self.applicationFragments) {
        return try decoder.decode(DeviceSealedApplication.self, from: bytes)
      }
    }
  }

  /// Takes the next fragment of a message of `kind`; returns the whole message once its last
  /// fragment arrived. Nothing is kept beyond the total the first fragment announced, and that
  /// total is checked against the kind's bound before anything is buffered.
  private func take(_ frame: Data, as kind: Fragmented) throws -> Data? {
    guard frame.count >= Self.fragmentHeaderSize, frame[frame.startIndex] == kind.marker else {
      throw DeviceLayerError.protocolViolation("expected a \(kind.noun) fragment")
    }
    let header = frame.prefix(Self.fragmentHeaderSize)
    let total = header.dropFirst(33).prefix(4).reduce(0) { ($0 << 8) | Int($1) }
    let index = header.dropFirst(37).prefix(2).reduce(0) { ($0 << 8) | Int($1) }
    let count = header.dropFirst(39).prefix(2).reduce(0) { ($0 << 8) | Int($1) }
    guard total >= kind.minimum, total <= kind.maximum,
      count == (total + Self.fragmentChunkSize - 1) / Self.fragmentChunkSize,
      index < count,
      frame.count - Self.fragmentHeaderSize
        == min(Self.fragmentChunkSize, total - index * Self.fragmentChunkSize)
    else { throw DeviceLayerError.protocolViolation("\(kind.noun) fragment bounds") }
    let digest = Data(header.dropFirst().prefix(32))
    if index == 0 {
      guard assembly == nil else {
        throw DeviceLayerError.protocolViolation("interleaved \(kind.noun) fragments")
      }
      var bytes = Data()
      bytes.reserveCapacity(total)
      assembly = FragmentAssembly(
        digest: digest, total: total, count: count, next: 0, bytes: bytes)
    }
    guard var value = assembly, value.digest == digest, value.total == total,
      value.count == count, value.next == index
    else { throw DeviceLayerError.protocolViolation("\(kind.noun) fragment order") }
    assembly = nil
    value.bytes.append(frame.dropFirst(Self.fragmentHeaderSize))
    value.next += 1
    if value.next == count {
      guard value.bytes.count == total, Data(SHA256.hash(data: value.bytes)) == digest else {
        throw DeviceLayerError.protocolViolation("\(kind.noun) fragment digest")
      }
      return value.bytes
    }
    assembly = value
    return nil
  }

  /// Receives one pairing message, whole: either one Noise message, or the fragments of a
  /// larger one. A message announced as larger than ``PairingExchange/maximumMessageBytes``
  /// is refused at its first fragment, before anything is buffered.
  func receiveBootstrap() async throws -> DeviceMessage {
    await receiving.acquire()
    defer { receiving.release() }
    guard group == nil else {
      throw DeviceLayerError.protocolViolation("bootstrap already finished")
    }
    do {
      var plaintext = try await receivePlaintext()
      if plaintext.first == Self.pairingRefusalMarker {
        throw PairingRefusal(noticeCode: plaintext.count == 2 ? plaintext.last : nil)
      }
      if plaintext.first == Self.bootstrapFragments.marker {
        while true {
          if plaintext.first == Self.bootstrapFragments.marker,
            plaintext.count >= Self.fragmentHeaderSize,
            plaintext.dropFirst(33).prefix(4).reduce(0, { ($0 << 8) | Int($1) })
              > PairingExchange.maximumMessageBytes
          {
            throw PairingRefusal.oversizedMessage
          }
          if let whole = try take(plaintext, as: Self.bootstrapFragments) {
            plaintext = whole
            break
          }
          plaintext = try await receivePlaintext()
        }
      }
      let message = try decoder.decode(DeviceMessage.self, from: plaintext)
      guard Self.isBootstrap(message.body) else {
        throw DeviceLayerError.protocolViolation("expected pairing bootstrap")
      }
      return message
    } catch {
      closeNow()
      throw error
    }
  }

  func acknowledgeReceived(_ id: ULID) async throws {
    guard let group, let completed = receipts.removeValue(forKey: id) else { return }
    do {
      try await group.acknowledgeOpened(receiptIDs: completed.map(\.id))
    } catch {
      receipts[id, default: []].insert(contentsOf: completed, at: 0)
      throw error
    }
  }

  func acknowledgeApplied(_ conversation: ConversationID, through rseq: Int64) async throws
    -> [ULID]
  {
    guard let group else { return [] }
    let completed = receipts.filter { _, values in
      values.allSatisfy {
        $0.conversation == conversation && ($0.rseq.map { $0 <= rseq } ?? false)
      }
    }
    guard !completed.isEmpty else { return [] }
    var receiptIDs: [String] = []
    for (id, values) in completed {
      receipts[id] = nil
      receiptIDs.append(contentsOf: values.map(\.id))
    }
    do {
      try await group.acknowledgeOpened(receiptIDs: receiptIDs)
      return Array(completed.keys)
    } catch {
      for (id, values) in completed { receipts[id, default: []].insert(contentsOf: values, at: 0) }
      throw error
    }
  }

  func receivePlaintext() async throws -> Data {
    guard !isClosed else { throw DeviceLayerError.closed }
    let frame = try await channel.receive()
    guard frame.first == LinkFrameKind.transport.rawValue else {
      closeNow()
      throw DeviceLayerError.protocolViolation("expected a transport frame")
    }
    do {
      return try transport.open(Data(frame.dropFirst()))
    } catch {
      closeNow()
      throw error
    }
  }

  /// Hands the transport to a replacement link object on the same channel (pairing learns the
  /// joiner's identity only after the handshake); this object stops working.
  func detachTransport() throws -> NoiseTransport {
    guard !isClosed else { throw DeviceLayerError.closed }
    isClosed = true
    return transport
  }

  /// Closes the link and its channel.
  public func close() { closeNow() }

  private func closeNow() {
    isClosed = true
    assembly = nil
    channel.close()
  }
}
