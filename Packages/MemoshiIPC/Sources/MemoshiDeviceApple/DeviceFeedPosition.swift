import MemoshiDevice
import MemoshiMLS
import MemoshiProtocol

/// Used only for authenticated immutable CloudKit record addressing. DeviceGroup, not this
/// module, owns the durable sender-ratchet cursors, predecessor gaps and epoch-drain barrier.
struct DeviceSenderFeedPosition: Codable, Hashable, Sendable {
  let groupID: String
  let groupEpoch: UInt64
  let sender: DeviceID
  let ordinal: UInt64
  let previousOrdinal: UInt64
}

/// Sender-feed positions a store has finished with, kept as closed ordinal ranges per group,
/// sender and epoch. A sender's ordinals are contiguous within an epoch, so finished positions
/// coalesce into few ranges. An ordinal the store has not finished with stays outside every
/// range, however low it is: a frame that arrives late or out of order is never refused unseen.
///
/// What is kept is bounded by `coalesce`, which only ever covers more positions. It covers a
/// position the store never saw only when Native can produce nothing more for it, so that the
/// frame, offered to Native again, would be refused there as well.
struct DeviceHandledPositions: Codable, Equatable, Sendable {
  private var ranges: [String: [ClosedRange<UInt64>]] = [:]
  /// Per group, the epoch below which every position is covered, except those in `open`.
  private var floors: [String: UInt64] = [:]
  /// Ordinals below their group's floor that are not covered: Native still held an unconsumed
  /// receipt for each when the floor was set. Keyed like `ranges`.
  private var open: [String: Set<UInt64>] = [:]

  init() {}

