import CryptoKit
import Foundation
import MemoshiProtocol
import Synchronization

/// The QR code's content (protocol.md §12.2, D82): a full-entropy one-time key, the paired
/// device's ID and public keys, and link hints. The key is the Noise IKpsk2 pre-shared key; the
/// code works once, for 5 minutes, and only while its screen is open.
public struct PairingInvitation: Hashable, Sendable {
  /// How long a code works after it is shown.
  public static let lifetimeMilliseconds: Int64 = 300_000
  /// The QR text prefix and version.
  public static let prefix = "memoshi-pair:1:"

  /// Names the code so the inviter can find its key; not secret.
  public let codeID: Data
  /// The one-time key, 32 random bytes: the handshake's pre-shared key.
  public let key: Data
  /// The device showing the code.
  public let inviter: DevicePeer
  /// When the code was shown, Unix milliseconds.
  public let issuedAt: Int64
  /// When it stops working.
  public let expiresAt: Int64
  /// Where to reach the inviter, such as `tcp:127.0.0.1:52011`.
  public let hints: [String]

  init(
    codeID: Data, key: Data, inviter: DevicePeer, issuedAt: Int64, expiresAt: Int64,
    hints: [String]
  ) {
    self.codeID = codeID
    self.key = key
    self.inviter = inviter
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
    self.hints = hints
  }

  private struct Wire: Codable {
    var c: String
    var k: String
    var d: DeviceID
    var s: String
    var a: String
    var i: Int64
    var x: Int64
    var h: [String]
  }

  /// The text the QR code encodes.
  public var text: String {
    let wire = Wire(
      c: codeID.base64URL, k: key.base64URL, d: inviter.deviceID, s: inviter.signingKey.base64URL,
      a: inviter.agreementKey.base64URL, i: issuedAt, x: expiresAt, h: hints)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let json = (try? encoder.encode(wire)) ?? Data()
    return Self.prefix + json.base64URL
  }

  /// Parses scanned QR text.
  public init(text: String) throws {
    guard text.hasPrefix(Self.prefix),
      let json = Data(base64URL: String(text.dropFirst(Self.prefix.count))),
      let wire = try? JSONDecoder().decode(Wire.self, from: json),
      let codeID = Data(base64URL: wire.c), codeID.count == 16,
      let key = Data(base64URL: wire.k), key.count == 32,
      let signing = Data(base64URL: wire.s), signing.count == 32,
      let agreement = Data(base64URL: wire.a), agreement.count == 32,
      wire.x > wire.i
    else { throw DeviceLayerError.invalid("pairing code") }
    self.init(
      codeID: codeID, key: key,
      inviter: DevicePeer(deviceID: wire.d, signingKey: signing, agreementKey: agreement),
      issuedAt: wire.i, expiresAt: wire.x, hints: wire.h)
  }
}

/// Why pairing was refused. Every reason surfaces as `pairing_failed` (protocol.md §12.2); the
/// reason is for diagnostics and tests.
public enum PairingRefusal: Error, Equatable, Sendable {
  /// No code with this ID was shown here.
  case unknownCode
  /// The code is older than 5 minutes.
  case expired
  /// The code already paired a device.
  case alreadyUsed
  /// The code's screen closed.
  case voided
  /// The handshake failed: a wrong key, a wrong device or a tampered message.
  case handshakeFailed
  /// A pairing message was missing, malformed or inconsistent with the handshake.
  case invalidMessage(String)
  /// A signature over the device list or the confirmation did not verify.
  case badSignature
  /// A pairing message is larger than ``PairingExchange/maximumMessageBytes``: the group has
  /// too many devices for another one to join. Nothing of the message was sent or kept.
  case oversizedMessage
  /// The group already has ``DeviceGroup/maximumMembers`` devices: no further device can join
  /// until one is removed.
  case groupFull

  /// The reason byte of the notice that tells a joiner why its pairing ends; nil for a refusal
  /// the joiner is not told.
  var noticeCode: UInt8? {
    if case .groupFull = self { 0x01 } else { nil }
  }

