import Foundation

/// Unlike NIO futures, completion can be observed after an owned event loop has
/// stopped. It carries no executor affinity and completes every waiter once.
internal final class AsyncResult<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<Value, any Error>?
  private var continuations: [CheckedContinuation<Value, any Error>] = []

  func complete(_ result: Result<Value, any Error>) {
    let waiting = lock.withLock {
      guard self.result == nil else { return [CheckedContinuation<Value, any Error>]() }
      self.result = result
      let waiting = continuations
      continuations.removeAll()
      return waiting
    }
    for continuation in waiting { continuation.resume(with: result) }
  }

  func get() async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
      let ready: Result<Value, any Error>? = lock.withLock {
        if let result { return result }
        continuations.append(continuation)
        return nil
      }
      if let ready { continuation.resume(with: ready) }
    }
  }
}
