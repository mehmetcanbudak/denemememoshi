import Foundation
import MemoshiProtocol

extension Store {
  /// Reads local ownership bookkeeping, not a cross-device authority grant.
  public func lease(_ conversationID: ConversationID) throws -> ConversationLease? {
    try requireOpen()
    return try readLease(conversationID)
  }

  /// Local single-device compare-and-swap only. Never use this as proof of a CloudKit/relay
  /// authority grant or provisional cross-device hand-over. A live lease cannot be stolen.
  public func claimConversation(
    _ conversationID: ConversationID, expectedEpoch: Int64?, expiresAt: Int64, at now: Int64
  ) throws -> ConversationLease {
    try requireOpen()
    guard now >= 0, expiresAt > now else {
      throw StoreError.invalidCommit("A lease must expire after its claim")
    }
    let (lease, events) = try writer.transaction(write: true) {
      try refuseDeletedConversation(conversationID)
      let current = try readLease(conversationID)
      guard current?.epoch == expectedEpoch,
        current?.runnerDeviceID == nil || (current?.expiresAt ?? 0) <= now
      else {
        throw StoreError.leaseFenced(conversationID: conversationID, currentEpoch: current?.epoch)
      }
      let previous = current?.epoch ?? 0
      guard previous < Int64.max else { throw StoreError.sequenceExhausted }
      let next = previous + 1
      try writer.execute(
        """
        INSERT INTO leases (conversation_id, epoch, runner_device_id, expires_at) VALUES (?, ?, ?, ?)
        ON CONFLICT (conversation_id) DO UPDATE SET epoch = excluded.epoch,
          runner_device_id = excluded.runner_device_id, expires_at = excluded.expires_at
        """,
        [
          .text(conversationID.rawValue), .integer(next), .text(deviceID.rawValue),
          .integer(expiresAt),
        ])
      let events = try flushGatewayAudit(conversationID: conversationID, at: now)
      let lease = ConversationLease(
        conversationID: conversationID, epoch: next, runnerDeviceID: deviceID, expiresAt: expiresAt)
      return (lease, events)
    }
    eventBus.publish(events)
    return lease
  }

  /// Extends a current, unexpired local lease without changing its epoch.
  public func renewConversation(
    _ fence: ConversationFence, expiresAt: Int64, at now: Int64
  ) throws -> ConversationLease {
    try requireOpen()
    guard expiresAt > now else {
      throw StoreError.invalidCommit("A renewal must expire in the future")
    }
    return try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      try writer.execute(
        "UPDATE leases SET expires_at = ? WHERE conversation_id = ?",
        [.integer(expiresAt), .text(fence.conversationID.rawValue)])
      return ConversationLease(
        conversationID: fence.conversationID, epoch: fence.epoch,
        runnerDeviceID: deviceID, expiresAt: expiresAt)
    }
  }

  /// Keeps the fencing epoch as a tombstone, so the next claim can never reuse it.
  public func releaseConversation(_ fence: ConversationFence, at now: Int64) throws {
    try requireOpen()
    let events = try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      let events = try flushGatewayAudit(conversationID: fence.conversationID, at: now)
      try writer.execute(
        "UPDATE leases SET runner_device_id = NULL, expires_at = NULL WHERE conversation_id = ?",
        [.text(fence.conversationID.rawValue)])
      return events
    }
    eventBus.publish(events)
  }

  /// A point-in-time local admission check. Pi_Swift must still enforce its own fencing at
  /// the actual durable write; this is not a cross-device authority grant.
  public func validateConversation(_ fence: ConversationFence, at now: Int64) throws {
    try requireOpen()
    try writer.transaction(write: false) { try checkFence(fence, at: now) }
  }

  /// Validates the fence and exclusively reserves its Pi path without creating a Pi database.
  public func acquireConversation(
    _ fence: ConversationFence, at now: Int64
  ) throws -> ConversationOwnership {
    try requireOpen()
    return try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      let file = directory.appendingPathComponent("pi/\(fence.conversationID.rawValue).sqlite")
      let lock = try directories.acquireConversationLock(fence.conversationID)
      try directories.checkConversationFile(file)
      return ConversationOwnership(fence: fence, fileURL: file, lock: lock)
    }
  }

  func readLease(_ conversationID: ConversationID) throws -> ConversationLease? {
    try writer.query(
      "SELECT epoch, runner_device_id, expires_at FROM leases WHERE conversation_id = ?",
      [.text(conversationID.rawValue)]
    ) { row in
      ConversationLease(
        conversationID: conversationID, epoch: row.integer(0),
        runnerDeviceID: try row.text(1).map(DeviceID.init), expiresAt: row.optionalInteger(2))
    }.first
  }

  func checkFence(_ fence: ConversationFence, at now: Int64) throws {
    try refuseDeletedConversation(fence.conversationID)
    let current = try readLease(fence.conversationID)
    guard let current, current.epoch == fence.epoch, current.runnerDeviceID == deviceID,
      let expiresAt = current.expiresAt, expiresAt > now
    else {
      throw StoreError.leaseFenced(
        conversationID: fence.conversationID, currentEpoch: current?.epoch)
    }
  }

  private func refuseDeletedConversation(_ id: ConversationID) throws {
    guard
      try writer.integer(
        "SELECT COUNT(*) FROM chats WHERE id = ? AND deleted_at IS NOT NULL",
        [.text(id.rawValue)]) == 0
    else { throw StoreError.chatNotFound }
  }
}
