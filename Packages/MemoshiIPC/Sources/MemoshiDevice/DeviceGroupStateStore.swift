import CryptoKit
import Darwin
import Foundation
import MemoshiMLS
import MemoshiProtocol

/// The whole state a device saves for its group. A snapshot row of `group.jsonl` is this value
/// in the form every earlier version wrote (its coded field names must not change); from
/// version 4 on, without the consumed history, which `group-history.jsonl` holds.
struct GroupSavedState: Codable, Equatable, Sendable {
  struct SentApplication: Codable, Equatable, Sendable {
    var inputDigest: Data
    var ciphertextID: String
    var packet: DeviceSealedApplication
    var operationID: String?
    var receiptPending: Bool
    var feedPending = true
  }

  struct RecordKey: Codable, Equatable, Sendable {
    var groupID: String
    var epoch: UInt64
    var groupContext: Data
    var secret: Data
    var members: [DevicePeer]

    var value: GroupStateRecordKey {
      GroupStateRecordKey(
        groupID: groupID, epoch: epoch, groupContext: groupContext, secret: secret, members: members
      )
    }
  }

  /// The final `device.hello` an accepted add owes its joiner, sealable once the host has
  /// completed that add, in the add's epoch or a later one.
  struct PendingHello: Codable, Equatable, Sendable {
    var message: DeviceMessage
  }

  /// An own seal the authority did not accept before its group state closed. It is no longer
  /// published; its plaintext receipt stays under `ciphertextID` until the same operation is
  /// sealed again in a later epoch.
  struct RetiredSeal: Codable, Equatable, Sendable {
    var ciphertextID: String
    var operationID: String?
    var kind: DeviceSealedApplication.Kind
    var recipient: DeviceAddress?
    var epoch: UInt64
  }

  /// One consumed ciphertext and the route it was opened under, if it had one.
  struct Consumption: Codable, Equatable, Sendable {
    var id: String
    var route: DeviceApplicationRouting?
  }

  var version = 3
  var groupID: String
  var epoch: Int64
  var members: [DeviceListEntry]
  var active: Bool
  var joiningClient = false
  var pendingJoin = false
  var confirmationAttempted = false
  var anchor: GroupAuthorityAnchor
  var keyPackage: Data?
  var pendingAdd: DeviceGroup.PreparedAdd?
  var pendingRequest: GroupCommit?
  var pendingCompletion: GroupCommit?
  var pendingHello: PendingHello?
  var secretState: Data
  var sent: [UInt64: SentApplication] = [:]
  var operations: [String: UInt64] = [:]
  var opened: [String: MLSOpenedMessage] = [:]
  var openedRoutes: [String: DeviceApplicationRouting] = [:]
  var sourceSeals: [String: UInt64] = [:]
  var deferredConsumption: Set<String> = []
  var recordKeys: [UInt64: RecordKey] = [:]
  var revoked: Set<DeviceID> = []
  var nextApplicationOrdinal: UInt64 = 1
  var previousApplicationOrdinal: UInt64 = 0
  var acceptedApplicationOrdinal: UInt64 = 0
  var received: [UInt64: [DeviceID: UInt64]] = [:]
  var receivedDigests: [UInt64: [DeviceID: Data]] = [:]
  var waiting: [String: DeviceApplicationFeedDelivery] = [:]
  var completedEpochs: [UInt64: DeviceApplicationEpochBoundary] = [:]
  // The consumed history changes only through `consume(_:)`, which also logs the batch: the
  // history file replays the batches instead of comparing up to `maximumConsumed` entries.
  private(set) var consumed: [String] = []
  private(set) var consumedHead = 0
  private(set) var spentRoutes: [String: DeviceApplicationRouting] = [:]
  var retired: [RetiredSeal]?
  /// Version 4: the consumed history is saved in its own file, through this mark. Version 3
  /// (every file before D133) has no mark and carries the history in this value itself.
  var historyMark: UInt64?
  /// The random identity of the history row at `historyMark`: a history file is read only if
  /// its row at that mark has it, so files of two timelines are never combined.
  var historyID: String?
  /// Batches consumed since the last save, in order. Not saved with the state.
  private(set) var unsavedConsumption: [[Consumption]] = []
  /// Whether this value descends from the last saved one by field changes and `consume(_:)`
  /// alone. A value built anew does not, and is saved as a snapshot.
  private(set) var continuesSaved = false

