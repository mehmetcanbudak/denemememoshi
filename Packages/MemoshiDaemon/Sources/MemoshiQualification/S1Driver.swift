import Darwin
import Foundation
import MemoshiProtocol
import MemoshiStore

/// Finite S1.1 plus reachable S1.2/S1.16 development evidence. No gate budgets are applied.
package enum S1Driver {
  package static func run(_ options: S1Options) async -> Int32 {
    let results = S1Results()
    let owned = S1Children()
    let paths: QualificationPaths
    do {
      guard (1...30).contains(options.openSamples), options.timeout > .zero else {
        throw DriverError.invalid("S1 needs 1...30 open samples and a positive timeout")
      }
      paths = try QualificationPaths(work: options.workDirectory, output: options.outputDirectory)
    } catch {
      LineWriter.standardError.text("s1: \(error)")
      return 64
    }
    let canary = Canary.generate(label: "s1-provider-bearer")
    var ownsWork = false
    var ownsOutput = false
    var provider: S1Provider?
    var requestsHandle: FileHandle?
    do {
      try QualificationPaths.create(paths.work)
      ownsWork = true
      try QualificationPaths.create(paths.output)
      ownsOutput = true
      let logs = paths.output.appendingPathComponent("logs", isDirectory: true)
      try QualificationPaths.create(logs)
      try QualificationPaths.create(paths.work.appendingPathComponent("home", isDirectory: true))
      try QualificationPaths.create(paths.work.appendingPathComponent("tmp", isDirectory: true))
      let requestURL = logs.appendingPathComponent("requests.jsonl")
      try Data().write(to: requestURL, options: .withoutOverwriting)
      let handle = try FileHandle(forWritingTo: requestURL)
      requestsHandle = handle
      let server = try await S1Provider.start(bearer: canary)
      provider = server
      let scenario = S1Scenario(
        options: options, paths: paths, logs: logs, provider: server, bearer: canary,
        requests: LineWriter(handle: handle), results: results, owned: owned)
      try await withDeadline(options.timeout, "S1 finite scenario") { try await scenario.run() }
    } catch {
      await results.fail(String(describing: error))
      LineWriter.standardError.text("s1: \(error)")
    }
    // Runs after startup errors and deadline cancellation, too. Only registered children can
    // be signaled. Provider close terminates its own held HTTP sockets, not any external server.
    await owned.stopAll(results)
    if let provider {
      await provider.close()
      await results.provider(provider.summary)
      let summary = provider.summary
      if summary.unauthorized != 0 || summary.unexpected != 0
        || summary.contextIsolationFailures != 0 || summary.requestSecretHits != 0
      {
        await results.fail(
          "S1 controlled provider recorded an authorization, shape, context or secret invariant failure"
        )
      }
    }
    do { try requestsHandle?.close() } catch {
      await results.fail("S1 request log could not be closed")
    }
    if ownsWork {
      do {
        let scan = try CanaryScanner(canaries: [canary]).scan([paths.work])
        await results.audit(scan)
        if !scan.hits.isEmpty {
          await results.fail("S1 provider bearer leaked outside its private pipe/header")
        }
      } catch {
        await results.fail("S1 canary scan failed: \(error)")
      }
      do { try FileManager.default.removeItem(at: paths.work) } catch {
        await results.fail("S1 owned work-root cleanup failed: \(error)")
      }
      if FileManager.default.fileExists(atPath: paths.work.path) {
        await results.fail("S1 owned work root remains after cleanup")
      }
    }
    if ownsOutput {
      do {
        try await results.write(
          to: paths.output, executable: options.executable, arguments: options.arguments,
          scanner: CanaryScanner(canaries: [canary]))
      } catch {
        await results.fail("S1 report could not be retained: \(error)")
        LineWriter.standardError.text("s1 report: \(error)")
      }
    }
    return await results.failures.isEmpty ? 0 : 1
  }
}

private struct S1PendingTurn: Sendable {
  let token: String
  let params: ChatsSendParams
}

