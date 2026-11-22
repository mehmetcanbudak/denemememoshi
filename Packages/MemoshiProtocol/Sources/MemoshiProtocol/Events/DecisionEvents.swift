/// `approval.requested` (A): a call needs a decision. The payload carries the Approval's fields
/// except `confirmationText`; the envelope carries its bot, conversation, task and origin.
public struct ApprovalRequestedPayload: EventPayload {
  /// `approval.requested`.
  public static let eventType = "approval.requested"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited

  /// The approval.
  public var approvalId: ApprovalID
  /// The card that shows it.
  public var cardId: CardID
  /// The provider's call ID.
  public var toolCallId: String
  /// The outer call of a nested Code Mode or MCP-bridge call.
  public var parentToolCallId: String?
  /// The tool's name.
  public var tool: String
  /// The classified verb, for connector tools.
  public var verb: String?
  /// The tier, 0–5.
  public var tier: Tier
  /// The bot's permission mode when the call asked.
  public var permissionMode: PermissionMode
  /// Whether the user is present.
  public var attendance: Attendance
  /// The policy exposure flags.
  public var exposure: Exposure
  /// The kind of computer the call targets.
  public var computerKind: ComputerKind?
  /// The device that will run the call.
  public var deviceId: DeviceID
  /// Canonical paths, hosts and accounts the call touches.
  public var targets: [String]
  /// SHA-256 of the canonical arguments.
  public var argsHash: String
  /// The redacted arguments.
  public var argsPreview: JSONValue
  /// The policy rule that asked.
  public var ruleId: String
  /// Why the rule asked.
  public var reasonCode: String
  /// The policy version that decided.
  public var policyVersion: String
  /// When it expires to denied.
  public var expiresAt: Int64
  /// Whether the decision needs typed confirmation (T5).
  public var confirmationRequired: Bool

  /// Creates the payload.
  public init(
    approvalId: ApprovalID, cardId: CardID, toolCallId: String, parentToolCallId: String? = nil,
    tool: String, verb: String? = nil, tier: Tier, permissionMode: PermissionMode,
    attendance: Attendance, exposure: Exposure, computerKind: ComputerKind? = nil,
    deviceId: DeviceID, targets: [String], argsHash: String, argsPreview: JSONValue,
    ruleId: String, reasonCode: String, policyVersion: String, expiresAt: Int64,
    confirmationRequired: Bool
  ) {
    self.approvalId = approvalId
    self.cardId = cardId
    self.toolCallId = toolCallId
    self.parentToolCallId = parentToolCallId
    self.tool = tool
    self.verb = verb
    self.tier = tier
    self.permissionMode = permissionMode
    self.attendance = attendance
    self.exposure = exposure
    self.computerKind = computerKind
    self.deviceId = deviceId
    self.targets = targets
    self.argsHash = argsHash
    self.argsPreview = argsPreview
    self.ruleId = ruleId
    self.reasonCode = reasonCode
    self.policyVersion = policyVersion
    self.expiresAt = expiresAt
    self.confirmationRequired = confirmationRequired
  }

  /// `.approvalRequested(self)`.
  public var asEvent: Event { .approvalRequested(self) }
}

/// `approval.resolved` (A): the user decided.
public struct ApprovalResolvedPayload: EventPayload {
  /// `approval.resolved`.
  public static let eventType = "approval.resolved"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited

  /// The approval.
  public var approvalId: ApprovalID
  /// The decision: `allowed` or `denied`.
  public var status: ResolvedApprovalStatus
  /// When allowed: for once, the task, or always.
  public var scope: ApprovalScope?
  /// The `tool_rule` grant created by `task` or `always`.
  public var grantId: GrantID?
  /// Who decided.
  public var decidedBy: Actor
  /// T5: whether the typed confirmation matched.
  public var typedConfirmationOk: Bool?
  /// T4 and T5: how the deciding device checked its owner.
  public var deviceAuth: DeviceAuthMethod?

