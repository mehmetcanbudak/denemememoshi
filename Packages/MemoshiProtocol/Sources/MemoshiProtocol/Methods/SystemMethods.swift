/// `system.hello`: the first frame on a connection (protocol.md §3.3).
public enum SystemHello: RPCMethod {
  /// The handshake.
  public typealias Params = SystemHelloParams
  /// The daemon's answer.
  public typealias Result = SystemHelloResult
  /// `system.hello`.
  public static let name = "system.hello"
  /// Reads nothing and writes nothing.
  public static let isMutating = false
}

/// `system.status`: the daemon's state (protocol.md §5.1).
public enum SystemStatus: RPCMethod {
  /// None.
  public typealias Params = EmptyParams
  /// The daemon's state.
  public typealias Result = SystemStatusResult
  /// `system.status`.
  public static let name = "system.status"
  /// Read-only.
  public static let isMutating = false
}

/// The parameters of `system.hello`.
public struct SystemHelloParams: Codable, Hashable, Sendable {
  /// The 64 lowercase hex characters of `run/memoshid.token`.
  public var token: HelloToken
  /// The connecting client.
  public var client: ClientInfo
  /// The protocol versions the client supports.
  public var protocolRange: ProtocolRange
  /// The capabilities the client offers.
  public var capabilities: [Capability]
  /// The client's locale, such as `en-US`.
  public var locale: String
  /// The client's time zone, such as `Europe/Istanbul`.
  public var timeZone: String

  /// Creates hello parameters.
  public init(
    token: HelloToken, client: ClientInfo, protocolRange: ProtocolRange,
    capabilities: [Capability],
    locale: String, timeZone: String
  ) {
    self.token = token
    self.client = client
    self.protocolRange = protocolRange
    self.capabilities = capabilities
    self.locale = locale
    self.timeZone = timeZone
  }

  private enum CodingKeys: String, CodingKey {
    case token
    case client
    case protocolRange = "protocol"
    case capabilities
    case locale
    case timeZone
  }
}

/// The client in `system.hello`.
public struct ClientInfo: Codable, Hashable, Sendable {
  /// The product name, such as `Memoshi`.
  public var name: String
  /// The marketing version.
  public var version: String
  /// The build number.
  public var build: String
  /// The client's role (protocol.md §3.4).
  public var role: ClientRole

  /// Creates client information.
  public init(name: String, version: String, build: String, role: ClientRole) {
    self.name = name
    self.version = version
    self.build = build
    self.role = role
  }
}

/// A client's role (protocol.md §3.4).
public enum ClientRole: OpenEnum {
  /// Memoshi.app.
  case app
  /// The bundled signed `memoshi` CLI.
  case cli
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.app: "app", .cli: "cli"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// The result of `system.hello`.
public struct SystemHelloResult: Codable, Hashable, Sendable {
  /// The connection's ID.
  public var connectionId: String
  /// The daemon.
  public var daemon: DaemonInfo
  /// The chosen protocol major version.
  public var protocolVersion: Int
  /// The capabilities both sides support.
  public var capabilities: [Capability]
  /// The identity of the daemon's event log. A client that resumes against another identity
  /// drops its cursor and reloads (D131).
  public var logId: LogID
  /// The newest durable `seq` on this device's log.
  public var head: Int64
  /// The oldest `seq` still retained.
  public var minRetainedSeq: Int64
  /// The daemon's clock, Unix milliseconds.
  public var serverTime: Int64
  /// The SHA-256 of the canonical `protocol.schema.json`; informational only.
  public var schemaHash: String
  /// The connection's limits.
  public var limits: ConnectionLimits

  /// Creates a hello result.
  public init(
    connectionId: String, daemon: DaemonInfo, protocolVersion: Int, capabilities: [Capability],
    logId: LogID, head: Int64, minRetainedSeq: Int64, serverTime: Int64, schemaHash: String,
    limits: ConnectionLimits
  ) {
    self.connectionId = connectionId
    self.daemon = daemon
    self.protocolVersion = protocolVersion
    self.capabilities = capabilities
    self.logId = logId
    self.head = head
    self.minRetainedSeq = minRetainedSeq
    self.serverTime = serverTime
    self.schemaHash = schemaHash
    self.limits = limits
  }