  /// The refusal a received notice stands for.
  init(noticeCode: UInt8?) {
    self = noticeCode == 0x01 ? .groupFull : .invalidMessage("pairing refused")
  }
}

/// The inviter's one-time codes: issued, single use, void when their screen closes.
public final class PairingCodeBook: Sendable {
  private enum Status: Equatable {
    case open
    case reserved(UUID)
    case used
    case voided
  }

  private struct Entry {
    var key: Data
    var expiresAt: Int64
    var status: Status
  }

  private let entries = Mutex<[Data: Entry]>([:])

  /// Creates an empty book.
  public init() {}

  /// Shows a new code. Each code is independent; the caller voids it when its screen closes.
  public func issue(
    for identity: DeviceIdentity, hints: [String],
    at now: Int64 = DeviceClock.wallMilliseconds()
  ) -> PairingInvitation {
    let invitation = PairingInvitation(
      codeID: Data.random(count: 16), key: Data.random(count: 32), inviter: identity.peer,
      issuedAt: now, expiresAt: now + PairingInvitation.lifetimeMilliseconds, hints: hints)
    entries.withLock {
      $0[invitation.codeID] = Entry(
        key: invitation.key, expiresAt: invitation.expiresAt, status: .open)
    }
    return invitation
  }

  /// The code's screen closed: the code stops working at once.
  public func void(_ codeID: Data) {
    entries.withLock { entries in
      switch entries[codeID]?.status {
      case .open, .reserved: entries[codeID]?.status = .voided
      case .used, .voided, nil: break
      }
    }
  }

  /// The key of a code that is still open and unexpired.
  func key(for codeID: Data, at now: Int64) throws(PairingRefusal) -> Data {
    let entry = entries.withLock { $0[codeID] }
    guard let entry else { throw .unknownCode }
    try Self.check(entry, at: now)
    return entry.key
  }

  /// A proven QR-key holder reserves one attempt; activation still requires its final signature.
  func reserve(_ codeID: Data, at now: Int64) throws(PairingRefusal) -> UUID {
    let token = UUID()
    let refusal: PairingRefusal? = entries.withLock { entries in
      guard let entry = entries[codeID] else { return .unknownCode }
      do throws(PairingRefusal) {
        try Self.check(entry, at: now)
      } catch { return error }
      entries[codeID]?.status = .reserved(token)
      return nil
    }
    if let refusal { throw refusal }
    return token
  }

  func validateReservation(_ codeID: Data, token: UUID, at now: Int64) throws(PairingRefusal) {
    guard let entry = entries.withLock({ $0[codeID] }) else { throw .unknownCode }
    try Self.checkReservation(entry, token: token, at: now)
  }

  func confirm(_ codeID: Data, token: UUID, at now: Int64) throws(PairingRefusal) {
    let refusal: PairingRefusal? = entries.withLock { entries in
      guard let entry = entries[codeID] else { return .unknownCode }
      do throws(PairingRefusal) {
        try Self.checkReservation(entry, token: token, at: now)
      } catch { return error }
      entries[codeID]?.status = .used
      return nil
    }
    if let refusal { throw refusal }
  }

  private static func checkReservation(
    _ entry: Entry, token: UUID, at now: Int64
  ) throws(PairingRefusal) {
    switch entry.status {
    case .reserved(let current):
      guard current == token else { throw .alreadyUsed }
      guard now < entry.expiresAt else { throw .expired }
    case .used: throw .alreadyUsed
    case .voided: throw .voided
    case .open: throw .invalidMessage("unreserved pairing confirmation")
    }
  }

  private static func check(_ entry: Entry, at now: Int64) throws(PairingRefusal) {
    switch entry.status {
    case .used: throw .alreadyUsed
    case .reserved: throw .alreadyUsed
    case .voided: throw .voided
    case .open: guard now < entry.expiresAt else { throw .expired }
    }
  }
}

/// The authority's compare-and-swap on the group epoch (protocol.md §12.4).
public typealias GroupCommitter = @Sendable (GroupCommit) async throws -> GroupCommitResult

/// Runs after the native transition is checkpointed, with its mutation gate released.
public typealias GroupCommitCompletion = @Sendable (GroupCommit) async throws -> Void

