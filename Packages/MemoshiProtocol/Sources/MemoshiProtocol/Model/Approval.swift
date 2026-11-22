/// A pending decision on one tool call; it expires to denied (object-model.md §4.19).
public struct Approval: Codable, Hashable, Sendable {
  /// The approval's ID.
  public var id: ApprovalID
  /// The bot whose call it is.
  public var botId: BotID
  /// The conversation of the call.
  public var conversationId: ConversationID
  /// The task of the call.
  public var taskId: TaskID
  /// The provider's call ID.
  public var toolCallId: String
  /// The outer call of a nested Code Mode or MCP-bridge call.
  public var parentToolCallId: String?
  /// The tool's name.
  public var tool: String
  /// The classified verb, for connector tools.
  public var verb: String?
  /// The tier, 0–5 (shown as T0–T5).
  public var tier: Tier
  /// The bot's permission mode when the call asked.
  public var permissionMode: PermissionMode
  /// Why the work exists.
  public var origin: Origin
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
  /// The redacted arguments; shows the exact command for T2 and above.
  public var argsPreview: JSONValue
  /// The policy rule that asked.
  public var ruleId: String
  /// Why the rule asked.
  public var reasonCode: String
  /// The policy version that decided.
  public var policyVersion: String
  /// T5: the text the user must type.
  public var confirmationText: String?
  /// The approval's state.
  public var status: ApprovalStatus
  /// When allowed: for once, the task, or always.
  public var scope: ApprovalScope?
  /// The `tool_rule` grant created by `task` or `always`.
  public var grantId: GrantID?
  /// When it expires to denied.
  public var expiresAt: Int64
  /// Who decided.
  public var decidedBy: Actor?
  /// When it was decided.
  public var decidedAt: Int64?
  /// T4 and T5: how the deciding device checked its owner.
  public var deviceAuth: DeviceAuthMethod?
  /// When it was created.
  public var createdAt: Int64

  /// Creates an approval record.
  public init(
    id: ApprovalID, botId: BotID, conversationId: ConversationID, taskId: TaskID,
    toolCallId: String, parentToolCallId: String? = nil, tool: String, verb: String? = nil,
    tier: Tier, permissionMode: PermissionMode, origin: Origin, attendance: Attendance,
    exposure: Exposure, computerKind: ComputerKind? = nil, deviceId: DeviceID, targets: [String],
    argsHash: String, argsPreview: JSONValue, ruleId: String, reasonCode: String,
    policyVersion: String, confirmationText: String? = nil, status: ApprovalStatus,
    scope: ApprovalScope? = nil, grantId: GrantID? = nil, expiresAt: Int64,
    decidedBy: Actor? = nil, decidedAt: Int64? = nil, deviceAuth: DeviceAuthMethod? = nil,
    createdAt: Int64
  ) {
    self.id = id
    self.botId = botId
    self.conversationId = conversationId
    self.taskId = taskId
    self.toolCallId = toolCallId
    self.parentToolCallId = parentToolCallId
    self.tool = tool
    self.verb = verb
    self.tier = tier
    self.permissionMode = permissionMode
    self.origin = origin
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
    self.confirmationText = confirmationText
    self.status = status
    self.scope = scope
    self.grantId = grantId
    self.expiresAt = expiresAt
    self.decidedBy = decidedBy
    self.decidedAt = decidedAt
    self.deviceAuth = deviceAuth
    self.createdAt = createdAt
  }
}

/// An approval's state (object-model.md §5.3).
public enum ApprovalStatus: OpenEnum {
  case pending
  case allowed
  case denied
  case expired
  case canceled
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .pending: "pending", .allowed: "allowed", .denied: "denied", .expired: "expired",
    .canceled: "canceled",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// How far an allowed approval reaches.
public enum ApprovalScope: OpenEnum {
  case once
  case task
  case always
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .once: "once", .task: "task", .always: "always",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
