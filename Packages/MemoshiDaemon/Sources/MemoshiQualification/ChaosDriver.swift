import CryptoKit
import Darwin
import Foundation
import MemoshiProtocol
import MemoshiStore
import Synchronization

/// Which model the qualification host's `local` provider reaches.
package enum ChaosModelSelection: Sendable, Equatable {
  /// The scripted loopback provider (`QualificationProvider`).
  case scripted
  /// One model of a local OpenAI-compatible server, such as Ollama, behind the
  /// canary-checking `RealModelProxy`. The driver never starts, stops or pulls it.
  case upstream(URL, model: String)
}

/// Options for one chaos batch.
package struct ChaosOptions: Sendable {
  /// Runs in the batch.
  package var runs: Int
  /// The seed that fixes every kill point and delay.
  package var seed: UInt64
  /// An absent or empty directory for isolated synthetic homes, stores and the ledger.
  package var workDirectory: URL
  /// Where results, logs and the ledger journal copy are written.
  package var outputDirectory: URL
  /// Kill points to draw from.
  package var points: [KillPoint]
  /// Deliberate kills before each run's final life.
  package var killsPerRun: Int
  /// Host startup order after a restart.
  package var startup: StartupOrder
  /// Keep each run's data/home directories instead of removing them.
  package var keepRunDirectories: Bool
  /// How long a life may take to reach its kill point, or the final life a terminal turn,
  /// before the run fails.
  package var terminalTimeout: Duration
  /// The model behind the host's provider.
  package var model: ChaosModelSelection
  /// This executable, re-run as the `ledger` and `host` children.
  package var executable: URL
  /// The invocation, recorded in the report.
  package var arguments: [String]

  package init(
    runs: Int, seed: UInt64, workDirectory: URL, outputDirectory: URL, points: [KillPoint],
    killsPerRun: Int, startup: StartupOrder, keepRunDirectories: Bool,
    terminalTimeout: Duration = .seconds(90), model: ChaosModelSelection = .scripted,
    executable: URL, arguments: [String]
  ) {
    self.runs = runs
    self.seed = seed
    self.workDirectory = workDirectory
    self.outputDirectory = outputDirectory
    self.points = points
    self.killsPerRun = killsPerRun
    self.startup = startup
    self.keepRunDirectories = keepRunDirectories
    self.terminalTimeout = terminalTimeout
    self.model = model
    self.executable = executable
    self.arguments = arguments
  }
}

/// The model a batch used, as recorded in `summary.json`.
package struct ChaosModelReport: Codable, Equatable, Sendable {
  /// `scripted` or `proxy`.
  package var mode: String
  /// The model each run selected under the host's `local` provider.
  package var model: String
  /// The proxied local endpoint, for `proxy`.
  package var upstream: String?
}

/// Batch-level facts written to `summary.json`.
package struct ChaosBatchReport: Codable, Sendable {
  /// The invocation.
  package var arguments: [String]
  /// The plan.
  package var plan: ChaosPlan
  /// Host startup order.
  package var startup: StartupOrder
  /// The selected model behind the host's provider.
  package var model: ChaosModelReport
  /// Aggregated run results.
  package var summary: ChaosSummary
  /// The ledger's own summary over HTTP before it stopped.
  package var ledgerLive: EffectLedgerSummary?
  /// The summary recomputed offline from the durable journal.
  package var ledgerJournal: EffectLedgerSummary?
  /// Whether the live and journal summaries agree.
  package var ledgerJournalConsistent: Bool
  /// How the ledger process ended.
  package var ledgerExit: String?
  /// Whether the work directory's runs, ledger, logs and scratch were removed.
  package var workCleanup: Bool
  /// Batch startup, capture, retention, publication and cleanup failures.
  package var failures: [String]
  /// Started, ISO 8601.
  package var startedAt: String
  /// Finished, ISO 8601.
  package var finishedAt: String
}

