import Foundation
import MemoshiProtocol

extension Store {
  /// Exactly one authenticated user decision. A retry returns its original committed receipt.
  /// Source grants whose deadline has passed end first. A decision whose source-grant revisions
  /// are no longer current is canceled instead of answered, so a late answer never revives it.
  public func respondToApproval(
    _ params: CardsRespondParams, paramsHash: String, actor: Actor,
    fence: ConversationFence, at now: Int64
  ) throws -> CardsRespondResult {
    try requireOpen()
    guard actor.kind == .user, params.surface == nil || params.surface == .ui else {
      throw ApprovalError.forbidden
    }
    try expireFolderGrants(try cardSourceGrants(params.cardId), at: now)
    var events: [EventEnvelope] = []
    let outcome: ApprovalAnswer = try writer.transaction(write: true) {
      if var previous = try requestResult(
        params.requestId, method: CardsRespond.name, paramsHash: paramsHash,
        as: CardsRespondResult.self)
      {
        previous.replayed = true
        return .answered(previous)
      }
      try checkFence(fence, at: now)
      guard
        let rawID = try writer.text(
          "SELECT approval_id FROM approval_bindings WHERE card_id = ?",
          [.text(params.cardId.rawValue)]),
        let binding = try readApprovalBinding(ApprovalID(rawID), database: writer)
      else { throw ApprovalError.notFound }
      guard binding.approval.conversationId == fence.conversationID,
        binding.card.conversationId == fence.conversationID
      else { throw ApprovalError.bindingConflict }
      if binding.card.status == .expired || binding.approval.status == .expired {
        throw ApprovalError.expired(binding.card.id)
      }
      guard binding.card.status == .pending, binding.approval.status == .pending else {
        throw ApprovalError.resolved(
          cardID: binding.card.id,
          action: binding.card.outcome?.action ?? binding.card.status.rawValue)
      }
      if binding.approval.expiresAt <= now {
        events += try endPendingApproval(binding, ending: .expired, at: now)
        return .ended(.expired(binding.card.id))
      }
      let sourcesCurrent = try binding.sourceGrants.allSatisfy { reference in
        let check = try checkFolderGrant(
          reference, botID: binding.approval.botId,
          access: binding.operation == "fs.read" ? .read : .write, at: now, database: writer)
        if case .success = check { return true }
        return false
      }
      guard sourcesCurrent else {
        events += try endPendingApproval(binding, ending: .canceled(.grantRevoked), at: now)
        return .ended(.resolved(cardID: binding.card.id, action: CardStatus.canceled.rawValue))
      }
      // High-risk decisions are never accepted on a claimed method/signature alone.
      // This development profile has no paired-device owner-proof verifier or T4/T5 tools.
      guard binding.approval.tier.rawValue < 4 else { throw ApprovalError.deviceAuthRequired }
      if params.action == "allow_task" || params.action == "always_allow" {
        throw ApprovalError.capabilityMissing
      }
      guard params.action == "allow_once" || params.action == "deny" else {
        throw ApprovalError.invalidRequest
      }
      try validateApprovalAnswer(params)
      var approval = binding.approval
      var card = binding.card
      let allowed = params.action == "allow_once"
      approval.status = allowed ? .allowed : .denied
      approval.scope = allowed ? .once : nil
      approval.decidedBy = actor
      approval.decidedAt = now
      card.status = .resolved
      card.outcome = CardOutcome(action: params.action, payload: params.payload)
      card.inbox = false
      card.needsYou = false
      card.resolvedBy = actor
      card.resolvedAt = now
      try writeRecord(.approval(approval))
      try writeRecord(.card(card))
      events += try updateApprovalWait(taskID: approval.taskId, at: now)
      events.append(
        try append(
          approvalEvent(
            approval, at: now, actor: actor,
            event: .approvalResolved(
              .init(
                approvalId: approval.id, status: allowed ? .allowed : .denied,
                scope: approval.scope, decidedBy: actor)))))
      let resolved = try append(
        approvalEvent(
          approval, at: now, actor: actor,
          subject: ObjectRef(kind: "card", id: card.id.rawValue),
          event: .cardResolved(
            .init(
              cardId: card.id, outcome: CardOutcome(action: params.action, payload: params.payload),
              by: .user))))
      events.append(resolved)
      guard let writtenSeq = resolved.seq else { throw ApprovalError.bindingConflict }
      let receipt = CardsRespondResult(
        card: card,
        effects: .init(approvalId: approval.id, status: approval.status, scope: approval.scope),
        writtenSeq: writtenSeq, replayed: false)
      try saveRequest(
        params.requestId, method: CardsRespond.name, paramsHash: paramsHash, result: receipt,
        at: now)
      return .answered(receipt)
    }
    eventBus.publish(events)
    switch outcome {
    case .answered(let receipt): return receipt
    case .ended(let refusal): throw refusal
    }
  }

