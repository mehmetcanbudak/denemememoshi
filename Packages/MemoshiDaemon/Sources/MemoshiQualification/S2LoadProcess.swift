import Foundation
import MemoshiDevice
import MemoshiProtocol

/// One S2.12 load run's declared mix, per load process.
package struct S2LoadOptions: Codable, Sendable {
  /// The relay (and its lease authority).
  package var relayPort: Int
  /// Simulated users; each has two devices, an iPhone that runs the conversations and the home
  /// Mac that idle conversations are rebalanced to.
  package var users: Int
  /// Active conversations per user (Chats, Sessions and routine/watch lanes with work).
  package var activePerUser: Int
  /// Idle conversations per user.
  package var idlePerUser: Int
  /// Renewal interval and lease length of an active conversation.
  package var activeRenewMs: Int64
  package var activeTtlMs: Int64
  /// Renewal interval and finite wake lease of an idle one. Zero disables periodic renewal;
  /// a wake still claims `idleTtlMs` and leaves that lease to expire.
  package var idleRenewMs: Int64
  package var idleTtlMs: Int64
  /// Idle conversations per user moved (rebalanced, or woken when idle leases are not held)
  /// once per idle cycle.
  package var movesPerUserPerCycle: Int
  /// How long the steady phase runs.
  package var durationMs: Int64
  /// Claims in flight at once during the initial claim burst.
  package var claimConcurrency: Int

  package init(
    relayPort: Int, users: Int, activePerUser: Int, idlePerUser: Int, activeRenewMs: Int64,
    activeTtlMs: Int64, idleRenewMs: Int64, idleTtlMs: Int64, movesPerUserPerCycle: Int,
    durationMs: Int64, claimConcurrency: Int
  ) {
    self.relayPort = relayPort
    self.users = users
    self.activePerUser = activePerUser
    self.idlePerUser = idlePerUser
    self.activeRenewMs = activeRenewMs
    self.activeTtlMs = activeTtlMs
    self.idleRenewMs = idleRenewMs
    self.idleTtlMs = idleTtlMs
    self.movesPerUserPerCycle = movesPerUserPerCycle
    self.durationMs = durationMs
    self.claimConcurrency = claimConcurrency
  }
}

/// What one load process measured.
package struct S2LoadReport: Codable, Sendable {
  package var options: S2LoadOptions
  package var devices: Int
  package var conversations: Int
  /// Client leases scheduled for periodic renewal at report time, not all live authority leases.
  package var periodicallyRenewedLeases: Int
  package var claimPhaseSeconds: Double
  package var steadyStartMonotonicNs: UInt64
  package var steadyPhaseSeconds: Double
  package var claims: S2Distribution
  package var renewals: S2Distribution
  package var lateness: S2Distribution
  package var latenessFirstWindow: S2Distribution
  package var latenessLastWindow: S2Distribution
  package var moves: S2Distribution
  package var renewOperations: Int
  /// Steady-phase authority RPC attempts, including failed and retried requests.
  package var authorityOperations: Int
  package var renewalsPerSecond: Double
  package var operationsPerSecond: Double
  package var loadInducedExpiries: Int
  package var fencedRenewals: Int
  package var recoveryClaims: Int
  package var claimFailures: Int
  package var moveFailures: Int
  package var errors: Int
  package var maximumInFlight: Int
  package var conversationKinds: [String: Int]
  package var activeConversationKinds: [String: Int]
  package var idleConversationKinds: [String: Int]
  package var requestAttempts: Int
  package var transportFailures: Int
  package var moveRetryAttempts: Int
  package var authorityPersistence = "synchronized-append-journal"
  package var pushMeasurement = "not implemented; no APNs traffic or provider quota claimed"
}

