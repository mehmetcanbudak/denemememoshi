import AppCore
import Foundation
import MemoshiClient
import MemoshiProtocol
import MemoshiRuntime
import MemoshiTransport
import Observation

/// Composer response speed mode: Fast caps reasoning effort to `.low` for quicker replies.
enum ComposerSpeedMode: String, CaseIterable, Identifiable, Sendable {
  case standard = "Standard"
  case fast = "Fast"

  var id: String { rawValue }
}

extension ThinkingEffort {
  static let composerChoices: [ThinkingEffort] = [
    .off, .minimal, .low, .medium, .high, .xhigh, .max,
  ]

  var composerDisplayName: String {
    switch self {
    case .off: "Off"
    case .minimal: "Minimal"
    case .low: "Low"
    case .medium: "Medium"
    case .high: "High"
    case .xhigh: "Extra High"
    case .max: "Max"
    case .unknown(let raw): raw
    }
  }

  /// Parses persisted wire values (`"high"`, `"xhigh"`) and legacy display labels (`"Extra High"`).
  static func parseComposerPreference(_ raw: String?) -> ThinkingEffort {
    guard let raw else { return .high }
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "off": return .off
    case "minimal": return .minimal
    case "low": return .low
    case "medium": return .medium
    case "high": return .high
    case "xhigh", "extra high": return .xhigh
    case "max": return .max
    default: return .high
    }
  }
}

/// App-owned drafts plus in-memory projections of actual daemon snapshots/events.
/// Finished transcript text is never persisted in UI preferences.
@MainActor
@Observable
final class LiveChatModel {
  /// Client-observed timing of the latest send: the development HUD's only turn latency.
  struct TurnTiming: Equatable {
    let requestId: ULID
    let started: ContinuousClock.Instant
    var taskId: TaskID?
    /// From Send to the first streamed text delta of that turn reaching this consumer.
    var firstDelta: Duration?
    /// From Send to this consumer applying the turn's terminal task state.
    var duration: Duration?
    var status: TaskStatus?
  }

  /// Durable facts this consumer applied and acknowledged since its latest bootstrap barrier.
  struct AppliedEvents: Equatable {
    let baseline: Int64
    var count = 0
    var last: Int64?
    /// Each acknowledged seq followed the previous one: no gap and no second application.
    var isContiguous: Bool { (last ?? baseline) - baseline == Int64(count) }
  }

