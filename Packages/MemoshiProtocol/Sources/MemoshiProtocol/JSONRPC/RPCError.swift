/// The JSON-RPC `error` object (protocol.md §10). Clients branch on `data.kind`, never on
/// `message`.
public struct RPCError: Error, Codable, Hashable, Sendable {
  /// The JSON-RPC code: −32700 to −32600 are standard; Memoshi uses −32000 to −32099.
  public var code: Int
  /// A human-readable message.
  public var message: String
  /// The stable discriminator and the kind's details.
  public var data: RPCErrorData

  /// Creates an error with an explicit code.
  public init(code: Int, message: String, data: RPCErrorData) {
    self.code = code
    self.message = message
    self.data = data
  }

  /// Creates an error whose code is its kind's code.
  public init(message: String, data: RPCErrorData) {
    self.init(code: data.kind.code ?? -32603, message: message, data: data)
  }

  /// The error's kind.
  public var kind: RPCErrorKind { data.kind }
}

/// `error.data`: `{kind, retryable}` and exactly the details its kind defines, side by side in
/// one flat object (protocol.md §10). The schema's `RPCErrorData` is a union by `kind`, so a kind
/// requires its own details and its own `retryable` value, and allows no other details.
public struct RPCErrorData: Hashable, Sendable {
  /// The kind and its details.
  public var details: RPCErrorDetails

  /// Creates error data. `retryable` is not a parameter: the kind fixes it.
  public init(details: RPCErrorDetails) {
    self.details = details
  }

  /// The stable discriminator.
  public var kind: RPCErrorKind { details.kind }

  /// Whether sending the same request again may succeed. A known kind fixes the value
  /// (``RPCErrorKind/retryable``, protocol.md §10), whatever a peer sent; for a kind this build
  /// does not know it is the value received.
  public var retryable: Bool {
    if let retryable = kind.retryable { return retryable }
    guard case .unknown(_, .object(let members)) = details,
      case .bool(let retryable)? = members["retryable"]
    else { return false }
    return retryable
  }
}

extension RPCErrorData: Codable, WireShaped {
  private enum CodingKeys: String, CodingKey {
    case kind
    case retryable
  }

  /// One variant per known kind: `retryable`, fixed to the kind's value, and the kind's
  /// details.
  public static var wireShape: WireShape {
    .union(
      discriminator: "kind",
      variants: RPCErrorKind.wireTable.rawValues.map { tag in
        let kind = RPCErrorKind(rawValue: tag)
        return WireVariant(
          tag: tag,
          fields: [RPCErrorBasics.self] + RPCErrorDetails.detailFields(of: kind),
          constants: kind.retryable.map { ["retryable": .bool($0)] } ?? [:])
      })
  }

  /// Decodes the data by its `kind`. An unknown kind becomes `.unknown` unless decoding is
  /// strict; a known kind without its details fails in both modes. `retryable` is required.
  /// Both modes read a known kind's flag tolerantly: the schema fixes it per kind, and the
  /// decoded data reports the kind's value whatever was sent (D130).
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let rawKind = try container.decode(String.self, forKey: .kind)
    _ = try RPCErrorBasics(from: decoder)
    let kind = RPCErrorKind(rawValue: rawKind)
    guard kind.isKnown else {
      if decoder.isStrictProtocolDecoding {
        throw DecodingError.dataCorruptedError(
          forKey: .kind, in: container, debugDescription: "Unknown error kind \(rawKind)")
      }
      self.init(details: .unknown(kind: rawKind, raw: try JSONValue(from: decoder)))
      return
    }
    self.init(details: try RPCErrorDetails(kind: kind, from: decoder))
  }

  /// Encodes `kind`, `retryable` and the details in one object; an unknown kind's data as
  /// received.
  public func encode(to encoder: any Encoder) throws {
    if case .unknown(_, let raw) = details {
      try raw.encode(to: encoder)
      return
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind.rawValue, forKey: .kind)
    try container.encode(retryable, forKey: .retryable)
    try details.payload?.encode(to: encoder)
  }
}

/// The member every error's data carries besides `kind`.
private struct RPCErrorBasics: Decodable {
  let retryable: Bool
}

