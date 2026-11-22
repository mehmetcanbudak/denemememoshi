import Chord
import CryptoKit
import Foundation
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable
import Synchronization

/// Safe, presentation-ready failures; provider response bodies never escape this module.
public enum RuntimeError: Error, Equatable, Sendable {
  case invalidParams
  case modelUnavailable
  case providerUnavailable
  case busy
  case notStarted
  case stopping
  case projectionFailed
  case recoveryRequired
}

/// The development text-chat seam. No Pi type, tool, environment or credential reaches a caller.
public actor RuntimeAdapter {
  let store: Store
  let modelRegistry: PiAI.ModelsRegistry
  let credentials: ProviderCredentials
  let toolDefinitions: [RuntimeToolDefinition]
  /// Development/qualification-only Code Mode and MCP tools; `.none` in the app and daemon.
  let extensionComposition: RuntimeExtensionComposition
  /// Connected once, on the first activation that needs it, and closed by close().
  var extensionSession: Task<RuntimeExtensionSession, any Error>?
  let publishLive: @Sendable (EventEnvelope) async throws -> Void
  /// Keyless loopback requests use PiAI's transport. A request carrying a model credential uses
  /// one that never follows a redirect, because its lease checked the first hop only.
  let providerFetch: PiAI.FetchFunction
  let keyedProviderFetch: PiAI.FetchFunction
  let sourceFolders: SourceFolderAuthority?
  /// Development/qualification-only conversation computers (S1.12); nil installs no `env`
  /// hook, so every call resolves no environment, as in the app and daemon.
  let environments: RuntimeEnvironments?
  /// Open conversation threads. A conversation opens on first use and closes after
  /// `idleThreadLimit` without a turn, queued input or pending approval.
  var threads: [ConversationID: RuntimeThread] = [:]
  /// The one in-flight open per conversation, which concurrent callers join.
  var openings: [ConversationID: Task<Void, any Error>] = [:]
  /// An idle close in flight; a caller that needs the conversation waits for it, then reopens.
  var threadClosings: [ConversationID: Task<Void, Never>] = [:]
  /// Single-flight Session retirement prevents another use from reopening its closing store.
  var lifecycleAdmissions: [ConversationID: LifecycleAdmission] = [:]
  var lifecycleMaintenanceFailed = false
  var admissions: [ULID: Admission] = [:]
  var started = false
  var closing = false
  var configuring = false
  var refreshingModels = false
  /// resume() ran: a conversation opened later resumes its scheduler as it opens.
  var schedulerResumed = false
  /// How long an open conversation may stay unused before it closes (S1.2: 10 minutes).
  let idleThreadLimit: Duration
  var idleSweeper: Task<Void, Never>?

  struct Admission: Sendable {
    let hash: String
    let task: Task<ChatsSendResult, any Error>
  }

  struct LifecycleAdmission: Sendable {
    let requestID: ULID
    let hash: String
    let task: Task<LifecycleReceipt, any Error>
  }

  /// Composes metadata, a per-use authenticated credential resolver and focused live events.
  /// Folder management exists only with trusted host source roots, never RPC or model input.
  /// `extensions` and `environments` are explicit development/qualification composition;
  /// production passes none.
  public init(
    store: Store, resolveCredential: RuntimeCredentialResolver? = nil,
    tools: [RuntimeToolDefinition] = [], extensions: RuntimeExtensionComposition = .none,
    environments: RuntimeEnvironmentComposition = .none,
    sourceContext: SourcePathPolicyContext? = nil,
    publishLive: @escaping @Sendable (EventEnvelope) async throws -> Void
  ) {
    self.init(
      store: store, resolveCredential: resolveCredential, tools: tools, extensions: extensions,
      environments: environments, sourceContext: sourceContext, routeProviderRequest: nil,
      publishLive: publishLive)
  }

  /// Tests alone pass `routeProviderRequest`: each provider request keeps its real fixed URL
  /// through the credential lease, header and origin checks, then only the transport delivers
  /// it to the routed URL, a controlled loopback provider. Production has no such seam.
  init(
    store: Store, resolveCredential: RuntimeCredentialResolver? = nil,
    tools: [RuntimeToolDefinition] = [], extensions: RuntimeExtensionComposition = .none,
    environments: RuntimeEnvironmentComposition = .none,
    sourceContext: SourcePathPolicyContext? = nil,
    routeProviderRequest: (@Sendable (URL) -> URL)?,
    idleThreadLimit: Duration = .seconds(600),
    publishLive: @escaping @Sendable (EventEnvelope) async throws -> Void
  ) {
    self.store = store
    self.toolDefinitions = tools
    self.extensionComposition = extensions
    self.environments = RuntimeEnvironments(environments)
    self.idleThreadLimit = idleThreadLimit
    self.publishLive = publishLive
    let credentials = ProviderCredentials(store: store, resolve: resolveCredential)
    self.credentials = credentials
    self.modelRegistry = PiAI.createModels(
      .init(credentials: credentials, authContext: PiAI.StaticAuthContext()))
    func routed(_ transport: @escaping PiAI.FetchFunction) -> PiAI.FetchFunction {
      guard let routeProviderRequest else { return transport }
      return { request, signal in
        var routed = request
        routed.url = routeProviderRequest(request.url)
        return try await transport(routed, signal)
      }
    }
    self.providerFetch = routed(PiAI.URLSessionFetch(configuration: .ephemeral).fetch)
    self.keyedProviderFetch = routed(RedirectRefusingFetch().fetch)
    self.sourceFolders = sourceContext.map { SourceFolderAuthority(store: store, context: $0) }
  }

  /// Opens actual Pi storage and its committed watcher without starting model generation or
  /// reaching any provider, so the daemon can listen at once. Only conversations with an
  /// unfinished turn or a recovery hold open here (S1.2); every other one opens on first use.
  public func start() async throws {
    guard !started, !closing else { throw RuntimeError.notStarted }
    let assistant = try await store.ensureAssistantChat(at: IDGenerator.nowMilliseconds())
    // The Assistant's Ask first policy exists before its Chat first opens.
    _ = try await store.ensureBotPolicy(assistant.botId, at: IDGenerator.nowMilliseconds())
    for provider in try await store.modelProviders().value {
      try installProvider(provider)
    }
    var opened: [RuntimeThread] = []
    do {
      // A purge that cannot finish yet is reported in status and retried by maintenance. Its
      // Sessions stay retired and unrestorable, so it never keeps other conversations closed.
      await maintainSessionTrash()
      for conversation in try await store.conversationsNeedingResume() {
        opened.append(try await openThread(conversation))
      }
    } catch {
      for thread in opened { try? await closeThread(thread, quiescing: false) }
      throw error
    }
    started = true
    startIdleSweeper()
  }

  /// Resumes existing text work once the authenticated daemon is ready to deliver frames. Before
  /// a thread first resumes, a configured provider whose model its unfinished turns selected but
  /// the registry lacks is discovered, bounded. If the model is still unknown, as for a keyed
  /// local provider before the app's Keychain host connects, the thread stays paused and counts
  /// in `RuntimeStatus.awaitingModels` instead of letting Pi fail the run as `no_model` before
  /// it keeps the partial; a later successful `modelsList()` resumes it. A conversation that
  /// opens afterwards resumes the same way as it opens.
  public func resume() async throws {
    try requireReady()
    schedulerResumed = true
    for thread in Array(threads.values) {
      try await resumeThread(thread)
    }
  }

  /// One thread's part of resume(). A recovery hold keeps it inspection-only.
  func resumeThread(_ thread: RuntimeThread) async throws {
    guard try await store.chatRecovery(thread.conversationID).value == nil else { return }
    if thread.engine == nil { try await activateThread(thread) }
    guard thread.engine != nil else { throw RuntimeError.projectionFailed }
    if !thread.resumed {
      let missing = try await missingModelProviders(thread)
      if !missing.isEmpty { await discoverModels(missing) }
    }
    try await resumeIfModelsKnown(thread)
  }

  /// Resumes threads that were paused for an unknown model once listing has discovered it.
  func resumeAwaitingModels() async throws {
    for thread in Array(threads.values) where thread.awaitingModels {
      try await resumeIfModelsKnown(thread)
    }
  }

  /// Resumes the thread's scheduler unless an unfinished turn still waits for an unknown model.
  /// Stop calls this again: a turn that was asked to stop no longer waits for its model.
  func resumeIfModelsKnown(_ thread: RuntimeThread) async throws {
    guard let engine = thread.engine else { return }
    try await reconcileTaskAborts(thread)
    if !thread.resumed {
      guard try await missingModelProviders(thread).isEmpty else {
        thread.awaitingModels = true
        return
      }
      thread.awaitingModels = false
      // Recorded before Pi continues them, so before any continued reply streams.
      try await recordResumedTurns(thread)
    }
    try await engine.harness.resume()
    thread.resumed = true
    try await reconcileParkedTurns(thread, graph: engine.taskGraph.value)
    try await drainQueuedInputs(thread)
  }

  /// Configured providers whose models this conversation's unfinished turns selected but the
  /// registry does not know. A turn whose Pi run was asked to stop needs no model: Pi's paused
  /// scheduler only marks the stop, so the thread must resume for the run to settle as stopped.
  /// A turn queued under a hold with no request or bot model records `default`. Once Pi has
  /// admitted it, the model its run uses is the one Pi holds for the conversation; while it
  /// is still queued Pi holds an earlier turn's model, which this input does not wait for.
  private func missingModelProviders(_ thread: RuntimeThread) async throws -> Set<String> {
    let configured = Set(try await store.modelProviders().value.map(\.id))
    var missing: Set<String> = []
    var originals = Set<MemoshiProtocol.TaskID>()
    for binding in try await store.runtimeSubagents(thread.conversationID) {
      if let task = try await store.task(binding.taskId).value,
        [.queued, .running, .waiting].contains(task.status)
      {
        originals.insert(binding.originalTaskId)
      }
    }
    var stopping: [SubmissionId] = []
    if let run = try await thread.engine?.harness.snapshot(
      PiDurable.liveDoc, owner: ConversationId.root.rawValue)?.run,
      let task = try await thread.storage.task(run.taskId),
      task.abortRequested, task.abortReason == nil
    {
      stopping = Array(run.inputs)
    }
    let agentModel = try await thread.engine?.harness.conversation().agent().model
    for turn in try await store.chatTurns(thread.conversationID).value {
      let stopped = turn.piSubmissionId.map { stopping.contains(SubmissionId($0)) } ?? false
      guard (!turn.isTerminal && !stopped) || originals.contains(turn.taskId) else { continue }
      var pieces = turn.model.ref.rawValue.split(separator: "/", maxSplits: 1).map(String.init)
      if turn.model.ref.rawValue == "default", turn.piSubmissionId != nil, let agentModel {
        pieces = [agentModel.provider.displayString, agentModel.modelId.displayString]
      }
      guard pieces.count == 2, configured.contains(pieces[0]),
        modelRegistry.getModel(PiCore.JSONString(pieces[0]), PiCore.JSONString(pieces[1])) == nil
      else { continue }
      missing.insert(pieces[0])
    }
    return missing
  }

  /// Bounded, so a stalled endpoint cannot hold resumption indefinitely.
  private func discoverModels(_ providers: Set<String>) async {
    let limit = PiCore.AbortController()
    let deadline = Task {
      try await Task.sleep(for: Self.resumeDiscoveryLimit)
      limit.abort()
    }
    defer { deadline.cancel() }
    _ = await modelRegistry.refresh(
      .init(
        allowNetwork: true, providers: providers.sorted().map { PiCore.JSONString($0) },
        signal: limit.signal))
  }

  static let resumeDiscoveryLimit = Duration.seconds(15)

  /// Actual process-local activity, not background scheduler or full-engine qualification.
  public func status() -> RuntimeStatus {
    RuntimeStatus(
      openThreads: threads.count,
      liveRuns: threads.values.reduce(0) {
        $0 + ($1.engine == nil ? 0 : ($1.activeRequest == nil ? 0 : 1) + $1.liveSubagents.count)
      },
      awaitingModels: threads.values.reduce(0) { $0 + ($1.awaitingModels ? 1 : 0) },
      lifecycleMaintenanceFailed: lifecycleMaintenanceFailed)
  }

  /// Closes every conversation and SQLite before releasing local ownership. It stops no work
  /// (D139): Pi's close writes what still runs back as pending, and the next start continues
  /// it. No force-kill is used.
  public func close() async throws {
    guard !closing else { return }
    closing = true
    idleSweeper?.cancel()
    idleSweeper = nil
    var failure: (any Error)?
    // A send that is refused or fails while stopping is that caller's result, not a teardown
    // failure.
    for admission in admissions.values { _ = await admission.task.result }
    // Opens and idle closes already in flight finish first; nothing new starts while closing.
    for opening in Array(openings.values) { _ = await opening.result }
    for closing in Array(threadClosings.values) { await closing.value }
    for admission in Array(lifecycleAdmissions.values) { _ = await admission.task.result }
    for thread in Array(threads.values) {
      do { try await closeThread(thread, quiescing: true) } catch { failure = failure ?? error }
    }
    threads.removeAll()
    // No Harness can resolve an environment now; daemons end by EOF, then gateway clients.
    await environments?.closeAll()
    // Every Harness that could run a script or reach a server is closed by now.
    if let session = extensionSession {
      extensionSession = nil
      await (try? session.value)?.close()
    }
    started = false
    if let failure { throw failure }
  }

  /// Lists persisted application Chats with their metadata watermark.
  public func listChats() async throws -> ChatsListResult {
    try requireReady()
    let snapshot = try await store.chats()
    return ChatsListResult(items: snapshot.value, asOf: snapshot.asOf)
  }

  /// Reads explicit provider configuration without exposing credentials.
  public func providers() async throws -> ModelsProvidersListResult {
    try requireReady()
    let snapshot = try await store.modelProviders()
    return ModelsProvidersListResult(items: snapshot.value, asOf: snapshot.asOf)
  }

  /// Configures explicit providers and opaque key references; values never enter settings.
  public func configure(_ params: ModelsProvidersConfigureParams) async throws
    -> ModelsProvidersConfigureResult
  {
    try requireReady()
    guard !configuring, !refreshingModels, admissions.isEmpty,
      threads.values.allSatisfy({ $0.activeRequest == nil })
    else { throw RuntimeError.busy }
    let definition = try Self.validateProvider(
      id: params.providerId, baseURL: params.baseUrl, secretRef: params.secretRef)
    configuring = true
    defer { configuring = false }
    let result = try await store.configureProvider(
      params, name: definition.name, paramsHash: Self.paramsHash(params),
      at: IDGenerator.nowMilliseconds())
    // A retried old configure returns its original receipt without reverting a newer setting.
    if let current = try await store.modelProviders().value.first(where: {
      $0.id == params.providerId
    }) {
      try installProvider(current)
    }
    return result
  }

  /// Discovers only explicit providers; one failed key does not silently select a different model.
  public func modelsList() async throws -> ModelsListResult {
    try requireReady()
    guard !configuring, !refreshingModels else { throw RuntimeError.busy }
    refreshingModels = true
    defer { refreshingModels = false }
    let configured = try await store.modelProviders().value
    guard !configured.isEmpty else { return ModelsListResult(items: []) }
    let refreshed = await modelRegistry.refresh(
      .init(allowNetwork: true, providers: configured.map { PiCore.JSONString($0.id) }))
    guard !refreshed.aborted else { throw RuntimeError.providerUnavailable }
    var items: [AvailableModel] = []
    var unavailable: [String] = []
    for provider in configured {
      let id = PiCore.JSONString(provider.id)
      guard let definition = ModelProviderDefinition.named(provider.id),
        refreshed.errors[id] == nil
      else {
        unavailable.append(provider.id)
        continue
      }
      let models: [PiAI.Model]
      switch definition.endpoint {
      case .loopback:
        models = modelRegistry.getModels(id)
      case .fixed:
        // A fixed API's catalog is offered only once the app actually releases its key.
        do {
          models = try await modelRegistry.getAvailable(id)
          guard !models.isEmpty else {
            unavailable.append(provider.id)
            continue
          }
        } catch {
          try Task.checkCancellation()
          unavailable.append(provider.id)
          continue
        }
      }
      for model in models {
        items.append(
          AvailableModel(
            ref: MemoshiProtocol.ModelRef(
              ref: try ModelName(provider.id + "/" + model.id.displayString)),
            name: model.name.displayString, contextWindow: model.contextWindow,
            maxTokens: model.maxTokens))
      }
    }
    try await resumeAwaitingModels()
    return ModelsListResult(
      items: items, unavailableProviders: unavailable.isEmpty ? nil : unavailable)
  }

  /// Sends are single-flight by the original client key, including while RPC callers disconnect.
  public func send(_ params: ChatsSendParams) async throws -> ChatsSendResult {
    try requireReady()
    let hash = try Self.paramsHash(params)
    if let current = admissions[params.requestId] {
      guard current.hash == hash else { throw StoreError.requestConflict }
      var result = try await current.task.value
      result.replayed = true
      return result
    }
    // The conversation opens inside the single-flight admission, once per original key.
    let task = Task {
      try await self.withThread(params.chatId) { adapter, thread in
        try await adapter.admit(params, hash: hash, thread: thread)
      }
    }
    admissions[params.requestId] = Admission(hash: hash, task: task)
    let result: ChatsSendResult
    do {
      defer { admissions.removeValue(forKey: params.requestId) }
      result = try await task.value
    }
    if let thread = threads[params.chatId] { try await drainQueuedInputs(thread) }
    return result
  }

  /// Aborts the originally captured submission/task; replaying an old Stop cannot stop a new turn.
  public func abort(_ params: ChatsAbortParams) async throws -> EmptyParams {
    try requireReady()
    guard params.includeBackground != true else { throw RuntimeError.invalidParams }
    return try await withThread(params.chatId) { adapter, thread in
      try await adapter.abort(params, thread: thread)
    }
  }

  private func abort(_ params: ChatsAbortParams, thread: RuntimeThread) async throws
    -> EmptyParams
  {
    let operation = try await store.prepareChatAbort(
      params, paramsHash: Self.paramsHash(params), fence: thread.ownership.fence,
      at: IDGenerator.nowMilliseconds())
    guard let request = operation.targetRequestID,
      let turn = try await store.chatTurn(request), !turn.isTerminal
    else { return EmptyParams() }
    guard try await store.chatRecovery(params.chatId).value == nil, thread.engine != nil
    else {
      throw RuntimeError.recoveryRequired
    }
    // The captured turn stops as its task does, including one Pi has not admitted yet. The
    // Stop is recorded first, so a kill before Pi's abort ends the work still finds it.
    try await store.recordStop(
      turn.taskId, fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
    try await abortStoredTask(turn.taskId, thread: thread)
    if thread.awaitingModels { try await resumeIfModelsKnown(thread) }
    return EmptyParams()
  }

  /// Resolves immutable Pi entries for a bounded metadata-index page.
  public func history(_ params: ChatsHistoryParams) async throws -> ChatsHistoryResult {
    try requireReady()
    return try await withThread(params.chatId) { adapter, thread in
      try await adapter.history(params, thread: thread)
    }
  }

  private func history(_ params: ChatsHistoryParams, thread: RuntimeThread) async throws
    -> ChatsHistoryResult
  {
    guard !thread.failed else { throw RuntimeError.projectionFailed }
    let page = try await store.chatMessagePage(params)
    var messages: [ChatMessage] = []
    messages.reserveCapacity(page.items.count)
    for index in page.items {
      guard let entryID = index.piEntryId,
        let entry = try await thread.storage.entry(conversationId: .root, EntryId(entryID))?.entry,
        let message = entry.model?.first
      else { throw RuntimeError.projectionFailed }
      messages.append(
        ChatMessage(
          id: index.id, conversationId: index.conversationId,
          taskId: index.taskId, role: index.role, content: Self.content(message),
          createdAt: index.createdAt, requestId: index.requestId, stopReason: index.stopReason,
          resumedAfterInterruption: index.resumedAfterInterruption))
    }
    var live: ChatLiveState?
    if page.recovery == nil, let engine = thread.engine,
      let state = try await engine.harness.snapshot(
        PiDurable.liveDoc, owner: ConversationId.root.rawValue), let run = state.run,
      let turn = try await store.chatTurns(params.chatId, activeOnly: true).value.first,
      let submissionID = turn.piSubmissionId, run.inputs.contains(SubmissionId(submissionID))
    {
      let message = try state.generation?.message.map { partial in
        // Pi timestamps are Numbers now; this host's clock only writes whole milliseconds.
        guard let createdAt = Int64(exactly: partial.timestamp) else {
          throw RuntimeError.projectionFailed
        }
        return ChatMessage(
          id: turn.assistantMessageId,
          conversationId: thread.ownership.fence.conversationID, taskId: turn.taskId,
          role: .bot, content: Self.content(.assistant(partial)), createdAt: createdAt,
          resumedAfterInterruption: turn.resumedAfterInterruption)
      }
      live = ChatLiveState(
        taskId: turn.taskId, message: message,
        resumedAfterInterruption: turn.resumedAfterInterruption)
    }
    return ChatsHistoryResult(
      items: messages, live: live, nextBefore: page.nextBefore, asOf: page.asOf,
      recovery: page.recovery, queued: page.queued.isEmpty ? nil : page.queued)
  }

  func requireReady() throws {
    guard !closing else { throw RuntimeError.stopping }
    guard started else { throw RuntimeError.notStarted }
  }

  static func paramsHash<Value: Encodable>(_ params: Value) throws -> String {
    let value = try MemoshiProtocol.JSONValue.parse(ProtocolCoding.makeEncoder().encode(params))
    let digest = SHA256.hash(data: Data(value.canonicalText.utf8))
    let digits: StaticString = "0123456789abcdef"
    return digits.withUTF8Buffer { alphabet in
      String(unsafeUninitializedCapacity: 64) { output in
        for (index, byte) in digest.enumerated() {
          output[index * 2] = alphabet[Int(byte >> 4)]
          output[index * 2 + 1] = alphabet[Int(byte & 15)]
        }
        return 64
      }
    }
  }

  static func validateEndpoint(_ value: String) throws {
    guard let url = URLComponents(string: value),
      url.scheme == "http" || url.scheme == "https",
      ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host?.lowercased() ?? ""),
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      url.url != nil
    else { throw RuntimeError.invalidParams }
  }

  /// Admits only a provider in the table, at its loopback or fixed endpoint, with a reference of
  /// a kind it accepts. A fixed cloud API never runs keyless.
  @discardableResult
  static func validateProvider(id: String, baseURL: String, secretRef: String?) throws
    -> ModelProviderDefinition
  {
    guard let definition = ModelProviderDefinition.named(id) else {
      throw RuntimeError.invalidParams
    }
    if let secretRef {
      guard let reference = ModelCredentialReference(rawValue: secretRef),
        reference.kind != .chatGPT || definition.acceptsChatGPT
      else { throw RuntimeError.invalidParams }
    }
    switch definition.endpoint {
    case .loopback:
      try validateEndpoint(baseURL)
    case .fixed(let fixed):
      guard baseURL == fixed, secretRef != nil else { throw RuntimeError.invalidParams }
    }
    return definition
  }

  func installProvider(_ configuration: ModelProviderConfiguration) throws {
    let definition = try Self.validateProvider(
      id: configuration.id, baseURL: configuration.baseUrl, secretRef: configuration.secretRef)
    let fetch = configuration.secretRef == nil ? providerFetch : keyedProviderFetch
    let credentials = self.credentials
    let protectedFetch: PiAI.FetchFunction = { request, signal in
      try await credentials.fetch(
        request, signal: signal, provider: configuration, definition: definition, using: fetch)
    }
    var provider = try definition.makeProvider(configuration, protectedFetch)
    // Only the declared wire API is listed, admitted or resolved, so every request carries the
    // key in the header the lease accepts; other catalog models do not exist for Memoshi.
    let api = definition.api
    let chatModels = provider.getModels
    provider.getModels = { try chatModels().filter { $0.api == api } }
    let allModels = provider.getAllModels
    provider.getAllModels = {
      try (allModels?() ?? chatModels().map(PiAI.AnyModel.chat)).filter {
        $0.chatModel?.api == api
      }
    }
    if configuration.secretRef != nil {
      let stream = provider.stream
      provider.stream = { model, context, options in
        sanitizingProviderEvents(stream(model, context, options))
      }
      let simple = provider.streamSimple
      provider.streamSimple = { model, context, options in
        sanitizingProviderEvents(simple(model, context, options))
      }
    }
    modelRegistry.setProvider(provider)
  }
}

