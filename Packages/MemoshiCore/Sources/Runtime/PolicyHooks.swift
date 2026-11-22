import Chord
import Foundation
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable

/// One policy extension per locally owned Chat. No SDK invocation object crosses an actor hop.
struct PolicyHooks: Sendable {
  static let name: PiCore.JSONString = "memoshi.policy"

  /// The Harness tool policy Pi_Swift requires (E21). Its default, `.conservative`, denies every
  /// tool that declares no effects, which is every Memoshi tool. Memoshi decides in its
  /// mandatory hooks (`beforeTool`, `afterTool` and the dispatch-time recheck wrap), which the
  /// engine runs for every call, nested and Code Mode calls included; `RuntimeAdapter` refuses
  /// to open a Harness without them. Pi runs no hook before it executes a call again (purpose
  /// `.rerun`), so this policy admits a replay-unsafe call's next execution as `beforeTool`
  /// admits its first, under the policy that holds then (D51): Run again is no permission
  /// (D52), and an approval of an earlier execution does not cover this one. A replay-safe
  /// call reruns as the same call. Moving the rest of the hard allow/deny into this policy is a
  /// later adoption step, not part of the pin move.
  var enginePolicy: PiDurable.ToolPolicy {
    PiDurable.ToolPolicy { request, api, context in
      guard request.purpose == .rerun,
        entries[request.call.call.name.displayString]?.replaySafe != true
      else { return .allow }
      guard
        let reason = try await admit(
          request.call, attempt: request.attempt, api: api, context: context)
      else { return .allow }
      return .deny(reason)
    }
  }

  /// The memo naming the approval that execution `attempt` of a call waits on. Pi memos are
  /// written once, so each execution has its own, and an approval admits that one execution.
  static func approvalKey(_ attempt: Int) -> PiCore.JSONString {
    attempt == 1 ? "memoshi.approval" : PiCore.JSONString("memoshi.approval/\(attempt)")
  }

  /// Pinned before `enginePolicy` admits execution `attempt` (> 1) of a replay-unsafe call.
  private static func rerunKey(_ attempt: Int) -> PiCore.JSONString {
    PiCore.JSONString("memoshi.policy.rerun/\(attempt)")
  }

  /// The execution a replay-unsafe call is on: the last rerun `enginePolicy` admitted, else 1.
  nonisolated(nonsending) private static func execution(
    _ api: PiDurable.HookApi, context: Chord.Context
  ) async throws -> Int {
    var attempt = 1
    while try await api.memo(rerunKey(attempt + 1), context: context) != nil { attempt += 1 }
    return attempt
  }

  /// Replay-unsafe tools whose every execution records Memoshi's dispatch before any effect:
  /// host tools here and every extension tool through its wrap (`RuntimeAdapter` refuses a
  /// Harness in which an extension tool is not wrapped).
  var dispatchRecordedToolNames: Set<String> {
    Set(enabledToolNames.filter { entries[$0]?.replaySafe == false })
  }
  let store: Store
  private let credentials: ProviderCredentials
  let chat: ChatSummary
  let fence: ConversationFence
  /// Host definitions this extension registers and executes itself.
  private let definitions: [String: RuntimeToolDefinition]
  /// Every tool's trusted policy: host definitions and tools other extensions register.
  let entries: [String: ToolPolicyEntry]
  /// One filtered, deterministic set for registry installation and model discovery.
  let toolNames: [String]
  /// Tools other extensions register; this extension wraps each one.
  let extensionToolNames: [String]
  /// Every enabled tool, then the subset offered before `tool_search` loads anything.
  let enabledToolNames: [String]
  let modelToolNames: [String]
  /// Set once the runtime closes this Harness: a decision wait the close ends keeps its
  /// approval for the next open.
  let closing: HarnessClosing

