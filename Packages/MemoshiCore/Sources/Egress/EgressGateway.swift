import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import Synchronization

/// One attributed gateway decision. It names the bindings a request carried, not their values;
/// the log masks recognized credential forms in every string before retaining the decision.
public struct EgressDecision: Sendable, Codable, Equatable {
  /// Milliseconds since 1970.
  public let at: Int64
  /// The bot of the gateway client that carried the request.
  public let bot: String
  /// The conversation of that client.
  public let conversation: String
  /// The computer of that client.
  public let computer: String
  /// The tool call whose live attribution token the request presented, or nil when it had none.
  public let call: String?
  /// `CONNECT` or the forwarded HTTP method, with known credential forms masked.
  public let method: String
  /// The requested host, normalized when valid, with known credential forms masked before capping.
  public let host: String
  /// The requested port.
  public let port: Int
  /// Whether the gateway let the request reach its upstream.
  public let allowed: Bool
  /// `allowed`, or the refusal reason such as `host_not_allowed`.
  public let reason: String
  /// The refused address class after resolution, such as `loopback`.
  public let addressClass: String?
  /// Secret bindings whose placeholders the request carried.
  public let secrets: [String]
  /// Header injections keyed by binding name with opaque broker references; never values.
  public let secretReferences: [String: String]
}

/// The gateway's own append-only decision log: the most recent decisions in memory for
/// inspection and, when configured, one JSON line per decision in a private file. Denials are
/// the attributed violations. Every string is scrubbed before either sink sees it, against
/// placeholders and credential values released anywhere in this gateway's lifetime and the
/// tokens of its live calls; denied hosts never cause broker reads.
final class EgressDecisionLog: Sendable {
  private struct State: Sendable {
    /// The retained window as a ring: once full, `oldest` is the next entry replaced.
    var entries: [EgressDecision] = []
    var oldest = 0
    var recorded = 0
    var protectedValues: Set<String> = []
    var liveTokens: Set<String> = []
    /// Changes whenever a protection is added or dropped.
    var generation = 0
    var scrubber = EgressEchoScrubber(values: [])

    func redacted(_ decision: EgressDecision) -> EgressDecision {
      func text(_ value: String) -> String {
        scrubber.scrub(value, ignoringASCIICase: true)
      }
      return EgressDecision(
        at: decision.at, bot: text(decision.bot), conversation: text(decision.conversation),
        computer: text(decision.computer), call: decision.call.map(text),
        method: text(decision.method), host: String(text(decision.host).prefix(255)),
        port: decision.port, allowed: decision.allowed, reason: text(decision.reason),
        addressClass: decision.addressClass.map(text), secrets: decision.secrets.map(text),
        secretReferences: Dictionary(
          decision.secretReferences.map { (text($0.key), text($0.value)) },
          uniquingKeysWith: { first, _ in first }))
    }
  }

  private let state = Mutex(State())
  private let file: Mutex<FileHandle?>
  private let window: Int