/// Mutable view state is confined to RuntimeAdapter, never passed to the callback task.
final class RuntimeThread {
  /// The conversation as it was opened: a Chat or a Session and its (lead) bot.
  let conversation: ChatSummary
  let ownership: MemoshiStore.ConversationOwnership
  let storage: PiDurable.SqliteStorage
  var engine: RuntimeEngine?
  /// The one in-flight Harness activation that concurrent callers and close() join.
  var activation: Task<Void, any Error>?
  let toolOutcomes = CommittedToolOutcomes()
  var activeRequest: ULID?
  var liveSubagents: Set<MemoshiProtocol.TaskID> = []
  /// Hydrated once; graph frames add newly created task-owned scopes thereafter.
  var piChildren: Set<PiDurable.ConversationId>?
  var childEvents: [PiDurable.ConversationId: PiDurable.AgentEventStream] = [:]
  var childEventOpenings: Set<PiDurable.ConversationId> = []
  var childProgressAt: [PiDurable.ConversationId: ContinuousClock.Instant] = [:]
  var childProgressJobs: [PiDurable.ConversationId: Task<Void, Never>] = [:]
  /// Interrupted-step decision waits this runtime already answered or held.
  var accountedSteps: Set<PiDurable.TaskId> = []
  /// Interrupted-step decision waits this runtime answered with the user's Resume choice.
  var answeredWaits: Set<PiDurable.TaskId> = []
  var queueAdmission: Task<ChatsSendResult, any Error>?
  var text = ""
  var textUTF16Count: Int64 = 0
  var failed = false
  /// The Harness scheduler was resumed in this process.
  var resumed = false
  /// Admitted turns whose Pi submission had not settled when this Harness opened: a restart or
  /// a closed Harness cut them off, and Pi continues them once its scheduler first resumes.
  var interruptedTurns: [ULID] = []
  /// Live subagent tasks that were running when this Harness opened, so `recordResumedTurns`
  /// emits `task.resumed { by: system }` when Pi continues them.
  var interruptedSubagents: [MemoshiProtocol.TaskID] = []
  /// Turns whose Pi run hit `restartLimit` and was parked; aborted so Pi frees the conversation
  /// and projected as `.failed` (`restart_limit`) rather than user-canceled.
  var parkedRequests: Set<ULID> = []
  /// Unfinished work waits, paused, for a model the registry does not know yet.
  var awaitingModels = false
  /// A failed activation closed `storage` with its Harness: no call can read this thread again.
  var storageClosed = false
  /// Calls currently using this thread; an idle close never closes a thread in use.
  var users = 0
  /// The latest call or Pi event, which the idle close measures from.
  var lastUsed = ContinuousClock.now

