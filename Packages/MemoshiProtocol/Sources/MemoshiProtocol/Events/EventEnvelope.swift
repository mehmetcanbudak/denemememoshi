/// One event: the envelope of events.md §2 around a typed payload.
///
/// Durable events carry the device log's `seq`; UI-only frames carry `seq: null` and `after`,
/// the last durable `seq` when they were sent, and no `cseq`. An event this build cannot read
/// decodes as ``Event/unknown(type:typeVersion:raw:)`` and is reported to the decoder's
/// ``ProtocolDiagnosticsSink``; it is never dropped.
public struct EventEnvelope: Codable, Hashable, Sendable {
  /// The envelope version: `1` in protocol version 1, the only value this build reads.
  public var v: EnvelopeVersion
  /// The device log's sequence number; `nil` (encoded as `null`) for UI-only frames.
  public var seq: Int64?
  /// UI-only frames only: the last durable `seq` when the frame was sent.
  public var after: Int64?
  /// The conversation sequence number, for durable events in a conversation.
  public var cseq: Int64?
  /// When the change happened, Unix milliseconds.
  public var ts: Int64
  /// The device that made the change.
  public var deviceId: DeviceID
  /// Who caused it.
  public var actor: Actor
  /// The primary object.
  public var subject: ObjectRef
  /// Routing context.
  public var scope: EventScope
  /// Why the work exists, on events about work.
  public var origin: Origin?
  /// The typed event: its `type`, `typeVersion` and payload.
  public var event: Event

  /// Creates an envelope.
  public init(
    v: EnvelopeVersion = .current, seq: Int64?, after: Int64? = nil, cseq: Int64? = nil, ts: Int64,
    deviceId: DeviceID, actor: Actor, subject: ObjectRef, scope: EventScope,
    origin: Origin? = nil, event: Event
  ) {
    self.v = v
    self.seq = seq
    self.after = after
    self.cseq = cseq
    self.ts = ts
    self.deviceId = deviceId
    self.actor = actor
    self.subject = subject
    self.scope = scope
    self.origin = origin
    self.event = event
  }

  /// The event's `type`, such as `message.created`.
  public var type: String { event.type }

  /// The payload's schema version.
  public var typeVersion: Int { event.typeVersion }

  /// The envelope as persisted: live-only (†) payload fields removed (events.md §2).
  public func persistedForm() -> EventEnvelope {
    var copy = self
    copy.event = event.strippingLiveOnlyFields()
    return copy
  }

  private enum CodingKeys: String, CodingKey {
    case v
    case seq
    case after
    case cseq
    case ts
    case type
    case typeVersion
    case deviceId
    case actor
    case subject
    case scope
    case origin
    case payload
  }

  /// Decodes an envelope and checks its class rules: a UI-only type has `seq: null`, `after`
  /// and no `cseq`; a durable or audited type has a `seq` and no `after`. A strict decoder
  /// rejects a violation; a lenient one keeps the event and reports a diagnostic.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let v = try container.decode(EnvelopeVersion.self, forKey: .v)
    let seq = try container.decode(Int64?.self, forKey: .seq)
    let after = try container.decodeIfPresent(Int64.self, forKey: .after)
    let cseq = try container.decodeIfPresent(Int64.self, forKey: .cseq)
    let ts = try container.decode(Int64.self, forKey: .ts)
    let deviceId = try container.decode(DeviceID.self, forKey: .deviceId)
    let actor = try container.decode(Actor.self, forKey: .actor)
    let subject = try container.decode(ObjectRef.self, forKey: .subject)
    let scope = try container.decode(EventScope.self, forKey: .scope)
    let origin = try container.decodeIfPresent(Origin.self, forKey: .origin)
    let type = try container.decode(String.self, forKey: .type)
    let typeVersion = try container.decode(Int.self, forKey: .typeVersion)
    let strict = decoder.isStrictProtocolDecoding