  init(
    store: Store, credentials: ProviderCredentials, chat: ChatSummary, fence: ConversationFence,
    tools: [RuntimeToolDefinition], extensionTools: [RuntimeExtensionTool] = [],
    closing: HarnessClosing
  ) throws {
    var definitions: [String: RuntimeToolDefinition] = [:]
    var entries: [String: ToolPolicyEntry] = [:]
    for tool in tools where tool.chatID.map({ $0.rawValue == chat.id.rawValue }) ?? true {
      guard !tool.name.isEmpty, tool.name.utf8.count <= 64, definitions[tool.name] == nil,
        tool.operation.tier < 4, case .object = tool.parameters,
        (tool.operation == .fileRead || tool.operation == .fileWrite)
          == (tool.sourceTargets != nil)
      else { throw RuntimeToolError.invalidDefinition }
      definitions[tool.name] = tool
      entries[tool.name] = try ToolPolicyEntry(tool)
    }
    var deferred = Set<String>()
    for tool in extensionTools {
      // A host tool can never shadow, or stand in for, another extension's reviewed tool.
      guard !tool.name.isEmpty, tool.name.utf8.count <= 64, entries[tool.name] == nil,
        tool.policy.operation.tier < 4, case .object = tool.parameters
      else { throw RuntimeToolError.invalidDefinition }
      entries[tool.name] = try ToolPolicyEntry(tool)
      if tool.deferred { deferred.insert(tool.name) }
    }
    self.store = store
    self.credentials = credentials
    self.chat = chat
    self.fence = fence
    self.closing = closing
    self.definitions = definitions
    self.entries = entries
    self.toolNames = definitions.keys.sorted()
    self.extensionToolNames = extensionTools.map(\.name)
    self.enabledToolNames = toolNames + extensionToolNames
    self.modelToolNames = enabledToolNames.filter { !deferred.contains($0) }
  }

  func extensionDefinition() throws -> PiDurable.Extension {
    let registrations = try toolNames.map { name -> PiDurable.ToolRegistration in
      guard let definition = definitions[name], let entry = entries[name] else {
        throw RuntimeToolError.invalidDefinition
      }
      return PiDurable.ToolRegistration(
        name: PiCore.JSONString(name), description: PiCore.JSONString(definition.description),
        parameters: try ToolJSON.sdk(definition.parameters),
        replay: definition.replaySafe ? .safe : .unsafe,
        structuredOutputSchema: try definition.resultSchema.map(ToolJSON.sdk),
        callers: [.model, .tools],
        execute: { arguments, api, context in
          var dispatch: PolicyToolIdentity?
          do {
            let values = try ToolJSON.application(arguments)
            let identity = try await recheck(
              entry, arguments: values, api: api, context: context)
            try context.throwIfAborted()
            try api.signal.throwIfAborted()
            if !definition.replaySafe {
              try await store.beginUnsafeToolDispatch(
                identity, fence: fence, at: IDGenerator.nowMilliseconds())
              dispatch = identity
            }
            let result = try await definition.execute(
              values, RuntimeToolInvocation(api: api, context: context, fence: fence, policy: self))
            try api.signal.throwIfAborted()
            guard result.data == nil || definition.resultSchema != nil else {
              throw RuntimeToolError.invalidArguments
            }
            let encoded = try result.data.map(ToolJSON.sdk)
            if let dispatch {
              try await store.finishUnsafeToolDispatch(
                dispatch,
                outcome: result.effectOutcome == .unknown
                  ? .unknown : .returned(ok: !result.isError),
                fence: fence, at: IDGenerator.nowMilliseconds())
            }
            return PiDurable.ToolExecutionResult(
              output: [.text(.init(text: PiCore.JSONString(result.text)))],
              structuredOutput: encoded, isError: result.isError)
          } catch {
            if let dispatch {
              try? await store.finishUnsafeToolDispatch(
                dispatch,
                outcome: error as? RuntimeToolExecutionError == .notApplied
                  ? .returned(ok: false) : .unknown,
                fence: fence, at: IDGenerator.nowMilliseconds())
            }
            try api.signal.throwIfAborted()
            return PiDurable.ToolExecutionResult(
              output: [
                .text(.init(text: "The tool was not authorized or could not complete safely."))
              ], isError: true)
          }
        })
    }
    return PiDurable.Extension(
      name: Self.name, tools: registrations,
      hooks: [
        .init(
          task: "pi.tool",
          handlers: .init(
            beforeTool: { call, api, context in try await before(call, api: api, context: context)
            },
            afterTool: { call, result, api, context in
              await after(call, result: result, api: api, context: context)
            })),
        .init(
          task: "pi.generation",
          handlers: .init(
            beforeRequest: { messages, api, context in
              try await waitForRecovery(signal: api.signal, context: context)
              // First: it finds where each stopped reply goes by Pi's own messages.
              let stopped = try await stoppedReplies(messages, api: api, context: context)
              let truthful = try await Self.truthfulInterruptions(
                stopped ?? messages, api: api, context: context)
              return try await resumeNotes(
                truthful ?? stopped ?? messages, api: api, context: context)
                ?? truthful ?? stopped
            },
            afterTools: { _, entries, api, context in
              try await observeCommittedResults(
                entries, api: api, context: context, fence: fence)
              try await waitForRecovery(signal: api.signal, context: context)
            })),
      ], wraps: extensionWraps())
  }

