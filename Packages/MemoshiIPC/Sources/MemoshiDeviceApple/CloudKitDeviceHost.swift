import Foundation
import MemoshiDevice
import MemoshiProtocol

/// What ``CloudKitDeviceHost/eraseAfterRemoval()`` could not erase. Every other store was
/// erased; calling it again tries the rest.
public struct CloudRemovalErasureFailure: Error {
  /// One error for each store that could not be erased, in the order they were tried.
  public let failures: [any Error]
}

/// App/helper-owned composition for one real native device group. Keep this owner alive for
/// launch/wake/push/backstop fetching. It never authorizes itself, and init performs no I/O.
/// A newly scanned device resolves the target group only AFTER the authenticated Welcome has
/// installed that group; no account lookup is driven by an untrusted QR route hint alone.
public actor CloudKitDeviceHost {
  private struct Components: Sendable {
    let groupID: String
    let mailbox: CloudKitMailbox
    let spool: CloudMailboxStore
    let states: CloudKitStateAuthority
    let groups: CloudKitGroupAuthority
    let leases: CloudKitLeaseAuthority
    let feeds: CloudKitFeedAuthority
    let enrollment: CloudEnrollmentJournal
    let enrollmentIntent: CloudEnrollmentIntent
  }

  private let identity: DeviceIdentity
  private let group: DeviceGroup
  private let directory: URL
  private let maximumLeaseMilliseconds: Int64
  private let backstopSeconds: UInt64
  private var mayCreateEnrollmentIntent: Bool
  private var authorized = false
  private var generation = UUID()
  private var active: Components?
  private var opening: Task<Components, any Error>?
  private weak var node: DeviceNode?
  private var wakeTask: Task<Void, Never>?
  private var wakeSubscription: CloudFrameSubscription?
  private var processing: (UUID, Task<Void, any Error>)?
  private var backgroundRecoveryFailure: (any Error)?

  /// Retains the caller-owned identity/group and local journal directory without I/O or consent.
  /// Lease limits are milliseconds; the fetch backstop interval is seconds. First-enrollment
  /// permission only allows local intent creation, not CloudKit access or APNs registration.
  public init(
    identity: DeviceIdentity, group: DeviceGroup, directory: URL,
    maximumLeaseMilliseconds: Int64, backstopSeconds: UInt64 = 300,
    allowFirstEnrollment: Bool = false
  ) {
    self.identity = identity
    self.group = group
    self.directory = directory
    self.maximumLeaseMilliseconds = maximumLeaseMilliseconds
    self.backstopSeconds = backstopSeconds
    mayCreateEnrollmentIntent = allowFirstEnrollment
  }

  /// Called by the explicit identity-enrollment factory before returning the lab, not on
  /// Show/Scan. This only writes/resumes encrypted LOCAL intent; it performs no Cloud call.
  public func prepareEnrollmentIntent() async throws {
    let permit = mayCreateEnrollmentIntent
    mayCreateEnrollmentIntent = false
    let intent = try CloudEnrollmentIntent(
      directory: directory, identity: identity, allowCreation: permit)
    await intent.close()
  }

  /// Explicit signed-host/user opt-in only. This sets consent; the first requested operation
  /// performs the real CloudKit activation. It does not enroll an account or register APNs.
  public func authorizeCloudOperations() { authorized = true }

  /// Attaching a local owner is inert until explicit Cloud consent/activation. No caller-created
  /// plaintext receipt is trusted: the Node reopens its exact durable Native cache and executes
  /// its existing fenced/current-policy dispatch.
  public func attachNode(_ node: DeviceNode) async throws {
    guard node.group === group else {
      throw AppleDeviceError.invalidState("Cloud Node group owner")
    }
    self.node = node
    if authorized, active != nil { try await processRetainedInbox() }
  }

  /// Returns the retained background inbox failure, or the active mailbox's synchronization
  /// failure when none is retained. This observation does not activate CloudKit or retry recovery.
  public func recoveryFailure() async -> (any Error)? {
    if let backgroundRecoveryFailure { return backgroundRecoveryFailure }
    return await active?.mailbox.synchronizationFailure()
  }

  /// Revokes this owner's consent, cancels its work, and closes active cloud/local components.
  /// Durable journals are not deleted and the attached Node's group is not replaced.
  public func disable() async {
    authorized = false
    generation = UUID()
    opening?.cancel()
    opening = nil
    wakeTask?.cancel()
    wakeTask = nil
    processing?.1.cancel()
    processing = nil
    wakeSubscription = nil
    if let active {
      self.active = nil
      await Self.close(active)
    }
  }

  private static func close(_ components: Components) async {
    await components.mailbox.stop()
    await components.spool.close()
    await components.groups.close()
    await components.enrollment.close()
    await components.enrollmentIntent.close()
  }

  /// D133: once this device's removal from its group is verified (its own group state no
  /// longer lists it), stops the mailbox and every component and erases, also when they were
  /// not opened in this run, every store this host keeps for the group: the state
  /// authority's checkpoint (re-key plaintext and index pins), the spool
  /// (``CloudMailboxStore/erase()``: inbox, outbox, handled positions, engine state, fetch
  /// token, account binding) and the group's ``DeviceTransportStore`` in
  /// ``transportStoreDirectory()`` (``DeviceTransportStore/erase()``). Each is replaced without
  /// being read, so one that can no longer be read is erased as well. A store that cannot be
  /// erased now does not stop the others; ``CloudRemovalErasureFailure`` then lists it, and
  /// the next call tries it again. From then on no component opens for the group, so nothing
  /// is uploaded, fetched or woken for it again. A device that is still a member, also one a
  /// relay only refused, is left as it is. Repeating it is harmless.
  public func eraseAfterRemoval() async throws {
    guard await !isMember() else { return }
    let pending = opening
    await disable()
    // An opening that `disable()` cancelled may still hold the journals: it ends, and what it
    // opened is closed, before they are erased.
    if let components = try? await pending?.value { await Self.close(components) }
    let root = try await zoneDirectory()
    var failures: [any Error] = []
    do {
      try CloudKitStateAuthority.eraseRemovedState(
        directory: root.appendingPathComponent("authority", isDirectory: true),
        identity: identity)
    } catch { failures.append(error) }
    do {
      try CloudMailboxStore.eraseRemovedState(
        directory: root.appendingPathComponent("mailbox", isDirectory: true), identity: identity)
    } catch { failures.append(error) }
    do {
      try DeviceTransportStore.eraseRemovedState(
        directory: try await transportStoreDirectory(), identity: identity)
    } catch { failures.append(error) }
    guard failures.isEmpty else { throw CloudRemovalErasureFailure(failures: failures) }
  }

  /// Where the ``DeviceTransportStore`` of this host's group keeps its journal: in the
  /// group's own directory, beside its spool and state authority, so that
  /// ``eraseAfterRemoval()`` erases it with them (D133). Pass it as the store's `directory`.
  /// Performs no I/O and needs no consent.
  public func transportStoreDirectory() async throws -> URL {
    try await zoneDirectory().appendingPathComponent("transport", isDirectory: true)
  }

  /// The directory of this host's group: its stores live in it.
  private func zoneDirectory() async throws -> URL {
    let configuration = try CloudDeviceConfiguration(
      groupID: await group.groupID, backstopSeconds: backstopSeconds)
    return directory.appendingPathComponent(configuration.zoneName, isDirectory: true)
  }

  /// The same test as `DeviceNode.membership`: only a verified removal commit takes this device
  /// out of its own group state.
  private func isMember() async -> Bool {
    await group.members.contains { $0.deviceId == identity.deviceID }
  }

  /// Pass these methods as DeviceNode's groupCommit/groupSnapshot callbacks. The node applies
  /// the returned ordered commits itself, preserving its Native group ownership/checkpoints.
  public func compareAndSwap(_ commit: GroupCommit) async throws -> GroupCommitResult {
    let components = try await components(groupID: commit.groupId)
    return try await components.groups.compareAndSwap(commit: commit)
  }

  /// Pass as Node.groupDidCommit, after its Native checkpoint/gate release and before hello.
  public func didCommit(_ commit: GroupCommit) async throws {
    let components = try await components(groupID: commit.groupId)
    try await components.groups.didCommit(commit)
  }

  /// Resolves the consent-gated group authority and reads its ordered commit snapshot at or
  /// beyond `minimumEpoch`. Activation and authority errors propagate; this does not apply commits.
  public func snapshot(groupID: String, minimumEpoch: Int64) async throws -> AuthorityGroup {
    let components = try await components(groupID: groupID)
    return try await components.groups.snapshot(groupID: groupID, minimumEpoch: minimumEpoch)
  }

  /// Both callbacks are required by a Cloud-backed Node. Publication completes before ANY
  /// Noise/direct fanout; the epoch reader proves the closed immutable prior-epoch prefix.
  public func applicationSend(_ application: DeviceSealedApplication) async throws {
    let components = try await components(groupID: group.groupID)
    try await components.feeds.publish(application)
  }

  /// Reads the requested immutable application-epoch feed through the consent-gated authority.
  /// The caller remains responsible for applying the verified feed to its owned Native group.
  public func applicationFeedReader(_ request: DeviceApplicationEpochRequest) async throws
    -> DeviceApplicationEpochFeed
  {
    let components = try await components(groupID: request.groupID)
    return try await components.feeds.read(request)
  }

  /// Explicit Start Cloud Lab/launch of an already-enabled signed host, never normal app init.
  public func activateCurrentGroup() async throws {
    _ = try await components(groupID: group.groupID)
    try await active?.mailbox.flush()
    try await processRetainedInbox()
  }

  /// Fetches and flushes an already-active mailbox, then processes its retained inbox through
  /// the attached Node. Disabled/inactive state and synchronization or application failures throw.
  public func fetch(_ reason: CloudFetchReason) async throws {
    guard authorized, let active else { throw AppleDeviceError.disabled }
    try await active.mailbox.fetch(reason: reason)
    try await active.mailbox.flush()
    try await processRetainedInbox()
  }

  /// Uses a matching subscription hint only to trigger an authoritative mailbox fetch.
  /// Returns whether the hint was accepted; no push payload becomes application authority.
  public func receivedWake(_ hint: CloudWakeHint) async throws -> Bool {
    guard authorized, let active else { throw AppleDeviceError.disabled }
    let accepted = try await active.mailbox.receivedWake(hint)
    if accepted { try await processRetainedInbox() }
    return accepted
  }

  /// Returns this host's shared mailbox, activating components only with explicit cloud consent.
  /// The host retains lifecycle ownership; obtaining it can perform CloudKit I/O and throw.
  public func mailbox() async throws -> CloudKitMailbox {
    try await components(groupID: group.groupID).mailbox
  }

  /// Returns the shared encrypted local spool paired with this host's mailbox.
  /// Resolving inactive components requires consent and can perform CloudKit I/O.
  public func mailboxStore() async throws -> CloudMailboxStore {
    try await components(groupID: group.groupID).spool
  }

  /// Returns the shared conditional group-commit authority, resolving consent-gated components.
  /// The returned authority does not replace the Node's ownership of its local Native group.
  public func groupAuthority() async throws -> CloudKitGroupAuthority {
    try await components(groupID: group.groupID).groups
  }

  /// Returns the shared fenced-lease authority, resolving consent-gated components as needed.
  /// Activation errors propagate; merely obtaining it grants no execution lease.
  public func leaseAuthority() async throws -> CloudKitLeaseAuthority {
    try await components(groupID: group.groupID).leases
  }

  /// Returns the shared protected-state authority, resolving consent-gated components as needed.
  /// Its conditional cloud persistence remains separate from local Native group checkpoints.
  public func stateRecords() async throws -> CloudKitStateAuthority {
    try await components(groupID: group.groupID).states
  }

  private func components(groupID: String) async throws -> Components {
    guard authorized else { throw AppleDeviceError.disabled }
    // A removed device opens nothing for its former group (D133).
    guard await isMember() else { throw AppleDeviceError.revoked }
    guard await group.groupID == groupID else { throw AppleDeviceError.staleEpoch }
    if let active {
      guard active.groupID == groupID else { throw AppleDeviceError.staleEpoch }
      return active
    }
    if let opening {
      let token = generation
      let result = try await opening.value
      guard authorized, generation == token else { throw AppleDeviceError.disabled }
      return result
    }
    let token = generation
    let task = Task { try await self.open(groupID: groupID, generation: token) }
    opening = task
    // After disable() and a new authorization a later caller may already have registered its
    // own opening task; only this caller's registration is cleared.
    defer { if opening == task { opening = nil } }
    let result = try await task.value
    guard authorized, generation == token else {
      await Self.close(result)
      throw AppleDeviceError.disabled
    }
    active = result
    try await startWakeReader(result)
    return result
  }

  private func startWakeReader(_ components: Components) async throws {
    guard wakeTask == nil else { return }
    let subscription = try await components.mailbox.subscribe()
    wakeSubscription = subscription
    wakeTask = Task { [weak self] in
      do {
        for try await _ in subscription.frames {
          guard let self else { return }
          do { try await self.processRetainedInbox() } catch {
            await self.retainRecoveryFailure(error)
          }
        }
      } catch {
        await self?.retainRecoveryFailure(error)
      }
    }
  }

  private func retainRecoveryFailure(_ error: any Error) { backgroundRecoveryFailure = error }

  private func processRetainedInbox() async throws {
    guard authorized, let active, let node else { return }
    if let processing { return try await processing.1.value }
    let id = UUID()
    let task = Task { try await self.processRetainedInbox(active, node: node) }
    processing = (id, task)
    defer { if processing?.0 == id { processing = nil } }
    do {
      try await task.value
      backgroundRecoveryFailure = nil
    } catch {
      backgroundRecoveryFailure = error
      throw error
    }
  }

  /// The first step of every inbox pass: this device's own feed is brought to the authority
  /// and the authority's accepted feed to the group.
  ///
  /// Own seals advance this device's feed cursor when they are made, and catch-up refuses a
  /// cursor ahead of the authority, so what is still pending is published first. A frame whose
  /// epoch closed before the authority accepted it does not fail that flush. The membership
  /// read that follows is where the group reads the closed boundary and retires the frame's
  /// seal. The node then seals the retired messages it can rebuild again and publishes them
  /// through its sender, which is this host's `applicationSend`: that removes the retired
  /// frame from the outbox and uploads the new one. It comes before the catch-up because the
  /// new seal has advanced this device's cursor again. The pass holds nothing that the
  /// node's sender, snapshot reader or feed reader need.
  static func reconcileOwnFeed(
    node: DeviceNode, flush: @Sendable () async throws -> Void,
    reader: @escaping DeviceApplicationEpochReader
  ) async throws {
    try await flush()
    try await node.refreshMembership()
    try await node.publishPendingApplications()
    try await node.group.catchUpApplicationFeed(using: reader)
  }

  private func processRetainedInbox(_ components: Components, node: DeviceNode) async throws {
    try await Self.reconcileOwnFeed(
      node: node, flush: { try await components.mailbox.flush() },
      reader: { try await components.feeds.read($0) })
    let anchor = try await group.authorityAnchor()
    var held = false
    for frame in try await components.spool.incoming() {
      try Task.checkCancellation()
      let packet = try DeviceTransportPacket(decoding: frame.bytes)
      guard packet.header.groupID == components.groupID else {
        throw AppleDeviceError.conflictingReplay
      }
      if packet.groupEpoch < UInt64(anchor.epoch) {
        try await components.spool.acknowledgeIfRetained(frame.bytes)
        continue
      }
      let signer = try await components.groups.signer(packet.header.sender, at: packet.groupEpoch)
      try packet.verify(signer: signer)
      let hold = Self.hold(for: packet, local: identity.deviceID)
      if hold == .recovery {
        held = true
        continue
      }
      if signer.deviceID == identity.deviceID {
        guard try await group.applicationWasProcessed(ciphertext: packet.ciphertext) else {
          throw AppleDeviceError.stateRecoveryRequired
        }
        try await components.spool.acknowledgeIfRetained(frame.bytes)
        continue
      }
      // Ordered host envelopes belong to their explicit DeviceMessageApplying owner. Native
      // crypto consumption alone MUST NOT acknowledge that owner's business application.
      if hold == .transportOwner { continue }
      _ = try await group.openOrderedApplication(
        DeviceApplicationFeedDelivery(sender: signer, application: packet.application()))
      // The ordered Native open validates the entire Node AAD and its source routing.
      guard let recipient = packet.nativeRecipient else {
        held = true
        continue
      }
      if recipient != .group, recipient != .device(identity.deviceID) {
        try await group.acknowledgeOpened(ciphertext: packet.ciphertext)
        try await components.spool.acknowledgeIfRetained(frame.bytes)
        continue
      }
      switch try await node.receiveApplication(ciphertext: packet.ciphertext) {
      case .consumed: try await components.spool.acknowledgeIfRetained(frame.bytes)
      case .pendingRecovery: held = true
      }
    }
    if await components.spool.handledCoalescingDue {
      let native = try await group.handledPositionsCoalescing()
      try await components.spool.coalesceHandled(
        groupID: native.groupID, floor: native.floor, unconsumed: native.unconsumed)
    }
    if held { throw AppleDeviceError.stateRecoveryRequired }
  }

  /// Why this pass leaves a verified frame retained in the spool without consuming it.
  enum RetainedFrameHold: Equatable, Sendable {
    /// No consumer here can route it; the pass reports `stateRecoveryRequired`.
    case recovery
    /// A peer's ordered host envelope. Its DeviceApplicationTransport shares this spool and
    /// acknowledges the frame after the host applied it, so waiting for that owner is the
    /// normal state of a delivered message and not a failed pass.
    case transportOwner
  }

  static func hold(for packet: DeviceTransportPacket, local: DeviceID) -> RetainedFrameHold? {
    if packet.header.kind == .rawNative, packet.nativeRecipient == nil { return .recovery }
    if packet.header.sender == local { return nil }
    return packet.header.kind == .orderedTransport ? .transportOwner : nil
  }

  private func open(groupID: String, generation token: UUID) async throws -> Components {
    let configuration = try CloudDeviceConfiguration(
      groupID: groupID, backstopSeconds: backstopSeconds)
    let root = directory.appendingPathComponent(configuration.zoneName, isDirectory: true)
    let intent = try CloudEnrollmentIntent(
      directory: directory, identity: identity, allowCreation: false)
    var candidate: CloudEnrollmentJournal?
    do {
      let permit = try await intent.beginBinding(groupID: groupID)
      candidate = try CloudEnrollmentJournal(
        directory: root, identity: identity, groupID: groupID, allowFirstEnrollment: permit)
      try await intent.finishBinding(groupID: groupID)
    } catch {
      await candidate?.close()
      await intent.close()
      throw error
    }
    guard let enrollment = candidate else { throw AppleDeviceError.stateRecoveryRequired }
    let spool = try CloudMailboxStore(
      directory: root.appendingPathComponent("mailbox"), identity: identity)
    let mailbox = CloudKitMailbox(configuration: configuration, spool: spool)
    let groups = CloudKitGroupAuthority(
      mailbox: mailbox, group: group, identity: identity, groupID: groupID,
      stateDirectory: root.appendingPathComponent("authority"), spool: spool)
    do {
      try Task.checkCancellation()
      if enrollment.wasReady {
        guard try await spool.boundAccount() == enrollment.boundAccount else {
          throw AppleDeviceError.stateRecoveryRequired
        }
      }
      try await mailbox.activate(allowZoneCreation: !enrollment.wasReady)
      guard authorized, generation == token, await group.groupID == groupID else {
        throw AppleDeviceError.disabled
      }
      let anchor = try await group.authorityAnchor()
      if enrollment.wasReady {
        _ = try await groups.feedHead()  // Missing enrolled authority is never a new empty root.
      } else if anchor.epoch == 0, await group.epoch == 0 {
        try await groups.bootstrapIfAbsent()
      }
      let feeds = try await groups.applicationFeeds()
      try await mailbox.installFeedWriter(feeds)
      let states = try await groups.stateRecords()
      let leases = try CloudKitLeaseAuthority(
        group: group, identity: identity, states: states,
        maximumLeaseMilliseconds: maximumLeaseMilliseconds)
      try Task.checkCancellation()
      guard authorized, generation == token else { throw AppleDeviceError.disabled }
      guard let account = try await spool.boundAccount() else {
        throw AppleDeviceError.stateRecoveryRequired
      }
      try await enrollment.ready(account: account)
      return Components(
        groupID: groupID, mailbox: mailbox, spool: spool, states: states,
        groups: groups, leases: leases, feeds: feeds, enrollment: enrollment,
        enrollmentIntent: intent)
    } catch {
      await mailbox.stop()
      await spool.close()
      await groups.close()
      await enrollment.close()
      await intent.close()
      throw error
    }
  }
}
