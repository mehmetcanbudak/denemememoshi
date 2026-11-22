import CryptoKit
import Darwin
import Foundation
import MemoshiProtocol
import MemoshiRuntime
import MemoshiStore

/// Development-machine, synthetic-provider measurements; never an S1 reference-box verdict.
package struct S1Options: Sendable {
  package var workDirectory: URL
  package var outputDirectory: URL
  package var executable: URL
  package var openSamples: Int
  package var timeout: Duration
  package var arguments: [String]

  package init(
    workDirectory: URL, outputDirectory: URL, executable: URL, openSamples: Int = 3,
    timeout: Duration = .seconds(300), arguments: [String] = []
  ) {
    self.workDirectory = workDirectory
    self.outputDirectory = outputDirectory
    self.executable = executable
    self.openSamples = openSamples
    self.timeout = timeout
    self.arguments = arguments
  }
}

/// One raw observation. Nanoseconds are integer clock deltas, bytes are not rounded to MB.
package struct S1Sample: Codable, Sendable {
  package var series: String
  package var life: Int
  package var conversation: String
  package var value: Int64
  package var unit: String
}

/// Nearest-rank percentiles; an empty series stays unmeasured, not zero.
package struct S1Distribution: Codable, Equatable, Sendable {
  package var n: Int
  package var p50: Int64?
  package var p95: Int64?
  package var minimum: Int64?
  package var maximum: Int64?

  package init(_ values: [Int64]) {
    let sorted = values.sorted()
    n = sorted.count
    p50 = ChaosSummary.percentile(sorted, 0.50)
    p95 = ChaosSummary.percentile(sorted, 0.95)
    minimum = sorted.first
    maximum = sorted.last
  }
}

/// Per-turn logical event storage, excluding shared SQLite pages, indexes and WAL framing.
package struct S1TurnBytes: Codable, Sendable {
  package var requestId: String
  package var conversationId: String
  package var taskId: String
  package var status: String
  package var events: Int
  /// The exact ProtocolCoding JSON payload representation stored in events.payload.
  package var payloadBytes: Int64
  /// Canonical replay-envelope JSON bytes, without newline or JSON-RPC notification wrapper.
  package var envelopeBytes: Int64
  package var types: [String: Int]
}

/// A self-reading of this host process, not the driver's RSS or a fabricated per-Harness cost.
package struct S1ProcessReading: Codable, Sendable {
  package var pid: Int32
  package var openThreads: Int
  package var liveRuns: Int
  package var awaitingModels: Int
  package var footprintBytes: Int64?
  package var residentBytes: Int64?
  package var maximumResidentBytes: Int64?
  package var footprintError: Int32?
  package var turns: [TurnState]
}

package enum S1Clock {
  package static func nanoseconds(since start: ContinuousClock.Instant) -> Int64 {
    let elapsed = ContinuousClock.now - start
    return elapsed.components.seconds * 1_000_000_000
      + elapsed.components.attoseconds / 1_000_000_000
  }
}

package enum S1Footprint {
  package static func read() -> (footprint: Int64?, resident: Int64?, peak: Int64?, error: Int32?) {
    // Same installed-SDK pattern as Runtime/Qualification/CodeModeWorkload.swift Footprint.read.
    var information = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
    let capacity = Int(count)
    let result = withUnsafeMutablePointer(to: &information) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    var usage = rusage()
    let peak = getrusage(RUSAGE_SELF, &usage) == 0 ? Int64(usage.ru_maxrss) : nil
    guard result == KERN_SUCCESS else { return (nil, nil, peak, result) }
    return (Int64(information.phys_footprint), Int64(information.resident_size), peak, nil)
  }
}