  /// A pending memo must still name a live Pi tool task. This is not a deliberate-kill proof.
  nonisolated(nonsending) func reconcile(_ storage: PiDurable.SqliteStorage) async throws {
    while try await store.expireApprovals(fence: fence, at: IDGenerator.nowMilliseconds()).count
      == 256
    {}
    for binding in try await store.pendingApprovalBindings(fence.conversationID) {
      let record: PiDurable.TaskRecord?
      if let key = Int(binding.runtimeTaskKey), key > 0 {
        record = try await storage.task(TaskId(key))
      } else {
        record = nil
      }
      if record?.status.isLive != true
        || record?.memos?.contains(where: { key, value in
          (key == Self.approvalKey(1) || key.displayString.hasPrefix("memoshi.approval/"))
            && value.stringValue == binding.approval.id.rawValue
        }) != true
      {
        try await store.cancelApproval(
          binding.approval.id, reason: .callAborted, fence: fence, at: IDGenerator.nowMilliseconds()
        )
      }
    }
  }

  nonisolated(nonsending) private func before(
    _ call: PiDurable.ToolHookCall, api: PiDurable.HookApi, context: Chord.Context
  ) async throws -> PiDurable.BeforeToolResult? {
    try await admit(call, attempt: 1, api: api, context: context).map { .init(block: $0) }
  }

