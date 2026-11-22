/// `bot.created` (A): a bot and its Chat were committed. Avatar, Computer and Browser
/// provisioning are not implemented by the Phase 0 profile and are not implied by this fact.
public struct BotCreatedPayload: EventPayload {
  /// `bot.created`.
  public static let eventType = "bot.created"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited
  /// The display name at creation.
  public var name: String
  /// The pinned Assistant or a teammate.
  public var role: BotRole
  /// Who created the bot.
  public var createdBy: Actor
  /// Its one Chat.
  public var chatId: ChatID

  /// Creates the payload.
  public init(name: String, role: BotRole, createdBy: Actor, chatId: ChatID) {
    self.name = name
    self.role = role
    self.createdBy = createdBy
    self.chatId = chatId
  }
  /// `.botCreated(self)`.
  public var asEvent: Event { .botCreated(self) }
}

/// `bot.updated` (A): a profile revision was applied. Bodies remain in the bot record,
/// not a second copy in the event log; consumers reload the profile at this revision.
public struct BotUpdatedPayload: EventPayload {
  /// `bot.updated`.
  public static let eventType = "bot.updated"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited
  /// Fields that actually changed.
  public var changed: [String]
  /// The resulting profile revision.
  public var revision: Int64

  /// Creates the payload.
  public init(changed: [String], revision: Int64) {
    self.changed = changed
    self.revision = revision
  }
  /// `.botUpdated(self)`.
  public var asEvent: Event { .botUpdated(self) }
}

/// `chat.created` (D): the bot's one continuous Chat was committed with its profile.
public struct ChatCreatedPayload: EventPayload {
  /// `chat.created`.
  public static let eventType = "chat.created"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable
  /// The Chat's bot.
  public var botId: BotID

  /// Creates the payload.
  public init(botId: BotID) { self.botId = botId }
  /// `.chatCreated(self)`.
  public var asEvent: Event { .chatCreated(self) }
}

/// `session.created` (D): a project-less Session was committed under its lead bot.
public struct SessionCreatedPayload: EventPayload {
  /// `session.created`.
  public static let eventType = "session.created"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable
  /// The bot that leads the Session.
  public var leadBotId: BotID
  /// Why this Session was opened.
  public var origin: Origin

  /// Creates the payload.
  public init(leadBotId: BotID, origin: Origin) {
    self.leadBotId = leadBotId
    self.origin = origin
  }
  /// `.sessionCreated(self)`.
  public var asEvent: Event { .sessionCreated(self) }
}
