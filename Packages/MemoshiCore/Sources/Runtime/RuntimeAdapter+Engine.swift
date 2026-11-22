import Foundation
import MemoshiProtocol
import MemoshiStore
import PiCore
import PiDurable

extension RuntimeAdapter {
  /// A held conversation keeps its storage reader but never opens Harness, whose recovery
  /// would otherwise mutate task state and consume restart attempts even without resume().
  /// Concurrent callers join one activation, so a second Harness never opens on this storage;
  /// close() drains an activation already in flight before closing its engine or storage.
  func activateThread(_ thread: RuntimeThread) async throws {
    guard thread.engine == nil else { return }
    if let current = thread.activation { return try await current.value }
    guard !closing else { throw RuntimeError.stopping }
    let conversationID = thread.conversationID
    let identity = ObjectIdentifier(thread)
    let task = Task { try await self.openEngine(conversationID, identity: identity) }
    thread.activation = task
    do {
      defer { thread.activation = nil }
      try await task.value
    } catch {
      // A Harness that opened and then failed closed the Pi storage this thread reads. The
      // thread closes, so the next call reopens the conversation; close() does its own teardown.
      if thread.storageClosed, !closing, threads[conversationID] === thread {
        try? await closeThread(thread, quiescing: false)
      }
      throw error
    }
  }