  /// Memoshi's decision before execution `attempt` of a call: its first (`beforeTool`) or a
  /// replay-unsafe call's next (`enginePolicy`). Nil admits it; otherwise why it is blocked.
  /// An `ask` waits for an approval bound to this execution (`approvalKey`).
  nonisolated(nonsending) private func admit(
    _ call: PiDurable.ToolHookCall, attempt: Int, api: PiDurable.HookApi, context: Chord.Context
  ) async throws -> PiCore.JSONString? {
    var pending: ApprovalID?
    do {
      try await waitForRecovery(signal: api.signal, context: context)
      // The pinned pi.tool caller passes its TaskRuntime through HookApi's read-only signature.
      guard let runtime = api as? PiDurable.TaskRuntime else {
        throw RuntimeToolError.notAuthorized
      }
      if attempt > 1 {
        // Before anything else: this execution's recheck reads this execution's approval.
        _ = try await runtime.memo(Self.rerunKey(attempt), value: true, context: context)
      }
      guard let entry = entries[call.call.name.displayString] else {
        throw RuntimeToolError.notAuthorized
      }
      let arguments = try ToolJSON.application(.object(call.call.arguments))
      let taskID = try await RuntimeTaskScope.taskID(
        api, store: store, chat: chat, fence: fence, context: context, toolName: entry.name)
      let (snapshot, decision, source) = try await evaluate(
        entry, arguments: arguments, taskID: taskID)
      let hash = try RuntimeAdapter.paramsHash(arguments)
      let parentValue: PiCore.JSONValue =
        call.parent.map { .string($0.callId.displayString) } ?? .null
      guard
        try await runtime.memo("memoshi.policy.parent", value: parentValue, context: context)
          == parentValue
      else {
        throw RuntimeToolError.notAuthorized
      }
      // Pinned like the parent: a rerun hook and the dispatch recheck report the same channel.
      let via = try await callVia(entry, parent: call.parent, api: api, context: context)
      let viaValue: PiCore.JSONValue = via.map { .string($0.rawValue) } ?? .null
      guard
        try await runtime.memo("memoshi.policy.via", value: viaValue, context: context)
          == viaValue
      else {
        throw RuntimeToolError.notAuthorized
      }
      try await record(
        decision, entry: entry, snapshot: snapshot,
        callID: call.call.id.displayString, parentID: call.parent?.callId.displayString,
        via: via, argsHash: hash, recheck: false, taskKey: api.taskId.rawValue)
      switch decision.kind {
      case .allow:
        let expected = try authorization(
          entry, snapshot: snapshot, argsHash: hash, callID: call.call.id.displayString,
          sourceHash: source?.contentHash)
        guard
          try await runtime.memo("memoshi.policy.authorization", value: expected, context: context)
            == expected
        else {
          throw RuntimeToolError.notAuthorized
        }
        return nil
      case .ask:
        let candidate = try IDGenerator.shared.objectID(ApprovalIDKind.self)
        let memo = try await runtime.memo(
          Self.approvalKey(attempt), value: .string(candidate.rawValue), context: context)
        guard let raw = memo.stringValue else { throw RuntimeToolError.notAuthorized }
        let id = try ApprovalID(raw)
        pending = id
        let now = IDGenerator.nowMilliseconds()
        let attended = snapshot.task.regime == .attended
        let preview = try await credentials.scrubPolicyMetadata(arguments)
        let approval = Approval(
          id: id, botId: chat.botId, conversationId: fence.conversationID, taskId: snapshot.task.id,
          toolCallId: call.call.id.displayString,
          parentToolCallId: call.parent?.callId.displayString,
          tool: entry.name, tier: try Tier(entry.operation.tier),
          permissionMode: snapshot.policy.permissionMode,
          origin: snapshot.task.origin, attendance: attended ? .attended : .unattended,
          exposure: snapshot.exposure, computerKind: .macSandbox, deviceId: store.deviceID,
          targets: source?.targets ?? targets(entry, arguments: preview),
          argsHash: hash, argsPreview: preview,
          ruleId: decision.reasonCode, reasonCode: decision.reasonCode,
          policyVersion: entry.version,
          status: .pending, expiresAt: now + (attended ? 1_800_000 : 600_000), createdAt: now)
        let card = Card(
          id: try IDGenerator.shared.objectID(CardIDKind.self), kind: .approval,
          conversationId: fence.conversationID,
          messageId: snapshot.turn.assistantMessageId, botId: chat.botId, taskId: snapshot.task.id,
          subject: .init(kind: "approval", id: id.rawValue), status: .pending, inbox: true,
          needsYou: true,
          title: try Title("Allow " + entry.name + "?"),
          payload: ["approvalId": .string(id.rawValue), "actions": ["allow_once", "deny"]],
          expiresAt: approval.expiresAt, createdAt: now)
        _ = try await store.ensureApproval(
          .init(
            approval: approval, card: card, runtimeTaskKey: String(api.taskId.rawValue),
            operation: entry.operation.rawValue, sourceGrants: source?.references ?? []),
          fence: fence, at: now)
        let signal = api.signal
        let status = try await PiAI.withAbortSignal(signal) { try await wait(id) }
        if let refusal = Self.refusal(status) { return refusal }
        let expected = try authorization(
          entry, snapshot: snapshot, argsHash: hash, callID: call.call.id.displayString,
          sourceHash: source?.contentHash)
        guard
          try await runtime.memo("memoshi.policy.authorization", value: expected, context: context)
            == expected
        else {
          throw RuntimeToolError.notAuthorized
        }
        return nil
      default:
        return "Policy denied this call. Nothing was done."
      }
    } catch {
      // A close is not the user's answer: Pi writes this task back as pending, and the next
      // open reruns this hook, which finds the same approval by its memo (policy.md §10.1).
      // That open cancels it instead when its task no longer names it (`reconcile`).
      if let pending, !closing.began {
        try? await store.cancelApproval(
          pending, reason: .callAborted, fence: fence, at: IDGenerator.nowMilliseconds())
      }
      try api.signal.throwIfAborted()
      return "Policy could not safely authorize this call. Nothing was done."
    }
  }

  /// What the model reads for an approval that ended without Allow: each outcome its own
  /// result (D139, policy.md §10.1), so it does not retry after a denial and can offer to ask
  /// again after an expiry. Nil for an allowed approval.
  static func refusal(_ status: ApprovalStatus) -> PiCore.JSONString? {
    switch status {
    case .allowed: nil
    case .denied: "The user denied the call; nothing was done."
    case .expired: "The user did not answer in time; nothing was done."
    case .canceled: "The approval was canceled before an answer; nothing was done."
    case .pending, .unknown: "Policy could not safely authorize this call. Nothing was done."
    }
  }

