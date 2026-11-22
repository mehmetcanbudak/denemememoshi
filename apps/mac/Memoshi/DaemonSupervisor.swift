import AppCore
import AppKit
import Darwin
import Foundation
import MemoshiClient
import MemoshiProtocol
import MemoshiRuntime
import MemoshiTransport
import Observation
import ServiceManagement

/// Registration is permission to run, not evidence of a live process or an authenticated peer.
enum DaemonRegistration: Equatable {
  case notRegistered
  case enabled
  case requiresApproval
  case notFound
  case unknown

  init(_ status: SMAppService.Status) {
    switch status {
    case .notRegistered: self = .notRegistered
    case .enabled: self = .enabled
    case .requiresApproval: self = .requiresApproval
    case .notFound: self = .notFound
    @unknown default: self = .unknown
    }
  }
}

enum DaemonSupervisionError: Error, Equatable {
  case signingRequired
  case versionMismatch
  case damagedBundle
  case unsafeDataDirectory
  case authenticationFailed
  case startServiceFailed
  case registrationFailed
  case existingDaemonNotOwned
  case connectionFailed
  case helperExited(Int32)
  case helperTerminated(signal: Int32)
  case restartLimitReached(exits: Int)
  case quitBlocked
  case agentStillRunning
}

/// What a supervisor operation is waiting for. While it waits, a socket that is missing or
/// refused is expected, so the client's `daemonStopped` is not what the status says
/// (protocol.md §3.1: stopped means missing for 3 s with no agent running).
enum DaemonWait: Equatable {
  /// Looking for a daemon that may already be running.
  case connecting
  /// A helper this app started, or the registered agent it started, has not opened its socket
  /// yet (D130: this app's own helper is awaited up to 120 s).
  case helperStarting
  /// The background service was unregistered and its daemon has not exited yet.
  case agentStopping
}

/// The one line the status popover gives about the connection, most specific first.
enum DaemonStatusNote: Equatable {
  case problem(DaemonSupervisionError)
  case waiting(DaemonWait)
  case daemonStopped
  case versionMismatch
  case signingRequired

  init?(problem: DaemonSupervisionError?, wait: DaemonWait?, client: ClientConnectionState?) {
    if let problem {
      self = .problem(problem)
    } else if let wait {
      self = .waiting(wait)
    } else {
      switch client {
      case .daemonStopped: self = .daemonStopped
      case .versionMismatch: self = .versionMismatch
      case .signingRequired: self = .signingRequired
      default: return nil
      }
    }
  }
}

/// Automatic recovery of the app-owned helper after an exit this app did not request.
enum HelperRecovery: Equatable {
  case idle
  case restarting(attempt: Int)
  case stopped(exits: Int)
}

/// Owns the authenticated helper lifetime; UI state never becomes a canonical transcript store.
@MainActor
@Observable
final class DaemonSupervisor {
  let isDevelopmentChat: Bool

  /// 04-architecture §2.3 treats three crashes within five minutes as a crash loop: automatic
  /// restarts stop there until the user explicitly starts the helper again.
  static let crashLoopExits = 3
  static let crashLoopWindow = Duration.seconds(300)
  /// How long this app's own running helper is awaited before its socket answers. Longer than
  /// the slowest storage stall the handoff records (96 s); a hung helper ends the wait here.
  static let helperStartCeiling = Duration.seconds(120)
  /// How long an unregistered agent's daemon is awaited before this app starts its own helper.
  /// launchd kills a job that outlives the plist's 30 s `ExitTimeOut`, so this bound is only
  /// passed if that kill failed.
  static let agentStopCeiling = Duration.seconds(35)

  init(developmentChat: Bool = false) {
    self.isDevelopmentChat = developmentChat
    #if DEBUG
      linkConditioner = DevelopmentLinkConditioner()
    #else
      linkConditioner = developmentChat ? DevelopmentLinkConditioner() : nil
    #endif
  }

