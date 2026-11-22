import CryptoKit
import Foundation
import MemoshiProtocol
import Synchronization

/// The relay's wire: length-prefixed frames on one TCP connection per device. A device proves
/// its signing key, then sends opaque link frames addressed by device ID and stream ID; the relay
/// forwards them, queueing them while the recipient is offline (store-and-forward), and answers
/// lease-authority messages. The relay never holds a link key, so link traffic is ciphertext to
/// it; it sees device IDs, stream IDs, sizes and timing, and the lease records it decides.
enum RelayFrameKind: UInt8 {
  case hello = 0x01
  case challenge = 0x02
  case proof = 0x03
  case ready = 0x04
  case refused = 0x05
  case send = 0x10
  case deliver = 0x11
  case mailboxDelivery = 0x12
  case mailboxAck = 0x13
  case streamEnded = 0x14
  case authority = 0x20
  case authorityReply = 0x21
  case control = 0x22
  case controlReply = 0x23
  case membership = 0x24
  case applicationChanged = 0x25
}

enum RelayWire {
  static let purpose = Data("memoshi.relay.v1".utf8)
  /// Tells a device it was removed from its group. The relay then answers only what the device
  /// needs to learn of that removal (``RelayServer``).
  static let revokedRefusal = Data([RelayFrameKind.refused.rawValue]) + Data("revoked".utf8)

  /// `[kind][id length][device ID][stream ID, 4 bytes][payload]`.
  static func addressed(_ kind: RelayFrameKind, device: DeviceID, stream: UInt32, payload: Data)
    -> Data
  {
    let id = Data(device.rawValue.utf8)
    var frame = Data([kind.rawValue, UInt8(id.count)])
    frame.append(id)
    withUnsafeBytes(of: stream.bigEndian) { frame.append(contentsOf: $0) }
    frame.append(payload)
    return frame
  }

  /// Splits an addressed frame after its kind byte.
  static func parseAddressed(_ frame: Data) -> (DeviceID, UInt32, Data)? {
    let body = frame.dropFirst()
    guard let length = body.first.map(Int.init), body.count >= 1 + length + 4,
      let device = try? DeviceID(String(decoding: body.dropFirst().prefix(length), as: UTF8.self))
    else { return nil }
    let streamBytes = body.dropFirst(1 + length).prefix(4)
    let stream = streamBytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    return (device, stream, Data(body.dropFirst(1 + length + 4)))
  }
}

/// What the relay saw: every forwarded payload, authority message and control frame, for the
/// content audit.
public struct RelayJournalEntry: Sendable {
  /// `send`, `authority`, `authorityReply`, `control` or `controlReply`.
  public let kind: String
  /// The sending device, or nil for the authority's replies.
  public let from: DeviceID?
  /// The addressed device, or nil for messages to the authority.
  public let to: DeviceID?
  /// The exact bytes the relay held.
  public let bytes: Data
}

/// Relay counters.
public struct RelayStatistics: Codable, Hashable, Sendable {
  /// Authenticated connections accepted.
  public var connections = 0
  /// Connections refused (bad proof or revoked device).
  public var refusals = 0
  /// Frames forwarded live.
  public var forwarded = 0
  /// Frames queued for an offline device.
  public var queued = 0
  /// Queued frames delivered on reconnect.
  public var deliveredFromMailbox = 0
  /// Deliveries refused at the mailbox limit or when durable enqueue failed.
  public var mailboxDrops = 0
  /// Authority messages answered or applied.
  public var authorityMessages = 0
}

/// A loopback relay with store-and-forward mailboxes and the lease authority.
public final class RelayServer: Sendable {
  private struct Connection {
    let id: UUID
    let channel: TCPFrameChannel
  }

  private struct State {
    var connections: [DeviceID: Connection] = [:]
    /// The one removal reading each removed device may hold, and when its recent ones began.
    var readings: [DeviceID: Connection] = [:]
    var readingStarts: [DeviceID: [Int64]] = [:]
    var statistics = RelayStatistics()
  }

  /// What one removal reading may fetch: membership pages of one commit each, and bytes.
  static let maximumRemovalReads = DeviceGroup.maximumRemovalPages
  static let maximumRemovalReadingBytes = 64 * 1024 * 1024
  /// How many removal readings one removed device may begin per minute.
  static let maximumRemovalReadingsPerMinute = 8

  /// The bound port on 127.0.0.1.
  public let port: Int
  /// The lease authority this relay runs.
  public let authority: RelayLeaseAuthority
  private let listener: TCPFrameListener
  private let state = Mutex(State())
  private let mailbox: RelayMailbox
  private let handlers = PendingDeviceHandlers()
  /// Runs between a member's authentication and its admission; tests use it to hold an
  /// admission while the device is revoked.
  let beforeAdmission = Mutex<(@Sendable (DeviceID) async -> Void)?>(nil)
  /// Runs between the authority's answer to a device's control request and its delivery.
  let beforeControlReply = Mutex<(@Sendable (DeviceID) async -> Void)?>(nil)
  /// Runs after a removal commit was applied and before its subject is told and disconnected.
  let beforeRevocationNotice = Mutex<(@Sendable (DeviceID) async -> Void)?>(nil)
  /// Runs in routing after the recipient's revocation was checked and before its frame is
  /// queued; tests use it to revoke the recipient in between.
  let beforeEnqueue = Mutex<(@Sendable (DeviceID) async -> Void)?>(nil)