  init(file url: URL?, retaining window: Int = EgressLimits.standard.retainedDecisions) throws {
    self.window = max(1, window)
    guard let url else {
      file = Mutex(nil)
      return
    }
    let descriptor = Darwin.open(
      url.path, O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw EgressConfigurationError.logUnavailable }
    file = Mutex(FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
  }

  /// Placeholders and credential values. Their recognized forms are kept after rotation too:
  /// an old value must not become loggable again. Registration precedes forwarding a fetched
  /// credential.
  func protect(_ value: String) {
    state.withLock {
      guard !value.isEmpty, $0.protectedValues.insert(value).inserted else { return }
      $0.scrubber.include(value)
      $0.generation += 1
    }
  }

  /// A call's attribution token, protected from before it is exposed until the call ends. A
  /// revoked token attributes nothing, so keeping every one would only make each later
  /// decision and response slower.
  func protectCall(_ token: String) {
    state.withLock {
      guard $0.liveTokens.insert(token).inserted else { return }
      $0.scrubber.include(token)
      $0.generation += 1
    }
  }

  func releaseCall(_ token: String) {
    state.withLock {
      guard $0.liveTokens.remove(token) != nil else { return }
      $0.scrubber.exclude(token)
      $0.generation += 1
    }
  }

  /// Request-supplied decision text, masked as soon as the request arrives: its call may end,
  /// and its token's protection with it, before the decision is recorded.
  func scrub(_ text: String) -> String {
    state.withLock { $0.scrubber.scrub(text, ignoringASCIICase: true) }
  }

  /// Refreshes per-response protections; streams never share their pending body suffix.
  func refreshResponseScrubber(_ stream: inout EgressEchoScrubber, since version: Int) -> Int {
    state.withLock { current in
      if version != current.generation { stream.adoptProtections(from: current.scrubber) }
      return current.generation
    }
  }

  @discardableResult
  func append(_ decision: EgressDecision) throws -> EgressDecision {
    let safe = state.withLock { $0.redacted(decision) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let line = try encoder.encode(safe)
    try file.withLock { handle in
      try handle?.write(contentsOf: line + Data([0x0a]))
    }
    state.withLock {
      $0.recorded += 1
      if $0.entries.count < window {
        $0.entries.append(safe)
      } else {
        $0.entries[$0.oldest] = safe
        $0.oldest = ($0.oldest + 1) % window
      }
    }
    return safe
  }

  /// The retained window, oldest first.
  var snapshot: [EgressDecision] {
    state.withLock { Array($0.entries[$0.oldest...] + $0.entries[..<$0.oldest]) }
  }

  /// Decisions appended so far, including those no longer retained in memory.
  var recorded: Int { state.withLock { $0.recorded } }

  /// The retained window, oldest first, and the count recorded so far, read under one lock so
  /// the two always describe the same moment.
  var retained: (decisions: [EgressDecision], recorded: Int) {
    state.withLock {
      (Array($0.entries[$0.oldest...] + $0.entries[..<$0.oldest]), $0.recorded)
    }
  }

  /// Distinct recognized forms currently protected.
  var protectionCount: Int { state.withLock { $0.scrubber.formCount } }

  func close() { file.withLock { $0 = nil } }
}

/// The gateway's resource bounds. Production uses `standard`; tests alone shorten them.
struct EgressLimits: Sendable {
  /// Open proxy connections one client may hold, counting a tunnel's upstream that has
  /// outlived its client connection; a further one is closed at once.
  var connections = 64
  /// How long a connection may take to deliver its request head.
  var headDeadline = TimeAmount.seconds(60)
  /// Name resolutions one client may have in flight; further ones wait their turn.
  var resolutions = 1
  /// Decisions kept in memory for inspection; the log file and the sink receive every one.
  var retainedDecisions = 4096
  /// How long a tunnel's upstream, left behind by its client, may take to accept what the
  /// client had sent.
  var flushDeadline = TimeAmount.seconds(10)

  static let standard = EgressLimits()
}

/// The development HTTP forward and `CONNECT` gateway. Each client has an isolated loopback
/// listener and, when requested, an exact Unix-domain socket reachable from its sandbox.
/// The sandbox permits that socket alone: no TCP, UDP, localhost alias or same-port LAN rule.
/// DNS is resolved outside the sandbox; every answer is checked and only those are dialed.
/// Opaque CONNECT traffic is host-level only, not method or credential-content enforcement.
/// A request carrying no proxy credential at all is answered `407` with a Basic challenge and
/// closed, so a client that sends its credential only when challenged (WebKit) can authenticate;
/// a challenge is counted in `challenges`, never recorded as a decision or audited.
public final class EgressGateway: Sendable {
  let group: MultiThreadedEventLoopGroup
  private let threadPool: NIOThreadPool
  let log: EgressDecisionLog
  let resolve: @Sendable (String, Int) async throws -> [SocketAddress]
  let route: (@Sendable (SocketAddress) -> SocketAddress)?
  let authorizer: (any EgressRequestAuthorizer)?
  private let decisionSink: (any EgressDecisionSink)?
  let upstreamTLS: NIOSSLContext
  let limits: EgressLimits
  private let clients = Mutex<[ObjectIdentifier: EgressClient]?>([:])
  private let challengeCount = Mutex(0)

  private init(
    group: MultiThreadedEventLoopGroup, threadPool: NIOThreadPool, log: EgressDecisionLog,
    resolve: (@Sendable (String, Int) async throws -> [SocketAddress])?,
    route: (@Sendable (SocketAddress) -> SocketAddress)?,
    authorizer: (any EgressRequestAuthorizer)?, decisionSink: (any EgressDecisionSink)?,
    upstreamTLS: NIOSSLContext, limits: EgressLimits
  ) {
    self.group = group
    self.threadPool = threadPool
    self.log = log
    self.resolve =
      resolve ?? { host, port in
        try await threadPool.runIfActive { try EgressResolver.system(host, port: port) }
      }
    self.route = route
    self.authorizer = authorizer
    self.decisionSink = decisionSink
    self.upstreamTLS = upstreamTLS
    self.limits = limits
  }

  /// Starts the gateway. With `decisionLog`, every decision is also appended to that new
  /// private file, which must not exist yet.
  public static func start(
    decisionLog: URL? = nil, authorizer: (any EgressRequestAuthorizer)? = nil,
    decisionSink: (any EgressDecisionSink)? = nil
  ) async throws -> EgressGateway {
    try await start(
      decisionLog: decisionLog, resolve: nil, route: nil, authorizer: authorizer,
      decisionSink: decisionSink)
  }

  /// Tests alone pass `resolve` and `route`: a request still meets every name, list, mask and
  /// address check against the resolved address, and only the connection is then delivered to
  /// the routed address, an owned loopback server. Production has no such seam.
  static func start(
    decisionLog: URL?, resolve: (@Sendable (String, Int) async throws -> [SocketAddress])?,
    route: (@Sendable (SocketAddress) -> SocketAddress)?,
    authorizer: (any EgressRequestAuthorizer)? = nil,
    decisionSink: (any EgressDecisionSink)? = nil, upstreamTLS: NIOSSLContext? = nil,
    limits: EgressLimits = .standard
  ) async throws -> EgressGateway {
    let log = try EgressDecisionLog(file: decisionLog, retaining: limits.retainedDecisions)
    let tls = try upstreamTLS ?? NIOSSLContext(configuration: .makeClientConfiguration())
    let pool = NIOThreadPool(numberOfThreads: 2)
    pool.start()
    return EgressGateway(
      group: MultiThreadedEventLoopGroup(numberOfThreads: 1), threadPool: pool, log: log,
      resolve: resolve, route: route, authorizer: authorizer, decisionSink: decisionSink,
      upstreamTLS: tls, limits: limits)
  }

  /// The most recent decisions, oldest first. Memory keeps a bounded window of them; the
  /// decision log file and the decision sink receive every decision.
  public var decisions: [EgressDecision] { log.snapshot }

  /// Decisions recorded so far, including those `decisions` no longer retains.
  public var decisionCount: Int { log.recorded }

  /// ``decisions`` and ``decisionCount`` read together at one moment: `recorded` counts every
  /// decision up to and including the newest in `decisions`.
  public var decisionWindow: (decisions: [EgressDecision], recorded: Int) { log.retained }

  /// Proxy-authentication challenges answered so far: requests with no `Proxy-Authorization`.
  /// Separate from decisions: a challenge allows nothing, refuses no host and resolves nothing.
  public var challenges: Int { challengeCount.withLock { $0 } }

  func noteChallenge() { challengeCount.withLock { $0 += 1 } }

  /// Audit-before-dispatch: the external sink receives only the scrubbed record. A failed
  /// required sink does not turn an unrecorded request into an allowed upstream effect.
  func record(_ decision: EgressDecision) async -> Bool {
    do {
      let safe = try log.append(decision)
      try await decisionSink?.record(safe)
      return true
    } catch {
      return false
    }
  }

  /// Opens one computer's isolated listener and, optionally, a host-owned Unix socket.
  /// `confinedSocket` is the usable route for a Seatbelt daemon; ordinary TCP proxy clients
  /// such as WebKit use the loopback listener without receiving any kernel allowance.
  public func openClient(
    _ identity: EgressClientIdentity, policy: EgressPolicy, confinedSocket: Bool = false
  ) async throws -> EgressClient {
    let core = EgressClientCore(identity: identity, policy: policy, gateway: self)
    let connections = core.connections
    let limits = limits
    let socket = confinedSocket ? try EgressUnixSocket() : nil
    let listener: any Channel
    var unixListener: (any Channel)?
    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(.backlog, value: 64)
      .childChannelOption(.allowRemoteHalfClosure, value: true)
      .childChannelInitializer { channel in
        // A failed initializer closes the connection: one client cannot hold every descriptor.
        guard connections.add(channel, limit: limits.connections) else {
          return channel.eventLoop.makeFailedFuture(EgressConfigurationError.closed)
        }
        return channel.eventLoop.makeCompletedFuture {
          let endOfInput = EgressEndOfInput()
          try channel.pipeline.syncOperations.addHandler(endOfInput)
          try channel.pipeline.syncOperations.addHandler(
            ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)),
            name: EgressProxyHandler.decoderName)
          try channel.pipeline.syncOperations.addHandler(
            HTTPResponseEncoder(), name: EgressProxyHandler.encoderName)
          try channel.pipeline.syncOperations.addHandler(
            EgressProxyHandler(core: core, endOfInput: endOfInput))
        }
      }
    do {
      listener = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
    } catch {
      socket?.remove()
      throw EgressConfigurationError.unbound
    }
    do {
      if let socket {
        unixListener = try await bootstrap.bind(unixDomainSocketPath: socket.path).get()
        try socket.seal()
        if let authorities = policy.tlsInterception?.certificateAuthoritiesPEM {
          try socket.publishCertificateAuthorities(authorities)
        }
      } else {
        unixListener = nil
      }
    } catch {
      try? await listener.close().get()
      try? await unixListener?.close().get()
      socket?.remove()
      throw EgressConfigurationError.unbound
    }
    guard let port = listener.localAddress?.port else {
      try? await listener.close().get()
      try? await unixListener?.close().get()
      socket?.remove()
      throw EgressConfigurationError.unbound
    }
    let client = EgressClient(
      core: core, port: port, listener: listener, unixListener: unixListener, socket: socket,
      connections: connections, gateway: self)
    let added = clients.withLock { open -> Bool in
      guard open != nil else { return false }
      open?[ObjectIdentifier(client)] = client
      return true
    }
    guard added else {
      await client.close()
      throw EgressConfigurationError.closed
    }
    return client
  }