  /// Exposes only a client that has completed real peer authentication and hello.
  var authenticatedClient: MemoshiClient? {
    hasAuthenticatedDaemon ? client : nil
  }
  private(set) var registration = DaemonRegistration.notRegistered
  private(set) var clientStatus: ClientStatus?
  private(set) var daemonStatus: SystemStatusResult?
  private(set) var isBusy = false
  private(set) var isAppOwned = false
  private(set) var problem: DaemonSupervisionError?
  private(set) var helperRecovery = HelperRecovery.idle
  /// What the operation in progress is waiting for, if anything.
  private(set) var wait: DaemonWait?
  private(set) var lastHelperExit: OwnedDaemonProcess.Exit?
  /// The debug menu's per-frame delay for this app session; never persisted.
  private(set) var injectedLatency = Duration.zero

  @ObservationIgnored private let service = SMAppService.agent(
    plistName: "com.mehmetcanbudak.memoshi.memoshid.plist")
  @ObservationIgnored private let label = "com.mehmetcanbudak.memoshi.memoshid"
  @ObservationIgnored private var client: MemoshiClient?
  @ObservationIgnored private(set) var modelKeychain: ModelKeychain?
  @ObservationIgnored private(set) var chatGPTSubscription: ChatGPTSubscription?
  @ObservationIgnored private var owned: OwnedDaemonProcess?
  @ObservationIgnored private var operationTask: Task<Void, Never>?
  @ObservationIgnored private var statusTask: Task<Void, Never>?
  @ObservationIgnored private var pollingTask: Task<Void, Never>?
  @ObservationIgnored private var hasStarted = false
  @ObservationIgnored private var isQuitting = false
  @ObservationIgnored private var unexpectedExits: [ContinuousClock.Instant] = []
  @ObservationIgnored private var restartTask: Task<Void, Never>?
  /// Development composition only: carries the debug menu's latency and drop hooks.
  @ObservationIgnored private let linkConditioner: DevelopmentLinkConditioner?
  @ObservationIgnored private var announcedConnectionID: String?

  /// Called once per authenticated connection, and for the current one when set. No window's
  /// view update is involved, so the app-lifetime consumer attaches with every window closed.
  @ObservationIgnored var onAuthenticated: (@MainActor (MemoshiClient) -> Void)? {
    didSet {
      guard let client = authenticatedClient else { return }
      announcedConnectionID = clientStatus?.hello?.connectionId
      onAuthenticated?(client)
    }
  }

  private var dataDirectory: URL {
    URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      .appendingPathComponent(
        isDevelopmentChat
          ? "Library/Application Support/Memoshi Development/Text Chat"
          : "Library/Application Support/Memoshi", isDirectory: true)
  }

  /// Active Memoshi data root shared with `memoshid`'s personal host tools (Notes, Mail drafts).
  var activeDataDirectory: URL { dataDirectory }

  private var helperExecutable: URL {
    Bundle.main.bundleURL.appendingPathComponent(
      "Contents/Helpers/memoshid.app/Contents/MacOS/memoshid")
  }

  var hasAuthenticatedDaemon: Bool { clientStatus?.hello != nil }

  /// Starting the app never registers an agent or changes login/background preferences.
  func start() {
    guard !hasStarted else { return }
    hasStarted = true
    refreshRegistration()
    startPolling()
    retryConnection()
  }

  func retryConnection() {
    // An explicit start or reconnect ends any earlier crash-loop hold.
    restartTask?.cancel()
    restartTask = nil
    unexpectedExits.removeAll()
    helperRecovery = .idle
    runOperation {
      await self.client?.disconnect()
      try await self.connectOrStart()
    }
  }

  /// The running helper this app started and still owns, once it has answered hello.
  var ownedHelperPID: Int? {
    guard isAppOwned, let owned, owned.isRunning, clientStatus?.hello?.daemon.pid == owned.pid
    else { return nil }
    return owned.pid
  }

  /// The debug menu offers latency and drop only in the development composition.
  var supportsLinkConditions: Bool { linkConditioner != nil }

