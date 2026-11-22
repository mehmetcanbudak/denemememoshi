import Darwin
import Foundation
import MemoshiDevice
import MemoshiProtocol
import Synchronization

/// One process of the S2 harness the driver owns: every stdout line is kept in order, and
/// commands are answered by `id`.
package final class S2Child: Sendable {
  /// A short name for logs, such as `mac`.
  package let name: String
  /// The owned process.
  package let process: ChildProcess
  private let lines: Inbox<String>
  private let nextID = Mutex(0)

  private init(name: String, process: ChildProcess, lines: Inbox<String>) {
    self.name = name
    self.process = process
    self.lines = lines
  }

  /// Spawns `executable arguments…` with logs under `logs`.
  package static func spawn(
    name: String, executable: URL, arguments: [String], environment: [String: String], logs: URL
  ) throws -> S2Child {
    let inbox = Inbox<String>()
    let process = try ChildProcess.spawn(
      executable: executable, arguments: arguments, environment: environment,
      stdoutLog: logs.appendingPathComponent("\(name).stdout.jsonl"),
      stderrLog: logs.appendingPathComponent("\(name).stderr.log"),
      onLine: { await inbox.put($0) }, onEnd: { await inbox.finish() })
    return S2Child(name: name, process: process, lines: inbox)
  }

  /// The first line whose `event` is `event`, parsed.
  package func waitFor(event: String, timeout: Duration = .seconds(30)) async throws -> JSONValue {
    let lines = lines
    let found = try await withDeadline(timeout, "\(name) \(event)") {
      await lines.first { line in line.contains("\"event\":\"\(event)\"") }
    }
    guard let found else { throw DriverError.childEnded("\(name) before \(event)") }
    return try JSONValue.parse(Data(found.item.utf8))
  }

  /// Sends one command and waits for its reply. A reply with `ok: false` throws.
  @discardableResult
  package func call(
    _ op: String, timeout: Duration = .seconds(60),
    _ configure: (inout S2Command) -> Void = { _ in }
  ) async throws -> JSONValue {
    let id = nextID.withLock { value in
      value += 1
      return value
    }
    var command = S2Command(id: id, op: op)
    configure(&command)
    let start = await lines.count
    try process.send(try JSONEncoder().encode(command))
    let marker = "\"id\":\(id),"
    let lines = lines
    let found = try await withDeadline(timeout, "\(name) \(op)") {
      await lines.first(from: start) { $0.hasPrefix("{") && $0.contains(marker) }
    }
    guard let found else { throw DriverError.childEnded("\(name) during \(op)") }
    let reply = try JSONValue.parse(Data(found.item.utf8))
    guard reply["ok"]?.bool == true else {
      throw S2CallError(child: name, op: op, message: reply["error"]?.string ?? "failed")
    }
    return reply
  }

  /// Every node event line so far.
  package func events() async -> [S2Line] {
    let decoder = JSONDecoder()
    return await lines.all.compactMap { line in
      guard line.contains("\"event\":\"node\"") else { return nil }
      return try? decoder.decode(S2Line.self, from: Data(line.utf8))
    }
  }

  /// Node events of one kind for one conversation.
  package func events(_ kind: String, conversation: String? = nil) async -> [S2Line] {
    await events().filter {
      $0.kind == kind && (conversation == nil || $0.conversation == conversation)
    }
  }

  /// Polls a command until `condition` holds or `timeout` passes.
  package func poll(
    _ op: String, timeout: Duration = .seconds(10), configure: (inout S2Command) -> Void,
    until condition: (JSONValue) -> Bool
  ) async throws -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if condition(try await call(op, configure)) { return true }
      try await Task.sleep(for: .milliseconds(5))
    }
    return false
  }

  /// Closes stdin, the normal stop, and waits for the exit; a child that does not stop within
  /// `timeout` is killed. Returns how it ended.
  package func stop(timeout: Duration = .seconds(20)) async throws -> ChildExit? {
    process.closeStdin()
    if let exit = await process.waitForExit(timeout: timeout) {
      try await process.drainOutput()
      return exit
    }
    process.signal(SIGKILL)
    let exit = await process.waitForExit(timeout: .seconds(5))
    try await process.drainOutput()
    return exit
  }
}

/// A command the child answered with `ok: false`.
package struct S2CallError: Error, CustomStringConvertible {
  package let child: String
  package let op: String
  package let message: String

  package var description: String { "\(child) \(op): \(message)" }
}

extension JSONValue {
  /// The member named `key` of an object.
  package subscript(key: String) -> JSONValue? {
    if case .object(let members) = self { return members[key] }
    return nil
  }

  package var bool: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  package var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  package var int: Int64? {
    switch self {
    case .integer(let value): return value
    case .double(let value): return Int64(value)
    default: return nil
    }
  }

  package var array: [JSONValue]? {
    if case .array(let value) = self { return value }
    return nil
  }
}
