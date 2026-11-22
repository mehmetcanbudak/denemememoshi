/// A typed event: one case per registered event type, plus an explicit unknown case.
public enum Event: Hashable, Sendable {
  case systemStopping(SystemStoppingPayload)
  case systemMigrated(SystemMigratedPayload)
  case systemAppConnected(SystemAppConnectedPayload)
  case systemAppDisconnected(SystemAppDisconnectedPayload)
  case systemPruned(SystemPrunedPayload)
  case systemSettingsChanged(SystemSettingsChangedPayload)
  case botCreated(BotCreatedPayload)
  case botUpdated(BotUpdatedPayload)
  case chatCreated(ChatCreatedPayload)
  case sessionCreated(SessionCreatedPayload)
  case sessionDeleted(SessionDeletedPayload)
  case sessionRestored(SessionRestoredPayload)
  case sessionPurged(SessionPurgedPayload)
  case trashEmptied(TrashEmptiedPayload)
  case messageCreated(MessageCreatedPayload)
  case messageDelta(MessageDeltaPayload)
  case messageCompleted(MessageCompletedPayload)
  case messageFailed(MessageFailedPayload)
  case messageQueued(MessageQueuedPayload)
  case messageForwarded(MessageForwardedPayload)
  case sideThreadOpened(SideThreadOpenedPayload)
  case taskCreated(TaskCreatedPayload)
  case taskStarted(TaskStartedPayload)
  case taskStatusChanged(TaskStatusChangedPayload)
  case taskProgress(TaskProgressPayload)
  case taskCancelRequested(TaskCancelRequestedPayload)
  case taskResumed(TaskResumedPayload)
  case taskFinished(TaskFinishedPayload)
  case toolInterrupted(ToolInterruptedPayload)
  case toolInterruptionResolved(ToolInterruptionResolvedPayload)
  case policyDecided(PolicyDecidedPayload)
  case policyRedacted(PolicyRedactedPayload)
  case toolCompleted(ToolCompletedPayload)
  case approvalRequested(ApprovalRequestedPayload)
  case approvalResolved(ApprovalResolvedPayload)
  case approvalExpired(ApprovalExpiredPayload)
  case approvalCanceled(ApprovalCanceledPayload)
  case grantGranted(GrantGrantedPayload)
  case grantRevoked(GrantRevokedPayload)
  case grantExpired(GrantExpiredPayload)
  case egressAllowed(EgressAllowedPayload)
  case egressBlocked(EgressBlockedPayload)
  case secretUsed(SecretUsedPayload)
  case cardCreated(CardCreatedPayload)
  case cardUpdated(CardUpdatedPayload)
  case cardResolved(CardResolvedPayload)
  case cardExpired(CardExpiredPayload)
  case cardCanceled(CardCanceledPayload)
  case cardAnswerLapsed(CardAnswerLapsedPayload)
  case inboxChanged(InboxChangedPayload)
  case systemResyncRequired(SystemResyncRequiredPayload)
  /// An event this build cannot read: an unknown `type`, an unsupported `typeVersion`, or a
  /// payload that failed to decode. The raw payload is kept so it re-encodes unchanged.
  case unknown(type: String, typeVersion: Int, raw: JSONValue)

  /// The typed payload; `nil` for `.unknown`.
  public var payload: (any EventPayload)? {
    switch self {
    case .systemStopping(let payload): payload
    case .systemMigrated(let payload): payload
    case .systemAppConnected(let payload): payload
    case .systemAppDisconnected(let payload): payload
    case .systemPruned(let payload): payload
    case .systemSettingsChanged(let payload): payload
    case .botCreated(let payload): payload
    case .botUpdated(let payload): payload
    case .chatCreated(let payload): payload
    case .sessionCreated(let payload): payload
    case .sessionDeleted(let payload): payload
    case .sessionRestored(let payload): payload
    case .sessionPurged(let payload): payload
    case .trashEmptied(let payload): payload
    case .messageCreated(let payload): payload
    case .messageDelta(let payload): payload
    case .messageCompleted(let payload): payload
    case .messageFailed(let payload): payload
    case .messageQueued(let payload): payload
    case .messageForwarded(let payload): payload
    case .sideThreadOpened(let payload): payload
    case .taskCreated(let payload): payload
    case .taskStarted(let payload): payload
    case .taskStatusChanged(let payload): payload
    case .taskProgress(let payload): payload
    case .taskCancelRequested(let payload): payload
    case .taskResumed(let payload): payload
    case .taskFinished(let payload): payload
    case .toolInterrupted(let payload): payload
    case .toolInterruptionResolved(let payload): payload
    case .policyDecided(let payload): payload
    case .policyRedacted(let payload): payload
    case .toolCompleted(let payload): payload
    case .approvalRequested(let payload): payload
    case .approvalResolved(let payload): payload
    case .approvalExpired(let payload): payload
    case .approvalCanceled(let payload): payload
    case .grantGranted(let payload): payload
    case .grantRevoked(let payload): payload
    case .grantExpired(let payload): payload
    case .egressAllowed(let payload): payload
    case .egressBlocked(let payload): payload
    case .secretUsed(let payload): payload
    case .cardCreated(let payload): payload
    case .cardUpdated(let payload): payload
    case .cardResolved(let payload): payload
    case .cardExpired(let payload): payload
    case .cardCanceled(let payload): payload
    case .cardAnswerLapsed(let payload): payload
    case .inboxChanged(let payload): payload
    case .systemResyncRequired(let payload): payload
    case .unknown: nil
    }
  }

  /// The event type, such as `message.created`.
  public var type: String {
    if case .unknown(let type, _, _) = self { return type }
    return payload.map { Swift.type(of: $0).eventType } ?? ""
  }

  /// The payload's schema version.
  public var typeVersion: Int {
    if case .unknown(_, let typeVersion, _) = self { return typeVersion }
    return payload.map { Swift.type(of: $0).typeVersion } ?? 0
  }

  /// The event without its live-only (†) payload fields.
  public func strippingLiveOnlyFields() -> Event {
    payload?.strippingLiveOnlyFields().asEvent ?? self
  }
}
