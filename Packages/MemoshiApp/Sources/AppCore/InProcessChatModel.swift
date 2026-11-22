import Foundation
import MemoshiProtocol
import Observation

/// One ordered engine subscription: durable facts after `head` in sequence order, and this
/// device's live UI frames, each delivered after the durable fact its `after` names.
public struct EngineEventFeed: Sendable {
  /// Snapshots read after subscribing cover every durable fact through this sequence number.
  public let head: Int64
  /// Ends normally when the engine closes; fails when the consumer fell too far behind.
  public let events: AsyncThrowingStream<EventEnvelope, any Error>

  /// Wraps an engine's subscription.
  public init(head: Int64, events: AsyncThrowingStream<EventEnvelope, any Error>) {
    self.head = head
    self.events = events
  }
}

/// What the iPhone and iPad host hands the projection: its in-process engine's typed API (D78)
/// and an ordered event subscription.
public struct InProcessEngineConnection: Sendable {
  /// The engine's typed API.
  public let api: any MemoshiAPI
  /// Opens a new ordered subscription; called again after a failed one.
  public let subscribe: @Sendable () async throws -> EngineEventFeed

  /// Composes the connection; the engine and its lifetime stay with the host.
  public init(
    api: any MemoshiAPI, subscribe: @escaping @Sendable () async throws -> EngineEventFeed
  ) {
    self.api = api
    self.subscribe = subscribe
  }
}

/// A user-started turn's observable activity, for the host's continued-processing progress.
/// Keyed by the send's original request ID, which exists before the engine admits the turn.
public enum TurnActivity: Equatable, Sendable {
  /// The user pressed Send; nothing is admitted yet.
  case began(ULID)
  /// The turn's live reply has reached this many UTF-16 code units.
  case progressed(ULID, utf16Count: Int)
  /// The turn waits for the person's approval. It is not stalled: no reply text arrives until
  /// they answer, so a host may give up its background time meanwhile.
  case waitingForApproval(ULID)
  /// The turn runs again after waiting for approval.
  case resumed(ULID)
  /// The turn reached a terminal status, the send was refused, or its delivery is uncertain.
  case ended(ULID, succeeded: Bool)
}

