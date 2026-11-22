import Foundation
import MemoshiProtocol

/// Refusals of a bot or Session change. A refused change writes nothing and stores no receipt.
public enum ConversationRecordError: Error, Equatable, Sendable {
  /// A name, job, persona, title or model value outside its documented limits.
  case invalidProfile
  /// No such bot.
  case botNotFound
  /// Another bot already has this name, ignoring case.
  case nameTaken
  /// The bot changed since the revision the edit expected.
  case staleRevision(current: Int64)
}

extension Store {
  /// The documented profile limits (object-model.md §4.3, §4.6), in Characters.
  public enum ProfileLimits {
    /// A bot's single-line name.
    public static let name = 40
    /// A bot's job.
    public static let job = 280
    /// A bot's persona body.
    public static let persona = 4_000
    /// A Session's title.
    public static let title = 120
  }

  /// Bootstraps the Assistant and its one Chat once; repeated launches preserve both.
  public func ensureAssistantChat(at now: Int64) throws -> ChatSummary {
    try requireOpen()
    var events: [EventEnvelope] = []
    let result = try writer.transaction(write: true) {
      if let existing = try readConversations(
        "WHERE c.kind = 'assistant'", [], database: writer
      ).first {
        return existing
      }
      let bot = try IDGenerator.shared.objectID(BotIDKind.self)
      let chat = try IDGenerator.shared.objectID(ChatIDKind.self)
      try insertBot(bot, role: .assistant, name: "Assistant", at: now)
      try writer.execute(
        "INSERT INTO chats (id, kind, bot_id, title, created_at) VALUES (?, 'assistant', ?, NULL, ?)",
        [.text(chat.rawValue), .text(bot.rawValue), .integer(now)])
      events = try appendBotCreation(
        botID: bot, chatID: chat, name: "Assistant", role: .assistant,
        actor: Actor(kind: .system), at: now)
      return ChatSummary(
        id: try ConversationID(chat.rawValue), kind: .assistant, botId: bot, title: "Assistant",
        createdAt: now)
    }
    eventBus.publish(events)
    return result
  }

  /// Lists every conversation and the same read transaction's global position: the Assistant's
  /// Chat first, then other bots' Chats, then Sessions, each in creation order.
  public func chats() throws -> StoreSnapshot<[ChatSummary]> {
    try requireOpen()
    return try reader.transaction(write: false) {
      StoreSnapshot(
        value: try readConversations("", [], database: reader),
        asOf: try position(conversationID: nil))
    }
  }

  /// One conversation's current summary, or nil when it does not exist.
  public func conversation(_ id: ConversationID) throws -> ChatSummary? {
    try requireOpen()
    return try readConversation(id, database: reader)
  }

  /// Conversations whose work must be reconciled at startup: an admitted, running, waiting or
  /// queued turn, or a recovery hold. Every other conversation opens on first use.
  public func conversationsNeedingResume() throws -> [ChatSummary] {
    try requireOpen()
    return try reader.transaction(write: false) {
      try readConversations("", [], database: reader).filter { conversation in
        try hasActiveTurn(conversation.id, database: reader)
          || reader.integer(
            "SELECT COUNT(*) FROM tasks WHERE conversation_id = ? AND status IN ('queued', 'running', 'waiting')",
            [.text(conversation.id.rawValue)]) != 0
          || readChatRecovery(conversation.id, database: reader) != nil
      }
    }
  }

  /// Whether a conversation has no turn in flight, no queued input, no pending card or
  /// approval and no recovery hold, so its Pi store may close until next use.
  public func conversationIsIdle(_ id: ConversationID) throws -> Bool {
    try requireOpen()
    return try reader.transaction(write: false) {
      let value: [SQLiteConnection.Value] = [.text(id.rawValue)]
      return try !hasActiveTurn(id, database: reader)
        && reader.integer(
          "SELECT COUNT(*) FROM tasks WHERE conversation_id = ? AND status IN ('queued', 'running', 'waiting')",
          value) == 0
        && reader.integer(
          "SELECT COUNT(*) FROM chat_queued_inputs WHERE conversation_id = ?", value) == 0
        && reader.integer(
          "SELECT COUNT(*) FROM cards WHERE conversation_id = ? AND status = 'pending'", value) == 0
        && reader.integer(
          "SELECT COUNT(*) FROM approvals WHERE conversation_id = ? AND status = 'pending'", value)
          == 0
        && readChatRecovery(id, database: reader) == nil
    }
  }

