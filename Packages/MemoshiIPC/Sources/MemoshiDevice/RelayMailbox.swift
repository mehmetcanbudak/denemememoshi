import Foundation
import MemoshiProtocol
import Synchronization

/// Ciphertext transport delivery, not a durable application/replica acknowledgement. The
/// authority's high-water/digest reconciliation remains the recovery source of truth.
final class RelayMailbox: Sendable {
  struct Item: Codable, Sendable {
    var id: UUID
    var recipient: DeviceID
    var frame: Data
  }

  private enum Record: Codable {
    case enqueue(Item)
    case acknowledge(DeviceID, UUID)
    /// Every frame queued for a revoked device, dropped at once.
    case drop(DeviceID)
  }

  private struct Queue {
    var order: [UUID] = []
    var head = 0
    var items: [UUID: Item] = [:]
    var count: Int { items.count }

    mutating func append(_ item: Item) {
      order.append(item.id)
      items[item.id] = item
    }

    mutating func remove(_ id: UUID) {
      items[id] = nil
      while head < order.count, items[order[head]] == nil { head += 1 }
      if head > 1_024, head * 2 > order.count {
        order.removeFirst(head)
        head = 0
      }
    }

    var pending: [Item] { order[head...].compactMap { items[$0] } }
  }

  private struct State {
    var mailboxes: [DeviceID: Queue] = [:]
    var failed = false
  }

  private let state: Mutex<State>
  private let journal: DeviceStateJournal?
  private let limit: Int

  init(directory: URL?, limit: Int) throws {
    guard limit > 0 else { throw DeviceLayerError.invalid("mailbox limit") }
    self.limit = limit
    journal = try directory.map {
      try DeviceStateJournal(
        url: $0.appendingPathComponent("mailboxes.jsonl"), purpose: "memoshi.relay-mailboxes.v1")
    }
    var initial = State()
    for bytes in journal?.takeRecovered() ?? [] {
      switch try JSONDecoder().decode(Record.self, from: bytes) {
      case .enqueue(let item):
        initial.mailboxes[item.recipient, default: Queue()].append(item)
      case .acknowledge(let recipient, let id):
        initial.mailboxes[recipient]?.remove(id)
        if initial.mailboxes[recipient]?.count == 0 { initial.mailboxes[recipient] = nil }
      case .drop(let recipient):
        initial.mailboxes[recipient] = nil
      }
    }
    state = Mutex(initial)
  }

  func enqueue(_ frame: Data, to recipient: DeviceID) throws -> Item {
    try state.withLock { state in
      guard !state.failed else { throw DeviceLayerError.closed }
      guard state.mailboxes[recipient, default: Queue()].count < limit else {
        throw DeviceLayerError.invalid("mailbox full")
      }
      let item = Item(id: UUID(), recipient: recipient, frame: frame)
      do { try journal?.append(Record.enqueue(item)) } catch {
        state.failed = true
        throw error
      }
      state.mailboxes[recipient, default: Queue()].append(item)
      return item
    }
  }

  func pending(for recipient: DeviceID) throws -> [Item] {
    try state.withLock { state in
      guard !state.failed else { throw DeviceLayerError.closed }
      return state.mailboxes[recipient]?.pending ?? []
    }
  }

  func depth(for recipient: DeviceID) throws -> Int {
    try state.withLock { state in
      guard !state.failed else { throw DeviceLayerError.closed }
      return state.mailboxes[recipient]?.count ?? 0
    }
  }

  func acknowledge(_ id: UUID, by recipient: DeviceID) throws {
    try state.withLock { state in
      guard !state.failed else { throw DeviceLayerError.closed }
      guard state.mailboxes[recipient]?.items[id] != nil else { return }
      do { try journal?.append(Record.acknowledge(recipient, id)) } catch {
        state.failed = true
        throw error
      }
      state.mailboxes[recipient]?.remove(id)
      if state.mailboxes[recipient]?.count == 0 { state.mailboxes[recipient] = nil }
    }
  }

  /// Drops, durably, every frame queued for a revoked device: the relay never delivers or
  /// keeps one (protocol.md §12.5). Nothing happens when none is queued.
  func drop(for recipient: DeviceID) throws {
    try state.withLock { state in
      guard !state.failed else { throw DeviceLayerError.closed }
      guard state.mailboxes[recipient] != nil else { return }
      do { try journal?.append(Record.drop(recipient)) } catch {
        state.failed = true
        throw error
      }
      state.mailboxes[recipient] = nil
    }
  }

  /// The devices with frames queued.
  var recipients: [DeviceID] { state.withLock { Array($0.mailboxes.keys) } }

  func close() {
    state.withLock { $0.failed = true }
    journal?.close()
  }
}
