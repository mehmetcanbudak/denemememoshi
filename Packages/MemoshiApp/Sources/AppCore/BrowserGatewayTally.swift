import Foundation

/// Hands out a review gateway's decisions once each, across reads (Mac and mobile review hosts).
/// The gateway keeps only its newest decisions; each read gives that window together with the
/// count recorded up to its newest entry, taken at one moment (`EgressGateway.decisionWindow`).
/// Decisions that left the window between two reads are counted, never guessed as allowed or
/// denied: these gateways have no log file or sink.
public struct BrowserGatewayTally: Sendable {
  /// Decisions recorded up to the last read.
  public private(set) var counted = 0

  /// A tally of a gateway nothing was read from yet.
  public init() {}

  /// The decisions recorded since the last read that `window` still holds, and how many more
  /// were recorded but already left it.
  public mutating func take<Decision>(_ window: [Decision], recorded: Int) -> (
    fresh: [Decision], uncounted: Int
  ) {
    let new = max(0, recorded - counted)
    let fresh = Array(window.suffix(new))
    counted = max(counted, recorded)
    return (fresh, new - fresh.count)
  }
}