/// The P0-15 kill/resume driver: starts the ledger and the selected model (the scripted provider
/// or the real-model proxy), then for each planned run starts host lives, kills them with SIGKILL
/// at the planned point, restarts, answers approvals through the real path and verifies the final
/// state, receipts, approvals, ledger and canaries. Every process it signals is one it spawned.
package enum ChaosDriver {
  /// Runs the batch; 0 when every run passed and every output scan was clean.
  package static func run(_ options: ChaosOptions) async -> Int32 {
    _ = Darwin.signal(SIGPIPE, SIG_IGN)
    let log = LineWriter.standardError
    let started = Date()
    let plan: ChaosPlan
    let evidence: ChaosEvidence
    do {
      plan = try ChaosPlan(
        seed: options.seed, runs: options.runs, points: options.points,
        killsPerRun: options.killsPerRun)
      evidence = try ChaosEvidence.prepare(
        work: options.workDirectory, output: options.outputDirectory)
    } catch {
      log.text("memoshi-qualification: chaos refused: \(error)")
      return 2
    }
    let described: ChaosModelReport
    switch options.model {
    case .scripted:
      described = ChaosModelReport(mode: "scripted", model: QualificationProvider.modelID)
    case .upstream(let upstream, let model):
      described = ChaosModelReport(mode: "proxy", model: model, upstream: upstream.absoluteString)
    }
    var provider: (any ChaosModel)?
    var ledger: LedgerProcess?
    var attemptedLedger = false
    var results: [RunResult] = []
    var canaries: [Canary] = []
    var failures: [String] = []
    do {
      try evidence.write(plan, named: "plan.json")
      let activeProvider: any ChaosModel
      switch options.model {
      case .scripted:
        activeProvider = try await QualificationProvider.start()
      case .upstream(let upstream, let model):
        activeProvider = try await RealModelProxy.start(upstream: upstream, modelID: model)
      }
      provider = activeProvider
      attemptedLedger = true
      let activeLedger = try await LedgerProcess.start(
        executable: options.executable, directory: evidence.ledger,
        scratch: evidence.work.url, logs: evidence.logs)
      ledger = activeLedger
      log.text(
        "memoshi-qualification: ledger on 127.0.0.1:\(activeLedger.port), provider "
          + activeProvider.baseURL)
      let context = RunContext(
        options: options, model: activeProvider, ledger: activeLedger, evidence: evidence)
      for planned in plan.runs {
        let (result, used) = await runOne(planned, context: context)
        results.append(result)
        canaries += used
        log.text(
          "memoshi-qualification: \(result.run) \(planned.killPoint.rawValue) → "
            + "\(result.outcome.rawValue)"
            + (result.failures.isEmpty ? "" : " (\(result.failures.joined(separator: "; ")))"))
      }
    } catch {
      failures.append("batch: \(error)")
    }
    provider?.disarm()
    var ledgerLive: EffectLedgerSummary?
    var ledgerExit: ChildExit?
    if let ledger {
      do { ledgerLive = try await ledger.client.summary() } catch {
        failures.append("live ledger summary: \(error)")
      }
      do { ledgerExit = try await ledger.stop() } catch {
        ledgerExit = ledger.child.exit
        failures.append("ledger capture: \(error)")
      }
    }
    if let provider { await provider.close() }
    var ledgerJournal: EffectLedgerSummary?
    if attemptedLedger {
      do {
        ledgerJournal = try EffectLedgerState.summarize(EffectLedgerJournal.read(evidence.journal))
      } catch { failures.append("ledger journal: \(error)") }
      failures += evidence.retainLedger(canaries: canaries)
    }
    let ledgerConsistent = ledgerLive != nil && ledgerLive == ledgerJournal
    let cleanup = evidence.cleanUp(keepRuns: options.keepRunDirectories)
    failures += cleanup.failures
    let summary = ChaosSummary.aggregate(results)
    let formatter = ISO8601DateFormatter()
    let startedAt = formatter.string(from: started)
    let finishedAt = formatter.string(from: Date())
    do { try evidence.writeResults(results) } catch {
      failures.append("results publication: \(error)")
    }
    let modelLine =
      described.mode == "scripted"
      ? "controlled loopback provider"
      : "local model \(described.model) through the canary-checking loopback proxy"
    let header = [
      "# P0-15 kill/resume results",
      "",
      "Runtime-host level (real MemoshiStore + RuntimeAdapter + pinned PiDurable, "
        + "\(modelLine)). Development evidence, not an S1 gate result.",
      "",
      "- Seed \(options.seed), \(options.runs) runs, \(options.killsPerRun) kill(s) per run, "
        + "startup \(options.startup.rawValue)",
      "- Started \(startedAt), finished \(finishedAt)",
    ]
    var report = ChaosBatchReport(
      arguments: options.arguments, plan: plan, startup: options.startup, model: described,
      summary: summary, ledgerLive: ledgerLive, ledgerJournal: ledgerJournal,
      ledgerJournalConsistent: ledgerConsistent, ledgerExit: ledgerExit?.description,
      workCleanup: cleanup.complete, failures: failures, startedAt: startedAt,
      finishedAt: finishedAt)
    // The table states the batch verdict and every failure known when it is rendered, so it is
    // rendered after the output scan. Only its own and the summary's publication come later.
    func renderTable(outputClean: Bool) -> Data {
      let verdict = ChaosVerdict(
        passed: failures.isEmpty && summary.runs == plan.runs.count && summary.failed == 0
          && outputClean && ledgerExit == .exited(0) && ledgerConsistent && cleanup.complete,
        ledgerExit: ledgerExit?.description ?? "not started",
        ledgerJournalConsistent: ledgerConsistent, workCleanup: cleanup.complete,
        outputClean: outputClean, failures: failures)
      return Data(
        ChaosMarkdown.render(
          results, summary: summary, ledger: ledgerJournal, verdict: verdict, header: header
        ).utf8)
    }
    var outputClean = false
    var tableBytes: Data?
    var summaryBytes: Data?
    do {
      let baseScan = try evidence.scan([evidence.output.url], canaries: canaries)
      let scanner = try CanaryScanner(canaries: canaries)
      // Scan the final table and summary bytes before their exclusive publication.
      func rendered(outputClean: Bool) throws -> (
        table: Data, summary: Data, scan: CanaryScanReport
      ) {
        report.failures = failures
        let table = renderTable(outputClean: outputClean)
        let summary = try JSONLines.prettyEncoder.encode(report)
        var scan = baseScan
        scanner.scanBytes(table, path: "0:/results.md", into: &scan)
        scanner.scanBytes(summary, path: "0:/summary.json", into: &scan)
        return (table, summary, scan)
      }
      var output = try rendered(outputClean: true)
      if !output.scan.hits.isEmpty {
        failures.append("output canary scan: \(output.scan.hits.count) hits")
        output = try rendered(outputClean: false)
      }
      try evidence.write(output.scan, named: "output-canary-scan.json")
      outputClean = output.scan.hits.isEmpty
      tableBytes = output.table
      summaryBytes = output.summary
    } catch {
      failures.append("output canary scan or publication: \(error)")
    }
    do {
      try evidence.write(tableBytes ?? renderTable(outputClean: false), named: "results.md")
    } catch {
      failures.append("table publication: \(error)")
      summaryBytes = nil
    }
    report.failures = failures
    do {
      let bytes = try summaryBytes ?? JSONLines.prettyEncoder.encode(report)
      try evidence.write(bytes, named: "summary.json")
    } catch { failures.append("summary publication: \(error)") }
    for failure in failures { log.text("memoshi-qualification: \(failure)") }
    log.text(
      "memoshi-qualification: \(summary.passed)/\(summary.runs) passed, duplicates "
        + "\(summary.duplicates), output scan \(outputClean ? "clean" : "failed"), "
        + "ledger \(ledgerExit?.description ?? "not started"), journal consistent "
        + "\(ledgerConsistent), work cleanup \(cleanup.complete ? "complete" : "incomplete")")
    let ok =
      failures.isEmpty && summary.runs == plan.runs.count && summary.failed == 0 && outputClean
      && ledgerExit == .exited(0) && ledgerConsistent && cleanup.complete
    return ok ? 0 : 1
  }

  // MARK: - One run

  private static func runOne(_ planned: PlannedRun, context: RunContext) async -> (
    RunResult, [Canary]
  ) {
    let started = ContinuousClock.now
    let run = String(format: "r%03d", planned.index) + "-s\(context.options.seed)"
    var result = RunResult(run: run, plan: planned)
    let bearer = Canary.generate(label: "provider-bearer")
    let token = Canary.generate(label: "ledger-token")
    let paths = RunPaths(root: context.evidence.runs.appendingPathComponent(run, isDirectory: true))
    var state = RunState()
    var ownedRun: ChaosDirectory?
    do {
      try context.evidence.work.requireCurrent()
      ownedRun = try ChaosDirectory.create(paths.root)
      try paths.createChildren()
      try writeSecret(token.value, to: paths.tokenFile)
      try await context.ledger.register(run: run, token: token)
      context.model.arm(
        run: run, bearer: bearer.value, toolName: QualificationHost.toolName,
        callID: "mq-\(run)-call", subagents: planned.killPoint == .subagent,
        codeMode: planned.killPoint == .codemodeNested)
      let secretRef = "kc_" + UUID().uuidString
      for life in 1...(planned.kills + 1) {
        try await driveLife(
          life, planned: planned, run: run, paths: paths, secretRef: secretRef, bearer: bearer,
          context: context, state: &state, result: &result)
      }
    } catch {
      result.fail("harness: \(error)")
    }
    if result.finalStatus == nil, let last = state.lastSnapshot {
      // The final life did not verify; keep the last observed durable state as evidence.
      result.finalStatus = last.turn?.status
      result.approvals = last.approvals.count
      result.cards = last.cards.count
      result.toolCompletions = last.toolCompletions.count
      result.subagentCompletions = last.subagentCompletions.count
      result.childTaskStatuses = last.childTasks.map(\.status)
    }
    do {
      let attempts = try await context.ledger.client.attempts(run: run)
      result.ledger = EffectLedgerState.summarize(attempts).runs[run] ?? EffectTotals()
      if result.ledger.effects != 1 {
        result.fail("ledger holds \(result.ledger.effects) effects, expected exactly 1")
      }
      if result.ledger.duplicates > 0 {
        result.fail("\(result.ledger.duplicates) duplicated effects")
      }
      if result.ledger.conflicts > 0 { result.fail("\(result.ledger.conflicts) ledger conflicts") }
      if Set(attempts.map(\.attempt.key)).count > 1 {
        result.fail("the effect was posted under more than one idempotency key")
      }
    } catch {
      result.fail("ledger query: \(error)")
    }
    if planned.killPoint == .approvalWaiting {
      result.approvalReattach =
        state.reattachObservations > 0 && !state.reattachMismatch && result.approvals == 1
        ? .reattached : .failed
      if result.approvalReattach == .failed { result.fail("approval did not reattach") }
    }
    context.model.clearPause()
    result.provider = context.model.counts
    if result.provider.unauthorized > 0 {
      result.fail("\(result.provider.unauthorized) provider requests lacked the bearer canary")
    }
    var retention = ChaosLogRetention.withheld
    do {
      guard let ownedRun else { throw DriverError.invalid("Run directory was not created") }
      try context.evidence.work.requireCurrent()
      try ownedRun.requireCurrent()
      let files = try context.evidence.logFiles(in: paths.logs)
      let scan = try context.evidence.scan(
        [paths.root, context.ledger.directory], canaries: [bearer, token],
        excluding: [paths.tokenFile.path])
      result.canaryFilesScanned = scan.filesScanned
      result.canaryBytesScanned = scan.bytesScanned
      result.canaryHits = scan.hits
      if !scan.hits.isEmpty { result.fail("\(scan.hits.count) canary hits") }
      if scan.excluded.count != 1 {
        result.fail("the ledger-token source file was not scanned out")
      }
      if scan.hits.isEmpty, scan.excluded.count == 1 { retention = .clean(files) }
    } catch {
      result.fail("canary scan: \(error)")
    }
    for failure in context.evidence.retainRunLogs(retention, run: run) { result.fail(failure) }
    if !context.options.keepRunDirectories, let ownedRun {
      do { try context.evidence.removeRun(ownedRun) } catch { result.fail("run cleanup: \(error)") }
    }
    result.outcome = result.failures.isEmpty ? .pass : .fail
    result.durationMs = milliseconds(ContinuousClock.now - started)
    return (result, [bearer, token])
  }

  /// One host life: spawn, ready, (re)submit the original send, then either drive to the kill
  /// point and SIGKILL, or drive to the terminal state, verify and close normally.
  private static func driveLife(
    _ life: Int, planned: PlannedRun, run: String, paths: RunPaths, secretRef: String,
    bearer: Canary, context: RunContext, state: inout RunState, result: inout RunResult
  ) async throws {
    let final = life > planned.kills
    state.lifeMarker = life
    if !final && planned.killPoint == .streaming {
      context.model.pauseStreaming(afterDeltas: planned.streamingDeltas)
    } else if !final && planned.killPoint == .subagent {
      context.model.pauseChildStream()
    } else {
      context.model.clearPause()
    }
    state.pausedStreamsAtLifeStart = context.model.counts.pausedStreams
    var pause: ToolGate?
    if !final && (planned.killPoint == .toolExecuting || planned.killPoint == .codemodeNested) {
      pause = .toolExecuting
    }
    if !final && planned.killPoint == .effectPosted { pause = .effectPosted }
    let configuration = HostConfiguration(
      run: run, life: life, dataDirectory: paths.data.path,
      providerBaseURL: context.model.baseURL, providerSecretRef: secretRef,
      providerBearer: bearer.value, configureProvider: life == 1,
      ledgerPort: context.ledger.port, ledgerTokenFile: paths.tokenFile.path, pause: pause,
      subagents: planned.killPoint == .subagent, codeMode: planned.killPoint == .codemodeNested,
      startup: context.options.startup)
    let host = try await HostProcess.spawn(
      executable: context.options.executable, environment: paths.environment,
      logs: paths.logs, life: life, configuration: configuration)
    do {
      let ready = try await host.ready(timeout: .seconds(60))
      if life > 1 { result.resumeToReadyMs.append(milliseconds(ready.at - host.child.spawnedAt)) }
      if let elapsed = ready.message.fields?["elapsedMs"].flatMap({ Int64($0) }) {
        result.hostReadyMs.append(elapsed)
      }
      let chat = try ConversationID(ready.message.fields?["chatId"] ?? "")
      if let known = state.chatID, known != chat {
        result.fail("Chat identity changed in life \(life)")
      }
      state.chatID = chat
      let params =
        try state.params
        ?? ChatsSendParams(
          requestId: IDGenerator.shared.next(), chatId: chat,
          content: [.text(TextPart(text: Self.request(run: run, killPoint: planned.killPoint)))],
          model: ModelRef(ref: ModelName("local/" + context.model.modelID)))
      state.params = params
      let sent = try await host.call(.send, send: params)
      guard sent.ok == true, let receipt = sent.receipt else {
        throw DriverError.invalid("send in life \(life): \(sent.error ?? "no receipt")")
      }
      if let original = state.receipt {
        let same =
          receipt.messageId == original.messageId && receipt.taskId == original.taskId
          && receipt.writtenSeq == original.writtenSeq && receipt.replayed == true
        if !same { result.fail("life \(life) resubmission did not return the original receipt") }
        result.originalReceipts = (result.originalReceipts ?? true) && same
      } else {
        state.receipt = receipt
      }
      if final {
        let snapshot = try await driveToTerminal(
          host, run: run, context: context, state: &state, result: &result)
        verifyFinal(
          snapshot, expectedFinalText: context.model.expectedFinalText, state: state,
          result: &result)
        for failure in subagentFailures(
          snapshot, planned: planned, counts: context.model.counts,
          holdsChildStreams: context.model.holdsChildStreams)
        {
          result.fail(failure)
        }
        for failure in codeModeFailures(snapshot, planned: planned) {
          result.fail(failure)
        }
        let closed = try await host.call(.shutdown)
        if closed.ok != true { result.fail("normal close failed: \(closed.error ?? "unknown")") }
        let exit = await host.child.waitForExit(timeout: .seconds(20))
        result.lifeExits.append(exit?.description ?? "running")
        if exit != .exited(0) { result.fail("final life ended \(exit?.description ?? "running")") }
      } else {
        try await advance(
          to: planned.killPoint, host: host, run: run, context: context, state: &state,
          result: &result)
        if planned.killDelayMilliseconds > 0 {
          try await Task.sleep(for: .milliseconds(planned.killDelayMilliseconds))
        }
        host.child.signal(SIGKILL)
        let exit = await host.child.waitForExit(timeout: .seconds(20))
        result.lifeExits.append(exit?.description ?? "running")
        if exit == .signaled(SIGKILL) {
          result.killsDelivered += 1
        } else {
          result.fail("life \(life) did not end by SIGKILL (\(exit?.description ?? "running"))")
        }
      }
      if host.child.exit == nil {
        host.child.signal(SIGKILL)
        _ = await host.child.waitForExit(timeout: .seconds(20))
      }
      try await host.child.drainOutput()
    } catch {
      if host.child.exit == nil {
        host.child.signal(SIGKILL)
        _ = await host.child.waitForExit(timeout: .seconds(20))
      }
      result.lifeExits.append(host.child.exit?.description ?? "running")
      do { try await host.child.drainOutput() } catch let captureError {
        result.fail("host capture: \(captureError)")
      }
      throw error
    }
  }

  /// Drives a kill life until the planned point is observed.
  private static func advance(
    to point: KillPoint, host: HostProcess, run: String, context: RunContext,
    state: inout RunState, result: inout RunResult
  ) async throws {
    let deadline = ContinuousClock.now + context.options.terminalTimeout
    switch point {
    case .streaming:
      // The model holds a reply open after text the host already received. A real model may
      // call the tool before streaming any text, so approvals are answered meanwhile.
      while true {
        if context.model.counts.pausedStreams > state.pausedStreamsAtLifeStart,
          await host.inbox.all.contains(where: { $0.event == "delta" })
        {
          break
        }
        let snapshot = try await inspect(host, state: &state)
        if let turn = snapshot.turn, ["done", "failed", "canceled"].contains(turn.status),
          snapshot.liveRuns == 0
        {
          throw DriverError.invalid("the turn ended \(turn.status) before a reply streamed text")
        }
        try await answerPending(
          snapshot, host: host, run: run, context: context, state: &state, result: &result)
        guard ContinuousClock.now < deadline else {
          throw DriverError.timeout("a held reply stream (\(describe(snapshot)))")
        }
        try await Task.sleep(for: .milliseconds(50))
      }
    case .approvalWaiting:
      while true {
        let snapshot = try await inspect(host, state: &state)
        let pending = snapshot.approvals.filter { $0.status == "pending" }
        if let approval = pending.first {
          let card = snapshot.cards.first { $0.subjectId == approval.id }
          observePending(approval, card: card, pendingCount: pending.count, state: &state)
          try await requireNoEffectBeforeDecision(
            host: host, run: run, context: context, result: &result)
          if state.pendingAtKill == nil, let card {
            state.pendingAtKill = PendingDecision(approval: approval.id, card: card.id)
          }
          return
        }
        guard ContinuousClock.now < deadline else {
          throw DriverError.timeout("a pending approval (\(describe(snapshot)))")
        }
        try await Task.sleep(for: .milliseconds(100))
      }
    case .toolExecuting, .effectPosted, .codemodeNested:
      let gate = point == .effectPosted ? ToolGate.effectPosted : .toolExecuting
      while true {
        if await host.inbox.all.contains(where: {
          $0.event == "paused" && $0.fields?["gate"] == gate.rawValue
        }) {
          break
        }
        let snapshot = try await inspect(host, state: &state)
        try await answerPending(
          snapshot, host: host, run: run, context: context, state: &state, result: &result)
        guard ContinuousClock.now < deadline else {
          throw DriverError.timeout("tool gate \(gate.rawValue) (\(describe(snapshot)))")
        }
        try await Task.sleep(for: .milliseconds(50))
      }
      if point == .effectPosted {
        let attempts = try await context.ledger.client.attempts(run: run)
        if !attempts.contains(where: { $0.disposition == .recorded }) {
          result.fail("no recorded effect at the effect-posted kill point")
        }
      }
    case .subagent:
      // A spawned child conversation is running inside the host. The scripted provider holds
      // the child's own request open, and only that held stream opens the window. A real
      // model's child cannot be held; it is visible as a second live run. Approvals are
      // answered meanwhile.
      while true {
        if context.model.counts.pausedStreams > state.pausedStreamsAtLifeStart {
          result.subagentKillWindows.append("held-child-stream")
          break
        }
        let snapshot = try await inspect(host, state: &state)
        if !context.model.holdsChildStreams, snapshot.liveRuns >= 2 {
          result.subagentKillWindows.append("second-live-run")
          break
        }
        if let turn = snapshot.turn, ["done", "failed", "canceled"].contains(turn.status),
          snapshot.liveRuns == 0
        {
          throw DriverError.invalid("the turn ended \(turn.status) before a child ran")
        }
        try await answerPending(
          snapshot, host: host, run: run, context: context, state: &state, result: &result)
        guard ContinuousClock.now < deadline else {
          throw DriverError.timeout("a running child (\(describe(snapshot)))")
        }
        try await Task.sleep(for: .milliseconds(50))
      }
    case .compaction:
      // Not drivable yet: the runtime composition starts no compaction step and emits no
      // compaction event. Refuse the run instead of hanging.
      throw DriverError.invalid(
        "the compaction kill point is not drivable: the runtime starts no compaction step")
    case .idle:
      _ = try await driveToTerminal(
        host, run: run, context: context, state: &state, result: &result)
    }
  }

  /// Answers pending approvals until the turn is terminal with no live run.
  private static func driveToTerminal(
    _ host: HostProcess, run: String, context: RunContext, state: inout RunState,
    result: inout RunResult
  ) async throws -> HostSnapshot {
    let deadline = ContinuousClock.now + context.options.terminalTimeout
    var heldSince: ContinuousClock.Instant?
    while true {
      let snapshot = try await inspect(host, state: &state)
      if let turn = snapshot.turn, ["done", "failed", "canceled"].contains(turn.status),
        snapshot.liveRuns == 0
      {
        return snapshot
      }
      if snapshot.recoveryHold {
        // A recovery hold never clears by itself; there is no Resume card to answer yet.
        let since = heldSince ?? ContinuousClock.now
        heldSince = since
        if ContinuousClock.now - since > .seconds(3) {
          result.fail("recovery hold: \(describe(snapshot))")
          return snapshot
        }
      }
      try await answerPending(
        snapshot, host: host, run: run, context: context, state: &state, result: &result)
      guard ContinuousClock.now < deadline else {
        throw DriverError.timeout("a terminal turn (\(describe(snapshot)))")
      }
      try await Task.sleep(for: .milliseconds(100))
    }
  }

  /// Answers one new pending approval through `RuntimeAdapter.respondToCard` (allow once).
  private static func answerPending(
    _ snapshot: HostSnapshot, host: HostProcess, run: String, context: RunContext,
    state: inout RunState, result: inout RunResult
  ) async throws {
    let pending = snapshot.approvals.filter { $0.status == "pending" }
    guard let approval = pending.first, !state.answered.contains(approval.id) else { return }
    let card = snapshot.cards.first { $0.subjectId == approval.id && $0.status == "pending" }
    observePending(approval, card: card, pendingCount: pending.count, state: &state)
    try await requireNoEffectBeforeDecision(host: host, run: run, context: context, result: &result)
    guard let card else {
      result.fail("pending approval \(approval.id) has no pending card")
      state.answered.insert(approval.id)
      return
    }
    let answered = try await host.call(
      .respond,
      respond: CardsRespondParams(
        requestId: IDGenerator.shared.next(), cardId: CardID(card.id), action: "allow_once",
        surface: .ui))
    guard answered.ok == true else {
      throw DriverError.invalid("approval answer: \(answered.error ?? "unknown")")
    }
    state.answered.insert(approval.id)
  }

  /// Compares a pending approval seen after a restart with the one pending at the kill.
  private static func observePending(
    _ approval: ApprovalState, card: CardState?, pendingCount: Int, state: inout RunState
  ) {
    if pendingCount > 1 { state.reattachMismatch = true }
    guard let expected = state.pendingAtKill,
      !state.compared.contains(approval.id + "@" + "\(state.lifeMarker)")
    else { return }
    state.compared.insert(approval.id + "@" + "\(state.lifeMarker)")
    state.reattachObservations += 1
    if approval.id != expected.approval || card?.id != expected.card {
      state.reattachMismatch = true
    }
  }

  /// Fails the run if the external effect or tool execution preceded the decision.
  private static func requireNoEffectBeforeDecision(
    host: HostProcess, run: String, context: RunContext, result: inout RunResult
  ) async throws {
    let attempts = try await context.ledger.client.attempts(run: run)
    let executed = await host.inbox.all.contains { $0.event == "tool_executing" }
    if attempts.contains(where: { $0.disposition == .recorded }) || executed {
      result.executedWithoutDecision = true
      result.fail("the tool ran or its effect was recorded before the approval decision")
    }
  }

  /// `expectedFinalText` is the scripted answer; a real model's answer must be nonempty text that
  /// finished with stop reason `stop`.
  private static func verifyFinal(
    _ snapshot: HostSnapshot, expectedFinalText: String?, state: RunState,
    result: inout RunResult
  ) {
    result.finalStatus = snapshot.turn?.status
    result.approvals = snapshot.approvals.count
    result.cards = snapshot.cards.count
    result.toolCompletions = snapshot.toolCompletions.count
    result.subagentCompletions = snapshot.subagentCompletions.count
    result.childTaskStatuses = snapshot.childTasks.map(\.status)
    guard let turn = snapshot.turn, let receipt = state.receipt, let params = state.params else {
      result.fail("the run's turn is missing")
      return
    }
    if turn.status != "done" {
      result.fail("turn ended \(turn.status)" + (turn.errorCode.map { " (\($0))" } ?? ""))
    }
    if snapshot.task?.status != "done" { result.fail("task ended \(snapshot.task?.status ?? "?")") }
    if turn.messageId != receipt.messageId.rawValue || turn.taskId != receipt.taskId.rawValue
      || turn.writtenSeq != receipt.writtenSeq
    {
      result.fail("the stored receipt differs from the original")
    }
    if snapshot.live { result.fail("a live generation remains") }
    if snapshot.recoveryHold { result.fail("a recovery hold remains") }
    if snapshot.queued != 0 { result.fail("\(snapshot.queued) queued inputs remain") }
    var transcript = TranscriptCheck()
    let users = snapshot.messages.filter { $0.role == "user" }
    let bots = snapshot.messages.filter { $0.role == "bot" }
    transcript.userMessages = users.count
    transcript.botMessages = bots.count
    let isFinalAnswer = { (message: MessageState) -> Bool in
      guard message.role == "bot", message.stopReason == "stop" else { return false }
      guard let expectedFinalText else {
        return !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      return message.text == expectedFinalText
    }
    transcript.finalAnswers = bots.filter(isFinalAnswer).count
    transcript.endsWithFinalAnswer = snapshot.messages.last.map(isFinalAnswer) ?? false
    transcript.uniqueIDs = Set(snapshot.messages.map(\.id)).count == snapshot.messages.count
    result.transcript = transcript
    let sentText = params.content.map { part -> String in
      if case .text(let text) = part { return text.text }
      return ""
    }.joined()
    if users.count != 1 || users.first?.id != turn.messageId
      || users.first?.requestId != params.requestId.rawValue || users.first?.text != sentText
    {
      result.fail("the transcript does not hold exactly the original user message")
    }
    if bots.count != 1 || transcript.finalAnswers != 1 || !transcript.endsWithFinalAnswer {
      let last = snapshot.messages.last.map {
        "\($0.role) message, stop \($0.stopReason ?? "none"), \($0.text.count) characters"
      }
      result.fail(
        "the transcript does not end with exactly one final answer (\(bots.count) bot messages, "
          + "last: \(last ?? "none"))")
    }
    if !transcript.uniqueIDs { result.fail("duplicate transcript message IDs") }
    if snapshot.approvals.count != 1 {
      result.fail("\(snapshot.approvals.count) approvals, expected 1")
    } else if let approval = snapshot.approvals.first,
      approval.status != "allowed" || approval.decidedBy != "user"
    {
      result.fail("approval ended \(approval.status) by \(approval.decidedBy ?? "nobody")")
    }
    if snapshot.cards.count != 1 { result.fail("\(snapshot.cards.count) cards, expected 1") }
    if snapshot.toolCompletions.count != 1 || snapshot.toolCompletions.first?.ok != true {
      result.fail(
        "tool completions \(snapshot.toolCompletions.map { $0.ok ? "ok" : ($0.errorCode ?? "error") })"
      )
    }
  }

  /// The S1.13 subagent point's own final state: exactly one successful delegation whose one
  /// child task finished `done` with no tools, and, when the model holds child streams, one
  /// held child request per kill plus the one that answered. A run at any other point must
  /// spawn no child. The parent's checks in `verifyFinal` cannot see a lost or failed child.
  package static func subagentFailures(
    _ snapshot: HostSnapshot, planned: PlannedRun, counts: ProviderCounts,
    holdsChildStreams: Bool
  ) -> [String] {
    let delegations = snapshot.subagentCompletions
    let children = snapshot.childTasks
    guard planned.killPoint == .subagent else {
      if delegations.isEmpty && children.isEmpty { return [] }
      return [
        "a run without delegation has \(delegations.count) subagent completions and "
          + "\(children.count) child tasks"
      ]
    }
    var failures: [String] = []
    if delegations.count != 1 || delegations.first?.ok != true {
      failures.append(
        "subagent completions \(delegations.map { $0.ok ? "ok" : ($0.errorCode ?? "error") }), "
          + "expected exactly one ok")
    }
    if children.count != 1 || children.first?.status != "done" {
      failures.append("child tasks \(children.map(\.status)), expected exactly one done")
    }
    for child in children where child.toolNames != [] {
      failures.append(
        "child \(child.id) may call \(child.toolNames.map { "\($0)" } ?? "unknown tools"), "
          + "expected none")
    }
    if counts.subagentResultMismatches > 0 {
      failures.append(
        "\(counts.subagentResultMismatches) subagent results were not the child's answer")
    }
    if holdsChildStreams && counts.childReplies != planned.kills + 1 {
      failures.append(
        "\(counts.childReplies) child requests, expected \(planned.kills + 1): one held per "
          + "kill and one answered")
    }
    return failures
  }

  /// The S1.13 nested Code Mode point's own final state: exactly one successful `codemode` tool
  /// completion for a `codemode-nested` run, and none for any other point.
  package static func codeModeFailures(
    _ snapshot: HostSnapshot, planned: PlannedRun
  ) -> [String] {
    let completions = snapshot.codeModeCompletions
    guard planned.killPoint == .codemodeNested else {
      if completions.isEmpty { return [] }
      return ["a run without Code Mode has \(completions.count) codemode completions"]
    }
    if completions.count != 1 || completions.first?.ok != true {
      return [
        "codemode completions \(completions.map { $0.ok ? "ok" : ($0.errorCode ?? "error") }), "
          + "expected exactly one ok"
      ]
    }
    return []
  }

  // MARK: - Support

  /// Inspects through the host and keeps the snapshot as the run's latest durable evidence.
  private static func inspect(_ host: HostProcess, state: inout RunState) async throws
    -> HostSnapshot
  {
    let snapshot = try await host.inspect(state.params?.requestId)
    state.lastSnapshot = snapshot
    return snapshot
  }

  private static func describe(_ snapshot: HostSnapshot) -> String {
    let approvals = snapshot.approvals.map { "\($0.status)" }.joined(separator: ",")
    return
      "turn \(snapshot.turn?.status ?? "none"), task \(snapshot.task?.status ?? "none")"
      + "/\(snapshot.task?.waitingOn ?? "-"), approvals [\(approvals)], live runs "
      + "\(snapshot.liveRuns), hold \(snapshot.recoveryHold)"
  }

  /// The run's one user message. The scripted provider ignores it; a real model needs the
  /// instruction to call the qualification tool exactly once and then answer. A subagent run
  /// delegates to a child first; the child task carries the marker the harness recognizes.
  package static func request(run: String, killPoint: KillPoint) -> String {
    if killPoint == .codemodeNested {
      return "Call the \(QualificationProvider.codeModeToolName) tool exactly once with argument "
        + "`code` set to: "
        + "`return await tools.\(QualificationHost.toolName)("
        + "{ step: \"effect-1\", note: \"Qualification effect for \(run)\" });` "
        + "Do not call \(QualificationHost.toolName) directly; only call "
        + "\(QualificationProvider.codeModeToolName). When it returns, reply with one short "
        + "sentence saying the effect is recorded. Do not call any tool again."
    }
    let delegation =
      killPoint == .subagent
      ? "First call the \(QualificationProvider.subagentToolName) tool exactly once, with task "
        + "\"\(QualificationProvider.childTask(run: run))\", and wait for the child's answer. "
      : ""
    return delegation
      + "Call the \(QualificationHost.toolName) tool exactly once, with step \"effect-1\", to "
      + "record the qualification effect for run \(run). When it returns, reply with one short "
      + "sentence saying the effect is recorded. Do not call any tool again."
  }

  static func milliseconds(_ duration: Duration) -> Int64 {
    duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
  }

  private static func writeSecret(_ value: String, to url: URL) throws {
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw DriverError.invalid("secret file \(url.lastPathComponent)") }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do {
      try handle.write(contentsOf: Data(value.utf8))
      try handle.close()
    } catch {
      try? handle.close()
      throw error
    }
  }
}