  static let maximumConsumed = 16_384

  private enum CodingKeys: String, CodingKey {
    case version, groupID, epoch, members, active, joiningClient, pendingJoin
    case confirmationAttempted, anchor, keyPackage, pendingAdd, pendingRequest, pendingCompletion
    case pendingHello, secretState, sent, operations, opened, openedRoutes, sourceSeals
    case deferredConsumption, recordKeys, revoked, nextApplicationOrdinal
    case previousApplicationOrdinal, acceptedApplicationOrdinal, received, receivedDigests
    case waiting, completedEpochs, consumed, consumedHead, spentRoutes, retired, historyMark
    case historyID
  }

  init(
    groupID: String, epoch: Int64, members: [DeviceListEntry], active: Bool,
    joiningClient: Bool = false, anchor: GroupAuthorityAnchor, secretState: Data
  ) {
    self.groupID = groupID
    self.epoch = epoch
    self.members = members
    self.active = active
    self.joiningClient = joiningClient
    self.anchor = anchor
    self.secretState = secretState
  }

  /// Adds `batch` to the consumed history, then evicts the oldest entries above the cap (each
  /// with its route) and drops the evicted prefix of the array once it is at least half of it.
  /// Returns the evicted IDs. Recovery replays the same batches through this function, so the
  /// history on disk loses an entry exactly when the history in memory does.
  mutating func consume(_ batch: [Consumption]) -> [String] {
    let before = (consumed.count, consumedHead)
    for entry in batch {
      if let route = entry.route { spentRoutes[entry.id] = route }
      consumed.append(entry.id)
    }
    var evicted: [String] = []
    while consumed.count - consumedHead > Self.maximumConsumed {
      let id = consumed[consumedHead]
      consumedHead += 1
      spentRoutes.removeValue(forKey: id)
      evicted.append(id)
    }
    if consumedHead >= 1_024, consumedHead * 2 >= consumed.count {
      consumed.removeFirst(consumedHead)
      consumedHead = 0
    }
    if !batch.isEmpty || before != (consumed.count, consumedHead) {
      unsavedConsumption.append(batch)
    }
    return evicted
  }

  /// Called when this exact value is durable: nothing is unsaved and later values continue it.
  mutating func markSaved() {
    if !unsavedConsumption.isEmpty { unsavedConsumption = [] }
    continuesSaved = true
  }

  /// This value without its consumed history: what the store keeps, compares and writes to
  /// the state file.
  fileprivate var withoutHistory: GroupSavedState {
    var copy = self
    copy.consumed = []
    copy.consumedHead = 0
    copy.spentRoutes = [:]
    copy.markSaved()
    return copy
  }

  fileprivate var history: GroupHistory {
    GroupHistory(consumed: consumed, consumedHead: consumedHead, spentRoutes: spentRoutes)
  }

  /// After a verified removal: the consumed history is dropped with everything else the
  /// device got through the group. A version-4 state without a mark has no history file.
  mutating func eraseHistory() {
    version = 4
    consumed = []
    consumedHead = 0
    spentRoutes = [:]
    unsavedConsumption = []
    historyMark = nil
    historyID = nil
  }

  /// Recovery only: the history read from the history file, not a consumption.
  fileprivate mutating func restore(_ history: GroupHistory) {
    consumed = history.consumed
    consumedHead = history.consumedHead
    spentRoutes = history.spentRoutes
  }
}

/// The whole consumed history as of one mark of `group-history.jsonl`.
struct GroupHistory: Codable, Equatable {
  var mark: UInt64 = 0
  var consumed: [String]
  var consumedHead: Int
  var spentRoutes: [String: DeviceApplicationRouting]
}