/// Seals the final hello of an accepted add and publishes it as one step, under the caller's
/// own send gate, so that nothing of the caller reads its feed between the seal and the
/// publication. Returns the seal.
public typealias PairingHelloSender =
  @Sendable (DeviceMessage) async throws -> DeviceSealedApplication

/// A completed pairing: the peer, the group epoch that added it, and the open link the pairing
/// ran on, whose first message after pairing is `device.hello`.
public struct PairingResult: Sendable {
  /// The device paired with.
  public let peer: DevicePeer
  /// The group's ID.
  public let groupID: String
  /// The group epoch after the add.
  public let groupEpoch: Int64
  /// The signed member list at that epoch.
  public let devices: SignedDeviceList
  /// The link, already authenticated by the pairing handshake.
  public let link: DeviceLink
  /// Measurement points on this side, monotonic nanoseconds.
  public let timings: PairingTimings
  /// True on the inviter when the authority accepted the add but the host's completion of it
  /// failed: the device is in the group and the pairing succeeded, but its final hello was not
  /// sent and the link is closed. The node completes the add on its retry and then delivers
  /// the hello, from which the joiner completes its join. Always false on the joiner.
  public let completionPending: Bool
}

/// Where the time went on one side of a pairing.
public struct PairingTimings: Codable, Hashable, Sendable {
  /// When the side started.
  public var started: UInt64
  /// When the two Noise messages were done and the transport keys existed.
  public var handshakeDone: UInt64
  /// When pairing completed on this side.
  public var paired: UInt64
}

/// Noise IKpsk2 authenticates the scanned QR and carries only the pairing bootstrap. A real
/// native KeyPackage/Welcome and durable membership CAS precede the first MLS device.hello.
public enum PairingExchange {
  /// The largest pairing message a device sends or accepts, in bytes of its encoding. A
  /// `pair.welcome` carries the native MLS Welcome and the signed device list, about 1.5 KB
  /// for each member of the group: a full group of ``DeviceGroup/maximumMembers`` devices
  /// needs about 100 KB, and this bound would hold about 170. A message that does not fit one
  /// Noise message (65,519 bytes) is sent as several.
  public static let maximumMessageBytes = 256 * 1024

  static func prologue(codeID: Data) -> Data { Data("memoshi.pair.v1".utf8) + codeID }

  /// The new device: scans the code and pairs over `channel`.
  public static func join(
    invitation: PairingInvitation, identity: DeviceIdentity, group: DeviceGroup,
    channel: any FrameChannel, appVersion: String = "0.0.1", osVersion: String = "27.0",
    beforeApplication: (@Sendable (UInt64) async throws -> Void)? = nil,
    now: @escaping @Sendable () -> Int64 = { DeviceClock.wallMilliseconds() }
  ) async throws -> PairingResult {
    try await withTaskCancellationHandler {
      let owner: UUID
      do { owner = try await group.beginJoinExchange() } catch {
        channel.close()
        throw error
      }
      do {
        let result = try await joinOpen(
          invitation: invitation, identity: identity, group: group, channel: channel,
          owner: owner, appVersion: appVersion, osVersion: osVersion,
          beforeApplication: beforeApplication, now: now)
        await group.endJoinExchange(owner)
        return result
      } catch {
        await group.endJoinExchange(owner)
        channel.close()
        throw error
      }
    } onCancel: {
      channel.close()
    }
  }