  /// Creates the payload.
  public init(
    approvalId: ApprovalID, status: ResolvedApprovalStatus, scope: ApprovalScope? = nil,
    grantId: GrantID? = nil, decidedBy: Actor, typedConfirmationOk: Bool? = nil,
    deviceAuth: DeviceAuthMethod? = nil
  ) {
    self.approvalId = approvalId
    self.status = status
    self.scope = scope
    self.grantId = grantId
    self.decidedBy = decidedBy
    self.typedConfirmationOk = typedConfirmationOk
    self.deviceAuth = deviceAuth
  }

  /// `.approvalResolved(self)`.
  public var asEvent: Event { .approvalResolved(self) }
}

/// `approval.expired` (A): `expiresAt` passed; treated as denied.
public struct ApprovalExpiredPayload: EventPayload {
  /// `approval.expired`.
  public static let eventType = "approval.expired"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited

  /// The approval.
  public var approvalId: ApprovalID

  /// Creates the payload.
  public init(approvalId: ApprovalID) {
    self.approvalId = approvalId
  }

  /// `.approvalExpired(self)`.
  public var asEvent: Event { .approvalExpired(self) }
}

/// `approval.canceled` (A): the call went away before a decision.
public struct ApprovalCanceledPayload: EventPayload {
  /// `approval.canceled`.
  public static let eventType = "approval.canceled"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited

  /// The approval.
  public var approvalId: ApprovalID
  /// Why it went away.
  public var reason: ApprovalCancelReason

  /// Creates the payload.
  public init(approvalId: ApprovalID, reason: ApprovalCancelReason) {
    self.approvalId = approvalId
    self.reason = reason
  }

  /// `.approvalCanceled(self)`.
  public var asEvent: Event { .approvalCanceled(self) }
}

/// `card.created` (D): a card was placed.
public struct CardCreatedPayload: EventPayload {
  /// `card.created`.
  public static let eventType = "card.created"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The card.
  public var cardId: CardID
  /// Its kind.
  public var kind: CardKind
  /// Its kind-specific subtype.
  public var variant: String?
  /// The domain object it presents.
  public var subject: ObjectRef?
  /// The transcript entry it is anchored to.
  public var messageId: MessageID
  /// Its title.
  public var title: Title
  /// Whether it is listed in the Inbox.
  public var inbox: Bool
  /// Whether it counts toward `needs_you`.
  public var needsYou: Bool
  /// When its subject expires.
  public var expiresAt: Int64?
  /// Kind-specific display data, redacted.
  public var payload: JSONValue

  /// Creates the payload.
  public init(
    cardId: CardID, kind: CardKind, variant: String? = nil, subject: ObjectRef? = nil,
    messageId: MessageID, title: Title, inbox: Bool, needsYou: Bool, expiresAt: Int64? = nil,
    payload: JSONValue
  ) {
    self.cardId = cardId
    self.kind = kind
    self.variant = variant
    self.subject = subject
    self.messageId = messageId
    self.title = title
    self.inbox = inbox
    self.needsYou = needsYou
    self.expiresAt = expiresAt
    self.payload = payload
  }

  /// `.cardCreated(self)`.
  public var asEvent: Event { .cardCreated(self) }
}

/// `card.updated` (D): a card's display data changed, for example a Resume card that no longer
/// offers Run again once the engine has ended its call (D51).
public struct CardUpdatedPayload: EventPayload {
  /// `card.updated`.
  public static let eventType = "card.updated"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The card.
  public var cardId: CardID
  /// Its new kind-specific display data, redacted.
  public var payload: JSONValue

  /// Creates the payload.
  public init(cardId: CardID, payload: JSONValue) {
    self.cardId = cardId
    self.payload = payload
  }

  /// `.cardUpdated(self)`.
  public var asEvent: Event { .cardUpdated(self) }
}

/// `card.resolved` (D): resolved through `cards.respond`, after the domain event.
public struct CardResolvedPayload: EventPayload {
  /// `card.resolved`.
  public static let eventType = "card.resolved"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The card.
  public var cardId: CardID
  /// The action taken and its payload.
  public var outcome: CardOutcome
  /// Who resolved it.
  public var by: ActorKind

  /// Creates the payload.
  public init(cardId: CardID, outcome: CardOutcome, by: ActorKind) {
    self.cardId = cardId
    self.outcome = outcome
    self.by = by
  }

  /// `.cardResolved(self)`.
  public var asEvent: Event { .cardResolved(self) }
}

