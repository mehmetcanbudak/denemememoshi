import Chord
import Foundation
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable

extension RuntimeAdapter {
  /// The conversation's open thread. It opens on first use, once: concurrent callers join the
  /// same open, and a conversation that is closing for idleness finishes closing, then reopens.
  /// After resume() a newly opened thread resumes its scheduler before any caller uses it.
  func openedThread(_ id: ConversationID) async throws -> RuntimeThread {
    while true {
      try requireReady()
      guard lifecycleAdmissions[id] == nil else { throw RuntimeError.busy }
      if let opening = openings[id] {
        try await opening.value
        if let thread = threads[id] { return thread }
        continue
      }
      if let closing = threadClosings[id] {
        await closing.value
        continue
      }
      if let thread = threads[id] { return thread }
      guard let conversation = try await store.conversation(id) else {
        throw StoreError.chatNotFound
      }
      // The lookup suspended this actor: another caller may have begun an open or a close.
      if openings[id] != nil || threadClosings[id] != nil || threads[id] != nil
        || lifecycleAdmissions[id] != nil
      {
        continue
      }
      let task = Task { try await self.openAndResume(conversation) }
      openings[id] = task
      defer { openings[id] = nil }
      try await task.value
      if let thread = threads[id] { return thread }
    }
  }

  private func openAndResume(_ conversation: ChatSummary) async throws {
    let thread = try await openThread(conversation)
    guard schedulerResumed else { return }
    do {
      try await resumeThread(thread)
    } catch {
      // Nothing half-resumed stays open; the next call opens the conversation again.
      try? await closeThread(thread, quiescing: false)
      throw error
    }
  }

  /// Runs one call against the conversation's open thread; an idle close leaves a thread in
  /// use open, and measures idleness from the call's end. The body runs on this actor.
  func withThread<Result>(
    _ id: ConversationID, _ body: (isolated RuntimeAdapter, RuntimeThread) async throws -> Result
  ) async throws -> Result {
    let thread = try await openedThread(id)
    guard lifecycleAdmissions[id] == nil, !closing else { throw RuntimeError.busy }
    thread.users += 1
    defer {
      thread.users -= 1
      thread.lastUsed = .now
    }
    return try await body(self, thread)
  }

  /// Claims the conversation's local lease, reserves and opens its own Pi store, then activates
  /// its engine unless a recovery hold keeps it inspection-only.
  @discardableResult
  func openThread(_ conversation: ChatSummary) async throws -> RuntimeThread {
    let now = IDGenerator.nowMilliseconds()
    let id = conversation.id
    let previous = try await store.lease(id)
    let lease: MemoshiStore.ConversationLease
    let claimedLease: Bool
    if let previous, previous.runnerDeviceID == store.deviceID, (previous.expiresAt ?? 0) > now {
      lease = previous
      claimedLease = false
    } else {
      // This is process-local ownership, not a fabricated distributed lease or Pi commit fence.
      lease = try await store.claimConversation(
        id, expectedEpoch: previous?.epoch, expiresAt: Int64.max, at: now)
      claimedLease = true
    }
    var ownership: MemoshiStore.ConversationOwnership?
    var storage: PiDurable.SqliteStorage?
    do {
      let acquired = try await store.acquireConversation(lease.fence, at: now)
      ownership = acquired
      _ = try await store.ensureBotPolicy(conversation.botId, at: now)
      let opened = try await PiDurable.openSqliteStorage(acquired.fileURL.path)
      storage = opened
      let thread = RuntimeThread(conversation: conversation, ownership: acquired, storage: opened)
      threads[id] = thread
      do {
        try await activateThread(thread)
        thread.interruptedTurns = try await interruptedTurns(thread)
        thread.interruptedSubagents = try await interruptedSubagents(thread)
      } catch RuntimeError.recoveryRequired {
        try await reconcile(thread)
      }
      return thread
    } catch {
      if let thread = threads.removeValue(forKey: id), let engine = thread.engine {
        await stopChildEvents(thread)
        _ = await engine.events.stop()
        _ = await engine.taskGraph.stop()
        engine.stopToolOutcomes()
        try? await engine.harness.close()
      } else if let storage {
        try? await storage.close()
      }
      ownership?.release()
      // A reused lease may belong to the live runtime whose flock refused this open.
      // Release only a claim made here, or a lease whose actual ownership we acquired.
      if claimedLease || ownership != nil {
        try? await store.releaseConversation(lease.fence, at: IDGenerator.nowMilliseconds())
      }
      throw error
    }
  }

