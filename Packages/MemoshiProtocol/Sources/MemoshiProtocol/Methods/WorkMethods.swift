/// `tasks.get`: one task and its children (protocol.md §5.5).
public enum TasksGet: RPCMethod {
  /// The task.
  public typealias Params = TasksGetParams
  /// The task, its children and the snapshot position.
  public typealias Result = TasksGetResult
  /// `tasks.get`.
  public static let name = "tasks.get"
  /// Read-only.
  public static let isMutating = false
}

/// `tasks.abort`: stop a task; the abort runs bottom-up (protocol.md §5.5).
public enum TasksAbort: RPCMethod {
  /// The task.
  public typealias Params = TasksAbortParams
  /// The task after the abort was requested.
  public typealias Result = TasksAbortResult
  /// `tasks.abort`.
  public static let name = "tasks.abort"
  /// Requests cancellation.
  public static let isMutating = true
}

/// `cards.respond`: the only method that decides a card (protocol.md §5.6).
public enum CardsRespond: RPCMethod {
  /// The answer.
  public typealias Params = CardsRespondParams
  /// The resolved card.
  public typealias Result = CardsRespondResult
  /// `cards.respond`.
  public static let name = "cards.respond"
  /// Decides a card.
  public static let isMutating = true
}

/// `approvals.list`: approvals, read-only; decisions use `cards.respond` (protocol.md §5.6).
public enum ApprovalsList: RPCMethod {
  /// The filter and the page.
  public typealias Params = ApprovalsListParams
  /// One page of approvals.
  public typealias Result = ApprovalsListResult
  /// `approvals.list`.
  public static let name = "approvals.list"
  /// Read-only.
  public static let isMutating = false
}

/// The parameters of `tasks.get`.
public struct TasksGetParams: Codable, Hashable, Sendable {
  /// The task.
  public var taskId: TaskID

  /// Creates get parameters.
  public init(taskId: TaskID) {
    self.taskId = taskId
  }
}

/// The result of `tasks.get`.
public struct TasksGetResult: Codable, Hashable, Sendable {
  /// The task.
  public var task: MemoshiTask
  /// Its child tasks and subagents.
  public var children: [MemoshiTask]
  /// The snapshot position.
  public var asOf: AsOf

  /// Creates a get result.
  public init(task: MemoshiTask, children: [MemoshiTask], asOf: AsOf) {
    self.task = task
    self.children = children
    self.asOf = asOf
  }
}

/// The parameters of `tasks.abort`.
public struct TasksAbortParams: Codable, Hashable, Sendable, IdempotentParams {
  /// The client's idempotency key.
  public var requestId: ULID
  /// The task to stop.
  public var taskId: TaskID
  /// Where the request came from; absent means `ui`.
  public var surface: RequestSurface?

  /// Creates abort parameters.
  public init(requestId: ULID, taskId: TaskID, surface: RequestSurface? = nil) {
    self.requestId = requestId
    self.taskId = taskId
    self.surface = surface
  }
}

/// The result of `tasks.abort`.
public struct TasksAbortResult: Codable, Hashable, Sendable {
  /// The task after the abort was requested.
  public var task: MemoshiTask
  /// The highest `seq` the request wrote.
  public var writtenSeq: Int64
  /// `true` when this is the stored result of an earlier request with the same `requestId`.
  public var replayed: Bool?

  /// Creates an abort result.
  public init(task: MemoshiTask, writtenSeq: Int64, replayed: Bool? = nil) {
    self.task = task
    self.writtenSeq = writtenSeq
    self.replayed = replayed
  }
}

/// The parameters of `cards.respond`.
public struct CardsRespondParams: Codable, Hashable, Sendable, IdempotentParams {
  /// The client's idempotency key.
  public var requestId: ULID
  /// The card.
  public var cardId: CardID
  /// One of the card's declared actions, such as `allow_once`, or a generated card's button ID.
  public var action: String
  /// The action's payload, such as `always_allow`'s `{scope, expiresInDays, pattern?}`.
  public var payload: JSONValue?
  /// For a T4 or T5 decision: this device's proof that it checked its owner.
  public var deviceAuth: DeviceAuthProof?
  /// Where the request came from; absent means `ui`.
  public var surface: RequestSurface?

  /// Creates respond parameters.
  public init(
    requestId: ULID, cardId: CardID, action: String, payload: JSONValue? = nil,
    deviceAuth: DeviceAuthProof? = nil, surface: RequestSurface? = nil
  ) {
    self.requestId = requestId
    self.cardId = cardId
    self.action = action
    self.payload = payload
    self.deviceAuth = deviceAuth
    self.surface = surface
  }
}

/// The result of `cards.respond`.
public struct CardsRespondResult: Codable, Hashable, Sendable {
  /// The card after the answer.
  public var card: Card
  /// What the answer did to the card's approval.
  public var effects: ApprovalEffect?
  /// The highest `seq` the request wrote.
  public var writtenSeq: Int64
  /// `true` when the runner of the card's conversation could not be reached: the answer waits
  /// until the card expires (D73).
  public var queued: Bool?
  /// `true` when this is the stored result of an earlier request with the same `requestId`.
  public var replayed: Bool?

  /// Creates a respond result.
  public init(
    card: Card, effects: ApprovalEffect? = nil, writtenSeq: Int64, queued: Bool? = nil,
    replayed: Bool? = nil
  ) {
    self.card = card
    self.effects = effects
    self.writtenSeq = writtenSeq
    self.queued = queued
    self.replayed = replayed
  }
}

/// What answering an approval or purchase card did to its approval.
public struct ApprovalEffect: Codable, Hashable, Sendable {
  /// The approval.
  public var approvalId: ApprovalID
  /// Its new state.
  public var status: ApprovalStatus
  /// When allowed: for once, the task, or always.
  public var scope: ApprovalScope?
  /// The `tool_rule` grant created by `task` or `always`.
  public var grantId: GrantID?

  /// Creates an approval effect.
  public init(
    approvalId: ApprovalID, status: ApprovalStatus, scope: ApprovalScope? = nil,
    grantId: GrantID? = nil
  ) {
    self.approvalId = approvalId
    self.status = status
    self.scope = scope
    self.grantId = grantId
  }
}

/// The parameters of `approvals.list`.
public struct ApprovalsListParams: Codable, Hashable, Sendable {
  /// Only approvals in this state.
  public var status: ApprovalStatus?
  /// Only this bot's approvals.
  public var botId: BotID?
  /// Where the previous page ended.
  public var cursor: String?
  /// The page size, 1 to 200.
  public var limit: PageLimit

  /// Creates list parameters.
  public init(
    status: ApprovalStatus? = nil, botId: BotID? = nil, cursor: String? = nil, limit: PageLimit
  ) {
    self.status = status
    self.botId = botId
    self.cursor = cursor
    self.limit = limit
  }
}

/// The result of `approvals.list`.
public struct ApprovalsListResult: Codable, Hashable, Sendable {
  /// One page of approvals.
  public var items: [Approval]
  /// Where the next page starts; absent on the last page.
  public var nextCursor: String?
  /// The snapshot position.
  public var asOf: AsOf

  /// Creates a list result.
  public init(items: [Approval], nextCursor: String? = nil, asOf: AsOf) {
    self.items = items
    self.nextCursor = nextCursor
    self.asOf = asOf
  }
}