  func forget(_ client: EgressClient) {
    _ = clients.withLock { $0?.removeValue(forKey: ObjectIdentifier(client)) }
  }

  /// Closes every client's listener and connections, then the event loop and resolver threads.
  public func shutdown() async {
    let open = clients.withLock { open -> [EgressClient] in
      defer { open = nil }
      return open.map { Array($0.values) } ?? []
    }
    for client in open { await client.close() }
    log.close()
    try? await threadPool.shutdownGracefully()
    try? await group.shutdownGracefully()
  }
}

/// A live tool call's attribution. Its token travels as the proxy credential of that call's
/// commands; ending the call revokes it.
public struct EgressCallAttribution: Sendable, Hashable {
  /// The tool call's ID, as decisions record it.
  public let call: String
  let token: String
}

/// One computer's isolated proxy endpoints, masks and live call attributions.
public final class EgressClient: Sendable {
  /// The attributed bot, conversation and computer.
  public var identity: EgressClientIdentity { core.identity }
  /// The loopback listener. A confined daemon never receives permission to connect by TCP.
  public let port: Int
  /// The optional confined route. Use a Unix-socket-capable HTTP client, for example curl's
  /// `--unix-socket \"$MEMOSHI_EGRESS_SOCKET\"`; a proxy-ignoring client still fails closed.
  public var socketPath: String? { socket?.path }
  /// Public trust material only; scoped to this client, never installed in a system trust store.
  public var certificateBundlePath: String? { socket?.certificateBundlePath }
  let core: EgressClientCore
  private let listener: any Channel
  private let unixListener: (any Channel)?
  private let socket: EgressUnixSocket?
  private let connections: EgressConnections
  private let gateway: EgressGateway
  private let closed = Mutex(false)

