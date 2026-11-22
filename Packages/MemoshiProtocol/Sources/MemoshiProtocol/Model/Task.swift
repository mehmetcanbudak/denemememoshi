/// A durable unit of work inside a conversation (object-model.md §4.7).
public struct MemoshiTask: Codable, Hashable, Sendable, WireNamed {
  /// The task's ID.
  public var id: TaskID
  /// The conversation it belongs to.
  public var conversationId: ConversationID
  /// The parent, for child tasks and subagents.
  public var parentTaskId: TaskID?
  /// The bot doing the work.
  public var botId: BotID
  /// What kind of work this is.
  public var kind: TaskKind
  /// Why the work exists.
  public var origin: Origin
  /// Derived from the origin.
  public var regime: Regime
  /// A short title, at most 120 characters.
  public var title: Title
  /// The lifecycle state.
  public var status: TaskStatus
  /// What the task waits for; set iff `status` is `waiting`.
  public var waitingOn: WaitingOn?
  /// How it ended; set iff `status` is terminal.
  public var outcome: TaskOutcome?
  /// A one-line result, at most 500 characters.
  public var summary: Summary?
  /// Why it failed.
  public var error: TaskError?
  /// The routine whose run this is.
  public var routineId: RoutineID?
  /// The watch that started it.
  public var watchId: WatchID?
  /// The wake that started it.
  public var wakeId: WakeID?
  /// The handoff it serves.
  public var handoffId: HandoffID?
  /// For `app` tasks, the program call it carries.
  public var source: TaskSource?
  /// For runs, the fire time being served.
  public var scheduledFor: Int64?
  /// The idempotency key of its Pi submission, such as `run:rtn_…:<scheduledFor>`.
  public var requestId: String
  /// The budgets charged: routine, then bot, then group or handoff.
  public var budgetIds: [BudgetID]
  /// Usage rolled up from its usage records, children included.
  public var usage: Usage
  /// What a restart or an expired lease does to it.
  public var resumeMode: ResumeMode
  /// The step an interruption left unsettled.
  public var interruptedStep: InterruptedStep?
  /// When Stop was pressed.
  public var cancelRequestedAt: Int64?
  /// When it first ran.
  public var startedAt: Int64?
  /// When it ended.
  public var endedAt: Int64?
  /// When it was created.
  public var createdAt: Int64

  /// Creates a task record.
  public init(
    id: TaskID, conversationId: ConversationID, parentTaskId: TaskID? = nil, botId: BotID,
    kind: TaskKind, origin: Origin, regime: Regime, title: Title, status: TaskStatus,
    waitingOn: WaitingOn? = nil, outcome: TaskOutcome? = nil, summary: Summary? = nil,
    error: TaskError? = nil, routineId: RoutineID? = nil, watchId: WatchID? = nil,
    wakeId: WakeID? = nil, handoffId: HandoffID? = nil, source: TaskSource? = nil,
    scheduledFor: Int64? = nil, requestId: String, budgetIds: [BudgetID], usage: Usage,
    resumeMode: ResumeMode, interruptedStep: InterruptedStep? = nil,
    cancelRequestedAt: Int64? = nil, startedAt: Int64? = nil, endedAt: Int64? = nil,
    createdAt: Int64
  ) {
    self.id = id
    self.conversationId = conversationId
    self.parentTaskId = parentTaskId
    self.botId = botId
    self.kind = kind
    self.origin = origin
    self.regime = regime
    self.title = title
    self.status = status
    self.waitingOn = waitingOn
    self.outcome = outcome
    self.summary = summary
    self.error = error
    self.routineId = routineId
    self.watchId = watchId
    self.wakeId = wakeId
    self.handoffId = handoffId
    self.source = source
    self.scheduledFor = scheduledFor
    self.requestId = requestId
    self.budgetIds = budgetIds
    self.usage = usage
    self.resumeMode = resumeMode
    self.interruptedStep = interruptedStep
    self.cancelRequestedAt = cancelRequestedAt
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.createdAt = createdAt
  }

  /// `Task`: the object's name in object-model.md. The Swift type is `MemoshiTask` so it does
  /// not shadow Swift's `Task`.
  public static var wireName: String { "Task" }
}

/// Why a task failed: `{code, message, retryable}`.
public struct TaskError: Codable, Hashable, Sendable {
  /// A stable code, such as `steps` for a run cap.
  public var code: String
  /// A human-readable message.
  public var message: String
  /// Whether retrying may help.
  public var retryable: Bool