  private enum CodingKeys: String, CodingKey {
    case connectionId
    case daemon
    case protocolVersion = "protocol"
    case capabilities
    case logId
    case head
    case minRetainedSeq
    case serverTime
    case schemaHash
    case limits
  }
}

/// The daemon in `system.hello`.
public struct DaemonInfo: Codable, Hashable, Sendable {
  /// The marketing version.
  public var version: String
  /// The build number.
  public var build: String
  /// The daemon's process ID.
  public var pid: Int
  /// When the daemon started.
  public var startedAt: Int64

  /// Creates daemon information.
  public init(version: String, build: String, pid: Int, startedAt: Int64) {
    self.version = version
    self.build = build
    self.pid = pid
    self.startedAt = startedAt
  }
}

/// A connection's limits (protocol.md §11).
public struct ConnectionLimits: Codable, Hashable, Sendable {
  /// The largest inbound message, in bytes.
  public var maxInboundBytes: Int
  /// The largest outbound frame, in bytes.
  public var maxOutboundFrameBytes: Int
  /// The most events in one batch frame.
  public var maxBatchEvents: Int
  /// The most requests in flight on the connection.
  public var maxInFlightRequests: Int
  /// The most focused conversations.
  public var maxFocus: Int

  /// Creates limits.
  public init(
    maxInboundBytes: Int, maxOutboundFrameBytes: Int, maxBatchEvents: Int,
    maxInFlightRequests: Int, maxFocus: Int
  ) {
    self.maxInboundBytes = maxInboundBytes
    self.maxOutboundFrameBytes = maxOutboundFrameBytes
    self.maxBatchEvents = maxBatchEvents
    self.maxInFlightRequests = maxInFlightRequests
    self.maxFocus = maxFocus
  }
}

/// The result of `system.status`.
public struct SystemStatusResult: Codable, Hashable, Sendable {
  /// The daemon's state.
  public var state: DaemonState
  /// The scheduler's state.
  public var scheduler: SchedulerState
  /// Whether the host connection (Memoshi.app's `host.*` server) is connected.
  public var hostConnected: Bool
  /// How many conversation stores are open.
  public var openThreads: Int
  /// How many runs are live.
  public var liveRuns: Int
  /// Present after repeated crashes put the daemon in safe mode.
  public var crashLoop: CrashLoop?

  /// Creates a status result.
  public init(
    state: DaemonState, scheduler: SchedulerState, hostConnected: Bool, openThreads: Int,
    liveRuns: Int, crashLoop: CrashLoop? = nil
  ) {
    self.state = state
    self.scheduler = scheduler
    self.hostConnected = hostConnected
    self.openThreads = openThreads
    self.liveRuns = liveRuns
    self.crashLoop = crashLoop
  }
}

/// The crashes that put the daemon in safe mode: at least 3 in 5 minutes (04-architecture §2.3).
public struct CrashLoop: Codable, Hashable, Sendable {
  /// How many crashes fell in the window.
  public var crashes: Int
  /// The window's length in milliseconds.
  public var windowMs: Int64
  /// When the last crash happened.
  public var lastCrashAt: Int64

  /// Creates a crash-loop record.
  public init(crashes: Int, windowMs: Int64, lastCrashAt: Int64) {
    self.crashes = crashes
    self.windowMs = windowMs
    self.lastCrashAt = lastCrashAt
  }
}

/// The daemon's state (protocol.md §5.1).
public enum DaemonState: OpenEnum {
  case starting
  case ready
  /// Preparing for an update.
  case quiescing
  /// After a crash loop: reads work, nothing runs.
  case safeMode
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .starting: "starting", .ready: "ready", .quiescing: "quiescing", .safeMode: "safe_mode",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// The scheduler's state (04-architecture §2.3, §2.5).
public enum SchedulerState: OpenEnum {
  case running
  /// Paused while the Mac sleeps.
  case paused
  /// Held while the daemon quiesces for an update.
  case held
  /// Off in safe mode.
  case off
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .running: "running", .paused: "paused", .held: "held", .off: "off",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
