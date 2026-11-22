import AppCore
import Foundation
import MemoshiDevice
import MemoshiDeviceApple
import MemoshiProtocol

/// Compile into the native app targets, never AppCore or IPC. The signed host constructs the
/// real DeviceNode with its durable identity and selected group authority before presenting UI.
/// Construction and local roster reads never activate CloudKit/APNs, relay or Bonjour.
public actor MemoshiDevicePairingHost: DevicePairingBackend {
  private let node: DeviceNode
  private nonisolated let book: PairingCodeBook
  private var localListener: Task<Void, any Error>?

  /// Retains the already constructed native node; it does not create keys or start a listener.
  public init(node: DeviceNode) {
    self.node = node
    book = node.book
  }

  /// Only the user's Show Pairing Code action calls this. The native host must declare camera
  /// and local-network usage, _memoshi._tcp, and retain the node for existing connections.
  public func showInvitation() async throws -> DevicePairingCode {
    // A full group issues no code and uses none up, so it does not advertise either: the code's
    // Bonjour hint needs the listener, and once started the listener stays with the node.
    // AppCore does not know the device layer, so the limit travels in the failure.
    guard await node.group.members.count < DeviceGroup.maximumMembers else {
      throw DevicePairingFailure.groupFull(limit: DeviceGroup.maximumMembers)
    }
    if localListener == nil {
      let node = node
      localListener = Task { _ = try await node.listenBonjour() }
    }
    do { try await localListener?.value } catch {
      localListener = nil
      throw Self.mapped(error, fallback: .unavailable)
    }
    try Task.checkCancellation()
    let invitation: PairingInvitation
    do { invitation = try await node.invite() } catch PairingRefusal.groupFull {
      // A device joined while the listener started.
      throw DevicePairingFailure.groupFull(limit: DeviceGroup.maximumMembers)
    }
    guard !invitation.hints.isEmpty else {
      book.void(invitation.codeID)
      throw DevicePairingFailure.unavailable
    }
    return try DevicePairingCode(
      id: invitation.codeID.base64EncodedString(), text: invitation.text,
      issuedAt: invitation.issuedAt, expiresAt: invitation.expiresAt)
  }

  /// No asynchronous hop: the Noise book is mutex-owned and invalidated before UI dismissal.
  public nonisolated func invalidateInvitation(id: String) {
    guard let codeID = Data(base64Encoded: id), codeID.count == 16 else { return }
    book.void(codeID)
  }

  /// Validates an unexpired scanned invitation and completes its authenticated native join.
  public func pair(scannedText: String) async throws -> DevicePairingPeer {
    let invitation: PairingInvitation
    do {
      invitation = try PairingInvitation(text: scannedText)
      _ = try DevicePairingCode(
        id: invitation.codeID.base64EncodedString(), text: scannedText,
        issuedAt: invitation.issuedAt, expiresAt: invitation.expiresAt)
    } catch { throw DevicePairingFailure.invalidCode }
    guard DeviceClock.wallMilliseconds() < invitation.expiresAt else {
      throw DevicePairingFailure.expired
    }
    do {
      let paired = try await node.pair(using: invitation)
      try Task.checkCancellation()
      let entry = paired.devices.devices.first { $0.deviceId == paired.peer.deviceID }
      return DevicePairingPeer(
        id: paired.peer.deviceID.rawValue,
        name: entry?.name.rawValue ?? paired.peer.deviceID.rawValue,
        platform: entry?.platform.rawValue ?? "")
    } catch PairingRefusal.expired { throw DevicePairingFailure.expired } catch PairingRefusal
      .groupFull
    {
      // The other device's group filled up after it showed its code.
      throw DevicePairingFailure.peerGroupFull(limit: DeviceGroup.maximumMembers)
    } catch is CancellationError { throw CancellationError() } catch {
      throw Self.mapped(error, fallback: .pairingFailed)
    }
  }

  /// Returns the local durable membership roster excluding this device, without network access.
  public func pairedDevices() async throws -> [DevicePairingPeer] {
    let ownID = node.identity.deviceID
    return await node.group.members.filter { $0.deviceId != ownID }.map {
      DevicePairingPeer(
        id: $0.deviceId.rawValue, name: $0.name.rawValue, platform: $0.platform.rawValue)
    }
  }

  /// Requests the node's authoritative revocation; cancellation and refusal remain failures.
  public func revoke(deviceID: String) async throws {
    do {
      try await node.revoke(DeviceID(deviceID))
    } catch is CancellationError { throw CancellationError() } catch {
      throw Self.mapped(error, fallback: .revocationFailed)
    }
  }

  fileprivate static func mapped(_ error: any Error, fallback: DevicePairingFailure)
    -> DevicePairingFailure
  {
    if let failure = error as? DevicePairingFailure { return failure }
    if let error = error as? AppleDeviceError, error == .stateRecoveryRequired {
      return .recoveryRequired
    }
    if let error = error as? DeviceApplicationFeedError {
      switch error {
      case .unavailable, .incompleteBoundary, .unacceptedOldEpoch, .missingPredecessor:
        return .recoveryRequired
      default: break
      }
    }
    return fallback
  }
}

