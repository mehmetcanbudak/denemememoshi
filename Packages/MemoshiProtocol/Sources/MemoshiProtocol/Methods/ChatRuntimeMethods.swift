/// What a listed conversation is: the Assistant's Chat, another bot's Chat, or a Session.
public enum ConversationKind: OpenEnum {
  /// The pinned Assistant's one Chat.
  case assistant
  /// Another bot's one Chat.
  case bot
  /// A working thread led by one bot (object-model.md §4.6).
  case session
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .assistant: "assistant", .bot: "bot", .session: "session",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// A content-free conversation list projection: a Chat or a Session. Transcript text is read
/// only through `chats.history`.
public struct ChatSummary: Codable, Hashable, Sendable {
  /// The persistent conversation identity: a Chat's `cht_` or a Session's `ses_`.
  public var id: ConversationID
  /// Which kind of conversation this is.
  public var kind: ConversationKind
  /// The bot whose Chat this is, or the Session's lead bot.
  public var botId: BotID
  /// The bot's current name for a Chat, or the Session's title.
  public var title: String
  /// Creation time in Unix milliseconds.
  public var createdAt: Int64

  /// Creates a content-free list projection.
  public init(
    id: ConversationID, kind: ConversationKind, botId: BotID, title: String, createdAt: Int64
  ) {
    self.id = id
    self.kind = kind
    self.botId = botId
    self.title = title
    self.createdAt = createdAt
  }
}

/// A transcript message resolved from Pi storage, never stored in the application event log.
public struct ChatMessage: Codable, Hashable, Sendable {
  /// The stable application message identity.
  public var id: MessageID
  /// The owning Chat.
  public var conversationId: ConversationID
  /// The turn that owns this message.
  public var taskId: TaskID
  /// User or bot.
  public var role: MessageRole
  /// Text content for this slice.
  public var content: [ContentPart]
  /// Creation time in Unix milliseconds.
  public var createdAt: Int64
  /// The original send key, when this is a user message.
  public var requestId: ULID?
  /// Set for a settled bot message.
  public var stopReason: StopReason?
  /// `true` on a bot message whose turn a restart cut off and the runtime then continued by
  /// itself (`task.resumed` by `system`, events.md §5.5); absent otherwise.
  public var resumedAfterInterruption: Bool?

  /// Creates a resolved transcript message.
  public init(
    id: MessageID, conversationId: ConversationID, taskId: TaskID, role: MessageRole,
    content: [ContentPart], createdAt: Int64, requestId: ULID? = nil,
    stopReason: StopReason? = nil, resumedAfterInterruption: Bool? = nil
  ) {
    self.id = id
    self.conversationId = conversationId
    self.taskId = taskId
    self.role = role
    self.content = content
    self.createdAt = createdAt
    self.requestId = requestId
    self.stopReason = stopReason
    self.resumedAfterInterruption = resumedAfterInterruption
  }
}

/// Current in-flight state, read from the live Pi conversation rather than a UI timer.
public struct ChatLiveState: Codable, Hashable, Sendable {
  /// The actual admitted turn.
  public var taskId: TaskID
  /// The partial bot message, if generation has begun.
  public var message: ChatMessage?
  /// `true` when a restart cut this turn off and the runtime continued it by itself, also
  /// before its continued reply streams; absent otherwise.
  public var resumedAfterInterruption: Bool?

  /// Creates an in-flight projection.
  public init(
    taskId: TaskID, message: ChatMessage? = nil, resumedAfterInterruption: Bool? = nil
  ) {
    self.taskId = taskId
    self.message = message
    self.resumedAfterInterruption = resumedAfterInterruption
  }
}

/// `chats.list`: lists actual persisted conversations, not the design-preview roster: the
/// Assistant's Chat first, then other bots' Chats, then Sessions.
public enum ChatsList: RPCMethod {
  /// No list parameters are required by the development profile.
  public typealias Params = EmptyParams
  /// Persisted conversations and their metadata watermark.
  public typealias Result = ChatsListResult
  /// JSON-RPC method name.
  public static let name = "chats.list"
  /// Listing does not mutate durable state.
  public static let isMutating = false
}

/// A content-free list and its application-store watermark.
public struct ChatsListResult: Codable, Hashable, Sendable {
  /// Actual persisted Chats, without message content.
  public var items: [ChatSummary]
  /// Watermark of the application-store read.
  public var asOf: AsOf