/// `memoshi-qualification s2-load`: drives the relay's lease authority with a declared mix of
/// active and idle conversations from many simulated devices, each with its own authenticated
/// relay connection, and reports latencies, scheduling lateness and expiry/fencing outcomes.
package enum S2LoadProcess {
  package static func samplesDirectory(for output: URL) -> URL {
    output.deletingPathExtension().appendingPathExtension("samples")
  }

  package static func run(options: S2LoadOptions, output: URL) async -> Int32 {
    raiseDescriptorLimit()
    do {
      guard !FileManager.default.fileExists(atPath: output.path),
        !FileManager.default.fileExists(atPath: samplesDirectory(for: output).path)
      else { throw DriverError.invalid("load output already exists") }
      let runner = try await S2LoadRunner.connect(options)
      let report = try await runner.run()
      try JSONLines.prettyEncoder.encode(report).write(to: output, options: .withoutOverwriting)
      try await runner.writeSamples(to: samplesDirectory(for: output))
      LineWriter.standardOutput.write(
        [
          "event": JSONValue.string("loadDone"),
          "renewals": .integer(Int64(report.renewOperations)),
          "expiries": .integer(Int64(report.loadInducedExpiries)),
        ])
      await runner.close()
      return report.loadInducedExpiries == 0 && report.fencedRenewals == 0
        && report.claimFailures == 0 && report.moveFailures == 0 && report.errors == 0 ? 0 : 2
    } catch {
      LineWriter.standardError.text("s2-load: \(error)")
      return 1
    }
  }
}

private struct S2LoadOperation: Sendable {
  var phase: String
  var messageID: String
  var deviceID: String
  var conversationID: String
  var operation: String
  var epoch: Int64?
  var started: UInt64
  var finished: UInt64
  var outcome: String
}

