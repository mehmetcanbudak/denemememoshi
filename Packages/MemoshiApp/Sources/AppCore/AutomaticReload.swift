import Foundation
import MemoshiProtocol

/// The rule for an event consumer whose update failed with a timeout or a daemon error: every
/// snapshot is reloaded once, by itself, before the failure is shown (D130). There is no loop:
/// within one streak a second such failure, and any failure of the reload, is passed on.
@MainActor
public final class AutomaticReload {
  /// What kind of update is being applied.
  public enum Step: Sendable {
    /// A durable event or a resync barrier. Only one that applies normally ends a streak.
    case durable
    /// A UI-only frame. Applying one is not progress.
    case transient
  }

  private var reloaded = false
  private let isTimeout: @MainActor (any Error) -> Bool

  /// `isTimeout` recognises the caller's own request-timeout error; a daemon error
  /// (`RPCError`) is recognised here.
  public init(isTimeout: @escaping @MainActor (any Error) -> Bool) {
    self.isTimeout = isTimeout
  }

  /// Forgets the streak, for a new consumer.
  public func reset() { reloaded = false }

  /// Applies one update. When `apply` fails with a timeout or a daemon error and no reload
  /// was made in this streak, `reload` runs once in its place. Every other failure, including
  /// one thrown by `reload`, is passed on unchanged for the caller to classify.
  public func run(
    _ step: Step, apply: @MainActor () async throws -> Void,
    reload: @MainActor () async throws -> Void
  ) async throws {
    do {
      try await apply()
      if step == .durable { reloaded = false }
    } catch let error where !reloaded && (isTimeout(error) || error is RPCError) {
      reloaded = true
      try await reload()
    }
  }
}
