import Foundation
import MemoshiProtocol

/// Current local authority for a gateway call, resolved from the immutable Pi-task binding.
/// The provider's reusable tool-call ID is never used to choose an owning task.
public struct GatewayCallAuthority: Sendable {
  /// Exact immutable tool identity, including its actual owning task and nested parent.
  public let call: PolicyToolIdentity
  /// Current bot policy, root origin, budget and exposure snapshot for that task.
  public let snapshot: PolicyCallSnapshot
  /// The current local writer epoch; not a cross-device authority grant.
  public let fence: ConversationFence
}

/// Already-scrubbed transport metadata; no URL, headers, body, placeholder or credential value.
public struct GatewayAuditFact: Sendable {
  /// Conversation whose isolated gateway client made the request.
  public let conversationID: ConversationID
  /// Bot bound to that client by trusted host code.
  public let botID: BotID
  /// Durable Pi task key when authenticated; nil never infers the current root task.
  public let runtimeTaskKey: String?
  /// Trusted computer identity, with no filesystem path.
  public let computerID: String
  /// Normalized, scrubbed destination host; no URL or query.
  public let host: String
  /// Admission at the gateway boundary, not proof of delivery or an external effect.
  public let allowed: Bool
  /// Opaque broker references for actual prepared header injections, never credential values.
  public let secretReferences: [String]

  /// Captures the scrubbed metadata that the required sink durably records before dispatch.
  public init(
    conversationID: ConversationID, botID: BotID, runtimeTaskKey: String?, computerID: String,
    host: String, allowed: Bool, secretReferences: [String]
  ) {
    self.conversationID = conversationID
    self.botID = botID
    self.runtimeTaskKey = runtimeTaskKey
    self.computerID = computerID
    self.host = host
    self.allowed = allowed
    self.secretReferences = secretReferences
  }
}

extension Store {
  /// Resolves the exact live call and current local fence; completed/prepared calls fail closed.
  public func gatewayCallSnapshot(
    conversationID: ConversationID, botID: BotID, runtimeTaskKey: String, at now: Int64
  ) throws -> GatewayCallAuthority {
    try requireOpen()
    guard let caller = try gatewayCaller(conversationID, bot: botID, key: runtimeTaskKey),
      caller.executing, let lease = try readLease(conversationID)
    else { throw ApprovalError.bindingConflict }
    try checkFence(lease.fence, at: now)
    let snapshot = try policyCallSnapshot(
      chatID: conversationID, taskID: caller.call.taskId, fence: lease.fence, at: now)
    return GatewayCallAuthority(call: caller.call, snapshot: snapshot, fence: lease.fence)
  }

  /// Final local recheck has no suspension between reading stop/mode/budget state and
  /// recording the decision. This is not Pi's unqualified transactional cross-device fence.
  public func recordGatewayPolicyDecision(
    _ decision: PolicyDecidedPayload, call: PolicyToolIdentity, fence: ConversationFence,
    at now: Int64
  ) throws {
    if decision.decision == .allow {
      let current = try policyCallSnapshot(
        chatID: fence.conversationID, taskID: call.taskId, fence: fence, at: now)
      guard current.policy.permissionMode == decision.permissionMode,
        current.policy.active, !current.policy.killSwitch, current.task.budgetIds.isEmpty,
        current.task.cancelRequestedAt == nil,
        [.queued, .running, .waiting].contains(current.task.status)
      else { throw ApprovalError.bindingConflict }
    }
    try recordPolicyToolDecision(decision, call: call, fence: fence, at: now)
  }

  /// Host refusals may be audited without an active conversation lease; they authorize no
  /// conversation execution. An allowance always requires the exact live task and local fence.
  public func recordGatewayAudit(_ fact: GatewayAuditFact, at now: Int64) throws {
    try requireOpen()
    let events = try writer.transaction(write: true) {
      guard
        try writer.text(
          "SELECT bot_id FROM chats WHERE id = ?", [.text(fact.conversationID.rawValue)])
          == fact.botID.rawValue
      else { throw ApprovalError.bindingConflict }
      let caller = try fact.runtimeTaskKey.flatMap {
        try gatewayCaller(fact.conversationID, bot: fact.botID, key: $0)
      }
      if fact.allowed {
        guard let caller, caller.executing, let lease = try readLease(fact.conversationID) else {
          throw ApprovalError.bindingConflict
        }
        try checkFence(lease.fence, at: now)
      }
      guard
        fact.secretReferences.allSatisfy({
          !$0.isEmpty && $0.utf8.count <= 256 && !$0.contains("*")
            && !$0.utf8.contains(where: { $0 == 0 || $0 == 10 || $0 == 13 })
        })
      else { throw ApprovalError.bindingConflict }
      var appended: [EventEnvelope] = []
      let scope = EventScope(
        botId: fact.botID, conversationId: fact.conversationID, taskId: caller?.call.taskId)
      func draft(_ event: Event) -> EventDraft {
        EventDraft(
          ts: now, actor: Actor(kind: .system),
          subject: ObjectRef(kind: "computer", id: fact.computerID),
          scope: scope, origin: caller?.task.origin, event: event)
      }
      if let caller, caller.executing {
        let values: [SQLiteConnection.Value] = [
          .text(caller.call.taskId.rawValue), .text(fact.computerID), .text(fact.host),
          .integer(fact.allowed ? 1 : 0),
        ]
        let exists =
          try writer.integer(
            "SELECT COUNT(*) FROM gateway_audit_hosts WHERE task_id = ? AND computer_id = ? AND host = ? AND allowed = ?",
            values) == 1
        if !exists {
          try writer.execute(
            """
            INSERT INTO gateway_audit_hosts
              (conversation_id, task_id, bot_id, computer_id, host, allowed, pending_count, last_at)
            VALUES (?, ?, ?, ?, ?, ?, 0, ?)
            """,
            [
              .text(fact.conversationID.rawValue), .text(caller.call.taskId.rawValue),
              .text(fact.botID.rawValue), .text(fact.computerID), .text(fact.host),
              .integer(fact.allowed ? 1 : 0), .integer(now),
            ])
          if fact.allowed {
            appended.append(
              try append(
                draft(
                  .egressAllowed(
                    .init(
                      host: fact.host, computerId: fact.computerID, taskId: caller.call.taskId)))))
          } else {
            appended.append(
              try append(
                draft(
                  .egressBlocked(
                    .init(
                      host: fact.host, computerId: fact.computerID, taskId: caller.call.taskId,
                      count: 1)))))
          }
        } else if !fact.allowed {
          try writer.execute(
            """
            UPDATE gateway_audit_hosts SET pending_count = pending_count + 1, last_at = ?
            WHERE task_id = ? AND computer_id = ? AND host = ? AND allowed = 0
            """,
            [
              .integer(now), .text(caller.call.taskId.rawValue), .text(fact.computerID),
              .text(fact.host),
            ])
        }
      } else {
        // No current-root inference for unauthenticated or unknown attribution labels.
        guard !fact.allowed else { throw ApprovalError.bindingConflict }
        appended.append(
          try append(
            draft(
              .egressBlocked(
                .init(
                  host: fact.host, computerId: fact.computerID, taskId: caller?.call.taskId,
                  count: 1)))))
      }
      if fact.allowed {
        for reference in Set(fact.secretReferences).sorted() {
          appended.append(
            try append(
              draft(
                .secretUsed(
                  .init(
                    secretRef: reference, purpose: .egressPlaceholder, host: fact.host)))))
        }
      }
      return appended
    }
    eventBus.publish(events)
  }

