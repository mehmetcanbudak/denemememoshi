#if os(macOS)
  import Chord
  import Darwin
  import Foundation
  import MemoshiEgress
  import MemoshiProtocol
  import PiEnv
  import Synchronization

  /// One conversation's This Mac sandbox: a lazily started, Seatbelt-confined PiEnv daemon rooted
  /// in its private working copy for file operations, and one Seatbelt instance per command,
  /// each with its own denial tag (S4.7). The only outbound route is its exact host-owned Unix
  /// socket; TCP, UDP, local services, other bots' sockets and proxy-ignoring commands remain
  /// denied.
  final class SandboxComputerSession: RuntimeEnvironmentSession {
    let computer: RuntimeSandboxComputer
    let environment: any ExecutionEnv
    private let daemons: SandboxDaemons
    private let denials: SandboxDenialMonitor

    /// Refuses non-canonical paths before anything starts; Seatbelt compares canonical paths.
    init(
      computer: RuntimeSandboxComputer, conversation: ConversationID, bot: BotID,
      host: RuntimeSandboxHost
    ) throws {
      for path in [computer.home, computer.workingRoot, host.daemonCommand.first].compactMap({ $0 })
      {
        guard SandboxPaths.isCanonical(path) else {
          throw RuntimeEnvironmentError.invalidComposition
        }
      }
      try SandboxPaths.ensurePrivateDirectory(computer.home + "/tmp")
      self.computer = computer
      daemons = SandboxDaemons(
        computer: computer,
        identity: EgressClientIdentity(
          bot: bot.rawValue, conversation: conversation.rawValue, computer: computer.id),
        host: host)
      environment = SandboxExecutionEnv(
        id: "memoshi-sandbox-" + computer.id, cwd: computer.workingRoot ?? computer.home,
        daemons: daemons)
      denials = host.denials
      denials.open()
    }

    func close() async {
      await daemons.close()
      denials.close()
    }
  }

  /// Starts each daemon life and each command under its generated profile with a fresh denial
  /// tag, and owns every daemon, command and the gateway client until close. Closing ends
  /// running commands' process groups and waits for them at most ``commandCloseBound``, then
  /// ends daemons by stdin EOF; only a daemon that has not exited within the bound has its own
  /// process group killed. Close always ends with the gateway client closed.
  actor SandboxDaemons {
    let computer: RuntimeSandboxComputer
    let identity: EgressClientIdentity
    let host: RuntimeSandboxHost
    /// Starts `/usr/bin/sandbox-exec` for each command from the unconfined host: a confined
    /// process cannot start a second Seatbelt instance, so the daemon cannot tag its commands.
    /// The launcher is on the sealed system volume, out of every bot's reach.
    nonisolated let commands: LocalExecutionEnv
    private var client: EgressClient?
    private var opening: Task<EgressClient, any Error>?
    private var remote: RemoteExecutionEnv?
    private var connecting: Task<RemoteExecutionEnv, any Error>?
    private var daemons: [(transport: ProcessEnvTransport, tag: String)] = []
    private var closed = false
    /// Commands past their last `closed` check that have not returned, by token: each one's
    /// tag and the settlement its caller waits on.
    private var running: [Int: (tag: String, settlement: SandboxCommandSettlement)] = [:]
    private var nextCommand = 0

    /// How long close waits for running commands once it has ended their process groups. PiEnv
    /// returns a command only when its output pipes go idle, so a descendant that left the
    /// command's process group (`setsid`) and keeps writing holds it past every kill.
    static let commandCloseBound: Duration = .seconds(10)

    init(computer: RuntimeSandboxComputer, identity: EgressClientIdentity, host: RuntimeSandboxHost)
    {
      self.computer = computer
      self.identity = identity
      self.host = host
      commands = LocalExecutionEnv(cwd: computer.workingRoot ?? computer.home)
    }

    /// What one command needs: the profile, the confined environment and, with a call, its
    /// gateway attribution, which the caller ends when the command returns.
    struct CommandLaunch: Sendable {
      let profile: String
      let environment: [String: String]
      let client: EgressClient
      let attribution: EgressCallAttribution?
    }

    func commandLaunch(call: String?) async throws -> CommandLaunch {
      guard !closed else { throw RuntimeEnvironmentError.closed }
      let client = try await gatewayClient()
      guard let socketPath = client.socketPath else {
        throw RuntimeEnvironmentError.invalidComposition
      }
      return CommandLaunch(
        profile: profile(socketPath, client), environment: environment(client), client: client,
        attribution: call.map { client.beginCall($0) })
    }

    /// The connected environment, starting the first daemon on first use.
    func environment() async throws -> RemoteExecutionEnv {
      if let remote { return remote }
      if let connecting { return try await connecting.value }
      guard !closed else { throw RuntimeEnvironmentError.closed }
      let task = Task { try await self.connect() }
      connecting = task
      do {
        let value = try await task.value
        connecting = nil
        return value
      } catch {
        connecting = nil
        throw error
      }
    }

    /// The connected environment if a daemon was ever started, without starting one.
    var started: RemoteExecutionEnv? { remote }

    /// The last check before a command's spawn: refused once the session closed. Every
    /// admitted command is ended by `close`, even one that spawns after its first cleanup.
    func beginCommand(tag: String, settlement: SandboxCommandSettlement) throws -> Int {
      guard !closed else { throw RuntimeEnvironmentError.closed }
      nextCommand += 1
      running[nextCommand] = (tag, settlement)
      return nextCommand
    }

    /// Whether the command was still running here; false once close abandoned it.
    func endCommand(_ token: Int) -> Bool { running.removeValue(forKey: token) != nil }

    func close() async {
      closed = true
      await commands.cleanup(context: .background)
      // A command admitted just before `closed` may spawn after that cleanup: end it too.
      let deadline = ContinuousClock.now.advanced(by: Self.commandCloseBound)
      while !running.isEmpty, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(20))
        await commands.cleanup(context: .background)
      }
      // Its leader is gone with its process group; only a detached descendant still holds its
      // output. The command is recorded as returned and its caller is answered now.
      let abandoned = running.values
      running.removeAll()
      for command in abandoned {
        host.denials.returned(command.tag, exitCode: nil)
        command.settlement.settle(.failure(SandboxExecutionEnv.unavailable))
      }
      if let connecting { _ = await connecting.result }
      if let opening { _ = await opening.result }
      await remote?.close()
      remote = nil
      for (daemon, tag) in daemons {
        // A daemon that ignored EOF within the bound has its process group ended by close.
        _ = await Self.exits(daemon, within: .seconds(10))
        await daemon.close()
        host.denials.returned(tag, exitCode: nil)
      }
      daemons.removeAll()
      await client?.close()
      client = nil
    }

    private func connect() async throws -> RemoteExecutionEnv {
      _ = try await gatewayClient()
      let connected = try await RemoteExecutionEnv.connect(
        id: "memoshi-sandbox-" + computer.id, cwd: computer.workingRoot ?? computer.home,
        shellPath: "/bin/sh",
        connector: { [weak self] in
          guard let self else { throw RuntimeEnvironmentError.closed }
          return try await self.launch()
        })
      guard !closed else {
        await connected.close()
        throw RuntimeEnvironmentError.closed
      }
      remote = connected
      return connected
    }

    private func gatewayClient() async throws -> EgressClient {
      if let client { return client }
      if let opening { return try await opening.value }
      guard !closed else { throw RuntimeEnvironmentError.closed }
      let gateway = host.gateway
      let identity = identity
      let policy = computer.network
      let task = Task {
        try await gateway.openClient(identity, policy: policy, confinedSocket: true)
      }
      opening = task
      do {
        let opened = try await task.value
        opening = nil
        guard !closed else {
          await opened.close()
          throw RuntimeEnvironmentError.closed
        }
        client = opened
        return opened
      } catch {
        opening = nil
        throw error
      }
    }

    /// One daemon life: generated profile, launch under Seatbelt, a fresh token on stdin only,
    /// then the framed hello. Also the reconnect path after a daemon is lost.
    private func launch() async throws -> EnvConnection {
      guard !closed else { throw RuntimeEnvironmentError.closed }
      let client = try await gatewayClient()
      guard let socketPath = client.socketPath else {
        throw RuntimeEnvironmentError.invalidComposition
      }
      let tag = try await host.denials.register(
        .daemon, identity: identity, call: nil, command: host.daemonCommand)
      let transport: ProcessEnvTransport
      do {
        transport = try await ProcessEnvTransport.launch(
          argv: ["/usr/bin/sandbox-exec", "-D", "INV=" + tag, "-p", profile(socketPath, client)]
            + host.daemonCommand,
          cwd: computer.workingRoot ?? computer.home, environment: environment(client))
      } catch {
        host.denials.returned(tag, exitCode: nil)
        throw error
      }
      // close() may have finished while this daemon was starting: nothing else would end it.
      guard !closed else {
        await transport.close()
        host.denials.returned(tag, exitCode: nil)
        throw RuntimeEnvironmentError.closed
      }
      daemons.append((transport, tag))
      do {
        let token = SandboxToken.make()
        try await transport.write(Data((token + "\n").utf8))
        return try await EnvConnection.connect(
          transport: SandboxEOFTransport(transport), token: token)
      } catch {
        // A daemon that never completed its handshake is ended now, not when the session closes.
        daemons.removeAll { $0.transport === transport }
        await transport.close()
        host.denials.returned(tag, exitCode: nil)
        throw error
      }
    }

    private func profile(_ socketPath: String, _ client: EgressClient) -> String {
      SandboxProfile.make(
        executable: host.daemonCommand[0], home: computer.home, workingRoot: computer.workingRoot,
        gatewaySocket: socketPath, certificateBundle: client.certificateBundlePath,
        readOnlyToolchainRoots: host.readOnlyToolchainRoots)
    }

    /// The confined environment of daemons and commands alike.
    private func environment(_ client: EgressClient) -> [String: String] {
      Self.mergedLaunchEnvironment(
        base: Self.processBase, proxy: client.proxyEnvironment(),
        placeholders: client.placeholders, home: computer.home,
        workingRoot: computer.workingRoot, toolchainRoots: host.readOnlyToolchainRoots)
    }

    /// The process base of every confined launch. Each of its names, and every name
    /// ``daemonOwnedEnvironment(home:workingRoot:toolchainRoots:)`` sets, is one
    /// ``EgressSecretBinding/isReservedName(_:)`` refuses for a mask.
    static let processBase = [
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8",
      "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null",
    ]

    /// A launch environment: the egress placeholders, then every host-set value over them (the
    /// process base, the gateway proxy variables, then the identity and guard variables). A
    /// mask cannot be named like a host-owned variable (``EgressSecretBinding`` refuses it);
    /// a placeholder that is anyway is dropped, also where the host leaves that variable
    /// unset for this launch.
    static func mergedLaunchEnvironment(
      base: [String: String], proxy: [String: String], placeholders: [String: String],
      home: String, workingRoot: String?, toolchainRoots: [String]
    ) -> [String: String] {
      var environment = placeholders.filter { !EgressSecretBinding.isReservedName($0.key) }
      environment.merge(base) { _, new in new }
      environment.merge(proxy) { _, new in new }
      environment.merge(
        Self.daemonOwnedEnvironment(
          home: home, workingRoot: workingRoot, toolchainRoots: toolchainRoots)
      ) { _, new in new }
      return environment
    }

    /// What the host itself sets for one daemon life, unaffected by anything the gateway client
    /// supplies.
    static func daemonOwnedEnvironment(
      home: String, workingRoot: String?, toolchainRoots: [String]
    ) -> [String: String] {
      var variables = ["HOME": home, "TMPDIR": home + "/tmp"]
      variables.merge(
        SandboxGuardedFiles.rootVariables(workingRoot: workingRoot, toolchainRoots: toolchainRoots)
      ) { _, new in new }
      return variables
    }

    private static func exits(_ daemon: ProcessEnvTransport, within limit: Duration) async -> Bool {
      let exited = Mutex(false)
      let waiter = Task {
        _ = await daemon.wait()
        exited.withLock { $0 = true }
      }
      let deadline = ContinuousClock.now.advanced(by: limit)
      while ContinuousClock.now < deadline {
        if exited.withLock({ $0 }) { return true }
        try? await Task.sleep(for: .milliseconds(20))
      }
      _ = waiter
      return exited.withLock { $0 }
    }

    /// Where a command asked to start in `requested` starts: resolved lexically against the
    /// computer's working directory, with `~` as the bot's home. Nil when it leaves the home,
    /// the working copy and every toolchain root. Nothing is looked up.
    nonisolated func commandDirectory(_ requested: String) -> String? {
      let scalars = requested.unicodeScalars
      let expanded =
        scalars.elementsEqual("~".unicodeScalars) || scalars.starts(with: "~/".unicodeScalars)
        ? computer.home + String(Substring(scalars.dropFirst())) : requested
      let path = SandboxPaths.lexical(expanded, base: computer.workingRoot ?? computer.home)
      let roots =
        [computer.home] + [computer.workingRoot].compactMap { $0 } + host.readOnlyToolchainRoots
      return roots.contains { SandboxPaths.isWithin(path, root: $0) } ? path : nil
    }
  }

  /// Closing sends EOF on the daemon's stdin; the daemon then ends the commands it started and
  /// exits on its own.
  private final class SandboxEOFTransport: EnvTransport, Sendable {
    let process: ProcessEnvTransport
    init(_ process: ProcessEnvTransport) { self.process = process }
    func read() async throws -> Data? { try await process.read() }
    func write(_ data: Data) async throws { try await process.write(data) }
    func close() async { process.finishInput() }
  }

  /// The one outcome a command's caller waits for: the command's own result, or unavailable
  /// once its closed session stopped waiting for it.
  final class SandboxCommandSettlement: Sendable {
    private typealias Outcome = Result<ShellExecResult, ExecutionError>
    private let state = Mutex<(outcome: Outcome?, waiter: CheckedContinuation<Outcome, Never>?)>(
      (nil, nil))

    /// The first outcome wins; a later one is dropped.
    func settle(_ outcome: Result<ShellExecResult, ExecutionError>) {
      let waiter = state.withLock { value -> CheckedContinuation<Outcome, Never>? in
        guard value.outcome == nil else { return nil }
        value.outcome = outcome
        defer { value.waiter = nil }
        return value.waiter
      }
      waiter?.resume(returning: outcome)
    }

    var result: Result<ShellExecResult, ExecutionError> {
      get async {
        await withCheckedContinuation { continuation in
          let ready = state.withLock { value -> Outcome? in
            if let outcome = value.outcome { return outcome }
            value.waiter = continuation
            return nil
          }
          if let ready { continuation.resume(returning: ready) }
        }
      }
    }
  }

  enum SandboxToken {
    /// A fresh 256-bit session token in lowercase hex.
    static func make() -> String {
      var generator = SystemRandomNumberGenerator()
      return (0..<32).map { _ in
        String(format: "%02x", UInt8.random(in: 0...255, using: &generator))
      }
      .joined()
    }
  }

  enum SandboxPaths {
    static func isCanonical(_ path: String) -> Bool {
      guard path.hasPrefix("/"), let resolved = realpath(path, nil) else { return false }
      defer { free(resolved) }
      return String(cString: resolved) == path
    }

    /// Creates the directory with mode 0700 unless it already is a directory.
    static func ensurePrivateDirectory(_ path: String) throws {
      var info = stat()
      if lstat(path, &info) == 0 {
        guard info.st_mode & S_IFMT == S_IFDIR else {
          throw RuntimeEnvironmentError.invalidComposition
        }
        return
      }
      guard mkdir(path, 0o700) == 0 else { throw RuntimeEnvironmentError.invalidComposition }
    }

    /// `path` made absolute against `base`, with `.` and `..` resolved lexically on scalars.
    static func lexical(_ path: String, base: String) -> String {
      let joined = path.unicodeScalars.first == "/" ? path : base + "/" + path
      var names: [String] = []
      for part in joined.unicodeScalars.split(separator: "/") {
        let name = String(Substring(part))
        if name.unicodeScalars.elementsEqual(".".unicodeScalars) { continue }
        if name.unicodeScalars.elementsEqual("..".unicodeScalars) {
          _ = names.popLast()
          continue
        }
        names.append(name)
      }
      return "/" + names.joined(separator: "/")
    }

    /// Whether lexical `path` is `root` or below it, comparing scalars exactly.
    static func isWithin(_ path: String, root: String) -> Bool {
      path.unicodeScalars.elementsEqual(root.unicodeScalars)
        || path.unicodeScalars.starts(with: (root + "/").unicodeScalars)
    }
  }

  /// D96's deny-default private-copy candidate. The exact host-owned Unix socket is the only
  /// outbound exception. In particular no IP/localhost selector is emitted: Seatbelt's
  /// `localhost:port` also admits the Mac's LAN addresses at that port.
  enum SandboxProfile {
    /// Appended to every deny rule: the kernel's report of that denial then ends with the
    /// instance's `INV` parameter, its invocation tag (S4.7).
    static let tagMessage = #"(with message (param "INV"))"#

    /// The protected-secret predicate, generated from ``SourceSecretSpellings`` so the profile
    /// and host admission cannot drift. A secret-spelled component protects itself and every
    /// descendant; only an exact lowercase template leaf is exempt, never a template directory
    /// or a template below a secret directory. Matching is ASCII case-insensitive: Seatbelt
    /// cannot fold Unicode or drop default-ignorable scalars, which admission refuses instead
    /// and the daemon's guard adds (``SandboxGuardedFiles/protectsSecret(in:)``).
    static let protectedSecret: String = {
      let patterns = secretPatterns
      return "(require-any " + regex(patterns.directory) + " (require-all "
        + regex(patterns.leaf) + " (require-not " + regex(patterns.template) + ")))"
    }()

    /// The regular expressions of ``protectedSecret``: a secret-spelled directory, a
    /// secret-spelled leaf, and the exempt template leaves.
    fileprivate static let secretPatterns: (directory: String, leaf: String, template: String) = {
      typealias Spellings = SourceSecretSpellings
      let any = "[^/]*"
      var alternatives = Spellings.names.map { pattern($0) }
      alternatives.append(pattern(Spellings.templatedPrefix) + any)
      alternatives += Spellings.prefixes.map { pattern($0) + any }
      alternatives += Spellings.suffixes.map { any + pattern($0) }
      alternatives += Spellings.affixes.map { pattern($0.prefix) + any + pattern($0.suffix) }
      alternatives += Spellings.children.map { pattern($0.parent) + "/" + pattern($0.name) }
      alternatives += Spellings.childPrefixes.map {
        pattern($0.parent) + "/" + pattern($0.prefix) + any
      }
      let component = "(" + alternatives.joined(separator: "|") + ")"
      let templates =
        "("
        + Spellings.templates.map { pattern($0, caseInsensitive: false) }
        .joined(separator: "|") + ")"
      return ("/" + component + "/", "/" + component + "$", "/" + templates + "$")
    }()

    /// D103 `host_exec` write targets inside the roots: each of these directories and
    /// everything below it.
    static let hostExecDirectories = [".git/hooks", ".vscode", ".idea"]
    /// D103 `host_exec` write targets inside the roots: exactly these entries.
    static let hostExecLeaves = [".git/config", ".gitconfig", ".bashrc", ".zshrc", ".mcp.json"]

    /// Every protected host-exec entry as lowercase names, and whether it protects everything
    /// below it. `.git` itself stays writable so a bot can create and move repositories.
    // Open until a host git exists: a directory built elsewhere can be renamed onto `.git`.
    static let hostExecEntries: [(names: [String], below: Bool)] =
      hostExecLeaves.map { ($0.split(separator: "/").map(String.init), false) }
      + hostExecDirectories.map { ($0.split(separator: "/").map(String.init), true) }

    /// ``hostExecEntries`` as the profile's write exception, ASCII case-insensitive as the
    /// secret rules are.
    static let hostExecPath: String = {
      let alternatives = hostExecEntries.map { entry in
        entry.names.map { pattern($0) }.joined(separator: "/") + (entry.below ? "(/.*)?" : "")
      }
      return regex("/(" + alternatives.joined(separator: "|") + ")$")
    }()

    static func make(
      executable: String, home: String, workingRoot: String?, gatewaySocket: String? = nil,
      certificateBundle: String? = nil, readOnlyToolchainRoots: [String] = []
    ) -> String {
      let hostExec = Self.hostExecPath
      let protectedSecret = Self.protectedSecret
      var roots = [home]
      if let workingRoot { roots.append(workingRoot) }
      var rules = [
        "(version 1)",
        deny("default"),
        #"(allow process-exec (require-not (require-any (literal "/usr/bin/security") (literal "/usr/bin/osascript") (literal "/usr/bin/open") (literal "/usr/bin/pbcopy") (literal "/usr/bin/pbpaste") (literal "/usr/bin/sudo") (literal "/usr/bin/su"))))"#,
        "(allow process-fork)",
        "(allow signal (target same-sandbox))",
        "(allow process-info* (target same-sandbox))",
        "(allow sysctl-read)",
        #"(allow file-read* (require-any (subpath "/System/Library") (subpath "/System/Cryptexes/OS/usr/lib") (subpath "/usr/lib") (subpath "/usr/bin") (subpath "/usr/share") (subpath "/bin") (subpath "/sbin") (literal "/dev/null") (literal "/dev/random") (literal "/dev/urandom") (literal "#
          + quoted(executable) + ")))",
        #"(allow file-read* (literal "/private/var/select/sh"))"#,
        #"(allow file-read* (literal "/Library/Preferences/com.apple.dt.Xcode.plist"))"#,
        #"(allow file-read* (subpath "/private/etc/ssl"))"#,
        #"(allow file-write-data (literal "/dev/null"))"#,
        #"(allow file-read* (literal "/"))"#,
        "(allow file-read-metadata (vnode-type DIRECTORY))",
      ]
      for root in readOnlyToolchainRoots {
        rules.append(
          "(allow file-read* (require-all (subpath " + quoted(root) + ") (require-not "
            + protectedSecret + ")))")
      }
      for root in roots {
        rules.append(
          "(allow file-read* (require-all (subpath " + quoted(root) + ") (require-not "
            + protectedSecret + ")))")
        rules.append(
          "(allow file-write* (require-all (subpath " + quoted(root) + ") (require-not "
            + protectedSecret + ") (require-not " + hostExec + ")))")
      }
      for root in readOnlyToolchainRoots {
        rules.append(deny("file-write* (subpath " + quoted(root) + ")"))
        protectAncestors(of: root, rules: &rules)
      }
      rules.append(deny("file-write* (literal " + quoted(executable) + ")"))
      protectAncestors(of: executable, rules: &rules)
      if let gatewaySocket {
        rules.append("(allow network-outbound (literal " + quoted(gatewaySocket) + "))")
        rules.append("(allow file-read-metadata (literal " + quoted(gatewaySocket) + "))")
      }
      if let certificateBundle {
        rules.append("(allow file-read* (literal " + quoted(certificateBundle) + "))")
      }
      return rules.joined(separator: "\n")
    }

    // Path-based protection must also prevent moving the protected inode to a writable name.
    // Split scalars: a combining filename can make "/" part of a larger Character.
    private static func protectAncestors(of path: String, rules: inout [String]) {
      var ancestor = path.unicodeScalars[...]
      while let slash = ancestor.lastIndex(of: "/"), slash != ancestor.startIndex {
        ancestor = ancestor[..<slash]
        rules.append(deny("file-write-unlink (literal " + quoted(String(ancestor)) + ")"))
      }
    }

    private static func deny(_ rule: String) -> String { "(deny " + rule + " " + tagMessage + ")" }

    private static func quoted(_ text: String) -> String {
      "\""
        + text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// An ERE fragment matching `text` literally, ASCII letters case-insensitively by default.
    private static func pattern(_ text: String, caseInsensitive: Bool = true) -> String {
      text.unicodeScalars.map { scalar -> String in
        let character = String(scalar)
        switch scalar {
        case "a"..."z", "A"..."Z":
          return caseInsensitive
            ? "[" + character.lowercased() + character.uppercased() + "]" : character
        case "0"..."9", "_", "-":
          return character
        case "^", "]", "\\":
          return "\\" + character
        default:
          return scalar.isASCII ? "[" + character + "]" : character
        }
      }
      .joined()
    }

    private static func regex(_ pattern: String) -> String { "(regex #\"" + pattern + "\")" }
  }

  /// ``SandboxProfile/protectedSecret`` evaluated in process: its own expressions compiled once
  /// as POSIX extended expressions and matched against a path's bytes, so the daemon's guard
  /// refuses at least what the kernel denies. They use only syntax Seatbelt and POSIX read
  /// alike: bracket expressions, `[^/]*`, groups, alternation and a final `$`.
  final class SandboxSecretExpressions: Sendable {
    static let shared = SandboxSecretExpressions()
    private let directory: SandboxPathExpression
    private let leaf: SandboxPathExpression
    private let template: SandboxPathExpression

    private init() {
      let patterns = SandboxProfile.secretPatterns
      directory = SandboxPathExpression(patterns.directory)
      leaf = SandboxPathExpression(patterns.leaf)
      template = SandboxPathExpression(patterns.template)
    }

    /// Whether the profile protects the absolute `path` as a secret.
    func protects(_ path: String) -> Bool {
      directory.matches(path) || (leaf.matches(path) && !template.matches(path))
    }
  }

  /// One compiled POSIX extended expression, matched against a path's bytes. `regexec` only
  /// reads a compiled expression, so concurrent matches are safe.
  final class SandboxPathExpression: @unchecked Sendable {
    private let compiled = UnsafeMutablePointer<regex_t>.allocate(capacity: 1)

    init(_ pattern: String) {
      // The patterns are generated from constants: one that does not compile is a build defect.
      let status = regcomp(compiled, pattern, REG_EXTENDED | REG_NOSUB)
      precondition(status == 0, "a generated sandbox expression does not compile")
    }

    deinit {
      regfree(compiled)
      compiled.deallocate()
    }

    func matches(_ text: String) -> Bool { regexec(compiled, text, 0, nil, 0) == 0 }
  }

  /// The lazily connected environment Pi receives for a sandboxed conversation. Only `id` and
  /// `cwd` are answered without a daemon; every file or command operation starts it on first use.
  final class SandboxExecutionEnv: ExecutionEnv {
    let id: String
    let cwd: String
    private let daemons: SandboxDaemons

    init(id: String, cwd: String, daemons: SandboxDaemons) {
      self.id = id
      self.cwd = cwd
      self.daemons = daemons
    }

    /// Runs a command whose gateway requests and kernel denials are attributed to `call`.
    func exec(
      _ command: ShellCommand, options: ShellExecOptions?, call: String, context: Context
    ) async -> Result<ShellExecResult, ExecutionError> {
      await run(command, options: options, call: call, context: context)
    }

    /// Without a call, a command still reaches only the gateway, which challenges a request with
    /// no proxy credential (`407`) and refuses any other as unattributed. Its denials still
    /// carry its own invocation tag.
    func exec(_ command: ShellCommand, options: ShellExecOptions?, context: Context) async
      -> Result<
        ShellExecResult, ExecutionError
      >
    {
      await run(command, options: options, call: nil, context: context)
    }

    func cleanup(context: Context) async {
      await daemons.commands.cleanup(context: context)
      await daemons.started?.cleanup(context: context)
    }

    /// A command's refusal when its computer is closed or cannot record it.
    static let unavailable = ExecutionError(.spawnError, "This computer is unavailable.")
    /// A command's refusal when its working directory leaves the computer. It names no path
    /// and is the same whether that path exists or not.
    static let outsideComputer = ExecutionError(
      .spawnError, "That working directory is not in this computer.")
    /// Run by the confined shell when a command starts in another directory of the computer:
    /// the directory is looked up and entered inside the Seatbelt instance, never by the host.
    static let enterDirectory = #"cd -- "$1" || exit 1; shift; exec "$@""#

    /// One command in its own Seatbelt instance under the computer's profile, with a fresh tag
    /// registered before the exec. Environment, timeout, abort and output behave as in the
    /// daemon: the same PiEnv process runner, the confined environment, then `options`. A
    /// `cwd` is resolved lexically and entered by the confined command (``enterDirectory``).
    private func run(
      _ command: ShellCommand, options: ShellExecOptions?, call: String?, context: Context
    ) async -> Result<ShellExecResult, ExecutionError> {
      let argv: [String]
      switch command {
      case .shell(let text): argv = ["/bin/sh", "-c", text]
      case .argv(let given):
        guard !given.isEmpty else {
          return .failure(ExecutionError(.spawnError, "Empty argv: no program to run"))
        }
        argv = given
      }
      var confined = options ?? ShellExecOptions()
      // The unconfined host never looks a caller's directory up: PiEnv would `stat` it and
      // spawn into it before Seatbelt applies.
      var start: String?
      if let requested = confined.cwd {
        guard let directory = daemons.commandDirectory(requested) else {
          return .failure(Self.outsideComputer)
        }
        if directory != cwd { start = directory }
        confined.cwd = nil
      }
      let launch: SandboxDaemons.CommandLaunch
      do { launch = try await daemons.commandLaunch(call: call) } catch {
        return .failure(Self.unavailable)
      }
      defer { if let attribution = launch.attribution { launch.client.endCall(attribution) } }
      let denials = daemons.host.denials
      let tag: String
      do {
        tag = try await denials.register(
          .command, identity: daemons.identity, call: call, command: argv)
      } catch { return .failure(Self.unavailable) }
      await denials.awaitStartup(within: .seconds(10))
      var environment = confined.inheritEnv == false ? [:] : launch.environment
      environment.merge(confined.env ?? [:]) { _, new in new }
      if let attribution = launch.attribution {
        environment.merge(launch.client.proxyEnvironment(attribution)) { _, new in new }
      }
      confined.env = environment
      confined.inheritEnv = false
      let confinedArgv =
        ["/usr/bin/sandbox-exec", "-D", "INV=" + tag, "-p", launch.profile]
        + (start.map { ["/bin/sh", "-c", Self.enterDirectory, "sh", $0] } ?? []) + argv
      // The session may have closed during registration or the reader's start.
      let settlement = SandboxCommandSettlement()
      let token: Int
      do { token = try await daemons.beginCommand(tag: tag, settlement: settlement) } catch {
        denials.returned(tag, exitCode: nil)
        return .failure(Self.unavailable)
      }
      let owner = daemons
      let prepared = confined
      let execution = Task {
        let result = await owner.commands.exec(
          .argv(confinedArgv), options: prepared, context: context)
        // A command its closed session abandoned was already recorded as returned.
        if await owner.endCommand(token) {
          denials.returned(tag, exitCode: try? result.get().exitCode)
        }
        settlement.settle(result)
      }
      return await withTaskCancellationHandler {
        await settlement.result
      } onCancel: {
        execution.cancel()
      }
    }

    private func file<T>(_ body: (RemoteExecutionEnv) async -> Result<T, FileError>) async
      -> Result<
        T, FileError
      >
    {
      do { return await body(try await daemons.environment()) } catch {
        return .failure(FileError(.unknown, "This computer is unavailable."))
      }
    }

    func absolutePath(_ path: String, context: Context) async -> Result<String, FileError> {
      await file { await $0.absolutePath(path, context: context) }
    }
    func joinPath(_ parts: [String], context: Context) async -> Result<String, FileError> {
      await file { await $0.joinPath(parts, context: context) }
    }
    func readTextFile(_ path: String, context: Context) async -> Result<String, FileError> {
      await file { await $0.readTextFile(path, context: context) }
    }
    func openTextLineReader(_ path: String, context: Context) async -> Result<
      any TextLineReader, FileError
    > {
      await file { await $0.openTextLineReader(path, context: context) }
    }
    func readTextLines(_ path: String, options: ReadTextLinesOptions?, context: Context) async
      -> Result<[String], FileError>
    {
      await file { await $0.readTextLines(path, options: options, context: context) }
    }
    func readBinaryFile(_ path: String, context: Context) async -> Result<Data, FileError> {
      await file { await $0.readBinaryFile(path, context: context) }
    }
    func openBinaryReader(_ path: String, options: BinaryReaderOptions?, context: Context) async
      -> Result<any BinaryReader, FileError>
    {
      await file { await $0.openBinaryReader(path, options: options, context: context) }
    }
    func writeFile(_ path: String, _ content: FileContent, context: Context) async -> Result<
      Void, FileError
    > {
      await file { await $0.writeFile(path, content, context: context) }
    }
    func appendFile(_ path: String, _ content: FileContent, context: Context) async -> Result<
      Void, FileError
    > {
      await file { await $0.appendFile(path, content, context: context) }
    }
    func truncateFile(_ path: String, size: Int, context: Context) async -> Result<Void, FileError>
    {
      await file { await $0.truncateFile(path, size: size, context: context) }
    }
    func flushFile(_ path: String, context: Context) async -> Result<Void, FileError> {
      await file { await $0.flushFile(path, context: context) }
    }
    func renameFile(_ sourcePath: String, _ destinationPath: String, context: Context) async
      -> Result<Void, FileError>
    {
      await file { await $0.renameFile(sourcePath, destinationPath, context: context) }
    }
    func fileInfo(_ path: String, context: Context) async -> Result<FileInfo, FileError> {
      await file { await $0.fileInfo(path, context: context) }
    }
    func listDir(_ path: String, context: Context) async -> Result<[FileInfo], FileError> {
      await file { await $0.listDir(path, context: context) }
    }
    func listFiles(_ path: String, options: ListFilesOptions?, context: Context) async -> Result<
      FileListing, FileError
    > {
      await file { await $0.listFiles(path, options: options, context: context) }
    }
    func openDirReader(_ path: String, context: Context) async -> Result<any DirReader, FileError> {
      await file { await $0.openDirReader(path, context: context) }
    }
    func watch(
      _ targets: [WatchTarget], onChange: @escaping @Sendable (WatchChange) -> Void,
      context: Context
    ) async -> Result<any FileWatcher, FileError> {
      await file { await $0.watch(targets, onChange: onChange, context: context) }
    }
    func canonicalPath(_ path: String, context: Context) async -> Result<String, FileError> {
      await file { await $0.canonicalPath(path, context: context) }
    }
    func exists(_ path: String, context: Context) async -> Result<Bool, FileError> {
      await file { await $0.exists(path, context: context) }
    }
    func createDir(_ path: String, options: CreateDirOptions?, context: Context) async -> Result<
      Void, FileError
    > {
      await file { await $0.createDir(path, options: options, context: context) }
    }
    func remove(_ path: String, options: RemoveOptions?, context: Context) async -> Result<
      Void, FileError
    > {
      await file { await $0.remove(path, options: options, context: context) }
    }
    func createTempDir(prefix: String?, context: Context) async -> Result<String, FileError> {
      await file { await $0.createTempDir(prefix: prefix, context: context) }
    }
    func createTempFile(options: TempFileOptions?, context: Context) async -> Result<
      String, FileError
    > {
      await file { await $0.createTempFile(options: options, context: context) }
    }
  }

  /// A Pi-type-free view of one sandboxed command started in the directory a caller such as
  /// Pi's tools passes as `cwd`, for the runtime tests: the same `exec` those callers reach.
  struct SandboxCommandProbe: Sendable {
    enum Outcome: Equatable, Sendable {
      /// The command ran: its exit status and combined output.
      case exited(Int, output: String)
      /// It was refused before it ran.
      case refused(String)
    }

    private let environment: SandboxExecutionEnv

    /// Nil unless `environment` is a sandboxed computer's.
    init?(_ environment: any ExecutionEnv) {
      guard let sandboxed = environment as? SandboxExecutionEnv else { return nil }
      self.environment = sandboxed
    }

    func run(_ argv: [String], cwd: String?, call: String) async -> Outcome {
      let output = Mutex("")
      let result = await environment.exec(
        .argv(argv),
        options: ShellExecOptions(
          cwd: cwd, onOutput: { text, _, _ in output.withLock { $0 += text } }),
        call: call, context: .background)
      switch result {
      case .success(let completed):
        return .exited(completed.exitCode, output: output.withLock { $0 })
      case .failure(let error): return .refused(error.message)
      }
    }
  }

  extension RuntimeComputerHandle {
    /// S4-T7's exec baseline (S4 row 6's "unsandboxed"): the PiEnv `LocalExecutionEnv` path a
    /// sandboxed computer starts each command through, without `sandbox-exec`, its profile, a
    /// gateway client or a denial tag. For the runtime tests; no composition returns it.
    static func unsandboxedBaseline(cwd: String) -> RuntimeComputerHandle {
      RuntimeComputerHandle(
        environment: LocalExecutionEnv(cwd: cwd), call: "call-baseline", signal: .any([]))
    }
  }

  /// The confined daemon's own entrypoint, for a trusted host executable such as the test
  /// fixture. Its session token arrives as the first line on standard input, never in argv,
  /// the environment or a file.
  public enum RuntimeSandboxDaemon {
    /// Serves one PiEnv session on standard input and output; returns the exit status.
    public static func serve() async -> Int32 {
      _ = signal(SIGPIPE, SIG_IGN)
      do {
        let token = try readToken()
        let transport = try DescriptorEnvTransport(input: STDIN_FILENO, output: STDOUT_FILENO)
        // S4-T3: every file request resolves through the descriptor guard (H3), never the
        // unguarded default. The roots come from the environment the host set at launch.
        let files = try SandboxGuardedFiles.service(
          environment: ProcessInfo.processInfo.environment)
        try await EnvDaemonSession(transport: transport, files: files).serve(token: token)
        return 0
      } catch {
        FileHandle.standardError.write(Data("memoshi sandbox daemon: session failed\n".utf8))
        return 2
      }
    }

    /// Reads exactly the token line byte by byte, so no protocol byte is consumed.
    private static func readToken() throws -> String {
      var token: [UInt8] = []
      while true {
        var byte: UInt8 = 0
        let count = Darwin.read(STDIN_FILENO, &byte, 1)
        if count < 0 && errno == EINTR { continue }
        guard count == 1 else { throw RuntimeEnvironmentError.unavailable }
        if byte == 10 { break }
        guard token.count < 64, (48...57).contains(byte) || (97...102).contains(byte) else {
          throw RuntimeEnvironmentError.unavailable
        }
        token.append(byte)
      }
      guard token.count == 64 else { throw RuntimeEnvironmentError.unavailable }
      return String(decoding: token, as: UTF8.self)
    }
  }
#endif
