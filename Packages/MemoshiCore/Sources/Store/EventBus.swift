import Foundation
import MemoshiProtocol
import Synchronization

/// Invalid-capacity, closed-stream and explicit overflow failures.
public enum EventBusError: Error, Equatable, Sendable {
  case invalidCapacity
  case overflow
  case closed
}

/// In-process fan-out; SQLite remains the source of truth. Re-expressed from Draft 3
/// sidecar/src/events/bus.ts at ce39f8a7ca324ce1c2473518593b1fb4f96ebe4b.
/// Publish committed batches in commit order. A slow consumer terminates with `overflow`
/// after draining its bounded buffer, and must replay from its own last applied seq.
public final class EventBus: Sendable {
  private struct Subscription: Sendable {
    let conversationID: ConversationID?
    let continuation: AsyncThrowingStream<EventEnvelope, any Error>.Continuation
  }

  private struct State: Sendable {
    var subscriptions: [UUID: Subscription] = [:]
    var isClosed = false
  }

  private let state = Mutex(State())

  /// Creates a subscriber registry with per-subscription bounded buffers.
  public init() {}

  /// `nil` receives all events; a conversation subscription receives only that conversation.
  public func subscribe(
    conversationID: ConversationID? = nil, capacity: Int = 256
  ) throws -> AsyncThrowingStream<EventEnvelope, any Error> {
    guard (1...10_000).contains(capacity) else { throw EventBusError.invalidCapacity }
    return try state.withLock { state in
      guard state.isClosed == false else { throw EventBusError.closed }
      let id = UUID()
      let (stream, continuation) = AsyncThrowingStream<EventEnvelope, any Error>.makeStream(
        bufferingPolicy: .bufferingOldest(capacity))
      // finish/yield may invoke termination while the mutex is held. Cleanup must not reenter it.
      continuation.onTermination = { @Sendable [weak self] _ in
        Task { self?.remove(id) }
      }
      state.subscriptions[id] = Subscription(
        conversationID: conversationID, continuation: continuation)
      return stream
    }
  }

  /// Synchronous publication lets a Store finish COMMIT and publish before its actor can reenter.
  public func publish(_ events: [EventEnvelope]) {
    state.withLock { state in
      for event in events {
        var ended: [UUID] = []
        for (id, subscription) in state.subscriptions {
          guard
            subscription.conversationID == nil
              || subscription.conversationID == event.scope.conversationId
          else { continue }
          switch subscription.continuation.yield(event) {
          case .enqueued:
            break
          case .dropped:
            subscription.continuation.finish(throwing: EventBusError.overflow)
            ended.append(id)
          case .terminated:
            ended.append(id)
          @unknown default:
            subscription.continuation.finish(throwing: EventBusError.overflow)
            ended.append(id)
          }
        }
        for id in ended { state.subscriptions.removeValue(forKey: id) }
      }
    }
  }

  /// Finishes every subscription and refuses new subscribers.
  public func close() {
    state.withLock { state in
      state.isClosed = true
      for subscription in state.subscriptions.values { subscription.continuation.finish() }
      state.subscriptions.removeAll()
    }
  }

  private func remove(_ id: UUID) {
    state.withLock { _ = $0.subscriptions.removeValue(forKey: id) }
  }
}