/// The difference between two consecutive saved states: one change row of `group.jsonl`. Only
/// fields that differ are present. Applying it to the earlier state gives the later one.
struct GroupStateChange: Codable {
  struct Scalars: Codable, Equatable {
    var version: Int
    var groupID: String
    var epoch: Int64
    var active: Bool
    var joiningClient: Bool
    var pendingJoin: Bool
    var confirmationAttempted: Bool
    var nextApplicationOrdinal: UInt64
    var previousApplicationOrdinal: UInt64
    var acceptedApplicationOrdinal: UInt64
    var historyMark: UInt64?
    var historyID: String?

    init(_ state: GroupSavedState) {
      version = state.version
      groupID = state.groupID
      epoch = state.epoch
      active = state.active
      joiningClient = state.joiningClient
      pendingJoin = state.pendingJoin
      confirmationAttempted = state.confirmationAttempted
      nextApplicationOrdinal = state.nextApplicationOrdinal
      previousApplicationOrdinal = state.previousApplicationOrdinal
      acceptedApplicationOrdinal = state.acceptedApplicationOrdinal
      historyMark = state.historyMark
      historyID = state.historyID
    }
  }

  /// The new value of a field that may be absent.
  struct Slot<Value: Codable & Equatable>: Codable {
    var value: Value?

    init?(from old: Value?, to new: Value?) {
      guard old != new else { return nil }
      value = new
    }
  }

  /// Entries set and keys removed in a dictionary.
  struct Entries<Key: Codable & Hashable, Value: Codable & Equatable>: Codable {
    var set: [Key: Value] = [:]
    var removed: [Key] = []

    init?(from old: [Key: Value], to new: [Key: Value]) {
      guard old != new else { return nil }
      for (key, value) in new where old[key] != value { set[key] = value }
      for key in old.keys where new[key] == nil { removed.append(key) }
    }

    func apply(to dictionary: inout [Key: Value]) {
      for key in removed { dictionary.removeValue(forKey: key) }
      for (key, value) in set { dictionary[key] = value }
    }
  }

  /// The same one level down: a dictionary of dictionaries, changed entry by entry.
  struct NestedEntries<Outer: Codable & Hashable, Key: Codable & Hashable, Value>: Codable
  where Value: Codable & Equatable {
    /// For each outer key that is new or differs: the whole inner dictionary of a new key, the
    /// inner changes of an existing one.
    var created: [Outer: [Key: Value]] = [:]
    var changed: [Outer: Entries<Key, Value>] = [:]
    var removed: [Outer] = []

    init?(from old: [Outer: [Key: Value]], to new: [Outer: [Key: Value]]) {
      guard old != new else { return nil }
      for (key, inner) in new {
        guard let before = old[key] else {
          created[key] = inner
          continue
        }
        if let change = Entries(from: before, to: inner) { changed[key] = change }
      }
      for key in old.keys where new[key] == nil { removed.append(key) }
    }

    func apply(to dictionary: inout [Outer: [Key: Value]]) {
      for key in removed { dictionary.removeValue(forKey: key) }
      for (key, inner) in created { dictionary[key] = inner }
      for (key, change) in changed { change.apply(to: &dictionary[key, default: [:]]) }
    }
  }

  /// Members inserted into and removed from a set.
  struct Members<Element: Codable & Hashable>: Codable {
    var inserted: [Element] = []
    var removed: [Element] = []

    init?(from old: Set<Element>, to new: Set<Element>) {
      guard old != new else { return nil }
      inserted = Array(new.subtracting(old))
      removed = Array(old.subtracting(new))
    }

    func apply(to set: inout Set<Element>) {
      set.subtract(removed)
      set.formUnion(inserted)
    }
  }

  /// The bytes of a value that differ from its earlier form, which keeps `prefix` bytes at its
  /// start and `suffix` bytes at its end. The native MLS state is one opaque text of which a
  /// message changes about a hundred bytes in one place.
  struct Patch: Codable {
    var prefix: Int
    var suffix: Int
    var middle: Data

    init?(from old: Data, to new: Data) {
      guard old != new else { return nil }
      let (start, end) = old.withUnsafeBytes { before in
        new.withUnsafeBytes { after in
          let start = Self.common(before, after, limit: min(before.count, after.count))
          let end = Self.common(
            before, after, limit: min(before.count, after.count) - start, fromEnd: true)
          return (start, end)
        }
      }
      prefix = start
      suffix = end
      middle = new.subdata(in: (new.startIndex + start)..<(new.endIndex - end))
    }

