import Foundation
import MemoshiProtocol

extension Store {
  /// Reads configured providers and opaque references, never credential values.
  public func modelProviders() throws -> StoreSnapshot<[ModelProviderConfiguration]> {
    try requireOpen()
    return try reader.transaction(write: false) {
      let providers = try reader.query("SELECT record FROM model_providers ORDER BY id") {
        try decoder.decode(ModelProviderConfiguration.self, from: $0.requiredData(0))
      }
      return StoreSnapshot(value: providers, asOf: try position(conversationID: nil))
    }
  }

  /// Commits configuration and its idempotent receipt together. The runtime admits the provider
  /// and its endpoint scope from its provider table, which also supplies the display name.
  public func configureProvider(
    _ params: ModelsProvidersConfigureParams, name: String, paramsHash: String, at now: Int64
  ) throws -> ModelsProvidersConfigureResult {
    try requireOpen()
    var events: [EventEnvelope] = []
    let result = try writer.transaction(write: true) {
      if var previous = try requestResult(
        params.requestId, method: ModelsProvidersConfigure.name, paramsHash: paramsHash,
        as: ModelsProvidersConfigureResult.self)
      {
        previous.replayed = true
        return previous
      }
      let provider = ModelProviderConfiguration(
        id: params.providerId, name: name, baseUrl: params.baseUrl, secretRef: params.secretRef)
      try writer.execute(
        "INSERT INTO model_providers (id, record) VALUES (?, ?) ON CONFLICT (id) DO UPDATE SET record = excluded.record",
        [.text(provider.id), .json(try encoder.encode(provider))])
      let event = try append(
        EventDraft(
          ts: now, actor: Actor(kind: .user), subject: ObjectRef(kind: "system", id: "models"),
          event: .systemSettingsChanged(
            SystemSettingsChangedPayload(
              keys: ["models.providers." + provider.id],
              values: ["models.providers." + provider.id: .string(provider.baseUrl)]))))
      events.append(event)
      guard let seq = event.seq else {
        throw StoreError.invalidCommit("Provider configuration event must be durable")
      }
      let result = ModelsProvidersConfigureResult(
        provider: provider, writtenSeq: seq, replayed: false)
      try saveRequest(
        params.requestId, method: ModelsProvidersConfigure.name,
        paramsHash: paramsHash, result: result, at: now)
      return result
    }
    eventBus.publish(events)
    return result
  }

  /// Reads the durable outbox identity independently of any visible transcript.
  public func chatTurn(_ requestID: ULID) throws -> StoredChatTurn? {
    try requireOpen()
    return try readTurn(requestID, database: reader)
  }

  /// Enumerates metadata for reconciliation; text is never duplicated in this collection.
  public func chatTurns(_ chatID: ConversationID, activeOnly: Bool = false) throws
    -> StoreSnapshot<[StoredChatTurn]>
  {
    try requireOpen()
    return try reader.transaction(write: false) {
      let filter = activeOnly ? " AND status IN ('queued', 'running', 'waiting')" : ""
      let items = try reader.query(
        "SELECT record FROM chat_turns WHERE conversation_id = ?\(filter) ORDER BY request_id",
        [.text(chatID.rawValue)]
      ) { try decoder.decode(StoredChatTurn.self, from: $0.requiredData(0)) }
      return StoreSnapshot(value: items, asOf: try position(conversationID: chatID))
    }
  }

  /// Reads a bounded index page; the runtime resolves its entry references through Pi storage.
  public func chatMessagePage(_ params: ChatsHistoryParams) throws -> ChatIndexPage {
    try requireOpen()
    guard (1...200).contains(params.limit) else {
      throw StoreError.invalidCommit("History limit must be 1...200")
    }
    return try reader.transaction(write: false) {
      let chatExists =
        try reader.integer(
          "SELECT COUNT(*) FROM chats WHERE id = ?", [.text(params.chatId.rawValue)]) == 1
      guard chatExists else { throw StoreError.chatNotFound }
      var filter = ""
      var values: [SQLiteConnection.Value] = [.text(params.chatId.rawValue)]
      if let before = params.before {
        guard
          try reader.integer(
            "SELECT COUNT(*) FROM message_indexes WHERE conversation_id = ? AND id = ?",
            [.text(params.chatId.rawValue), .text(before.rawValue)]) == 1
        else { throw StoreError.invalidCommit("Unknown history cursor") }
        filter = " AND id < ?"
        values.append(.text(before.rawValue))
      }
      values.append(.integer(Int64(params.limit + 1)))
      let rows = try reader.query(
        "SELECT record FROM message_indexes WHERE conversation_id = ? AND pi_entry_id IS NOT NULL\(filter) ORDER BY id DESC LIMIT ?",
        values
      ) { try decoder.decode(IndexedChatMessage.self, from: $0.requiredData(0)) }
      let selected = Array(rows.prefix(params.limit).reversed())
      return ChatIndexPage(
        items: selected, nextBefore: rows.count > params.limit ? selected.first?.id : nil,
        asOf: try position(conversationID: params.chatId),
        recovery: try readChatRecovery(params.chatId, database: reader),
        queued: try readQueuedChatMessages(params.chatId, database: reader))
    }
  }

  /// Captures the initial cancellation target transactionally; a replay never targets new work.
  public func prepareChatAbort(
    _ params: ChatsAbortParams, paramsHash: String, fence: ConversationFence, at now: Int64
  ) throws -> StoredChatAbort {
    try requireOpen()
    var events: [EventEnvelope] = []
    let result = try writer.transaction(write: true) {
      if let previous = try requestResult(
        params.requestId, method: ChatsAbort.name,
        paramsHash: paramsHash, as: StoredChatAbort.self)
      {
        return previous
      }
      guard fence.conversationID.rawValue == params.chatId.rawValue else {
        throw StoreError.invalidCommit("Wrong Chat cancellation fence")
      }
      try checkFence(fence, at: now)
      guard
        try writer.integer(
          "SELECT COUNT(*) FROM chats WHERE id = ?", [.text(params.chatId.rawValue)]) == 1
      else { throw StoreError.chatNotFound }
      let target: ULID?
      if let queued = params.queuedRequestId {
        events += try cancelQueuedChatInput(queued, chatID: params.chatId, at: now)
        target = queued
      } else {
        let key = try writer.text(
          """
          SELECT request_id FROM chat_turns WHERE conversation_id = ?
            AND status IN ('queued', 'running', 'waiting')
            AND json_extract(record, '$.queueReason') IS NULL
          """, [.text(params.chatId.rawValue)])
        target = try key.map(ULID.init)
      }
      let result = StoredChatAbort(requestId: params.requestId, targetRequestID: target)
      try saveRequest(
        params.requestId, method: ChatsAbort.name, paramsHash: paramsHash, result: result, at: now)
      return result
    }
    eventBus.publish(events)
    return result
  }
}
