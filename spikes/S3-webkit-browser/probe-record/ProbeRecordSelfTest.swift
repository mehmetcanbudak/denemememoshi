// Self-test for the browser lab's cookie-probe registry (D131). The registry is compiled into
// the iPhone and iPad app, which has no test target, so this runs its source on the Mac:
//
//   xcrun swiftc -D MEMOSHI_PROBE_RECORD_SELFTEST -parse-as-library \
//     -o "${TMPDIR:-/tmp}/probe-record-selftest" apps/shared/BrowserReviewProfile.swift \
//     apps/shared/MobileBrowserProbeRecord.swift \
//     spikes/S3-webkit-browser/probe-record/ProbeRecordSelfTest.swift \
//     && "${TMPDIR:-/tmp}/probe-record-selftest"
//
// Nothing is launched, no web view or cookie store exists here, and no saved registry is read.
import Foundation

@main
struct ProbeRecordSelfTest {
  typealias Registry = MobileBrowserProbeRegistry
  nonisolated(unsafe) static var failures: [String] = []

  static func check(_ condition: Bool, _ label: String, line: Int = #line) {
    if !condition { failures.append("line \(line): \(label)") }
  }

  static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
  static let day: TimeInterval = 24 * 60 * 60

  static func fresh() -> Registry { Registry(now: start) }

  /// The nonce the registry expects in a store, or a value no store can hold.
  static func nonce(_ registry: Registry, _ store: Int) -> String {
    registry.profiles.indices.contains(store)
      ? registry.profiles[store].probe?.nonce ?? "no-probe" : "no-profile"
  }

  static func main() {
    newRegistryHasNoGeneration()
    firstCheckStartsGenerationOne()
    verdictsNameTheirGeneration()
    expiredProbeIsNeitherPassNorFailureUntilReset()
    foreignValueFailsEvenAfterExpiry()
    resetKeepsEarlierFailures()
    resetRecordsTheEndingGenerationFirst()
    onlyAResetReplacesProbes()
    recordStaysSmall()
    savedRegistryRoundTrips()
    registrySavedBeforeGenerationsIsGenerationOne()
    inconsistentRegistriesAreRefused()
    if failures.isEmpty {
      print("probe-record self-test: 12 cases passed")
    } else {
      for failure in failures { print("FAILED " + failure) }
      print("probe-record self-test: \(failures.count) failed checks")
      exit(1)
    }
  }

  static func newRegistryHasNoGeneration() {
    var registry = fresh()
    check(registry.profiles.count == 2, "two profiles")
    check(registry.profiles.allSatisfy { $0.probe == nil }, "no probes yet")
    check(registry.generations.isEmpty && registry.current == nil, "no generation yet")
    check(
      registry.record(found: [], store: 0, initializing: false, at: start) == nil,
      "no verdict without a generation")
    check(registry.generations.isEmpty, "a refused verdict records nothing")
  }

  static func firstCheckStartsGenerationOne() {
    var registry = fresh()
    check(registry.startFirstGeneration(at: start) == 1, "first generation is 1")
    check(registry.current == 1, "current is 1")
    check(registry.profiles.allSatisfy { $0.probe?.setAt == start }, "both probes set now")
    check(nonce(registry, 0) != nonce(registry, 1), "distinct nonces")
    check(registry.isValid, "valid after the first generation")
  }

  static func verdictsNameTheirGeneration() {
    var registry = fresh()
    _ = registry.startFirstGeneration(at: start)
    let first = registry.record(
      found: [nonce(registry, 0)], store: 0, initializing: true, at: start)
    check(first?.verdict == .initialized, "own probe right after seeding")
    check(first?.code == "persistentCookieProbesInitialized.generation1", "code names 1")
    let later = registry.record(
      found: [nonce(registry, 1)], store: 1, initializing: false, at: start + day)
    check(later?.verdict == .retained, "own probe later")
    check(later?.code == "retainedPersistentCookieIsolationObserved.generation1", "retained 1")
    let missing = registry.record(found: [], store: 0, initializing: false, at: start + day)
    check(missing?.verdict == .failed, "a missing probe before expiry is a failure")
    check(missing?.code == "cookieIsolationFailed.generation1", "failure names 1")
    check(missing?.verdict.isPass == false, "a failure is not a pass")
    let both = registry.record(
      found: [nonce(registry, 0), nonce(registry, 1)], store: 0, initializing: false,
      at: start + day)
    check(both?.verdict == .failed, "the other store's probe here is a failure")
  }