    func report(_ reason: ProtocolDiagnostic.Reason, _ detail: String) {
      decoder.reportProtocolDiagnostic(
        ProtocolDiagnostic(
          reason: reason, type: type, typeVersion: typeVersion, seq: seq,
          conversationId: scope.conversationId?.rawValue,
          codingPath: decoder.protocolCodingPath, detail: detail))
    }

    func keepUnknown(_ reason: ProtocolDiagnostic.Reason, _ detail: String) throws -> Event {
      if strict {
        throw DecodingError.dataCorruptedError(
          forKey: .type, in: container, debugDescription: detail)
      }
      let raw = try container.decode(JSONValue.self, forKey: .payload)
      report(reason, detail)
      return .unknown(type: type, typeVersion: typeVersion, raw: raw)
    }

    let event: Event
    if let payloadType = EventRegistry.payloadType(for: type) {
      if payloadType.typeVersion != typeVersion {
        event = try keepUnknown(
          .unsupportedEventVersion,
          "\(type) has typeVersion \(typeVersion); this build reads \(payloadType.typeVersion)")
      } else {
        do {
          event = try Self.decodePayload(payloadType, from: container)
        } catch {
          event = try keepUnknown(.undecodableEventPayload, "\(type) payload: \(error)")
        }
        let consistent =
          switch payloadType.eventClass {
          case .uiOnly: seq == nil && after != nil && cseq == nil
          case .durable, .audited: seq != nil && after == nil
          }
        if !consistent {
          let detail = "\(type) is \(payloadType.eventClass): seq, after or cseq disagree"
          if strict {
            throw DecodingError.dataCorruptedError(
              forKey: .seq, in: container, debugDescription: detail)
          }
          report(.inconsistentEventClass, detail)
        }
      }
    } else {
      event = try keepUnknown(.unknownEventType, "Unknown event type \(type)")
    }

    self.init(
      v: v, seq: seq, after: after, cseq: cseq, ts: ts, deviceId: deviceId, actor: actor,
      subject: subject, scope: scope, origin: origin, event: event)
  }

  private static func decodePayload<Payload: EventPayload>(
    _ payloadType: Payload.Type, from container: KeyedDecodingContainer<CodingKeys>
  ) throws -> Event {
    try container.decode(Payload.self, forKey: .payload).asEvent
  }

  /// Encodes the envelope, writing `"seq": null` for UI-only frames.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(v, forKey: .v)
    try container.encode(seq, forKey: .seq)
    try container.encodeIfPresent(after, forKey: .after)
    try container.encodeIfPresent(cseq, forKey: .cseq)
    try container.encode(ts, forKey: .ts)
    try container.encode(event.type, forKey: .type)
    try container.encode(event.typeVersion, forKey: .typeVersion)
    try container.encode(deviceId, forKey: .deviceId)
    try container.encode(actor, forKey: .actor)
    try container.encode(subject, forKey: .subject)
    try container.encode(scope, forKey: .scope)
    try container.encodeIfPresent(origin, forKey: .origin)
    switch event {
    case .unknown(_, _, let raw):
      try container.encode(raw, forKey: .payload)
    default:
      if let payload = event.payload {
        try container.encode(payload, forKey: .payload)
      }
    }
  }
}

/// An event's routing context: `{botId?, conversationId?, projectId?, taskId?}`.
public struct EventScope: Codable, Hashable, Sendable {
  /// The bot.
  public var botId: BotID?
  /// The conversation.
  public var conversationId: ConversationID?
  /// The project.
  public var projectId: ProjectID?
  /// The task.
  public var taskId: TaskID?

  /// Creates a scope.
  public init(
    botId: BotID? = nil, conversationId: ConversationID? = nil, projectId: ProjectID? = nil,
    taskId: TaskID? = nil
  ) {
    self.botId = botId
    self.conversationId = conversationId
    self.projectId = projectId
    self.taskId = taskId
  }
}