    /// The number of equal bytes at the start (or the end) of both buffers, at most `limit`.
    private static func common(
      _ left: UnsafeRawBufferPointer, _ right: UnsafeRawBufferPointer, limit: Int,
      fromEnd: Bool = false
    ) -> Int {
      guard limit > 0, let a = left.baseAddress, let b = right.baseAddress else { return 0 }
      let step = 4_096
      var count = 0
      // Whole blocks first, then the block that differs byte by byte.
      while limit - count >= step {
        let x = fromEnd ? a + (left.count - count - step) : a + count
        let y = fromEnd ? b + (right.count - count - step) : b + count
        guard memcmp(x, y, step) == 0 else { break }
        count += step
      }
      while count < limit {
        let x = fromEnd ? left[left.count - count - 1] : left[count]
        let y = fromEnd ? right[right.count - count - 1] : right[count]
        guard x == y else { break }
        count += 1
      }
      return count
    }

    func apply(to old: Data) throws -> Data {
      guard prefix >= 0, suffix >= 0, prefix + suffix <= old.count else {
        throw DeviceLayerError.invalid("durable MLS group state")
      }
      var result = Data(capacity: prefix + middle.count + suffix)
      result.append(old.prefix(prefix))
      result.append(middle)
      result.append(old.suffix(suffix))
      return result
    }
  }

  typealias Saved = GroupSavedState

  var scalars: Scalars?
  var members: [DeviceListEntry]?
  var anchor: GroupAuthorityAnchor?
  var keyPackage: Slot<Data>?
  var pendingAdd: Slot<DeviceGroup.PreparedAdd>?
  var pendingRequest: Slot<GroupCommit>?
  var pendingCompletion: Slot<GroupCommit>?
  var pendingHello: Slot<Saved.PendingHello>?
  var retired: Slot<[Saved.RetiredSeal]>?
  var secretState: Patch?
  var sent: Entries<UInt64, Saved.SentApplication>?
  var operations: Entries<String, UInt64>?
  var opened: Entries<String, MLSOpenedMessage>?
  var openedRoutes: Entries<String, DeviceApplicationRouting>?
  var sourceSeals: Entries<String, UInt64>?
  var deferredConsumption: Members<String>?
  var recordKeys: Entries<UInt64, Saved.RecordKey>?
  var revoked: Members<DeviceID>?
  var received: NestedEntries<UInt64, DeviceID, UInt64>?
  var receivedDigests: NestedEntries<UInt64, DeviceID, Data>?
  var waiting: Entries<String, DeviceApplicationFeedDelivery>?
  var completedEpochs: Entries<UInt64, DeviceApplicationEpochBoundary>?

  /// The change from `old` to `new`, neither with its consumed history (the history file
  /// carries that). Nil when nothing differs.
  init?(from old: Saved, to new: Saved) {
    let before = Scalars(old)
    let after = Scalars(new)
    scalars = before == after ? nil : after
    members = old.members == new.members ? nil : new.members
    anchor = old.anchor == new.anchor ? nil : new.anchor
    keyPackage = Slot(from: old.keyPackage, to: new.keyPackage)
    pendingAdd = Slot(from: old.pendingAdd, to: new.pendingAdd)
    pendingRequest = Slot(from: old.pendingRequest, to: new.pendingRequest)
    pendingCompletion = Slot(from: old.pendingCompletion, to: new.pendingCompletion)
    pendingHello = Slot(from: old.pendingHello, to: new.pendingHello)
    retired = Slot(from: old.retired, to: new.retired)
    secretState = Patch(from: old.secretState, to: new.secretState)
    sent = Entries(from: old.sent, to: new.sent)
    operations = Entries(from: old.operations, to: new.operations)
    opened = Entries(from: old.opened, to: new.opened)
    openedRoutes = Entries(from: old.openedRoutes, to: new.openedRoutes)
    sourceSeals = Entries(from: old.sourceSeals, to: new.sourceSeals)
    deferredConsumption = Members(from: old.deferredConsumption, to: new.deferredConsumption)
    recordKeys = Entries(from: old.recordKeys, to: new.recordKeys)
    revoked = Members(from: old.revoked, to: new.revoked)
    received = NestedEntries(from: old.received, to: new.received)
    receivedDigests = NestedEntries(from: old.receivedDigests, to: new.receivedDigests)
    waiting = Entries(from: old.waiting, to: new.waiting)
    completedEpochs = Entries(from: old.completedEpochs, to: new.completedEpochs)
    let unchanged = [
      scalars == nil, members == nil, anchor == nil, keyPackage == nil, pendingAdd == nil,
      pendingRequest == nil, pendingCompletion == nil, pendingHello == nil, retired == nil,
      secretState == nil, sent == nil, operations == nil, opened == nil, openedRoutes == nil,
      sourceSeals == nil, deferredConsumption == nil, recordKeys == nil, revoked == nil,
      received == nil, receivedDigests == nil, waiting == nil, completedEpochs == nil,
    ].allSatisfy { $0 }
    if unchanged { return nil }
  }

