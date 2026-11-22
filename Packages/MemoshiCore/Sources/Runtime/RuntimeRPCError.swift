import MemoshiProtocol
import MemoshiStore

/// Safe domain refusals shared by the socket and in-process hosts. Unknown failures remain
/// unknown: the socket closes rather than claiming delivery, and the in-process host reports
/// an incident without exposing provider, filesystem or SDK error text.
public enum RuntimeRPCError {
  /// A recognized domain refusal, or nil when the transport must handle an unknown failure.
  public static func map(_ error: any Error) -> RPCError? {
    switch error {
    case let error as RPCError:
      return error
    case let error as RuntimeError:
      switch error {
      case .invalidParams: return invalidParams()
      case .busy:
        return make(.busy, "The conversation or model settings are busy.")
      case .modelUnavailable, .providerUnavailable:
        return make(
          .providerError,
          "The selected model or its key is unavailable. Check provider settings and refresh models."
        )
      case .notStarted:
        return make(.invalidState, "The text runtime has not started.")
      case .stopping:
        return make(.shuttingDown, "The text runtime is stopping.")
      case .projectionFailed:
        return make(.storageFailed, "Conversation state could not be reconciled.")
      case .recoveryRequired:
        return make(
          .busy, "This chat requires recovery. Stop cannot undo an uncertain tool effect.")
      }
    case let error as ApprovalError:
      switch error {
      case .notFound: return make(.notFound, "Approval card not found.")
      case .invalidRequest: return invalidParams()
      case .forbidden:
        return make(.forbidden, "Only the authenticated app user may answer this card.")
      case .deviceAuthRequired:
        return make(.deviceAuthRequired, "A verified device owner check is required.")
      case .capabilityMissing:
        return make(.capabilityMissing, "This approval action is not enabled.")
      case .bindingConflict:
        return make(.conflict, "Approval state changed; refresh the card.")
      case .resolved(let cardID, let action):
        return make(
          .cardResolved(CardResolvedDetails(cardId: cardID, resolution: action)),
          "This card was already answered.")
      case .expired(let cardID):
        return make(.cardExpired(CardExpiredDetails(cardId: cardID)), "This card has expired.")
      }
    case let error as ConversationRecordError:
      switch error {
      case .invalidProfile: return invalidParams()
      case .botNotFound: return make(.notFound, "Bot not found.")
      case .nameTaken: return make(.conflict, "Another bot already has this name.")
      case .staleRevision:
        return make(.conflict, "This bot changed since it was loaded. Reload it, then edit again.")
      }
    case let error as StoreError:
      switch error {
      case .requestConflict:
        return make(
          .idempotencyConflict, "This request key already identifies different parameters.")
      case .chatBusy:
        return make(.busy, "The conversation is already answering.")
      case .chatNotFound:
        return make(.notFound, "Conversation not found.")
      case .chatRecoveryRequired:
        return make(.busy, "This chat is paused until its tool outcome is resolved.")
      case .chatQueueFull:
        return make(
          .busy,
          "The recovery queue is full (32 messages or 256 KiB total). Cancel an unsent message first."
        )
      default:
        return make(.storageFailed, "Storage operation failed.")
      }
    default:
      return nil
    }
  }

  private static func make(_ details: RPCErrorDetails, _ message: String) -> RPCError {
    RPCError(message: message, data: RPCErrorData(details: details))
  }

  private static func invalidParams() -> RPCError {
    make(
      .invalidParams(
        InvalidParamsDetails(issues: [ParamIssue(path: "/params", message: "Invalid parameters.")])),
      "Parameters do not match the method.")
  }
}
