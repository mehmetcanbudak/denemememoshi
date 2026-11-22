/// `message.forward`, a device that is not the runner → the conversation's runner: a message the
/// user sent there. The runner admits it with the client's `requestId`, answers it and streams
/// the answer back; the lease does not move (protocol.md §12.6, D73).
public struct MessageForward: DeviceMessagePayload {
  /// `message.forward`.
  public static let messageType = "message.forward"

  /// The conversation.
  public var conversationId: ConversationID
  /// The client's idempotency key from the original send.
  public var requestId: ULID
  /// The message.
  public var content: [ContentPart]
  /// Where the original send came from (protocol.md §3.4). Required, so a forwarder cannot
  /// raise a message's trust by leaving it out; the runner derives the origin from it exactly
  /// as for a local request.
  public var surface: RequestSurface
  /// What to do while the conversation is busy, from the original send.
  public var whenBusy: WhenBusy?
  /// A per-turn model override, from the original send.
  public var model: ModelRef?

  /// Creates the payload.
  public init(
    conversationId: ConversationID, requestId: ULID, content: [ContentPart],
    surface: RequestSurface, whenBusy: WhenBusy? = nil, model: ModelRef? = nil
  ) {
    self.conversationId = conversationId
    self.requestId = requestId
    self.content = content
    self.surface = surface
    self.whenBusy = whenBusy
    self.model = model
  }

  /// `.messageForward(self)`.
  public var asBody: DeviceMessageBody { .messageForward(self) }
}

/// `message.forwardResult`, runner → the forwarding device: the admission, or why it failed.
public struct MessageForwardResult: DeviceMessagePayload {
  /// `message.forwardResult`.
  public static let messageType = "message.forwardResult"

  /// The conversation.
  public var conversationId: ConversationID
  /// The forwarded message's idempotency key.
  public var requestId: ULID
  /// The admitted message.
  public var messageId: MessageID?
  /// The turn's task.
  public var taskId: TaskID?
  /// Why admission failed.
  public var error: RPCError?

  /// Creates the payload.
  public init(
    conversationId: ConversationID, requestId: ULID, messageId: MessageID? = nil,
    taskId: TaskID? = nil, error: RPCError? = nil
  ) {
    self.conversationId = conversationId
    self.requestId = requestId
    self.messageId = messageId
    self.taskId = taskId
    self.error = error
  }

  /// `.messageForwardResult(self)`.
  public var asBody: DeviceMessageBody { .messageForwardResult(self) }
}

/// `intent.forward`, a replica → the runner of the conversation it touches: a card answer, a
/// stop or an edit made there, applied once by the client's `requestId`. If the runner is
/// unreachable it waits in the mailbox (protocol.md §12.6).
public struct IntentForward: DeviceMessagePayload {
  /// `intent.forward`.
  public static let messageType = "intent.forward"

  /// The conversation the intent touches.
  public var conversationId: ConversationID
  /// The mutating method, such as `cards.respond`.
  public var method: String
  /// The method's parameters, `requestId` included; the runner decodes them by `method`.
  public var params: JSONValue
  /// The client's idempotency key.
  public var requestId: ULID

  /// Creates the payload.
  public init(conversationId: ConversationID, method: String, params: JSONValue, requestId: ULID) {
    self.conversationId = conversationId
    self.method = method
    self.params = params
    self.requestId = requestId
  }

  /// `.intentForward(self)`.
  public var asBody: DeviceMessageBody { .intentForward(self) }
}

/// `intent.result`, runner → the forwarding device: the applied intent's result or error.
public struct IntentResult: DeviceMessagePayload {
  /// `intent.result`.
  public static let messageType = "intent.result"

  /// The conversation the intent touched.
  public var conversationId: ConversationID
  /// The intent's idempotency key.
  public var requestId: ULID
  /// The method that was applied.
  public var method: String
  /// The method's result.
  public var result: JSONValue?
  /// The method's error.
  public var error: RPCError?

  /// Creates the payload.
  public init(
    conversationId: ConversationID, requestId: ULID, method: String, result: JSONValue? = nil,
    error: RPCError? = nil
  ) {
    self.conversationId = conversationId
    self.requestId = requestId
    self.method = method
    self.result = result
    self.error = error
  }

  /// `.intentResult(self)`.
  public var asBody: DeviceMessageBody { .intentResult(self) }
}

/// `effect.intent`, runner → another device or the relay: a write-ahead copy of an external
/// effect's intent, acknowledged before the effect runs, so a runner that takes over after a
/// failure checks the outcome instead of repeating the effect (D73).
public struct EffectIntent: DeviceMessagePayload {
  /// `effect.intent`.
  public static let messageType = "effect.intent"

  /// The conversation.
  public var conversationId: ConversationID
  /// The runner's lease epoch.
  public var epoch: Int64
  /// The task making the effect.
  public var taskId: TaskID
  /// The tool call that makes the effect.
  public var callId: String
  /// The hash of the effect's canonical intent.
  public var intentHash: String

  /// Creates the payload.
  public init(
    conversationId: ConversationID, epoch: Int64, taskId: TaskID, callId: String,
    intentHash: String
  ) {
    self.conversationId = conversationId
    self.epoch = epoch
    self.taskId = taskId
    self.callId = callId
    self.intentHash = intentHash
  }

  /// `.effectIntent(self)`.
  public var asBody: DeviceMessageBody { .effectIntent(self) }
}

/// `effect.ack`, the holder of an intent copy → runner: the copy is stored; the effect may run.
public struct EffectAck: DeviceMessagePayload {
  /// `effect.ack`.
  public static let messageType = "effect.ack"

  /// The conversation.
  public var conversationId: ConversationID
  /// The epoch of the acknowledged intent.
  public var epoch: Int64
  /// The tool call.
  public var callId: String
  /// The acknowledged intent's hash.
  public var intentHash: String

  /// Creates the payload.
  public init(conversationId: ConversationID, epoch: Int64, callId: String, intentHash: String) {
    self.conversationId = conversationId
    self.epoch = epoch
    self.callId = callId
    self.intentHash = intentHash
  }

  /// `.effectAck(self)`.
  public var asBody: DeviceMessageBody { .effectAck(self) }
}