  private init(
    port: Int, authority: RelayLeaseAuthority, listener: TCPFrameListener, mailbox: RelayMailbox
  ) {
    self.port = port
    self.authority = authority
    self.listener = listener
    self.mailbox = mailbox
  }

  /// Starts listening on 127.0.0.1 on an OS-chosen port unless one is given.
  public static func start(
    authority: RelayLeaseAuthority, port: Int = 0, mailboxLimit: Int = 10_000,
    mailboxDirectory: URL? = nil,
    journal: (@Sendable (RelayJournalEntry) -> Void)? = nil
  ) async throws -> RelayServer {
    let mailbox = try RelayMailbox(directory: mailboxDirectory, limit: mailboxLimit)
    // Frames kept for a device revoked while no relay heard it are dropped before any session.
    do {
      for recipient in mailbox.recipients where authority.hasRevoked(recipient) {
        try mailbox.drop(for: recipient)
      }
    } catch {
      mailbox.close()
      throw error
    }
    let slot = Locked<RelayServer?>(nil)
    // Lease deadlines are judged on the authority's clock when NIO reads each frame, so a
    // stalled serve loop or durable write cannot spend the runner's remaining lease.
    let listener = try await TCPFrameListener.bind(port: port, arrivalClock: authority.now) {
      channel in
      guard let server = slot.withLock({ $0 }) else { return channel.close() }
      server.handlers.start(channel: channel) { identifier in
        await server.serve(channel, identifier: identifier, journal: journal)
      }
    }
    let server = RelayServer(
      port: listener.port, authority: authority, listener: listener, mailbox: mailbox)
    slot.withLock { $0 = server }
    return server
  }

  /// The relay's counters.
  public var statistics: RelayStatistics { state.withLock { $0.statistics } }

  /// Whether a device currently has an authenticated connection.
  public func isConnected(_ device: DeviceID) -> Bool {
    state.withLock { $0.connections[device] != nil }
  }

  /// Unacknowledged deliveries, or nil when durable mailbox storage is unavailable.
  public func mailboxDepth(for device: DeviceID) -> Int? { try? mailbox.depth(for: device) }

  /// Stops listening and closes every device connection.
  public func close() async {
    guard let pending = handlers.beginClose() else {
      await handlers.waitUntilClosed()
      return
    }
    pending.cancelAndClose()
    state.withLock { $0.connections.removeAll() }
    await listener.close()
    await pending.join()
    mailbox.close()
    handlers.finishClose()
  }

  private func serve(
    _ channel: TCPFrameChannel, identifier: UUID,
    journal: (@Sendable (RelayJournalEntry) -> Void)?
  ) async {
    guard let (device, removed) = await authenticate(channel) else {
      state.withLock { $0.statistics.refusals += 1 }
      return
    }
    if removed {
      // Refused: no session. The connection stays only to read this device's removal.
      state.withLock { $0.statistics.refusals += 1 }
      await serveRemovalReading(channel, identifier: identifier, device: device, journal: journal)
      return
    }
    if let hold = beforeAdmission.withLock({ $0 }) { await hold(device) }
    let connection = Connection(id: identifier, channel: channel)
    var replaced: TCPFrameChannel?
    do {
      try handlers.admit(identifier) {
        replaced = try state.withLock { state in
          // Revoked since its hello was checked: no `ready`, no mailbox, no session.
          guard !authority.hasRevoked(device) else {
            state.statistics.refusals += 1
            throw DeviceLayerError.unknownPeer
          }
          let queued = try mailbox.pending(for: device)
          // Ready and the durable prefix precede live forwarding.
          try channel.send(Data([RelayFrameKind.ready.rawValue]))
          for item in queued { try channel.send(Self.delivery(item)) }
          let previous = state.connections.updateValue(connection, forKey: device)
          state.statistics.connections += 1
          state.statistics.deliveredFromMailbox += queued.count
          return previous?.channel
        }
      }
    } catch { return }
    replaced?.close()
    defer {
      state.withLock { state in
        if state.connections[device]?.id == connection.id {
          state.connections.removeValue(forKey: device)
        }
      }
    }
    while !Task.isCancelled, let received = try? await channel.receiveWithArrival() {
      let frame = received.bytes
      switch frame.first.flatMap(RelayFrameKind.init(rawValue:)) {
      case .send:
        guard await authority.enrolledPeer(device) != nil else { return }
        guard let (recipient, stream, payload) = RelayWire.parseAddressed(frame) else { return }
        guard await authority.canRoute(from: device, to: recipient) else { return }
        journal?(RelayJournalEntry(kind: "send", from: device, to: recipient, bytes: payload))
        do {
          try await route(
            RelayWire.addressed(.deliver, device: device, stream: stream, payload: payload),
            to: recipient)
        } catch {
          // The recipient cannot take this frame, so its stream has a gap nothing can fill.
          // Only that stream ends: this connection is also the sender's authority session.
          try? channel.send(
            RelayWire.addressed(.streamEnded, device: recipient, stream: stream, payload: Data()))
        }
      case .mailboxAck:
        guard let id = UUID(uuidString: String(decoding: frame.dropFirst(), as: UTF8.self)) else {
          return
        }
        do { try mailbox.acknowledge(id, by: device) } catch { return }
      case .authority:
        let bytes = Data(frame.dropFirst())
        journal?(RelayJournalEntry(kind: "authority", from: device, to: nil, bytes: bytes))
        guard
          let message = try? ProtocolCoding.makeDecoder().decode(DeviceMessage.self, from: bytes)
        else { return }
        let reply = await authority.handle(message, from: device, receivedAt: received.arrival)
        state.withLock { $0.statistics.authorityMessages += 1 }
        if reply == nil {
          guard case .leaseRelease = message.body else { return }
        }
        if let reply, let encoded = try? ProtocolCoding.makeEncoder().encode(reply) {
          guard
            answer(
              encoded, kind: .authorityReply, to: device, on: channel, journal: journal)
          else { return }
        }
        if case .groupCommit(let commit) = message.body,
          case .groupCommitResult(let result)? = reply?.body, result.accepted
        {
          if commit.change == .remove, let hold = beforeRevocationNotice.withLock({ $0 }) {
            await hold(commit.subjectDeviceId)
          }
          await notifyMembership(commit, sender: device)
          if commit.change == .remove { disconnect(commit.subjectDeviceId) }
        }
        if await authority.enrolledPeer(device) == nil { return }
      case .control:
        let bytes = Data(frame.dropFirst())
        journal?(RelayJournalEntry(kind: "control", from: device, to: nil, bytes: bytes))
        guard
          let request = try? ProtocolCoding.makeDecoder().decode(
            AuthorityControlRequest.self, from: bytes)
        else { return }
        let reply = await authority.control(request, from: device)
        if let hold = beforeControlReply.withLock({ $0 }) { await hold(device) }
        guard let encoded = try? ProtocolCoding.makeEncoder().encode(reply),
          answer(encoded, kind: .controlReply, to: device, on: channel, journal: journal)
        else { return }
        if let notice = reply.applicationPublished { await notifyApplications(notice) }
      default:
        return
      }
    }
  }