  init(
    core: EgressClientCore, port: Int, listener: any Channel, unixListener: (any Channel)?,
    socket: EgressUnixSocket?, connections: EgressConnections, gateway: EgressGateway
  ) {
    self.core = core
    self.port = port
    self.listener = listener
    self.unixListener = unixListener
    self.socket = socket
    self.connections = connections
    self.gateway = gateway
  }

  /// Each masked credential's environment variable and placeholder, for the sandbox.
  public var placeholders: [String: String] {
    Dictionary(uniqueKeysWithValues: core.masks.map { ($0.name, $0.placeholder) })
  }

  /// An explicit host-side proxy configuration, with no Codable or descriptive conformance.
  /// Revoking the attribution invalidates these credentials on the next request.
  public func proxyConfiguration(_ attribution: EgressCallAttribution) -> EgressProxyConfiguration {
    EgressProxyConfiguration(port: UInt16(port), password: attribution.token)
  }

  /// Proxy variables carrying the call's attribution token, and the confined Unix socket when
  /// available. No proxy variable itself grants network permission.
  public func proxyEnvironment(_ attribution: EgressCallAttribution? = nil) -> [String: String] {
    let credential = attribution.map { "memoshi:" + $0.token + "@" } ?? ""
    let proxy = "http://" + credential + "127.0.0.1:" + String(port)
    var environment: [String: String] = [:]
    for name in Self.bypassVariables { environment[name] = "" }
    if let socket { environment[Self.socketVariable] = socket.path }
    if let certificateBundlePath {
      for name in Self.certificateVariables { environment[name] = certificateBundlePath }
    }
    for name in Self.proxyVariables { environment[name] = proxy }
    return environment
  }

  /// Every variable ``proxyEnvironment(_:)`` may set, whether or not it sets it for this client:
  /// a sandbox host keeps these names for itself.
  public static let proxyVariableNames: Set<String> = Set(
    bypassVariables + [socketVariable] + certificateVariables + proxyVariables)
  private static let bypassVariables = ["no_proxy", "NO_PROXY"]
  private static let socketVariable = "MEMOSHI_EGRESS_SOCKET"
  private static let certificateVariables = [
    "CURL_CA_BUNDLE", "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE",
  ]
  private static let proxyVariables = ["http_proxy", "https_proxy", "all_proxy"].flatMap {
    [$0, $0.uppercased()]
  }

  /// Starts attributing requests that present the returned token to `call`.
  public func beginCall(_ call: String) -> EgressCallAttribution {
    let attribution = EgressCallAttribution(call: call, token: EgressRandom.hex(bytes: 16))
    core.protections.protectCall(attribution.token)
    core.calls.withLock { $0[attribution.token] = EgressLiveCall(id: call) }
    return attribution
  }

  /// Revokes the call and closes its active requests and opaque tunnels too.
  public func endCall(_ attribution: EgressCallAttribution) {
    let call = core.calls.withLock { $0.removeValue(forKey: attribution.token) }
    core.protections.releaseCall(attribution.token)
    for channel in call?.connections.drain() ?? [] { channel.close(promise: nil) }
  }

  /// Creates and registers an owned native exchange atomically with client closure. A
  /// registration is a drainage handle only; its request still presents the ordinary live
  /// attribution token. A closed client creates no exchange: after gateway shutdown its event
  /// loops are stopped, and a promise made there could never complete.
  func registerFetch() throws -> (key: String, operation: EgressFetchOperation) {
    try closed.withLock { closed in
      guard !closed else { throw EgressConfigurationError.closed }
      let operation = EgressFetchOperation(eventLoop: core.group.next())
      let key = EgressRandom.hex(bytes: 16)
      core.nativeFetches.withLock { $0[key] = operation }
      return (key, operation)
    }
  }

  /// Stops listening, closes every open connection and revokes every token.
  public func close() async {
    guard
      closed.withLock({ value -> Bool in
        defer { value = true }
        return !value
      })
    else { return }
    let fetches = core.nativeFetches.withLock { operations in
      defer { operations.removeAll() }
      return Array(operations.values)
    }
    for operation in fetches { operation.fail(EgressConfigurationError.closed) }
    let revoked = core.calls.withLock { calls in
      defer { calls.removeAll() }
      return calls
    }
    for (token, call) in revoked {
      core.protections.releaseCall(token)
      // Upstreams too: a tunnel's far side otherwise stays until its pending bytes are taken.
      for channel in call.connections.drain() { channel.close(promise: nil) }
    }
    try? await listener.close().get()
    try? await unixListener?.close().get()
    for channel in connections.drain() { try? await channel.close().get() }
    // A decision outlives its connection; none may complete on a stopped event loop.
    await core.decisions.drain()
    for operation in fetches { await operation.drain() }
    socket?.remove()
    gateway.forget(self)
  }
}