  static func expiredProbeIsNeitherPassNorFailureUntilReset() {
    var registry = fresh()
    _ = registry.startFirstGeneration(at: start)
    let lifetime = Registry.probeLifetime
    let before = registry.record(
      found: [], store: 0, initializing: false, at: start + lifetime - 1)
    check(before?.verdict == .failed, "absent one second before expiry is a failure")
    for days in [0.0, 1, 400] {
      let verdict = registry.record(
        found: [], store: 0, initializing: false, at: start + lifetime + days * day)
      check(verdict?.verdict == .expired, "expired stays expired after \(days) more days")
      check(
        verdict?.code == "persistentCookieProbeExpiredNoIsolationVerdict.generation1",
        "expired names 1")
      check(verdict?.verdict.isPass == false, "expired is not a pass")
    }
    let resetAt = start + lifetime + 2 * day
    let ended = registry.reset(found: [[], []], at: resetAt)
    check(ended?.generation == 2, "a reset starts generation 2")
    check(
      ended?.closing.map(\.code)
        == Array(repeating: "persistentCookieProbeExpiredNoIsolationVerdict.generation1", count: 2),
      "and first records the expired generation as expired, not as a pass")
    let seeded = registry.record(
      found: [nonce(registry, 0)], store: 0, initializing: true, at: resetAt)
    check(seeded?.code == "persistentCookieProbesInitialized.generation2", "new probes, 2")
    let lost = registry.record(found: [], store: 1, initializing: true, at: resetAt)
    check(lost?.code == "cookieIsolationFailed.generation2", "a probe lost in a reset fails")
  }

  static func foreignValueFailsEvenAfterExpiry() {
    var registry = fresh()
    _ = registry.startFirstGeneration(at: start)
    let verdict = registry.record(
      found: ["someone-else"], store: 0, initializing: false,
      at: start + Registry.probeLifetime + day)
    check(verdict?.verdict == .failed, "a foreign value is a failure, expired or not")
  }

  static func resetKeepsEarlierFailures() {
    var registry = fresh()
    _ = registry.startFirstGeneration(at: start)
    _ = registry.record(found: [], store: 0, initializing: false, at: start + day)
    _ = registry.record(found: [nonce(registry, 1)], store: 1, initializing: false, at: start + day)
    let oldNonces = [nonce(registry, 0), nonce(registry, 1)]
    let ended = registry.reset(found: [[], [oldNonces[1]]], at: start + 2 * day)
    check(ended?.generation == 2, "reset")
    check(!oldNonces.contains(nonce(registry, 0)), "store 1 has a new nonce")
    check(!oldNonces.contains(nonce(registry, 1)), "store 2 has a new nonce")
    for store in 0...1 {
      let verdict = registry.record(
        found: [nonce(registry, store)], store: store, initializing: true, at: start + 2 * day)
      check(verdict?.verdict.isPass == true, "the new generation passes")
    }
    check(registry.generations.count == 2, "two generations")
    let first = registry.generations.first?.tallies ?? []
    let failures = first.filter { $0.verdict == .failed }
    check(
      failures.map(\.count) == [2] && failures.first?.store == 1,
      "generation 1 keeps its earlier failure and the one read when it ended")
    check(
      first.filter { $0.verdict == .retained }.map(\.count) == [2],
      "and its earlier pass and the one read when it ended")
    check(first.count == 2, "nothing else was added to generation 1 or removed from it")
    check(
      registry.generations.last?.tallies.contains { $0.verdict == .failed } == false,
      "and is not counted against generation 2")
    let stale = registry.record(
      found: [oldNonces[0]], store: 0, initializing: false, at: start + 3 * day)
    check(stale?.code == "cookieIsolationFailed.generation2", "an old probe no longer passes")
  }

  /// The gap a reset must not have: a probe lost since the last check, then Reset instead of
  /// Check. The loss is read and recorded under the generation that ends.
  static func resetRecordsTheEndingGenerationFirst() {
    var registry = fresh()
    _ = registry.startFirstGeneration(at: start)
    for store in 0...1 {
      _ = registry.record(
        found: [nonce(registry, store)], store: store, initializing: true, at: start)
    }
    let kept = nonce(registry, 0)
    let ended = registry.reset(found: [[kept], []], at: start + day)
    check(ended?.generation == 2, "generation 2 starts")
    check(
      ended?.closing.map(\.code) == [
        "retainedPersistentCookieIsolationObserved.generation1",
        "cookieIsolationFailed.generation1",
      ], "both stores are read under generation 1 first")
    for store in 0...1 {
      _ = registry.record(
        found: [nonce(registry, store)], store: store, initializing: true, at: start + day)
    }
    let first = registry.generations.first?.tallies ?? []
    check(
      first.contains { $0.store == 2 && $0.verdict == .failed && $0.count == 1 },
      "the loss is in the record of generation 1")
    check(
      registry.generations.last?.tallies.allSatisfy { $0.verdict == .initialized } == true,
      "generation 2 has only its own verdicts")
    check(
      registry.generations.flatMap(\.tallies).contains { !$0.verdict.isPass },
      "so the record is not passes only")
    var other = fresh()
    _ = other.startFirstGeneration(at: start)
    let swapped = other.reset(found: [[nonce(other, 1)], [nonce(other, 1)]], at: start + day)
    check(
      swapped?.closing.first?.code == "cookieIsolationFailed.generation1",
      "the other store's probe found at a reset is recorded as a failure too")
  }

