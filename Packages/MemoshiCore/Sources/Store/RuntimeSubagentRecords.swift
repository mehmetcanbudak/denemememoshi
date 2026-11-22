import MemoshiProtocol

/// Immutable application ownership of an actual Pi task and its task-owned child conversation.
/// No transcript or model response is copied. Tool names are the immutable inherited ceiling.
public struct RuntimeSubagentBinding: Codable, Hashable, Sendable {
  /// The application task presented in graph, history and targeted cancellation APIs.
  public let taskId: TaskID
  /// The owning application Chat or Session, never the child's private Pi conversation ID.
  public let conversationId: ConversationID
  /// The original application turn that initiated delegation.
  public let originalTaskId: TaskID
  /// The immutable Pi task represented by this application task.
  public let piOwnerTaskId: Int
  /// The actual Pi child conversation whose entries supply history.
  public let piConversationId: Int
  /// The original Pi tool task that created the delegation.
  public let sourceToolTaskId: Int
  /// Whether the child uses the conversation-anchored background lifecycle.
  public let background: Bool
  /// The stable delegation request identity retained in its checkpoint.
  public let requestId: String
  /// Binding creation time in Unix milliseconds.
  public let createdAt: Int64
  /// The immutable reviewed parent-tool ceiling, excluding further delegation.
  public let toolNames: [String]

  /// Records verified ownership and the inherited capability ceiling without transcript text.
  public init(
    taskId: TaskID, conversationId: ConversationID, originalTaskId: TaskID,
    piOwnerTaskId: Int, piConversationId: Int, sourceToolTaskId: Int,
    background: Bool, requestId: String, createdAt: Int64, toolNames: [String]
  ) {
    self.taskId = taskId
    self.conversationId = conversationId
    self.originalTaskId = originalTaskId
    self.piOwnerTaskId = piOwnerTaskId
    self.piConversationId = piConversationId
    self.sourceToolTaskId = sourceToolTaskId
    self.background = background
    self.requestId = requestId
    self.createdAt = createdAt
    self.toolNames = toolNames
  }
}
