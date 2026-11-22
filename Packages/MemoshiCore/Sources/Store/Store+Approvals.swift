import Foundation
import MemoshiProtocol

extension Store {
  /// Creates approval, card, memo association and exact source-grant dependencies once;
  /// reattachment keeps the original deadline and dependencies. Each source grant must be current
  /// for the approval's bot at creation (`FolderGrantError` otherwise). Grants whose deadline has
  /// passed end first, so a reattached decision that depended on one is already canceled.
  public func ensureApproval(
    _ proposed: ApprovalBinding, fence: ConversationFence, at now: Int64
  ) throws -> ApprovalBinding {
    try requireOpen()
    try validateFolderGrantReferences(proposed.sourceGrants)
    try expireFolderGrants(proposed.sourceGrants.map(\.grantID), at: now)
    var events: [EventEnvelope] = []
    let result = try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      guard proposed.approval.conversationId == fence.conversationID else {
        throw ApprovalError.bindingConflict
      }
      if let previous = try readApprovalBinding(proposed.approval.id, database: writer) {
        guard sameApprovalCall(previous, proposed) else { throw ApprovalError.bindingConflict }
        return previous
      }
      let approval = proposed.approval
      let card = proposed.card
      guard approval.status == .pending, card.status == .pending, card.kind == .approval,
        card.subject == ObjectRef(kind: "approval", id: approval.id.rawValue),
        card.conversationId == approval.conversationId, card.botId == approval.botId,
        card.taskId == approval.taskId, card.expiresAt == approval.expiresAt,
        card.inbox, card.needsYou, approval.expiresAt > now,
        approval.expiresAt > approval.createdAt, !approval.argsHash.isEmpty,
        !proposed.runtimeTaskKey.isEmpty, proposed.runtimeTaskKey.utf8.count <= 128,
        !proposed.operation.isEmpty,
        let taskBytes = try writer.query(
          "SELECT record FROM tasks WHERE id = ?", [.text(approval.taskId.rawValue)],
          row: { try $0.requiredData(0) }
        ).first
      else { throw ApprovalError.invalidRequest }
      let task = try decoder.decode(MemoshiTask.self, from: taskBytes)
      // A task held for another reason takes no new decision; its existing ones may still end.
      guard task.botId == approval.botId, task.conversationId == approval.conversationId,
        [.queued, .running, .waiting].contains(task.status),
        task.waitingOn == nil || task.waitingOn == .approval
      else { throw ApprovalError.bindingConflict }
      for reference in proposed.sourceGrants {
        _ = try checkFolderGrant(
          reference, botID: approval.botId,
          access: proposed.operation == "fs.read" ? .read : .write, at: now, database: writer
        ).get()
      }
      try writeRecord(.approval(approval))
      try writeRecord(.card(card))
      try writer.execute(
        "INSERT INTO approval_bindings (approval_id, card_id, runtime_task_key, operation) VALUES (?, ?, ?, ?)",
        [
          .text(approval.id.rawValue), .text(card.id.rawValue), .text(proposed.runtimeTaskKey),
          .text(proposed.operation),
        ])
      for (position, reference) in proposed.sourceGrants.enumerated() {
        try writer.execute(
          """
          INSERT INTO approval_source_grants (approval_id, grant_id, revision, position)
          VALUES (?, ?, ?, ?)
          """,
          [
            .text(approval.id.rawValue), .text(reference.grantID.rawValue),
            .integer(reference.revision), .integer(Int64(position)),
          ])
      }
      events += try updateApprovalWait(taskID: approval.taskId, at: now)
      events.append(
        try append(
          approvalEvent(
            approval, at: now,
            event: .approvalRequested(
              .init(
                approvalId: approval.id, cardId: card.id, toolCallId: approval.toolCallId,
                parentToolCallId: approval.parentToolCallId, tool: approval.tool,
                verb: approval.verb,
                tier: approval.tier, permissionMode: approval.permissionMode,
                attendance: approval.attendance,
                exposure: approval.exposure, computerKind: approval.computerKind,
                deviceId: approval.deviceId,
                targets: approval.targets, argsHash: approval.argsHash,
                argsPreview: approval.argsPreview,
                ruleId: approval.ruleId, reasonCode: approval.reasonCode,
                policyVersion: approval.policyVersion,
                expiresAt: approval.expiresAt,
                confirmationRequired: approval.confirmationText != nil)))))
      events.append(
        try append(
          approvalEvent(
            approval, at: now,
            subject: ObjectRef(kind: "card", id: card.id.rawValue),
            event: .cardCreated(
              .init(
                cardId: card.id, kind: card.kind, variant: card.variant, subject: card.subject,
                messageId: card.messageId, title: card.title, inbox: card.inbox,
                needsYou: card.needsYou,
                expiresAt: card.expiresAt, payload: card.payload)))))
      return proposed
    }
    eventBus.publish(events)
    return result
  }

  /// Reads the linked current records and watermark together, even after event retention.
  public func approvalBinding(_ id: ApprovalID) throws -> StoreSnapshot<ApprovalBinding?> {
    try requireOpen()
    return try reader.transaction(write: false) {
      let binding = try readApprovalBinding(id, database: reader)
      return StoreSnapshot(
        value: binding, asOf: try position(conversationID: binding?.approval.conversationId))
    }
  }

  /// Enumerates only live decisions for recovery/expiry on their locally owned conversation.
  public func pendingApprovalBindings(_ conversation: ConversationID) throws -> [ApprovalBinding] {
    try requireOpen()
    return try reader.transaction(write: false) {
      try reader.query(
        """
        SELECT a.record, c.record, b.runtime_task_key, b.operation
        FROM approvals a LEFT JOIN approval_bindings b ON b.approval_id = a.id
        LEFT JOIN cards c ON c.id = b.card_id
        WHERE a.conversation_id = ? AND a.status = 'pending' ORDER BY a.id
        """, [.text(conversation.rawValue)]
      ) { try bindingRow($0) }.map { try withSourceGrants($0, database: reader) }
    }
  }

  func readApprovalBinding(_ id: ApprovalID, database: SQLiteConnection) throws -> ApprovalBinding?
  {
    try database.query(
      """
      SELECT a.record, c.record, b.runtime_task_key, b.operation
      FROM approval_bindings b JOIN approvals a ON a.id = b.approval_id
      JOIN cards c ON c.id = b.card_id WHERE b.approval_id = ?
      """, [.text(id.rawValue)]
    ) { try bindingRow($0) }.first.map { try withSourceGrants($0, database: database) }
  }

  private func bindingRow(_ row: SQLiteRow) throws -> ApprovalBinding {
    ApprovalBinding(
      approval: try decoder.decode(Approval.self, from: row.requiredData(0)),
      card: try decoder.decode(Card.self, from: row.requiredData(1)),
      runtimeTaskKey: try row.requiredText(2), operation: try row.requiredText(3))
  }

  /// Adds the decision's persisted source-grant revisions in their original order.
  private func withSourceGrants(
    _ binding: ApprovalBinding, database: SQLiteConnection
  ) throws -> ApprovalBinding {
    let sources = try database.query(
      """
      SELECT grant_id, revision FROM approval_source_grants
      WHERE approval_id = ? ORDER BY position
      """, [.text(binding.approval.id.rawValue)]
    ) { FolderGrantReference(grantID: try GrantID($0.requiredText(0)), revision: $0.integer(1)) }
    return ApprovalBinding(
      approval: binding.approval, card: binding.card, runtimeTaskKey: binding.runtimeTaskKey,
      operation: binding.operation, sourceGrants: sources)
  }

  func approvalEvent(
    _ approval: Approval, at now: Int64, actor: Actor = Actor(kind: .system),
    subject: ObjectRef? = nil, event: Event
  ) -> EventDraft {
    EventDraft(
      ts: now, actor: actor,
      subject: subject ?? ObjectRef(kind: "approval", id: approval.id.rawValue),
      scope: EventScope(
        botId: approval.botId, conversationId: approval.conversationId, taskId: approval.taskId),
      origin: approval.origin, event: event)
  }

  private func sameApprovalCall(_ existing: ApprovalBinding, _ candidate: ApprovalBinding) -> Bool {
    let lhs = existing.approval
    let rhs = candidate.approval
    return existing.runtimeTaskKey == candidate.runtimeTaskKey
      && existing.operation == candidate.operation
      && lhs.id == rhs.id && lhs.botId == rhs.botId && lhs.conversationId == rhs.conversationId
      && lhs.taskId == rhs.taskId && lhs.toolCallId == rhs.toolCallId
      && lhs.parentToolCallId == rhs.parentToolCallId && lhs.tool == rhs.tool
      && lhs.verb == rhs.verb
      && lhs.tier == rhs.tier && lhs.argsHash == rhs.argsHash && lhs.targets == rhs.targets
      && lhs.policyVersion == rhs.policyVersion && lhs.confirmationText == rhs.confirmationText
      && Set(existing.sourceGrants) == Set(candidate.sourceGrants)
  }
}
