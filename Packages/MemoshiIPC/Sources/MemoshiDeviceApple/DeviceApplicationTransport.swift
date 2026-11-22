import Foundation
import MemoshiDevice
import MemoshiProtocol
import Synchronization

/// Local send progress only; neither state proves remote application or grants execution authority.
public enum DeviceSendState: String, Sendable {
  /// Restart-safe local ciphertext only; not a remote delivery, lease or execution permission.
  case queued
  /// A carrier accepted it; only an authenticated, durable peer receipt proves application.
  case carrierAccepted
}

/// Identifies a durably reserved application send and its observed carrier progress.
/// A peer's authenticated host-apply acknowledgement is a separate boundary.
public struct DeviceSendReceipt: Sendable {
  /// Original application message identifier retained for deduplication across retransmission.
  public let messageID: String
  /// Reserved positive sequence within the sender/recipient/application stream.
  public let sequence: UInt64
  /// Whether a live carrier accepted the published ciphertext, not whether the peer applied it.
  public let state: DeviceSendState
}

/// One peer's routes; every transport for a Node shares DeviceTransportStore and the Node's
/// genuine Native group. Publication/epoch-reader callbacks must be the real relay or Cloud
/// authority. Init starts no network, listener, account lookup, camera or credential grant.
public actor DeviceApplicationTransport {
  private let identity: DeviceIdentity
  private let peer: DevicePeer
  private let group: DeviceGroup
  private let node: DeviceNode
  private let store: DeviceTransportStore
  private let application: any DeviceMessageApplying
  private let publishApplication: DeviceApplicationSender
  private let epochReader: DeviceApplicationEpochReader
  private let cloudSpool: CloudMailboxStore?
  private let groupAuthority: CloudKitGroupAuthority?
  private let now: @Sendable () -> Int64
  private var draining = false
  private var closed = false
  private var listening = false
  private var listener: DeviceBonjourListener?
  /// Carrier frames whose Native predecessor had not been opened yet, by ciphertext identifier.
  /// DeviceGroup keeps their ciphertext across restart, but on a live direct or relay route
  /// only these bytes bring the opened envelope back to this transport. They are memory only:
  /// a restart reconnects, and the sender then replays its unacknowledged frames.
  private var parked: [String: Data] = [:]
  private var parkedBytes = 0
  /// The bound DeviceGroup applies to its own retained inbox; beyond it a frame is not parked
  /// here and is recovered by the sender's next replay, as before.
  private static let maximumParkedBytes = 12 * 1024 * 1024
  /// Re-offers parked frames when the group opens an application by any path, including the
  /// Node's link, feed catch-up and another peer's transport, none of which hands a parked
  /// frame back to this transport. Started with the first inbound frame; `stop()` cancels it.
  private var parkedWatcher: Task<Void, Never>?
  private var backgroundFailure: (any Error)?
  /// The seal in progress for each message ID (see `seal(_:)`).
  private var sealing: [String: Task<Data, any Error>] = [:]
  /// Runs in `pendingCiphertexts` after it read the store's pending sends and before it seals
  /// them; tests use it to send meanwhile.
  nonisolated let afterPendingSnapshot = Mutex<(@Sendable () async -> Void)?>(nil)
  private lazy var racer = DeviceLinkRacer(
    pending: { [weak self] in
      guard let self else { throw AppleDeviceError.closed }
      return try await self.pendingCiphertexts()
    },
    receive: { [weak self] bytes in
      guard let self else { throw AppleDeviceError.closed }
      try await self.receive(bytes)
    })

  /// Retains the caller's Node/group, shared durable transport store, and transactional host.
  /// `publish`/`epochReader` must use the actual authority; an iCloud route also requires its shared
  /// mailbox spool. Construction starts no work, and `now` supplies Unix milliseconds for expiry.
  public init(
    identity: DeviceIdentity, peer: DevicePeer, group: DeviceGroup, node: DeviceNode,
    store: DeviceTransportStore, application: any DeviceMessageApplying,
    publish: @escaping DeviceApplicationSender, epochReader: @escaping DeviceApplicationEpochReader,
    cloudSpool: CloudMailboxStore? = nil, groupAuthority: CloudKitGroupAuthority? = nil,
    now: @escaping @Sendable () -> Int64 = { DeviceClock.wallMilliseconds() }
  ) {
    self.identity = identity
    self.peer = peer
    self.group = group
    self.node = node
    self.store = store
    self.application = application
    publishApplication = publish
    self.epochReader = epochReader
    self.cloudSpool = cloudSpool
    self.groupAuthority = groupAuthority
    self.now = now
  }

  /// Refreshes membership, publishes own seals the authority has not accepted yet, catches up
  /// the authority feed and retained inbox, then starts candidates in direct/relay/iCloud
  /// priority with the supplied duration between successive attempts.
  /// Recovery, lifecycle, or missing-iCloud-spool failures throw without granting message authority.
  /// One-shot: a second start is refused before any refresh, catch-up or replay, and a lost relay
  /// or iCloud route is not dialled again. To reconnect, stop this transport and build a new one
  /// over the same shared store.
  public func start(_ candidates: [DeviceRouteCandidate], stagger: Duration) async throws {
    guard !closed else { throw AppleDeviceError.closed }
    guard !candidates.contains(where: { $0.route == .icloud }) || cloudSpool != nil else {
      throw AppleDeviceError.invalidState("Cloud route requires its durable shared spool")
    }
    try await racer.requireStartable(candidates)
    try await node.refreshMembership()
    try await ensurePeer()
    // An acknowledgement whose seal a closed epoch never accepted is sealed again first: the
    // publication below then carries it, like every other pending seal.
    for retained in try await store.retainedAcknowledgements(
      from: peer.deviceID, to: identity.deviceID)
    {
      _ = try await currentAcknowledgement(retained)
    }
    try await abandonSupersededAcknowledgements()
    // A seal advances this device's own feed cursor when it is made. Catch-up refuses a cursor
    // ahead of the authority, so seals whose publication failed are published first.
    for item in try await group.pendingApplicationFeed() { try await publishApplication(item) }
    try await group.catchUpApplicationFeed(using: epochReader)
    if let latest = try await cloudSpool?.incoming().last { try await receive(latest.bytes) }
    _ = try await pendingCiphertexts()
    try await racer.start(candidates, stagger: stagger)
    try await drain()
  }

  /// Returns the racer's local lifecycle stream; observing it starts no route or delivery work.
  public func routeEvents() -> AsyncStream<DeviceRouteEvent> { racer.events }

  /// Returns the failure of the last delivery pass that ran on a group wake-up, where no route
  /// was being read whose end would report it, or `nil` once a later delivery pass succeeded.
  /// Observation only: it retries nothing and grants no authority.
  public func recoveryFailure() -> (any Error)? { backgroundFailure }

  /// Separate data service instance from Node's pairing/control port. Only explicit opt-in
  /// starts Bonjour/local-network use; the outer Noise IK authenticates an already-paired peer.
  public func listenBonjour() async throws -> Int {
    guard !closed else { throw AppleDeviceError.closed }
    if let listener { return listener.port }
    guard !listening else { throw AppleDeviceError.invalidState("data listener opening") }
    listening = true
    defer { listening = false }
    try await ensurePeer()
    let opened = try await AppleDirectCarrier.listenBonjour(
      identity: identity, group: group, peer: peer
    ) { [weak self] endpoint in
      guard let self else {
        await endpoint.close()
        return
      }
      await self.attachDirect(endpoint)
    }
    guard !closed else {
      opened.close()
      throw AppleDeviceError.closed
    }
    listener = opened
    return opened.port
  }

  private func attachDirect(_ endpoint: DeviceRouteEndpoint) async {
    guard !closed else {
      await endpoint.close()
      return
    }
    await racer.attach(endpoint, route: .direct)
  }

  /// Call on membership/revocation changes as well as launch/wake. Every actual send/read also
  /// checks Native membership; an idle old socket is never authority to execute a command.
  public func refreshMembership() async throws {
    try await node.refreshMembership()
    do { try await ensurePeer() } catch {
      await stop()
      throw error
    }
  }

  /// Mints the ID for a message that will be sent through this transport. It is the ULID of the
  /// current time unless the clock gives one at or below an ID this device's send history
  /// already covers, in which case it is the next ULID above that. A send with such an ID is
  /// never refused as `retiredMessageIdentifier`, even after the clock was set back.
  public func nextMessageID() async throws -> ULID {
    try await store.mintMessageID(at: now())
  }

  /// Durably reserves and seals a message for this peer, publishing to the authority before carrier
  /// fanout. Acknowledged sends are remembered up to the store's capacity; beyond it the oldest
  /// are retired, and a message whose unknown ID is not above theirs is refused with
  /// `retiredMessageIdentifier` instead of being sent a second time. `expiresAt` is Unix milliseconds; encoded message JSON is limited to 40 KiB to leave
  /// MLS-envelope space. Failures can leave restart-safe pending work; a returned receipt never
  /// proves peer application, and retransmission reuses the original reserved ciphertext.
  public func send(_ message: DeviceMessage, stream: String, expiresAt: Int64? = nil) async throws
    -> DeviceSendReceipt
  {
    guard !closed, message.from == .device(identity.deviceID), message.to == .device(peer.deviceID)
    else {
      throw AppleDeviceError.invalidState("application sender/recipient")
    }
    try await node.refreshMembership()
    try await ensurePeer()
    let info = try await group.groupInfo()
    guard expiresAt.map({ $0 > now() }) ?? true else {
      throw AppleDeviceError.invalidState("expired outgoing message")
    }
    let bytes = try ProtocolCoding.makeEncoder().encode(message)
    // DeviceGroup's real Native plaintext ceiling is 64 KiB. Leave room for the authenticated
    // envelope's base64 and metadata instead of persisting an impossible oversized intent.
    guard bytes.count <= 40 * 1024 else {
      throw AppleDeviceError.invalidState("application message exceeds carrier limit")
    }
    let outgoing = try await store.reserve(
      messageID: message.msgId.rawValue, sender: identity.deviceID, recipient: peer.deviceID,
      stream: stream, groupEpoch: info.epoch, expiresAt: expiresAt, payload: bytes)
    let packet = try await seal(outgoing)
    try await publishApplication(DeviceTransportPacket(decoding: packet).application())
    let state: DeviceSendState
    do {
      try await racer.publish(packet)
      state = .carrierAccepted
    } catch AppleDeviceError.authorityUnavailable { state = .queued }
    return DeviceSendReceipt(
      messageID: outgoing.delivery.messageID, sequence: outgoing.delivery.sequence, state: state)
  }

  /// Seals a message, or returns the frame retained for it. A send and a replay of the same
  /// message share one seal at a time, and each acts on the message's entry as the store holds
  /// it then, not on what its caller read earlier: the replay of an intent that a send sealed
  /// meanwhile returns that seal instead of minting a second one for the same message.
  private func seal(_ outgoing: DeviceTransportStore.Outgoing) async throws -> Data {
    let messageID = outgoing.delivery.messageID
    while let running = sealing[messageID] { _ = await running.result }
    let task = Task {
      defer { sealing[messageID] = nil }
      let frame = try await sealCurrent(try await store.outgoing(messageID: messageID) ?? outgoing)
      // This transport owns the message, so the seal's own plaintext receipt ends here, as
      // every receipt this device opened does. The group keeps it until the authority has
      // accepted the seal: D131 may still seal it again.
      try await group.acknowledgeOpened(
        ciphertext: DeviceTransportPacket(decoding: frame).ciphertext)
      return frame
    }
    sealing[messageID] = task
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private func sealCurrent(_ outgoing: DeviceTransportStore.Outgoing) async throws -> Data {
    if let ciphertext = outgoing.ciphertext {
      guard
        try await group.applicationAwaitsReseal(
          ciphertext: DeviceTransportPacket(decoding: ciphertext).ciphertext)
      else { return ciphertext }
      // The group retired this seal: its epoch closed before the authority accepted it, so
      // the frame was never published and never put on a carrier. The message goes back to
      // an unsealed intent in the installed epoch and is sealed again under the same
      // operation, with its message ID and sequence. No receiver can hold the retired frame,
      // so none can apply both (D131).
      let epoch = try await group.groupInfo().epoch
      guard epoch > outgoing.delivery.groupEpoch else { throw AppleDeviceError.staleEpoch }
      let intent = try await store.unseal(
        messageID: outgoing.delivery.messageID, groupEpoch: epoch)
      return try await seal(intent.delivery)
    }
    do {
      return try await seal(outgoing.delivery)
    } catch AppleDeviceError.staleEpoch {
      // The intent was reserved before a membership change and never sealed, so nothing bound
      // to its epoch has left this device. Seal it in the current epoch with its original
      // sequence; a change that lands during this attempt is retried by the next caller.
      let rebound = try await store.rebind(
        messageID: outgoing.delivery.messageID, groupEpoch: try await group.groupInfo().epoch)
      if let ciphertext = rebound.ciphertext { return ciphertext }
      return try await seal(rebound.delivery)
    }
  }

  private func seal(_ delivery: DeviceDelivery) async throws -> Data {
    // An add whose host completion is pending owes its hello first: finish it, as the node's
    // own sends do, or the group refuses this seal.
    try await node.finishPendingMembershipChange()
    let envelope = DeviceGroupEnvelope(version: 1, body: .application(delivery))
    let operationID = "application." + delivery.messageID
    let groupID = await group.groupID
    let ordered = try await group.sealOrderedApplication(
      JSONEncoder().encode(envelope), operationID: operationID
    ) { ordinal, epoch in
      guard epoch == delivery.groupEpoch else { throw AppleDeviceError.staleEpoch }
      return try DeviceTransportHeader(
        groupID: groupID, groupEpoch: epoch, sender: delivery.sender, recipient: delivery.recipient,
        ordinal: ordinal
      ).authenticatedData()
    }
    let packet = try CloudKitFeedAuthority.packet(ordered, groupID: groupID, identity: identity)
      .encoded()
    let retained = try await store.sealed(messageID: delivery.messageID, ciphertext: packet)
    try await group.acknowledgeSealed(operationID: operationID)
    return retained
  }

  private static func acknowledgementOperation(stream: String, sequence: UInt64) -> String {
    "acknowledgement." + stream + ".\(sequence)"
  }

  /// Seals an acknowledgement envelope for `recipient` under its stream's operation ID and
  /// returns the seal with its signed frame.
  private func sealAcknowledgement(
    _ envelope: Data, stream: String, sequence: UInt64, recipient: DeviceID
  ) async throws -> (seal: DeviceSealedApplication, frame: Data) {
    try await node.finishPendingMembershipChange()
    let groupID = await group.groupID
    let sender = identity.deviceID
    let ordered = try await group.sealOrderedApplication(
      envelope, operationID: Self.acknowledgementOperation(stream: stream, sequence: sequence)
    ) { ordinal, epoch in
      try DeviceTransportHeader(
        groupID: groupID, groupEpoch: epoch, sender: sender, recipient: recipient,
        ordinal: ordinal
      ).authenticatedData()
    }
    // As for a message: the seal's own plaintext receipt ends here, and the group keeps it
    // until the authority has accepted the seal.
    try await group.acknowledgeOpened(ciphertext: ordered.message.ciphertext)
    return (
      ordered,
      try CloudKitFeedAuthority.packet(ordered, groupID: groupID, identity: identity).encoded()
    )
  }

  /// The frame of a stream's latest acknowledgement. When the group retired its seal (the
  /// epoch closed before the authority accepted it, so it was never published and never put
  /// on a carrier), the same acknowledgement is first sealed again in the installed epoch
  /// under the same operation ID, as an application message is (D131). The store saves the
  /// retired seal's plaintext before the group seals, so that a restart at any step seals
  /// the same bytes under the same operation and ends with one acknowledgement.
  private func currentAcknowledgement(_ retained: DeviceTransportStore.RetainedAcknowledgement)
    async throws -> Data
  {
    let retired = try DeviceTransportPacket(decoding: retained.frame)
    var plaintext = retained.resealing
    if plaintext == nil {
      guard try await group.applicationAwaitsReseal(ciphertext: retired.ciphertext) else {
        return retained.frame
      }
      guard
        let held = try await group.applicationReceipt(ciphertext: retired.ciphertext)?.opened
          .plaintext
      else { throw AppleDeviceError.stateRecoveryRequired }
      try await store.unsealAcknowledgement(stream: retained.stream, plaintext: held)
      plaintext = held
    }
    guard let plaintext,
      case .acknowledgement(let sender, let recipient, let stream, let sequence, _, _) =
        try JSONDecoder().decode(DeviceGroupEnvelope.self, from: plaintext).body,
      sender == identity.deviceID,
      recipient.rawValue + ":" + sender.rawValue + ":" + stream == retained.stream
    else { throw AppleDeviceError.conflictingReplay }
    guard try await group.groupInfo().epoch > retired.groupEpoch else {
      throw AppleDeviceError.staleEpoch
    }
    let frame = try await sealAcknowledgement(
      plaintext, stream: retained.stream, sequence: sequence, recipient: recipient
    ).frame
    let current = try await store.resealedAcknowledgement(
      stream: retained.stream, ciphertext: frame)
    try await group.acknowledgeSealed(
      operationID: Self.acknowledgementOperation(stream: retained.stream, sequence: sequence))
    try await abandonSupersededAcknowledgements()
    return current
  }

  /// Ends the retired acknowledgement seals of this peer's streams that will never be sealed
  /// again: those for a sequence below their stream's cursor. The acknowledgement at the
  /// cursor is cumulative and answers the sender for all of them, and it is the only one this
  /// transport seals again. Without this, such a seal and its plaintext would stay in the
  /// group for good. A retired seal was never accepted and never put on a carrier.
  private func abandonSupersededAcknowledgements() async throws {
    let prefix =
      "acknowledgement." + peer.deviceID.rawValue + ":" + identity.deviceID.rawValue + ":"
    for operation in try await group.retiredOrderedOperations() where operation.hasPrefix(prefix) {
      // The operation ID ends in the stream name, a dot and the sequence.
      let rest = operation.dropFirst(prefix.count)
      guard let dot = rest.lastIndex(of: "."),
        let sequence = UInt64(rest[rest.index(after: dot)...]),
        try await sequence
          < store.cursor(
            sender: peer.deviceID, recipient: identity.deviceID, stream: String(rest[..<dot]))
      else { continue }
      try await group.abandonRetired(operationID: operation)
    }
  }

  func pendingCiphertexts() async throws -> [Data] {
    try await ensurePeer()
    var frames: [Data] = []
    // One frame per seal, keyed by the device's seal ordinal: device signatures are randomized,
    // so a pending feed item whose journaled frame is already listed must not be signed again.
    var seals: Set<UInt64> = []
    let pending = try await store.pendingOutgoing(to: peer.deviceID)
    if let hold = afterPendingSnapshot.withLock({ $0 }) { await hold() }
    for outgoing in pending {
      let bytes = try await seal(outgoing)
      if seals.insert(try DeviceTransportPacket(decoding: bytes).header.ordinal).inserted {
        frames.append(bytes)
      }
    }
    // Include ALL sender generations, including Node controls and other recipients. A selected
    // peer may ignore their domain content only AFTER opening/checkpointing their ratchets.
    let groupID = await group.groupID
    for item in try await group.pendingApplicationFeed() {
      try await publishApplication(item)
      guard seals.insert(item.ordinal).inserted else { continue }
      frames.append(
        try CloudKitFeedAuthority.packet(item, groupID: groupID, identity: identity).encoded())
    }
    for bytes in frames {
      try await publishApplication(DeviceTransportPacket(decoding: bytes).application())
    }
    return try frames.sorted {
      let lhs = try DeviceTransportPacket(decoding: $0)
      let rhs = try DeviceTransportPacket(decoding: $1)
      if lhs.groupEpoch != rhs.groupEpoch { return lhs.groupEpoch < rhs.groupEpoch }
      return lhs.header.ordinal < rhs.header.ordinal
    }
  }

  private func ensurePeer() async throws {
    let info = try await group.groupInfo()
    guard info.isActive, identity.deviceID != peer.deviceID,
      await group.member(peer.deviceID, agreementKey: peer.agreementKey) == peer
    else { throw AppleDeviceError.revoked }
  }

  private func signer(for packet: DeviceTransportPacket) async throws -> DevicePeer {
    guard packet.header.groupID == (await group.groupID) else {
      throw AppleDeviceError.conflictingReplay
    }
    if packet.header.sender == identity.deviceID { return identity.peer }
    if let groupAuthority {
      return try await groupAuthority.signer(packet.header.sender, at: packet.groupEpoch)
    }
    guard let entry = await group.members.first(where: { $0.deviceId == packet.header.sender })
    else { throw AppleDeviceError.revoked }
    return try DevicePeer(deviceID: entry.deviceId, publicKeys: entry.publicKeys)
  }

  private func receive(_ bytes: Data) async throws {
    try await store.serializeIngress { [weak self] in
      guard let self else { throw AppleDeviceError.closed }
      try await self.receiveSerial(bytes)
    }
  }

  private func receiveSerial(_ bytes: Data) async throws {
    guard !closed else { throw AppleDeviceError.closed }
    if parkedWatcher == nil { await watchOpenedApplications() }
    // The stream is a coalesced wake. Every page has already reached the encrypted spool;
    // recover every sender/recipient in Native order before considering a newer sample.
    while true {
      do {
        if let cloudSpool {
          for frame in try await cloudSpool.incoming() { try await process(frame.bytes) }
        }
        try await process(bytes)
        break
      } catch let error as AppleDeviceError where error == DeviceTransportStore.inboxFull {
        // The refused frame was not recorded: it is still with its sender or in the spool.
        // What is ready is delivered first, which is what makes room. When that applied a
        // delivery, the pass goes on from the frames it has not taken in yet. Only when it
        // applied nothing does the inbox stay full and the error end the pass, and the frame
        // is offered again later.
        try await node.refreshMembership()
        guard try await drain() > 0 else { throw error }
      }
    }
    // The arrived frame is delivered before parked frames are offered again, so a parked frame
    // that now fails cannot hold back this frame's delivery. Its failure still ends the route,
    // as on arrival.
    try await node.refreshMembership()
    try await drain()
    let failure = try await redriveAndDeliver(after: bytes)
    try await coalesceHandledPositions()
    if let failure { throw failure }
  }

  /// Coalesces the saved handled positions of the store, and of the shared cloud spool, once
  /// they have grown past their limit. Native says which positions it still holds an
  /// unconsumed receipt for; those stay uncovered.
  private func coalesceHandledPositions() async throws {
    let storeDue = await store.handledCoalescingDue
    let spoolDue = await cloudSpool?.handledCoalescingDue ?? false
    guard storeDue || spoolDue else { return }
    let native = try await group.handledPositionsCoalescing()
    if storeDue {
      try await store.coalesceHandled(
        groupID: native.groupID, floor: native.floor, unconsumed: native.unconsumed)
    }
    if spoolDue {
      try await cloudSpool?.coalesceHandled(
        groupID: native.groupID, floor: native.floor, unconsumed: native.unconsumed)
    }
  }

  private func watchOpenedApplications() async {
    // Subscribed before this transport can park a frame, so no opening is missed.
    let updates = await group.openedApplicationUpdates()
    guard parkedWatcher == nil, !closed else { return }
    parkedWatcher = Task { [weak self] in
      for await _ in updates {
        guard let self else { return }
        await self.redriveAfterOpening()
      }
    }
  }

  /// A wake-up names no position and is not a receipt: parked frames pass the same serial
  /// ingress, signature, ordering and replay checks as on arrival.
  private func redriveAfterOpening() async {
    guard !closed, !parked.isEmpty else { return }
    do {
      try await store.serializeIngress { [weak self] in
        guard let self else { throw AppleDeviceError.closed }
        try await self.redriveSerial()
      }
    } catch {
      // A failed delivery was retained for `recoveryFailure()`. Closing, cancellation and
      // ingress backpressure only end this pass; the next wake-up or frame offers again.
    }
  }

  private func redriveSerial() async throws {
    guard !closed else { throw AppleDeviceError.closed }
    do {
      // A parked frame that fails here was dropped as on arrival. The sender still holds it
      // unacknowledged and replays it on its next route, where a failure ends that route.
      _ = try await redriveAndDeliver(after: nil)
    } catch {
      // No route is being read whose end would report a failed delivery: keep it observable.
      backgroundFailure = error
      throw error
    }
  }

  /// Offers parked frames again and delivers what became ready, even when one of them failed.
  /// Returns that parked frame's failure; a failed delivery pass throws.
  private func redriveAndDeliver(after current: Data?) async throws -> (any Error)? {
    let waiting = parked.count
    var failure: (any Error)?
    do { try await redriveParked(after: current) } catch { failure = error }
    if parked.count < waiting {
      try await node.refreshMembership()
      try await drain()
    }
    return failure
  }

  /// Offers parked frames again once another frame has been handled or the group has opened an
  /// application. Ordinals are contiguous within one sender and epoch, so each chain is tried
  /// in order and stops at its first frame that is still waiting. A frame that now fails is
  /// dropped exactly as on arrival, and the sender replays it on its next route.
  private func redriveParked(after current: Data?) async throws {
    let currentID = current.map { DeviceCiphertext(bytes: $0).identifier }
    let waiting = try parked.filter { $0.key != currentID }.map {
      (id: $0.key, bytes: $0.value, header: try DeviceTransportPacket(decoding: $0.value).header)
    }.sorted {
      if $0.header.groupEpoch != $1.header.groupEpoch {
        return $0.header.groupEpoch < $1.header.groupEpoch
      }
      if $0.header.sender != $1.header.sender {
        return $0.header.sender.rawValue < $1.header.sender.rawValue
      }
      return $0.header.ordinal < $1.header.ordinal
    }
    var stalled: (epoch: UInt64, sender: DeviceID)?
    for item in waiting {
      if let stalled, stalled.epoch == item.header.groupEpoch,
        stalled.sender == item.header.sender
      {
        continue
      }
      parked[item.id] = nil
      parkedBytes -= item.bytes.count
      try await process(item.bytes)
      if parked[item.id] != nil { stalled = (item.header.groupEpoch, item.header.sender) }
    }
  }

  private func process(_ bytes: Data) async throws {
    let packet = try DeviceTransportPacket(decoding: bytes)
    guard packet.header.groupID == (await group.groupID) else {
      throw AppleDeviceError.conflictingReplay
    }
    let anchor = try await group.authorityAnchor()
    if packet.groupEpoch < UInt64(anchor.epoch) {
      // Welcome never grants old epochs. This is local transport retirement only, not an
      // empty lease/log snapshot, sender permission or server deletion. The join anchor is the
      // saved mark that refuses these frames for good, so the store keeps no entry for them.
      try await cloudSpool?.acknowledgeIfRetained(bytes)
      return
    }
    if try await store.isRetained(bytes) {
      if packet.header.sender == peer.deviceID,
        let retained = try await store.retainedAcknowledgement(for: bytes)
      {
        let ack = try await currentAcknowledgement(retained)
        try await publishApplication(DeviceTransportPacket(decoding: ack).application())
        do { try await racer.publish(ack) } catch AppleDeviceError.authorityUnavailable {}
      }
      return
    }
    let authenticated = try await signer(for: packet)
    try packet.verify(signer: authenticated)  // BEFORE opening a one-shot Native ratchet.
    if try await store.isHandled(packet.position) {
      // The store finished with the frame at this feed position and retired its entry. Native
      // opened that ordinal then and would refuse it now; it is refused here without asking.
      try await cloudSpool?.acknowledgeIfRetained(bytes)
      return
    }
    if authenticated.deviceID == identity.deviceID {
      if packet.header.kind == .rawNative, packet.nativeRecipient == nil {
        throw AppleDeviceError.stateRecoveryRequired
      }
      guard try await group.applicationWasProcessed(ciphertext: packet.ciphertext) else {
        throw AppleDeviceError.stateRecoveryRequired
      }
      // Publication/local loopback is not canonical Node consumption. In particular keep an
      // own messageForward plaintext until Node sees the definitive fenced result/rejection.
      try await store.ignored(bytes)
      try await cloudSpool?.acknowledgeIfRetained(bytes)
      return
    }
    let receipt: GroupApplicationReceipt?
    do {
      receipt = try await group.openOrderedApplication(
        DeviceApplicationFeedDelivery(sender: authenticated, application: packet.application()))
    } catch DeviceApplicationFeedError.missingPredecessor {
      // Group has fsynced the gap/ciphertext. Neither a successful route nor this return is an
      // application acknowledgement. Keep the frame so that it is offered again when its
      // predecessor has been opened; a fetch/backstop or the sender's replay also supplies it.
      let identifier = DeviceCiphertext(bytes: bytes).identifier
      if parked[identifier] == nil, parkedBytes + bytes.count <= Self.maximumParkedBytes {
        parked[identifier] = bytes
        parkedBytes += bytes.count
      }
      return
    }
    guard let receipt else {
      try await store.ignored(bytes)
      try await cloudSpool?.acknowledgeIfRetained(bytes)
      return
    }
    let opened = receipt.opened
    guard opened.groupEpoch == packet.groupEpoch, opened.sender == authenticated.mlsCredential,
      opened.authenticatedData == packet.nativeAuthenticatedData
    else { throw AppleDeviceError.conflictingReplay }
    if packet.header.kind == .rawNative {
      // DeviceGroup has checked the complete versioned Node AAD against this packet's
      // sender/recipient/epoch/ordinal. Comparing it with a bare domain string is invalid.
      guard let recipient = packet.nativeRecipient else {
        throw AppleDeviceError.stateRecoveryRequired
      }
      if recipient != .group, recipient != .device(identity.deviceID) {
        try await store.ignored(bytes)
        try await group.acknowledgeOpened(ciphertext: packet.ciphertext)
        try await cloudSpool?.acknowledgeIfRetained(bytes)
        return
      }
      switch try await node.receiveApplication(ciphertext: packet.ciphertext) {
      case .consumed:
        try await store.ignored(bytes)
        try await cloudSpool?.acknowledgeIfRetained(bytes)
      case .pendingRecovery: throw AppleDeviceError.stateRecoveryRequired
      }
      return
    }
    let envelope = try JSONDecoder().decode(DeviceGroupEnvelope.self, from: opened.plaintext)
    guard envelope.version == 1 else {
      throw AppleDeviceError.invalidState("application envelope version")
    }
    switch envelope.body {
    case .application(let delivery):
      guard delivery.sender == packet.header.sender, delivery.recipient == packet.header.recipient,
        delivery.groupEpoch == opened.groupEpoch
      else { throw AppleDeviceError.conflictingReplay }
      let message = try ProtocolCoding.makeDecoder().decode(
        DeviceMessage.self, from: delivery.message)
      guard message.msgId.rawValue == delivery.messageID, message.from == .device(delivery.sender),
        message.to == .device(delivery.recipient)
      else { throw AppleDeviceError.conflictingReplay }
      if delivery.recipient != identity.deviceID {
        try await store.ignored(bytes)
        try await group.acknowledgeOpened(ciphertext: packet.ciphertext)
        try await cloudSpool?.acknowledgeIfRetained(bytes)
        return
      }
    case .acknowledgement(let sender, let recipient, _, _, _, _):
      guard sender == packet.header.sender, recipient == packet.header.recipient else {
        throw AppleDeviceError.conflictingReplay
      }
      if recipient != identity.deviceID {
        try await store.ignored(bytes)
        try await group.acknowledgeOpened(ciphertext: packet.ciphertext)
        try await cloudSpool?.acknowledgeIfRetained(bytes)
        return
      }
      try await node.refreshMembership()
      let current = try await group.groupInfo()
      guard current.isActive, current.epoch == opened.groupEpoch,
        current.members.contains(where: { $0.deviceID == sender.rawValue })
      else {
        // A late old-epoch/revoked receipt must not clear an outcome-unknown outbox.
        try await store.ignored(bytes)
        try await group.acknowledgeOpened(ciphertext: packet.ciphertext)
        try await cloudSpool?.acknowledgeIfRetained(bytes)
        return
      }
    }
    do {
      try await store.received(bytes, envelope: envelope)
    } catch let error as AppleDeviceError where error == DeviceTransportStore.inboxFull {
      // A full inbox recorded nothing, and nothing is retired: the group keeps its receipt
      // and a cloud copy stays in the spool, so the frame is taken in when it is offered
      // again after room was made.
      throw error
    } catch {
      // The replay store refused this authenticated envelope without changing state. Retire the
      // frame so that the sender's replay and a retained cloud copy are not opened again, then
      // report the refusal. A persistence failure makes `ignored` throw as well and retires
      // nothing.
      try await store.ignored(bytes)
      try await group.acknowledgeOpened(ciphertext: packet.ciphertext)
      try await cloudSpool?.acknowledgeIfRetained(bytes)
      throw error
    }
    try await group.acknowledgeOpened(ciphertext: packet.ciphertext)
    if case .acknowledgement = envelope.body { try await cloudSpool?.acknowledgeIfRetained(bytes) }
  }

  /// Delivers this peer's ready deliveries to the host, in stream order, and returns how many
  /// it delivered.
  @discardableResult
  private func drain() async throws -> Int {
    guard !draining else { return 0 }
    var delivered = 0
    draining = true
    defer { draining = false }
    while let delivery = try await store.ready(from: peer.deviceID, to: identity.deviceID).first {
      // A retired acknowledgement is sealed again and published before the stream's next
      // acknowledgement replaces it, so that its retired seal does not stay behind.
      if let retained = await store.retainedAcknowledgement(stream: delivery.streamKey) {
        let current = try await currentAcknowledgement(retained)
        if current != retained.frame {
          try await publishApplication(DeviceTransportPacket(decoding: current).application())
        }
      }
      let info = try await group.groupInfo()
      guard info.isActive else { throw AppleDeviceError.revoked }
      let receipt: DeviceApplyReceipt
      if let expiry = delivery.expiresAt, expiry <= now() {
        receipt = try await application.reject(delivery, reason: .expired)
      } else if delivery.groupEpoch != info.epoch {
        receipt = try await application.reject(delivery, reason: .staleEpoch)
      } else if !info.members.contains(where: { $0.deviceID == delivery.sender.rawValue }) {
        receipt = try await application.reject(delivery, reason: .revoked)
      } else {
        // The actual host rechecks policy, approval/card expiry and conversation lease fencing
        // in the SAME durable mutation transaction. Connectivity never grants those rights.
        receipt = try await application.apply(delivery)
      }
      let envelope = DeviceGroupEnvelope(
        version: 1,
        body: .acknowledgement(
          sender: identity.deviceID, recipient: delivery.sender, stream: delivery.stream,
          sequence: delivery.sequence, messageID: delivery.messageID, digest: delivery.digest))
      let (ordered, packet) = try await sealAcknowledgement(
        JSONEncoder().encode(envelope), stream: delivery.streamKey, sequence: delivery.sequence,
        recipient: delivery.sender)
      let operationID = Self.acknowledgementOperation(
        stream: delivery.streamKey, sequence: delivery.sequence)
      try await store.applied(delivery, receipt: receipt, acknowledgement: packet)
      try await group.acknowledgeSealed(operationID: operationID)
      try await publishApplication(ordered)
      for id in try await store.ciphertextIdentifiers(messageID: delivery.messageID) {
        try await cloudSpool?.acknowledgeIfRetained(identifier: id)
      }
      do { try await racer.publish(packet) } catch AppleDeviceError.authorityUnavailable {}
      delivered += 1
    }
    backgroundFailure = nil
    return delivered
  }

  /// Permanently closes this peer's Bonjour listener and route racer.
  /// The shared durable stores, mailbox, Node, and Native group remain caller-owned and open.
  public func stop() async {
    closed = true
    parkedWatcher?.cancel()
    parkedWatcher = nil
    parked.removeAll()
    parkedBytes = 0
    listener?.close()
    listener = nil
    await racer.stop()
  }

  deinit { parkedWatcher?.cancel() }
}
