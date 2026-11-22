import Foundation
import MemoshiProtocol
import Network

/// One observation the node reports, stamped with system-wide monotonic nanoseconds so that
/// observations from several processes on one Mac can be joined (replica lag, hand-over time).
public struct NodeEvent: Codable, Hashable, Sendable {
  /// What happened, such as `committed`, `applied`, `fenced` or `granted`.
  public var kind: String
  /// When, in ``DeviceClock/monotonicNanoseconds()``.
  public var at: UInt64
  /// The conversation, if any.
  public var conversation: String?
  /// The lease epoch involved.
  public var epoch: Int64?
  /// The replication sequence involved.
  public var rseq: Int64?
  /// The other device involved.
  public var peer: String?
  /// The link route involved.
  public var route: String?
  /// Free-form detail, such as a grant reason or an error.
  public var detail: String?
}

/// Whether this device is still in its group, as its own native group state shows.
public enum DeviceGroupMembership: String, Codable, Hashable, Sendable {
  /// The device is in its group's roster.
  case member
  /// A commit that removes this device was applied to the group state it holds: it can no
  /// longer read or write the group. Survives a restart.
  case removed
}

/// Reads authenticated ordered commits after the caller's durable native MLS epoch.
public typealias GroupSnapshotReader = @Sendable (String, Int64) async throws -> AuthorityGroup

