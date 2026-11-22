// Memoshi Code Mode workload harness for the D89/D90 record:
// docs/research/spikes/2026-11-02-code-mode-workload.md.
// Fixtures: docs/research/spikes/fixtures/CodeModeWorkload/22dc6c26f3c5/.
// Nonshipping qualification source: Package.swift excludes this directory from the MemoshiRuntime library.
//
// Public-API consumer of Pi_Swift, written at 892585fc8d8be3093b58c34aacffcd4e68c3a8d9 (PiDurable, PiCodeMode, PiAI, PiCore, Chord),
// modelled on upstream's `bench:codemode` (packages/durable/test/codemode-bench.ts at 22dc6c26f3c5). It is meant to be
// compiled into the SDK owner's Release measurement host (macOS command line for smoke runs, an iOS app for the reference
// devices). provenance.json records the digest of every revision and what was compiled or executed with it.
//
// One call to `CodeModeWorkloadRunner.runLaunch` is one process launch of the protocol in the record: idle baseline, Code
// Mode initialisation, then cold, warm-up and warm turns (W1/W2) or warm-up, stop/limit case and isolation turns (W3*).
// The device driver starts a fresh process for every launch and enforces the per-launch deadline.

import Chord
import CryptoKit
import Darwin
import Foundation
import PiAI
import PiCodeMode
import PiCore
import PiDurable
import Synchronization

#if os(iOS)
  import os
#endif

// MARK: - Deterministic fixture tools (scenario.json `tools`)

/// Generators for every fixture tool result. Values contain no character that JSON must escape except the newline that
/// `issueGet` writes as the two-character escape, so the text equals JavaScript's `JSON.stringify` of the same object.
enum CodeModeWorkloadFixture {
  static let repository = "memoshi/fixture"
  static let filePaths: [String] = (1...10).map {
    "Sources/Module\(CodeModeWorkloadFixture.pad($0, 2))/File\(CodeModeWorkloadFixture.pad($0, 2)).swift"
  }

  static func pad(_ value: Int, _ width: Int) -> String {
    let digits = String(value)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
  }

  static func issuesList(repo: String, state: String, limit: Int) -> String? {
    guard repo == repository, state == "open", (1...9).contains(limit) else { return nil }
    let items = (0..<limit).map { offset -> String in
      let number = 100 + limit - offset
      return #"{"number":\#(number),"title":"Fixture issue \#(number)"}"#
    }
    return #"{"repo":"\#(repo)","state":"open","items":[\#(items.joined(separator: ","))]}"#
  }

  static func issueBodyLines(_ number: Int) -> [String] {
    var lines = ["## Summary"]
    for paragraph in 1...24 {
      lines.append(
        "Paragraph \(pad(paragraph, 2)) of issue \(number): the fixture text repeats until the body reaches its target size."
      )
    }
    lines.append("## Tasks")
    for task in 1...8 {
      lines.append((task <= number % 5 ? "- [x] " : "- [ ] ") + "Task \(task) for issue \(number)")
    }
    return lines
  }

