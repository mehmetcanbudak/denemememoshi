/// A persisted task requiring explicit recovery, without inventing missing tool metadata.
public struct HeldChatStep: Codable, Hashable, Sendable {
  /// The application task whose interruption holds its entire Chat.
  public var taskId: TaskID
  /// Known interruption evidence; absent when the recorded task has no finer detail.
  public var step: InterruptedStep?

  /// Creates an output-free description of the held work.
  public init(taskId: TaskID, step: InterruptedStep?) {
    self.taskId = taskId
    self.step = step
  }
}

/// Why no new model request or tool dispatch may start in this Chat.
/// A hold is derived from durable evidence, never cleared by Bypass or matching file bytes.
public struct ChatRecoveryHold: Codable, Hashable, Sendable {
  /// The unsettled tasks, in stable order. An actual hold always has at least one step.
  public var steps: [HeldChatStep]

  /// Captures the persisted recovery requirements.
  public init(steps: [HeldChatStep]) { self.steps = steps }
}

/// An accepted but unsubmitted input. It is not a canonical transcript message.
public struct QueuedChatMessage: Codable, Hashable, Sendable {
  /// The original idempotent send key, preserved until delivery or cancellation.
  public var requestId: ULID
  /// Reserved stable message identity; no Pi entry exists yet.
  public var messageId: MessageID
  /// The queued input's application task.
  public var taskId: TaskID
  /// The explicit model choice, never a substitute provider.
  public var model: ModelRef
  /// Unsent content, removed from the outbox when Pi admission commits or it is canceled.
  public var content: [ContentPart]
  /// Original acceptance time in Unix milliseconds.
  public var createdAt: Int64

  /// Creates a device-local unsent queue projection.
  public init(
    requestId: ULID, messageId: MessageID, taskId: TaskID, model: ModelRef,
    content: [ContentPart], createdAt: Int64
  ) {
    self.requestId = requestId
    self.messageId = messageId
    self.taskId = taskId
    self.model = model
    self.content = content
    self.createdAt = createdAt
  }
}