  /// Every bot, the Assistant first, then in creation order.
  public func bots() throws -> StoreSnapshot<[Bot]> {
    try requireOpen()
    return try reader.transaction(write: false) {
      StoreSnapshot(
        value: try readBots("", [], database: reader), asOf: try position(conversationID: nil))
    }
  }

  /// One bot's current profile, read at the point of use.
  public func bot(_ id: BotID) throws -> StoreSnapshot<Bot?> {
    try requireOpen()
    return try reader.transaction(write: false) {
      StoreSnapshot(
        value: try readBots("WHERE b.id = ?", [.text(id.rawValue)], database: reader).first,
        asOf: try position(conversationID: nil))
    }
  }

  /// Creates a bot and its one Chat in one transaction. Replaying the original request returns
  /// its original receipt; reusing the key with other parameters is refused.
  public func createBot(
    _ params: BotsCreateParams, paramsHash: String, at now: Int64
  ) throws -> BotsCreateResult {
    try requireOpen()
    var events: [EventEnvelope] = []
    let receipt = try writer.transaction(write: true) {
      if var previous = try requestResult(
        params.requestId, method: BotsCreate.name, paramsHash: paramsHash,
        as: BotsCreateResult.self)
      {
        previous.replayed = true
        return previous
      }
      let name = try Self.profileName(params.name)
      let bot = try IDGenerator.shared.objectID(BotIDKind.self)
      let chat = try IDGenerator.shared.objectID(ChatIDKind.self)
      try insertBot(bot, role: .bot, name: name, at: now)
      try writer.execute(
        "INSERT INTO chats (id, kind, bot_id, title, created_at) VALUES (?, 'bot', ?, NULL, ?)",
        [.text(chat.rawValue), .text(bot.rawValue), .integer(now)])
      guard
        let created = try readBots("WHERE b.id = ?", [.text(bot.rawValue)], database: writer).first
      else { throw ConversationRecordError.botNotFound }
      events = try appendBotCreation(
        botID: bot, chatID: chat, name: created.name, role: .bot,
        actor: Actor(kind: .user), at: now)
      let result = BotsCreateResult(bot: created, chatId: chat, replayed: false)
      try saveRequest(
        params.requestId, method: BotsCreate.name, paramsHash: paramsHash, result: result, at: now)
      return result
    }
    eventBus.publish(events)
    return receipt
  }

  /// Applies one profile edit at exactly the expected revision. A change advances the revision
  /// by one; an edit that changes nothing keeps it. The receipt is checked first, so a retried
  /// original edit returns its original result and never applies again.
  public func updateBot(
    _ params: BotsUpdateParams, paramsHash: String, at now: Int64
  ) throws -> BotsUpdateResult {
    try requireOpen()
    var events: [EventEnvelope] = []
    let receipt = try writer.transaction(write: true) {
      if var previous = try requestResult(
        params.requestId, method: BotsUpdate.name, paramsHash: paramsHash,
        as: BotsUpdateResult.self)
      {
        previous.replayed = true
        return previous
      }
      guard
        var bot = try readBots("WHERE b.id = ?", [.text(params.botId.rawValue)], database: writer)
          .first
      else { throw ConversationRecordError.botNotFound }
      guard bot.revision == params.expectedRevision else {
        throw ConversationRecordError.staleRevision(current: bot.revision)
      }
      let previous = bot
      // Only a name that becomes a different name is checked and re-keyed: bots stored before
      // names were compared canonically may already share one, and must stay editable.
      var renamedKey: String?
      if let name = params.patch.name {
        bot.name = try Self.profileName(name)
        let key = Self.nameKey(bot.name)
        if key != Self.nameKey(previous.name) {
          guard try !nameIsTaken(bot.name, except: bot.id) else {
            throw ConversationRecordError.nameTaken
          }
          renamedKey = key
        }
      }
      if let job = params.patch.job {
        guard job.count <= ProfileLimits.job else { throw ConversationRecordError.invalidProfile }
        bot.job = job
      }
      if let persona = params.patch.persona {
        guard persona.count <= ProfileLimits.persona else {
          throw ConversationRecordError.invalidProfile
        }
        bot.persona = persona
      }
      if let model = params.patch.model {
        guard model.effort?.isKnown ?? true else { throw ConversationRecordError.invalidProfile }
        bot.model = model
      }
      if bot != previous {
        guard bot.revision < Int64.max else { throw StoreError.sequenceExhausted }
        bot.revision += 1
        bot.updatedAt = max(now, bot.createdAt)
        try writer.execute(
          """
          UPDATE bots SET name = ?, name_key = COALESCE(?, name_key), job = ?, persona = ?,
            model_ref = ?, effort = ?, revision = ?, updated_at = ?
          WHERE id = ? AND revision = ?
          """,
          [
            .text(bot.name), SQLiteConnection.Value(renamedKey), .text(bot.job),
            .text(bot.persona),
            .text(bot.model.ref.rawValue), bot.model.effort.map { .text($0.rawValue) } ?? .null,
            .integer(bot.revision), .integer(bot.updatedAt), .text(bot.id.rawValue),
            .integer(previous.revision),
          ])
        var changed: [String] = []
        if bot.name != previous.name { changed.append("name") }
        if bot.job != previous.job { changed.append("job") }
        if bot.persona != previous.persona { changed.append("persona") }
        if bot.model != previous.model { changed.append("model") }
        events = [
          try append(
            EventDraft(
              ts: now, actor: Actor(kind: .user),
              subject: ObjectRef(kind: "bot", id: bot.id.rawValue),
              scope: EventScope(botId: bot.id),
              event: .botUpdated(.init(changed: changed, revision: bot.revision))))
        ]
      }
      let result = BotsUpdateResult(bot: bot, replayed: false)
      try saveRequest(
        params.requestId, method: BotsUpdate.name, paramsHash: paramsHash, result: result, at: now)
      return result
    }
    eventBus.publish(events)
    return receipt
  }