/// The iPhone and iPad Assistant Chat over the in-process engine: authoritative history pages,
/// live text frames, Stop, explicit local model settings and the shared approval projection.
/// Finished transcript text is never persisted in UI preferences.
@MainActor
@Observable
public final class InProcessChatModel {
  /// The shared approval projection for this engine.
  public let reviews: LiveApprovalModel
  /// The Assistant's Chat, once listed.
  public private(set) var chat: ChatSummary?
  /// Loaded committed messages, oldest first.
  public private(set) var messages: [ChatMessage] = []
  /// The in-flight turn and its partial reply.
  public private(set) var live: ChatLiveState?
  /// A whole-Chat recovery hold, if any.
  public private(set) var recovery: ChatRecoveryHold?
  /// Accepted inputs waiting behind a recovery hold.
  public private(set) var queued: [QueuedChatMessage] = []
  /// What each held step's Resume card offers now, by card (D51).
  public private(set) var resumeChoices: [CardID: [ResumeAction]] = [:]
  /// Resume cards whose answer is on its way to the engine. An answer stays here until its call
  /// returns, also after `detach`, so the same card is never answered twice at once.
  public private(set) var answeringResume: Set<CardID> = []
  /// The latest turn's task snapshot.
  public private(set) var task: MemoshiTask?
  /// Whether an event subscription is open. The snapshots it bootstraps from may still be
  /// loading.
  public private(set) var isConnected = false
  /// Whether an older history page is loading.
  public private(set) var isLoadingOlder = false
  /// Whether a Send awaits admission.
  public private(set) var isSending = false
  /// Whether a Stop is in flight.
  public private(set) var isStopping = false
  /// The cursor for the next older history page.
  public private(set) var nextBefore: MessageID?
  /// A problem to show beside the composer.
  public private(set) var problem: String?
  /// Whether a saved Send awaits its receipt.
  public private(set) var hasUnconfirmedSend = false
  /// Why sending is blocked when the saved Send could not be read; nil when there is no such
  /// record. It is separate from `problem`, so no later failure can replace it, and it stays
  /// until the person discards the record.
  public private(set) var unreadableSendExplanation: String?
  /// Why the engine definitely refused the saved Send on its latest attempt, in the engine's
  /// own words; nil when there is no such refusal. The request stays saved and Retry is
  /// unchanged; the person may discard it instead. It is saved with the request, so a relaunch
  /// still offers the discard.
  public private(set) var refusedSendReason: String? {
    didSet { savedSend.recordRefusal(refusedSendReason) }
  }
  /// Explicitly configured providers, without credentials.
  public private(set) var providers: [ModelProviderConfiguration] = []
  /// Models the configured providers actually listed.
  public private(set) var models: [AvailableModel] = []
  /// Whether a provider configuration is in flight.
  public private(set) var isConfiguring = false
  /// Whether model discovery is in flight.
  public private(set) var isLoadingModels = false
  /// A provider or discovery problem to show in model settings.
  public private(set) var modelProblem: String?
  /// The provider-qualified model the next Send names, saved as a UI preference.
  public var selectedModel: String {
    didSet { defaults.set(selectedModel, forKey: Keys.model) }
  }
  /// Unsent composer text, saved as a UI preference.
  public var draft: String {
    didSet { defaults.set(draft, forKey: Keys.draft) }
  }
  /// Receives the active turn's activity on the main actor.
  @ObservationIgnored public var onTurnActivity: (@MainActor (TurnActivity) -> Void)?

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let makeRequestID: @Sendable () throws -> ULID
  @ObservationIgnored private let savedSend: SavedSend
  @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
  @ObservationIgnored private var connection: InProcessEngineConnection?
  @ObservationIgnored private var eventTask: Task<Void, Never>?
  @ObservationIgnored private var sendTask: Task<Void, Never>?
  @ObservationIgnored private var stopTask: Task<Void, Never>?
  @ObservationIgnored private var olderTask: Task<Void, Never>?
  @ObservationIgnored private var modelTask: Task<Void, Never>?
  /// Settings work an earlier attachment started, which `detach` cancelled. Its call can still
  /// run in its engine, which may be the one attached now, and an engine refuses a listing as
  /// busy while a configuration runs.
  @ObservationIgnored private var detachedModelWork: Task<Void, Never>?
  @ObservationIgnored private var modelWork = 0
  @ObservationIgnored private var modelListing = 0
  @ObservationIgnored private var pending: ChatsSendParams?
  @ObservationIgnored private var stopIntent: ChatsAbortParams?
  /// An answer whose delivery is uncertain keeps its request ID, so a retry is the same answer.
  @ObservationIgnored private var resumeIntents: [CardID: CardsRespondParams] = [:]
  @ObservationIgnored private var resumeTasks: [CardID: Task<Void, Never>] = [:]
  @ObservationIgnored private var activeTurn:
    (requestId: ULID, taskId: TaskID?, awaitsApproval: Bool)?
  @ObservationIgnored private var backgroundCancellations: Set<ULID> = []
  @ObservationIgnored private var historyAsOf: Int64 = 0
  @ObservationIgnored private var taskAsOf: Int64 = 0
  @ObservationIgnored private var providersAsOf: Int64 = 0
  @ObservationIgnored private var historyRequest = 0
  @ObservationIgnored private var appliedHistoryRequest = 0
  /// Whether the open subscription's bootstrap snapshots have loaded.
  private var isSnapshotLoaded = false

  private enum Keys {
    static let draft = "text-chat.draft"
    static let model = "text-chat.model"
  }

  /// Restores the draft, the model choice and any unconfirmed Send from UI preferences.
  /// `makeRequestID` is the host's canonical ULID generator for every new request this model
  /// and its approval projection send; retries reuse saved keys. `sleep` waits one delay before
  /// a failed subscription is opened again, and throws when the wait is cancelled.
  public init(
    defaults: UserDefaults = .standard, makeRequestID: @escaping @Sendable () throws -> ULID,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.defaults = defaults
    self.savedSend = SavedSend(defaults: defaults)
    self.makeRequestID = makeRequestID
    self.sleep = sleep
    self.reviews = LiveApprovalModel(defaults: defaults, makeRequestID: makeRequestID)
    self.draft = defaults.string(forKey: Keys.draft) ?? ""
    self.selectedModel = defaults.string(forKey: Keys.model) ?? ""
    switch savedSend.load() {
    case .readable(let request, let refusal):
      pending = request
      hasUnconfirmedSend = true
      refusedSendReason = refusal
    case .unreadable:
      hasUnconfirmedSend = true
      unreadableSendExplanation = String(
        localized:
          "The saved delivery record could not be read. Sending is blocked to avoid duplicating an uncertain message.",
        bundle: #bundle
      )
    case nil:
      break
    }
  }