  /// Creates a task error.
  public init(code: String, message: String, retryable: Bool) {
    self.code = code
    self.message = message
    self.retryable = retryable
  }
}

/// The program call an `app` task carries (object-model.md §4.7 `source`).
public struct TaskSource: Codable, Hashable, Sendable {
  /// A live card or an App.
  public var kind: TaskSourceKind
  /// The program's ID.
  public var id: ProgramID
  /// The program's version.
  public var version: Int
  /// What started the call; it sets the task's origin.
  public var trigger: TaskTrigger
  /// The background job's name, for `trigger = job`.
  public var job: String?

  /// Creates a task source.
  public init(
    kind: TaskSourceKind, id: ProgramID, version: Int, trigger: TaskTrigger, job: String? = nil
  ) {
    self.kind = kind
    self.id = id
    self.version = version
    self.trigger = trigger
    self.job = job
  }
}

/// A step an interruption left unsettled (object-model.md §4.7 `interruptedStep`).
public struct InterruptedStep: Codable, Hashable, Sendable {
  /// The provider's call ID.
  public var toolCallId: String
  /// The tool's name.
  public var tool: String
  /// The outcome check's state.
  public var check: OutcomeCheckState
  /// The Resume card, when one is shown.
  public var cardId: CardID?
  /// When the step was interrupted.
  public var since: Int64

  /// Creates an interrupted step.
  public init(
    toolCallId: String, tool: String, check: OutcomeCheckState, cardId: CardID? = nil, since: Int64
  ) {
    self.toolCallId = toolCallId
    self.tool = tool
    self.check = check
    self.cardId = cardId
    self.since = since
  }
}

/// What kind of work a task is.
public enum TaskKind: OpenEnum {
  /// An interactive input until its answer.
  case turn
  /// Routine, wake, watch, webhook or connector-event work.
  case run
  case subagent
  /// Delegated work.
  case handoff
  /// One tool call from a live card or App.
  case app
  /// One user message in a Group (v1.1).
  case groupTurn
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .turn: "turn", .run: "run", .subagent: "subagent", .handoff: "handoff", .app: "app",
    .groupTurn: "group_turn",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// A task's lifecycle state (object-model.md §5.2).
public enum TaskStatus: OpenEnum {
  case queued
  case running
  case waiting
  case done
  case failed
  case canceled
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .queued: "queued", .running: "running", .waiting: "waiting", .done: "done",
    .failed: "failed", .canceled: "canceled",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// What a waiting task waits for.
public enum WaitingOn: OpenEnum {
  case approval
  /// A question, form or sign-in.
  case user
  case childTasks
  case takeover
  case computer
  /// A tool or local model on an unreachable device: "Waiting for your Mac".
  case device
  /// A budget stop, or a budget slice that cannot be renewed yet.
  case budget
  /// A provisional runner's external effect waits for the authority to confirm its lease.
  case authority
  /// An interrupted step's automatic check is running.
  case outcomeCheck
  /// An interrupted step waits behind a Resume card.
  case resume
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .approval: "approval", .user: "user", .childTasks: "child_tasks", .takeover: "takeover",
    .computer: "computer", .device: "device", .budget: "budget", .authority: "authority",
    .outcomeCheck: "outcome_check", .resume: "resume",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// How a terminal task ended.
public enum TaskOutcome: OpenEnum {
  case answered
  /// Finished with news.
  case updated
  /// Finished quietly.
  case noUpdate
  case failed
  case canceled
  case budgetStopped
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .answered: "answered", .updated: "updated", .noUpdate: "no_update", .failed: "failed",
    .canceled: "canceled", .budgetStopped: "budget_stopped",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// What a restart or an expired lease does to a task (D42).
public enum ResumeMode: OpenEnum {
  case auto
  case explicit
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.auto: "auto", .explicit: "explicit"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// The state of an interrupted step's outcome check (D51).
public enum OutcomeCheckState: OpenEnum {
  case pending
  case happened
  case notHappened
  case inconclusive
  /// The tool declares no outcome check.
  case none
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .pending: "pending", .happened: "happened", .notHappened: "not_happened",
    .inconclusive: "inconclusive", .none: "none",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// The kind of program an `app` task comes from.
public enum TaskSourceKind: OpenEnum {
  case liveCard
  case miniApp
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .liveCard: "live_card", .miniApp: "mini_app",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// What started a program's call.
public enum TaskTrigger: OpenEnum {
  case gesture
  case appear
  case change
  case timer
  case job
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .gesture: "gesture", .appear: "appear", .change: "change", .timer: "timer", .job: "job",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
