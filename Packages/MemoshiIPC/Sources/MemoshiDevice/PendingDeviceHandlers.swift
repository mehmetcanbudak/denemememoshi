import Foundation
import Synchronization

final class PendingDeviceHandlers: Sendable {
  struct Snapshot: Sendable {
    let channels: [any FrameChannel]
    let tasks: [Task<Void, Never>]

    func cancelAndClose() {
      for task in tasks { task.cancel() }
      for channel in channels { channel.close() }
    }

    func join() async {
      for task in tasks { await task.value }
    }
  }

  private enum Phase {
    case accepting
    case closing
    case closed
  }

  private struct State {
    var phase = Phase.accepting
    var channels: [UUID: any FrameChannel] = [:]
    var tasks: [UUID: Task<Void, Never>] = [:]
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = Mutex(State())

  @discardableResult
  func start(
    channel: (any FrameChannel)? = nil,
    _ operation: @escaping @Sendable (UUID) async -> Void
  ) -> Task<Void, Never>? {
    let identifier = UUID()
    let task = state.withLock { state -> Task<Void, Never>? in
      guard case .accepting = state.phase else { return nil }
      state.channels[identifier] = channel
      // Completion cannot remove its record before task insertion has finished.
      let task = Task { [self] in
        if !Task.isCancelled { await operation(identifier) }
        finished(identifier)
      }
      state.tasks[identifier] = task
      return task
    }
    if task == nil { channel?.close() }
    return task
  }

  func admit(_ identifier: UUID, _ commit: () throws -> Void) throws {
    try state.withLock { state in
      guard case .accepting = state.phase, state.channels[identifier] != nil else {
        throw DeviceLayerError.closed
      }
      try commit()
    }
  }

  func transfer(_ identifier: UUID) throws {
    try state.withLock { state in
      guard case .accepting = state.phase,
        state.channels.removeValue(forKey: identifier) != nil
      else { throw DeviceLayerError.closed }
    }
  }

  private func finished(_ identifier: UUID) {
    let channel = state.withLock { $0.channels.removeValue(forKey: identifier) }
    channel?.close()
    _ = state.withLock { $0.tasks.removeValue(forKey: identifier) }
  }

  func beginClose() -> Snapshot? {
    state.withLock { state in
      guard case .accepting = state.phase else { return nil }
      state.phase = .closing
      return Snapshot(channels: Array(state.channels.values), tasks: Array(state.tasks.values))
    }
  }

  func waitUntilClosed() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let complete = state.withLock { state in
        if case .closed = state.phase { return true }
        state.waiters.append(continuation)
        return false
      }
      if complete { continuation.resume() }
    }
  }

  func finishClose() {
    let waiters = state.withLock { state in
      state.phase = .closed
      defer { state.waiters.removeAll() }
      return state.waiters
    }
    for waiter in waiters { waiter.resume() }
  }
}
