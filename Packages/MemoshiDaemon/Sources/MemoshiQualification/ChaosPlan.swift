import Foundation

/// Where the driver deliberately SIGKILLs the qualification host (phase-0 S1.13 kill points this
/// runtime-host harness can reach).
package enum KillPoint: String, Codable, CaseIterable, Sendable {
  /// The provider has streamed reply text the host already received; the model call is open.
  case streaming
  /// The approved tool is executing and has not posted its effect.
  case toolExecuting = "tool-executing"
  /// The tool call waits on a pending approval decision.
  case approvalWaiting = "approval-waiting"
  /// The ledger accepted the effect; Pi has not committed the tool result.
  case effectPosted = "effect-posted"
  /// The turn finished and the runtime has no live run.
  case idle
  /// A spawned child conversation is running inside the host; the kill reaches parent and child.
  case subagent
  /// A Code Mode script is executing a nested tool call; the kill interrupts the script and nested call.
  case codemodeNested = "codemode-nested"
  /// The runtime is inside a compaction step. Not yet drivable: the runtime composition starts
  /// no compaction and emits no compaction event.
  case compaction

  /// Whether the point is gated unrun: a batch that draws it cannot pass, so a default
  /// selection must not include it. An explicit `--points` selection keeps the gate's refusal.
  package var isGated: Bool {
    self == .compaction
  }

  /// What a batch without `--points` draws: the five points the recorded S1.13 batches were
  /// measured on, in declaration order, so a recorded seed still reproduces its plan. Any other
  /// point runs only when `--points` names it.
  package static var defaultSelection: [KillPoint] {
    allCases.filter { $0.defaultExclusionReason == nil }
  }

  /// Why a point is left out of `defaultSelection`, or nil for a default point.
  package var defaultExclusionReason: String? {
    switch self {
    case .streaming, .toolExecuting, .approvalWaiting, .effectPosted, .idle: nil
    case .subagent, .codemodeNested:
      "outside the recorded S1.13 default; select it with --points (no real-model batch has run it)"
    case .compaction: "not drivable yet: the runtime starts no compaction step"
    }
  }
}

/// SplitMix64. The plan relies only on this generator and its own bounded draws, never on
/// standard-library shuffling, so a seed reproduces the same plan on every toolchain.
package struct SeededGenerator: RandomNumberGenerator, Sendable {
  private var state: UInt64

  package init(seed: UInt64) { state = seed }

  package mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }

  /// An unbiased draw from `0..<bound` by rejection sampling.
  package mutating func draw(below bound: Int) -> Int {
    precondition(bound > 0)
    let limit = UInt64(bound)
    let threshold = (0 &- limit) % limit
    while true {
      let value = next()
      if value >= threshold { return Int(value % limit) }
    }
  }
}

/// One planned run: where and how often the host is killed before its final, uninterrupted life.
package struct PlannedRun: Codable, Equatable, Sendable {
  /// One-based position in the batch.
  package let index: Int
  /// Where every deliberate kill of this run happens.
  package let killPoint: KillPoint
  /// Deliberate kills before the final life; each kill starts a new host life.
  package let kills: Int
  /// Reply deltas the provider streams before pausing a streaming-kill request (1...3).
  package let streamingDeltas: Int
  /// Seeded delay after the kill point is observed and before SIGKILL (0...250 ms).
  package let killDelayMilliseconds: Int

  package init(
    index: Int, killPoint: KillPoint, kills: Int, streamingDeltas: Int, killDelayMilliseconds: Int
  ) {
    self.index = index
    self.killPoint = killPoint
    self.kills = kills
    self.streamingDeltas = streamingDeltas
    self.killDelayMilliseconds = killDelayMilliseconds
  }
}

/// A seed-determined batch. Every consecutive block of `points.count` runs covers each selected
/// point once, in seeded order, so per-point counts differ by at most one: a 50-run batch gives
/// each of the five default points ten runs, but over six points two get nine and four get eight.
package struct ChaosPlan: Codable, Equatable, Sendable {
  /// The seed that, with the ordered point selection, run count and kills per run, determines
  /// the plan.
  package let seed: UInt64
  /// The resolved point selection in the order the plan shuffles it, so a batch that relied on
  /// the default selection records what it drew from.
  package let points: [KillPoint]
  /// Runs in execution order.
  package let runs: [PlannedRun]

  /// Plan validation failures.
  package enum PlanError: Error, Equatable {
    /// Runs and kills per run must be positive; points must be non-empty and unique.
    case invalid
  }

  package init(seed: UInt64, runs count: Int, points: [KillPoint], killsPerRun: Int = 1) throws {
    guard count > 0, killsPerRun > 0, !points.isEmpty, Set(points).count == points.count else {
      throw PlanError.invalid
    }
    var generator = SeededGenerator(seed: seed)
    var order: [KillPoint] = []
    var runs: [PlannedRun] = []
    runs.reserveCapacity(count)
    for index in 1...count {
      if order.isEmpty {
        order = points
        // Fisher-Yates over this block with the plan's own bounded draws.
        for position in stride(from: order.count - 1, to: 0, by: -1) {
          order.swapAt(position, generator.draw(below: position + 1))
        }
      }
      let point = order.removeFirst()
      runs.append(
        PlannedRun(
          index: index, killPoint: point, kills: killsPerRun,
          streamingDeltas: 1 + generator.draw(below: 3),
          killDelayMilliseconds: generator.draw(below: 251)))
    }
    self.seed = seed
    self.points = points
    self.runs = runs
  }
}