/// Credentials for an explicitly composed native proxy client. Values are never persistence or
/// presentation models; a live attribution owns their lifetime.
public struct EgressProxyConfiguration: Sendable {
  /// The client's loopback proxy address, never the upstream destination.
  public let host = "127.0.0.1"
  /// The TCP listener port for this client's proxy endpoint.
  public let port: UInt16
  /// The fixed proxy-authentication user; the password supplies live call attribution.
  public let username = "memoshi"
  /// The call's revocable attribution token, not an upstream credential or persisted secret.
  public let password: String

  init(port: UInt16, password: String) {
    self.port = port
    self.password = password
  }
}

final class EgressLiveCall: Sendable {
  let id: String
  let connections = EgressConnections()
  init(id: String) { self.id = id }
}

struct EgressActiveAttribution: Sendable {
  let token: String
  let live: EgressLiveCall
}

/// The policy half of a client, shared by its connection handlers.
final class EgressClientCore: Sendable {
  let identity: EgressClientIdentity
  let rules: [EgressHostRule]
  let masks: [EgressMask]
  let interception: EgressTLSInterception?
  let calls = Mutex<[String: EgressLiveCall]>([:])
  let nativeFetches = Mutex<[String: EgressFetchOperation]>([:])
  let decisions = EgressDecisions()
  /// The client's accepted connections, and tunnel upstreams that outlive them.
  let connections = EgressConnections()
  /// The client's name lookups one at a time per its limit; `resolutionsWaiting` counts those
  /// held back.
  private let resolutions: EgressTurns
  private let gateway: EgressGateway

  init(identity: EgressClientIdentity, policy: EgressPolicy, gateway: EgressGateway) {
    self.identity = identity
    rules = policy.hosts
    masks = policy.secrets.map(EgressMask.init)
    interception = policy.tlsInterception
    resolutions = EgressTurns(gateway.limits.resolutions)
    self.gateway = gateway
    for mask in masks { gateway.log.protect(mask.placeholder) }
  }

  var group: MultiThreadedEventLoopGroup { gateway.group }
  var upstreamTLS: NIOSSLContext { gateway.upstreamTLS }
  var limits: EgressLimits { gateway.limits }
  var protections: EgressDecisionLog { gateway.log }
  var resolutionsWaiting: Int { resolutions.waiting }

  /// Where a checked address is dialed: itself, except through the tests' route seam.
  func dialed(_ address: SocketAddress) -> SocketAddress { gateway.route?(address) ?? address }

