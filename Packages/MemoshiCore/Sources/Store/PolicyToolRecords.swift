import MemoshiProtocol

/// Immutable application attribution for one Pi call in a fenced conversation.
public struct PolicyToolIdentity: Sendable, Equatable {
  /// The opaque task key or committed generation-result entry key, never a model-supplied ID.
  public let runtimeTaskKey: String
  /// The actual stored application task owning this call.
  public let taskId: TaskID
  /// The call identifier from Pi's immutable input or generation-side rejection.
  public let toolCallId: String
  /// The outer call identifier for a nested invocation.
  public let parentToolCallId: String?
  /// The tool name from Pi's immutable input or result.
  public let tool: String

  /// Binds committed runtime identity without accepting caller-provided scope or origin.
  public init(
    runtimeTaskKey: String, taskId: TaskID, toolCallId: String,
    parentToolCallId: String? = nil, tool: String
  ) {
    self.runtimeTaskKey = runtimeTaskKey
    self.taskId = taskId
    self.toolCallId = toolCallId
    self.parentToolCallId = parentToolCallId
    self.tool = tool
  }
}

/// Output-free accounting prepared before Pi commits either scrubbed result representation.
struct PolicyToolPreparation: Codable, Equatable {
  let redaction: PolicyRedactedPayload?
  let exposure: Exposure
}