  /// Whether the Chat's current turn is still queued, running or waiting.
  public var isWorking: Bool {
    recovery == nil
      && (live != nil || task.map { [.queued, .running, .waiting].contains($0.status) } == true)
  }

  /// Whether Send may submit the draft now.
  public var canSend: Bool {
    isConnected && chat != nil && selectedModelRef != nil
      && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !isWorking && !isSending && !isConfiguring && !hasUnreadableSend && !hasUnconfirmedSend
  }

  /// Whether the saved Send could not be read. Sending stays blocked until the person discards
  /// the record.
  public var hasUnreadableSend: Bool { unreadableSendExplanation != nil }

  /// Whether the person may discard the unreadable saved Send. Offered only while this Chat's
  /// current snapshot is loaded, so it can be checked.
  public var canDiscardUnreadableSend: Bool {
    hasUnreadableSend && isSnapshotLoaded && chat != nil
  }

  /// Whether the saved Send may be retried with its original request ID.
  public var canRetrySend: Bool {
    isConnected && pending != nil && !isSending && !hasUnreadableSend
  }

  /// Whether the person may discard the saved Send the engine refused.
  public var canDiscardRefusedSend: Bool {
    refusedSendReason != nil && pending != nil && !isSending
  }

  /// Whether Stop may cancel the current turn now.
  public var canStop: Bool {
    recovery == nil && isConnected && chat != nil && isWorking && !isStopping
  }

  private var selectedModelRef: ModelRef? {
    models.first { $0.ref.ref.rawValue == selectedModel }?.ref
  }

  /// Starts the one event consumer for this engine. Replaces an earlier attachment.
  public func attach(_ connection: InProcessEngineConnection) {
    detach()
    self.connection = connection
    // Another engine's sequence numbers do not order this one's snapshots.
    historyAsOf = 0
    taskAsOf = 0
    providersAsOf = 0
    // Nor are its providers and models this engine's. Its settings work, cancelled by
    // `detach`, may still return; it writes nothing and leaves this engine's first listing,
    // which the bootstrap starts, unblocked.
    modelWork += 1
    modelListing += 1
    providers = []
    models = []
    modelProblem = nil
    isConfiguring = false
    isLoadingModels = false
    reviews.attach(connection.api)
    // The consumer holds the model until `detach` cancels it or the feed ends.
    eventTask = Task { await self.run(connection) }
  }

  /// Stops consuming events and every in-flight request this model started.
  public func detach() {
    eventTask?.cancel()
    sendTask?.cancel()
    stopTask?.cancel()
    olderTask?.cancel()
    modelTask?.cancel()
    if let modelTask {
      let earlier = detachedModelWork
      detachedModelWork = Task {
        await earlier?.value
        await modelTask.value
      }
    }
    for answer in resumeTasks.values { answer.cancel() }
    eventTask = nil
    sendTask = nil
    stopTask = nil
    olderTask = nil
    modelTask = nil
    resumeTasks.removeAll()
    connection = nil
    reviews.stop()
    setConnected(false)
  }

  /// Saves the draft as a request with a new ID, then submits it once.
  public func send() {
    guard canSend, let chat, let model = selectedModelRef, let connection else { return }
    do {
      let params = ChatsSendParams(
        requestId: try makeRequestID(), chatId: chat.id,
        content: [.text(TextPart(text: draft))], whenBusy: .reject, model: model, surface: .ui)
      try persistPending(params)
      performSend(params, connection: connection)
    } catch { problem = Self.message(error) }
  }

  /// Resends the saved request unchanged; the engine returns its original receipt if it exists.
  public func retrySend() {
    guard canRetrySend, let pending, let connection else { return }
    performSend(pending, connection: connection)
  }