  /// Sends the authority's answer unless its device was revoked since it asked: a revoked
  /// device is sent nothing more, so an answer given just before its removal is dropped. Under
  /// the relay's lock, like every delivery. False ends the session.
  private func answer(
    _ encoded: Data, kind: RelayFrameKind, to device: DeviceID, on channel: TCPFrameChannel,
    journal: (@Sendable (RelayJournalEntry) -> Void)?
  ) -> Bool {
    state.withLock { _ in
      guard !authority.hasRevoked(device) else { return false }
      journal?(
        RelayJournalEntry(
          kind: kind == .authorityReply ? "authorityReply" : "controlReply", from: nil,
          to: device, bytes: encoded))
      try? channel.send(Data([kind.rawValue]) + encoded)
      return true
    }
  }

  private func notifyMembership(_ commit: GroupCommit, sender: DeviceID) async {
    guard
      let snapshot = await authority.groupSnapshot(
        commit.groupId, for: sender, afterEpoch: commit.fromEpoch),
      let bytes = try? ProtocolCoding.makeEncoder().encode(snapshot)
    else { return }
    let channels = state.withLock { state in
      var recipients = Set(snapshot.members.map(\.deviceId))
      if commit.change == .remove { recipients.insert(commit.subjectDeviceId) }
      return recipients.compactMap { state.connections[$0]?.channel }
    }
    for channel in channels {
      try? channel.send(Data([RelayFrameKind.membership.rawValue]) + bytes)
    }
  }

  private func notifyApplications(_ notice: AuthorityApplicationFeedNotice) async {
    guard let bytes = try? ProtocolCoding.makeEncoder().encode(notice) else { return }
    let connected = state.withLock { state in state.connections.map { ($0.key, $0.value.channel) } }
    for (device, channel) in connected {
      guard await authority.groupSnapshot(notice.groupID, for: device) != nil else { continue }
      // This is only a wakeup. Ciphertext remains in the durable full feed; reconnect always
      // reads the authority again, so losing a connection cannot erase an accepted packet.
      try? channel.send(Data([RelayFrameKind.applicationChanged.rawValue]) + bytes)
    }
  }

  /// Journals before any delivery. Removal requires the recipient's transport acknowledgement;
  /// a reconnect or relay restart can resend the same delivery identity, never invent a payload.
  private func route(_ frame: Data, to recipient: DeviceID) async throws {
    guard frame.count + 37 <= TCPFrameChannel.maximumFrame else {
      throw DeviceLayerError.frameTooLarge(frame.count + 37)
    }
    // A revoked device is never sent or kept a frame, whenever its sender was checked.
    guard !authority.hasRevoked(recipient) else { throw DeviceLayerError.unknownPeer }
    if let hold = beforeEnqueue.withLock({ $0 }) { await hold(recipient) }
    let item: RelayMailbox.Item
    do { item = try mailbox.enqueue(frame, to: recipient) } catch {
      state.withLock { $0.statistics.mailboxDrops += 1 }
      throw error
    }
    let routed = state.withLock { state -> Bool in
      // Revoked since the check above: the frame is neither delivered nor kept.
      guard !authority.hasRevoked(recipient) else { return false }
      if let connection = state.connections[recipient],
        (try? connection.channel.send(Self.delivery(item))) != nil
      {
        state.statistics.forwarded += 1
      } else {
        state.statistics.queued += 1
      }
      return true
    }
    guard routed else {
      try? mailbox.drop(for: recipient)
      throw DeviceLayerError.unknownPeer
    }
  }

