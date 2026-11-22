import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

/// Authenticated Unix sockets with SwiftNIO WebSocket framing and bounded resource ownership.
public enum LocalWebSocket {
  /// Authenticates the actual helper before sending HTTP or reading WebSocket bytes.
  public static func connect(at paths: IPCPaths, policy: PeerPolicy) async throws -> LocalConnection
  {
    try Task.checkCancellation()
    _ = try PeerAuthentication.currentIdentity()
    return try await connect(at: paths, check: .codeSignature(policy))
  }

  /// The peer check is a parameter only so that tests can reach the ordering around it without a
  /// signed build. The public entry point always passes the code-signature check.
  internal static func connect<Guest>(
    at paths: IPCPaths, check: PeerCheck<Guest>
  ) async throws -> LocalConnection {
    try Task.checkCancellation()
    try paths.validateSocket()
    let resources = EventLoopOwner()
    do {
      let channel = try await ClientBootstrap(group: resources.group)
        .channelOption(.autoRead, value: false)
        .channelOption(
          .recvAllocator,
          value: FixedSizeRecvByteBufferAllocator(capacity: TransportLimits.receiveChunkBytes)
        )
        .channelOption(.maxMessagesPerRead, value: 1)
        .channelOption(.writeBufferWaterMark, value: .init(low: 1_048_576, high: 4_194_304))
        .connectTimeout(.seconds(5))
        .connect(unixDomainSocketPath: paths.socketURL.path).get()
      do {
        // No pipeline handlers, reads or writes exist yet. autoRead was false
        // before registration/connect, not disabled after an initial read.
        let peer = try await channel.eventLoop.flatSubmit { check.run(on: channel) }.get()
        let (connection, handshake) = try await channel.eventLoop.submit {
          let state = ConnectionState(channel: channel, isServer: false)
          let handshake = UpgradeHandshake(channel: channel)
          try configureClientUpgrade(state: state, handshake: handshake)
          return (LocalConnection(peer: peer, state: state, resources: resources), handshake)
        }.get()
        return try await withTaskCancellationHandler {
          try Task.checkCancellation()
          try await channel.setOption(.autoRead, value: true).get()
          try await channel.eventLoop.flatSubmit { () -> EventLoopFuture<Void> in
            guard channel.isActive else {
              return channel.eventLoop.makeFailedFuture(IPCError.upgradeFailed)
            }
            var headers = HTTPHeaders()
            headers.add(name: "Host", value: "localhost")
            headers.add(name: "Sec-WebSocket-Protocol", value: "memoshi.v1")
            // Enqueue head+end in one event-loop turn. A fast 101 must not
            // remove the HTTP encoder between two awaited request writes.
            channel.write(
              HTTPClientRequestPart.head(
                .init(version: .http1_1, method: .GET, uri: "/", headers: headers)),
              promise: nil)
            return channel.writeAndFlush(HTTPClientRequestPart.end(nil))
          }.get()
          try await handshake.ready.get()
          try Task.checkCancellation()
          channel.closeFuture.whenComplete { _ in resources.stop() }
          return connection
        } onCancel: {
          channel.close(promise: nil)
        }
      } catch {
        channel.close(promise: nil)
        throw error
      }
    } catch {
      resources.stop()
      await resources.waitUntilStopped()
      throw mapSocketError(error, operation: "connect Unix socket")
    }
  }

  /// Publishes a private listener and verifies each accepted peer before consuming bytes.
  public static func listen(
    at paths: IPCPaths, policy: PeerPolicy,
    onConnection: @escaping @Sendable (LocalConnection) async -> Void
  ) async throws -> LocalWebSocketListener {
    try Task.checkCancellation()
    _ = try PeerAuthentication.currentIdentity()
    return try await listen(at: paths, check: .codeSignature(policy), onConnection: onConnection)
  }