  /// Every network request meets the current authorizer and audit sink before dispatch. No
  /// authorizer means hard allowlist-only qualification, never implicit Bypass. A request with no
  /// proxy credential at all is challenged first; a wrong or stale one is refused `unattributed`.
  func decide(
    _ head: HTTPRequestHead, channel: any Channel,
    intercepted: EgressInterceptedTarget? = nil
  ) async -> EgressVerdict {
    if intercepted == nil, !head.headers.contains(name: "proxy-authorization") {
      gateway.noteChallenge()
      return .challenge
    }
    let attribution = intercepted?.attribution ?? attributedCall(head.headers)
    if let attribution { attribution.live.connections.add(channel) }
    let target = EgressTarget(head, intercepted: intercepted)
    var decision = Draft(
      core: self, call: attribution?.live.id, method: gateway.log.scrub(head.method.rawValue),
      host: gateway.log.scrub(target.map { $0.normalized ?? $0.rawHost } ?? ""),
      port: target?.port ?? 0)
    guard let attribution else { return await refuse(&decision, "unattributed") }
    guard let target else { return await refuse(&decision, "invalid_request") }
    guard let host = target.normalized else {
      return await refuse(&decision, target.isIPLiteral ? "ip_literal" : "invalid_host")
    }
    if EgressHost.isIPLiteral(host) { return await refuse(&decision, "ip_literal") }
    if EgressHost.isLocalName(host) { return await refuse(&decision, "local_name") }
    let allowlisted = rules.contains { $0.matches(host: host, port: target.port) }
    if !allowlisted && rules.contains(where: { $0.matches(host: host) }) {
      return await refuse(&decision, "port_not_allowed")
    }
    if !allowlisted && gateway.authorizer == nil {
      return await refuse(&decision, "host_not_allowed")
    }
    let present = target.isConnect ? [] : EgressHeaderMasks.present(in: head, masks: masks)
    // Only a header that is forwarded can carry an injection; a stripped one releases nothing.
    let forwardable = target.isConnect ? HTTPHeaders() : Self.forwardedHeaders(head)
    let injections = EgressHeaderMasks.present(in: forwardable, masks: masks)
    decision.secrets = present.map(\.name).sorted()
    decision.secretReferences = Dictionary(
      uniqueKeysWithValues:
        injections.map { ($0.name, $0.secretRef) })
    if present.contains(where: { !$0.hosts.contains(host) }) {
      return await refuse(&decision, "secret_unbound_host")
    }
    let secretBound = masks.contains(where: { $0.hosts.contains(host) })
    if target.isConnect && secretBound && interception?.identities[host] == nil {
      return await refuse(&decision, "tls_interception_required")
    }
    let methodVisible = secretBound && !target.isConnect
    let writeAllowed = rules.contains(where: {
      $0.write && $0.matches(host: host, port: target.port)
    })
    let hasBody =
      head.headers.contains(name: "transfer-encoding")
      || (head.headers.first(name: "content-length").map { Int($0) != 0 } ?? false)
    let bodylessRead = (head.method == .GET || head.method == .HEAD) && !hasBody
    let request = EgressAuthorizationRequest(
      identity: identity, call: attribution.live.id, method: head.method.rawValue,
      host: host, port: target.port, allowlisted: allowlisted, tier: allowlisted ? 0 : 3,
      methodVisible: methodVisible,
      interceptsTLS: target.isConnect && secretBound && interception?.identities[host] != nil,
      usesTLS: target.isTLS,
      writeAllowed: writeAllowed,
      sendTier: methodVisible ? (bodylessRead ? 0 : (writeAllowed ? 3 : 4)) : nil,
      secrets: decision.secrets, secretReferences: decision.secretReferences)
    if gateway.authorizer == nil && (request.sendTier ?? 0) > 0 {
      return await refuse(&decision, "policy_required")
    }
    // DNS is already an external effect: never resolve a denied or unapproved hostname.
    guard !Task.isCancelled, isActive(attribution) else {
      return await refuse(&decision, "call_ended")
    }
    if let authorizer = gateway.authorizer {
      do {
        let authorization = try await authorizer.authorize(request)
        switch authorization {
        case .allow: break
        case .ask: return await refuse(&decision, "approval_required")
        case .deny: return await refuse(&decision, "policy_denied")
        }
      } catch { return await refuse(&decision, "policy_unavailable") }
    }
    guard !Task.isCancelled, isActive(attribution) else {
      return await refuse(&decision, "call_ended")
    }
    // A bound credential leaves only over verified TLS, whatever the authorizer allowed.
    if !injections.isEmpty && !target.isTLS {
      return await refuse(&decision, "secret_transport")
    }
    // One client's slow lookups wait for each other, not on every shared resolver thread.
    guard await resolutions.enter() else { return await refuse(&decision, "call_ended") }
    let resolved = try? await gateway.resolve(host, target.port)
    resolutions.leave()
    guard let addresses = resolved, !addresses.isEmpty else {
      return await refuse(&decision, "resolution_failed")
    }
    for address in addresses {
      if let addressClass = EgressAddress.deniedClass(address) {
        decision.addressClass = addressClass
        return await refuse(&decision, "resolved_private_address")
      }
    }
    var forwarded: HTTPRequestHead?
    if !target.isConnect {
      var values: [(placeholder: String, value: String)] = []
      do {
        for mask in injections {
          let value = try await mask.value()
          gateway.log.protect(value)
          guard value.utf8.count >= 6,
            !value.utf8.contains(where: { $0 == 0 || $0 == 10 || $0 == 13 })
          else { return await refuse(&decision, "secret_unavailable") }
          values.append((mask.placeholder, value))
        }
      } catch { return await refuse(&decision, "secret_unavailable") }
      forwarded = Self.forwardedHead(
        head, headers: forwardable, target: target, host: host, values: values)
      // Any gateway-known value can be echoed, including a rotated or other request's value.
      forwarded?.headers.replaceOrAdd(name: "accept-encoding", value: "identity")
    }
    guard isActive(attribution) else { return await refuse(&decision, "call_ended") }
    guard await gateway.record(decision.finish(allowed: true, reason: "allowed")) else {
      return await refuse(&decision, "audit_unavailable")
    }
    guard isActive(attribution) else { return await refuse(&decision, "call_ended") }
    if let authorizer = gateway.authorizer {
      do {
        switch try await authorizer.authorize(request) {
        case .allow: break
        case .ask: return await refuse(&decision, "approval_required")
        case .deny: return await refuse(&decision, "policy_denied")
        }
      } catch { return await refuse(&decision, "policy_unavailable") }
    }
    guard isActive(attribution) else { return await refuse(&decision, "call_ended") }
    return .allow(
      EgressRoute(
        addresses: addresses, head: forwarded,
        protections: gateway.log, attribution: attribution,
        tlsHost: target.isTLS && !target.isConnect ? host : nil,
        interception: target.isConnect ? interception?.identities[host] : nil,
        host: host, port: target.port))
  }

  private func refuse(_ decision: inout Draft, _ reason: String) async -> EgressVerdict {
    _ = await gateway.record(decision.finish(allowed: false, reason: reason))
    return .deny(reason)
  }

  func isActive(_ attribution: EgressActiveAttribution) -> Bool {
    !Task.isCancelled && calls.withLock { $0[attribution.token] === attribution.live }
  }