  /// Discards a saved Send that could not be read, so sending can resume. Only the person may
  /// choose this: the earlier message may or may not have been delivered, and nothing is resent.
  public func discardUnreadableSend() {
    guard canDiscardUnreadableSend else { return }
    savedSend.remove()
    unreadableSendExplanation = nil
    hasUnconfirmedSend = false
  }

  /// Discards the saved Send the engine definitely refused, so sending can resume. Only the
  /// person may choose this. It removes that saved request alone: the draft stays and nothing
  /// is sent.
  public func discardRefusedSend() {
    guard canDiscardRefusedSend else { return }
    clearRefusedPending()
  }

  /// Stops the Chat's current turn. A retried Stop keeps its original request ID.
  public func stop() {
    guard canStop, let chat, let connection else { return }
    sendStop(chat: chat, connection: connection)
  }

  private func sendStop(chat: ChatSummary, connection: InProcessEngineConnection) {
    do {
      let params =
        try stopIntent
        ?? ChatsAbortParams(requestId: makeRequestID(), chatId: chat.id)
      stopIntent = params
      isStopping = true
      problem = nil
      stopTask = Task { [weak self] in
        guard let self else { return }
        defer {
          self.isStopping = false
          self.stopTask = nil
        }
        do {
          _ = try await connection.api.call(ChatsAbort.self, params)
          self.stopIntent = nil
          try await self.reloadHistory(connection.api, replacing: false)
        } catch {
          if !Task.isCancelled { self.problem = Self.message(error) }
        }
      }
    } catch { problem = Self.message(error) }
  }

  /// Answers a held step's Resume card with Run again, Skip or Mark as done (D51). The engine
  /// settles the step and the Chat continues; a retried answer keeps its original request ID.
  public func answerResume(_ card: CardID, _ action: ResumeAction) {
    guard isConnected, let connection, !answeringResume.contains(card),
      resumeChoices[card]?.contains(action) == true
    else { return }
    do {
      let params: CardsRespondParams
      if let earlier = resumeIntents[card], earlier.action == action.rawValue {
        params = earlier
      } else {
        params = CardsRespondParams(
          requestId: try makeRequestID(), cardId: card, action: action.rawValue, surface: .ui)
      }
      resumeIntents[card] = params
      answeringResume.insert(card)
      problem = nil
      resumeTasks[card] = Task { [weak self] in
        guard let self else { return }
        defer {
          self.answeringResume.remove(card)
          self.resumeTasks.removeValue(forKey: card)
        }
        do {
          _ = try await connection.api.call(CardsRespond.self, params)
          self.resumeIntents.removeValue(forKey: card)
          // After `detach`, the Chat on screen may be another engine's.
          try Task.checkCancellation()
          try await self.reloadHistory(connection.api, replacing: false)
        } catch {
          if !Task.isCancelled { self.problem = Self.message(error) }
        }
      }
    } catch { problem = Self.message(error) }
  }

  /// The background scheduler expired or the person canceled its Live Activity. Only the
  /// matching user-started turn is stopped; a late callback never stops a later turn.
  public func stopBackgroundTurn(_ request: ULID) {
    guard activeTurn?.requestId == request else { return }
    backgroundCancellations.insert(request)
    if canStop { stop() }
  }

  /// Loads the next older history page before the oldest loaded message.
  public func loadOlder() {
    guard let connection, let chat, let before = nextBefore, !isLoadingOlder else { return }
    isLoadingOlder = true
    olderTask = Task { [weak self] in
      guard let self else { return }
      defer {
        self.isLoadingOlder = false
        self.olderTask = nil
      }
      do {
        let page = try await connection.api.call(
          ChatsHistory.self, .init(chatId: chat.id, before: before))
        try Task.checkCancellation()
        let existing = Set(self.messages.map(\.id))
        self.messages.insert(contentsOf: page.items.filter { !existing.contains($0.id) }, at: 0)
        self.nextBefore = page.nextBefore
      } catch {
        if !Task.isCancelled { self.problem = Self.message(error) }
      }
    }
  }