/// One device's real MLS links and fenced local conversation replicas. Optional encrypted
/// journals preserve native secrets, replicas and uncertain publication. Membership may use
/// an explicitly selected CloudKit adapter; conversation store/lease authority is separate.
public actor DeviceNode {
  /// This device.
  public nonisolated let identity: DeviceIdentity
  /// This device's view of the device group.
  public nonisolated let group: DeviceGroup
  /// One-time pairing codes this device shows.
  public nonisolated let book = PairingCodeBook()
  /// Everything the node observes, in order.
  public nonisolated let events: AsyncStream<NodeEvent>
  private let sink: AsyncStream<NodeEvent>.Continuation
  private let store: any ConversationStore
  private let now: @Sendable () -> Int64
  private let commitMembership: GroupCommitter?
  private let readMembership: GroupSnapshotReader?
  private let membershipDidCommit: GroupCommitCompletion?
  private let sendApplication: DeviceApplicationSender?
  private let readApplicationFeed: DeviceApplicationEpochReader?
  private let sendingApplications = SerialGate()
  /// How many tasks wait for the node's send gate; for tests that order work around it.
  nonisolated var sendGateWaiters: Int { sendingApplications.waiting }
  private let applicationRecoveryGate = SerialGate()
  private var requiresRecovery = false
  /// Restored conversations whose history and fence are not yet reconciled with the authority.
  /// Each is held on its own: leases are per conversation, so one that cannot reconcile never
  /// holds the others.
  private var unreconciled: Set<ConversationID> = []
  private enum Lifecycle {
    case running
    case stopping(Task<Void, Never>)
    case stopped
  }

  private var lifecycle = Lifecycle.running
  private var stopping: Bool {
    if case .running = lifecycle { return false }
    return true
  }
  private var membershipRevoked = false
  /// Whether `removedFromGroup` was reported in this run.
  private var removalReported = false
  /// Whether a removal reading runs: one at a time.
  private var readingRemoval = false
  /// Whether this node deleted, after a verified removal, what it held for the group; from
  /// then on its replica journal takes no record.
  private var removalErased = false
  /// Runs where reporting a verified removal waits; tests use it to hold that report while
  /// another caller asks for the removal.
  nonisolated let beforeRemovalReport = Locked<(@Sendable () async -> Void)?>(nil)

  private enum Role: String {
    case replica
    case runner
    case handingOver
  }

  private struct Conversation {
    var epoch: Int64 = 0
    var runner: DeviceID?
    var expiresAt: Int64?
    var role = Role.replica
    var heldEpoch: Int64?
    /// The lease length this runner claimed; its renewals extend by the same length.
    var leaseTTL: Int64?
    var lastRseq: Int64 = 0
    var catchUpAfterRseq: Int64?
    var log: [ReplicaChange] = []
    var pending: [Int64: (ReplicaChange, DeviceID)] = [:]
    var receipts: [ULID: MessageForwardResult] = [:]
    var identities: [Int64: String] = [:]
    var publication: (operationID: ULID, change: ReplicaChange)?
    /// A reservation under which this node's store wrote nothing: the store was not called,
    /// or refused the commit before writing. Its release is repeated until the authority
    /// confirms it.
    var abandoned: ULID?
  }

  private struct InboxItem {
    var receipt: GroupApplicationReceipt
    var message: DeviceMessage
    var sender: DeviceID
  }

  private struct DeferredForwardResult {
    var acknowledge: @Sendable () async throws -> Void
    var result: MessageForwardResult
  }

  private struct ReplicaAcknowledgement {
    var digest: String
    var acknowledge: @Sendable () async throws -> Void
  }

  private enum JournalRecord: Codable, Sendable {
    case lease(LeaseRecord, heldEpoch: Int64?)
    case publication(ULID, ReplicaChange)
    case change(ReplicaChange)
    case abandoned(ConversationID, ULID?)
    /// Set before a reservation is requested and cleared before the store is called for it.
    case reserving(ConversationID, ULID?)
    /// The device was removed from its group and deleted what it held for it: the only record
    /// of a replica journal it rewrote. It carries no group content.
    case removed
  }

  /// Every replica-journal append runs on this writer's lane, in decision order.
  nonisolated let journalWriter: OrderedJournalWriter?
  private var persistenceFailed = false

  private var links: [DeviceID: [LinkRoute: DeviceLink]] = [:]
  private nonisolated let handlers = PendingDeviceHandlers()
  private var relay: RelayClient?
  private var relayEndpoint: (host: String, port: Int)?
  private var listener: TCPFrameListener?
  private var bonjourListener: DeviceBonjourListener?
  private var conversations: [ConversationID: Conversation] = [:]
  private var seen = MessageWindow(capacity: 200_000)
  private var forwardWaiters: [ULID: [UUID: CheckedContinuation<MessageForwardResult, any Error>]] =
    [:]
  private var deferredResults: [ConversationID: [ULID: [DeferredForwardResult]]] = [:]
  private var admissions: [ULID: Task<MessageForwardResult, any Error>] = [:]
  private var replicaAcknowledgements: [ConversationID: [Int64: [ReplicaAcknowledgement]]] = [:]
  private var grantWaiters: [ConversationID: [UUID: CheckedContinuation<Int64, any Error>]] = [:]
  private var renewals: [ConversationID: Task<Void, Never>] = [:]
  /// The last store lease write issued per conversation; each new one runs after it.
  private var leaseWrites: [ConversationID: Task<Void, any Error>] = [:]
  private var gates: [ConversationID: SerialGate] = [:]
  /// The node's attempt to finish a pending membership completion, shared by every send that
  /// arrives while it runs; failed attempts since the last success, for which pending
  /// completion, and from when (`now()` milliseconds) the next one may run.
  private var completionAttempt: Task<Bool, Never>?
  private var completionFailures = 0
  private var completionFailedFor: GroupCommit?
  private var completionFailedAt: Int64 = 0
  private var completionRetryAt: Int64 = 0
  /// How many answer changes the runner commits after admitting a forwarded message.
  private var answerChunks = 3
  /// The lease length the node uses for claims it makes on its own (hand-over, take-over).
  private var leaseMilliseconds: Int64 = 10_000
  private var renewMilliseconds: Int64 = 3_000
  /// How many changes each conversation keeps for catch-up.
  private let logLimit = 4_096

  /// Creates the node for `identity` over `store`.
  public init(
    identity: DeviceIdentity, store: any ConversationStore, group: DeviceGroup? = nil,
    groupCommit: GroupCommitter? = nil, groupSnapshot: GroupSnapshotReader? = nil,
    groupDidCommit: GroupCommitCompletion? = nil,
    applicationSend: DeviceApplicationSender? = nil,
    applicationFeedReader: DeviceApplicationEpochReader? = nil, directory: URL? = nil,
    now: @escaping @Sendable () -> Int64 = { DeviceClock.wallMilliseconds() }
  ) throws {
    guard (groupCommit == nil) == (groupSnapshot == nil),
      groupDidCommit == nil || groupCommit != nil,
      (applicationSend == nil) == (applicationFeedReader == nil),
      groupCommit == nil || applicationSend != nil
    else {
      throw DeviceLayerError.invalid("membership authority callbacks must be selected together")
    }
    if let group {
      guard group.localPeer == identity.peer,
        group.stateDirectory?.standardizedFileURL
          == directory?.appendingPathComponent("membership").standardizedFileURL
      else { throw DeviceLayerError.invalid("external native group identity or state directory") }
    }
    if let directory {
      let membership = directory.appendingPathComponent("membership")
      let membershipExists = FileManager.default.fileExists(
        atPath: membership.appendingPathComponent("group.jsonl").path)
      let replicasExist = FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("replicas/replicas.jsonl").path)
      let membershipRestored = group.map(\.wasRestored) ?? membershipExists
      // A first launch that stopped between the two stores journaled nothing, and its
      // membership checkpoint still carries the first-launch marker. Without that marker a
      // missing half is lost history.
      guard
        membershipRestored == replicasExist
          || (membershipRestored && !replicasExist && DeviceGroup.isFirstLaunch(in: membership))
      else {
        throw DeviceLayerError.invalid("incomplete durable device state")
      }
    }
    self.identity = identity
    if let group {
      self.group = group
    } else {
      self.group = try DeviceGroup(
        identity: identity, directory: directory.map { $0.appendingPathComponent("membership") })
    }
    commitMembership = groupCommit
    readMembership = groupSnapshot
    membershipDidCommit = groupDidCommit
    sendApplication = applicationSend
    readApplicationFeed = applicationFeedReader
    self.store = store
    self.now = now
    (events, sink) = AsyncStream.makeStream(of: NodeEvent.self, bufferingPolicy: .unbounded)
    journalWriter = try directory.map {
      OrderedJournalWriter(
        journal: try DeviceStateJournal(
          url: $0.appendingPathComponent("replicas/replicas.jsonl"),
          key: identity.stateEncryptionKey(), purpose: "memoshi.replica-state.v1"))
    }
    for bytes in journalWriter?.takeRecovered() ?? [] {
      switch try JSONDecoder().decode(JournalRecord.self, from: bytes) {
      case .lease(let lease, let heldEpoch):
        var state = conversations[lease.conversationID] ?? Conversation()
        let adopted = try LeaseRules.adopt(
          lease,
          over: state.epoch == 0
            ? nil
            : LeaseRecord(
              conversationID: lease.conversationID, epoch: state.epoch, runner: state.runner,
              expiresAt: state.expiresAt))
        state.epoch = adopted.epoch
        state.runner = adopted.runner
        state.expiresAt = adopted.expiresAt
        state.heldEpoch = heldEpoch ?? state.heldEpoch
        // Reopen never restores execution authority. A fresh authority CAS/reconciliation is required.
        state.role = .replica
        conversations[lease.conversationID] = state
      case .publication(let operationID, let change):
        conversations[change.conversationId, default: Conversation()].publication = (
          operationID, change
        )
      case .abandoned(let conversation, let operationID):
        conversations[conversation, default: Conversation()].abandoned = operationID
      case .reserving(let conversation, let operationID):
        // A journal that ends with this set was written by a process that asked for the
        // reservation and stopped before its store was called: the operation is abandoned.
        conversations[conversation, default: Conversation()].abandoned = operationID
      case .change(let change):
        let state = conversations[change.conversationId] ?? Conversation()
        guard change.rseq == state.lastRseq + 1 else {
          throw DeviceLayerError.invalid("durable replica sequence")
        }
        conversations[change.conversationId] = Self.appending(
          change, digest: try change.committedDigest(), to: state, logLimit: logLimit)
      case .removed:
        conversations.removeAll()
        removalErased = true
        membershipRevoked = true
      }
    }
    if let directory {
      try DeviceGroup.finishFirstLaunch(in: directory.appendingPathComponent("membership"))
    }
    requiresRecovery = self.group.wasRestored
    unreconciled = Set(conversations.keys)
  }

  /// Sets the lease timing for claims the node makes itself and for renewals it starts.
  public func configure(
    leaseMilliseconds: Int64, renewMilliseconds: Int64, answerChunks: Int = 3
  ) {
    self.leaseMilliseconds = leaseMilliseconds
    self.renewMilliseconds = renewMilliseconds
    self.answerChunks = answerChunks
  }

  // MARK: - Listening, pairing and links

  /// Listens on loopback for pairing attempts and direct links; returns the port.
  public func listen(port: Int = 0) async throws -> Int {
    guard !stopping else { throw DeviceLayerError.closed }
    let listener = try await TCPFrameListener.bind(port: port) { [weak self] channel in
      guard let self else { return channel.close() }
      self.handlers.start(channel: channel) { [weak self] identifier in
        await self?.acceptDirect(channel, identifier: identifier)
      }
    }
    guard !stopping else {
      await listener.close()
      throw DeviceLayerError.closed
    }
    let previous = self.listener
    self.listener = listener
    await previous?.close()
    guard !stopping else { throw DeviceLayerError.closed }
    return listener.port
  }

  /// Opts into a real LAN listener/discovery advertisement. The containing signed host must
  /// supply its local-network usage/Bonjour declarations and explicitly start this listener.
  public func listenBonjour() async throws -> Int {
    guard !stopping else { throw DeviceLayerError.closed }
    guard bonjourListener == nil else {
      throw DeviceLayerError.invalid("Bonjour already listening")
    }
    let listener = try await DeviceBonjourListener.start(name: identity.deviceID.rawValue) {
      [weak self] channel in
      guard let self else { return channel.close() }
      self.handlers.start(channel: channel) { [weak self] identifier in
        await self?.acceptDirect(channel, identifier: identifier)
      }
    }
    guard !stopping else {
      listener.close()
      throw DeviceLayerError.closed
    }
    bonjourListener = listener
    return listener.port
  }

  /// Shows a new pairing code for this device's direct listener. A group that already has
  /// ``DeviceGroup/maximumMembers`` devices shows none (``PairingRefusal/groupFull``), so no
  /// code is used up on a pairing that cannot succeed.
  public func invite() async throws -> PairingInvitation {
    guard await group.members.count < DeviceGroup.maximumMembers else {
      throw PairingRefusal.groupFull
    }
    var hints = listener.map { ["tcp:127.0.0.1:\($0.port)"] } ?? []
    hints.append("group:\(await group.groupID)")
    if bonjourListener != nil { hints.append("bonjour:\(identity.deviceID.rawValue)") }
    if let endpoint = relayEndpoint {
      var address = URLComponents()
      address.scheme = "relay"
      address.host = endpoint.host
      address.port = endpoint.port
      if let url = address.string { hints.append(url) }
    }
    return book.issue(for: identity, hints: hints, at: now())
  }

  /// Joins the device group of the device that showed `invitation`, over its direct hint.
  public func pair(using invitation: PairingInvitation) async throws -> PairingResult {
    guard !stopping else { throw DeviceLayerError.closed }
    let pending = Locked<(any FrameChannel)?>(nil)
    guard conversations.isEmpty else {
      throw DeviceLayerError.invalid("existing device history requires an explicit group migration")
    }
    return try await withTaskCancellationHandler {
      do {
        let channel: any FrameChannel
        if let hint = invitation.hints.first(where: { $0.hasPrefix("bonjour:") }) {
          channel = try await NetworkDeviceFrameChannel.connect(
            endpoint: .service(
              name: String(hint.dropFirst(8)), type: DeviceBonjourBrowser.serviceType,
              domain: "local.", interface: nil))
        } else if let hint = invitation.hints.first(where: { $0.hasPrefix("tcp:") }),
          let address = URLComponents(string: "tcp://" + String(hint.dropFirst(4))),
          let host = address.host, let port = address.port
        {
          channel = try await TCPFrameChannel.connect(host: host, port: port)
        } else {
          throw DeviceLayerError.invalid("no direct hint in the pairing code")
        }
        pending.withLock { $0 = channel }
        try Task.checkCancellation()
        let result = try await PairingExchange.join(
          invitation: invitation, identity: identity, group: group, channel: channel,
          beforeApplication: prepareApplicationEpoch, now: now)
        if readMembership == nil, relay == nil,
          let hint = invitation.hints.first(where: { $0.hasPrefix("relay://") }),
          let address = URLComponents(string: hint), let host = address.host,
          let port = address.port
        {
          try await connectRelay(host: host, port: port)
        }
        try await refreshMembership()
        try await register(result.link)
        pending.withLock { $0 = nil }
        return result
      } catch {
        pending.withLock { $0?.close() }
        throw error
      }
    } onCancel: {
      pending.withLock { $0?.close() }
    }
  }

  /// Opens a direct link to a paired device.
  public func connect(to peer: DevicePeer, host: String = "127.0.0.1", port: Int) async throws {
    try await requireMember(peer)
    let channel = try await TCPFrameChannel.connect(host: host, port: port)
    try await register(
      try await DeviceLink.initiate(
        identity: identity, peer: peer, group: group, route: .direct, channel: channel,
        beforeApplication: prepareApplicationEpoch))
  }

  /// Connects an untrusted discovered route only after fresh membership/Noise verification.
  public func connect(to peer: DevicePeer, endpoint: NWEndpoint) async throws {
    try await requireMember(peer)
    let channel = try await NetworkDeviceFrameChannel.connect(endpoint: endpoint)
    try await register(
      try await DeviceLink.initiate(
        identity: identity, peer: peer, group: group, route: .direct, channel: channel,
        beforeApplication: prepareApplicationEpoch))
  }

  /// Connects to the relay, which also carries the lease authority. A device whose removal it
  /// has installed connects to nothing: it finishes its deletion and throws `unknownPeer`.
  public func connectRelay(host: String = "127.0.0.1", port: Int) async throws {
    guard !stopping else { throw DeviceLayerError.closed }
    if await membership == .removed {
      await reportRemoval()
      throw DeviceLayerError.unknownPeer
    }
    relayEndpoint = (host, port)
    let client = try await RelayClient.connect(
      host: host, port: port, identity: identity,
      onMembership: { [weak self] snapshot in
        self?.handlers.start { [weak self] _ in await self?.membershipChanged(snapshot) }
      },
      onApplication: { [weak self] groupID, epoch in
        self?.handlers.start { [weak self] _ in
          await self?.applicationChanged(groupID: groupID, epoch: epoch)
        }
      },
      onRemoved: { [weak self] in
        self?.handlers.start { [weak self] _ in _ = await self?.readRemoval(reconnecting: true) }
      },
      onIncoming: { [weak self] stream in
        guard let self else { return stream.close() }
        self.handlers.start(channel: stream) { [weak self] identifier in
          await self?.acceptRelay(stream, identifier: identifier)
        }
      })
    guard !stopping else {
      client.close()
      throw DeviceLayerError.closed
    }
    relay?.close()
    relay = client
    if client.isRemovalReading { try await requireRemovalProof() }
  }

  /// Reconciles reopened journals with the live authority. Only an unexpired, still-owned
  /// epoch with every exact committed payload may resume writing; a released epoch never does.
  /// A device whose removal was installed finishes deleting what it held and throws
  /// `unknownPeer`.
  public func recover() async throws {
    if await membership == .removed {
      await reportRemoval()
      throw DeviceLayerError.unknownPeer
    }
    guard !persistenceFailed, !stopping, !membershipRevoked else {
      throw DeviceLayerError.io("device state unavailable")
    }
    try await publishPendingApplications()
    try await refreshMembership()
    try await group.recoverPendingCommit(
      using: groupCommitter, applicationFeedReader: applicationFeedReader)
    try await group.completeCommittedMembership(using: membershipDidCommit)
    try await deliverPendingHello()
    try await catchUpPublishedApplications()
    try await group.recoverJoinCompletion()
    let inbox = try await recoverIncomingReplicas()
    var failure = inbox.failure
    for conversation in Array(conversations.keys) {
      let gate = gate(for: conversation)
      await gate.acquire()
      do {
        try await recoverPublication(conversation)
        let trusted = try await authorityState(conversation)
        try await reconcile(conversation, against: trusted)
        let local = conversations[conversation]
        let mayResume =
          local?.runner == identity.deviceID && local?.heldEpoch == trusted.epoch
          && trusted.runner == identity.deviceID && (trusted.expiresAt ?? 0) > now()
        await observe(leaseRecord(conversation, from: trusted))
        if mayResume {
          let resumed = lease(of: conversation)
          try await leaseWrite(conversation) { try await $0.adoptLease(resumed, at: $1) }
          conversations[conversation]?.role = .runner
        }
        unreconciled.remove(conversation)
        emit(
          "recovered", conversation: conversation, epoch: trusted.epoch,
          rseq: lastRseq(of: conversation), detail: mayResume ? "runner" : "replica")
        gate.release()
      } catch {
        gate.release()
        // This conversation stays held; the others still reconcile.
        emit("recoveryHeld", conversation: conversation, detail: "\(error)")
        if failure == nil { failure = error }
      }
    }
    // Membership and the native feed are reconciled; every conversation that reconciled above
    // has its retained canonical prefix and execution fence, and the rest stay held.
    requiresRecovery = false
    try await recoverIncomingActions(inbox.deferred)
    if let failure { throw failure }
  }

  /// Reuses the already-authenticated plaintext checkpointed with the native ratchet. A kill
  /// between decryption and canonical application never requires a forbidden second decrypt.
  /// A conversation whose retained change cannot be applied yet keeps its later changes in
  /// order and is reported as `failure`; the other conversations are still applied.
  private func recoverIncomingReplicas() async throws -> (
    deferred: [InboxItem], failure: (any Error)?
  ) {
    var replicas: [InboxItem] = []
    var deferred: [InboxItem] = []
    for receipt in try await group.pendingApplicationReceipts() {
      let message: DeviceMessage
      let sender: DeviceID
      do {
        guard let decoded = try DeviceGroup.nodeMessage(receipt, groupID: await group.groupID)
        else {
          continue  // An explicit different/unknown host retains responsibility for this AAD.
        }
        message = decoded
        sender = try DeviceID(receipt.opened.sender.deviceID)
      } catch {
        try await group.acknowledgeOpened(receiptIDs: [receipt.id])
        emit("invalidInboxDiscarded", detail: "invalid authenticated device envelope")
        continue
      }
      if sender == identity.deviceID {
        if case .messageForward(let forward) = message.body,
          conversations[forward.conversationId]?.receipts[forward.requestId] == nil
        {
          deferred.append(InboxItem(receipt: receipt, message: message, sender: sender))
        } else {
          try await group.acknowledgeOpened(receiptIDs: [receipt.id])
        }
        continue
      }
      if case .device(let recipient) = message.to, recipient != identity.deviceID {
        try await group.acknowledgeOpened(receiptIDs: [receipt.id])
        continue  // Complete native feed, never nonrecipient domain dispatch.
      }
      let item = InboxItem(receipt: receipt, message: message, sender: sender)
      if case .replicaChange = message.body { replicas.append(item) } else { deferred.append(item) }
    }
    replicas.sort { left, right in
      guard case .replicaChange(let a) = left.message.body,
        case .replicaChange(let b) = right.message.body
      else { return left.message.msgId.rawValue < right.message.msgId.rawValue }
      if a.conversationId != b.conversationId {
        return a.conversationId.rawValue < b.conversationId.rawValue
      }
      return a.rseq < b.rseq
    }
    var held: Set<ConversationID> = []
    var failure: (any Error)?
    for item in replicas {
      guard case .replicaChange(let change) = item.message.body,
        !held.contains(change.conversationId)
      else { continue }
      if await apply(change, from: item.sender) == .rejected {
        try await group.acknowledgeOpened(receiptIDs: [item.receipt.id])
        continue
      }
      guard
        conversations[change.conversationId]?.identities[change.rseq]
          == (try change.committedDigest())
      else {
        held.insert(change.conversationId)
        if failure == nil {
          failure = DeviceLayerError.invalid("durable inbox awaiting committed history")
        }
        continue
      }
      try await group.acknowledgeOpened(receiptIDs: [item.receipt.id])
    }
    return (deferred, failure)
  }

  private func recoverIncomingActions(_ items: [InboxItem], liveControls: Bool = false) async throws
  {
    var destinations: [ULID: Set<DeviceID>] = [:]
    var replayed: Set<ULID> = []
    for item in items where item.sender == identity.deviceID {
      if case .messageForward(let forward) = item.message.body,
        case .device(let recipient) = item.message.to
      {
        destinations[forward.requestId, default: []].insert(recipient)
      }
    }
    for item in items {
      if await group.ownsJoinCompletion(item.message) { continue }
      if awaitsRecovery(Self.conversation(of: item.message.body)) { continue }
      if item.sender == identity.deviceID, case .messageForward(let forward) = item.message.body {
        if let canonical = conversations[forward.conversationId]?.receipts[forward.requestId] {
          try await retireOwnForwardInput(canonical)
          continue
        }
        guard replayed.insert(forward.requestId).inserted else { continue }
        let trusted = try await authorityState(forward.conversationId)
        guard let runner = trusted.runner, (trusted.expiresAt ?? 0) > now() else {
          emit(
            "outboundInputAwaitingRunner", conversation: forward.conversationId,
            detail: forward.requestId.rawValue)
          continue
        }
        if runner == identity.deviceID {
          guard conversations[forward.conversationId]?.role == .runner,
            conversations[forward.conversationId]?.heldEpoch == trusted.epoch
          else { continue }
          await admit(forward, from: identity.deviceID) {
            try await self.group.acknowledgeOpened(receiptIDs: [item.receipt.id])
          }
        } else if destinations[forward.requestId]?.contains(runner) != true {
          // The original requestId/surface/content are unchanged. Admission uses the same
          // canonical idempotency ledger; this is recovery, not a second user operation.
          try await deliver(.messageForward(forward), to: runner)
          destinations[forward.requestId, default: []].insert(runner)
        }
        continue
      }
      switch item.message.body {
      case .messageForward, .messageForwardResult, .replicaSubscribe:
        try await dispatchRecovered(item)
      case .deviceHello, .leaseGranted, .leaseRequest, .leaseHandOver, .leaseFenced:
        if liveControls {
          try await dispatchRecovered(item)
        } else {
          // Cold reopen supersedes captured control notices. No old hand-over request may
          // act on a newly reconciled execution lease.
          try await group.acknowledgeOpened(receiptIDs: [item.receipt.id])
        }
      default:
        emit("applicationConsumerRequired", peer: item.sender, detail: item.message.type)
      // Keep unsupported authenticated input; policy/intent application is not invented here.
      }
    }
  }

  private func dispatchRecovered(_ item: InboxItem) async throws {
    let credential = item.receipt.opened.sender
    guard let peer = await group.member(item.sender, agreementKey: credential.agreementPublicKey),
      peer.mlsCredential == credential
    else {
      try await group.acknowledgeOpened(receiptIDs: [item.receipt.id])
      return
    }
    await handleAuthenticated(item.message, from: peer, route: nil) {
      try await self.consume(receiptID: item.receipt.id, messageID: item.message.msgId)
    }
  }

  /// Opens an end-to-end encrypted link to a paired device through the relay.
  public func openRelayLink(to peer: DevicePeer) async throws {
    guard let relay else { throw DeviceLayerError.invalid("not connected to a relay") }
    try await requireMember(peer)
    try await register(
      try await DeviceLink.initiate(
        identity: identity, peer: peer, group: group, route: .relay,
        channel: relay.openStream(to: peer.deviceID), beforeApplication: prepareApplicationEpoch)
    )
  }

  /// Drops the relay connection, keeping relay links' streams: this device is offline to the
  /// relay, which queues frames for it.
  public func relayOffline() { relay?.disconnect() }

  /// Reconnects to the relay; queued frames arrive first, in order.
  public func relayOnline() async throws {
    guard let relay else { throw DeviceLayerError.invalid("not connected to a relay") }
    try await relay.reconnect()
    if relay.isRemovalReading { try await requireRemovalProof() }
    try await refreshMembership()
    try await group.recoverPendingCommit(
      using: groupCommitter, applicationFeedReader: applicationFeedReader)
    try await group.completeCommittedMembership(using: membershipDidCommit)
    try await deliverPendingHello()
    try await refreshMembership()
    try await catchUpApplications()
    for conversation in Array(conversations.keys) {
      let gate = gate(for: conversation)
      await gate.acquire()
      do {
        try await recoverPublication(conversation)
        gate.release()
      } catch {
        gate.release()
        throw error
      }
    }
    for peer in Array(links.keys) { await synchronize(with: peer) }
  }

  /// The routes currently linked to a device.
  public func routes(to peer: DeviceID) -> [LinkRoute] {
    (links[peer].map { Array($0.keys) } ?? []).sorted { $0.rawValue < $1.rawValue }
  }

  /// Closes links to a device, all of them or one route.
  public func dropLinks(to peer: DeviceID, route: LinkRoute? = nil) async {
    let dropped = links[peer]?.filter { route == nil || $0.key == route }.map(\.value) ?? []
    for link in dropped { await link.close() }
  }

  /// Revokes a paired device: the authority's group commit removes it, and its links close.
  public func revoke(_ peer: DeviceID) async throws {
    try await refreshMembership()
    let committer = groupCommitter
    // The removal closes this epoch: an owed final hello and every unpublished seal go first.
    try await deliverPendingHello()
    try await publishPendingApplications()
    try await group.remove(peer, commit: committer, applicationFeedReader: applicationFeedReader)
    try await group.completeCommittedMembership(using: membershipDidCommit)
    await dropLinks(to: peer)
    emit("revoked", peer: peer)
  }

  /// Closes admission and owns shutdown without waiting for the requesting callback to unwind.
  public func requestStop() {
    guard case .running = lifecycle else { return }
    let pending = handlers.beginClose()
    let listening = listener
    let connected = links.values.flatMap(\.values)
    let admitting = Array(admissions.values)
    lifecycle = .stopping(
      Task {
        await self.finishStopping(
          pending: pending, listener: listening, links: connected, admissions: admitting)
      })
    pending?.cancelAndClose()
    relay?.close()  // Unblock native cutoff/CAS reads before joining their owners.
    relay = nil
    listener = nil
    bonjourListener?.close()
    bonjourListener = nil
    for task in admitting { task.cancel() }
    for waiters in forwardWaiters.values {
      for waiter in waiters.values { waiter.resume(throwing: DeviceLayerError.closed) }
    }
    forwardWaiters.removeAll()
    for waiters in grantWaiters.values {
      for waiter in waiters.values { waiter.resume(throwing: DeviceLayerError.closed) }
    }
    grantWaiters.removeAll()
  }

  /// Joins all Node-owned work and releases exclusive replica/native journal ownership.
  /// Native callbacks must use `requestStop()` and return instead of awaiting their own join.
  public func stopAndWait() async {
    requestStop()
    if case .stopping(let task) = lifecycle { await task.value }
  }

  private func finishStopping(
    pending: PendingDeviceHandlers.Snapshot?, listener: TCPFrameListener?,
    links connected: [DeviceLink], admissions admitting: [Task<MessageForwardResult, any Error>]
  ) async {
    await listener?.close()
    for link in connected { await link.close() }
    await pending?.join()
    for task in admitting { _ = await task.result }
    for write in leaseWrites.values { _ = await write.result }
    leaseWrites.removeAll()
    renewals.removeAll()
    admissions.removeAll()
    links.removeAll()
    await applicationRecoveryGate.acquire()
    let held = Array(gates.values)
    for gate in held { await gate.acquire() }
    await sendingApplications.acquire()
    persistenceFailed = true
    await group.close()
    await journalWriter?.close()
    sendingApplications.release()
    for gate in held.reversed() { gate.release() }
    applicationRecoveryGate.release()
    sink.finish()
    handlers.finishClose()
    lifecycle = .stopped
  }

  private func acceptDirect(_ channel: any FrameChannel, identifier: UUID) async {
    guard !stopping, !Task.isCancelled else { return }
    guard let first = try? await channel.receive() else { return }
    let replay = PrefetchedChannel(first: first, inner: channel)
    do {
      try Task.checkCancellation()
      switch first.first.flatMap(LinkFrameKind.init(rawValue:)) {
      case .pairingInitiation:
        try await refreshMembership()
        // The add closes this epoch's feed: a final hello still owed to an earlier joiner, or a
        // seal still unpublished then, could never be accepted.
        try await deliverPendingHello()
        try await publishPendingApplications()
        let result = try await PairingExchange.accept(
          identity: identity, book: book, group: group, channel: replay, commit: groupCommitter,
          groupDidCommit: membershipDidCommit,
          applicationSend: applicationSender, helloSend: pairingHelloSender,
          applicationFeedReader: applicationFeedReader,
          beforeApplication: prepareApplicationEpoch,
          now: now)
        // An add whose host completion failed is paired all the same; the node's next send or
        // inbox pass completes it and delivers the hello it owes.
        let pending = result.completionPending ? ", completion pending" : ""
        emit("paired", peer: result.peer.deviceID, detail: "epoch \(result.groupEpoch)\(pending)")
        try await register(result.link, pending: identifier)
      case .handshakeInitiation:
        try await refreshMembership()
        try await register(
          try await DeviceLink.accept(
            identity: identity, group: group, route: .direct, channel: replay,
            beforeApplication: prepareApplicationEpoch), pending: identifier)
      default:
        return
      }
    } catch {
      emit("refused", route: .direct, detail: "\(error)")
    }
  }

  private func acceptRelay(_ stream: RelayStream, identifier: UUID) async {
    guard !stopping, !Task.isCancelled,
      (try? await refreshMembership()) != nil
    else { return }
    do {
      try Task.checkCancellation()
      try await register(
        try await DeviceLink.accept(
          identity: identity, group: group, route: .relay, channel: stream,
          beforeApplication: prepareApplicationEpoch), pending: identifier)
    } catch {
      emit("refused", peer: stream.peer, route: .relay, detail: "\(error)")
    }
  }

  private func register(_ link: DeviceLink, pending identifier: UUID? = nil) async throws {
    do {
      guard !stopping else { throw DeviceLayerError.closed }
      try await requireMember(link.peer)
      guard !stopping else { throw DeviceLayerError.closed }
      try Task.checkCancellation()
      if let identifier { try handlers.transfer(identifier) }
    } catch {
      await link.close()
      throw error
    }
    let peer = link.peer.deviceID
    let previous = links[peer]?[link.route]
    links[peer, default: [:]][link.route] = link
    emit("linkUp", peer: peer, route: link.route)
    handlers.start { [weak self] _ in
      if !Task.isCancelled { await self?.synchronize(with: peer) }
      while !Task.isCancelled {
        do {
          let message = try await link.receive()
          await self?.handle(message, via: link)
        } catch let error as DeviceApplicationFeedError {
          guard let self else { return }
          do { try await self.catchUpApplications() } catch {
            await self.emitApplicationRecoveryFailure(error)
          }
          if case .conflictingPublication = error {
            await self.linkEnded(link, error: error)
            return
          }
        } catch {
          await self?.linkEnded(link, error: error)
          return
        }
      }
      await link.close()
      await self?.linkEnded(link, error: CancellationError())
    }
    if let previous { await previous.close() }
  }

  private func linkEnded(_ link: DeviceLink, error: any Error) {
    let peer = link.peer.deviceID
    if links[peer]?[link.route] === link {
      links[peer]?[link.route] = nil
      emit("linkDown", peer: peer, route: link.route, detail: "\(error)")
    }
  }

  private var groupCommitter: GroupCommitter {
    if let commitMembership { return commitMembership }
    let relay = relay
    let identity = identity
    return { commit in
      guard let relay else { throw DeviceLayerError.invalid("no group authority reachable") }
      let reply = try await relay.authority(
        DeviceMessage(
          msgId: try DeviceULID.next(), from: .device(identity.deviceID), to: .authority,
          sentAt: DeviceClock.wallMilliseconds(), body: .groupCommit(commit)))
      guard case .groupCommitResult(let result) = reply?.body else {
        throw DeviceLayerError.protocolViolation("expected group.commitResult")
      }
      guard result.groupId == commit.groupId else {
        throw DeviceLayerError.protocolViolation("group authority identity mismatch")
      }
      if !result.accepted, result.epoch > commit.fromEpoch {
        let expected = try AuthenticatedGroupCommit.decode(commit, committer: identity.peer)
          .orderedCommit
        let snapshot = try await relay.membership(commit.groupId, afterEpoch: commit.fromEpoch)
        if snapshot.commits.contains(expected) {
          // This is the exact retained authoritative receipt, not a second CAS acceptance.
          return GroupCommitResult(
            groupId: commit.groupId, accepted: true, epoch: Int64(expected.targetEpoch))
        }
      }
      return result
    }
  }

  private var applicationFeedReader: DeviceApplicationEpochReader {
    if let readApplicationFeed { return readApplicationFeed }
    return { [weak self] request in
      guard let self else { throw DeviceLayerError.closed }
      return try await self.readRelayApplicationFeed(request)
    }
  }

  private func readRelayApplicationFeed(_ request: DeviceApplicationEpochRequest) async throws
    -> DeviceApplicationEpochFeed
  {
    guard let relay else { throw DeviceApplicationFeedError.unavailable }
    return try await relay.applicationFeed(request)
  }

  private var prepareApplicationEpoch: @Sendable (UInt64) async throws -> Void {
    { [weak self] expected in
      guard let self else { throw DeviceLayerError.closed }
      try await self.refreshMembership()
      guard let expectedEpoch = Int64(exactly: expected), await self.group.epoch >= expectedEpoch
      else {
        throw DeviceApplicationFeedError.unavailable
      }
    }
  }

  private var applicationSender: DeviceApplicationSender {
    { [weak self] application in
      guard let self else { throw DeviceLayerError.closed }
      try await self.publishAndFanout(application)
    }
  }

  /// The final hello is sealed and published under `sendingApplications`, like every other
  /// seal of this node: a catch-up holds that gate while it reads the feed, so it never meets
  /// the hello sealed and not yet published.
  private var pairingHelloSender: PairingHelloSender {
    { [weak self] hello in
      guard let self else { throw DeviceLayerError.closed }
      return try await self.sealAndPublishHello(hello)
    }
  }

  private func sealAndPublishHello(_ hello: DeviceMessage) async throws
    -> DeviceSealedApplication
  {
    await sendingApplications.acquire()
    defer { sendingApplications.release() }
    guard !stopping else { throw DeviceLayerError.closed }
    try Task.checkCancellation()
    let application = try await group.sealDeviceMessage(hello)
    try await publishHoldingGate(application)
    return application
  }

  /// Seals again the seals a closed group state retired and publishes this node's pending
  /// feed through its application sender; when the sender answers that a seal's group state
  /// closed, the node installs the new state, seals again and publishes once more. Nothing
  /// retired and nothing pending: nothing is sent. A host that drives its own inbox pass (the
  /// CloudKit route) calls this after it read membership, so that an ordinary fetch gets a
  /// retired message out again without any other caller.
  public func publishPendingApplications() async throws {
    try await finishPendingMembership()
    await sendingApplications.acquire()
    defer { sendingApplications.release() }
    guard !stopping else { throw DeviceLayerError.closed }
    try Task.checkCancellation()
    try await publishPendingApplicationsHoldingGate()
  }

  private func publishPendingApplicationsHoldingGate() async throws {
    // Seals retired from a closed group state are sealed again first, in their order.
    try await group.resealRetiredApplications()
    do {
      if let last = try await group.pendingApplicationFeed().last {
        try await publishAndFanoutHoldingGate(last)
      }
    } catch DeviceApplicationFeedError.unacceptedOldEpoch {
      // A pending seal belongs to a group state that closed, as after a restart: install the
      // new state, which retires it, seal it again and publish once more.
      try await refreshMembership()
      try await group.resealRetiredApplications()
      if let last = try await group.pendingApplicationFeed().last {
        try await publishAndFanoutHoldingGate(last)
      }
    }
    try await group.acknowledgePublishedNodeSeals()
  }

  /// Publishes one seal. When the authority answers that the seal's group state closed before
  /// it was accepted, the node installs the new state, which retires the seal, and publishes
  /// its re-seal under the same operation ID instead: the message is delivered once. Returns
  /// whether this seal was published; false means its group state closed first and the pending
  /// feed, with the re-seal if there is one, was published instead.
  @discardableResult
  private func publishHoldingGate(
    _ application: DeviceSealedApplication, preferred: LinkRoute? = nil
  ) async throws -> Bool {
    do {
      try await publishAndFanoutHoldingGate(application, preferred: preferred)
      return true
    } catch DeviceApplicationFeedError.unacceptedOldEpoch {
      try await refreshMembership()
      try await publishPendingApplicationsHoldingGate()
      return false
    }
  }

  private func publishAndFanout(
    _ application: DeviceSealedApplication, preferred: LinkRoute? = nil
  ) async throws {
    await sendingApplications.acquire()
    defer { sendingApplications.release() }
    guard !stopping else { throw DeviceLayerError.closed }
    try Task.checkCancellation()
    try await publishHoldingGate(application, preferred: preferred)
  }

  private func publishAndFanoutHoldingGate(
    _ application: DeviceSealedApplication, preferred: LinkRoute? = nil
  ) async throws {
    let pendingFeed = try await group.pendingApplicationFeed()
    let newlyPublished = pendingFeed.contains { $0.ordinal == application.ordinal }
    for pending in pendingFeed {
      if let sendApplication {
        try await sendApplication(pending)
      } else {
        guard let relay else { throw DeviceApplicationFeedError.unavailable }
        let publication = try await group.applicationPublication(pending)
        try await relay.publishApplication(publication)
      }
      try await group.acknowledgeApplicationFeed(throughOrdinal: pending.ordinal)
      try await group.acknowledgeSealed(ordinal: pending.ordinal)
      if let receipt = try await group.applicationReceipt(ciphertext: pending.message.ciphertext),
        let message = try DeviceGroup.nodeMessage(receipt, groupID: await group.groupID)
      {
        if case .messageForward = message.body {
          // The accepted full feed cannot reopen our own sent ciphertext. Keep the original
          // input until its canonical result or an authoritative rejection is durable.
        } else {
          try await group.acknowledgeOpened(receiptIDs: [receipt.id])
        }
      }
    }
    // Every previous-epoch participant already drained this immutable accepted prefix before
    // retiring it; newly admitted members must not receive ciphertext from before their join.
    guard newlyPublished, application.message.groupEpoch == UInt64(await group.epoch) else {
      return
    }
    let eligible = try await group.applicationMembers(epoch: application.message.groupEpoch)
    for peer in Array(links.keys) {
      guard let routes = links[peer], let member = eligible.first(where: { $0.deviceID == peer }),
        await group.member(peer, agreementKey: member.agreementKey) == member
      else { continue }
      let preference: LinkRoute?
      if application.recipient == .device(peer) { preference = preferred } else { preference = nil }
      guard let link = preference.flatMap({ routes[$0] }) ?? routes[.direct] ?? routes[.relay]
      else { continue }
      do { try await link.sendSealed(application) } catch {
        // Shared publication is already durable. A failed live route never substitutes for
        // that proof or drops the accepted packet; the receiver catches up from the full feed.
        emit("liveDeliveryDeferred", peer: peer, route: link.route, detail: "\(error)")
      }
    }
  }

  /// Reopens no native ciphertext twice. Crypto catches up first; canonical replicas and
  /// idempotent input are then applied through the same store/fence handlers as live links.
  public func catchUpApplications() async throws {
    guard !stopping else { throw DeviceLayerError.closed }
    await applicationRecoveryGate.acquire()
    defer { applicationRecoveryGate.release() }
    guard !stopping else { throw DeviceLayerError.closed }
    try await catchUpPublishedApplications()
    let inbox = try await recoverIncomingReplicas()
    if !requiresRecovery { try await recoverIncomingActions(inbox.deferred, liveControls: true) }
    if let failure = inbox.failure { throw failure }
  }

  /// Sealing, publication and a current native-feed read share one boundary. Receipt consumers
  /// run after this gate is released because they may send their own authenticated response.
  private func catchUpPublishedApplications() async throws {
    await sendingApplications.acquire()
    defer { sendingApplications.release() }
    guard !stopping else { throw DeviceLayerError.closed }
    try Task.checkCancellation()
    try await publishPendingApplicationsHoldingGate()
    try await refreshMembership()
    try await group.catchUpApplicationFeed(using: applicationFeedReader)
  }

  private func emitApplicationRecoveryFailure(_ error: any Error) {
    emit("applicationRecoveryRequired", detail: "\(error)")
  }

  /// Only already-authenticated, durably checkpointed native inbox entries may reach this
  /// seam. A transport's caller-created opened object cannot bypass sender/fence validation.
  public func receiveApplication(ciphertext: Data) async throws -> DeviceApplicationDisposition {
    guard !stopping else { throw DeviceLayerError.closed }
    try await refreshMembership()
    if try await group.applicationWasConsumed(ciphertext: ciphertext) { return .consumed }
    guard let receipt = try await group.applicationReceipt(ciphertext: ciphertext),
      let message = try DeviceGroup.nodeMessage(receipt, groupID: await group.groupID)
    else { return .pendingRecovery }
    if receipt.opened.sender == identity.peer.mlsCredential {
      guard !awaitsRecovery(Self.conversation(of: message.body)) else { return .pendingRecovery }
      if case .messageForward(let forward) = message.body,
        conversations[forward.conversationId]?.receipts[forward.requestId] == nil
      {
        return .pendingRecovery
      }
      try await group.acknowledgeOpened(receiptIDs: [receipt.id])
      return try await group.applicationWasConsumed(ciphertext: ciphertext)
        ? .consumed : .pendingRecovery
    }
    if case .device(let recipient) = message.to, recipient != identity.deviceID {
      try await group.acknowledgeOpened(receiptIDs: [receipt.id])
      return .consumed
    }
    guard !awaitsRecovery(Self.conversation(of: message.body)) else { return .pendingRecovery }
    let peer = DevicePeer(
      deviceID: try DeviceID(receipt.opened.sender.deviceID),
      signingKey: receipt.opened.sender.signingPublicKey,
      agreementKey: receipt.opened.sender.agreementPublicKey)
    if case .replicaChange = message.body {
      // Historical canonical payloads are verified against the actual authority digest below.
    } else if await group.member(peer.deviceID, agreementKey: peer.agreementKey) != peer {
      try await group.acknowledgeOpened(receiptIDs: [receipt.id])
      emit("revokedInboxRejected", peer: peer.deviceID)
      return .consumed
    }
    await handleAuthenticated(message, from: peer, route: nil) {
      try await self.consume(receiptID: receipt.id, messageID: message.msgId)
    }
    return try await group.applicationWasConsumed(ciphertext: ciphertext)
      ? .consumed : .pendingRecovery
  }

  /// Whether this device is still in its group. Only a native commit that removes it, applied
  /// to the group state it holds, takes it out of its own roster; a relay's refusal or a roster
  /// it was shown never does. Read from the group's checkpoint, so it survives a restart.
  public var membership: DeviceGroupMembership {
    get async {
      await group.members.contains(where: { $0.deviceId == identity.deviceID })
        ? .member : .removed
    }
  }

  /// Whether this node deleted, after its verified removal, every conversation replica and its
  /// replica journal. Read from that journal, so it survives a restart. The host deletes its
  /// own conversation store and offline approvals when ``membership`` is `.removed`.
  public var deletedRemovedData: Bool { removalErased }

  /// Reads the configured membership authority (or qualification relay) through its reported
  /// head, draining each closed base-epoch native feed before installing the next commit.
  /// Fences removed membership and closes obsolete links; does not refresh conversation leases
  /// or dispatch domain consumers. Missing authority/gaps throw, preserving earlier checkpoints.
  /// A roster without this device is proved by its commits alone
  /// (``DeviceGroup/installRemoval(from:reading:)``); no application message is read for it.
  public func refreshMembership() async throws {
    while true {
      let before = await group.epoch
      let groupID = await group.groupID
      guard !stopping else { throw DeviceLayerError.closed }
      try Task.checkCancellation()
      let snapshot = try await membershipPage(groupID, after: before)
      try await applyMembership(snapshot)
      if await membership == .removed { return }
      let after = await group.epoch
      if after >= snapshot.epoch { return }
      guard after > before else { throw DeviceLayerError.invalid("MLS authority commit gap") }
    }
  }

  private func membershipPage(_ groupID: String, after: Int64) async throws -> AuthorityGroup {
    if let readMembership { return try await readMembership(groupID, after) }
    guard let relay else { throw DeviceLayerError.invalid("no group authority reachable") }
    return try await relay.membership(groupID, afterEpoch: after)
  }

  private func requireMember(_ peer: DevicePeer) async throws {
    try await refreshMembership()
    guard await group.member(peer.deviceID, agreementKey: peer.agreementKey) == peer else {
      throw DeviceLayerError.unknownPeer
    }
  }

  private func applicationChanged(groupID: String, epoch: UInt64) async {
    guard groupID == (await group.groupID) else { return }
    do { try await catchUpApplications() } catch {
      emit("applicationRecoveryRequired", epoch: Int64(exactly: epoch), detail: "\(error)")
    }
  }

  private func membershipChanged(_ snapshot: AuthorityGroup) async {
    guard snapshot.groupID == (await group.groupID) else { return }
    do {
      if snapshot.members.contains(where: { $0.deviceId == identity.deviceID }) {
        try await refreshMembership()
      } else {
        // The relay ends this session next; its removal is read over a fresh connection.
        _ = await readRemoval(reconnecting: true)
        return  // A removed device cannot read a future epoch or resume execution.
      }
      try await catchUpApplications()
    } catch {
      emit("membershipRefused", detail: "\(error)")
    }
  }

  private func applyMembership(_ snapshot: AuthorityGroup) async throws {
    let knownEpoch = await group.epoch
    guard !stopping else { throw DeviceLayerError.closed }
    try Task.checkCancellation()
    guard snapshot.epoch >= knownEpoch else { return }
    if !snapshot.members.contains(where: { $0.deviceId == identity.deviceID }) {
      await fenceRemovedMembership()
      let groupID = await group.groupID
      let removed = try await group.installRemoval(
        from: snapshot,
        reading: { [weak self] after in
          guard let self else { throw DeviceLayerError.closed }
          return try await self.membershipPage(groupID, after: after)
        })
      guard removed else { throw DeviceLayerError.invalid("removal not proven") }
    } else {
      try await group.adoptAuthority(snapshot, applicationFeedReader: applicationFeedReader)
    }
    let peers = await group.peers
    for peer in Array(links.keys) {
      for link in links[peer].map({ Array($0.values) }) ?? []
      where !peers.contains(link.peer) {
        if links[peer]?[link.route] === link { links[peer]?[link.route] = nil }
        await link.close()
        emit("revokedLink", peer: peer, route: link.route)
      }
      if links[peer]?.isEmpty == true { links[peer] = nil }
    }
    if await membership == .removed { await reportRemoval() }
  }

  /// The relay refused this device as removed. Throws `unknownPeer` when the group's commits
  /// prove it; otherwise the refusal stands as before (`protocolViolation`).
  private func requireRemovalProof() async throws {
    if await readRemoval(reconnecting: false) { throw DeviceLayerError.unknownPeer }
    throw DeviceLayerError.protocolViolation("relay refused the connection")
  }

  /// Reads membership over a connection the relay keeps only for that (a fresh one when
  /// `reconnecting`, after the relay ended this device's session). True only when a commit
  /// removing this device was applied to its own group state; otherwise the reading connection
  /// is dropped and nothing of the group changed. One reading at a time.
  private func readRemoval(reconnecting: Bool) async -> Bool {
    if await membership == .removed {
      await reportRemoval()
      return true
    }
    guard !readingRemoval, let relay else { return false }
    readingRemoval = true
    defer { readingRemoval = false }
    if reconnecting {
      do { try await relay.reconnect() } catch {
        emit("removalUnproven", detail: "\(error)")
        return false
      }
      guard relay.isRemovalReading else { return false }
    }
    do { try await refreshMembership() } catch { emit("membershipRefused", detail: "\(error)") }
    if await membership == .removed {
      await reportRemoval()
      return true
    }
    relay.disconnect()
    emit("removalUnproven")
    return false
  }

  /// Reports, once per run, that a commit removing this device was applied (the group dropped
  /// every message it held, its keys and its history in that checkpoint), deletes what this
  /// node held for the group, and closes the relay client (later calls on it fail as `closed`;
  /// a new `connectRelay` fails as `unknownPeer`). Every call closes the client and finishes
  /// the deletion before it returns, also one that comes while the report waits. Runs only
  /// after a verified removal: a device the relay merely refused keeps everything.
  private func reportRemoval() async {
    membershipRevoked = true
    relay?.close()
    if !removalReported {
      if let hold = beforeRemovalReport.withLock({ $0 }) { await hold() }
      let epoch = await group.epoch
      if !removalReported {
        removalReported = true
        emit("removedFromGroup", epoch: epoch)
      }
      // A client connected while this call waited is closed as well.
      relay?.close()
    }
    eraseRemovedReplicas()
  }

  /// Deletes this node's conversation replicas and rewrites its replica journal as one
  /// `removed` marker, durably (replaced and synchronized before this returns); every later
  /// journal record is refused. The conversation store and any offline approvals belong to the
  /// host, which deletes them on ``membership`` `.removed` (event `removedDataDeleted`).
  private func eraseRemovedReplicas() {
    guard !removalErased else { return }
    for conversation in Array(conversations.keys) { stopRenewing(conversation) }
    do {
      try journalWriter?.replaceNow(JournalRecord.removed)
    } catch {
      persistenceFailed = true
      emit("removedDataDeletionFailed", detail: "\(error)")
      return
    }
    removalErased = true
    conversations.removeAll()
    unreconciled.removeAll()
    deferredResults.removeAll()
    replicaAcknowledgements.removeAll()
    emit("removedDataDeleted")
  }

  private func fenceRemovedMembership() async {
    membershipRevoked = true
    requiresRecovery = true
    for conversation in Array(conversations.keys) {
      guard var state = conversations[conversation],
        state.runner == identity.deviceID || state.role == .runner || state.role == .handingOver
      else { continue }
      stopRenewing(conversation)
      state.role = .replica
      state.runner = nil
      state.expiresAt = nil
      conversations[conversation] = state
      do {
        try persist(.lease(lease(of: conversation), heldEpoch: state.heldEpoch))
        if let held = state.heldEpoch {
          try await leaseWrite(conversation) {
            try await $0.releaseLease(conversation, epoch: held, at: $1)
          }
        }
      } catch {
        emit(
          "revocationFenceUnavailable", conversation: conversation, epoch: state.epoch,
          detail: "\(error)")
      }
    }
  }

  private func synchronize(with peer: DeviceID) async {
    guard !stopping, !Task.isCancelled else { return }
    for conversation in Array(conversations.keys) {
      try? await deliver(
        .replicaSubscribe(
          ReplicaSubscribe(conversationId: conversation, afterRseq: lastRseq(of: conversation))),
        to: peer)
    }
  }

  // MARK: - Sending

  /// Publishes once even when the destination has no live link, then fans the same native
  /// ciphertext to every live epoch participant. Nonrecipients never dispatch its payload.
  private func deliver(
    _ body: DeviceMessageBody, to peer: DeviceID, prefer: LinkRoute? = nil
  ) async throws {
    guard !stopping else { throw DeviceLayerError.closed }
    try await finishPendingMembership()
    await sendingApplications.acquire()
    defer { sendingApplications.release() }
    guard !stopping else { throw DeviceLayerError.closed }
    try Task.checkCancellation()
    guard let peerIdentity = (await group.peers).first(where: { $0.deviceID == peer }) else {
      throw DeviceLayerError.unknownPeer
    }
    try await requireMember(peerIdentity)
    guard !stopping else { throw DeviceLayerError.closed }
    try Task.checkCancellation()
    let application = try await group.sealDeviceMessage(message(body, to: .device(peer)))
    guard try await !publishHoldingGate(application, preferred: prefer),
      try await group.applicationAwaitsReseal(ciphertext: application.message.ciphertext),
      await group.member(peer, agreementKey: peerIdentity.agreementKey) != peerIdentity
    else { return }
    // The seal's group state closed and its recipient left the group with that change, so the
    // message is never sealed again. Nothing was sent.
    throw DeviceLayerError.unknownPeer
  }

  /// Issues the final hello an accepted add still owes its joiner, whose pending join completes
  /// only on that hello.
  private func deliverPendingHello() async throws {
    await sendingApplications.acquire()
    defer { sendingApplications.release() }
    guard !stopping else { throw DeviceLayerError.closed }
    guard let application = try await group.sealPendingHello() else { return }
    try await publishHoldingGate(application)
  }

  /// For a host that seals through the group itself (`DeviceApplicationTransport`): finishes
  /// an add whose host completion is pending before the host seals, as the node's own sends do.
  /// Throws only `CancellationError`.
  public func finishPendingMembershipChange() async throws {
    try await finishPendingMembership()
  }

  /// An add whose host completion did not finish (its callback failed, or the process stopped)
  /// keeps the hello it owes unsealed, and the group refuses every other seal until that hello
  /// is sealed (`DeviceLayerError.membershipChangePending`). So each send first finishes the
  /// completion and publishes the owed hello; while a pairing exchange completes the add, this
  /// waits for it. A change whose authority reply was lost is resolved first, the same way
  /// (``resolvePendingMembershipRequest()``). One attempt runs at a time and the sends that
  /// arrive meanwhile share it. After a failed attempt the next waits 500 ms, doubling up to
  /// 60 s. The delay belongs to one pending change: it starts again once any path finished that
  /// one (a send, a pairing exchange, `recover()`, `relayOnline()`) or another is pending. A
  /// send during the delay makes no authority or host call, so its seal is refused at once with
  /// that typed, retryable error. Cancelling the sending task ends its wait with
  /// `CancellationError` before it seals anything; the attempt itself runs on.
  private func finishPendingMembership() async throws {
    try Task.checkCancellation()
    if let attempt = completionAttempt {
      _ = try await Self.value(of: attempt)
    } else {
      let request = await group.pendingMembershipRequest
      let completion = await group.pendingMembershipCompletion
      let pending = request ?? completion
      if pending != completionFailedFor {
        completionFailures = 0
        completionFailedFor = nil
        completionRetryAt = 0
      }
      let time = now()
      // A wall clock set back never extends the delay.
      if completionAttempt == nil, time >= completionRetryAt || time < completionFailedAt {
        let group = group
        let complete = membershipDidCommit
        let attempt = Task {
          var completed = true
          if request != nil {
            completed = (try? await resolvePendingMembershipRequest()) != nil
          }
          if completed {
            completed = (try? await group.completeCommittedMembership(using: complete)) != nil
          }
          completionEnded(completed, pending: pending)
          return completed
        }
        completionAttempt = attempt
        _ = try await Self.value(of: attempt)
      } else if let attempt = completionAttempt {
        _ = try await Self.value(of: attempt)
      }
    }
    try Task.checkCancellation()
    try? await deliverPendingHello()
  }

  /// A membership change whose authority reply was lost keeps its exact request, and every
  /// seal waits for it. The authority's ordered commits show whether it was applied; when they
  /// do not, the same bytes go to the authority again. An accepted change is installed and its
  /// host completion is owed; a refusal at its base epoch discards it; any other answer leaves
  /// it uncertain (`DeviceGroup.recoverPendingCommit`).
  private func resolvePendingMembershipRequest() async throws {
    try await refreshMembership()
    try await group.recoverPendingCommit(
      using: groupCommitter, applicationFeedReader: applicationFeedReader)
  }

  private func completionEnded(_ completed: Bool, pending: GroupCommit?) {
    completionAttempt = nil
    if completed {
      completionFailures = 0
      completionFailedFor = nil
      completionRetryAt = 0
    } else {
      completionFailures += 1
      completionFailedFor = pending
      completionFailedAt = now()
      completionRetryAt =
        completionFailedAt + min(500 << Int64(min(completionFailures - 1, 7)), 60_000)
    }
  }

  /// Waits for `task` unless the calling task is cancelled first, which ends the wait with
  /// `CancellationError`; `task` itself runs on.
  private static func value<Value: Sendable>(of task: Task<Value, Never>) async throws -> Value {
    let waiter = Locked<CheckedContinuation<Value, any Error>?>(nil)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        waiter.withLock { $0 = continuation }
        Task {
          let value = await task.value
          waiter.withLock { $0.take() }?.resume(returning: value)
        }
        if Task.isCancelled { waiter.withLock { $0.take() }?.resume(throwing: CancellationError()) }
      }
    } onCancel: {
      waiter.withLock { $0.take() }?.resume(throwing: CancellationError())
    }
  }

  /// `readsMembership` is false when the caller read membership for this same operation: the
  /// read is not what keeps a seal out of a closed group state (the authority refuses it and
  /// the node seals it again), so a second one buys nothing.
  private func broadcast(_ body: DeviceMessageBody, readsMembership: Bool = true) async {
    guard !stopping, !Task.isCancelled else { return }
    do { try await finishPendingMembership() } catch { return }
    await sendingApplications.acquire()
    defer { sendingApplications.release() }
    guard !stopping, !Task.isCancelled else { return }
    do {
      // Seal in the epoch the authority still accepts: a membership change ordered since this
      // node last looked would leave the seal unaccepted in a closed epoch. The read only
      // narrows that window; when it fails the message is still sealed and retained, and is
      // published with the pending feed later.
      if readsMembership { try? await refreshMembership() }
      let application = try await group.sealDeviceMessage(message(body, to: .group))
      try await publishHoldingGate(application)
    } catch {
      emit("applicationRecoveryRequired", detail: "\(error)")
    }
  }

  private func message(_ body: DeviceMessageBody, to recipient: DeviceAddress) throws
    -> DeviceMessage
  {
    DeviceMessage(
      msgId: try DeviceULID.next(), from: .device(identity.deviceID), to: recipient,
      sentAt: now(), body: body)
  }

  private func authority(_ body: DeviceMessageBody) async throws -> DeviceMessageBody? {
    guard let relay else { throw DeviceLayerError.invalid("no lease authority reachable") }
    return try await relay.authority(message(body, to: .authority))?.body
  }

  /// Sends one raw message to the lease authority, bypassing the node's lease view; for
  /// measuring the authority itself. `lease.release` has no answer.
  public func requestAuthority(_ body: DeviceMessageBody) async throws -> DeviceMessageBody? {
    try await authority(body)
  }

  /// Sends one raw message to the lease authority over a fresh relay connection, past this
  /// node's own guards and its relay client, for measuring that the relay or the authority
  /// refuses this device (a removed device need not cooperate). Nil when the relay ended the
  /// connection unanswered. Needs an earlier `connectRelay` for the relay's address.
  public func attemptUnguardedAuthority(_ body: DeviceMessageBody) async throws
    -> DeviceMessageBody?
  {
    guard let relayEndpoint else { throw DeviceLayerError.invalid("not connected to a relay") }
    return try await RelayClient.probeAuthority(
      host: relayEndpoint.host, port: relayEndpoint.port, identity: identity,
      message: message(body, to: .authority))?.body
  }

  /// Presents this device's identity and key to another device's direct listener without the
  /// membership check this side applies to its own links, for measuring that the other device
  /// refuses it: a removed device, which knows it was removed, need not cooperate. True only if
  /// the other device answered the handshake; the attempt never becomes a link.
  public func attemptUnguardedLink(to peer: DevicePeer, host: String = "127.0.0.1", port: Int)
    async throws -> Bool
  {
    let channel = try await TCPFrameChannel.connect(host: host, port: port)
    defer { channel.close() }
    var handshake = try NoiseHandshake(
      pattern: .link, initiator: true, prologue: DeviceLink.prologue,
      localStatic: identity.agreementKey(), remoteStatic: peer.agreementPublicKey)
    try channel.send(
      Data([LinkFrameKind.handshakeInitiation.rawValue])
        + handshake.writeMessage(payload: Data(identity.deviceID.rawValue.utf8)))
    guard let reply = try? await channel.receive() else { return false }
    return reply.first == LinkFrameKind.handshakeResponse.rawValue
  }

  // MARK: - Leases

  /// The node's view of one conversation's lease.
  public func lease(of conversation: ConversationID) -> LeaseRecord {
    let state = conversations[conversation] ?? Conversation()
    return LeaseRecord(
      conversationID: conversation, epoch: state.epoch, runner: state.runner,
      expiresAt: state.expiresAt)
  }

  /// The last replication sequence this node holds for a conversation.
  public func lastRseq(of conversation: ConversationID) -> Int64 {
    conversations[conversation]?.lastRseq ?? 0
  }

  /// Claims a lease from the authority. On a win the store adopts the epoch and every linked
  /// device hears `lease.granted`; on a loss the node adopts the authority's newer record.
  @discardableResult
  public func claim(
    _ conversation: ConversationID, ttl: Int64? = nil, reason: LeaseGrantReason = .created,
    expectedEpoch: Int64? = nil
  ) async throws -> LeaseClaimResult {
    guard !persistenceFailed, !stopping, !membershipRevoked, !awaitsRecovery(conversation) else {
      throw DeviceLayerError.io("device authority recovery required")
    }
    // A surviving identity cannot replace missing native state with a fresh root.
    try await refreshMembership()
    let gate = gate(for: conversation)
    await gate.acquire()
    defer { gate.release() }
    guard !stopping, !membershipRevoked, !awaitsRecovery(conversation) else {
      throw DeviceLayerError.closed
    }
    try await recoverPublication(conversation)
    let trusted = try await authorityState(conversation)
    await observe(leaseRecord(conversation, from: trusted))
    try await reconcile(conversation, against: trusted)
    let known = trusted.epoch
    let expected = expectedEpoch ?? (known == 0 ? nil : known)
    // The epoch a removal moved the lease to is granted again with `reason: revoked` (§12.5).
    let grantReason: LeaseGrantReason =
      trusted.runner == nil && trusted.reason == .revoked ? .revoked : reason
    let reply = try await authority(
      .leaseClaim(
        LeaseClaim(
          conversationId: conversation, expectedEpoch: expected,
          expiresAt: now() + (ttl ?? leaseMilliseconds))))
    guard case .leaseClaimResult(let result) = reply else {
      throw DeviceLayerError.protocolViolation("expected lease.claimResult")
    }
    if result.granted, let expiresAt = result.expiresAt {
      // Re-read after the CAS: a former runner could have published its final change between
      // our preflight and the grant. The grant alone never enables writes over stale history.
      let grantedState = try await authorityState(conversation)
      guard grantedState.epoch == result.epoch, grantedState.runner == identity.deviceID else {
        throw FenceError.fenced(currentEpoch: grantedState.epoch)
      }
      try await reconcile(conversation, against: grantedState)
      let granted = LeaseRecord(
        conversationID: conversation, epoch: result.epoch, runner: identity.deviceID,
        expiresAt: expiresAt)
      try await leaseWrite(conversation) { try await $0.adoptLease(granted, at: $1) }
      guard !stopping, !membershipRevoked else {
        let epoch = result.epoch
        try await leaseWrite(conversation) {
          try await $0.releaseLease(conversation, epoch: epoch, at: $1)
        }
        throw DeviceLayerError.closed
      }
      var state = conversations[conversation] ?? Conversation()
      state.epoch = result.epoch
      state.runner = identity.deviceID
      state.expiresAt = expiresAt
      state.role = .runner
      state.heldEpoch = result.epoch
      state.leaseTTL = ttl ?? leaseMilliseconds
      try persist(
        .lease(
          LeaseRecord(
            conversationID: conversation, epoch: state.epoch, runner: state.runner,
            expiresAt: state.expiresAt), heldEpoch: state.heldEpoch))
      conversations[conversation] = state
      emit(
        "granted", conversation: conversation, epoch: result.epoch, detail: grantReason.rawValue)
      await broadcast(
        .leaseGranted(
          LeaseGranted(
            conversationId: conversation, epoch: result.epoch, runnerDeviceId: identity.deviceID,
            expiresAt: expiresAt, reason: grantReason)))
      for waiter in (grantWaiters.removeValue(forKey: conversation) ?? [:]).values {
        waiter.resume(returning: result.epoch)
      }
    } else if result.epoch == trusted.epoch, result.runnerDeviceId == nil {
      // Still the state read above, so an epoch a removal moved the lease to stays claimable.
      await observe(leaseRecord(conversation, from: trusted))
    } else {
      await observe(
        LeaseRecord(
          conversationID: conversation, epoch: result.epoch, runner: result.runnerDeviceId,
          expiresAt: result.expiresAt))
    }
    return result
  }

  /// Renews the lease every `interval` until stopped or refused.
  public func startRenewing(_ conversation: ConversationID, every interval: Int64? = nil) {
    guard !stopping, !Task.isCancelled else { return }
    renewals[conversation]?.cancel()
    let interval = interval ?? renewMilliseconds
    renewals[conversation] = handlers.start { [weak self] _ in
      var next = DeviceClock.monotonicNanoseconds()
      while !Task.isCancelled {
        next += UInt64(interval) * 1_000_000
        let wait = Int64(next) - Int64(DeviceClock.monotonicNanoseconds())
        if wait > 0 {
          do { try await Task.sleep(for: .nanoseconds(wait)) } catch { return }
        }
        guard !Task.isCancelled, let self else { return }
        guard await self.renewOnce(conversation, scheduled: next) else { return }
      }
    }
  }

  /// Stops renewing; the lease lapses at its expiry unless handed over or released.
  public func stopRenewing(_ conversation: ConversationID) {
    renewals.removeValue(forKey: conversation)?.cancel()
  }

  /// One renewal; false once the runner is fenced.
  private func renewOnce(_ conversation: ConversationID, scheduled: UInt64) async -> Bool {
    guard !stopping, !Task.isCancelled,
      let state = conversations[conversation], state.role == .runner,
      let epoch = state.heldEpoch
    else { return false }
    let started = DeviceClock.monotonicNanoseconds()
    do {
      let ttl = state.leaseTTL ?? leaseMilliseconds
      let reply = try await authority(
        .leaseRenew(
          LeaseRenew(conversationId: conversation, epoch: epoch, expiresAt: now() + ttl)))
      guard !stopping, !Task.isCancelled else { return false }
      guard case .leaseRenewResult(let result) = reply else { return false }
      let finished = DeviceClock.monotonicNanoseconds()
      if result.renewed {
        // The reply can land after this device observed a newer epoch or handed the lease
        // over; a renewal is recorded only for the epoch it still holds.
        guard let current = conversations[conversation], current.role == .runner,
          current.heldEpoch == epoch, current.epoch == epoch
        else { return false }
        conversations[conversation]?.expiresAt = result.expiresAt
        // The store write is queued behind earlier lease writes and is not awaited, so a stalled
        // local store never delays the next renewal. It carries only the authority's expiry.
        let renewed = LeaseRecord(
          conversationID: conversation, epoch: epoch, runner: identity.deviceID,
          expiresAt: result.expiresAt)
        let adoption = enqueueLeaseWrite(conversation) { try await $0.adoptLease(renewed, at: $1) }
        handlers.start { [weak self] _ in
          guard case .failure(let error) = await adoption.result else { return }
          await self?.renewalAdoptionFailed(conversation, epoch: epoch, error)
        }
        // Recovery never trusts a journaled expiry: it re-reads the authority and resumes only
        // the epoch it already held, which this record does not change. So the record is ordered
        // behind every earlier journal write but not awaited, and a stalled fsync never holds
        // up the node or the next renewal. Its failure still fails the node closed.
        if let journaled = try enqueuePersist(.lease(lease(of: conversation), heldEpoch: epoch)) {
          handlers.start { [weak self] _ in
            do { try await journaled.value() } catch {
              await self?.renewalJournalFailed(conversation, epoch: epoch, error)
            }
          }
        }
        emit(
          "renewed", conversation: conversation, epoch: epoch,
          detail:
            "rtt_ns=\(finished - started) late_ns=\(started > scheduled ? started - scheduled : 0)"
            + " ttl_ms=\(ttl) expires_at=\(result.expiresAt)")
        return true
      }
      emit("renewRefused", conversation: conversation, epoch: result.epoch)
      await lose(conversation, observed: result.epoch)
      return false
    } catch {
      emit("renewFailed", conversation: conversation, epoch: epoch, detail: "\(error)")
      return true
    }
  }

  private func renewalAdoptionFailed(
    _ conversation: ConversationID, epoch: Int64, _ error: any Error
  ) {
    emit("renewFailed", conversation: conversation, epoch: epoch, detail: "store: \(error)")
  }

  private func renewalJournalFailed(
    _ conversation: ConversationID, epoch: Int64, _ error: any Error
  ) {
    persistenceFailed = true
    emit("renewFailed", conversation: conversation, epoch: epoch, detail: "journal: \(error)")
  }

  /// Issues one store lease write after every lease write already issued for the conversation,
  /// so the store applies lease effects in the order this actor decided them. Awaiting the
  /// returned task is optional; later lease writes and commits wait for it regardless.
  @discardableResult
  private func enqueueLeaseWrite(
    _ conversation: ConversationID,
    _ write: @escaping @Sendable (any ConversationStore, Int64) async throws -> Void
  ) -> Task<Void, any Error> {
    let previous = leaseWrites[conversation]
    let store = store
    let now = now
    let task = Task<Void, any Error> {
      _ = await previous?.result
      try await write(store, now())
    }
    leaseWrites[conversation] = task
    return task
  }

  /// Awaits an ordered store lease write and rethrows its error.
  private func leaseWrite(
    _ conversation: ConversationID,
    _ write: @escaping @Sendable (any ConversationStore, Int64) async throws -> Void
  ) async throws {
    try await enqueueLeaseWrite(conversation, write).value
  }

  /// Claims a lease as soon as its runner's lease lapses, polling the authority at the expiry
  /// it reports; fails at `deadline` (monotonic nanoseconds).
  public func takeOver(_ conversation: ConversationID, deadline: UInt64) async throws
    -> LeaseClaimResult
  {
    while true {
      let result = try await claim(conversation, reason: .expired)
      if result.granted { return result }
      let current = DeviceClock.monotonicNanoseconds()
      guard current < deadline else { throw DeviceLayerError.timeout("take-over") }
      let untilExpiry = max(1, (result.expiresAt ?? now()) - now() + 1)
      let wait = min(UInt64(untilExpiry) * 1_000_000, deadline - current)
      try await Task.sleep(for: .nanoseconds(Int64(wait)))
    }
  }

  /// Asks the conversation's runner to hand an idle conversation to this device (rebalancing)
  /// and waits for this device's grant; returns the new epoch.
  public func rebalance(_ conversation: ConversationID, timeout: Duration = .seconds(10))
    async throws
    -> Int64
  {
    guard !stopping, !membershipRevoked, !awaitsRecovery(conversation) else {
      throw DeviceLayerError.closed
    }
    let observed = try await authorityState(conversation)
    guard let runner = observed.runner, runner != identity.deviceID,
      observed.epoch > 0, (observed.expiresAt ?? 0) > now()
    else { throw DeviceLayerError.invalid("no live observed runner to rebalance from") }
    await observe(
      LeaseRecord(
        conversationID: conversation, epoch: observed.epoch, runner: runner,
        expiresAt: observed.expiresAt))
    guard !stopping, !membershipRevoked else { throw DeviceLayerError.closed }
    let id = UUID()
    return try await withCheckedThrowingContinuation { continuation in
      grantWaiters[conversation, default: [:]][id] = continuation
      handlers.start { [weak self] _ in
        guard let self else { return }
        do {
          try await self.deliver(
            .leaseRequest(
              LeaseRequest(
                conversationId: conversation, reason: .rebalance, expectedEpoch: observed.epoch)),
            to: runner)
        } catch {
          await self.failGrantWaiter(conversation, id, error)
        }
      }
      handlers.start { [weak self] _ in
        do { try await Task.sleep(for: timeout) } catch { return }
        await self?.failGrantWaiter(conversation, id, DeviceLayerError.timeout("rebalance"))
      }
    }
  }

  private func failGrantWaiter(_ conversation: ConversationID, _ id: UUID, _ error: any Error) {
    grantWaiters[conversation]?.removeValue(forKey: id)?.resume(throwing: error)
  }

  private func failGrantWaiters(_ conversation: ConversationID, _ error: any Error) {
    for waiter in (grantWaiters.removeValue(forKey: conversation) ?? [:]).values {
      waiter.resume(throwing: error)
    }
  }

  /// The runner side of a hand-over: once idle, stop writing, release the lease at the
  /// authority and tell the requester it may claim.
  private func handOver(
    _ conversation: ConversationID, to target: DeviceID, expectedEpoch: Int64
  ) async {
    let gate = gate(for: conversation)
    await gate.acquire()
    defer { gate.release() }
    guard !stopping, !Task.isCancelled,
      var state = conversations[conversation], state.role == .runner,
      let epoch = state.heldEpoch, epoch == expectedEpoch
    else { return }
    do {
      let trusted = try await authorityState(conversation)
      guard !stopping, !Task.isCancelled,
        trusted.runner == identity.deviceID, trusted.epoch == expectedEpoch,
        (trusted.expiresAt ?? 0) > now(), conversations[conversation]?.role == .runner,
        conversations[conversation]?.heldEpoch == expectedEpoch
      else {
        emit("handOverFenceRefused", conversation: conversation, epoch: expectedEpoch, peer: target)
        return
      }
    } catch {
      emit(
        "handOverAuthorityUnavailable", conversation: conversation, epoch: expectedEpoch,
        detail: "\(error)")
      return
    }
    state.role = .handingOver
    conversations[conversation] = state
    stopRenewing(conversation)
    do {
      try persist(
        .lease(
          LeaseRecord(conversationID: conversation, epoch: epoch, runner: nil, expiresAt: nil),
          heldEpoch: epoch))
      try await leaseWrite(conversation) {
        try await $0.releaseLease(conversation, epoch: epoch, at: $1)
      }
      _ = try await authority(
        .leaseRelease(
          LeaseRelease(conversationId: conversation, epoch: epoch, lastRseq: state.lastRseq)))
      try await deliver(
        .leaseHandOver(
          LeaseHandOver(
            conversationId: conversation, epoch: epoch, toDeviceId: target,
            lastRseq: state.lastRseq)), to: target)
      emit("handedOver", conversation: conversation, epoch: epoch, peer: target)
    } catch {
      emit("handOverFailed", conversation: conversation, epoch: epoch, detail: "\(error)")
    }
    // The successor's lease.granted may already have arrived while this awaited; keep it.
    if conversations[conversation]?.role == .handingOver {
      conversations[conversation]?.role = .replica
    }
    if conversations[conversation]?.epoch == epoch {
      conversations[conversation]?.runner = nil
    }
  }

  /// The receiving side: wait for every change up to `lastRseq`, then claim the next epoch,
  /// retrying while the authority has not yet applied the runner's release.
  private func takeHandOver(_ handOver: LeaseHandOver, from runner: DeviceID) async {
    guard !stopping, !Task.isCancelled else { return }
    let conversation = handOver.conversationId
    let deadline = ContinuousClock.now + .seconds(5)
    while lastRseq(of: conversation) < handOver.lastRseq, ContinuousClock.now < deadline {
      do { try await Task.sleep(for: .milliseconds(1)) } catch { return }
    }
    guard lastRseq(of: conversation) >= handOver.lastRseq else {
      emit("handOverIncomplete", conversation: conversation, epoch: handOver.epoch, peer: runner)
      return
    }
    while !stopping, !Task.isCancelled, ContinuousClock.now < deadline {
      do {
        let result = try await claim(
          conversation, reason: .rebalanced, expectedEpoch: handOver.epoch)
        if result.granted {
          startRenewing(conversation)
          return
        }
        guard result.epoch == handOver.epoch, result.runnerDeviceId == runner else {
          emit("handOverLost", conversation: conversation, epoch: result.epoch)
          return
        }
      } catch {
        emit("handOverClaimFailed", conversation: conversation, detail: "\(error)")
      }
      do { try await Task.sleep(for: .milliseconds(2)) } catch { return }
    }
    failGrantWaiters(conversation, DeviceLayerError.timeout("hand-over claim"))
  }

  /// This device learned it no longer holds its lease.
  private func lose(_ conversation: ConversationID, observed epoch: Int64) async {
    stopRenewing(conversation)
    guard var state = conversations[conversation] else { return }
    if state.role == .runner { state.role = .replica }
    if epoch > state.epoch {
      state.epoch = epoch
      state.runner = nil
      state.expiresAt = nil
      let released = LeaseRecord(
        conversationID: conversation, epoch: epoch, runner: nil, expiresAt: nil)
      try? await leaseWrite(conversation) { try await $0.adoptLease(released, at: $1) }
    }
    conversations[conversation] = state
    do {
      try persist(.lease(lease(of: conversation), heldEpoch: state.heldEpoch))
    } catch { emit("durabilityFailed", conversation: conversation) }
    emit("leaseLost", conversation: conversation, epoch: epoch)
  }

  /// What the node records of the authority's lease state. An epoch a removal moved the lease
  /// to (§12.5, `reason: revoked`, no runner) is held by no device and goes to the next claim,
  /// so it is recorded as the end of the epoch before it, which fences the removed runner.
  /// Recorded as it stands, a store would take it for a released epoch, which never comes back.
  private func leaseRecord(_ conversation: ConversationID, from trusted: AuthorityConversation)
    -> LeaseRecord
  {
    guard trusted.runner == nil, trusted.reason == .revoked, trusted.epoch > 0 else {
      return LeaseRecord(
        conversationID: conversation, epoch: trusted.epoch, runner: trusted.runner,
        expiresAt: trusted.expiresAt)
    }
    return LeaseRecord(
      conversationID: conversation, epoch: trusted.epoch - 1, runner: nil, expiresAt: nil)
  }

  /// Adopts only a record obtained directly from the trusted qualification authority.
  private func observe(_ record: LeaseRecord) async {
    var state = conversations[record.conversationID] ?? Conversation()
    guard record.epoch >= state.epoch else { return }
    let wasRunner = state.role == .runner && record.runner != identity.deviceID
    if record.epoch > state.epoch || state.runner != record.runner {
      state.epoch = record.epoch
      state.runner = record.runner
      state.expiresAt = record.expiresAt
    } else if let expiresAt = record.expiresAt {
      state.expiresAt = max(state.expiresAt ?? 0, expiresAt)
    }
    if wasRunner {
      state.role = .replica
      stopRenewing(record.conversationID)
    }
    do {
      try persist(
        .lease(
          LeaseRecord(
            conversationID: record.conversationID, epoch: state.epoch, runner: state.runner,
            expiresAt: state.expiresAt), heldEpoch: state.heldEpoch))
    } catch {
      emit("durabilityFailed", conversation: record.conversationID)
      return
    }
    conversations[record.conversationID] = state
    // Own metadata is not permission to revive a reopened runner. claim/recover adopt the
    // writable store fence only after exact committed-history reconciliation.
    if record.runner != identity.deviceID || state.role == .runner {
      try? await leaseWrite(record.conversationID) { try await $0.adoptLease(record, at: $1) }
    }
  }

  // MARK: - Writes and replication

  /// Commits one change as the conversation's runner and replicates it to every linked device.
  @discardableResult
  public func commit(_ conversation: ConversationID, label: String, requestID: ULID? = nil)
    async throws -> ReplicaChange
  {
    let gate = gate(for: conversation)
    await gate.acquire()
    defer { gate.release() }
    return try await commitHoldingGate(conversation, label: label, requestID: requestID)
  }

  private func commitHoldingGate(
    _ conversation: ConversationID, label: String, requestID: ULID?, extra: [ReplicatedRecord] = []
  ) async throws -> ReplicaChange {
    guard !persistenceFailed, !stopping, !membershipRevoked, !awaitsRecovery(conversation) else {
      throw DeviceLayerError.io("device authority recovery required")
    }
    try await recoverPublication(conversation)
    guard let state = conversations[conversation], state.role == .runner,
      let epoch = state.heldEpoch, state.publication == nil
    else {
      emit("writeRefused", conversation: conversation, detail: "not the runner")
      throw FenceError.fenced(currentEpoch: conversations[conversation]?.epoch)
    }
    try await refreshMembership()
    guard let relay else { throw DeviceLayerError.invalid("no lease authority reachable") }
    let trusted = try await authorityState(conversation)
    guard trusted.epoch == epoch, trusted.runner == identity.deviceID,
      (trusted.expiresAt ?? 0) > now()
    else {
      await observe(leaseRecord(conversation, from: trusted))
      throw FenceError.fenced(currentEpoch: trusted.epoch)
    }
    try await reconcile(conversation, against: trusted)
    let operationID = try DeviceULID.next()
    // The journal says that the store was not called under this operation, from before the
    // reservation is requested until just before the store call. So a reservation whose
    // reply was lost, or whose writer stopped in between, can be released: it names no record.
    try await awaitDurable(try enqueuePersist(.reserving(conversation, operationID)))
    let reservation: CommittedIdentity
    do {
      let reserved = try await relay.control(
        .reserve(
          conversation, epoch: epoch, after: trusted.committedRseq, operationID: operationID))
      guard reserved.accepted, let granted = reserved.identity,
        granted.rseq == trusted.committedRseq + 1, granted.epoch == epoch,
        granted.writer == identity.deviceID, granted.operationID == operationID
      else {
        throw DeviceLayerError.invalid("committed history reservation unavailable")
      }
      guard !stopping, !membershipRevoked else { throw DeviceLayerError.closed }
      reservation = granted
      try await awaitDurable(try enqueuePersist(.reserving(conversation, nil)))
    } catch {
      // The store was never called, so the reservation, if the authority holds one, names no
      // record.
      try? await abandonReservation(conversation, operationID)
      throw error
    }
    // If the store fails in any other way, or the publication fails, the write may have
    // happened and the reservation deliberately remains unresolved: neither this node nor a
    // successor may invent a replacement record at its sequence.
    // The store judges the fence only after every lease write this node already decided.
    _ = await leaseWrites[conversation]?.result
    let committed: CommittedChange
    do {
      committed = try await store.commit(
        PendingChange(
          conversationID: conversation, epoch: epoch, label: label, requestID: requestID),
        at: now())
    } catch let refusal as FenceError {
      // The store refused at its fence before writing anything: the reservation is released.
      try? await abandonReservation(conversation, operationID)
      throw refusal
    }
    let rseq = reservation.rseq
    let change = ReplicaChange(
      conversationId: conversation, epoch: epoch, rseq: rseq, records: committed.records + extra,
      events: committed.events, piChanges: [])
    conversations[conversation]?.publication = (operationID, change)
    // Awaited, not blocking: nothing is published before this record is durable, and the node
    // keeps answering and renewing while it waits.
    try await awaitDurable(try enqueuePersist(.publication(operationID, change)))
    let digest = try change.committedDigest()
    let published = try await relay.control(
      .publish(conversation, operationID: operationID, digest: digest))
    guard published.accepted, published.identity?.digest == digest else {
      throw DeviceLayerError.invalid("committed history publication unavailable")
    }
    // The change joins the log in the same actor turn its record is issued, so no concurrent
    // replica apply can journal the same sequence; it is reported and broadcast only once durable.
    let durable = try enqueuePersist(.change(change))
    conversations[conversation] = Self.appending(
      change, digest: digest, to: conversations[conversation] ?? Conversation(),
      logLimit: logLimit)
    try await awaitDurable(durable)
    emit("committed", conversation: conversation, epoch: epoch, rseq: rseq)
    // This commit read membership before it reserved its sequence.
    await broadcast(.replicaChange(change), readsMembership: false)
    return change
  }

  /// Re-publishes the exact locally committed operation after an uncertain authority reply.
  /// It never rebuilds or renumbers the operation, and never clears a missing local payload.
  private func recoverPublication(_ conversation: ConversationID) async throws {
    try await releaseAbandonedReservation(conversation)
    guard let publication = conversations[conversation]?.publication else { return }
    guard !persistenceFailed else { throw DeviceLayerError.io("device state unavailable") }
    guard let relay else { throw DeviceLayerError.closed }
    let digest = try publication.change.committedDigest()
    let reply = try await relay.control(
      .publish(conversation, operationID: publication.operationID, digest: digest))
    guard reply.accepted, reply.identity?.digest == digest,
      reply.identity?.rseq == publication.change.rseq
    else {
      throw DeviceLayerError.invalid("committed history publication unresolved")
    }
    if lastRseq(of: conversation) < publication.change.rseq {
      try append(publication.change, digest: digest)
      emit(
        "committed", conversation: conversation, epoch: publication.change.epoch,
        rseq: publication.change.rseq, detail: "publication reconciled")
      await broadcast(.replicaChange(publication.change))
    }
  }

  /// Journals that `operationID`'s reservation names no local write, then asks the authority to
  /// end it. Only a commit whose store was not called, or refused at its fence, comes here; the
  /// authority also confirms it for a reservation it never recorded.
  private func abandonReservation(_ conversation: ConversationID, _ operationID: ULID) async throws
  {
    conversations[conversation]?.abandoned = operationID
    try persist(.abandoned(conversation, operationID))
    try await releaseAbandonedReservation(conversation)
  }

  /// Repeats the release of an abandoned reservation until the authority confirms it; a lost
  /// reply or a restart in between changes nothing, because the authority confirms a repeat.
  private func releaseAbandonedReservation(_ conversation: ConversationID) async throws {
    guard let operationID = conversations[conversation]?.abandoned else { return }
    guard !persistenceFailed else { throw DeviceLayerError.io("device state unavailable") }
    guard let relay else { throw DeviceLayerError.closed }
    let reply = try await relay.control(.cancelReservation(conversation, operationID: operationID))
    guard reply.accepted else {
      throw DeviceLayerError.invalid("committed history reservation release unresolved")
    }
    conversations[conversation]?.abandoned = nil
    try persist(.abandoned(conversation, nil))
    emit("reservationReleased", conversation: conversation)
  }

  private func append(_ change: ReplicaChange, digest: String) throws {
    try persist(.change(change))
    conversations[change.conversationId] = Self.appending(
      change, digest: digest, to: conversations[change.conversationId] ?? Conversation(),
      logLimit: logLimit)
  }

  private static func appending(
    _ change: ReplicaChange, digest: String, to current: Conversation, logLimit: Int
  ) -> Conversation {
    var state = current
    state.publication = nil
    state.lastRseq = change.rseq
    state.catchUpAfterRseq = nil
    state.log.append(change)
    state.identities[change.rseq] = digest
    if state.log.count > logLimit { state.log.removeFirst(state.log.count - logLimit) }
    for record in change.records where record.kind == "forwardReceipt" {
      if let requestID = try? ULID(record.id), case .object(let value)? = record.value,
        case .string(let message)? = value["messageId"], case .string(let task)? = value["taskId"]
      {
        state.receipts[requestID] = MessageForwardResult(
          conversationId: change.conversationId, requestId: requestID,
          messageId: try? MessageID(message), taskId: try? TaskID(task))
      }
    }
    return state
  }

  /// Every record identity is corroborated by the authority before lease adoption or apply.
  /// Historical records may be replayed by another current member, but never invented by it.
  private enum ReplicaDisposition { case applied, pending, rejected, unavailable }

  private func apply(_ change: ReplicaChange, from sender: DeviceID) async -> ReplicaDisposition {
    guard !stopping else { return .unavailable }
    let conversation = change.conversationId
    do {
      guard let relay else { throw DeviceLayerError.closed }
      let trusted = try await authorityState(conversation)
      let proof = try await relay.control(.identity(conversation, change.rseq))
      let digest = try change.committedDigest()
      guard proof.accepted, let identity = proof.identity, identity.rseq == change.rseq,
        identity.epoch == change.epoch, identity.digest == digest
      else {
        emit(
          "fenced", conversation: conversation, epoch: change.epoch, rseq: change.rseq,
          peer: sender, detail: "uncommitted or conflicting identity")
        try? await deliver(
          .leaseFenced(
            LeaseFenced(
              conversationId: conversation, staleEpoch: change.epoch, currentEpoch: trusted.epoch,
              runnerDeviceId: trusted.runner ?? self.identity.deviceID, what: .change)), to: sender)
        return .rejected
      }
      await observe(leaseRecord(conversation, from: trusted))
      var state = conversations[conversation] ?? Conversation()
      if change.rseq <= state.lastRseq {
        guard state.identities[change.rseq] == digest else {
          emit("historyConflict", conversation: conversation, rseq: change.rseq, peer: sender)
          return .rejected
        }
        emit("duplicate", conversation: conversation, epoch: change.epoch, rseq: change.rseq)
        return .applied
      }
      guard change.rseq == state.lastRseq + 1 else {
        if let pending = state.pending[change.rseq], pending.0 != change {
          emit("historyConflict", conversation: conversation, rseq: change.rseq, peer: sender)
          return .rejected
        }
        state.pending[change.rseq] = (change, sender)
        let needsCatchUp = state.catchUpAfterRseq != state.lastRseq
        state.catchUpAfterRseq = state.lastRseq
        conversations[conversation] = state
        if needsCatchUp {
          try? await deliver(
            .replicaSubscribe(
              ReplicaSubscribe(conversationId: conversation, afterRseq: state.lastRseq)),
            to: sender)
        }
        return .pending
      }
      try append(change, digest: digest)
      emit(
        "applied", conversation: conversation, epoch: change.epoch, rseq: change.rseq, peer: sender)
      if let next = conversations[conversation]?.pending.removeValue(forKey: change.rseq + 1) {
        _ = await apply(next.0, from: next.1)
      }
      return .applied
    } catch {
      emit(
        "replicationUnavailable", conversation: conversation, rseq: change.rseq, detail: "\(error)")
      return .unavailable
    }
  }

  private func authorityState(_ conversation: ConversationID) async throws -> AuthorityConversation
  {
    guard let relay else { throw DeviceLayerError.invalid("no lease authority reachable") }
    return try await relay.conversation(conversation)
  }

  private func reconcile(_ conversation: ConversationID, against trusted: AuthorityConversation)
    async throws
  {
    guard trusted.pending == nil else {
      throw DeviceLayerError.invalid("committed history unavailable: unresolved reservation")
    }
    let local = lastRseq(of: conversation)
    guard local <= trusted.committedRseq else {
      throw DeviceLayerError.invalid("committed history conflicts with authority high-water")
    }
    if local < trusted.committedRseq {
      for peer in Array(links.keys) { await synchronize(with: peer) }
      let deadline = ContinuousClock.now + .seconds(2)
      while lastRseq(of: conversation) < trusted.committedRseq, ContinuousClock.now < deadline,
        !links.values.allSatisfy(\.isEmpty)
      {
        try await Task.sleep(for: .milliseconds(1))
      }
    }
    guard lastRseq(of: conversation) == trusted.committedRseq,
      trusted.committedRseq == 0
        || conversations[conversation]?.identities[trusted.committedRseq]
          == trusted.lastIdentity?.digest
    else {
      emit("historyUnavailable", conversation: conversation, rseq: trusted.committedRseq)
      throw DeviceLayerError.invalid("committed history unavailable at \(trusted.committedRseq)")
    }
  }

  // MARK: - Forwarding

  /// Forwards a message typed on this device to the conversation's runner and waits for its
  /// admission; the answer arrives as replicated changes. The same `requestID` is applied once
  /// however often, and over whichever links, it is sent.
  public func forward(
    _ conversation: ConversationID, requestID: ULID, text: String, prefer route: LinkRoute? = nil,
    timeout: Duration = .seconds(10)
  ) async throws -> MessageForwardResult {
    guard !stopping, !membershipRevoked, !awaitsRecovery(conversation) else {
      throw DeviceLayerError.closed
    }
    guard let runner = conversations[conversation]?.runner, runner != identity.deviceID else {
      throw DeviceLayerError.invalid("no other runner to forward to")
    }
    let id = UUID()
    return try await withCheckedThrowingContinuation { continuation in
      forwardWaiters[requestID, default: [:]][id] = continuation
      handlers.start { [weak self] _ in
        guard let self else { return }
        do {
          try await self.deliver(
            .messageForward(
              MessageForward(
                conversationId: conversation, requestId: requestID,
                content: [.text(TextPart(text: text))], surface: .ui)), to: runner, prefer: route)
        } catch {
          await self.failForward(requestID, id, error)
        }
      }
      handlers.start { [weak self] _ in
        do { try await Task.sleep(for: timeout) } catch { return }
        await self?.failForward(requestID, id, DeviceLayerError.timeout("forward"))
      }
    }
  }

  private func failForward(_ requestID: ULID, _ id: UUID, _ error: any Error) {
    forwardWaiters[requestID]?.removeValue(forKey: id)?.resume(throwing: error)
  }

  /// The runner admits a forwarded message once per `requestId`, then commits its answer.
  private func admit(
    _ forward: MessageForward, from sender: DeviceID,
    acknowledge: @Sendable () async throws -> Void
  ) async {
    guard !stopping, !Task.isCancelled, !membershipRevoked else { return }
    let conversation = forward.conversationId
    if let receipt = conversations[conversation]?.receipts[forward.requestId] {
      emit(
        "forwardDuplicate", conversation: conversation, peer: sender,
        detail: forward.requestId.rawValue)
      guard await acknowledgeInbox(acknowledge) else { return }
      try? await deliver(.messageForwardResult(receipt), to: sender)
      return
    }
    if let running = admissions[forward.requestId] {
      emit(
        "forwardDuplicate", conversation: conversation, peer: sender,
        detail: forward.requestId.rawValue)
      if let result = try? await running.value {
        guard !stopping, !Task.isCancelled else { return }
        guard await acknowledgeInbox(acknowledge) else { return }
        try? await deliver(.messageForwardResult(result), to: sender)
      }
      return
    }
    let text = forward.content.compactMap { part -> String? in
      if case .text(let text) = part { return text.text }
      return nil
    }.joined()
    let task = Task { () async throws -> MessageForwardResult in
      try await self.admitOnce(forward, text: text)
    }
    admissions[forward.requestId] = task
    let result: MessageForwardResult
    do {
      result = try await task.value
    } catch {
      admissions[forward.requestId] = nil
      guard !stopping, !Task.isCancelled, !(error is CancellationError) else { return }
      result = MessageForwardResult(
        conversationId: conversation, requestId: forward.requestId,
        error: RPCError(
          message: "This device does not run the conversation",
          data: RPCErrorData(
            details: .leaseFenced(
              LeaseFencedDetails(currentEpoch: conversations[conversation]?.epoch ?? 0)))))
    }
    admissions[forward.requestId] = nil
    guard !stopping, !Task.isCancelled else { return }
    // Consume before exposing a definitive rejection. Otherwise a crash could replay a
    // previously rejected request as a new action under a future execution lease.
    guard await acknowledgeInbox(acknowledge) else { return }
    try? await deliver(.messageForwardResult(result), to: sender)
    guard !stopping, !Task.isCancelled, result.error == nil else { return }
    emit(
      "forwardAdmitted", conversation: conversation, peer: sender,
      detail: forward.requestId.rawValue)
    for chunk in 1...max(answerChunks, 1) {
      guard !stopping, !Task.isCancelled else { return }
      _ = try? await commit(
        conversation, label: "answer \(chunk)/\(answerChunks) to \(forward.requestId.rawValue)")
    }
  }

  private func admitOnce(_ forward: MessageForward, text: String) async throws
    -> MessageForwardResult
  {
    let conversation = forward.conversationId
    let gate = gate(for: conversation)
    await gate.acquire()
    defer { gate.release() }
    guard !stopping, !Task.isCancelled, !membershipRevoked else { throw DeviceLayerError.closed }
    try await recoverPublication(conversation)
    if let receipt = conversations[conversation]?.receipts[forward.requestId] { return receipt }
    let messageID = try MessageID("msg_" + DeviceULID.make())
    let taskID = try TaskID("tsk_" + DeviceULID.make())
    let receipt = ReplicatedRecord(
      kind: "forwardReceipt", id: forward.requestId.rawValue, op: .upsert,
      value: .object([
        "messageId": .string(messageID.rawValue), "taskId": .string(taskID.rawValue),
      ]))
    _ = try await commitHoldingGate(
      conversation, label: "message: \(text)", requestID: forward.requestId, extra: [receipt])
    return MessageForwardResult(
      conversationId: conversation, requestId: forward.requestId, messageId: messageID,
      taskId: taskID)
  }

  // MARK: - Fencing probes

  /// After losing a lease, tries to write as the old runner would: once through the local store
  /// with the last epoch this device held, and once as a forged change to every linked device.
  /// Returns whether the local store refused; peers answer with `lease.fenced`.
  public func attemptStaleWrite(_ conversation: ConversationID, label: String) async -> Bool {
    guard let state = conversations[conversation], let epoch = state.heldEpoch else { return false }
    let refused: Bool
    _ = await leaseWrites[conversation]?.result
    do {
      _ = try await store.commit(
        PendingChange(conversationID: conversation, epoch: epoch, label: label), at: now())
      refused = false
      emit("staleWriteAccepted", conversation: conversation, epoch: epoch)
    } catch {
      refused = true
      emit("staleWriteRefused", conversation: conversation, epoch: epoch, detail: "\(error)")
    }
    let forged = ReplicaChange(
      conversationId: conversation, epoch: epoch, rseq: state.lastRseq + 1,
      records: [
        ReplicatedRecord(
          kind: "note", id: "stale", op: .upsert, value: .object(["label": .string(label)]))
      ], events: [], piChanges: [])
    await broadcast(.replicaChange(forged))
    return refused
  }

  // MARK: - Dispatch

  private func handle(_ message: DeviceMessage, via link: DeviceLink) async {
    guard !stopping, !Task.isCancelled else { return }
    guard !awaitsRecovery(Self.conversation(of: message.body)) else {
      emit(
        "applicationRecoveryRequired", peer: link.peer.deviceID,
        detail: "native plaintext retained until authority reconciliation")
      return
    }
    do { try await requireMember(link.peer) } catch {
      // A closed authority connection cannot authorize this message, but it does not revoke
      // the already authenticated stream. Retain its Noise state so queued ciphertext stays
      // ordered across reconnect; relayOnline revalidates membership and requests exact history.
      if (error as? DeviceLayerError) != .closed { await link.close() }
      emit("refused", peer: link.peer.deviceID, route: link.route, detail: "membership unavailable")
      return
    }
    await handleAuthenticated(message, from: link.peer, route: link.route) {
      try await self.consume(link, messageID: message.msgId)
    }
  }

  private func handleAuthenticated(
    _ message: DeviceMessage, from peer: DevicePeer, route: LinkRoute?,
    acknowledge: @escaping @Sendable () async throws -> Void
  ) async {
    if await group.ownsJoinCompletion(message) { return }
    guard !stopping, !Task.isCancelled else { return }
    let sender = peer.deviceID
    guard seen.insert(message.msgId) else {
      emit("duplicateMessage", peer: sender, route: route, detail: message.type)
      let committedReplica: Bool
      if case .replicaChange(let change) = message.body, let digest = try? change.committedDigest()
      {
        committedReplica = conversations[change.conversationId]?.identities[change.rseq] == digest
      } else {
        committedReplica = false
      }
      if seen.isComplete(message.msgId) || committedReplica {
        _ = await acknowledgeInbox(acknowledge)
      }
      return
    }
    guard message.from == .device(sender) else {
      emit("refused", peer: sender, route: route, detail: "sender mismatch")
      return
    }
    switch message.body {
    case .replicaChange(let change):
      let disposition = await apply(change, from: sender)
      if disposition == .rejected {
        _ = await acknowledgeInbox(acknowledge)
      } else if let digest = try? change.committedDigest() {
        replicaAcknowledgements[change.conversationId, default: [:]][change.rseq, default: []]
          .append(
            ReplicaAcknowledgement(digest: digest, acknowledge: acknowledge))
      }
      await acknowledgeAppliedInbox(change.conversationId)
      return
    case .replicaSubscribe(let subscribe):
      // An unknown conversation and an unreachable cursor are definitive: nothing to send.
      guard let state = conversations[subscribe.conversationId] else { break }
      let missing = state.log.filter { $0.rseq > subscribe.afterRseq }
      guard subscribe.afterRseq >= 0,
        subscribe.afterRseq >= state.lastRseq || missing.first?.rseq == subscribe.afterRseq + 1
      else {
        emit(
          "historyUnavailable", conversation: subscribe.conversationId,
          rseq: subscribe.afterRseq, peer: sender, detail: "retained log does not reach cursor")
        break
      }
      for change in missing { try? await deliver(.replicaChange(change), to: sender) }
    case .leaseGranted(let granted):
      do {
        let trusted = try await authorityState(granted.conversationId)
        guard trusted.epoch == granted.epoch, trusted.runner == granted.runnerDeviceId,
          sender == granted.runnerDeviceId
        else {
          emit(
            "untrustedGrant", conversation: granted.conversationId, epoch: granted.epoch,
            peer: sender)
          _ = await acknowledgeInbox(acknowledge)
          return
        }
        await observe(leaseRecord(granted.conversationId, from: trusted))
        emit(
          "observedGrant", conversation: granted.conversationId, epoch: trusted.epoch,
          peer: trusted.runner, detail: granted.reason.rawValue)
      } catch {
        emit(
          "leaseObservationUnavailable", conversation: granted.conversationId, detail: "\(error)")
        seen.allowRetry(message.msgId)
        return
      }
    case .leaseRequest(let request):
      do {
        let trusted = try await authorityState(request.conversationId)
        guard trusted.runner == identity.deviceID, trusted.epoch == request.expectedEpoch,
          (trusted.expiresAt ?? 0) > now()
        else {
          emit(
            "staleHandOverRequest", conversation: request.conversationId,
            epoch: request.expectedEpoch, peer: sender)
          _ = await acknowledgeInbox(acknowledge)
          return
        }
      } catch {
        emit(
          "handOverAuthorityUnavailable", conversation: request.conversationId, detail: "\(error)")
        return
      }
      handlers.start { [weak self] _ in
        guard let self else { return }
        await self.handOver(
          request.conversationId, to: sender, expectedEpoch: request.expectedEpoch)
        _ = await self.acknowledgeInbox(acknowledge)
      }
      return
    case .leaseHandOver(let handOver):
      guard handOver.toDeviceId == identity.deviceID else { return }
      emit(
        "handOverReceived", conversation: handOver.conversationId, epoch: handOver.epoch,
        peer: sender)
      handlers.start { [weak self] _ in
        guard let self else { return }
        await self.takeHandOver(handOver, from: sender)
        _ = await self.acknowledgeInbox(acknowledge)
      }
      return
    case .leaseFenced(let fenced):
      emit(
        "staleRejectedByPeer", conversation: fenced.conversationId, epoch: fenced.staleEpoch,
        peer: sender, detail: "current \(fenced.currentEpoch)")
      if let trusted = try? await authorityState(fenced.conversationId) {
        await observe(leaseRecord(fenced.conversationId, from: trusted))
      }
    case .messageForward(let forward):
      handlers.start { [weak self] _ in
        await self?.admit(forward, from: sender, acknowledge: acknowledge)
      }
      return
    case .messageForwardResult(let result):
      if result.error == nil,
        conversations[result.conversationId]?.receipts[result.requestId] == nil
      {
        deferredResults[result.conversationId, default: [:]][result.requestId, default: []].append(
          DeferredForwardResult(acknowledge: acknowledge, result: result))
        try? await deliver(
          .replicaSubscribe(
            ReplicaSubscribe(
              conversationId: result.conversationId, afterRseq: lastRseq(of: result.conversationId))
          ),
          to: sender)
        return
      }
      if result.error != nil {
        do {
          let trusted = try await authorityState(result.conversationId)
          guard trusted.runner == sender, (trusted.expiresAt ?? 0) > now() else {
            emit("forwardRejectionUntrusted", conversation: result.conversationId, peer: sender)
            // The rejection carries no authority and is consumed; the forward input is kept.
            break
          }
          try await retireOwnForwardInput(result)
          resolveForward(result)
        } catch {
          emit(
            "forwardRejectionUnavailable", conversation: result.conversationId, detail: "\(error)")
          return
        }
      } else if conversations[result.conversationId]?.receipts[result.requestId] == result {
        do { try await retireOwnForwardInput(result) } catch {
          emit("forwardReceiptUnavailable", conversation: result.conversationId, detail: "\(error)")
          return
        }
        resolveForward(result)
      } else {
        emit("forwardResultConflict", conversation: result.conversationId, peer: sender)
      }
    case .deviceHello:
      break  // The native sender and its source-bound recipient were already authenticated.
    default:
      emit("applicationConsumerRequired", peer: sender, detail: message.type)
      return  // Preserve unsupported authenticated input; no pretend handler or delivery ACK.
    }
    _ = await acknowledgeInbox(acknowledge)
  }

  // MARK: - Helpers

  /// Whether work on a conversation still waits for `recover()`: the whole node after a
  /// reopen, or this conversation alone when it could not reconcile.
  private func awaitsRecovery(_ conversation: ConversationID?) -> Bool {
    requiresRecovery || conversation.map(unreconciled.contains) == true
  }

  /// The conversation a device message acts on, if it names one.
  private static func conversation(of body: DeviceMessageBody) -> ConversationID? {
    switch body {
    case .replicaChange(let change): change.conversationId
    case .replicaSubscribe(let subscribe): subscribe.conversationId
    case .leaseGranted(let granted): granted.conversationId
    case .leaseRequest(let request): request.conversationId
    case .leaseHandOver(let handOver): handOver.conversationId
    case .leaseFenced(let fenced): fenced.conversationId
    case .messageForward(let forward): forward.conversationId
    case .messageForwardResult(let result): result.conversationId
    default: nil
    }
  }

  private func resolveForward(_ result: MessageForwardResult) {
    for waiter in (forwardWaiters.removeValue(forKey: result.requestId) ?? [:]).values {
      waiter.resume(returning: result)
    }
  }

  private func consume(_ link: DeviceLink, messageID: ULID) async throws {
    seen.complete(messageID)
    try await link.acknowledgeReceived(messageID)
  }

  private func consume(receiptID: String, messageID: ULID) async throws {
    seen.complete(messageID)
    try await group.acknowledgeOpened(receiptIDs: [receiptID])
  }

  private func retireOwnForwardInput(_ result: MessageForwardResult) async throws {
    var ids: [String] = []
    for receipt in try await group.pendingApplicationReceipts()
    where receipt.opened.sender == identity.peer.mlsCredential {
      guard let message = try DeviceGroup.nodeMessage(receipt, groupID: await group.groupID),
        case .messageForward(let forward) = message.body,
        forward.conversationId == result.conversationId, forward.requestId == result.requestId
      else { continue }
      ids.append(receipt.id)
    }
    try await group.acknowledgeOpened(receiptIDs: ids)
  }

  private func consumeApplied(
    _ link: DeviceLink, conversation: ConversationID, through cursor: Int64
  ) async throws {
    let completed = try await link.acknowledgeApplied(conversation, through: cursor)
    for id in completed { seen.complete(id) }
  }

  private func acknowledgeInbox(_ acknowledge: @Sendable () async throws -> Void) async -> Bool {
    do {
      try await acknowledge()
      return true
    } catch {
      emit("inboxCheckpointUnavailable", detail: "\(error)")
      return false
    }
  }

  private func acknowledgeAppliedInbox(_ conversation: ConversationID) async {
    let cursor = lastRseq(of: conversation)
    for routes in links.values {
      for link in routes.values {
        _ = await acknowledgeInbox {
          try await self.consumeApplied(link, conversation: conversation, through: cursor)
        }
      }
    }
    let sequences = replicaAcknowledgements[conversation]?.keys.map { $0 } ?? []
    for sequence in sequences
    where sequence <= cursor {
      guard let canonical = conversations[conversation]?.identities[sequence],
        let acknowledgements = replicaAcknowledgements[conversation]?.removeValue(forKey: sequence)
      else { continue }
      for entry in acknowledgements where entry.digest == canonical {
        _ = await acknowledgeInbox(entry.acknowledge)
      }
    }
    if replicaAcknowledgements[conversation]?.isEmpty == true {
      replicaAcknowledgements[conversation] = nil
    }
    guard let pending = deferredResults[conversation] else { return }
    for request in pending.keys {
      guard let canonical = conversations[conversation]?.receipts[request],
        let replies = deferredResults[conversation]?.removeValue(forKey: request)
      else { continue }
      for reply in replies {
        if reply.result == canonical {
          do { try await retireOwnForwardInput(canonical) } catch {
            emit("forwardReceiptUnavailable", conversation: conversation, detail: "\(error)")
            continue
          }
          resolveForward(canonical)
        } else {
          emit("forwardResultConflict", conversation: conversation)
        }
        _ = await acknowledgeInbox(reply.acknowledge)
      }
    }
    if deferredResults[conversation]?.isEmpty == true { deferredResults[conversation] = nil }
  }

  /// Appends after every earlier journal write and blocks the node until it is durable. Lease
  /// decisions (claim, loss, fencing, hand-over, observed epochs) and replica applies use this:
  /// their in-memory change and its durable record happen in one actor turn.
  private func persist(_ record: JournalRecord) throws {
    guard !persistenceFailed, !removalErased else {
      throw DeviceLayerError.io("device state unavailable")
    }
    do {
      try journalWriter?.appendNow(record)
    } catch {
      persistenceFailed = true
      throw error
    }
  }

  /// Issues an append after every earlier journal write without waiting for it; nil without a
  /// journal. The caller either awaits it with ``awaitDurable(_:)`` or reports its failure.
  private func enqueuePersist(_ record: JournalRecord) throws -> PendingJournalWrite? {
    guard !persistenceFailed, !removalErased else {
      throw DeviceLayerError.io("device state unavailable")
    }
    return journalWriter?.enqueue(record)
  }

  /// Suspends, without blocking the node, until an issued append is durable.
  private func awaitDurable(_ write: PendingJournalWrite?) async throws {
    do {
      try await write?.value()
    } catch {
      persistenceFailed = true
      throw error
    }
  }

  private func gate(for conversation: ConversationID) -> SerialGate {
    if let gate = gates[conversation] { return gate }
    let gate = SerialGate()
    gates[conversation] = gate
    return gate
  }

  private func emit(
    _ kind: String, conversation: ConversationID? = nil, epoch: Int64? = nil, rseq: Int64? = nil,
    peer: DeviceID? = nil, route: LinkRoute? = nil, detail: String? = nil
  ) {
    sink.yield(
      NodeEvent(
        kind: kind, at: DeviceClock.monotonicNanoseconds(), conversation: conversation?.rawValue,
        epoch: epoch, rseq: rseq, peer: peer?.rawValue, route: route?.rawValue, detail: detail))
  }
}

