/// An interactive element inside a conversation (object-model.md §4.18). Cards are decided
/// only through `cards.respond`.
public struct Card: Codable, Hashable, Sendable {
  /// The card's ID.
  public var id: CardID
  /// What kind of card this is.
  public var kind: CardKind
  /// A kind-specific subtype, such as `patch` for an approval shown as a diff.
  public var variant: String?
  /// The conversation it was posted in.
  public var conversationId: ConversationID
  /// The transcript entry it is anchored to.
  public var messageId: MessageID
  /// The bot it belongs to.
  public var botId: BotID
  /// The task it belongs to.
  public var taskId: TaskID?
  /// The domain object it presents.
  public var subject: ObjectRef?
  /// Its lifecycle state.
  public var status: CardStatus
  /// The kind-specific result once resolved.
  public var outcome: CardOutcome?
  /// Listed in the Inbox while pending or unseen.
  public var inbox: Bool
  /// Counts toward the bot's `needs_you` status.
  public var needsYou: Bool
  /// A short title, at most 120 characters.
  public var title: Title
  /// Kind-specific display data, redacted; never secrets.
  public var payload: JSONValue
  /// For `generated` cards: `json` or `swift`.
  public var sourceFormat: CardSourceFormat?
  /// For a live card: its Swift source.
  public var sourceText: String?
  /// For a live card: its permission list and what the user approved of it (cards.md §11.11).
  public var permissions: JSONValue?
  /// For a live Apple-data card (Drop 2): the item it shows.
  public var resource: JSONValue?
  /// When its subject expires.
  public var expiresAt: Int64?
  /// When a `run_summary` or news card was seen.
  public var seenAt: Int64?
  /// Who resolved it.
  public var resolvedBy: Actor?
  /// When it was resolved.
  public var resolvedAt: Int64?
  /// When it was created.
  public var createdAt: Int64

  /// Creates a card record.
  public init(
    id: CardID, kind: CardKind, variant: String? = nil, conversationId: ConversationID,
    messageId: MessageID, botId: BotID, taskId: TaskID? = nil, subject: ObjectRef? = nil,
    status: CardStatus, outcome: CardOutcome? = nil, inbox: Bool, needsYou: Bool, title: Title,
    payload: JSONValue, sourceFormat: CardSourceFormat? = nil, sourceText: String? = nil,
    permissions: JSONValue? = nil, resource: JSONValue? = nil, expiresAt: Int64? = nil,
    seenAt: Int64? = nil, resolvedBy: Actor? = nil, resolvedAt: Int64? = nil, createdAt: Int64
  ) {
    self.id = id
    self.kind = kind
    self.variant = variant
    self.conversationId = conversationId
    self.messageId = messageId
    self.botId = botId
    self.taskId = taskId
    self.subject = subject
    self.status = status
    self.outcome = outcome
    self.inbox = inbox
    self.needsYou = needsYou
    self.title = title
    self.payload = payload
    self.sourceFormat = sourceFormat
    self.sourceText = sourceText
    self.permissions = permissions
    self.resource = resource
    self.expiresAt = expiresAt
    self.seenAt = seenAt
    self.resolvedBy = resolvedBy
    self.resolvedAt = resolvedAt
    self.createdAt = createdAt
  }
}

/// How a card was resolved: the action taken and its payload.
public struct CardOutcome: Codable, Hashable, Sendable {
  /// The card action, such as `allow_once` or a generated card's button ID.
  public var action: String
  /// The action's payload, such as `always_allow`'s scope.
  public var payload: JSONValue?

  /// Creates an outcome.
  public init(action: String, payload: JSONValue? = nil) {
    self.action = action
    self.payload = payload
  }
}

/// What kind of card this is (object-model.md §4.18).
public enum CardKind: OpenEnum {
  case approval
  case draft
  case question
  case form
  case secureForm
  case signIn
  case purchase
  case handoff
  case routineProposal
  case memoryProposal
  case botProposal
  case grantRequest
  case budgetWarning
  case budgetStop
  case runSummary
  case error
  case takeoverRequest
  case resume
  case appleData
  case generated
  case setupChecklist
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .approval: "approval", .draft: "draft", .question: "question", .form: "form",
    .secureForm: "secure_form", .signIn: "sign_in", .purchase: "purchase",
    .handoff: "handoff", .routineProposal: "routine_proposal",
    .memoryProposal: "memory_proposal", .botProposal: "bot_proposal",
    .grantRequest: "grant_request", .budgetWarning: "budget_warning",
    .budgetStop: "budget_stop", .runSummary: "run_summary", .error: "error",
    .takeoverRequest: "takeover_request", .resume: "resume", .appleData: "apple_data",
    .generated: "generated", .setupChecklist: "setup_checklist",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// A card's lifecycle state; it never returns to `pending`.
public enum CardStatus: OpenEnum {
  case pending
  case resolved
  case expired
  case canceled
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .pending: "pending", .resolved: "resolved", .expired: "expired", .canceled: "canceled",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// How a `generated` card is written.
public enum CardSourceFormat: OpenEnum {
  /// A JSON card from the block catalog.
  case json
  /// A live card, Swift that the engine runs.
  case swift
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.json: "json", .swift: "swift"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
