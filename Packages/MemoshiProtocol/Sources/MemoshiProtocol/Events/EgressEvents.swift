/// The first admitted gateway connection to a host in a task. Not proof of an external effect.
public struct EgressAllowedPayload: EventPayload {
  /// Canonical gateway-admission event name.
  public static let eventType = "egress.allowed"
  /// Version of this payload.
  public static let typeVersion = 1
  /// Gateway admissions are included in the durable audit.
  public static let eventClass = EventClass.audited
  /// Scrubbed destination host, never a URL or query.
  public var host: String
  /// Trusted computer identity.
  public var computerId: String
  /// Actual task owning the authenticated live tool call.
  public var taskId: TaskID

  /// Records admission before dispatch; it does not assert delivery.
  public init(host: String, computerId: String, taskId: TaskID) {
    self.host = host
    self.computerId = computerId
    self.taskId = taskId
  }

  /// The typed event.
  public var asEvent: Event { .egressAllowed(self) }
}

/// A gateway refusal, coalesced per host/task. Malformed or unauthenticated requests have
/// no attributable task; nil is deliberate, never an invented task or the current root turn.
public struct EgressBlockedPayload: EventPayload {
  /// Canonical gateway-refusal event name.
  public static let eventType = "egress.blocked"
  /// Version of this payload.
  public static let typeVersion = 1
  /// Gateway refusals are included in the durable audit.
  public static let eventClass = EventClass.audited
  /// Scrubbed destination host, never a URL or query.
  public var host: String
  /// Trusted computer identity.
  public var computerId: String
  /// Actual owning task when authenticated; absent for unknown or malformed attribution.
  public var taskId: TaskID?
  /// Refusals represented by this first event or later durable summary.
  public var count: Int64

  /// Captures a refusal without inventing task ownership.
  public init(host: String, computerId: String, taskId: TaskID?, count: Int64) {
    self.host = host
    self.computerId = computerId
    self.taskId = taskId
    self.count = count
  }

  /// The typed event.
  public var asEvent: Event { .egressBlocked(self) }
}

/// Credential-use metadata from a trusted broker association, never a credential or placeholder.
public struct SecretUsedPayload: EventPayload {
  /// Canonical broker-use event name.
  public static let eventType = "secret.used"
  /// Version of this payload.
  public static let typeVersion = 1
  /// Credential use is included in the durable audit.
  public static let eventClass = EventClass.audited
  /// Opaque broker association, never a credential or mask token.
  public var secretRef: String
  /// Operation for which the broker association was used.
  public var purpose: SecretUsePurpose
  /// Scrubbed destination host.
  public var host: String

  /// Records the association of an actual prepared injection.
  public init(secretRef: String, purpose: SecretUsePurpose, host: String) {
    self.secretRef = secretRef
    self.purpose = purpose
    self.host = host
  }

  /// The typed event.
  public var asEvent: Event { .secretUsed(self) }
}

/// Distinct broker purposes from events.md; unknown values remain forward-compatible.
public enum SecretUsePurpose: OpenEnum {
  /// A credential supplied to an authorized browser form.
  case browserFill
  /// A masked header supplied through the egress gateway.
  case egressPlaceholder
  /// A credential supplied to an authorized command environment.
  case execEnv
  /// An unrecognized purpose retained without inventing semantics.
  case unknown(String)

  /// Known wire spellings.
  public static let wireTable = OpenEnumTable<Self>([
    .browserFill: "browser_fill", .egressPlaceholder: "egress_placeholder", .execEnv: "exec_env",
  ])

  /// The preserved spelling of an unrecognized purpose.
  public var unknownRawValue: String? {
    if case .unknown(let value) = self { value } else { nil }
  }
}
