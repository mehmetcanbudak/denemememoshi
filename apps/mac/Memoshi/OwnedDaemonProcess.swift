import Darwin
import Foundation
import MemoshiProtocol
import MemoshiRuntime

/// This owner never signals a discovered PID or a launchd job. Its pipe ties foreground
/// lifetime to this app even after unexpected app exit; memoshid watches stdin EOF. Quit and
/// stop are graceful; only the explicit development kill below ever sends SIGKILL.
@MainActor
final class OwnedDaemonProcess {
  /// How the child ended, and whether this app had asked it to stop first.
  struct Exit: Equatable, Sendable {
    /// The exit status, or the signal number when `signaled`.
    let status: Int32
    /// True when an uncaught signal ended the process.
    let signaled: Bool
    /// True when `stop()` was requested before the exit.
    let requested: Bool
  }

  private let process: Process
  private let lifetimeWriter: FileHandle
  private(set) var stopRequested = false

  var isRunning: Bool { process.isRunning }
  var pid: Int { Int(process.processIdentifier) }
  var exitStatus: Int32? { process.isRunning ? nil : process.terminationStatus }

  init(
    executable: URL, dataDirectory: URL, developmentChat: Bool = false,
    onExit: @escaping @MainActor @Sendable (OwnedDaemonProcess, Exit) -> Void
  ) throws {
    let process = Process()
    let lifetime = Pipe()
    lifetimeWriter = lifetime.fileHandleForWriting
    self.process = process
    guard fcntl(lifetimeWriter.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    process.executableURL = executable
    process.arguments = ["--foreground", "--data-directory", dataDirectory.path]
    if developmentChat {
      process.arguments?.append("--development-chat")
    }
    process.arguments?.append(contentsOf: Self.developmentToolArguments)
    process.environment = Self.sanitizedEnvironment
    process.currentDirectoryURL = executable.deletingLastPathComponent()
    process.standardInput = lifetime
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    // Foundation reports the exit on its own thread; ownership decisions stay on the main actor.
    process.terminationHandler = { [weak self] ended in
      let status = ended.terminationStatus
      let signaled = ended.terminationReason == .uncaughtSignal
      Task { @MainActor in
        guard let self else { return }
        onExit(self, Exit(status: status, signaled: signaled, requested: self.stopRequested))
      }
    }
    try process.run()
  }

  deinit {
    try? lifetimeWriter.close()
    if process.isRunning { process.terminate() }
  }

  /// Only known process handles are stopped. A failed grace deadline blocks app quit instead
  /// of leaving a child behind or escalating to a deliberate SIGKILL.
  func stop() async -> Bool {
    stopRequested = true
    try? lifetimeWriter.close()
    if process.isRunning { process.terminate() }
    let process = process
    return await Task { @MainActor in
      let began = ContinuousClock.now
      while process.isRunning {
        if began.duration(to: .now) >= .seconds(30) { return false }
        try? await Task.sleep(for: .milliseconds(50))
      }
      return true
    }.value
  }

  /// Development fault injection only: SIGKILL to this app's own running child, through the
  /// handle that started it. Quit, stop and service handoff never call this.
  func killForDevelopment() -> Bool {
    guard process.isRunning else { return false }
    return Darwin.kill(process.processIdentifier, SIGKILL) == 0
  }

  /// The development helper's tool flags, passed as explicit arguments rather than through the
  /// sanitized environment: `DevelopmentApprovalProbe` only when this Debug app itself was
  /// launched with `-MemoshiDevelopmentApprovalTool YES` (argument domain only). Release builds
  /// compile none, and the LaunchAgent's fixed arguments never carry one.
  static var developmentToolArguments: [String] {
    #if DEBUG
      DevelopmentLaunchArgument.isSet(DevelopmentApprovalProbe.launchArgument)
        ? [DevelopmentApprovalProbe.helperFlag] : []
    #else
      []
    #endif
  }

  /// An allowlist constructed from system values, not a filtered copy of the app environment.
  static var sanitizedEnvironment: [String: String] {
    [
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      "HOME": NSHomeDirectory(),
      "USER": NSUserName(),
      "LOGNAME": NSUserName(),
      "TMPDIR": FileManager.default.temporaryDirectory.path,
      "LANG": "en_US.UTF-8",
    ]
  }
}

/// The daemon that answered a hello, followed until it exits. Reads process information only:
/// it never signals that process.
enum DaemonProcessExit {
  /// Whether the daemon still runs: its PID names a live process of this user that started no
  /// later than the daemon said it did, so a PID reused by a newer process does not count.
  static func isRunning(_ daemon: DaemonInfo) -> Bool {
    guard let pid = Int32(exactly: daemon.pid), pid > 0 else { return false }
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
    guard info.pbi_uid == getuid(), info.pbi_status != UInt32(SZOMB) else { return false }
    let started = Int64(info.pbi_start_tvsec) * 1_000 + Int64(info.pbi_start_tvusec) / 1_000
    return started <= daemon.startedAt
  }

  /// Checks every `interval` until `isRunning` reports an exit, for at most `bound` of waiting.
  /// Returns whether the process exited.
  @MainActor
  static func wait(
    within bound: Duration, checkingEvery interval: Duration = .milliseconds(100),
    isRunning: () -> Bool,
    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) async throws -> Bool {
    var waited = Duration.zero
    while isRunning() {
      guard waited < bound else { return false }
      try await sleep(interval)
      waited += interval
    }
    return true
  }
}

/// Starts an eligible launchd job only if absent. No `-k`, PID lookup, shell or provider secrets.
@MainActor
func kickstartRegisteredDaemon(label: String) async throws {
  let process = Process()
  let (exits, continuation) = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
  process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
  process.arguments = ["kickstart", "gui/\(geteuid())/\(label)"]
  process.environment = OwnedDaemonProcess.sanitizedEnvironment
  process.standardInput = FileHandle.nullDevice
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice
  process.terminationHandler = { process in
    continuation.yield(process.terminationStatus)
    continuation.finish()
  }
  try process.run()
  let deadline = Task { @MainActor in
    do {
      try await Task.sleep(for: .seconds(5))
      if process.isRunning { process.terminate() }
    } catch {}
  }
  defer { deadline.cancel() }
  let status: Int32? = await withTaskCancellationHandler {
    for await status in exits { return status }
    return nil
  } onCancel: {
    if process.isRunning { process.terminate() }
  }
  if process.isRunning {
    process.terminate()
    await Task.detached { process.waitUntilExit() }.value
  }
  try Task.checkCancellation()
  guard status == 0 else { throw DaemonSupervisionError.startServiceFailed }
}
