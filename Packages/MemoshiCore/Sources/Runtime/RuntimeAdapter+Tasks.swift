import Foundation
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable

extension RuntimeAdapter {
  func receiveTaskGraph(_ graph: PiDurable.TaskGraph, conversationID: ConversationID) async throws {
    guard let thread = threads[conversationID], !thread.failed else { return }
    thread.lastUsed = .now
    try await drainToolOutcomes(thread)
    try await reconcileSubagents(thread, graph: graph)
    try await reconcileParkedTurns(thread, graph: graph)
    try await applyResumeDecisions(thread, graph: graph)
    try await settleUndispatchedSteps(thread, graph: graph)
  }

  /// Discover the SDK's real task-owned child scopes, including a spawn whose app projection
  /// was interrupted. Unknown ownership fails closed, never becoming a new app conversation.
  func childConversations(_ thread: RuntimeThread) async throws -> [PiDurable.ConversationId] {
    if let known = thread.piChildren { return known.sorted() }
    var cursor: PiDurable.Cursor?
    var children: [PiDurable.ConversationId] = []
    repeat {
      let page = try await thread.storage.scanConversations(
        .init(ownerConversationId: .root),
        limit: 128, cursor: cursor)
      for record in page.items {
        _ = try await RuntimeTaskScope.child(
          record.id, storage: thread.storage, store: store,
          chat: thread.conversation, fence: thread.ownership.fence)
        children.append(record.id)
      }
      cursor = page.next
    } while cursor != nil
    thread.piChildren = Set(children)
    return children
  }

  func policyTaskID(
    conversation: PiDurable.ConversationId, assistant: PiDurable.EntryId, thread: RuntimeThread
  ) async throws -> MemoshiProtocol.TaskID {
    if conversation == .root {
      return try await RuntimeTaskScope.originalTaskID(
        before: assistant, storage: thread.storage,
        store: store, chat: thread.conversationID)
    }
    return try await RuntimeTaskScope.child(
      conversation, storage: thread.storage, store: store,
      chat: thread.conversation, fence: thread.ownership.fence
    ).taskId
  }

  func reconcileSubagents(_ thread: RuntimeThread, graph: PiDurable.TaskGraph) async throws {
    if thread.piChildren == nil { _ = try await childConversations(thread) }
    for value in graph.tasks.values {
      let node = try value.decode(PiDurable.TaskGraphNode.self)
      for child in node.conversations where thread.piChildren?.contains(child) != true {
        _ = try await RuntimeTaskScope.child(
          child, storage: thread.storage, store: store,
          chat: thread.conversation, fence: thread.ownership.fence)
        thread.piChildren?.insert(child)
      }
    }
    for binding in try await store.runtimeSubagents(thread.conversationID, activeOnly: true) {
      let id = PiDurable.TaskId(binding.piOwnerTaskId)
      guard let owner = try await thread.storage.task(id) else {
        throw RuntimeError.projectionFailed
      }
      if owner.status != .terminal { try await ensureChildEvents(binding, thread: thread) }
      let node = try graph[id]
      let status: MemoshiProtocol.TaskStatus
      if owner.status == .terminal {
        let submission = try await thread.storage.submissionByRequest(
          ConversationId(binding.piConversationId), requestId: PiCore.JSONString(binding.requestId))
        if owner.state.outcome?.status == .aborted || submission?.reason == "aborted" {
          status = .canceled
        } else if owner.state.outcome?.status != .completed {
          status = .failed
        } else if let submission, submission.status == .done, let answer = submission.answer,
          let entry = try await thread.storage.entry(
            conversationId: ConversationId(binding.piConversationId), answer)?.entry,
          let message = entry.model?.first?.assistantMessage, message.toolCalls.isEmpty
        {
          status =
            message.stopReason == .aborted
            ? .canceled : (message.stopReason == .error ? .failed : .done)
        } else {
          status = .failed
        }
      } else {
        // Use the actual committed graph for live state; not a timer, a separate Session or a
        // fabricated lifecycle. Storage is the authority when an old frame trails settlement.
        let state = node?.state.status ?? owner.status
        switch state {
        case .pending: status = .queued
        case .waiting, .sleeping, .completing: status = .waiting
        case .running: status = .running
        case .terminal: throw RuntimeError.projectionFailed
        }
      }
      try await store.projectRuntimeSubagent(
        binding.taskId, status: status,
        cancelRequested: owner.abortRequested, fence: thread.ownership.fence,
        at: IDGenerator.nowMilliseconds())
      if [.done, .failed, .canceled].contains(status) {
        thread.liveSubagents.remove(binding.taskId)
        await stopChildEvents(ConversationId(binding.piConversationId), thread: thread)
      } else {
        thread.liveSubagents.insert(binding.taskId)
      }
    }
  }