/// Mutable evidence survives scenario errors, so the retained report explains partial runs.
package actor S1Results {
  package var samples: [S1Sample] = []
  package var turns: [S1TurnBytes] = []
  package var checks: [String: Int] = [:]
  package var failures: [String] = []
  package var exits: [String] = []
  package var scan: CanaryScanReport?
  package var provider: S1ProviderSummary?

  package init() {}
  package func add(_ sample: S1Sample) { samples.append(sample) }
  package func turn(_ value: S1TurnBytes) { turns.append(value) }
  package func check(_ name: String, _ count: Int = 1) { checks[name, default: 0] += count }
  package func fail(_ message: String) { failures.append(message) }
  package func exit(_ value: String) { exits.append(value) }
  package func audit(_ value: CanaryScanReport) { scan = value }
  package func provider(_ value: S1ProviderSummary) { provider = value }

  package func write(
    to output: URL, executable: URL, arguments: [String], scanner: CanaryScanner
  ) throws {
    let directory = output.appendingPathComponent("samples", isDirectory: true)
    try QualificationPaths.create(directory)
    let grouped = Dictionary(grouping: samples, by: \.series)
    let perConversation = Dictionary(
      grouping: grouped["conversation-open-resume-history"] ?? [], by: \.conversation
    ).mapValues { S1Distribution($0.map(\.value)) }
    var distributions: [String: S1Distribution] = [:]
    for (name, values) in grouped {
      distributions[name] = S1Distribution(values.map(\.value))
      let csv =
        "sample,life,conversation,value,unit\n"
        + values.enumerated().map { index, value in
          "\(index + 1),\(value.life),\(value.conversation),\(value.value),\(value.unit)"
        }.joined(separator: "\n") + "\n"
      try Data(csv.utf8).write(
        to: directory.appendingPathComponent(name + ".csv"), options: .withoutOverwriting)
    }
    let turnCSV =
      "requestId,conversationId,taskId,status,events,payloadBytes,envelopeBytes\n"
      + turns.map {
        "\($0.requestId),\($0.conversationId),\($0.taskId),\($0.status),\($0.events),\($0.payloadBytes),\($0.envelopeBytes)"
      }.joined(separator: "\n") + "\n"
    try Data(turnCSV.utf8).write(
      to: directory.appendingPathComponent("event-bytes-per-turn.csv"), options: .withoutOverwriting
    )
    func summaryRow(_ name: String, _ conversation: String, _ value: S1Distribution, _ unit: String)
      -> String
    {
      [
        name, conversation, String(value.n), value.p50.map { String($0) } ?? "",
        value.p95.map { String($0) } ?? "", value.minimum.map { String($0) } ?? "",
        value.maximum.map { String($0) } ?? "", unit,
      ].joined(separator: ",")
    }
    var summaryRows = ["series,conversation,n,p50,p95,min,max,unit"]
    for (name, distribution) in distributions.sorted(by: { $0.key < $1.key }) {
      summaryRows.append(summaryRow(name, "all", distribution, grouped[name]?.first?.unit ?? ""))
    }
    for (conversation, distribution) in perConversation.sorted(by: { $0.key < $1.key }) {
      summaryRows.append(
        summaryRow("conversation-open-resume-history", conversation, distribution, "ns"))
    }
    try Data((summaryRows.joined(separator: "\n") + "\n").utf8).write(
      to: directory.appendingPathComponent("summary.csv"), options: .withoutOverwriting)
    let outputScan = try scanner.scan([output])
    if scan == nil { scan = outputScan } else { scan?.merge(outputScan) }
    if !outputScan.hits.isEmpty {
      failures.append("S1 retained logs/artifacts contain a provider-bearer canary")
    }
    struct Report: Encodable {
      let evidenceClass: String
      let referenceQualification: Bool
      let passedInvariants: Bool
      let protocolBoundary: String
      let unexercised: [String]
      let boundaries: [String: String]
      let distributions: [String: S1Distribution]
      let perConversationOpenResume: [String: S1Distribution]
      let units: [String: String]
      let checks: [String: Int]
      let failures: [String]
      let processExits: [String]
      let turns: [S1TurnBytes]
      let scan: CanaryScanReport?
      let provider: S1ProviderSummary?
      let host: [String: String]
      let arguments: [String]
    }
    let report = Report(
      evidenceClass: "development-machine / scripted loopback provider / pinned-candidate runtime",
      referenceQualification: false, passedInvariants: failures.isEmpty,
      protocolBoundary:
        "Production JSONRPCCodec and typed request/result/event shapes over driver-owned stdin/stdout; actual Store + RuntimeAdapter + PiDurable/PiAI. NOT DaemonServer/RPCSession or authenticated Unix WebSocket.",
      unexercised: [
        "Genuine helper/app signature, same-FD peer authentication, hello, Unix WebSocket, RPCSession subscription/focus/backpressure. DaemonServer requires the sealed helper identity before storage; no qualifying signed test fixture is supplied and this command never changes signing or bypasses that guard.",
        "Reference-box budgets, slice-N qualification, real-model behavior, cloud providers, physical devices and production composition.",
        "Ten-minute idle expiry and live conversation deletion: this command does not wait out idle expiry; no conversation-delete API is implemented by the development runtime.",
        "Pure SQLite COMMIT syscall time: send admission includes Pi admission and projection; retention COMMIT under load includes the Store actor, transaction and durable event publication.",
        "Per-Harness exclusive allocation: process footprint deltas include shared caches, allocator retention, SQLite and the runtime. No allocation attribution is inferred.",
      ],
      boundaries: [
        "conversation-open-resume-history":
          "Host ContinuousClock immediately before runtime.history until it returns, on first access to a settled persisted conversation in a fresh process after runtime.start/resume/modelsList. Includes local lease, Pi SQLite open, Harness activation/resume and a bounded (200) history read; excludes process startup, model discovery, JSON encoding and pipe transit. before/after openThreads must advance by exactly one.",
        "send-admission-eight":
          "Host ContinuousClock immediately before runtime.send until its durable receipt returns for eight concurrently issued original requests, one per conversation. Includes actual Pi submission + application projections; excludes answer generation completion, JSON encoding and pipe transit.",
        "retention-commit-eight-streams":
          "Host ContinuousClock around Store.setEventRetentionDays alternating 30/31 so every sample commits exactly one settings event, while all eight actual provider SSE streams remain open and their final frames are held. Each stream paces the deterministic answer suffix at one ASCII character/20ms until release; all eight must emit additional text during the batch. Includes actor queue/SQLite transaction/durable bus publication. A 1ms inter-sample sleep is outside the clock interval. Not a direct measurement of internal Pi commit duration or real-model throughput.",
        "footprint":
          "TASK_VM_INFO phys_footprint and resident_size read inside the owned runtime-host PID. 10-open-4-streaming samples require status openThreads=10/liveRuns=4, four observed live text deltas and four provider streams held before final completion. All four must emit additional paced text during the 20-sample interval (10ms between samples). ru_maxrss is a separate process lifetime peak in bytes on Darwin. Provider and driver are outside the measured host process.",
        "event-bytes":
          "Per settled turn, paginated Store.replay at a fixed head, grouped by scope.taskId. payloadBytes is ProtocolCoding-encoded Event.payload (events.payload TEXT representation); envelopeBytes is canonical replay EventEnvelope JSON without newline or notification wrapper. Excludes SQLite B-tree/index/WAL allocation and lifecycle events not bound to a turn. Exact raw envelopes retained in event-log.jsonl. No durable message.delta or synthetic transcript marker is permitted.",
        "restart-ready":
          "Driver ContinuousClock from posix_spawn return to receiving host ready after real runtime.start/resume. Not scheduler throughput or reference-box qualification.",
        "canary-scan":
          "Raw scan of the owned work root before deletion and every retained output file after logs close and CSV serialization. The final report is also scanned in memory before its sole write. Covers the scanner's raw/JSON/percent/base64/hex forms; compressed encodings and system-wide logs are not inspected.",
      ],
      distributions: distributions, perConversationOpenResume: perConversation,
      units: grouped.mapValues { $0.first?.unit ?? "unmeasured" }, checks: checks,
      failures: failures, processExits: exits, turns: turns, scan: scan, provider: provider,
      host: Self.metadata(executable: executable), arguments: arguments)
    let encoded = try JSONLines.prettyEncoder.encode(report)
    var reportScan = CanaryScanReport()
    scanner.scanBytes(encoded, path: "s1-measurements.json", into: &reportScan)
    guard reportScan.hits.isEmpty else {
      throw DriverError.invalid(
        "S1 final report contained a provider-bearer canary and was not written")
    }
    try encoded.write(
      to: output.appendingPathComponent("s1-measurements.json"), options: .withoutOverwriting)
  }

  private static func metadata(executable: URL) -> [String: String] {
    func systemString(_ key: String) -> String {
      var size = 0
      guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return "unavailable" }
      var bytes = [CChar](repeating: 0, count: size)
      guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return "unavailable" }
      return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    let process = ProcessInfo.processInfo
    var values = [
      "recordedAt": ISO8601DateFormatter().string(from: Date()),
      "os": process.operatingSystemVersionString,
      "model": systemString("hw.model"), "architecture": systemString("hw.machine"),
      "memoryBytes": String(process.physicalMemory),
      "activeCPUs": String(process.activeProcessorCount), "cpus": String(process.processorCount),
      "thermalState": String(describing: process.thermalState),
      "lowPowerMode": String(process.isLowPowerModeEnabled),
      "systemUptimeSeconds": String(process.systemUptime),
      "applicationSchema": String(Store.schemaVersion),
      "declaredPiCandidate": PiDevelopmentSnapshot.revision,
    ]
    #if DEBUG
      values["buildConfiguration"] = "Debug"
    #else
      values["buildConfiguration"] = "Release"
    #endif
    if let bytes = try? Data(contentsOf: executable, options: .mappedIfSafe) {
      values["executableSHA256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }
        .joined()
    }
    return values
  }
}
