// Non-shipping driver for the signed replay qualification (P0-07, P0-08, exit criterion 6).
// It must be signed as `com.mehmetcanbudak.memoshi.mac`. It starts signed `memoshi-replay-daemon`
// lives, commits durable events through them, and checks that a live client and a client parked
// at seq 0 fold the same chain as the daemon's commit receipts and as a fresh store fold.
//   memoshi-replay-client --daemon FILE --schema FILE --root DIR --output FILE
//     [--cycles 1000] [--restart-every 100] [--seed N]
import Foundation
import MemoshiClient
import MemoshiProtocol
import MemoshiReplayKit
import MemoshiTransport

setvbuf(stdout, nil, _IOLBF, 0)

struct Failure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

let arguments = CommandLine.arguments
func option(_ flag: String) -> String? {
  arguments.firstIndex(of: flag).flatMap {
    arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
  }
}
guard let daemonPath = option("--daemon"), let schemaPath = option("--schema"),
  let rootPath = option("--root"), let outputPath = option("--output")
else {
  FileHandle.standardError.write(
    Data(
      "usage: --daemon FILE --schema FILE --root DIR --output FILE [--cycles N] [--restart-every N] [--seed N]\n"
        .utf8))
  exit(64)
}
let cycles = option("--cycles").flatMap(Int.init) ?? 1000
let restartEvery = option("--restart-every").flatMap(Int.init) ?? 100
let seed = option("--seed").flatMap(UInt64.init) ?? 20_261_119

/// SplitMix64: the seed makes the offline commit counts reproducible.
struct Random {
  var state: UInt64
  mutating func next(_ bound: Int) -> Int {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return Int((z ^ (z >> 31)) % UInt64(bound))
  }
}

func milliseconds(_ duration: Duration) -> Int {
  Int(duration.components.seconds) * 1000
    + Int(duration.components.attoseconds / 1_000_000_000_000_000)
}

func within<T: Sendable>(
  _ seconds: Double, _ what: String, _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await body() }
    group.addTask {
      try await Task.sleep(for: .seconds(seconds))
      throw Failure("timed out: \(what)")
    }
    defer { group.cancelAll() }
    guard let first = try await group.next() else { throw Failure("no result: \(what)") }
    return first
  }
}

/// What one client applied: the chain, and every anomaly the client's own ordering would hide.
actor Applied {
  private(set) var chain = ReplayChain()
  private(set) var duplicates = 0
  private(set) var gaps = 0
  private(set) var acknowledgments = 0
  private(set) var resyncs: [String] = []
  private(set) var transients = 0

  var head: Int64 { chain.head }

  func apply(_ envelope: EventEnvelope) throws {
    switch try chain.append(envelope) {
    case .next: acknowledgments += 1
    case .duplicate: duplicates += 1
    case .gap: gaps += 1
    }
  }

  struct Snapshot: Sendable {
    let chain: ReplayChain
    let duplicates: Int
    let gaps: Int
    let acknowledgments: Int
    let resyncs: [String]
  }

  func snapshot() -> Snapshot {
    Snapshot(
      chain: chain, duplicates: duplicates, gaps: gaps, acknowledgments: acknowledgments,
      resyncs: resyncs)
  }

  func resync(_ request: ResyncRequest) { resyncs.append(request.reason.rawValue) }
  func transient() { transients += 1 }
}

struct HelperExit {
  let reason: Process.TerminationReason
  let status: Int32
  let millis: Int
}

/// One signed helper process, driven over stdin and stdout lines.
final class Helper: @unchecked Sendable {
  let process = Process()
  let input = Pipe()
  let output = Pipe()
  var lines: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator

  init(binary: String, arguments: [String], log: String) throws {
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = arguments
    process.standardInput = input
    process.standardOutput = output
    FileManager.default.createFile(atPath: log, contents: nil)
    process.standardError = try FileHandle(forWritingTo: URL(fileURLWithPath: log))
    try process.run()
    lines = output.fileHandleForReading.bytes.lines.makeAsyncIterator()
  }

  func line(_ what: String) async throws -> String {
    guard let text = try await lines.next() else { throw Failure("helper ended before \(what)") }
    return text
  }

  func command(_ text: String) throws {
    try input.fileHandleForWriting.write(contentsOf: Data((text + "\n").utf8))
  }

  /// The envelope a `COMMIT` or `STOP` line carries.
  func envelope(_ prefix: String) async throws -> EventEnvelope {
    let text = try await line(prefix)
    guard text.hasPrefix(prefix + " "), text != prefix + " none" else {
      throw Failure("expected \(prefix), got \(text)")
    }
    return try ReplayWire.decode(String(text.dropFirst(prefix.count + 1)))
  }