/// An error's kind with its details (protocol.md §10). Kinds without details carry none.
public enum RPCErrorDetails: Hashable, Sendable {
  case parseError
  case invalidRequest
  case methodNotFound
  case invalidParams(InvalidParamsDetails)
  case internalError(InternalErrorDetails)
  case unauthorized
  case versionMismatch(VersionMismatchDetails)
  case forbidden
  case notFound
  case conflict
  case busy
  case idempotencyConflict
  case cardResolved(CardResolvedDetails)
  case cardExpired(CardExpiredDetails)
  case policyDenied(PolicyDeniedDetails)
  case budgetExhausted(BudgetExhaustedDetails)
  case hostUnavailable
  case computerUnavailable
  case providerError
  case rateLimited(RateLimitedDetails)
  case payloadTooLarge
  case invalidState
  case storageFailed
  case shuttingDown
  case capabilityMissing
  case timeout
  case canceled
  case typedConfirmationMismatch
  case leaseFenced(LeaseFencedDetails)
  case deviceUnreachable
  case deviceRevoked
  case pairingFailed
  case deviceGrantMissing
  case updateRequired
  case deviceAuthRequired
  /// A kind this build does not know, with its whole `data` object as received.
  case unknown(kind: String, raw: JSONValue)

  /// The kind.
  public var kind: RPCErrorKind {
    switch self {
    case .parseError: .parseError
    case .invalidRequest: .invalidRequest
    case .methodNotFound: .methodNotFound
    case .invalidParams: .invalidParams
    case .internalError: .internalError
    case .unauthorized: .unauthorized
    case .versionMismatch: .versionMismatch
    case .forbidden: .forbidden
    case .notFound: .notFound
    case .conflict: .conflict
    case .busy: .busy
    case .idempotencyConflict: .idempotencyConflict
    case .cardResolved: .cardResolved
    case .cardExpired: .cardExpired
    case .policyDenied: .policyDenied
    case .budgetExhausted: .budgetExhausted
    case .hostUnavailable: .hostUnavailable
    case .computerUnavailable: .computerUnavailable
    case .providerError: .providerError
    case .rateLimited: .rateLimited
    case .payloadTooLarge: .payloadTooLarge
    case .invalidState: .invalidState
    case .storageFailed: .storageFailed
    case .shuttingDown: .shuttingDown
    case .capabilityMissing: .capabilityMissing
    case .timeout: .timeout
    case .canceled: .canceled
    case .typedConfirmationMismatch: .typedConfirmationMismatch
    case .leaseFenced: .leaseFenced
    case .deviceUnreachable: .deviceUnreachable
    case .deviceRevoked: .deviceRevoked
    case .pairingFailed: .pairingFailed
    case .deviceGrantMissing: .deviceGrantMissing
    case .updateRequired: .updateRequired
    case .deviceAuthRequired: .deviceAuthRequired
    case .unknown(let kind, _): .unknown(kind)
    }
  }

  /// The details' own fields, encoded beside `kind` and `retryable`.
  var payload: (any Encodable)? {
    switch self {
    case .invalidParams(let details): details
    case .internalError(let details): details
    case .versionMismatch(let details): details
    case .cardResolved(let details): details
    case .cardExpired(let details): details
    case .policyDenied(let details): details
    case .budgetExhausted(let details): details
    case .rateLimited(let details): details
    case .leaseFenced(let details): details
    default: nil
    }
  }

  /// The types that decode a kind's details; none for a kind without details.
  static func detailFields(of kind: RPCErrorKind) -> [any Decodable.Type] {
    switch kind {
    case .invalidParams: [InvalidParamsDetails.self]
    case .internalError: [InternalErrorDetails.self]
    case .versionMismatch: [VersionMismatchDetails.self]
    case .cardResolved: [CardResolvedDetails.self]
    case .cardExpired: [CardExpiredDetails.self]
    case .policyDenied: [PolicyDeniedDetails.self]
    case .budgetExhausted: [BudgetExhaustedDetails.self]
    case .rateLimited: [RateLimitedDetails.self]
    case .leaseFenced: [LeaseFencedDetails.self]
    default: []
    }
  }

  /// Decodes a known kind's details from the data object.
  init(kind: RPCErrorKind, from decoder: any Decoder) throws {
    switch kind {
    case .parseError: self = .parseError
    case .invalidRequest: self = .invalidRequest
    case .methodNotFound: self = .methodNotFound
    case .invalidParams: self = .invalidParams(try InvalidParamsDetails(from: decoder))
    case .internalError: self = .internalError(try InternalErrorDetails(from: decoder))
    case .unauthorized: self = .unauthorized
    case .versionMismatch: self = .versionMismatch(try VersionMismatchDetails(from: decoder))
    case .forbidden: self = .forbidden
    case .notFound: self = .notFound
    case .conflict: self = .conflict
    case .busy: self = .busy
    case .idempotencyConflict: self = .idempotencyConflict
    case .cardResolved: self = .cardResolved(try CardResolvedDetails(from: decoder))
    case .cardExpired: self = .cardExpired(try CardExpiredDetails(from: decoder))
    case .policyDenied: self = .policyDenied(try PolicyDeniedDetails(from: decoder))
    case .budgetExhausted: self = .budgetExhausted(try BudgetExhaustedDetails(from: decoder))
    case .hostUnavailable: self = .hostUnavailable
    case .computerUnavailable: self = .computerUnavailable
    case .providerError: self = .providerError
    case .rateLimited: self = .rateLimited(try RateLimitedDetails(from: decoder))
    case .payloadTooLarge: self = .payloadTooLarge
    case .invalidState: self = .invalidState
    case .storageFailed: self = .storageFailed
    case .shuttingDown: self = .shuttingDown
    case .capabilityMissing: self = .capabilityMissing
    case .timeout: self = .timeout
    case .canceled: self = .canceled
    case .typedConfirmationMismatch: self = .typedConfirmationMismatch
    case .leaseFenced: self = .leaseFenced(try LeaseFencedDetails(from: decoder))
    case .deviceUnreachable: self = .deviceUnreachable
    case .deviceRevoked: self = .deviceRevoked
    case .pairingFailed: self = .pairingFailed
    case .deviceGrantMissing: self = .deviceGrantMissing
    case .updateRequired: self = .updateRequired
    case .deviceAuthRequired: self = .deviceAuthRequired
    case .unknown(let raw):
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath, debugDescription: "Unknown error kind \(raw)"))
    }
  }
}