  static func issueGet(repo: String, number: Int) -> String? {
    guard repo == repository, (101...109).contains(number) else { return nil }
    let index = number - 100
    var labels = ["fixture", number % 2 == 0 ? "bug" : "feature"]
    if number % 4 == 0 { labels.append("ui") }
    let labelList = labels.map { #""\#($0)""# }.joined(separator: ",")
    let body = issueBodyLines(number).joined(separator: #"\n"#)
    let created = "2026-10-\(pad(10 + index, 2))T09:00:00Z"
    let updated = "2026-11-\(pad(((index * 3) % 4) + 1, 2))T\(pad(10 + index, 2)):00:00Z"
    return
      #"{"number":\#(number),"title":"Fixture issue \#(number)","state":"open","author":"author-\#((number % 3) + 1)","labels":[\#(labelList)],"createdAt":"\#(created)","updatedAt":"\#(updated)","comments":\#(number % 9),"body":"\#(body)"}"#
  }

  static func codeSearch(query: String, path: String, maxResults: Int) -> String? {
    guard query == "TODO(memoshi)", path == "Sources", (1...10).contains(maxResults) else {
      return nil
    }
    let matches = filePaths.prefix(maxResults).map { #"{"path":"\#($0)","line":25}"# }
    return #"{"query":"TODO(memoshi)","matches":[\#(matches.joined(separator: ","))]}"#
  }

  static func fileRead(path: String) -> String? {
    guard let position = filePaths.firstIndex(of: path) else { return nil }
    let module = pad(position + 1, 2)
    var text = ""
    text.reserveCapacity(46_000)
    for line in 1...1_000 {
      let number = pad(line, 4)
      if line % 25 == 0 {
        text += "// TODO(memoshi): item \(module)-\(number) review needed.\n"
      } else {
        text += "let v\(module)_\(number) = \(number) + \(module) // fixture code line\n"
      }
    }
    return text
  }

  static func symbolsOutline(paths: [String]) -> String? {
    guard (1...10).contains(paths.count) else { return nil }
    var files: [String] = []
    for path in paths {
      guard let position = filePaths.firstIndex(of: path) else { return nil }
      let module = pad(position + 1, 2)
      files.append(
        #"{"path":"\#(path)","symbols":960,"firstSymbol":"v\#(module)_0001","lastSymbol":"v\#(module)_0999"}"#
      )
    }
    return #"{"files":[\#(files.joined(separator: ","))]}"#
  }
}

// MARK: - Observation helpers

/// Signals the harness when a W3 script reaches its stop/limit phase through the `probe_mark` fixture tool.
actor ProbeSignal {
  private var fired: [String] = []
  private var waiter: CheckedContinuation<String, Never>?

  func fire(_ phase: String) {
    if let waiter {
      self.waiter = nil
      waiter.resume(returning: phase)
    } else {
      fired.append(phase)
    }
  }

  /// The driver's per-launch deadline bounds this wait when a script never reaches its probe.
  func next() async -> String {
    if !fired.isEmpty { return fired.removeFirst() }
    return await withCheckedContinuation { waiter = $0 }
  }
}

final class Counter: Sendable {
  private let value = Mutex(0)
  func increment() { value.withLock { $0 += 1 } }
  func take() -> Int {
    value.withLock { current in
      defer { current = 0 }
      return current
    }
  }
}

final class CodemodeExecutions: Sendable {
  struct Execution: Sendable {
    let durationMs: Double
    let result: ToolExecutionResult?
    let error: String?
  }
  private let items = Mutex<[Execution]>([])
  func record(_ execution: Execution) { items.withLock { $0.append(execution) } }
  func take() -> [Execution] {
    items.withLock { current in
      defer { current.removeAll() }
      return current
    }
  }
}

final class EngineObservations: Sendable {
  private let moduleLoads = Mutex<[Double]>([])
  private let workers = Mutex<[CodemodeWorkerLifetime]>([])
  func moduleLoaded(_ milliseconds: Double) { moduleLoads.withLock { $0.append(milliseconds) } }
  func workerStarted(_ lifetime: CodemodeWorkerLifetime) {
    workers.withLock { $0.append(lifetime) }
  }
  func takeModuleLoads() -> [Double] {
    moduleLoads.withLock { current in
      defer { current.removeAll() }
      return current
    }
  }
  func workerCount() -> Int { workers.withLock { $0.count } }
  func lastWorker() -> CodemodeWorkerLifetime? { workers.withLock { $0.last } }
}

/// One request a fixture tool answered, counted inside the tool, so it shows what the script actually received.
struct FixtureCall: Sendable {
  let tool: String
  /// The issue number or file path that selects the result, for the tools that have one.
  let key: String?
  let bytes: Int
  let lines: Int
  let accepted: Bool
}

final class FixtureLedger: Sendable {
  private let calls = Mutex<[FixtureCall]>([])
  func record(_ call: FixtureCall) { calls.withLock { $0.append(call) } }
  func take() -> [FixtureCall] {
    calls.withLock { current in
      defer { current.removeAll() }
      return current
    }
  }
}

func milliseconds(_ duration: Duration) -> Double {
  let parts = duration.components
  return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
}

struct FootprintReading: Sendable, Codable {
  /// `task_vm_info.phys_footprint`, the figure the iOS memory limit uses.
  var physFootprint: UInt64
  /// `task_vm_info.ledger_phys_footprint_peak` (TASK_VM_INFO rev3+); treated as the process high-water mark.
  var ledgerPeak: Int64?
  /// `os_proc_available_memory()` on iOS; nil on macOS.
  var availableBytes: UInt64?
}

enum Footprint {
  static func read() -> FootprintReading? {
    // Same pattern as Pi_Swift's Scripts/benchmarks/ai-release.swift MemorySnapshot.capture().
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
    let capacity = Int(count)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard status == KERN_SUCCESS else { return nil }
    var peak: Int64?
    if let offset = MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_phys_footprint_peak),
      Int(count) * MemoryLayout<integer_t>.stride >= offset + MemoryLayout<Int64>.size
    {
      peak = info.ledger_phys_footprint_peak
    }
    #if os(iOS)
      let available: UInt64? = UInt64(os_proc_available_memory())
    #else
      let available: UInt64? = nil
    #endif
    return FootprintReading(
      physFootprint: UInt64(info.phys_footprint), ledgerPeak: peak, availableBytes: available)
  }
}

struct EnvironmentReading: Sendable, Codable {
  var thermalState: String
  var lowPowerMode: Bool
  var debuggerAttached: Bool
  var buildConfiguration: String
  var operatingSystem: String

  static func read() -> EnvironmentReading {
    let thermal: String
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: thermal = "nominal"
    case .fair: thermal = "fair"
    case .serious: thermal = "serious"
    case .critical: thermal = "critical"
    @unknown default: thermal = "unknown"
    }
    var process = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    let traced =
      sysctl(&name, UInt32(name.count), &process, &size, nil, 0) == 0
      && (process.kp_proc.p_flag & P_TRACED) != 0
    #if DEBUG
      let configuration = "debug"
    #else
      let configuration = "release"
    #endif
    return EnvironmentReading(
      thermalState: thermal, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
      debuggerAttached: traced,
      buildConfiguration: configuration,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString)
  }
}

/// The guest that PiCodeMode's resource bundle resolves: `getQuickJSWasmURL()` is the URL `loadQuickJSWasm()` reads. It is
/// read after the last turn, so the measured cold path still includes the first resource lookup.
struct GuestReading: Sendable, Codable {
  var path: String
  var bytes: Int
  var sha256: String

