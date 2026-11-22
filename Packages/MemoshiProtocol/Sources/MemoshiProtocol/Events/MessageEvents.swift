/// `message.created` (D): a user message was admitted, a bot message started streaming, or a
/// card, note or summary entry was placed.
public struct MessageCreatedPayload: EventPayload {
  /// `message.created`.
  public static let eventType = "message.created"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable
  /// `content` is attached only to the live frame for focusing connections.
  public static let liveOnlyKeys = ["content"]

  /// The message.
  public var messageId: MessageID
  /// Who wrote it.
  public var role: MessageRole
  /// The author, in Groups with many bot authors.
  public var authorId: String?
  /// What kind of entry it is.
  public var kind: MessageKind
  /// For user messages: the client's `requestId`, which confirms the optimistic composer row.
  public var requestId: ULID?
  /// The message it replies to.
  public var replyToMessageId: MessageID?
  /// Attachment metadata; never their contents.
  public var attachments: [AttachmentInfo]
  /// † The message's content, on the live frame only.
  public var content: [ContentPart]?

  /// Creates the payload.
  public init(
    messageId: MessageID, role: MessageRole, authorId: String? = nil, kind: MessageKind,
    requestId: ULID? = nil, replyToMessageId: MessageID? = nil, attachments: [AttachmentInfo],
    content: [ContentPart]? = nil
  ) {
    self.messageId = messageId
    self.role = role
    self.authorId = authorId
    self.kind = kind
    self.requestId = requestId
    self.replyToMessageId = replyToMessageId
    self.attachments = attachments
    self.content = content
  }

  /// `.messageCreated(self)`.
  public var asEvent: Event { .messageCreated(self) }

  /// The payload without `content`.
  public func strippingLiveOnlyFields() -> Self {
    var copy = self
    copy.content = nil
    return copy
  }
}

/// `message.delta` (U): a streaming partial. The receiver applies the offset rule of
/// protocol.md §7.4.
public struct MessageDeltaPayload: EventPayload {
  /// `message.delta`.
  public static let eventType = "message.delta"
  /// Version 1.
  public static let typeVersion = 1
  /// UI-only.
  public static let eventClass = EventClass.uiOnly

  /// The streaming message.
  public var messageId: MessageID
  /// Which stream the text belongs to.
  public var channel: DeltaChannel
  /// The message's length in UTF-16 code units before this append.
  public var offsetUtf16: Int64
  /// The appended text.
  public var text: String

  /// Creates the payload.
  public init(messageId: MessageID, channel: DeltaChannel, offsetUtf16: Int64, text: String) {
    self.messageId = messageId
    self.channel = channel
    self.offsetUtf16 = offsetUtf16
    self.text = text
  }

  /// `.messageDelta(self)`.
  public var asEvent: Event { .messageDelta(self) }
}

/// `message.completed` (D): the assistant entry committed. Metadata only; `content` is attached
/// only to the live frame.
public struct MessageCompletedPayload: EventPayload {
  /// `message.completed`.
  public static let eventType = "message.completed"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable
  /// `content` is attached only to the live frame for focusing connections.
  public static let liveOnlyKeys = ["content"]

  /// The message.
  public var messageId: MessageID
  /// Why generation stopped.
  public var stopReason: StopReason
  /// The generation's usage.
  public var usage: Usage?
  /// `true` when crash recovery emitted this event late (events.md §8).
  public var reconciled: Bool?
  /// † The final content, on the live frame only.
  public var content: [ContentPart]?

  /// Creates the payload.
  public init(
    messageId: MessageID, stopReason: StopReason, usage: Usage? = nil, reconciled: Bool? = nil,
    content: [ContentPart]? = nil
  ) {
    self.messageId = messageId
    self.stopReason = stopReason
    self.usage = usage
    self.reconciled = reconciled
    self.content = content
  }

  /// `.messageCompleted(self)`.
  public var asEvent: Event { .messageCompleted(self) }

  /// The payload without `content`.
  public func strippingLiveOnlyFields() -> Self {
    var copy = self
    copy.content = nil
    return copy
  }
}

/// `message.failed` (D): the generation failed; partial text is kept.
public struct MessageFailedPayload: EventPayload {
  /// `message.failed`.
  public static let eventType = "message.failed"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The message.
  public var messageId: MessageID
  /// What failed.
  public var error: MessageError
  /// Whether partial text was kept.
  public var partial: Bool

  /// Creates the payload.
  public init(messageId: MessageID, error: MessageError, partial: Bool) {
    self.messageId = messageId
    self.error = error
    self.partial = partial
  }

  /// `.messageFailed(self)`.
  public var asEvent: Event { .messageFailed(self) }
}