/// `invalid_params`: the schema problems found.
public struct InvalidParamsDetails: Codable, Hashable, Sendable {
  /// The problems.
  public var issues: [ParamIssue]

  /// Creates the details.
  public init(issues: [ParamIssue]) {
    self.issues = issues
  }
}

/// `internal_error`: where to look in the logs.
public struct InternalErrorDetails: Codable, Hashable, Sendable {
  /// The incident's ID in the logs.
  public var incidentId: String

  /// Creates the details.
  public init(incidentId: String) {
    self.incidentId = incidentId
  }
}

/// `version_mismatch`: both sides' versions and what the app should do (protocol.md §3.5).
public struct VersionMismatchDetails: Codable, Hashable, Sendable {
  /// The versions the daemon supports.
  public var daemon: ProtocolRange
  /// The versions the client offered.
  public var client: ProtocolRange
  /// What the app should do.
  public var action: VersionMismatchAction

  /// Creates the details.
  public init(daemon: ProtocolRange, client: ProtocolRange, action: VersionMismatchAction) {
    self.daemon = daemon
    self.client = client
    self.action = action
  }
}

/// `card_resolved`: the card and the action that resolved it first.
public struct CardResolvedDetails: Codable, Hashable, Sendable {
  /// The card.
  public var cardId: CardID
  /// The action that resolved it.
  public var resolution: String

  /// Creates the details.
  public init(cardId: CardID, resolution: String) {
    self.cardId = cardId
    self.resolution = resolution
  }
}

/// `card_expired`: the card.
public struct CardExpiredDetails: Codable, Hashable, Sendable {
  /// The card.
  public var cardId: CardID

  /// Creates the details.
  public init(cardId: CardID) {
    self.cardId = cardId
  }
}

/// `policy_denied`: the rule that denied.
public struct PolicyDeniedDetails: Codable, Hashable, Sendable {
  /// The rule.
  public var ruleId: String

  /// Creates the details.
  public init(ruleId: String) {
    self.ruleId = ruleId
  }
}

/// `budget_exhausted`: the budget that stopped, what it applies to, and when it resets.
public struct BudgetExhaustedDetails: Codable, Hashable, Sendable {
  /// The budget.
  public var budgetId: BudgetID
  /// What the budget applies to, such as `{kind: bot, id}`.
  public var scope: ObjectRef
  /// When it resets.
  public var resetsAt: Int64

  /// Creates the details.
  public init(budgetId: BudgetID, scope: ObjectRef, resetsAt: Int64) {
    self.budgetId = budgetId
    self.scope = scope
    self.resetsAt = resetsAt
  }
}

/// `rate_limited`: how long to wait.
public struct RateLimitedDetails: Codable, Hashable, Sendable {
  /// Milliseconds to wait before retrying.
  public var retryAfterMs: Int64

  /// Creates the details.
  public init(retryAfterMs: Int64) {
    self.retryAfterMs = retryAfterMs
  }
}

/// `lease_fenced`: the conversation's current lease epoch.
public struct LeaseFencedDetails: Codable, Hashable, Sendable {
  /// The current epoch.
  public var currentEpoch: Int64

  /// Creates the details.
  public init(currentEpoch: Int64) {
    self.currentEpoch = currentEpoch
  }
}

/// One schema problem in `invalid_params`.
public struct ParamIssue: Codable, Hashable, Sendable {
  /// A JSON Pointer to the offending parameter.
  public var path: String
  /// What is wrong.
  public var message: String

  /// Creates an issue.
  public init(path: String, message: String) {
    self.path = path
    self.message = message
  }
}

