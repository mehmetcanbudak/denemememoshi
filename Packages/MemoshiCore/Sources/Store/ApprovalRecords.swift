import MemoshiProtocol

/// Safe domain failures; raw SQL, arguments and confirmation text never escape in errors.
public enum ApprovalError: Error, Equatable, Sendable {
  case notFound
  case invalidRequest
  case forbidden
  case deviceAuthRequired
  case capabilityMissing
  case bindingConflict
  case resolved(cardID: CardID, action: String)
  case expired(CardID)
}

/// The durable association between an application decision and one opaque runtime tool task.
public struct ApprovalBinding: Sendable {
  /// The authoritative decision record.
  public let approval: Approval
  /// The card that exclusively presents this decision.
  public let card: Card
  /// The durable Pi tool-task ID, opaque outside the runtime adapter.
  public let runtimeTaskKey: String
  /// The trusted operation class that requested approval.
  public let operation: String
  /// The exact folder-grant revisions this decision depends on. Any change to one of them ends a
  /// pending decision; a terminal decision keeps them, so a later dispatch check still denies.
  public let sourceGrants: [FolderGrantReference]

  /// Associates one tool task, decision, card and its exact source-grant revisions, without
  /// renewing an existing deadline.
  public init(
    approval: Approval, card: Card, runtimeTaskKey: String, operation: String,
    sourceGrants: [FolderGrantReference] = []
  ) {
    self.approval = approval
    self.card = card
    self.runtimeTaskKey = runtimeTaskKey
    self.operation = operation
    self.sourceGrants = sourceGrants
  }
}

/// Current stored mode and hard-stop state, read again at each authorization and dispatch.
public struct BotPolicyState: Equatable, Sendable {
  /// The bot's currently stored permission mode.
  public let permissionMode: PermissionMode
  /// Whether the bot is currently permitted to run.
  public let active: Bool
  /// Whether the global hard stop is active.
  public let killSwitch: Bool
}

/// One current authority read for the active turn or an explicitly selected stored task.
public struct PolicyCallSnapshot: Sendable {
  /// The actual active turn, or the original stored turn selected during reconciliation.
  public let turn: StoredChatTurn
  /// The application task owning the tool call.
  public let task: MemoshiTask
  /// The mode and hard stops read in the same snapshot.
  public let policy: BotPolicyState
  /// Sticky untrusted/private-data flags from prior tool output.
  public let exposure: Exposure
}