  /// Applies every field change.
  func apply(to state: inout Saved) throws {
    if let scalars {
      state.version = scalars.version
      state.groupID = scalars.groupID
      state.epoch = scalars.epoch
      state.active = scalars.active
      state.joiningClient = scalars.joiningClient
      state.pendingJoin = scalars.pendingJoin
      state.confirmationAttempted = scalars.confirmationAttempted
      state.nextApplicationOrdinal = scalars.nextApplicationOrdinal
      state.previousApplicationOrdinal = scalars.previousApplicationOrdinal
      state.acceptedApplicationOrdinal = scalars.acceptedApplicationOrdinal
      state.historyMark = scalars.historyMark
      state.historyID = scalars.historyID
    }
    if let members { state.members = members }
    if let anchor { state.anchor = anchor }
    if let keyPackage { state.keyPackage = keyPackage.value }
    if let pendingAdd { state.pendingAdd = pendingAdd.value }
    if let pendingRequest { state.pendingRequest = pendingRequest.value }
    if let pendingCompletion { state.pendingCompletion = pendingCompletion.value }
    if let pendingHello { state.pendingHello = pendingHello.value }
    if let retired { state.retired = retired.value }
    if let secretState { state.secretState = try secretState.apply(to: state.secretState) }
    sent?.apply(to: &state.sent)
    operations?.apply(to: &state.operations)
    opened?.apply(to: &state.opened)
    openedRoutes?.apply(to: &state.openedRoutes)
    sourceSeals?.apply(to: &state.sourceSeals)
    deferredConsumption?.apply(to: &state.deferredConsumption)
    recordKeys?.apply(to: &state.recordKeys)
    revoked?.apply(to: &state.revoked)
    received?.apply(to: &state.received)
    receivedDigests?.apply(to: &state.receivedDigests)
    waiting?.apply(to: &state.waiting)
    completedEpochs?.apply(to: &state.completedEpochs)
  }

  /// Whether going from `old` to `new` replaces or removes key material of a group state, or
  /// starts, ends or changes a membership transition: such a change is written as a snapshot,
  /// never as a row, so that what it replaced leaves the disk when its save returns. The
  /// fields are the version, the epoch, the membership and its pending transitions, the key
  /// package and the exporter record keys. Every save of a group this device is not an active
  /// member of (removed, or still joining) counts as well: what a removed device drops must
  /// not outlive the call. The native state is opaque: a change replacing more than half of
  /// it counts too (a commit replaces about 93% of it, a message about 120 bytes).
  static func replacesGroupSecrets(from old: Saved, to new: Saved) -> Bool {
    if !old.active || !new.active || old.version != new.version || old.epoch != new.epoch
      || old.joiningClient != new.joiningClient || old.pendingJoin != new.pendingJoin
      || old.confirmationAttempted != new.confirmationAttempted
      || old.keyPackage != new.keyPackage || old.pendingAdd != new.pendingAdd
      || old.pendingRequest != new.pendingRequest
      || old.pendingCompletion != new.pendingCompletion || old.members != new.members
      || old.anchor != new.anchor || old.recordKeys != new.recordKeys
    {
      return true
    }
    guard let patch = Patch(from: old.secretState, to: new.secretState) else { return false }
    return (old.secretState.count - patch.prefix - patch.suffix) * 2 > old.secretState.count
  }
}

