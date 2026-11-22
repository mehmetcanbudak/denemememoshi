import Foundation

/// Nonsecret logical high-water, kept in the device-only encrypted latest-value checkpoint.
/// Native membership/key epochs do not reset authority counters or permit same-counter forks.
struct CloudStateIndexPin: Codable, Hashable, Sendable {
  let epoch: UInt64
  let counter: UInt64
  let digest: Data

  static func accept(_ candidate: Self, over previous: Self?) throws -> Self {
    guard let previous else { return candidate }
    guard candidate.epoch >= previous.epoch, candidate.counter >= previous.counter else {
      throw AppleDeviceError.conflictingReplay
    }
    if candidate.epoch > previous.epoch {
      guard candidate.counter > previous.counter else { throw AppleDeviceError.conflictingReplay }
    } else if candidate.counter == previous.counter {
      guard candidate.digest == previous.digest else { throw AppleDeviceError.conflictingReplay }
    }
    return candidate
  }
}