/// Explicit identity selection for the device-link lab, never automatic replacement of a key.
public enum MemoshiPairingIdentityEnrollment: Sendable {
  /// Requires the existing device-only Keychain identity and its initialized local group state.
  case loadExisting
  /// Explicit user enrollment only; duplicate, locked or unavailable Keychain items are errors.
  /// An enrollment that then fails removes the identity it added and the state it wrote.
  case createNew(name: String, platform: DevicePlatform)
}

/// Native application/group ports backed by the explicitly selected CloudKit device host.
public struct MemoshiPairingAuthority: Sendable {
  /// Compares and swaps a group transition through the selected authority.
  public let commit: GroupCommitter
  /// Obtains authenticated membership at or beyond the requested minimum epoch.
  public let snapshot: @Sendable (String, Int64) async throws -> AuthorityGroup
  /// Completes the selected authority's post-commit work for the exact committed transition.
  public let didCommit: GroupCommitCompletion
  /// Publishes the exact native sender record before any carrier exposes it.
  public let applicationSend: DeviceApplicationSender
  /// Reads authenticated ordered native sender records and their epoch boundary.
  public let applicationFeedReader: DeviceApplicationEpochReader
  private let bindNode: @Sendable (DeviceNode) async throws -> Void
  private let shutdown: @Sendable () async -> Void
  private let prepareEnrollment: @Sendable () async throws -> Void
  private let eraseRemoved: @Sendable () async throws -> Void

  /// The signed UI authorizes the host separately. Constructing these ports does not activate
  /// an account, register APNs or start a listener, and supplies no fallback/no-op authority.
  public init(cloud: CloudKitDeviceHost) {
    commit = { try await cloud.compareAndSwap($0) }
    snapshot = { try await cloud.snapshot(groupID: $0, minimumEpoch: $1) }
    didCommit = { try await cloud.didCommit($0) }
    applicationSend = { try await cloud.applicationSend($0) }
    applicationFeedReader = { try await cloud.applicationFeedReader($0) }
    bindNode = { try await cloud.attachNode($0) }
    shutdown = { await cloud.disable() }
    prepareEnrollment = { try await cloud.prepareEnrollmentIntent() }
    eraseRemoved = { try await cloud.eraseAfterRemoval() }
  }

  /// Connects the node to the already selected host without substituting an authority.
  public func attach(_ node: DeviceNode) async throws { try await bindNode(node) }
  /// Checkpoints the host's unbound enrollment intent before opening its native node.
  public func prepare() async throws { try await prepareEnrollment() }
  /// Disables only this authority host and its owned link/push work.
  public func close() async { await shutdown() }
  /// D133: after this device's verified removal, stops the host for the group and erases its
  /// local transport spool; does nothing for a member.
  public func eraseAfterRemoval() async throws { try await eraseRemoved() }
}

/// The lab's device-only Keychain behind the four calls the enrollment rules make.
private struct LabKeychain: DeviceEnrollmentKeychain {
  let keychain: DeviceIdentityKeychain
  let enrollment: MemoshiPairingIdentityEnrollment

  func load() async throws -> DeviceIdentity { try await keychain.load() }

  func create() async throws -> DeviceIdentity {
    guard case .createNew(let name, let platform) = enrollment else {
      throw DevicePairingFailure.unavailable
    }
    return try await keychain.create(name: name, platform: platform)
  }

  func completeEnrollment() async throws { try await keychain.completeEnrollment() }
  func removeUnenrolled() async throws { try await keychain.removeUnenrolled() }
}

/// The node's own view of its removal, for AppCore's `DeviceRemovalErasure`.
private struct NodeRemoval: RemovedDeviceSource {
  let node: DeviceNode

  func isRemoved() async -> Bool { await node.membership == .removed }

  func finishDeletion() async -> Bool {
    // A removed node's recovery finishes deleting what it held, then refuses (`unknownPeer`).
    try? await node.recover()
    return await node.deletedRemovedData
  }
}

