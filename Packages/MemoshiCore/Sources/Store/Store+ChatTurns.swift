import Foundation
import MemoshiProtocol

extension Store {
  /// Reserves stable identities before Pi admission. Only recovery-held, unsubmitted input
  /// content is retained; it never becomes an application transcript or event payload.
  /// Without a hold, a new ordinary send is refused as busy while older queued input remains.
  public func prepareChatTurn(
    _ params: ChatsSendParams, paramsHash: String, model: ModelRef,
    fence: ConversationFence, at now: Int64
  ) throws -> StoredChatTurn {
    try requireOpen()
    let chatID = params.chatId
    let requestID = params.requestId
    var events: [EventEnvelope] = []
    let result = try writer.transaction(write: true) {
      if let _: ChatsSendResult = try requestResult(
        requestID, method: ChatsSend.name,
        paramsHash: paramsHash, as: ChatsSendResult.self)
      {
        guard let previous = try readTurn(requestID, database: writer), previous.chatId == chatID
        else { throw StoreError.requestConflict }
        return previous
      }
      guard fence.conversationID == chatID else {
        throw StoreError.invalidCommit("Wrong Chat fence")
      }
      try checkFence(fence, at: now)
      guard let chat = try readConversation(chatID, database: writer) else {
        throw StoreError.chatNotFound
      }
      let held = try readChatRecovery(chatID, database: writer) != nil
      if !held {
        // Strict FIFO: no new ordinary turn reserves ahead of an older durable queued input,
        // even a parked one. It must be admitted or explicitly canceled first.
        guard
          try writer.integer(
            """
            SELECT COUNT(*) FROM chat_turns WHERE conversation_id = ?
              AND status IN ('queued', 'running', 'waiting')
              AND json_extract(record, '$.queueReason') IS NULL
            """, [.text(chatID.rawValue)]) == 0,
          try writer.integer(
            "SELECT COUNT(*) FROM chat_queued_inputs WHERE conversation_id = ?",
            [.text(chatID.rawValue)]) == 0
        else { throw StoreError.chatBusy }
      }
      var turn = StoredChatTurn(
        requestId: requestID, chatId: chatID, paramsHash: paramsHash, model: model,
        messageId: try IDGenerator.shared.objectID(MessageIDKind.self),
        assistantMessageId: try IDGenerator.shared.objectID(MessageIDKind.self),
        taskId: try IDGenerator.shared.objectID(TaskIDKind.self), createdAt: now)
      if held { turn.queueReason = .resume }
      let task = try taskRecord(turn, chat: chat, at: now)
      try writeRecord(.task(task))
      let event = try append(
        turnEvent(
          turn, chat: chat, at: now,
          subject: ObjectRef(kind: "task", id: turn.taskId.rawValue),
          event: .taskCreated(
            TaskCreatedPayload(
              taskId: task.id, kind: .turn, title: task.title,
              origin: task.origin, regime: .attended))))
      events.append(event)
      guard let seq = event.seq else {
        throw StoreError.invalidCommit("Task creation event must be durable")
      }
      turn.writtenSeq = seq
      try saveRequest(
        requestID, method: ChatsSend.name, paramsHash: paramsHash,
        result: turn.receipt(replayed: false), at: now)
      try writer.execute(
        "INSERT INTO chat_turns (request_id, conversation_id, status, record) VALUES (?, ?, ?, ?)",
        [
          .text(requestID.rawValue), .text(chatID.rawValue), .text(turn.status.rawValue),
          .json(try encoder.encode(turn)),
        ])
      if held { try retainQueuedChatInput(turn, params: params) }
      return turn
    }
    eventBus.publish(events)
    return result
  }