  /// Debug menu only: SIGKILL this app's own authenticated helper after the user confirmed
  /// that PID. A registered LaunchAgent, a discovered PID or a helper replaced since the
  /// confirmation is never signaled. Recovery is the ordinary unexpected-exit path.
  @discardableResult
  func killOwnedHelperForDevelopment(confirmedPID: Int) -> Bool {
    #if DEBUG
      let allowed = true
    #else
      let allowed = isDevelopmentChat
    #endif
    guard allowed, !isQuitting, let owned, ownedHelperPID == confirmedPID else {
      return false
    }
    return owned.killForDevelopment()
  }

  /// Debug menu only: closes the live client carrier as a transport failure. The client's own
  /// reconnect replays from its applied cursor; no request is resent by this action.
  func dropConnectionForDevelopment() {
    guard let linkConditioner, hasAuthenticatedDaemon else { return }
    Task { await linkConditioner.dropConnection() }
  }

  /// Debug menu only: delays each later frame in both directions for this app session.
  /// Turning the delay on or off reconnects once, so a connection is never half-delayed.
  func setInjectedLatency(_ latency: Duration) {
    guard let linkConditioner else { return }
    injectedLatency = max(.zero, latency)
    Task { await linkConditioner.setLatency(latency) }
  }

  /// This method is invoked only by the explicit user-facing Enable Background Service action.
  func enableBackgroundService() {
    guard !isDevelopmentChat else { return }
    runOperation {
      try self.validateBundleLayout()
      _ = try PeerAuthentication.currentIdentity()
      let client = try self.prepareClient()
      do {
        let hello = try await client.connect()
        guard let owned = self.owned, owned.isRunning, hello.daemon.pid == owned.pid else {
          throw DaemonSupervisionError.existingDaemonNotOwned
        }
      } catch {
        guard self.isStopped(error) else { throw error }
      }
      if let owned = self.owned {
        guard await owned.stop() else { throw DaemonSupervisionError.quitBlocked }
        self.owned = nil
        self.isAppOwned = false
      }
      await self.client?.disconnect()
      do { try self.service.register() } catch {
        self.refreshRegistration()
        guard self.registration == .requiresApproval else {
          throw DaemonSupervisionError.registrationFailed
        }
      }
      self.refreshRegistration()
      try await self.connectOrStart()
    }
  }

  /// Unregistering can stop launchd's service; the UI discloses that and requires user action.
  /// Its daemon holds the store lock and the socket until it has exited, so this app's own
  /// helper starts only after that.
  func disableBackgroundService() {
    guard !isDevelopmentChat else { return }
    runOperation {
      let connected = self.clientStatus?.hello?.daemon
      let agent = connected.flatMap { $0.pid == self.owned?.pid ? nil : $0 }
      await self.client?.disconnect()
      do { try await self.unregisterService() } catch {
        throw DaemonSupervisionError.registrationFailed
      }
      self.refreshRegistration()
      if let agent { try await self.awaitExit(of: agent) }
      try await self.connectOrStart()
    }
  }

  private func awaitExit(of agent: DaemonInfo) async throws {
    wait = .agentStopping
    defer { wait = nil }
    let exited = try await DaemonProcessExit.wait(within: Self.agentStopCeiling) {
      DaemonProcessExit.isRunning(agent)
    }
    guard exited else { throw DaemonSupervisionError.agentStillRunning }
  }

  private func unregisterService() async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      service.unregister { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }

  func openBackgroundSettings() { SMAppService.openSystemSettingsLoginItems() }

  func revealAppForRepair() {
    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
  }

  func refreshRegistration() {
    guard !isDevelopmentChat else { return }
    registration = DaemonRegistration(service.status)
  }