/// The lab's in-memory conversation store, which holds what the node wrote for the group.
private struct ReceivedConversations: GroupReceivedStore {
  let store: MemoryConversationStore

  func eraseReceivedData() async throws { await store.erase() }
}

/// The selected authority's local transport spool, which holds frames received or to be sent
/// through the group.
private struct ReceivedTransportFrames: GroupReceivedStore {
  let authority: MemoshiPairingAuthority

  func eraseReceivedData() async throws { try await authority.eraseAfterRemoval() }
}

/// The native development entry owns this lifetime. It is a device-link laboratory, not a
/// daemon/Pi store host; the caller must describe the injected ConversationStore honestly.
public struct MemoshiPairingLabSession: Sendable, DeviceEnrollmentSession {
  /// The device-only identity loaded or explicitly enrolled for this lab.
  public let identity: DeviceIdentity
  /// The native group and its encrypted local checkpoint/receipt owner.
  public let group: DeviceGroup
  /// The owned device-link node; its injected store is not implicitly a Pi replica.
  public let node: DeviceNode
  /// Native pairing/revocation operations exposed to the lab's explicit UI actions.
  public let backend: MemoshiDevicePairingHost
  private let authority: MemoshiPairingAuthority?
  /// D133: what this device deletes once its removal from the group is verified.
  private let removal: DeviceRemovalErasure

  /// Call only from explicit Start/Open Lab. No automatic identity fallback, account lookup,
  /// cloud/relay activation, push registration, camera access or network listener is performed.
  public static func open(
    enrollment: MemoshiPairingIdentityEnrollment, validatedAccessGroup: String,
    directory: URL, store: @Sendable (DeviceIdentity) async throws -> MemoryConversationStore,
    authority: (
      @Sendable (DeviceGroup, DeviceIdentity, Bool) async throws -> MemoshiPairingAuthority
    )? = nil
  ) async throws -> MemoshiPairingLabSession {
    guard directory.isFileURL else { throw DevicePairingFailure.unavailable }
    let keychain = try DeviceIdentityKeychain(
      accessGroup: validatedAccessGroup, account: "device-pairing-lab")
    // The rules of a first enrollment and of opening it again are AppCore's
    // `DeviceFirstEnrollment`; this supplies the Keychain, the directory and the assembly.
    let rules = DeviceFirstEnrollment(
      keychain: LabKeychain(keychain: keychain, enrollment: enrollment),
      files: DeviceEnrollmentDirectory(directory),
      failure: { MemoshiDevicePairingHost.mapped($0, fallback: .unavailable) })
    let request: DeviceEnrollmentRequest
    switch enrollment {
    case .loadExisting: request = .loadExisting
    case .createNew: request = .createNew
    }
    return try await rules.open(request) { identity, firstEnrollment in
      try await assemble(
        identity: identity, createdNewIdentity: firstEnrollment, directory: directory,
        store: store, authority: authority)
    }
  }