  static func onlyAResetReplacesProbes() {
    var registry = fresh()
    check(registry.reset(found: [[], []], at: start) == nil, "no reset before generation 1")
    check(registry.generations.isEmpty, "and nothing changes")
    _ = registry.startFirstGeneration(at: start)
    let before = registry
    check(registry.startFirstGeneration(at: start + day) == nil, "generation 1 starts only once")
    check(registry == before, "a second start changes nothing")
    check(registry.reset(found: [[]], at: start + day) == nil, "a reset needs both stores read")
    check(registry.reset(found: [[], [], []], at: start + day) == nil, "exactly both")
    check(registry == before, "a refused reset changes nothing")
  }

  static func recordStaysSmall() {
    var registry = fresh()
    _ = registry.startFirstGeneration(at: start)
    for second in 0..<1_000 {
      _ = registry.record(
        found: [nonce(registry, 0)], store: 0, initializing: false,
        at: start + TimeInterval(second))
    }
    let tallies = registry.generations.first?.tallies ?? []
    check(tallies.map(\.count) == [1_000], "one tally for 1,000 equal verdicts")
    check(tallies.first?.lastAt == start + 999, "with the last time")
  }

  static func savedRegistryRoundTrips() {
    var registry = fresh()
    _ = registry.startFirstGeneration(at: start)
    _ = registry.record(found: [], store: 1, initializing: false, at: start + day)
    _ = registry.reset(found: [[], []], at: start + 2 * day)
    guard let data = try? registry.encoded() else {
      check(false, "encodes")
      return
    }
    check(Registry.decode(data) == registry, "decodes to the same registry")
    check(Registry.decode(Data("not json".utf8)) == nil, "unreadable bytes are refused")
  }

  static func registrySavedBeforeGenerationsIsGenerationOne() {
    let seeded = (1...2).map {
      BrowserReviewProfile(
        id: UUID(), name: "Mobile fixture review \($0)", createdAt: start,
        probe: BrowserIsolationProbe(nonce: "nonce-\($0)", setAt: start + TimeInterval($0)))
    }
    let empty = seeded.map {
      BrowserReviewProfile(id: $0.id, name: $0.name, createdAt: $0.createdAt, probe: nil)
    }
    guard let seededData = try? JSONEncoder().encode(seeded),
      let emptyData = try? JSONEncoder().encode(empty)
    else {
      check(false, "legacy bytes")
      return
    }
    let old = Registry.decode(seededData)
    check(old?.profiles == seeded, "the saved probes are kept as they are")
    check(old?.generations.map(\.number) == [1], "and are generation 1")
    check(old?.generations.first?.startedAt == start + 1, "started when the first was set")
    check(old?.generations.first?.tallies.isEmpty == true, "with no recorded verdicts")
    let unseeded = Registry.decode(emptyData)
    check(unseeded?.profiles == empty && unseeded?.generations.isEmpty == true, "no probes: none")
  }

  static func inconsistentRegistriesAreRefused() {
    var registry = fresh()
    _ = registry.startFirstGeneration(at: start)
    _ = registry.reset(found: [[], []], at: start + day)
    guard let data = try? registry.encoded(),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let profiles = object["profiles"] as? [[String: Any]],
      let generations = object["generations"] as? [[String: Any]]
    else {
      check(false, "saved form is an object with profiles and generations")
      return
    }
    func refused(_ label: String, _ change: (inout [String: Any]) -> Void) {
      var changed = object
      change(&changed)
      let bytes = (try? JSONSerialization.data(withJSONObject: changed)) ?? Data()
      check(Registry.decode(bytes) == nil, label)
    }
    refused("a generation number with a gap") { $0["generations"] = [generations[1]] }
    refused("probes without a generation") { $0["generations"] = [[String: Any]]() }
    refused("a generation without probes") {
      $0["profiles"] = profiles.map { profile in profile.filter { $0.key != "probe" } }
    }
    refused("one profile") { $0["profiles"] = [profiles[0]] }
    refused("the same profile twice") { $0["profiles"] = [profiles[0], profiles[0]] }
    refused("a probe in only one store") {
      $0["profiles"] = [profiles[0], profiles[1].filter { $0.key != "probe" }]
    }
  }
}
