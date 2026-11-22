import Darwin
import Foundation
import MemoshiDevice
import MemoshiProtocol

/// How one S2 batch runs.
package struct S2Options: Sendable {
  package var workDirectory: URL
  package var outputDirectory: URL
  package var executable: URL
  /// Small counts for a smoke run.
  package var quick: Bool
  /// Wait out a real 5-minute QR lifetime once.
  package var realExpiry: Bool
  /// Run the S2.12 authority-load matrix.
  package var load: Bool
  /// Opt into actual Bonjour advertisement/discovery on the current host's local network.
  package var bonjour: Bool

  package init(
    workDirectory: URL, outputDirectory: URL, executable: URL, quick: Bool, realExpiry: Bool,
    load: Bool, bonjour: Bool = false
  ) {
    self.workDirectory = workDirectory
    self.outputDirectory = outputDirectory
    self.executable = executable
    self.quick = quick
    self.realExpiry = realExpiry
    self.load = load
    self.bonjour = bonjour
  }
}

/// Everything one batch measured: raw nanosecond samples per series, counters, informational
/// notes and the failures that disqualify the batch.
actor S2Results {
  var series: [String: [UInt64]] = [:]
  var counters: [String: Int] = [:]
  var notes: [String] = []
  var failures: [String] = []
  var loads: [String: [S2LoadReport]] = [:]
  var relays: [String: S2RelaySummary] = [:]
  var storage: S2Storage?
  var revocation: (device: String, at: Int64, conversation: String)?

  func add(_ name: String, _ sample: UInt64) { series[name, default: []].append(sample) }
  func add(_ name: String, _ samples: [UInt64]) { series[name, default: []] += samples }
  func count(_ name: String, _ delta: Int = 1) { counters[name, default: 0] += delta }
  func set(_ name: String, _ value: Int) { counters[name] = value }
  func note(_ text: String) { notes.append(text) }
  func fail(_ text: String) { failures.append(text) }
  func load(_ name: String, _ reports: [S2LoadReport]) { loads[name] = reports }
  func describeStorage(_ storage: S2Storage) { self.storage = storage }
  func probeStorage(_ probe: S2SyncProbe) { storage?.probes.append(probe) }
  func revoked(_ device: String, at time: Int64, conversation: String) {
    revocation = (device, time, conversation)
  }

  /// The prefix of every series and counter the stress phase records.
  static let stressPrefix = "stress."
  /// The prefix of every series and counter of the scenarios that run once, after the stress
  /// phase and in its group: the QR negative checks, offline-approval expiry, revocation, the
  /// late QR check and restart recovery. None of them is a qualified number (D133).
  static let oncePrefix = "once."

  /// Splits names into the qualified phase's (with the batch-wide ones) and, without their
  /// prefix, the stress phase's and the once-only scenarios'.
  static func phases<Value>(_ values: [String: Value]) -> (
    qualified: [String: Value], stress: [String: Value], once: [String: Value]
  ) {
    var qualified: [String: Value] = [:]
    var stress: [String: Value] = [:]
    var once: [String: Value] = [:]
    for (name, value) in values {
      if name.hasPrefix(stressPrefix) {
        stress[String(name.dropFirst(stressPrefix.count))] = value
      } else if name.hasPrefix(oncePrefix) {
        once[String(name.dropFirst(oncePrefix.count))] = value
      } else {
        qualified[name] = value
      }
    }
    return (qualified, stress, once)
  }

  /// Admits a relay's own summary: its journal closed cleanly and, where it kept a grant log
  /// (the main relay must), its authority never issued one conversation epoch twice. The load
  /// relays keep none, so they report no duplicate count. The main relay must also bear out
  /// the revocation scenario from its own grant log and counters: the revoked device held a
  /// lease before its revocation and was granted none from then on, another device was granted
  /// its conversation
  /// at exactly the next epoch, and the relay refused at least as many connections as revoked
  /// probes the driver saw it refuse (the hello, and each raw claim or renewal it ended
  /// unanswered), each of which already raised its count by exactly one during the probe.
  func relay(_ name: String, _ summary: S2RelaySummary) throws {
    relays[name] = summary
    try summary.journal.requireClosed()
    guard name != "main" || summary.duplicateGrants != nil else {
      throw DriverError.invalid("S2 main relay kept no grant log")
    }
    guard (summary.duplicateGrants ?? 0) == 0 else {
      throw DriverError.invalid("S2 authority issued one conversation epoch twice")
    }
    guard name == "main", let revocation else { return }
    let own = summary.grantLog.filter { $0.runner.rawValue == revocation.device }
    let late = own.filter { $0.grantedAt >= revocation.at }.count
    guard late == 0 else {
      counters[Self.oncePrefix + "revoke.claim.accepted", default: 0] += late
      throw DriverError.invalid("S2 authority granted a lease to the revoked device")
    }
    guard !own.isEmpty else {
      throw DriverError.invalid("S2 revoked device held no lease before its revocation")
    }
    let refusedByRelay = [
      "revoke.relay.refused", "revoke.claim.connectionClosed", "revoke.renew.connectionClosed",
    ].reduce(0) { $0 + counters[Self.oncePrefix + $1, default: 0] }
    guard summary.statistics.refusals >= refusedByRelay else {
      throw DriverError.invalid("S2 relay recorded fewer refusals than revoked probes it refused")
    }
    let heldEpoch = own.filter { $0.conversationID.rawValue == revocation.conversation }
      .map(\.epoch).max()
    guard let heldEpoch,
      summary.grantLog.contains(where: {
        $0.conversationID.rawValue == revocation.conversation
          && $0.runner.rawValue != revocation.device && $0.grantedAt >= revocation.at
          && $0.epoch == heldEpoch + 1
      })
    else {
      throw DriverError.invalid("S2 no successor took over the revoked device's conversation")
    }
  }

  /// Checks the scenarios that run once, under their prefix, the batch-wide content audit, then
  /// every check of the measured scenarios for the qualified phase and again, under its prefix,
  /// for the stress phase (D133).
  func validate(realExpiry: Bool, bonjour: Bool) throws {
    let qualified = S2Options.qualifiedGroupDevices
    guard counters["group.qualified.devices"] == qualified else {
      throw DriverError.invalid(
        "S2 qualified measurements need exactly \(qualified) devices in the group")
    }
    guard counters["group.stress.devices", default: 0] > qualified else {
      throw DriverError.invalid(
        "S2 stress measurements need a larger group than \(qualified) devices")
    }
    let phases = ["", Self.stressPrefix]
    let measuredForbidden = [
      "pairing.unexpectedRefusal", "replica.direct.order.broken", "replica.relay.order.broken",
      "forward.resent.different", "forward.leaseMoved", "stale.local.accepted",
      "audit.chat.epochWentBackwards", "audit.chat.twoWriterEpochs",
      "audit.session.epochWentBackwards", "audit.session.twoWriterEpochs",
      "expiry.staleAccepted", "sf.deliveredWhileOffline", "sf.order.broken",
      "expiry.oldRunner.concurrentAccepted", "audit.expiry.epochWentBackwards",
      "audit.expiry.twoWriterEpochs",
    ]
    let onceForbidden = [
      "qr.replay.accepted", "qr.void.accepted", "qr.expired.accepted", "qr.wrongKey.accepted",
      "qr.afterWrongKey.refused", "revoke.relay.accepted", "revoke.authority.accepted",
      "revoke.claim.accepted", "revoke.renew.accepted", "revoke.write.accepted",
      "revoke.write.afterRevocation", "revoke.link.accepted",
      "audit.revoked.epochWentBackwards", "audit.revoked.twoWriterEpochs",
      "approval.expired.selected",
    ]
    let forbidden =
      onceForbidden.map { Self.oncePrefix + $0 } + ["audit.relay.hits"]
      + phases.flatMap { phase in measuredForbidden.map { phase + $0 } }
    for name in forbidden where counters[name, default: 0] != 0 {
      throw DriverError.invalid("S2 invariant failed: \(name)")
    }
    let measuredRequired = [
      "replica.direct.order.ok", "replica.relay.order.ok", "forward.leaseStayed", "sf.order.ok",
      "expiry.oldRunner.concurrentRefused", "expiry.successor.concurrentAccepted",
    ]
    let onceRequired = [
      "qr.replay.refused", "qr.void.refused", "qr.wrongKey.refused", "qr.afterWrongKey.paired",
      "revoke.lease.held", "revoke.renewals.beforeRevocation", "revoke.relay.refused",
      "revoke.authority.refused", "revoke.claim.refused", "revoke.renew.refused",
      "revoke.control.rawClaimGranted", "revoke.write.refused", "revoke.successor.accepted",
      "revoke.link.refused", "approval.beforeExpiry.retained", "approval.expired.noticeRetained",
      "restart.runnerPayloadRetained", "restart.originalReceiptRetained",
    ]
    let required =
      onceRequired.map { Self.oncePrefix + $0 } + ["audit.control.hits"]
      + phases.flatMap { phase in measuredRequired.map { phase + $0 } }
    for name in required where counters[name, default: 0] == 0 {
      throw DriverError.invalid("S2 proof missing: \(name)")
    }
    for phase in phases {
      guard counters[phase + "forward.uniqueRequests", default: 0] > 0,
        counters[phase + "forward.uniqueRequests"] == counters[phase + "forward.admissions"],
        counters[phase + "forward.resent", default: 0] > 0,
        counters[phase + "forward.resent"] == counters[phase + "forward.resent.sameResult"]
      else {
        throw DriverError.invalid(
          "S2 \(phase.isEmpty ? "" : "stress ")forwarding admission audit")
      }
    }
    if realExpiry, counters[Self.oncePrefix + "qr.expired.refused", default: 0] != 1 {
      throw DriverError.invalid("S2 real five-minute QR expiry proof missing")
    }
    if bonjour, counters["bonjour.committedReplica", default: 0] != 1 {
      throw DriverError.invalid("S2 selected Bonjour discovery/replication proof missing")
    }
    for reports in loads.values {
      guard reports.count == 3,
        reports.allSatisfy({ $0.claimFailures == 0 && $0.errors == 0 && $0.moveFailures == 0 })
      else {
        throw DriverError.invalid("S2 load process failed or reported errors")
      }
    }
  }
}

/// Records one phase's series and counters: under their own names for the qualified phase,
/// under ``S2Results/stressPrefix`` for the stress phase and under ``S2Results/oncePrefix`` for
/// the scenarios that run once.
struct S2Recorder: Sendable {
  let base: S2Results
  var prefix = ""

