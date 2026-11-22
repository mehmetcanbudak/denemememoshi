/// `task.created` (D): a task was created; for runs, in the claim transaction.
public struct TaskCreatedPayload: EventPayload {
  /// `task.created`.
  public static let eventType = "task.created"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The task.
  public var taskId: TaskID
  /// What kind of work it is.
  public var kind: TaskKind
  /// Its title.
  public var title: Title
  /// Why the work exists; the envelope's `origin` carries the same value.
  public var origin: Origin?
  /// Derived from the origin.
  public var regime: Regime
  /// The parent task.
  public var parentTaskId: TaskID?
  /// The routine whose run this is.
  public var routineId: RoutineID?
  /// The watch that started it.
  public var watchId: WatchID?
  /// The wake that started it.
  public var wakeId: WakeID?
  /// The handoff it serves.
  public var handoffId: HandoffID?
  /// For runs, the fire time being served.
  public var scheduledFor: Int64?

  /// Creates the payload.
  public init(
    taskId: TaskID, kind: TaskKind, title: Title, origin: Origin? = nil, regime: Regime,
    parentTaskId: TaskID? = nil, routineId: RoutineID? = nil, watchId: WatchID? = nil,
    wakeId: WakeID? = nil, handoffId: HandoffID? = nil, scheduledFor: Int64? = nil
  ) {
    self.taskId = taskId
    self.kind = kind
    self.title = title
    self.origin = origin
    self.regime = regime
    self.parentTaskId = parentTaskId
    self.routineId = routineId
    self.watchId = watchId
    self.wakeId = wakeId
    self.handoffId = handoffId
    self.scheduledFor = scheduledFor
  }

  /// `.taskCreated(self)`.
  public var asEvent: Event { .taskCreated(self) }
}

/// `task.started` (D): the task's first transition to `running`.
public struct TaskStartedPayload: EventPayload {
  /// `task.started`.
  public static let eventType = "task.started"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The task.
  public var taskId: TaskID
  /// Its status, `running`.
  public var status: TaskStartedStatus?

  /// Creates the payload.
  public init(taskId: TaskID, status: TaskStartedStatus? = nil) {
    self.taskId = taskId
    self.status = status
  }

  /// `.taskStarted(self)`.
  public var asEvent: Event { .taskStarted(self) }
}

/// `task.status_changed` (D): a non-terminal transition.
public struct TaskStatusChangedPayload: EventPayload {
  /// `task.status_changed`.
  public static let eventType = "task.status_changed"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The task.
  public var taskId: TaskID
  /// The new status: `running` or `waiting`.
  public var status: ActiveTaskStatus
  /// What it waits for, when `waiting`.
  public var waitingOn: WaitingOn?
  /// The status before: `running` or `waiting`, since `task.started` and `task.finished` report
  /// every transition out of `queued` (object-model.md §5.2).
  public var previous: ActiveTaskStatus

  /// Creates the payload.
  public init(
    taskId: TaskID, status: ActiveTaskStatus, waitingOn: WaitingOn? = nil,
    previous: ActiveTaskStatus
  ) {
    self.taskId = taskId
    self.status = status
    self.waitingOn = waitingOn
    self.previous = previous
  }

  /// `.taskStatusChanged(self)`.
  public var asEvent: Event { .taskStatusChanged(self) }
}

/// `task.progress` (U): progress text for chips and tickers, throttled to 1 Hz per task.
public struct TaskProgressPayload: EventPayload {
  /// `task.progress`.
  public static let eventType = "task.progress"
  /// Version 1.
  public static let typeVersion = 1
  /// UI-only.
  public static let eventClass = EventClass.uiOnly

  /// The task.
  public var taskId: TaskID
  /// The progress text.
  public var message: String
  /// The current step's number.
  public var step: Int?
  /// The percentage done, 0–100.
  public var percent: Percent?

  /// Creates the payload.
  public init(taskId: TaskID, message: String, step: Int? = nil, percent: Percent? = nil) {
    self.taskId = taskId
    self.message = message
    self.step = step
    self.percent = percent
  }

  /// `.taskProgress(self)`.
  public var asEvent: Event { .taskProgress(self) }
}

/// `task.cancel_requested` (D): Stop was pressed; the abort runs bottom-up.
public struct TaskCancelRequestedPayload: EventPayload {
  /// `task.cancel_requested`.
  public static let eventType = "task.cancel_requested"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The task.
  public var taskId: TaskID
  /// Who asked.
  public var by: ActorKind

  /// Creates the payload.
  public init(taskId: TaskID, by: ActorKind) {
    self.taskId = taskId
    self.by = by
  }

  /// `.taskCancelRequested(self)`.
  public var asEvent: Event { .taskCancelRequested(self) }
}

