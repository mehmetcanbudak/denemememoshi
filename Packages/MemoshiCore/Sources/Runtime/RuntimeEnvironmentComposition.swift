import Foundation
import MemoshiEgress
import MemoshiProtocol
import MemoshiStore

/// Explicit development and qualification composition of conversation computers (S1.12, P0-21).
/// The normal app and daemon pass ``none``: no `env` hook is installed, so every call keeps
/// resolving no environment. No RPC, stored record or model input can select any of it.
public struct RuntimeEnvironmentComposition: Sendable {
  /// The production composition: no computer for any conversation.
  public static let none = RuntimeEnvironmentComposition()

  /// Resolves each call's conversation and bot to the bot's Computer.
  public var directory: (any RuntimeComputerDirectory)?
  /// Starts This Mac sandbox computers; required when the directory can return one.
  public var sandbox: RuntimeSandboxHost?

  /// Composes a computer directory and, for sandboxed computers, their host.
  public init(
    directory: (any RuntimeComputerDirectory)? = nil, sandbox: RuntimeSandboxHost? = nil
  ) {
    self.directory = directory
    self.sandbox = sandbox
  }
}

/// The narrow bot → Computer lookup between conversation records and environments. The runtime
/// asks on every tool call and generation, so a changed Computer applies from the next call.
public protocol RuntimeComputerDirectory: Sendable {
  /// The computer `bot` uses in `conversation` now.
  func computer(conversation: ConversationID, bot: BotID) async throws -> RuntimeComputer
}

/// A conversation's computer (06 §2.1).
public enum RuntimeComputer: Sendable {
  /// No computer: tools see no execution environment, the production default.
  case none
  /// This Mac (sandboxed): a Seatbelt-confined PiEnv daemon for file operations and one
  /// Seatbelt instance per command, whose only network is the egress gateway client (D16,
  /// D77, D96).
  case thisMacSandbox(RuntimeSandboxComputer)
}

/// One sandboxed computer. The runtime keeps one daemon per conversation while the directory
/// returns the same instance, and replaces it when the directory returns a different one.
public final class RuntimeSandboxComputer: Sendable {
  /// The computer's identity, recorded with every gateway decision.
  public let id: String
  /// The bot's private home: `HOME`, with `TMPDIR` at `tmp/` inside it. Canonical and absolute.
  public let home: String
  /// The conversation's private working copy, such as ``RuntimeWorkingCopy/workingRoot``, where
  /// commands start. Never a live source folder (D96). Canonical and absolute.
  public let workingRoot: String?
  /// The bot's network list and masked credentials.
  public let network: EgressPolicy

  /// Paths must already be canonical (`realpath`), because Seatbelt compares canonical paths.
  public init(id: String, home: String, workingRoot: String?, network: EgressPolicy) {
    self.id = id
    self.home = home
    self.workingRoot = workingRoot
    self.network = network
  }
}

/// Starts a confined daemon with the current Store-backed gateway policy and required audit.
/// The production app/helper still supply no sandbox host.
public struct RuntimeSandboxHost: Sendable {
  /// An absolute executable and its arguments. The process must run
  /// ``RuntimeSandboxDaemon/serve()``; the profile lets it read and execute only that file
  /// beyond approved system paths.
  public let daemonCommand: [String]
  /// Every sandbox receives only its own exact Unix-domain gateway socket. Proxy environment
  /// variables alone are not confinement or tool compatibility: commands must support that
  /// transport (for example curl --unix-socket). TCP/UDP-only tools remain unavailable.
  public let gateway: EgressGateway
  /// Explicitly trusted installed compiler/runtime assets, readable but never writable.
  /// Canonical directories only; never pass a user home, source grant or shared cache here.
  /// No toolchain discovery, install, network or Mach-service permission is implied.
  public let readOnlyToolchainRoots: [String]
  #if os(macOS)
    /// Attributes every kernel denial in these sandboxes to its command or daemon life by the
    /// tag the kernel prints (S4.7). Its reader runs while a sandbox session is open.
    public let denials: SandboxDenialMonitor
  #endif

  /// Creates both gateway ports from the same current-policy/audit owner. A mask alone never
  /// grants credential access; absent account authority denies every actual injection.
  /// `denialLog`, when given, must not exist yet: each invocation, its return, every denial
  /// and every reader gap become one JSON line there, created private (0600). The same
  /// entries are kept in `store`, bounded by row count (S4.7).
  public init(
    daemonCommand: [String], store: Store, directory: any RuntimeComputerDirectory,
    decisionLog: URL? = nil, accountAuthority: RuntimeGatewayPolicy.AccountAuthority? = nil,
    readOnlyToolchainRoots: [String] = [], denialLog: URL? = nil
  ) async throws {
    try Self.validateCommand(daemonCommand)
    try Self.validateToolchainRoots(readOnlyToolchainRoots)
    #if os(macOS)
      denials = try SandboxDenialMonitor(log: denialLog, store: store)
    #endif
    let policy = RuntimeGatewayPolicy(
      store: store, directory: directory, accountAuthority: accountAuthority)
    gateway = try await EgressGateway.start(
      decisionLog: decisionLog, authorizer: policy, decisionSink: policy)
    self.daemonCommand = daemonCommand
    self.readOnlyToolchainRoots = readOnlyToolchainRoots
  }

  // Kernel-only fixtures inject their owned resolver/transport without pretending to run a
  // live Store. This is deliberately not a public app/daemon construction path.
  init(
    daemonCommand: [String], gateway: EgressGateway, readOnlyToolchainRoots: [String] = [],
    denialLog: URL? = nil, store: Store? = nil
  ) throws {
    try Self.validateCommand(daemonCommand)
    try Self.validateToolchainRoots(readOnlyToolchainRoots)
    #if os(macOS)
      denials = try SandboxDenialMonitor(log: denialLog, store: store)
    #endif
    self.daemonCommand = daemonCommand
    self.gateway = gateway
    self.readOnlyToolchainRoots = readOnlyToolchainRoots
  }

  /// Closes the host-owned egress gateway once every sandbox session has closed.
  public func close() async {
    await gateway.shutdown()
  }

  #if os(macOS)
    // Kernel fixtures that drive the denial reader themselves.
    init(daemonCommand: [String], gateway: EgressGateway, monitor: SandboxDenialMonitor) throws {
      try Self.validateCommand(daemonCommand)
      denials = monitor
      self.daemonCommand = daemonCommand
      self.gateway = gateway
      readOnlyToolchainRoots = []
    }
  #endif

  private static func validateCommand(_ command: [String]) throws {
    guard let executable = command.first, executable.hasPrefix("/"),
      FileManager.default.isExecutableFile(atPath: executable)
    else { throw RuntimeEnvironmentError.invalidComposition }
  }

  private static func validateToolchainRoots(_ roots: [String]) throws {
    #if os(macOS)
      for root in roots {
        var directory: ObjCBool = false
        guard root != "/", SandboxPaths.isCanonical(root),
          FileManager.default.fileExists(atPath: root, isDirectory: &directory),
          directory.boolValue
        else { throw RuntimeEnvironmentError.invalidComposition }
      }
    #else
      guard roots.isEmpty else { throw RuntimeEnvironmentError.invalidComposition }
    #endif
  }
}

/// Presentation-safe environment failures; native diagnostics never reach a caller or model.
public enum RuntimeEnvironmentError: Error, Equatable, Sendable {
  case invalidComposition
  case unavailable
  case closed
  case commandFailed
}