  let providerSetup: ModelProviderSetup
  let reviews: LiveApprovalModel
  let folders: FolderGrantSetup
  let directory: LiveConversationDirectory
  let taskInspector: LiveTaskInspector
  private(set) var chat: ChatSummary?
  private(set) var messages: [ChatMessage] = []
  private(set) var live: ChatLiveState?
  private(set) var recovery: ChatRecoveryHold?
  private(set) var queued: [QueuedChatMessage] = []
  private(set) var cancelingQueued: Set<ULID> = []
  /// What each held step's Resume card offers now, by card (D51).
  private(set) var resumeChoices: [CardID: [ResumeAction]] = [:]
  /// Resume cards whose answer is on its way to the runtime.
  private(set) var answeringResume: Set<CardID> = []
  private(set) var task: MemoshiTask?
  private(set) var connection = ClientConnectionState.disconnected
  private(set) var isLoading = false
  private(set) var isSending = false
  private(set) var isStopping = false
  private(set) var nextBefore: MessageID?
  private(set) var problem: String?
  private(set) var hasUnconfirmedSend = false
  /// Why the saved Send cannot be retried: its record could not be read. Non-nil exactly
  /// while `hasUnreadableSend`; `problem` stays free for other failures.
  private(set) var unreadableSendExplanation: String?
  /// Whether the saved Send could not be read, so it can never be retried. Sending stays
  /// blocked until the person discards the record.
  var hasUnreadableSend: Bool { unreadableSendExplanation != nil }
  /// Why the runtime definitely refused the saved Send on its latest attempt, in its own
  /// words; nil when there is no such refusal. The request stays saved and Retry is unchanged;
  /// the person may discard it instead. It is saved with the request, so a relaunch still
  /// offers the discard.
  private(set) var refusedSendReason: String? {
    didSet { savedSend.recordRefusal(refusedSendReason) }
  }
  private(set) var unknownEventCount = 0
  /// Bounded committed metadata since the latest bootstrap, not historical audit retrieval.
  private(set) var activityEvents: [EventEnvelope] = []
  private(set) var activityBaseline: Int64?
  private(set) var activityOmittedCount = 0
  @ObservationIgnored private var activityLastSeq: Int64 = 0
  private static let activityRetentionCount = 200
  /// Authoritative task snapshots across real conversations, including their Pi children.
  var knownTasks: [TaskID: MemoshiTask] { taskSnapshots.tasks }
  private var taskSnapshots = TaskSnapshots()
  private(set) var isLoadingTasks = false
  private(set) var taskListProblem: String?
  /// Increments when a bootstrap barrier replaces the snapshots the task list derives from.
  private(set) var taskListGeneration = 0
  private(set) var lastTurn: TurnTiming?
  private(set) var appliedEvents: AppliedEvents?
  /// Completed connections this app session, so a reconnect is observable.
  private(set) var connectionCount = 0
  var draft = "" {
    didSet {
      if let chat { defaults.set(draft, forKey: "text-chat.draft." + chat.id.rawValue) }
    }
  }
  var composerThinkingEffort: ThinkingEffort = .high {
    didSet {
      defaults.set(composerThinkingEffort.rawValue, forKey: "composer.thinkingLevel")
    }
  }
  var composerSpeedMode: ComposerSpeedMode = .standard {
    didSet {
      defaults.set(composerSpeedMode.rawValue, forKey: "composer.speedMode")
    }
  }

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let savedSend: SavedSend
  @ObservationIgnored private var client: MemoshiClient?
  @ObservationIgnored private var eventTask: Task<Void, Never>?
  @ObservationIgnored private var statusTask: Task<Void, Never>?
  @ObservationIgnored private var actionTask: Task<Void, Never>?
  @ObservationIgnored private var pending: ChatsSendParams?
  @ObservationIgnored private var stopIntent: ChatsAbortParams?
  @ObservationIgnored private var queuedCancelIntents: [ULID: ChatsAbortParams] = [:]
  @ObservationIgnored private var queuedCancelTasks: [ULID: Task<Void, Never>] = [:]
  /// An answer whose delivery is uncertain keeps its request ID, so a retry is the same answer.
  @ObservationIgnored private var resumeIntents: [CardID: CardsRespondParams] = [:]
  @ObservationIgnored private var resumeTasks: [CardID: Task<Void, Never>] = [:]
  @ObservationIgnored private var visibleOwners: Set<UUID> = []
  @ObservationIgnored private var historyAsOf = SnapshotWatermark()
  @ObservationIgnored private var taskAsOf = SnapshotWatermark()
  @ObservationIgnored private var opaqueEvents: [EventEnvelope] = []
  @ObservationIgnored private var historyRequest = 0
  @ObservationIgnored private var appliedHistoryRequest = 0
  @ObservationIgnored private var appliedFocus: [ConversationID]?
  @ObservationIgnored private var updatingFocus = false
  /// Set until the first bootstrap, and when a lost connection or an invalidated receipt
  /// interrupted this consumer's own application: the review projection is then reloaded before
  /// the next event is applied. A reconnect alone needs nothing here; the projection reloads
  /// itself once it is connected again (`LiveApprovalModel.connectionChanged`).
  @ObservationIgnored private var reviewNeedsReconnectSnapshot = true
  /// One automatic reload after a failed update (D130; the rule is AppCore's, tested there).
  @ObservationIgnored private let automaticReload = AutomaticReload { error in
    if case .requestTimedOut = error as? ClientError { return true }
    return false
  }
  @ObservationIgnored private var earlyDelta: (task: TaskID, at: ContinuousClock.Instant)?
  @ObservationIgnored private var lastConnectionID: String?
  @ObservationIgnored private var lastDaemon: DaemonInfo?
  @ObservationIgnored private var needsModelDiscovery = false
  @ObservationIgnored private var taskLoad: Task<Void, Never>?
  @ObservationIgnored private var taskReloadRequested = false
  @ObservationIgnored private var tasksVisible = false

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.providerSetup = ModelProviderSetup(defaults: defaults)
    self.reviews = LiveApprovalModel(defaults: defaults, makeRequestID: MemoshiClient.requestID)
    self.folders = FolderGrantSetup(defaults: defaults)
    self.directory = LiveConversationDirectory(defaults: defaults)
    self.taskInspector = LiveTaskInspector(defaults: defaults)
    self.draft = defaults.string(forKey: "text-chat.draft") ?? ""
    self.composerThinkingEffort = ThinkingEffort.parseComposerPreference(
      defaults.string(forKey: "composer.thinkingLevel"))
    self.composerSpeedMode =
      defaults.string(forKey: "composer.speedMode").flatMap(ComposerSpeedMode.init(rawValue:))
      ?? .standard
    self.savedSend = SavedSend(defaults: defaults)
    switch savedSend.load() {
    case .readable(let request, let refusal):
      pending = request
      hasUnconfirmedSend = true
      refusedSendReason = refusal
    case .unreadable:
      hasUnconfirmedSend = true
      unreadableSendExplanation = String(
        localized:
          "The saved delivery record could not be read. Sending is blocked to avoid duplicating an uncertain message."
      )
    case nil:
      break
    }
  }

  var isWorking: Bool {
    recovery == nil
      && (live != nil || task.map { [.queued, .running, .waiting].contains($0.status) } == true)
  }

  var canSend: Bool {
    connection == .connected && chat != nil && selectedSendModel != nil && !isLoading
      && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !isWorking && !isSending && !providerSetup.isConfiguring
      && !providerSetup.hasUnconfirmedConfiguration && !hasUnreadableSend && !hasUnconfirmedSend
  }

  /// Whether the composer can queue a follow-up or steer the active turn while the bot is working (CH-07).
  var canQueueWhileWorking: Bool {
    connection == .connected && chat != nil && selectedSendModel != nil && !isLoading
      && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && isWorking && recovery == nil && !isSending && !isStopping
      && !providerSetup.isConfiguring && !providerSetup.hasUnconfirmedConfiguration
      && !hasUnreadableSend && !hasUnconfirmedSend
  }

  var canRetrySend: Bool {
    connection == .connected && pending != nil && !isSending && !hasUnreadableSend
  }

  /// Offered only while this conversation's current snapshot is loaded, so it can be checked.
  var canDiscardUnreadableSend: Bool {
    hasUnreadableSend && connection == .connected && chat != nil && !isLoading
  }

  /// Removes only a record that can never be read or retried. Nothing is sent.
  func discardUnreadableSend() {
    guard canDiscardUnreadableSend else { return }
    savedSend.remove()
    unreadableSendExplanation = nil
    hasUnconfirmedSend = false
    problem = String(
      localized:
        "The unreadable saved delivery record was discarded without sending anything. Check this conversation before sending the same message again."
    )
  }

  /// Whether the person may discard the saved Send the runtime refused.
  var canDiscardRefusedSend: Bool {
    refusedSendReason != nil && pending != nil && !isSending
  }

  /// D130: discards the saved Send the runtime definitely refused, so sending can resume. It
  /// removes that saved request alone: the draft stays and nothing is sent.
  func discardRefusedSend() {
    guard canDiscardRefusedSend else { return }
    clearRefusedPending()
  }

  var botModel: ModelRef? {
    guard let bot = directory.bots.first(where: { $0.id == chat?.botId }),
      bot.model.ref.rawValue != "default"
    else { return nil }
    return bot.model
  }

  var sendProvider: ModelProviderDefinition? {
    let ref = botModel?.ref.rawValue ?? providerSetup.selectedModel
    return ref.split(separator: "/", maxSplits: 1).first.flatMap {
      ModelProviderDefinition.named(String($0))
    }
  }

  var sendUsage: ModelUsageDisclosure? {
    sendProvider.map { provider in
      provider.usage(secretRef: providerSetup.providers.first { $0.id == provider.id }?.secretRef)
    }
  }

  /// The reasoning effort sent to `memoshid` for non-local models (`MOD-04`).
  /// Fast mode caps reasoning effort to `.low` while preserving `.off` and `.minimal`.
  var effectiveThinkingEffort: ThinkingEffort {
    let base = botModel?.effort ?? composerThinkingEffort
    switch composerSpeedMode {
    case .standard:
      return base
    case .fast:
      switch base {
      case .off, .minimal, .low:
        return base
      default:
        return .low
      }
    }
  }

  /// Whether the active target model is a local server model (effort is left to the server default).
  var isSelectedModelLocal: Bool {
    let ref = botModel?.ref.rawValue ?? providerSetup.selectedModel
    return ref.hasPrefix("local/")
  }

  /// Exposed internally for unit tests verifying effort and speed mode resolution.
  var resolvedSendModel: ModelRef? { selectedSendModel }

  private var selectedSendModel: ModelRef? {
    func withComposerEffort(_ base: ModelRef) -> ModelRef {
      if base.ref.rawValue.hasPrefix("local/") {
        return ModelRef(ref: base.ref, effort: nil)
      }
      return ModelRef(ref: base.ref, effort: effectiveThinkingEffort)
    }

    if let botModel {
      return providerSetup.models.contains(where: { $0.ref.ref == botModel.ref })
        ? withComposerEffort(botModel) : nil
    }
    if let selected = providerSetup.models.first(where: {
      $0.ref.ref.rawValue == providerSetup.selectedModel
    }) {
      return withComposerEffort(selected.ref)
    }
    // Queuing cannot dispatch or discover a model. Preserve an earlier explicit selection
    // even when the held, inspection-only runtime has not loaded its catalog.
    guard recovery != nil, let ref = try? ModelName(providerSetup.selectedModel) else { return nil }
    let parts = ref.rawValue.split(separator: "/", maxSplits: 1)
    guard parts.count == 2,
      providerSetup.providers.contains(where: { $0.id == parts[0] })
    else { return nil }
    return withComposerEffort(ModelRef(ref: ref))
  }

  /// Attach one event consumer to the authenticated app-lifetime client, not one per chat pane.
  func attach(_ client: MemoshiClient) {
    if self.client === client, eventTask != nil { return }
    eventTask?.cancel()
    statusTask?.cancel()
    self.client = client
    automaticReload.reset()
    providerSetup.attach(client)
    reviews.attach(client)
    folders.attach(client)
    directory.attach(client)
    taskInspector.attach(client)
    statusTask = Task { [weak self, client] in
      for await status in await client.updates() {
        guard let self, !Task.isCancelled else { return }
        await self.handleStatusUpdate(status, client: client)
      }
    }
    eventTask = Task { [weak self, client] in
      do {
        let stream = try await client.events()
        for try await update in stream {
          guard let self, !Task.isCancelled else { return }
          do {
            let step: AutomaticReload.Step
            if case .transient = update { step = .transient } else { step = .durable }
            // D130: after a timeout or daemon error every snapshot is reloaded once. A failure
            // of that reload, or of a later update before a durable one applies normally,
            // reaches the cases below and, unless it is a connection loss, ends this
            // consumer: Reconnect. No loop.
            try await self.automaticReload.run(step) {
              switch update {
              case .resyncRequired(let barrier):
                try await self.bootstrap(client, barrier: barrier)
              case .event(let receipt):
                try await self.apply(receipt.envelope, client: client)
                try await client.acknowledgeApplied(receipt)
                self.noteApplied(receipt.envelope.seq)
              case .transient(let envelope):
                try await self.applyTransient(envelope, client: client)
              }
            } reload: {
              try await self.reloadAfterFailure(update, client: client)
            }
          } catch let error as ClientError {
            switch error {
            case .notConnected, .disconnected, .staleAcknowledgment, .connectionClosed:
              // The cursor did not advance. This consumer receives reconnect replay or a
              // fresh barrier; an obsolete receipt must not end approval synchronization.
              self.reviewNeedsReconnectSnapshot = true
            default:
              throw error
            }
          } catch let error as IPCError where error != .outboundOverflow {
            // A plain loss during a call arrives as `connectionClosed` above. A teardown the
            // client classifies as more than a loss (signing, authentication, a stopped
            // daemon) keeps the carrier's error. The cursor did not advance then either, so
            // this consumer stays attached and replays on the next connection.
            self.reviewNeedsReconnectSnapshot = true
          }
        }
      } catch is CancellationError {
      } catch {
        self?.problem = Self.message(error)
      }
      self?.eventTask = nil
    }
  }

  func stop() {
    providerSetup.stop()
    reviews.stop()
    folders.stop()
    taskInspector.detach()
    for task in queuedCancelTasks.values { task.cancel() }
    for task in resumeTasks.values { task.cancel() }
    taskLoad?.cancel()
    taskLoad = nil
    queuedCancelTasks.removeAll()
    resumeTasks.removeAll()
    actionTask?.cancel()
    statusTask?.cancel()
    eventTask?.cancel()
    actionTask = nil
    statusTask = nil
    eventTask = nil
  }

  func showTasks() {
    tasksVisible = true
    taskInspector.show()
    loadTasks()
    Task { await updateFocus() }
  }

  func hideTasks() {
    tasksVisible = false
    taskInspector.hide()
    Task { await updateFocus() }
  }

  func inspectTask(_ task: MemoshiTask?) {
    let previous = taskInspector.conversationID
    taskInspector.select(task)
    if previous != taskInspector.conversationID { Task { await updateFocus() } }
  }

  func show(owner: UUID) async {
    visibleOwners.insert(owner)
    await updateFocus()
    if let client, chat != nil {
      do { try await reloadHistory(client, replacing: false) } catch {
        problem = Self.message(error)
      }
    }
  }

  func hide(owner: UUID) async {
    visibleOwners.remove(owner)
    await updateFocus()
  }

  /// Changes only the visible projection and focus. A running turn on the previous
  /// conversation keeps running in memoshid; its history is read when selected again.
  func selectConversation(_ id: ConversationID) async {
    guard id != chat?.id, !isSending, !isStopping, !isLoading, !hasUnconfirmedSend,
      let selected = directory.conversations.first(where: { $0.id == id }), let client
    else { return }
    isLoading = true
    defer { isLoading = false }
    useConversation(selected)
    do {
      try await reloadHistory(client, replacing: true)
      await updateFocus()
    } catch { problem = Self.message(error) }
  }

  private func useConversation(_ selected: ChatSummary?) {
    guard selected?.id != chat?.id else {
      chat = selected
      return
    }
    chat = selected
    defaults.set(selected?.id.rawValue, forKey: "text-chat.selected-conversation")
    draft =
      selected.map { defaults.string(forKey: "text-chat.draft." + $0.id.rawValue) ?? "" } ?? ""
    messages = []
    live = nil
    recovery = nil
    resumeChoices = [:]
    queued = []
    task = nil
    nextBefore = nil
    problem = nil
    historyAsOf.reset()
    taskAsOf.reset()
    stopIntent = nil
    appliedFocus = nil
    taskListGeneration += 1
  }

  func send(whenBusy: WhenBusy = .reject) {
    let allowed = whenBusy == .reject ? canSend : (canSend || canQueueWhileWorking)
    guard allowed, let chat, let model = selectedSendModel else { return }
    do {
      let params = ChatsSendParams(
        requestId: try MemoshiClient.requestID(), chatId: chat.id,
        content: [.text(TextPart(text: draft))], whenBusy: whenBusy, model: model, surface: .ui)
      try persistPending(params)
      performSend(params)
    } catch { problem = Self.message(error) }
  }

  /// Re-sends an earlier prompt cleanly without overwriting an unrelated composer draft.
  func retryPrompt(_ prompt: String) {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, connection == .connected, let chat, let model = selectedSendModel,
      !isLoading, !isWorking, !isSending, !providerSetup.isConfiguring,
      !providerSetup.hasUnconfirmedConfiguration, !hasUnreadableSend, !hasUnconfirmedSend
    else { return }
    do {
      let params = ChatsSendParams(
        requestId: try MemoshiClient.requestID(), chatId: chat.id,
        content: [.text(TextPart(text: trimmed))], whenBusy: .reject, model: model, surface: .ui)
      try persistPending(params)
      performSend(params)
    } catch { problem = Self.message(error) }
  }

  /// Sends a prompt from Quick Entry or Command Palette, optionally switching conversations first,
  /// without clobbering any unrelated composer draft. Defaults to `.followUp` so prompts sent
  /// while a bot is busy queue cleanly instead of failing.
  @discardableResult
  func sendQuickPrompt(
    _ prompt: String, to conversationID: ConversationID? = nil, whenBusy: WhenBusy = .followUp
  ) async -> Bool {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, connection == .connected else { return false }
    if let target = conversationID, target != chat?.id {
      await selectConversation(target)
      guard chat?.id == target else { return false }
    }
    let busyAllowed = whenBusy == .followUp || whenBusy == .steer
    guard let chat, let model = selectedSendModel,
      !isLoading, (!isWorking || (busyAllowed && recovery == nil)), !isSending,
      !providerSetup.isConfiguring, !providerSetup.hasUnconfirmedConfiguration,
      !hasUnreadableSend, !hasUnconfirmedSend
    else { return false }
    do {
      let params = ChatsSendParams(
        requestId: try MemoshiClient.requestID(), chatId: chat.id,
        content: [.text(TextPart(text: trimmed))], whenBusy: whenBusy, model: model, surface: .ui)
      try persistPending(params)
      performSend(params)
      return true
    } catch {
      problem = Self.message(error)
      return false
    }
  }

  func retrySend() {
    guard canRetrySend, let pending else { return }
    performSend(pending)
  }

  func stopGeneration() {
    guard recovery == nil, let chat, let client, connection == .connected,
      isWorking, !isStopping
    else { return }
    do {
      let params =
        try stopIntent ?? ChatsAbortParams(requestId: MemoshiClient.requestID(), chatId: chat.id)
      stopIntent = params
      isStopping = true
      problem = nil
      actionTask = Task { [weak self, client] in
        guard let self else { return }
        defer {
          self.isStopping = false
          self.actionTask = nil
        }
        do {
          _ = try await client.call(ChatsAbort.self, params)
          self.stopIntent = nil
          try await self.reloadHistory(client, replacing: false)
        } catch { self.problem = Self.message(error) }
      }
    } catch { problem = Self.message(error) }
  }

  /// Answers a held step's Resume card with Run again, Skip or Mark as done (D51). The runtime
  /// settles the step and the chat continues; a retried answer keeps its original request ID.
  func answerResume(_ card: CardID, _ action: ResumeAction) {
    guard let client, connection == .connected, !answeringResume.contains(card),
      resumeChoices[card]?.contains(action) == true
    else { return }
    do {
      let params: CardsRespondParams
      if let earlier = resumeIntents[card], earlier.action == action.rawValue {
        params = earlier
      } else {
        params = CardsRespondParams(
          requestId: try MemoshiClient.requestID(), cardId: card, action: action.rawValue,
          surface: .ui)
      }
      resumeIntents[card] = params
      answeringResume.insert(card)
      problem = nil
      resumeTasks[card] = Task { [weak self, client] in
        guard let self else { return }
        defer {
          self.answeringResume.remove(card)
          self.resumeTasks.removeValue(forKey: card)
        }
        do {
          _ = try await client.call(CardsRespond.self, params)
          self.resumeIntents.removeValue(forKey: card)
          // A stopped model no longer reloads through the client it used.
          try Task.checkCancellation()
          try await self.reloadHistory(client, replacing: false)
        } catch {
          if !Task.isCancelled { self.problem = Self.message(error) }
        }
      }
    } catch { problem = Self.message(error) }
  }

  func cancelQueued(_ input: QueuedChatMessage) {
    guard let client, let chat, connection == .connected,
      queued.contains(where: { $0.requestId == input.requestId }),
      !cancelingQueued.contains(input.requestId)
    else { return }
    do {
      let params =
        try queuedCancelIntents[input.requestId]
        ?? ChatsAbortParams(
          requestId: MemoshiClient.requestID(), chatId: chat.id, queuedRequestId: input.requestId)
      queuedCancelIntents[input.requestId] = params
      cancelingQueued.insert(input.requestId)
      queuedCancelTasks[input.requestId] = Task { [weak self, client] in
        guard let self else { return }
        defer {
          self.cancelingQueued.remove(input.requestId)
          self.queuedCancelTasks.removeValue(forKey: input.requestId)
        }
        do {
          _ = try await client.call(ChatsAbort.self, params)
          self.queuedCancelIntents.removeValue(forKey: input.requestId)
          try await self.reloadHistory(client, replacing: false)
        } catch { self.problem = Self.message(error) }
      }
    } catch { problem = Self.message(error) }
  }

  func loadOlder() {
    guard let client, let chat, let before = nextBefore, !isLoading else { return }
    isLoading = true
    actionTask = Task { [weak self, client] in
      guard let self else { return }
      defer {
        self.isLoading = false
        self.actionTask = nil
      }
      do {
        let page = try await client.call(ChatsHistory.self, .init(chatId: chat.id, before: before))
        guard self.chat?.id == chat.id else { return }
        let existing = Set(self.messages.map(\.id))
        self.messages.insert(contentsOf: page.items.filter { !existing.contains($0.id) }, at: 0)
        self.nextBefore = page.nextBefore
      } catch { self.problem = Self.message(error) }
    }
  }

  /// Task identities the applied chat snapshots mention, in transcript order.
  var referencedTaskIDs: [TaskID] {
    var seen = Set<TaskID>()
    var ordered: [TaskID] = []
    func add(_ id: TaskID?) {
      if let id, seen.insert(id).inserted { ordered.append(id) }
    }
    for message in messages { add(message.taskId) }
    for step in recovery?.steps ?? [] { add(step.taskId) }
    add(live?.taskId)
    add(task?.id)
    for entry in reviews.entries where entry.card.conversationId.rawValue == chat?.id.rawValue {
      add(entry.card.taskId)
    }
    return ordered
  }

  /// Reads the persisted graph for each real conversation. The app's existing event consumer
  /// maintains individual nodes; a visible Tasks window also observes other conversations.
  func loadTasks() {
    taskReloadRequested = true
    guard taskLoad == nil else { return }
    taskLoad = Task { [weak self] in
      await self?.runTaskLoads()
      self?.taskLoad = nil
    }
  }

  private func runTaskLoads() async {
    isLoadingTasks = true
    defer { isLoadingTasks = false }
    while taskReloadRequested, let client, connection == .connected {
      taskReloadRequested = false
      taskListProblem = nil
      for conversation in directory.conversations {
        do {
          let snapshot = try await client.call(
            TasksGraph.self, .init(conversationId: conversation.id))
          guard !Task.isCancelled else { return }
          for item in snapshot.nodes { record(item, asOf: snapshot.asOf.seq) }
        } catch is CancellationError {
          return
        } catch {
          taskListProblem = Self.message(error)
          return
        }
      }
    }
  }

  private static func isTerminal(_ status: TaskStatus) -> Bool {
    [.done, .failed, .canceled].contains(status)
  }

  private func record(_ snapshot: TasksGetResult) {
    record(snapshot.task, asOf: snapshot.asOf.seq)
    for child in snapshot.children { record(child, asOf: snapshot.asOf.seq) }
  }

  private func record(_ item: MemoshiTask, asOf sequence: Int64) {
    guard taskSnapshots.record(item, asOf: sequence) else { return }
    observeTurn(item)
  }

  @discardableResult
  private func recordRootTask(_ snapshot: TasksGetResult, expected: TaskID) -> Bool {
    guard !Task.isCancelled, snapshot.task.id == expected,
      snapshot.task.conversationId == chat?.id, snapshot.task.kind == .turn,
      taskAsOf.admits(snapshot.asOf.seq)
    else { return false }
    // A newly queued follow-up turn must not clobber the actively running root turn.
    if snapshot.task.status == .queued, let current = task, current.id != snapshot.task.id,
      [.queued, .running, .waiting].contains(current.status)
    {
      return false
    }
    task = snapshot.task
    taskAsOf.advance(to: snapshot.asOf.seq)
    return true
  }

  private func noteAdmitted(_ result: ChatsSendResult, requestId: ULID) {
    guard var timing = lastTurn, timing.requestId == requestId, timing.taskId == nil else { return }
    timing.taskId = result.taskId
    // A delta can reach the consumer before the admission response does.
    if let early = earlyDelta, early.task == result.taskId {
      timing.firstDelta = timing.started.duration(to: early.at)
    }
    earlyDelta = nil
    lastTurn = timing
    if let known = knownTasks[result.taskId] { observeTurn(known) }
  }

  private func noteDelta(_ taskID: TaskID) {
    guard var timing = lastTurn, timing.firstDelta == nil, timing.duration == nil else { return }
    let now = ContinuousClock.now
    if let expected = timing.taskId {
      guard expected == taskID else { return }
      timing.firstDelta = timing.started.duration(to: now)
      lastTurn = timing
    } else if earlyDelta == nil {
      earlyDelta = (taskID, now)
    }
  }

  private func observeTurn(_ observed: MemoshiTask) {
    guard var timing = lastTurn, timing.taskId == observed.id, timing.duration == nil,
      Self.isTerminal(observed.status)
    else { return }
    timing.duration = timing.started.duration(to: .now)
    timing.status = observed.status
    lastTurn = timing
  }

  private func noteApplied(_ seq: Int64?) {
    guard let seq, var applied = appliedEvents else { return }
    applied.count += 1
    applied.last = seq
    appliedEvents = applied
  }

  private func bootstrap(_ client: MemoshiClient, barrier: ResyncRequest) async throws {
    isLoading = true
    defer { isLoading = false }
    // A resync replaces every snapshot. Its barrier can lie below the earlier watermarks when
    // the daemon's log is another one or a restored copy (D131), so none may reject it.
    historyAsOf.reset()
    taskAsOf.reset()
    taskSnapshots.removeAll()
    providerSetup.prepareForResync()
    directory.prepareForResync()
    taskInspector.prepareForResync()
    try await loadSnapshots(client, minimumSeq: barrier.head)
    try await client.completeResync(barrier, appliedThrough: barrier.head)
    appliedEvents = AppliedEvents(baseline: barrier.head)
    activityEvents.removeAll(keepingCapacity: true)
    activityBaseline = barrier.head
    activityLastSeq = barrier.head
    activityOmittedCount = 0
    taskListGeneration += 1
    await updateFocus()
    if !providerSetup.providers.isEmpty {
      do { try await providerSetup.reloadModels() } catch { problem = Self.message(error) }
    }
  }

  /// D130: a timeout or daemon error while one update was applied is answered by reloading
  /// every snapshot. The reload covers a durable event, so its receipt is acknowledged.
  private func reloadAfterFailure(_ update: ClientEvent, client: MemoshiClient) async throws {
    if case .resyncRequired(let barrier) = update {
      try await bootstrap(client, barrier: barrier)
      return
    }
    isLoading = true
    defer { isLoading = false }
    switch update {
    case .event(let receipt):
      try await loadSnapshots(client, minimumSeq: receipt.envelope.seq ?? 0)
      if receipt.envelope.type == "session.purged" {
        defaults.removeObject(forKey: "text-chat.draft." + receipt.envelope.subject.id)
      }
      try await client.acknowledgeApplied(receipt)
      noteApplied(receipt.envelope.seq)
    case .transient(let envelope):
      try await loadSnapshots(client, minimumSeq: envelope.after ?? 0)
    case .resyncRequired:
      break
    }
    taskListGeneration += 1
  }

  /// Replaces every store's snapshot with one that covers `minimumSeq`.
  private func loadSnapshots(_ client: MemoshiClient, minimumSeq: Int64) async throws {
    let chats = try await client.call(ChatsList.self, EmptyParams())
    try await directory.reload(minimumSeq: minimumSeq)
    try await directory.reloadTrashIfVisible(minimumSeq: minimumSeq)
    pruneTasks()
    let providers = try await client.call(ModelsProvidersList.self, EmptyParams())
    try await reviews.reload(client, minimumSeq: minimumSeq, replacing: true)
    guard chats.asOf.seq >= minimumSeq, providers.asOf.seq >= minimumSeq
    else { throw ClientError.protocolViolation("Snapshot predates bootstrap barrier") }
    if let assistant = chats.items.first(where: { $0.kind == .assistant }),
      defaults.object(forKey: "text-chat.draft." + assistant.id.rawValue) == nil,
      let legacy = defaults.string(forKey: "text-chat.draft")
    {
      defaults.set(legacy, forKey: "text-chat.draft." + assistant.id.rawValue)
      defaults.removeObject(forKey: "text-chat.draft")
    }
    let selected =
      pending?.chatId
      ?? defaults.string(forKey: "text-chat.selected-conversation").flatMap {
        try? ConversationID($0)
      }
    useConversation(chats.items.first(where: { $0.id == selected }) ?? chats.items.first)
    providerSetup.applyProviders(providers)
    // The Assistant's folder snapshot is applied before the barrier is acknowledged.
    try await folders.bootstrap(
      client, assistant: directory.conversations.first { $0.kind == .assistant },
      minimumSeq: minimumSeq)
    if chat != nil {
      try await reloadHistory(client, replacing: true)
      guard historyAsOf.covers(minimumSeq) else {
        throw ClientError.protocolViolation("History predates bootstrap barrier")
      }
    } else {
      messages = []
      live = nil
      task = nil
      recovery = nil
      resumeChoices = [:]
      queued = []
    }
    reviewNeedsReconnectSnapshot = false
  }

  /// Returns true for gateway-only metadata, which cannot change the Pi transcript/task.
  private func recordActivity(_ envelope: EventEnvelope) -> Bool {
    let metadataOnly: Bool
    switch envelope.event {
    case .egressAllowed, .egressBlocked, .secretUsed: metadataOnly = true
    case .policyDecided, .policyRedacted, .toolCompleted: metadataOnly = false
    default: return false
    }
    if let seq = envelope.seq, seq > activityLastSeq {
      activityLastSeq = seq
      activityEvents.append(envelope)
      if activityEvents.count > Self.activityRetentionCount {
        activityEvents.removeFirst()
        activityOmittedCount += 1
      }
    }
    return metadataOnly
  }

  private func apply(_ envelope: EventEnvelope, client: MemoshiClient) async throws {
    let activityOnly = recordActivity(envelope)
    taskInspector.observe(envelope)
    if reviewNeedsReconnectSnapshot {
      try await reviews.reload(client, minimumSeq: envelope.seq ?? 0)
      reviewNeedsReconnectSnapshot = false
    }
    try await reviews.apply(envelope, client: client)
    try await folders.apply(envelope, client: client)
    if activityOnly { return }
    if case .unknown = envelope.event {
      opaqueEvents.append(envelope)
      if opaqueEvents.count > 64 { opaqueEvents.removeFirst() }
      unknownEventCount += 1
      return
    }
    if envelope.type == "system.settings_changed" {
      try await providerSetup.reloadProvidersIfNewer(than: envelope.seq ?? 0)
    }
    if [
      "bot.created", "bot.updated", "chat.created", "session.created", "session.deleted",
      "session.restored", "session.purged", "trash.emptied",
    ].contains(envelope.type) {
      try await directory.reload(minimumSeq: envelope.seq ?? 0)
      pruneTasks()
      try await directory.reloadTrashIfVisible(minimumSeq: envelope.seq ?? 0)
      if let updated = directory.conversations.first(where: { $0.id == chat?.id }) {
        chat = updated
      } else if chat != nil {
        useConversation(directory.conversations.first(where: { $0.kind == .assistant }))
        if chat != nil { try await reloadHistory(client, replacing: true) }
        await updateFocus()
      }
      if envelope.type == "session.purged" {
        defaults.removeObject(forKey: "text-chat.draft." + envelope.subject.id)
      }
    }
    if let taskID = envelope.scope.taskId,
      tasksVisible || envelope.scope.conversationId == chat?.id,
      taskSnapshots.isBehind(taskID, at: envelope.seq ?? 0)
        || (envelope.scope.conversationId == chat?.id && !taskAsOf.covers(envelope.seq ?? 0))
    {
      let snapshot = try await client.call(TasksGet.self, .init(taskId: taskID))
      record(snapshot)
      recordRootTask(snapshot, expected: taskID)
    }
    guard envelope.scope.conversationId == chat?.id else { return }
    if !historyAsOf.covers(envelope.seq ?? 0) {
      try await reloadHistory(client, replacing: false)
    }
  }

  /// Drops task snapshots of conversations the directory no longer lists (trashed or purged).
  private func pruneTasks() {
    taskSnapshots.prune(keeping: Set(directory.conversations.map(\.id)))
  }

  private func applyTransient(_ envelope: EventEnvelope, client: MemoshiClient) async throws {
    taskInspector.observe(envelope)
    guard recovery == nil, envelope.scope.conversationId?.rawValue == chat?.id.rawValue,
      historyAsOf.admits(envelope.after ?? 0),
      case .messageDelta(let delta) = envelope.event, delta.channel == .text,
      let taskID = envelope.scope.taskId, let chat
    else { return }
    if taskID != task?.id {
      let snapshot = try await client.call(TasksGet.self, .init(taskId: taskID))
      record(snapshot)
      guard [.queued, .running, .waiting].contains(snapshot.task.status),
        recordRootTask(snapshot, expected: taskID)
      else { return }
    }
    guard taskID == task?.id,
      task.map({ [.queued, .running, .waiting].contains($0.status) }) == true
    else { return }
    noteDelta(taskID)
    if messages.contains(where: { $0.id == delta.messageId }) { return }
    switch try applyLiveTextDelta(delta, chatID: chat.id, taskID: taskID, ts: envelope.ts) {
    case .applied, .ignored:
      break
    case .needsReload:
      try await reloadHistory(client, replacing: false)
    }
  }

  /// Outcome of applying a live text delta to `live`.
  enum LiveDeltaOutcome: Equatable { case applied, ignored, needsReload }

  /// Applies a client status update, tracking reconnects and helper restarts. Exposed internally
  /// so unit tests exercise reconnect state transitions without launching a daemon.
  func observeStatus(state: ClientConnectionState, hello: SystemHelloResult?) {
    // Status updates may coalesce; a new hello identity still reveals every reconnect.
    if let hello, hello.connectionId != lastConnectionID {
      lastConnectionID = hello.connectionId
      connectionCount += 1
      // A restarted helper starts with an empty in-memory model catalog. Replay alone does
      // not run discovery again, so the explicitly configured providers are re-read.
      if let previous = lastDaemon, previous != hello.daemon {
        needsModelDiscovery = true
      }
      lastDaemon = hello.daemon
    }
    connection = state
    reviews.connectionChanged(isConnected: state == .connected)
    folders.connectionChanged(state)
    if state != .connected {
      appliedFocus = nil
    }
  }

  private func handleStatusUpdate(_ status: ClientStatus, client: MemoshiClient) async {
    observeStatus(state: status.state, hello: status.hello)
    if status.state == .connected {
      if folders.needsReconnectSnapshot {
        // A failed folder read is reported in the Folders sheet; chat and review continue.
        do {
          try await folders.reload(client, minimumSeq: status.lastAppliedSeq ?? 0)
        } catch {}
      }
      if needsModelDiscovery, !providerSetup.providers.isEmpty {
        needsModelDiscovery = false
        do { try await providerSetup.reloadModels() } catch {
          problem = Self.message(error)
        }
      }
      await updateFocus()
    }
  }

  /// Internal visibility for unit tests verifying reconnect model-discovery flags.
  var isModelDiscoveryPending: Bool { needsModelDiscovery }

  /// Internal visibility for unit tests seeding live state before delta frames arrive.
  func seedLiveStateForTesting(_ state: ChatLiveState?) { live = state }

  /// Appends a live text delta to `live`, preserving `resumedAfterInterruption` only for the
  /// matching task.
  func applyLiveTextDelta(
    _ delta: MessageDeltaPayload, chatID: ConversationID, taskID: TaskID, ts: Int64
  ) throws -> LiveDeltaOutcome {
    var partial = live?.message
    // A turn continued after a restart keeps its mark on the reply it streams again.
    let resumed = live?.taskId == taskID ? live?.resumedAfterInterruption : nil
    if partial?.id != delta.messageId {
      if delta.offsetUtf16 != 0 { return .needsReload }
      partial = ChatMessage(
        id: delta.messageId, conversationId: try ConversationID(chatID.rawValue),
        taskId: taskID, role: .bot, content: [.text(TextPart(text: ""))], createdAt: ts,
        resumedAfterInterruption: resumed)
    }
    guard var message = partial else { return .ignored }
    let text = Self.text(message)
    let length = Int64(text.utf16.count)
    guard delta.offsetUtf16 == length else {
      // Replays or missing frames are resolved from Pi, not appended twice or sliced by Character.
      if delta.offsetUtf16 < length { return .ignored }
      return .needsReload
    }
    message.content = [.text(TextPart(text: text + delta.text))]
    live = ChatLiveState(taskId: taskID, message: message, resumedAfterInterruption: resumed)
    return .applied
  }

  private func reloadHistory(_ client: MemoshiClient, replacing: Bool) async throws {
    guard let chat else { return }
    historyRequest += 1
    let request = historyRequest
    let page = try await client.call(ChatsHistory.self, .init(chatId: chat.id))
    var choices: [CardID: [ResumeAction]] = [:]
    for step in page.recovery?.steps ?? [] {
      guard let card = step.step?.cardId else { continue }
      choices[card] = try await client.call(CardsGet.self, .init(cardId: card)).card.resumeChoices
    }
    guard self.chat?.id == chat.id, request >= appliedHistoryRequest,
      historyAsOf.admits(page.asOf.seq)
    else { return }
    appliedHistoryRequest = request
    if replacing {
      messages = page.items
      nextBefore = page.nextBefore
    } else {
      let freshIDs = Set(page.items.map(\.id))
      let oldest = page.items.first?.id.rawValue
      // Keep only previously loaded pages older than the fresh window. This avoids resurrecting
      // a stale in-flight row while preserving intentional history pagination.
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
    historyAsOf.advance(to: page.asOf.seq)
    if let key = pending?.requestId,
      messages.contains(where: { $0.requestId == key })
        || queued.contains(where: { $0.requestId == key })
    {
      confirmPending()
    }
    let latestTaskID =
      page.recovery?.steps.first?.taskId ?? page.live?.taskId ?? page.items.last?.taskId
    if let latestTaskID {
      let snapshot = try await client.call(TasksGet.self, .init(taskId: latestTaskID))
      guard self.chat?.id == chat.id else { return }
      record(snapshot)
      recordRootTask(snapshot, expected: latestTaskID)
    } else {
      task = nil
      taskAsOf.replace(with: page.asOf.seq)
    }
    if !isWorking {
      isStopping = false
      stopIntent = nil
    }
  }

  private var desiredFocus: [ConversationID] {
    var targets = Set<ConversationID>()
    if !visibleOwners.isEmpty, let chat { targets.insert(chat.id) }
    if tasksVisible, let conversation = taskInspector.conversationID {
      targets.insert(conversation)
    }
    return targets.sorted { $0.rawValue < $1.rawValue }
  }

  private func updateFocus() async {
    guard let client, connection == .connected, !updatingFocus else { return }
    updatingFocus = true
    defer { updatingFocus = false }
    do {
      while connection == .connected {
        let desired = desiredFocus
        guard appliedFocus != desired else { return }
        try await client.setFocus(desired)
        appliedFocus = desired
      }
    } catch ClientError.subscriptionBusy {
      // Connection completion publishes another status; apply focus after its lifecycle call ends.
    } catch { problem = Self.message(error) }
  }

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

  private func performSend(_ params: ChatsSendParams) {
    guard let client, !isSending else { return }
    isSending = true
    problem = nil
    refusedSendReason = nil
    // A retry of the same uncertain request keeps timing from the original Send.
    if lastTurn?.requestId != params.requestId {
      lastTurn = TurnTiming(requestId: params.requestId, started: .now)
      earlyDelta = nil
    }
    actionTask = Task { [weak self, client] in
      guard let self else { return }
      defer {
        self.isSending = false
        self.actionTask = nil
      }
      do {
        let admitted = try await client.call(ChatsSend.self, params)
        self.noteAdmitted(admitted, requestId: params.requestId)
        self.confirmPending()
      } catch {
        // The rule is AppCore's, shared with the in-process Chat and tested there.
        switch SendFailure(failure: error, isSaved: self.pending != nil) {
        case .refused:
          // Nothing was delivered. Preserve the editable draft.
          self.problem = Self.message(error)
          self.clearRefusedPending()
        case .refusedAsSaved:
          self.refusedSendReason = Self.message(error)
        case .uncertain:
          self.problem = Self.message(error)
        }
        return
      }
      do { try await self.reloadHistory(client, replacing: false) } catch {
        self.problem = Self.message(error)
      }
    }
  }

  static func text(_ message: ChatMessage) -> String {
    message.content.reduce(into: "") { result, part in
      if case .text(let text) = part { result.append(text.text) }
    }
  }

  private static func message(_ error: any Error) -> String {
    if let error = error as? RPCError { return error.message }
    if let error = error as? ClientError {
      switch error {
      case .notSynchronized: return String(localized: "Conversation state is still synchronizing.")
      case .requestTimedOut:
        return String(
          localized:
            "The request timed out. Delivery may already have occurred; reconnect or retry the same message."
        )
      default:
        return String(
          localized:
            "The daemon connection changed. Reconnect to reload authoritative conversation state.")
      }
    }
    return String(
      localized: "The operation could not be completed. No substitute model or reply was used.")
  }
}