/// One isolated batch; all mutable scenario state stays on this actor.
private actor S1Scenario {
  let options: S1Options
  let paths: QualificationPaths
  let logs: URL
  let provider: S1Provider
  let bearer: Canary
  let providerReference = ModelCredentialReference(kind: .apiKey).rawValue
  let requests: LineWriter
  let results: S1Results
  let owned: S1Children
  var life = 0
  var originals: [S1SubmittedTurn] = []

  init(
    options: S1Options, paths: QualificationPaths, logs: URL, provider: S1Provider, bearer: Canary,
    requests: LineWriter, results: S1Results, owned: S1Children
  ) {
    self.options = options
    self.paths = paths
    self.logs = logs
    self.provider = provider
    self.bearer = bearer
    self.requests = requests
    self.results = results
    self.owned = owned
  }

  func run() async throws {
    let first = try await boot()
    let listed = try await first.call(BotsList.self, BotsListParams()).value.items
    guard listed.count == 1, let assistant = listed.first, assistant.role == .assistant else {
      throw DriverError.invalid("S1 root must start with exactly one real Assistant")
    }
    var bots: [Bot] = []
    for name in ["Cedar", "Birch", "Maple"] {
      let created = try await first.call(
        BotsCreate.self, BotsCreateParams(requestId: IDGenerator.shared.next(), name: name)
      ).value
      guard created.bot.role == .bot, created.bot.name == name else {
        throw DriverError.invalid("S1 named bot was not created")
      }
      bots.append(created.bot)
    }
    let session = try await first.call(
      SessionsCreate.self,
      SessionsCreateParams(
        requestId: IDGenerator.shared.next(), leadBotId: bots[0].id, title: "S1 Work Session")
    )
    .value.session
    let five = try await first.call(ChatsList.self, EmptyParams()).value.items
    let requiredIDs = Set(
      try ([assistant.chatId] + bots.map(\.chatId)).map { try ConversationID($0.rawValue) }
        + [try ConversationID(session.id.rawValue)])
    guard five.count == 5, Set(five.map(\.id)) == requiredIDs,
      five.filter({ $0.kind == .assistant }).count == 1,
      five.filter({ $0.kind == .bot }).count == 3,
      five.filter({ $0.kind == .session }).count == 1,
      Set(five.map(\.id)).count == 5
    else { throw DriverError.invalid("S1 Assistant + three bot Chats + Session mapping") }
    await results.check("assistant-three-bots-session")
    try await configure(first)
    let cursor = await first.cursor()
    let killedTurns = try await send(first, to: five.map(\.id), phase: "kill", pause: true)
    let beforeKill = try await first.probe(killedTurns.map(\.params.requestId))
    guard beforeKill.turns.count == 5, Set(beforeKill.turns.map(\.requestId)).count == 5,
      Set(beforeKill.turns.map(\.assistantMessageId)).count == 5
    else { throw DriverError.invalid("S1 pre-kill turn identities are not one-to-one") }
    try save(beforeKill, as: "admitted-before-kill.json")
    try await provider.waitUntilHeld(Set(killedTurns.map(\.token)))
    try await first.streaming(requiredIDs, from: cursor)
    let streaming = try await first.probe()
    guard streaming.openThreads == 5, streaming.liveRuns == 5 else {
      throw DriverError.invalid("S1 kill requires five live conversation streams")
    }
    try await first.killWhileStreaming()
    await results.check("owned-sigkill-while-five-streaming")

    let reopened = try await boot()
    for turn in killedTurns {
      let replay = try await reopened.call(ChatsSend.self, turn.params).value
      try S1Invariants.replay(turn.receipt, replay)
      await results.check("original-receipt-replayed-after-kill")
    }
    let settled = try await waitSettled(reopened)
    try S1Invariants.settled(settled, originals: originals)
    let beforeByRequest = Dictionary(
      uniqueKeysWithValues: beforeKill.turns.map { ($0.requestId, $0) })
    for turn in settled {
      guard beforeByRequest[turn.requestId]?.assistantMessageId == turn.assistantMessageId else {
        throw DriverError.invalid("S1 restart replaced a reserved answer identity")
      }
    }
    try await histories(
      reopened, conversations: five, states: settled, filename: "histories-after-kill.json")
    try verifyPiFiles(five)
    await results.check("isolated-pi-stores-after-kill", five.count)

    // Exactly ten conversations for footprint and concurrency samples: nine home Chats (the
    // Assistant and eight named bots) and one Session, not a claim of ten distinct bot Harnesses.
    for index in 1...5 {
      _ = try await reopened.call(
        BotsCreate.self,
        BotsCreateParams(requestId: IDGenerator.shared.next(), name: "S1 Extra \(index)"))
    }
    let ten = try await reopened.call(ChatsList.self, EmptyParams()).value.items
    guard ten.count == 10, Set(ten.map(\.id)).count == 10 else {
      throw DriverError.invalid("S1 footprint needs ten actual conversations")
    }
    try save(ten, as: "conversation-layout.json")
    try await stopNormally(reopened)

    var measured: S1Child?
    for sample in 1...options.openSamples {
      let child = try await boot()
      let ready = try await child.probe()
      guard ready.openThreads == 0, ready.liveRuns == 0, ready.awaitingModels == 0 else {
        throw DriverError.invalid("S1 settled conversations were not opened lazily")
      }
      // Excluded from the per-conversation interval; every provider is explicitly configured.
      _ = try await child.call(ModelsList.self, EmptyParams())
      let baseline = try await child.probe()
      await recordProcess(baseline, phase: "zero-open", conversation: "all")
      var previous = baseline.footprintBytes
      let providerCompletions = provider.summary.completions
      for (index, conversation) in ten.enumerated() {
        let history = try await child.call(
          ChatsHistory.self, ChatsHistoryParams(chatId: conversation.id, limit: 200))
        guard history.measurement.openThreadsBefore == index,
          history.measurement.openThreadsAfter == index + 1,
          history.measurement.liveRunsAfter == 0
        else { throw DriverError.invalid("S1 open/resume did not lazily add exactly one Harness") }
        await results.add(
          S1Sample(
            series: "conversation-open-resume-history", life: life,
            conversation: conversation.id.rawValue, value: history.measurement.durationNs,
            unit: "ns"))
        let expected = originals.filter { $0.params.chatId == conversation.id }
        try S1Invariants.history(
          history.value, conversation: conversation.id, originals: expected, turns: settled)
        let reading = try await child.probe()
        if let current = reading.footprintBytes, let previous {
          await results.add(
            S1Sample(
              series: "footprint-increment-per-open", life: life,
              conversation: conversation.id.rawValue, value: current - previous, unit: "bytes"))
        }
        previous = reading.footprintBytes
      }
      guard provider.summary.completions == providerCompletions else {
        throw DriverError.invalid("S1 settled store open unexpectedly generated model work")
      }
      await results.check("lazy-open-resume-history", ten.count)
      if sample < options.openSamples { try await stopNormally(child) } else { measured = child }
    }
    guard let measured else { throw DriverError.invalid("S1 open sample host missing") }
    try verifyPiFiles(ten)
    try await footprints(measured, streams: [], phase: "ten-open-idle")

    let fourIDs = Array(ten.prefix(4).map(\.id))
    let fourCursor = await measured.cursor()
    let four = try await send(measured, to: fourIDs, phase: "footprint", pause: true)
    try await provider.waitUntilHeld(Set(four.map(\.token)))
    try await measured.streaming(Set(fourIDs), from: fourCursor)
    try await footprints(measured, streams: four, phase: "ten-open-four-streaming")
    provider.release(Set(four.map(\.token)))
    _ = try await waitSettled(measured)
    await results.check("ten-open-four-streaming-footprint")

    let eightIDs = Array(ten.prefix(8).map(\.id))
    let eightCursor = await measured.cursor()
    let eight = try await send(measured, to: eightIDs, phase: "eight", pause: true)
    let held = Set(eight.map(\.token))
    try await provider.waitUntilHeld(held)
    try await measured.streaming(Set(eightIDs), from: eightCursor)
    let pacedBefore = provider.summary.pacedDeltas
    for index in 0..<64 {
      try Task.checkCancellation()
      guard provider.held.isSuperset(of: held) else {
        throw DriverError.invalid("S1 eight-stream commit measurement lost a held provider stream")
      }
      let reply = try await measured.control(
        "commit", retentionDays: index.isMultiple(of: 2) ? 31 : 30)
      guard reply.committedEvents == 1, let duration = reply.durationNs else {
        throw DriverError.invalid("S1 commit measurement lacks a real changed event")
      }
      await results.add(
        S1Sample(
          series: "retention-commit-eight-streams", life: life, conversation: "all",
          value: duration, unit: "ns"))
      // Outside each measured Store interval: keep the batch long enough for paced SSE work.
      try await Task.sleep(for: .milliseconds(1))
    }
    guard
      held.allSatisfy({
        provider.summary.pacedDeltas[$0, default: 0] > pacedBefore[$0, default: 0]
      })
    else {
      throw DriverError.invalid(
        "S1 commit batch did not overlap text delivery on all eight streams")
    }
    provider.release(held)
    let finalStates = try await waitSettled(measured)
    try S1Invariants.settled(finalStates, originals: originals)
    await results.check("real-retention-commits-with-eight-streams", 64)

    // Replaying every original again after all later mutations also catches mutable writtenSeq.
    for turn in originals {
      let replay = try await measured.call(ChatsSend.self, turn.params).value
      try S1Invariants.replay(turn.receipt, replay)
      await results.check("original-receipt-replayed-after-later-mutations")
    }
    try await histories(
      measured, conversations: ten, states: finalStates, filename: "histories-final.json")
    try save(originals, as: "original-sends-and-receipts.json")
    try save(finalStates, as: "settled-turns.json")
    try await auditEvents(measured, states: finalStates)
    try await stopNormally(measured)
  }

  private func boot() async throws -> S1Child {
    try Task.checkCancellation()
    life += 1
    let child = try await S1Child.spawn(
      name: "host-life-\(life)", executable: options.executable,
      environment: [
        "HOME": paths.work.appendingPathComponent("home").path,
        "TMPDIR": paths.work.appendingPathComponent("tmp").path + "/", "PATH": "/usr/bin:/bin",
      ],
      logs: logs, requests: requests, owned: owned,
      configuration: S1HostConfiguration(
        directory: paths.work.appendingPathComponent("data", isDirectory: true).path,
        providerBaseURL: provider.baseURL, providerSecretRef: providerReference,
        providerBearer: bearer.value))
    _ = try await child.ready()
    await results.add(
      S1Sample(
        series: "process-spawn-to-ready", life: life, conversation: "all",
        value: S1Clock.nanoseconds(since: child.process.spawnedAt), unit: "ns"))
    return child
  }

  private func configure(_ child: S1Child) async throws {
    _ = try await child.call(
      ModelsProvidersConfigure.self,
      ModelsProvidersConfigureParams(
        requestId: IDGenerator.shared.next(), providerId: "local", baseUrl: provider.baseURL,
        secretRef: providerReference))
    let providers = try await child.call(ModelsProvidersList.self, EmptyParams()).value.items
    guard providers.count == 1, providers[0].id == "local",
      providers[0].baseUrl == provider.baseURL,
      providers[0].secretRef == providerReference
    else { throw DriverError.invalid("S1 provider configuration escaped its owned loopback") }
    let models = try await child.call(ModelsList.self, EmptyParams()).value
    guard models.items.contains(where: { $0.ref.ref.rawValue == "local/" + S1Provider.modelID })
    else {
      throw DriverError.invalid("S1 actual PiAI discovery did not list its scripted model")
    }
  }

  private func send(
    _ child: S1Child, to conversations: [ConversationID], phase: String, pause: Bool
  ) async throws -> [S1SubmittedTurn] {
    var pending: [S1PendingTurn] = []
    for conversation in conversations {
      let request = try IDGenerator.shared.next()
      let token = phase + "-" + request.rawValue
      try provider.register(token, conversation: conversation, pause: pause)
      pending.append(
        S1PendingTurn(
          token: token,
          params: ChatsSendParams(
            requestId: request, chatId: conversation,
            content: [.text(TextPart(text: S1Provider.userText(token)))], whenBusy: .reject,
            model: ModelRef(ref: try ModelName("local/" + S1Provider.modelID)), surface: .ui)))
    }
    let values = try await withThrowingTaskGroup(of: S1Measured<S1SubmittedTurn>.self) { group in
      for turn in pending {
        group.addTask {
          let measured = try await child.call(ChatsSend.self, turn.params)
          guard measured.value.replayed != true, measured.value.writtenSeq > 0 else {
            throw DriverError.invalid("S1 new send did not return an original committed receipt")
          }
          return S1Measured(
            value: S1SubmittedTurn(token: turn.token, params: turn.params, receipt: measured.value),
            measurement: measured.measurement)
        }
      }
      var values: [S1Measured<S1SubmittedTurn>] = []
      for try await value in group { values.append(value) }
      return values
    }
    let submitted = values.map(\.value)
    originals += submitted
    if phase == "eight" {
      for value in values {
        await results.add(
          S1Sample(
            series: "send-admission-eight", life: life,
            conversation: value.value.params.chatId.rawValue,
            value: value.measurement.durationNs, unit: "ns"))
      }
    }
    return submitted
  }

  private func waitSettled(_ child: S1Child) async throws -> [TurnState] {
    let deadline = ContinuousClock.now + .seconds(45)
    while ContinuousClock.now < deadline {
      try Task.checkCancellation()
      let reading = try await child.probe(originals.map(\.params.requestId))
      guard
        reading.turns.allSatisfy({
          !["failed", "canceled"].contains($0.status) && !$0.recoveryHeld && $0.errorCode == nil
        })
      else {
        throw DriverError.invalid(
          "S1 turn failed, canceled or entered recovery instead of settling")
      }
      if reading.liveRuns == 0, reading.awaitingModels == 0,
        reading.turns.count == originals.count, reading.turns.allSatisfy({ $0.status == "done" })
      {
        return reading.turns
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw DriverError.timeout("S1 all original turns settled")
  }

  private func histories(
    _ child: S1Child, conversations: [ChatSummary], states: [TurnState], filename: String
  ) async throws {
    var pages: [String: ChatsHistoryResult] = [:]
    var globalIDs = Set<MessageID>()
    for conversation in conversations {
      let history = try await child.call(
        ChatsHistory.self, ChatsHistoryParams(chatId: conversation.id, limit: 200)
      ).value
      let expected = originals.filter { $0.params.chatId == conversation.id }
      try S1Invariants.history(
        history, conversation: conversation.id, originals: expected, turns: states)
      for message in history.items {
        guard globalIDs.insert(message.id).inserted else {
          throw DriverError.invalid("S1 message identity appeared in two conversation histories")
        }
      }
      pages[conversation.id.rawValue] = history
    }
    try save(pages, as: filename)
    await results.check("exact-one-user-and-settled-answer", originals.count)
    await results.check("isolated-conversation-history", conversations.count)
  }

  private func footprints(_ child: S1Child, streams: [S1SubmittedTurn], phase: String) async throws
  {
    let held = Set(streams.map(\.token))
    let pacedBefore = provider.summary.pacedDeltas
    for _ in 0..<20 {
      try Task.checkCancellation()
      let reading = try await child.probe()
      guard reading.openThreads == 10, reading.liveRuns == streams.count,
        provider.held.isSuperset(of: held)
      else {
        throw DriverError.invalid(
          "S1 process footprint sample has the wrong open/streaming workload")
      }
      await recordProcess(reading, phase: phase, conversation: "all")
      try await Task.sleep(for: .milliseconds(10))
    }
    guard
      held.allSatisfy({
        provider.summary.pacedDeltas[$0, default: 0] > pacedBefore[$0, default: 0]
      })
    else {
      throw DriverError.invalid("S1 footprint interval did not overlap its actual text streams")
    }
  }

  private func recordProcess(_ reading: S1ProcessReading, phase: String, conversation: String) async
  {
    for (suffix, value) in [
      ("footprint", reading.footprintBytes), ("resident", reading.residentBytes),
      ("lifetime-maxrss", reading.maximumResidentBytes),
    ] {
      if let value {
        await results.add(
          S1Sample(
            series: phase + "-" + suffix, life: life, conversation: conversation, value: value,
            unit: "bytes"))
      } else {
        await results.check("unavailable-" + suffix)
      }
    }
  }

  private func auditEvents(_ child: S1Child, states: [TurnState]) async throws {
    var after: Int64 = 0
    var through: Int64?
    var events: [EventEnvelope] = []
    while true {
      let reply = try await child.control("events", after: after, through: through)
      guard let page = reply.page else { throw DriverError.invalid("S1 replay page missing") }
      if through == nil { through = page.through }
      guard page.through == through else {
        throw DriverError.invalid("S1 replay changed its fixed head")
      }
      for event in page.events {
        guard event.seq == after + 1 else {
          throw DriverError.invalid("S1 event replay sequence gap")
        }
        if case .messageDelta = event.event {
          throw DriverError.invalid("S1 live delta persisted in event log")
        }
        after += 1
        events.append(event)
      }
      guard after == page.nextAfter else { throw DriverError.invalid("S1 replay cursor mismatch") }
      if !page.hasMore { break }
    }
    let encoder = ProtocolCoding.makeEncoder()
    let transcriptNeedles = originals.flatMap {
      [S1Provider.userText($0.token), S1Provider.finalText($0.token)]
    }
    var log = Data()
    for event in events {
      let encoded = try encoder.encode(event)
      // Neither the exact user marker nor settled reply may be in canonical durable events.
      let text = String(decoding: encoded, as: UTF8.self)
      guard !transcriptNeedles.contains(where: { text.contains($0) }) else {
        throw DriverError.invalid("S1 event log duplicated transcript content")
      }
      log.append(encoded)
      log.append(UInt8(ascii: "\n"))
    }
    try log.write(
      to: paths.output.appendingPathComponent("event-log.jsonl"), options: .withoutOverwriting)
    let byRequest = Dictionary(uniqueKeysWithValues: states.map { ($0.requestId, $0) })
    for turn in originals {
      let scoped = events.filter { $0.scope.taskId == turn.receipt.taskId }
      var types: [String: Int] = [:]
      var payloadBytes: Int64 = 0
      var envelopeBytes: Int64 = 0
      var users = 0
      var answers = 0
      var completed = 0
      for event in scoped {
        types[event.event.type, default: 0] += 1
        guard let payload = event.event.payload else {
          throw DriverError.invalid("S1 unknown durable payload")
        }
        payloadBytes += Int64(try encoder.encode(payload).count)
        envelopeBytes += Int64(try encoder.encode(event).count)
        switch event.event {
        case .messageCreated(let value):
          if value.role == .user { users += 1 }
          if value.role == .bot { answers += 1 }
        case .messageCompleted: completed += 1
        default: break
        }
      }
      guard users == 1, answers == 1, completed == 1,
        let state = byRequest[turn.params.requestId.rawValue], state.status == "done"
      else {
        throw DriverError.invalid(
          "S1 committed event mapping duplicated or lost a turn message fact")
      }
      await results.turn(
        S1TurnBytes(
          requestId: turn.params.requestId.rawValue, conversationId: turn.params.chatId.rawValue,
          taskId: turn.receipt.taskId.rawValue, status: state.status, events: scoped.count,
          payloadBytes: payloadBytes, envelopeBytes: envelopeBytes, types: types))
      for (series, value) in [
        ("event-payload-per-turn", payloadBytes), ("event-envelope-per-turn", envelopeBytes),
      ] {
        await results.add(
          S1Sample(
            series: series, life: life, conversation: turn.params.chatId.rawValue, value: value,
            unit: "bytes"))
      }
    }
    await results.check("content-free-durable-event-mapping", originals.count)
  }

  private func verifyPiFiles(_ conversations: [ChatSummary]) throws {
    var identities = Set<String>()
    for conversation in conversations {
      let path = paths.work.appendingPathComponent("data/pi/\(conversation.id.rawValue).sqlite")
        .path
      var information = stat()
      guard lstat(path, &information) == 0, information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
        identities.insert("\(information.st_dev):\(information.st_ino)").inserted
      else {
        throw DriverError.invalid("S1 conversations do not own distinct regular Pi SQLite files")
      }
    }
  }

  private func stopNormally(_ child: S1Child) async throws {
    guard try await child.stop() == .exited(0) else {
      throw DriverError.invalid("S1 expected a clean runtime/store close")
    }
  }

  private func save(_ value: some Encodable, as filename: String) throws {
    try JSONLines.prettyEncoder.encode(value).write(
      to: paths.output.appendingPathComponent(filename), options: .withoutOverwriting)
  }
}