  static func read() throws -> GuestReading {
    let url = try getQuickJSWasmURL()
    let data = try Data(contentsOf: url)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return GuestReading(path: url.path, bytes: data.count, sha256: digest)
  }
}

// MARK: - Expected values (expected.json; the guest pin from scenario.json)

struct ScenarioFile: Decodable {
  struct Guest: Decodable {
    let wasmBytes: Int
    let wasmSha256: String
  }
  let guest: Guest
}

struct ExpectedFile: Decodable {
  let workloads: [String: ExpectedWorkload]
}

/// One `inputBytes` value: the size every call of a tool returns, or sizes keyed by the call's issue number or path.
enum ExpectedBytes: Decodable, Equatable {
  case each(Int)
  case byKey([String: Int])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Int.self) {
      self = .each(value)
    } else {
      self = .byKey(try container.decode([String: Int].self))
    }
  }
}

struct ExpectedWorkload: Decodable {
  let script: String
  let outcome: String
  let result: String?
  let resultBytes: Int?
  let nestedCalls: Int?
  let callsByTool: [String: Int]?
  let hookDecisions: Int?
  /// `script` (UTF-8 bytes of the script file), `nestedTotal` (all served results), `<tool>` and `<tool>_lines`.
  let inputBytes: [String: ExpectedBytes]?
  let probePhase: String?
  let completedValueIfNotStopped: String?
  let errorTextAnyOf: [String]?
}

// MARK: - Launch protocol

enum WorkloadID: String, Sendable, Codable, CaseIterable {
  case w1 = "W1"
  case w2 = "W2"
  case w3a = "W3a"
  case w3b = "W3b"
  case w3c = "W3c"
}

struct WorkloadLaunchOptions: Sendable {
  var workload: WorkloadID
  /// The fixture root: `scenario.json`, `expected.json` and `scripts/`.
  var fixture: URL
  /// A fresh, private, empty directory for this launch's SQLite store.
  var storeDirectory: URL
  /// Declared by the host build. Results count only when E32/P05-06 diagnostics confirm it.
  var backendLabel: String
  var launchIndex: Int
  var memoryLimitBytes: Int
  var idleBeforeBaselineMs: Int
  var gapMs: Int
  var stopDelayMs: Int

  init(
    workload: WorkloadID, fixture: URL, storeDirectory: URL, backendLabel: String, launchIndex: Int,
    memoryLimitBytes: Int = 268_435_456, idleBeforeBaselineMs: Int = 2_000, gapMs: Int = 1_500,
    stopDelayMs: Int = 100
  ) {
    self.workload = workload
    self.fixture = fixture
    self.storeDirectory = storeDirectory
    self.backendLabel = backendLabel
    self.launchIndex = launchIndex
    self.memoryLimitBytes = memoryLimitBytes
    self.idleBeforeBaselineMs = idleBeforeBaselineMs
    self.gapMs = gapMs
    self.stopDelayMs = stopDelayMs
  }
}

struct TurnSample: Sendable, Codable {
  /// `cold`, `warmup`, `warm`, `stop`, `limit` or `isolation`.
  var mode: String
  var workload: String
  /// The gated boundary: entry to exit of the durable `codemode` tool's `execute`.
  var codemodeMs: Double?
  /// `submit` to the submission's terminal `wait()`, upstream bench-compatible; reported, not gated.
  var turnMs: Double
  var commits: Int
  var hookDecisions: Int
  /// Executions of the outer codemode tool and faux model requests in this turn; a completed turn has 1 and 2.
  var codemodeExecutions: Int
  var modelCalls: Int
  /// Nested calls as the codemode result's `details.calls` reports them.
  var nestedCalls: Int?
  var nestedCallsByTool: [String: Int]?
  /// Calls the fixture tools served and the UTF-8 bytes they returned, counted inside the tools.
  var fixtureCallsByTool: [String: Int]
  var nestedResultBytes: Int
  var scriptBytes: Int
  /// The script's returned string (completed turns) or the joined failure text (W3c, stop cases), and its UTF-8 size.
  var resultText: String?
  var resultBytes: Int?
  var workerStartsSoFar: Int
  var moduleLoadsMs: [Double]
  var verified: Bool
  var verification: String
  /// W3 stop cases: Stop pressed to `Conversation.abort()` returning, to the terminal submission, and to VM exit.
  var abortReturnedMs: Double?
  var stopSettledMs: Double?
  var workerExitedMs: Double?
}

