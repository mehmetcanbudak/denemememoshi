import Foundation
import MemoshiProtocol
import MemoshiStore

/// The iPhone and iPad engine host (D46, D78; 04-architecture §2.7). It composes the Store and
/// RuntimeAdapter memoshid composes, in the app's private container, and serves ``MemoshiAPI``
/// with Swift values: no JSON, socket, token or peer check. One store directory has one open
/// engine; a second open, from this process or another, is refused before it writes.
///
/// The app composition supplies no tools. A development composition may pass trusted
/// definitions, which the runtime's mandatory policy hooks govern exactly as on the Mac.
public actor InProcessEngine: MemoshiAPI {
  let store: Store
  let runtime: RuntimeAdapter
  private let feeds: InProcessEventFeeds
  private var isClosed = false

  private init(
    store: Store, tools: [RuntimeToolDefinition], extensions: RuntimeExtensionComposition
  ) {
    let feeds = InProcessEventFeeds()
    self.store = store
    self.feeds = feeds
    self.runtime = RuntimeAdapter(
      store: store, tools: tools, extensions: extensions,
      publishLive: { event in
        try await InProcessEngine.publishLive(event, store: store, feeds: feeds)
      })
  }

  /// Opens the store and starts the runtime without contacting a provider. Call ``resume()``
  /// once a consumer is attached, as memoshid resumes once it listens.
  public static func open(
    directory: URL, tools: [RuntimeToolDefinition] = [],
    extensions: RuntimeExtensionComposition = .none
  ) async throws -> InProcessEngine {
    let engine = InProcessEngine(
      store: try Store(directory: directory), tools: tools, extensions: extensions)
    do {
      try await engine.start()
    } catch {
      try? await engine.close()
      throw error
    }
    return engine
  }

  private func start() async throws {
    try await runtime.start()
  }

  /// Resumes unfinished turns. A turn whose model is still unknown stays paused until a later
  /// `models.list` discovers it; nothing is substituted.
  public func resume() async throws {
    guard !isClosed else { throw RuntimeError.stopping }
    try await runtime.resume()
  }

  /// Closes the runtime, which stops no work (D139), and SQLite before ending every event
  /// subscription. A reply still streaming continues after the next open.
  public func close() async throws {
    guard !isClosed else { return }
    isClosed = true
    var failure: (any Error)?
    do { try await runtime.close() } catch { failure = error }
    do { try await store.close() } catch { failure = failure ?? error }
    feeds.finish()
    if let failure { throw failure }
  }

  /// Subscribes before the caller reads any snapshot, so the snapshots cover `head` and the
  /// feed carries everything after it.
  public func events() async throws -> InProcessEventFeed {
    guard !isClosed else { throw EventBusError.closed }
    return try feeds.subscribe(try await store.observeEvents(after: nil))
  }

  /// A new idempotency key from the canonical ULID generator, for a caller's mutating request.
  public nonisolated func requestID() throws -> ULID {
    try IDGenerator.shared.next()
  }

  /// Calls one method in process. Refusals are the same ``RPCError`` details and messages the
  /// Mac receives over its socket.
  public func call<Method: RPCMethod>(
    _ method: Method.Type, _ params: Method.Params
  ) async throws -> Method.Result {
    guard !isClosed else {
      throw Self.rpcError(.shuttingDown, "The engine is closed.")
    }
    do {
      return try await route(method, params)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw Self.rpcError(for: error)
    }
  }

  private func route<Method: RPCMethod>(
    _ method: Method.Type, _ params: Method.Params
  ) async throws -> Method.Result {
    let value: any Sendable
    switch (Method.name, params) {
    case (BotsList.name, let params as BotsListParams):
      value = try await runtime.listBots(params)
    case (BotsGet.name, let params as BotsGetParams):
      value = try await runtime.bot(params)
    case (BotsCreate.name, let params as BotsCreateParams):
      value = try await runtime.createBot(params)
    case (BotsUpdate.name, let params as BotsUpdateParams):
      value = try await runtime.updateBot(params)
    case (SessionsCreate.name, let params as SessionsCreateParams):
      value = try await runtime.createSession(params)
    case (SessionsDelete.name, let params as SessionsDeleteParams):
      value = try await runtime.deleteSession(params)
    case (TrashList.name, is EmptyParams):
      value = try await runtime.listTrash()
    case (TrashRestore.name, let params as TrashRestoreParams):
      value = try await runtime.restoreSession(params)
    case (TrashEmpty.name, let params as TrashEmptyParams):
      value = try await runtime.emptyTrash(params)
    case (ChatsList.name, is EmptyParams):
      value = try await runtime.listChats()
    case (ChatsHistory.name, let params as ChatsHistoryParams):
      value = try await runtime.history(params)
    case (ChatsSend.name, let params as ChatsSendParams):
      value = try await runtime.send(params)
    case (ChatsAbort.name, let params as ChatsAbortParams):
      value = try await runtime.abort(params)
    case (ModelsProvidersList.name, is EmptyParams):
      value = try await runtime.providers()
    case (ModelsProvidersConfigure.name, let params as ModelsProvidersConfigureParams):
      value = try await runtime.configure(params)
    case (ModelsList.name, is EmptyParams):
      value = try await runtime.modelsList()
    case (TasksGet.name, let params as TasksGetParams):
      guard let task = try await store.taskDetails(params.taskId) else {
        throw Self.rpcError(.notFound, "Task not found.")
      }
      value = task
    case (TasksAbort.name, let params as TasksAbortParams):
      value = try await runtime.abortTask(params)
    case (TasksGraph.name, let params as TasksGraphParams):
      value = try await runtime.taskGraph(params)
    case (TasksHistory.name, let params as TasksHistoryParams):
      value = try await runtime.taskHistory(params)
    case (ApprovalsList.name, let params as ApprovalsListParams):
      let cursor: ApprovalID?
      do { cursor = try params.cursor.map(ApprovalID.init) } catch {
        throw RuntimeError.invalidParams
      }
      value = try await store.approvalsPage(
        status: params.status, botID: params.botId, after: cursor, limit: params.limit)
    case (CardsList.name, let params as CardsListParams):
      let cursor: CardID?
      do { cursor = try params.cursor.map(CardID.init) } catch {
        throw RuntimeError.invalidParams
      }
      value = try await store.cardsPage(
        conversationID: params.conversationId, status: params.status, after: cursor,
        limit: params.limit)
    case (CardsGet.name, let params as CardsGetParams):
      let snapshot = try await store.card(params.cardId)
      guard let card = snapshot.value else { throw Self.rpcError(.notFound, "Card not found.") }
      value = CardsGetResult(card: card, asOf: snapshot.asOf)
    case (CardsRespond.name, let params as CardsRespondParams):
      value = try await runtime.respondToCard(params)
    default:
      // Handshakes, socket subscriptions and app-host calls have no in-process meaning; other
      // methods are not implemented by this host yet.
      throw Self.rpcError(.methodNotFound, "Method is not implemented.")
    }
    guard let result = value as? Method.Result else { throw RuntimeError.invalidParams }
    return result
  }

  /// The memoshid admission rule for live frames: only this device's UI-only events, stamped
  /// with the current durable head so a consumer can order them after their commit.
  static func publishLive(
    _ event: EventEnvelope, store: Store, feeds: InProcessEventFeeds
  ) async throws {
    guard event.seq == nil, event.cseq == nil, let payload = event.event.payload,
      type(of: payload).eventClass == .uiOnly, event.deviceId == store.deviceID
    else { throw StoreError.invalidCommit("Only local UI-only events may be published live") }
    var event = event
    event.after = try await store.replayBounds().head
    feeds.publish(event)
  }

  private static func rpcError(_ details: RPCErrorDetails, _ message: String) -> RPCError {
    RPCError(message: message, data: RPCErrorData(details: details))
  }

  static func rpcError(for error: any Error) -> RPCError {
    if let refusal = RuntimeRPCError.map(error) { return refusal }
    let incident = (try? IDGenerator.shared.next().rawValue) ?? "unavailable"
    return rpcError(
      .internalError(InternalErrorDetails(incidentId: incident)),
      "The engine could not complete the request.")
  }
}