  /// A snapshot written before the floor existed has ranges only.
  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    ranges = try values.decode([String: [ClosedRange<UInt64>]].self, forKey: .ranges)
    floors = try values.decodeIfPresent([String: UInt64].self, forKey: .floors) ?? [:]
    open = try values.decodeIfPresent([String: Set<UInt64>].self, forKey: .open) ?? [:]
  }

  /// The number of ranges and uncovered exceptions kept, over all senders and epochs.
  var rangeCount: Int {
    ranges.values.reduce(0) { $0 + $1.count } + open.values.reduce(0) { $0 + $1.count }
  }

  func contains(_ position: DeviceSenderFeedPosition) -> Bool {
    let key = Self.key(position)
    if position.groupEpoch < floors[position.groupID] ?? 0 {
      return !(open[key]?.contains(position.ordinal) ?? false)
    }
    guard let list = ranges[key] else { return false }
    let index = Self.firstIndex(in: list, reaching: position.ordinal)
    return index < list.count && list[index].lowerBound <= position.ordinal
  }

  mutating func insert(_ position: DeviceSenderFeedPosition) {
    let key = Self.key(position)
    if position.groupEpoch < floors[position.groupID] ?? 0 {
      open[key]?.remove(position.ordinal)
      if open[key]?.isEmpty == true { open[key] = nil }
      return
    }
    let ordinal = position.ordinal
    var list = ranges[key] ?? []
    let index = Self.firstIndex(in: list, reaching: ordinal)
    if index < list.count, list[index].lowerBound <= ordinal { return }
    let joinsLower = index > 0 && list[index - 1].upperBound == ordinal - 1
    let joinsUpper =
      index < list.count && ordinal < UInt64.max && list[index].lowerBound == ordinal + 1
    switch (joinsLower, joinsUpper) {
    case (true, true):
      list[index - 1] = list[index - 1].lowerBound...list[index].upperBound
      list.remove(at: index)
    case (true, false): list[index - 1] = list[index - 1].lowerBound...ordinal
    case (false, true): list[index] = ordinal...list[index].upperBound
    case (false, false): list.insert(ordinal...ordinal, at: index)
    }
    ranges[key] = list
  }

  /// The positions of `unconsumed` that `coalesce` must leave uncovered: those that are not
  /// covered now and that it would cover otherwise, and the exceptions already kept. Saving
  /// these instead of the whole list gives the same result.
  func coalescingExceptions(
    groupID: String, floor: UInt64, unconsumed: [DeviceSenderFeedPosition]
  ) -> [DeviceSenderFeedPosition] {
    let floor = max(floor, floors[groupID] ?? 0)
    return unconsumed.filter { position in
      guard position.groupID == groupID, !contains(position) else { return false }
      if position.groupEpoch < floor { return true }
      guard let list = ranges[Self.key(position)], let lower = list.first?.lowerBound,
        let upper = list.last?.upperBound
      else { return false }
      return position.ordinal > lower && position.ordinal < upper
    }
  }

  /// Shrinks what is kept for one group without uncovering any covered position.
  ///
  /// `floor` is the oldest epoch whose frames Native can still open, and `unconsumed` lists
  /// the positions for which Native holds an unconsumed receipt. Below the floor the saved
  /// epoch replaces every list. From the floor on, each list becomes the one span from its
  /// lowest to its highest covered ordinal.
  ///
  /// A position this covers although the store never finished with it is either in an epoch
  /// Native can no longer open, or below an ordinal of the same sender and epoch that Native
  /// has opened, and Native opens a sender's ordinals in order. Native holds no receipt for
  /// it, so its frame, offered again, would be refused by Native too. The positions in
  /// `unconsumed` stay uncovered until the store finishes with them.
  mutating func coalesce(groupID: String, floor: UInt64, unconsumed: [DeviceSenderFeedPosition]) {
    let floor = max(floor, floors[groupID] ?? 0)
    var held: [String: Set<UInt64>] = [:]
    var early: [String: Set<UInt64>] = [:]
    for position in unconsumed where position.groupID == groupID && !contains(position) {
      if position.groupEpoch < floor {
        early[Self.key(position), default: []].insert(position.ordinal)
      } else {
        held[Self.key(position), default: []].insert(position.ordinal)
      }
    }
    let prefix = groupID + "\u{0}"
    for (key, list) in ranges where key.hasPrefix(prefix) {
      guard let epoch = Self.epoch(ofKey: key), let lower = list.first?.lowerBound,
        let upper = list.last?.upperBound
      else { continue }
      if epoch < floor {
        ranges[key] = nil
        continue
      }
      var spans: [ClosedRange<UInt64>] = []
      var start = lower
      for ordinal in (held[key] ?? []).sorted() where ordinal >= start && ordinal < upper {
        if ordinal > start { spans.append(start...ordinal - 1) }
        start = ordinal + 1
      }
      spans.append(start...upper)
      ranges[key] = spans
    }
    // An exception kept from an earlier floor ends when Native no longer holds its receipt.
    for key in open.keys where key.hasPrefix(prefix) { open[key] = nil }
    for (key, ordinals) in early { open[key] = ordinals }
    if floor > 0 { floors[groupID] = floor }
  }

  /// The first range that ends at or after `ordinal`; ranges are sorted and never touch.
  private static func firstIndex(in list: [ClosedRange<UInt64>], reaching ordinal: UInt64) -> Int {
    var low = 0
    var high = list.count
    while low < high {
      let middle = (low + high) / 2
      if list[middle].upperBound < ordinal { low = middle + 1 } else { high = middle }
    }
    return low
  }

  private static func key(_ position: DeviceSenderFeedPosition) -> String {
    "\(position.groupID)\u{0}\(position.sender.rawValue)\u{0}\(position.groupEpoch)"
  }

  private static func epoch(ofKey key: String) -> UInt64? {
    key.split(separator: "\u{0}", omittingEmptySubsequences: false).last.flatMap { UInt64($0) }
  }
}

extension DeviceGroup {
  /// What a store needs to coalesce its handled positions for this group: the oldest epoch
  /// whose frames Native can still open (it keeps the keys of the current epoch and the three
  /// before it), and every position for which it holds an unconsumed receipt.
  func handledPositionsCoalescing() async throws -> (
    groupID: String, floor: UInt64, unconsumed: [DeviceSenderFeedPosition]
  ) {
    let epoch = try await groupInfo().epoch
    let groupID = groupID
    let unconsumed = try await pendingApplicationReceipts().compactMap { receipt in
      receipt.routing.map {
        DeviceSenderFeedPosition(
          groupID: groupID, groupEpoch: $0.epoch, sender: $0.sender, ordinal: $0.ordinal,
          previousOrdinal: $0.previousOrdinal)
      }
    }
    return (groupID, epoch >= 3 ? epoch - 3 : 0, unconsumed)
  }
}