  private func attributedCall(_ headers: HTTPHeaders) -> EgressActiveAttribution? {
    guard headers["proxy-authorization"].count == 1,
      let value = headers.first(name: "proxy-authorization")
    else { return nil }
    let parts = value.split(separator: " ", maxSplits: 1)
    guard parts.count == 2, parts[0].lowercased() == "basic",
      let data = Data(base64Encoded: String(parts[1])),
      let text = String(data: data, encoding: .utf8),
      let separator = text.firstIndex(of: ":"), text[..<separator] == "memoshi"
    else { return nil }
    let token = String(text[text.index(after: separator)...])
    return calls.withLock { calls in
      calls[token].map { EgressActiveAttribution(token: token, live: $0) }
    }
  }

  /// The request's headers without proxy, hop-by-hop and `Connection`-listed ones.
  private static func forwardedHeaders(_ head: HTTPRequestHead) -> HTTPHeaders {
    var headers = HTTPHeaders()
    let listed = Set(
      head.headers["connection"].flatMap { $0.split(separator: ",") }.map {
        $0.trimmingCharacters(in: .whitespaces).lowercased()
      })
    let hopByHop: Set<String> = [
      "connection", "keep-alive", "proxy-authorization", "proxy-connection", "te", "trailer",
      "upgrade", "host",
    ]
    for (name, value) in head.headers {
      let lowered = name.lowercased()
      if hopByHop.contains(lowered) || listed.contains(lowered) { continue }
      headers.add(name: name, value: value)
    }
    return headers
  }

  /// The upstream request: origin-form target, the real `Host`, the forwarded headers with
  /// masked credentials replaced, and `Connection: close`.
  private static func forwardedHead(
    _ head: HTTPRequestHead, headers forwardable: HTTPHeaders, target: EgressTarget,
    host: String, values: [(placeholder: String, value: String)]
  ) -> HTTPRequestHead {
    var headers = forwardable
    EgressHeaderMasks.substitute(&headers, values: values)
    // The authority as the client's URL had it: no port when it is the scheme's default.
    let defaultPort = target.isTLS ? 443 : 80
    headers.replaceOrAdd(
      name: "host", value: target.port == defaultPort ? host : host + ":" + String(target.port))
    headers.replaceOrAdd(name: "connection", value: "close")
    return HTTPRequestHead(
      version: .http1_1, method: head.method, uri: target.originForm, headers: headers)
  }

  struct Draft {
    let core: EgressClientCore
    let call: String?
    let method: String
    let host: String
    let port: Int
    var addressClass: String?
    var secrets: [String] = []
    var secretReferences: [String: String] = [:]

    init(core: EgressClientCore, call: String?, method: String, host: String, port: Int) {
      self.core = core
      self.call = call
      self.method = method
      self.host = host
      self.port = port
    }

    func finish(allowed: Bool, reason: String) -> EgressDecision {
      EgressDecision(
        at: Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)),
        bot: core.identity.bot, conversation: core.identity.conversation,
        computer: core.identity.computer, call: call, method: method, host: host, port: port,
        allowed: allowed, reason: reason, addressClass: addressClass, secrets: secrets,
        secretReferences: secretReferences)
    }
  }
}

/// The gateway's answer to one request head.
enum EgressVerdict: Sendable {
  case deny(String)
  /// No proxy credential: answer `407` with a Basic challenge; nothing was decided.
  case challenge
  case allow(EgressRoute)
}

/// Where an allowed request goes: every resolved address, each one checked and tried in order
/// until one connects; the rewritten head of a forwarded request (nil for a tunnel) and the
/// gateway's protections for its response.
struct EgressRoute: Sendable {
  let addresses: [SocketAddress]
  let head: HTTPRequestHead?
  let protections: EgressDecisionLog
  let attribution: EgressActiveAttribution
  let tlsHost: String?
  let interception: NIOSSLContext?
  let host: String
  let port: Int
}

struct EgressInterceptedTarget: Sendable {
  let host: String
  let port: Int
  let attribution: EgressActiveAttribution
}

/// A proxy request's destination: `CONNECT host:port` or an absolute-form `http://` target.
struct EgressTarget: Sendable {
  let rawHost: String
  let normalized: String?
  let port: Int
  let isConnect: Bool
  let isTLS: Bool
  let isIPLiteral: Bool
  let originForm: String

  init?(_ head: HTTPRequestHead, intercepted: EgressInterceptedTarget? = nil) {
    if let intercepted {
      guard head.method != .CONNECT, head.uri.hasPrefix("/"), !head.uri.hasPrefix("//"),
        head.headers["host"].count == 1,
        let authority = head.headers.first(name: "host"),
        let host = EgressTarget(
          HTTPRequestHead(
            version: .http1_1, method: .CONNECT,
            uri: authority.contains(":")
              ? authority : authority + ":443")),
        host.normalized == intercepted.host, host.port == intercepted.port
      else { return nil }
      self.init(
        host: intercepted.host, port: intercepted.port, isConnect: false, isTLS: true,
        originForm: head.uri)
      return
    }
    if head.method == .CONNECT {
      let authority = head.uri
      guard let colon = authority.lastIndex(of: ":"),
        let port = Int(authority[authority.index(after: colon)...]), (1...65_535).contains(port)
      else { return nil }
      let host = String(authority[..<colon])
      self.init(host: host, port: port, isConnect: true, isTLS: true, originForm: "")
      return
    }
    guard let components = URLComponents(string: head.uri),
      let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
      let host = components.percentEncodedHost, components.user == nil, components.password == nil,
      components.fragment == nil
    else { return nil }
    let port = components.port ?? (scheme == "https" ? 443 : 80)
    guard (1...65_535).contains(port) else { return nil }
    var origin = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
    if let query = components.percentEncodedQuery { origin += "?" + query }
    self.init(
      host: host, port: port, isConnect: false, isTLS: scheme == "https", originForm: origin)
  }