  nonisolated(nonsending) private func evaluate(
    _ entry: ToolPolicyEntry, arguments: MemoshiProtocol.JSONValue, taskID: MemoshiProtocol.TaskID
  ) async throws -> (PolicyCallSnapshot, ToolPolicyDecision, RuntimeSourceAuthorization?) {
    let granted = try await entry.authorize(arguments)
    var source: RuntimeSourceAuthorization?
    var sourceDenial: ToolPolicyDecision?
    if granted, let resolve = entry.sourceTargets {
      do {
        source = try await RuntimeSourceAuthorization.resolve(
          resolve(arguments), operation: entry.operation, store: store, botID: chat.botId,
          at: IDGenerator.nowMilliseconds())
      } catch is FolderGrantError {
        sourceDenial = .init(.deny, "grant.missing")
      } catch is SourceFolderAuthorityError {
        sourceDenial = .init(.deny, "source.root_changed")
      } catch is SourcePathPolicyError {
        sourceDenial = .init(.deny, "hard_deny.path")
      }
    }
    let snapshot = try await store.policyCallSnapshot(
      chatID: chat.id, taskID: taskID, fence: fence, at: IDGenerator.nowMilliseconds())
    let context = ToolPolicyContext(
      permissionMode: snapshot.policy.permissionMode, rootOrigin: snapshot.task.origin.rootKind,
      grantsPresent: granted && sourceDenial == nil,
      budgetAvailable: snapshot.task.budgetIds.isEmpty,
      botActive: snapshot.policy.active && snapshot.task.cancelRequestedAt == nil
        && [.queued, .running, .waiting].contains(snapshot.task.status),
      killSwitch: snapshot.policy.killSwitch,
      sourcePathClasses: source?.classes ?? [])
    let decision =
      !granted
      ? ToolPolicyDecision(.deny, "grant.missing")
      : sourceDenial ?? ToolPolicy.evaluate(entry.operation, context: context)
    return (snapshot, decision, source)
  }

  nonisolated(nonsending) func recheck(
    _ entry: ToolPolicyEntry, arguments: MemoshiProtocol.JSONValue,
    api: PiDurable.ToolExecutionApi, context: Chord.Context
  ) async throws -> PolicyToolIdentity {
    let taskID = try await RuntimeTaskScope.taskID(
      api, store: store, chat: chat, fence: fence, context: context, toolName: entry.name)
    let (snapshot, decision, source) = try await evaluate(
      entry, arguments: arguments, taskID: taskID)
    let hash = try RuntimeAdapter.paramsHash(arguments)
    let parent = try await api.memo("memoshi.policy.parent", context: context)?.stringValue
    let via = try await api.memo("memoshi.policy.via", context: context)?.stringValue.map {
      ToolCallVia(rawValue: $0)
    }
    if decision.kind == .deny {
      try await record(
        decision, entry: entry, snapshot: snapshot,
        callID: api.callId.displayString, parentID: parent, via: via, argsHash: hash,
        recheck: true, taskKey: api.taskId.rawValue)
      throw RuntimeToolError.notAuthorized
    }
    let expected = try authorization(
      entry, snapshot: snapshot, argsHash: hash, callID: api.callId.displayString,
      sourceHash: source?.contentHash)
    guard try await api.memo("memoshi.policy.authorization", context: context) == expected else {
      try await record(
        .init(.deny, "policy.missing_authorization"), entry: entry, snapshot: snapshot,
        callID: api.callId.displayString, parentID: parent, via: via, argsHash: hash,
        recheck: true, taskKey: api.taskId.rawValue)
      throw RuntimeToolError.notAuthorized
    }
    var effective = decision
    if decision.kind == .ask {
      // Only this execution's approval admits it; a replay-safe rerun is the same call.
      let attempt = entry.replaySafe ? 1 : try await Self.execution(api, context: context)
      guard
        let raw = try await api.memo(Self.approvalKey(attempt), context: context)?.stringValue,
        let binding = try await store.approvalBinding(ApprovalID(raw)).value,
        binding.approval.status == .allowed, binding.approval.argsHash == hash,
        binding.runtimeTaskKey == String(api.taskId.rawValue),
        binding.operation == entry.operation.rawValue,
        binding.approval.policyVersion == entry.version,
        binding.approval.toolCallId == api.callId.displayString,
        binding.sourceGrants == (source?.references ?? [])
      else {
        try await record(
          .init(.deny, "policy.invalid_approval"), entry: entry, snapshot: snapshot,
          callID: api.callId.displayString, parentID: parent, via: via, argsHash: hash,
          recheck: true, taskKey: api.taskId.rawValue)
        throw RuntimeToolError.notAuthorized
      }
      effective = .init(.allow, "approval.allowed")
    }
    try await record(
      effective, entry: entry, snapshot: snapshot,
      callID: api.callId.displayString, parentID: parent, via: via, argsHash: hash,
      recheck: true, taskKey: api.taskId.rawValue)
    guard effective.kind == .allow else { throw RuntimeToolError.notAuthorized }
    return PolicyToolIdentity(
      runtimeTaskKey: String(api.taskId.rawValue), taskId: snapshot.task.id,
      toolCallId: api.callId.displayString, parentToolCallId: parent, tool: entry.name)
  }

