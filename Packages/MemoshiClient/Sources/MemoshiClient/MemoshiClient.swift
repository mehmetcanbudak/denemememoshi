import Darwin
import Foundation
import MemoshiProtocol
import MemoshiTransport

/// Typed local RPC plus an explicitly acknowledged, memory-only event cursor. This actor owns
/// its connection and tasks. Owners must await `disconnect()` when their lifetime ends.
public actor MemoshiClient: MemoshiAPI {
  let configuration: ClientConfiguration
  let transport: any ClientTransport
  let codec: JSONRPCCodec
  let tokenReader: @Sendable (URL) throws -> HelloToken
  let sleep: @Sendable (Duration) async throws -> Void
  let keychainHostHandler: KeychainHostHandler?
  let hostDecoder = ProtocolCoding.makeDecoder(strict: true)
  let hostEncoder = ProtocolCoding.makeEncoder()
  var hostCalls: [UUID: HostCall] = [:]
  var hostRequestIDs: [String: UUID] = [:]

  var connection: (any ClientConnection)?
  var connectionTask: Task<SystemHelloResult, any Error>?
  var receiveTask: Task<Void, Never>?
  var reconnectTask: Task<Void, Never>?
  var subscriptionTask: Task<Void, Never>?
  var generation: UInt64 = 0
  var wantsConnection = false
  var nextRequestID: UInt64 = 0
  var pending: [String: PendingCall] = [:]
  var statusValue = ClientStatus(
    state: .disconnected, hello: nil, lastAppliedSeq: nil, pendingCalls: 0,
    resync: nil, failure: nil, isSubscribed: false)
  var observers: [UUID: AsyncStream<ClientStatus>.Continuation] = [:]

  var eventContinuation: AsyncThrowingStream<ClientEvent, any Error>.Continuation?
  var eventConsumerID: UUID?
  var eventQueue = EventBuffer()
  var stagedEvents = EventBuffer()
  var stagedTransients = EventBuffer()
  var transientQueue = EventBuffer()
  var outstandingDelivery: EventDelivery?
  var outstandingBytes = 0
  var receivedThrough: Int64?
  /// The cursor is `statusValue.lastAppliedSeq` together with the log it was taken from and
  /// the `ts` of the event at that position (D131). All three change only when the consumer
  /// acknowledges an applied event or a completed resync, and none is persisted.
  var cursorLogId: LogID?
  var lastAppliedTs: Int64?
  var replayHead: Int64?
  var subscriptionPending = false
  var subscriptionControlInFlight = false
  var subscribed = false
  var needsResubscribe = false
  var needsFullResync = false
  var pendingResyncTrigger: EventEnvelope?
  var focus: FocusList?
  let maximumBufferedEvents = 10_000
  let maximumBufferedBytes = 8 * 1024 * 1024
  /// The first reconnect delay, in milliseconds, after the next buffer overflow. It doubles with
  /// each overflow, to the connection backoff's 5 s, until the consumer catches up, so a
  /// consumer that stays too slow is not sent the same replay again and again without pause.
  var overflowReconnectDelay = 100

  /// Creates a typed client; the default carrier enforces the real peer policy.
  /// A non-nil Keychain handler offers `host.keychain.v1` only for role `app`; nil stays UI-only.
  /// Role `app` also offers `bots.grants.folder.v1`, which only a folder-grant backend accepts.
  public init(
    configuration: ClientConfiguration,
    transport: any ClientTransport = UnixWebSocketTransport(),
    diagnostics: (any ProtocolDiagnosticsSink)? = nil,
    keychainHostHandler: KeychainHostHandler? = nil
  ) {
    self.configuration = configuration
    self.transport = transport
    self.keychainHostHandler = keychainHostHandler
    codec = JSONRPCCodec(diagnostics: diagnostics)
    tokenReader = { try DaemonToken.read(from: $0) }
    sleep = { try await Task.sleep(for: $0) }
  }

  /// Deterministic behavioral tests replace the token file and timer, not production policy.
  init(
    configuration: ClientConfiguration, transport: any ClientTransport,
    tokenReader: @escaping @Sendable (URL) throws -> HelloToken,
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    diagnostics: (any ProtocolDiagnosticsSink)? = nil,
    keychainHostHandler: KeychainHostHandler? = nil
  ) {
    self.configuration = configuration
    self.transport = transport
    self.tokenReader = tokenReader
    self.sleep = sleep
    self.keychainHostHandler = keychainHostHandler
    codec = JSONRPCCodec(diagnostics: diagnostics)
  }

  deinit {
    connectionTask?.cancel()
    receiveTask?.cancel()
    reconnectTask?.cancel()
    subscriptionTask?.cancel()
    for call in hostCalls.values {
      call.work.cancel()
      call.timeout.cancel()
    }
    for call in pending.values {
      call.timeout.cancel()
      call.send.cancel()
      call.continuation.resume(throwing: ClientError.disconnected)
    }
    eventContinuation?.finish()
    for observer in observers.values { observer.finish() }
    if let connection {
      Task {
        await connection.close(code: 1000, reason: "client released")
        await connection.waitUntilClosed()
      }
    }
  }

  /// Returns the current in-memory connection, request and cursor state.
  public func status() -> ClientStatus { statusValue }

  /// Status observers may coalesce updates; durable events never use this lossy stream.
  public func updates() -> AsyncStream<ClientStatus> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<ClientStatus>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    observers[id] = continuation
    continuation.yield(statusValue)
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeObserver(id) }
    }
    return stream
  }

  /// Opens the real carrier, authenticates the peer, then re-reads the token and sends hello.
  /// Concurrent connect callers share an attempt. Cancellation of any waiter cancels that
  /// attempt and closes its connection; no implicit retry of a mutating RPC is performed.
  @discardableResult
  public func connect() async throws -> SystemHelloResult {
    wantsConnection = true
    if connectionTask == nil {
      reconnectTask?.cancel()
      reconnectTask = nil
    }
    return try await beginConnect()
  }

  /// Cancels reconnect and pending work, invalidates receipts and awaits carrier cleanup.
  public func disconnect() async {
    wantsConnection = false
    generation &+= 1
    let attempt = connectionTask
    let receiver = receiveTask
    connectionTask = nil
    attempt?.cancel()
    reconnectTask?.cancel()
    reconnectTask = nil
    await tearDown(error: ClientError.disconnected, state: .disconnected, failure: nil)
    _ = await attempt?.result
    await receiver?.value
  }

  func beginConnect() async throws -> SystemHelloResult {
    try Task.checkCancellation()
    if let connectionTask {
      return try await awaitConnectAttempt(connectionTask, generation: generation)
    }
    if connection != nil, let hello = statusValue.hello { return hello }
    generation &+= 1
    let attemptGeneration = generation
    statusValue.state = .connecting
    statusValue.failure = nil
    publishStatus()
    let task = Task { try await self.establish(generation: attemptGeneration) }
    connectionTask = task
    do {
      let result = try await awaitConnectAttempt(task, generation: attemptGeneration)
      connectionTask = nil
      return result
    } catch {
      if generation == attemptGeneration {
        connectionTask = nil
        let classification = classify(error)
        await tearDown(error: error, state: classification.0, failure: classification.1)
      }
      throw error
    }
  }

  func awaitConnectAttempt(
    _ task: Task<SystemHelloResult, any Error>, generation expected: UInt64
  ) async throws -> SystemHelloResult {
    do {
      return try await withTaskCancellationHandler {
        let result = try await task.value
        try Task.checkCancellation()
        guard generation == expected, connection != nil else { throw ClientError.disconnected }
        return result
      } onCancel: {
        task.cancel()
        Task { await self.cancelAttempt(generation: expected) }
      }
    } catch {
      if Task.isCancelled { throw CancellationError() }
      throw error
    }
  }

  func establish(generation expected: UInt64) async throws -> SystemHelloResult {
    guard configuration.requestTimeout > .zero else {
      throw ClientError.protocolViolation("Request timeout must be positive")
    }
    let paths = try IPCPaths(directory: configuration.dataDirectory)
    let opened = try await transport.connect(at: paths, policy: configuration.peerPolicy)
    guard generation == expected, !Task.isCancelled else {
      await opened.close(code: 1000, reason: "connect canceled")
      await opened.waitUntilClosed()
      throw CancellationError()
    }
    connection = opened
    receiveTask = Task { [weak self, opened] in
      do {
        for try await frame in opened.messages {
          guard let self else { break }
          try await self.receive(frame, generation: expected)
        }
        await self?.connectionLost(
          ClientError.connectionClosed(code: 1006, reason: "closed"), generation: expected)
      } catch {
        await self?.connectionLost(error, generation: expected)
      }
    }

    // The carrier has already checked the actual peer. Never move this read above connect.
    let token = try tokenReader(paths.tokenURL)
    try Task.checkCancellation()
    var capabilities = [try Capability("events.focus.v1")]
    if configuration.client.role == .app, keychainHostHandler != nil {
      capabilities.append(try Capability("host.keychain.v1"))
    }
    // Only the authenticated app manages folder grants; the daemon accepts it with a real backend.
    if configuration.client.role == .app {
      capabilities.append(try Capability("bots.grants.folder.v1"))
    }
    let hello = try await request(
      SystemHello.self,
      SystemHelloParams(
        token: token, client: configuration.client,
        protocolRange: ProtocolRange(min: ProtocolVersion.minimum, max: ProtocolVersion.current),
        capabilities: capabilities, locale: configuration.locale, timeZone: configuration.timeZone),
      generation: expected)
    guard generation == expected, connection != nil, !Task.isCancelled else {
      throw ClientError.disconnected
    }
    guard (ProtocolVersion.minimum...ProtocolVersion.current).contains(hello.protocolVersion) else {
      throw ClientError.versionMismatch(selected: hello.protocolVersion)
    }
    guard Set(hello.capabilities).isSubset(of: Set(capabilities)),
      hello.limits.maxInFlightRequests > 0, hello.limits.maxInboundBytes > 0,
      hello.limits.maxOutboundFrameBytes > 0, hello.limits.maxBatchEvents > 0,
      hello.limits.maxFocus >= 0, hello.head >= 0, hello.minRetainedSeq >= 0,
      hello.minRetainedSeq <= hello.head
        || hello.head < Int64.max && hello.minRetainedSeq == hello.head + 1
    else { throw ClientError.protocolViolation("Invalid negotiated capabilities or limits") }
    statusValue.hello = hello
    statusValue.state = .syncing
    publishStatus()
    // A cursor past this daemon's head can never be replayed here (a restored backup or a
    // recreated data directory), so every reconnect would be refused: resync instead. A cursor
    // from another event log is withheld by `subscribe` itself (D131).
    let cursor = statusValue.lastAppliedSeq
    try await subscribe(
      generation: expected, reason: cursor == nil ? .coldStart : .cursorExpired,
      discardingCursor: cursor.map { $0 > hello.head } ?? false)
    guard generation == expected, connection != nil, !Task.isCancelled else {
      throw ClientError.disconnected
    }
    return hello
  }

  func cancelAttempt(generation expected: UInt64) async {
    guard expected == generation else { return }
    await disconnect()
  }

  func connectionLost(_ error: any Error, generation expected: UInt64) async {
    guard expected == generation, connection != nil else { return }
    let wasConnecting = connectionTask != nil
    let classification = classify(error)
    await tearDown(error: error, state: classification.0, failure: classification.1)
    guard !wasConnecting, wantsConnection, configuration.automaticallyReconnect,
      canReconnect(after: error), expected == generation
    else { return }
    statusValue.state = .reconnecting
    publishStatus()
    var delay = 100
    if error as? ClientError == .eventBufferOverflow {
      delay = overflowReconnectDelay
      overflowReconnectDelay = min(overflowReconnectDelay * 2, 5_000)
    }
    reconnectTask = Task { [weak self] in await self?.reconnect(startingAt: delay) }
  }

  /// Retries with jittered delays that double from `startingAt` milliseconds to 5 s.
  func reconnect(startingAt initial: Int) async {
    let started = ContinuousClock.now
    var delay = initial
    while wantsConnection, !Task.isCancelled {
      do {
        let jittered = min(5_000, max(100, Int(Double(delay) * Double.random(in: 0.8...1.2))))
        try await sleep(.milliseconds(jittered))
        try Task.checkCancellation()
        _ = try await beginConnect()
        return
      } catch {
        guard !Task.isCancelled, wantsConnection, canReconnect(after: error) else { return }
        if statusValue.failure == .daemonStopped, started.duration(to: .now) >= .seconds(3) {
          statusValue.state = .daemonStopped
          publishStatus()
          return
        }
        statusValue.state = .reconnecting
        publishStatus()
        delay = min(delay * 2, 5_000)
      }
    }
  }

  func tearDown(error: any Error, state: ClientConnectionState, failure: ClientFailure?) async {
    let old = connection
    connection = nil
    receiveTask?.cancel()
    receiveTask = nil
    subscriptionTask?.cancel()
    subscriptionTask = nil
    cancelHostCalls()
    failPending(error)
    clearEventDelivery()
    subscribed = false
    subscriptionPending = false
    subscriptionControlInFlight = false
    statusValue.hello = nil
    statusValue.resync = nil
    statusValue.state = state
    statusValue.failure = failure
    publishStatus()
    if let old {
      await old.close(code: 1000, reason: "client closing")
      await old.waitUntilClosed()
    }
  }

  func classify(_ error: any Error) -> (ClientConnectionState, ClientFailure?) {
    if error is CancellationError { return (.disconnected, nil) }
    if let error = error as? ClientError {
      switch error {
      case .versionMismatch, .connectionClosed(code: 4409, reason: _):
        return (.versionMismatch, .versionMismatch)
      case .protocolViolation: return (.failed, .protocolViolation)
      case .eventBufferOverflow: return (.failed, .eventBufferOverflow)
      case .disconnected: return (.disconnected, nil)
      default: break
      }
    }
    if let error = error as? RPCError, error.kind == .versionMismatch {
      return (.versionMismatch, .versionMismatch)
    }
    if let error = error as? IPCError {
      switch error {
      case .signingRequired: return (.signingRequired, .signingRequired)
      case .closed(code: 4409, reason: _): return (.versionMismatch, .versionMismatch)
      case .systemCall(operation: _, code: ENOENT), .systemCall(operation: _, code: ECONNREFUSED):
        return (.daemonStopped, .daemonStopped)
      default: break
      }
    }
    return (.failed, .transport)
  }

  func canReconnect(after error: any Error) -> Bool {
    switch classify(error).1 {
    case .signingRequired, .versionMismatch, .protocolViolation: return false
    default: break
    }
    if let error = error as? IPCError {
      switch error {
      case .unsafePath, .invalidPolicy, .authenticationFailed, .invalidToken: return false
      default: break
      }
    }
    return !(error is CancellationError)
  }

  func publishStatus() {
    statusValue.pendingCalls = pending.count
    statusValue.isSubscribed = subscribed
    for observer in observers.values { observer.yield(statusValue) }
  }

  func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
}
