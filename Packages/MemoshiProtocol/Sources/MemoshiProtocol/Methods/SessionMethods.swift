/// A working thread led by one bot, with its own Pi store: the development subset of
/// object-model.md §4.6. It renders its lead bot's identity, persona and job, and uses the
/// lead bot's model and effort.
public struct Session: Codable, Hashable, Sendable {
  /// The Session.
  public var id: SessionID
  /// The bot that leads it.
  public var leadBotId: BotID
  /// Its title, at most 120 characters.
  public var title: String
  /// Creation time in Unix milliseconds.
  public var createdAt: Int64

  /// Creates a Session record.
  public init(id: SessionID, leadBotId: BotID, title: String, createdAt: Int64) {
    self.id = id
    self.leadBotId = leadBotId
    self.title = title
    self.createdAt = createdAt
  }
}

/// `sessions.create`: opens a Session without a project. Its messages use `chats.send`,
/// `chats.history` and `chats.abort` with the Session's ID.
public enum SessionsCreate: RPCMethod {
  /// The lead bot and an optional title.
  public typealias Params = SessionsCreateParams
  /// The new Session.
  public typealias Result = SessionsCreateResult
  /// `sessions.create`.
  public static let name = "sessions.create"
  /// Creates a Session.
  public static let isMutating = true
}

/// The parameters of `sessions.create`.
public struct SessionsCreateParams: Codable, Hashable, Sendable, IdempotentParams {
  /// The client's idempotency key.
  public var requestId: ULID
  /// The bot that leads the Session.
  public var leadBotId: BotID
  /// A title; absent means a default title.
  public var title: String?

  /// Creates create parameters.
  public init(requestId: ULID, leadBotId: BotID, title: String? = nil) {
    self.requestId = requestId
    self.leadBotId = leadBotId
    self.title = title
  }
}

/// The result of `sessions.create`: a historical receipt, not current state.
public struct SessionsCreateResult: Codable, Hashable, Sendable {
  /// The Session as this request created it; a replay returns it unchanged.
  public var session: Session
  /// `true` when this is the stored result of an earlier request with the same `requestId`.
  public var replayed: Bool?

  /// Creates a create result.
  public init(session: Session, replayed: Bool? = nil) {
    self.session = session
    self.replayed = replayed
  }
}