  /// Creates a list snapshot from persisted Chat metadata.
  public init(items: [ChatSummary], asOf: AsOf) {
    self.items = items
    self.asOf = asOf
  }
}

/// `chats.history`: a bounded transcript page read from Pi entries.
public enum ChatsHistory: RPCMethod {
  /// Chat identity, exclusive cursor and bounded page size.
  public typealias Params = ChatsHistoryParams
  /// Committed messages plus separate in-flight state.
  public typealias Result = ChatsHistoryResult
  /// JSON-RPC method name.
  public static let name = "chats.history"
  /// History reads do not mutate durable state.
  public static let isMutating = false
}

/// Reads messages before an exclusive stable message cursor, newest page first.
public struct ChatsHistoryParams: Codable, Hashable, Sendable {
  /// The Chat or Session whose Pi entries are resolved.
  public var chatId: ConversationID
  /// Exclusive cursor into older committed messages.
  public var before: MessageID?
  /// Requested page size; the development runtime accepts 1 through 200.
  public var limit: Int

  /// Requests the newest page unless an older-page cursor is supplied.
  public init(chatId: ConversationID, before: MessageID? = nil, limit: Int = 100) {
    self.chatId = chatId
    self.before = before
    self.limit = limit
  }
}

/// Messages are ordered oldest to newest within a page. `live` is separate from committed text.
public struct ChatsHistoryResult: Codable, Hashable, Sendable {
  /// Committed messages ordered oldest to newest within this page.
  public var items: [ChatMessage]
  /// Current generation, separate from the immutable committed transcript.
  public var live: ChatLiveState?
  /// Cursor for the next older page, absent at the beginning of history.
  public var nextBefore: MessageID?
  /// Committed application-index watermark; live text is not durable event content.
  public var asOf: AsOf
  /// A whole-Chat recovery hold; it is not cleared by sending, Stop or Bypass.
  public var recovery: ChatRecoveryHold?
  /// Accepted but unsubmitted inputs, outside `items` and canonical Pi history.
  public var queued: [QueuedChatMessage]?

  /// Creates an authoritative history page without caching transcript text in events.
  public init(
    items: [ChatMessage], live: ChatLiveState? = nil, nextBefore: MessageID? = nil,
    asOf: AsOf, recovery: ChatRecoveryHold? = nil, queued: [QueuedChatMessage]? = nil
  ) {
    self.items = items
    self.live = live
    self.nextBefore = nextBefore
    self.asOf = asOf
    self.recovery = recovery
    self.queued = queued
  }
}

/// `chats.abort`: stops the actual conversation, not merely its visible stream.
public enum ChatsAbort: RPCMethod {
  /// Idempotent cancellation intent for the selected Chat.
  public typealias Params = ChatsAbortParams
  /// Empty acknowledgment; actual cancellation is observed through task state.
  public typealias Result = EmptyParams
  /// JSON-RPC method name.
  public static let name = "chats.abort"
  /// Cancellation requires a persistent idempotency key.
  public static let isMutating = true
}

/// Idempotent user cancellation of a conversation's current turn.
public struct ChatsAbortParams: Codable, Hashable, Sendable, IdempotentParams {
  /// Original cancellation key, reused when delivery is uncertain.
  public var requestId: ULID
  /// The Chat or Session whose current turn is captured as the cancellation target.
  public var chatId: ConversationID
  /// Reserved broader scope; true is rejected by the text-only development runtime.
  public var includeBackground: Bool?
  /// Cancels this accepted but unsubmitted input only; never the uncertain running step.
  public var queuedRequestId: ULID?

  /// Creates a Stop intent, or targets one durable queued input without invoking Pi.
  public init(
    requestId: ULID, chatId: ConversationID, includeBackground: Bool? = nil,
    queuedRequestId: ULID? = nil
  ) {
    self.requestId = requestId
    self.chatId = chatId
    self.includeBackground = includeBackground
    self.queuedRequestId = queuedRequestId
  }
}

/// A configured model provider. No key or other credential value belongs here.
public struct ModelProviderConfiguration: Codable, Hashable, Sendable {
  /// Provider identity from the runtime's provider table: `local`, `openai`, `anthropic` or
  /// `openrouter`.
  public var id: String
  /// Human-readable provider label.
  public var name: String
  /// Validated endpoint: the local loopback server, or the cloud provider's fixed HTTPS API.
  public var baseUrl: String
  /// Opaque app-Keychain reference, never the credential value.
  public var secretRef: String?