  private init(host: String, port: Int, isConnect: Bool, isTLS: Bool, originForm: String) {
    rawHost = host
    isIPLiteral = host.hasPrefix("[") || host.contains(":")
    normalized = isIPLiteral ? nil : EgressHost.normalize(host)
    self.port = port
    self.isConnect = isConnect
    self.isTLS = isTLS
    self.originForm = originForm
  }
}

/// Name resolution on the gateway's own threads, never inside the sandbox.
enum EgressResolver {
  struct Failure: Error {}

  static func system(_ host: String, port: Int) throws -> [SocketAddress] {
    var hints = addrinfo()
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    hints.ai_protocol = IPPROTO_TCP
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, String(port), &hints, &result) == 0, let first = result else {
      throw Failure()
    }
    defer { freeaddrinfo(first) }
    var addresses: [SocketAddress] = []
    var cursor: UnsafeMutablePointer<addrinfo>? = first
    while let info = cursor {
      if let pointer = info.pointee.ai_addr {
        switch info.pointee.ai_family {
        case AF_INET:
          let address = pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
          addresses.append(SocketAddress(address, host: host))
        case AF_INET6:
          let address = pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
            $0.pointee
          }
          addresses.append(SocketAddress(address, host: host))
        default:
          break
        }
      }
      cursor = info.pointee.ai_next
    }
    return addresses
  }
}

/// A client's open connections, closed with it.
final class EgressConnections: Sendable {
  private let open = Mutex<[ObjectIdentifier: any Channel]>([:])

  /// False, adding nothing, when `limit` connections are already open.
  @discardableResult
  func add(_ channel: any Channel, limit: Int = .max) -> Bool {
    let id = ObjectIdentifier(channel)
    let added = open.withLock { open -> Bool in
      guard open.count < limit else { return false }
      open[id] = channel
      return true
    }
    guard added else { return false }
    channel.closeFuture.whenComplete { [weak self] _ in
      _ = self?.open.withLock { $0.removeValue(forKey: id) }
    }
    return true
  }

  func drain() -> [any Channel] {
    open.withLock { values in
      defer { values.removeAll() }
      return Array(values.values)
    }
  }
}

/// A client's request decisions still in flight. Closing the client waits for them, as it does
/// for native fetches, so none completes on an event loop that shutdown has stopped.
final class EgressDecisions: Sendable {
  private let pending = Mutex<[ObjectIdentifier: EventLoopFuture<EgressVerdict>]>([:])

  func add(_ decision: EventLoopFuture<EgressVerdict>) {
    let id = ObjectIdentifier(decision)
    pending.withLock { $0[id] = decision }
    decision.whenComplete { [weak self] _ in
      _ = self?.pending.withLock { $0.removeValue(forKey: id) }
    }
  }

  func drain() async {
    for decision in pending.withLock({ Array($0.values) }) { _ = try? await decision.get() }
  }
}

/// A bounded number of turns, taken in arrival order.
final class EgressTurns: Sendable {
  private struct State: Sendable {
    var free: Int
    var issued = 0
    var waiting: [(id: Int, turn: CheckedContinuation<Bool, Never>)] = []
    var cancelled: Set<Int> = []
  }

  private let state: Mutex<State>

  init(_ count: Int) { state = Mutex(State(free: max(1, count))) }

  /// Waits for a turn. False, holding none, when the task is cancelled first.
  func enter() async -> Bool {
    let id = state.withLock { state -> Int? in
      if state.free > 0 {
        state.free -= 1
        return nil
      }
      state.issued += 1
      return state.issued
    }
    guard let id else { return true }
    let entered = await withTaskCancellationHandler {
      await withCheckedContinuation { turn in
        let cancelled = state.withLock { state -> Bool in
          if state.cancelled.remove(id) != nil { return true }
          state.waiting.append((id, turn))
          return false
        }
        if cancelled { turn.resume(returning: false) }
      }
    } onCancel: {
      let turn = state.withLock { state -> CheckedContinuation<Bool, Never>? in
        guard let index = state.waiting.firstIndex(where: { $0.id == id }) else {
          // Not waiting yet, or already given its turn; the latter leaves like any holder.
          state.cancelled.insert(id)
          return nil
        }
        return state.waiting.remove(at: index).turn
      }
      turn?.resume(returning: false)
    }
    // A cancellation that arrived after the turn was given left its mark behind.
    state.withLock { _ = $0.cancelled.remove(id) }
    return entered
  }

  /// Hands the turn to the longest waiter, if any.
  func leave() {
    let next = state.withLock { state -> CheckedContinuation<Bool, Never>? in
      guard !state.waiting.isEmpty else {
        state.free += 1
        return nil
      }
      return state.waiting.removeFirst().turn
    }
    next?.resume(returning: true)
  }

  /// Requests waiting for a turn now.
  var waiting: Int { state.withLock { $0.waiting.count } }
}