/// `task.resumed` (D): the task continued after an interruption or an error card.
public struct TaskResumedPayload: EventPayload {
  /// `task.resumed`.
  public static let eventType = "task.resumed"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The task.
  public var taskId: TaskID
  /// `user` (a Resume or error card) or `system` (an automatic resume or a definite outcome
  /// check).
  public var by: ResumedBy

  /// Creates the payload.
  public init(taskId: TaskID, by: ResumedBy) {
    self.taskId = taskId
    self.by = by
  }

  /// `.taskResumed(self)`.
  public var asEvent: Event { .taskResumed(self) }
}

/// `task.finished` (A): the task reached `done`, `failed` or `canceled`.
public struct TaskFinishedPayload: EventPayload {
  /// `task.finished`.
  public static let eventType = "task.finished"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited

  /// The task.
  public var taskId: TaskID
  /// The terminal status.
  public var status: TerminalTaskStatus
  /// How it ended.
  public var outcome: TaskOutcome
  /// A one-line result.
  public var summary: Summary?
  /// Why it failed.
  public var error: TaskError?
  /// Its usage, children included.
  public var usage: Usage
  /// How long it ran.
  public var durationMs: Int64

  /// Creates the payload.
  public init(
    taskId: TaskID, status: TerminalTaskStatus, outcome: TaskOutcome, summary: Summary? = nil,
    error: TaskError? = nil, usage: Usage, durationMs: Int64
  ) {
    self.taskId = taskId
    self.status = status
    self.outcome = outcome
    self.summary = summary
    self.error = error
    self.usage = usage
    self.durationMs = durationMs
  }

  /// `.taskFinished(self)`.
  public var asEvent: Event { .taskFinished(self) }
}

/// `tool.interrupted` (A): a restart, an expired lease or a Stop cut a call off before its
/// outcome was recorded (D51).
public struct ToolInterruptedPayload: EventPayload {
  /// `tool.interrupted`.
  public static let eventType = "tool.interrupted"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited

  /// The interrupted call.
  public var toolCallId: String
  /// The tool.
  public var tool: String
  /// Whether its tool may run again by itself.
  public var replay: ToolReplay
  /// What happens next: it reruns, its outcome check runs, or a Resume card asks the user.
  public var effect: InterruptionEffect

  /// Creates the payload.
  public init(toolCallId: String, tool: String, replay: ToolReplay, effect: InterruptionEffect) {
    self.toolCallId = toolCallId
    self.tool = tool
    self.replay = replay
    self.effect = effect
  }

  /// `.toolInterrupted(self)`.
  public var asEvent: Event { .toolInterrupted(self) }
}

/// Whether an interrupted call's tool may run again by itself (D42).
public enum ToolReplay: OpenEnum {
  case safe
  case unsafe
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.safe: "safe", .unsafe: "unsafe"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// What follows an interrupted call (D51).
public enum InterruptionEffect: OpenEnum {
  case rerun
  case outcomeCheck
  case resumeCard
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .rerun: "rerun", .outcomeCheck: "outcome_check", .resumeCard: "resume_card",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// `tool.interruption_resolved` (A): the user answered a Resume card, on any device (D51).
public struct ToolInterruptionResolvedPayload: EventPayload {
  /// `tool.interruption_resolved`.
  public static let eventType = "tool.interruption_resolved"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited

  /// The interrupted call.
  public var toolCallId: String
  /// The tool.
  public var tool: String
  /// What the user chose.
  public var action: ResumeAction
  /// The Resume card.
  public var cardId: CardID
  /// Who answered.
  public var by: ActorKind

  /// Creates the payload.
  public init(
    toolCallId: String, tool: String, action: ResumeAction, cardId: CardID, by: ActorKind
  ) {
    self.toolCallId = toolCallId
    self.tool = tool
    self.action = action
    self.cardId = cardId
    self.by = by
  }

  /// `.toolInterruptionResolved(self)`.
  public var asEvent: Event { .toolInterruptionResolved(self) }
}

/// The user's choice on a Resume card.
public enum ResumeAction: OpenEnum {
  case runAgain
  case skip
  case markDone
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .runAgain: "run_again", .skip: "skip", .markDone: "mark_done",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// The status `task.started` reports: only `running` (events.md §5.5).
public enum TaskStartedStatus: OpenEnum {
  case running
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.running: "running"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// The status on either side of a non-terminal transition: `running` or `waiting`
/// (events.md §5.5, object-model.md §5.2).
public enum ActiveTaskStatus: OpenEnum {
  case running
  case waiting
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.running: "running", .waiting: "waiting"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// A terminal status: `done`, `failed` or `canceled` (events.md §5.5 `task.finished`).
public enum TerminalTaskStatus: OpenEnum {
  case done
  case failed
  case canceled
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .done: "done", .failed: "failed", .canceled: "canceled",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// Who resumed a task: `user` (a Resume or error card) or `system` (events.md §5.5).
public enum ResumedBy: OpenEnum {
  case user
  case system
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.user: "user", .system: "system"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