/// Shared batch services for every run.
struct RunContext: Sendable {
  let options: ChaosOptions
  let model: any ChaosModel
  let ledger: LedgerProcess
  let evidence: ChaosEvidence
}

/// A decision pending at a kill: what every restart must reattach to.
struct PendingDecision: Sendable {
  let approval: String
  let card: String
}

/// Per-run driver state carried across host lives.
struct RunState {
  var chatID: ConversationID?
  var params: ChatsSendParams?
  var receipt: ChatsSendResult?
  var answered: Set<String> = []
  var pendingAtKill: PendingDecision?
  var compared: Set<String> = []
  var lifeMarker = 0
  var reattachObservations = 0
  var reattachMismatch = false
  var lastSnapshot: HostSnapshot?
  /// The model's held-stream count when this life started; a streaming kill waits for more.
  var pausedStreamsAtLifeStart = 0
}

/// One run's isolated synthetic home, store, temporary, secret and log directories.
struct RunPaths: Sendable {
  let root: URL
  var data: URL { root.appendingPathComponent("data", isDirectory: true) }
  var home: URL { root.appendingPathComponent("home", isDirectory: true) }
  var tmp: URL { root.appendingPathComponent("tmp", isDirectory: true) }
  var secrets: URL { root.appendingPathComponent("secrets", isDirectory: true) }
  var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }
  /// The declared synthetic secret source file: the only place the ledger canary may exist.
  var tokenFile: URL { secrets.appendingPathComponent("ledger-token") }

  func createChildren() throws {
    for directory in [data, home, tmp, secrets, logs] {
      _ = try ChaosDirectory.create(directory)
    }
  }

  /// The host's whole environment: only the synthetic home and temporary directory.
  var environment: [String: String] {
    [
      "HOME": home.path, "CFFIXED_USER_HOME": home.path, "TMPDIR": tmp.path + "/",
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    ]
  }
}

