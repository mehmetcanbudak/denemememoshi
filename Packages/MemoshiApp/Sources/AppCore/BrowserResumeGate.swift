import Foundation

/// Resumes one continuation with the first of: the operation's result, a timeout or task
/// cancellation. WebKit calls cannot be cancelled, so late results are ignored, not awaited.
@MainActor
public final class BrowserResumeGate<Value: Sendable> {
  private var continuation: CheckedContinuation<Value, any Error>?
  private var pending: Result<Value, any Error>?
  private var timer: Task<Void, Never>?
  private var isFinished = false

  /// An idle gate; `value` starts its operation.
  public init() {}

  /// Runs `start` and returns the first outcome. `start` must arrange a later `resume`. In a
  /// task already cancelled, `start` never runs: a load or call it would issue is not started.
  public func value(
    timeout: Duration, timeoutError: any Error, start: () -> Void
  ) async throws -> Value {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        install(continuation, timeout: timeout, timeoutError: timeoutError)
        guard !Task.isCancelled else { return resume(.failure(CancellationError())) }
        start()
      }
    } onCancel: {
      Task { @MainActor in self.resume(.failure(CancellationError())) }
    }
  }

  /// Delivers the operation's outcome; only the first outcome counts.
  public func resume(_ result: Result<Value, any Error>) {
    guard !isFinished else { return }
    guard let continuation else {
      pending = result
      return
    }
    isFinished = true
    self.continuation = nil
    timer?.cancel()
    timer = nil
    continuation.resume(with: result)
  }

  private func install(
    _ continuation: CheckedContinuation<Value, any Error>, timeout: Duration,
    timeoutError: any Error
  ) {
    if let pending {
      isFinished = true
      self.pending = nil
      continuation.resume(with: pending)
      return
    }
    self.continuation = continuation
    timer = Task { @MainActor [weak self] in
      try? await Task.sleep(for: timeout)
      guard !Task.isCancelled else { return }
      self?.resume(.failure(timeoutError))
    }
  }
}