  nonisolated(nonsending) private func after(
    _ call: PiDurable.ToolHookCall, result: PiDurable.ToolExecutionResult,
    api: PiDurable.HookApi, context: Chord.Context
  ) async -> PiDurable.ToolExecutionResult {
    var result = result
    var hostRedactions: Int64 = 0
    if case .object(var details) = result.details,
      let marker = details.removeValue(forKey: RuntimeMCPHostRedaction.detailsKey)
    {
      result.details = details.isEmpty ? nil : .object(details)
      if case .mcp? = entries[call.call.name.displayString]?.source {
        guard
          marker
            == .object([
              "count": .number(1), "kinds": .array([.string("mcp_host_secret")]),
            ])
        else { return ToolOutputScrubber.withheld }
        hostRedactions = 1
      }
    }
    let scrubbed = await credentials.scrubToolOutput(result)
    let redactionCount = scrubbed.count + hostRedactions
    let redactionKinds =
      hostRedactions == 0 ? scrubbed.kinds : Set(scrubbed.kinds + ["mcp_host_secret"]).sorted()
    do {
      guard let entry = entries[call.call.name.displayString] else {
        return ToolOutputScrubber.withheld
      }
      let taskID = try await RuntimeTaskScope.taskID(
        api, store: store, chat: chat, fence: fence, context: context, toolName: entry.name)
      let snapshot = try await store.policyCallSnapshot(
        chatID: chat.id, taskID: taskID, fence: fence, at: IDGenerator.nowMilliseconds())
      try await store.preparePolicyToolResult(
        call: PolicyToolIdentity(
          runtimeTaskKey: String(api.taskId.rawValue), taskId: snapshot.task.id,
          toolCallId: call.call.id.displayString,
          parentToolCallId: call.parent?.callId.displayString, tool: entry.name),
        redaction: redactionCount == 0
          ? nil
          : .init(
            toolCallId: call.call.id.displayString, count: redactionCount, kinds: redactionKinds),
        exposure: entry.outputExposure, fence: fence, at: IDGenerator.nowMilliseconds())
      return scrubbed.result
    } catch {
      // Pi catches a throwing afterTool and keeps its prior result: return withheld, never throw.
      return ToolOutputScrubber.withheld
    }
  }

  private func authorization(
    _ entry: ToolPolicyEntry, snapshot: PolicyCallSnapshot, argsHash: String,
    callID: String, sourceHash: String?
  ) throws -> PiCore.JSONValue {
    [
      "tool": .string(entry.name), "argsHash": .string(argsHash), "callId": .string(callID),
      "taskId": .string(snapshot.task.id.rawValue),
      "policyVersion": .string(entry.version),
      "sourceHash": sourceHash.map(PiCore.JSONValue.string) ?? .null,
    ]
  }

  private func targets(_ entry: ToolPolicyEntry, arguments: MemoshiProtocol.JSONValue)
    -> [String]
  {
    guard case .object(let schema) = entry.parameters,
      case .object(let properties) = schema["properties"],
      case .object(let values) = arguments
    else { return [] }
    var targets: [String] = []
    for key in properties.keys.sorted() {
      guard case .object(let property) = properties[key], case .string = property["x-memoshi-role"],
        let value = values[key]
      else { continue }
      switch value {
      case .string(let value): targets.append(value)
      case .array(let values):
        for value in values { if case .string(let value) = value { targets.append(value) } }
      default: break
      }
    }
    return targets
  }