/// A host life driven over its stdin/stdout.
final class HostProcess: Sendable {
  let child: ChildProcess
  let inbox: Inbox<HostMessage>
  private let nextID = Mutex(0)

  private init(child: ChildProcess, inbox: Inbox<HostMessage>) {
    self.child = child
    self.inbox = inbox
  }

  static func spawn(
    executable: URL, environment: [String: String], logs: URL, life: Int,
    configuration: HostConfiguration
  ) async throws -> HostProcess {
    let inbox = Inbox<HostMessage>()
    let child = try ChildProcess.spawn(
      executable: executable, arguments: ["host"], environment: environment,
      stdoutLog: logs.appendingPathComponent("host-life-\(life).jsonl"),
      stderrLog: logs.appendingPathComponent("host-life-\(life).stderr.log"),
      onLine: { line in
        if let message = try? JSONDecoder().decode(HostMessage.self, from: Data(line.utf8)) {
          await inbox.put(message)
        }
      },
      onEnd: { await inbox.finish() })
    let host = HostProcess(child: child, inbox: inbox)
    do {
      // The configuration, with the bearer canary, travels only on this pipe.
      try child.send(try JSONLines.encoder.encode(configuration))
    } catch {
      child.signal(SIGKILL)
      child.closeStdin()
      _ = await child.waitForExit(timeout: .seconds(20))
      do { try await child.drainOutput() } catch let captureError {
        throw DriverError.invalid("host startup: \(error); capture: \(captureError)")
      }
      throw error
    }
    return host
  }