  /// The one teardown of an open thread, by close() or after it was idle. A close stops no
  /// work (D139): with `quiescing`, as close() closes every thread, what still runs is left to
  /// Pi's close, which writes it back as pending, and the next open continues it as after a
  /// crash. A streaming reply is generated again, and a turn or a foreground child that waits
  /// on the user's decision asks with the same Card (object-model.md §5.2, policy.md §10.1);
  /// only the user's Stop ends either. An idle thread has nothing running, and its settled
  /// state is projected before it closes. Work that never resumed or that a recovery hold
  /// keeps stays durable for the next open.
  func closeThread(_ thread: RuntimeThread, quiescing: Bool) async throws {
    var failure: (any Error)?
    // An activation already in flight finishes, or fails, before its engine or storage closes.
    if let activation = thread.activation { _ = await activation.result }
    do {
      try await drainToolOutcomes(thread)
      try await store.parkUnsettledToolDispatches(
        fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
      if let engine = thread.engine, thread.resumed, !quiescing,
        try await store.chatRecovery(thread.conversationID).value == nil
      {
        try await engine.harness.waitForIdle()
        try await drainToolOutcomes(thread)
        try await reconcile(thread)
        try await reconcileSubagents(thread, graph: engine.taskGraph.value)
      }
    } catch { failure = failure ?? error }
    if let engine = thread.engine {
      await stopChildEvents(thread)
      _ = await engine.events.stop()
      _ = await engine.taskGraph.stop()
      engine.stopToolOutcomes()
      engine.closing.begin()
      do { try await engine.harness.close() } catch { failure = failure ?? error }
    } else {
      do { try await thread.storage.close() } catch { failure = failure ?? error }
    }
    thread.ownership.release()
    do {
      try await store.releaseConversation(
        thread.ownership.fence, at: IDGenerator.nowMilliseconds())
    } catch { failure = failure ?? error }
    if threads[thread.conversationID] === thread {
      threads.removeValue(forKey: thread.conversationID)
    }
    // Its Harness is closed, so nothing resolves this conversation's computer any more.
    await environments?.close(conversation: thread.conversationID)
    if let failure { throw failure }
  }

  /// Closes every open conversation unused for at least `limit` with no turn, queued input,
  /// pending approval or card and no recovery hold, whose Pi scheduler has no run (S1.2). Its
  /// lease is released; the next call reopens it under a new epoch.
  func closeIdleThreads(idleFor limit: Duration) async {
    for thread in Array(threads.values) {
      guard await isIdle(thread, for: limit) else { continue }
      // The checks suspended this actor; recheck in-memory state, then close without a gap.
      let id = thread.conversationID
      guard !closing, threads[id] === thread, threadClosings[id] == nil, openings[id] == nil,
        lifecycleAdmissions[id] == nil, isUnused(thread, for: limit)
      else { continue }
      let task = Task {
        guard let current = self.threads[id] else { return }
        try? await self.closeThread(current, quiescing: false)
      }
      threadClosings[id] = task
      await task.value
      threadClosings[id] = nil
    }
  }

  /// Checks for idle conversations at a tenth of the limit, at most every minute.
  func startIdleSweeper() {
    let limit = idleThreadLimit
    let interval = max(min(limit / 10, .seconds(60)), .milliseconds(10))
    idleSweeper = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: interval) } catch { return }
        guard let self else { return }
        await self.closeIdleThreads(idleFor: limit)
        await self.maintainSessionTrash()
      }
    }
  }

  private func isUnused(_ thread: RuntimeThread, for limit: Duration) -> Bool {
    thread.users == 0 && thread.activation == nil && thread.activeRequest == nil
      && thread.queueAdmission == nil && !thread.awaitingModels
      && ContinuousClock.now - thread.lastUsed >= limit
  }

  func isIdle(_ thread: RuntimeThread, for limit: Duration) async -> Bool {
    guard isUnused(thread, for: limit),
      (try? await store.conversationIsIdle(thread.conversationID)) == true
    else { return false }
    guard let engine = thread.engine else { return true }
    do {
      let live = try await engine.harness.snapshot(
        PiDurable.liveDoc, owner: ConversationId.root.rawValue)
      return live?.run == nil
    } catch {
      return false
    }
  }

  /// The agent fields every submission sets from current records (S1.5): the model, its
  /// thinking level and the conversation's offered tools, keeping deferred tools that
  /// `tool_search` loaded. The change applies from the next request.
  func agentChange(
    _ engine: RuntimeEngine, model: PiAI.Model, thinkingLevel: PiAI.ModelThinkingLevel
  ) async throws -> PiDurable.AgentChange {
    let loaded = try await engine.harness.conversation().agent().tools.filter(\.deferred)
      .map(\.name)
    return PiDurable.AgentChange(
      model: .set(PiDurable.ModelRef(provider: model.provider, modelId: model.id)),
      thinkingLevel: .set(thinkingLevel), tools: .set(.names(engine.tools)),
      modelTools: .set(.names(engine.modelTools + loaded)))
  }

  func admit(
    _ params: ChatsSendParams, hash: String, thread: RuntimeThread, releasingQueued: Bool = false
  ) async throws -> ChatsSendResult {
    try requireReady()
    guard !configuring, threads[thread.conversationID] === thread, !thread.failed else {
      throw RuntimeError.busy
    }
    guard thread.queueAdmission == nil || releasingQueued else { throw RuntimeError.busy }
    guard params.whenBusy == nil || params.whenBusy == .reject,
      params.surface == nil || params.surface == .ui,
      !params.content.isEmpty
    else { throw RuntimeError.invalidParams }
    var parts: [String] = []
    for part in params.content {
      guard case .text(let text) = part else { throw RuntimeError.invalidParams }
      parts.append(text.text)
    }
    let text = parts.joined()
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw RuntimeError.invalidParams
    }
    let existing = try await store.chatTurn(params.requestId)
    if let existing {
      guard existing.paramsHash == hash, existing.chatId == params.chatId else {
        throw StoreError.requestConflict
      }
      if existing.userEntryId != nil || (!releasingQueued && existing.queueReason != nil) {
        return existing.receipt(replayed: true)
      }
      if existing.isTerminal { return existing.receipt(replayed: true) }
    }
    // The request's model and effort win, else the bot's current ones (S1.5). A retry of an
    // original request reuses the choice its turn recorded.
    let profile = try await store.bot(thread.botID).value
    let requested = existing?.model ?? params.model
    let explicit = requested.flatMap { $0.ref.rawValue == "default" ? nil : $0 }
    let configured = profile.flatMap { $0.model.ref.rawValue == "default" ? nil : $0.model }
    let effort = requested?.effort ?? profile?.model.effort ?? .off
    guard let level = PiAI.ModelThinkingLevel(rawValue: effort.rawValue) else {
      throw RuntimeError.invalidParams
    }
    let choice = explicit ?? configured
    let pieces = choice.map { $0.ref.rawValue.split(separator: "/", maxSplits: 1).map(String.init) }
    if let pieces {
      guard pieces.count == 2,
        try await store.modelProviders().value.contains(where: { $0.id == pieces[0] })
      else {
        // A request naming no configured provider is invalid; a bot's stale choice is unavailable.
        if explicit != nil { throw RuntimeError.invalidParams }
        throw RuntimeError.modelUnavailable
      }
    }
    if try await store.chatRecovery(params.chatId).value != nil {
      guard !releasingQueued else { throw StoreError.chatRecoveryRequired }
      // The Store rechecks the hold atomically with queuing. Once it has cleared nothing is
      // reserved here, so normal admission below releases older queued inputs first. A send
      // with no request or bot model queues that `default` reference: no model is looked up
      // and no engine opens while held, and its release resolves the first local model.
      if let queued = try await store.queueHeldChatTurn(
        params, paramsHash: hash,
        model: ModelRef(ref: try choice?.ref ?? ModelName("default"), effort: effort),
        fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
      {
        return queued.receipt(replayed: existing != nil)
      }
    }
    let model: PiAI.Model?
    if let pieces {
      model = modelRegistry.getModel(PiCore.JSONString(pieces[0]), PiCore.JSONString(pieces[1]))
    } else {
      // An unspecified model never silently falls back to a paid remote provider.
      model = modelRegistry.getModels("local").first
    }
    guard let model else { throw RuntimeError.modelUnavailable }
    let selected = MemoshiProtocol.ModelRef(
      ref: try ModelName(model.provider.displayString + "/" + model.id.displayString),
      effort: effort)
    if thread.engine == nil { try await activateThread(thread) }
    if existing == nil && !releasingQueued {
      // Older durable inputs keep precedence, including any queued while this thread was held
      // open without an engine or released while another new send is admitting.
      try await drainQueuedInputs(thread)
    }
    var turn = try await store.prepareChatTurn(
      params, paramsHash: hash, model: selected, fence: thread.ownership.fence,
      at: IDGenerator.nowMilliseconds())
    if releasingQueued {
      turn = try await store.claimQueuedChatInput(
        params.requestId, fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
      // Canceled after this release read it: consumed as terminal, never submitted.
      if turn.isTerminal { return turn.receipt(replayed: true) }
    } else if turn.queueReason != nil {
      return turn.receipt(replayed: existing != nil)
    }
    guard let engine = thread.engine else { throw RuntimeError.recoveryRequired }
    thread.activeRequest = turn.requestId
    do {
      // Model, effort and tools follow the current records from this request on (S1.5).
      try await engine.harness.conversation().configure(
        try await agentChange(engine, model: model, thinkingLevel: level))
      if let current = try await store.chatTurn(turn.requestId), current.isTerminal {
        if thread.activeRequest == turn.requestId { thread.activeRequest = nil }
        return current.receipt(replayed: existing != nil)
      }
      let submission = try await engine.harness.submit(
        .input(
          content: .text(PiCore.JSONString(text)),
          whenBusy: .reject,
          entry: .init(
            kind: "memoshi.user",
            data: ["memoshiRequestId": .string(PiCore.JSONString(params.requestId.rawValue))]),
          requestId: PiCore.JSONString(params.requestId.rawValue)))
      let record = try await submission.status()
      guard record.entry != nil else {
        _ = try await submission.abort()
        throw RuntimeError.busy
      }
      try await project(record, thread: thread)
      guard let admitted = try await store.chatTurn(params.requestId) else {
        throw RuntimeError.projectionFailed
      }
      return admitted.receipt(replayed: existing != nil)
    } catch {
      if let record = try await thread.storage.submissionByRequest(
        .root,
        requestId: PiCore.JSONString(params.requestId.rawValue)), record.entry != nil
      {
        try await project(record, thread: thread)
        guard let admitted = try await store.chatTurn(params.requestId) else {
          throw RuntimeError.projectionFailed
        }
        return admitted.receipt(replayed: existing != nil)
      }
      if releasingQueued {
        try await store.returnQueuedChatInput(
          turn.requestId, fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
        if thread.activeRequest == turn.requestId { thread.activeRequest = nil }
        if error is PiDurable.ConversationBusy { throw RuntimeError.busy }
        if let error = error as? RuntimeError { throw error }
        throw RuntimeError.modelUnavailable
      }
      _ = try await store.projectChatTurn(
        turn.requestId, status: .failed,
        error: MessageError(
          code: "admission_failed", message: "The selected model did not admit this message.",
          retryable: false),
        fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
      if thread.activeRequest == turn.requestId { thread.activeRequest = nil }
      if let error = error as? RuntimeError { throw error }
      throw RuntimeError.modelUnavailable
    }
  }

  func reconcile(_ thread: RuntimeThread) async throws {
    let active = try await store.chatTurns(thread.conversationID, activeOnly: true).value
    for turn in active {
      if turn.queueReason != nil { continue }
      if let record = try await thread.storage.submissionByRequest(
        .root,
        requestId: PiCore.JSONString(turn.requestId.rawValue))
      {
        if turn.recoveryStep == nil { thread.activeRequest = turn.requestId }
        try await project(record, thread: thread)
      } else {
        // A crash before Pi admission has no model-visible input. Only the original client
        // request can retry it; never invent text or start a replacement model turn here.
        if turn.recoveryStep == nil, try await !store.hasQueuedChatInput(turn.requestId) {
          thread.activeRequest = turn.requestId
        }
      }
    }
  }

  /// The admitted turns Pi has not settled as this conversation's Harness opens, captured once:
  /// a turn this process admits later, or one a Resume answer continues, was not cut off by
  /// the restart.
  private func interruptedTurns(_ thread: RuntimeThread) async throws -> [ULID] {
    var turns: [ULID] = []
    for turn in try await store.chatTurns(thread.conversationID, activeOnly: true).value
    where turn.queueReason == nil && turn.recoveryStep == nil {
      if let record = try await thread.storage.submissionByRequest(
        .root, requestId: PiCore.JSONString(turn.requestId.rawValue)),
        record.entry != nil, !record.isSettled
      {
        turns.append(turn.requestId)
      }
    }
    return turns
  }

  /// Live subagent child tasks whose Pi owner task is still live as this Harness opens.
  private func interruptedSubagents(
    _ thread: RuntimeThread
  ) async throws -> [MemoshiProtocol.TaskID] {
    var tasks: [MemoshiProtocol.TaskID] = []
    for binding in try await store.runtimeSubagents(thread.conversationID, activeOnly: true) {
      guard let task = try await store.task(binding.taskId).value,
        task.resumeMode != .explicit, task.cancelRequestedAt == nil,
        let owner = try await thread.storage.task(PiDurable.TaskId(binding.piOwnerTaskId)),
        owner.status != .terminal, !owner.abortRequested
      else { continue }
      tasks.append(binding.taskId)
    }
    return tasks
  }

  /// events.md §5.5: just before Pi's scheduler first resumes, each turn or live subagent its
  /// Harness found cut off is recorded as resumed by `system`, since Pi then continues it by
  /// itself. Not one that has settled or was stopped meanwhile (the Store checks Memoshi's Stop,
  /// this Pi's abort mark), nor one Pi keeps parked, such as a run over its restart limit.
  func recordResumedTurns(_ thread: RuntimeThread) async throws {
    let turns = thread.interruptedTurns
    let subagents = thread.interruptedSubagents
    thread.interruptedTurns = []
    thread.interruptedSubagents = []
    guard !turns.isEmpty || !subagents.isEmpty, let engine = thread.engine else { return }
    var blockedConversations: Set<PiDurable.ConversationId> = []
    var blockedTasks: Set<PiDurable.TaskId> = []
    for value in engine.taskGraph.value.tasks.values {
      let node = try value.decode(PiDurable.TaskGraphNode.self)
      // A held interrupted step is the Resume card's to continue, not this restart's.
      if let reason = node.blocked, reason != .interruptedStep {
        blockedConversations.insert(node.conversationId)
        blockedTasks.insert(node.id)
      }
    }
    if !turns.isEmpty && !blockedConversations.contains(.root) {
      var stopping: Set<PiDurable.SubmissionId> = []
      if let run = try await engine.harness.snapshot(
        PiDurable.liveDoc, owner: ConversationId.root.rawValue)?.run,
        let task = try await thread.storage.task(run.taskId), task.abortRequested
      {
        stopping = Set(run.inputs)
      }
      for request in turns {
        guard
          let record = try await thread.storage.submissionByRequest(
            .root, requestId: PiCore.JSONString(request.rawValue)),
          !record.isSettled, !stopping.contains(record.id)
        else { continue }
        try await store.recordTurnResumed(
          request, fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
      }
    }
    for taskID in subagents {
      guard let binding = try await store.runtimeSubagent(taskID) else { continue }
      let ownerID = PiDurable.TaskId(binding.piOwnerTaskId)
      let childConversation = PiDurable.ConversationId(binding.piConversationId)
      guard !blockedTasks.contains(ownerID), !blockedConversations.contains(childConversation),
        let owner = try await thread.storage.task(ownerID),
        owner.status != .terminal, !owner.abortRequested
      else { continue }
      try await store.recordSubagentResumed(
        taskID, fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
    }
  }

  /// When Pi parks a root run after hitting its restart limit (5 restarts without progress),
  /// abort the parked run so Pi settles the submission instead of leaving the turn `"running"`
  /// and blocking the conversation. `project` turns parked submissions into `.failed`
  /// (`restart_limit`), never user-canceled.
  func reconcileParkedTurns(_ thread: RuntimeThread, graph: PiDurable.TaskGraph) async throws {
    guard let engine = thread.engine, !closing else { return }
    var parkedNodes: [PiDurable.TaskId] = []
    for value in graph.tasks.values {
      let node = try value.decode(PiDurable.TaskGraphNode.self)
      if node.conversationId == .root, node.blocked == .restartLimit, !node.abortRequested {
        parkedNodes.append(node.id)
      }
    }
    guard !parkedNodes.isEmpty else { return }
    // A turn waiting on a pending approval is not stuck in "running"; leave its Card intact.
    let hasPendingApproval = try await store.approvals(conversationID: thread.conversationID)
      .value.contains { $0.status == .pending }
    guard !hasPendingApproval else { return }
    let active = try await store.chatTurns(thread.conversationID, activeOnly: true).value
    for turn in active where turn.queueReason == nil && turn.recoveryStep == nil {
      if let task = try await store.task(turn.taskId).value, task.cancelRequestedAt != nil {
        continue
      }
      if let record = try await thread.storage.submissionByRequest(
        .root, requestId: PiCore.JSONString(turn.requestId.rawValue)),
        record.entry != nil, !record.isSettled
      {
        thread.parkedRequests.insert(turn.requestId)
      }
    }
    if let run = try await engine.harness.snapshot(
      PiDurable.liveDoc, owner: ConversationId.root.rawValue)?.run
    {
      _ = try await engine.harness.abortTask(run.taskId)
    }
    for taskID in parkedNodes {
      _ = try await engine.harness.abortTask(taskID)
    }
  }

  func project(_ record: PiDurable.SubmissionRecord, thread: RuntimeThread) async throws {
    if record.isSettled { try await drainToolOutcomes(thread) }
    guard let key = record.requestId, let request = try? ULID(key.displayString),
      let current = try await store.chatTurn(request), !current.isTerminal
    else { return }
    let terminal = record.isSettled
    // The reply is bound once the submission settles, never from an earlier attempt's entry.
    let run = terminal ? try await settledRun(record, thread: thread) : SettledRun()
    let status: MemoshiProtocol.TaskStatus
    var failure: MessageError?
    if terminal {
      if thread.parkedRequests.contains(request) {
        status = .failed
        failure = MessageError(
          code: "restart_limit",
          message: "This turn was interrupted too many times without progress.",
          retryable: false)
      } else if run.answer?.stopReason == .aborted || record.reason == "aborted" {
        if toolDefinitions.isEmpty, extensionComposition.isEmpty,
          run.messages.contains(where: { !$0.toolCalls.isEmpty && $0.stopReason != .aborted })
        {
          // No tool is installed, so `receive` itself stopped this run after a completed
          // tool-requesting message. That is a failure the user did not ask for, never their
          // Stop; a call still streaming when someone stopped the run is not one.
          status = .failed
          failure = MessageError(
            code: "tool_unavailable",
            message: "The selected model asked for a tool, and this chat offers none.",
            retryable: false)
        } else {
          status = .canceled
        }
      } else if record.status == .done, let answer = run.answer, answer.stopReason != .error,
        answer.toolCalls.isEmpty
      {
        status = .done
      } else {
        status = .failed
        failure = MessageError(
          code: "model_failed", message: "The selected model could not finish this response.",
          retryable: false)
      }
    } else {
      status = record.entry == nil ? .queued : .running
    }
    // A stopped turn whose every reply called a tool still shows where it stopped: its final
    // reply, whose own stop reason is the tool call, is the turn's reply and reads aborted.
    let stoppedCall = run.reply == nil && status == .canceled ? run.final : nil
    let reply = run.reply ?? stoppedCall
    let result = try await store.projectChatTurn(
      request, piSubmissionID: record.id.rawValue,
      userEntryID: record.entry?.rawValue, assistantEntryID: reply?.id.rawValue,
      assistantStarted: reply != nil, status: status,
      // A failed turn's kept partial reads as failed, even one a restart converted as aborted.
      stopReason: stoppedCall != nil
        ? .aborted
        : run.reply.map { status == .failed ? .error : Self.stopReason($0.message.stopReason) },
      usage: terminal ? try await runUsage(run.messages) : nil, error: failure,
      fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
    if result.isTerminal {
      thread.parkedRequests.remove(request)
      if thread.activeRequest == request {
        thread.activeRequest = nil
        thread.text = ""
        thread.textUTF16Count = 0
      }
    } else if result.recoveryStep == nil {
      thread.activeRequest = request
    }
  }

  /// A settled submission's committed assistant entries, read from durable Pi state. The reply
  /// is Pi's answer when there is one. A failed or stopped submission keeps the last partial its
  /// user saw: the final assistant entry with text that requested no tools, else the final one
  /// that requested none. So a partial that a restart converted is not the reply once a later
  /// attempt answers, but it is when the retry fails before streaming (an empty error entry) or
  /// when the turn is stopped or parked before the retry streams anything. `final` is the last
  /// assistant entry, tool calls or not.
  func settledRun(_ record: PiDurable.SubmissionRecord, thread: RuntimeThread) async throws
    -> SettledRun
  {
    var run = SettledRun()
    var last: (id: PiDurable.EntryId, message: PiAI.AssistantMessage)?
    var lastWithText: (id: PiDurable.EntryId, message: PiAI.AssistantMessage)?
    if let input = record.entry {
      var cursor: PiDurable.Cursor?
      scan: repeat {
        let page = try await thread.storage.scanEntries(
          PiDurable.EntryQuery(
            conversationId: .root, minEntryId: PiDurable.EntryId(input.rawValue + 1),
            order: .ascending),
          limit: 64, cursor: cursor)
        for entry in page.items {
          // The next admitted input begins another submission's entries.
          if entry.data?["memoshiRequestId"] != nil { break scan }
          guard let message = entry.model?.first?.assistantMessage else { continue }
          run.messages.append(message)
          if entry.id == record.answer { run.answer = message }
          run.final = (entry.id, message)
          guard message.toolCalls.isEmpty else { continue }
          last = (entry.id, message)
          if !Self.text(message).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastWithText = (entry.id, message)
          }
        }
        cursor = page.next
      } while cursor != nil
    }
    if let answer = record.answer {
      if run.answer == nil {
        run.answer = try await thread.storage.entry(conversationId: .root, answer)?.entry.model?
          .first?.assistantMessage
      }
      run.reply = run.answer.map { (answer, $0) }
    } else {
      run.reply = lastWithText ?? last
    }
    return run
  }

  func failThread(_ conversationID: ConversationID) async {
    guard let thread = threads[conversationID] else { return }
    thread.failed = true
    // close() stops no work: it leaves every turn and child, background or not, to Pi's close
    // for the next open (D139). A callback that fails while stopping, such as a UI frame the
    // quiescing daemon refuses, must not cancel any of it.
    guard !closing else { return }
    if let engine = thread.engine,
      let snapshot = try? await store.chatRecovery(conversationID), snapshot.value == nil
    {
      try? await engine.harness.conversation().abort(background: true)
    }
  }
}

/// One settled submission's assistant messages in commit order, its answer, its reply and its
/// final assistant entry.
struct SettledRun {
  var messages: [PiAI.AssistantMessage] = []
  var answer: PiAI.AssistantMessage?
  var reply: (id: PiDurable.EntryId, message: PiAI.AssistantMessage)?
  var final: (id: PiDurable.EntryId, message: PiAI.AssistantMessage)?
}
