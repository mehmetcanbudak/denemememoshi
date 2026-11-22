/// The host-side policy decision requested before every valid public destination is dialed.
/// No URL, body, headers, credentials, placeholder values or proxy token cross this seam.
public struct EgressAuthorizationRequest: Sendable, Equatable {
  /// The trusted client's bot, conversation and computer attribution, not HTTP-supplied identity.
  public let identity: EgressClientIdentity
  /// The live tool-call identifier selected by the request's active proxy attribution token.
  public let call: String
  /// The visible HTTP verb, or `CONNECT` when the tunneled request itself is opaque.
  public let method: String
  /// The normalized destination DNS name; IP literals and local names are refused before this seam.
  public let host: String
  /// The destination TCP port, checked separately from the host's network-list membership.
  public let port: Int
  /// Membership in this client's configured network list. A host not listed is T3, not an
  /// automatic permission; only the trusted host authorizer can resolve Ask/Bypass/rules.
  public let allowlisted: Bool
  /// Host-level T0 or T3. Opaque CONNECT does not expose a method, body or send operation.
  public let tier: Int
  /// True only for a secret-bound host whose HTTP headers the gateway can inspect. Other
  /// This Mac/WebKit destinations deliberately receive host-level control (policy §3.7).
  public let methodVisible: Bool
  /// A CONNECT that will terminate at this client's configured TLS inspection boundary.
  /// This lets current policy refuse a stale opaque client after secret-host grants change.
  public let interceptsTLS: Bool
  /// The actual upstream transport, not a port-number inference.
  public let usesTLS: Bool
  /// Whether a configured host-and-port rule grants writes; not a substitute for live authorization.
  public let writeAllowed: Bool
  /// For visible requests: T0 for bodyless GET/HEAD, otherwise T3 with a write grant or T4.
  /// Opaque tunnels and host-only requests carry nil, not a fabricated read classification.
  public let sendTier: Int?
  /// Names of bound credentials requested for injection, never their values.
  public let secrets: [String]
  /// Actual immutable broker associations for header injections, not environment-variable names.
  public let secretReferences: [String: String]
}

/// The trusted host's decision for this attempt, subject to the gateway's non-overridable checks.
public enum EgressAuthorization: Sendable {
  /// Allows dispatch only while attribution remains active and required audit recording succeeds.
  case allow
  /// A host can wait for a real user card inside authorize; returning ask refuses this attempt
  /// without sending anything. Nothing is retried automatically.
  case ask
  /// Refuses upstream dispatch for this attempt, including a recheck after earlier authorization.
  case deny
}

/// Reads current bot/grants/mode/origin/kill-switch records for each request. It may narrow the
/// gateway's hard boundaries but cannot override IP/local/private-address or secret-host checks.
public protocol EgressRequestAuthorizer: Sendable {
  func authorize(_ request: EgressAuthorizationRequest) async throws -> EgressAuthorization
}

/// Durably projects a redacted gateway decision to the owning store/audit boundary. An allowed
/// request is not dialed if the required sink throws. Store event coalescing belongs to the sink,
/// not to the gateway; repeated network requests still receive individual policy decisions.
public protocol EgressDecisionSink: Sendable {
  func record(_ decision: EgressDecision) async throws
}