  private static func delivery(_ item: RelayMailbox.Item) -> Data {
    Data([RelayFrameKind.mailboxDelivery.rawValue]) + Data(item.id.uuidString.utf8) + item.frame
  }

  /// Ends a removed device's session: it is told why, and the connection closes; the frames
  /// queued for it are dropped. To learn of its removal it connects again and gets a removal
  /// reading.
  private func disconnect(_ device: DeviceID) {
    let channel = state.withLock { $0.connections.removeValue(forKey: device)?.channel }
    if let channel {
      try? channel.send(RelayWire.revokedRefusal)
      channel.close()
    }
    try? mailbox.drop(for: device)
  }

  /// A removed device's refused connection, kept only to read its removal: the relay answers
  /// `group` requests (the membership commits up to that removal), never an application
  /// message of any epoch. One reading per device (a new one replaces the old), at most
  /// ``maximumRemovalReadingsPerMinute`` begun per minute, at most ``maximumRemovalReads``
  /// answers and ``maximumRemovalReadingBytes`` each; it ends with any other frame, or with
  /// the first request after the answer that reached the removal.
  private func serveRemovalReading(
    _ channel: TCPFrameChannel, identifier: UUID, device: DeviceID,
    journal: (@Sendable (RelayJournalEntry) -> Void)?
  ) async {
    let now = authority.now()
    let admitted = state.withLock { state -> (Bool, TCPFrameChannel?) in
      let recent = (state.readingStarts[device] ?? []).filter { now - $0 < 60_000 }
      guard recent.count < Self.maximumRemovalReadingsPerMinute else {
        state.readingStarts[device] = recent
        return (false, nil)
      }
      state.readingStarts[device] = recent + [now]
      let replaced = state.readings.updateValue(
        Connection(id: identifier, channel: channel), forKey: device)
      return (true, replaced?.channel)
    }
    admitted.1?.close()
    guard admitted.0 else { return }
    defer {
      state.withLock { state in
        if state.readings[device]?.id == identifier { state.readings.removeValue(forKey: device) }
      }
    }
    guard (try? channel.send(RelayWire.revokedRefusal)) != nil else { return }
    var answers = 0
    var bytes = 0
    var reachedRemoval = false
    while !Task.isCancelled, let frame = try? await channel.receive(),
      !reachedRemoval, answers < Self.maximumRemovalReads,
      frame.first == RelayFrameKind.control.rawValue,
      let request = try? ProtocolCoding.makeDecoder().decode(
        AuthorityControlRequest.self, from: frame.dropFirst()),
      case .group = request.operation
    {
      journal?(
        RelayJournalEntry(kind: "control", from: device, to: nil, bytes: Data(frame.dropFirst())))
      let reply = await authority.control(request, from: device)
      guard let encoded = try? ProtocolCoding.makeEncoder().encode(reply) else { return }
      answers += 1
      bytes += encoded.count
      guard bytes <= Self.maximumRemovalReadingBytes else { return }
      journal?(RelayJournalEntry(kind: "controlReply", from: nil, to: device, bytes: encoded))
      guard (try? channel.send(Data([RelayFrameKind.controlReply.rawValue]) + encoded)) != nil
      else { return }
      reachedRemoval =
        reply.group.map { group in
          group.commits.last.map { $0.targetEpoch >= UInt64(max(0, group.epoch)) } ?? true
        } ?? true
    }
  }

  /// Hello, challenge, proof: the device proves its signing key. A removed device whose removal
  /// the authority recorded proves it the same way and is marked `removed`; any other revoked
  /// device is refused here.
  private func authenticate(_ channel: TCPFrameChannel) async -> (DeviceID, removed: Bool)? {
    guard let hello = try? await channel.receive(), hello.first == RelayFrameKind.hello.rawValue,
      let length = hello.dropFirst().first.map(Int.init), hello.count == 2 + length + 32,
      let device = try? DeviceID(
        String(decoding: hello.dropFirst(2).prefix(length), as: UTF8.self)),
      let enrolled = await helloPeer(device),
      enrolled.signingKey == Data(hello.suffix(32)),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: enrolled.signingKey)
    else { return nil }
    let nonce = Data.random(count: 32)
    guard (try? channel.send(Data([RelayFrameKind.challenge.rawValue]) + nonce)) != nil,
      let proof = try? await channel.receive(), proof.first == RelayFrameKind.proof.rawValue,
      key.isValidSignature(
        proof.dropFirst(), for: RelayWire.purpose + nonce + Data(device.rawValue.utf8))
    else { return nil }
    if await authority.enrolledPeer(device) == enrolled { return (device, false) }
    if await authority.removedPeer(device) == enrolled { return (device, true) }
    return nil
  }

  private func helloPeer(_ device: DeviceID) async -> DevicePeer? {
    if let enrolled = await authority.enrolledPeer(device) { return enrolled }
    return await authority.removedPeer(device)
  }
}