  /// Opens a Session led by an existing bot. Its transcript later lives in its own Pi store.
  public func createSession(
    _ params: SessionsCreateParams, paramsHash: String, at now: Int64
  ) throws -> SessionsCreateResult {
    try requireOpen()
    var events: [EventEnvelope] = []
    let receipt = try writer.transaction(write: true) {
      if var previous = try requestResult(
        params.requestId, method: SessionsCreate.name, paramsHash: paramsHash,
        as: SessionsCreateResult.self)
      {
        previous.replayed = true
        return previous
      }
      guard
        try writer.integer(
          "SELECT COUNT(*) FROM bots WHERE id = ?", [.text(params.leadBotId.rawValue)]) == 1
      else { throw ConversationRecordError.botNotFound }
      let title = try Self.singleLine(params.title ?? "New session", limit: ProfileLimits.title)
      let session = Session(
        id: try IDGenerator.shared.objectID(SessionIDKind.self), leadBotId: params.leadBotId,
        title: title, createdAt: now)
      try writer.execute(
        "INSERT INTO chats (id, kind, bot_id, title, created_at) VALUES (?, 'session', ?, ?, ?)",
        [
          .text(session.id.rawValue), .text(session.leadBotId.rawValue), .text(title),
          .integer(now),
        ])
      let origin = Origin(kind: .user, rootKind: .user, hops: .root)
      events = [
        try append(
          EventDraft(
            ts: now, actor: Actor(kind: .user),
            subject: ObjectRef(kind: "session", id: session.id.rawValue),
            scope: EventScope(
              botId: session.leadBotId, conversationId: try ConversationID(session.id.rawValue)),
            origin: origin,
            event: .sessionCreated(.init(leadBotId: session.leadBotId, origin: origin))))
      ]
      let result = SessionsCreateResult(session: session, replayed: false)
      try saveRequest(
        params.requestId, method: SessionsCreate.name, paramsHash: paramsHash, result: result,
        at: now)
      return result
    }
    eventBus.publish(events)
    return receipt
  }

  private func appendBotCreation(
    botID: BotID, chatID: ChatID, name: String, role: BotRole, actor: Actor, at now: Int64
  ) throws -> [EventEnvelope] {
    [
      try append(
        EventDraft(
          ts: now, actor: actor, subject: ObjectRef(kind: "bot", id: botID.rawValue),
          scope: EventScope(botId: botID),
          event: .botCreated(.init(name: name, role: role, createdBy: actor, chatId: chatID)))),
      try append(
        EventDraft(
          ts: now, actor: actor, subject: ObjectRef(kind: "chat", id: chatID.rawValue),
          scope: EventScope(botId: botID, conversationId: try ConversationID(chatID.rawValue)),
          event: .chatCreated(.init(botId: botID)))),
    ]
  }

  func readConversation(_ id: ConversationID, database: SQLiteConnection) throws -> ChatSummary? {
    try readConversations("WHERE c.id = ?", [.text(id.rawValue)], database: database).first
  }

