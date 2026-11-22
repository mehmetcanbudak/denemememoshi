/// Whether a bot is the pinned Assistant (object-model.md §4.2) or another teammate.
public enum BotRole: OpenEnum {
  /// The one Assistant; it cannot be archived, deleted or created.
  case assistant
  /// A teammate the user created.
  case bot
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.assistant: "assistant", .bot: "bot"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// A bot's current profile: the development subset of object-model.md §4.3 that every model
/// request renders (identity, persona and job) plus its model and effort.
public struct Bot: Codable, Hashable, Sendable {
  /// The bot.
  public var id: BotID
  /// The Assistant or a teammate; never changes.
  public var role: BotRole
  /// Single-line display name, at most 40 characters, unique ignoring case.
  public var name: String
  /// What it is for, at most 280 characters; empty until set.
  public var job: String
  /// The persona body, at most 4,000 characters; empty until set.
  public var persona: String
  /// `default` or `provider/model`, with the thinking level used when a send names none.
  public var model: ModelRef
  /// The applied profile version; every applied edit advances it by one.
  public var revision: Int64
  /// Its one Chat.
  public var chatId: ChatID
  /// Creation time in Unix milliseconds.
  public var createdAt: Int64
  /// Time of the latest applied edit in Unix milliseconds.
  public var updatedAt: Int64

  /// Creates a profile.
  public init(
    id: BotID, role: BotRole, name: String, job: String, persona: String, model: ModelRef,
    revision: Int64, chatId: ChatID, createdAt: Int64, updatedAt: Int64
  ) {
    self.id = id
    self.role = role
    self.name = name
    self.job = job
    self.persona = persona
    self.model = model
    self.revision = revision
    self.chatId = chatId
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

/// `bots.list`: every bot, the Assistant first.
public enum BotsList: RPCMethod {
  /// The list options.
  public typealias Params = BotsListParams
  /// The bots and the snapshot position.
  public typealias Result = BotsListResult
  /// `bots.list`.
  public static let name = "bots.list"
  /// Read-only.
  public static let isMutating = false
}

/// The parameters of `bots.list`.
public struct BotsListParams: Codable, Hashable, Sendable {
  /// Whether archived bots are listed too.
  public var includeArchived: Bool?

  /// Creates list parameters.
  public init(includeArchived: Bool? = nil) {
    self.includeArchived = includeArchived
  }
}

/// The bots and the position of the read that produced them.
public struct BotsListResult: Codable, Hashable, Sendable {
  /// The bots, the Assistant first, then in creation order.
  public var items: [Bot]
  /// The snapshot position.
  public var asOf: AsOf

  /// Creates a list result.
  public init(items: [Bot], asOf: AsOf) {
    self.items = items
    self.asOf = asOf
  }
}

/// `bots.get`: one bot's current profile.
public enum BotsGet: RPCMethod {
  /// The bot.
  public typealias Params = BotsGetParams
  /// Its profile and the snapshot position.
  public typealias Result = BotsGetResult
  /// `bots.get`.
  public static let name = "bots.get"
  /// Read-only.
  public static let isMutating = false
}

/// The parameters of `bots.get`.
public struct BotsGetParams: Codable, Hashable, Sendable {
  /// The bot.
  public var botId: BotID

  /// Creates get parameters.
  public init(botId: BotID) {
    self.botId = botId
  }
}

/// One bot and the position of the read that produced it.
public struct BotsGetResult: Codable, Hashable, Sendable {
  /// The bot's current profile.
  public var bot: Bot
  /// The snapshot position.
  public var asOf: AsOf

  /// Creates a get result.
  public init(bot: Bot, asOf: AsOf) {
    self.bot = bot
    self.asOf = asOf
  }
}

/// `bots.create`: creates a bot together with its one Chat. User only (protocol.md §5.2).
public enum BotsCreate: RPCMethod {
  /// The new bot's name.
  public typealias Params = BotsCreateParams
  /// The bot and its Chat.
  public typealias Result = BotsCreateResult
  /// `bots.create`.
  public static let name = "bots.create"
  /// Creates a bot.
  public static let isMutating = true
}

/// The parameters of `bots.create`.
public struct BotsCreateParams: Codable, Hashable, Sendable, IdempotentParams {
  /// The client's idempotency key.
  public var requestId: ULID
  /// The display name.
  public var name: String

  /// Creates create parameters.
  public init(requestId: ULID, name: String) {
    self.requestId = requestId
    self.name = name
  }
}

/// The result of `bots.create`: a historical receipt, not current state.
public struct BotsCreateResult: Codable, Hashable, Sendable {
  /// The bot as this request created it; a replay returns it unchanged.
  public var bot: Bot
  /// Its one Chat.
  public var chatId: ChatID
  /// `true` when this is the stored result of an earlier request with the same `requestId`.
  public var replayed: Bool?

  /// Creates a create result.
  public init(bot: Bot, chatId: ChatID, replayed: Bool? = nil) {
    self.bot = bot
    self.chatId = chatId
    self.replayed = replayed
  }
}

/// `bots.update`: applies one profile edit at the revision the editor saw. The next model
/// request renders the new identity, persona and job, and uses the new model and effort.
public enum BotsUpdate: RPCMethod {
  /// The bot, the edit and the revision it expects.
  public typealias Params = BotsUpdateParams
  /// The bot as the edit left it.
  public typealias Result = BotsUpdateResult
  /// `bots.update`.
  public static let name = "bots.update"
  /// Changes a bot.
  public static let isMutating = true
}

/// The fields one edit changes; an absent field keeps its current value.
public struct BotPatch: Codable, Hashable, Sendable {
  /// A new display name.
  public var name: String?
  /// A new job.
  public var job: String?
  /// A new persona.
  public var persona: String?
  /// A new model and effort; `default` clears the model choice.
  public var model: ModelRef?

  /// Creates a patch.
  public init(
    name: String? = nil, job: String? = nil, persona: String? = nil, model: ModelRef? = nil
  ) {
    self.name = name
    self.job = job
    self.persona = persona
    self.model = model
  }
}

/// The parameters of `bots.update`.
public struct BotsUpdateParams: Codable, Hashable, Sendable, IdempotentParams {
  /// The client's idempotency key.
  public var requestId: ULID
  /// The bot.
  public var botId: BotID
  /// The edit.
  public var patch: BotPatch
  /// The revision the editor saw; a different current revision refuses the edit.
  public var expectedRevision: Int64

  /// Creates update parameters.
  public init(requestId: ULID, botId: BotID, patch: BotPatch, expectedRevision: Int64) {
    self.requestId = requestId
    self.botId = botId
    self.patch = patch
    self.expectedRevision = expectedRevision
  }
}

/// The result of `bots.update`: a historical receipt, not current state.
public struct BotsUpdateResult: Codable, Hashable, Sendable {
  /// The bot as this request left it; a replay returns it unchanged.
  public var bot: Bot
  /// `true` when this is the stored result of an earlier request with the same `requestId`.
  public var replayed: Bool?

  /// Creates an update result.
  public init(bot: Bot, replayed: Bool? = nil) {
    self.bot = bot
    self.replayed = replayed
  }
}