struct LaunchResult: Sendable, Codable {
  var schema = "memoshi.codemode-workload.result.v1"
  var workload: String
  var backendLabel: String
  var launchIndex: Int
  var memoryLimitBytes: Int
  var environmentBefore: EnvironmentReading
  var environmentAfter: EnvironmentReading
  var idleBaseline: FootprintReading?
  var codemodeInitMs: Double
  var samples: [TurnSample]
  var finalReading: FootprintReading?
  /// max(ledger peak at end of launch, final phys_footprint) − idle baseline phys_footprint; nil when unreadable.
  var incrementalPeakBytes: Int64?
  /// The quickjs.wasm the resource bundle resolved, checked against scenario.json's guest pin.
  var guest: GuestReading?
  var failures: [String]
}

enum CodeModeWorkloadRunner {
  /// A completed turn makes exactly two faux model requests: the codemode tool call, then the closing text.
  static let modelCallsPerTurn = 2

  static func runLaunch(_ options: WorkloadLaunchOptions) async throws -> LaunchResult {
    let expected = try JSONDecoder().decode(
      ExpectedFile.self,
      from: Data(contentsOf: options.fixture.appendingPathComponent("expected.json")))
    let scenario = try JSONDecoder().decode(
      ScenarioFile.self,
      from: Data(contentsOf: options.fixture.appendingPathComponent("scenario.json")))
    let environmentBefore = EnvironmentReading.read()
    var failures: [String] = []

    // Composition outside the measured region: store, model, fixture tools and the counting policy hooks.
    let probe = ProbeSignal()
    let ledger = FixtureLedger()
    let decisions = Counter()
    let commits = Counter()
    let executions = CodemodeExecutions()
    let engine = EngineObservations()
    try FileManager.default.createDirectory(
      at: options.storeDirectory, withIntermediateDirectories: true)
    let storage = try await openSqliteStorage(
      options.storeDirectory.appendingPathComponent("session.sqlite").path)
    let faux = try fauxProvider()
    let models = createModels()
    models.setProvider(faux.provider)
    let registry = createRegistry()
    try registry.install(
      Extension(name: "fixture.tools", tools: fixtureTools(probe: probe, ledger: ledger)))
    try registry.install(
      Extension(
        name: "fixture.policy",
        hooks: [
          HookRegistration(
            task: "pi.tool",
            handlers: HookHandlers(
              beforeTool: { _, _, _ in
                decisions.increment()
                return nil
              },
              afterTool: { _, _, _, _ in nil }))
        ]))
    let harness = try await Harness.open(
      storage: storage,
      options: HarnessOptions(
        models: models, registry: registry,
        toolPolicy: ToolPolicy { _, _, _ in .allow }))
    let stopCommits = try await harness.session.subscribeCommits { _, _ in commits.increment() }
    try await harness.conversation().configure(
      AgentChange(model: .set(ModelRef(provider: "faux", modelId: "faux-1"))))

    try await Task.sleep(for: .milliseconds(options.idleBeforeBaselineMs))
    let idleBaseline = Footprint.read()

    // Code Mode initialisation is measured: sandbox construction, then live installation of the codemode tool.
    let initStarted = ContinuousClock.now
    let useWasmKit = options.backendLabel.lowercased() == "wasmkit"
    let sandboxOptions: CodemodeSandboxOptions
    if useWasmKit {
      sandboxOptions = CodemodeSandboxOptions(
        memoryLimitBytes: options.memoryLimitBytes,
        wasmLoader: {
          let started = ContinuousClock.now
          let module = try await loadQuickJSWasm()
          engine.moduleLoaded(milliseconds(started.duration(to: .now)))
          return module
        },
        onWorkerStarted: { lifetime in engine.workerStarted(lifetime) })
    } else {
      sandboxOptions = CodemodeSandboxOptions(
        memoryLimitBytes: options.memoryLimitBytes,
        onWorkerStarted: { lifetime in engine.workerStarted(lifetime) })
    }
    let sandbox = try CodemodeSandbox(options: sandboxOptions)
    try registry.install(
      Extension(
        name: "codemode", tools: [timedCodemodeTool(sandbox: sandbox, executions: executions)]))
    let codemodeInitMs = milliseconds(initStarted.duration(to: .now))
    if engine.workerCount() != 0 {
      failures.append("a Code Mode worker started before the cold turn")
    }

    var samples: [TurnSample] = []
    var turnIndex = 0
    func script(_ workload: WorkloadID) throws -> (
      entry: ExpectedWorkload, code: JSONString, bytes: Int
    ) {
      guard let entry = expected.workloads[workload.rawValue] else {
        throw PiError("fixture", "expected.json has no \(workload.rawValue)")
      }
      let source = try String(
        contentsOf: options.fixture.appendingPathComponent(entry.script), encoding: .utf8)
      return (entry, JSONString(source), source.utf8.count)
    }
    /// Clears every per-turn counter and returns the faux provider's request count before the turn.
    func resetCounters() -> Int {
      _ = executions.take()
      _ = decisions.take()
      _ = commits.take()
      _ = ledger.take()
      return faux.state.callCount
    }
    func completedTurn(_ workload: WorkloadID, mode: String) async throws -> TurnSample {
      turnIndex += 1
      let (entry, code, scriptBytes) = try script(workload)
      let modelCallsBefore = resetCounters()
      faux.setResponses(
        codemodeResponses(
          code: code, callID: "\(workload.rawValue.lowercased())-\(mode)-\(turnIndex)"))
      let started = ContinuousClock.now
      let submission = try await harness.conversation().submit(.input(content: .text("go")))
      _ = try await submission.wait()
      let turnMs = milliseconds(started.duration(to: .now))
      let turnExecutions = executions.take()
      let served = ledger.take()
      let decisionCount = decisions.take()
      let modelCalls = faux.state.callCount - modelCallsBefore
      let pending = faux.pendingResponses()
      var check = verify(turnExecutions, served: served, expected: entry, scriptBytes: scriptBytes)
      if let wanted = entry.hookDecisions, decisionCount != wanted {
        check.fail("\(decisionCount) policy decisions, expected \(wanted)")
      }
      if modelCalls != modelCallsPerTurn || pending != 0 {
        check.fail(
          "\(modelCalls) model requests with \(pending) scripted responses left, expected \(modelCallsPerTurn) and 0"
        )
      }
      return TurnSample(
        mode: mode, workload: workload.rawValue, codemodeMs: turnExecutions.last?.durationMs,
        turnMs: turnMs, commits: commits.take(),
        hookDecisions: decisionCount, codemodeExecutions: turnExecutions.count,
        modelCalls: modelCalls,
        nestedCalls: check.nestedCalls, nestedCallsByTool: check.nestedCallsByTool,
        fixtureCallsByTool: callsByTool(served),
        nestedResultBytes: served.reduce(0) { $0 + $1.bytes }, scriptBytes: scriptBytes,
        resultText: check.resultText,
        resultBytes: check.resultBytes, workerStartsSoFar: engine.workerCount(),
        moduleLoadsMs: engine.takeModuleLoads(),
        verified: check.verified, verification: check.summary(entry))
    }
    func gap() async throws { try await Task.sleep(for: .milliseconds(options.gapMs)) }
    func stopTurn(_ workload: WorkloadID) async throws -> TurnSample {
      turnIndex += 1
      let (entry, code, scriptBytes) = try script(workload)
      let modelCallsBefore = resetCounters()
      faux.setResponses(
        codemodeResponses(code: code, callID: "\(workload.rawValue.lowercased())-stop-\(turnIndex)")
      )
      let started = ContinuousClock.now
      let submission = try await harness.conversation().submit(.input(content: .text("go")))
      let phase = await probe.next()
      try await Task.sleep(for: .milliseconds(options.stopDelayMs))
      let worker = engine.lastWorker()
      let stopPressed = ContinuousClock.now
      try await harness.conversation().abort()
      let abortReturnedMs = milliseconds(stopPressed.duration(to: .now))
      var notes = ["probe phase \(phase)"]
      do { _ = try await submission.wait() } catch { notes.append("wait threw \(error)") }
      let stopSettledMs = milliseconds(stopPressed.duration(to: .now))
      var workerExitedMs: Double?
      if let worker {
        await worker.exited
        workerExitedMs = milliseconds(stopPressed.duration(to: .now))
      }
      let turnMs = milliseconds(started.duration(to: .now))
      let turnExecutions = executions.take()
      let served = ledger.take()
      let execution = turnExecutions.last
      var verified = phase == entry.probePhase
      if !verified { notes.append("expected probe phase \(entry.probePhase ?? "none")") }
      var text: String?
      var nestedCalls: Int?
      var nestedByTool: [String: Int]?
      if let result = execution?.result {
        let joined = (result.output ?? []).compactMap { $0.textContent?.text.displayString }.joined(
          separator: "\n")
        text = joined
        if let completed = entry.completedValueIfNotStopped, !result.isError,
          joined.hasSuffix(completed)
        {
          verified = false
          notes.append("script completed before the stop (not exercised)")
        }
        let calls = result.details?["calls"]?.arrayValue ?? []
        nestedCalls = calls.count
        nestedByTool = nestedCallsByTool(calls)
        if calls.count > 1 {
          verified = false
          notes.append("\(calls.count) nested calls, expected only probe_mark")
        }
      }
      // No nested call may follow Stop, even when the aborted codemode call returns no result to inspect.
      if served.map(\.tool) != ["probe_mark"] {
        verified = false
        notes.append("fixture tools served \(served.map(\.tool)), expected only probe_mark")
      }
      return TurnSample(
        mode: "stop", workload: workload.rawValue, codemodeMs: execution?.durationMs,
        turnMs: turnMs, commits: commits.take(),
        hookDecisions: decisions.take(), codemodeExecutions: turnExecutions.count,
        modelCalls: faux.state.callCount - modelCallsBefore,
        nestedCalls: nestedCalls, nestedCallsByTool: nestedByTool,
        fixtureCallsByTool: callsByTool(served),
        nestedResultBytes: served.reduce(0) { $0 + $1.bytes }, scriptBytes: scriptBytes,
        resultText: text, resultBytes: text?.utf8.count,
        workerStartsSoFar: engine.workerCount(), moduleLoadsMs: engine.takeModuleLoads(),
        verified: verified,
        verification: notes.joined(separator: "; "),
        abortReturnedMs: abortReturnedMs, stopSettledMs: stopSettledMs,
        workerExitedMs: workerExitedMs)
    }

    switch options.workload {
    case .w1, .w2:
      samples.append(try await completedTurn(options.workload, mode: "cold"))
      try await gap()
      samples.append(try await completedTurn(options.workload, mode: "warmup"))
      try await gap()
      samples.append(try await completedTurn(options.workload, mode: "warm"))
      try await gap()
    case .w3a, .w3b:
      samples.append(try await completedTurn(.w1, mode: "warmup"))
      try await gap()
      samples.append(try await stopTurn(options.workload))
      try await gap()
      samples.append(try await completedTurn(.w1, mode: "isolation"))
      try await gap()
    case .w3c:
      samples.append(try await completedTurn(.w1, mode: "warmup"))
      try await gap()
      samples.append(try await completedTurn(.w3c, mode: "limit"))
      try await gap()
      samples.append(try await completedTurn(.w1, mode: "isolation"))
      try await gap()
    }

    let finalReading = Footprint.read()
    stopCommits()
    try await harness.close()
    await sandbox.close()
    try? FileManager.default.removeItem(at: options.storeDirectory)

    var guest: GuestReading?
    do {
      let reading = try GuestReading.read()
      guest = reading
      if reading.sha256 != scenario.guest.wasmSha256 || reading.bytes != scenario.guest.wasmBytes {
        failures.append(
          "guest \(reading.path) is \(reading.bytes) bytes with SHA-256 \(reading.sha256), expected \(scenario.guest.wasmBytes) bytes with \(scenario.guest.wasmSha256)"
        )
      }
    } catch {
      failures.append("guest resource unreadable: \(error)")
    }
    for sample in samples where !sample.verified {
      failures.append("\(sample.mode) \(sample.workload): \(sample.verification)")
    }
    var incremental: Int64?
    if let idleBaseline, let finalReading {
      let high = max(
        finalReading.ledgerPeak ?? Int64(finalReading.physFootprint),
        Int64(finalReading.physFootprint))
      incremental = high - Int64(idleBaseline.physFootprint)
    }
    return LaunchResult(
      workload: options.workload.rawValue, backendLabel: options.backendLabel,
      launchIndex: options.launchIndex,
      memoryLimitBytes: options.memoryLimitBytes, environmentBefore: environmentBefore,
      environmentAfter: EnvironmentReading.read(),
      idleBaseline: idleBaseline, codemodeInitMs: codemodeInitMs, samples: samples,
      finalReading: finalReading,
      incrementalPeakBytes: incremental, guest: guest, failures: failures)
  }

