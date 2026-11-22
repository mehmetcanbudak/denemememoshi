import Foundation
import MemoshiProtocol
import MemoshiStore
import Synchronization

/// One ordered in-process subscription (``InProcessEngine/events()``).
public struct InProcessEventFeed: Sendable {
  /// Snapshots read after subscribing cover every durable fact through this sequence number.
  public let head: Int64
  /// Durable facts after `head` in sequence order, and this device's live UI frames, each after
  /// the durable fact its `after` names. Ends when the engine closes. Fails with
  /// `EventBusError.overflow` once the consumer is a full buffer behind; it must then subscribe
  /// and bootstrap again. Live frames may be dropped; durable facts never are.
  public let events: AsyncThrowingStream<EventEnvelope, any Error>
}

/// Fans live UI frames out to in-process subscriptions; durable facts come from the Store's bus.
final class InProcessEventFeeds: Sendable {
  private struct State: Sendable {
    var subscriptions: [UUID: InProcessSubscription] = [:]
    var isFinished = false
  }

  private let state = Mutex(State())

  /// Bridges one Store observation, captured before any snapshot read, into an ordered feed.
  func subscribe(_ observation: EventObservation, capacity: Int = 1_024) throws
    -> InProcessEventFeed
  {
    let id = UUID()
    let (stream, continuation) = AsyncThrowingStream<EventEnvelope, any Error>.makeStream(
      bufferingPolicy: .bufferingOldest(capacity))
    let subscription = InProcessSubscription(
      continuation: continuation, delivered: observation.bounds.head)
    // finish/yield may run termination while a lock is held; cleanup never reenters one.
    continuation.onTermination = { @Sendable [weak self] _ in
      Task {
        subscription.cancelPump()
        self?.remove(id)
      }
    }
    try state.withLock { state in
      guard !state.isFinished else { throw EventBusError.closed }
      state.subscriptions[id] = subscription
    }
    subscription.startPump(
      Task {
        do {
          for try await event in observation.events { subscription.durable(event) }
          subscription.finish(throwing: nil)
        } catch is CancellationError {
          subscription.finish(throwing: nil)
        } catch {
          subscription.finish(throwing: error)
        }
      })
    return InProcessEventFeed(head: observation.bounds.head, events: stream)
  }

  /// Offers one stamped live frame to every current subscription.
  func publish(_ event: EventEnvelope) {
    let current = state.withLock { Array($0.subscriptions.values) }
    for subscription in current { subscription.live(event) }
  }

  /// Ends every subscription and refuses new ones.
  func finish() {
    let current = state.withLock { state in
      state.isFinished = true
      let current = Array(state.subscriptions.values)
      state.subscriptions.removeAll()
      return current
    }
    for subscription in current { subscription.finish(throwing: nil) }
  }

  private func remove(_ id: UUID) {
    state.withLock { _ = $0.subscriptions.removeValue(forKey: id) }
  }
}

/// Orders one consumer's feed: a live frame waits until the durable fact its `after` names has
/// been delivered, so it never overtakes the commit it follows.
private final class InProcessSubscription: Sendable {
  private struct State: Sendable {
    var delivered: Int64
    var held: [EventEnvelope] = []
    var isFinished = false
  }

  private struct Pump: Sendable {
    var task: Task<Void, Never>?
    var isCanceled = false
  }

  /// Live frames that may wait for their durable predecessor; older ones are dropped beyond it.
  private static let heldLimit = 256

  private let continuation: AsyncThrowingStream<EventEnvelope, any Error>.Continuation
  private let state: Mutex<State>
  private let pump = Mutex(Pump())

  init(continuation: AsyncThrowingStream<EventEnvelope, any Error>.Continuation, delivered: Int64) {
    self.continuation = continuation
    self.state = Mutex(State(delivered: delivered))
  }

  func startPump(_ task: Task<Void, Never>) {
    let canceled = pump.withLock { pump in
      pump.task = task
      return pump.isCanceled
    }
    if canceled { task.cancel() }
  }

  func cancelPump() {
    let task = pump.withLock { pump in
      pump.isCanceled = true
      return pump.task
    }
    task?.cancel()
  }

  func durable(_ event: EventEnvelope) {
    state.withLock { state in
      guard !state.isFinished else { return }
      guard case .enqueued = continuation.yield(event) else {
        state.isFinished = true
        state.held.removeAll()
        continuation.finish(throwing: EventBusError.overflow)
        return
      }
      if let seq = event.seq { state.delivered = max(state.delivered, seq) }
      var released = 0
      for frame in state.held {
        guard (frame.after ?? 0) <= state.delivered else { break }
        _ = continuation.yield(frame)
        released += 1
      }
      state.held.removeFirst(released)
    }
  }

  func live(_ event: EventEnvelope) {
    state.withLock { state in
      guard !state.isFinished else { return }
      if state.held.isEmpty, (event.after ?? 0) <= state.delivered {
        // A dropped UI frame is recovered from history by the consumer's offset check.
        _ = continuation.yield(event)
      } else {
        if state.held.count == Self.heldLimit { state.held.removeFirst() }
        state.held.append(event)
      }
    }
  }

  func finish(throwing error: (any Error)?) {
    state.withLock { state in
      guard !state.isFinished else { return }
      state.isFinished = true
      state.held.removeAll()
      continuation.finish(throwing: error)
    }
  }
}
