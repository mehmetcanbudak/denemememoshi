import Foundation
import MemoshiProtocol
import MemoshiRuntime
import MemoshiStore
import MemoshiTransport

/// Authenticated local service with explicit opt-in text/provider, app-broker and local
/// folder-grant capabilities.
public actor DaemonServer {
  typealias Listen =
    @Sendable (
      IPCPaths, PeerPolicy, @escaping @Sendable (LocalConnection) async -> Void
    ) async throws -> LocalWebSocketListener
  /// Starts the text runtime. Tests hold this step to stop the server while it runs.
  typealias StartRuntime = @Sendable (RuntimeAdapter) async throws -> Void

  let configuration: DaemonConfiguration
  let store: Store
  let paths: IPCPaths
  let identity: PeerIdentity
  let info: DaemonInfo
  let daemonLock: DaemonLock
  let capabilities: [Capability]
  private let toolDefinitions: [RuntimeToolDefinition]
  private let runtimeExtensions: RuntimeExtensionComposition
  private let sandboxDaemonCommand: [String]?
  private let sourceContext: SourcePathPolicyContext?
  private let listen: Listen
  private let startRuntime: StartRuntime
  var token: HelloToken?
  var listener: LocalWebSocketListener?
  var starting: Task<LocalWebSocketListener, any Error>?
  var maintenance: Task<Void, Never>?
  var sessions: [UUID: RPCSession] = [:]
  var runtime: RuntimeAdapter?
  var sandboxHost: RuntimeSandboxHost?
  var hostSessionID: UUID?
  var keychainHostReady = false
  var state = DaemonState.starting
  var didStart = false
  var isStopped = false
  var stopFailure: (any Error)?
  var stoppedWaiters: [CheckedContinuation<Void, Never>] = []

  /// Verifies this helper's identity before acquiring the singleton lock or opening its store.
  public init(
    configuration: DaemonConfiguration, tools: [RuntimeToolDefinition] = [],
    extensions: RuntimeExtensionComposition = .none,
    sandboxDaemonCommand: [String]? = nil
  ) throws {
    let identity = try PeerAuthentication.currentIdentity()
    guard identity.signingIdentifier == DaemonConfiguration.helperIdentifier else {
      throw DaemonError.wrongSigningIdentity
    }
    try self.init(
      configuration: configuration, identity: identity, tools: tools, extensions: extensions,
      sandboxDaemonCommand: sandboxDaemonCommand,
      listen: { try await LocalWebSocket.listen(at: $0, policy: $1, onConnection: $2) })
  }

  /// The service behind the identity check. Apart from the initializer above, only tests call
  /// this, with the helper identity and listener an unsigned process cannot obtain, and a
  /// runtime start they can hold.
  init(
    configuration: DaemonConfiguration, identity: PeerIdentity,
    tools: [RuntimeToolDefinition] = [], extensions: RuntimeExtensionComposition = .none,
    sandboxDaemonCommand: [String]? = nil,
    listen: @escaping Listen, startRuntime: @escaping StartRuntime = { try await $0.start() }
  ) throws {
    guard
      configuration.enableTextChat
        || (tools.isEmpty && extensions.codeMode == nil && extensions.mcpServers.isEmpty
          && extensions.subagents == nil && sandboxDaemonCommand == nil)
    else {
      throw RuntimeToolError.invalidDefinition
    }
    let lock = try DaemonLock.acquire(in: configuration.dataDirectory)
    let store = try Store(directory: configuration.dataDirectory)
    self.configuration = configuration
    self.identity = identity
    self.daemonLock = lock
    self.store = store
    self.toolDefinitions = tools
    self.runtimeExtensions = extensions
    self.sandboxDaemonCommand = sandboxDaemonCommand
    self.listen = listen
    self.startRuntime = startRuntime
    self.paths = try IPCPaths(directory: configuration.dataDirectory, createDirectories: true)
    self.info = DaemonInfo(
      version: configuration.version, build: configuration.build,
      pid: Int(ProcessInfo.processInfo.processIdentifier), startedAt: IDGenerator.nowMilliseconds())
    let sourceContext =
      configuration.enableTextChat
      ? DaemonServer.sourcePolicyContext(dataDirectory: configuration.dataDirectory) : nil
    self.sourceContext = sourceContext
    var capabilities = [try Capability("events.focus.v1")]
    if configuration.enableTextChat {
      capabilities.append(try Capability("host.keychain.v1"))
      // Advertised only with a real backend over verified trusted roots; tools stay disabled.
      if sourceContext != nil { capabilities.append(try Capability("bots.grants.folder.v1")) }
    }
    self.capabilities = capabilities
  }

  /// Rotates the bearer token and starts authenticated Unix WebSocket service.
  public func start() async throws {
    guard didStart == false else { throw DaemonError.alreadyStarted }
    // A stop that reached the actor first is a normal stop, not a second start.
    guard state != .quiescing, isStopped == false else { throw DaemonError.notRunning }
    didStart = true
    do {
      if configuration.enableTextChat {
        let environments: RuntimeEnvironmentComposition
        if let command = sandboxDaemonCommand, let executable = command.first {
          let canonicalExecutable = try ThisMacComputerDirectory.canonicalPath(executable)
          let canonicalCommand = [canonicalExecutable] + Array(command.dropFirst())
          let directory = ThisMacComputerDirectory(dataDirectory: configuration.dataDirectory)
          let host = try await RuntimeSandboxHost(
            daemonCommand: canonicalCommand, store: store, directory: directory)
          self.sandboxHost = host
          environments = RuntimeEnvironmentComposition(directory: directory, sandbox: host)
        } else {
          environments = .none
        }
        let runtime = RuntimeAdapter(
          store: store,
          resolveCredential: { [weak self] params in
            guard let self else { throw DaemonError.notRunning }
            return try await self.requestCredential(params)
          },
          tools: toolDefinitions, extensions: runtimeExtensions, environments: environments,
          sourceContext: sourceContext,
          publishLive: { [weak self] event in
            guard let self else { throw DaemonError.notRunning }
            try await self.publishLive(event)
          })
        self.runtime = runtime
        try await startRuntime(runtime)
        // A stop during that suspension released the singleton lock: mint and bind nothing.
        guard state != .quiescing, isStopped == false else { throw DaemonError.notRunning }
      }
      let token = try DaemonToken.mint(at: paths.tokenURL)
      self.token = token
      let policy = try PeerPolicy(
        teamID: identity.teamID, identifiers: [DaemonConfiguration.appIdentifier])
      let paths = self.paths
      let startup = Task { [weak self, listen] in
        try await listen(paths, policy) { [weak self] connection in
          guard let self else {
            await connection.close(code: 4503, reason: "daemon_stopped")
            return
          }
          await self.accept(connection, token: token)
        }
      }
      starting = startup
      let listener = try await startup.value
      starting = nil
      guard state != .quiescing, isStopped == false else {
        // The stop that won owns the shutdown and has already recorded its cause.
        await listener.close(
          code: Self.closeCode(stoppedBy: stopFailure), reason: "daemon_stopping")
        throw DaemonError.notRunning
      }
      self.listener = listener
      state = .ready
      try await runtime?.resume()
      maintenance = Task { [weak self] in
        while Task.isCancelled == false {
          do { try await Task.sleep(for: .seconds(60)) } catch { return }
          guard let self else { return }
          do { _ = try await self.pruneEvents() } catch {
            await self.failMaintenance(error)
            return
          }
        }
      }
    } catch {
      starting = nil
      // A stop that won the race owns the shutdown; what it did to this startup (a closed
      // store, a canceled bind) is not a service failure. Its own failure is still reported.
      guard state != .quiescing, isStopped == false else {
        await finish(reason: nil, failure: nil)
        throw DaemonError.notRunning
      }
      await finish(reason: nil, failure: error)
      throw error
    }
  }

  /// Runtime callers use this seam, never publish a durable envelope independently of COMMIT.
  public func commit(
    _ change: StoreCommit, at now: Int64 = IDGenerator.nowMilliseconds()
  ) async throws -> [EventEnvelope] {
    guard state == .ready, isStopped == false else { throw DaemonError.notRunning }
    return try await store.commit(change, at: now)
  }

  /// Atomically changes retention and publishes its committed change event.
  public func setEventRetentionDays(
    _ days: Int, at now: Int64 = IDGenerator.nowMilliseconds()
  ) async throws -> [EventEnvelope] {
    guard state == .ready, isStopped == false else { throw DaemonError.notRunning }
    return try await store.setEventRetentionDays(days, at: now)
  }

  /// Removes one eligible retained prefix and publishes the committed pruning fact.
  public func pruneEvents(
    at now: Int64 = IDGenerator.nowMilliseconds()
  ) async throws -> PruneResult {
    guard state == .ready, isStopped == false else { throw DaemonError.notRunning }
    return try await store.pruneEvents(now: now)
  }

  /// Live-only UI data is never put in SQLite and only focused connections receive its content.
  public func publishLive(_ event: EventEnvelope) async throws {
    guard state == .ready, isStopped == false else { throw DaemonError.notRunning }
    guard event.seq == nil, event.cseq == nil, let payload = event.event.payload,
      type(of: payload).eventClass == .uiOnly, event.deviceId == store.deviceID
    else { throw StoreError.invalidCommit("Only local UI-only events may be published live") }
    var event = event
    event.after = try await store.replayBounds().head
    for session in sessions.values { try await session.enqueueLive(event) }
  }

  /// Reports actual text-runtime and negotiated app-host activity.
  public func status() async -> SystemStatusResult {
    let activity = await runtime?.status()
    return SystemStatusResult(
      state: state, scheduler: .off, hostConnected: keychainHostReady && state == .ready,
      openThreads: activity?.openThreads ?? 0, liveRuns: activity?.liveRuns ?? 0)
  }

  /// Persists graceful stopping, closes owned resources and releases both writer locks.
  public func stop(reason: SystemStoppingReason = .user) async throws {
    await finish(reason: reason, failure: nil)
    if let stopFailure { throw stopFailure }
  }

  /// Waits for complete service shutdown and rethrows any startup or storage failure.
  public func waitUntilStopped() async throws {
    if isStopped == false {
      await withCheckedContinuation { stoppedWaiters.append($0) }
    }
    if let stopFailure { throw stopFailure }
  }

  private func accept(_ connection: LocalConnection, token: HelloToken) async {
    guard state != .quiescing, isStopped == false else {
      await connection.close(code: 4503, reason: "daemon_stopping")
      return
    }
    let id = UUID()
    let session = RPCSession(
      connection: connection, token: token, store: store, info: info,
      schemaHash: configuration.schemaHash, capabilities: capabilities, runtime: runtime,
      status: { [weak self] in
        guard let self else { throw DaemonError.notRunning }
        return await self.status()
      },
      claimHost: { [weak self] in
        guard let self else { return false }
        return await self.claimKeychainHost(id)
      },
      hostOpened: { [weak self] version, capabilities in
        guard let self else { throw DaemonError.notRunning }
        try await self.openKeychainHost(id, version: version, capabilities: capabilities)
      })
    sessions[id] = session
    await session.run()
    sessions.removeValue(forKey: id)
    do { try await dropKeychainHost(id) } catch {
      // Listener teardown waits for connection callbacks, so schedule it after this one returns.
      maintenance?.cancel()
      maintenance = Task { [weak self] in await self?.failMaintenance(error) }
    }
  }

  private func failMaintenance(_ error: any Error) async {
    await finish(reason: nil, failure: error)
  }

  private func finish(reason: SystemStoppingReason?, failure: (any Error)?) async {
    guard isStopped == false else { return }
    if state == .quiescing {
      await withCheckedContinuation { stoppedWaiters.append($0) }
      return
    }
    state = .quiescing
    keychainHostReady = false
    // Recorded before the first suspension: a start that resumes meanwhile closes its listener
    // with the same code.
    stopFailure = failure
    // The listener closes every accepted connection, so it must carry the daemon's own code
    // (protocol.md §3.6); the sessions it has not yet removed get the same one.
    let code = Self.closeCode(stoppedBy: failure)
    for session in sessions.values { await session.stopHostWork() }
    maintenance?.cancel()
    maintenance = nil
    if let starting, let pending = try? await starting.value {
      await pending.close(code: code, reason: "daemon_stopping")
    }
    starting = nil
    if let runtime {
      do { try await runtime.close() } catch { stopFailure = stopFailure ?? error }
    }
    runtime = nil
    if let sandboxHost {
      await sandboxHost.close()
    }
    sandboxHost = nil
    if let reason {
      do {
        let event = EventDraft(
          ts: IDGenerator.nowMilliseconds(), actor: Actor(kind: .system),
          subject: ObjectRef(kind: "system", id: "memoshid"),
          event: .systemStopping(SystemStoppingPayload(reason: reason)))
        _ = try await store.commit(StoreCommit(events: [event]), at: event.ts)
      } catch { stopFailure = stopFailure ?? error }
    }
    if let listener { await listener.close(code: code, reason: "daemon_stopping") }
    listener = nil
    for session in sessions.values {
      await session.close(code: code, reason: "daemon_stopping")
    }
    sessions.removeAll()
    hostSessionID = nil
    do { try await store.close() } catch { stopFailure = stopFailure ?? error }
    daemonLock.release()
    isStopped = true
    for waiter in stoppedWaiters { waiter.resume() }
    stoppedWaiters.removeAll()
  }

  /// protocol.md §3.6: a stop closes its clients with 4503, and one a failure caused with 4500.
  private static func closeCode(stoppedBy failure: (any Error)?) -> Int {
    failure == nil ? 4503 : 4500
  }
}