  /// The peer check is a parameter for the same reason as in `connect(at:check:)`.
  internal static func listen<Guest>(
    at paths: IPCPaths, check: PeerCheck<Guest>,
    onConnection: @escaping @Sendable (LocalConnection) async -> Void
  ) async throws -> LocalWebSocketListener {
    try Task.checkCancellation()
    try paths.validateDirectories()
    let lease = try SocketLease(url: paths.socketURL)
    let resources = EventLoopOwner()
    let registry = ConnectionRegistry()
    do {
      // NIO owns the descriptor from here, but not its pathname: for an adopted socket it
      // never unlinks by name, which leaves the lease's inode check as the only removal.
      let socket = try lease.bind()
      let channel = try await ServerBootstrap(group: resources.group)
        .serverChannelOption(.autoRead, value: false)
        .serverChannelOption(.backlog, value: 128)
        .childChannelOption(.autoRead, value: false)
        .childChannelOption(
          .recvAllocator,
          value: FixedSizeRecvByteBufferAllocator(capacity: TransportLimits.receiveChunkBytes)
        )
        .childChannelOption(.maxMessagesPerRead, value: 1)
        .childChannelOption(.writeBufferWaterMark, value: .init(low: 1_048_576, high: 4_194_304))
        .childChannelInitializer { channel in
          // NIO2.104.0 AcceptHandler applies child options and invokes this initializer before
          // forwarding the child for registration. Thus even a peer that pipelines HTTP in
          // connect() cannot be read until the returned future has succeeded. The listener's
          // close waits for every check it began, so none completes on a stopped loop.
          guard registry.beginCheck() else {
            return channel.eventLoop.makeFailedFuture(
              IPCError.closed(code: 1001, reason: "Listener stopping"))
          }
          let accepted = check.run(on: channel).flatMapThrowing { peer in
            let state = ConnectionState(channel: channel, isServer: true)
            guard registry.add(state) else {
              throw IPCError.closed(code: 1001, reason: "Listener stopping")
            }
            channel.closeFuture.whenComplete { _ in registry.remove(state) }
            let connection = LocalConnection(peer: peer, state: state)
            let handshake = UpgradeHandshake(channel: channel)
            try configureServerUpgrade(state: state, handshake: handshake) {
              registry.start(connection: connection, onConnection: onConnection)
            }
          }.flatMap {
            channel.setOption(.autoRead, value: true)
          }
          // After this turn of the loop, so the accept handler's own callbacks run first.
          accepted.whenComplete { _ in channel.eventLoop.execute { registry.endCheck() } }
          return accepted
        }
        .withBoundSocket(socket).get()
      do {
        // The adopted socket listens under its staging name and cannot accept with
        // autoRead=false. Its private parent is already 0700. Accepts begin only after the
        // 0600 socket has its public name.
        try lease.publish()
        try Task.checkCancellation()
        let listener = LocalWebSocketListener(
          channel: channel, resources: resources, registry: registry, lease: lease)
        try await channel.setOption(.autoRead, value: true).get()
        return listener
      } catch {
        channel.close(promise: nil)
        try? await channel.closeFuture.get()
        throw error
      }
    } catch {
      await registry.closeConnections()
      resources.stop()
      await resources.waitUntilStopped()
      lease.release()
      throw mapSocketError(error, operation: "listen Unix socket")
    }
  }

  private static func mapSocketError(_ error: any Error, operation: String) -> any Error {
    if let error = error as? IOError {
      return IPCError.systemCall(operation: operation, code: error.errnoCode)
    }
    return error
  }
}

/// Owns its listening channel, accepted channels, callback tasks and event loop.
public final class LocalWebSocketListener: Sendable {
  private let channel: any Channel
  private let resources: EventLoopOwner
  private let registry: ConnectionRegistry
  private let lease: SocketLease
  private let stopped = AsyncLatch()