  func add(_ name: String, _ sample: UInt64) async { await base.add(prefix + name, sample) }
  func add(_ name: String, _ samples: [UInt64]) async { await base.add(prefix + name, samples) }
  func count(_ name: String, _ delta: Int = 1) async { await base.count(prefix + name, delta) }
  func set(_ name: String, _ value: Int) async { await base.set(prefix + name, value) }
  func note(_ text: String) async { await base.note(text) }
  func fail(_ text: String) async { await base.fail(text) }

  /// Counts one outcome of a check that ran, and its other outcome as 0: the report then holds
  /// both, so an absent counter means that the check never ran.
  func outcome(_ happened: Bool, _ yes: String, else no: String) async {
    await count(yes, happened ? 1 : 0)
    await count(no, happened ? 0 : 1)
  }
}

/// When the device sent a renewal the authority accepted, on the wall clock: the granted
/// expiry less the lease time, both read from the `renewed` event's detail.
func s2RenewalSentAt(_ event: S2Line) -> Int64? {
  var fields: [Substring: Int64] = [:]
  for part in (event.detail ?? "").split(separator: " ") {
    let pair = part.split(separator: "=", maxSplits: 1)
    if pair.count == 2, let value = Int64(pair[1]) { fields[pair[0]] = value }
  }
  guard let expiry = fields["expires_at"], let lease = fields["ttl_ms"] else { return nil }
  return expiry - lease
}

/// Nanoseconds from `start` to `end` on the devices' shared monotonic clock; nil when `end`
/// precedes `start`, which is never a sample.
func s2Elapsed(from start: UInt64, to end: UInt64) -> UInt64? {
  end >= start ? end - start : nil
}

/// Both devices' accepted commits of one conversation joined in time order: epochs must never
/// go backwards, and each epoch must have exactly one writing device.
struct S2TwoWriterAudit: Equatable, Sendable {
  var commits = 0
  var epochs = 0
  var writers = 0
  var commitsWithoutEpoch = 0
  var epochWentBackwards = 0
  var twoWriterEpochs = 0

  init(_ commits: [(event: S2Line, device: String)]) {
    var writer: [Int64: String] = [:]
    var devices = Set<String>()
    var highest: Int64 = 0
    for (event, device) in commits.sorted(by: { $0.event.at < $1.event.at }) {
      guard let epoch = event.epoch else {
        commitsWithoutEpoch += 1
        continue
      }
      if epoch < highest { epochWentBackwards += 1 }
      highest = max(highest, epoch)
      if let existing = writer[epoch], existing != device { twoWriterEpochs += 1 }
      writer[epoch] = device
      devices.insert(device)
    }
    self.commits = commits.count
    epochs = writer.count
    writers = devices.count
  }

  /// An audit that saw too little proves nothing: every commit must carry its epoch, and the
  /// history must span at least `writers` devices and `epochs` epochs.
  func requireObserved(writers: Int, epochs: Int) throws {
    guard commitsWithoutEpoch == 0 else {
      throw DriverError.invalid("S2 two-writer audit met a commit without an epoch")
    }
    guard commits > 0, self.writers >= writers, self.epochs >= epochs else {
      throw DriverError.invalid("S2 two-writer audit was vacuous")
    }
  }
}

/// The three conversations the two-writer audit covers, and how much of each must be seen for
/// its audit to prove anything.
enum S2AuditedHistory: String, Sendable {
  /// The hand-over Chat: the Mac and the iPhone hold it in turn.
  case chat
  /// The hand-over Session: the Mac holds it throughout, so one writer and one epoch are what
  /// a correct run shows; the audit requires its commits only.
  case session
  /// The expiry conversation: the runner commits before each freeze and its successor after
  /// the take-over. Without both devices and two epochs no frozen-runner fencing was audited.
  case expiry

  var writers: Int { self == .session ? 1 : 2 }
  var epochs: Int { self == .session ? 1 : 2 }
}

/// A `commitStream` or `writeLoop` reply (``S2CommitTally``): the commits accepted, and those
/// that the fence or the device's own membership refused. Any other failure refused nothing,
/// so it is a batch error, as is a reply without its counts.
struct S2Writes: Equatable, Sendable {
  let accepted: Int
  let refusedByFence: Int
  let refusedByMembership: Int
  var refused: Int { refusedByFence + refusedByMembership }

  /// `what` names the writes in an error, such as "mac hand-over writes".
  init(_ reply: JSONValue, of what: String) throws {
    guard let accepted = reply["accepted"]?.int, let refused = reply["refused"]?.int,
      let fence = reply["refusedBy"]?["fence"]?.int,
      let membership = reply["refusedBy"]?["membership"]?.int, refused == fence + membership,
      let failed = reply["failed"]?.int, let errors = reply["errors"]?.array
    else { throw DriverError.invalid("S2 \(what) reported no outcome") }
    guard failed == 0 else {
      throw DriverError.invalid(
        "S2 \(what) failed without a refusal: "
          + errors.map { $0.string ?? "\($0)" }.joined(separator: "; "))
    }
    self.accepted = Int(accepted)
    refusedByFence = Int(fence)
    refusedByMembership = Int(membership)
  }
}

/// What a revoked device can still do, asked without the guards its own node applies to
/// itself: a revoked device need not cooperate. Each probe reports an explicit outcome from
/// the party that must refuse. A timeout, an ended child or any other error is a batch error,
/// never a refusal.
///
/// The device held `held` at `heldEpoch`, committed to it and had a renewal accepted before it
/// was revoked (D133), so the run also shows what becomes of that lease: the authority itself
/// refuses the revoked sender, no renewal and no commit of it is accepted afterwards, and the
/// witness takes the conversation over at the next epoch.
///
/// It runs once, after the stress phase, so it records under ``S2Results/oncePrefix``.
struct S2RevocationProbe: Sendable {
  let revoked: S2Child
  let witness: S2Child
  let relay: S2Child
  let revokedPeer: S2Peer
  let witnessPeer: S2Peer
  let witnessPort: Int
  let relayPort: Int
  /// The conversation the revoked device held, the epoch it held it at, and when the driver
  /// saw the revocation confirmed, on the devices' monotonic clock and on the wall clock.
  let held: String
  let heldEpoch: Int64
  let revokedAt: UInt64
  let revokedAtWall: Int64
  /// Rides in the successor's commits, for the content audit.
  let label: String
  var timeout: Duration = .seconds(60)
  /// How long after the revocation the revoked device's renewals are watched.
  var renewalWindow: Duration = .milliseconds(2_500)

  func run(conversation: String, results base: S2Results) async throws {
    let results = S2Recorder(base: base, prefix: S2Results.oncePrefix)
    let started = ContinuousClock.now
    // The revoked device reads its own removal first (D133). Until it has, its node may still
    // accept its own commits, and the connection it reads the removal on is a relay refusal of
    // its own, which must land before the relay's count is read for any probe below.
    try await awaitRemoval()
    // The relay itself must refuse a fresh hello signed by the revoked identity, and count it.
    var relayBefore = try await relayRefusals()
    let hello = try await revoked.call("rawRelayHello", timeout: timeout) { $0.port = relayPort }
    guard let accepted = hello["accepted"]?.bool else {
      throw DriverError.invalid("revoked relay hello outcome")
    }
    if !accepted { try await requireRelayRefusal(since: relayBefore, of: "hello") }
    await results.outcome(accepted, "revoke.relay.accepted", else: "revoke.relay.refused")
    // Before any successor claims: the removed device's lease is expired and free, so only the
    // revocation can make the authority refuse it.
    let removedAt = try await askAuthority(results)
    // A raw claim reaches the authority only over an authenticated relay connection: either
    // the authority denies it, or the relay refuses the connection. The main relay's grant log
    // is checked against the revocation time when the batch ends.
    relayBefore = try await relayRefusals()
    let claim = try await revoked.call("rawClaim", timeout: timeout) {
      $0.conversation = conversation
    }
    try await recordRaw(claim, granted: "granted", as: "claim", relayBefore, results)
    // The same for a raw renewal of the lease it held.
    relayBefore = try await relayRefusals()
    let renewal = try await revoked.call("rawRenew", timeout: timeout) {
      $0.conversation = held
      $0.epoch = heldEpoch
    }
    try await recordRaw(renewal, granted: "renewed", as: "renewal", relayBefore, results)
    // The same raw path answers a member: the witness's raw claim of a fresh conversation is
    // granted, then released. An unanswered request above was refused, not lost on a path that
    // answers nobody.
    let control = try await witness.call("rawClaimAndRelease", timeout: timeout) {
      $0.conversation = "cht_" + DeviceULID.make()
    }
    guard control["answered"]?.bool == true, control["granted"]?.bool == true,
      control["released"]?.bool == true
    else { throw DriverError.invalid("S2 member raw claim control was not granted and released") }
    await results.count("revoke.control.rawClaimGranted")
    // Its own commit attempts on the conversation it held must accept nothing. Only its fence
    // or its own membership refuses a commit; any other failure, such as its closed store,
    // refuses nothing and is a batch error.
    let reply = try await revoked.call("commitStream", timeout: timeout) {
      $0.conversation = held
      $0.count = 3
      $0.label = "revoked device \(label)"
    }
    let writes = try S2Writes(reply, of: "revoked device's commits")
    await results.count("revoke.write.accepted", writes.accepted)
    await results.count("revoke.write.refused", writes.refused)
    await results.count("revoke.write.refusedByFence", writes.refusedByFence)
    await results.count("revoke.write.refusedByMembership", writes.refusedByMembership)
    // The witness takes the conversation over at exactly the next epoch and writes there.
    let taken = try await witness.call("takeOver", timeout: timeout) {
      $0.conversation = held
      $0.timeoutMs = 15_000
    }
    guard taken["epoch"]?.int == heldEpoch + 1 else {
      throw DriverError.invalid("successor did not take over at the next epoch")
    }
    await results.add("revoke.successor.takeOver", UInt64(taken["durationNs"]?.int ?? 0))
    try await witness.call("renew", timeout: timeout) { $0.conversation = held }
    let successor = try await witness.call("commitStream", timeout: timeout) {
      $0.conversation = held
      $0.count = 3
      $0.label = "successor \(label)"
    }
    guard successor["accepted"]?.int == 3 else {
      throw DriverError.invalid("successor commits were not all accepted")
    }
    await results.count("revoke.successor.accepted", 3)
    try await probeLink(results)
    // A renewal loop that still ran would have had a renewal accepted inside this window.
    try await Task.sleep(until: started + renewalWindow, clock: .continuous)
    var renewedBefore = 0
    var renewedAfter = 0
    for event in await revoked.events("renewed", conversation: held) {
      guard let sent = s2RenewalSentAt(event) else {
        throw DriverError.invalid("revoked renewal event without its expiry")
      }
      if sent > removedAt { renewedAfter += 1 } else { renewedBefore += 1 }
    }
    guard renewedBefore > 0 else {
      throw DriverError.invalid("revoked device had no renewal accepted before")
    }
    await results.set("revoke.renewals.beforeRevocation", renewedBefore)
    await results.count("revoke.renew.accepted", renewedAfter)
    // Its commits end before the revocation, and no epoch has both writers.
    let own = await revoked.events("committed", conversation: held)
    await results.set("revoke.write.afterRevocation", own.filter { $0.at >= revokedAt }.count)
    let audit = S2TwoWriterAudit(
      own.map { ($0, "revoked") }
        + (await witness.events("committed", conversation: held)).map { ($0, "successor") })
    await results.set("audit.revoked.commits", audit.commits)
    await results.set("audit.revoked.epochs", audit.epochs)
    await results.set("audit.revoked.writers", audit.writers)
    await results.set("audit.revoked.commitsWithoutEpoch", audit.commitsWithoutEpoch)
    await results.set("audit.revoked.epochWentBackwards", audit.epochWentBackwards)
    await results.set("audit.revoked.twoWriterEpochs", audit.twoWriterEpochs)
    try audit.requireObserved(writers: 2, epochs: 2)
  }