  private func openEngine(_ conversationID: ConversationID, identity: ObjectIdentifier)
    async throws
  {
    guard let thread = threads[conversationID], ObjectIdentifier(thread) == identity else {
      throw RuntimeError.stopping
    }
    // Explicit development/qualification composition only; `.none` connects nothing.
    let session = try await extensionSessionIfNeeded()
    let subagents = extensionComposition.subagents.map {
      RuntimeSubagents(
        configuration: $0, store: store, chat: thread.conversation,
        fence: thread.ownership.fence)
    }
    let closing = HarnessClosing()
    let policy = try PolicyHooks(
      store: store, credentials: credentials, chat: thread.conversation,
      fence: thread.ownership.fence, tools: toolDefinitions,
      extensionTools: (session?.tools ?? []) + (subagents?.tools() ?? []), closing: closing)
    try await policy.reconcile(thread.storage)
    try await reconcileToolOutcomes(thread)
    try await store.projectChatRecovery(
      conversationID, fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
    guard try await store.chatRecovery(conversationID).value == nil else {
      throw RuntimeError.recoveryRequired
    }
    let registry = PiDurable.createRegistry()
    // Bound to this conversation's (lead) bot; every request renders its current record.
    let prompt = IdentityPrompt(
      store: store, botID: thread.botID, toolsEnabled: !policy.enabledToolNames.isEmpty)
    try registry.install(.init(name: "memoshi.text", sections: prompt.sections))
    try registry.install(policy.extensionDefinition())
    for item in session?.extensions ?? [] { try registry.install(item) }
    if let subagents { try registry.install(subagents.definition()) }
    // Mandatory hooks, and a dispatch recheck wrap for every tool another extension registers.
    let installed = registry.snapshot().extension(PolicyHooks.name)
    let wrapped = Set(
      installed?.wraps.compactMap { wrap -> String? in
        guard case .tool(let name, _) = wrap else { return nil }
        return name.nativeString
      } ?? [])
    guard
      installed?.hooks.contains(where: {
        $0.task == "pi.tool" && $0.handlers.beforeTool != nil && $0.handlers.afterTool != nil
      }) == true, wrapped == Set(policy.extensionToolNames)
    else { throw RuntimeToolError.unavailable }
    // S1.12: every tool call and generation asks the bot's Computer for this conversation's
    // environment. Without a composed directory no hook exists and none resolves, as before.
    let instance = try await PiDurable.Harness.open(
      storage: thread.storage,
      options: PiDurable.HarnessOptions(
        models: modelRegistry, registry: registry,
        settings: PiDurable.HarnessSettings(retry: .init(enabled: false)),
        env: environmentHook(conversation: conversationID, bot: thread.botID),
        toolPolicy: policy.enginePolicy))
    var stop: (@Sendable () -> Void)?
    var events: PiDurable.AgentEventStream?
    var graph: PiDurable.CommittedWatch<PiDurable.TaskGraph>?
    do {
      let outcomes = thread.toolOutcomes
      stop = try await instance.session.subscribeCommits { publication, _ in
        outcomes.capture(publication)
      }
      // Deferred tools that tool_search already loaded stay offered across reactivation.
      let loaded = try await instance.conversation().agent().tools.filter(\.deferred).map(\.name)
      let tools = policy.enabledToolNames.map { PiCore.JSONString($0) }
      let modelTools = policy.modelToolNames.map { PiCore.JSONString($0) }
      let extensions =
        ["memoshi.text", PolicyHooks.name] + (session?.extensions.map(\.name) ?? [])
        + (subagents == nil ? [] : [RuntimeSubagents.name])
      try await instance.conversation().configure(
        PiDurable.AgentChange(
          extensions: .set(.names(extensions)), tools: .set(.names(tools)),
          modelTools: .set(.names(modelTools + loaded)), instructions: .clear, cwd: .clear))
      let watcher = try await instance.watchEvents()
      events = watcher
      let taskGraph = try await instance.watchTaskGraph()
      graph = taskGraph
      guard let stop else { throw RuntimeError.projectionFailed }
      thread.engine = RuntimeEngine(
        harness: instance, events: watcher, taskGraph: taskGraph, stopToolOutcomes: stop,
        tools: tools, modelTools: modelTools,
        dispatchRecordedTools: policy.dispatchRecordedToolNames, closing: closing)
      try await reconcileToolOutcomes(thread)
      try await reconcile(thread)
      try await reconcileSubagents(thread, graph: taskGraph.value)
      try await applyResumeDecisions(thread, graph: taskGraph.value)
      try await settleUndispatchedSteps(thread, graph: taskGraph.value)
      try taskGraph.start { [weak self] value, _, _ in
        guard let self else { return }
        do {
          try await self.receiveTaskGraph(value, conversationID: conversationID)
        } catch {
          await self.failThread(conversationID)
        }
      }
      try watcher.start { [weak self] batch, _ in
        guard let self else { return }
        do {
          try await self.receive(batch, conversationID: conversationID)
        } catch {
          await self.failThread(conversationID)
        }
      }
    } catch {
      await stopChildEvents(thread)
      if let events { _ = await events.stop() }
      if let graph { _ = await graph.stop() }
      stop?()
      thread.engine = nil
      try? await instance.close()
      thread.storageClosed = true
      throw error
    }
  }

  /// Connects the explicit extension composition once and shares it across conversations.
  /// A failure is kept: a development composition that cannot start never opens partially.
  func extensionSessionIfNeeded() async throws -> RuntimeExtensionSession? {
    guard !extensionComposition.isEmpty else { return nil }
    if let existing = extensionSession { return try await existing.value }
    let composition = extensionComposition
    let credentials = credentials
    let opening = Task {
      try await RuntimeExtensionSession.open(composition, credentials: credentials)
    }
    extensionSession = opening
    return try await opening.value
  }

  func nestedToolResult(
    _ thread: RuntimeThread, parent: PiDurable.TaskId, key: PiCore.JSONString
  ) async throws -> PiDurable.NestedCallState? {
    let address = PiDurable.DocumentAddress(
      kind: PiDurable.nestedCallDoc.definition.kind, scope: .task(parent), key: key)
    guard let record = try await thread.storage.findDocument(address, at: .current),
      let document = try await thread.storage.document(record.id, at: .current)
    else { return nil }
    guard document.version == PiDurable.nestedCallDoc.definition.version else {
      throw RuntimeError.projectionFailed
    }
    return try PiCore.JSONValue.object(document.value).decode(PiDurable.NestedCallState.self)
  }
}