/// A device's connection to the relay: authenticated, carrying link streams to other devices
/// and requests to the lease authority.
public final class RelayClient: Sendable {
  /// This device.
  public let deviceID: DeviceID
  private let identity: DeviceIdentity
  private let host: String
  private let port: Int
  private let connection = Mutex<TCPFrameChannel?>(nil)
  private let streams = Mutex<[StreamKey: FrameQueue]>([:])
  private let waiters = Mutex<[Waiter]>([])
  private let closed = Mutex(false)
  private let onIncoming: @Sendable (RelayStream) -> Void
  private let onMembership: @Sendable (AuthorityGroup) -> Void
  private let onApplication: (@Sendable (String, UInt64) -> Void)?
  private let onRemoved: (@Sendable () -> Void)?
  /// The connection the relay keeps only for reading this device's removal.
  private let removalReading = Mutex<ObjectIdentifier?>(nil)
  private let controlWaiters = Mutex<[UUID: ControlWaiter]>([:])
  private let encoder = ProtocolCoding.makeEncoder()
  private let receivedDeliveries = Mutex<(order: [UUID], head: Int, ids: Set<UUID>)>(([], 0, []))
  private let feedPublishGate = SerialGate()

  private struct StreamKey: Hashable {
    let peer: DeviceID
    let stream: UInt32
  }

  private struct Waiter {
    let connection: ObjectIdentifier
    let continuation: CheckedContinuation<DeviceMessage, any Error>
  }

  private struct ControlWaiter {
    let connection: ObjectIdentifier
    let continuation: CheckedContinuation<AuthorityControlReply, any Error>
  }

  private init(
    identity: DeviceIdentity, host: String, port: Int,
    onMembership: @escaping @Sendable (AuthorityGroup) -> Void,
    onApplication: (@Sendable (String, UInt64) -> Void)?,
    onRemoved: (@Sendable () -> Void)?,
    onIncoming: @escaping @Sendable (RelayStream) -> Void
  ) {
    self.deviceID = identity.deviceID
    self.identity = identity
    self.host = host
    self.port = port
    self.onIncoming = onIncoming
    self.onMembership = onMembership
    self.onApplication = onApplication
    self.onRemoved = onRemoved
  }

  /// Connects and authenticates. `onIncoming` receives each stream another device opens.
  ///
  /// A relay that refuses this device fails the connect, and its refusal during a session ends
  /// the connection. With `onRemoved`, a refusal because this device was removed from its group
  /// leaves a connection that only reads the membership commits up to that removal
  /// (``isRemovalReading``); every other request on it fails as `closed`. `onRemoved` runs when
  /// the relay says so during a session, before the connection ends. The relay's word proves
  /// nothing: only the group's commits, applied to this device's own group state, do.
  public static func connect(
    host: String = "127.0.0.1", port: Int, identity: DeviceIdentity,
    onMembership: @escaping @Sendable (AuthorityGroup) -> Void = { _ in },
    onApplication: (@Sendable (String, UInt64) -> Void)? = nil,
    onRemoved: (@Sendable () -> Void)? = nil,
    onIncoming: @escaping @Sendable (RelayStream) -> Void
  ) async throws -> RelayClient {
    let client = RelayClient(
      identity: identity, host: host, port: port,
      onMembership: onMembership, onApplication: onApplication, onRemoved: onRemoved,
      onIncoming: onIncoming)
    try await client.reconnect()
    return client
  }

  /// (Re)connects and authenticates. Streams survive a reconnect, so frames the relay queued
  /// while this device was offline arrive on them, in order, before any newer frame.
  public func reconnect() async throws {
    guard closed.withLock({ !$0 }) else { throw DeviceLayerError.closed }
    let channel = try await TCPFrameChannel.connect(host: host, port: port)
    var removal = false
    do {
      let id = Data(identity.deviceID.rawValue.utf8)
      try channel.send(
        Data([RelayFrameKind.hello.rawValue, UInt8(id.count)]) + id + identity.peer.signingKey)
      let challenge = try await channel.receive()
      guard challenge.first == RelayFrameKind.challenge.rawValue, challenge.count == 33 else {
        throw DeviceLayerError.protocolViolation("relay refused the connection")
      }
      try channel.send(
        Data([RelayFrameKind.proof.rawValue])
          + identity.sign(RelayWire.purpose + challenge.dropFirst() + id))
      let answer = try await channel.receive()
      if answer == RelayWire.revokedRefusal, onRemoved != nil {
        removal = true
      } else if answer.first != RelayFrameKind.ready.rawValue {
        throw DeviceLayerError.protocolViolation("relay refused the connection")
      }
    } catch {
      channel.close()
      throw error
    }
    // `close()` may have run during the handshake: a closed client never keeps a connection.
    let previous: TCPFrameChannel?
    do {
      previous = try closed.withLock { isClosed in
        guard !isClosed else { throw DeviceLayerError.closed }
        return connection.withLock { current in
          defer { current = channel }
          return current
        }
      }
    } catch {
      channel.close()
      throw error
    }
    previous?.close()
    removalReading.withLock { $0 = removal ? ObjectIdentifier(channel) : nil }
    Task { await self.read(channel) }
  }

  /// Whether the current connection is one the relay keeps only for reading this device's
  /// removal: it refused this device's hello as removed.
  public var isRemovalReading: Bool {
    guard let current = connection.withLock({ $0 }) else { return false }
    return removalReading.withLock { $0 } == ObjectIdentifier(current)
  }