/// Replays one already-received frame, then reads from the underlying channel.
final class PrefetchedChannel: FrameChannel {
  private let first: Locked<Data?>
  private let inner: any FrameChannel

  init(first: Data, inner: any FrameChannel) {
    self.first = Locked(first)
    self.inner = inner
  }

  func send(_ frame: Data) throws { try inner.send(frame) }

  func receive() async throws -> Data {
    if let frame = first.withLock({ value -> Data? in
      defer { value = nil }
      return value
    }) {
      return frame
    }
    return try await inner.receive()
  }

  func close() { inner.close() }
}

/// A FIFO async mutex for one conversation's writes and hand-over.
final class SerialGate: Sendable {
  private struct State {
    var held = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = Locked(State())

  func acquire() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let granted = state.withLock { state -> Bool in
        if state.held {
          state.waiters.append(continuation)
          return false
        }
        state.held = true
        return true
      }
      if granted { continuation.resume() }
    }
  }

  func release() {
    let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
      if state.waiters.isEmpty {
        state.held = false
        return nil
      }
      return state.waiters.removeFirst()
    }
    next?.resume()
  }

  /// How many tasks wait for the gate.
  var waiting: Int { state.withLock { $0.waiters.count } }
}

/// Remembers recent message IDs so a message that arrives twice, or over two links, applies once.
struct MessageWindow {
  private enum State {
    case processing
    case retryable
    case complete
  }

  private var members: [ULID: State] = [:]
  private var order: [ULID] = []
  private var head = 0
  let capacity: Int

  init(capacity: Int) { self.capacity = capacity }

  /// Admits a new ID or a retained notice whose authority check was unavailable.
  /// Retrying reuses its existing capacity slot; concurrent in-flight duplicates stay inert.
  mutating func insert(_ id: ULID) -> Bool {
    if let previous = members[id] {
      guard case .retryable = previous else { return false }
      members[id] = .processing
      return true
    }
    members[id] = .processing
    order.append(id)
    if order.count - head > capacity {
      members.removeValue(forKey: order[head])
      head += 1
      if head > capacity {
        order.removeFirst(head)
        head = 0
      }
    }
    return true
  }

  func isComplete(_ id: ULID) -> Bool {
    if case .complete? = members[id] { return true }
    return false
  }

  mutating func allowRetry(_ id: ULID) {
    if case .processing? = members[id] { members[id] = .retryable }
  }

  mutating func complete(_ id: ULID) {
    if members[id] != nil { members[id] = .complete }
  }
}