  static func codemodeResponses(code: JSONString, callID: String) -> [FauxResponseStep] {
    [
      .message(
        fauxAssistantMessage(
          [
            .toolCall(
              fauxToolCall(
                name: CODEMODE_TOOL_NAME, arguments: ["code": .string(code)], id: JSONString(callID)
              ))
          ], stopReason: .toolUse)),
      .message(fauxAssistantMessage("ok")),
    ]
  }

  /// Wraps the real durable codemode tool; the wrapper adds only two clock reads around its `execute`.
  static func timedCodemodeTool(sandbox: CodemodeSandbox, executions: CodemodeExecutions)
    -> ToolRegistration
  {
    var tool = createCodemodeTool(CodemodeToolOptions(sandbox: sandbox, models: false))
    let base = tool.execute
    tool.execute = { arguments, api, context in
      let started = ContinuousClock.now
      do {
        let result = try await base(arguments, api, context)
        executions.record(
          .init(durationMs: milliseconds(started.duration(to: .now)), result: result, error: nil))
        return result
      } catch {
        executions.record(
          .init(
            durationMs: milliseconds(started.duration(to: .now)), result: nil,
            error: String(describing: error)))
        throw error
      }
    }
    return tool
  }

  struct TurnCheck {
    var problems: [String] = []
    var nestedCalls: Int?
    var nestedCallsByTool: [String: Int]?
    var resultText: String?
    var resultBytes: Int?
    var verified: Bool { problems.isEmpty }
    mutating func fail(_ problem: String) { problems.append(problem) }
    func summary(_ expected: ExpectedWorkload) -> String {
      guard verified else { return problems.joined(separator: "; ") }
      return expected.outcome == "scriptFailure" ? "failed as expected" : "matched expected.json"
    }
  }

