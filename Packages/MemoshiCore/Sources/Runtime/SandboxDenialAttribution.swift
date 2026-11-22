#if os(macOS)
  import CryptoKit
  import Darwin
  import Foundation
  import MemoshiEgress
  import MemoshiStore
  import Synchronization

  /// One Seatbelt instance: a command, a daemon life, or the reader's own probe. Its tag is the
  /// `INV` profile parameter, so the kernel ends every denial report of that instance, and of
  /// every descendant, with it (S4.7).
  public struct SandboxInvocation: Sendable, Codable, Equatable {
    /// What the Seatbelt instance runs.
    public enum Kind: String, Sendable, Codable {
      /// One command, started by the host in its own instance.
      case command
      /// One confined PiEnv daemon life; its file operations share this tag.
      case daemon
      /// The reader's liveness probe; never a bot's work.
      case probe
    }

    /// `memoshi-inv-` and 128 random bits in lowercase hex; never reused.
    public let tag: String
    /// What the instance runs.
    public let kind: Kind
    /// The bot of the computer; nil for a probe.
    public let bot: String?
    /// The conversation of the computer; nil for a probe.
    public let conversation: String?
    /// The computer; nil for a probe.
    public let computer: String?
    /// The tool call whose command this is, when it has one.
    public let call: String?
    /// SHA-256 of the argv, each argument NUL-terminated; never the command's text.
    public let command: String?
    /// Milliseconds since 1970, before the exec.
    public let startedAt: Int64

    static let prefix = "memoshi-inv-"

    static func makeTag() -> String {
      var generator = SystemRandomNumberGenerator()
      return prefix
        + (0..<16).map { _ in
          String(format: "%02x", UInt8.random(in: 0...255, using: &generator))
        }.joined()
    }

    static func isTag(_ text: Substring) -> Bool {
      guard text.utf8.starts(with: prefix.utf8) else { return false }
      let body = text.utf8.dropFirst(prefix.utf8.count)
      return body.count == 32
        && body.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func digest(_ argv: [String]) -> String {
      var hasher = SHA256()
      for argument in argv {
        hasher.update(data: Data(argument.utf8))
        hasher.update(data: Data([0]))
      }
      return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
  }

  /// The moment an invocation's leader exited. Its tag stays valid: a detached descendant keeps
  /// the instance, and its later denials still belong to this invocation.
  public struct SandboxInvocationReturn: Sendable, Codable, Equatable {
    /// The invocation's tag.
    public let tag: String
    /// Milliseconds since 1970.
    public let at: Int64
    /// The leader's exit status, when the command produced one.
    public let exitCode: Int?
  }

  /// One kernel denial report read back from the unified log.
  public struct SandboxDenial: Sendable, Codable, Equatable {
    /// Milliseconds since 1970 when the reader received it.
    public let at: Int64
    /// The log's own timestamp text.
    public let reportedAt: String?
    /// The report's last line: the tag the kernel printed.
    public let tag: String
    /// The registered invocation with that tag, or nil when it is unattributed.
    public let invocation: SandboxInvocation?
    /// `unknown_tag` (a well-formed tag this monitor does not hold: from an earlier host life,
    /// or an invocation forgotten after its return; see ``SandboxDenialMonitor``),
    /// `malformed_tag`, or `truncated` (the kernel cut the report, at about 1,011 characters,
    /// before its tag line; kept only from a process shown to be Memoshi's); nil when
    /// attributed.
    public let unattributed: String?
    /// The report without its tag line, at most 4096 bytes. Empty for `unknown_tag`: no
    /// conversation held here names it, so a purge could not remove the paths it holds.
    public let report: String
    /// For a coalesced "N duplicate reports for …" line, N; otherwise 0.
    public let duplicates: Int
    /// Received after the invocation's leader returned: from a descendant that outlived it.
    /// The tag names that process lineage; a later command that drove the descendant (through
    /// a shared file, FIFO or socket) is not traceable.
    public let afterReturn: Bool
  }

  /// A time when denials could not be read. Reports are not kept by the log system, so
  /// anything the kernel reported in a gap is lost; counts are lower bounds.
  public struct SandboxAttributionGap: Sendable, Codable, Equatable {
    /// Milliseconds since 1970 when reading stopped or had not yet been proved.
    public let from: Int64
    /// Nil while it is still open.
    public let to: Int64?
    /// `reader_starting`, `reader_stopped`, `reader_idle` (no open session), `reader_silent`
    /// (a running reader stopped returning probes; `from` is the last confirmed probe),
    /// `events_lost` (the log system said so), `report_truncated` (reports that lost their tag,
    /// counted; consecutive ones within 1 s share one gap), `report_burst` or `report_rate`
    /// (reports came faster than the log delivers reliably, so some may be missing; kernel
    /// times), `reports_dropped` (dense probe reports that never came back: a measured loss, a
    /// lower bound), `store_dropped` (denials kept here but not in the Store) or `log_dropped`
    /// (entries the optional log file could not take).
    public let reason: String
    /// Reports in a `report_truncated`, `report_burst` or `report_rate` stretch, missing probe
    /// reports for `reports_dropped`, or entries a `store_dropped` or `log_dropped` gap stands
    /// for.
    public var count: Int? = nil
  }

  /// One persisted line of the attribution log; exactly one field is set.
  public struct SandboxAttributionEntry: Sendable, Codable, Equatable {
    /// Registered before its exec.
    public var invocation: SandboxInvocation?
    /// Its leader exited.
    public var returned: SandboxInvocationReturn?
    /// A kernel report read back.
    public var denial: SandboxDenial?
    /// A gap opened, or the same gap (same `from`) closed.
    public var gap: SandboxAttributionGap?
  }

  /// Delivers the unified log's sandbox reports as ndjson lines.
  protocol SandboxReportSource: Sendable {
    /// `onEnd` runs once if the source stops on its own.
    func start(
      onLine: @escaping @Sendable (Data) -> Void, onEnd: @escaping @Sendable () -> Void
    ) throws -> any SandboxReportSubscription
  }

  protocol SandboxReportSubscription: Sendable {
    func stop()
    /// Keeps the reader alive but delivering nothing (development evidence and tests).
    func pause()
  }

  /// Makes the kernel report `reports` denials carrying `tag`, each on its own path.
  protocol SandboxReaderProbing: Sendable {
    /// How many reports one run makes the kernel emit.
    var reports: Int { get }
    func run(tag: String) async
  }

  /// Attributes every sandbox denial to the invocation whose tag the kernel printed, never by
  /// time, PID or which command is running. One per host; the reader runs while at least one
  /// sandbox session is open. Coverage starts only when a probe's own report comes back, and
  /// while a command runs a probe every `heartbeatInterval` must come back within
  /// `heartbeatBound`, or a `reader_silent` gap opens from the last confirmed probe.
  ///
  /// Its memory is bounded for the host's whole life: a returned invocation is forgotten once
  /// `returnedRetention` has passed or `retainingReturned` newer ones returned (a later denial
  /// of its tag is then `unknown_tag`; the Store still holds the invocation), the newest
  /// `retaining` denials are kept, and the newest `retainingGaps` gaps plus any still open or
  /// growing.
  public final class SandboxDenialMonitor: Sendable {
    private enum Beat {
      case wait
      case restart
      case probe(String)
    }

    private struct Probe {
      let generation: Int
      let sentAt: Int64
      /// Reports of this probe received so far.
      var answered = 0
    }

    private struct State {
      var invocations: [String: SandboxInvocation] = [:]
      var returned: [String: Int64] = [:]
      /// Returned tags and when they returned, oldest first: forgotten from the front.
      var returnedOrder: [(tag: String, at: Int64)] = []
      var probes: [String: Probe] = [:]
      var probeOrder: [String] = []
      /// Command tags registered whose leader has not returned.
      var running: Set<String> = []
      var heartbeating = false
      /// Kernel times (µs) of the latest reports, for burst detection.
      var recent: [Int64] = []
      var burstGap: Int?
      /// The `store_dropped` gap still growing; a denial the Store queue took ends it.
      var storeDropGap: Int?
      /// The `report_truncated` gap that the next truncated report within 1 s grows.
      var truncatedGap: Int?
      /// When the last probe whose report came back was sent, in this coverage.
      var lastConfirmed: Int64?
      var denials: [SandboxDenial] = []
      var oldest = 0
      /// Retained gaps by sequence (their order in this life and in the Store); `gapOrder`
      /// holds the retained sequences, ascending.
      var gaps: [Int: SandboxAttributionGap] = [:]
      var gapOrder: [Int] = []
      var nextGap = 0
      var openGap: Int?
      var sessions = 0
      var subscription: (any SandboxReportSubscription)?
      var generation = 0
      var covered = false
      /// A start or restart is under way.
      var starting = false
      /// The first start after the last idle period is under way.
      var fresh = false
      var failures = 0
      /// The `log_dropped` gap still growing; a successful log write ends it.
      var logDropGap: Int?
      /// Kernel times (µs) of the last `rateReports` reports, oldest first once full.
      var rateTimes: [Int64] = []
      var rateNext = 0
      var rateGap: Int?
      /// Receive time (ms) until which reports count as fast: dense probing runs until then.
      var hotUntil: Int64 = 0
      var dense = false
      var droppedGap: Int?
      /// Probe checks scheduled (`denseBound` after their probe) that have not run yet.
      var pendingChecks = 0
      /// PIDs that attributed reports named while they ran in this host's process tree,
      /// newest last (truncation filter).
      var recentPIDs: [Int32] = []
      var recentPIDSet: Set<Int32> = []

      /// Gaps that may still change: never dropped from memory.
      var activeGaps: Set<Int> {
        Set(
          [openGap, burstGap, storeDropGap, truncatedGap, logDropGap, rateGap, droppedGap]
            .compactMap { $0 })
      }
    }

    private let state = Mutex(State())
    private let file: Mutex<FileHandle?>
    private let source: any SandboxReportSource
    private let probe: any SandboxReaderProbing
    private let restartDelay: Duration
    private let probeInterval: Duration
    private let probeAttempts: Int
    private let heartbeatInterval: Duration
    private let heartbeatBound: Duration
    private let denseInterval: Duration
    private let denseBound: Duration
    private let window: Int
    private let gapLimit: Int
    private let returnedLimit: Int
    private let returnedRetention: Int64
    private let persistence: SandboxAttributionPersistence?
    /// When this monitor started (µs since 1970): a process started earlier cannot be a
    /// descendant of anything Memoshi ran through it.
    private let startedAt: UInt64
    /// This monitor's life: it names its gaps in the Store.
    let life: String

    static let kernelSender = "/System/Library/Extensions/Sandbox.kext/Contents/MacOS/Sandbox"

    /// `log`, when given, must not exist yet; it is created private (0600). `store`, when
    /// given, receives every invocation before its exec and every return, denial and gap.
    init(
      log url: URL?, store: Store? = nil,
      retention: SandboxAttributionRetention = .standard,
      source: any SandboxReportSource = UnifiedLogReportSource(),
      probe: any SandboxReaderProbing = SandboxReaderProbe(), restartDelay: Duration = .seconds(1),
      probeInterval: Duration = .milliseconds(250), probeAttempts: Int = 40,
      heartbeatInterval: Duration = .seconds(2), heartbeatBound: Duration = .seconds(5),
      denseInterval: Duration = .milliseconds(100), denseBound: Duration = .seconds(1),
      retaining window: Int = 4096, retainingGaps: Int = 1024, retainingReturned: Int = 4096,
      returnedRetention: Duration = .seconds(3600), storeQueue: Int = 8192
    ) throws {
      self.source = source
      self.probe = probe
      self.restartDelay = restartDelay
      self.probeInterval = probeInterval
      self.probeAttempts = max(1, probeAttempts)
      self.heartbeatInterval = heartbeatInterval
      self.heartbeatBound = heartbeatBound
      self.denseInterval = denseInterval
      self.denseBound = denseBound
      self.window = max(1, window)
      gapLimit = max(1, retainingGaps)
      returnedLimit = max(0, retainingReturned)
      let (seconds, attoseconds) = returnedRetention.components
      self.returnedRetention = max(0, seconds * 1000 + attoseconds / 1_000_000_000_000_000)
      var now = timeval()
      gettimeofday(&now, nil)
      startedAt = UInt64(now.tv_sec) * 1_000_000 + UInt64(now.tv_usec)
      let life = String(SandboxInvocation.makeTag().dropFirst(SandboxInvocation.prefix.count))
      self.life = life
      persistence = store.map {
        SandboxAttributionPersistence(
          store: $0, life: life, retention: retention, capacity: storeQueue)
      }
      if let url {
        let descriptor = Darwin.open(
          url.path, O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw RuntimeEnvironmentError.invalidComposition }
        file = Mutex(FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
      } else {
        file = Mutex(nil)
      }
      persistence?.onFailure { [weak self] in self?.storeFailed($0) }
    }

    // MARK: Inspection

    /// The retained denials, oldest first.
    public var denials: [SandboxDenial] {
      state.withLock { Array($0.denials[$0.oldest...] + $0.denials[..<$0.oldest]) }
    }

    /// The retained gaps, in order; an open one has no end.
    public var gaps: [SandboxAttributionGap] {
      state.withLock { value in value.gapOrder.compactMap { value.gaps[$0] } }
    }

    /// Whether a probe proved the reader live and it has not stopped since.
    public var covered: Bool { state.withLock { $0.covered } }

    /// Registered command and daemon invocations still held, oldest first.
    public var invocations: [SandboxInvocation] {
      state.withLock { $0.invocations.values.filter { $0.kind != .probe } }
        .sorted { ($0.startedAt, $0.tag) < ($1.startedAt, $1.tag) }
    }

    /// When each returned invocation still held exited, by tag.
    public var returnedTimes: [String: Int64] { state.withLock { $0.returned } }

    /// When the last probe that came back was sent, while covered; a `reader_silent` gap
    /// starts here.
    public var lastConfirmed: Int64? { state.withLock { $0.covered ? $0.lastConfirmed : nil } }

    /// Whether the running-command probe loop is active.
    var heartbeating: Bool { state.withLock { $0.heartbeating } }

    /// Whether dense probing (reports coming fast) is active.
    var probingDensely: Bool { state.withLock { $0.dense } }

    /// Whether dense probing has ended and every scheduled probe check has run: what the reader
    /// will record about reports received so far is recorded.
    var settled: Bool { state.withLock { !$0.dense && $0.pendingChecks == 0 } }

    /// Waits until every entry handed to the Store so far is written.
    func flush() async { await persistence?.flush() }

    /// Stops and resumes Store writes, as a Store slower than the reports would (tests).
    func holdStore() { persistence?.hold() }
    func releaseStore() { persistence?.release() }

    // MARK: Invocations

    /// Records a new invocation before its exec and returns its fresh tag. Fails when the Store
    /// cannot record it: a command must not run unrecorded. A failing optional log is a gap.
    func register(
      _ kind: SandboxInvocation.Kind, identity: EgressClientIdentity?, call: String?,
      command: [String]?
    ) async throws -> String {
      let invocation = SandboxInvocation(
        tag: SandboxInvocation.makeTag(), kind: kind, bot: identity?.bot,
        conversation: identity?.conversation, computer: identity?.computer, call: call,
        command: command.map(SandboxInvocation.digest), startedAt: Self.now())
      if let persistence { try await persistence.invocation(invocation) }
      let heartbeat = state.withLock { value -> Bool in
        forgetReturned(at: invocation.startedAt, in: &value)
        append(SandboxAttributionEntry(invocation: invocation), to: &value)
        value.invocations[invocation.tag] = invocation
        guard kind == .command else { return false }
        value.running.insert(invocation.tag)
        guard !value.heartbeating else { return false }
        value.heartbeating = true
        return true
      }
      if heartbeat { Task { await self.heartbeat() } }
      return invocation.tag
    }

    func returned(_ tag: String, exitCode: Int?) {
      let entry = SandboxInvocationReturn(tag: tag, at: Self.now(), exitCode: exitCode)
      state.withLock { value in
        value.returned[tag] = entry.at
        value.returnedOrder.append((tag, entry.at))
        value.running.remove(tag)
        append(SandboxAttributionEntry(returned: entry), to: &value)
        forgetReturned(at: entry.at, in: &value)
      }
      persistence?.enqueue(.returned(entry))
    }

    /// Forgets returned invocations beyond `returnedLimit` or older than `returnedRetention`;
    /// a running one is never forgotten.
    private func forgetReturned(at now: Int64, in value: inout State) {
      while let oldest = value.returnedOrder.first,
        value.returnedOrder.count > returnedLimit || oldest.at <= now - returnedRetention
      {
        value.returnedOrder.removeFirst()
        // A tag that returned again later stays until that return is forgotten.
        guard value.returned[oldest.tag] == oldest.at else { continue }
        value.returned[oldest.tag] = nil
        value.invocations[oldest.tag] = nil
      }
    }

    // MARK: Reader lifecycle

    /// A sandbox session opened; the first one starts the reader.
    func open() {
      let start = state.withLock { value -> Bool in
        value.sessions += 1
        guard value.sessions == 1 else { return false }
        value.fresh = true
        return true
      }
      if start { startReader() }
    }

    /// A sandbox session closed; after the last one the reader stops and a gap stays open.
    func close() {
      let subscription = state.withLock { value -> (any SandboxReportSubscription)? in
        value.sessions = max(0, value.sessions - 1)
        guard value.sessions == 0 else { return nil }
        value.generation += 1
        value.covered = false
        value.starting = false
        value.fresh = false
        openGap("reader_idle", in: &value)
        defer { value.subscription = nil }
        return value.subscription
      }
      subscription?.stop()
    }

    /// Waits until the reader is covered or its current start attempt has given up.
    func awaitCoverage(within limit: Duration) async -> Bool {
      await wait(within: limit) { $0.covered || !$0.starting }
    }

    /// For a command: waits only while the first start after an idle period is under way, so a
    /// command normally runs covered and never waits on a reader that keeps failing.
    func awaitStartup(within limit: Duration) async {
      _ = await wait(within: limit) { $0.covered || !$0.fresh }
    }

    /// Ends the current log stream as if it had died (development evidence and tests).
    func interruptReader() {
      let (subscription, generation) = state.withLock { ($0.subscription, $0.generation) }
      readerEnded(generation)
      subscription?.stop()
    }

    /// Keeps the current log stream running but silent, as a stalled reader would be
    /// (development evidence and tests).
    func pauseReader() {
      state.withLock { $0.subscription }?.pause()
    }

    private func wait(within limit: Duration, until done: (State) -> Bool) async -> Bool {
      let deadline = ContinuousClock.now.advanced(by: limit)
      while true {
        let (finished, covered) = state.withLock { (done($0), $0.covered) }
        if finished || ContinuousClock.now >= deadline { return covered }
        try? await Task.sleep(for: .milliseconds(10))
      }
    }

    private func startReader() {
      let generation = state.withLock { value -> Int? in
        guard value.sessions > 0 else { return nil }
        value.generation += 1
        value.covered = false
        value.starting = true
        if value.openGap == nil { openGap("reader_starting", in: &value) }
        return value.generation
      }
      guard let generation else { return }
      let subscription: any SandboxReportSubscription
      do {
        subscription = try source.start(
          onLine: { [weak self] in self?.ingest($0) },
          onEnd: { [weak self] in self?.readerEnded(generation) })
      } catch {
        readerEnded(generation)
        return
      }
      let current = state.withLock { value -> Bool in
        guard value.generation == generation else { return false }
        value.subscription = subscription
        return true
      }
      guard current else {
        subscription.stop()
        return
      }
      Task { await self.probeUntilCovered(generation) }
    }

    private func probeUntilCovered(_ generation: Int) async {
      for attempt in 0..<probeAttempts {
        let tag = state.withLock { value -> String? in
          guard value.generation == generation, !value.covered else { return nil }
          return newProbe(in: &value)
        }
        guard let tag else { break }
        await probe.run(tag: tag)
        if state.withLock({ $0.generation != generation || $0.covered }) { break }
        if attempt + 1 < probeAttempts { try? await Task.sleep(for: probeInterval) }
      }
      state.withLock { value in
        guard value.generation == generation else { return }
        value.starting = false
        value.fresh = false
      }
    }

    /// A fresh probe tag of the current generation; only the newest 256 are remembered.
    private func newProbe(in value: inout State) -> String {
      let tag = SandboxInvocation.makeTag()
      value.probes[tag] = Probe(generation: value.generation, sentAt: Self.now())
      value.probeOrder.append(tag)
      if value.probeOrder.count > 256 {
        value.probes[value.probeOrder.removeFirst()] = nil
      }
      return tag
    }

    /// While a command runs: a probe now and every `heartbeatInterval`. A covered reader whose
    /// probe does not come back within `heartbeatBound` is silent: a gap from the last
    /// confirmed probe opens and the reader restarts.
    private func heartbeat() async {
      while true {
        let next = state.withLock { value -> (Int, Beat)? in
          guard !value.running.isEmpty, value.sessions > 0 else {
            value.heartbeating = false
            return nil
          }
          guard value.covered else {
            return (value.generation, value.starting ? .wait : .restart)
          }
          return (value.generation, .probe(newProbe(in: &value)))
        }
        guard let (generation, beat) = next else { return }
        switch beat {
        case .wait:
          // An uncovered reader is being started and probed.
          break
        case .restart:
          // Its start attempt gave up while the stream still runs: end it and start again.
          readerLost(generation, reason: "reader_silent")
        case .probe(let tag):
          let deadline = ContinuousClock.now.advanced(by: heartbeatBound)
          let sent = state.withLock { $0.probes[tag]?.sentAt } ?? Self.now()
          await probe.run(tag: tag)
          while true {
            let (answered, current) = state.withLock {
              (($0.probes[tag]?.answered ?? 0) > 0, $0.generation == generation && $0.covered)
            }
            if answered {
              // Some of its reports came back: any that did not are a measured loss.
              state.withLock { $0.pendingChecks += 1 }
              Task {
                try? await Task.sleep(for: self.denseBound)
                self.checkDense(tag, generation: generation, sent: sent)
              }
              break
            }
            if !current { break }
            if ContinuousClock.now >= deadline {
              readerLost(generation, reason: "reader_silent")
              break
            }
            try? await Task.sleep(for: .milliseconds(10))
          }
        }
        try? await Task.sleep(for: heartbeatInterval)
      }
    }

    /// The stream ended: a gap opens now and, while sessions remain, a restart follows.
    private func readerEnded(_ generation: Int) {
      readerLost(generation, reason: "reader_stopped")
    }

    /// The reader of `generation` is lost. A stopped one opens its gap now; a silent one is
    /// ended and its gap starts at the last confirmed probe.
    private func readerLost(_ generation: Int, reason: String) {
      let silent = reason == "reader_silent"
      let (subscription, restart) = state.withLock {
        value -> ((any SandboxReportSubscription)?, (Int, Duration)?) in
        guard value.generation == generation, !silent || value.covered || !value.starting else {
          return (nil, nil)
        }
        let subscription = value.subscription
        let from = silent && value.covered ? value.lastConfirmed : nil
        value.generation += 1
        value.subscription = nil
        value.covered = false
        // A command waits for the first start only; never for restarts of a failing reader.
        value.fresh = false
        openGap(reason, from: from, in: &value)
        guard value.sessions > 0 else {
          value.starting = false
          return (subscription, nil)
        }
        value.starting = true
        let delay = restartDelay * (1 << min(value.failures, 5))
        value.failures += 1
        return (subscription, (value.generation, min(delay, .seconds(30))))
      }
      if silent { subscription?.stop() }
      guard let (expected, delay) = restart else { return }
      Task {
        if delay > .zero { try? await Task.sleep(for: delay) }
        guard self.state.withLock({ $0.generation == expected && $0.sessions > 0 }) else { return }
        self.startReader()
      }
    }

    // MARK: Reports

    /// One ndjson line from the reader. Only the kernel's own Sandbox reports count. A message
    /// is read as bytes, never as `Character`s, so no scalar a bot puts at the end of a path can
    /// join the kernel's newline or truncation mark: the tag is the bytes after the last
    /// newline, so a path cannot move it, and a report whose last line is no tag is kept as
    /// unattributed. A report the kernel truncated before its tag is never attributed: see
    /// ``truncated(_:at:kernelTime:reportedAt:)``. One the log could not compose
    /// (``illegibleReport``) names no process, so it is counted the same way, without text.
    func ingest(_ line: Data) {
      guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
        return
      }
      let now = Self.now()
      if event["eventType"] as? String == "lossEvent" {
        state.withLock { value in
          addGap(SandboxAttributionGap(from: now, to: now, reason: "events_lost"), in: &value)
        }
        return
      }
      guard event["eventType"] as? String == "logEvent",
        (event["processID"] as? NSNumber)?.intValue == 0,
        (event["senderImagePath"] as? String) == Self.kernelSender,
        let message = event["eventMessage"] as? String
      else { return }
      let reportedAt = event["timestamp"] as? String
      let kernelTime = reportedAt.flatMap(Self.microseconds) ?? now * 1000
      let bytes = Array(message.utf8)
      if bytes.reversed().starts(with: Self.truncationMark.utf8.reversed())
        || bytes.elementsEqual(Self.illegibleReport.utf8)
      {
        truncated(bytes, at: now, kernelTime: kernelTime, reportedAt: reportedAt)
        return
      }
      guard bytes.firstRange(of: SandboxInvocation.prefix.utf8) != nil else { return }
      let newline = bytes.lastIndex(of: 0x0A)
      let tagBytes = newline.map { bytes[($0 + 1)...] } ?? []
      let reportBytes = newline.map { bytes[..<$0] } ?? bytes[...]
      let tag = String(decoding: tagBytes, as: UTF8.self)
      let report = Self.bounded(reportBytes, 4096)
      let duplicates = Self.duplicates(report)
      // An attributed report's PIDs are remembered only once shown to be this host's: the
      // process name before the PID is the bot's to choose.
      let unverified = state.withLock { value -> [Int32] in
        guard value.invocations[tag] != nil else { return [] }
        return Self.reportPIDs(reportBytes).filter { !value.recentPIDSet.contains($0) }
      }
      let verified = unverified.filter(Self.descendsFromHost)
      let dense = state.withLock { value -> Bool in
        let dense = noteReport(at: kernelTime, receivedAt: now, in: &value)
        if var probe = value.probes[tag] {
          guard probe.generation == value.generation else { return dense }
          probe.answered += 1
          value.probes[tag] = probe
          if !value.covered {
            value.covered = true
            value.starting = false
            value.fresh = false
            value.failures = 0
            value.lastConfirmed = probe.sentAt
            closeGap(in: &value, at: now)
          } else {
            value.lastConfirmed = max(value.lastConfirmed ?? probe.sentAt, probe.sentAt)
          }
          return dense
        }
        let invocation = value.invocations[tag]
        if invocation != nil { for pid in verified { remember(pid, in: &value) } }
        let unattributed =
          invocation != nil
          ? nil : SandboxInvocation.isTag(tag[...]) ? "unknown_tag" : "malformed_tag"
        // An unknown tag names no conversation this host still holds, so a purge could never
        // reach the paths in its report: only the denial and its count are kept.
        keep(
          SandboxDenial(
            at: now, reportedAt: reportedAt, tag: Self.bounded(tagBytes, 256),
            invocation: invocation, unattributed: unattributed,
            report: unattributed == "unknown_tag" ? "" : report, duplicates: duplicates,
            afterReturn: invocation.map { value.returned[$0.tag] != nil } ?? false),
          in: &value)
        return dense
      }
      if dense { Task { await self.denseProbing() } }
    }

    /// A report the kernel cut short before its tag line. Every PID it may name decides:
    /// - all of them alive outside this host's process tree and older than this monitor: another
    ///   app's report, ignored;
    /// - all of them this host's (this host or a live descendant, or a PID an attributed report
    ///   named that has exited since): kept as `truncated`, with a counted `report_truncated`
    ///   gap;
    /// - otherwise (an exited short command, an orphan re-parented to launchd, a name that
    ///   hides the PID): the counted gap only, without the report's text.
    private func truncated(
      _ bytes: [UInt8], at now: Int64, kernelTime: Int64, reportedAt: String?
    ) {
      let lineages = Self.reportPIDs(bytes[...]).map { pid in
        (pid, Self.lineage(of: pid, since: startedAt))
      }
      if !lineages.isEmpty, lineages.allSatisfy({ $0.1 == .foreign }) { return }
      let dense = state.withLock { value -> Bool in
        let dense = noteReport(at: kernelTime, receivedAt: now, in: &value)
        countTruncated(at: now, in: &value)
        let mine =
          !lineages.isEmpty
          && lineages.allSatisfy { pid, lineage in
            lineage == .host || (lineage == .gone && value.recentPIDSet.contains(pid))
          }
        guard mine else { return dense }
        let report = Self.bounded(bytes[...], 4096)
        keep(
          SandboxDenial(
            at: now, reportedAt: reportedAt, tag: "", invocation: nil, unattributed: "truncated",
            report: report, duplicates: Self.duplicates(report), afterReturn: false),
          in: &value)
        return dense
      }
      if dense { Task { await self.denseProbing() } }
    }

    private func remember(_ pid: Int32, in value: inout State) {
      guard value.recentPIDSet.insert(pid).inserted else { return }
      value.recentPIDs.append(pid)
      if value.recentPIDs.count > 4096 {
        value.recentPIDSet.remove(value.recentPIDs.removeFirst())
      }
    }

    /// Every PID "Sandbox: name(pid) deny…" may name, also after "N duplicate reports for ":
    /// each "(digits) deny" after the prefix. The kernel prints the bot-chosen process name
    /// first, and a name may itself hold "(1) deny", so no single match is trusted.
    static func reportPIDs(_ bytes: ArraySlice<UInt8>) -> [Int32] {
      guard let start = bytes.firstRange(of: "Sandbox: ".utf8) else { return [] }
      let marker = Array(") deny".utf8)
      var pids: [Int32] = []
      var rest = bytes[start.upperBound...]
      while let close = rest.firstRange(of: marker) {
        var open = close.lowerBound
        while open > rest.startIndex, (48...57).contains(bytes[open - 1]) { open -= 1 }
        if open > rest.startIndex, bytes[open - 1] == UInt8(ascii: "("),
          (1...10).contains(close.lowerBound - open),
          let pid = Int32(String(decoding: bytes[open..<close.lowerBound], as: UTF8.self)),
          !pids.contains(pid)
        {
          pids.append(pid)
        }
        rest = bytes[close.upperBound...]
      }
      return pids
    }

    /// What the process table says about a PID a report names.
    enum Lineage: Equatable {
      /// This host or a live descendant of it.
      case host
      /// Alive outside this host's process tree and started before this monitor.
      case foreign
      /// Alive outside this host's process tree, started since: perhaps a command's orphan.
      case unproven
      /// No such process.
      case gone
    }

    static func lineage(of pid: Int32, since start: UInt64) -> Lineage {
      guard pid > 0, let process = processEntry(pid) else { return .gone }
      if descendsFromHost(pid) { return .host }
      return process.started < start ? .foreign : .unproven
    }

    /// Whether `pid` is alive and this host or one of its descendants (parent chain).
    static func descendsFromHost(_ pid: Int32) -> Bool {
      let host = getpid()
      var current = pid
      for _ in 0..<64 {
        if current == host { return true }
        guard current > 1, let process = processEntry(current) else { return false }
        current = process.parent
      }
      return false
    }

    /// A live process's parent and start time (µs since 1970), readable for every user's
    /// process.
    private static func processEntry(_ pid: Int32) -> (parent: Int32, started: UInt64)? {
      var entry = kinfo_proc()
      var size = MemoryLayout<kinfo_proc>.stride
      var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
      guard sysctl(&name, 4, &entry, &size, nil, 0) == 0, size > 0 else { return nil }
      let started = entry.kp_proc.p_un.__p_starttime
      return (
        entry.kp_eproc.e_ppid, UInt64(started.tv_sec) * 1_000_000 + UInt64(started.tv_usec)
      )
    }

    /// What the kernel appends to a report it cut short.
    static let truncationMark = "<\u{2026}>"
    /// What `log stream` delivers for a kernel report it cannot compose. Measured 2026-11-20:
    /// the kernel cuts a report at 1,008 bytes, wherever that falls, and appends
    /// ``truncationMark``; a cut inside a multi-byte character leaves bytes that are not UTF-8,
    /// and the log then delivers only this text, with no process, path, tag or mark. A bot can
    /// place a two-byte character across the cut with one byte of padding, so this is a
    /// truncated report too.
    static let illegibleReport = "<compose failure [illegible log arguments]>"
    /// Reports per `burstWindow` (kernel time) above which the log may drop some without a
    /// loss event. Measured 2026-11-14: bursts of 100 reports in about 1.4 ms lost 0–19, 50 in
    /// 0.8 ms lost none, and normal command traffic peaked at 26 reports in 1 ms.
    static let burstReports = 32
    static let burstWindow: Int64 = 1000

    /// Delivered reports per second (kernel time) from which the log may drop some without a
    /// loss event. Measured 2026-11-14 with one process at a fixed pace (2 runs each): 1,000/s
    /// and 2,500/s lost none; 5,000/s lost 369 and 2,904 of 15,000; 7,500–25,000/s lost up to
    /// 5,137 of 15,000. Below this rate a loss is not detected; counts stay lower bounds.
    static let rateReports = 1000
    static let rateWindow: Int64 = 1_000_000

    /// Counts a report toward burst and rate detection: `burstReports` within `burstWindow`
    /// (µs) grow a `report_burst` gap, `rateReports` within `rateWindow` a `report_rate` gap,
    /// each spanning those reports. While either holds, and for 1 s after, dense probes measure
    /// what the log drops. Returns true when dense probing must start.
    private func noteReport(at time: Int64, receivedAt now: Int64, in value: inout State) -> Bool {
      value.recent.append(time)
      if value.recent.count > Self.burstReports { value.recent.removeFirst() }
      var hot = false
      if value.recent.count == Self.burstReports, let first = value.recent.min(),
        let last = value.recent.max(), last - first <= Self.burstWindow
      {
        grow(\.burstGap, "report_burst", from: first, to: last, base: Self.burstReports, in: &value)
        hot = true
      }
      // A ring of the last `rateReports` kernel times; once full, `rateNext` is the oldest.
      if value.rateTimes.count < Self.rateReports {
        value.rateTimes.append(time)
      } else {
        value.rateTimes[value.rateNext] = time
        value.rateNext = (value.rateNext + 1) % Self.rateReports
      }
      if value.rateTimes.count == Self.rateReports {
        let oldest = value.rateTimes[value.rateNext]
        if time - oldest <= Self.rateWindow, time >= oldest {
          grow(\.rateGap, "report_rate", from: oldest, to: time, base: Self.rateReports, in: &value)
          hot = true
        }
      }
      guard hot else { return false }
      value.hotUntil = now + 1000
      guard !value.dense, value.sessions > 0 else { return false }
      value.dense = true
      return true
    }

    /// Opens a closed gap over [from, to] (µs), or grows the current one of its kind when it
    /// still reaches `from`, counting each further report.
    private func grow(
      _ slot: WritableKeyPath<State, Int?>, _ reason: String, from: Int64, to: Int64, base: Int,
      in value: inout State
    ) {
      let start = from / 1000
      let end = (to + 999) / 1000
      if let index = value[keyPath: slot], let gap = value.gaps[index], let current = gap.to,
        current >= start
      {
        update(
          index,
          SandboxAttributionGap(
            from: gap.from, to: max(current, end), reason: gap.reason,
            count: (gap.count ?? 0) + 1), in: &value)
      } else {
        value[keyPath: slot] = addGap(
          SandboxAttributionGap(from: start, to: end, reason: reason, count: base), in: &value)
      }
    }

    /// While reports come fast: a probe every `denseInterval`, each checked `denseBound` after
    /// it was sent (heartbeat probes are checked the same way). Every probe report that did not
    /// come back grows a counted `reports_dropped` gap: a measured loss, and a lower bound of
    /// what the log dropped. Probes sample the stream; a loss between them can go unseen.
    private func denseProbing() async {
      while true {
        let next = state.withLock { value -> (Int, String?, Int64)? in
          guard value.sessions > 0, Self.now() < value.hotUntil else {
            value.dense = false
            return nil
          }
          // An uncovered reader is already a gap.
          guard value.covered else { return (value.generation, nil, 0) }
          let tag = newProbe(in: &value)
          value.pendingChecks += 1
          return (value.generation, tag, value.probes[tag]?.sentAt ?? Self.now())
        }
        guard let (generation, tag, sent) = next else { return }
        if let tag {
          Task {
            await self.probe.run(tag: tag)
            try? await Task.sleep(for: self.denseBound)
            self.checkDense(tag, generation: generation, sent: sent)
          }
        }
        try? await Task.sleep(for: denseInterval)
      }
    }

    private func checkDense(_ tag: String, generation: Int, sent: Int64) {
      let now = Self.now()
      state.withLock { value in
        value.pendingChecks -= 1
        guard value.generation == generation, value.covered, let probe = value.probes[tag] else {
          return
        }
        let missing = max(0, self.probe.reports - probe.answered)
        guard missing > 0 else { return }
        if let index = value.droppedGap, let gap = value.gaps[index], let end = gap.to,
          end >= sent - 1000
        {
          update(
            index,
            SandboxAttributionGap(
              from: gap.from, to: max(end, now), reason: gap.reason,
              count: (gap.count ?? 0) + missing), in: &value)
        } else {
          value.droppedGap = addGap(
            SandboxAttributionGap(from: sent, to: now, reason: "reports_dropped", count: missing),
            in: &value)
        }
      }
    }

    /// Keeps a denial in memory, the log and the Store. One the Store queue cannot take grows
    /// a `store_dropped` gap instead; commands keep running.
    private func keep(_ denial: SandboxDenial, in value: inout State) {
      if value.denials.count < window {
        value.denials.append(denial)
      } else {
        value.denials[value.oldest] = denial
        value.oldest = (value.oldest + 1) % window
      }
      append(SandboxAttributionEntry(denial: denial), to: &value)
      guard let persistence else { return }
      if persistence.enqueue(.denial(denial)) {
        value.storeDropGap = nil
      } else {
        storeDropped(1, at: denial.at, in: &value)
      }
    }

    /// `count` denials did not reach the Store.
    private func storeDropped(_ count: Int, at now: Int64, in value: inout State) {
      if let index = value.storeDropGap, let gap = value.gaps[index] {
        update(
          index,
          SandboxAttributionGap(
            from: gap.from, to: max(gap.to ?? now, now), reason: gap.reason,
            count: (gap.count ?? 0) + count), in: &value)
      } else {
        value.storeDropGap = addGap(
          SandboxAttributionGap(from: now, to: now, reason: "store_dropped", count: count),
          in: &value)
      }
    }

    /// One truncated report: grows the `report_truncated` gap that reaches back within 1 s, or
    /// opens a new one, so a flood is one counted gap.
    private func countTruncated(at now: Int64, in value: inout State) {
      if let index = value.truncatedGap, let gap = value.gaps[index], let end = gap.to,
        now - end <= 1000
      {
        update(
          index,
          SandboxAttributionGap(
            from: gap.from, to: max(end, now), reason: gap.reason, count: (gap.count ?? 0) + 1),
          in: &value)
      } else {
        value.truncatedGap = addGap(
          SandboxAttributionGap(from: now, to: now, reason: "report_truncated", count: 1),
          in: &value)
      }
    }

    /// The Store failed to write a batch holding `count` denials.
    func storeFailed(_ count: Int) {
      let now = Self.now()
      state.withLock { value in
        value.storeDropGap = nil
        storeDropped(count, at: now, in: &value)
      }
    }

    /// Appends a gap that is already closed (or a marker), outside the open-gap sequence, and
    /// returns its sequence.
    @discardableResult
    private func addGap(_ gap: SandboxAttributionGap, in value: inout State) -> Int {
      let sequence = insert(gap, in: &value)
      append(SandboxAttributionEntry(gap: gap), to: &value)
      persistence?.enqueue(.gap(gap, sequence: sequence))
      return sequence
    }

    /// The same gap (same sequence) closed or grown.
    private func update(_ sequence: Int, _ gap: SandboxAttributionGap, in value: inout State) {
      value.gaps[sequence] = gap
      append(SandboxAttributionEntry(gap: gap), to: &value)
      persistence?.enqueue(.gap(gap, sequence: sequence))
    }

    /// Retains `gap` under the next sequence. Beyond `gapLimit` the oldest gaps that can no
    /// longer change leave memory (the Store keeps its own record); an open or growing gap and
    /// the newest one stay.
    private func insert(_ gap: SandboxAttributionGap, in value: inout State) -> Int {
      let sequence = value.nextGap
      value.nextGap += 1
      value.gaps[sequence] = gap
      value.gapOrder.append(sequence)
      guard value.gapOrder.count > gapLimit else { return sequence }
      let active = value.activeGaps
      var index = 0
      while value.gapOrder.count > gapLimit, index < value.gapOrder.count - 1 {
        let old = value.gapOrder[index]
        if active.contains(old) {
          index += 1
        } else {
          value.gapOrder.remove(at: index)
          value.gaps[old] = nil
        }
      }
      return sequence
    }

    /// Microseconds since 1970 of a log timestamp such as `2026-11-14 16:25:47.032387+0300`.
    static func microseconds(_ text: String) -> Int64? {
      let bytes = Array(text.utf8)
      guard bytes.count == 31, bytes[4] == 45, bytes[10] == 32, bytes[19] == 46 else {
        return nil
      }
      func number(_ range: Range<Int>) -> Int? {
        var result = 0
        for byte in bytes[range] {
          guard (48...57).contains(byte) else { return nil }
          result = result * 10 + Int(byte - 48)
        }
        return result
      }
      guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
        let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
        let fraction = number(20..<26), let zoneHours = number(27..<29),
        let zoneMinutes = number(29..<31), bytes[26] == 43 || bytes[26] == 45
      else { return nil }
      var parts = tm()
      parts.tm_year = Int32(year - 1900)
      parts.tm_mon = Int32(month - 1)
      parts.tm_mday = Int32(day)
      parts.tm_hour = Int32(hour)
      parts.tm_min = Int32(minute)
      parts.tm_sec = Int32(second)
      let utc = Int64(timegm(&parts))
      let offset = Int64(zoneHours * 3600 + zoneMinutes * 60) * (bytes[26] == 43 ? 1 : -1)
      return (utc - offset) * 1_000_000 + Int64(fraction)
    }

    /// At most `limit` bytes of `bytes`, cut back to a whole scalar.
    private static func bounded(_ bytes: ArraySlice<UInt8>, _ limit: Int) -> String {
      var kept = Array(bytes.prefix(limit))
      while String(validating: kept, as: UTF8.self) == nil, !kept.isEmpty { kept.removeLast() }
      return String(decoding: kept, as: UTF8.self)
    }

    /// N from a coalesced "N duplicate report(s) for …" line.
    private static func duplicates(_ report: String) -> Int {
      let words = report.split(separator: " ", maxSplits: 3)
      guard words.count == 4, words[1] == "duplicate",
        words[2] == "report" || words[2] == "reports",
        let count = Int(words[0])
      else { return 0 }
      return count
    }

    // MARK: Persistence

    /// Opens a gap from `from` (default now), ending a different open one first; the same
    /// reason keeps running.
    private func openGap(_ reason: String, from: Int64? = nil, in value: inout State) {
      let now = Self.now()
      if let index = value.openGap {
        guard value.gaps[index]?.reason != reason else { return }
        closeGap(in: &value, at: now)
      }
      value.openGap = addGap(
        SandboxAttributionGap(from: min(from ?? now, now), to: nil, reason: reason), in: &value)
    }

    private func closeGap(in value: inout State, at now: Int64) {
      guard let index = value.openGap else { return }
      value.openGap = nil
      guard let open = value.gaps[index] else { return }
      update(
        index, SandboxAttributionGap(from: open.from, to: now, reason: open.reason), in: &value)
    }

    /// Writes one entry to the optional log. A failed write refuses nothing: it grows a counted
    /// `log_dropped` gap, kept in memory and the Store (never in the failing log).
    private func append(_ entry: SandboxAttributionEntry, to value: inout State) {
      do {
        let wrote = try file.withLock { handle -> Bool in
          guard let handle else { return false }
          let encoder = JSONEncoder()
          encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
          try handle.write(contentsOf: try encoder.encode(entry) + Data([0x0a]))
          return true
        }
        if wrote { value.logDropGap = nil }
      } catch {
        let now = Self.now()
        if let index = value.logDropGap, let gap = value.gaps[index] {
          let grown = SandboxAttributionGap(
            from: gap.from, to: max(gap.to ?? now, now), reason: gap.reason,
            count: (gap.count ?? 0) + 1)
          value.gaps[index] = grown
          persistence?.enqueue(.gap(grown, sequence: index))
        } else {
          let gap = SandboxAttributionGap(from: now, to: now, reason: "log_dropped", count: 1)
          let sequence = insert(gap, in: &value)
          value.logDropGap = sequence
          persistence?.enqueue(.gap(gap, sequence: sequence))
        }
      }
    }

    /// Makes the optional log fail every later write (tests).
    func breakLogForTesting() {
      let descriptor = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
      file.withLock { $0 = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true) }
    }

    private static func now() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }
  }

  /// `log stream` limited to the kernel's sandbox reports that carry a Memoshi tag. Runs as the
  /// logged-in user without extra entitlements (measured 2026-11-14).
  struct UnifiedLogReportSource: SandboxReportSource {
    /// Tagged reports, every Sandbox report the kernel truncated (its tag may be gone) and every
    /// one the log could not compose (``SandboxDenialMonitor/illegibleReport``). The suffix is
    /// the mark without its `<`: a Prepend scalar a path ends with can join `<` into one
    /// Character, never `…`; the monitor checks the whole mark on bytes. Measured 2026-11-20: a
    /// path's U+0600 arrives as its own UTF-8 bytes, unescaped, and a report cut right after one
    /// still matches this suffix.
    static let predicate =
      #"sender == "Sandbox" AND (eventMessage CONTAINS ""# + SandboxInvocation.prefix
      + #"" OR eventMessage == ""# + SandboxDenialMonitor.illegibleReport
      + #"" OR eventMessage ENDSWITH ""# + String(SandboxDenialMonitor.truncationMark.dropFirst())
      + #"")"#

    func start(
      onLine: @escaping @Sendable (Data) -> Void, onEnd: @escaping @Sendable () -> Void
    ) throws -> any SandboxReportSubscription {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
      process.arguments = [
        "stream", "--style", "ndjson", "--level", "default", "--predicate", Self.predicate,
      ]
      process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
      let output = Pipe()
      process.standardOutput = output
      process.standardError = FileHandle.nullDevice
      process.standardInput = FileHandle.nullDevice
      let pending = LineBuffer()
      output.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty else {
          handle.readabilityHandler = nil
          onEnd()
          return
        }
        let lines = pending.data.withLock { buffer -> [Data] in
          buffer.append(data)
          var lines: [Data] = []
          while let newline = buffer.firstIndex(of: 0x0a) {
            lines.append(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
          }
          return lines
        }
        for line in lines { onLine(Data(line)) }
      }
      do { try process.run() } catch {
        output.fileHandleForReading.readabilityHandler = nil
        throw RuntimeEnvironmentError.unavailable
      }
      return UnifiedLogSubscription(process: process)
    }
  }

  final class LineBuffer: Sendable {
    let data = Mutex(Data())
  }

  final class UnifiedLogSubscription: SandboxReportSubscription {
    private let process: Mutex<Process?>

    init(process: Process) { self.process = Mutex(process) }

    func stop() {
      let process = self.process.withLock { value -> Process? in
        defer { value = nil }
        return value
      }
      guard let process, process.isRunning else { return }
      process.terminate()
      // A stopped reader receives the termination only once it continues.
      kill(process.processIdentifier, SIGCONT)
    }

    func pause() {
      guard let process = self.process.withLock({ $0 }), process.isRunning else { return }
      kill(process.processIdentifier, SIGSTOP)
    }
  }

  /// Writes attribution to the Store: each invocation before its exec (a failure refuses that
  /// command), then returns, denials and gaps in order, drained in batches of one transaction
  /// each. At most `capacity` denials wait; the monitor turns each one beyond that, and each
  /// denial of a batch the Store refused, into a counted `store_dropped` gap. Returns and gaps
  /// always queue. No other command is ever refused for it.
  final class SandboxAttributionPersistence: Sendable {
    enum Write: Sendable {
      case returned(SandboxInvocationReturn)
      case denial(SandboxDenial)
      case gap(SandboxAttributionGap, sequence: Int)
      case flush(CheckedContinuation<Void, Never>)
    }

    final class Queue: Sendable {
      struct Pending {
        var writes: [Write] = []
        var denials = 0
        var held = false
        /// Where each gap's queued write sits in `writes`, by sequence: a later state of the
        /// same gap replaces it, so a growing gap queues one write however often it grows.
        var gaps: [Int: Int] = [:]
      }
      let pending = Mutex(Pending())
      /// Told how many denials a refused batch held.
      let failed = Mutex<(@Sendable (Int) -> Void)?>(nil)
    }

    private let store: Store
    private let retention: SandboxAttributionRetention
    private let capacity: Int
    private let queue = Queue()
    private let wake: AsyncStream<Void>.Continuation

    init(
      store: Store, life: String, retention: SandboxAttributionRetention, capacity: Int = 8192
    ) {
      self.store = store
      self.retention = retention
      self.capacity = max(1, capacity)
      let (signals, wake) = AsyncStream.makeStream(
        of: Void.self, bufferingPolicy: .bufferingNewest(1))
      self.wake = wake
      let queue = queue
      Task {
        for await _ in signals {
          while true {
            let batch = queue.pending.withLock { pending -> [Write] in
              guard !pending.held else { return [] }
              defer {
                pending.writes.removeAll()
                pending.denials = 0
                pending.gaps.removeAll()
              }
              return pending.writes
            }
            if batch.isEmpty { break }
            var writes: [SandboxAttributionWrite] = []
            var flushes: [CheckedContinuation<Void, Never>] = []
            var denials = 0
            for write in batch {
              switch write {
              case .returned(let entry):
                writes.append(.returned(tag: entry.tag, at: entry.at, exitCode: entry.exitCode))
              case .denial(let denial):
                denials += 1
                writes.append(
                  .denial(Self.record(denial), invocation: denial.invocation.map(Self.record)))
              case .gap(let gap, let sequence):
                writes.append(
                  .gap(
                    SandboxGapRecord(
                      life: life, sequence: sequence, from: gap.from, to: gap.to,
                      reason: gap.reason, count: gap.count)))
              case .flush(let done):
                flushes.append(done)
              }
            }
            if !writes.isEmpty {
              do {
                try await store.recordSandboxAttribution(writes, retention: retention)
              } catch {
                if denials > 0 { queue.failed.withLock { $0 }?(denials) }
              }
            }
            for done in flushes { done.resume() }
          }
        }
      }
    }

    deinit { wake.finish() }

    /// Called with the denial count of each batch the Store refused.
    func onFailure(_ handler: @escaping @Sendable (Int) -> Void) {
      queue.failed.withLock { $0 = handler }
    }

    /// Writes the invocation before its exec.
    func invocation(_ invocation: SandboxInvocation) async throws {
      do {
        try await store.recordSandboxInvocation(Self.record(invocation), retention: retention)
      } catch {
        throw RuntimeEnvironmentError.unavailable
      }
    }

    /// Queues `write`; false when it is a denial and `capacity` denials already wait.
    @discardableResult
    func enqueue(_ write: Write) -> Bool {
      let taken = queue.pending.withLock { pending -> Bool in
        switch write {
        case .denial:
          guard pending.denials < capacity else { return false }
          pending.denials += 1
        case .gap(_, let sequence):
          if let index = pending.gaps[sequence] {
            pending.writes[index] = write
            return true
          }
          pending.gaps[sequence] = pending.writes.count
        case .returned, .flush:
          break
        }
        pending.writes.append(write)
        return true
      }
      if taken { wake.yield() }
      return taken
    }

    /// Waits until everything queued so far is written (or refused).
    func flush() async {
      await withCheckedContinuation { enqueue(.flush($0)) }
    }

    /// Stops draining until `release` (tests: a Store slower than the reports).
    func hold() { queue.pending.withLock { $0.held = true } }

    func release() {
      queue.pending.withLock { $0.held = false }
      wake.yield()
    }

    private static func record(_ invocation: SandboxInvocation) -> SandboxInvocationRecord {
      SandboxInvocationRecord(
        tag: invocation.tag, kind: invocation.kind.rawValue, botID: invocation.bot,
        conversationID: invocation.conversation, computerID: invocation.computer,
        callID: invocation.call, commandSHA256: invocation.command,
        startedAt: invocation.startedAt)
    }

    private static func record(_ denial: SandboxDenial) -> SandboxDenialRecord {
      SandboxDenialRecord(
        tag: denial.tag, invocationTag: denial.invocation?.tag, receivedAt: denial.at,
        reportedAt: denial.reportedAt, unattributed: denial.unattributed, report: denial.report,
        duplicates: denial.duplicates, afterReturn: denial.afterReturn)
    }
  }

  /// A one-rule instance that denies reading four device files with the probe's tag, so one
  /// run makes the kernel emit four distinct reports; host-owned fixed argv, never a bot's
  /// command.
  struct SandboxReaderProbe: SandboxReaderProbing {
    static let paths = ["/dev/zero", "/dev/null", "/dev/random", "/dev/urandom"]
    static let profile =
      "(version 1)\n(allow default)\n(deny file-read-data (require-any "
      + paths.map { "(literal \"\($0)\")" }.joined(separator: " ") + ") "
      + SandboxProfile.tagMessage + ")"

    var reports: Int { Self.paths.count }

    func run(tag: String) async {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
      process.arguments =
        [
          "-D", "INV=" + tag, "-p", Self.profile, "/usr/bin/head", "-c", "1",
        ] + Self.paths
      process.environment = ["PATH": "/usr/bin:/bin"]
      process.standardInput = FileHandle.nullDevice
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        process.terminationHandler = { _ in continuation.resume() }
        do { try process.run() } catch {
          process.terminationHandler = nil
          continuation.resume()
        }
      }
    }
  }
#endif