  /// Waits for `ready` (or `fatal`) and returns it with the time the driver received it.
  func ready(timeout: Duration) async throws -> (message: HostMessage, at: ContinuousClock.Instant)
  {
    let inbox = inbox
    let found = try await withDeadline(timeout, "host ready") {
      await inbox.first { $0.event == "ready" || $0.event == "fatal" }
    }
    let at = ContinuousClock.now
    guard let message = found?.item else { throw DriverError.childEnded("ready") }
    guard message.event == "ready" else {
      throw DriverError.invalid("host failed to start: \(message.error ?? "unknown")")
    }
    return (message, at)
  }

  /// Waits for the first event with this name in this life.
  func event(_ name: String, timeout: Duration) async throws -> HostMessage {
    let inbox = inbox
    let found = try await withDeadline(timeout, "host event \(name)") {
      await inbox.first { $0.event == name }
    }
    guard let message = found?.item else { throw DriverError.childEnded("event \(name)") }
    return message
  }

  /// Sends one command and waits for its response.
  func call(
    _ operation: HostCommand.Operation, send: ChatsSendParams? = nil,
    respond: CardsRespondParams? = nil, requestId: ULID? = nil,
    timeout: Duration = .seconds(30)
  ) async throws -> HostMessage {
    let id = nextID.withLock { value in
      value += 1
      return value
    }
    try child.send(
      try JSONLines.encoder.encode(
        HostCommand(id: id, op: operation, send: send, respond: respond, requestId: requestId)))
    let inbox = inbox
    let found = try await withDeadline(timeout, "host \(operation.rawValue)") {
      await inbox.first { $0.id == id }
    }
    guard let message = found?.item else {
      throw DriverError.childEnded("response to \(operation.rawValue)")
    }
    return message
  }