  nonisolated(nonsending) private func record(
    _ decision: ToolPolicyDecision, entry: ToolPolicyEntry, snapshot: PolicyCallSnapshot,
    callID: String, parentID: String?, via: ToolCallVia?, argsHash: String, recheck: Bool,
    taskKey: Int
  ) async throws {
    let payload = PolicyDecidedPayload(
      toolCallId: callID, parentToolCallId: parentID, via: via,
      tool: entry.name, decision: decision.kind, autoSend: decision.autoSend ? true : nil,
      tier: try Tier(entry.operation.tier), opClass: entry.operation.rawValue,
      ruleId: decision.reasonCode,
      permissionMode: snapshot.policy.permissionMode, plan: false, origin: snapshot.task.origin,
      attendance: snapshot.task.regime == .attended ? .attended : .unattended,
      exposure: snapshot.exposure,
      deviceId: store.deviceID, recheck: recheck ? true : nil, reasonCode: decision.reasonCode,
      policyVersion: entry.version, argsHash: argsHash)
    try await store.recordPolicyToolDecision(
      payload,
      call: PolicyToolIdentity(
        runtimeTaskKey: String(taskKey), taskId: snapshot.task.id, toolCallId: callID,
        parentToolCallId: parentID, tool: entry.name),
      fence: fence, at: IDGenerator.nowMilliseconds())
  }

  private func wait(_ id: ApprovalID) async throws -> ApprovalStatus {
    let stream = try store.subscribeEvents(capacity: 256)
    return try await withThrowingTaskGroup(of: ApprovalStatus.self) { group in
      defer { group.cancelAll() }
      group.addTask {
        var stream = stream
        while true {
          do {
            for try await event in stream {
              guard
                event.type.hasPrefix("approval.") || event.type == "system.settings_changed"
                  || event.type == "task.finished"
              else { continue }
              let finished = event.type == "task.finished" ? event.scope.taskId : nil
              if let status = try await settled(id, finished: finished) { return status }
            }
            throw RuntimeToolError.unavailable
          } catch EventBusError.overflow {
            // The bus dropped this subscriber: nothing was decided and nothing was aborted.
            // Observe again first, then re-read the durable state the gap may have changed.
            stream = try store.subscribeEvents(capacity: 256)
            if let status = try await settled(id, finished: nil) { return status }
          }
        }
      }
      guard let initial = try await store.approvalBinding(id).value else {
        throw ApprovalError.notFound
      }
      if initial.approval.status != .pending { return initial.approval.status }
      group.addTask {
        while true {
          guard let binding = try await store.approvalBinding(id).value else {
            throw ApprovalError.notFound
          }
          if binding.approval.status != .pending { return binding.approval.status }
          let remaining = binding.approval.expiresAt - IDGenerator.nowMilliseconds()
          if remaining > 0 {
            try await Task.sleep(for: .milliseconds(remaining))
          } else {
            _ = try await store.expireApprovals(fence: fence, at: IDGenerator.nowMilliseconds())
          }
        }
      }
      guard let status = try await group.next() else { throw RuntimeToolError.unavailable }
      return status
    }
  }

  /// The approval's status once it is no longer pending. A pending approval is canceled, and
  /// that status returned, when its bot is stopped or `finished` is its own task.
  private func settled(_ id: ApprovalID, finished: MemoshiProtocol.TaskID?) async throws
    -> ApprovalStatus?
  {
    guard let binding = try await store.approvalBinding(id).value else {
      throw ApprovalError.notFound
    }
    if binding.approval.status != .pending { return binding.approval.status }
    let policy = try await store.botPolicy(chat.botId)
    guard
      !policy.active || policy.killSwitch
        || (finished != nil && finished == binding.approval.taskId)
    else { return nil }
    try await store.cancelApproval(
      id, reason: policy.killSwitch ? .killSwitch : .taskCanceled, fence: fence,
      at: IDGenerator.nowMilliseconds())
    guard let ended = try await store.approvalBinding(id).value else {
      throw ApprovalError.notFound
    }
    return ended.approval.status
  }
}