  private static func joinOpen(
    invitation: PairingInvitation, identity: DeviceIdentity, group: DeviceGroup,
    channel: any FrameChannel, owner: UUID, appVersion: String, osVersion: String,
    beforeApplication: (@Sendable (UInt64) async throws -> Void)?,
    now: @escaping @Sendable () -> Int64
  ) async throws -> PairingResult {
    let started = DeviceClock.monotonicNanoseconds()
    var handshake = try NoiseHandshake(
      pattern: .pairing, initiator: true, prologue: prologue(codeID: invitation.codeID),
      localStatic: identity.agreementKey(),
      remoteStatic: invitation.inviter.agreementPublicKey, psk: invitation.key)
    let first = try handshake.writeMessage()
    do {
      try Task.checkCancellation()
      try channel.send(
        Data([LinkFrameKind.pairingInitiation.rawValue]) + invitation.codeID + first)
      let reply = try await channel.receive()
      guard reply.first == LinkFrameKind.pairingResponse.rawValue else {
        throw PairingRefusal.invalidMessage("expected a pairing response")
      }
      do {
        _ = try handshake.readMessage(Data(reply.dropFirst()))
      } catch {
        throw PairingRefusal.handshakeFailed
      }
    } catch {
      channel.close()
      if Task.isCancelled { throw CancellationError() }
      throw error is PairingRefusal ? error : PairingRefusal.handshakeFailed
    }
    let handshakeDone = DeviceClock.monotonicNanoseconds()
    var link = DeviceLink(
      peer: invitation.inviter, route: .direct, transport: try handshake.split(),
      channel: channel)
    var confirmationAttempted = false
    do {
      let me = identity.peer
      let keyPackage = try await group.prepareJoining()
      try Task.checkCancellation()
      try await link.sendBootstrap(
        message(
          from: identity, to: invitation.inviter.deviceID, at: now(),
          .pairHello(
            PairHello(
              deviceId: identity.deviceID, name: try DeviceName(String(identity.name.prefix(60))),
              platform: identity.platform, osVersion: osVersion, appVersion: appVersion,
              publicKeys: try me.publicKeys,
              keyPackage: try Base64Bytes(keyPackage.base64EncodedString())))))
      guard case .pairWelcome(let welcome) = try await link.receiveBootstrap().body else {
        throw PairingRefusal.invalidMessage("expected pair.welcome")
      }
      if let hint = invitation.hints.first(where: { $0.hasPrefix("group:") }) {
        guard String(hint.dropFirst(6)) == welcome.groupId else {
          throw PairingRefusal.invalidMessage("QR group identity mismatch")
        }
      }
      guard
        DeviceGroup.verify(welcome.devices, groupID: welcome.groupId, signer: invitation.inviter),
        welcome.devices.epoch == welcome.epoch,
        welcome.devices.signerDeviceId == invitation.inviter.deviceID,
        welcome.devices.devices.contains(where: {
          $0.deviceId == identity.deviceID
            && (try? DevicePeer(deviceID: $0.deviceId, publicKeys: $0.publicKeys)) == me
        })
      else { throw PairingRefusal.badSignature }
      try Task.checkCancellation()
      guard let nativeWelcome = Data(base64Encoded: welcome.welcome.rawValue),
        !nativeWelcome.isEmpty
      else {
        throw PairingRefusal.invalidMessage("missing native MLS Welcome")
      }
      try await group.join(
        groupID: welcome.groupId, list: welcome.devices, inviter: invitation.inviter,
        welcome: nativeWelcome)
      try Task.checkCancellation()
      let confirmation = try confirmStatement(
        deviceID: identity.deviceID, keys: try me.publicKeys, epoch: welcome.epoch,
        handshakeHash: link.handshakeHash)
      confirmationAttempted = true
      try await group.markConfirmationAttempted()
      try await link.sendBootstrap(
        message(
          from: identity, to: invitation.inviter.deviceID, at: now(),
          .pairConfirm(
            PairConfirm(
              deviceId: identity.deviceID, publicKeys: try me.publicKeys, epoch: welcome.epoch,
              signature: try Base64Bytes(identity.sign(confirmation).base64EncodedString())))))
      link = DeviceLink(
        peer: invitation.inviter, route: .direct, transport: try await link.detachTransport(),
        channel: channel, group: group, beforeApplication: beforeApplication)
      let hello = try await link.receive()
      guard case .deviceHello = hello.body else {
        throw PairingRefusal.invalidMessage("expected device.hello")
      }
      try await group.finishJoin(hello, owner: owner)
      try await link.acknowledgeReceived(hello.msgId)
      return PairingResult(
        peer: invitation.inviter, groupID: welcome.groupId, groupEpoch: welcome.epoch,
        devices: welcome.devices, link: link,
        timings: PairingTimings(
          started: started, handshakeDone: handshakeDone,
          paired: DeviceClock.monotonicNanoseconds()),
        completionPending: false)
    } catch {
      await link.close()
      if !confirmationAttempted { await group.abandonUnconfirmedJoin() }
      if Task.isCancelled { throw CancellationError() }
      throw error
    }
  }