/// What the app does after `version_mismatch` (protocol.md §3.5).
public enum VersionMismatchAction: OpenEnum {
  case updateApp
  case restartDaemon
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .updateApp: "update_app", .restartDaemon: "restart_daemon",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// The stable error discriminator, `error.data.kind` (protocol.md §10).
public enum RPCErrorKind: OpenEnum {
  case parseError
  case invalidRequest
  case methodNotFound
  case invalidParams
  case internalError
  case unauthorized
  case versionMismatch
  case forbidden
  case notFound
  case conflict
  case busy
  case idempotencyConflict
  case cardResolved
  case cardExpired
  case policyDenied
  case budgetExhausted
  case hostUnavailable
  case computerUnavailable
  case providerError
  case rateLimited
  case payloadTooLarge
  case invalidState
  case storageFailed
  case shuttingDown
  case capabilityMissing
  case timeout
  case canceled
  case typedConfirmationMismatch
  case leaseFenced
  case deviceUnreachable
  case deviceRevoked
  case pairingFailed
  case deviceGrantMissing
  case updateRequired
  case deviceAuthRequired
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .parseError: "parse_error", .invalidRequest: "invalid_request",
    .methodNotFound: "method_not_found", .invalidParams: "invalid_params",
    .internalError: "internal_error", .unauthorized: "unauthorized",
    .versionMismatch: "version_mismatch", .forbidden: "forbidden", .notFound: "not_found",
    .conflict: "conflict", .busy: "busy", .idempotencyConflict: "idempotency_conflict",
    .cardResolved: "card_resolved", .cardExpired: "card_expired",
    .policyDenied: "policy_denied", .budgetExhausted: "budget_exhausted",
    .hostUnavailable: "host_unavailable", .computerUnavailable: "computer_unavailable",
    .providerError: "provider_error", .rateLimited: "rate_limited",
    .payloadTooLarge: "payload_too_large", .invalidState: "invalid_state",
    .storageFailed: "storage_failed", .shuttingDown: "shutting_down",
    .capabilityMissing: "capability_missing", .timeout: "timeout", .canceled: "canceled",
    .typedConfirmationMismatch: "typed_confirmation_mismatch", .leaseFenced: "lease_fenced",
    .deviceUnreachable: "device_unreachable", .deviceRevoked: "device_revoked",
    .pairingFailed: "pairing_failed", .deviceGrantMissing: "device_grant_missing",
    .updateRequired: "update_required", .deviceAuthRequired: "device_auth_required",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }

  /// The JSON-RPC code of each known kind (protocol.md §10).
  public static let codes: [RPCErrorKind: Int] = [
    .parseError: -32700, .invalidRequest: -32600, .methodNotFound: -32601,
    .invalidParams: -32602, .internalError: -32603, .unauthorized: -32000,
    .versionMismatch: -32001, .forbidden: -32002, .notFound: -32003, .conflict: -32004,
    .busy: -32005, .idempotencyConflict: -32006, .cardResolved: -32007,
    .cardExpired: -32008, .policyDenied: -32009, .budgetExhausted: -32010,
    .hostUnavailable: -32011, .computerUnavailable: -32012, .providerError: -32013,
    .rateLimited: -32014, .payloadTooLarge: -32015, .invalidState: -32016,
    .storageFailed: -32017, .shuttingDown: -32018, .capabilityMissing: -32019,
    .timeout: -32020, .canceled: -32021, .typedConfirmationMismatch: -32022,
    .leaseFenced: -32023, .deviceUnreachable: -32024, .deviceRevoked: -32025,
    .pairingFailed: -32026, .deviceGrantMissing: -32027, .updateRequired: -32028,
    .deviceAuthRequired: -32029,
  ]

  /// This kind's JSON-RPC code; `nil` for an unknown kind.
  public var code: Int? { Self.codes[self] }

  /// Whether sending the same request again may succeed: protocol.md §10's Retry column, where
  /// Yes and Maybe are `true`, and No, Reconnect, After a refresh and After the check are
  /// `false`, because the request must change or the client must act first. `nil` for an
  /// unknown kind.
  public var retryable: Bool? {
    switch self {
    case .internalError, .busy, .hostUnavailable, .computerUnavailable, .providerError,
      .rateLimited, .invalidState, .storageFailed, .shuttingDown, .timeout, .deviceUnreachable:
      true
    case .parseError, .invalidRequest, .methodNotFound, .invalidParams, .unauthorized,
      .versionMismatch, .forbidden, .notFound, .conflict, .idempotencyConflict, .cardResolved,
      .cardExpired, .policyDenied, .budgetExhausted, .payloadTooLarge, .capabilityMissing,
      .canceled, .typedConfirmationMismatch, .leaseFenced, .deviceRevoked, .pairingFailed,
      .deviceGrantMissing, .updateRequired, .deviceAuthRequired:
      false
    case .unknown: nil
    }
  }
}