  /// The conversation's Pi store and its one writer's identity.
  var conversationID: ConversationID { conversation.id }
  /// The bot whose identity, persona, job, model and effort every request renders.
  var botID: BotID { conversation.botId }

  init(
    conversation: ChatSummary, ownership: MemoshiStore.ConversationOwnership,
    storage: PiDurable.SqliteStorage
  ) {
    self.conversation = conversation
    self.ownership = ownership
    self.storage = storage
  }
}

/// Every scheduler-owned resource has one lifecycle. Inspection-only threads have none.
struct RuntimeEngine {
  let harness: PiDurable.Harness
  let events: PiDurable.AgentEventStream
  let taskGraph: PiDurable.CommittedWatch<PiDurable.TaskGraph>
  let stopToolOutcomes: @Sendable () -> Void
  /// The conversation's offered tools and the subset its model sees, applied again with the
  /// model and effort before every submission.
  let tools: [PiCore.JSONString]
  let modelTools: [PiCore.JSONString]
  /// `PolicyHooks.dispatchRecordedToolNames` of this Harness's composition.
  let dispatchRecordedTools: Set<String>
  /// Shared with this Harness's `PolicyHooks`; set just before the Harness closes.
  let closing: HarnessClosing
}

/// Whether the runtime has begun closing one conversation's Harness. A decision wait that the
/// close ends, a foreground child's included, keeps its approval pending for the next open: Pi
/// writes the waiting tool task back as `pending`, and its rerun `beforeTool` finds the same
/// approval by its memo (policy.md §10.1). Only the user's Stop, the kill switch, a revoked
/// grant or its expiry ends a pending decision.
final class HarnessClosing: Sendable {
  private let state = Mutex(false)
  var began: Bool { state.withLock { $0 } }
  func begin() { state.withLock { $0 = true } }
}
