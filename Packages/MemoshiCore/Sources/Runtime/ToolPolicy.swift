import MemoshiProtocol

/// Trusted tool-definition metadata, never a classification supplied by model arguments.
public enum ToolPolicyOperation: String, Codable, Hashable, Sendable {
  case selfState = "self.state"
  case selfPropose = "self.propose"
  case modelCall = "model.call"
  case codeRun = "code.run"
  case fileRead = "fs.read"
  case fileWrite = "fs.write"
  case gitRead = "git.read"
  case gitLocal = "git.local"
  case shellExecute = "shell.exec"
  case pythonRun = "python.run"
  case networkFetch = "net.fetch"
  case networkSend = "net.send"
  case connectorRead = "connector.read"
  case connectorStage = "connector.stage"
  case connectorWrite = "connector.write"
  case connectorSend = "connector.send"
  case connectorDestroy = "connector.destroy"
  case connectorMoney = "connector.money"
  case connectorPermission = "connector.permission"
  case secretUse = "secret.use"
  case secretReveal = "secret.reveal"
  case money = "spend.pay"
  case appleRead = "apple.read"
  case appleWrite = "apple.write"
  case unknown

  /// The ungranted base class; exact current host grants refine network classification.
  public var tier: Int {
    switch self {
    case .selfState, .selfPropose, .modelCall, .codeRun, .fileRead, .gitRead: 0
    case .fileWrite, .gitLocal: 1
    case .shellExecute, .pythonRun: 2
    case .networkFetch, .connectorRead, .connectorStage, .secretUse, .appleRead, .unknown: 3
    case .networkSend, .connectorWrite, .connectorSend, .appleWrite: 4
    case .connectorDestroy, .connectorMoney, .connectorPermission, .secretReveal, .money: 5
    }
  }

  var keepsCard: Bool {
    switch self {
    case .connectorMoney, .connectorPermission, .secretUse, .secretReveal, .money, .unknown: true
    default: false
    }
  }

  /// Only these operations read declared source targets; any other operation may write them.
  var readsSourceOnly: Bool {
    switch self {
    case .fileRead, .gitRead: true
    default: false
    }
  }
}

/// Current host/port grant, supplied by the host directory rather than request arguments.
public enum ToolPolicyNetworkGrant: Equatable, Sendable {
  /// No currently granted host/port; host access retains T3 friction.
  case none
  /// Bodyless reads are T0; visible sends remain T4.
  case read
  /// Bodyless reads are T0; visible sends are T3, not unconditional permission.
  case readWrite
}

/// Facts supplied by the host's current records, not by the tool or the model.
public struct ToolPolicyContext: Sendable {
  /// The current stored permission mode.
  public var permissionMode: PermissionMode
  /// The immutable root of the delegation chain.
  public var rootOrigin: OriginKind
  /// Whether current host grant and target checks permit the operation.
  public var grantsPresent: Bool
  /// Whether current budget authority permits dispatch.
  public var budgetAvailable: Bool
  /// Whether the bot is active rather than paused.
  public var botActive: Bool
  /// Whether the global hard stop overrides all modes.
  public var killSwitch: Bool
  /// Whether the session is restricted to planning.
  public var plan: Bool
  /// Whether a local write is confined to the bot's own home.
  public var isBotHome: Bool
  /// The actual target computer class.
  public var computerKind: ComputerKind
  /// Original-source classes of every declared source target, derived by trusted host code
  /// through ``SourcePathPolicy``; empty when the call has none. Source data is never bot home.
  public var sourcePathClasses: Set<SourcePathClass>
  /// Exact current destination authority; opaque This Mac tunnels remain host-level.
  public var networkGrant: ToolPolicyNetworkGrant

  /// Grant and budget authority must be explicit even for a read.
  public init(
    permissionMode: PermissionMode, rootOrigin: OriginKind,
    grantsPresent: Bool, budgetAvailable: Bool, botActive: Bool = true,
    killSwitch: Bool = false, plan: Bool = false, isBotHome: Bool = false,
    computerKind: ComputerKind = .macSandbox, sourcePathClasses: Set<SourcePathClass> = [],
    networkGrant: ToolPolicyNetworkGrant = .none
  ) {
    self.permissionMode = permissionMode
    self.rootOrigin = rootOrigin
    self.grantsPresent = grantsPresent
    self.budgetAvailable = budgetAvailable
    self.botActive = botActive
    self.killSwitch = killSwitch
    self.plan = plan
    self.isBotHome = isBotHome
    self.computerKind = computerKind
    self.sourcePathClasses = sourcePathClasses
    self.networkGrant = networkGrant
  }
}

/// Friction and its audit reason. A draft is never permission to run the original tool.
public struct ToolPolicyDecision: Equatable, Sendable {
  /// The shared wire-level decision kinds.
  public typealias Kind = PolicyDecisionKind
  /// Friction to apply; a draft never authorizes the original effect.
  public let kind: Kind
  /// Stable presentation-safe audit reason.
  public let reasonCode: String
  /// Whether policy would auto-send a reviewed draft; no sender is installed here.
  public let autoSend: Bool
  /// Whether a high-risk decision requires typed confirmation.
  public let typedConfirmationRequired: Bool

  init(_ kind: Kind, _ reason: String, autoSend: Bool = false, typed: Bool = false) {
    self.kind = kind
    self.reasonCode = reason
    self.autoSend = autoSend
    self.typedConfirmationRequired = typed
  }
}