/// Owns a group's saved state: two encrypted journals in the group's directory.
///
/// `group.jsonl` holds the state without its consumed history: one snapshot row, then change
/// rows. A change row ends only after all of its bytes were synchronized behind a write
/// barrier, so a crash leaves at most an unended last row, which reopening discards. A save
/// that replaces or removes key material of a group state
/// (``GroupStateChange/replacesGroupSecrets(from:to:)``) writes a snapshot, which replaces the
/// file; so does the save after `maximumChanges` rows. Anything a row carried and a later save
/// deleted (a message's ratchet secret, a consumed plaintext) therefore leaves the disk at most
/// that many rows later, or when that save returns.
///
/// `group-history.jsonl` holds the consumed history, which is not secret and is far larger:
/// rows numbered by mark, each with a random identity, the first a whole history, each later
/// one either the batches one save consumed or a whole history that replaces it. The state
/// names the mark and identity of the last row it includes and is written after that row, so
/// rows above the mark are a save that never returned and are dropped, and a row of another
/// timeline at the same mark is refused. Its compaction rewrites only this file, once the
/// rows after its whole history (counted across restarts) are as large as it.
///
/// A file of the code before D133 (version 3) is one snapshot with the history inside; its
/// first save writes the history file and then a version-4 snapshot. Until that snapshot is
/// in place the version-3 file is the state and the history file is not read. A removed
/// device's state (version 4 without a mark) has no history: the file is deleted after the
/// state that no longer names it, and at open if it is still there.
struct GroupStateStore {
  private static let filename = "group.jsonl"
  private static let historyFilename = "group-history.jsonl"
  /// Rows after which the state file is rewritten as a snapshot.
  static let maximumChanges = 64
  /// The state file is also rewritten once its rows reach its snapshot's size, and the history
  /// file once its rows reach its first row's size; never before they hold this much.
  private static let minimumChangeBytes: UInt64 = 64 * 1024

  private let journal: DeviceStateJournal
  private let historyJournal: DeviceStateJournal
  /// The last saved state, without its consumed history.
  private var saved: GroupSavedState?
  private var snapshotBytes: UInt64 = 0
  private var changeBytes: UInt64 = 0
  private var changes = 0
  /// Change rows were found at open: the next save rewrites the file.
  private var compactsNext = false
  /// The highest history mark on disk, also of a row the state does not name.
  private var historyMarkOnDisk: UInt64 = 0
  /// The history file's first row and the rows after it, as written (also before this open).
  private var historyHeadBytes: UInt64 = 0
  private var historyRowBytes: UInt64 = 0
  private(set) var snapshotsWritten = 0

  /// Bytes written and synchronized to both files since they were opened.
  var bytesWritten: UInt64 { journal.bytesWritten + historyJournal.bytesWritten }

  /// Opens the files if a state was ever saved; the first save creates them otherwise.
  init(directory: URL, key: SymmetricKey) throws {
    let url = directory.appendingPathComponent(Self.filename)
    let historyURL = directory.appendingPathComponent(Self.historyFilename)
    journal = try DeviceStateJournal(
      url: url, key: key, purpose: "memoshi.group-state.v1", createsFile: false)
    historyJournal = try DeviceStateJournal(
      url: historyURL, key: key, purpose: "memoshi.group-history.v1", createsFile: false)
    // Both locks are held. A file that was written and never renamed is not saved state;
    // the file it was to replace is still complete.
    _ = unlink(url.path + ".next")
    _ = unlink(historyURL.path + ".next")
    let rows = journal.recoveredRowBytes
    snapshotBytes = UInt64(rows.first ?? 0)
    changeBytes = UInt64(rows.dropFirst().reduce(0, +))
  }

  private static var corrupt: DeviceLayerError { .invalid("durable MLS group state") }
  private static var mismatch: DeviceLayerError {
    .invalid("group history does not match its state")
  }

