import Darwin
import Foundation
import Synchronization

/// How an owned child ended.
package enum ChildExit: Equatable, Sendable, CustomStringConvertible {
  /// Normal exit with a status code.
  case exited(Int32)
  /// Terminated by a signal, such as 9 for SIGKILL.
  case signaled(Int32)
  /// The operating system could not report or reap this child.
  case waitFailed(Int32)

  package var description: String {
    switch self {
    case .exited(let code): "exit \(code)"
    case .signaled(let signal): "signal \(signal)"
    case .waitFailed(let code): "wait failed (\(code))"
    }
  }
}

/// Driver failures.
package enum DriverError: Error, Equatable, CustomStringConvertible {
  /// A bounded wait expired.
  case timeout(String)
  /// The child's stdout closed before the awaited line arrived.
  case childEnded(String)
  /// The child could not be started.
  case spawnFailed(Int32)
  /// A precondition on paths or options failed.
  case invalid(String)

  package var description: String {
    switch self {
    case .timeout(let what): "timeout waiting for \(what)"
    case .childEnded(let what): "child ended before \(what)"
    case .spawnFailed(let code): "spawn failed (\(code))"
    case .invalid(let what): "invalid: \(what)"
    }
  }
}

/// Runs `operation` with a deadline; the losing side is cancelled.
package func withDeadline<T: Sendable>(
  _ duration: Duration, _ what: String, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await operation() }
    group.addTask {
      try await Task.sleep(for: duration)
      throw DriverError.timeout(what)
    }
    defer { group.cancelAll() }
    guard let value = try await group.next() else { throw DriverError.timeout(what) }
    return value
  }
}

/// Every decoded stdout line of one child, in order. Waits are cancellation-aware.
package actor Inbox<Element: Sendable> {
  private var items: [Element] = []
  private var finished = false
  private var waiters:
    [UUID: (
      from: Int, match: @Sendable (Element) -> Bool, continuation: CheckedContinuation<Int?, Never>
    )] = [:]

  package init() {}

  /// Appends one item and wakes waiters it satisfies.
  package func put(_ item: Element) {
    items.append(item)
    let index = items.count - 1
    for (id, waiter) in waiters where index >= waiter.from && waiter.match(item) {
      waiters.removeValue(forKey: id)
      waiter.continuation.resume(returning: index)
    }
  }

  /// Marks the stream ended; pending waits return nil.
  package func finish() {
    finished = true
    for waiter in waiters.values { waiter.continuation.resume(returning: nil) }
    waiters.removeAll()
  }

  /// The number of items received so far, usable as a later `from` cursor.
  package var count: Int { items.count }

  /// Every item received so far.
  package var all: [Element] { items }

  /// The first item at or after `from` that matches, waiting for it if needed; nil if the
  /// stream ended first or the caller was cancelled.
  package func first(from: Int = 0, where match: @escaping @Sendable (Element) -> Bool) async
    -> (index: Int, item: Element)?
  {
    if let index = items.indices.first(where: { $0 >= from && match(items[$0]) }) {
      return (index, items[index])
    }
    guard !finished else { return nil }
    let id = UUID()
    let index: Int? = await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
        if Task.isCancelled {
          continuation.resume(returning: nil)
        } else {
          waiters[id] = (from, match, continuation)
        }
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
    guard let index else { return nil }
    return (index, items[index])
  }

  private func cancel(_ id: UUID) {
    waiters.removeValue(forKey: id)?.continuation.resume(returning: nil)
  }
}

package enum ChildCaptureError: Error, Equatable, Sendable {
  case writeFailed
  case closeFailed
}

