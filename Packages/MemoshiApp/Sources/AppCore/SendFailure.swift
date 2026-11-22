import MemoshiProtocol

/// How a Chat answers a failed Send of its saved request (D130). The Mac and the in-process
/// Chat apply this one rule.
public enum SendFailure: Equatable, Sendable {
  /// A definite refusal of the request as sent: the engine applied nothing. The saved request
  /// is removed and the editable draft stays.
  case refused
  /// The engine definitely refused the saved request and will refuse it again as it stands.
  /// The request stays saved and Retry is unchanged; the refusal is named so that the person
  /// may discard the request instead.
  case refusedAsSaved
  /// No definite refusal of a saved request: delivery may be uncertain, or history already
  /// confirmed the request. The failure is shown, and a saved request stays for Retry.
  case uncertain

  /// Classifies what a Send threw. `isSaved` is whether its request is still saved; history
  /// can confirm it while the Send is in flight.
  public init(failure error: any Error, isSaved: Bool) {
    guard let error = error as? RPCError else {
      self = .uncertain
      return
    }
    switch error.kind {
    case .invalidParams, .busy, .notFound, .providerError, .methodNotFound, .forbidden:
      self = .refused
    // The owning runner changed: the earlier one may still have applied the request.
    case .leaseFenced:
      self = .uncertain
    default:
      self = isSaved && !error.data.retryable ? .refusedAsSaved : .uncertain
    }
  }
}