  internal init(
    channel: any Channel, resources: EventLoopOwner, registry: ConnectionRegistry,
    lease: SocketLease
  ) {
    self.channel = channel
    self.resources = resources
    self.registry = registry
    self.lease = lease
  }

  /// Closes accepted connections with `code` and `reason` and ends their callbacks, then
  /// awaits the owned event-loop shutdown.
  public func close(code: Int = 1001, reason: String = "Listener stopping") async {
    guard let snapshot = registry.beginClose() else {
      await stopped.wait()
      return
    }
    channel.close(promise: nil)
    try? await channel.closeFuture.get()
    await registry.finishClose(snapshot, code: code, reason: reason)
    resources.stop()
    await resources.waitUntilStopped()
    lease.release()
    stopped.finish()
  }
}

/// Short lock-protected ownership operations only. Protocol work stays on NIO;
/// application callbacks stay in Swift tasks and never run under this lock.
internal final class ConnectionRegistry: @unchecked Sendable {
  struct Snapshot: Sendable {
    let states: [ConnectionState]
    let tasks: [Task<Void, Never>]
  }

  private let lock = NSLock()
  private var stopping = false
  private var states: [ObjectIdentifier: ConnectionState] = [:]
  private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
  /// Peer checks begun and not yet ended. Each completes on the listener's event loop, so
  /// closing waits for them before that loop stops.
  private var checks = 0
  private var checksEnded: [CheckedContinuation<Void, Never>] = []

  /// A peer check is starting; false once the listener is stopping.
  func beginCheck() -> Bool {
    lock.withLock {
      guard !stopping else { return false }
      checks += 1
      return true
    }
  }

  func endCheck() {
    let waiting = lock.withLock {
      checks -= 1
      guard checks == 0 else { return [CheckedContinuation<Void, Never>]() }
      defer { checksEnded.removeAll() }
      return checksEnded
    }
    for waiter in waiting { waiter.resume() }
  }

  private func waitForChecks() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let idle = lock.withLock {
        guard checks > 0 else { return true }
        checksEnded.append(continuation)
        return false
      }
      if idle { continuation.resume() }
    }
  }

  func add(_ state: ConnectionState) -> Bool {
    lock.withLock {
      guard !stopping else { return false }
      states[ObjectIdentifier(state)] = state
      return true
    }
  }

  func remove(_ state: ConnectionState) {
    _ = lock.withLock { states.removeValue(forKey: ObjectIdentifier(state)) }
  }

  func start(
    connection: LocalConnection, onConnection: @escaping @Sendable (LocalConnection) async -> Void
  ) {
    let identifier = ObjectIdentifier(connection.state)
    lock.withLock {
      guard !stopping else { return }
      // Holding the lock across creation prevents a completed task racing its
      // insertion and leaving a completed ownership record behind.
      tasks[identifier] = Task { [self] in
        await onConnection(connection)
        await connection.close()
        _ = lock.withLock { tasks.removeValue(forKey: identifier) }
      }
    }
  }

  func beginClose() -> Snapshot? {
    lock.withLock {
      guard !stopping else { return nil }
      stopping = true
      return Snapshot(states: Array(states.values), tasks: Array(tasks.values))
    }
  }

  func finishClose(_ snapshot: Snapshot, code: Int, reason: String) async {
    // Queue the owner's close first. Cancelling a callback that is waiting for a message
    // queues its own 1001 close from the cancellation handler, and the first close wins.
    for state in snapshot.states {
      state.channel.eventLoop.execute { state.close(code: code, reason: reason) }
    }
    for task in snapshot.tasks { task.cancel() }
    for state in snapshot.states { try? await state.channel.closeFuture.get() }
    for task in snapshot.tasks { await task.value }
    // A check still running ends with its connection refused: the registry is stopping.
    await waitForChecks()
  }

  func closeConnections() async {
    if let snapshot = beginClose() {
      await finishClose(snapshot, code: 1001, reason: "Listener stopping")
    }
  }
}