  /// Waits, bounded, until the revoked device reports that it read its own removal.
  private func awaitRemoval() async throws {
    let deadline = ContinuousClock.now + timeout
    while await revoked.events("removedFromGroup").isEmpty {
      guard ContinuousClock.now < deadline else {
        throw DriverError.timeout("\(revoked.name) removedFromGroup")
      }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  /// The connections the relay refused so far, by its own count (`stats`).
  private func relayRefusals() async throws -> Int {
    let stats = try await relay.call("stats", timeout: timeout)
    guard let refusals = stats["statistics"]?["refusals"]?.int else {
      throw DriverError.invalid("relay refusal count")
    }
    return Int(refusals)
  }

  /// Requires the relay to have refused exactly one connection since its count was `before`:
  /// the probe's own. The relay counts a refusal just after the probe can see it, so this
  /// waits, bounded, for it. None is no relay refusal, and more than one cannot be told apart
  /// from the probe's; either is a batch error.
  private func requireRelayRefusal(since before: Int, of what: String) async throws {
    let deadline = ContinuousClock.now + timeout
    while true {
      let refused = try await relayRefusals() - before
      if refused == 1 { return }
      guard refused == 0 else {
        throw DriverError.invalid(
          "S2 relay refused \(refused) connections during one revoked probe")
      }
      guard ContinuousClock.now < deadline else {
        throw DriverError.invalid("S2 relay recorded no refusal of the revoked device's \(what)")
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  /// Records a raw claim's or renewal's outcome under `revoke.claim` or `revoke.renew`. An
  /// answer is the authority's own. An unanswered request ended with its connection, which is
  /// a refusal only when the relay's count shows that it refused that connection
  /// (`connectionClosed`).
  private func recordRaw(
    _ reply: JSONValue, granted key: String, as what: String, _ relayBefore: Int,
    _ results: S2Recorder
  ) async throws {
    let name = what == "claim" ? "revoke.claim" : "revoke.renew"
    switch (reply["answered"]?.bool, reply[key]?.bool) {
    case (true?, let granted?):
      await results.outcome(granted, name + ".accepted", else: name + ".refused")
      await results.count(name + ".connectionClosed", 0)
    case (false?, nil):
      try await requireRelayRefusal(since: relayBefore, of: "raw " + what)
      await results.outcome(false, name + ".accepted", else: name + ".refused")
      await results.count(name + ".connectionClosed")
    default:
      throw DriverError.invalid("revoked \(what) outcome")
    }
  }

  /// Has the relay process put the revoked device's claim and renewal to its authority
  /// directly, as it would for an authenticated connection. Returns the authority's own time
  /// of the removal when the lease record shows it, else the driver's.
  private func askAuthority(_ results: S2Recorder) async throws -> Int64 {
    let asked = try await relay.call("revokedProbe", timeout: timeout) {
      $0.peer = revokedPeer
      $0.candidates = [witnessPeer]
      $0.conversation = held
      $0.epoch = heldEpoch
    }
    let expired = asked["leaseExpired"]?.bool == true
    await results.set("revoke.lease.expiredAtRemoval", expired ? 1 : 0)
    let served = asked["claimGranted"]?.bool == true || asked["renewed"]?.bool == true
    if !served {
      // Refused by the authority's own membership check, counted by it, with the lease record
      // untouched; and the same path grants a member, so it could have shown a grant.
      guard asked["isRevoked"]?.bool == true, asked["revokedRefusals"]?.int == 2,
        asked["claimAnswered"]?.bool == false, asked["renewAnswered"]?.bool == false,
        asked["leaseUnchanged"]?.bool == true, asked["leaseEpoch"]?.int == heldEpoch + 1,
        asked["memberClaimGranted"]?.bool == true
      else { throw DriverError.invalid("revoked authority probe outcome") }
    }
    await results.outcome(served, "revoke.authority.accepted", else: "revoke.authority.refused")
    if expired, let removal = asked["leaseExpiresAt"]?.int { return removal }
    return revokedAtWall
  }

  /// The peer must refuse the handshake itself: a link the revoked device gave up on its own
  /// is no proof. The link may open at the TCP level.
  private func probeLink(_ results: S2Recorder) async throws {
    let refusedBefore = await refusals()
    let link = try await revoked.call("rawLink", timeout: timeout) {
      $0.peer = witnessPeer
      $0.port = witnessPort
    }
    guard let linked = link["linked"]?.bool else {
      throw DriverError.invalid("revoked link outcome")
    }
    let routes = try await witness.call("routes", timeout: timeout) { $0.peer = revokedPeer }
    if linked || (routes["routes"]?.array ?? []).contains(.string("direct")) {
      await results.outcome(true, "revoke.link.accepted", else: "revoke.link.refused")
      return
    }
    let deadline = ContinuousClock.now + timeout
    while await refusals() == refusedBefore {
      guard ContinuousClock.now < deadline else {
        throw DriverError.timeout("\(witness.name) refusing the revoked link")
      }
      try await Task.sleep(for: .milliseconds(5))
    }
    await results.outcome(false, "revoke.link.accepted", else: "revoke.link.refused")
  }

  /// Direct-link handshakes the witness refused so far because their initiator is not a
  /// member. A refused handshake names no peer; a refusal that names one is a message refused
  /// on a link that already existed. A handshake the witness answered and then gave up on at
  /// its deadline reports a timeout, not `unknownPeer`: there the witness refused nobody.
  private func refusals() async -> Int {
    await witness.events("refused").filter {
      $0.route == "direct" && $0.peer == nil && $0.detail == "unknownPeer"
    }.count
  }
}

/// The S2 development batch on one Mac (loopback only): a relay with the lease authority and
/// three device processes (Mac, iPhone and iPad stand-ins), each with its own identity, real
/// `MemoshiStore` and device node. It measures pairing, links, lease operations, replica lag,
/// forwarding, hand-overs with fencing, expiry take-over with the runner frozen (SIGSTOP),
/// store-and-forward and revocation, then the S2.12 authority-load matrix.
package enum S2Driver {
  package static func run(_ requested: S2Options) async -> Int32 {
    let results = S2Results()
    let fileManager = FileManager.default
    let paths: QualificationPaths
    do {
      paths = try QualificationPaths(
        work: requested.workDirectory, output: requested.outputDirectory)
    } catch {
      LineWriter.standardError.text("s2: \(error)")
      return 64
    }
    var options = requested
    options.workDirectory = paths.work
    options.outputDirectory = paths.output
    let logs = options.outputDirectory.appendingPathComponent("logs", isDirectory: true)
    var status: Int32 = 0
    var children: [S2Child] = []
    var ownsWorkDirectory = false
    var ownsOutputDirectory = false
    do {
      try QualificationPaths.create(paths.work)
      ownsWorkDirectory = true
      try QualificationPaths.create(paths.output)
      ownsOutputDirectory = true
      try QualificationPaths.create(logs)
      await results.describeStorage(S2Storage.describe(paths.work))
      await results.probeStorage(
        await S2SyncProbe.measure(in: paths.work, phase: "beforeScenarios"))
      let world = try await S2World.start(options, logs: logs, owned: &children)
      let canary = Canary.generate(label: "s2-content")
      try await S2Scenarios(
        world: world, options: options, results: S2Recorder(base: results), canary: canary
      ).runAll()
      for child in world.devices {
        let exit = try await child.stop()
        children.removeAll { $0 === child }
        guard exit == .exited(0) else {
          throw DriverError.invalid(
            "\(child.name) did not shut down cleanly: \(String(describing: exit))")
        }
      }
      var relayFailures: [String] = []
      let relayExit: ChildExit?
      do { relayExit = try await world.relay.stop() } catch {
        relayExit = world.relay.process.exit
        relayFailures.append("main relay capture failed: \(error)")
      }
      if relayExit != nil { children.removeAll { $0 === world.relay } }
      if relayExit != .exited(0) {
        relayFailures.append(
          "main relay did not shut down cleanly: \(String(describing: relayExit))")
      }
      do {
        let summary = try JSONDecoder().decode(
          S2RelaySummary.self,
          from: Data(contentsOf: world.relayDirectory.appendingPathComponent("relay-summary.json")))
        try await results.relay("main", summary)
      } catch { relayFailures.append("main relay summary: \(error)") }
      if !relayFailures.isEmpty {
        for failure in relayFailures { await results.fail(failure) }
        throw DriverError.invalid("main relay shutdown or evidence capture failed")
      }
      try await S2Scenarios.contentAudit(world: world, canary: canary, results: results)
      if options.load {
        try await S2Scenarios.loadMatrix(options, logs: logs, results: results, owned: &children)
      }
      try await results.validate(realExpiry: options.realExpiry, bonjour: options.bonjour)
    } catch {
      LineWriter.standardError.text("s2: \(error)")
      await results.fail("batch error: \(error)")
      status = 1
    }
    for child in children {
      do {
        let exit = try await child.stop(timeout: .seconds(5))
        if exit == nil {
          await results.fail("\(child.name) could not be reaped")
          status = 1
        }
      } catch {
        await results.fail("\(child.name) capture failed: \(error)")
        status = 1
      }
    }
    var mainRelayRetentionFailed = false
    let mainRelaySummary = await results.relays["main"]
    if children.contains(where: { $0.name == "relay" }) || mainRelaySummary != nil {
      let relayDirectory = paths.work.appendingPathComponent("relay", isDirectory: true)
      for name in ["relay-summary.json", "relay-journal.bin"] {
        do {
          let source = relayDirectory.appendingPathComponent(name)
          var information = stat()
          guard lstat(source.path, &information) == 0,
            information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
          else {
            throw DriverError.invalid("Required main relay artifact \(name) is not a regular file")
          }
          try fileManager.copyItem(
            at: source, to: paths.output.appendingPathComponent("main-\(name)"))
        } catch {
          await results.fail("main relay \(name) retention failed with \(error)")
          mainRelayRetentionFailed = true
          status = 1
        }
      }
      if mainRelaySummary == nil {
        do {
          let summary = try JSONDecoder().decode(
            S2RelaySummary.self,
            from: Data(
              contentsOf: paths.output.appendingPathComponent("main-relay-summary.json")))
          try await results.relay("main", summary)
        } catch {
          await results.fail("main relay retained summary failed with \(error)")
          status = 1
        }
      }
    }
    if mainRelayRetentionFailed {
      await results.note(
        "Owned work retained at \(paths.work.path) after required evidence failure")
    }
    if ownsWorkDirectory, fileManager.fileExists(atPath: paths.work.path) {
      await results.probeStorage(await S2SyncProbe.measure(in: paths.work, phase: "afterBatch"))
    }
    // Cleanup precedes the report, so the retained verdict covers it too.
    if ownsWorkDirectory && !mainRelayRetentionFailed {
      try? fileManager.removeItem(at: options.workDirectory)
      if fileManager.fileExists(atPath: options.workDirectory.path) {
        await results.fail("Owned work root remains after cleanup")
        status = 1
      }
    }
    if ownsOutputDirectory {
      do {
        try await writeReport(results, options: options, passed: status == 0, to: paths.output)
      } catch {
        LineWriter.standardError.text("s2 report: \(error)")
        status = 1
      }
    }
    return status
  }

  private static func writeReport(
    _ results: S2Results, options: S2Options, passed: Bool, to directory: URL
  ) async throws {
    let samples = directory.appendingPathComponent("samples", isDirectory: true)
    try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
    var summary: [String: JSONValue] = [:]
    for (name, values) in await results.series.sorted(by: { $0.key < $1.key }) {
      let csv =
        "ms\n" + values.map { String(format: "%.3f", Double($0) / 1e6) }.joined(separator: "\n")
      try Data((csv + "\n").utf8).write(to: samples.appendingPathComponent("\(name).csv"))
      let distribution = S2Distribution(values)
      summary[name] = try JSONValue.parse(JSONLines.encoder.encode(distribution))
    }
    /// One phase's group size; `nil` (written as null) when the batch never reached it.
    struct Phase: Encodable {
      let groupDevices: Int?
      let what: String
      var series: [String: JSONValue]?
      var counters: [String: Int]?

      enum CodingKeys: String, CodingKey { case groupDevices, what, series, counters }

      func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupDevices, forKey: .groupDevices)
        try container.encode(what, forKey: .what)
        try container.encodeIfPresent(series, forKey: .series)
        try container.encodeIfPresent(counters, forKey: .counters)
      }
    }
    struct Report: Encodable {
      /// Whether the batch passed, cleanup included; the process exit status says the same.
      let passed: Bool
      /// The qualified phase: `series` and `counters` below were measured at this group size,
      /// apart from the batch-wide counters that `what` names.
      let qualified: Phase
      /// The stress phase, reported apart from the qualified numbers.
      let stress: Phase
      /// The scenarios that run once, in the stress group, reported apart from both phases.
      let once: Phase
      let series: [String: JSONValue]
      let counters: [String: Int]
      /// Informational observations; none of them disqualifies the batch.
      let notes: [String]
      /// Every reason the batch did not pass.
      let failures: [String]
      let loads: [String: [S2LoadReport]]
      let relays: [String: S2RelaySummary]
      let host: [String: String]
      let storage: S2Storage?
      let quick: Bool
      let realQRExpirySelected: Bool
      let authorityLoadSelected: Bool
      let bonjourSelected: Bool
      let authorityPersistence = "synchronized-append-journal"
      let evidenceClass = "controlled-mac-processes-not-physical-device-or-pi-replication"
      let deviceApplicationCrypto = "native-rfc9420-mls-rs-suite0001-inside-noise"
      let devicePersistence = "encrypted-native-inbox-replay-and-ordered-full-sender-feed-cutoffs"
      let identityStorage = "explicit-qualification-only-file-not-production-keychain"
      let authorityLoadScope =
        "raw-local-metadata-issuer-not-pi-transactions-or-deployed-device-capacity"
    }
    var host = [String: String]()
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var model = [CChar](repeating: 0, count: max(size, 1))
    sysctlbyname("hw.model", &model, &size, nil, 0)
    host["model"] = String(
      decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    host["os"] = ProcessInfo.processInfo.operatingSystemVersionString
    host["cpus"] = String(ProcessInfo.processInfo.activeProcessorCount)
    host["memoryBytes"] = String(ProcessInfo.processInfo.physicalMemory)
    let series = S2Results.phases(summary)
    let counters = S2Results.phases(await results.counters)
    let report = Report(
      passed: passed,
      qualified: Phase(
        groupDevices: counters.qualified["group.qualified.devices"],
        what: "The series and counters at the top level: the pairing that built this group and "
          + "the measured scenarios (links, lease operations, replica lag, forwarding, "
          + "hand-overs, expiry, store-and-forward and the optional Bonjour scenario) with this "
          + "many devices in the group, the qualified numbers (D133); and batch-wide counters "
          + "(group sizes, the content audit, reservation and recovery tallies). The stress "
          + "phase and the scenarios that run once are reported apart."),
      stress: Phase(
        groupDevices: counters.qualified["group.stress.devices"],
        what: "The same scenarios run again in the same processes with this many devices in "
          + "the group. A stress measurement, not the qualified numbers (D133).",
        series: series.stress, counters: counters.stress),
      once: Phase(
        groupDevices: counters.qualified["group.once.devices"],
        what: "Scenarios that run once, in the stress phase's processes and group: the QR "
          + "negative checks while that group's last device joins, offline-approval expiry and "
          + "revocation with this many devices in the group, then the late QR check and restart "
          + "recovery without the revoked iPad. Measured once in the stress group, not the "
          + "qualified numbers (D133).",
        series: series.once, counters: counters.once),
      series: series.qualified, counters: counters.qualified,
      notes: await results.notes, failures: await results.failures,
      loads: await results.loads, relays: await results.relays, host: host,
      storage: await results.storage,
      quick: options.quick, realQRExpirySelected: options.realExpiry,
      authorityLoadSelected: options.load, bonjourSelected: options.bonjour)
    try JSONLines.prettyEncoder.encode(report).write(
      to: directory.appendingPathComponent("s2-measurements.json"))
  }
}

extension S2Options {
  /// Devices in the group while the qualified measurements run (D133).
  static let qualifiedGroupDevices = 8
  /// Probe devices paired before the qualified phase: with the Mac, the iPhone and the iPad
  /// they make the qualified group.
  fileprivate var qualifiedProbes: Int { Self.qualifiedGroupDevices - 3 }
  /// Probe devices paired for the stress phase; one more joins in the wrong-key check, which
  /// makes 54 devices in a full run and 13 in a quick one.
  fileprivate var stressProbes: Int { quick ? 4 : 45 }
}

/// The relay and three devices.
private struct S2World: Sendable {
  let relay: S2Child
  let relayPort: Int
  let relayDirectory: URL
  let mac: S2Child
  let phone: S2Child
  let ipad: S2Child
  let macPeer: S2Peer
  let phonePeer: S2Peer
  let ipadPeer: S2Peer
  let macPort: Int
  let directories: [String: URL]

  var devices: [S2Child] { [mac, phone, ipad] }

  static func start(_ options: S2Options, logs: URL, owned: inout [S2Child]) async throws -> S2World
  {
    let work = options.workDirectory
    let relayDirectory = work.appendingPathComponent("relay", isDirectory: true)
    try FileManager.default.createDirectory(at: relayDirectory, withIntermediateDirectories: true)
    let environment = [
      "HOME": work.path, "TMPDIR": work.path + "/", "PATH": "/usr/bin:/bin",
    ]
    let relay = try S2Child.spawn(
      name: "relay", executable: options.executable,
      arguments: ["s2-relay", "--directory", relayDirectory.path], environment: environment,
      logs: logs)
    owned.append(relay)
    let listening = try await relay.waitFor(event: "listening")
    guard let port = listening["port"]?.int else { throw DriverError.invalid("relay port") }
    var children: [String: S2Child] = [:]
    var peers: [String: S2Peer] = [:]
    var ports: [String: Int] = [:]
    var directories: [String: URL] = [:]
    var groupID: String?
    for (name, label, platform) in [
      ("mac", "Mac", "mac"), ("phone", "iPhone", "iphone"), ("ipad", "iPad", "ipad"),
    ] {
      let directory = work.appendingPathComponent(name, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      directories[name] = directory
      let child = try S2Child.spawn(
        name: name, executable: options.executable,
        arguments: [
          "s2-device", "--directory", directory.path, "--name", label, "--platform", platform,
        ], environment: environment, logs: logs)
      owned.append(child)
      let ready = try await child.waitFor(event: "ready")
      guard let peer = ready["peer"], let devicePort = ready["port"]?.int,
        let initialGroup = ready["groupId"]?.string
      else {
        throw DriverError.invalid("\(name) ready")
      }
      peers[name] = try JSONDecoder().decode(S2Peer.self, from: JSONLines.encoder.encode(peer))
      ports[name] = Int(devicePort)
      if name == "mac" { groupID = initialGroup }
      children[name] = child
    }
    guard let mac = children["mac"], let phone = children["phone"], let ipad = children["ipad"],
      let macPeer = peers["mac"], let phonePeer = peers["phone"], let ipadPeer = peers["ipad"],
      let macPort = ports["mac"], let groupID
    else { throw DriverError.invalid("world") }
    // The authority receives only public identities over its private owner pipe. Every positive
    // pairing probe is a genuinely new member, not an unauthorized self-enrollment or re-pair.
    let prepared = try await phone.call("preparePairProbes") {
      $0.count =
        options.qualifiedProbes + options.stressProbes + 2 + (options.realExpiry ? 1 : 0)
    }
    guard let publicProbes = prepared["peers"] else {
      throw DriverError.invalid("pairing probe enrollment")
    }
    let probePeers = try JSONDecoder().decode(
      [S2Peer].self, from: JSONLines.encoder.encode(publicProbes))
    try await relay.call("enroll") {
      $0.groupId = groupID
      $0.peers = [macPeer]
      $0.candidates = [phonePeer, ipadPeer] + probePeers
    }
    try await mac.call("relayConnect") { $0.port = Int(port) }
    try await phone.call("relayConnect") { $0.port = Int(port) }
    try await ipad.call("relayConnect") { $0.port = Int(port) }
    return S2World(
      relay: relay, relayPort: Int(port), relayDirectory: relayDirectory, mac: mac, phone: phone,
      ipad: ipad, macPeer: macPeer, phonePeer: phonePeer, ipadPeer: ipadPeer, macPort: macPort,
      directories: directories)
  }
}

private struct S2Scenarios {
  let world: S2World
  let options: S2Options
  let results: S2Recorder
  /// Rides in every committed label and forwarded text, so the content audit can look for it.
  let canary: Canary

  private var quick: Bool { options.quick }
  private func n(_ full: Int, _ smoke: Int) -> Int { quick ? smoke : full }
  private func now() -> UInt64 { DeviceClock.monotonicNanoseconds() }
  private func conversation(_ prefix: String = "cht") -> String { prefix + "_" + DeviceULID.make() }

  func runAll() async throws {
    var expiring: (qr: String, issued: ContinuousClock.Instant)?
    if options.realExpiry {
      let code = try await world.mac.call("invite")
      expiring = (code["qr"]?.string ?? "", ContinuousClock.now)
    }
    // Qualified phase (D133): the Mac, the iPhone, the iPad and five probe devices.
    try await pairDevices()
    _ = try await pairProbes(options.qualifiedProbes)
    let qualified = try await groupDevices()
    await results.set("group.qualified.devices", qualified)
    guard qualified == S2Options.qualifiedGroupDevices else {
      throw DriverError.invalid("S2 qualified phase has \(qualified) devices in the group")
    }
    try await measured()
    // Stress phase: the remaining probes join, and the same scenarios run again under the
    // stress prefix. The scenarios that run once follow in that group under their own prefix:
    // none of their numbers is a qualified one. The QR checks run here too, so the qualified
    // group is exactly eight.
    let stress = S2Scenarios(
      world: world, options: options,
      results: S2Recorder(base: results.base, prefix: S2Results.stressPrefix), canary: canary)
    let once = S2Scenarios(
      world: world, options: options,
      results: S2Recorder(base: results.base, prefix: S2Results.oncePrefix), canary: canary)
    let lastCode = try await stress.pairProbes(options.stressProbes)
    try await once.qrChecks(replaying: lastCode)
    await results.set("group.stress.devices", try await groupDevices())
    try await stress.measured()
    await results.set("group.once.devices", try await groupDevices())
    try await once.offlineApprovalExpiry()
    try await once.revocation()
    if let expiring {
      let ready = expiring.issued + .seconds(301)
      if ContinuousClock.now < ready { try await Task.sleep(until: ready, clock: .continuous) }
      let late = try await world.phone.call("pairProbe") { $0.qr = expiring.qr }
      await once.results.outcome(
        late["paired"]?.bool == true, "qr.expired.accepted", else: "qr.expired.refused")
      await results.note("QR used 301 s after issue: \(late["refusal"]?.string ?? "paired")")
    }
    try await once.restartRecovery()
    // Reported, not required: both depend on races that no scenario forces. A writer whose
    // reserve was refused or failed, or whose store refused at the fence, releases the sequence
    // it asked for, and a publication that met a closed group epoch is sealed again instead of
    // surfacing as held (expected 0).
    var released = 0
    var heldAtClosedEpoch = 0
    for device in [world.mac, world.phone] {
      released += await device.events("reservationReleased").count
      heldAtClosedEpoch += await device.events("applicationRecoveryRequired").filter {
        $0.detail == "unacceptedOldEpoch"
      }.count
    }
    await results.set("reservation.released", released)
    await results.set("recovery.unacceptedOldEpochReported", heldAtClosedEpoch)
  }

  /// Exercises real elapsed-time selection and durable notices, not a fabricated runner/policy.
  private func offlineApprovalExpiry() async throws {
    let id = conversation()
    let expiring = DeviceULID.make()
    let live = DeviceULID.make()
    let issued = DeviceClock.wallMilliseconds()
    for (request, deadline) in [(expiring, issued + 1_000), (live, issued + 30_000)] {
      try await world.phone.call("approvalQueue") {
        $0.conversation = id
        $0.requestId = request
        $0.cardId = "crd_" + DeviceULID.make()
        $0.expiresAt = deadline
      }
    }
    try await world.phone.call("approvalReopen")
    let before = try await world.phone.call("approvalSelect")
    guard before["pending"]?.array?.contains(.string(expiring)) == true,
      before["pending"]?.array?.contains(.string(live)) == true
    else { throw DriverError.invalid("offline answer missing before expiry after reopen") }
    await results.count("approval.beforeExpiry.retained", 2)
    try await Task.sleep(for: .milliseconds(1_200))
    let after = try await world.phone.call("approvalSelect")
    let selected = after["pending"]?.array?.contains(.string(expiring)) == true
    await results.count("approval.expired.selected", selected ? 1 : 0)
    guard after["pending"]?.array?.contains(.string(live)) == true,
      after["expired"]?.array?.contains(.string(expiring)) == true
    else { throw DriverError.invalid("offline answer expiry selection or notice missing") }
    try await world.phone.call("approvalReopen")
    let reopened = try await world.phone.call("approvalSelect")
    guard reopened["pending"]?.array?.contains(.string(expiring)) == false,
      reopened["expired"]?.array?.contains(.string(expiring)) == true
    else { throw DriverError.invalid("offline answer expiry notice was not durable") }
    await results.count("approval.expired.noticeRetained")
    await results.note(
      "Offline approval mailbox retained original answers before expiry, removed an expired "
        + "answer and retained its display notice across reopen. No real runner card/policy apply "
        + "or native notice display is claimed.")
  }

  /// A fresh owned OS process reopens the exact device identity, Store, encrypted membership,
  /// replica cursor and forwarding receipt. It does not reopen or replicate a Pi store.
  private func restartRecovery() async throws {
    let id = conversation()
    let request = DeviceULID.make()
    try await world.mac.call("configure") {
      $0.ttlMs = 30_000
      $0.everyMs = 10_000
    }
    try await claimAndRenew(world.mac, id, ttl: 30_000, every: 10_000)
    try await waitRunner(world.phone, id, runner: world.macPeer)
    let original = try await world.phone.call("forward") {
      $0.conversation = id
      $0.requestId = request
      $0.text = "restart receipt \(canary.value)"
    }
    try await waitRseq(world.phone, id, atLeast: 4)
    guard try await world.mac.stop() == .exited(0),
      let directory = world.directories["mac"]
    else { throw DriverError.invalid("pre-recovery device did not close normally") }
    let restarted = try S2Child.spawn(
      name: "mac-restarted", executable: options.executable,
      arguments: [
        "s2-device", "--directory", directory.path, "--name", "Mac", "--platform", "mac",
      ],
      environment: [
        "HOME": options.workDirectory.path, "TMPDIR": options.workDirectory.path + "/",
        "PATH": "/usr/bin:/bin",
      ], logs: options.outputDirectory.appendingPathComponent("logs"))
    do {
      let ready = try await restarted.waitFor(event: "ready")
      guard ready["deviceId"]?.string == world.macPeer.deviceId,
        let port = ready["port"]?.int
      else { throw DriverError.invalid("recovery changed the device identity") }
      try await restarted.call("relayConnect") { $0.port = world.relayPort }
      try await restarted.call("recover", timeout: .seconds(120))
      let recovered = try await restarted.call("lease") { $0.conversation = id }
      guard recovered["lastRseq"]?.int == 4,
        recovered["runner"]?.string == world.macPeer.deviceId
      else { throw DriverError.invalid("recovered device did not retain its exact history") }
      let next = try await restarted.call("commitStream") {
        $0.conversation = id
        $0.count = 1
        $0.label = "after real process reopen \(canary.value)"
      }
      guard next["accepted"]?.int == 1 else {
        throw DriverError.invalid("recovered live authority could not commit the next sequence")
      }
      await results.count("restart.runnerPayloadRetained")
      try await world.phone.call("directLink") {
        $0.peer = world.macPeer
        $0.port = Int(port)
      }
      let replayed = try await world.phone.call("forward") {
        $0.conversation = id
        $0.requestId = request
        $0.text = "restart receipt \(canary.value)"
      }
      guard original["messageId"] == replayed["messageId"],
        original["taskId"] == replayed["taskId"]
      else { throw DriverError.invalid("recovered forwarding changed the original receipt") }
      try await waitRseq(world.phone, id, atLeast: 5)
      await results.count("restart.originalReceiptRetained")
      guard try await restarted.stop() == .exited(0) else {
        throw DriverError.invalid("recovered device did not stop normally")
      }
    } catch {
      do { _ = try await restarted.stop(timeout: .seconds(5)) } catch let captureError {
        await results.fail("\(restarted.name) capture failed: \(captureError)")
      }
      throw error
    }
  }

  private func bonjourLinks() async throws {
    for device in [world.mac, world.phone] { try await device.call("bonjourListen") }
    for (device, peer) in [(world.mac, world.phonePeer), (world.phone, world.macPeer)] {
      let discovered = try await device.call("bonjourDiscover") {
        $0.peer = peer
        $0.timeoutMs = 15_000
      }
      guard discovered["discovered"]?.bool == true else {
        throw DriverError.invalid("selected Bonjour discovery returned no real service")
      }
      await results.count("bonjour.discovery.real")
    }
    let linked = try await world.phone.call("bonjourLink") { $0.peer = world.macPeer }
    await results.add("link.bonjour.handshake", UInt64(linked["handshakeNs"]?.int ?? 0))
    let id = conversation()
    try await claimAndRenew(world.mac, id)
    let committed = try await world.mac.call("commitStream") {
      $0.conversation = id
      $0.count = 5
      $0.label = "real discovered service \(canary.value)"
    }
    guard committed["accepted"]?.int == 5 else {
      throw DriverError.invalid("selected Bonjour writer did not commit")
    }
    try await waitRseq(world.phone, id, atLeast: 5)
    await results.add("replica.bonjour", await lag(id, runner: world.mac, replica: world.phone))
    await results.count("bonjour.committedReplica")
  }

  // MARK: Pairing (S2.1)

  /// The scenarios whose numbers depend on the size of the group. Each phase runs them once,
  /// from the node's default lease settings, and leaves those behind: the expiry scenario
  /// shortens them, and a later take-over without its own lease time would inherit that.
  private func measured() async throws {
    try await defaultLeaseSettings()
    try await links()
    try await leaseOperations()
    if options.bonjour, results.prefix.isEmpty { try await bonjourLinks() }
    try await replicaLag()
    try await forwarding()
    try await handOvers()
    try await expiryTakeOver()
    try await storeAndForward()
    try await defaultLeaseSettings()
  }

  private func defaultLeaseSettings() async throws {
    for device in [world.mac, world.phone] {
      try await device.call("configure") {
        $0.ttlMs = 10_000
        $0.everyMs = 3_000
      }
    }
  }

  /// How many devices the Mac's group holds.
  private func groupDevices() async throws -> Int {
    guard let devices = try await world.mac.call("group")["devices"]?.int else {
      throw DriverError.invalid("group size")
    }
    return Int(devices)
  }

  private func pairDevices() async throws {
    for device in [world.phone, world.ipad] {
      let code = try await world.mac.call("invite")
      let paired = try await device.call("pair") { $0.qr = code["qr"]?.string }
      await results.add("pairing.device.total", UInt64(paired["totalNs"]?.int ?? 0))
    }
  }

  /// Pairs `count` fresh probe devices; returns the last code used.
  private func pairProbes(_ count: Int) async throws -> String {
    var lastCode = ""
    await results.count("pairing.unexpectedRefusal", 0)
    for _ in 0..<count {
      let code = try await world.mac.call("invite")
      lastCode = code["qr"]?.string ?? ""
      let probe = try await world.phone.call("pairProbe") { $0.qr = lastCode }
      guard probe["paired"]?.bool == true else {
        await results.count("pairing.unexpectedRefusal")
        continue
      }
      await results.add("pairing.probe.connect", UInt64(probe["connectNs"]?.int ?? 0))
      await results.add("pairing.probe.handshake", UInt64(probe["handshakeNs"]?.int ?? 0))
      await results.add("pairing.probe.total", UInt64(probe["totalNs"]?.int ?? 0))
    }
    return lastCode
  }

  private func qrChecks(replaying lastCode: String) async throws {
    // A replayed code.
    let replay = try await world.phone.call("pairProbe") { $0.qr = lastCode }
    await results.outcome(
      replay["paired"]?.bool == true, "qr.replay.accepted", else: "qr.replay.refused")
    // A code whose screen closed.
    let voided = try await world.mac.call("invite")
    try await world.mac.call("void") { $0.codeId = voided["codeId"]?.string }
    let afterVoid = try await world.phone.call("pairProbe") { $0.qr = voided["qr"]?.string }
    await results.outcome(
      afterVoid["paired"]?.bool == true, "qr.void.accepted", else: "qr.void.refused")
    // A wrong key, then the same code with its right key: the failure did not use it up.
    let code = try await world.mac.call("invite")
    let qr = code["qr"]?.string ?? ""
    let wrong = try await world.phone.call("pairProbe") { $0.qr = Self.wrongKey(qr) }
    await results.outcome(
      wrong["paired"]?.bool == true, "qr.wrongKey.accepted", else: "qr.wrongKey.refused")
    let right = try await world.phone.call("pairProbe") { $0.qr = qr }
    await results.outcome(
      right["paired"]?.bool == true, "qr.afterWrongKey.paired", else: "qr.afterWrongKey.refused")
  }

  /// The same QR text with one bit of its one-time key flipped.
  private static func wrongKey(_ text: String) -> String {
    let prefix = PairingInvitation.prefix
    guard text.hasPrefix(prefix),
      let json = Data(base64URL: String(text.dropFirst(prefix.count))),
      case .object(var members)? = try? JSONValue.parse(json),
      case .string(let key)? = members["k"], var bytes = Data(base64URL: key)
    else { return text }
    bytes[0] ^= 0x01
    members["k"] = .string(bytes.base64URLText)
    guard let encoded = try? JSONLines.encoder.encode(JSONValue.object(members)) else {
      return text
    }
    return prefix + encoded.base64URLText
  }

  // MARK: Links

  private func links() async throws {
    for _ in 0..<n(50, 5) {
      let reply = try await world.phone.call("directLink") {
        $0.peer = world.macPeer
        $0.port = world.macPort
      }
      await results.add("link.direct.handshake", UInt64(reply["handshakeNs"]?.int ?? 0))
    }
    for _ in 0..<n(50, 5) {
      let reply = try await world.phone.call("relayLink") { $0.peer = world.macPeer }
      await results.add("link.relay.handshake", UInt64(reply["handshakeNs"]?.int ?? 0))
    }
    try await world.ipad.call("directLink") {
      $0.peer = world.macPeer
      $0.port = world.macPort
    }
    try await world.ipad.call("relayLink") { $0.peer = world.macPeer }
    try await waitRoutes(world.phone, to: world.macPeer, count: 2)
    try await waitRoutes(world.mac, to: world.phonePeer, count: 2)
  }

  private func waitRoutes(_ device: S2Child, to peer: S2Peer, count: Int) async throws {
    let linked = try await device.poll(
      "routes", configure: { $0.peer = peer },
      until: { ($0["routes"]?.array?.count ?? 0) == count })
    if !linked { throw DriverError.timeout("\(device.name) routes") }
  }

  // MARK: Lease operations against the relay authority

  private func leaseOperations() async throws {
    for device in [world.phone, world.mac] {
      let reply = try await device.call("leaseBench", timeout: .seconds(300)) {
        $0.count = n(300, 20)
      }
      for (key, series) in [
        ("claimNs", "lease.claim"), ("renewNs", "lease.renew"),
        ("reclaimNs", "lease.reclaimAfterRelease"),
      ] {
        await results.add(series, (reply[key]?.array ?? []).compactMap { $0.int.map(UInt64.init) })
      }
    }
  }

  // MARK: Replica lag (S2.6)

  private func claimAndRenew(
    _ device: S2Child, _ id: String, ttl: Int64 = 6_000, every: Int64 = 2_000
  )
    async throws
  {
    let claim = try await device.call("claim") {
      $0.conversation = id
      $0.ttlMs = ttl
    }
    guard claim["granted"]?.bool == true else { throw DriverError.invalid("claim \(id)") }
    try await device.call("renew") {
      $0.conversation = id
      $0.everyMs = every
    }
  }

  private func waitRunner(_ device: S2Child, _ id: String, runner: S2Peer) async throws {
    let seen = try await device.poll(
      "lease", configure: { $0.conversation = id },
      until: { $0["runner"]?.string == runner.deviceId })
    if !seen { throw DriverError.timeout("\(device.name) sees runner of \(id)") }
  }

  private func waitRseq(
    _ device: S2Child, _ id: String, atLeast rseq: Int64, timeout: Duration = .seconds(60)
  )
    async throws
  {
    let reached = try await device.poll(
      "lease", timeout: timeout, configure: { $0.conversation = id },
      until: { ($0["lastRseq"]?.int ?? 0) >= rseq })
    if !reached { throw DriverError.timeout("\(device.name) rseq \(rseq) of \(id)") }
  }

  /// Lag per change: the replica's `applied` time minus the runner's `committed` time.
  private func lag(_ id: String, runner: S2Child, replica: S2Child) async -> [UInt64] {
    var committed: [Int64: UInt64] = [:]
    for event in await runner.events("committed", conversation: id) {
      if let rseq = event.rseq { committed[rseq] = event.at }
    }
    return await replica.events("applied", conversation: id).compactMap { event in
      guard let rseq = event.rseq, let start = committed[rseq], event.at >= start else {
        return nil
      }
      return event.at - start
    }
  }

  private func replicaLag() async throws {
    let paced = n(500, 40)
    let burst = n(1_000, 60)
    for route in ["direct", "relay"] {
      if route == "relay" {
        try await world.phone.call("dropLinks") {
          $0.peer = world.macPeer
          $0.route = "direct"
        }
        try await waitRoutes(world.phone, to: world.macPeer, count: 1)
        try await waitRoutes(world.mac, to: world.phonePeer, count: 1)
      }
      let id = conversation()
      try await claimAndRenew(world.mac, id)
      try await waitRunner(world.phone, id, runner: world.macPeer)
      try await world.mac.call("commitStream", timeout: .seconds(300)) {
        $0.conversation = id
        $0.count = paced
        $0.intervalMs = 20
        $0.label = "paced \(canary.value)"
      }
      try await waitRseq(world.phone, id, atLeast: Int64(paced))
      await results.add(
        "replica.\(route).paced20ms", await lag(id, runner: world.mac, replica: world.phone))
      let burstID = conversation()
      try await claimAndRenew(world.mac, burstID)
      try await waitRunner(world.phone, burstID, runner: world.macPeer)
      try await world.mac.call("commitStream", timeout: .seconds(300)) {
        $0.conversation = burstID
        $0.count = burst
        $0.label = "burst \(canary.value)"
      }
      try await waitRseq(world.phone, burstID, atLeast: Int64(burst))
      await results.add(
        "replica.\(route).burst", await lag(burstID, runner: world.mac, replica: world.phone))
      await checkOrder(burstID, replica: world.phone, expected: burst, label: "replica.\(route)")
    }
    try await world.phone.call("directLink") {
      $0.peer = world.macPeer
      $0.port = world.macPort
    }
    try await waitRoutes(world.phone, to: world.macPeer, count: 2)
  }

  /// Every rseq applied exactly once, in order.
  private func checkOrder(_ id: String, replica: S2Child, expected: Int, label: String) async {
    let applied = await replica.events("applied", conversation: id).compactMap(\.rseq)
    let inOrder = applied == Array(1...Int64(expected))
    await results.outcome(inOrder, "\(label).order.ok", else: "\(label).order.broken")
    await results.count(
      "\(label).duplicates", await replica.events("duplicate", conversation: id).count)
  }

  // MARK: Forwarding (S2.8)

  private func forwarding() async throws {
    let id = conversation()
    try await claimAndRenew(world.mac, id)
    try await waitRunner(world.phone, id, runner: world.macPeer)
    var requests = Set<String>()
    var resent = 0
    for route in ["direct", "relay"] {
      for index in 0..<n(200, 10) {
        let request = DeviceULID.make()
        requests.insert(request)
        let before = try await world.phone.call("lease") { $0.conversation = id }
        let start = before["lastRseq"]?.int ?? 0
        let reply = try await world.phone.call("forward") {
          $0.conversation = id
          $0.requestId = request
          $0.text = "forwarded \(index) \(canary.value)"
          $0.route = route
        }
        guard reply["error"]?.string == nil, let messageID = reply["messageId"]?.string else {
          await results.count("forward.\(route).failed")
          continue
        }
        await results.add("forward.\(route).admission", UInt64(reply["rttNs"]?.int ?? 0))
        // The admission and its three answer chunks replicate back to the iPhone.
        try await waitRseq(world.phone, id, atLeast: start + 4)
        if let startedAt = reply["startedAt"]?.int,
          let answered = await world.phone.events("applied", conversation: id).first(where: {
            $0.rseq == start + 4
          }), let elapsed = s2Elapsed(from: UInt64(startedAt), to: answered.at)
        {
          await results.add("forward.\(route).answered", elapsed)
        }
        if index % 10 == 0 {
          resent += 1
          let again = try await world.phone.call("forward") {
            $0.conversation = id
            $0.requestId = request
            $0.text = "forwarded \(index) \(canary.value)"
            $0.route = route == "direct" ? "relay" : "direct"
          }
          await results.outcome(
            again["messageId"]?.string == messageID, "forward.resent.sameResult",
            else: "forward.resent.different")
        }
      }
    }
    let admitted = await world.mac.events("forwardAdmitted", conversation: id).count
    let duplicates = await world.mac.events("forwardDuplicate", conversation: id).count
    await results.set("forward.uniqueRequests", requests.count)
    await results.set("forward.admissions", admitted)
    await results.set("forward.duplicatesAnswered", duplicates)
    await results.set("forward.resent", resent)
    let stillMac = try await world.phone.call("lease") { $0.conversation = id }
    await results.outcome(
      stillMac["runner"]?.string == world.macPeer.deviceId, "forward.leaseStayed",
      else: "forward.leaseMoved")
  }

  // MARK: Hand-overs, fencing and two writers (S2.5, S2.7)

  private func handOvers() async throws {
    let chat = conversation("cht")
    let session = conversation("ses")
    try await claimAndRenew(world.phone, chat)
    try await claimAndRenew(world.mac, session)
    try await waitRunner(world.mac, chat, runner: world.phonePeer)
    try await waitRunner(world.phone, session, runner: world.macPeer)
    let rounds = n(100, 10)
    let writeMs = quick ? 6_000 : 40_000
    async let loops = withThrowingTaskGroup(of: (what: String, reply: JSONValue).self) { group in
      for device in [world.mac, world.phone] {
        for id in [chat, session] {
          group.addTask {
            let reply = try await device.call(
              "writeLoop", timeout: .seconds(writeMs / 1_000 + 60)
            ) {
              $0.conversation = id
              $0.durationMs = writeMs
              $0.intervalUs = 2_000
              $0.label = "loop \(canary.value)"
            }
            return ("\(device.name) hand-over writes of \(id)", reply)
          }
        }
      }
      var replies: [(what: String, reply: JSONValue)] = []
      for try await reply in group { replies.append(reply) }
      return replies
    }
    var staleRefused = 0
    var staleAccepted = 0
    for round in 0..<rounds {
      let (target, other, otherPeer) =
        round % 2 == 0
        ? (world.mac, world.phone, world.phonePeer) : (world.phone, world.mac, world.macPeer)
      try await waitRunner(target, chat, runner: otherPeer)
      let reply = try await target.call("rebalance") { $0.conversation = chat }
      await results.add("handover.rebalance", UInt64(reply["durationNs"]?.int ?? 0))
      let stale = try await other.call("staleWrite") {
        $0.conversation = chat
        $0.label = "stale after round \(round)"
      }
      if stale["storeRefused"]?.bool == true { staleRefused += 1 } else { staleAccepted += 1 }
    }
    // Only the fence or a device's membership refuses a write; any other failure is a batch
    // error (``S2Writes``).
    for writes in try await loops.map({ try S2Writes($0.reply, of: $0.what) }) {
      await results.count("writes.accepted", writes.accepted)
      await results.count("writes.refused", writes.refused)
    }
    await results.set("stale.local.refused", staleRefused)
    await results.set("stale.local.accepted", staleAccepted)
    let rejectedByPeer =
      await world.mac.events("staleRejectedByPeer", conversation: chat).count
      + world.phone.events("staleRejectedByPeer", conversation: chat).count
    await results.set("stale.forged.rejectedByPeer", rejectedByPeer)
    await results.set("stale.forged.sent", rounds)
    try await twoWriterAudit(chat, .chat)
    try await twoWriterAudit(session, .session)
  }

  /// Audits both devices' accepted commits and requires the history to be large enough to
  /// prove something: every commit with an epoch, and what `history` says must be seen.
  private func twoWriterAudit(_ id: String, _ history: S2AuditedHistory) async throws {
    let label = history.rawValue
    let audit = S2TwoWriterAudit(
      await world.mac.events("committed", conversation: id).map { ($0, "mac") }
        + world.phone.events("committed", conversation: id).map { ($0, "phone") })
    await results.set("audit.\(label).commits", audit.commits)
    await results.set("audit.\(label).epochs", audit.epochs)
    await results.set("audit.\(label).writers", audit.writers)
    await results.set("audit.\(label).commitsWithoutEpoch", audit.commitsWithoutEpoch)
    await results.set("audit.\(label).epochWentBackwards", audit.epochWentBackwards)
    await results.set("audit.\(label).twoWriterEpochs", audit.twoWriterEpochs)
    let fenced =
      await world.mac.events("fenced", conversation: id).count
      + world.phone.events("fenced", conversation: id).count
    await results.set("audit.\(label).replicaRejections", fenced)
    await results.set("audit.\(label).requiredWriters", history.writers)
    await results.set("audit.\(label).requiredEpochs", history.epochs)
    try audit.requireObserved(writers: history.writers, epochs: history.epochs)
  }

  // MARK: Expiry take-over with the runner frozen (S2.5), then rebalancing back

  private func expiryTakeOver() async throws {
    let ttl: Int64 = 3_000
    for device in [world.mac, world.phone] {
      try await device.call("configure") {
        $0.ttlMs = ttl
        $0.everyMs = 1_000
      }
    }
    let id = conversation()
    try await claimAndRenew(world.mac, id, ttl: ttl, every: 1_000)
    for cycle in 0..<n(20, 2) {
      try await waitRunner(world.phone, id, runner: world.macPeer)
      let beforeFreeze = try await world.mac.call("commitStream") {
        $0.conversation = id
        $0.count = 1
        $0.label = "before expiry \(cycle) \(canary.value)"
      }
      guard beforeFreeze["accepted"]?.int == 1 else {
        throw DriverError.invalid("expiry runner did not write before freeze")
      }
      let head = try await world.mac.call("lease") { $0.conversation = id }
      try await waitRseq(world.phone, id, atLeast: head["lastRseq"]?.int ?? 0)
      await results.count("expiry.beforeFreeze.accepted")
      try await Task.sleep(for: .milliseconds(Int.random(in: 0..<1_000)))
      let frozen = now()
      world.mac.process.signal(SIGSTOP)
      let taken: JSONValue
      do {
        taken = try await world.phone.call("takeOver", timeout: .seconds(30)) {
          $0.conversation = id
          $0.timeoutMs = 15_000
        }
      } catch {
        world.mac.process.signal(SIGCONT)
        throw error
      }
      if let started = taken["startedAt"]?.int, let duration = taken["durationNs"]?.int {
        await results.add("expiry.takeOverAfterFreeze", UInt64(started + duration) - frozen)
      }
      try await world.phone.call("renew") {
        $0.conversation = id
        $0.everyMs = 1_000
      }
      world.mac.process.signal(SIGCONT)
      // The frozen writer was quiescent before SIGSTOP, so this is not a deliberately
      // stranded reservation. On resume both processes attempt real fenced store commits.
      async let oldWrites = world.mac.call("writeLoop") {
        $0.conversation = id
        $0.durationMs = 1_000
        $0.intervalUs = 2_000
        $0.label = "expired old runner \(cycle)"
      }
      async let newWrites = world.phone.call("writeLoop") {
        $0.conversation = id
        $0.durationMs = 1_000
        $0.intervalUs = 2_000
        $0.label = "expiry successor \(cycle) \(canary.value)"
      }
      let (oldReply, newReply) = try await (oldWrites, newWrites)
      let old = try S2Writes(oldReply, of: "expired old runner's writes")
      let new = try S2Writes(newReply, of: "expiry successor's writes")
      let oldAccepted = old.accepted
      let oldRefused = old.refused
      let newAccepted = new.accepted
      await results.count("expiry.oldRunner.concurrentAccepted", oldAccepted)
      await results.count("expiry.oldRunner.concurrentRefused", oldRefused)
      await results.count("expiry.successor.concurrentAccepted", newAccepted)
      guard oldAccepted == 0, oldRefused > 0, newAccepted > 0 else {
        throw DriverError.invalid("expiry concurrent writing was unsafe or vacuous")
      }
      let stale = try await world.mac.call("staleWrite") {
        $0.conversation = id
        $0.label = "after freeze \(cycle)"
      }
      await results.outcome(
        stale["storeRefused"]?.bool == true, "expiry.staleRefused", else: "expiry.staleAccepted")
      try await waitRunner(world.mac, id, runner: world.phonePeer)
      let back = try await world.mac.call("rebalance") { $0.conversation = id }
      await results.add("expiry.rebalanceBack", UInt64(back["durationNs"]?.int ?? 0))
    }
    await results.set(
      "expiry.renewRefusedOnMac", await world.mac.events("renewRefused", conversation: id).count)
    try await twoWriterAudit(id, .expiry)
  }

  // MARK: Store-and-forward through the relay (S2.4)

  private func storeAndForward() async throws {
    try await world.phone.call("dropLinks") {
      $0.peer = world.macPeer
      $0.route = "direct"
    }
    try await waitRoutes(world.phone, to: world.macPeer, count: 1)
    let id = conversation()
    try await claimAndRenew(world.mac, id)
    try await waitRunner(world.phone, id, runner: world.macPeer)
    var expected: Int64 = 0
    for _ in 0..<n(10, 2) {
      try await world.phone.call("relayOffline")
      try await Task.sleep(for: .milliseconds(200))
      try await world.mac.call("commitStream") {
        $0.conversation = id
        $0.count = 100
        $0.label = "while offline \(canary.value)"
      }
      expected += 100
      try await Task.sleep(for: .milliseconds(100))
      let before = try await world.phone.call("lease") { $0.conversation = id }
      await results.outcome(
        (before["lastRseq"]?.int ?? 0) < expected, "sf.heldWhileOffline",
        else: "sf.deliveredWhileOffline")
      let started = now()
      try await world.phone.call("relayOnline")
      try await waitRseq(world.phone, id, atLeast: expected)
      if let last = await world.phone.events("applied", conversation: id).first(where: {
        $0.rseq == expected
      }), let elapsed = s2Elapsed(from: started, to: last.at) {
        await results.add("sf.catchUp100", elapsed)
      }
    }
    await checkOrder(id, replica: world.phone, expected: Int(expected), label: "sf")
    try await world.phone.call("directLink") {
      $0.peer = world.macPeer
      $0.port = world.macPort
    }
  }

  // MARK: Revocation (S2.1)

  private func revocation() async throws {
    // The device that will be revoked holds a lease, commits and has a renewal accepted first,
    // so that "nothing afterwards" says something (D133).
    let held = conversation()
    try await claimAndRenew(world.ipad, held)
    try await waitRunner(world.mac, held, runner: world.ipadPeer)
    let written = try await world.ipad.call("commitStream") {
      $0.conversation = held
      $0.count = 3
      $0.label = "held before revocation \(canary.value)"
    }
    guard written["accepted"]?.int == 3 else {
      throw DriverError.invalid("device to be revoked could not commit")
    }
    try await waitRseq(world.mac, held, atLeast: 3)
    let renewalDeadline = ContinuousClock.now + .seconds(15)
    while await world.ipad.events("renewed", conversation: held).isEmpty {
      guard ContinuousClock.now < renewalDeadline else {
        throw DriverError.timeout("renewal before the revocation")
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    let lease = try await world.ipad.call("lease") { $0.conversation = held }
    guard let heldEpoch = lease["epoch"]?.int, lease["runner"]?.string == world.ipadPeer.deviceId
    else { throw DriverError.invalid("device to be revoked does not hold its lease") }
    await results.count("revoke.lease.held")
    let reply = try await world.mac.call("revoke") { $0.peer = world.ipadPeer }
    let revokedAt = now()
    let revokedAtWall = DeviceClock.wallMilliseconds()
    await results.set("revoke.groupEpoch", Int(reply["groupEpoch"]?.int ?? 0))
    await results.base.revoked(world.ipadPeer.deviceId, at: revokedAtWall, conversation: held)
    // The probe waits for the iPad to report that it read its removal: no fixed settle.
    try await S2RevocationProbe(
      revoked: world.ipad, witness: world.mac, relay: world.relay, revokedPeer: world.ipadPeer,
      witnessPeer: world.macPeer, witnessPort: world.macPort, relayPort: world.relayPort,
      held: held, heldEpoch: heldEpoch, revokedAt: revokedAt, revokedAtWall: revokedAtWall,
      label: "after revocation \(canary.value)"
    ).run(conversation: conversation(), results: results.base)
  }

  // MARK: Content audit (S2.4, "content readable by the relay")

  static func contentAudit(world: S2World, canary: Canary, results: S2Results) async throws {
    // Every label and forwarded text above carried the run's canary; the scanner looks for it in
    // every encoding. The relay's files (its journal of every payload it held, and its summary)
    // must have none, while the Mac's store, which holds the plaintext by design, must show it,
    // proving the scan can see it.
    let scanner = try CanaryScanner(canaries: [canary])
    let relay = try scanner.scan([world.relayDirectory])
    let control = try scanner.scan([
      world.directories["mac", default: world.relayDirectory].appendingPathComponent("store")
    ])
    await results.set("audit.relay.filesScanned", relay.filesScanned)
    await results.set("audit.relay.bytesScanned", relay.bytesScanned)
    await results.set("audit.relay.hits", relay.hits.count)
    await results.set("audit.control.hits", control.hits.count)
  }

  // MARK: S2.12 authority load

  static func loadMatrix(
    _ options: S2Options, logs: URL, results: S2Results, owned: inout [S2Child]
  ) async throws {
    struct Config {
      let name: String
      let processes: Int
      let users: Int
      let active: Int
      let idle: Int
      let activeRenew: Int64
      let activeTTL: Int64
      let idleRenew: Int64
      let idleTTL: Int64
      let moves: Int
    }
    let seconds: Int64 = options.quick ? 8_000 : 60_000
    let configs: [Config] = [
      Config(
        name: "baseline-active-only", processes: 3, users: 10, active: 8, idle: 0,
        activeRenew: 1_000, activeTTL: 3_000, idleRenew: 0, idleTTL: 0, moves: 0),
      Config(
        name: "mix-idle-renewed", processes: 3, users: 10, active: 8, idle: 32,
        activeRenew: 1_000, activeTTL: 3_000, idleRenew: 10_000, idleTTL: 30_000, moves: 2),
      Config(
        name: "mix-idle-unleased", processes: 3, users: 10, active: 8, idle: 32,
        activeRenew: 1_000, activeTTL: 3_000, idleRenew: 0, idleTTL: 30_000, moves: 2),
      Config(
        name: "scaled-mix-idle-renewed", processes: 3, users: options.quick ? 20 : 100,
        active: 8, idle: 32, activeRenew: 1_000, activeTTL: 3_000, idleRenew: 10_000,
        idleTTL: 30_000, moves: 2),
    ]
    let environment = [
      "HOME": options.workDirectory.path, "TMPDIR": options.workDirectory.path + "/",
      "PATH": "/usr/bin:/bin",
    ]
    for config in configs {
      let directory = options.workDirectory.appendingPathComponent("load-\(config.name)")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let relay = try S2Child.spawn(
        name: "load-relay-\(config.name)", executable: options.executable,
        arguments: [
          "s2-relay", "--directory", directory.path, "--no-authority-journal", "--no-grant-log",
        ], environment: environment, logs: logs)
      owned.append(relay)
      guard let port = try await relay.waitFor(event: "listening")["port"]?.int else {
        throw DriverError.invalid("load relay port")
      }
      var loaders: [S2Child] = []
      for index in 0..<config.processes {
        let output = directory.appendingPathComponent("load-\(index).json")
        loaders.append(
          try S2Child.spawn(
            name: "load-\(config.name)-\(index)", executable: options.executable,
            arguments: [
              "s2-load", "--relay-port", String(port), "--users", String(config.users),
              "--active", String(config.active), "--idle", String(config.idle),
              "--active-renew-ms", String(config.activeRenew), "--active-ttl-ms",
              String(config.activeTTL), "--idle-renew-ms", String(config.idleRenew),
              "--idle-ttl-ms", String(config.idleTTL), "--moves", String(config.moves),
              "--duration-ms", String(seconds), "--output", output.path,
            ], environment: environment, logs: logs))
        owned.append(loaders[loaders.count - 1])
      }
      for loader in loaders {
        let enrollment = try await loader.waitFor(event: "loadEnrollment")
        guard let groupID = enrollment["groupId"]?.string, let peers = enrollment["peers"] else {
          throw DriverError.invalid("\(loader.name) omitted trusted load enrollment")
        }
        let roster = try JSONDecoder().decode([S2Peer].self, from: JSONLines.encoder.encode(peers))
        try await relay.call("enroll") {
          $0.groupId = groupID
          $0.peers = roster
        }
      }
      for loader in loaders { try loader.process.send(Data("enrolled".utf8)) }
      var reports: [S2LoadReport] = []
      var failures: [String] = []
      let sampleParent = options.outputDirectory.appendingPathComponent(
        "load-samples/\(config.name)", isDirectory: true)
      try FileManager.default.createDirectory(at: sampleParent, withIntermediateDirectories: true)
      for (index, loader) in loaders.enumerated() {
        let exit = await loader.process.waitForExit(timeout: .seconds(Int(seconds / 1_000) + 180))
        if exit == nil {
          loader.process.signal(SIGKILL)
          _ = await loader.process.waitForExit(timeout: .seconds(5))
          failures.append("\(loader.name) timed out")
        } else if exit != .exited(0) {
          failures.append("\(loader.name) did not exit successfully: \(String(describing: exit))")
        }
        do { try await loader.process.drainOutput() } catch {
          failures.append("\(loader.name) capture failed: \(error)")
        }
        let output = directory.appendingPathComponent("load-\(index).json")
        do {
          let report = try JSONDecoder().decode(S2LoadReport.self, from: Data(contentsOf: output))
          reports.append(report)
          await results.load(config.name, reports)
        } catch { failures.append("\(loader.name) report: \(error)") }
        // A failed worker must not skip its siblings' reports or raw observations. Attempt
        // each retention independently, including a partial sample directory on failure.
        let retained = sampleParent.appendingPathComponent(String(index), isDirectory: true)
        do {
          let samples = S2LoadProcess.samplesDirectory(for: output)
          if FileManager.default.fileExists(atPath: samples.path) {
            try FileManager.default.moveItem(at: samples, to: retained)
          } else {
            failures.append("\(loader.name) produced no raw samples")
          }
        } catch { failures.append("\(loader.name) sample retention: \(error)") }
        do {
          if !FileManager.default.fileExists(atPath: retained.path) {
            try FileManager.default.createDirectory(
              at: retained, withIntermediateDirectories: false)
          }
          try FileManager.default.moveItem(
            at: output, to: retained.appendingPathComponent("report.json"))
        } catch { failures.append("\(loader.name) report retention: \(error)") }
      }
      let relayExit: ChildExit?
      do { relayExit = try await relay.stop() } catch {
        relayExit = relay.process.exit
        failures.append("\(relay.name) capture failed: \(error)")
      }
      if relayExit != .exited(0) {
        failures.append("\(relay.name) did not shut down cleanly: \(String(describing: relayExit))")
      }
      do {
        let data = try Data(contentsOf: directory.appendingPathComponent("relay-summary.json"))
        try await results.relay(
          "load-\(config.name)", try JSONDecoder().decode(S2RelaySummary.self, from: data))
      } catch { failures.append("\(relay.name) summary: \(error)") }
      if !failures.isEmpty {
        for failure in failures { await results.fail(failure) }
        throw DriverError.invalid(
          "\(config.name) load failed; all available worker evidence was collected")
      }
    }
  }
}

extension Data {
  /// Unpadded base64url text.
  fileprivate var base64URLText: String {
    base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  /// Decodes unpadded base64url.
  fileprivate init?(base64URL text: String) {
    var standard = text.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while standard.count % 4 != 0 { standard += "=" }
    self.init(base64Encoded: standard)
  }
}