  /// Completed turns: the codemode tool executed once; the last text block of its result is the script's returned string
  /// at the expected UTF-8 size; every nested call is `ok`; the per-tool counts match both as the codemode result reports
  /// them and as the fixture tools served them; and every served result has its expected size. W3c expects a failed
  /// script whose text names the limit failure.
  static func verify(
    _ executions: [CodemodeExecutions.Execution], served: [FixtureCall], expected: ExpectedWorkload,
    scriptBytes: Int
  ) -> TurnCheck {
    var check = TurnCheck()
    if executions.count != 1 {
      check.fail("the codemode tool executed \(executions.count) times, expected once")
    }
    checkServed(served, expected: expected, scriptBytes: scriptBytes, into: &check)
    guard let execution = executions.last else { return check }
    guard let result = execution.result else {
      check.fail("codemode threw: \(execution.error ?? "unknown")")
      return check
    }
    let texts = (result.output ?? []).compactMap { $0.textContent?.text.displayString }
    let calls = result.details?["calls"]?.arrayValue ?? []
    check.nestedCalls = calls.count
    check.nestedCallsByTool = nestedCallsByTool(calls)
    if expected.outcome == "scriptFailure" {
      let joined = texts.joined(separator: "\n")
      check.resultText = joined
      check.resultBytes = joined.utf8.count
      if !result.isError {
        check.fail("script did not fail")
      } else if !(expected.errorTextAnyOf ?? []).contains(where: { joined.contains($0) }) {
        check.fail("failed without the expected text")
      }
    } else {
      check.resultText = texts.last
      check.resultBytes = texts.last?.utf8.count
      if result.isError {
        check.fail("script failed: \(texts.joined(separator: " | "))")
      } else if texts.last != expected.result {
        check.fail("result differs from expected.json")
      }
      if let wanted = expected.resultBytes, check.resultBytes != wanted {
        check.fail(
          "result is \(check.resultBytes.map(String.init) ?? "missing") bytes, expected \(wanted)")
      }
      let unfinished = calls.filter { $0["status"]?.textValue?.displayString != "ok" }.count
      if unfinished > 0 { check.fail("\(unfinished) nested calls did not finish ok") }
    }
    if let wanted = expected.nestedCalls, calls.count != wanted {
      check.fail("\(calls.count) nested calls, expected \(wanted)")
    }
    if let wanted = expected.callsByTool, check.nestedCallsByTool != wanted {
      check.fail("nested calls by tool \(check.nestedCallsByTool ?? [:]), expected \(wanted)")
    }
    return check
  }

