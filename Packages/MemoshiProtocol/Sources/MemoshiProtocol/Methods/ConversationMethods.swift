/// `events.subscribe`: start the event stream, replaying from a cursor or asking for a resync
/// (protocol.md §8).
public enum EventsSubscribe: RPCMethod {
  /// The cursor and the conversations in focus.
  public typealias Params = EventsSubscribeParams
  /// Replay or resync.
  public typealias Result = EventsSubscribeResult
  /// `events.subscribe`.
  public static let name = "events.subscribe"
  /// Changes only the connection's subscription.
  public static let isMutating = false
}

/// The parameters of `events.subscribe`.
public struct EventsSubscribeParams: Codable, Hashable, Sendable, WireDependent {
  /// The last durable `seq` the client applied; `null` (a cold launch) always means resync.
  public private(set) var after: Int64?
  /// The `ts` of the event at `after`, Unix milliseconds, when the client knows it. A daemon
  /// whose own event at `after` has another time refuses the cursor, as after its log was
  /// restored from a backup (D131). Present only with a non-null `after`.
  public private(set) var afterTs: Int64?
  /// The conversations whose UI-only frames this connection wants, at most 8.
  public var focus: FocusList?

  /// Creates subscribe parameters that state no time for the cursor.
  public init(after: Int64?, focus: FocusList? = nil) {
    self.after = after
    self.focus = focus
  }

  /// Creates subscribe parameters that resume after `after` and state the time of the event
  /// there, when the client knows it.
  public init(after: Int64, afterTs: Int64?, focus: FocusList? = nil) {
    self.after = after
    self.afterTs = afterTs
    self.focus = focus
  }

  /// `afterTs` needs a non-null `after`.
  public static let wireDependencies = ["afterTs": "after"]

  private enum CodingKeys: String, CodingKey {
    case after
    case afterTs
    case focus
  }

  /// Decodes the parameters. `after` must be present, even when it is `null`; `afterTs`
  /// without a non-null `after` fails in both decoding modes.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    after = try container.decode(Int64?.self, forKey: .after)
    afterTs = try container.decodeIfPresent(Int64.self, forKey: .afterTs)
    focus = try container.decodeIfPresent(FocusList.self, forKey: .focus)
    if afterTs != nil, after == nil {
      throw DecodingError.dataCorruptedError(
        forKey: .afterTs, in: container, debugDescription: "afterTs needs a non-null after")
    }
  }

  /// Encodes the parameters, writing `"after": null` for no cursor.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(after, forKey: .after)
    try container.encodeIfPresent(afterTs, forKey: .afterTs)
    try container.encodeIfPresent(focus, forKey: .focus)
  }
}

/// The result of `events.subscribe`.
public struct EventsSubscribeResult: Codable, Hashable, Sendable {
  /// Whether events replay from the cursor or the client must resync.
  public var mode: SubscribeMode
  /// The newest durable `seq`.
  public var head: Int64
  /// The `ts` of the durable event at `head`, Unix milliseconds: what a client that resumes
  /// after `head` states as `afterTs` (D131). Absent when the log is empty or that event is
  /// no longer kept.
  public var headTs: Int64?
  /// The oldest `seq` still retained.
  public var minRetainedSeq: Int64

  /// Creates a subscribe result.
  public init(mode: SubscribeMode, head: Int64, headTs: Int64? = nil, minRetainedSeq: Int64) {
    self.mode = mode
    self.head = head
    self.headTs = headTs
    self.minRetainedSeq = minRetainedSeq
  }
}

/// How a subscription starts.
public enum SubscribeMode: OpenEnum {
  /// Every durable event after the cursor follows.
  case replay
  /// The cursor is too old or `null`: refetch with list and history calls.
  case resync
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.replay: "replay", .resync: "resync"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// `chats.send`: send a message in a bot's Chat or a Session (protocol.md §5.3).
public enum ChatsSend: RPCMethod {
  /// The message.
  public typealias Params = ChatsSendParams
  /// The admission.
  public typealias Result = ChatsSendResult
  /// `chats.send`.
  public static let name = "chats.send"
  /// Admits a message.
  public static let isMutating = true
}

/// The parameters of `chats.send`.
public struct ChatsSendParams: Codable, Hashable, Sendable, IdempotentParams {
  /// The client's idempotency key, passed on to Pi (protocol.md §9).
  public var requestId: ULID
  /// The Chat or Session.
  public var chatId: ConversationID
  /// The message: text, mentions and attachment references.
  public var content: [ContentPart]
  /// What to do while the conversation is busy; the engine's default applies when absent.
  public var whenBusy: WhenBusy?
  /// A per-turn model override; absent means the bot's model and effort.
  public var model: ModelRef?
  /// Where the request came from; absent means `ui`.
  public var surface: RequestSurface?

  /// Creates send parameters.
  public init(
    requestId: ULID, chatId: ConversationID, content: [ContentPart], whenBusy: WhenBusy? = nil,
    model: ModelRef? = nil, surface: RequestSurface? = nil
  ) {
    self.requestId = requestId
    self.chatId = chatId
    self.content = content
    self.whenBusy = whenBusy
    self.model = model
    self.surface = surface
  }
}

/// The result of `chats.send` on admission.
public struct ChatsSendResult: Codable, Hashable, Sendable {
  /// The user message's ID.
  public var messageId: MessageID
  /// The turn's task.
  public var taskId: TaskID
  /// The highest `seq` the request wrote.
  public var writtenSeq: Int64
  /// Set when the turn runs in a side thread because the runner is unreachable.
  public var sideThreadId: SideThreadID?
  /// `true` when this is the stored result of an earlier request with the same `requestId`.
  public var replayed: Bool?

  /// Creates a send result.
  public init(
    messageId: MessageID, taskId: TaskID, writtenSeq: Int64, sideThreadId: SideThreadID? = nil,
    replayed: Bool? = nil
  ) {
    self.messageId = messageId
    self.taskId = taskId
    self.writtenSeq = writtenSeq
    self.sideThreadId = sideThreadId
    self.replayed = replayed
  }
}