/// How an event type is stored (events.md §4).
public enum EventClass: String, Hashable, Sendable, CustomStringConvertible {
  /// Persisted and mirrored to the audit log.
  case audited
  /// Persisted and replayable.
  case durable
  /// Never stored; streamed only.
  case uiOnly

  /// The class's letter in the catalog: A, D or U.
  public var description: String {
    switch self {
    case .audited: "A"
    case .durable: "D"
    case .uiOnly: "U"
    }
  }
}

/// A typed event payload. Each conforming type is one catalog entry of events.md §5.
public protocol EventPayload: Codable, Hashable, Sendable {
  /// The event type, such as `message.created`.
  static var eventType: String { get }
  /// The payload schema version this type reads and writes.
  static var typeVersion: Int { get }
  /// How the type is stored.
  static var eventClass: EventClass { get }
  /// The live-only (†) payload keys, stripped before persistence.
  static var liveOnlyKeys: [String] { get }
  /// This payload wrapped as its ``Event`` case.
  var asEvent: Event { get }
  /// The payload without its live-only fields.
  func strippingLiveOnlyFields() -> Self
}

extension EventPayload {
  /// No live-only fields.
  public static var liveOnlyKeys: [String] { [] }

  /// The payload unchanged: it has no live-only fields.
  public func strippingLiveOnlyFields() -> Self { self }
}

/// Every event type this build reads and writes, in catalog order.
public enum EventRegistry {
  /// The registered payload types.
  public static let payloadTypes: [any EventPayload.Type] = [
    SystemStoppingPayload.self,
    SystemMigratedPayload.self,
    SystemAppConnectedPayload.self,
    SystemAppDisconnectedPayload.self,
    SystemPrunedPayload.self,
    SystemSettingsChangedPayload.self,
    BotCreatedPayload.self,
    BotUpdatedPayload.self,
    ChatCreatedPayload.self,
    SessionCreatedPayload.self,
    SessionDeletedPayload.self,
    SessionRestoredPayload.self,
    SessionPurgedPayload.self,
    TrashEmptiedPayload.self,
    MessageCreatedPayload.self,
    MessageDeltaPayload.self,
    MessageCompletedPayload.self,
    MessageFailedPayload.self,
    MessageQueuedPayload.self,
    MessageForwardedPayload.self,
    SideThreadOpenedPayload.self,
    TaskCreatedPayload.self,
    TaskStartedPayload.self,
    TaskStatusChangedPayload.self,
    TaskProgressPayload.self,
    TaskCancelRequestedPayload.self,
    TaskResumedPayload.self,
    TaskFinishedPayload.self,
    ToolInterruptedPayload.self,
    ToolInterruptionResolvedPayload.self,
    PolicyDecidedPayload.self,
    PolicyRedactedPayload.self,
    ToolCompletedPayload.self,
    ApprovalRequestedPayload.self,
    ApprovalResolvedPayload.self,
    ApprovalExpiredPayload.self,
    ApprovalCanceledPayload.self,
    GrantGrantedPayload.self,
    GrantRevokedPayload.self,
    GrantExpiredPayload.self,
    EgressAllowedPayload.self,
    EgressBlockedPayload.self,
    SecretUsedPayload.self,
    CardCreatedPayload.self,
    CardUpdatedPayload.self,
    CardResolvedPayload.self,
    CardExpiredPayload.self,
    CardCanceledPayload.self,
    CardAnswerLapsedPayload.self,
    InboxChangedPayload.self,
    SystemResyncRequiredPayload.self,
  ]

  private static let payloadTypesByType: [String: any EventPayload.Type] = Dictionary(
    uniqueKeysWithValues: payloadTypes.map { ($0.eventType, $0) })

  /// The payload type registered for an event type.
  public static func payloadType(for type: String) -> (any EventPayload.Type)? {
    payloadTypesByType[type]
  }
}