/// A child process the driver started and owns, spawned with `posix_spawn` so every descriptor
/// is explicit: a stdin pipe, a stdout pipe read as lines (and copied to a log file) and stderr
/// appended to a log file. No other descriptor is inherited.
package final class ChildProcess: Sendable {
  /// The child's process ID.
  package let pid: pid_t
  /// When `posix_spawn` returned.
  package let spawnedAt: ContinuousClock.Instant
  private let stdin: Mutex<FileHandle?>
  private let exitStatus = Mutex<ChildExit?>(nil)
  private let reader: Task<Void, any Error>

  private init(
    pid: pid_t, spawnedAt: ContinuousClock.Instant, stdin: FileHandle, reader: Task<Void, any Error>
  ) {
    self.pid = pid
    self.spawnedAt = spawnedAt
    self.stdin = Mutex(stdin)
    self.reader = reader
  }

  /// Spawns `executable arguments…` with exactly `environment`. Each stdout line is appended to
  /// `stdoutLog` and handed to `onLine`; `onEnd` runs once stdout closes.
  package static func spawn(
    executable: URL, arguments: [String], environment: [String: String], stdoutLog: URL,
    stderrLog: URL, owningStdout: FileHandle? = nil,
    closeStdout: @escaping @Sendable (FileHandle) throws -> Void = { try $0.close() },
    onLine: @escaping @Sendable (String) async -> Void,
    onEnd: @escaping @Sendable () async -> Void
  ) throws -> ChildProcess {
    var input: [Int32] = [-1, -1]
    var output: [Int32] = [-1, -1]
    guard pipe(&input) == 0 else { throw DriverError.spawnFailed(errno) }
    guard pipe(&output) == 0 else {
      close(input[0])
      close(input[1])
      throw DriverError.spawnFailed(errno)
    }
    for descriptor in input + output { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }
    // A write to a child that already ended must fail with EPIPE in `send`, never end the
    // owning driver with SIGPIPE before it reaps, cleans up and reports.
    guard fcntl(input[1], F_SETNOSIGPIPE, 1) == 0 else {
      let code = errno
      for descriptor in input + output { close(descriptor) }
      throw DriverError.spawnFailed(code)
    }
    let errorDescriptor = open(stderrLog.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o600)
    guard errorDescriptor >= 0 else {
      for descriptor in input + output { close(descriptor) }
      throw DriverError.spawnFailed(errno)
    }
    defer { close(errorDescriptor) }
    let log: FileHandle
    if let owningStdout {
      log = owningStdout
    } else {
      guard
        FileManager.default.createFile(
          atPath: stdoutLog.path, contents: nil, attributes: [.posixPermissions: 0o600]),
        let handle = try? FileHandle(forWritingTo: stdoutLog)
      else {
        for descriptor in input + output { close(descriptor) }
        throw DriverError.invalid("stdout log \(stdoutLog.lastPathComponent)")
      }
      log = handle
    }

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO)
    posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&actions, errorDescriptor, STDERR_FILENO)
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    // Close every descriptor not named above in the child.
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

    let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
    let envp =
      environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
      for pointer in argv { free(pointer) }
      for pointer in envp { free(pointer) }
    }
    var pid: pid_t = 0
    let status = posix_spawn(&pid, executable.path, &actions, &attributes, argv, envp)
    close(input[0])
    close(output[1])
    guard status == 0 else {
      close(input[1])
      close(output[0])
      try? closeStdout(log)
      throw DriverError.spawnFailed(status)
    }
    let spawnedAt = ContinuousClock.now
    let lines = LineStream.lines(from: output[0], closeAtEnd: true)
    let reader = Task<Void, any Error> {
      var failure: ChildCaptureError?
      for await line in lines {
        if failure == nil {
          do { try log.write(contentsOf: Data((line + "\n").utf8)) } catch {
            failure = .writeFailed
          }
        }
        await onLine(line)
      }
      do { try closeStdout(log) } catch {
        if failure == nil { failure = .closeFailed }
      }
      await onEnd()
      if let failure { throw failure }
    }
    let child = ChildProcess(
      pid: pid, spawnedAt: spawnedAt,
      stdin: FileHandle(fileDescriptor: input[1], closeOnDealloc: true), reader: reader)
    child.monitorExit()
    return child
  }

  /// Writes one line to the child's stdin; throws when the child no longer reads it.
  package func send(_ line: Data) throws {
    var bytes = line
    bytes.append(UInt8(ascii: "\n"))
    try stdin.withLock { handle in
      guard let handle else { throw DriverError.childEnded("stdin write") }
      try handle.write(contentsOf: bytes)
    }
  }

  /// Closes stdin: the child's normal-stop signal.
  package func closeStdin() {
    stdin.withLock { handle in
      try? handle?.close()
      handle = nil
    }
  }

  /// Sends a signal to this child only, and only while it is unreaped. The exit is recorded and
  /// the zombie reaped under the same lock, so this can never reach a reused process ID.
  package func signal(_ number: Int32) {
    exitStatus.withLock { exit in
      guard exit == nil else { return }
      _ = Darwin.kill(pid, number)
    }
  }

  /// The reaped exit status, once the child has ended.
  package var exit: ChildExit? { exitStatus.withLock { $0 } }

  /// Polls for the reaped exit status; nil when `timeout` passes first.
  package func waitForExit(timeout: Duration) async -> ChildExit? {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if let exit { return exit }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return exit
  }

  /// Waits for the terminal stdout capture outcome after all lines and `onEnd`.
  package func drainOutput() async throws { try await reader.value }

  /// Watches on a dedicated thread. Darwin may return a stop notification even for
  /// `WEXITED`; consume nonterminal statuses without holding the signal lock in a blocking wait.
  /// A terminal status is reaped under that lock, preventing signals to a reused process ID.
  private func monitorExit() {
    let pid = pid
    let thread = Thread { [self] in
      while true {
        var info = siginfo_t()
        var observed: Int32
        repeat {
          observed = waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT)
        } while observed == -1 && errno == EINTR
        let waitError = errno
        let ended = exitStatus.withLock { exit -> Bool in
          guard observed == 0 else {
            exit = .waitFailed(waitError)
            return true
          }
          let terminal =
            info.si_code == CLD_EXITED || info.si_code == CLD_KILLED
            || info.si_code == CLD_DUMPED
          let options = terminal ? 0 : WNOHANG | WUNTRACED | WCONTINUED
          var status: Int32 = 0
          var reaped: pid_t
          repeat { reaped = waitpid(pid, &status, options) } while reaped == -1 && errno == EINTR
          guard reaped != -1 else {
            exit = .waitFailed(errno)
            return true
          }
          guard reaped == pid, status & 0x7f != 0x7f else { return false }
          let signal = status & 0x7f
          exit = signal == 0 ? .exited((status >> 8) & 0xff) : .signaled(signal)
          return true
        }
        if ended { return }
      }
    }
    thread.start()
  }
}