  /// What the fixture tools served, counted inside the tools: rejected requests, calls per tool and result sizes.
  static func checkServed(
    _ served: [FixtureCall], expected: ExpectedWorkload, scriptBytes: Int,
    into check: inout TurnCheck
  ) {
    let rejectedTools = served.filter { !$0.accepted }.map(\.tool)
    if !rejectedTools.isEmpty { check.fail("fixture rejected \(rejectedTools)") }
    if let wanted = expected.callsByTool, callsByTool(served) != wanted {
      check.fail("fixture tools served \(callsByTool(served)), expected \(wanted)")
    }
    for (key, value) in (expected.inputBytes ?? [:]).sorted(by: { $0.key < $1.key }) {
      switch (key, value) {
      case ("script", .each(let wanted)):
        if scriptBytes != wanted {
          check.fail("script is \(scriptBytes) bytes, expected \(wanted)")
        }
      case ("nestedTotal", .each(let wanted)):
        let total = served.reduce(0) { $0 + $1.bytes }
        if total != wanted { check.fail("served results total \(total) bytes, expected \(wanted)") }
      case (let key, .each(let wanted)) where key.hasSuffix("_lines"):
        let tool = String(key.dropLast("_lines".count))
        let lines = served.filter { $0.tool == tool }.map(\.lines)
        if lines.isEmpty || lines.contains(where: { $0 != wanted }) {
          check.fail("\(tool) returned \(lines) lines, expected \(wanted) each")
        }
      case (let tool, .each(let wanted)):
        let sizes = served.filter { $0.tool == tool }.map(\.bytes)
        if sizes.isEmpty || sizes.contains(where: { $0 != wanted }) {
          check.fail("\(tool) returned \(sizes) bytes, expected \(wanted) each")
        }
      case (let tool, .byKey(let wanted)):
        let calls = served.filter { $0.tool == tool }
        let sizes = Dictionary(
          calls.map { ($0.key ?? "", $0.bytes) }, uniquingKeysWith: { _, _ in -1 })
        if calls.count != wanted.count || sizes != wanted {
          check.fail("\(tool) returned \(sizes) bytes by key, expected \(wanted)")
        }
      }
    }
  }

  static func callsByTool(_ served: [FixtureCall]) -> [String: Int] {
    served.reduce(into: [:]) { $0[$1.tool, default: 0] += 1 }
  }

  static func nestedCallsByTool(_ calls: [JSONValue]) -> [String: Int] {
    calls.reduce(into: [:]) { $0[$1["name"]?.textValue?.displayString ?? "?", default: 0] += 1 }
  }