  /// Creates credential-free provider metadata.
  public init(id: String, name: String, baseUrl: String, secretRef: String? = nil) {
    self.id = id
    self.name = name
    self.baseUrl = baseUrl
    self.secretRef = secretRef
  }
}

/// `models.providers.list`: persisted provider settings without credentials.
public enum ModelsProvidersList: RPCMethod {
  /// No parameters are required.
  public typealias Params = EmptyParams
  /// Persisted provider metadata and its watermark.
  public typealias Result = ModelsProvidersListResult
  /// JSON-RPC method name.
  public static let name = "models.providers.list"
  /// Reading provider settings does not mutate them.
  public static let isMutating = false
}

/// Configured providers and their metadata-store watermark.
public struct ModelsProvidersListResult: Codable, Hashable, Sendable {
  /// Explicitly configured providers; no ambient credentials are inferred.
  public var items: [ModelProviderConfiguration]
  /// Watermark of the provider metadata read.
  public var asOf: AsOf

  /// Creates a provider-settings snapshot without credential values.
  public init(items: [ModelProviderConfiguration], asOf: AsOf) {
    self.items = items
    self.asOf = asOf
  }
}

/// `models.providers.configure`: explicit endpoints and opaque app-Keychain references only.
public enum ModelsProvidersConfigure: RPCMethod {
  /// Idempotent configuration intent.
  public typealias Params = ModelsProvidersConfigureParams
  /// Committed setting and the original write sequence.
  public typealias Result = ModelsProvidersConfigureResult
  /// JSON-RPC method name.
  public static let name = "models.providers.configure"
  /// Configuration requires a persistent idempotency key.
  public static let isMutating = true
}

/// Provider settings carry references; credential values are resolved through the authenticated host.
public struct ModelsProvidersConfigureParams: Codable, Hashable, Sendable, IdempotentParams {
  /// Original configuration key, retained for conflict detection and replay.
  public var requestId: ULID
  /// Provider identity from the runtime's provider table; any other id is refused.
  public var providerId: String
  /// A loopback endpoint for `local`; for a cloud provider, exactly its fixed HTTPS base URL.
  public var baseUrl: String
  /// Opaque credential reference. Cloud providers require an API-key reference, or a ChatGPT
  /// sign-in reference for `openai` only; `local` may stay keyless.
  public var secretRef: String?

  /// Creates settings for explicit runtime validation before persistence.
  public init(requestId: ULID, providerId: String, baseUrl: String, secretRef: String? = nil) {
    self.requestId = requestId
    self.providerId = providerId
    self.baseUrl = baseUrl
    self.secretRef = secretRef
  }
}

/// The actual persisted provider and its committed sequence.
public struct ModelsProvidersConfigureResult: Codable, Hashable, Sendable {
  /// The setting committed by this request, including on idempotent replay.
  public var provider: ModelProviderConfiguration
  /// Sequence of the original provider-setting event.
  public var writtenSeq: Int64
  /// True when returning the original receipt without applying the setting again.
  public var replayed: Bool?

  /// Creates a durable configuration receipt.
  public init(provider: ModelProviderConfiguration, writtenSeq: Int64, replayed: Bool? = nil) {
    self.provider = provider
    self.writtenSeq = writtenSeq
    self.replayed = replayed
  }
}

/// A chat-capable model actually returned by the configured endpoint.
public struct AvailableModel: Codable, Hashable, Sendable {
  /// Provider-qualified model choice, not a credential.
  public var ref: ModelRef
  /// Display name returned by discovery.
  public var name: String
  /// Context-window token count supplied by the PiAI model catalog.
  public var contextWindow: Int
  /// Output-token ceiling supplied by the PiAI model catalog.
  public var maxTokens: Int

  /// Creates a discovered model choice with its catalogued token limits.
  public init(ref: ModelRef, name: String, contextWindow: Int, maxTokens: Int) {
    self.ref = ref
    self.name = name
    self.contextWindow = contextWindow
    self.maxTokens = maxTokens
  }
}

/// `models.list`: discovers models through explicitly configured PiAI providers.
public enum ModelsList: RPCMethod {
  /// No parameters are required.
  public typealias Params = EmptyParams
  /// Models discovered from the explicitly configured endpoint.
  public typealias Result = ModelsListResult
  /// JSON-RPC method name.
  public static let name = "models.list"
  /// Discovery does not change persisted provider settings.
  public static let isMutating = false
}

/// Available models; an empty collection is not a fabricated model selection.
public struct ModelsListResult: Codable, Hashable, Sendable {
  /// Available chat-capable model choices; empty remains empty.
  public var items: [AvailableModel]
  /// Providers that could not refresh. Their cached models are not offered as available.
  public var unavailableProviders: [String]?

  /// Creates a discovery result without inventing a fallback model.
  public init(items: [AvailableModel], unavailableProviders: [String]? = nil) {
    self.items = items
    self.unavailableProviders = unavailableProviders
  }
}
