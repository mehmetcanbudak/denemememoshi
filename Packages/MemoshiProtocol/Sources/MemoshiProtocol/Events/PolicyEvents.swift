/// `policy.decided`: content-free authorization metadata, mirrored to audit atomically.
public struct PolicyDecidedPayload: EventPayload {
  /// `policy.decided`.
  public static let eventType = "policy.decided"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable and atomically mirrored to audit.
  public static let eventClass = EventClass.audited
  /// The actual runtime call ID.
  public var toolCallId: String
  /// The outer call for a nested invocation.
  public var parentToolCallId: String?
  /// The channel the call arrived through (policy.md P1). Absent for a call nested in a host
  /// tool that is neither Code Mode nor an MCP bridge, and in facts recorded before this field.
  public var via: ToolCallVia?
  /// The registered tool name, or the requested name of an unavailable tool.
  public var tool: String
  /// The evaluated friction, not a claim that an effect occurred.
  public var decision: PolicyDecisionKind
  /// Whether policy permits automatic dispatch of a draft.
  public var autoSend: Bool?
  /// The trusted operation's T0–T5 classification.
  public var tier: Tier
  /// The trusted operation class.
  public var opClass: String
  /// The deciding rule.
  public var ruleId: String
  /// The stored mode read at this decision.
  public var permissionMode: PermissionMode
  /// Whether the session is restricted to planning.
  public var plan: Bool
  /// The preserved immediate and root origins.
  public var origin: Origin
  /// Whether the root work is attended.
  public var attendance: Attendance
  /// Sticky context exposure at authorization.
  public var exposure: Exposure
  /// The device making the decision.
  public var deviceId: DeviceID
  /// True for the fresh dispatch check, including recovery.
  public var recheck: Bool?
  /// A stable presentation-safe reason.
  public var reasonCode: String
  /// The hash of the policy and trusted tool metadata.
  public var policyVersion: String
  /// SHA-256 of the canonical arguments; never their contents.
  public var argsHash: String

  /// Creates content-free metadata for an authorization or dispatch decision.
  public init(
    toolCallId: String, parentToolCallId: String? = nil, via: ToolCallVia? = nil, tool: String,
    decision: PolicyDecisionKind, autoSend: Bool? = nil, tier: Tier, opClass: String,
    ruleId: String, permissionMode: PermissionMode, plan: Bool, origin: Origin,
    attendance: Attendance, exposure: Exposure, deviceId: DeviceID, recheck: Bool? = nil,
    reasonCode: String, policyVersion: String, argsHash: String
  ) {
    self.toolCallId = toolCallId
    self.parentToolCallId = parentToolCallId
    self.via = via
    self.tool = tool
    self.decision = decision
    self.autoSend = autoSend
    self.tier = tier
    self.opClass = opClass
    self.ruleId = ruleId
    self.permissionMode = permissionMode
    self.plan = plan
    self.origin = origin
    self.attendance = attendance
    self.exposure = exposure
    self.deviceId = deviceId
    self.recheck = recheck
    self.reasonCode = reasonCode
    self.policyVersion = policyVersion
    self.argsHash = argsHash
  }
  /// `.policyDecided(self)`.
  public var asEvent: Event { .policyDecided(self) }
}

/// The channel through which a tool call reached the mandatory policy hooks (policy.md P1).
public enum ToolCallVia: OpenEnum {
  /// The model called a tool that is not an MCP-bridge tool.
  case model
  /// A Code Mode script called a tool that is not an MCP-bridge tool; the call carries its
  /// script's `codemode` call as `parentToolCallId`.
  case codeMode
  /// An MCP-bridge tool, called by the model or nested in a script, which then sets
  /// `parentToolCallId`.
  case mcp
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .model: "model", .codeMode: "code_mode", .mcp: "mcp",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// `policy.redacted`: counts and detector kinds, never the original output or secret.
public struct PolicyRedactedPayload: EventPayload {
  /// `policy.redacted`.
  public static let eventType = "policy.redacted"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable and atomically mirrored to audit.
  public static let eventClass = EventClass.audited
  /// The call whose result was scrubbed.
  public var toolCallId: String
  /// The number of replacements or a withheld result.
  public var count: Int64
  /// Detector categories only, never matched values.
  public var kinds: [String]
  /// Creates safe redaction accounting.
  public init(toolCallId: String, count: Int64, kinds: [String]) {
    self.toolCallId = toolCallId
    self.count = count
    self.kinds = kinds
  }
  /// `.policyRedacted(self)`.
  public var asEvent: Event { .policyRedacted(self) }
}

/// `card.canceled`: its owning call/task ended without a user decision.
public struct CardCanceledPayload: EventPayload {
  /// `card.canceled`.
  public static let eventType = "card.canceled"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable; cancellation is not a user answer.
  public static let eventClass = EventClass.durable
  /// The canceled presentation.
  public var cardId: CardID
  /// Why its owning decision ended.
  public var reason: ApprovalCancelReason
  /// Creates the presentation counterpart of `approval.canceled`.
  public init(cardId: CardID, reason: ApprovalCancelReason) {
    self.cardId = cardId
    self.reason = reason
  }
  /// `.cardCanceled(self)`.
  public var asEvent: Event { .cardCanceled(self) }
}

/// `tool.completed`: one settled result's metadata; actual output stays only in Pi storage.
public struct ToolCompletedPayload: EventPayload {
  /// `tool.completed`.
  public static let eventType = "tool.completed"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable and atomically mirrored to audit.
  public static let eventClass = EventClass.audited
  /// The completed runtime call.
  public var toolCallId: String
  /// The outer call for a nested invocation.
  public var parentToolCallId: String?
  /// The registered tool name, or the requested name of an unavailable tool.
  public var tool: String
  /// Whether the result completed successfully.
  public var ok: Bool
  /// A stable error category, never a raw exception.
  public var errorCode: String?
  /// SDK execution milliseconds; zero when the committed result has no execution measurement.
  public var durationMs: Int64
  /// Committed model text bytes including SDK diagnostics; nested calls count returned text
  /// or canonical structured data. Zero for absent data; neither count is HTTP wire bytes.
  public var outputBytes: Int64
  /// The number of safe replacements in both result representations.
  public var redactions: Int64
  /// Creates output-free completion accounting.
  public init(
    toolCallId: String, parentToolCallId: String? = nil, tool: String, ok: Bool,
    errorCode: String? = nil, durationMs: Int64, outputBytes: Int64, redactions: Int64
  ) {
    self.toolCallId = toolCallId
    self.parentToolCallId = parentToolCallId
    self.tool = tool
    self.ok = ok
    self.errorCode = errorCode
    self.durationMs = durationMs
    self.outputBytes = outputBytes
    self.redactions = redactions
  }
  /// `.toolCompleted(self)`.
  public var asEvent: Event { .toolCompleted(self) }
}
