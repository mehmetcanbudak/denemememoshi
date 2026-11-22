import Foundation

/// The Pi_Swift release Memoshi builds against: the tag `slice-2.2` (D140). From D134 on, S1
/// results count for the gate (D90); a build alone is not an S1 pass.
public enum PiDevelopmentSnapshot {
  /// The exact Pi_Swift commit, as pinned in scripts/lib/pi-swift-pin.sh;
  /// scripts/check-prerequisites.sh refuses a value that disagrees.
  public static let revision = "56d6fc89ebb039ad1b5e9128c8b12131d92d0cbe"
  /// The upstream Pi revision recorded by that commit.
  public static let upstreamRevision = "22dc6c26f3c530e11b8cc40443ecdce2b3c84116"
}

/// Actual process-local engine activity, separate from scheduler and Apple-host readiness.
public struct RuntimeStatus: Equatable, Sendable {
  /// Open Pi-backed conversation stores.
  public let openThreads: Int
  /// Nonterminal root text turns and real task-owned child runs.
  public let liveRuns: Int
  /// Conversations whose unfinished work stays paused until its selected model is discovered.
  public let awaitingModels: Int
  /// A retained purge could not finish; its durable job remains held for a later retry.
  public let lifecycleMaintenanceFailed: Bool

  /// Reports observed runtime activity.
  public init(
    openThreads: Int, liveRuns: Int, awaitingModels: Int = 0,
    lifecycleMaintenanceFailed: Bool = false
  ) {
    self.openThreads = openThreads
    self.liveRuns = liveRuns
    self.awaitingModels = awaitingModels
    self.lifecycleMaintenanceFailed = lifecycleMaintenanceFailed
  }
}