  /// The saved state: the snapshot with every change row applied in order, and its history.
  /// Nil when nothing was ever saved. Later calls return nil.
  mutating func recover() throws -> GroupSavedState? {
    let rows = journal.takeRecovered()
    let historyRows = historyJournal.takeRecovered()
    let historyRowSizes = historyJournal.recoveredRowBytes
    guard let snapshot = rows.first else { return nil }
    var state = try JSONDecoder().decode(GroupSavedState.self, from: snapshot)
    for row in rows.dropFirst() {
      try JSONDecoder().decode(GroupStateChange.self, from: row).apply(to: &state)
    }
    switch (state.version, state.historyMark) {
    case (3, nil):
      // Pre-D133: the history is inside the state; any history file is an unfinished
      // conversion and is replaced by the next one.
      break
    case (4, nil):
      // A removed device's tombstone: no history. A file left by a kill is deleted now.
      guard state.historyID == nil, state.consumed.isEmpty else { throw Self.corrupt }
      if !historyRows.isEmpty || historyJournal.exists { try deleteHistory() }
    case (4, let mark?):
      guard let id = state.historyID else { throw Self.corrupt }
      var reached: UInt64?
      var stray = false
      var bytes: (head: Int, rows: Int) = (0, 0)
      for (bytesOfRow, data) in zip(historyRowSizes, historyRows) {
        let row = try JSONDecoder().decode(GroupHistoryRow.self, from: data)
        if row.mark > mark {
          stray = true
          historyMarkOnDisk = max(historyMarkOnDisk, row.mark)
          continue
        }
        // Marks run without a gap up to the state's; the first row is a whole history.
        guard !stray, reached.map({ row.mark == $0 + 1 }) ?? (row.history != nil) else {
          throw Self.corrupt
        }
        if let history = row.history {
          guard history.mark == row.mark else { throw Self.corrupt }
          state.restore(history)
          bytes = (bytesOfRow, 0)
        } else {
          bytes.rows += bytesOfRow
        }
        for batch in row.batches ?? [] { _ = state.consume(batch) }
        reached = row.mark
        if row.mark == mark, row.id != id { throw Self.mismatch }
      }
      guard reached == mark else { throw reached == nil ? Self.corrupt : Self.mismatch }
      historyMarkOnDisk = max(historyMarkOnDisk, mark)
      historyHeadBytes = UInt64(bytes.head)
      historyRowBytes = UInt64(bytes.rows)
      state.markSaved()
      // Rows of a save that never returned go now, before any later mark is written.
      if stray { try writeHistory(state.history, mark: mark, id: id) }
    default:
      throw Self.corrupt
    }
    state.markSaved()
    saved = state.withoutHistory
    changes = rows.count - 1
    compactsNext = changes > 0
    return state
  }

  /// Makes `state` durable before returning: its consumed batches as one history row, then
  /// the change from the last saved state as one row, or a snapshot (see the type).
  mutating func save(_ state: inout GroupSavedState) throws {
    if state.version == 4, state.historyMark == nil {
      // A removed device: the tombstone first, then the history it no longer names.
      let current = state.withoutHistory
      try writeSnapshot(current)
      saved = current
      state.markSaved()
      if historyJournal.exists { try deleteHistory() }
      return
    }
    guard let saved, state.continuesSaved, state.version == 4, let mark = state.historyMark
    else {
      try writeAll(&state)
      return
    }
    if !state.unsavedConsumption.isEmpty {
      let row = GroupHistoryRow(
        mark: mark + 1, id: UUID().uuidString, batches: state.unsavedConsumption)
      try appendHistory(row)
      state.historyMark = row.mark
      state.historyID = row.id
    }
    let current = state.withoutHistory
    if !compactsNext, changes < Self.maximumChanges,
      changeBytes < max(snapshotBytes, Self.minimumChangeBytes),
      !GroupStateChange.replacesGroupSecrets(from: saved, to: current)
    {
      if let change = GroupStateChange(from: saved, to: current) {
        // The row is written only if it rebuilds this state from the last saved one.
        var rebuilt = saved
        if (try? change.apply(to: &rebuilt)) != nil, rebuilt == current {
          let before = journal.bytesWritten
          try journal.append(change, endsAfterSynchronizing: true)
          changeBytes += journal.bytesWritten - before
          changes += 1
          self.saved = current
          state.markSaved()
          try compactHistoryIfDue(state)
          return
        }
      } else {
        state.markSaved()
        return
      }
    }
    try writeSnapshot(current)
    self.saved = current
    state.markSaved()
    try compactHistoryIfDue(state)
  }

