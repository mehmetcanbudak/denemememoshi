import Foundation
import MemoshiProtocol

/// Content-free submission outbox and projection state. Numeric Pi identities never cross RPC.
public struct StoredChatTurn: Codable, Hashable, Sendable {
  /// The original idempotent send key, retained through admission and replay.
  public let requestId: ULID
  /// The Chat or Session whose Pi store owns this turn.
  public let chatId: ConversationID
  /// Canonical parameter digest used to reject conflicting reuse of the send key.
  public let paramsHash: String
  /// The selected provider/model and thinking level for this turn; a retry reuses both.
  public let model: ModelRef
  /// Stable user-message identity, reserved before Pi admission.
  public let messageId: MessageID
  /// Stable reply identity, reserved before generation starts.
  public let assistantMessageId: MessageID
  /// The application task projected from the Pi submission.
  public let taskId: TaskID
  /// Admission time in Unix milliseconds.
  public let createdAt: Int64
  /// Pi's store-local submission identity, absent before successful admission.
  public internal(set) var piSubmissionId: Int?
  /// Immutable Pi entry backing the user message, absent until committed.
  public internal(set) var userEntryId: Int?
  /// Immutable Pi entry backing the reply, absent until committed.
  public internal(set) var assistantEntryId: Int?
  /// Whether the reply's application message-created fact has been projected.
  public internal(set) var assistantStarted = false
  /// Last committed application task state; terminal states cannot reopen.
  public internal(set) var status = TaskStatus.queued
  /// Settled reply termination reason, when known.
  public internal(set) var stopReason: StopReason?
  /// Projected usage metadata; transcript content remains in Pi.
  public internal(set) var usage: Usage?
  /// Sanitized failure information without raw provider response bodies.
  public internal(set) var error: MessageError?
  /// Why an accepted input is still outside Pi; nil after actual admission or cancellation.
  public internal(set) var queueReason: WaitingOn?
  /// An uncertain unsafe step keeps its original turn waiting until actual settlement.
  public internal(set) var recoveryStep: InterruptedStep?
  /// A restart cut this admitted turn off and Pi continued it by itself (`task.resumed` by
  /// `system`); nil when that never happened.
  public internal(set) var resumedAfterInterruption: Bool?
  /// Original admission sequence, retained unchanged in every replayed send receipt.
  public internal(set) var writtenSeq: Int64 = 0

  /// Whether admission/reconciliation must still inspect the Pi submission.
  public var isTerminal: Bool { status == .done || status == .failed || status == .canceled }

  /// The persistent send receipt. It never contains transcript text.
  public func receipt(replayed: Bool) -> ChatsSendResult {
    ChatsSendResult(
      messageId: messageId, taskId: taskId, writtenSeq: writtenSeq, replayed: replayed)
  }
}

/// A stable message identity and its Pi entry reference, without transcript content.
public struct IndexedChatMessage: Codable, Hashable, Sendable {
  /// Stable application identity exposed to history consumers.
  public let id: MessageID
  /// Owning Chat, independent of any current UI selection.
  public let conversationId: ConversationID
  /// Turn that produced this message.
  public let taskId: TaskID
  /// Whether the referenced entry is user input or a bot reply.
  public let role: MessageRole
  /// Message creation time in Unix milliseconds.
  public let createdAt: Int64
  /// Original send key for a user message; absent on bot replies.
  public let requestId: ULID?
  /// Store-local immutable Pi entry; nil while only identity is reserved.
  public var piEntryId: Int?
  /// Reply termination reason recorded when its Pi entry settles.
  public var stopReason: StopReason?
  /// Set on a reply whose turn Pi continued after a restart cut it off.
  public var resumedAfterInterruption: Bool?
}