  /// A task-targeted Stop has its own durable receipt and never targets a later root turn or
  /// a different background anchor. Replaying it repeats only that immutable Pi target.
  public func abortTask(_ params: TasksAbortParams) async throws -> TasksAbortResult {
    try requireReady()
    guard params.surface == nil || params.surface == .ui else { throw RuntimeError.invalidParams }
    guard let task = try await store.task(params.taskId).value else { throw ApprovalError.notFound }
    return try await withThread(task.conversationId) { adapter, thread in
      guard !thread.failed else { throw RuntimeError.projectionFailed }
      guard try await adapter.store.chatRecovery(thread.conversationID).value == nil,
        thread.engine != nil
      else { throw RuntimeError.recoveryRequired }
      let result = try await adapter.store.prepareTaskAbort(
        params,
        paramsHash: Self.paramsHash(params), fence: thread.ownership.fence,
        at: IDGenerator.nowMilliseconds())
      try await adapter.abortStoredTask(params.taskId, thread: thread)
      if thread.awaitingModels { try await adapter.resumeIfModelsKnown(thread) }
      return result
    }
  }

  func abortStoredTask(_ id: MemoshiProtocol.TaskID, thread: RuntimeThread) async throws {
    guard let task = try await store.task(id).value,
      [.queued, .running, .waiting].contains(task.status), let engine = thread.engine
    else { return }
    if let binding = try await store.runtimeSubagent(id) {
      let verified = try await RuntimeTaskScope.child(
        ConversationId(binding.piConversationId),
        storage: thread.storage, store: store, chat: thread.conversation,
        fence: thread.ownership.fence)
      guard verified == binding else { throw RuntimeError.projectionFailed }
      _ = try await engine.harness.abortTask(PiDurable.TaskId(binding.piOwnerTaskId))
    } else {
      guard task.kind == .turn,
        let turn = try await store.chatTurns(thread.conversationID).value.first(where: {
          $0.taskId == id
        })
      else { throw RuntimeError.invalidParams }
      guard let submission = turn.piSubmissionId else {
        // An admission in flight ends first, whatever its result; then the turn is read again.
        if let admission = admissions[turn.requestId] {
          _ = await admission.task.result
          try await abortStoredTask(id, thread: thread)
          return
        }
        if let admission = thread.queueAdmission {
          _ = await admission.result
          try await abortStoredTask(id, thread: thread)
          return
        }
        _ = try await store.projectChatTurn(
          turn.requestId, status: .canceled,
          fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
        if thread.activeRequest == turn.requestId { thread.activeRequest = nil }
        return
      }
      _ = try await engine.harness.abortSubmission(SubmissionId(submission))
      try await abortRootRun(engine, holding: SubmissionId(submission))
    }
  }

  /// Stops the conversation's root run, only the one that holds `submission` when given. A run
  /// hands itself to a new Pi task at every model round. A stop that finds the task it read
  /// already ended is therefore repeated against the run's next task, not lost.
  func abortRootRun(_ engine: RuntimeEngine, holding submission: SubmissionId?) async throws {
    var ended: PiDurable.TaskId?
    while let run = try await engine.harness.snapshot(
      PiDurable.liveDoc, owner: ConversationId.root.rawValue)?.run,
      run.taskId != ended, submission.map({ run.inputs.contains($0) }) ?? true
    {
      guard try await engine.harness.abortTask(run.taskId) == .terminal else { return }
      ended = run.taskId
    }
  }

  /// An abort committed just before a process death is applied before scheduler resumption.
  func reconcileTaskAborts(_ thread: RuntimeThread) async throws {
    for task in try await store.taskGraph(thread.conversationID).value
    where task.cancelRequestedAt != nil && [.queued, .running, .waiting].contains(task.status) {
      try await abortStoredTask(task.id, thread: thread)
    }
  }

  /// Reconciles actual Pi child outcomes before returning this conversation's persisted graph.
  public func taskGraph(_ params: TasksGraphParams) async throws -> TasksGraphResult {
    try requireReady()
    return try await withThread(params.conversationId) { adapter, thread in
      guard !thread.failed else { throw RuntimeError.projectionFailed }
      try await adapter.drainToolOutcomes(thread)
      if let engine = thread.engine {
        try await adapter.reconcileSubagents(thread, graph: engine.taskGraph.value)
      }
      let snapshot = try await adapter.store.taskGraph(params.conversationId)
      return TasksGraphResult(nodes: snapshot.value, asOf: snapshot.asOf)
    }
  }

  /// Reads a bounded page from a verified task-owned Pi child without moving its ownership.
  public func taskHistory(_ params: TasksHistoryParams) async throws -> TasksHistoryResult {
    try requireReady()
    guard params.limit.isWithinLimits else { throw RuntimeError.invalidParams }
    guard let binding = try await store.runtimeSubagent(params.taskId) else {
      throw ApprovalError.notFound
    }
    return try await withThread(binding.conversationId) { adapter, thread in
      guard !thread.failed else { throw RuntimeError.projectionFailed }
      let child = PiDurable.ConversationId(binding.piConversationId)
      let verified = try await RuntimeTaskScope.child(
        child, storage: thread.storage, store: adapter.store,
        chat: thread.conversation, fence: thread.ownership.fence)
      guard verified == binding else { throw RuntimeError.projectionFailed }
      var maximum: PiDurable.EntryId?
      if let before = params.before {
        guard let number = Int(before), number > 0, String(number) == before,
          let entry = try await thread.storage.entry(conversationId: child, EntryId(number))?.entry,
          entry.conversationId == child
        else { throw RuntimeError.invalidParams }
        maximum = EntryId(number - 1)
      }
      var cursor: PiDurable.Cursor?
      var items: [TaskHistoryMessage] = []
      repeat {
        let page = try await thread.storage.scanEntries(
          .init(
            conversationId: child,
            maxEntryId: maximum, order: .descending), limit: 128, cursor: cursor)
        for entry in page.items {
          guard let message = entry.model?.first else { continue }
          let role: MessageRole
          let stopReason: MemoshiProtocol.StopReason?
          let text: String
          switch message {
          case .user(let value):
            role = .user
            stopReason = nil
            text = value.content.blocks.compactMap { $0.textContent?.text.displayString }.joined()
          case .assistant(let value):
            role = .bot
            stopReason = Self.stopReason(value.stopReason)
            text = Self.text(value)
          default: continue
          }
          items.append(
            TaskHistoryMessage(
              entryId: String(entry.id.rawValue), role: role,
              text: text, stopReason: stopReason))
          if items.count > params.limit.rawValue { break }
        }
        cursor = page.next
      } while items.count <= params.limit.rawValue && cursor != nil
      let hasMore = items.count > params.limit.rawValue
      if hasMore { items.removeLast() }
      items.reverse()
      let live = try await thread.engine?.harness.snapshot(PiDurable.liveDoc, owner: child.rawValue)
      let snapshot = try await adapter.store.task(params.taskId)
      guard let task = snapshot.value else { throw RuntimeError.projectionFailed }
      return TasksHistoryResult(
        task: task, background: binding.background, items: items,
        liveText: live?.generation?.message.map(Self.text),
        nextBefore: hasMore ? items.first?.entryId : nil, asOf: snapshot.asOf)
    }
  }
}