  /// Return false rather than quit with a still-owned child. Registered agents are untouched.
  func stopForQuit() async -> Bool {
    isQuitting = true
    // A restart may be waiting behind an in-flight operation; cancel both before waiting.
    let restart = restartTask
    restart?.cancel()
    restartTask = nil
    operationTask?.cancel()
    await restart?.value
    let poller = pollingTask
    poller?.cancel()
    pollingTask = nil
    await poller?.value
    let operation = operationTask
    operation?.cancel()
    await operation?.value
    let observer = statusTask
    observer?.cancel()
    statusTask = nil
    await observer?.value
    await chatGPTSubscription?.close()
    await client?.disconnect()
    clientStatus = await client?.status()
    daemonStatus = nil
    if let owned, !(await owned.stop()) {
      problem = .quitBlocked
      isQuitting = false
      await chatGPTSubscription?.resumeAfterQuitVeto()
      if let client { observeClient(client) }
      startPolling()
      return false
    }
    owned = nil
    isAppOwned = false
    return true
  }

  private func runOperation(_ work: @escaping @MainActor () async throws -> Void) {
    guard !isBusy, !isQuitting else { return }
    isBusy = true
    problem = nil
    operationTask = Task { [weak self] in
      guard let self else { return }
      defer {
        self.isBusy = false
        self.operationTask = nil
      }
      do { try await work() } catch is CancellationError {} catch {
        // A crash-loop stop already names the actionable problem.
        if case .stopped = self.helperRecovery { return }
        self.problem = self.classify(error)
      }
    }
  }

  private func prepareClient() throws -> MemoshiClient {
    if let client {
      observeClient(client)
      return client
    }
    let identity = try PeerAuthentication.currentIdentity()
    guard identity.signingIdentifier == "com.mehmetcanbudak.memoshi.mac",
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String,
      let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      !version.isEmpty, !build.isEmpty
    else { throw DaemonSupervisionError.damagedBundle }
    let policy = try PeerPolicy(teamID: identity.teamID, identifiers: [label])
    let keychain = ModelKeychain(
      accessGroup: identity.teamID + ".com.mehmetcanbudak.memoshi.secrets")
    let subscription = ChatGPTSubscription(
      accessGroup: identity.teamID + ".com.mehmetcanbudak.memoshi.secrets",
      lockDirectory: dataDirectory.appendingPathComponent("model-auth-locks", isDirectory: true))
    let keychainHandler: KeychainHostHandler = { params in
      if ModelCredentialReference(rawValue: params.secretRef)?.kind == .chatGPT {
        return try await subscription.release(params)
      }
      let release = try await keychain.get(secretRef: params.secretRef, purpose: params.purpose)
      return HostKeychainGetResult(value: release.value, ttlMs: release.ttlMs)
    }
    let transport: any ClientTransport = linkConditioner ?? UnixWebSocketTransport()
    let client = MemoshiClient(
      configuration: ClientConfiguration(
        dataDirectory: dataDirectory, peerPolicy: policy,
        client: ClientInfo(name: "Memoshi", version: version, build: build, role: .app),
        requestTimeout: .seconds(10)),
      transport: transport, keychainHostHandler: keychainHandler)
    self.client = client
    modelKeychain = keychain
    chatGPTSubscription = subscription
    observeClient(client)
    return client
  }

  private func observeClient(_ client: MemoshiClient) {
    guard statusTask == nil else { return }
    statusTask = Task { [weak self, client] in
      let updates = await client.updates()
      for await status in updates {
        guard !Task.isCancelled, let self else { return }
        self.clientStatus = status
        if status.hello == nil { self.daemonStatus = nil }
        if let owned = self.owned {
          self.isAppOwned = owned.isRunning && status.hello?.daemon.pid == owned.pid
        } else {
          self.isAppOwned = false
        }
        if let hello = status.hello, hello.connectionId != self.announcedConnectionID {
          self.announcedConnectionID = hello.connectionId
          self.onAuthenticated?(client)
        }
      }
    }
  }

