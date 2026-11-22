import Chord
import Foundation
import MemoshiProtocol
import PiAI
import PiCore
import PiDurable
import PiEnv
import Synchronization

/// One conversation's resolved computer while the directory keeps returning it.
protocol RuntimeEnvironmentSession: Sendable {
  var computer: RuntimeSandboxComputer { get }
  var environment: any ExecutionEnv { get }
  func close() async
}

/// The Harness `env` hook behind ``RuntimeEnvironmentComposition``. Pi calls it for every tool
/// call and generation of a conversation; each call asks the directory for the bot's Computer
/// now. A conversation keeps one sandboxed daemon while its Computer is unchanged; a changed or
/// removed Computer closes the old daemon before the next call uses the new one.
actor RuntimeEnvironments {
  private let directory: any RuntimeComputerDirectory
  private let host: RuntimeSandboxHost?
  private var sessions: [ConversationID: any RuntimeEnvironmentSession] = [:]
  private var closed = false

  /// Nil for a composition without a directory, so no hook is installed at all.
  init?(_ composition: RuntimeEnvironmentComposition) {
    guard let directory = composition.directory else { return nil }
    self.directory = directory
    host = composition.sandbox
  }

  /// This call's environment, or nil when the bot has no computer here. A failure fails the
  /// call that needed it rather than letting it run anywhere else.
  func environment(conversation: ConversationID, bot: BotID) async throws -> (any ExecutionEnv)? {
    guard !closed else { throw RuntimeEnvironmentError.closed }
    let computer = try await directory.computer(conversation: conversation, bot: bot)
    guard !closed else { throw RuntimeEnvironmentError.closed }
    switch computer {
    case .none:
      await sessions.removeValue(forKey: conversation)?.close()
      return nil
    case .thisMacSandbox(let sandbox):
      if let current = sessions[conversation], current.computer === sandbox {
        return current.environment
      }
      #if os(macOS)
        guard let host else { throw RuntimeEnvironmentError.unavailable }
        let session = try SandboxComputerSession(
          computer: sandbox, conversation: conversation, bot: bot, host: host)
        let previous = sessions.updateValue(session, forKey: conversation)
        await previous?.close()
        return session.environment
      #else
        throw RuntimeEnvironmentError.unavailable
      #endif
    }
  }

  /// Ends one conversation's daemon and gateway client, for example when its thread closes.
  func close(conversation: ConversationID) async {
    await sessions.removeValue(forKey: conversation)?.close()
  }

  /// Ends every daemon and gateway client; later calls fail as closed.
  func closeAll() async {
    closed = true
    let open = Array(sessions.values)
    sessions.removeAll()
    for session in open { await session.close() }
  }
}

extension RuntimeAdapter {
  /// The Harness `env` hook for one conversation, or nil when no directory is composed.
  func environmentHook(conversation: ConversationID, bot: BotID)
    -> (@Sendable (PiDurable.EnvTarget, Chord.Context) async throws -> (any ExecutionEnv)?)?
  {
    guard let environments else { return nil }
    return { _, _ in try await environments.environment(conversation: conversation, bot: bot) }
  }
}

/// Command output a host tool may return to the model, bounded to its tail.
public struct RuntimeCommandResult: Sendable, Equatable {
  /// The command's exit status.
  public let exitCode: Int
  /// Combined standard output and error, in arrival order.
  public let output: String
  /// Whether earlier output was dropped to keep the bound.
  public let truncated: Bool
}

/// The computer one tool call's conversation resolved through the `env` hook, without Pi types.
/// On This Mac (sandboxed) file operations run inside the confined daemon and each command in
/// its own Seatbelt instance; a command's network requests and kernel denials carry this call.
public struct RuntimeComputerHandle: Sendable {
  private let environment: any ExecutionEnv
  private let call: String
  private let signal: PiCore.AbortSignal

  init(environment: any ExecutionEnv, call: String, signal: PiCore.AbortSignal) {
    self.environment = environment
    self.call = call
    self.signal = signal
  }

  /// Where commands start and relative paths resolve.
  public var workingDirectory: String { environment.cwd }

  /// Runs a program directly, without a shell. Output beyond `maximumOutputBytes` keeps its tail.
  public func run(
    _ argv: [String], timeoutSeconds: Double = 60, maximumOutputBytes: Int = 65_536
  ) async throws -> RuntimeCommandResult {
    guard !argv.isEmpty else { throw RuntimeEnvironmentError.commandFailed }
    return try await perform { context in
      let output = CommandOutput(limit: maximumOutputBytes)
      let options = ShellExecOptions(
        timeout: timeoutSeconds, onOutput: { text, _, _ in output.append(text) })
      let result: Result<ShellExecResult, ExecutionError>
      #if os(macOS)
        if let sandboxed = environment as? SandboxExecutionEnv {
          result = await sandboxed.exec(
            .argv(argv), options: options, call: call, context: context)
        } else {
          result = await environment.exec(.argv(argv), options: options, context: context)
        }
      #else
        result = await environment.exec(.argv(argv), options: options, context: context)
      #endif
      guard case .success(let completed) = result else {
        throw RuntimeEnvironmentError.commandFailed
      }
      let (text, truncated) = output.value
      return RuntimeCommandResult(exitCode: completed.exitCode, output: text, truncated: truncated)
    }
  }

  /// Reads a UTF-8 text file inside the computer.
  public func readTextFile(_ path: String) async throws -> String {
    try await perform { context in
      guard case .success(let text) = await environment.readTextFile(path, context: context)
      else { throw RuntimeEnvironmentError.commandFailed }
      return text
    }
  }

  /// Replaces a file's content inside the computer.
  public func writeTextFile(_ path: String, _ text: String) async throws {
    try await perform { context in
      guard
        case .success = await environment.writeFile(
          path, .bytes(Data(text.utf8)), context: context)
      else { throw RuntimeEnvironmentError.commandFailed }
    }
  }

  private func perform<Value: Sendable>(
    _ operation: @escaping @Sendable (Chord.Context) async throws -> Value
  ) async throws -> Value {
    try Task.checkCancellation()
    return try await PiAI.withAbortSignal(signal) {
      try Task.checkCancellation()
      let value = try await operation(Chord.Context.background.withAbortSignal(signal))
      try signal.throwIfAborted()
      try Task.checkCancellation()
      return value
    }
  }
}

/// The tail of a command's output; a character cut at the start decodes as U+FFFD.
private final class CommandOutput: Sendable {
  private let limit: Int
  private let state = Mutex<(bytes: [UInt8], truncated: Bool)>(([], false))

  init(limit: Int) { self.limit = max(0, limit) }

  func append(_ text: String) {
    state.withLock { value in
      value.bytes.append(contentsOf: text.utf8)
      let excess = value.bytes.count - limit
      guard excess > 0 else { return }
      value.bytes.removeFirst(excess)
      value.truncated = true
    }
  }

  var value: (String, Bool) {
    state.withLock { (String(decoding: $0.bytes, as: UTF8.self), $0.truncated) }
  }
}
