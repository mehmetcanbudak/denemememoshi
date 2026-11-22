import Darwin
import Foundation
import MemoshiProtocol
import Synchronization

package struct S1Measured<Value: Sendable>: Sendable {
  package var value: Value
  package var measurement: S1CallMeasurement
}

/// Owns one process life and its private pipe carrier. No PID discovery or unrelated signaling.
package final class S1Child: Sendable {
  package let name: String
  package let process: ChildProcess
  private let lines: Inbox<String>
  private let nextID = Mutex(0)
  private let requests: LineWriter

  private init(name: String, process: ChildProcess, lines: Inbox<String>, requests: LineWriter) {
    self.name = name
    self.process = process
    self.lines = lines
    self.requests = requests
  }

  /// Register before sending configuration or awaiting ready, so failed startup is cleaned too.
  package static func spawn(
    name: String, executable: URL, environment: [String: String], logs: URL,
    requests: LineWriter, owned: S1Children, configuration: S1HostConfiguration
  ) async throws -> S1Child {
    let lines = Inbox<String>()
    let process = try ChildProcess.spawn(
      executable: executable, arguments: ["s1-host"], environment: environment,
      stdoutLog: logs.appendingPathComponent(name + ".stdout.jsonl"),
      stderrLog: logs.appendingPathComponent(name + ".stderr.log"),
      onLine: { await lines.put($0) }, onEnd: { await lines.finish() })
    let child = S1Child(name: name, process: process, lines: lines, requests: requests)
    await owned.append(child)
    try process.send(try JSONLines.encoder.encode(configuration))
    return child
  }

  package func ready() async throws -> S1ProcessReading {
    let line = try await first("ready", timeout: .seconds(45)) {
      guard let value = try? JSONValue.parse(Data($0.utf8)) else { return false }
      return value["s1"]?.string == "fatal" || value["id"]?.string == "ready"
    }
    let reply = try JSONDecoder().decode(S1ControlReply.self, from: Data(line.utf8))
    guard reply.ok, let reading = reply.reading, reading.pid == process.pid else {
      throw DriverError.invalid("S1 host ready identity")
    }
    return reading
  }

  package func call<Method: RPCMethod>(
    _ method: Method.Type, _ params: Method.Params, timeout: Duration = .seconds(45)
  ) async throws -> S1Measured<Method.Result> {
    let id = try JSONRPCID("c:\(number())")
    let frame = try JSONRPCCodec().encodeRequest(method, id: id, params: params)
    let start = await lines.count
    // This is the actual request frame, not reconstructed parameters after the fact.
    requests.text(String(decoding: frame, as: UTF8.self))
    try process.send(frame)
    let response = try await first("\(Method.name) response", from: start, timeout: timeout) {
      guard let value = try? JSONValue.parse(Data($0.utf8)) else { return false }
      return value["jsonrpc"]?.string == "2.0" && value["id"]?.string == id.rawValue
    }
    let decoded = try JSONRPCCodec().decodeResponse(method, from: Data(response.utf8))
    guard decoded.id == id else { throw DriverError.invalid("S1 response correlation") }
    let value = try decoded.get()
    let measured = try await first("\(Method.name) measurement", from: start, timeout: timeout) {
      guard let value = try? JSONValue.parse(Data($0.utf8)) else { return false }
      return value["s1"]?.string == "measurement" && value["id"]?.string == id.rawValue
    }
    let measurement = try JSONDecoder().decode(S1CallMeasurement.self, from: Data(measured.utf8))
    guard measurement.method == Method.name, measurement.durationNs >= 0 else {
      throw DriverError.invalid("S1 call measurement correlation")
    }
    return S1Measured(value: value, measurement: measurement)
  }

  package func control(
    _ op: String, requestIds: [ULID] = [], after: Int64 = 0, through: Int64? = nil,
    retentionDays: Int? = nil
  ) async throws -> S1ControlReply {
    let id = "control:\(number())"
    let command = S1Control(
      s1: op, id: id, requestIds: requestIds, after: after, through: through,
      retentionDays: retentionDays)
    let start = await lines.count
    let frame = try JSONLines.encoder.encode(command)
    requests.text(String(decoding: frame, as: UTF8.self))
    try process.send(frame)
    let line = try await first("S1 \(op)", from: start, timeout: .seconds(30)) {
      guard let value = try? JSONValue.parse(Data($0.utf8)) else { return false }
      return value["s1"]?.string == "reply" && value["id"]?.string == id
    }
    let reply = try JSONDecoder().decode(S1ControlReply.self, from: Data(line.utf8))
    guard reply.ok else { throw DriverError.invalid("S1 \(op) failed in \(name)") }
    return reply
  }

  package func probe(_ requestIDs: [ULID] = []) async throws -> S1ProcessReading {
    let reply = try await control("probe", requestIds: requestIDs)
    guard let reading = reply.reading, reading.pid == process.pid else {
      throw DriverError.invalid("S1 probe process identity")
    }
    return reading
  }

  package func cursor() async -> Int { await lines.count }

  /// Waits for real message.delta notifications after this workload's actual stdout cursor.
  package func streaming(
    _ conversations: Set<ConversationID>, from: Int
  ) async throws {
    for conversation in conversations {
      _ = try await first("S1 current text delta", from: from, timeout: .seconds(30)) {
        guard let events = try? JSONRPCCodec().decodeEvents(from: Data($0.utf8)) else {
          return false
        }
        return events.contains { event in
          guard case .messageDelta(let delta) = event.event else { return false }
          return event.seq == nil && event.scope.conversationId == conversation
            && !delta.text.isEmpty
        }
      }
    }
  }

  package func killWhileStreaming() async throws {
    process.signal(SIGKILL)
    guard await process.waitForExit(timeout: .seconds(5)) == .signaled(SIGKILL) else {
      throw DriverError.invalid("S1 owned SIGKILL was not observed")
    }
    try await process.drainOutput()
  }

  package func stop() async throws -> ChildExit? {
    process.closeStdin()
    var exit = await process.waitForExit(timeout: .seconds(10))
    if exit == nil {
      process.signal(SIGKILL)
      exit = await process.waitForExit(timeout: .seconds(5))
    }
    try await process.drainOutput()
    return exit
  }

  private func number() -> Int {
    nextID.withLock { value in
      value += 1
      return value
    }
  }

  private func first(
    _ label: String, from: Int = 0, timeout: Duration,
    where match: @escaping @Sendable (String) -> Bool
  ) async throws -> String {
    let lines = lines
    let found = try await withDeadline(timeout, "\(name) \(label)") {
      await lines.first(from: from, where: match)
    }
    guard let found else { throw DriverError.childEnded("\(name) \(label)") }
    return found.item
  }
}

/// All process lives, including ones whose startup failed; retained until final cleanup.
package actor S1Children {
  private var children: [S1Child] = []
  package init() {}
  package func append(_ child: S1Child) { children.append(child) }
  package func stopAll(_ results: S1Results) async {
    for child in children {
      let exit: ChildExit?
      do { exit = try await child.stop() } catch {
        exit = child.process.exit
        await results.fail("Owned S1 child capture failed: \(child.name): \(error)")
      }
      await results.exit("\(child.name): \(exit.map(String.init(describing:)) ?? "not reaped")")
      if exit == nil { await results.fail("Owned S1 child could not be reaped: \(child.name)") }
    }
  }
}