  /// Opens the group, the selected authority and the node for `identity`; on failure it closes
  /// what it opened, so that no journal lock outlives the attempt. A device removed from its
  /// group opens no session: it deletes what it received and throws
  /// `DevicePairingRemovedFromGroup` with the deletion's outcome.
  private static func assemble(
    identity: DeviceIdentity, createdNewIdentity: Bool, directory: URL,
    store: @Sendable (DeviceIdentity) async throws -> MemoryConversationStore,
    authority: (
      @Sendable (DeviceGroup, DeviceIdentity, Bool) async throws -> MemoshiPairingAuthority
    )?
  ) async throws -> MemoshiPairingLabSession {
    // A first enrollment is not interrupted between its Keychain add and the node's durable
    // group and replica state: it would only have to be removed again. The caller closes a
    // session whose opening was cancelled.
    if !createdNewIdentity { try Task.checkCancellation() }
    let localStore = try await store(identity)
    if !createdNewIdentity { try Task.checkCancellation() }
    let group: DeviceGroup
    do {
      group = try DeviceGroup(
        identity: identity, directory: directory.appendingPathComponent("membership"))
    } catch { throw Self.restoreFailure(error) }
    // The same test as `DeviceNode.membership`: only a verified removal commit leaves this
    // device out of its own checkpointed roster.
    if await !group.members.contains(where: { $0.deviceId == identity.deviceID }) {
      // The authority is constructed only so that its local state can be erased. It is not
      // prepared or attached, and the node that runs the deletion gets none of its callbacks, so
      // no group operation or CloudKit call runs. The lab's closure still records Cloud consent
      // in memory (`authorizeCloudOperations`); the erase disables the host, which withdraws that
      // consent, before it deletes the host's local state checkpoint and spool.
      let removedAuthority: MemoshiPairingAuthority?
      do { removedAuthority = try await authority?(group, identity, createdNewIdentity) } catch {
        await group.close()
        throw Self.restoreFailure(error)
      }
      let failure = await finishRemoval(
        identity: identity, store: localStore, authority: removedAuthority, group: group,
        directory: directory)
      await removedAuthority?.close()
      throw failure
    }
    var selectedAuthority: MemoshiPairingAuthority?
    var node: DeviceNode?
    do {
      do { _ = try await group.groupInfo() }  // Local Native checkpoint only; no network.
      catch { throw Self.restoreFailure(error) }
      selectedAuthority = try await authority?(group, identity, createdNewIdentity)
      try await selectedAuthority?.prepare()
      let created = try DeviceNode(
        identity: identity, store: localStore, group: group,
        groupCommit: selectedAuthority?.commit, groupSnapshot: selectedAuthority?.snapshot,
        groupDidCommit: selectedAuthority?.didCommit,
        applicationSend: selectedAuthority?.applicationSend,
        applicationFeedReader: selectedAuthority?.applicationFeedReader,
        directory: directory)
      node = created
      try await selectedAuthority?.attach(created)
      return MemoshiPairingLabSession(
        identity: identity, group: group, node: created,
        backend: MemoshiDevicePairingHost(node: created), authority: selectedAuthority,
        removal: removalErasure(node: created, store: localStore, authority: selectedAuthority))
    } catch {
      await selectedAuthority?.close()
      // A node owns the group and its own journals once it exists.
      if let node { await node.stopAndWait() } else { await group.close() }
      if error is CancellationError { throw CancellationError() }
      throw MemoshiDevicePairingHost.mapped(error, fallback: .unavailable)
    }
  }

  /// The removed device's node, opened without any authority only to finish its deletion; the
  /// lab's own store and the authority's transport spool are erased too. Returns
  /// `DevicePairingRemovedFromGroup` with the deletion's outcome.
  private static func finishRemoval(
    identity: DeviceIdentity, store: MemoryConversationStore,
    authority: MemoshiPairingAuthority?, group: DeviceGroup, directory: URL
  ) async -> any Error {
    let node: DeviceNode
    do {
      node = try DeviceNode(identity: identity, store: store, group: group, directory: directory)
    } catch {
      // The group already shows the removal; the deletion is retried with a fresh node.
      await group.close()
      return DevicePairingRemovedFromGroup(deletion: .incomplete)
    }
    let outcome = await removalErasure(node: node, store: store, authority: authority).check()
    await node.stopAndWait()
    // The removal is verified: it is told also while a deletion is still incomplete.
    return DevicePairingRemovedFromGroup(deletion: outcome == .deleted ? .deleted : .incomplete)
  }

  private static func removalErasure(
    node: DeviceNode, store: MemoryConversationStore, authority: MemoshiPairingAuthority?
  ) -> DeviceRemovalErasure {
    let stores: [any GroupReceivedStore] =
      [ReceivedConversations(store: store)]
      + (authority.map { [ReceivedTransportFrames(authority: $0)] } ?? [])
    return DeviceRemovalErasure(device: NodeRemoval(node: node), stores: stores)
  }

  /// Waits for the node's notice of this device's verified removal, runs the deletion once and
  /// returns its outcome (`.deleted` or `.incomplete`) as soon as the removal is verified; nil
  /// when the node stopped first or the waiting task was cancelled. The node has one event
  /// stream: call this once.
  public func removalVerified() async -> DeviceRemovalOutcome? {
    for await event in node.events
    where event.kind == "removedFromGroup" || event.kind == "removedDataDeleted" {
      let outcome = await removal.check()
      if outcome != .member { return outcome }
    }
    return nil
  }

  private static func restoreFailure(_ error: any Error) -> DevicePairingFailure {
    if let error = error as? DevicePairingFailure { return error }
    return .recoveryRequired
  }

  /// Disables the owned authority host and drains/stops the lab node without deleting identity.
  public func close() async {
    await authority?.close()
    await node.stopAndWait()
  }

  /// Deliberately separate from the existing prototype and text-chat stores. On iOS this is
  /// inside the app's container. Existing roots are never deleted, migrated or chmodded here.
  public static func privateLabDirectory() throws -> URL {
    try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true
    )
    .appendingPathComponent("Memoshi Development/Device Pairing Lab", isDirectory: true)
  }
}