  /// Saves an explicit keyless loopback endpoint as the local provider, then lists its models.
  /// The engine validates the endpoint; nothing here substitutes another provider.
  public func configureLocalEndpoint(_ baseURL: String) {
    guard let connection, !isConfiguring, !isWorking else { return }
    isConfiguring = true
    modelProblem = nil
    // A listing in flight is cancelled and awaited first: the engine refuses a configuration
    // while one runs, and a superseded listing must not write over this one's result.
    let superseded = modelTask
    superseded?.cancel()
    modelWork += 1
    let work = modelWork
    modelTask = Task { [weak self] in
      await superseded?.value
      guard let self else { return }
      defer {
        if self.modelWork == work {
          self.isConfiguring = false
          self.modelTask = nil
        }
      }
      do {
        try Task.checkCancellation()
        let params = ModelsProvidersConfigureParams(
          requestId: try self.makeRequestID(), providerId: "local",
          baseUrl: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let configured = try await connection.api.call(ModelsProvidersConfigure.self, params)
        try await self.reloadProviders(connection.api, minimumSeq: configured.writtenSeq)
        try await self.loadModels(connection.api)
      } catch {
        if !Task.isCancelled { self.modelProblem = Self.message(error) }
      }
    }
  }

  /// Lists the configured providers' models again.
  public func refreshModels() {
    guard let connection, !isConfiguring, modelTask == nil else { return }
    modelWork += 1
    let work = modelWork
    modelTask = Task { [weak self] in
      guard let self else { return }
      // A superseded listing must not drop its successor's handle.
      defer { if self.modelWork == work { self.modelTask = nil } }
      do { try await self.loadModels(connection.api) } catch {
        if !Task.isCancelled { self.modelProblem = Self.message(error) }
      }
    }
  }

  /// The message's displayed text: its text parts in order.
  public static func text(_ message: ChatMessage) -> String {
    message.content.reduce(into: "") { result, part in
      if case .text(let text) = part { result.append(text.text) }
    }
  }

  // MARK: - Event consumer

  /// Subscribes, bootstraps from snapshots that cover the subscription head, then applies
  /// every fact in order. A failed subscription is replaced with a fresh bootstrap for as long
  /// as the model stays attached, after a wait 250 ms longer for each consecutive failure, at
  /// most 5 s; `detach` cancels the wait.
  private func run(_ connection: InProcessEngineConnection) async {
    var failures = 0
    while !Task.isCancelled {
      do {
        let feed = try await connection.subscribe()
        try Task.checkCancellation()
        setConnected(true)
        try await bootstrap(connection.api, head: feed.head)
        failures = 0
        for try await envelope in feed.events {
          try await apply(envelope, api: connection.api)
        }
        break
      } catch is CancellationError {
        break
      } catch {
        if Task.isCancelled { break }
        setConnected(false)
        problem = Self.message(error)
        failures += 1
        do { try await sleep(.milliseconds(250 * min(failures, 20))) } catch { break }
      }
    }
    // Only `detach` cancels this consumer, and it has already marked the model disconnected;
    // a replaced consumer must not disconnect its successor.
    if !Task.isCancelled { setConnected(false) }
  }

  private func setConnected(_ connected: Bool) {
    isConnected = connected
    isSnapshotLoaded = false
    reviews.connectionChanged(isConnected: connected)
  }

  private func bootstrap(_ api: any MemoshiAPI, head: Int64) async throws {
    let chats = try await api.call(ChatsList.self, EmptyParams())
    try Task.checkCancellation()
    try await reloadProviders(api, minimumSeq: head)
    try await reviews.reload(api, minimumSeq: head, replacing: true)
    guard chats.asOf.seq >= head else {
      throw ProjectionError.protocolViolation("Snapshot predates the subscription head")
    }
    chat = chats.items.first { $0.kind == .assistant }
    if chat != nil {
      try await reloadHistory(api, replacing: true)
    } else {
      messages = []
      live = nil
      task = nil
      recovery = nil
      resumeChoices = [:]
      queued = []
    }
    // A replaced consumer's bootstrap says nothing about its successor's snapshots.
    if !Task.isCancelled { isSnapshotLoaded = true }
    problem = nil
    if !providers.isEmpty { refreshModels() }
  }

  private func apply(_ envelope: EventEnvelope, api: any MemoshiAPI) async throws {
    guard let seq = envelope.seq else {
      try await applyLive(envelope, api: api)
      return
    }
    try await reviews.apply(envelope, client: api)
    if envelope.type == "system.settings_changed", seq > providersAsOf {
      try await reloadProviders(api, minimumSeq: seq)
    }
    guard let chat, envelope.scope.conversationId?.rawValue == chat.id.rawValue else { return }
    if let taskID = envelope.scope.taskId, seq > taskAsOf {
      recordRootTask(
        try await api.call(TasksGet.self, .init(taskId: taskID)), expected: taskID)
    }
    if seq > historyAsOf {
      try await reloadHistory(api, replacing: false)
    }
  }

  @discardableResult
  private func recordRootTask(_ snapshot: TasksGetResult, expected: TaskID) -> Bool {
    guard !Task.isCancelled, let chat, snapshot.task.id == expected,
      snapshot.task.conversationId == chat.id, snapshot.task.kind == .turn,
      snapshot.asOf.seq >= taskAsOf
    else { return false }
    task = snapshot.task
    taskAsOf = snapshot.asOf.seq
    observeTurn(snapshot.task)
    return true
  }

  private func applyLive(_ envelope: EventEnvelope, api: any MemoshiAPI) async throws {
    guard let chat, envelope.scope.conversationId?.rawValue == chat.id.rawValue else { return }
    if case .systemResyncRequired = envelope.event {
      try await reloadHistory(api, replacing: false)
      return
    }
    guard recovery == nil, (envelope.after ?? 0) >= historyAsOf,
      case .messageDelta(let delta) = envelope.event, delta.channel == .text,
      let taskID = envelope.scope.taskId
    else { return }
    if taskID != task?.id {
      // A bootstrap can precede the first visible Pi entry. Corroborate the task instead
      // of dropping its first frame or treating an attached child's text as the root reply.
      let snapshot = try await api.call(TasksGet.self, .init(taskId: taskID))
      guard [.queued, .running, .waiting].contains(snapshot.task.status),
        recordRootTask(snapshot, expected: taskID)
      else { return }
    }
    guard taskID == task?.id,
      task.map({ [.queued, .running, .waiting].contains($0.status) }) == true
    else { return }
    if messages.contains(where: { $0.id == delta.messageId }) { return }
    var partial = live?.message
    // A turn continued after a restart keeps its mark on the reply it streams again.
    let resumed = live?.taskId == taskID ? live?.resumedAfterInterruption : nil
    if partial?.id != delta.messageId {
      if delta.offsetUtf16 != 0 {
        try await reloadHistory(api, replacing: false)
        return
      }
      partial = ChatMessage(
        id: delta.messageId, conversationId: chat.id, taskId: taskID, role: .bot,
        content: [.text(TextPart(text: ""))], createdAt: envelope.ts,
        resumedAfterInterruption: resumed)
    }
    guard var message = partial else { return }
    let text = Self.text(message)
    let length = Int64(text.utf16.count)
    guard delta.offsetUtf16 == length else {
      // Replayed or missing frames are resolved from Pi, not appended twice or sliced.
      if delta.offsetUtf16 < length { return }
      try await reloadHistory(api, replacing: false)
      return
    }
    message.content = [.text(TextPart(text: text + delta.text))]
    live = ChatLiveState(taskId: taskID, message: message, resumedAfterInterruption: resumed)
    reportProgress()
  }

  private func reloadProviders(_ api: any MemoshiAPI, minimumSeq: Int64) async throws {
    let snapshot = try await api.call(ModelsProvidersList.self, EmptyParams())
    try Task.checkCancellation()
    guard snapshot.asOf.seq >= minimumSeq else {
      throw ProjectionError.protocolViolation("Provider snapshot predates its change")
    }
    guard snapshot.asOf.seq >= providersAsOf else { return }
    providers = snapshot.items
    providersAsOf = snapshot.asOf.seq
  }

  private func loadModels(_ api: any MemoshiAPI) async throws {
    // A cancelled listing that returns late must not clear its successor's indicator.
    modelListing += 1
    let listing = modelListing
    isLoadingModels = true
    defer { if modelListing == listing { isLoadingModels = false } }
    let listed = try await listModels(api)
    try Task.checkCancellation()
    models = listed.items
    if let unavailable = listed.unavailableProviders, !unavailable.isEmpty {
      modelProblem = String(
        localized:
          "The configured endpoint did not answer model discovery. Check that the local server is running; no other model is used.",
        bundle: #bundle
      )
    } else {
      modelProblem = nil
    }
    // Only an empty choice is defaulted. A saved model the endpoint no longer lists stays
    // unselected until the person chooses; no other model is substituted.
    if selectedModel.isEmpty, let first = models.first {
      selectedModel = first.ref.ref.rawValue
    }
  }

  /// The engine's model listing. A listing refused as busy while settings work an earlier
  /// attachment left running has not returned waits for that work and asks once more: the
  /// engine refuses before it looks at anything, and that work, cancelled, writes nothing here.
  private func listModels(_ api: any MemoshiAPI) async throws -> ModelsListResult {
    do {
      return try await api.call(ModelsList.self, EmptyParams())
    } catch let error as RPCError where error.kind == .busy {
      guard let earlier = detachedModelWork else { throw error }
      await earlier.value
      if detachedModelWork == earlier { detachedModelWork = nil }
      try Task.checkCancellation()
      return try await api.call(ModelsList.self, EmptyParams())
    }
  }

  private func reloadHistory(_ api: any MemoshiAPI, replacing: Bool) async throws {
    guard let chat else { return }
    historyRequest += 1
    let request = historyRequest
    let page = try await api.call(ChatsHistory.self, .init(chatId: chat.id))
    var choices: [CardID: [ResumeAction]] = [:]
    for step in page.recovery?.steps ?? [] {
      guard let card = step.step?.cardId else { continue }
      choices[card] = try await api.call(CardsGet.self, .init(cardId: card)).card.resumeChoices
    }
    try Task.checkCancellation()
    guard request >= appliedHistoryRequest, page.asOf.seq >= historyAsOf else { return }
    appliedHistoryRequest = request
    if replacing {
      messages = page.items
      nextBefore = page.nextBefore
    } else {
      let freshIDs = Set(page.items.map(\.id))
      let oldest = page.items.first?.id.rawValue
      // Keep only previously loaded pages older than the fresh window; never resurrect a
      // stale in-flight row while preserving intentional history pagination.
      let retained = messages.filter { message in
        !freshIDs.contains(message.id) && (oldest.map { message.id.rawValue < $0 } ?? false)
      }
      messages = retained + page.items
      if retained.isEmpty { nextBefore = page.nextBefore }
    }
    recovery = page.recovery
    resumeChoices = choices
    queued = page.queued ?? []
    live = page.recovery == nil ? page.live : nil
    historyAsOf = page.asOf.seq
    if let key = pending?.requestId {
      let confirming = messages.last { $0.requestId == key }
      if confirming != nil || queued.contains(where: { $0.requestId == key }) {
        confirmPending()
        // The receipt may never arrive; the confirmed message names the turn to follow.
        if let confirming, activeTurn?.requestId == key, activeTurn?.taskId == nil {
          activeTurn?.taskId = confirming.taskId
          if let task { observeTurn(task) }
        }
      }
    }
    let latestTaskID =
      page.recovery?.steps.first?.taskId ?? page.live?.taskId ?? page.items.last?.taskId
    if let latestTaskID {
      recordRootTask(
        try await api.call(TasksGet.self, .init(taskId: latestTaskID)), expected: latestTaskID)
      try Task.checkCancellation()
    } else {
      task = nil
      taskAsOf = page.asOf.seq
    }
    reportProgress()
    if !isWorking {
      isStopping = false
      stopIntent = nil
    }
  }

  // MARK: - Sending

  private func persistPending(_ params: ChatsSendParams) throws {
    try savedSend.save(params)
    pending = params
    hasUnconfirmedSend = true
  }

  private func confirmPending() {
    guard let pending else { return }
    let sent = pending.content.compactMap { part -> String? in
      if case .text(let text) = part { return text.text }
      return nil
    }.joined()
    if draft == sent { draft = "" }
    self.pending = nil
    hasUnconfirmedSend = false
    refusedSendReason = nil
    savedSend.remove()
  }

  private func clearRefusedPending() {
    pending = nil
    hasUnconfirmedSend = false
    refusedSendReason = nil
    savedSend.remove()
  }

  private func performSend(_ params: ChatsSendParams, connection: InProcessEngineConnection) {
    guard !isSending else { return }
    isSending = true
    problem = nil
    refusedSendReason = nil
    if activeTurn?.requestId != params.requestId {
      activeTurn = (params.requestId, nil, false)
      onTurnActivity?(.began(params.requestId))
    }
    sendTask = Task { [weak self] in
      guard let self else { return }
      defer {
        self.isSending = false
        self.sendTask = nil
      }
      var admitted = true
      do {
        let receipt = try await connection.api.call(ChatsSend.self, params)
        if self.activeTurn?.requestId == params.requestId {
          self.activeTurn?.taskId = receipt.taskId
        }
        self.confirmPending()
      } catch {
        // The rule is AppCore's, shared with the Mac and tested there.
        switch SendFailure(failure: error, isSaved: self.pending != nil) {
        case .refused:
          // Nothing was delivered: keep the editable draft only.
          self.problem = Self.message(error)
          self.clearRefusedPending()
          self.endTurn(params.requestId, succeeded: false)
          return
        case .refusedAsSaved:
          self.refusedSendReason = Self.message(error)
        case .uncertain:
          self.problem = Self.message(error)
        }
        if self.endUnconfirmedTurn(params.requestId) || Task.isCancelled { return }
        admitted = false
      }
      // The turn exists: the engine admitted it, or history confirmed it before an uncertain
      // error. A failed read from here on is neither a refused nor an uncertain Send, and a
      // background stop that arrived meanwhile still applies.
      var refreshed = true
      if admitted {
        do { try await self.reloadHistory(connection.api, replacing: false) } catch {
          if Task.isCancelled { return }
          self.problem = Self.message(error)
          refreshed = false
        }
      }
      guard self.backgroundCancellations.contains(params.requestId) else { return }
      if self.canStop {
        self.stop()
      } else if !refreshed, self.isConnected, self.recovery == nil, !self.isStopping,
        let chat = self.chat
      {
        // The projection could not load the turn, but its receipt proves there is one to stop.
        self.sendStop(chat: chat, connection: connection)
      }
    }
  }

  /// Delivery stays uncertain and the saved request remains retryable; only the host's
  /// progress shell ends here, never the engine's durable turn. Returns false, ending nothing,
  /// for a turn that history already confirmed: it is left to end with its task.
  private func endUnconfirmedTurn(_ requestId: ULID) -> Bool {
    guard activeTurn?.requestId == requestId, activeTurn?.taskId == nil else { return false }
    endTurn(requestId, succeeded: false)
    return true
  }

  private func reportProgress() {
    guard let turn = activeTurn, let taskID = turn.taskId, let live, live.taskId == taskID,
      let message = live.message
    else { return }
    onTurnActivity?(.progressed(turn.requestId, utf16Count: Self.text(message).utf16.count))
  }

  private func observeTurn(_ observed: MemoshiTask) {
    guard let turn = activeTurn, turn.taskId == observed.id else { return }
    if [.done, .failed, .canceled].contains(observed.status) {
      endTurn(turn.requestId, succeeded: observed.status == .done)
      return
    }
    let awaitsApproval = observed.status == .waiting && observed.waitingOn == .approval
    guard awaitsApproval != turn.awaitsApproval else { return }
    activeTurn?.awaitsApproval = awaitsApproval
    onTurnActivity?(
      awaitsApproval ? .waitingForApproval(turn.requestId) : .resumed(turn.requestId))
  }

  private func endTurn(_ requestId: ULID, succeeded: Bool) {
    guard activeTurn?.requestId == requestId else { return }
    activeTurn = nil
    backgroundCancellations.remove(requestId)
    onTurnActivity?(.ended(requestId, succeeded: succeeded))
  }

  private static func message(_ error: any Error) -> String {
    if let error = error as? RPCError { return error.message }
    return String(
      localized: "The operation could not be completed. No substitute model or reply was used.",
      bundle: #bundle)
  }
}
