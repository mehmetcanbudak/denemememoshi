#if DEBUG
  import CryptoKit
  import Darwin
  import Foundation
  import MemoshiEgress
  import MemoshiProtocol
  import MemoshiRuntime
  import PyodideSpike
  import os

  /// Development only (Phase 0 S6.5): the engine's `python_run` tool. Every call runs in the
  /// Assistant's own Pyodide realm, reads input files only through its app-created folder, and
  /// sends every Python network hop through an in-process egress gateway. Its policy class is
  /// `python.run` (T2). The gateway holds no host grant, so it refuses each hop before any DNS
  /// lookup: no Python request leaves the device. This file does not exist in Release builds.
  enum DevelopmentPythonTool {
    static let name = "python_run"

    /// `support` is the app's Application Support directory; the tool's folder lives beside the
    /// engine's data directory, never inside it.
    static func definition(support: URL) -> RuntimeToolDefinition {
      let runner = DevelopmentPythonRunner(
        root: support.appendingPathComponent("Memoshi-Development-Python", isDirectory: true))
      return RuntimeToolDefinition(
        name: name,
        description: """
          Development only: run Python 3 (Pyodide with numpy, pandas, scipy and matplotlib) in \
          this bot's private interpreter on this device. `inputs` are paths in the bot's folder, \
          copied into the cell's working directory under the same path; `outputs` are files the \
          cell writes there, saved to the bot's folder. Call memoshi_table(frame) to return a \
          table and memoshi_figure(figure) to return a PNG figure. Top-level await works. Network \
          requests go through the app's gateway, which currently allows no host.
          """,
        parameters: [
          "type": "object",
          "properties": [
            "code": ["type": "string", "minLength": 1, "maxLength": 262_144],
            "inputs": paths, "outputs": paths,
            "timeout_seconds": ["type": "number", "minimum": 1, "maximum": 300],
          ],
          "required": ["code"], "additionalProperties": false,
        ],
        operation: .pythonRun,
        // Cell output can carry the folder's files and network responses.
        outputExposure: Exposure(untrusted: true, privateData: true),
        authorize: { arguments in (try? DevelopmentPythonCall(arguments)) != nil },
        execute: { arguments, invocation in
          let call = try DevelopmentPythonCall(arguments)
          return try await invocation.runCancellable { try await runner.run(call) }
        })
    }

    private static let paths: JSONValue = [
      "type": "array", "maxItems": 32, "uniqueItems": true,
      "items": ["type": "string", "minLength": 1, "maxLength": 1_024],
    ]
  }

  /// Validated arguments; the host checks each path again before it copies or exports a file.
  struct DevelopmentPythonCall: Sendable {
    let code: String
    let inputs: [String]
    let outputs: [String]
    let timeoutSeconds: Double

    init(_ arguments: JSONValue) throws {
      guard case .object(let values) = arguments,
        Set(values.keys).isSubset(of: ["code", "inputs", "outputs", "timeout_seconds"]),
        case .string(let code)? = values["code"], !code.isEmpty
      else { throw RuntimeToolError.invalidArguments }
      func paths(_ key: String) throws -> [String] {
        guard let value = values[key] else { return [] }
        guard case .array(let items) = value, items.count <= 32 else {
          throw RuntimeToolError.invalidArguments
        }
        let paths = try items.map { item in
          guard case .string(let path) = item, !path.isEmpty else {
            throw RuntimeToolError.invalidArguments
          }
          return path
        }
        guard Set(paths).count == paths.count else { throw RuntimeToolError.invalidArguments }
        return paths
      }
      let timeout: Double
      switch values["timeout_seconds"] {
      case nil: timeout = 60
      case .integer(let value)?: timeout = Double(value)
      case .double(let value)?: timeout = value
      default: throw RuntimeToolError.invalidArguments
      }
      guard timeout.isFinite, (1...300).contains(timeout) else {
        throw RuntimeToolError.invalidArguments
      }
      self.code = code
      inputs = try paths("inputs")
      outputs = try paths("outputs")
      timeoutSeconds = timeout
    }
  }

  /// One realm, folder and gateway client for the Assistant, opened on the first call and kept
  /// for the app's lifetime. A timeout or cancel discards the realm; the next call starts a new one.
  @MainActor
  final class DevelopmentPythonRunner {
    private struct Session {
      let host: PyodideHost
      let folder: PyodideBotFolder
      let gateway: EgressGateway
    }

    /// A cell's PNG figure, saved write-once in the bot's folder.
    private struct SavedFigure {
      let path: String
      let bytes: Int
      let sha256: String
    }

    private struct Network {
      let hops: Int
      let allowed: Int
      let complete: Bool
    }

    private let root: URL
    private var session: Session?
    /// The one in-flight first-call setup; concurrent first calls await the same session.
    private var opening: Task<Session, any Error>?
    private let log = Logger(
      subsystem: "com.mehmetcanbudak.memoshi", category: "development-python")

    nonisolated init(root: URL) { self.root = root }

    func run(_ call: DevelopmentPythonCall) async throws -> RuntimeToolResult {
      let session: Session
      do {
        session = try await open()
      } catch {
        log.error("python_run unavailable: folder or gateway did not open")
        return RuntimeToolResult(
          text: "The development Python tool could not open its folder or gateway.", isError: true,
          effectOutcome: .notApplied)
      }
      let hopsBefore = session.gateway.decisionCount
      let request = PyodideRequest(
        code: call.code, inputPaths: call.inputs, outputPaths: call.outputs,
        timeoutSeconds: call.timeoutSeconds)
      let resultsExisted = session.folder.hasResultsDirectory
      let result: PyodideResult
      do {
        let starting = session.host.state != .ready
        // A realm that misses this start limit fails as `startTimedOut`: the cell never ran.
        // The cell's own `timeout_seconds` starts only when `execute` dispatches it. Stop
        // cancels this task through `runCancellable`, which ends the start at once as
        // `cancelled` and discards its half-started realm; the next call starts a new one.
        let startup = try await session.host.start(timeoutSeconds: 120)
        if starting {
          log.notice(
            "python realm ready: core=\(startup.coreSeconds, privacy: .public) stack=\(startup.scientificStackSeconds, privacy: .public) ready=\(startup.webViewToReadySeconds, privacy: .public)"
          )
        }
        result = try await session.host.execute(request)
      } catch let failure as PyodideFailure {
        // The host has drained the cell's network sends before it throws. A failed export
        // removes its files but can leave the run's directories, so the folder is checked. A
        // call that left no entry, and whose every hop the gateway refused, is a known no-effect
        // failure, not the unknown outcome that pauses the whole Chat.
        let network = Self.network(session.gateway, since: hopsBefore)
        let leftEntries =
          session.folder.hasResultDirectory(for: request.id)
          || (!resultsExisted && session.folder.hasResultsDirectory)
        let noEffect = network.complete && network.allowed == 0 && !leftEntries
        if failure == .cancelled, Task.isCancelled {
          // Stop ends the call with Pi's abort, which the engine keeps as an inconclusive
          // step whatever the tool knows; the log records what the runner observed.
          log.notice(
            "python_run cancelled: hops=\(network.hops, privacy: .public) noEffect=\(noEffect, privacy: .public)"
          )
          throw CancellationError()
        }
        log.notice(
          "python_run failed: \(failure.rawValue, privacy: .public) hops=\(network.hops, privacy: .public) allowed=\(network.allowed, privacy: .public) noEffect=\(noEffect, privacy: .public)"
        )
        return RuntimeToolResult(
          text: (failure.errorDescription ?? "Python failed.") + "\n" + Self.describe(network),
          isError: true, effectOutcome: noEffect ? .notApplied : .unknown)
      }
      // From here declared outputs exist; a later failure keeps the unknown outcome.
      let directory = "python-figures/" + result.requestID.uuidString.lowercased()
      let figures = try result.figures.enumerated().map { index, figure in
        let path = directory + "/figure-\(index + 1).png"
        try session.folder.stageInput(path: path, bytes: figure.png)
        return SavedFigure(path: path, bytes: figure.png.count, sha256: Self.hex(figure.png))
      }
      let network = Self.network(session.gateway, since: hopsBefore)
      log.notice(
        "python_run finished: request=\(result.requestID.uuidString, privacy: .public) seconds=\(result.elapsedSeconds, privacy: .public) tables=\(result.tables.count, privacy: .public) figures=\(figures.count, privacy: .public) files=\(result.artifacts.count, privacy: .public) hops=\(network.hops, privacy: .public) allowed=\(network.allowed, privacy: .public)"
      )
      return RuntimeToolResult(text: Self.render(result, figures: figures, network: network))
    }

    private func open() async throws -> Session {
      if let session { return session }
      if let opening { return try await opening.value }
      let task = Task { try await makeSession() }
      opening = task
      do {
        let session = try await task.value
        self.session = session
        opening = nil
        return session
      } catch {
        opening = nil
        throw error
      }
    }

    private func makeSession() async throws -> Session {
      // PyodideBotFolder walks from `/` without following symlinks, so it needs the physical
      // spelling of the container (`/private/var` on a device, not its `/var` alias).
      guard let physical = realpath(root.deletingLastPathComponent().path, nil) else {
        throw PyodideFailure.fileUnavailable
      }
      let support = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
      free(physical)
      let base = support.appendingPathComponent(root.lastPathComponent, isDirectory: true)
      let botDirectory = base.appendingPathComponent("assistant", isDirectory: true)
      for directory in [base, botDirectory] {
        guard mkdir(directory.path, 0o700) == 0 || errno == EEXIST else {
          throw PyodideFailure.fileUnavailable
        }
      }
      let folder = try PyodideBotFolder(ownedDirectory: botDirectory)
      let gateway = try await EgressGateway.start(
        decisionLog: base.appendingPathComponent(
          "egress-decisions-\(UUID().uuidString.lowercased()).jsonl"))
      let client: EgressClient
      do {
        client = try await gateway.openClient(
          EgressClientIdentity(
            bot: "assistant", conversation: "development-python", computer: "ios-pyodide"),
          policy: EgressPolicy(hosts: []))
      } catch {
        await gateway.shutdown()
        throw error
      }
      let host = PyodideHost(
        botID: UUID(), folder: folder, network: DevelopmentPythonEgress(client: client))
      return Session(host: host, folder: folder, gateway: gateway)
    }

    /// Gateway decisions since `before`. `complete` is false when the gateway's bounded memory
    /// window no longer holds all of them, so an allowed hop could be missed. The window and its
    /// count are read at one moment, so they cannot disagree.
    private static func network(_ gateway: EgressGateway, since before: Int) -> Network {
      let (window, recorded) = gateway.decisionWindow
      let hops = recorded - before
      return Network(
        hops: hops, allowed: window.suffix(hops).count(where: \.allowed),
        complete: hops <= window.count)
    }

    private static func describe(_ network: Network) -> String {
      "network: \(network.hops) hop(s) through the in-app gateway, \(network.allowed) allowed"
    }

    private static func render(
      _ result: PyodideResult, figures: [SavedFigure], network: Network
    ) -> String {
      var lines = [
        "python_run \(result.requestID.uuidString.lowercased()) finished in "
          + String(format: "%.2f", result.elapsedSeconds) + " s"
      ]
      lines.append("stdout:\n" + (result.stdout.isEmpty ? "(empty)" : result.stdout))
      if !result.stderr.isEmpty { lines.append("stderr:\n" + result.stderr) }
      for (index, table) in result.tables.enumerated() {
        let rows =
          table.jsonRows.utf8.count <= 8_192
          ? table.jsonRows : "(\(table.jsonRows.utf8.count) bytes of rows omitted)"
        lines.append(
          "table \(index + 1): columns \(table.columns.joined(separator: ", ")); "
            + "\(table.totalRows) rows; rows \(rows)")
      }
      for (index, figure) in figures.enumerated() {
        lines.append(
          "figure \(index + 1): PNG \(figure.path), \(figure.bytes) bytes, sha256 \(figure.sha256)")
      }
      for file in result.artifacts {
        lines.append("file: \(file.path), \(file.bytes) bytes, sha256 \(file.sha256)")
      }
      lines.append(describe(network))
      return lines.joined(separator: "\n")
    }

    private static func hex(_ data: Data) -> String {
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
  }

  /// One hop per send through this client's own loopback gateway listener, attributed to the cell.
  private struct DevelopmentPythonEgress: PyodideNetworkTransport {
    let client: EgressClient

    func send(_ request: PyodideHTTPRequest, cellID: UUID) async throws -> PyodideHTTPResponse {
      guard let url = URL(string: request.url) else { throw PyodideFailure.networkFailed }
      let call = client.beginCall("python_run-" + cellID.uuidString.lowercased())
      defer { client.endCall(call) }
      let response = try await client.fetch(
        url, method: request.method, headers: request.headers, body: request.body,
        attribution: call)
      return PyodideHTTPResponse(
        status: response.status, headers: response.headers, body: response.body)
    }
  }
#endif