  static func textResult(_ value: String) -> ToolExecutionResult {
    ToolExecutionResult(output: [.text(TextContent(text: JSONString(value)))])
  }

  static func rejected(_ tool: String) -> ToolExecutionResult {
    ToolExecutionResult(
      output: [.text(TextContent(text: JSONString("fixture: unexpected \(tool) request")))],
      isError: true)
  }

  static func argument(_ arguments: JSONValue, _ key: String) -> String? {
    arguments[key]?.textValue?.nativeString
  }

  /// Records the request in the ledger, then answers it with the generated text or the fixture's rejection.
  static func serve(_ ledger: FixtureLedger, _ tool: String, key: String? = nil, _ value: String?)
    -> ToolExecutionResult
  {
    guard let value else {
      ledger.record(FixtureCall(tool: tool, key: key, bytes: 0, lines: 0, accepted: false))
      return rejected(tool)
    }
    ledger.record(
      FixtureCall(
        tool: tool, key: key, bytes: value.utf8.count, lines: value.utf8.count(where: { $0 == 10 }),
        accepted: true))
    return textResult(value)
  }

  static func fixtureTools(probe: ProbeSignal, ledger: FixtureLedger) -> [ToolRegistration] {
    return [
      ToolRegistration(
        name: "issues_list", description: "List open issues in a fixture repository, newest first.",
        parameters: [
          "type": "object",
          "properties": [
            "repo": ["type": "string"], "state": ["type": "string"], "limit": ["type": "integer"],
          ], "required": ["repo", "state", "limit"],
        ],
        replay: .safe, callers: [.tools],
        execute: { arguments, _, _ in
          guard let repo = argument(arguments, "repo"), let state = argument(arguments, "state"),
            let limit = arguments["limit"]?.intValue
          else {
            return serve(ledger, "issues_list", nil)
          }
          return serve(
            ledger, "issues_list",
            CodeModeWorkloadFixture.issuesList(repo: repo, state: state, limit: limit))
        }),
      ToolRegistration(
        name: "issue_get", description: "Read one fixture issue as JSON.",
        parameters: [
          "type": "object",
          "properties": ["repo": ["type": "string"], "number": ["type": "integer"]],
          "required": ["repo", "number"],
        ],
        replay: .safe, callers: [.tools],
        execute: { arguments, _, _ in
          guard let repo = argument(arguments, "repo"), let number = arguments["number"]?.intValue
          else { return serve(ledger, "issue_get", nil) }
          return serve(
            ledger, "issue_get", key: String(number),
            CodeModeWorkloadFixture.issueGet(repo: repo, number: number))
        }),
      ToolRegistration(
        name: "code_search", description: "Search fixture sources for a literal string.",
        parameters: [
          "type": "object",
          "properties": [
            "query": ["type": "string"], "path": ["type": "string"],
            "maxResults": ["type": "integer"],
          ], "required": ["query", "path", "maxResults"],
        ],
        replay: .safe, callers: [.tools],
        execute: { arguments, _, _ in
          guard let query = argument(arguments, "query"), let path = argument(arguments, "path"),
            let limit = arguments["maxResults"]?.intValue
          else {
            return serve(ledger, "code_search", nil)
          }
          return serve(
            ledger, "code_search",
            CodeModeWorkloadFixture.codeSearch(query: query, path: path, maxResults: limit))
        }),
      ToolRegistration(
        name: "file_read", description: "Read one fixture source file.",
        parameters: [
          "type": "object", "properties": ["path": ["type": "string"]], "required": ["path"],
        ],
        replay: .safe, callers: [.tools],
        execute: { arguments, _, _ in
          guard let path = argument(arguments, "path") else {
            return serve(ledger, "file_read", nil)
          }
          return serve(ledger, "file_read", key: path, CodeModeWorkloadFixture.fileRead(path: path))
        }),
      ToolRegistration(
        name: "symbols_outline", description: "Summarize the symbols of fixture source files.",
        parameters: [
          "type": "object",
          "properties": ["paths": ["type": "array", "items": ["type": "string"]]],
          "required": ["paths"],
        ],
        replay: .safe, callers: [.tools],
        execute: { arguments, _, _ in
          let paths = (arguments["paths"]?.arrayValue ?? []).compactMap {
            $0.textValue?.nativeString
          }
          return serve(
            ledger, "symbols_outline", CodeModeWorkloadFixture.symbolsOutline(paths: paths))
        }),
      ToolRegistration(
        name: "probe_mark",
        description: "Tell the measurement harness that the script reached a phase.",
        parameters: [
          "type": "object", "properties": ["phase": ["type": "string"]], "required": ["phase"],
        ],
        replay: .safe, callers: [.tools],
        execute: { arguments, _, _ in
          guard let phase = argument(arguments, "phase") else {
            return serve(ledger, "probe_mark", nil)
          }
          // Recorded before the signal, so a Stop that follows the probe always finds it in the ledger.
          let result = serve(ledger, "probe_mark", key: phase, "ok")
          await probe.fire(phase)
          return result
        }),
    ]
  }
}