  /// The device showing the code: answers one pairing attempt on `channel`.
  public static func accept(
    identity: DeviceIdentity, book: PairingCodeBook, group: DeviceGroup, channel: any FrameChannel,
    commit: GroupCommitter? = nil, groupDidCommit: GroupCommitCompletion? = nil,
    applicationSend: DeviceApplicationSender? = nil, helloSend: PairingHelloSender? = nil,
    applicationFeedReader: DeviceApplicationEpochReader? = nil,
    beforeApplication: (@Sendable (UInt64) async throws -> Void)? = nil,
    appVersion: String = "0.0.1",
    now: @escaping @Sendable () -> Int64 = { DeviceClock.wallMilliseconds() }
  ) async throws -> PairingResult {
    try await withTaskCancellationHandler {
      try await acceptOpen(
        identity: identity, book: book, group: group, channel: channel, commit: commit,
        groupDidCommit: groupDidCommit, applicationSend: applicationSend, helloSend: helloSend,
        applicationFeedReader: applicationFeedReader, beforeApplication: beforeApplication,
        appVersion: appVersion, now: now)
    } onCancel: {
      channel.close()
    }
  }

  private static func acceptOpen(
    identity: DeviceIdentity, book: PairingCodeBook, group: DeviceGroup, channel: any FrameChannel,
    commit: GroupCommitter?, groupDidCommit: GroupCommitCompletion?,
    applicationSend: DeviceApplicationSender?, helloSend: PairingHelloSender?,
    applicationFeedReader: DeviceApplicationEpochReader?,
    beforeApplication: (@Sendable (UInt64) async throws -> Void)?,
    appVersion: String, now: @escaping @Sendable () -> Int64
  ) async throws -> PairingResult {
    let started = DeviceClock.monotonicNanoseconds()
    var handshake: NoiseHandshake
    let codeID: Data
    do {
      let first = try await channel.receive()
      guard first.first == LinkFrameKind.pairingInitiation.rawValue, first.count > 17 else {
        throw PairingRefusal.invalidMessage("expected a pairing initiation")
      }
      codeID = Data(first.dropFirst().prefix(16))
      let key = try book.key(for: codeID, at: now())
      handshake = try NoiseHandshake(
        pattern: .pairing, initiator: false, prologue: prologue(codeID: codeID),
        localStatic: identity.agreementKey(), psk: key)
      do {
        _ = try handshake.readMessage(Data(first.dropFirst(17)))
        try channel.send(
          Data([LinkFrameKind.pairingResponse.rawValue]) + handshake.writeMessage())
      } catch {
        throw PairingRefusal.handshakeFailed
      }
    } catch {
      channel.close()
      throw error
    }
    let handshakeDone = DeviceClock.monotonicNanoseconds()
    guard let remote = handshake.remoteStatic else {
      channel.close()
      throw PairingRefusal.handshakeFailed
    }
    // The joiner's identity is checked against its pair.hello below; until then the link's peer
    // is only its static key.
    let provisional = DevicePeer(
      deviceID: identity.deviceID, signingKey: Data(), agreementKey: remote.rawRepresentation)
    var link = DeviceLink(
      peer: provisional, route: .direct, transport: try handshake.split(), channel: channel)
    var preparedID: UUID?
    do {
      let helloMessage: DeviceMessage
      do {
        helloMessage = try await link.receiveBootstrap()
      } catch NoiseError.decryptFailed {
        // The joiner does not hold the code's key.
        throw PairingRefusal.handshakeFailed
      }
      guard case .pairHello(let hello) = helloMessage.body,
        helloMessage.from == .device(hello.deviceId)
      else { throw PairingRefusal.invalidMessage("expected pair.hello") }
      let joiner = try DevicePeer(deviceID: hello.deviceId, publicKeys: hello.publicKeys)
      guard joiner.agreementKey == remote.rawRepresentation else {
        throw PairingRefusal.invalidMessage("pair.hello keys differ from the handshake")
      }
      try Task.checkCancellation()
      // A full group adds no device: the joiner is told why, and its code is not reserved.
      guard await group.members.count < DeviceGroup.maximumMembers else {
        throw PairingRefusal.groupFull
      }
      let reservation = try book.reserve(codeID, at: now())
      guard let keyPackage = Data(base64Encoded: hello.keyPackage.rawValue), !keyPackage.isEmpty
      else {
        throw PairingRefusal.invalidMessage("missing native MLS KeyPackage")
      }
      let prepared = try await group.prepareAdding(
        joiner, name: hello.name.rawValue, platform: hello.platform, keyPackage: keyPackage)
      preparedID = prepared.id
      let signed = prepared.devices
      let epoch = signed.epoch
      guard let nativeWelcome = prepared.staged.welcome else {
        throw PairingRefusal.invalidMessage("native MLS add has no Welcome")
      }
      try await link.sendBootstrap(
        message(
          from: identity, to: joiner.deviceID, at: now(),
          .pairWelcome(
            PairWelcome(
              groupId: await group.groupID, epoch: epoch,
              welcome: try Base64Bytes(nativeWelcome.base64EncodedString()),
              devices: signed))))
      let confirmationMessage = try await receiveConfirmation(
        link: link, channel: channel, book: book, codeID: codeID, token: reservation, now: now)
      guard confirmationMessage.from == .device(joiner.deviceID),
        case .pairConfirm(let confirm) = confirmationMessage.body,
        confirm.deviceId == joiner.deviceID, confirm.epoch == epoch,
        (try? DevicePeer(deviceID: confirm.deviceId, publicKeys: confirm.publicKeys)) == joiner,
        let signature = Data(base64Encoded: confirm.signature.rawValue)
      else { throw PairingRefusal.invalidMessage("expected pair.confirm") }
      let statement = try confirmStatement(
        deviceID: joiner.deviceID, keys: confirm.publicKeys, epoch: epoch,
        handshakeHash: link.handshakeHash)
      guard joiner.verify(signature, over: statement) else { throw PairingRefusal.badSignature }
      try Task.checkCancellation()
      try book.confirm(codeID, token: reservation, at: now())
      let finalHello = try message(
        from: identity, to: joiner.deviceID, at: now(),
        .deviceHello(
          DeviceHello(
            appVersion: appVersion, appBuild: "1",
            protocolRange: ProtocolRange(
              min: ProtocolVersion.current, max: ProtocolVersion.current),
            capabilities: [], oldestRunnableAppVersion: appVersion)))
      _ = try await group.confirmAdding(
        prepared, hello: finalHello, commit: commit, applicationFeedReader: applicationFeedReader)
      // The add is committed: the device is in the group, and the pairing succeeds, also when
      // the host's completion of the add fails. That completion stays owed in the group state,
      // and the node finishes it on its retry, then delivers the hello (D133).
      let completionPending: Bool
      do {
        try await group.completeCommittedMembership(using: groupDidCommit)
        completionPending = false
      } catch let error where !(error is CancellationError) {
        completionPending = true
      }
      link = DeviceLink(
        peer: joiner, route: .direct, transport: try await link.detachTransport(),
        channel: channel, group: group, beforeApplication: beforeApplication)
      // Its final hello goes on this link when the authority accepted its seal, or the seal of
      // the same hello in a later group state when the hello's own state closed first (D131).
      // When neither is accepted yet, the completion is pending, or the link cannot take it,
      // the link ends, and the joiner completes its join from the hello in the group's feed.
      if !completionPending,
        let hello = await acceptedHello(
          finalHello, group: group, helloSend: helloSend, applicationSend: applicationSend)
      {
        do { try await link.sendSealed(hello) } catch { await link.close() }
      } else {
        await link.close()
      }
      return PairingResult(
        peer: joiner, groupID: await group.groupID, groupEpoch: epoch, devices: signed,
        link: link,
        timings: PairingTimings(
          started: started, handshakeDone: handshakeDone,
          paired: DeviceClock.monotonicNanoseconds()),
        completionPending: completionPending)
    } catch {
      if let refusal = error as? PairingRefusal, refusal.noticeCode != nil {
        try? await link.sendPairingRefusal(refusal)
      }
      await link.close()
      if let preparedID { await group.discardAdding(preparedID) }
      if Task.isCancelled { throw CancellationError() }
      throw error
    }
  }

