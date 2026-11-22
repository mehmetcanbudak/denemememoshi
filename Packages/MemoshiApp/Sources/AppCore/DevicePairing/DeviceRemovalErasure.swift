import Foundation

/// What the device layer says about this device's own place in its group. AppCore never
/// imports the device layer; the host adapts its node to these two calls.
public protocol RemovedDeviceSource: Sendable {
  /// Whether a verified commit removed this device from its group (the node's membership is
  /// `.removed`). A relay that only refused the device never makes this true.
  func isRemoved() async -> Bool
  /// Finishes the device layer's own deletion after the removal (group keys, its own signing
  /// key in the group, message history, conversation replicas) and returns whether it is
  /// complete (the node's `deletedRemovedData`).
  func finishDeletion() async -> Bool
}

/// A host store that holds data this device received through its group.
public protocol GroupReceivedStore: Sendable {
  /// Deletes everything the store holds, durably before it returns; later writes are refused.
  /// Repeating it is harmless.
  func eraseReceivedData() async throws
}

/// What one check of a device's removal found and did.
public enum DeviceRemovalOutcome: Hashable, Sendable {
  /// The device is in its group, also when a relay refused it: nothing was deleted.
  case member
  /// The device was removed and everything it received through the group is deleted. The
  /// person is told so.
  case deleted
  /// The device was removed, but some of that data is not deleted yet. Nothing is claimed; the
  /// next check (a later notice or the next open) tries again.
  case incomplete
}

/// This device was removed from its group. Opening it again shows this instead of a session;
/// the person is told so, and whether everything it received through the group is deleted.
public struct DevicePairingRemovedFromGroup: Error, Sendable {
  /// The outcome of the deletion this open ran: `.deleted` or `.incomplete`.
  public let deletion: DeviceRemovalOutcome

  /// `deletion` is what the open's check found.
  public init(deletion: DeviceRemovalOutcome) { self.deletion = deletion }
}

/// What the person is told about a verified removal.
public enum DeviceRemovalNotice: Hashable, Sendable {
  /// Everything the device received through the group is deleted.
  case deleted
  /// Some of it is not deleted yet; the deletion is being tried again.
  case deleting
  /// The retries ran out; the rest is deleted the next time the device is opened.
  case notDeletedYet
}

/// Follows a verified removal: tells the person at once, then retries an incomplete deletion
/// with a bounded backoff in the same run.
public struct DeviceRemovalRetry: Sendable {
  /// 1, 2, 4, 8, 16 then 30 seconds three times: eight retries in about two minutes.
  public static let standardDelays: [Duration] = [1, 2, 4, 8, 16, 30, 30, 30].map {
    .seconds($0)
  }
  private let delays: [Duration]
  private let sleep: @Sendable (Duration) async throws -> Void

  /// `sleep` waits one delay and throws when the retry is cancelled.
  public init(
    delays: [Duration] = Self.standardDelays,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.delays = delays
    self.sleep = sleep
  }

  /// `first` is the outcome of the check that verified the removal. A member is not followed.
  /// Otherwise the person is told at once (`.deleted` or `.deleting`); while the deletion is
  /// incomplete, `attempt` runs after each delay, and the end is reported: `.deleted`, or
  /// `.notDeletedYet` after the last delay. A cancelled wait ends it without another notice.
  public func follow(
    first: DeviceRemovalOutcome, attempt: @Sendable () async -> DeviceRemovalOutcome,
    report: @Sendable (DeviceRemovalNotice) async -> Void
  ) async {
    switch first {
    case .member: return
    case .deleted:
      await report(.deleted)
      return
    case .incomplete: await report(.deleting)
    }
    for delay in delays {
      do { try await sleep(delay) } catch { return }
      if Task.isCancelled { return }
      switch await attempt() {
      case .deleted:
        await report(.deleted)
        return
      case .member:
        return
      case .incomplete: continue
      }
    }
    await report(.notDeletedYet)
  }
}

/// D133, host side: once this device's removal from its group is verified, the host deletes
/// every store of its own that holds what the device received through the group. The device
/// layer deletes its own state; this asks it to finish and reports whether everything is gone.
public struct DeviceRemovalErasure: Sendable {
  private let device: any RemovedDeviceSource
  private let stores: [any GroupReceivedStore]

  /// `stores` are every host store that holds data received through the group.
  public init(device: any RemovedDeviceSource, stores: [any GroupReceivedStore]) {
    self.device = device
    self.stores = stores
  }

  /// Checks the device's membership; for a removed device deletes what it received. A store
  /// that fails does not stop the others; the outcome is `.deleted` only when nothing is left.
  public func check() async -> DeviceRemovalOutcome {
    guard await device.isRemoved() else { return .member }
    var complete = await device.finishDeletion()
    for store in stores {
      do { try await store.eraseReceivedData() } catch { complete = false }
    }
    return complete ? .deleted : .incomplete
  }
}
