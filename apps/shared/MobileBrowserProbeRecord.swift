// The self-test flag compiles this file on the Mac; see
// spikes/S3-webkit-browser/probe-record/ProbeRecordSelfTest.swift.
#if os(iOS) || MEMOSHI_PROBE_RECORD_SELFTEST
  import Foundation

  /// The mobile browser lab's two persistent fixture profiles, the cookie probes expected in
  /// their stores, and every verdict recorded for those probes (D131). It is saved as one
  /// value, so the expected probes and their generation cannot disagree after an interruption.
  ///
  /// A generation is the pair of probes created together, numbered from 1 without gaps. Only an
  /// explicit reset starts a later one. Verdicts are kept per generation, and a reset only adds
  /// a generation, so it can never turn an earlier failure into a pass.
  struct MobileBrowserProbeRegistry: Codable, Equatable, Sendable {
    /// What one check found in one store. The raw value is the observation code's first part.
    enum Verdict: String, Codable, CaseIterable, Sendable {
      /// The store holds exactly its own probe, right after that probe was set.
      case initialized = "persistentCookieProbesInitialized"
      /// The store still holds exactly its own probe.
      case retained = "retainedPersistentCookieIsolationObserved"
      /// The probe is absent after its own expiry date: that says nothing about the store.
      case expired = "persistentCookieProbeExpiredNoIsolationVerdict"
      /// The probe is missing before it could expire, or the store holds another value.
      case failed = "cookieIsolationFailed"

      var isPass: Bool { self == .initialized || self == .retained }
    }

    /// How often one store got one verdict in a generation, and when last. Counting keeps the
    /// record small however often a check runs, without dropping any verdict.
    struct Tally: Codable, Equatable, Sendable, Identifiable {
      /// 1 or 2, as the lab names its two review profiles.
      let store: Int
      let verdict: Verdict
      var count: Int
      var lastAt: Date
      var id: String { "\(store).\(verdict.rawValue)" }
    }

    struct Generation: Codable, Equatable, Sendable, Identifiable {
      let number: Int
      let startedAt: Date
      var tallies: [Tally]
      var id: Int { number }
    }

    /// How long a probe cookie lives; WebKit drops it afterwards.
    static let probeLifetime: TimeInterval = 30 * 24 * 60 * 60

    private(set) var profiles: [BrowserReviewProfile]
    private(set) var generations: [Generation]

    /// Two new fixture profiles with no probe and no generation yet.
    init(now: Date) {
      profiles = (1...2).map {
        BrowserReviewProfile(
          id: UUID(), name: "Mobile fixture review \($0)", createdAt: now, probe: nil)
      }
      generations = []
    }

    /// The generation whose probes the stores are expected to hold now.
    var current: Int? { generations.last?.number }

    /// Exactly two distinct profiles; probes in both stores or in neither; distinct nonces; a
    /// generation exactly when there are probes; generation numbers 1, 2, 3… without a gap.
    var isValid: Bool {
      let nonces = profiles.compactMap { $0.probe?.nonce }
      return profiles.count == 2 && Set(profiles.map(\.id)).count == 2
        && (nonces.isEmpty || nonces.count == 2) && Set(nonces).count == nonces.count
        && nonces.isEmpty == generations.isEmpty
        && generations.enumerated().allSatisfy { $0.element.number == $0.offset + 1 }
        && generations.allSatisfy { $0.tallies.allSatisfy { (1...2).contains($0.store) } }
    }

    /// Reads a saved registry, or the bare profile list saved before generations existed: its
    /// probes, if any, are generation 1 with no recorded verdicts. Anything unreadable or
    /// inconsistent is refused; the caller never replaces it.
    static func decode(_ data: Data) -> MobileBrowserProbeRegistry? {
      let decoder = JSONDecoder()
      var registry: MobileBrowserProbeRegistry
      if let saved = try? decoder.decode(MobileBrowserProbeRegistry.self, from: data) {
        registry = saved
      } else if let profiles = try? decoder.decode([BrowserReviewProfile].self, from: data) {
        registry = MobileBrowserProbeRegistry(now: Date())
        registry.profiles = profiles
        if let startedAt = profiles.compactMap({ $0.probe?.setAt }).min() {
          registry.generations = [Generation(number: 1, startedAt: startedAt, tallies: [])]
        }
      } else {
        return nil
      }
      return registry.isValid ? registry : nil
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    /// Starts generation 1 at the first check. Nil, changing nothing, once a generation exists:
    /// only `reset` replaces probes.
    mutating func startFirstGeneration(at now: Date) -> Int? {
      current == nil ? startGeneration(at: now) : nil
    }

    /// The explicit reset: ends the current generation and starts the next. `found` is what each
    /// store holds now, in store order. Those verdicts are recorded under the generation that
    /// ends before the new one starts, so a reset can never hide a probe that was lost since the
    /// last check. Nil, changing nothing, without a current generation or unless both stores
    /// were read.
    mutating func reset(
      found: [Set<String>], at now: Date
    ) -> (closing: [(verdict: Verdict, code: String)], generation: Int)? {
      guard current != nil, found.count == profiles.count else { return nil }
      var ended = self
      var closing: [(verdict: Verdict, code: String)] = []
      for (index, values) in found.enumerated() {
        guard
          let verdict = ended.record(found: values, store: index, initializing: false, at: now)
        else { return nil }
        closing.append(verdict)
      }
      let generation = ended.startGeneration(at: now)
      self = ended
      return (closing, generation)
    }

    /// New nonces for both stores and the next generation number. Earlier generations stay as
    /// they are. The caller saves the registry before it touches a cookie, so an interrupted
    /// start reads as a failure of the new generation, never a pass.
    private mutating func startGeneration(at now: Date) -> Int {
      let number = (current ?? 0) + 1
      for index in profiles.indices {
        profiles[index].probe = BrowserIsolationProbe(nonce: UUID().uuidString, setAt: now)
      }
      generations.append(Generation(number: number, startedAt: now, tallies: []))
      return number
    }

    /// Classifies the probe values found in one store (index 0 or 1) and records the verdict
    /// under the current generation. The returned code names that generation. Nil, recording
    /// nothing, when there is no generation or no such store.
    mutating func record(
      found values: Set<String>, store index: Int, initializing: Bool, at now: Date
    ) -> (verdict: Verdict, code: String)? {
      guard let number = current, profiles.indices.contains(index),
        let probe = profiles[index].probe
      else { return nil }
      let verdict: Verdict
      if values == [probe.nonce] {
        verdict = initializing ? .initialized : .retained
      } else if values.isEmpty, now >= probe.setAt.addingTimeInterval(Self.probeLifetime) {
        verdict = .expired
      } else {
        verdict = .failed
      }
      let last = generations.count - 1
      if let tally = generations[last].tallies.firstIndex(where: {
        $0.store == index + 1 && $0.verdict == verdict
      }) {
        generations[last].tallies[tally].count += 1
        generations[last].tallies[tally].lastAt = now
      } else {
        generations[last].tallies.append(
          Tally(store: index + 1, verdict: verdict, count: 1, lastAt: now))
      }
      return (verdict, "\(verdict.rawValue).generation\(number)")
    }
  }
#endif
