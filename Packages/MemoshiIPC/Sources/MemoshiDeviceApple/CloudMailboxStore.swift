import CryptoKit
import Foundation
import MemoshiDevice
import MemoshiProtocol

/// Device-owned encrypted spool. A fetched record is durable before a CloudKit token can advance.
/// Tokens are transport cursors only; application cursors move independently after host receipts.
///
/// An applied record's entry is not kept for ever (D131). Its sender feed position joins the
/// saved ranges of handled positions, and a fetched record at a handled position is dropped
/// before it is stored: the device layer applied that position already, so Native, which
/// opens each sender's ordinals in order, would refuse it again anyway. A position this spool
/// has not applied is outside every range, however late or out of order CloudKit delivers it.
public actor CloudMailboxStore {
  private enum Entry: Codable {
    case account(String)
    case outgoing(DeviceCiphertext)
    case uploaded([String])
    case incoming([DeviceCiphertext])
    case applied(String)
    case syncState(Data)
    case explicitFetchToken(Data?)
    case coalesced(String, UInt64, [DeviceSenderFeedPosition])
  }

  /// Everything the spool retains, written as the journal's first record when its history is
  /// rewritten. `outbox` lists the frame retained for each feed position before any other.
  private struct Snapshot: Codable {
    var account: String?
    var outbox: [DeviceCiphertext]
    var inbox: [DeviceCiphertext]
    var handled: DeviceHandledPositions
    var syncState: Data?
    var fetchToken: Data?
    /// Set only by ``CloudMailboxStore/erase()``, in a snapshot that holds nothing else.
    var erased: Bool?
  }

  private var journal: DeviceCompactingJournal
  private let maximumRecords: Int
  private var failed = false
  private var closed = false
  /// Erased after this device's verified removal (D133): every later use throws `revoked`.
  private var erased = false
  private var account: String?
  private var outbox: [String: DeviceCiphertext] = [:]
  /// The first outbox frame retained for each sender feed position, and its inverse.
  private var outboxSeals: [String: String] = [:]
  private var sealedIdentifiers: [String: String] = [:]
  private var inbox: [String: DeviceCiphertext] = [:]
  /// Feed positions whose records the device layer has applied: the saved retirement mark.
  private var handled = DeviceHandledPositions()
  /// The range count at which the handled positions are next coalesced.
  private var coalescingThreshold: Int
  private var syncState: Data?
  private var fetchToken: Data?

  func boundAccount() throws -> String? {
    try requireUsable()
    return account
  }

  private static let journalName = "cloudkit.jsonl"
  private static let journalPurpose = "com.memoshi.cloudkit-spool.v1"

  /// No Keychain/network calls: the host passes its already-enrolled device-only identity.
  public init(directory: URL, identity: DeviceIdentity, maximumRecords: Int = 16_384) throws {
    try self.init(
      directory: directory,
      key: identity.derivedStateEncryptionKey(purpose: Self.journalPurpose),
      maximumRecords: maximumRecords)
  }

  /// Explicit key injection supports local persistence/recovery tests, never a fake cloud service.
  public init(directory: URL, key: SymmetricKey, maximumRecords: Int = 16_384) throws {
    guard maximumRecords > 0 else { throw AppleDeviceError.invalidState("cloud spool capacity") }
    self.maximumRecords = maximumRecords
    coalescingThreshold = max(8, maximumRecords / 16)
    journal = try DeviceCompactingJournal(
      url: directory.appendingPathComponent(Self.journalName), key: key,
      purpose: Self.journalPurpose)
    let recovered = journal.takeRecovered()
    if let bytes = recovered.snapshot {
      let snapshot = try JSONDecoder().decode(Snapshot.self, from: bytes)
      account = snapshot.account
      for frame in snapshot.outbox {
        Self.retain(frame, in: &outbox, seals: &outboxSeals, identifiers: &sealedIdentifiers)
      }
      for frame in snapshot.inbox { inbox[frame.identifier] = frame }
      handled = snapshot.handled
      syncState = snapshot.syncState
      fetchToken = snapshot.fetchToken
      erased = snapshot.erased ?? false
    }
    for bytes in recovered.entries {
      switch try JSONDecoder().decode(Entry.self, from: bytes) {
      case .account(let value):
        if let account, account != value { throw AppleDeviceError.accountChanged }
        account = value
      case .outgoing(let frame):
        Self.retain(frame, in: &outbox, seals: &outboxSeals, identifiers: &sealedIdentifiers)
      case .uploaded(let identifiers):
        for identifier in identifiers {
          Self.release(
            identifier, from: &outbox, seals: &outboxSeals, identifiers: &sealedIdentifiers)
        }
      case .incoming(let frames):
        for frame in frames where !(Self.position(of: frame).map(handled.contains) ?? false) {
          inbox[frame.identifier] = frame
        }
      case .applied(let identifier): Self.finish(identifier, inbox: &inbox, handled: &handled)
      case .syncState(let value): syncState = value
      case .explicitFetchToken(let value): fetchToken = value
      case .coalesced(let groupID, let floor, let unconsumed):
        handled.coalesce(groupID: groupID, floor: floor, unconsumed: unconsumed)
      }
    }
    guard outbox.count <= maximumRecords, inbox.count <= maximumRecords else {
      throw AppleDeviceError.invalidState("cloud spool capacity")
    }
    if !recovered.entries.isEmpty {
      _ = try journal.compact(
        Self.snapshot(
          account: account, outbox: outbox, sealedIdentifiers: sealedIdentifiers, inbox: inbox,
          handled: handled, syncState: syncState, fetchToken: fetchToken))
    }
  }

  private static func snapshot(
    account: String?, outbox: [String: DeviceCiphertext], sealedIdentifiers: [String: String],
    inbox: [String: DeviceCiphertext], handled: DeviceHandledPositions, syncState: Data?,
    fetchToken: Data?
  ) throws -> Data {
    let frames = outbox.values.sorted { $0.identifier < $1.identifier }
    return try JSONEncoder().encode(
      Snapshot(
        account: account,
        outbox: frames.filter { sealedIdentifiers[$0.identifier] != nil }
          + frames.filter { sealedIdentifiers[$0.identifier] == nil },
        inbox: inbox.values.sorted { $0.identifier < $1.identifier }, handled: handled,
        syncState: syncState, fetchToken: fetchToken))
  }

  /// The applied record leaves the inbox and its feed position joins the handled ranges.
  private static func finish(
    _ identifier: String, inbox: inout [String: DeviceCiphertext],
    handled: inout DeviceHandledPositions
  ) {
    guard let frame = inbox.removeValue(forKey: identifier), let position = position(of: frame)
    else { return }
    handled.insert(position)
  }

  private static func position(of frame: DeviceCiphertext) -> DeviceSenderFeedPosition? {
    (try? DeviceTransportPacket(decoding: frame.bytes))?.position
  }

  /// An account change quarantines this spool; it never republishes old ciphertext into a new
  /// person's database or silently resets group identity/tokens. Explicit re-enrollment is required.
  func bind(account value: String) throws {
    try requireUsable()
    guard account == nil || account == value else { throw AppleDeviceError.accountChanged }
    if account == nil {
      try append(.account(value))
      account = value
      try compactIfNeeded()
    }
  }

  func enqueue(_ frame: DeviceCiphertext) throws {
    try requireUsable()
    guard frame.bytes.count > 0, frame.bytes.count <= 1_048_576 else {
      throw AppleDeviceError.invalidState("MLS ciphertext size")
    }
    if outbox[frame.identifier] == nil {
      guard outbox.count < maximumRecords else {
        throw AppleDeviceError.invalidState("cloud outbox full")
      }
      try append(.outgoing(frame))
      Self.retain(frame, in: &outbox, seals: &outboxSeals, identifiers: &sealedIdentifiers)
      try compactIfNeeded()
    }
  }

  /// Device signatures are randomized, so signing one seal again yields a byte-different frame
  /// for the same immutable feed record. Returns the frame this outbox already retains for the
  /// sender feed position, or durably enqueues the frame that `sign` produces.
  func outgoing(
    groupID: String, epoch: UInt64, sender: DeviceID, ordinal: UInt64,
    orEnqueue sign: @Sendable () throws -> DeviceCiphertext
  ) throws -> DeviceCiphertext {
    try requireUsable()
    let seal = Self.seal(groupID: groupID, epoch: epoch, sender: sender, ordinal: ordinal)
    if let identifier = outboxSeals[seal], let frame = outbox[identifier] { return frame }
    let frame = try sign()
    try enqueue(frame)
    return frame
  }

  func uploaded(_ identifiers: [String]) throws {
    try append(.uploaded(identifiers))
    for identifier in identifiers {
      Self.release(identifier, from: &outbox, seals: &outboxSeals, identifiers: &sealedIdentifiers)
    }
    try compactIfNeeded()
  }

  /// Removes frames that will never be uploaded: their epoch closed before the authority
  /// accepted them, and DeviceGroup has retired their seals (D131). Saved like an upload
  /// receipt, so a restart does not bring the frames back.
  func discard(_ identifiers: [String]) throws { try uploaded(identifiers) }

  private static func seal(groupID: String, epoch: UInt64, sender: DeviceID, ordinal: UInt64)
    -> String
  {
    "\(groupID)\u{0}\(epoch)\u{0}\(sender.rawValue)\u{0}\(ordinal)"
  }

  private static func retain(
    _ frame: DeviceCiphertext, in outbox: inout [String: DeviceCiphertext],
    seals: inout [String: String], identifiers: inout [String: String]
  ) {
    outbox[frame.identifier] = frame
    guard let packet = try? DeviceTransportPacket(decoding: frame.bytes) else { return }
    let position = seal(
      groupID: packet.header.groupID, epoch: packet.groupEpoch, sender: packet.header.sender,
      ordinal: packet.header.ordinal)
    if seals[position] == nil {
      seals[position] = frame.identifier
      identifiers[frame.identifier] = position
    }
  }

  private static func release(
    _ identifier: String, from outbox: inout [String: DeviceCiphertext],
    seals: inout [String: String], identifiers: inout [String: String]
  ) {
    outbox[identifier] = nil
    if let seal = identifiers.removeValue(forKey: identifier) { seals[seal] = nil }
  }

  func fetched(_ frames: [DeviceCiphertext]) throws -> [DeviceCiphertext] {
    try requireUsable()
    var identifiers: Set<String> = []
    var fresh: [DeviceCiphertext] = []
    for frame in frames
    where inbox[frame.identifier] == nil && identifiers.insert(frame.identifier).inserted {
      guard !frame.bytes.isEmpty, frame.bytes.count <= 1_048_576 else {
        throw AppleDeviceError.invalidState("cloud ciphertext size")
      }
      guard let position = Self.position(of: frame) else {
        throw AppleDeviceError.invalidState("cloud ciphertext")
      }
      // The record at this position was applied and its entry retired: refused, not stored.
      if !handled.contains(position) { fresh.append(frame) }
    }
    guard !fresh.isEmpty else { return [] }
    guard fresh.count <= maximumRecords - inbox.count else {
      throw AppleDeviceError.invalidState("cloud inbox capacity")
    }
    try append(.incoming(fresh))
    for frame in fresh { inbox[frame.identifier] = frame }
    try compactIfNeeded()
    return fresh
  }

  /// Called only after the device layer's durable idempotent application (or explicit rejection).
  /// An identifier that is not in the inbox needs nothing: its record was acknowledged before
  /// and its entry retired, so a repeated acknowledgement is not an error.
  public func acknowledgeApplied(ciphertextIdentifier: String) throws {
    try requireUsable()
    guard inbox[ciphertextIdentifier] != nil else { return }
    try append(.applied(ciphertextIdentifier))
    Self.finish(ciphertextIdentifier, inbox: &inbox, handled: &handled)
    try compactIfNeeded()
  }

  func acknowledgeIfRetained(_ ciphertext: Data) throws {
    try acknowledgeIfRetained(identifier: DeviceCiphertext(bytes: ciphertext).identifier)
  }

  func acknowledgeIfRetained(identifier: String) throws {
    try requireUsable()
    if inbox[identifier] != nil { try acknowledgeApplied(ciphertextIdentifier: identifier) }
  }

  func persistEngineState(_ value: Data) throws {
    try append(.syncState(value))
    syncState = value
    try compactIfNeeded()
  }

  func persistFetchToken(_ value: Data?) throws {
    try append(.explicitFetchToken(value))
    fetchToken = value
    try compactIfNeeded()
  }

  func engineState() throws -> Data? {
    try requireUsable()
    return syncState
  }

  func explicitFetchToken() throws -> Data? {
    try requireUsable()
    return fetchToken
  }

  func outgoing() throws -> [DeviceCiphertext] {
    try requireUsable()
    return outbox.values.sorted { $0.identifier < $1.identifier }
  }

  /// Only the authority writer removes an enqueued identifier, durably: with its upload
  /// receipt, or when it discards a frame that the authority will never accept.
  func containsOutgoing(identifier: String) throws -> Bool {
    try requireUsable()
    return outbox[identifier] != nil
  }

  func incoming() throws -> [DeviceCiphertext] {
    try requireUsable()
    return try inbox.values.map { frame in
      (frame: frame, header: try DeviceTransportPacket(decoding: frame.bytes).header)
    }.sorted {
      if $0.header.groupEpoch != $1.header.groupEpoch {
        return $0.header.groupEpoch < $1.header.groupEpoch
      }
      if $0.header.sender != $1.header.sender {
        return $0.header.sender.rawValue < $1.header.sender.rawValue
      }
      if $0.header.ordinal != $1.header.ordinal { return $0.header.ordinal < $1.header.ordinal }
      return $0.frame.identifier < $1.frame.identifier
    }.map(\.frame)
  }

  /// D133: after this device's verified removal from its group, deletes everything the spool
  /// holds for it: inbox and outbox frames, the handled feed positions (de-duplication marks:
  /// group ID, epochs, sender device IDs, ordinals), the CloudKit engine state, the fetch token
  /// and the account binding. The journal is replaced by one snapshot that says only that it
  /// was erased (written beside it and synchronized behind a write barrier, renamed over it,
  /// directory synchronized), so no byte of an earlier record is in the file when this
  /// returns. Every later use throws `revoked`, also after a reopen, so nothing is fetched
  /// into it or uploaded from it again. Repeating it rewrites the same snapshot. Not after
  /// ``close()``.
  public func erase() throws {
    guard !closed else { throw AppleDeviceError.closed }
    let snapshot = try Self.erasedSnapshot()
    do {
      guard try journal.compact(snapshot) else { throw AppleDeviceError.persistenceFailed }
    } catch {
      failed = true
      throw error
    }
    erased = true
    account = nil
    outbox.removeAll()
    outboxSeals.removeAll()
    sealedIdentifiers.removeAll()
    inbox.removeAll()
    handled = DeviceHandledPositions()
    syncState = nil
    fetchToken = nil
  }

  /// What ``erase()`` leaves: a snapshot that says only that the spool was erased.
  private static func erasedSnapshot() throws -> Data {
    try JSONEncoder().encode(
      Snapshot(
        account: nil, outbox: [], inbox: [], handled: DeviceHandledPositions(), syncState: nil,
        fetchToken: nil, erased: true))
  }

  /// D133, for a spool that is not open: the erasure of ``erase()``, written without reading
  /// the journal first, so that a spool that can no longer be opened (unreadable, or over its
  /// capacity) is erased as well. Nothing happens when the spool was never created. Call with
  /// no spool open on `directory`.
  static func eraseRemovedState(directory: URL, identity: DeviceIdentity) throws {
    let url = directory.appendingPathComponent(journalName)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    var journal = try DeviceCompactingJournal.discardingHistory(
      url: url, key: identity.derivedStateEncryptionKey(purpose: journalPurpose),
      purpose: journalPurpose)
    defer { journal.close() }
    guard try journal.compact(erasedSnapshot()) else { throw AppleDeviceError.persistenceFailed }
  }

  /// Closes this local journal and makes further spool access fail closed.
  /// Retained ciphertext, account binding, and fetch tokens remain on disk for reopening.
  public func close() {
    failed = true
    closed = true
    journal.close()
  }

  /// `revoked` once erased, `persistenceFailed` once failed or closed.
  private func requireUsable() throws {
    guard !erased else { throw AppleDeviceError.revoked }
    guard !failed else { throw AppleDeviceError.persistenceFailed }
  }

  private func append(_ entry: Entry) throws {
    try requireUsable()
    do { try journal.append(entry) } catch {
      failed = true
      throw error
    }
  }

  /// Rewrites the journal as one snapshot of what is retained, once enough history has
  /// accumulated. Called after the caller's own change is in memory, so the snapshot has it.
  /// The handled positions are part of the snapshot; an interrupted rewrite leaves the old
  /// journal, whose entries retire the same positions again when it is read.
  private func compactIfNeeded() throws {
    guard journal.needsCompaction else { return }
    do {
      _ = try journal.compact(
        Self.snapshot(
          account: account, outbox: outbox, sealedIdentifiers: sealedIdentifiers, inbox: inbox,
          handled: handled, syncState: syncState, fetchToken: fetchToken))
    } catch {
      failed = true
      throw error
    }
  }

  /// Whether the handled positions have grown enough to be coalesced.
  var handledCoalescingDue: Bool {
    !failed && !erased && handled.rangeCount > coalescingThreshold
  }

  /// Coalesces the handled positions of one group (see `DeviceHandledPositions.coalesce`).
  /// Afterwards the spool keeps one range for each sender in each of the at most four epochs
  /// Native can still open, and one more range or exception for each frame Native still
  /// holds unconsumed. The next pass is due when that count has doubled, and not below
  /// `maximumRecords / 16`. Records in the inbox stay there; a pass never uncovers a position.
  func coalesceHandled(groupID: String, floor: UInt64, unconsumed: [DeviceSenderFeedPosition])
    throws
  {
    let exceptions = handled.coalescingExceptions(
      groupID: groupID, floor: floor, unconsumed: unconsumed)
    try append(.coalesced(groupID, floor, exceptions))
    handled.coalesce(groupID: groupID, floor: floor, unconsumed: exceptions)
    coalescingThreshold = max(max(8, maximumRecords / 16), 2 * handled.rangeCount)
    try compactIfNeeded()
  }

  /// What the spool still retains, for observation: inbox records and handled-position ranges.
  var retainedHistory: (inbox: Int, ranges: Int) { (inbox.count, handled.rangeCount) }
}