  /// Reads the durable state through the host's real Store and RuntimeAdapter.
  func inspect(_ requestId: ULID?) async throws -> HostSnapshot {
    let response = try await call(.inspect, requestId: requestId)
    guard response.ok == true, let snapshot = response.snapshot else {
      throw DriverError.invalid("inspect: \(response.error ?? "no snapshot")")
    }
    return snapshot
  }
}

/// The effect-ledger child process.
final class LedgerProcess: Sendable {
  let child: ChildProcess
  let inbox: Inbox<[String: String]>
  let port: Int
  let directory: URL
  let client: EffectLedgerClient

  private init(
    child: ChildProcess, inbox: Inbox<[String: String]>, port: Int, directory: URL
  ) {
    self.child = child
    self.inbox = inbox
    self.port = port
    self.directory = directory
    client = EffectLedgerClient(port: port)
  }

  static func start(executable: URL, directory: URL, scratch: URL, logs: URL) async throws
    -> LedgerProcess
  {
    let home = scratch.appendingPathComponent("ledger-home", isDirectory: true)
    let tmp = scratch.appendingPathComponent("tmp", isDirectory: true)
    let inbox = Inbox<[String: String]>()
    let child = try ChildProcess.spawn(
      executable: executable, arguments: ["ledger", "--directory", directory.path],
      environment: [
        "HOME": home.path, "CFFIXED_USER_HOME": home.path, "TMPDIR": tmp.path + "/",
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      ],
      stdoutLog: logs.appendingPathComponent("ledger.jsonl"),
      stderrLog: logs.appendingPathComponent("ledger.stderr.log"),
      onLine: { line in
        if let fields = try? JSONDecoder().decode([String: String].self, from: Data(line.utf8)) {
          await inbox.put(fields)
        }
      },
      onEnd: { await inbox.finish() })
    do {
      let found = try await withDeadline(.seconds(30), "ledger listening") {
        await inbox.first { $0["event"] == "listening" || $0["event"] == "failed" }
      }
      guard let fields = found?.item, fields["event"] == "listening",
        let port = fields["port"].flatMap({ Int($0) }),
        try EffectLedgerClient.port(in: directory) == port
      else { throw DriverError.invalid("ledger did not start") }
      return LedgerProcess(child: child, inbox: inbox, port: port, directory: directory)
    } catch {
      child.signal(SIGKILL)
      child.closeStdin()
      _ = await child.waitForExit(timeout: .seconds(20))
      do { try await child.drainOutput() } catch let captureError {
        throw DriverError.invalid("ledger startup: \(error); capture: \(captureError)")
      }
      throw error
    }
  }

  /// Registers a run's bearer digest and waits for the acknowledgment.
  func register(run: String, token: Canary) async throws {
    let digest = Data(SHA256.hash(data: Data(token.value.utf8))).hexadecimal
    let from = await inbox.count
    try child.send(
      try JSONLines.encoder.encode(EffectLedgerControl(run: run, tokenSHA256: digest)))
    let inbox = inbox
    let found = try await withDeadline(.seconds(10), "ledger registration") {
      await inbox.first(from: from) { $0["run"] == run }
    }
    guard found?.item["event"] == "registered" else {
      throw DriverError.invalid("ledger refused registration")
    }
  }

  /// Normal stop: stdin EOF, then wait for exit.
  func stop() async throws -> ChildExit? {
    child.closeStdin()
    let exit = await child.waitForExit(timeout: .seconds(20))
    if exit == nil {
      child.signal(SIGKILL)
      _ = await child.waitForExit(timeout: .seconds(20))
    }
    try await child.drainOutput()
    return child.exit
  }
}