  /// Seals and publishes the final hello and returns its seal once the authority accepted it:
  /// only an accepted seal is ever emitted. A seal whose group state closed first was retired;
  /// the second attempt seals the same hello again in the state the group is in now, under the
  /// same operation ID (D131), or returns that seal if it was made already. Nil when no seal is
  /// accepted yet: the group still owes the hello and its node publishes it later.
  private static func acceptedHello(
    _ hello: DeviceMessage, group: DeviceGroup, helloSend: PairingHelloSender?,
    applicationSend: DeviceApplicationSender?
  ) async -> DeviceSealedApplication? {
    for _ in 0..<2 {
      let sealed: DeviceSealedApplication
      do {
        if let helloSend {
          sealed = try await helloSend(hello)
        } else {
          sealed = try await group.sealDeviceMessage(hello)
          if let applicationSend { try await applicationSend(sealed) }
        }
      } catch {
        continue
      }
      let ciphertext = sealed.message.ciphertext
      if (try? await group.applicationWasProcessed(ciphertext: ciphertext)) == true,
        (try? await group.applicationAwaitsReseal(ciphertext: ciphertext)) == false
      {
        return sealed
      }
    }
    return nil
  }

  /// Closing/expiring a displayed QR also wakes a peer withholding pair.confirm. Losing timer
  /// cancellation never closes a successful channel; genuine expiry/void closes only this one.
  private static func receiveConfirmation(
    link: DeviceLink, channel: any FrameChannel, book: PairingCodeBook, codeID: Data, token: UUID,
    now: @escaping @Sendable () -> Int64
  ) async throws -> DeviceMessage {
    try await withThrowingTaskGroup(of: DeviceMessage.self) { tasks in
      tasks.addTask { try await link.receiveBootstrap() }
      tasks.addTask {
        do {
          while true {
            try Task.checkCancellation()
            try book.validateReservation(codeID, token: token, at: now())
            try await Task.sleep(for: .milliseconds(100))
          }
        } catch {
          if !Task.isCancelled { channel.close() }
          throw error
        }
      }
      defer { tasks.cancelAll() }
      guard let message = try await tasks.next() else { throw DeviceLayerError.closed }
      return message
    }
  }