/// One bounded, ascending message-index page and its read-transaction watermark.
public struct ChatIndexPage: Sendable {
  /// Committed message references ordered oldest to newest within this page.
  public let items: [IndexedChatMessage]
  /// Exclusive cursor for the next older page, absent at the history boundary.
  public let nextBefore: MessageID?
  /// Application metadata watermark captured in the same read transaction.
  public let asOf: AsOf
  /// Explicit recovery requirements read at the same watermark as the message indexes.
  public let recovery: ChatRecoveryHold?
  /// Accepted but unsubmitted content, separate from canonical history.
  public let queued: [QueuedChatMessage]
}

/// Captures cancellation's original target; replaying Stop must never select a later turn.
public struct StoredChatAbort: Codable, Hashable, Sendable {
  /// Idempotency key for this cancellation intent.
  public let requestId: ULID
  /// Original target send key; nil records that there was no active turn.
  public let targetRequestID: ULID?
}

extension Store {
  /// A committed receipt for one original mutation request, read before any current check so a
  /// retry never executes again. Pending purges reserve the same method/parameter identity
  /// before a receipt exists. Conflicting reuse throws; a receipt is historical, not current state.
  public func requestReceipt<Value: Decodable & Sendable>(
    _ requestID: ULID, method: String, paramsHash: String, as type: Value.Type
  ) throws -> Value? {
    try requireOpen()
    return try writer.transaction(write: false) {
      try requestResult(requestID, method: method, paramsHash: paramsHash, as: type)
    }
  }

  func requestResult<Value: Decodable>(
    _ requestID: ULID, method: String, paramsHash: String, as type: Value.Type
  ) throws -> Value? {
    let rows = try writer.query(
      "SELECT method, params_hash, result FROM requests WHERE request_id = ?",
      [.text(requestID.rawValue)]
    ) { (try $0.requiredText(0), try $0.requiredText(1), try $0.requiredData(2)) }
    guard let row = rows.first else {
      if let reservedHash = try writer.text(
        "SELECT params_hash FROM session_purge_jobs WHERE request_id = ?",
        [.text(requestID.rawValue)])
      {
        guard method == TrashEmpty.name, paramsHash == reservedHash else {
          throw StoreError.requestConflict
        }
      }
      return nil
    }
    guard row.0 == method, row.1 == paramsHash else { throw StoreError.requestConflict }
    return try decoder.decode(type, from: row.2)
  }

  func saveRequest<Value: Encodable>(
    _ requestID: ULID, method: String, paramsHash: String, result: Value, at now: Int64
  ) throws {
    try writer.execute(
      "INSERT INTO requests (request_id, method, params_hash, result, created_at) VALUES (?, ?, ?, ?, ?)",
      [
        .text(requestID.rawValue), .text(method), .text(paramsHash),
        .json(try encoder.encode(result)), .integer(now),
      ])
  }

  func readTurn(_ requestID: ULID, database: SQLiteConnection) throws -> StoredChatTurn? {
    try database.query(
      "SELECT record FROM chat_turns WHERE request_id = ?", [.text(requestID.rawValue)]
    ) { try decoder.decode(StoredChatTurn.self, from: $0.requiredData(0)) }.first
  }

  func writeTurn(_ turn: StoredChatTurn) throws {
    try writer.execute(
      "UPDATE chat_turns SET status = ?, record = ? WHERE request_id = ?",
      [
        .text(turn.status.rawValue), .json(try encoder.encode(turn)),
        .text(turn.requestId.rawValue),
      ])
  }

  func writeMessageIndex(_ message: IndexedChatMessage) throws {
    try writer.execute(
      """
      INSERT INTO message_indexes (id, conversation_id, pi_entry_id, record) VALUES (?, ?, ?, ?)
      ON CONFLICT (id) DO UPDATE SET pi_entry_id = excluded.pi_entry_id, record = excluded.record
      """,
      [
        .text(message.id.rawValue), .text(message.conversationId.rawValue),
        message.piEntryId.map { .integer(Int64($0)) } ?? .null,
        .json(try encoder.encode(message)),
      ])
  }
}