  /// Projects only committed Pi facts. Duplicate or late callbacks cannot reopen a terminal turn.
  public func projectChatTurn(
    _ requestID: ULID, piSubmissionID: Int? = nil, userEntryID: Int? = nil,
    assistantEntryID: Int? = nil, assistantStarted: Bool = false, status: TaskStatus,
    stopReason: StopReason? = nil, usage: Usage? = nil, error: MessageError? = nil,
    fence: ConversationFence, at now: Int64
  ) throws -> StoredChatTurn {
    try requireOpen()
    var events: [EventEnvelope] = []
    let result = try writer.transaction(write: true) {
      guard var turn = try readTurn(requestID, database: writer) else {
        throw StoreError.chatNotFound
      }
      guard fence.conversationID.rawValue == turn.chatId.rawValue else {
        throw StoreError.invalidCommit("Wrong Chat fence")
      }
      try checkFence(fence, at: now)
      if turn.isTerminal { return turn }
      let held = turn.recoveryStep != nil
      guard [.queued, .running, .done, .failed, .canceled].contains(status) else {
        throw StoreError.invalidCommit("Unsupported text-turn status")
      }
      guard let chat = try readConversation(turn.chatId, database: writer) else {
        throw StoreError.chatNotFound
      }
      let previous = turn
      if let piSubmissionID {
        guard turn.piSubmissionId == nil || turn.piSubmissionId == piSubmissionID else {
          throw StoreError.requestConflict
        }
        turn.piSubmissionId = piSubmissionID
      }
      if let userEntryID, turn.userEntryId == nil {
        turn.userEntryId = userEntryID
        turn.queueReason = nil
        try writer.execute(
          "DELETE FROM chat_queued_inputs WHERE request_id = ?", [.text(requestID.rawValue)])
        try writeMessageIndex(
          IndexedChatMessage(
            id: turn.messageId,
            conversationId: fence.conversationID, taskId: turn.taskId, role: .user,
            createdAt: turn.createdAt, requestId: turn.requestId, piEntryId: userEntryID))
        events.append(
          try append(
            turnEvent(
              turn, chat: chat, at: now,
              subject: ObjectRef(kind: "message", id: turn.messageId.rawValue),
              event: .messageCreated(
                MessageCreatedPayload(
                  messageId: turn.messageId,
                  role: .user, kind: .text, requestId: turn.requestId, attachments: [])))))
      }
      if !held && status != .queued && turn.status == .queued {
        turn.status = .running
        events.append(
          try append(
            turnEvent(
              turn, chat: chat, at: now,
              subject: ObjectRef(kind: "task", id: turn.taskId.rawValue),
              event: .taskStarted(TaskStartedPayload(taskId: turn.taskId)))))
      }
      if (assistantStarted || assistantEntryID != nil) && !turn.assistantStarted {
        turn.assistantStarted = true
        events.append(
          try append(
            turnEvent(
              turn, chat: chat, at: now,
              subject: ObjectRef(kind: "message", id: turn.assistantMessageId.rawValue),
              event: .messageCreated(
                MessageCreatedPayload(
                  messageId: turn.assistantMessageId,
                  role: .bot, authorId: chat.botId.rawValue, kind: .text, attachments: [])))))
      }
      if let assistantEntryID, turn.assistantEntryId == nil {
        turn.assistantEntryId = assistantEntryID
        turn.stopReason = stopReason
        turn.usage = usage
        try writeMessageIndex(
          IndexedChatMessage(
            id: turn.assistantMessageId,
            conversationId: fence.conversationID, taskId: turn.taskId, role: .bot,
            createdAt: now, requestId: nil, piEntryId: assistantEntryID, stopReason: stopReason,
            resumedAfterInterruption: turn.resumedAfterInterruption))
        events.append(
          try append(
            turnEvent(
              turn, chat: chat, at: now,
              subject: ObjectRef(kind: "message", id: turn.assistantMessageId.rawValue),
              event: .messageCompleted(
                MessageCompletedPayload(
                  messageId: turn.assistantMessageId,
                  stopReason: stopReason ?? .stop, usage: usage)))))
      }
      if !held && (status == .done || status == .failed || status == .canceled) {
        turn.status = status
        turn.stopReason = stopReason
        turn.usage = usage
        turn.error = error
        turn.queueReason = nil
        try writer.execute(
          "DELETE FROM chat_queued_inputs WHERE request_id = ?", [.text(requestID.rawValue)])
        if let error {
          events.append(
            try append(
              turnEvent(
                turn, chat: chat, at: now,
                subject: ObjectRef(kind: "message", id: turn.assistantMessageId.rawValue),
                event: .messageFailed(
                  MessageFailedPayload(
                    messageId: turn.assistantMessageId,
                    error: error, partial: assistantEntryID != nil)))))
        }
        let task = try taskRecord(turn, chat: chat, at: now)
        guard let outcome = task.outcome else {
          throw StoreError.invalidCommit("Terminal task must have an outcome")
        }
        try writeRecord(.task(task))
        events += try cancelTaskApprovals(task.id, at: now)
        events.append(
          try append(
            turnEvent(
              turn, chat: chat, at: now,
              subject: ObjectRef(kind: "task", id: turn.taskId.rawValue),
              event: .taskFinished(
                TaskFinishedPayload(
                  taskId: task.id,
                  status: status == .done ? .done : status == .canceled ? .canceled : .failed,
                  outcome: outcome, error: task.error, usage: task.usage,
                  durationMs: max(0, now - turn.createdAt))))))
      } else if turn != previous {
        try writeRecord(.task(taskRecord(turn, chat: chat, at: now)))
      }
      if turn != previous { try writeTurn(turn) }
      return turn
    }
    eventBus.publish(events)
    return result
  }

  func turnEvent(
    _ turn: StoredChatTurn, chat: ChatSummary, at now: Int64,
    subject: ObjectRef, event: Event
  ) throws -> EventDraft {
    EventDraft(
      ts: now, actor: Actor(kind: .system), subject: subject,
      scope: EventScope(botId: chat.botId, conversationId: chat.id, taskId: turn.taskId),
      origin: Origin(kind: .user, rootKind: .user), event: event)
  }

  func taskRecord(_ turn: StoredChatTurn, chat: ChatSummary, at now: Int64) throws
    -> MemoshiTask
  {
    let taskError = turn.error.map {
      TaskError(code: $0.code, message: $0.message, retryable: $0.retryable)
    }
    let canceledAt =
      try writer.query(
        "SELECT json_extract(record, '$.cancelRequestedAt') FROM tasks WHERE id = ?",
        [.text(turn.taskId.rawValue)], row: { $0.optionalInteger(0) }
      ).first ?? nil
    return MemoshiTask(
      id: turn.taskId, conversationId: chat.id, botId: chat.botId,
      kind: .turn, origin: Origin(kind: .user, rootKind: .user), regime: .attended,
      title: try Title("Conversation turn"), status: turn.status,
      waitingOn: turn.status == .waiting ? (turn.recoveryStep == nil ? .approval : .resume) : nil,
      outcome: turn.isTerminal
        ? (turn.status == .done ? .answered : turn.status == .canceled ? .canceled : .failed) : nil,
      error: taskError, requestId: turn.requestId.rawValue, budgetIds: [],
      usage: turn.usage
        ?? Usage(
          inputTokens: 0, outputTokens: 0, cacheReadTokens: 0,
          cacheWriteTokens: 0, costMicroUsd: 0, costKnown: false),
      resumeMode: turn.recoveryStep == nil ? .auto : .explicit,
      interruptedStep: turn.recoveryStep,
      cancelRequestedAt: canceledAt,
      startedAt: turn.status == .queued ? nil : turn.createdAt,
      endedAt: turn.isTerminal ? now : nil, createdAt: turn.createdAt)
  }
}