  /// A state that does not continue the saved one (a new group, a fresh join, a version-3
  /// state): its whole history under a new mark, then its snapshot naming that mark. A
  /// version-4 file gets the history as an appended row, so that until the snapshot is in
  /// place the earlier state still finds its own history; any other file is replaced.
  private mutating func writeAll(_ state: inout GroupSavedState) throws {
    let mark = historyMarkOnDisk + 1
    let id = UUID().uuidString
    var history = state.history
    history.mark = mark
    if saved?.version == 4, saved?.historyMark != nil {
      try appendHistory(GroupHistoryRow(mark: mark, id: id, history: history))
    } else {
      try writeHistory(history, mark: mark, id: id)
    }
    state.version = 4
    state.historyMark = mark
    state.historyID = id
    let current = state.withoutHistory
    try writeSnapshot(current)
    saved = current
    state.markSaved()
    try compactHistoryIfDue(state)
  }

  private mutating func appendHistory(_ row: GroupHistoryRow) throws {
    let before = historyJournal.bytesWritten
    try historyJournal.append(row, endsAfterSynchronizing: true)
    historyRowBytes += historyJournal.bytesWritten - before
    historyMarkOnDisk = max(historyMarkOnDisk, row.mark)
  }

  private mutating func writeHistory(_ history: GroupHistory, mark: UInt64, id: String) throws {
    var history = history
    history.mark = mark
    let before = historyJournal.bytesWritten
    try historyJournal.replace(GroupHistoryRow(mark: mark, id: id, history: history))
    historyHeadBytes = historyJournal.bytesWritten - before
    historyRowBytes = 0
    historyMarkOnDisk = mark
  }

  /// Deletes the history file durably (a removed device's state no longer names it).
  private mutating func deleteHistory() throws {
    try historyJournal.remove()
    historyHeadBytes = 0
    historyRowBytes = 0
  }

  /// After the state file names the current mark: the history file becomes one whole row,
  /// under that mark's identity.
  private mutating func compactHistoryIfDue(_ state: GroupSavedState) throws {
    guard historyRowBytes >= max(historyHeadBytes, Self.minimumChangeBytes),
      let mark = state.historyMark, let id = state.historyID
    else { return }
    try writeHistory(state.history, mark: mark, id: id)
  }

  private mutating func writeSnapshot(_ state: GroupSavedState) throws {
    let before = journal.bytesWritten
    try journal.replace(state)
    snapshotBytes = journal.bytesWritten - before
    changeBytes = 0
    changes = 0
    compactsNext = false
    snapshotsWritten += 1
  }

  /// Replaces the state file by one snapshot of `state`, which must be the last saved state.
  mutating func compact(_ state: GroupSavedState) throws {
    guard changes > 0, state.continuesSaved, state.unsavedConsumption.isEmpty,
      state.withoutHistory == saved
    else { return }
    try writeSnapshot(state.withoutHistory)
  }

  func close() {
    journal.close()
    historyJournal.close()
  }
}

/// One row of `group-history.jsonl`: a whole history, or the batches one save consumed. `id`
/// is random and never repeats; a compaction keeps the identity of the row it replaces.
struct GroupHistoryRow: Codable {
  var mark: UInt64
  var id: String
  var history: GroupHistory?
  var batches: [[GroupSavedState.Consumption]]?

  init(mark: UInt64, id: String, history: GroupHistory) {
    self.mark = mark
    self.id = id
    self.history = history
  }

  init(mark: UInt64, id: String, batches: [[GroupSavedState.Consumption]]) {
    self.mark = mark
    self.id = id
    self.batches = batches
  }
}