private actor S2LoadRunner {
  private struct Lease {
    let id: ConversationID
    let user: Int
    var holder: Int
    var epoch: Int64 = 0
    var active: Bool
    var kind: String
    var held = false
    var nextDue: UInt64 = 0
    var inFlight = false
  }

  private let options: S2LoadOptions
  private let clients: [[RelayClient]]
  private var leases: [Lease] = []
  private var claimRTT: [UInt64] = []
  private var renewRTT: [UInt64] = []
  private var lateness: [(at: UInt64, late: UInt64)] = []
  private var moveTimes: [UInt64] = []
  private var expiries = 0
  private var fenced = 0
  private var recoveries = 0
  private var claimFailures = 0
  private var moveFailures = 0
  private var errors = 0
  private var inFlight = 0
  private var maximumInFlight = 0
  private var running = true
  private var measuring = false
  private var authorityOperations = 0
  private var operations: [S2LoadOperation] = []
  private var moveRetryAttempts = 0

  private init(options: S2LoadOptions, clients: [[RelayClient]]) {
    self.options = options
    self.clients = clients
  }

  static func connect(_ options: S2LoadOptions) async throws -> S2LoadRunner {
    var identities: [[DeviceIdentity]] = []
    var peers: [S2Peer] = []
    for user in 0..<options.users {
      var devices: [DeviceIdentity] = []
      for (index, name) in ["iPhone", "Mac"].enumerated() {
        let identity = try DeviceIdentity.generate(
          name: "\(name) \(user)", platform: index == 0 ? .iphone : .mac)
        devices.append(identity)
        peers.append(S2Peer(identity.peer))
      }
      identities.append(devices)
    }
    // Only the owned parent's private pipe can enroll this public roster. A remote relay
    // hello cannot register a key or grant group authority.
    LineWriter.standardOutput.write([
      "event": .string("loadEnrollment"), "groupId": .string(DeviceULID.make()),
      "peers": try JSONValue.parse(JSONLines.encoder.encode(peers)),
    ])
    guard readLine() == "enrolled" else {
      throw DriverError.invalid("Owned parent did not confirm load enrollment")
    }
    var clients: [[RelayClient]] = []
    for devices in identities {
      var connections: [RelayClient] = []
      for identity in devices {
        connections.append(
          try await RelayClient.connect(port: options.relayPort, identity: identity) { $0.close() })
      }
      clients.append(connections)
    }
    return S2LoadRunner(options: options, clients: clients)
  }

  func close() {
    for client in clients.flatMap({ $0 }) { client.close() }
  }

  private func now() -> UInt64 { DeviceClock.monotonicNanoseconds() }

  private func interval(_ lease: Lease) -> Int64 {
    lease.active ? options.activeRenewMs : options.idleRenewMs
  }

  private func ttl(_ lease: Lease) -> Int64 {
    lease.active ? options.activeTtlMs : options.idleTtlMs
  }

  private func request(_ client: RelayClient, _ body: DeviceMessageBody) async throws
    -> DeviceMessageBody?
  {
    let messageID = try DeviceULID.next()
    let message = DeviceMessage(
      msgId: messageID, from: .device(client.deviceID), to: .authority,
      sentAt: DeviceClock.wallMilliseconds(), body: body)
    if measuring { authorityOperations += 1 }
    var operation: String
    var conversation: ConversationID
    var epoch: Int64?
    switch body {
    case .leaseClaim(let claim):
      operation = "claim"
      conversation = claim.conversationId
      epoch = claim.expectedEpoch
    case .leaseRenew(let renew):
      operation = "renew"
      conversation = renew.conversationId
      epoch = renew.epoch
    case .leaseRelease(let release):
      operation = "release"
      conversation = release.conversationId
      epoch = release.epoch
    default: throw DriverError.invalid("undeclared authority load operation")
    }
    let phase = measuring ? "steady" : "initial-claim"
    let started = now()
    do {
      let reply = try await client.authority(message)?.body
      let outcome: String
      switch reply {
      case .leaseClaimResult(let result): outcome = result.granted ? "granted" : "claim-denied"
      case .leaseRenewResult(let result): outcome = result.renewed ? "renewed" : "renewal-denied"
      case nil: outcome = "release-sent-unacknowledged"
      default: outcome = "unexpected-reply"
      }
      operations.append(
        S2LoadOperation(
          phase: phase, messageID: messageID.rawValue, deviceID: client.deviceID.rawValue,
          conversationID: conversation.rawValue, operation: operation, epoch: epoch,
          started: started, finished: now(), outcome: outcome))
      return reply
    } catch {
      operations.append(
        S2LoadOperation(
          phase: phase, messageID: messageID.rawValue, deviceID: client.deviceID.rawValue,
          conversationID: conversation.rawValue, operation: operation, epoch: epoch,
          started: started, finished: now(), outcome: "transport-failure"))
      throw error
    }
  }

  func run() async throws -> S2LoadReport {
    for user in 0..<options.users {
      for index in 0..<(options.activePerUser + options.idlePerUser) {
        let kind = ["chat", "session", "routine-lane", "watch-lane"][index % 4]
        let prefix = kind == "chat" ? "cht" : kind == "session" ? "ses" : "lan"
        leases.append(
          Lease(
            id: try ConversationID(prefix + "_" + DeviceULID.make()), user: user, holder: 0,
            active: index < options.activePerUser, kind: kind))
      }
    }
    // The initial claim burst: every lease the policy holds, bounded concurrency.
    let claimStarted = now()
    let toClaim = leases.indices.filter { leases[$0].active || options.idleRenewMs > 0 }
    let limit = max(options.claimConcurrency, 1)
    await withTaskGroup(of: Void.self) { group in
      var next = 0
      while next < min(limit, toClaim.count) {
        let index = toClaim[next]
        next += 1
        group.addTask { await self.claim(index, holder: 0) }
      }
      while await group.next() != nil {
        guard next < toClaim.count else { continue }
        let index = toClaim[next]
        next += 1
        group.addTask { await self.claim(index, holder: 0) }
      }
    }
    let claimSeconds = Double(now() - claimStarted) / 1e9
    // Stagger the first renewals uniformly over each interval.
    let start = now()
    measuring = true
    for index in leases.indices where leases[index].held {
      let period = UInt64(interval(leases[index])) * 1_000_000
      leases[index].nextDue = start + UInt64.random(in: 0..<max(period, 1))
    }
    let end = start + UInt64(options.durationMs) * 1_000_000
    let cycle = UInt64(max(options.idleRenewMs, options.activeRenewMs * 5)) * 1_000_000
    var nextCycle = start + cycle
    while now() < end {
      let tick = now()
      for index in leases.indices
      where leases[index].held && !leases[index].inFlight && leases[index].nextDue <= tick {
        leases[index].inFlight = true
        let due = leases[index].nextDue
        leases[index].nextDue += UInt64(interval(leases[index])) * 1_000_000
        begin()
        Task { await self.renew(index, due: due) }
      }
      if tick >= nextCycle {
        nextCycle += cycle
        moveIdle()
      }
      try await Task.sleep(for: .milliseconds(2))
    }
    running = false
    let drain = now() + 5_000_000_000
    while inFlight > 0, now() < drain { try await Task.sleep(for: .milliseconds(5)) }
    guard inFlight == 0 else { throw DriverError.timeout("load operations drain") }
    let steadySeconds = Double(now() - start) / 1e9
    measuring = false
    let window = UInt64(min(options.durationMs / 4, 10_000)) * 1_000_000
    return S2LoadReport(
      options: options, devices: clients.count * 2, conversations: leases.count,
      periodicallyRenewedLeases: leases.filter(\.held).count, claimPhaseSeconds: claimSeconds,
      steadyStartMonotonicNs: start,
      steadyPhaseSeconds: steadySeconds,
      claims: S2Distribution(claimRTT), renewals: S2Distribution(renewRTT),
      lateness: S2Distribution(lateness.map(\.late)),
      latenessFirstWindow: S2Distribution(lateness.filter { $0.at < start + window }.map(\.late)),
      latenessLastWindow: S2Distribution(lateness.filter { $0.at >= end - window }.map(\.late)),
      moves: S2Distribution(moveTimes), renewOperations: renewRTT.count,
      authorityOperations: authorityOperations,
      renewalsPerSecond: Double(renewRTT.count) / steadySeconds,
      operationsPerSecond: Double(authorityOperations) / steadySeconds,
      loadInducedExpiries: expiries, fencedRenewals: fenced, recoveryClaims: recoveries,
      claimFailures: claimFailures, moveFailures: moveFailures, errors: errors,
      maximumInFlight: maximumInFlight,
      conversationKinds: Dictionary(grouping: leases, by: \.kind).mapValues(\.count),
      activeConversationKinds: Dictionary(grouping: leases.filter(\.active), by: \.kind).mapValues(
        \.count),
      idleConversationKinds: Dictionary(grouping: leases.filter { !$0.active }, by: \.kind)
        .mapValues(\.count),
      requestAttempts: operations.count,
      transportFailures: operations.lazy.filter { $0.outcome == "transport-failure" }.count,
      moveRetryAttempts: moveRetryAttempts)
  }

  /// Keeps the observations from which the report's distributions were calculated.
  func writeSamples(to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    try Self.writeDurations(claimRTT, to: directory.appendingPathComponent("claims.csv"))
    try Self.writeDurations(renewRTT, to: directory.appendingPathComponent("renewals.csv"))
    try Self.writeDurations(moveTimes, to: directory.appendingPathComponent("moves.csv"))
    var csv = "monotonic_ns,lateness_ns\n"
    csv.reserveCapacity(40 * lateness.count + csv.utf8.count)
    for sample in lateness {
      csv.append(String(sample.at))
      csv.append(",")
      csv.append(String(sample.late))
      csv.append("\n")
    }
    try Data(csv.utf8).write(
      to: directory.appendingPathComponent("scheduler.csv"), options: .withoutOverwriting)
    var attempts =
      "phase,message_id,device_id,conversation_id,operation,expected_epoch,started_monotonic_ns,finished_monotonic_ns,outcome\n"
    for sample in operations {
      attempts +=
        "\(sample.phase),\(sample.messageID),\(sample.deviceID),\(sample.conversationID),"
        + "\(sample.operation),\(sample.epoch.map(String.init) ?? ""),\(sample.started),\(sample.finished),\(sample.outcome)\n"
    }
    try Data(attempts.utf8).write(
      to: directory.appendingPathComponent("authority-attempts.csv"), options: .withoutOverwriting)
  }

  private static func writeDurations(_ values: borrowing [UInt64], to path: URL) throws {
    var csv = "duration_ns\n"
    csv.reserveCapacity(24 * values.count + csv.utf8.count)
    for index in values.indices {
      csv.append(String(values[index]))
      csv.append("\n")
    }
    try Data(csv.utf8).write(to: path, options: .withoutOverwriting)
  }

  private func begin() {
    inFlight += 1
    maximumInFlight = max(maximumInFlight, inFlight)
  }

  private func claim(_ index: Int, holder: Int) async {
    begin()
    defer { inFlight -= 1 }
    let lease = leases[index]
    let started = now()
    do {
      guard
        case .leaseClaimResult(let result)? = try await request(
          clients[lease.user][holder],
          .leaseClaim(
            LeaseClaim(
              conversationId: lease.id, expectedEpoch: lease.epoch == 0 ? nil : lease.epoch,
              expiresAt: DeviceClock.wallMilliseconds() + ttl(lease)))), result.granted
      else {
        claimFailures += 1
        return
      }
      claimRTT.append(now() - started)
      leases[index].epoch = result.epoch
      leases[index].holder = holder
      leases[index].held = true
    } catch {
      errors += 1
    }
  }

  private func renew(_ index: Int, due: UInt64) async {
    defer {
      inFlight -= 1
      leases[index].inFlight = false
    }
    let started = now()
    lateness.append((started, started > due ? started - due : 0))
    let lease = leases[index]
    do {
      guard
        case .leaseRenewResult(let result)? = try await request(
          clients[lease.user][lease.holder],
          .leaseRenew(
            LeaseRenew(
              conversationId: lease.id, epoch: lease.epoch,
              expiresAt: DeviceClock.wallMilliseconds() + ttl(lease))))
      else {
        errors += 1
        return
      }
      renewRTT.append(now() - started)
      guard !result.renewed else { return }
      if result.epoch == lease.epoch { expiries += 1 } else { fenced += 1 }
      // Recover: claim the next epoch so the run continues measuring.
      leases[index].epoch = result.epoch
      leases[index].held = false
      guard running else { return }
      recoveries += 1
      await claim(index, holder: lease.holder)
    } catch {
      errors += 1
    }
  }

  /// Once per idle cycle, each user's next idle conversations go to the home Mac: release by
  /// the iPhone, then claim by the Mac (retrying while the release is still in flight). With
  /// unheld idle leases, the Mac claims a woken conversation instead.
  private func moveIdle() {
    for user in 0..<options.users {
      let candidates = leases.indices.filter {
        leases[$0].user == user && !leases[$0].active && leases[$0].holder == 0
          && !leases[$0].inFlight
      }
      for index in candidates.prefix(options.movesPerUserPerCycle) {
        leases[index].inFlight = true
        begin()
        Task { await self.move(index) }
      }
    }
  }

  private func move(_ index: Int) async {
    defer {
      inFlight -= 1
      leases[index].inFlight = false
    }
    let lease = leases[index]
    let started = now()
    do {
      if lease.held {
        _ = try await request(
          clients[lease.user][0],
          .leaseRelease(LeaseRelease(conversationId: lease.id, epoch: lease.epoch, lastRseq: 0)))
      }
      let deadline = started + 2_000_000_000
      var attempted = false
      while now() < deadline {
        if attempted { moveRetryAttempts += 1 }
        attempted = true
        guard
          case .leaseClaimResult(let result)? = try await request(
            clients[lease.user][1],
            .leaseClaim(
              LeaseClaim(
                conversationId: lease.id, expectedEpoch: lease.epoch == 0 ? nil : lease.epoch,
                expiresAt: DeviceClock.wallMilliseconds() + ttl(lease))))
        else { break }
        if result.granted {
          moveTimes.append(now() - started)
          leases[index].epoch = result.epoch
          leases[index].holder = 1
          leases[index].held = options.idleRenewMs > 0 || lease.active
          if leases[index].held {
            leases[index].nextDue = now() + UInt64(interval(leases[index])) * 1_000_000
          }
          return
        }
        try await Task.sleep(for: .milliseconds(1))
      }
      moveFailures += 1
    } catch {
      errors += 1
    }
  }
}

/// n, percentiles and extremes of a set of nanosecond samples, reported in milliseconds.
package struct S2Distribution: Codable, Sendable {
  package var n: Int
  package var p50Ms: Double?
  package var p95Ms: Double?
  package var p99Ms: Double?
  package var minMs: Double?
  package var maxMs: Double?
  package var meanMs: Double?

  package init(_ samples: [UInt64]) {
    n = samples.count
    guard !samples.isEmpty else { return }
    let sorted = samples.sorted()
    func at(_ quantile: Double) -> Double {
      // Nearest-rank percentile.
      let rank = Int((quantile * Double(sorted.count)).rounded(.up))
      return Double(sorted[min(max(rank, 1), sorted.count) - 1]) / 1e6
    }
    p50Ms = at(0.50)
    p95Ms = at(0.95)
    p99Ms = at(0.99)
    minMs = Double(sorted[0]) / 1e6
    maxMs = Double(sorted[sorted.count - 1]) / 1e6
    meanMs = Double(sorted.reduce(0, +)) / Double(sorted.count) / 1e6
  }
}