  /// `probeExisting: false` skips the initial wait for an already-starting helper; it is used
  /// only after this app's own helper exited, when no other owner is expected.
  private func connectOrStart(probeExisting: Bool = true) async throws {
    let client = try prepareClient()
    try Task.checkCancellation()
    do {
      try await probe(client, for: probeExisting ? .seconds(3) : .zero, waiting: .connecting)
      try await readDaemonStatus(client)
      return
    } catch {
      guard isStopped(error) else { throw error }
    }
    try Task.checkCancellation()
    // From here a helper is being started, so the status says so rather than "stopped".
    wait = .helperStarting
    defer { wait = nil }
    if isDevelopmentChat {
      if owned?.isRunning != true {
        try validateBundleLayout()
        try Task.checkCancellation()
        try startOwnedHelper(developmentChat: true)
      }
      try await probe(client, for: .seconds(3), awaiting: owned, waiting: .helperStarting)
      try await readDaemonStatus(client)
      return
    }
    refreshRegistration()
    switch registration {
    case .enabled:
      // kickstart without -k is safe even if a registered process is still starting. Never
      // spawn a fallback behind an enabled job whose IPC endpoint is merely unavailable.
      try await kickstartRegisteredDaemon(label: label)
    case .notRegistered, .requiresApproval, .notFound:
      if owned?.isRunning != true {
        // Service lookup can return notFound for a complete, never-registered app.
        // Validate the bundle itself instead of treating discovery as an integrity check.
        try validateBundleLayout()
        try Task.checkCancellation()
        try startOwnedHelper(developmentChat: false)
      }
    case .unknown:
      throw DaemonSupervisionError.connectionFailed
    }
    do {
      try await probe(client, for: .seconds(3), awaiting: owned, waiting: .helperStarting)
      try await readDaemonStatus(client)
    } catch {
      if let exit = owned?.exitStatus { throw DaemonSupervisionError.helperExited(exit) }
      throw error
    }
  }

  private func startOwnedHelper(developmentChat: Bool) throws {
    owned = try OwnedDaemonProcess(
      executable: helperExecutable, dataDirectory: dataDirectory, developmentChat: developmentChat
    ) { [weak self] process, exit in
      self?.ownedHelperExited(process, exit)
    }
  }