/// `card.expired` (D): the card's subject expired.
public struct CardExpiredPayload: EventPayload {
  /// `card.expired`.
  public static let eventType = "card.expired"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The card.
  public var cardId: CardID

  /// Creates the payload.
  public init(cardId: CardID) {
    self.cardId = cardId
  }

  /// `.cardExpired(self)`.
  public var asEvent: Event { .cardExpired(self) }
}

/// `card.answer_lapsed` (D): an answer queued while the runner of the card's conversation was
/// unreachable was dropped, because the card was no longer pending; the user is told (D73).
public struct CardAnswerLapsedPayload: EventPayload {
  /// `card.answer_lapsed`.
  public static let eventType = "card.answer_lapsed"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The card.
  public var cardId: CardID
  /// The device the answer was given on.
  public var answeredOnDeviceId: DeviceID

  /// Creates the payload.
  public init(cardId: CardID, answeredOnDeviceId: DeviceID) {
    self.cardId = cardId
    self.answeredOnDeviceId = answeredOnDeviceId
  }

  /// `.cardAnswerLapsed(self)`.
  public var asEvent: Event { .cardAnswerLapsed(self) }
}

/// `inbox.changed` (U): the Inbox counts changed (badges, the menu bar).
public struct InboxChangedPayload: EventPayload {
  /// `inbox.changed`.
  public static let eventType = "inbox.changed"
  /// Version 1.
  public static let typeVersion = 1
  /// UI-only.
  public static let eventClass = EventClass.uiOnly

  /// Pending cards in the Inbox.
  public var pendingCount: Int
  /// Pending cards that need the user.
  public var needsYouCount: Int
  /// Unseen news and failures.
  public var unreadCount: Int

  /// Creates the payload.
  public init(pendingCount: Int, needsYouCount: Int, unreadCount: Int) {
    self.pendingCount = pendingCount
    self.needsYouCount = needsYouCount
    self.unreadCount = unreadCount
  }

  /// `.inboxChanged(self)`.
  public var asEvent: Event { .inboxChanged(self) }
}

/// `system.resync_required` (U): one client must refetch the named scope, or everything.
public struct SystemResyncRequiredPayload: EventPayload {
  /// `system.resync_required`.
  public static let eventType = "system.resync_required"
  /// Version 1.
  public static let typeVersion = 1
  /// UI-only.
  public static let eventClass = EventClass.uiOnly

  /// The scope to refetch; absent means everything.
  public var scope: ResyncScope?
  /// Why.
  public var reason: ResyncReason

  /// Creates the payload.
  public init(scope: ResyncScope? = nil, reason: ResyncReason) {
    self.scope = scope
    self.reason = reason
  }

  /// `.systemResyncRequired(self)`.
  public var asEvent: Event { .systemResyncRequired(self) }
}

/// What a client must refetch after `system.resync_required`.
public struct ResyncScope: Codable, Hashable, Sendable {
  /// The conversation to refetch.
  public var conversationId: ConversationID

  /// Creates a scope.
  public init(conversationId: ConversationID) {
    self.conversationId = conversationId
  }
}

/// Why a client must resync.
public enum ResyncReason: OpenEnum {
  /// The cursor is older than the oldest retained event.
  case cursorExpired
  /// A `seq` or `cseq` gap.
  case gap
  /// A Pi watch overflowed or a store reopened.
  case projectorReset
  case protocolChanged
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .cursorExpired: "cursor_expired", .gap: "gap", .projectorReset: "projector_reset",
    .protocolChanged: "protocol_changed",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// Why an approval was canceled (policy.md §10.1).
public enum ApprovalCancelReason: OpenEnum {
  case taskCanceled
  case callAborted
  case superseded
  case killSwitch
  case grantRevoked
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .taskCanceled: "task_canceled", .callAborted: "call_aborted", .superseded: "superseded",
    .killSwitch: "kill_switch", .grantRevoked: "grant_revoked",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// The decision `approval.resolved` records: the subset of ``ApprovalStatus`` the catalog allows
/// (events.md §5.7).
public enum ResolvedApprovalStatus: OpenEnum {
  case allowed
  case denied
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.allowed: "allowed", .denied: "denied"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
