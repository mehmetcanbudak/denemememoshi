import CryptoKit
import Foundation
import MemoshiDevice
import MemoshiProtocol

/// Durable ordering/outbox state, independent of CloudKit's delivery order or change tokens.
/// The journal is private, encrypted, exclusive and fsynced; torn-tail recovery is inherited
/// from DeviceStateJournal. An I/O failure poisons the owner instead of acknowledging lost data.
///
/// De-duplication history is retired only below a saved mark under which the message is
/// refused anyway (D131):
/// - A received frame's entry is retired once its sender feed position is in the saved ranges
///   of handled positions. DeviceGroup has opened that ordinal by then and never opens an
///   ordinal at or below its cursor again; this store refuses the position itself first.
/// - A delivery's message identity and frame entries are retired once its stream's saved
///   cursor has moved past it; the cursor refuses every unknown ID at or below it. The delivery
///   at the cursor keeps its entries, so its replay is still answered with the stream's receipt.
/// - Acknowledged sends are retired, lowest message ID first, only when the outbox is full; a
///   send whose ID is unknown and at or below the saved send mark is refused.
///
/// What stays is bounded:
/// - Unacknowledged plus not yet retired sends: `maximumPending`.
/// - Frames of deliveries the host has not applied yet: `maximumPending`, plus at most one
///   frame for each stream (the delivery its cursor waits for is never refused).
/// - Per stream, as long as the stream exists: its cursors, its latest acknowledgement and the
///   frames of the delivery at its cursor.
/// - Handled positions: coalesced when they pass `maximumPending / 16` ranges (never fewer
///   than 8), see `coalesceHandled`.
public actor DeviceTransportStore {
  struct Outgoing: Codable, Sendable {
    let delivery: DeviceDelivery
    var ciphertext: Data?
  }

  /// A retained frame: one whose delivery is buffered or is the one at its stream's cursor.
  private struct Receipt: Codable {
    var stream: String
    var position: DeviceSenderFeedPosition?
    var messageID: String?
  }

  /// `opened` and `ignored` are the committed format, which recorded no feed position; they
  /// are still read. This store writes `openedAt` and `ignoredAt`.
  private enum Entry: Codable {
    case intent(DeviceDelivery)
    case sealed(String, Data)
    case opened(String, DeviceGroupEnvelope)
    case ignored(String)
    case applied(DeviceDelivery, Data, Data)
    case rebound(String, UInt64)
    case openedAt(String, DeviceSenderFeedPosition?, DeviceGroupEnvelope)
    case ignoredAt(String, DeviceSenderFeedPosition?)
    case retiredSends(String)
    case unsealed(String, UInt64)
    case minted(String)
    case acknowledgementUnsealed(String, Data)
    case acknowledgementSealed(String, Data)
    case coalesced(String, UInt64, [DeviceSenderFeedPosition])
  }

  /// Everything the store retains, written as the journal's first record when its history is
  /// rewritten. It contains every mark, so a rewrite can never lose one.
  private struct Snapshot: Codable {
    var outgoing: [String: Outgoing]
    var completed: [String: Outgoing]
    var sendCursors: [String: UInt64]
    var confirmedCursors: [String: UInt64]
    var retiredSendMark: String?
    var greatestSendID: String?
    var received: [String: Receipt]
    var unpositioned: [String: String]
    var handled: DeviceHandledPositions
    var latestAcknowledgements: [String: Data]
    var replay: DeviceReplayState
    /// Absent in a snapshot written before these existed.
    var lastMintedID: String?
    var resealingAcknowledgements: [String: Data]?
    /// Set only by ``DeviceTransportStore/erase()``, in a snapshot that holds nothing else.
    var erased: Bool?
  }

  /// A stream's latest acknowledgement as its transport must treat it.
  struct RetainedAcknowledgement: Sendable {
    let stream: String
    let frame: Data
    /// Set while the acknowledgement is being sealed again: the plaintext its retired seal
    /// held, which the new seal must carry byte for byte.
    let resealing: Data?
  }

  /// What `received` throws when the inbox is full. Nothing was recorded: the frame is
  /// neither retained nor retired, and is taken in when it is offered again after room was
  /// made.
  static let inboxFull = AppleDeviceError.invalidState("transport inbox capacity")

  private var journal: DeviceCompactingJournal
  private let maximumPending: Int
  private var failed = false
  private var closed = false
  /// Erased after this device's verified removal (D133): every later use throws `revoked`.
  private var erased = false
  private var replay = DeviceReplayState()
  private var outgoing: [String: Outgoing] = [:]
  private var completed: [String: Outgoing] = [:]
  private var applicationCiphertexts: [String: Set<String>] = [:]
  private var sendCursors: [String: UInt64] = [:]
  private var confirmedCursors: [String: UInt64] = [:]
  /// The greatest message ID whose acknowledged send was retired: the send mark.
  private var retiredSendMark: String?
  private var greatestSendID: String?
  /// The greatest ID `mintMessageID` returned. Saved, so that an ID is never minted twice.
  private var lastMintedID: String?
  private var received: [String: Receipt] = [:]
  /// How many entries of `received` belong to deliveries the host has not applied yet.
  private var unappliedFrames = 0
  /// Finished frames whose feed position is unknown because the committed journal format did
  /// not record it. Frozen: nothing new is added in operation and it is outside the capacity.
  private var unpositioned: [String: String] = [:]
  private var handled = DeviceHandledPositions()
  /// The range count at which the handled positions are next coalesced.
  private var coalescingThreshold: Int
  private var latestAcknowledgements: [String: Data] = [:]
  /// Streams whose latest acknowledgement is being sealed again, with the plaintext to seal.
  private var resealingAcknowledgements: [String: Data] = [:]
  private var ingressTail: Task<Void, any Error>?
  private var pendingIngress = 0

  private static let journalName = "transport.jsonl"
  private static let journalPurpose = "com.memoshi.device-transport.v1"

  /// Opens/replays the encrypted local transport journal using this enrolled identity's derived key.
  /// `maximumPending` must be positive. It bounds unacknowledged-plus-retained sends, and the
  /// frames of deliveries the host has not applied yet (the type's documentation states both
  /// bounds exactly); recovery/capacity failures throw rather than reset history.
  public init(directory: URL, identity: DeviceIdentity, maximumPending: Int = 16_384) async throws {
    try await self.init(
      directory: directory,
      key: identity.derivedStateEncryptionKey(purpose: Self.journalPurpose),
      maximumPending: maximumPending)
  }

  /// Opens the same exclusive, durable local journal with an explicitly owned encryption key.
  /// A journal written by an earlier version is read as it is and then rewritten as a snapshot.
  /// This performs local persistence/recovery, not CloudKit or account qualification.
  public init(directory: URL, key: SymmetricKey, maximumPending: Int = 16_384) async throws {
    guard maximumPending > 0 else { throw AppleDeviceError.invalidState("transport capacity") }
    self.maximumPending = maximumPending
    coalescingThreshold = max(8, maximumPending / 16)
    journal = try DeviceCompactingJournal(
      url: directory.appendingPathComponent(Self.journalName), key: key,
      purpose: Self.journalPurpose)
    let recovered = journal.takeRecovered()
    if let snapshot = recovered.snapshot {
      restore(try JSONDecoder().decode(Snapshot.self, from: snapshot))
    }
    for bytes in recovered.entries {
      try apply(JSONDecoder().decode(Entry.self, from: bytes))
    }
    // The awaited delivery of a stream is taken in even when the inbox is full, so the frames
    // may exceed the limit by one delivery for each stream that holds one.
    guard outgoing.count + completed.count <= maximumPending,
      unappliedFrames - replay.readyCount <= maximumPending
    else {
      throw AppleDeviceError.invalidState("transport capacity")
    }
    if !recovered.entries.isEmpty { try compact() }
  }

  /// All peer transports for one Native group share this owner. A ciphertext must enter the
  /// durable inbox once before another peer's reader can consume its one-shot MLS ratchet.
  func serializeIngress(_ operation: @escaping @Sendable () async throws -> Void) async throws {
    try requireOpen()
    guard pendingIngress < 256 else {
      throw AppleDeviceError.invalidState("inbound transport backpressure")
    }
    let previous = ingressTail
    let task = Task {
      if let previous { _ = await previous.result }
      try Task.checkCancellation()
      try await operation()
    }
    ingressTail = task
    pendingIngress += 1
    defer { pendingIngress -= 1 }
    try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  func reserve(
    messageID: String, sender: DeviceID, recipient: DeviceID, stream: String,
    groupEpoch: UInt64, expiresAt: Int64?, payload: Data
  ) throws -> Outgoing {
    try requireOpen()
    guard !stream.isEmpty, stream.utf8.count <= 128, payload.count <= 1_048_576 else {
      throw AppleDeviceError.invalidState("outgoing delivery")
    }
    if let existing = outgoing[messageID] ?? completed[messageID] {
      // The epoch is where the message is sealed, not part of its identity: a retry after a
      // membership change is the same send and returns the original reservation.
      let delivery = existing.delivery
      guard delivery.sender == sender, delivery.recipient == recipient,
        delivery.stream == stream, delivery.message == payload, delivery.expiresAt == expiresAt
      else { throw AppleDeviceError.conflictingReplay }
      return existing
    }
    // An unknown ID at or below the send mark may name a send whose history was retired. It
    // is refused, never given a second sequence.
    if let retiredSendMark, !Self.isAbove(messageID, retiredSendMark) {
      throw AppleDeviceError.retiredMessageIdentifier
    }
    if outgoing.count + completed.count >= maximumPending { try retireAcknowledgedSends() }
    guard outgoing.count + completed.count < maximumPending else {
      throw AppleDeviceError.invalidState("transport receipt capacity")
    }
    let key = sender.rawValue + ":" + recipient.rawValue + ":" + stream
    let sequence = (sendCursors[key] ?? 0).addingReportingOverflow(1)
    guard !sequence.overflow else { throw AppleDeviceError.invalidState("transport sequence") }
    let delivery = DeviceDelivery(
      messageID: messageID, sender: sender, recipient: recipient, stream: stream,
      sequence: sequence.partialValue, groupEpoch: groupEpoch, expiresAt: expiresAt,
      message: payload)
    try append(.intent(delivery))
    return Outgoing(delivery: delivery, ciphertext: nil)
  }

  /// Makes room in a full outbox: retires acknowledged sends, lowest message ID first, down to
  /// half the capacity, and saves the greatest retired ID as the send mark. Unacknowledged
  /// sends are never retired.
  private func retireAcknowledgedSends() throws {
    let excess = outgoing.count + completed.count - maximumPending / 2
    let identifiers = completed.keys.sorted { Self.isAbove($1, $0) }
    guard excess > 0, !identifiers.isEmpty else { return }
    try append(.retiredSends(identifiers[min(excess, identifiers.count) - 1]))
  }

  /// A message ID for a new send that the send mark cannot refuse: the ULID for the given Unix
  /// milliseconds, or, when the clock gives one at or below the mark or an ID this store
  /// already knows, the next ULID above the greatest of them. The ID is saved before it is
  /// returned, so the same ID is never minted twice, also not after a restart.
  ///
  /// Reserve it soon. An ID that is still unreserved after half a capacity of later sends was
  /// acknowledged and retired lies at or below the send mark and is refused with
  /// `retiredMessageIdentifier`; the message then needs a newly minted ID.
  func mintMessageID(at milliseconds: Int64) throws -> ULID {
    try requireOpen()
    let fresh = DeviceULID.make(at: milliseconds)
    var value = fresh
    let known = [retiredSendMark, greatestSendID, lastMintedID].compactMap { $0 }
      .filter { (try? ULID($0)) != nil }
    if let floor = known.max(by: { Self.isAbove($1, $0) }), !Self.isAbove(fresh, floor) {
      value = try Self.successor(of: floor)
    }
    let minted = try ULID(value)
    try append(.minted(value))
    return minted
  }

  /// Moves an intent that was never sealed to the epoch it will be sealed in, keeping its message
  /// identity, stream and sequence. Nothing bound to the earlier epoch has left this device;
  /// without this, an intent reserved before a membership change could never be sealed and
  /// would block its stream. A sealed message is returned unchanged.
  func rebind(messageID: String, groupEpoch: UInt64) throws -> Outgoing {
    try requireOpen()
    guard let existing = outgoing[messageID] else {
      throw AppleDeviceError.invalidState("unreserved message")
    }
    guard existing.ciphertext == nil, existing.delivery.groupEpoch != groupEpoch else {
      return existing
    }
    try append(.rebound(messageID, groupEpoch))
    return Outgoing(delivery: existing.delivery.sealed(in: groupEpoch), ciphertext: nil)
  }

  /// Returns a sealed message to an unsealed intent in a later epoch, keeping its identity,
  /// stream and sequence, and forgets its frame. Only for a message whose seal DeviceGroup
  /// retired: the epoch closed before the authority accepted that seal, so the frame was never
  /// published or put on a carrier and no receiver can hold it. The message is then sealed
  /// again, as one whose intent was reserved before the membership change (D131).
  func unseal(messageID: String, groupEpoch: UInt64) throws -> Outgoing {
    try requireOpen()
    guard let existing = outgoing[messageID] else {
      throw AppleDeviceError.invalidState("unreserved message")
    }
    guard existing.ciphertext != nil else { return existing }
    try append(.unsealed(messageID, groupEpoch))
    return Outgoing(delivery: existing.delivery.sealed(in: groupEpoch), ciphertext: nil)
  }

  /// Returns the frame retained for the message. Device signatures are randomized, so a second
  /// seal of the same message (a send racing a route replay) differs only in its signature;
  /// the first journaled frame stays the message's only ciphertext.
  @discardableResult
  func sealed(messageID: String, ciphertext: Data) throws -> Data {
    try requireOpen()
    guard let outgoing = outgoing[messageID] else {
      throw AppleDeviceError.invalidState("unreserved message")
    }
    if let existing = outgoing.ciphertext {
      guard existing == ciphertext || Self.isSameSeal(existing, ciphertext) else {
        throw AppleDeviceError.conflictingReplay
      }
      return existing
    }
    try append(.sealed(messageID, ciphertext))
    return ciphertext
  }

  private static func isSameSeal(_ retained: Data, _ ciphertext: Data) -> Bool {
    guard let retained = try? DeviceTransportPacket(decoding: retained),
      let packet = try? DeviceTransportPacket(decoding: ciphertext)
    else { return false }
    return retained.sealsSameContent(as: packet)
  }

  func pendingOutgoing(to recipient: DeviceID? = nil) throws -> [Outgoing] {
    try requireOpen()
    return outgoing.values.filter { recipient == nil || $0.delivery.recipient == recipient }.sorted
    {
      if $0.delivery.streamKey == $1.delivery.streamKey {
        return $0.delivery.sequence < $1.delivery.sequence
      }
      return $0.delivery.streamKey < $1.delivery.streamKey
    }
  }

  /// The message's current entry, unacknowledged or acknowledged and not yet retired.
  func outgoing(messageID: String) throws -> Outgoing? {
    try requireOpen()
    return outgoing[messageID] ?? completed[messageID]
  }

  func ciphertextIdentifiers(messageID: String) throws -> [String] {
    try requireOpen()
    return Array(applicationCiphertexts[messageID] ?? [])
  }

  /// Whether this store has taken this frame in: it retains the frame's entry, or it has
  /// finished with the frame's feed position.
  func hasReceived(_ ciphertext: Data) throws -> Bool {
    try requireOpen()
    if try isRetained(ciphertext) { return true }
    return Self.position(of: ciphertext).map(handled.contains) ?? false
  }

  /// Whether the entry of exactly this frame is retained.
  func isRetained(_ ciphertext: Data) throws -> Bool {
    try requireOpen()
    let identifier = DeviceCiphertext(bytes: ciphertext).identifier
    return received[identifier] != nil || unpositioned[identifier] != nil
  }

  /// Whether this store has finished with the frame at this feed position and retired its entry.
  /// Such a frame is refused without being offered to Native again.
  func isHandled(_ position: DeviceSenderFeedPosition) throws -> Bool {
    try requireOpen()
    return handled.contains(position)
  }

  /// Takes in a frame the group has opened. The inbox limit counts the retained frames of
  /// deliveries the host has not applied yet. A frame that would exceed it is refused with
  /// `inboxFull` and nothing is recorded. Never refused for room: an acknowledgement, which
  /// retains nothing, and the first frame of the delivery its stream's cursor waits for.
  func received(_ ciphertext: Data, envelope: DeviceGroupEnvelope) throws {
    try requireOpen()
    let identifier = DeviceCiphertext(bytes: ciphertext).identifier
    if received[identifier] != nil || unpositioned[identifier] != nil { return }
    let position = Self.position(of: ciphertext)
    if let position, handled.contains(position) { return }
    if case .application(let delivery) = envelope.body, replay.needsRoom(delivery) {
      guard unappliedFrames < maximumPending else { throw Self.inboxFull }
    }
    try append(.openedAt(identifier, position, envelope))
  }

  func ignored(_ ciphertext: Data) throws {
    try requireOpen()
    let identifier = DeviceCiphertext(bytes: ciphertext).identifier
    if received[identifier] != nil || unpositioned[identifier] != nil { return }
    let position = Self.position(of: ciphertext)
    if let position, handled.contains(position) { return }
    try append(.ignoredAt(identifier, position))
  }

  func acknowledgement(for ciphertext: Data) throws -> Data? {
    try requireOpen()
    let identifier = DeviceCiphertext(bytes: ciphertext).identifier
    guard let stream = received[identifier]?.stream ?? unpositioned[identifier] else { return nil }
    return latestAcknowledgements[stream]
  }

  /// The latest acknowledgement of the stream whose retained delivery frame this is.
  func retainedAcknowledgement(for ciphertext: Data) throws -> RetainedAcknowledgement? {
    try requireOpen()
    let identifier = DeviceCiphertext(bytes: ciphertext).identifier
    guard let stream = received[identifier]?.stream ?? unpositioned[identifier] else { return nil }
    return retainedAcknowledgement(stream: stream)
  }

  func retainedAcknowledgement(stream: String) -> RetainedAcknowledgement? {
    latestAcknowledgements[stream].map {
      RetainedAcknowledgement(
        stream: stream, frame: $0, resealing: resealingAcknowledgements[stream])
    }
  }

  /// The latest acknowledgement of every stream on which `sender` delivers to `recipient`.
  func retainedAcknowledgements(from sender: DeviceID, to recipient: DeviceID) throws
    -> [RetainedAcknowledgement]
  {
    try requireOpen()
    let prefix = sender.rawValue + ":" + recipient.rawValue + ":"
    return latestAcknowledgements.keys.filter { $0.hasPrefix(prefix) }.sorted().compactMap {
      retainedAcknowledgement(stream: $0)
    }
  }

  /// Records that the stream's latest acknowledgement will be sealed again, with the plaintext
  /// its retired seal held. Only for an acknowledgement whose seal DeviceGroup retired: the
  /// epoch closed before the authority accepted that seal, so its frame was never published
  /// or put on a carrier. Saved before the group seals, so a restart resumes with the same
  /// bytes under the same operation ID (D131).
  func unsealAcknowledgement(stream: String, plaintext: Data) throws {
    try requireOpen()
    guard resealingAcknowledgements[stream] == nil else { return }
    try append(.acknowledgementUnsealed(stream, plaintext))
  }

  /// Replaces the stream's retired acknowledgement by the frame of its new seal and returns
  /// the frame retained. Signatures are randomized: a second frame of the same seal changes
  /// nothing.
  func resealedAcknowledgement(stream: String, ciphertext: Data) throws -> Data {
    try requireOpen()
    guard resealingAcknowledgements[stream] != nil else {
      guard let existing = latestAcknowledgements[stream],
        existing == ciphertext || Self.isSameSeal(existing, ciphertext)
      else { throw AppleDeviceError.conflictingReplay }
      return existing
    }
    try append(.acknowledgementSealed(stream, ciphertext))
    return ciphertext
  }

  /// Whether the handled positions have grown enough to be coalesced.
  var handledCoalescingDue: Bool {
    !failed && !erased && handled.rangeCount > coalescingThreshold
  }

  /// Coalesces the handled positions of one group (see `DeviceHandledPositions.coalesce`).
  /// Afterwards the store keeps one range for each sender in each of the at most four epochs
  /// Native can still open, and one more range or exception for each frame Native still
  /// holds unconsumed, of which Native allows 16,384. The next pass is due when that count
  /// has doubled, and not below `maximumPending / 16`. A pass never uncovers a position.
  func coalesceHandled(groupID: String, floor: UInt64, unconsumed: [DeviceSenderFeedPosition])
    throws
  {
    try requireOpen()
    try append(
      .coalesced(
        groupID, floor,
        handled.coalescingExceptions(groupID: groupID, floor: floor, unconsumed: unconsumed)))
    coalescingThreshold = max(max(8, maximumPending / 16), 2 * handled.rangeCount)
  }

  func ready(from sender: DeviceID? = nil, to recipient: DeviceID? = nil) throws -> [DeviceDelivery]
  {
    try requireOpen()
    return replay.ready().filter {
      (sender == nil || $0.sender == sender) && (recipient == nil || $0.recipient == recipient)
    }
  }

  func applied(_ delivery: DeviceDelivery, receipt: DeviceApplyReceipt, acknowledgement: Data)
    throws
  {
    try requireOpen()
    guard receipt.messageID == delivery.messageID, receipt.digest == delivery.digest else {
      throw AppleDeviceError.conflictingReplay
    }
    try append(.applied(delivery, receipt.digest, acknowledgement))
  }

  /// Returns the last durably host-receipted incoming sequence for this exact stream, initially zero.
  /// Closed or persistence-failed owners throw; CloudKit fetch/upload progress never advances it.
  public func cursor(sender: DeviceID, recipient: DeviceID, stream: String) throws -> UInt64 {
    try requireOpen()
    return replay.cursor(sender: sender, recipient: recipient, stream: stream)
  }

  /// What the store still retains, for observation.
  struct RetainedHistory: Equatable, Sendable {
    /// Entries of frames whose delivery is buffered or at its stream's cursor.
    var frames: Int
    /// Frozen entries of the committed journal format.
    var unpositioned: Int
    var identities: Int
    var acknowledgedSends: Int
    /// Closed ranges of handled feed positions.
    var ranges: Int
  }

  var retainedHistory: RetainedHistory {
    RetainedHistory(
      frames: received.count, unpositioned: unpositioned.count,
      identities: replay.retainedIdentityCount, acknowledgedSends: completed.count,
      ranges: handled.rangeCount)
  }

  private func append(_ entry: Entry) throws {
    // `apply` validates before it mutates in every branch, so a refused entry leaves memory and
    // journal unchanged and this shared store usable. Only a journal failure after the mutation
    // permanently poisons the actor and sends no receipt: recovery uses complete journal
    // records, never this uncommitted memory.
    try apply(entry)
    do { try journal.append(entry) } catch {
      failed = true
      throw error
    }
    if journal.needsCompaction { try compact() }
  }

  /// Rewrites the journal as one snapshot of what is retained. The marks are part of the
  /// snapshot; if the rewrite is interrupted, the old journal with its mark entries is intact.
  private func compact() throws {
    let snapshot = try JSONEncoder().encode(
      Snapshot(
        outgoing: outgoing, completed: completed, sendCursors: sendCursors,
        confirmedCursors: confirmedCursors, retiredSendMark: retiredSendMark,
        greatestSendID: greatestSendID, received: received, unpositioned: unpositioned,
        handled: handled, latestAcknowledgements: latestAcknowledgements, replay: replay,
        lastMintedID: lastMintedID, resealingAcknowledgements: resealingAcknowledgements))
    do { _ = try journal.compact(snapshot) } catch {
      failed = true
      throw error
    }
  }

  private func restore(_ snapshot: Snapshot) {
    outgoing = snapshot.outgoing
    completed = snapshot.completed
    sendCursors = snapshot.sendCursors
    confirmedCursors = snapshot.confirmedCursors
    retiredSendMark = snapshot.retiredSendMark
    greatestSendID = snapshot.greatestSendID
    received = snapshot.received
    unpositioned = snapshot.unpositioned
    handled = snapshot.handled
    latestAcknowledgements = snapshot.latestAcknowledgements
    replay = snapshot.replay
    lastMintedID = snapshot.lastMintedID
    resealingAcknowledgements = snapshot.resealingAcknowledgements ?? [:]
    erased = snapshot.erased ?? false
    for (identifier, receipt) in received {
      if let messageID = receipt.messageID {
        applicationCiphertexts[messageID, default: []].insert(identifier)
      }
      if receipt.messageID != replay.appliedMessageID(streamKey: receipt.stream) {
        unappliedFrames += 1
      }
    }
  }

  private func apply(_ entry: Entry) throws {
    switch entry {
    case .intent(let delivery):
      guard outgoing[delivery.messageID] == nil,
        delivery.sequence == (sendCursors[delivery.streamKey] ?? 0) + 1
      else {
        throw AppleDeviceError.conflictingReplay
      }
      outgoing[delivery.messageID] = Outgoing(delivery: delivery, ciphertext: nil)
      sendCursors[delivery.streamKey] = delivery.sequence
      if greatestSendID.map({ Self.isAbove(delivery.messageID, $0) }) ?? true {
        greatestSendID = delivery.messageID
      }
    case .sealed(let messageID, let ciphertext):
      guard outgoing[messageID] != nil else {
        throw AppleDeviceError.invalidState("missing outgoing intent")
      }
      outgoing[messageID]?.ciphertext = ciphertext
    case .rebound(let messageID, let groupEpoch):
      guard let existing = outgoing[messageID], existing.ciphertext == nil,
        groupEpoch > existing.delivery.groupEpoch
      else { throw AppleDeviceError.conflictingReplay }
      outgoing[messageID] = Outgoing(
        delivery: existing.delivery.sealed(in: groupEpoch), ciphertext: nil)
    case .unsealed(let messageID, let groupEpoch):
      guard let existing = outgoing[messageID], existing.ciphertext != nil,
        groupEpoch > existing.delivery.groupEpoch
      else { throw AppleDeviceError.conflictingReplay }
      outgoing[messageID] = Outgoing(
        delivery: existing.delivery.sealed(in: groupEpoch), ciphertext: nil)
    case .retiredSends(let mark):
      for identifier in completed.keys where !Self.isAbove(identifier, mark) {
        completed[identifier] = nil
      }
      if retiredSendMark.map({ Self.isAbove(mark, $0) }) ?? true { retiredSendMark = mark }
    case .opened(let identifier, let envelope):
      // Only a journal written by the committed code has this entry. That code kept every
      // message identity for ever, so it could journal another frame of a delivery after the
      // stream's cursor had passed it. The identity is retired now and the cursor alone
      // refuses the delivery: such a frame is a finished one.
      if envelope.version == 1, case .application(let delivery) = envelope.body,
        replay.hasPassed(delivery)
      {
        finish(identifier, position: nil, stream: delivery.streamKey)
      } else {
        try opened(identifier, position: nil, envelope: envelope)
      }
    case .openedAt(let identifier, let position, let envelope):
      try opened(identifier, position: position, envelope: envelope)
    case .ignored(let identifier): finish(identifier, position: nil, stream: "")
    case .ignoredAt(let identifier, let position):
      finish(identifier, position: position, stream: "")
    case .applied(let delivery, let digest, let acknowledgement):
      let stream = delivery.streamKey
      let previous = replay.appliedMessageID(streamKey: stream)
      try replay.acknowledge(
        delivery, receipt: DeviceApplyReceipt(messageID: delivery.messageID, digest: digest))
      latestAcknowledgements[stream] = acknowledgement
      // A new acknowledgement ends the sealing again of the one it replaces.
      resealingAcknowledgements[stream] = nil
      // The applied delivery's frames stay, to answer its replay, but no longer need room.
      unappliedFrames -= applicationCiphertexts[delivery.messageID]?.count ?? 0
      // The cursor has moved past the previous delivery and now refuses it by itself.
      if let previous {
        for identifier in applicationCiphertexts.removeValue(forKey: previous) ?? [] {
          guard let receipt = received.removeValue(forKey: identifier) else { continue }
          finish(identifier, position: receipt.position, stream: receipt.stream)
        }
      }
    case .minted(let identifier):
      if lastMintedID.map({ Self.isAbove(identifier, $0) }) ?? true { lastMintedID = identifier }
    case .acknowledgementUnsealed(let stream, let plaintext):
      guard latestAcknowledgements[stream] != nil else {
        throw AppleDeviceError.conflictingReplay
      }
      resealingAcknowledgements[stream] = plaintext
    case .acknowledgementSealed(let stream, let ciphertext):
      guard resealingAcknowledgements[stream] != nil else {
        throw AppleDeviceError.conflictingReplay
      }
      latestAcknowledgements[stream] = ciphertext
      resealingAcknowledgements[stream] = nil
    case .coalesced(let groupID, let floor, let unconsumed):
      handled.coalesce(groupID: groupID, floor: floor, unconsumed: unconsumed)
    }
  }

  private func opened(
    _ identifier: String, position: DeviceSenderFeedPosition?, envelope: DeviceGroupEnvelope
  ) throws {
    guard envelope.version == 1 else {
      throw AppleDeviceError.invalidState("transport envelope version")
    }
    switch envelope.body {
    case .application(let delivery):
      try replay.receive(delivery)
      if replay.appliedMessageID(streamKey: delivery.streamKey) == delivery.messageID {
        // Another frame of the delivery at the stream's cursor. Nothing is left to buffer,
        // so the frame is finished and its replay is refused by its position.
        finish(identifier, position: position, stream: delivery.streamKey)
        return
      }
      received[identifier] = Receipt(
        stream: delivery.streamKey, position: position, messageID: delivery.messageID)
      applicationCiphertexts[delivery.messageID, default: []].insert(identifier)
      unappliedFrames += 1
    case .acknowledgement(
      let sender, let recipient, let stream, let sequence, let messageID, let digest):
      let key = recipient.rawValue + ":" + sender.rawValue + ":" + stream
      if sequence > (confirmedCursors[key] ?? 0) {
        guard let outgoing = outgoing[messageID], outgoing.delivery.streamKey == key,
          outgoing.delivery.sequence == sequence, outgoing.delivery.digest == digest
        else {
          throw AppleDeviceError.conflictingReplay
        }
        let acknowledged = self.outgoing.filter {
          $0.value.delivery.streamKey == key && $0.value.delivery.sequence <= sequence
        }
        for (id, value) in acknowledged {
          completed[id] = value
          self.outgoing[id] = nil
        }
        confirmedCursors[key] = sequence
      }
      finish(identifier, position: position, stream: "")
    }
  }

  /// Records that this store has finished with a frame. Its position joins the handled ranges
  /// and its identifier is not kept; only a frame of the committed format, which has no
  /// recorded position, keeps its identifier.
  private func finish(_ identifier: String, position: DeviceSenderFeedPosition?, stream: String) {
    if let position {
      handled.insert(position)
    } else {
      unpositioned[identifier] = stream
    }
  }

  private static func position(of ciphertext: Data) -> DeviceSenderFeedPosition? {
    (try? DeviceTransportPacket(decoding: ciphertext))?.position
  }

  /// Message IDs are ULIDs: their text orders them by the time they were minted.
  private static func isAbove(_ identifier: String, _ mark: String) -> Bool {
    mark.utf8.lexicographicallyPrecedes(identifier.utf8)
  }

  /// The next ULID in text order.
  private static func successor(of identifier: String) throws -> String {
    let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)
    var characters = Array(identifier.utf8)
    var index = characters.count - 1
    while index >= 0 {
      guard let digit = alphabet.firstIndex(of: characters[index]) else { break }
      if digit + 1 < alphabet.count {
        characters[index] = alphabet[digit + 1]
        let next = String(decoding: characters, as: UTF8.self)
        guard (try? ULID(next)) != nil else { break }
        return next
      }
      characters[index] = alphabet[0]
      index -= 1
    }
    throw AppleDeviceError.invalidState("message identifier space")
  }

  /// `revoked` once erased, `persistenceFailed` once failed or closed.
  private func requireOpen() throws {
    guard !erased else { throw AppleDeviceError.revoked }
    guard !failed else { throw AppleDeviceError.persistenceFailed }
  }

  /// D133: after this device's verified removal from its group, deletes everything the store
  /// holds for it: the messages it sent or is still to send (their plaintext with them), the
  /// deliveries it received, buffered or applied, the acknowledgements, every stream cursor
  /// and send mark, and the handled feed positions. The journal is replaced by one snapshot
  /// that says only that it was erased (written beside it and synchronized behind a write
  /// barrier, renamed over it, directory synchronized), so no byte of an earlier record is in
  /// the file when this returns. Every later use throws `revoked`, also after a reopen.
  /// Repeating it rewrites the same snapshot. Not after ``close()``.
  public func erase() throws {
    guard !closed else { throw AppleDeviceError.closed }
    do {
      guard try journal.compact(Self.erasedSnapshot()) else {
        throw AppleDeviceError.persistenceFailed
      }
    } catch {
      failed = true
      throw error
    }
    ingressTail?.cancel()
    applicationCiphertexts.removeAll()
    unappliedFrames = 0
    restore(Self.erasedState())
  }

  /// D133, for a store that is not open: the erasure of ``erase()``, written without reading
  /// the journal first, so that a store that can no longer be opened is erased as well.
  /// Nothing happens when the store was never created. Call with no store open on `directory`.
  public static func eraseRemovedState(directory: URL, identity: DeviceIdentity) throws {
    let url = directory.appendingPathComponent(journalName)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    var journal = try DeviceCompactingJournal.discardingHistory(
      url: url, key: identity.derivedStateEncryptionKey(purpose: journalPurpose),
      purpose: journalPurpose)
    defer { journal.close() }
    guard try journal.compact(erasedSnapshot()) else { throw AppleDeviceError.persistenceFailed }
  }

  /// What ``erase()`` leaves: a snapshot that says only that the store was erased.
  private static func erasedState() -> Snapshot {
    Snapshot(
      outgoing: [:], completed: [:], sendCursors: [:], confirmedCursors: [:],
      retiredSendMark: nil, greatestSendID: nil, received: [:], unpositioned: [:],
      handled: DeviceHandledPositions(), latestAcknowledgements: [:],
      replay: DeviceReplayState(), erased: true)
  }

  private static func erasedSnapshot() throws -> Data { try JSONEncoder().encode(erasedState()) }

  /// Closes the local journal, cancels the queued ingress tail, and fails future access closed.
  /// Does not erase outbox, replay, or acknowledgement history needed for restart recovery.
  public func close() {
    failed = true
    closed = true
    ingressTail?.cancel()
    journal.close()
  }
}

extension DeviceDelivery {
  /// The same delivery, stating the epoch it is sealed in.
  fileprivate func sealed(in groupEpoch: UInt64) -> DeviceDelivery {
    DeviceDelivery(
      messageID: messageID, sender: sender, recipient: recipient, stream: stream,
      sequence: sequence, groupEpoch: groupEpoch, expiresAt: expiresAt, message: message)
  }
}
