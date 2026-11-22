import Foundation
import MemoshiDevice

/// A ready authority is never inferred to be a fresh one after missing local/cloud state.
/// This checkpoint contains no cloud credential and is encrypted under the device-only key.
/// Even explicit creation permission cannot replace an existing empty checkpoint.
actor CloudEnrollmentJournal {
  private struct Checkpoint: Codable {
    enum Phase: String, Codable { case initializing, ready }
    let groupID: String
    let phase: Phase
    let account: String?
  }

  nonisolated let wasReady: Bool
  nonisolated let boundAccount: String?
  private let journal: DeviceStateJournal
  private let groupID: String
  private var currentAccount: String?

  init(
    directory: URL, identity: DeviceIdentity, groupID: String, allowFirstEnrollment: Bool
  ) throws {
    let url = directory.appendingPathComponent("cloud-enrollment.jsonl")
    let existed = FileManager.default.fileExists(atPath: url.path)
    guard existed || allowFirstEnrollment else { throw AppleDeviceError.stateRecoveryRequired }
    let purpose = "com.memoshi.cloud.enrollment.v1"
    let journal = try DeviceStateJournal(
      url: url,
      key: identity.derivedStateEncryptionKey(purpose: purpose), purpose: purpose)
    let state: Checkpoint
    if let bytes = journal.takeRecovered().last {
      state = try JSONDecoder().decode(Checkpoint.self, from: bytes)
      guard state.groupID == groupID,
        (state.phase == .ready) == (state.account != nil)
      else {
        journal.close()
        throw AppleDeviceError.stateRecoveryRequired
      }
    } else {
      guard allowFirstEnrollment, !existed else {
        journal.close()
        throw AppleDeviceError.stateRecoveryRequired
      }
      state = Checkpoint(groupID: groupID, phase: .initializing, account: nil)
      try journal.replace(state)
    }
    if state.phase == .ready {
      for path in ["mailbox/cloudkit.jsonl", "authority/state-authority.jsonl"] {
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).path)
        else {
          journal.close()
          throw AppleDeviceError.stateRecoveryRequired
        }
      }
    }
    self.journal = journal
    self.groupID = groupID
    currentAccount = state.account
    wasReady = state.phase == .ready
    boundAccount = state.account
  }
  func ready(account: String) throws {
    guard !account.isEmpty, currentAccount == nil || currentAccount == account else {
      throw AppleDeviceError.accountChanged
    }
    try journal.replace(Checkpoint(groupID: groupID, phase: .ready, account: account))
    currentAccount = account
  }

  func close() { journal.close() }
}
