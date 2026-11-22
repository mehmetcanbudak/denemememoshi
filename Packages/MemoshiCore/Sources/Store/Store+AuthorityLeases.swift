import Foundation
import MemoshiProtocol

extension Store {
  /// Records a lease that a cross-device lease authority decided (S2 development prototype), so
  /// this device's writes are fenced by the authority's epoch instead of a local claim.
  ///
  /// Epochs only move forward: a record older than the local one throws `leaseFenced`. A newer
  /// record replaces the local one whoever its runner is, which fences this device's older
  /// capability at once. At the same epoch a released lease stays released, the same runner's
  /// expiry only extends, and a different runner is refused as `invalidCommit`, because an
  /// authority never grants one epoch twice. `runnerDeviceID` and `expiresAt` are both present
  /// (a held lease) or both absent (released, or a holder this device does not know).
  @discardableResult
  public func recordAuthorityLease(
    _ conversationID: ConversationID, epoch: Int64, runnerDeviceID: DeviceID?, expiresAt: Int64?,
    at now: Int64
  ) throws -> ConversationLease {
    try requireOpen()
    guard epoch > 0, (runnerDeviceID == nil) == (expiresAt == nil) else {
      throw StoreError.invalidCommit(
        "An authority lease needs a positive epoch and a consistent holder")
    }
    return try writer.transaction(write: true) {
      let current = try readLease(conversationID)
      var next = ConversationLease(
        conversationID: conversationID, epoch: epoch, runnerDeviceID: runnerDeviceID,
        expiresAt: expiresAt)
      if let current {
        guard epoch >= current.epoch else {
          throw StoreError.leaseFenced(conversationID: conversationID, currentEpoch: current.epoch)
        }
        if epoch == current.epoch {
          guard let holder = current.runnerDeviceID else { return current }
          if let runnerDeviceID {
            guard runnerDeviceID == holder else {
              throw StoreError.invalidCommit("The authority reported two runners at one epoch")
            }
            next = ConversationLease(
              conversationID: conversationID, epoch: epoch, runnerDeviceID: holder,
              expiresAt: max(current.expiresAt ?? 0, expiresAt ?? 0))
          }
        }
      }
      try writer.execute(
        """
        INSERT INTO leases (conversation_id, epoch, runner_device_id, expires_at) VALUES (?, ?, ?, ?)
        ON CONFLICT (conversation_id) DO UPDATE SET epoch = excluded.epoch,
          runner_device_id = excluded.runner_device_id, expires_at = excluded.expires_at
        """,
        [
          .text(conversationID.rawValue), .integer(next.epoch),
          next.runnerDeviceID.map { .text($0.rawValue) } ?? .null,
          next.expiresAt.map { .integer($0) } ?? .null,
        ])
      return next
    }
  }
}