  private func readConversations(
    _ filter: String, _ values: [SQLiteConnection.Value], database: SQLiteConnection
  ) throws -> [ChatSummary] {
    try database.query(
      """
      SELECT c.id, c.kind, c.bot_id, COALESCE(c.title, b.name), c.created_at
      FROM chats c JOIN bots b ON b.id = c.bot_id
      \(filter.isEmpty ? "WHERE" : filter + " AND") c.deleted_at IS NULL
      ORDER BY CASE c.kind WHEN 'assistant' THEN 0 WHEN 'bot' THEN 1 ELSE 2 END, c.id
      """, values
    ) { row in
      ChatSummary(
        id: try ConversationID(row.requiredText(0)),
        kind: ConversationKind(rawValue: try row.requiredText(1)),
        botId: try BotID(row.requiredText(2)), title: try row.requiredText(3),
        createdAt: row.integer(4))
    }
  }

  private func readBots(
    _ filter: String, _ values: [SQLiteConnection.Value], database: SQLiteConnection
  ) throws -> [Bot] {
    try database.query(
      """
      SELECT b.id, b.role, b.name, b.job, b.persona, b.model_ref, b.effort, b.revision, c.id,
        b.created_at, b.updated_at
      FROM bots b JOIN chats c ON c.bot_id = b.id AND c.kind != 'session' \(filter)
      ORDER BY CASE b.role WHEN 'assistant' THEN 0 ELSE 1 END, b.id
      """, values
    ) { row in
      Bot(
        id: try BotID(row.requiredText(0)), role: BotRole(rawValue: try row.requiredText(1)),
        name: try row.requiredText(2), job: try row.requiredText(3),
        persona: try row.requiredText(4),
        model: ModelRef(
          ref: try ModelName(row.requiredText(5)),
          effort: row.text(6).map(ThinkingEffort.init(rawValue:))),
        revision: row.integer(7), chatId: try ChatID(row.requiredText(8)),
        createdAt: row.integer(9), updatedAt: row.integer(10))
    }
  }

  private func insertBot(_ id: BotID, role: BotRole, name: String, at now: Int64) throws {
    guard try !nameIsTaken(name) else { throw ConversationRecordError.nameTaken }
    let key = Self.nameKey(name)
    try writer.execute(
      """
      INSERT INTO bots (
        id, role, name, name_key, job, persona, model_ref, effort, revision, created_at, updated_at
      ) VALUES (?, ?, ?, ?, '', '', 'default', NULL, 1, ?, ?)
      """,
      [
        .text(id.rawValue), .text(role.rawValue), .text(name), .text(key), .integer(now),
        .integer(now),
      ])
  }

  private func hasActiveTurn(_ id: ConversationID, database: SQLiteConnection) throws -> Bool {
    try database.integer(
      """
      SELECT COUNT(*) FROM chat_turns
      WHERE conversation_id = ? AND status IN ('queued', 'running', 'waiting')
      """, [.text(id.rawValue)]) != 0
  }

  /// A bot's name: one line, without control or bidi formatting characters, 1…40 Characters.
  static func profileName(_ value: String) throws -> String {
    try singleLine(value, limit: ProfileLimits.name)
  }

  /// Strips control, format (including bidi) and line/paragraph separators, then trims.
  static func singleLine(_ value: String, limit: Int) throws -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in value.unicodeScalars {
      switch scalar.properties.generalCategory {
      case .control, .format, .lineSeparator, .paragraphSeparator: continue
      default: scalars.append(scalar)
      }
    }
    let text = String(scalars).trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty, text.count <= limit else { throw ConversationRecordError.invalidProfile }
    return text
  }

  /// Whether another bot holds this name. Every stored name is compared by the key computed
  /// here, so a row keyed by an earlier rule or by migration 9's `lower()` still matches.
  private func nameIsTaken(_ name: String, except id: BotID? = nil) throws -> Bool {
    let key = Self.nameKey(name)
    return try writer.query("SELECT id, name FROM bots") {
      (try $0.requiredText(0), try $0.requiredText(1))
    }.contains { $0.0 != id?.rawValue && Self.nameKey($0.1) == key }
  }

  /// The caseless, canonically composed form by which names are unique: full case folding, so
  /// pairs such as "Straße"/"STRASSE" match, and one byte sequence per canonically equal name.
  static func nameKey(_ name: String) -> String {
    name.folding(options: .caseInsensitive, locale: nil).precomposedStringWithCanonicalMapping
  }
}