/// `message.queued` (D): an admitted input was queued while the conversation was busy. Never
/// emitted for a device-local unsent message (D88).
public struct MessageQueuedPayload: EventPayload {
  /// `message.queued`.
  public static let eventType = "message.queued"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The queued message.
  public var messageId: MessageID
  /// The client's `requestId`, which confirms the optimistic row.
  public var requestId: ULID?
  /// How the input joins the busy conversation: `steer` or `follow_up`. A `reject` send is never
  /// queued.
  public var whenBusy: QueuedWhenBusy

  /// Creates the payload.
  public init(messageId: MessageID, requestId: ULID? = nil, whenBusy: QueuedWhenBusy) {
    self.messageId = messageId
    self.requestId = requestId
    self.whenBusy = whenBusy
  }

  /// `.messageQueued(self)`.
  public var asEvent: Event { .messageQueued(self) }
}

/// `message.forwarded` (D): a message sent on a device that is not the conversation's runner
/// reached the runner, which answers it (D73).
public struct MessageForwardedPayload: EventPayload {
  /// `message.forwarded`.
  public static let eventType = "message.forwarded"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The forwarded message.
  public var messageId: MessageID
  /// The device it was sent on.
  public var fromDeviceId: DeviceID

  /// Creates the payload.
  public init(messageId: MessageID, fromDeviceId: DeviceID) {
    self.messageId = messageId
    self.fromDeviceId = fromDeviceId
  }

  /// `.messageForwarded(self)`.
  public var asEvent: Event { .messageForwarded(self) }
}

/// `side_thread.opened` (D): a device that could neither reach the conversation's runner nor
/// take its lease started a real side thread with an available allowed model (D88).
public struct SideThreadOpenedPayload: EventPayload {
  /// `side_thread.opened`.
  public static let eventType = "side_thread.opened"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The side thread.
  public var sideThreadId: SideThreadID
  /// The Chat or Session the user was in.
  public var parentConversationId: ConversationID
  /// The parent's last `cseq` this device had.
  public var baseCseq: Int64

  /// Creates the payload.
  public init(sideThreadId: SideThreadID, parentConversationId: ConversationID, baseCseq: Int64) {
    self.sideThreadId = sideThreadId
    self.parentConversationId = parentConversationId
    self.baseCseq = baseCseq
  }

  /// `.sideThreadOpened(self)`.
  public var asEvent: Event { .sideThreadOpened(self) }
}

/// An attachment's metadata on `message.created`.
public struct AttachmentInfo: Codable, Hashable, Sendable {
  /// The file name.
  public var name: String
  /// The MIME type.
  public var mimeType: String
  /// The size in bytes.
  public var sizeBytes: Int64

  /// Creates attachment metadata.
  public init(name: String, mimeType: String, sizeBytes: Int64) {
    self.name = name
    self.mimeType = mimeType
    self.sizeBytes = sizeBytes
  }
}

/// Why a generation failed: `{code, message, retryable, retryAfterMs?}`.
public struct MessageError: Codable, Hashable, Sendable {
  /// A stable code.
  public var code: String
  /// A human-readable message.
  public var message: String
  /// Whether retrying may help.
  public var retryable: Bool
  /// How long to wait before retrying.
  public var retryAfterMs: Int64?

  /// Creates a message error.
  public init(code: String, message: String, retryable: Bool, retryAfterMs: Int64? = nil) {
    self.code = code
    self.message = message
    self.retryable = retryable
    self.retryAfterMs = retryAfterMs
  }
}

/// Who wrote a message (object-model.md §3.2).
public enum MessageRole: OpenEnum {
  case user
  case bot
  case system
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .user: "user", .bot: "bot", .system: "system",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// What kind of transcript entry a message is (object-model.md §3.2).
public enum MessageKind: OpenEnum {
  case text
  case card
  case runSummary
  case handoffNote
  case handoffResult
  case wakeNote
  case watchNote
  case sideThreadSummary
  case systemNote
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .text: "text", .card: "card", .runSummary: "run_summary", .handoffNote: "handoff_note",
    .handoffResult: "handoff_result", .wakeNote: "wake_note", .watchNote: "watch_note",
    .sideThreadSummary: "side_thread_summary", .systemNote: "system_note",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// Why a generation stopped.
public enum StopReason: OpenEnum {
  /// The model finished.
  case stop
  /// The output limit was reached.
  case length
  /// The model called a tool.
  case toolUse
  case error
  case aborted
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .stop: "stop", .length: "length", .toolUse: "tool_use", .error: "error",
    .aborted: "aborted",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// Which stream a delta belongs to.
public enum DeltaChannel: OpenEnum {
  case text
  case thinking
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.text: "text", .thinking: "thinking"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// How a queued input joins its busy conversation: the subset of ``WhenBusy`` that queues
/// (events.md §5.4).
public enum QueuedWhenBusy: OpenEnum {
  /// Steer the current turn.
  case steer
  /// Run after the current turn.
  case followUp
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.steer: "steer", .followUp: "follow_up"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
