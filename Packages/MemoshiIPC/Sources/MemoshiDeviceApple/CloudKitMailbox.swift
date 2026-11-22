import CloudKit
import Foundation
import MemoshiProtocol

/// Explicit per-host opt-in. Constructing a configuration, spool or mailbox performs no cloud call.
/// The host must validate its signed CloudKit/APNs entitlements before calling activate().
public struct CloudDeviceConfiguration: Hashable, Sendable {
  /// Container selected at explicit activation; this constant does not provision entitlements
  /// or establish that the current host/account can access it.
  public static let containerIdentifier = "iCloud.com.mehmetcanbudak.memoshi"
  /// Private custom-zone name derived from the supplied group identifier, not membership evidence.
  public let zoneName: String
  /// Database-subscription identifier used to match content-free wake hints.
  public let subscriptionID: String
  /// Interval in seconds between explicit fallback fetches while the mailbox is active.
  public let backstopSeconds: UInt64

  /// Derives names without I/O. Requires a nonempty ASCII alphanumeric/hyphen group identifier
  /// of at most 128 UTF-8 bytes and a backstop interval of 60 through 3,600 seconds.
  public init(groupID: String, backstopSeconds: UInt64 = 300) throws {
    guard !groupID.isEmpty, groupID.utf8.count <= 128,
      groupID.utf8.allSatisfy({
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
      }),
      (60...3_600).contains(backstopSeconds)
    else { throw AppleDeviceError.invalidState("CloudKit configuration") }
    zoneName = "MemoshiDevices-" + groupID
    subscriptionID = "memoshi.devices." + groupID
    self.backstopSeconds = backstopSeconds
  }
}

/// Caller-declared trigger for the same authoritative fetch path; none carries message authority.
public enum CloudFetchReason: String, Sendable {
  case launch, wake, relayNudge, push, backstop, user
}

/// Parse on the native delegate's actor, then send only this content-free typed hint.
public struct CloudWakeHint: Sendable {
  fileprivate let subscriptionID: String
  fileprivate let containerIdentifier: String

  /// Extracts subscription/container identifiers from a CloudKit notification, or returns `nil`
  /// when absent. Parsing does not match this host's subscription, fetch, or trust payload data.
  public static func parse(_ userInfo: [AnyHashable: Any]) -> CloudWakeHint? {
    guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
      let subscriptionID = notification.subscriptionID,
      let containerIdentifier = notification.containerIdentifier
    else { return nil }
    return CloudWakeHint(subscriptionID: subscriptionID, containerIdentifier: containerIdentifier)
  }
}

struct CloudAuthorityContext: Sendable {
  let database: CKDatabase
  let zone: CKRecordZone.ID
}

/// Coalesced ciphertext wake samples, not delivery receipts. Consumers recover the complete,
/// ordered inbox from the durable CloudMailboxStore before opening the sample's MLS epoch.
/// Dropping an older wake sample never deletes or acknowledges its retained mailbox record.
public struct CloudFrameSubscription: Sendable {
  let id: UUID
  /// Newest-only ciphertext sample stream with capacity one. Read the shared durable spool for
  /// the complete ordered inbox; consuming a sample does not acknowledge a message.
  public let frames: AsyncThrowingStream<Data, any Error>
}

