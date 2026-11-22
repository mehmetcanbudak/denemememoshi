import MemoshiProtocol

/// The live buffer starts at the same serial-writer boundary as these replay bounds.
public struct EventObservation: Sendable {
  /// The replay head and retention bounds captured before subsequent live commits.
  public let bounds: ReplayBounds
  /// Subsequent committed facts, with explicit overflow rather than silent loss.
  public let events: AsyncThrowingStream<EventEnvelope, any Error>
}

extension Store {
  /// No writer can enter between capturing the head and subscribing to subsequent commits.
  public func observeEvents(after: Int64?, capacity: Int = 128) throws -> EventObservation {
    try requireOpen()
    let bounds = try replayBounds()
    if let after, after < 0 || after > bounds.head { throw StoreError.invalidReplayCursor }
    return EventObservation(bounds: bounds, events: try eventBus.subscribe(capacity: capacity))
  }
}