  static func confirmStatement(
    deviceID: DeviceID, keys: DevicePublicKeys, epoch: Int64, handshakeHash: Data
  ) throws -> Data {
    struct Statement: Encodable {
      let purpose = "memoshi.pair.confirm.v1"
      let deviceId: DeviceID
      let publicKeys: DevicePublicKeys
      let epoch: Int64
      let handshakeHash: String
    }
    return Data(
      try ProtocolCoding.canonicalText(
        of: Statement(
          deviceId: deviceID, publicKeys: keys, epoch: epoch,
          handshakeHash: handshakeHash.base64EncodedString())
      ).utf8)
  }

  static func message(
    from identity: DeviceIdentity, to deviceID: DeviceID, at now: Int64, _ body: DeviceMessageBody
  ) throws -> DeviceMessage {
    DeviceMessage(
      msgId: try DeviceULID.next(), from: .device(identity.deviceID), to: .device(deviceID),
      sentAt: now, body: body)
  }
}

extension Data {
  /// `count` bytes from the system's secure random generator.
  static func random(count: Int) -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
  }

  /// Unpadded base64url.
  var base64URL: String {
    base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  /// Decodes unpadded base64url.
  init?(base64URL text: String) {
    var standard = text.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while standard.count % 4 != 0 { standard += "=" }
    self.init(base64Encoded: standard)
  }
}