  /// Final summaries are flushed by real tool completion and before normal lease release.
  /// Counters are durable, so a kill does not discard refusals awaiting coalescing.
  func flushGatewayAudit(
    conversationID: ConversationID, taskID: TaskID? = nil, at now: Int64
  ) throws -> [EventEnvelope] {
    var values: [SQLiteConnection.Value] = [.text(conversationID.rawValue)]
    let taskClause = taskID == nil ? "" : " AND g.task_id = ?"
    if let taskID { values.append(.text(taskID.rawValue)) }
    let rows = try writer.query(
      """
      SELECT g.task_id, g.computer_id, g.host, g.pending_count, t.record
      FROM gateway_audit_hosts g JOIN tasks t ON t.id = g.task_id
      WHERE g.conversation_id = ? AND g.allowed = 0 AND g.pending_count > 0\(taskClause)
      ORDER BY g.task_id, g.computer_id, g.host
      """, values
    ) { row in
      (
        try TaskID(row.requiredText(0)), try row.requiredText(1), try row.requiredText(2),
        row.integer(3), try decoder.decode(MemoshiTask.self, from: row.requiredData(4))
      )
    }
    var events: [EventEnvelope] = []
    events.reserveCapacity(rows.count)
    for (taskID, computer, host, count, task) in rows {
      events.append(
        try append(
          EventDraft(
            ts: now, actor: Actor(kind: .system),
            subject: ObjectRef(kind: "computer", id: computer),
            scope: EventScope(botId: task.botId, conversationId: conversationID, taskId: taskID),
            origin: task.origin,
            event: .egressBlocked(
              .init(host: host, computerId: computer, taskId: taskID, count: count)))))
      try writer.execute(
        "UPDATE gateway_audit_hosts SET pending_count = 0 WHERE task_id = ? AND computer_id = ? AND host = ? AND allowed = 0",
        [.text(taskID.rawValue), .text(computer), .text(host)])
    }
    return events
  }

  private struct GatewayStoredCaller {
    let call: PolicyToolIdentity
    let task: MemoshiTask
    let executing: Bool
  }

  private func gatewayCaller(_ conversation: ConversationID, bot: BotID, key: String) throws
    -> GatewayStoredCaller?
  {
    try writer.query(
      """
      SELECT p.task_id, p.bot_id, p.tool_call_id, p.parent_tool_call_id, p.tool, p.origin,
        p.decision_observed, p.preparation, p.completion_seq, t.record
      FROM policy_tool_calls p JOIN tasks t
        ON t.id = p.task_id AND t.conversation_id = p.conversation_id AND t.bot_id = p.bot_id
      WHERE p.conversation_id = ? AND p.runtime_task_key = ?
      """, [.text(conversation.rawValue), .text(key)]
    ) { row in
      let task = try decoder.decode(MemoshiTask.self, from: row.requiredData(9))
      guard try row.requiredText(0) == task.id.rawValue, try row.requiredText(1) == bot.rawValue,
        task.botId == bot, task.conversationId == conversation,
        try decoder.decode(Origin.self, from: row.requiredData(5)) == task.origin
      else { throw ApprovalError.bindingConflict }
      let call = try PolicyToolIdentity(
        runtimeTaskKey: key, taskId: task.id, toolCallId: row.requiredText(2),
        parentToolCallId: row.text(3), tool: row.requiredText(4))
      return GatewayStoredCaller(
        call: call, task: task,
        executing: row.integer(6) == 1 && row.data(7) == nil && row.optionalInteger(8) == nil
          && task.cancelRequestedAt == nil && [.queued, .running, .waiting].contains(task.status))
    }.first
  }
}