  /// Sends one message to the authority over a fresh connection as `identity`, whatever the
  /// relay answers to its hello: for measuring that the relay or the authority refuses a device
  /// (a removed one need not cooperate). Returns the authority's answer, or nil when the
  /// connection ends unanswered. A device the relay accepts gets a session that replaces its
  /// current one, and this probe ends it.
  public static func probeAuthority(
    host: String = "127.0.0.1", port: Int, identity: DeviceIdentity, message: DeviceMessage
  ) async throws -> DeviceMessage? {
    let channel = try await TCPFrameChannel.connect(host: host, port: port)
    defer { channel.close() }
    let id = Data(identity.deviceID.rawValue.utf8)
    do {
      try channel.send(
        Data([RelayFrameKind.hello.rawValue, UInt8(id.count)]) + id + identity.peer.signingKey)
      let challenge = try await channel.receive()
      if challenge.first == RelayFrameKind.challenge.rawValue, challenge.count == 33 {
        try channel.send(
          Data([RelayFrameKind.proof.rawValue])
            + identity.sign(RelayWire.purpose + challenge.dropFirst() + id))
      }
      try channel.send(
        Data([RelayFrameKind.authority.rawValue])
          + (try ProtocolCoding.makeEncoder().encode(message)))
      while true {
        let frame = try await channel.receive()
        guard frame.first == RelayFrameKind.authorityReply.rawValue else { continue }
        return try ProtocolCoding.makeDecoder().decode(DeviceMessage.self, from: frame.dropFirst())
      }
    } catch DeviceLayerError.closed {
      return nil
    }
  }

  /// Drops the connection but keeps every stream: this device is offline to the relay.
  public func disconnect() {
    connection.withLock { current in
      defer { current = nil }
      return current
    }?.close()
  }

  /// Whether a connection is up.
  public var isConnected: Bool { connection.withLock { $0 != nil } }

  /// Opens a new stream to another device.
  public func openStream(to peer: DeviceID) -> RelayStream {
    var generator = SystemRandomNumberGenerator()
    let stream = UInt32.random(in: 1 ... .max, using: &generator)
    let queue = FrameQueue()
    streams.withLock { $0[StreamKey(peer: peer, stream: stream)] = queue }
    return RelayStream(client: self, peer: peer, stream: stream, queue: queue)
  }

  /// Sends one message to the authority and waits for its answer. `lease.release` has none.
  public func authority(_ message: DeviceMessage) async throws -> DeviceMessage? {
    let frame = Data([RelayFrameKind.authority.rawValue]) + (try encoder.encode(message))
    if case .leaseRelease = message.body {
      try current().send(frame)
      return nil
    }
    return try await withCheckedThrowingContinuation { continuation in
      // Register and send under one lock: the relay answers in order, so waiters stay aligned.
      let failure: (any Error)? = waiters.withLock { waiters in
        do {
          let channel = try current()
          try channel.send(frame)
          waiters.append(
            Waiter(connection: ObjectIdentifier(channel), continuation: continuation))
          return nil
        } catch {
          return error
        }
      }
      if let failure { continuation.resume(throwing: failure) }
    }
  }

  func control(_ operation: AuthorityControlRequest.Operation) async throws -> AuthorityControlReply
  {
    let request = AuthorityControlRequest(id: UUID(), operation: operation)
    var readsMembership = false
    if case .group = operation { readsMembership = true }
    let frame = Data([RelayFrameKind.control.rawValue]) + (try encoder.encode(request))
    return try await withCheckedThrowingContinuation { continuation in
      let failure: (any Error)? = controlWaiters.withLock { waiters in
        do {
          let channel = try current(inSession: !readsMembership)
          try channel.send(frame)
          waiters[request.id] = ControlWaiter(
            connection: ObjectIdentifier(channel), continuation: continuation)
          return nil
        } catch { return error }
      }
      if let failure { continuation.resume(throwing: failure) }
    }
  }

  /// Retrieves membership from the trusted qualification authority, never a peer's assertion.
  public func membership(_ groupID: String, afterEpoch: Int64 = 0) async throws -> AuthorityGroup {
    let reply = try await control(.group(groupID, afterEpoch: afterEpoch))
    guard reply.accepted, let group = reply.group else { throw DeviceLayerError.unknownPeer }
    return group
  }

  /// The publication is device-signed and is accepted before a live Noise carrier may emit
  /// its ciphertext. Bounded chunks preserve the existing 70,000-byte relay frame contract.
  public func publishApplication(_ publication: DeviceApplicationPublication) async throws {
    await feedPublishGate.acquire()
    defer { feedPublishGate.release() }
    try Task.checkCancellation()
    guard publication.sender == identity.peer else { throw DeviceLayerError.unknownPeer }
    let bytes = try encoder.encode(publication)
    guard !bytes.isEmpty, bytes.count <= RelayLeaseAuthority.maximumFeedPublicationBytes else {
      throw DeviceLayerError.invalid("relay application publication limit")
    }
    let chunkSize = RelayLeaseAuthority.feedChunkSize
    let count = (bytes.count + chunkSize - 1) / chunkSize
    let transfer = UUID()
    for index in 0..<count {
      try Task.checkCancellation()
      let offset = index * chunkSize
      _ = try await applicationControl(
        .applicationUpload(
          transfer: transfer, index: index, count: count,
          bytes: bytes.subdata(in: offset..<min(bytes.count, offset + chunkSize))))
    }
  }

