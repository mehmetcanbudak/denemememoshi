import Foundation
import MemoshiProtocol

extension Store {
  /// The adapter supplies actual immutable Pi result metadata. This does not resolve an
  /// unknown effect: it only confirms a known return or holds a result changed by Pi.
  public func observeCommittedToolResult(
    _ completion: ToolCompletedPayload, runtimeTaskKey: String,
    fence: ConversationFence, at now: Int64
  ) throws {
    try requireOpen()
    let call = try writer.transaction(write: false) {
      try checkFence(fence, at: now)
      return try writer.query(
        """
        SELECT p.tool_call_id, p.tool, p.parent_tool_call_id, t.record
        FROM unsafe_tool_dispatches s
        JOIN policy_tool_calls p ON p.conversation_id = s.conversation_id
          AND p.runtime_task_key = s.runtime_task_key
        JOIN tasks t ON t.id = p.task_id
        WHERE s.conversation_id = ? AND s.runtime_task_key = ?
        """, [.text(fence.conversationID.rawValue), .text(runtimeTaskKey)]
      ) { row in
        let task = try decoder.decode(MemoshiTask.self, from: row.requiredData(3))
        return PolicyToolIdentity(
          runtimeTaskKey: runtimeTaskKey, taskId: task.id,
          toolCallId: try row.requiredText(0), parentToolCallId: row.text(2),
          tool: try row.requiredText(1))
      }.first
    }
    guard let call else { return }
    guard completion.toolCallId == call.toolCallId, completion.tool == call.tool,
      completion.parentToolCallId == call.parentToolCallId
    else { throw ApprovalError.bindingConflict }
    // The actor does not suspend between binding and this transaction. Reuse the one
    // idempotent audit/checkpoint writer; a stalled live consumer cannot delay it.
    try completePolicyTool(
      completion, call: call, fallbackDecision: nil, fence: fence, at: now)
  }
}
