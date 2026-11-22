import PiCore
import Synchronization

/// A single SDK manual-code prompt. The SDK signal retires the waiter when the browser wins.
final class SubscriptionCallbackInput: Sendable {
  private struct State {
    var waiter: CheckedContinuation<String, any Error>?
    var result: Result<String, any Error>?
  }
  private let state = Mutex(State())

  func wait(signal: PiCore.AbortSignal) async throws -> String {
    try signal.throwIfAborted()
    let token = signal.addListener { [self] _ in finish(.failure(CancellationError())) }
    defer { if let token { signal.removeListener(token) } }
    return try await withCheckedThrowingContinuation { continuation in
      let result = state.withLock { value -> Result<String, any Error>? in
        if let result = value.result { return result }
        value.waiter = continuation
        return nil
      }
      if let result { continuation.resume(with: result) }
    }
  }

  func submit(_ value: String) throws {
    let submitted = state.withLock { state -> (Bool, CheckedContinuation<String, any Error>?) in
      guard state.result == nil else { return (false, nil) }
      state.result = .success(value)
      defer { state.waiter = nil }
      return (true, state.waiter)
    }
    guard submitted.0 else { throw ChatGPTSignInError.invalidConfiguration }
    submitted.1?.resume(returning: value)
  }

  private func finish(_ result: Result<String, any Error>) {
    let waiter = state.withLock { state -> CheckedContinuation<String, any Error>? in
      guard state.result == nil else { return nil }
      state.result = result
      defer { state.waiter = nil }
      return state.waiter
    }
    waiter?.resume(with: result)
  }
}