  /// Fetches a complete full-sender suffix from the qualification relay, pinning one accepted
  /// boundary across bounded pages/chunks and verifying exact bytes, context and device signatures.
  /// Throws on missing/conflicting records or an unmet closed-cutoff requirement; does not
  /// native-open ciphertext, advance group cursors, or acknowledge domain consumption.
  public func applicationFeed(_ request: DeviceApplicationEpochRequest) async throws
    -> DeviceApplicationEpochFeed
  {
    var boundary: DeviceApplicationEpochBoundary?
    var after: AuthorityApplicationFeedPosition?
    var deliveries: [DeviceApplicationFeedDelivery] = []
    repeat {
      let reply = try await applicationControl(
        .applicationPage(request, boundary: boundary, after: after))
      guard let page = reply.applicationPage,
        page.boundary.groupID == request.groupID, page.boundary.epoch == request.epoch,
        boundary == nil || boundary == page.boundary,
        !request.requiresClosed || page.boundary.isClosed,
        page.locators.count <= 32
      else { throw DeviceApplicationFeedError.incompleteBoundary }
      boundary = page.boundary
      for locator in page.locators {
        guard locator.byteCount > 0,
          locator.byteCount <= RelayLeaseAuthority.maximumFeedPublicationBytes,
          locator.digest.count == 32, locator.ordinal > (request.after[locator.sender] ?? 0),
          locator.ordinal <= (page.boundary.cutoffs[locator.sender] ?? 0),
          let peer = request.members.first(where: { $0.deviceID == locator.sender })
        else { throw DeviceApplicationFeedError.conflictingPublication }
        var bytes = Data()
        bytes.reserveCapacity(locator.byteCount)
        while bytes.count < locator.byteCount {
          let response = try await applicationControl(
            .applicationChunk(
              groupID: request.groupID, epoch: request.epoch, sender: locator.sender,
              ordinal: locator.ordinal, offset: bytes.count))
          guard let chunk = response.applicationChunk, !chunk.isEmpty,
            chunk.count <= min(RelayLeaseAuthority.feedChunkSize, locator.byteCount - bytes.count)
          else { throw DeviceApplicationFeedError.incompleteBoundary }
          bytes.append(chunk)
        }
        guard Data(SHA256.hash(data: bytes)) == locator.digest else {
          throw DeviceApplicationFeedError.conflictingPublication
        }
        let publication = try ProtocolCoding.makeDecoder().decode(
          DeviceApplicationPublication.self, from: bytes)
        guard publication.groupID == request.groupID, publication.sender == peer,
          publication.application.ordinal == locator.ordinal,
          publication.application.message.groupEpoch == request.epoch,
          publication.groupContext == request.groupContext,
          peer.verify(publication.signature, over: try publication.statement())
        else { throw DeviceApplicationFeedError.conflictingPublication }
        deliveries.append(
          DeviceApplicationFeedDelivery(sender: peer, application: publication.application))
      }
      if let next = page.next {
        guard let last = page.locators.last, next.sender == last.sender,
          next.ordinal == last.ordinal,
          after.map({
            $0.sender.rawValue < next.sender.rawValue
              || ($0.sender == next.sender && $0.ordinal < next.ordinal)
          }) ?? true
        else { throw DeviceApplicationFeedError.incompleteBoundary }
      }
      after = page.next
    } while after != nil
    guard let boundary else { throw DeviceApplicationFeedError.incompleteBoundary }
    return DeviceApplicationEpochFeed(boundary: boundary, deliveries: deliveries)
  }

  private func applicationControl(_ operation: AuthorityControlRequest.Operation) async throws
    -> AuthorityControlReply
  {
    let reply = try await control(operation)
    if let error = reply.applicationError { throw error }
    guard reply.accepted else { throw DeviceApplicationFeedError.unavailable }
    return reply
  }

  /// Retrieves the trusted lease, committed high-water and unresolved reservation state.
  public func conversation(_ id: ConversationID) async throws -> AuthorityConversation {
    let reply = try await control(.conversation(id))
    guard reply.accepted, let state = reply.conversation else { throw DeviceLayerError.unknownPeer }
    return state
  }

  /// Closes the connection and every stream for good.
  public func close() {
    closed.withLock { $0 = true }
    disconnect()
    let queues = streams.withLock { streams in
      defer { streams.removeAll() }
      return Array(streams.values)
    }
    for queue in queues { queue.finish() }
  }

  /// The connection. A removal reading carries membership reads only: anything else fails here,
  /// as `closed`, instead of ending the reading at the relay.
  private func current(inSession: Bool = true) throws -> TCPFrameChannel {
    guard let channel = connection.withLock({ $0 }),
      !inSession || removalReading.withLock({ $0 }) != ObjectIdentifier(channel)
    else { throw DeviceLayerError.closed }
    return channel
  }

  fileprivate func send(_ payload: Data, to peer: DeviceID, stream: UInt32) throws {
    try current().send(RelayWire.addressed(.send, device: peer, stream: stream, payload: payload))
  }

  fileprivate func remove(peer: DeviceID, stream: UInt32) {
    _ = streams.withLock { $0.removeValue(forKey: StreamKey(peer: peer, stream: stream)) }
  }