  /// Cancellation is a fenced runtime transition, never a synthetic user answer.
  public func cancelApproval(
    _ id: ApprovalID, reason: ApprovalCancelReason, fence: ConversationFence, at now: Int64
  ) throws {
    try requireOpen()
    guard reason.isKnown else { throw ApprovalError.invalidRequest }
    let events = try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      guard let binding = try readApprovalBinding(id, database: writer) else {
        throw ApprovalError.notFound
      }
      guard binding.approval.conversationId == fence.conversationID else {
        throw ApprovalError.bindingConflict
      }
      return try endPendingApproval(
        binding, ending: binding.approval.expiresAt <= now ? .expired : .canceled(reason), at: now)
    }
    eventBus.publish(events)
  }

  /// A bounded startup/maintenance batch; expiry and its card fact commit together.
  public func expireApprovals(fence: ConversationFence, at now: Int64) throws -> [ApprovalID] {
    try requireOpen()
    var events: [EventEnvelope] = []
    let expired = try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      let ids = try writer.query(
        "SELECT id FROM approvals WHERE conversation_id = ? AND status = 'pending' AND json_extract(record, '$.expiresAt') <= ? ORDER BY id LIMIT 256",
        [.text(fence.conversationID.rawValue), .integer(now)]
      ) { try ApprovalID($0.requiredText(0)) }
      for id in ids {
        guard let binding = try readApprovalBinding(id, database: writer) else {
          throw ApprovalError.bindingConflict
        }
        events += try endPendingApproval(binding, ending: .expired, at: now)
      }
      return ids
    }
    eventBus.publish(events)
    return expired
  }

  private enum ApprovalEnding {
    case expired
    case canceled(ApprovalCancelReason)
  }

  /// A committed answer, or a refusal returned only after the ending it found has committed.
  private enum ApprovalAnswer {
    case answered(CardsRespondResult)
    case ended(ApprovalError)
  }

  /// Called only inside the terminal turn's already fenced writer transaction.
  func cancelTaskApprovals(_ taskID: TaskID, at now: Int64) throws -> [EventEnvelope] {
    let ids = try writer.query(
      "SELECT id FROM approvals WHERE json_extract(record, '$.taskId') = ? AND status = 'pending'",
      [.text(taskID.rawValue)], row: { try ApprovalID($0.requiredText(0)) })
    return try cancelPendingApprovals(ids, reason: .taskCanceled, at: now)
  }

  /// Called only inside an already admitted writer transaction. A decision whose own deadline
  /// has passed ends as expired instead.
  func cancelPendingApprovals(
    _ ids: [ApprovalID], reason: ApprovalCancelReason, at now: Int64
  ) throws -> [EventEnvelope] {
    var events: [EventEnvelope] = []
    for id in ids {
      guard let binding = try readApprovalBinding(id, database: writer) else {
        throw ApprovalError.bindingConflict
      }
      events += try endPendingApproval(
        binding, ending: binding.approval.expiresAt <= now ? .expired : .canceled(reason), at: now)
    }
    return events
  }

  /// The grants a card's decision depends on, read so their lapse commits before its answer.
  private func cardSourceGrants(_ cardID: CardID) throws -> [GrantID] {
    try reader.transaction(write: false) {
      try reader.query(
        """
        SELECT s.grant_id FROM approval_bindings b
        JOIN approval_source_grants s ON s.approval_id = b.approval_id
        WHERE b.card_id = ? ORDER BY s.position
        """, [.text(cardID.rawValue)]
      ) { try GrantID($0.requiredText(0)) }
    }
  }

  private func endPendingApproval(
    _ binding: ApprovalBinding, ending: ApprovalEnding, at now: Int64
  ) throws -> [EventEnvelope] {
    guard binding.approval.status == .pending else { return [] }
    guard binding.card.status == .pending else { throw ApprovalError.bindingConflict }
    var approval = binding.approval
    var card = binding.card
    let domain: Event
    let presentation: Event
    switch ending {
    case .expired:
      approval.status = .expired
      card.status = .expired
      domain = .approvalExpired(.init(approvalId: approval.id))
      presentation = .cardExpired(.init(cardId: card.id))
    case .canceled(let reason):
      approval.status = .canceled
      card.status = .canceled
      domain = .approvalCanceled(.init(approvalId: approval.id, reason: reason))
      presentation = .cardCanceled(.init(cardId: card.id, reason: reason))
    }
    card.inbox = false
    card.needsYou = false
    try writeRecord(.approval(approval))
    try writeRecord(.card(card))
    return [
      try append(approvalEvent(approval, at: now, event: domain)),
      try append(
        approvalEvent(
          approval, at: now,
          subject: ObjectRef(kind: "card", id: card.id.rawValue), event: presentation)),
    ] + (try updateApprovalWait(taskID: approval.taskId, at: now))
  }

  private func validateApprovalAnswer(_ params: CardsRespondParams) throws {
    guard let payload = params.payload else { return }
    guard case .object(let object) = payload else { throw ApprovalError.invalidRequest }
    if params.action == "allow_once" {
      guard object.isEmpty else { throw ApprovalError.invalidRequest }
    } else {
      guard object.keys.allSatisfy({ $0 == "note" }) else { throw ApprovalError.invalidRequest }
      if let note = object["note"] {
        guard case .string(let text) = note, text.utf8.count <= 2_048 else {
          throw ApprovalError.invalidRequest
        }
      }
    }
  }
}