/// CKSyncEngine owns its normal change tokens/batches. The explicit zone fetch has a separate
/// durable token and always contacts CloudKit, even if no push marked the engine's zone dirty.
/// Only MLS ciphertext is stored in encryptedValues; no message JSON is assigned to CKRecord.
public actor CloudKitMailbox: CKSyncEngineDelegate {
  private var subscribers: [UUID: AsyncThrowingStream<Data, any Error>.Continuation] = [:]
  private let configuration: CloudDeviceConfiguration
  private let spool: CloudMailboxStore
  private var container: CKContainer?
  private var database: CKDatabase?
  private var engine: CKSyncEngine?
  private var timer: Task<Void, Never>?
  private var active = false
  private var activating = false
  private var stopped = false
  private var failure: (any Error)?
  private var backgroundFailure: (any Error)?
  private var fetchTask: Task<Void, any Error>?
  private weak var feedWriter: CloudKitFeedAuthority?
  private var epoch = UUID()

  /// Retains configuration and the caller-owned durable spool without cloud calls.
  /// Explicit activation and host consent remain separate from construction.
  public init(configuration: CloudDeviceConfiguration, spool: CloudMailboxStore) {
    self.configuration = configuration
    self.spool = spool
  }

  private var zoneID: CKRecordZone.ID {
    CKRecordZone.ID(zoneName: configuration.zoneName, ownerName: CKCurrentUserDefaultName)
  }

  /// Subscribes to coalesced wake samples on an active mailbox, seeding from the latest retained
  /// frame when present. Full inbox recovery requires this mailbox's spool; inactive/read failures throw.
  public func subscribe() async throws -> CloudFrameSubscription {
    try requireActive()
    let id = UUID()
    let (frames, continuation) = AsyncThrowingStream<Data, any Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeSubscription(id) }
    }
    subscribers[id] = continuation
    do {
      let backlog = try await spool.incoming()
      try requireActive()
      if let latest = backlog.last { continuation.yield(latest.bytes) }
      return CloudFrameSubscription(id: id, frames: frames)
    } catch {
      subscribers.removeValue(forKey: id)?.finish(throwing: error)
      throw error
    }
  }

  /// Finishes this local subscription without stopping synchronization or removing spool records.
  public func unsubscribe(_ subscription: CloudFrameSubscription) {
    removeSubscription(subscription.id)
  }

  private func removeSubscription(_ id: UUID) {
    subscribers.removeValue(forKey: id)?.finish()
  }

  private func publishWake(_ bytes: Data) {
    var terminated: [UUID] = []
    for (id, continuation) in subscribers {
      if case .terminated = continuation.yield(bytes) { terminated.append(id) }
    }
    for id in terminated { subscribers[id] = nil }
  }

  private func finishSubscriptions(throwing error: (any Error)? = nil) {
    let active = subscribers.values
    subscribers.removeAll()
    for continuation in active { continuation.finish(throwing: error) }
  }

  /// The only activation entrypoint. This is an actual account lookup, zone/subscription save
  /// and launch fetch. Normal app composition MUST NOT call it without explicit user opt-in.
  public func activate(allowZoneCreation: Bool) async throws {
    guard !stopped, !activating, engine == nil, !active, failure == nil else {
      throw AppleDeviceError.invalidState("mailbox activation")
    }
    activating = true
    defer { activating = false }
    let activationEpoch = epoch
    let container = CKContainer(identifier: CloudDeviceConfiguration.containerIdentifier)
    guard try await container.accountStatus() == .available else {
      throw AppleDeviceError.authorityUnavailable
    }
    let user = try await container.userRecordID()
    try await spool.bind(account: user.recordName)
    guard epoch == activationEpoch else { throw AppleDeviceError.closed }
    let database = container.privateCloudDatabase
    // Creation is explicit, scoped to this group's private custom zone, never a global setup step.
    if allowZoneCreation { _ = try await database.save(CKRecordZone(zoneID: zoneID)) }
    guard epoch == activationEpoch, !stopped else { throw AppleDeviceError.closed }
    let subscription = CKDatabaseSubscription(subscriptionID: configuration.subscriptionID)
    let notification = CKSubscription.NotificationInfo()
    notification.shouldSendContentAvailable = true
    // No alert body/title, sound, badge, localization arguments or desiredKeys: content-free hint.
    subscription.notificationInfo = notification
    _ = try await database.save(subscription)
    guard epoch == activationEpoch else { throw AppleDeviceError.closed }
    let serialization = try await spool.engineState().map {
      try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
    }
    var settings = CKSyncEngine.Configuration(
      database: database, stateSerialization: serialization, delegate: self)
    settings.subscriptionID = configuration.subscriptionID
    settings.automaticallySync = false
    let engine = CKSyncEngine(settings)
    self.container = container
    self.database = database
    self.engine = engine
    active = true
    try await fetch(reason: .launch)
    let interval = configuration.backstopSeconds
    timer = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .seconds(interval))
          guard let self else { return }
          try await self.fetch(reason: .backstop)
          try await self.flush()
        } catch {
          // Only this timer's own cancellation ends the backstop. A cancellation that reaches it
          // through a fetch or flush shared with another caller is one failed round.
          if Task.isCancelled { return }
          await self?.recordTransientFetchFailure(error)
        }
      }
    }
  }

  func enqueueCiphertext(_ ciphertext: Data) async throws {
    try requireActive()
    _ = try DeviceTransportPacket(decoding: ciphertext)
    let frame = DeviceCiphertext(bytes: ciphertext)
    try await spool.enqueue(frame)
  }

  func installFeedWriter(_ writer: CloudKitFeedAuthority) throws {
    try requireActive()
    guard feedWriter == nil else {
      throw AppleDeviceError.invalidState("feed writer already installed")
    }
    feedWriter = writer
  }

  /// Flushes retained outbound ciphertext through the installed conditional feed writer.
  /// Inactive state, a missing writer, or save failures throw; success is not a host-apply receipt.
  public func flush() async throws {
    try requireActive()
    guard let feedWriter else { throw AppleDeviceError.stateRecoveryRequired }
    try await feedWriter.flush()
    backgroundFailure = nil
    try requireActive()
  }

  /// Launch, wake, relay nudge and backstop all use the same forced fetch, not a fake push.
  public func fetch(reason: CloudFetchReason) async throws {
    try requireActive()
    if let fetchTask { return try await fetchTask.value }
    let task = Task { try await self.performFetch(reason: reason) }
    fetchTask = task
    defer { fetchTask = nil }
    try await task.value
    // Publish only after the complete explicit fetch is durable, globally sorted by epoch.
    // CK callbacks/page boundaries are not an application or MLS ordering guarantee.
    if let latest = try await spool.incoming().last { publishWake(latest.bytes) }
    backgroundFailure = nil
  }

  private func performFetch(reason: CloudFetchReason) async throws {
    guard let engine, let database else { throw AppleDeviceError.closed }
    let generation = epoch
    try await engine.fetchChanges(.init(scope: .zoneIDs([zoneID])))
    try requireActive()
    var token =
      try await spool.explicitFetchToken().map {
        try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
      } ?? nil
    var resetExpiredToken = false
    while true {
      do {
        let changes = try await database.recordZoneChanges(
          inZoneWith: zoneID, since: token, resultsLimit: 200)
        guard generation == epoch else { throw AppleDeviceError.closed }
        let records = try changes.modificationResultsByID.values.map { try $0.get().record }
        try await retain(records)
        // Deletion does not authorize skipping an unapplied message. The durable local inbox
        // survives server deletion; immutable log records are never deleted by this module.
        token = changes.changeToken
        let encoded = try NSKeyedArchiver.archivedData(
          withRootObject: changes.changeToken, requiringSecureCoding: true)
        try await spool.persistFetchToken(encoded)
        if !changes.moreComing { return }
      } catch let error as CKError where error.code == .changeTokenExpired && !resetExpiredToken {
        resetExpiredToken = true
        token = nil
        try await spool.persistFetchToken(nil)
      }
    }
  }

  /// APNs registration remains the signed host's explicit responsibility.
  public func receivedWake(_ hint: CloudWakeHint) async throws -> Bool {
    guard hint.subscriptionID == configuration.subscriptionID,
      hint.containerIdentifier == CloudDeviceConfiguration.containerIdentifier
    else { return false }
    try await fetch(reason: .push)
    return true
  }

  /// Permanently stops this mailbox's timer/fetch/engine work and finishes local subscriptions.
  /// Does not delete remote records, unregister APNs, or close/delete the caller-owned spool.
  public func stop() async {
    stopped = true
    active = false
    epoch = UUID()
    timer?.cancel()
    timer = nil
    fetchTask?.cancel()
    fetchTask = nil
    await engine?.cancelOperations()
    engine = nil
    database = nil
    container = nil
    finishSubscriptions()
  }

  /// Persists engine serialization and fetched ciphertext, enforcing account/zone continuity.
  /// Delegate failures deactivate synchronization and finish subscriptions with that error;
  /// callbacks do not authorize application delivery or write outbound records.
  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    guard active else { return }
    do {
      switch event {
      case .stateUpdate(let update):
        try await spool.persistEngineState(JSONEncoder().encode(update.stateSerialization))
      case .fetchedRecordZoneChanges(let changes):
        try await retain(changes.modifications.map(\.record))
      case .accountChange(let change):
        switch change.changeType {
        case .signIn(let currentUser): try await spool.bind(account: currentUser.recordName)
        case .signOut, .switchAccounts: throw AppleDeviceError.accountChanged
        @unknown default: throw AppleDeviceError.accountChanged
        }
      case .fetchedDatabaseChanges(let changes):
        if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
          throw AppleDeviceError.invalidState("CloudKit group zone deleted")
        }
      default: break
      }
    } catch {
      failure = error
      active = false
      timer?.cancel()
      timer = nil
      finishSubscriptions(throwing: error)
      // Delegate events are serial. Do not recursively invoke fetch/send/cancel inside them.
    }
  }

  /// Intentionally returns no engine write batch: outbound records must use the atomic
  /// group-head/feed-head conditional-save path, which prevents appends after epoch closure.
  public func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    // Outbound records require group-head + feed-head + immutable ordinal CAS. Returning no
    // write batch is intentional: CKSyncEngine is used for real fetch/state/subscriptions,
    // never an asynchronous write path that could append after an epoch was closed.
    return nil
  }

  private func retain(_ records: [CKRecord]) async throws {
    let messages = try records.filter { $0.recordType == "MemoshiMLSMessage" }.map { record in
      guard record.recordID.zoneID == zoneID,
        let bytes = record.encryptedValues["mls"] as? Data
      else { throw AppleDeviceError.invalidState("CloudKit encrypted record") }
      let packet = try DeviceTransportPacket(decoding: bytes)
      let frame = DeviceCiphertext(bytes: bytes)
      guard CloudKitFeedAuthority.recordID(packet.position, zone: zoneID) == record.recordID else {
        throw AppleDeviceError.conflictingReplay
      }
      return frame
    }
    _ = try await spool.fetched(messages)
    if fetchTask == nil {
      if let latest = try await spool.incoming().last { publishWake(latest.bytes) }
    }
  }

  func authorityContext() throws -> CloudAuthorityContext {
    try requireActive()
    guard let database else { throw AppleDeviceError.closed }
    return CloudAuthorityContext(database: database, zone: zoneID)
  }

  private func requireActive() throws {
    if let failure { throw failure }
    guard active else { throw AppleDeviceError.disabled }
  }

  private func recordTransientFetchFailure(_ error: any Error) {
    backgroundFailure = error
    // The durable outbox/inbox and cursors are unchanged. A later explicit trigger retries sync;
    // this is not a successful fetch and does not grant a lease or acknowledge application.
    if !(error is CKError), !(error is AppleDeviceError), !(error is CancellationError) {
      failure = error
      active = false
      finishSubscriptions(throwing: error)
    }
  }

  /// Returns a retained fatal or background fetch failure without triggering synchronization.
  public func synchronizationFailure() -> (any Error)? { failure ?? backgroundFailure }

}
