import Foundation
import MemoshiProtocol

/// The position of the snapshot a store holds. Snapshots are read concurrently, so one is
/// admitted only at or above the held position. A reset admits the next snapshot at any
/// position: at a resync barrier the daemon's log can be another one or a restored copy whose
/// positions lie below the old ones (D131), and a different conversation has its own history.
public struct SnapshotWatermark: Equatable, Sendable {
  /// The held snapshot's position; zero when nothing is held.
  public private(set) var position: Int64

  /// Starts at `position`: zero admits every snapshot.
  public init(position: Int64 = 0) {
    self.position = position
  }

  /// Whether a snapshot at `position` may replace the held one.
  public func admits(_ position: Int64) -> Bool { position >= self.position }

  /// Whether the held snapshot already includes `position`.
  public func covers(_ position: Int64) -> Bool { self.position >= position }

  /// Records an admitted snapshot. Returns false, changing nothing, for an older one.
  @discardableResult
  public mutating func advance(to position: Int64) -> Bool {
    guard admits(position) else { return false }
    self.position = position
    return true
  }

  /// Records a snapshot that was accepted for another reason, whatever its position.
  public mutating func replace(with position: Int64) {
    self.position = position
  }

  /// Forgets the held position, so that the next snapshot replaces what is held.
  public mutating func reset() {
    position = 0
  }
}

/// The latest snapshot of each task across conversations, each with its own position.
public struct TaskSnapshots: Sendable {
  /// The tasks, by identity.
  public private(set) var tasks: [TaskID: MemoshiTask] = [:]
  private var positions: [TaskID: Int64] = [:]

  /// Starts empty.
  public init() {}

  /// Records a task's snapshot. Returns false, changing nothing, when a newer snapshot of
  /// that task is already held.
  @discardableResult
  public mutating func record(_ task: MemoshiTask, asOf position: Int64) -> Bool {
    guard position >= positions[task.id] ?? .min else { return false }
    positions[task.id] = position
    tasks[task.id] = task
    return true
  }

  /// Whether an event at `position` is newer than the held snapshot of its task.
  public func isBehind(_ task: TaskID, at position: Int64) -> Bool {
    position > positions[task] ?? 0
  }

  /// Drops the tasks of conversations that are no longer listed (trashed or purged).
  public mutating func prune(keeping conversations: Set<ConversationID>) {
    for stale in tasks.values where !conversations.contains(stale.conversationId) {
      tasks[stale.id] = nil
      positions[stale.id] = nil
    }
  }

  /// Empties the list at a resync barrier, so that snapshots at any position are recorded.
  public mutating func removeAll() {
    tasks.removeAll()
    positions.removeAll()
  }
}
