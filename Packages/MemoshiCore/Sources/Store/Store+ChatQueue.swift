import Foundation
import MemoshiProtocol

extension Store {
  /// The oldest held input by admission order, never by its client-chosen request ID.
  /// Original client parameters, not reconstructed or normalized input. Their original
  /// idempotency hash remains valid when a recovered conversation can admit them.
  public func nextQueuedChatInput(_ chatID: ConversationID) throws -> ChatsSendParams? {
    try requireOpen()
    return try reader.query(
      "SELECT record FROM chat_queued_inputs WHERE conversation_id = ? ORDER BY rowid LIMIT 1",
      [.text(chatID.rawValue)]
    ) { try decoder.decode(ChatsSendParams.self, from: $0.requiredData(0)) }.first
  }

  /// A claim survives normal reopen even before its Pi submission exists.
  public func hasQueuedChatInput(_ requestID: ULID) throws -> Bool {
    try requireOpen()
    return try reader.integer(
      "SELECT COUNT(*) FROM chat_queued_inputs WHERE request_id = ?",
      [.text(requestID.rawValue)]) == 1
  }

  /// Durably queues the exact original request only while the Chat's recovery hold exists.
  /// Identity is checked first: another Chat's fence, a stale fence or conflicting request reuse
  /// throws. While held it reserves the queued turn, or returns the original turn on replay.
  /// Once the hold is absent it writes no task, event, receipt or turn and returns nil; normal
  /// admission must then release older queued inputs first. Every check and the reservation run
  /// synchronously on this actor, the only Store writer, so no hold change can intervene.
  public func queueHeldChatTurn(
    _ params: ChatsSendParams, paramsHash: String, model: ModelRef,
    fence: ConversationFence, at now: Int64
  ) throws -> StoredChatTurn? {
    try requireOpen()
    let held: Bool = try writer.transaction(write: false) {
      guard fence.conversationID.rawValue == params.chatId.rawValue else {
        throw StoreError.invalidCommit("Wrong Chat fence")
      }
      try checkFence(fence, at: now)
      if try requestResult(
        params.requestId, method: ChatsSend.name, paramsHash: paramsHash,
        as: ChatsSendResult.self) != nil
      {
        guard try readTurn(params.requestId, database: writer)?.chatId == params.chatId else {
          throw StoreError.requestConflict
        }
      }
      return try readChatRecovery(params.chatId, database: writer) != nil
    }
    guard held else { return nil }
    return try prepareChatTurn(params, paramsHash: paramsHash, model: model, fence: fence, at: now)
  }

  /// Reserves the one active-turn slot before crossing into Pi. The input stays durable until
  /// its actual Pi user entry is observed, including a close between claim and submission.
  /// An input canceled after its release read it is returned unchanged as consumed: it
  /// reserves nothing and must not be submitted. Only the oldest held input can be claimed;
  /// a later one is refused as busy.
  public func claimQueuedChatInput(
    _ requestID: ULID, fence: ConversationFence, at now: Int64
  ) throws -> StoredChatTurn {
    try requireOpen()
    return try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      guard var turn = try readTurn(requestID, database: writer),
        turn.chatId.rawValue == fence.conversationID.rawValue
      else { throw StoreError.requestConflict }
      let retained = try writer.integer(
        "SELECT COUNT(*) FROM chat_queued_inputs WHERE request_id = ?",
        [.text(requestID.rawValue)])
      if turn.status == .canceled, turn.userEntryId == nil, turn.piSubmissionId == nil,
        retained == 0
      {
        return turn
      }
      guard !turn.isTerminal, turn.userEntryId == nil, retained == 1 else {
        throw StoreError.requestConflict
      }
      guard try readChatRecovery(turn.chatId, database: writer) == nil else {
        throw StoreError.chatRecoveryRequired
      }
      guard
        try writer.text(
          "SELECT request_id FROM chat_queued_inputs WHERE conversation_id = ? ORDER BY rowid LIMIT 1",
          [.text(turn.chatId.rawValue)]) == requestID.rawValue,
        try writer.integer(
          """
          SELECT COUNT(*) FROM chat_turns WHERE conversation_id = ? AND request_id != ?
            AND status IN ('queued', 'running', 'waiting')
            AND json_extract(record, '$.queueReason') IS NULL
          """, [.text(turn.chatId.rawValue), .text(requestID.rawValue)]) == 0
      else { throw StoreError.chatBusy }
      turn.queueReason = nil
      try writeTurn(turn)
      return turn
    }
  }

  /// Returns a claim only when Pi has not admitted it. No request ID or content is replaced.
  public func returnQueuedChatInput(
    _ requestID: ULID, fence: ConversationFence, at now: Int64
  ) throws {
    try requireOpen()
    try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      guard var turn = try readTurn(requestID, database: writer), !turn.isTerminal,
        turn.chatId.rawValue == fence.conversationID.rawValue,
        turn.userEntryId == nil, turn.piSubmissionId == nil,
        try writer.integer(
          "SELECT COUNT(*) FROM chat_queued_inputs WHERE request_id = ?",
          [.text(requestID.rawValue)]) == 1
      else { throw StoreError.requestConflict }
      turn.queueReason = .resume
      try writeTurn(turn)
    }
  }

  /// Runs inside the abort receipt transaction. Canceling unsent input never aborts the
  /// held Pi task, clears its recovery evidence, or selects a newer input on replay.
  func cancelQueuedChatInput(_ requestID: ULID, chatID: ConversationID, at now: Int64) throws
    -> [EventEnvelope]
  {
    guard var turn = try readTurn(requestID, database: writer), turn.chatId == chatID else {
      throw StoreError.chatNotFound
    }
    if turn.status == .canceled && turn.userEntryId == nil { return [] }
    guard !turn.isTerminal, turn.userEntryId == nil, turn.piSubmissionId == nil,
      turn.queueReason != nil,
      try writer.integer(
        "SELECT COUNT(*) FROM chat_queued_inputs WHERE request_id = ?",
        [.text(requestID.rawValue)]) == 1
    else { throw StoreError.requestConflict }
    guard let chat = try readConversation(chatID, database: writer) else {
      throw StoreError.chatNotFound
    }
    turn.status = .canceled
    turn.stopReason = .aborted
    turn.queueReason = nil
    try writeTurn(turn)
    try writer.execute(
      "DELETE FROM chat_queued_inputs WHERE request_id = ?", [.text(requestID.rawValue)])
    let task = try taskRecord(turn, chat: chat, at: now)
    try writeRecord(.task(task))
    return [
      try append(
        turnEvent(
          turn, chat: chat, at: now,
          subject: ObjectRef(kind: "task", id: task.id.rawValue),
          event: .taskFinished(
            TaskFinishedPayload(
              taskId: task.id, status: .canceled, outcome: .canceled, usage: task.usage,
              durationMs: max(0, now - turn.createdAt)))))
    ]
  }
}
