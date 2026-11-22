import Foundation
import MemoshiEgress
import MemoshiProtocol
import MemoshiStore

/// Development/qualification composition for the real gateway. Production remains `.none`.
/// Both gateway ports receive this instance; policy or audit failure refuses dispatch.
/// A configured mask is not an account grant.
public final class RuntimeGatewayPolicy: EgressRequestAuthorizer, EgressDecisionSink, Sendable {
  /// Must check current account/injection/host and attendance authority without releasing a value.
  public typealias AccountAuthority =
    @Sendable (
      GatewayCallAuthority, EgressAuthorizationRequest
    ) async throws -> Bool

  private let store: Store
  private let directory: any RuntimeComputerDirectory
  private let accountAuthority: AccountAuthority?

  /// Uses the supplied current Store and computer directory; no authority is synthesized.
  public init(
    store: Store, directory: any RuntimeComputerDirectory,
    accountAuthority: AccountAuthority? = nil
  ) {
    self.store = store
    self.directory = directory
    self.accountAuthority = accountAuthority
  }

  /// Rechecks current tool ownership, policy, computer and account authority before dialing.
  public func authorize(_ request: EgressAuthorizationRequest) async throws -> EgressAuthorization {
    do {
      var current = try await evaluateCurrent(request)
      if current.decision.kind == .allow, !request.secretReferences.isEmpty {
        let accountAllowed = try await accountAuthority?(current.authority, request) ?? false
        // Account checks may wait. Re-resolve computer/grants and read the store afterward.
        let refreshed = try await evaluateCurrent(request)
        guard refreshed.authority.call == current.authority.call else { return .deny }
        current = refreshed
        if current.decision.kind == .allow && !accountAllowed {
          current.decision = .init(.deny, "grant.account_missing")
        }
      }
      let authority = current.authority
      let snapshot = authority.snapshot
      let decision = current.decision
      let metadata: MemoshiProtocol.JSONValue = .object([
        "host": .string(request.host), "port": .string(String(request.port)),
        "method": .string(request.method), "methodVisible": .bool(request.methodVisible),
        "usesTLS": .bool(request.usesTLS), "interceptsTLS": .bool(request.interceptsTLS),
        "secretReferences": .object(request.secretReferences.mapValues { .string($0) }),
      ])
      let payload = PolicyDecidedPayload(
        toolCallId: authority.call.toolCallId, parentToolCallId: authority.call.parentToolCallId,
        tool: authority.call.tool, decision: decision.kind,
        autoSend: decision.autoSend ? true : nil,
        tier: try Tier(ToolPolicy.tier(current.operation, context: current.context)),
        opClass: current.operation.rawValue, ruleId: decision.reasonCode,
        permissionMode: snapshot.policy.permissionMode,
        plan: false, origin: snapshot.task.origin,
        attendance: snapshot.task.regime == .attended ? .attended : .unattended,
        exposure: snapshot.exposure, deviceId: store.deviceID, recheck: true,
        reasonCode: decision.reasonCode, policyVersion: "gateway-1",
        argsHash: try RuntimeAdapter.paramsHash(metadata))
      try await store.recordGatewayPolicyDecision(
        payload, call: authority.call, fence: authority.fence, at: IDGenerator.nowMilliseconds())
      switch decision.kind {
      case .allow: return .allow
      case .ask: return .ask
      default: return .deny  // A draft/auto-send recommendation is not an executable grant.
      }
    } catch is ApprovalError {
      return .deny
    } catch StoreError.leaseFenced {
      return .deny
    }
  }

  private struct Current {
    let authority: GatewayCallAuthority
    let context: ToolPolicyContext
    let operation: ToolPolicyOperation
    var decision: ToolPolicyDecision
  }

  private func evaluateCurrent(_ request: EgressAuthorizationRequest) async throws -> Current {
    let conversation = try ConversationID(request.identity.conversation)
    let bot = try BotID(request.identity.bot)
    // Directory lookup can suspend; read local stop/mode/budget/call state after it finishes.
    let computer = try await directory.computer(conversation: conversation, bot: bot)
    let authority = try await store.gatewayCallSnapshot(
      conversationID: conversation, botID: bot, runtimeTaskKey: request.call,
      at: IDGenerator.nowMilliseconds())
    let snapshot = authority.snapshot
    var networkGrant: ToolPolicyNetworkGrant = .none
    var hardReason: String?
    switch computer {
    case .none:
      hardReason = "grant.computer_missing"
    case .thisMacSandbox(let current):
      if current.id != request.identity.computer {
        hardReason = "grant.computer_changed"
      } else {
        var listed = false
        var write = false
        for rule in current.network.hosts where rule.matches(host: request.host, port: request.port)
        {
          listed = true
          write = write || rule.write
        }
        if listed { networkGrant = write ? .readWrite : .read }
        if request.allowlisted && !listed { hardReason = "grant.network_revoked" }
        let secretBound = current.network.secrets.contains { $0.hosts.contains(request.host) }
        if secretBound && !request.methodVisible
          && !(request.method == "CONNECT" && request.interceptsTLS)
        {
          hardReason = "gateway.reconfigure_required"
        }
        for (name, reference) in request.secretReferences {
          if !current.network.secrets.contains(where: {
            $0.name == name && $0.secretRef == reference && $0.hosts.contains(request.host)
          }) {
            hardReason = "grant.account_missing"
          }
        }
        if !request.secretReferences.isEmpty && !request.usesTLS {
          hardReason = "hard_deny.secret_transport"
        }
      }
    }
    // Opaque CONNECT intentionally has host-level control, not fabricated GET semantics.
    let operation: ToolPolicyOperation =
      request.methodVisible && (request.sendTier ?? 0) > 0 ? .networkSend : .networkFetch
    let context = ToolPolicyContext(
      permissionMode: snapshot.policy.permissionMode, rootOrigin: snapshot.task.origin.rootKind,
      grantsPresent: true, budgetAvailable: snapshot.task.budgetIds.isEmpty,
      botActive: snapshot.policy.active && snapshot.task.cancelRequestedAt == nil,
      killSwitch: snapshot.policy.killSwitch, networkGrant: networkGrant)
    var decision = ToolPolicy.evaluate(operation, context: context)
    if decision.kind != .deny, let hardReason { decision = .init(.deny, hardReason) }
    return Current(authority: authority, context: context, operation: operation, decision: decision)
  }

  /// Commits only scrubbed canonical metadata; a failed commit prevents gateway dispatch.
  public func record(_ decision: EgressDecision) async throws {
    try await store.recordGatewayAudit(
      GatewayAuditFact(
        conversationID: try ConversationID(decision.conversation), botID: try BotID(decision.bot),
        runtimeTaskKey: decision.call, computerID: decision.computer, host: decision.host,
        allowed: decision.allowed, secretReferences: Array(decision.secretReferences.values)),
      at: decision.at)
  }
}