  /// Restarts only this app's own helper after an exit it did not request, with backoff, and
  /// stops at the crash-loop bound. No LaunchAgent is registered and nothing else is signaled.
  private func ownedHelperExited(_ process: OwnedDaemonProcess, _ exit: OwnedDaemonProcess.Exit) {
    guard process === owned else { return }
    lastHelperExit = exit
    isAppOwned = false
    guard !isQuitting else { return }
    // The process ended, so nothing remains to own or report; a stop this app requested (one
    // that outlived a quit veto, for example) is not a crash and starts no recovery.
    owned = nil
    guard !exit.requested else { return }
    let now = ContinuousClock.now
    unexpectedExits.removeAll { $0.duration(to: now) >= Self.crashLoopWindow }
    unexpectedExits.append(now)
    restartTask?.cancel()
    restartTask = nil
    guard unexpectedExits.count < Self.crashLoopExits else {
      helperRecovery = .stopped(exits: unexpectedExits.count)
      problem = .restartLimitReached(exits: unexpectedExits.count)
      return
    }
    let attempt = unexpectedExits.count
    helperRecovery = .restarting(attempt: attempt)
    problem = exit.signaled ? .helperTerminated(signal: exit.status) : .helperExited(exit.status)
    // 0.5 s, then 2 s: the old socket and store lock are released by the exit itself.
    let delay = Duration.milliseconds(500) * (1 << (2 * (attempt - 1)))
    restartTask = Task { [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      await self?.restartOwnedHelper()
    }
  }

  private func restartOwnedHelper() async {
    // Work already in flight finishes first; it may have started a helper itself.
    while let operation = operationTask {
      await operation.value
      if Task.isCancelled { return }
    }
    restartTask = nil
    guard !isQuitting else { return }
    guard owned?.isRunning != true else {
      helperRecovery = .idle
      return
    }
    runOperation {
      defer {
        if self.restartTask == nil, case .restarting = self.helperRecovery {
          self.helperRecovery = .idle
        }
      }
      // The client may not yet have noticed the dead connection; a cached hello would
      // otherwise satisfy the probe and the restart would never start a helper.
      await self.client?.disconnect()
      try await self.connectOrStart(probeExisting: false)
    }
  }

  /// Retries while no daemon is listening. `duration` bounds the wait for a daemon this app
  /// did not start. This app's own helper binds its socket only after its store has opened, so
  /// it is awaited while it is running, up to `helperStartCeiling`. A helper already asked to
  /// stop will never listen and is not awaited. `waiting` is what the status says meanwhile.
  private func probe(
    _ client: MemoshiClient, for duration: Duration, awaiting helper: OwnedDaemonProcess? = nil,
    waiting: DaemonWait
  ) async throws {
    let previous = wait
    wait = waiting
    defer { wait = previous }
    let began = ContinuousClock.now
    while true {
      try Task.checkCancellation()
      do {
        _ = try await client.connect()
        return
      } catch {
        let elapsed = began.duration(to: .now)
        let helperStarting =
          helper.map { $0.isRunning && !$0.stopRequested } == true
          && elapsed < Self.helperStartCeiling
        guard isStopped(error), helperStarting || elapsed < duration else { throw error }
      }
      try await Task.sleep(for: .milliseconds(100))
    }
  }

  private func readDaemonStatus(_ client: MemoshiClient) async throws {
    daemonStatus = try await client.call(SystemStatus.self, EmptyParams())
    clientStatus = await client.status()
    if let owned {
      isAppOwned = owned.isRunning && clientStatus?.hello?.daemon.pid == owned.pid
    }
  }

  private func startPolling() {
    guard pollingTask == nil else { return }
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
        guard let self, !self.isQuitting else { return }
        self.refreshRegistration()
        if !self.isDevelopmentChat, self.registration == .enabled, self.owned?.isRunning == true,
          !self.isBusy
        {
          // Reconcile current ownership even if a popover or busy poll already observed approval.
          // The registered agent takes over only after the owned child releases its lock.
          self.runOperation {
            if let owned = self.owned {
              guard await owned.stop() else { throw DaemonSupervisionError.quitBlocked }
              self.owned = nil
              self.isAppOwned = false
            }
            await self.client?.disconnect()
            try await self.connectOrStart()
          }
        }
        if !self.isBusy, let client = self.client, await client.status().hello != nil {
          do { try await self.readDaemonStatus(client) } catch is CancellationError { return } catch
          { self.problem = self.classify(error) }
        }
        if let owned = self.owned, !owned.isRunning {
          self.problem = .helperExited(owned.exitStatus ?? 0)
          self.isAppOwned = false
        }
      }
    }
  }

  private func validateBundleLayout() throws {
    let plist = Bundle.main.bundleURL.appendingPathComponent(
      "Contents/Library/LaunchAgents/com.mehmetcanbudak.memoshi.memoshid.plist")
    guard FileManager.default.isExecutableFile(atPath: helperExecutable.path),
      FileManager.default.fileExists(atPath: plist.path)
    else {
      throw DaemonSupervisionError.damagedBundle
    }
  }

  private func isStopped(_ error: any Error) -> Bool {
    guard let error = error as? IPCError, case .systemCall(_, let code) = error else {
      return false
    }
    return code == ENOENT || code == ECONNREFUSED
  }

  private func classify(_ error: any Error) -> DaemonSupervisionError {
    if let error = error as? DaemonSupervisionError { return error }
    if let error = error as? IPCError {
      switch error {
      case .signingRequired: return .signingRequired
      case .authenticationFailed: return .authenticationFailed
      case .unsafePath: return .unsafeDataDirectory
      case .closed(code: 4409, reason: _): return .versionMismatch
      default: break
      }
    }
    if let error = error as? RPCError, error.kind == .versionMismatch { return .versionMismatch }
    if let error = error as? ClientError {
      switch error {
      // A call reports the daemon's 4409 close as `connectionClosed`, not as the carrier error.
      case .versionMismatch, .connectionClosed(code: 4409, reason: _): return .versionMismatch
      default: break
      }
    }
    return .connectionFailed
  }
}
