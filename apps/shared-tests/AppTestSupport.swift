import Foundation
import Testing

/// A defaults suite removed when the test ends.
final class TestDefaults: Sendable {
  let name = "memoshi-app-target-tests-\(UUID().uuidString)"
  var defaults: UserDefaults { UserDefaults(suiteName: name)! }

  deinit { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
}

/// Polls main-actor state until it holds, failing after a bounded wait.
@MainActor
func eventually(
  _ description: Comment, timeout: Duration = .seconds(5),
  _ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation
) async throws {
  let deadline = ContinuousClock.now + timeout
  while !condition() {
    guard ContinuousClock.now < deadline else {
      Issue.record("Timed out: \(description)", sourceLocation: sourceLocation)
      throw CancellationError()
    }
    try await Task.sleep(for: .milliseconds(5))
  }
}