  /// Ends stdin, the owner's EOF, and waits for the helper to exit.
  func finish() async -> HelperExit {
    let started = ContinuousClock.now
    try? input.fileHandleForWriting.close()
    let process = process
    await Task.detached { process.waitUntilExit() }.value
    return HelperExit(
      reason: process.terminationReason, status: process.terminationStatus,
      millis: milliseconds(started.duration(to: .now)))
  }
}

struct Assertion: Codable {
  let name: String
  let observed: String
  let passed: Bool
}

var assertions: [Assertion] = []
@MainActor func check(_ name: String, _ passed: Bool, _ observed: @autoclosure () -> String = "") {
  assertions.append(Assertion(name: name, observed: observed(), passed: passed))
  if !passed { print("FAIL \(name): \(observed())") }
}

// MARK: Run

let started = ContinuousClock.now
let root = URL(fileURLWithPath: rootPath, isDirectory: true)
let dataDirectory = root.appendingPathComponent("data", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let identity = try PeerAuthentication.currentIdentity()
let paths = try IPCPaths(directory: dataDirectory, createDirectories: true)
check(
  "client-signed-as-app", identity.signingIdentifier == "com.mehmetcanbudak.memoshi.mac",
  identity.signingIdentifier)

@MainActor func makeClient() throws -> MemoshiClient {
  MemoshiClient(
    configuration: ClientConfiguration(
      dataDirectory: dataDirectory,
      peerPolicy: try PeerPolicy(
        teamID: identity.teamID, identifiers: ["com.mehmetcanbudak.memoshi.memoshid"]),
      client: ClientInfo(name: "Memoshi", version: "replay", build: "1", role: .app)))
}

func consume(_ client: MemoshiClient, into applied: Applied) async throws -> Task<Void, any Error> {
  let stream = try await client.events()
  return Task {
    for try await event in stream {
      switch event {
      case .event(let delivery):
        try await applied.apply(delivery.envelope)
        try await client.acknowledgeApplied(delivery)
      case .resyncRequired(let request):
        await applied.resync(request)
        // A client's first connect sees the empty log, so its head is the whole baseline. A
        // later resync would be a finding: it is recorded and then fails an assertion.
        try await client.completeResync(request, appliedThrough: request.head)
      case .transient:
        await applied.transient()
      }
    }
  }
}

var helperIndex = 0
var helperExits: [(index: Int, exit: HelperExit)] = []
var helperIdentities: [String] = []

@MainActor func startHelper() async throws -> Helper {
  let helper = try Helper(
    binary: daemonPath,
    arguments: ["serve", "--data", dataDirectory.path, "--schema", schemaPath],
    log: root.appendingPathComponent("daemon-\(helperIndex)-stderr.log").path)
  let ready = try await within(30, "helper READY") { try await helper.line("READY") }
  guard ready.hasPrefix("READY ") else { throw Failure("helper said \(ready)") }
  helperIdentities.append(String(ready.dropFirst(6)))
  helperIndex += 1
  return helper
}

var receipts = ReplayChain()
var receiptDuplicates = 0
@MainActor func receipt(_ envelope: EventEnvelope) throws {
  if try receipts.append(envelope) != .next { receiptDuplicates += 1 }
}

var retention = 7
@MainActor func commit(_ helper: Helper) async throws {
  try helper.command("retention \(retention)")
  retention = retention == 365 ? 7 : retention + 1
  try receipt(try await within(30, "COMMIT") { try await helper.envelope("COMMIT") })
}

/// Waits until `applied` has folded every receipt so far.
@MainActor func caughtUp(_ applied: Applied, _ what: String) async throws {
  let target = receipts.head
  try await within(60, what) {
    while await applied.head < target { try await Task.sleep(for: .milliseconds(1)) }
  }
}

var random = Random(state: seed)
let live = try makeClient()
let liveApplied = Applied()
let rebuild = try makeClient()
let rebuildApplied = Applied()
let liveTask = try await consume(live, into: liveApplied)
let rebuildTask = try await consume(rebuild, into: rebuildApplied)

var helper = try await startHelper()
let firstHello = try await live.connect()
try await within(30, "live cold start") {
  while await liveApplied.resyncs.isEmpty { try await Task.sleep(for: .milliseconds(1)) }
}
check("live-cold-start-at-head-0", firstHello.head == 0, "head \(firstHello.head)")
// The rebuild client takes its baseline at the empty log, then parks at seq 0 until the end.
_ = try await rebuild.connect()
try await within(30, "rebuild cold start") {
  while await rebuildApplied.resyncs.isEmpty { try await Task.sleep(for: .milliseconds(1)) }
}
await rebuild.disconnect()
let parkedCursor = await rebuild.status().lastAppliedSeq
check(
  "rebuild-client-parked-at-seq-0", parkedCursor == 0, "cursor \(String(describing: parkedCursor))")

var restarts = 0
var restartCommits = 0
var tokenRotations: [Bool] = []
var reconnectedToNewProcess = 0
var disconnectCycles = 0
var offlineCommits = 0
var raceCommits = 0
let cyclesStarted = ContinuousClock.now

for cycle in 1...cycles {
  if cycle % restartEvery == 0 {
    // The owner ends the helper's life with EOF; the live client stays attached and must
    // reconnect by itself to the next life. A stop commits `system.stopping`.
    let before = try Data(contentsOf: paths.tokenURL)
    let oldPID = await live.status().hello?.daemon.pid
    helperExits.append((helperIndex - 1, await helper.finish()))
    try receipt(try await within(30, "STOP") { try await helper.envelope("STOP") })
    helper = try await startHelper()
    restarts += 1
    tokenRotations.append(try Data(contentsOf: paths.tokenURL) != before)
    // Commits on the new life, made while the live client is reconnecting by itself.
    for _ in 0..<(1 + random.next(2)) {
      try await commit(helper)
      restartCommits += 1
    }
    try await caughtUp(liveApplied, "live after restart \(restarts)")
    let newPID = await live.status().hello?.daemon.pid
    if let oldPID, let newPID, oldPID != newPID { reconnectedToNewProcess += 1 }
    continue
  }
  disconnectCycles += 1
  await live.disconnect()
  let offline = 1 + random.next(3)
  if cycle % 5 == 0 {
    // One commit races the reconnect.
    let connecting = Task { try await live.connect() }
    try await commit(helper)
    raceCommits += 1
    _ = try await within(30, "racing connect") { try await connecting.value }
    for _ in 1..<offline {
      try await commit(helper)
      offlineCommits += 1
    }
  } else {
    for _ in 0..<offline {
      try await commit(helper)
      offlineCommits += 1
    }
    _ = try await live.connect()
  }
  try await caughtUp(liveApplied, "live after cycle \(cycle)")
}
let cycleMillis = milliseconds(cyclesStarted.duration(to: .now))
try await caughtUp(liveApplied, "live before rebuild")

// The seq-0 rebuild: the parked client connects once, replays 1...head and must equal the live fold.
let rebuildStarted = ContinuousClock.now
_ = try await rebuild.connect()
try await caughtUp(rebuildApplied, "rebuild replay")
let rebuildMillis = milliseconds(rebuildStarted.duration(to: .now))

let liveFinal = await liveApplied.snapshot()
let rebuildFinal = await rebuildApplied.snapshot()
let liveChain = liveFinal.chain
let rebuildChain = rebuildFinal.chain
check(
  "live-projection-matches-receipt-chain",
  liveChain.hex == receipts.hex && liveChain.head == receipts.head,
  "live \(liveChain.head) \(liveChain.hex) receipts \(receipts.head) \(receipts.hex)")
check(
  "seq-zero-rebuild-equals-live-projection", rebuildChain.hex == liveChain.hex,
  "live \(liveChain.hex) rebuild \(rebuildChain.hex)")
check(
  "zero-duplicate-or-gap-deliveries",
  liveFinal.duplicates + liveFinal.gaps + rebuildFinal.duplicates + rebuildFinal.gaps == 0,
  "live [\(liveFinal.duplicates), \(liveFinal.gaps)] rebuild [\(rebuildFinal.duplicates), \(rebuildFinal.gaps)]"
)
check(
  "each-durable-fact-applied-then-acknowledged-once-per-client",
  liveFinal.acknowledgments == receipts.count && rebuildFinal.acknowledgments == receipts.count,
  "live \(liveFinal.acknowledgments), rebuild \(rebuildFinal.acknowledgments), expected \(receipts.count)"
)
check(
  "one-cold-start-bootstrap-per-client-and-no-later-resync",
  liveFinal.resyncs == ["coldStart"] && rebuildFinal.resyncs == ["coldStart"],
  "live \(liveFinal.resyncs), rebuild \(rebuildFinal.resyncs)")
check("no-receipt-duplicates", receiptDuplicates == 0, "\(receiptDuplicates)")
check(
  "every-helper-restart-rotated-the-token",
  tokenRotations.count == restarts && tokenRotations.allSatisfy { $0 },
  tokenRotations.map(String.init).joined(separator: " "))
check(
  "automatic-reconnect-reached-each-new-helper-process", reconnectedToNewProcess == restarts,
  "\(reconnectedToNewProcess) of \(restarts)")
check(
  "cycles-run", disconnectCycles + restarts == cycles,
  "disconnect \(disconnectCycles) + restart \(restarts) = \(cycles)")

// The last life ends as the others did; its `system.stopping` joins the receipts.
helperExits.append((helperIndex - 1, await helper.finish()))
try receipt(try await within(30, "final STOP") { try await helper.envelope("STOP") })
let liveState = await live.status().state.rawValue
let liveReachedStop = await liveApplied.head
await live.disconnect()
await rebuild.disconnect()
liveTask.cancel()
rebuildTask.cancel()
check(
  "every-helper-process-exited-naturally-after-owner-eof",
  helperExits.allSatisfy { $0.exit.reason == .exit && $0.exit.status == 0 },
  helperExits.map { "\($0.index):\($0.exit.reason == .exit ? "exit" : "signal")/\($0.exit.status)" }
    .joined(separator: " "))
check(
  "helpers-signed-as-memoshid-same-team",
  helperIdentities.allSatisfy {
    $0.contains("id=com.mehmetcanbudak.memoshi.memoshid") && $0.contains("team=\(identity.teamID)")
  }, "\(helperIdentities.count) helpers")

// A fresh store fold from seq 0, by a separate verify process, must equal the receipts.
let verifier = try Helper(
  binary: daemonPath, arguments: ["verify", "--data", dataDirectory.path],
  log: root.appendingPathComponent("daemon-verify-stderr.log").path)
let fold = try await within(60, "verify") { try await verifier.line("FOLD") }
_ = await verifier.finish()
@MainActor func field(_ name: String) -> String {
  fold.split(separator: " ").first { $0.hasPrefix(name + "=") }.map {
    String($0.dropFirst(name.count + 1))
  } ?? ""
}
check(
  "fresh-store-fold-from-seq-0-matches-receipt-chain",
  field("chain") == receipts.hex && field("head") == String(receipts.head)
    && field("duplicates") == "0" && field("gaps") == "0", fold)
check("store-retains-from-seq-1", field("min") == "1", field("min"))
check("current-schema-opened", field("schema") == "15", "schema \(field("schema"))")

struct Report: Codable {
  var kind = "memoshi-replay-seq-zero-qualification"
  let verdict: String
  let cycles: Int
  let restartEvery: Int
  let seed: UInt64
  let disconnectCycles: Int
  let offlineCommits: Int
  let raceCommits: Int
  let restarts: Int
  let restartCommits: Int
  let expectedHead: Int64
  let expectedChain: String
  let liveChain: String
  let rebuildChain: String
  let liveReachedBeforeFinalStop: Int64
  let liveStateAtEnd: String
  let cycleElapsedMs: Int
  let rebuildElapsedMs: Int
  let totalElapsedMs: Int
  let fold: String
  let clientIdentifier: String
  let teamID: String
  let schemaHash: String
  let scope: String
  let assertions: [Assertion]
}
let passed = assertions.allSatisfy(\.passed)
let report = Report(
  verdict: passed ? "pass" : "fail", cycles: cycles, restartEvery: restartEvery, seed: seed,
  disconnectCycles: disconnectCycles, offlineCommits: offlineCommits, raceCommits: raceCommits,
  restarts: restarts, restartCommits: restartCommits, expectedHead: receipts.head,
  expectedChain: receipts.hex, liveChain: liveChain.hex, rebuildChain: rebuildChain.hex,
  liveReachedBeforeFinalStop: liveReachedStop, liveStateAtEnd: liveState,
  cycleElapsedMs: cycleMillis, rebuildElapsedMs: rebuildMillis,
  totalElapsedMs: milliseconds(started.duration(to: .now)), fold: fold,
  clientIdentifier: identity.signingIdentifier, teamID: identity.teamID,
  schemaHash: firstHello.schemaHash,
  scope:
    "Production MemoshiDaemon, Store, Client and Transport over the real signed same-FD Unix WebSocket carrier on an owned synthetic store, with graceful owner-EOF helper restarts; not real-device, kill/chaos, SMAppService, release, S1 or S2 evidence. Not covered here: UI-only frame focus, descriptor accounting.",
  assertions: assertions)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(report).write(to: URL(fileURLWithPath: outputPath))
print(
  "VERDICT \(report.verdict) cycles=\(cycles) head=\(receipts.head) chain=\(receipts.hex) assertions=\(assertions.count) failed=\(assertions.filter { !$0.passed }.count)"
)
exit(passed ? 0 : 1)
