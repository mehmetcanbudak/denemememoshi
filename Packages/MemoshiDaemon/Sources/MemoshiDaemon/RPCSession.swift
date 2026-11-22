import Foundation
import MemoshiProtocol
import MemoshiRuntime
import MemoshiStore
import MemoshiTransport

/// The authenticated carrier as one session uses it; `LocalConnection` in the running daemon.
protocol SessionConnection: Sendable {
  var peer: PeerIdentity { get }
  var messages: AsyncThrowingStream<Data, any Error> { get }
  func send(_ data: Data) async throws
  func close(code: Int, reason: String) async
}

extension LocalConnection: SessionConnection {}

actor RPCSession {
  let connection: any SessionConnection
  let token: HelloToken
  let store: Store
  let info: DaemonInfo
  let schemaHash: String
  let capabilities: [Capability]
  let daemonStatus: @Sendable () async throws -> SystemStatusResult
  let runtime: RuntimeAdapter?
  let claimHostChannel: @Sendable () async -> Bool
  let didOpenHost: @Sendable (String, [Capability]) async throws -> Void
  /// Waits out a host call's deadline: `Task.sleep` in the daemon; tests release it explicitly.
  let hostCallSleep: @Sendable (Duration) async throws -> Void
  let codec = JSONRPCCodec()
  let encoder = ProtocolCoding.makeEncoder()
  let decoder = ProtocolCoding.makeDecoder(strict: true)
  var authenticated = false
  var closed = false
  var negotiated: Set<Capability> = []
  var focus: Set<ConversationID> = []
  var subscribed = false
  var generation: UInt64 = 0
  var liveAfter: Int64 = 0
  var lastSent: Int64 = 0
  var replaying = false
  var flushing = false
  /// Event frames not yet written (protocol.md §11).
  var queue = EventSendQueue()
  var helloDeadline: Task<Void, Never>?
  var readerTask: Task<Void, Never>?
  var replayTask: Task<Void, Never>?
  var flushTask: Task<Void, Never>?
  var responseWaiters: [CheckedContinuation<Void, Never>] = []
  var hostReady = false
  var nextHostID: UInt64 = 0
  var hostCalls: [String: PendingHostCall] = [:]
  var canceledHostCalls: Set<String> = []
  struct InFlightRequest {
    let id: JSONRPCID
    var work: Task<Void, Never>?
    var canceled = false
    var answered = false
  }

  @TaskLocal static var currentRequestToken: UUID?

  var requestJobs: [UUID: Task<Void, Never>] = [:]
  var inFlightRequests: [UUID: InFlightRequest] = [:]
  var inFlightRequestIDs: [String: UUID] = [:]
  var requestsInFlight = 0

  init(
    connection: any SessionConnection, token: HelloToken, store: Store, info: DaemonInfo,
    schemaHash: String, capabilities: [Capability], runtime: RuntimeAdapter?,
    status: @escaping @Sendable () async throws -> SystemStatusResult,
    claimHost: @escaping @Sendable () async -> Bool,
    hostOpened: @escaping @Sendable (String, [Capability]) async throws -> Void,
    hostCallSleep: @escaping @Sendable (Duration) async throws -> Void = {
      try await Task.sleep(for: $0)
    }
  ) {
    self.connection = connection
    self.token = token
    self.store = store
    self.info = info
    self.schemaHash = schemaHash
    self.capabilities = capabilities
    self.daemonStatus = status
    self.runtime = runtime
    self.claimHostChannel = claimHost
    self.didOpenHost = hostOpened
    self.hostCallSleep = hostCallSleep
  }

  func run() async {
    helloDeadline = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(5)) } catch { return }
      await self?.expireHello()
    }
    do {
      for try await data in connection.messages {
        guard closed == false else { break }
        try await receive(data)
      }
      await close(code: 1000, reason: "connection_closed")
    } catch {
      await close(code: 4500, reason: "connection_failed")
    }
  }

  func close(code: Int, reason: String) async {
    guard closed == false else { return }
    closed = true
    hostReady = false
    failHostCalls()
    for task in requestJobs.values { task.cancel() }
    for request in inFlightRequests.values { request.work?.cancel() }
    inFlightRequests.removeAll()
    inFlightRequestIDs.removeAll()
    cancelSubscription()
    helloDeadline?.cancel()
    helloDeadline = nil
    await connection.close(code: code, reason: reason)
  }

  private func expireHello() async {
    if authenticated == false { await close(code: 4400, reason: "hello_timeout") }
  }

  private func receive(_ data: Data) async throws {
    if case .response(let id) = try? codec.inspect(data) {
      try await receiveHostResponse(data, id: id)
      return
    }
    let frame: RPCFrame
    do {
      frame = try decoder.decode(RPCFrame.self, from: data)
    } catch RPCFrame.FrameError.invalidBatch {
      if authenticated == false {
        await close(code: 4400, reason: "hello_required")
      } else {
        try await sendError(id: nil, details: .invalidRequest, message: "Invalid request batch.")
      }
      return
    } catch {
      if authenticated == false {
        await close(code: 4400, reason: "hello_required")
      } else {
        try await sendError(id: nil, details: .parseError, message: "Invalid JSON.")
      }
      return
    }
    if authenticated == false {
      guard frame.isBatch == false, let request = frame.requests.first,
        case .hello(let hello) = request.operation, let id = request.id
      else {
        await close(code: 4400, reason: "hello_required")
        return
      }
      try await handshake(hello, id: id)
      return
    }
    await dispatchRequests(frame)
  }

  private func handshake(_ hello: SystemHelloParams, id: JSONRPCID) async throws {
    guard DaemonToken.matches(hello.token, token) else {
      try await sendError(id: id, details: .unauthorized, message: "Unauthorized.")
      await close(code: 4401, reason: "unauthorized")
      return
    }
    guard hello.client.role == .app,
      connection.peer.signingIdentifier == DaemonConfiguration.appIdentifier
    else {
      try await sendError(id: id, details: .forbidden, message: "Client role is not permitted.")
      await close(code: 4403, reason: "role_mismatch")
      return
    }
    let range = hello.protocolRange
    guard range.min > 0, range.min <= range.max else {
      try await invalidParams(id)
      await close(code: 4400, reason: "invalid_protocol_range")
      return
    }
    let minimum = max(range.min, ProtocolVersion.minimum)
    let maximum = min(range.max, ProtocolVersion.current)
    guard minimum <= maximum else {
      let details = VersionMismatchDetails(
        daemon: ProtocolRange(min: ProtocolVersion.minimum, max: ProtocolVersion.current),
        client: range, action: range.min > ProtocolVersion.current ? .restartDaemon : .updateApp)
      try await sendError(
        id: id, details: .versionMismatch(details), message: "No common protocol version.")
      await close(code: 4409, reason: "version_mismatch")
      return
    }
    authenticated = true
    helloDeadline?.cancel()
    helloDeadline = nil
    negotiated = Set(capabilities).intersection(hello.capabilities)
    if negotiated.contains(where: { $0.rawValue == "host.keychain.v1" }),
      !(await claimHostChannel())
    {
      negotiated = negotiated.filter { $0.rawValue != "host.keychain.v1" }
    }
    let bounds = try await store.replayBounds()
    let result = try SystemHelloResult(
      connectionId: "conn-" + IDGenerator.shared.next().rawValue, daemon: info,
      protocolVersion: maximum, capabilities: capabilities.filter { negotiated.contains($0) },
      logId: store.logID, head: bounds.head, minRetainedSeq: bounds.minRetainedSeq,
      serverTime: IDGenerator.nowMilliseconds(), schemaHash: schemaHash,
      limits: ConnectionLimits(
        maxInboundBytes: 1_048_576, maxOutboundFrameBytes: 4_194_304,
        maxBatchEvents: 256, maxInFlightRequests: 64, maxFocus: 8))
    try await send(SystemHello.self, id: id, result: result)
    if negotiated.contains(where: { $0.rawValue == "host.keychain.v1" }) {
      hostReady = true
      try await didOpenHost(hello.client.version, result.capabilities)
    }
  }

  func dispatchRequests(_ frame: RPCFrame) async {
    guard !closed else { return }
    // A notification, such as the app's `system.cancel`, is not a request: it gets no answer
    // and holds no slot, so a full set of slots never drops one (protocol.md §4, §11).
    var admitted: [(request: RPCRequest, token: UUID?)] = []
    var overflow: [RPCRequest] = []
    for request in frame.requests {
      switch request.operation {
      case .cancel(let id):
        cancelRequest(id)
      case .notification:
        break
      default:
        // protocol.md §11: a request over the in-flight limit is answered `rate_limited`.
        // Closing is reserved for event backpressure and would drop unrelated responses.
        if requestsInFlight < 64 {
          requestsInFlight += 1
          if let id = request.id {
            let token = UUID()
            inFlightRequests[token] = InFlightRequest(id: id)
            inFlightRequestIDs[id.rawValue] = token
            admitted.append((request, token))
          } else {
            admitted.append((request, nil))
          }
        } else {
          overflow.append(request)
        }
      }
    }
    if !admitted.isEmpty {
      let batchToken = UUID()
      requestJobs[batchToken] = Task<Void, Never> { [weak self] in
        await self?.runRequests(admitted, token: batchToken)
      }
    }
    do {
      for request in overflow {
        try await sendError(
          id: request.id, details: .rateLimited(RateLimitedDetails(retryAfterMs: 1_000)),
          message: "Too many requests are in flight.")
      }
    } catch {
      await close(code: 4500, reason: "request_failed")
    }
  }

  private func cancelRequest(_ id: JSONRPCID) {
    guard let token = inFlightRequestIDs.removeValue(forKey: id.rawValue) else { return }
    inFlightRequests[token]?.canceled = true
    inFlightRequests[token]?.work?.cancel()
  }

  private func runRequests(_ requests: [(request: RPCRequest, token: UUID?)], token: UUID) async {
    var processed = 0
    for item in requests {
      guard !Task.isCancelled, !closed else { break }
      processed += 1
      if let requestToken = item.token {
        if inFlightRequests[requestToken]?.canceled != true {
          let work = Task<Void, Never> { [weak self] in
            await RPCSession.$currentRequestToken.withValue(requestToken) {
              await self?.executeRequest(item.request, token: requestToken)
            }
          }
          inFlightRequests[requestToken]?.work = work
          await work.value
        }
        if let state = inFlightRequests.removeValue(forKey: requestToken) {
          if inFlightRequestIDs[state.id.rawValue] == requestToken {
            inFlightRequestIDs.removeValue(forKey: state.id.rawValue)
          }
          if state.canceled, !state.answered, !closed {
            do {
              if let method = item.request.method.flatMap(MethodRegistry.method(named:)),
                Self.followsWrittenEvents(method)
              {
                try await sendWrittenEvents()
              }
              try await sendError(
                id: state.id, details: .canceled, message: "Request was canceled.")
            } catch {
              await close(code: 4500, reason: "request_failed")
            }
          }
        }
      } else {
        do {
          try await handle(item.request)
        } catch {
          await close(code: 4500, reason: "request_failed")
        }
      }
      requestsInFlight -= 1
    }
    // Release slots and tracking for any tail items skipped because the session closed.
    let remaining = requests.dropFirst(processed)
    for item in remaining {
      if let requestToken = item.token,
        let state = inFlightRequests.removeValue(forKey: requestToken),
        inFlightRequestIDs[state.id.rawValue] == requestToken
      {
        inFlightRequestIDs.removeValue(forKey: state.id.rawValue)
      }
    }
    requestsInFlight -= remaining.count
    requestJobs.removeValue(forKey: token)
  }

  private func executeRequest(_ request: RPCRequest, token: UUID) async {
    do {
      try await handle(request)
    } catch is CancellationError {
      // Canceled by `system.cancel` (answered by `runRequests`) or by `close`.
    } catch {
      if inFlightRequests[token]?.canceled == true { return }
      await close(code: 4500, reason: "request_failed")
    }
  }

  func handle(_ request: RPCRequest) async throws {
    switch request.operation {
    case .notification, .cancel: return
    default: break
    }
    guard let id = request.id else {
      try await sendError(id: nil, details: .invalidRequest, message: "Invalid request.")
      return
    }
    do {
      switch request.operation {
      case .hello:
        try await sendError(id: id, details: .invalidState, message: "Already authenticated.")
      case .ping:
        try await send(
          SystemPing.self, id: id,
          result: SystemPingResult(serverTime: IDGenerator.nowMilliseconds()))
      case .status:
        try await send(SystemStatus.self, id: id, result: try await daemonStatus())
      case .subscribe(let params):
        try await subscribe(params, id: id)
      case .focus(let params):
        guard hasFocusCapability else {
          try await sendError(
            id: id, details: .capabilityMissing, message: "Focus was not negotiated.")
          return
        }
        focus = Set(params.conversationIds.elements)
        try await send(EventsFocus.self, id: id, result: EmptyParams())
      case .unsubscribe:
        cancelSubscription()
        try await send(EventsUnsubscribe.self, id: id, result: EmptyParams())
      case .bots(let params):
        try await send(BotsList.self, id: id, result: try await requireRuntime().listBots(params))
      case .bot(let params):
        try await send(BotsGet.self, id: id, result: try await requireRuntime().bot(params))
      case .createBot(let params):
        try await send(
          BotsCreate.self, id: id, result: try await requireRuntime().createBot(params))
      case .updateBot(let params):
        try await send(
          BotsUpdate.self, id: id, result: try await requireRuntime().updateBot(params))
      case .createSession(let params):
        try await send(
          SessionsCreate.self, id: id, result: try await requireRuntime().createSession(params))
      case .deleteSession(let params):
        try await send(
          SessionsDelete.self, id: id, result: try await requireRuntime().deleteSession(params))
      case .trash:
        try await send(TrashList.self, id: id, result: try await requireRuntime().listTrash())
      case .restoreSession(let params):
        try await send(
          TrashRestore.self, id: id, result: try await requireRuntime().restoreSession(params))
      case .emptyTrash(let params):
        try await send(
          TrashEmpty.self, id: id, result: try await requireRuntime().emptyTrash(params))
      case .grants(let params):
        try await send(
          BotsGrantsList.self, id: id,
          result: try await requireFolderGrants().listFolderGrants(params))
      case .updateGrant(let params):
        try await send(
          BotsGrantsUpdate.self, id: id,
          result: try await requireFolderGrants().updateFolderGrant(params))
      case .revokeGrant(let params):
        try await send(
          BotsGrantsRevoke.self, id: id,
          result: try await requireFolderGrants().revokeFolderGrant(params))
      case .chats:
        try await send(ChatsList.self, id: id, result: try await requireRuntime().listChats())
      case .history(let params):
        try await send(
          ChatsHistory.self, id: id, result: try await requireRuntime().history(params))
      case .send(let params):
        try await send(ChatsSend.self, id: id, result: try await requireRuntime().send(params))
      case .abort(let params):
        try await send(ChatsAbort.self, id: id, result: try await requireRuntime().abort(params))
      case .providers:
        try await send(
          ModelsProvidersList.self, id: id, result: try await requireRuntime().providers())
      case .configure(let params):
        try await send(
          ModelsProvidersConfigure.self, id: id,
          result: try await requireRuntime().configure(params))
      case .models:
        try await send(ModelsList.self, id: id, result: try await requireRuntime().modelsList())
      case .task(let params):
        guard let task = try await store.taskDetails(params.taskId) else {
          try await sendError(id: id, details: .notFound, message: "Task not found.")
          return
        }
        try await send(TasksGet.self, id: id, result: task)
      case .abortTask(let params):
        try await send(
          TasksAbort.self, id: id, result: try await requireRuntime().abortTask(params))
      case .taskGraph(let params):
        try await send(
          TasksGraph.self, id: id, result: try await requireRuntime().taskGraph(params))
      case .taskHistory(let params):
        try await send(
          TasksHistory.self, id: id, result: try await requireRuntime().taskHistory(params))
      case .approvals(let params):
        let cursor: ApprovalID?
        do { cursor = try params.cursor.map(ApprovalID.init) } catch {
          try await invalidParams(id)
          return
        }
        let page = try await store.approvalsPage(
          status: params.status, botID: params.botId, after: cursor, limit: params.limit)
        try await send(ApprovalsList.self, id: id, result: page)
      case .cards(let params):
        let cursor: CardID?
        do { cursor = try params.cursor.map(CardID.init) } catch {
          try await invalidParams(id)
          return
        }
        let page = try await store.cardsPage(
          conversationID: params.conversationId, status: params.status,
          after: cursor, limit: params.limit)
        try await send(CardsList.self, id: id, result: page)
      case .card(let params):
        let snapshot = try await store.card(params.cardId)
        guard let card = snapshot.value else {
          try await sendError(id: id, details: .notFound, message: "Card not found.")
          return
        }
        try await send(
          CardsGet.self, id: id, result: CardsGetResult(card: card, asOf: snapshot.asOf))
      case .respondToCard(let params):
        try await send(
          CardsRespond.self, id: id, result: try await requireRuntime().respondToCard(params))
      case .invalidRequest:
        try await sendError(id: id, details: .invalidRequest, message: "Invalid request.")
      case .invalidParams:
        try await invalidParams(id)
      case .unsupported:
        try await sendError(id: id, details: .methodNotFound, message: "Method is not implemented.")
      case .notification, .cancel:
        break
      }
    } catch {
      try await refuse(request, id: id, for: error)
    }
  }

  /// protocol.md §4: a refusal follows the events its handler committed, as a result does.
  /// `cards.respond` durably ends an approval it finds expired or no longer granted, and only
  /// then refuses. A failure without a safe answer ends the connection instead.
  private func refuse(_ request: RPCRequest, id: JSONRPCID, for error: any Error) async throws {
    if error is CancellationError,
      let token = Self.currentRequestToken, inFlightRequests[token]?.canceled == true
    {
      throw CancellationError()
    }
    guard let refusal = Self.refusal(for: error) else { throw error }
    if let method = request.method.flatMap(MethodRegistry.method(named:)),
      Self.followsWrittenEvents(method)
    {
      try await sendWrittenEvents()
    }
    try await sendError(id: id, details: refusal.data.details, message: refusal.message)
  }

  /// The fixed answer to a handler's failure, or nil when no answer is safe to send.
  private static func refusal(for error: any Error) -> RPCError? {
    switch error {
    case let error as FolderGrantError: folderGrantRefusal(error)
    case let error as SourceFolderAuthorityError: sourceFolderRefusal(error)
    case let error as SourcePathPolicyError: sourcePathRefusal(error)
    case let error as DaemonError where error == .notRunning:
      RPCError(message: "Daemon is stopping.", data: RPCErrorData(details: .shuttingDown))
    default: RuntimeRPCError.map(error)
    }
  }

  private func requireRuntime() throws -> RuntimeAdapter {
    guard let runtime else {
      throw RPCError(
        message: "Text chat is not enabled for this daemon.",
        data: RPCErrorData(details: .methodNotFound))
    }
    return runtime
  }

  var hasFocusCapability: Bool {
    negotiated.contains { $0.rawValue == "events.focus.v1" }
  }

  func send<Method: RPCMethod>(
    _ method: Method.Type, id: JSONRPCID, result: Method.Result
  ) async throws {
    let data = try encoder.encode(JSONRPCSuccessResponse<Method>(id: id, result: result))
    // Before the size check: a result too large to send is refused only after its events.
    if Self.followsWrittenEvents(Method.self) { try await sendWrittenEvents() }
    guard data.count <= 4_194_304 else {
      try await sendError(
        id: id, details: .payloadTooLarge,
        message: "Response exceeds the frame limit; request a smaller page.")
      return
    }
    try await sendResponseFrame(data)
  }

  /// protocol.md §4: on a subscribed connection the answer to a request that can write, its
  /// result or its refusal, follows the events it committed. `bots.grants.list` is read-only
  /// apart from durably ending grants whose deadline passed.
  static func followsWrittenEvents(_ method: any RPCMethod.Type) -> Bool {
    method.isMutating || method.name == BotsGrantsList.name
  }

  func sendError(id: JSONRPCID?, details: RPCErrorDetails, message: String) async throws {
    let error = RPCError(message: message, data: RPCErrorData(details: details))
    try await sendResponseFrame(encoder.encode(JSONRPCErrorResponse(id: id, error: error)))
  }

  private func sendResponseFrame(_ data: Data) async throws {
    if let token = Self.currentRequestToken {
      guard let state = inFlightRequests[token], !state.canceled, !state.answered else { return }
      inFlightRequests[token]?.answered = true
    }
    do {
      try await connection.send(data)
    } catch is CancellationError {
      if let token = Self.currentRequestToken, inFlightRequests[token]?.canceled == true {
        inFlightRequests[token]?.answered = false
      }
      throw CancellationError()
    }
  }

  func invalidParams(_ id: JSONRPCID) async throws {
    try await sendError(
      id: id,
      details: .invalidParams(
        InvalidParamsDetails(issues: [ParamIssue(path: "/params", message: "Invalid parameters.")])),
      message: "Parameters do not match the method.")
  }
}
