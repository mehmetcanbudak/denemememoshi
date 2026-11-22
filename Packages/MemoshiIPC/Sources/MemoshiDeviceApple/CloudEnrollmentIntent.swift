import Foundation
import MemoshiDevice
import MemoshiProtocol

/// One device identity's explicit first-enrollment permission. It is persisted BEFORE the lab
/// factory returns and is initially group-unbound: QR hints cannot choose an authority/account.
/// Only a group installed by the local Native owner may consume this exact intent.
/// Missing/empty bound history requires recovery, not a new unbound intent.
actor CloudEnrollmentIntent {
  private struct State: Codable {
    enum Phase: String, Codable { case unbound, binding, bound }
    let deviceID: DeviceID
    let phase: Phase
    let groupID: String?
  }

  private let journal: DeviceStateJournal
  private var state: State

  init(directory: URL, identity: DeviceIdentity, allowCreation: Bool) throws {
    let path = directory.appendingPathComponent("cloud-enrollment-intent.jsonl")
    let existed = FileManager.default.fileExists(atPath: path.path)
    guard allowCreation || existed else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    let purpose = "com.memoshi.cloud.enrollment-intent.v1"
    let journal = try DeviceStateJournal(
      url: path,
      key: identity.derivedStateEncryptionKey(purpose: purpose), purpose: purpose)
    let state: State
    if let bytes = journal.takeRecovered().last {
      state = try JSONDecoder().decode(State.self, from: bytes)
      guard state.deviceID == identity.deviceID,
        (state.phase == .unbound) == (state.groupID == nil)
      else {
        journal.close()
        throw AppleDeviceError.stateRecoveryRequired
      }
    } else {
      guard allowCreation, !existed else {
        journal.close()
        throw AppleDeviceError.stateRecoveryRequired
      }
      state = State(deviceID: identity.deviceID, phase: .unbound, groupID: nil)
      try journal.replace(state)
    }
    self.journal = journal
    self.state = state
  }

  /// True authorizes only creation/resumption of the matching per-group INITIALIZING marker.
  /// Finish binding BEFORE any Cloud call; a bound intent never re-creates deleted group state.
  func beginBinding(groupID: String) throws -> Bool {
    guard !groupID.isEmpty, state.groupID == nil || state.groupID == groupID else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    if state.phase == .bound { return false }
    let next = State(deviceID: state.deviceID, phase: .binding, groupID: groupID)
    try journal.replace(next)
    state = next
    return true
  }

  func finishBinding(groupID: String) throws {
    guard state.groupID == groupID, state.phase != .unbound else {
      throw AppleDeviceError.stateRecoveryRequired
    }
    if state.phase == .bound { return }
    let next = State(deviceID: state.deviceID, phase: .bound, groupID: groupID)
    try journal.replace(next)
    state = next
  }

  func close() { journal.close() }
}
