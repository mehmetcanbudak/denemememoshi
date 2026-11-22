/// `tasks.graph`: the persisted projection of real runtime work in one app conversation.
public enum TasksGraph: RPCMethod {
  /// The owning application conversation.
  public typealias Params = TasksGraphParams
  /// Persisted root and child tasks with their read watermark.
  public typealias Result = TasksGraphResult
  /// `tasks.graph`.
  public static let name = "tasks.graph"
  /// Inspection does not submit or cancel work.
  public static let isMutating = false
}

/// Selects the Chat or Session whose task graph is inspected.
public struct TasksGraphParams: Codable, Hashable, Sendable {
  /// The application conversation, not a private Pi child conversation.
  public var conversationId: ConversationID
  /// Creates a graph request for one conversation.
  public init(conversationId: ConversationID) { self.conversationId = conversationId }
}

/// A reconciled persisted graph and its metadata-store position.
public struct TasksGraphResult: Codable, Hashable, Sendable {
  /// Root and child task snapshots with their original ownership.
  public var nodes: [MemoshiTask]
  /// The position covered by this read.
  public var asOf: AsOf
  /// Creates a graph snapshot without copying transcript content.
  public init(nodes: [MemoshiTask], asOf: AsOf) {
    self.nodes = nodes
    self.asOf = asOf
  }
}

/// `tasks.history`: attach a read-only inspector to a task-owned child, without creating a
/// Session, moving ownership, submitting input or stopping any other work.
public enum TasksHistory: RPCMethod {
  /// Task identity, opaque cursor and bounded page size.
  public typealias Params = TasksHistoryParams
  /// The verified child task and its own entry history.
  public typealias Result = TasksHistoryResult
  /// `tasks.history`.
  public static let name = "tasks.history"
  /// Attaching an inspector does not change work ownership.
  public static let isMutating = false
}

/// Reads one bounded page from an existing task-owned child.
public struct TasksHistoryParams: Codable, Hashable, Sendable {
  /// The application child task, not an arbitrary Pi conversation.
  public var taskId: TaskID
  /// Exclusive opaque entry cursor returned by the preceding page.
  public var before: String?
  /// The required bounded page size.
  public var limit: PageLimit
  /// Requests the newest child entries unless an exclusive cursor is supplied.
  public init(taskId: TaskID, before: String? = nil, limit: PageLimit) {
    self.taskId = taskId
    self.before = before
    self.limit = limit
  }
}

/// Immutable child entry reference and text, resolved from Pi rather than stored a second time.
public struct TaskHistoryMessage: Codable, Hashable, Sendable {
  /// The immutable Pi entry identity used for stable pagination.
  public var entryId: String
  /// The entry's display role.
  public var role: MessageRole
  /// Entry text resolved from Pi, never copied into the durable event log.
  public var text: String
  /// The terminal bot-entry reason when present.
  public var stopReason: StopReason?
  /// Creates a resolved immutable history entry.
  public init(entryId: String, role: MessageRole, text: String, stopReason: StopReason? = nil) {
    self.entryId = entryId
    self.role = role
    self.text = text
    self.stopReason = stopReason
  }
}

/// One verified child task, committed entries and separate uncommitted text.
public struct TasksHistoryResult: Codable, Hashable, Sendable {
  /// The owning application task's current persisted snapshot.
  public var task: MemoshiTask
  /// Whether the binding has the background run/report lifecycle.
  public var background: Bool
  /// Committed entries ordered oldest to newest within this page.
  public var items: [TaskHistoryMessage]
  /// Uncommitted current assistant text, separate from immutable history and its entry IDs.
  public var liveText: String?
  /// The exclusive opaque cursor for an older page, absent at the start of history.
  public var nextBefore: String?
  /// The metadata position covered by the task snapshot.
  public var asOf: AsOf
  /// Creates an attached-child page without creating a Session or moving ownership.
  public init(
    task: MemoshiTask, background: Bool, items: [TaskHistoryMessage],
    liveText: String? = nil, nextBefore: String? = nil, asOf: AsOf
  ) {
    self.task = task
    self.background = background
    self.items = items
    self.liveText = liveText
    self.nextBefore = nextBefore
    self.asOf = asOf
  }
}