/// Pure tier/mode policy. Sandboxes, grants and dispatch guards remain separate enforcement.
public enum ToolPolicy {
  /// Classification includes only trusted current target grants (policy.md §3.7).
  public static func tier(
    _ operation: ToolPolicyOperation, context: ToolPolicyContext
  ) -> Int {
    switch operation {
    case .networkFetch: context.networkGrant == .none ? 3 : 0
    case .networkSend: context.networkGrant == .readWrite ? 3 : 4
    default: operation.tier
    }
  }

  /// Evaluates deterministic tier/mode friction after hard-stop and authority checks.
  ///
  /// Original-source path classes decide right after the kill switch, paused bot and budget,
  /// before origin, plan, grant and matrix friction; a `ci_config` write then carries
  /// `sensitive_path` after the matrix (policy.md §9).
  public static func evaluate(
    _ operation: ToolPolicyOperation, context: ToolPolicyContext
  ) -> ToolPolicyDecision {
    let tier = Self.tier(operation, context: context)
    guard context.permissionMode.isKnown, context.rootOrigin.isKnown,
      context.computerKind.isKnown
    else { return .init(.deny, "policy.unknown_context") }
    if context.killSwitch { return .init(.deny, "paused.kill_switch") }
    if !context.botActive { return .init(.deny, "paused.bot") }
    if !context.budgetAvailable { return .init(.deny, "budget.exhausted") }
    if let denial = sourcePathDenial(operation, classes: context.sourcePathClasses) {
      return denial
    }
    let regime: Regime
    switch context.rootOrigin {
    case .user: regime = .attended
    case .routine, .wake, .watch, .app: regime = .unattended
    case .webhook, .connectorEvent, .intent: regime = .untrusted
    default: return .init(.deny, "origin.invalid_root")
    }
    if tier == 5 && regime != .attended {
      return .init(.deny, "origin.no_t5_unattended")
    }
    if regime == .untrusted {
      if tier == 2 && context.computerKind != .botVm && context.computerKind != .cloud {
        return .init(.deny, "origin.untrusted_exec_host")
      }
      if operation == .unknown { return .init(.deny, "unknown.untrusted") }
    }
    if context.plan && tier > 0 { return .init(.deny, "plan.blocked") }
    if !context.grantsPresent {
      return .init(regime == .attended ? .ask : .deny, "grant.missing")
    }
    let mode: PermissionMode =
      context.permissionMode == .bypass && operation.keepsCard ? .askFirst : context.permissionMode
    let decision = matrix(tier: tier, regime: regime, mode: mode, context: context)
    // §4.5 `sensitive_path` only raises friction: it denies when not attended and turns allow
    // into ask outside Bypass (Ask first included, so a stricter mode never allows more).
    guard !operation.readsSourceOnly, context.sourcePathClasses.contains(.ciConfig),
      decision.kind != .deny
    else { return decision }
    if regime != .attended { return .init(.deny, "flag.sensitive_path") }
    if mode != .bypass && decision.kind == .allow { return .init(.ask, "flag.sensitive_path") }
    return decision
  }

  /// policy.md §3.5.2 effects this low-risk profile cannot serve. No redacted view, `host_exec`
  /// patch card or instruction proposal is installed, so those effects deny rather than
  /// degrade into a raw read or a plain write. Only git tools may change `git_internal` data.
  private static func sourcePathDenial(
    _ operation: ToolPolicyOperation, classes: Set<SourcePathClass>
  ) -> ToolPolicyDecision? {
    if classes.contains(.memoshiState) {
      return .init(.deny, "hard_deny.path_class.memoshi_state")
    }
    if classes.contains(.system) { return .init(.deny, "hard_deny.path_class.system") }
    let readOnly = operation.readsSourceOnly
    if classes.contains(.secret) {
      return .init(.deny, readOnly ? "secret.redaction_unavailable" : "secret.write_unavailable")
    }
    if readOnly { return nil }
    if classes.contains(.hostExec) {
      // A file-tool write would be a typed patch card; every other write is hard-denied.
      let reason =
        operation == .fileWrite ? "host_exec.patch_unavailable" : "hard_deny.path_class.host_exec"
      return .init(.deny, reason)
    }
    if classes.contains(.gitInternal) && operation != .gitLocal {
      return .init(.deny, "hard_deny.path_class.git_internal")
    }
    if classes.contains(.instruction) { return .init(.deny, "instruction.proposal_unavailable") }
    return nil
  }

  private static func matrix(
    tier: Int, regime: Regime, mode: PermissionMode, context: ToolPolicyContext
  ) -> ToolPolicyDecision {
    let bypass = mode == .bypass
    switch tier {
    case 0:
      return .init(.allow, "matrix.allow")
    case 1:
      // Original source data is never the bot home, whatever the host flag says.
      let botHome = context.isBotHome && context.sourcePathClasses.isEmpty
      let allowed = regime == .attended ? mode != .askFirst : botHome || bypass
      return .init(
        allowed ? .allow : .ask, allowed && bypass ? "bypass.allow" : "matrix.local_write")
    case 2:
      let isolated = context.computerKind == .botVm || context.computerKind == .cloud
      let allowed = regime == .attended ? mode != .askFirst : isolated || bypass
      return .init(allowed ? .allow : .ask, allowed && bypass ? "bypass.allow" : "matrix.execute")
    case 3:
      if regime != .attended { return .init(.deny, "rule.none_unattended") }
      return .init(bypass ? .allow : .ask, bypass ? "bypass.allow" : "matrix.reach_out")
    case 4:
      let autoSend = bypass && regime != .untrusted
      return .init(.draft, autoSend ? "bypass.send" : "matrix.draft", autoSend: autoSend)
    default:
      return .init(
        bypass ? .allow : .ask, bypass ? "bypass.allow" : "matrix.critical", typed: !bypass)
    }
  }
}