  private func deliver(_ frame: Data, deliveryID: UUID?) -> Bool {
    var incoming: RelayStream?
    let accepted = receivedDeliveries.withLock { state in
      if let deliveryID, state.ids.contains(deliveryID) { return true }
      guard let (peer, stream, payload) = RelayWire.parseAddressed(frame) else { return false }
      let key = StreamKey(peer: peer, stream: stream)
      let (queue, isNew) = streams.withLock { streams -> (FrameQueue, Bool) in
        if let queue = streams[key] { return (queue, false) }
        let queue = FrameQueue()
        streams[key] = queue
        return (queue, true)
      }
      switch queue.offer(payload) {
      case .accepted:
        break
      case .overflow, .terminated:
        return false
      }
      if isNew {
        incoming = RelayStream(client: self, peer: peer, stream: stream, queue: queue)
      }
      if let deliveryID {
        state.ids.insert(deliveryID)
        state.order.append(deliveryID)
        if state.order.count - state.head > 200_000 {
          state.ids.remove(state.order[state.head])
          state.head += 1
          if state.head > 1_024, state.head * 2 > state.order.count {
            state.order.removeFirst(state.head)
            state.head = 0
          }
        }
      }
      return true
    }
    if let incoming { onIncoming(incoming) }
    return accepted
  }

  private func read(_ channel: TCPFrameChannel) async {
    let id = ObjectIdentifier(channel)
    defer { channel.close() }
    readLoop: while var frame = try? await channel.receive() {
      var deliveryID: UUID?
      if frame.first == RelayFrameKind.mailboxDelivery.rawValue {
        guard frame.count > 37,
          let identifier = UUID(
            uuidString: String(decoding: frame.dropFirst().prefix(36), as: UTF8.self))
        else { break }
        deliveryID = identifier
        frame = Data(frame.dropFirst(37))
        guard frame.first == RelayFrameKind.deliver.rawValue else { break }
      }
      switch frame.first.flatMap(RelayFrameKind.init(rawValue:)) {
      case .deliver:
        guard deliver(frame, deliveryID: deliveryID) else { break readLoop }
      case .streamEnded:
        // The relay could not carry a frame on this stream; nothing later on it can decrypt.
        if let (peer, stream, _) = RelayWire.parseAddressed(frame) {
          streams.withLock { $0.removeValue(forKey: StreamKey(peer: peer, stream: stream)) }?
            .finish()
        }
      case .authorityReply:
        let waiter = waiters.withLock { waiters -> Waiter? in
          guard let index = waiters.firstIndex(where: { $0.connection == id }) else { return nil }
          return waiters.remove(at: index)
        }
        if let waiter {
          do {
            waiter.continuation.resume(
              returning: try ProtocolCoding.makeDecoder().decode(
                DeviceMessage.self, from: frame.dropFirst()))
          } catch {
            waiter.continuation.resume(throwing: error)
          }
        }
      case .controlReply:
        guard
          let reply = try? ProtocolCoding.makeDecoder().decode(
            AuthorityControlReply.self, from: frame.dropFirst())
        else {
          channel.close()
          continue
        }
        let waiter = controlWaiters.withLock { waiters -> ControlWaiter? in
          guard waiters[reply.id]?.connection == id else { return nil }
          return waiters.removeValue(forKey: reply.id)
        }
        waiter?.continuation.resume(returning: reply)
      case .membership:
        guard
          let group = try? ProtocolCoding.makeDecoder().decode(
            AuthorityGroup.self, from: frame.dropFirst())
        else {
          channel.close()
          continue
        }
        onMembership(group)
      case .applicationChanged:
        guard
          let notice = try? ProtocolCoding.makeDecoder().decode(
            AuthorityApplicationFeedNotice.self, from: frame.dropFirst())
        else {
          channel.close()
          continue
        }
        onApplication?(notice.groupID, notice.epoch)
      case .refused:
        // The relay removed this device during the session and closes the connection; its
        // word alone proves nothing. A reader connects again to read that removal.
        if frame == RelayWire.revokedRefusal { onRemoved?() }
        break readLoop
      default:
        break
      }
      if let deliveryID {
        // Receipt follows admission, not durable application by the device.
        try? channel.send(
          Data([RelayFrameKind.mailboxAck.rawValue]) + Data(deliveryID.uuidString.utf8))
      }
    }
    connection.withLock { current in
      if let existing = current, ObjectIdentifier(existing) == id { current = nil }
    }
    let orphaned = waiters.withLock { waiters in
      defer { waiters.removeAll { $0.connection == id } }
      return waiters.filter { $0.connection == id }
    }
    for waiter in orphaned { waiter.continuation.resume(throwing: DeviceLayerError.closed) }
    let abandoned = controlWaiters.withLock { waiters in
      let abandoned = waiters.filter { $0.value.connection == id }
      for key in abandoned.keys { waiters.removeValue(forKey: key) }
      return Array(abandoned.values)
    }
    for waiter in abandoned { waiter.continuation.resume(throwing: DeviceLayerError.closed) }
  }
}

/// One link's frames to or from one device through the relay.
public final class RelayStream: FrameChannel {
  /// The device at the other end.
  public let peer: DeviceID
  private let client: RelayClient
  private let stream: UInt32
  private let queue: FrameQueue

  fileprivate init(client: RelayClient, peer: DeviceID, stream: UInt32, queue: FrameQueue) {
    self.client = client
    self.peer = peer
    self.stream = stream
    self.queue = queue
  }

  /// Sends one frame to the peer through the relay.
  public func send(_ frame: Data) throws { try client.send(frame, to: peer, stream: stream) }

  /// The peer's next frame.
  public func receive() async throws -> Data { try await queue.next() }

  /// Ends this stream locally.
  public func close() {
    queue.finish()
    client.remove(peer: peer, stream: stream)
  }
}
