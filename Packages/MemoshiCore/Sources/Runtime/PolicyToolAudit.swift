import Foundation
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable
import Synchronization

enum CommittedToolSource: Hashable, Sendable {
  case task(Int)
  case entry(Int)

  var id: Int {
    switch self {
    case .task(let id), .entry(let id): id
    }
  }
}

/// Only content-free outcomes cross the synchronous commit listener. Task-scoped nested result
/// documents retire with their parent, so capture their final metadata while the commit has it.
final class CommittedToolOutcomes: Sendable {
  private struct Pending {
    let sequence: PiDurable.Seq
    let completion: ToolCompletedPayload?
  }
  private let values = Mutex<[CommittedToolSource: Pending]>([:])

  func capture(_ publication: PiDurable.CommitPublication) {
    var terminal: [Int: PiDurable.TaskRecord] = [:]
    for change in publication.changes {
      if case .task(let task) = change, task.kind == "pi.tool", task.status == .terminal {
        terminal[task.id.rawValue] = task
      }
    }
    var unstarted: [Int] = []
    for change in publication.changes {
      if case .entry(let entry) = change,
        entry.model?.first?.toolResultMessage != nil,
        entry.byTaskId.flatMap({ terminal[$0.rawValue] }) == nil
      {
        unstarted.append(entry.id.rawValue)
      }
    }
    guard !terminal.isEmpty || !unstarted.isEmpty else { return }
    var completions: [Int: ToolCompletedPayload] = [:]
    do {
      for change in publication.changes {
        switch change {
        case .entry(let entry):
          guard let id = entry.byTaskId?.rawValue, terminal[id] != nil,
            entry.model?.first?.toolResultMessage != nil
          else { continue }
          completions[id] = try ToolOutcomeMetadata.model(entry)
        case .document(.document(let record, _, _, let value?, _))
        where record.kind == "pi.tool.nested-call":
          let state = try PiCore.JSONValue.object(value).decode(PiDurable.NestedCallState.self)
          guard let result = state.result, let task = terminal[result.taskId.rawValue] else {
            continue
          }
          let input = try task.input?.decode(PiDurable.ToolTaskInput.self)
          guard let call = input?.nestedCall else { throw RuntimeError.projectionFailed }
          completions[task.id.rawValue] = try ToolOutcomeMetadata.nested(
            result, call: call, parent: input?.nestedParentCallId)
        default:
          break
        }
      }
    } catch {
      // A missing capture is observable and fails reconciliation closed; never infer success.
      completions.removeAll()
    }
    values.withLock { values in
      for id in terminal.keys {
        values[.task(id)] = Pending(sequence: publication.seq, completion: completions[id])
      }
      for id in unstarted {
        values[.entry(id)] = Pending(sequence: publication.seq, completion: nil)
      }
    }
  }

  func pending() -> [CommittedToolSource] {
    values.withLock { values in
      values.sorted {
        $0.value.sequence == $1.value.sequence
          ? $0.key.id < $1.key.id : $0.value.sequence < $1.value.sequence
      }.map(\.key)
    }
  }

  func completion(_ id: Int) -> ToolCompletedPayload? {
    values.withLock { $0[.task(id)]?.completion }
  }

  func remove(_ source: CommittedToolSource) {
    values.withLock { _ = $0.removeValue(forKey: source) }
  }
}

enum ToolOutcomeMetadata {
  static func model(_ entry: PiDurable.EntryRecord) throws -> ToolCompletedPayload {
    guard let result = entry.model?.first?.toolResultMessage else {
      throw RuntimeError.projectionFailed
    }
    let diagnostics = try entry.data?["diagnostics"]?.decode([PiDurable.ToolDiagnostic].self) ?? []
    return ToolCompletedPayload(
      toolCallId: result.toolCallId.displayString, tool: result.toolName.displayString,
      ok: !result.isError, errorCode: errorCode(result.isError, diagnostics: diagnostics),
      durationMs: Int64(result.durationMs ?? 0),
      outputBytes: Int64(
        result.content.reduce(0) { $0 + ($1.textContent?.text.displayString.utf8.count ?? 0) }),
      redactions: 0)
  }

  static func nested(
    _ result: PiDurable.NestedToolExecutionResult, call: PiDurable.NestedToolCall,
    parent: PiCore.JSONString?
  ) throws -> ToolCompletedPayload {
    let bytes: Int
    if case .string(let text) = result.structuredOutput {
      bytes = text.utf8.count
    } else if case .stringUTF16(let text) = result.structuredOutput {
      guard let native = text.nativeString else { throw RuntimeError.projectionFailed }
      bytes = native.utf8.count
    } else if let data = result.structuredOutput {
      bytes = try ToolJSON.application(data).canonicalText.utf8.count
    } else {
      bytes = 0
    }
    let duration = result.durationMs ?? 0
    guard duration.isFinite, duration >= 0, let milliseconds = Int64(exactly: duration.rounded())
    else {
      throw RuntimeError.projectionFailed
    }
    return ToolCompletedPayload(
      toolCallId: call.id.displayString, parentToolCallId: parent?.displayString,
      tool: call.name.displayString, ok: !result.isError,
      errorCode: errorCode(result.isError, diagnostics: result.diagnostics),
      durationMs: milliseconds, outputBytes: Int64(bytes), redactions: 0)
  }

  private static func errorCode(_ isError: Bool, diagnostics: [PiDurable.ToolDiagnostic]) -> String?
  {
    guard isError else { return nil }
    for diagnostic in diagnostics where diagnostic.severity == .error {
      switch diagnostic.code?.displayString {
      case "tool_unavailable": return "tool_unavailable"
      case "invalid_arguments": return "invalid_arguments"
      case "blocked": return "policy_denied"
      case "aborted": return "aborted"
      case "abandoned", "interrupted": return "interrupted"
      // Pi_Swift E20's settled interrupted steps (`interrupted_skipped`, …): still interrupted.
      case let code? where code.hasPrefix("interrupted_"): return "interrupted"
      case "invalid_structured_output": return "invalid_structured_output"
      default: continue
      }
    }
    return "tool_failed"
  }
}

extension RuntimeAdapter {
  /// Drain immutable receipts before settling an application turn, including overflow and Stop.
  func drainToolOutcomes(_ thread: RuntimeThread) async throws {
    for source in thread.toolOutcomes.pending() {
      switch source {
      case .task(let id):
        guard let task = try await thread.storage.task(TaskId(id)) else {
          throw RuntimeError.projectionFailed
        }
        try await projectToolOutcome(task, thread: thread)
      case .entry(let id):
        guard let entry = try await thread.storage.entry(EntryId(id))?.entry
        else {
          throw RuntimeError.projectionFailed
        }
        try await projectToolEntry(entry, thread: thread)
      }
    }
  }

  /// Bounded startup scan covers committed model receipts; an unavailable nested result is not
  /// reconstructed from a parent's success. Held crash/kill recovery is not qualified here.
  func reconcileToolOutcomes(_ thread: RuntimeThread) async throws {
    guard try await thread.storage.conversation(.root) != nil else { return }
    var cursor: PiDurable.Cursor?
    repeat {
      let page = try await thread.storage.scanTasks(
        .init(kind: "pi.tool", status: .terminal), limit: 128, cursor: cursor
      )
      for task in page.items { try await projectToolOutcome(task, thread: thread) }
      cursor = page.next
    } while cursor != nil
    let conversations = [.root] + (try await childConversations(thread))
    for conversation in conversations {
      cursor = nil
      repeat {
        let page = try await thread.storage.scanEntries(
          .init(conversationId: conversation, order: .ascending), limit: 128, cursor: cursor)
        for entry in page.items where entry.model?.first?.toolResultMessage != nil {
          try await projectToolEntry(entry, thread: thread)
        }
        cursor = page.next
      } while cursor != nil
    }
    try await drainToolOutcomes(thread)
  }

  /// The policy identity and arguments of one pi.tool task, from Pi's durable task and
  /// assistant entry.
  func policyToolCall(
    _ task: PiDurable.TaskRecord, input: PiDurable.ToolTaskInput, thread: RuntimeThread
  ) async throws -> (identity: PolicyToolIdentity, arguments: PiCore.JSONValue) {
    let observed = try await observedToolCall(task, input: input, thread: thread)
    let applicationTask = try await policyTaskID(
      conversation: task.conversationId, assistant: observed.assistant, thread: thread)
    let identity = PolicyToolIdentity(
      runtimeTaskKey: String(task.id.rawValue), taskId: applicationTask,
      toolCallId: observed.id.displayString,
      parentToolCallId: input.nestedParentCallId?.displayString,
      tool: observed.name.displayString)
    return (identity, observed.arguments)
  }

  func projectToolOutcome(_ task: PiDurable.TaskRecord, thread: RuntimeThread) async throws {
    // Capture before the first actor suspension: another observer may commit and discard it.
    let captured = thread.toolOutcomes.completion(task.id.rawValue)
    guard task.kind == "pi.tool", task.status == .terminal,
      let input = try task.input?.decode(PiDurable.ToolTaskInput.self)
    else { throw RuntimeError.projectionFailed }
    let (identity, arguments) = try await policyToolCall(task, input: input, thread: thread)
    let fence = thread.ownership.fence
    if try await store.policyToolCompletion(
      call: identity, fence: fence, at: IDGenerator.nowMilliseconds()) != nil
    {
      thread.toolOutcomes.remove(.task(task.id.rawValue))
      return
    }
    var completion: ToolCompletedPayload
    if let captured {
      completion = captured
    } else if input.modelCall != nil, let value = task.state.outcome?.result?["entryId"],
      let entry = try await thread.storage.entry(
        conversationId: task.conversationId, EntryId(try value.decode(Int.self)))?.entry
    {
      completion = try ToolOutcomeMetadata.model(entry)
    } else if let parent = input.nestedParent, let key = input.nestedKey,
      let state = try await nestedToolResult(thread, parent: parent, key: key),
      let result = state.result, result.taskId == task.id, let call = input.nestedCall
    {
      completion = try ToolOutcomeMetadata.nested(
        result, call: call, parent: input.nestedParentCallId)
    } else {
      let code: String
      switch task.state.outcome?.status {
      case .faulted: code = "task_faulted"
      case .orphaned: code = "task_orphaned"
      case .aborted: code = "aborted"
      default: throw RuntimeError.projectionFailed
      }
      completion = ToolCompletedPayload(
        toolCallId: identity.toolCallId, parentToolCallId: identity.parentToolCallId,
        tool: identity.tool, ok: false, errorCode: code, durationMs: 0, outputBytes: 0,
        redactions: 0)
    }
    completion.parentToolCallId = identity.parentToolCallId
    guard completion.toolCallId == identity.toolCallId, completion.tool == identity.tool else {
      throw RuntimeError.projectionFailed
    }
    try await commitToolOutcome(
      completion, identity: identity, arguments: arguments, input: input,
      thread: thread)
    thread.toolOutcomes.remove(.task(task.id.rawValue))
  }

  /// Pi can reject an unoffered call in pi.generation without ever creating a pi.tool task.
  /// The actual immutable result-entry ID is its receipt key, not an invented tool-task ID.
  func projectToolEntry(_ entry: PiDurable.EntryRecord, thread: RuntimeThread) async throws {
    guard let creator = entry.byTaskId,
      let task = try await thread.storage.task(creator)
    else { throw RuntimeError.projectionFailed }
    if task.kind == "pi.tool" {
      if task.status == .terminal {
        try await projectToolOutcome(task, thread: thread)
        thread.toolOutcomes.remove(.entry(entry.id.rawValue))
      }
      return
    }
    guard task.kind == "pi.generation", task.conversationId == entry.conversationId else {
      throw RuntimeError.projectionFailed
    }
    let applicationTask = try await policyTaskID(
      conversation: entry.conversationId, assistant: entry.id, thread: thread)
    let completion = try ToolOutcomeMetadata.model(entry)
    guard !completion.ok else { throw RuntimeError.projectionFailed }
    let identity = PolicyToolIdentity(
      runtimeTaskKey: "entry:" + String(entry.id.rawValue), taskId: applicationTask,
      toolCallId: completion.toolCallId, tool: completion.tool)
    if try await store.policyToolCompletion(
      call: identity, fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds()) != nil
    {
      thread.toolOutcomes.remove(.entry(entry.id.rawValue))
      return
    }
    var cursor: PiDurable.Cursor?
    repeat {
      let page = try await thread.storage.scanEntries(
        .init(
          conversationId: entry.conversationId,
          maxEntryId: entry.id, order: .descending), limit: 128, cursor: cursor)
      for candidate in page.items {
        guard let message = candidate.model?.first?.assistantMessage else { continue }
        guard candidate.byTaskId == creator,
          let call = message.toolCalls.first(where: {
            $0.id.displayString == completion.toolCallId && $0.name.displayString == completion.tool
          })
        else { throw RuntimeError.projectionFailed }
        try await commitToolOutcome(
          completion, identity: identity, arguments: .object(call.arguments), input: nil,
          thread: thread)
        thread.toolOutcomes.remove(.entry(entry.id.rawValue))
        return
      }
      cursor = page.next
    } while cursor != nil
    throw RuntimeError.projectionFailed
  }

  /// `input` is nil for a call Pi rejected inside `pi.generation`, before any tool task.
  private func commitToolOutcome(
    _ completion: ToolCompletedPayload, identity: PolicyToolIdentity,
    arguments: PiCore.JSONValue, input: PiDurable.ToolTaskInput?, thread: RuntimeThread
  ) async throws {
    let fence = thread.ownership.fence
    let fallback: PolicyDecidedPayload?
    if completion.ok {
      fallback = nil
    } else {
      let snapshot = try await store.policyCallSnapshot(
        chatID: thread.conversationID, taskID: identity.taskId, fence: fence,
        at: IDGenerator.nowMilliseconds())
      let entry = try await policyEntry(named: identity.tool, conversation: thread.conversationID)
      let operation = entry?.operation ?? .unknown
      let reason = "runtime." + (completion.errorCode ?? "tool_failed")
      let version =
        try entry?.version
        ?? Self.paramsHash([
          "policy": MemoshiProtocol.JSONValue.string("memoshi-policy-matrix-1"),
          "tool": .string(identity.tool), "operation": .string(operation.rawValue),
        ])
      var parentIsCodeMode = false
      if let input, let parent = try await parentToolName(input, thread: thread) {
        parentIsCodeMode = try await isCodeMode(parent, conversation: thread.conversationID)
      }
      fallback = PolicyDecidedPayload(
        toolCallId: identity.toolCallId, parentToolCallId: identity.parentToolCallId,
        via: PolicyHooks.via(
          entry?.source, nested: input?.isNestedCall == true, parentIsCodeMode: parentIsCodeMode),
        tool: identity.tool,
        decision: .deny, tier: try Tier(operation.tier), opClass: operation.rawValue,
        ruleId: reason,
        permissionMode: snapshot.policy.permissionMode, plan: false, origin: snapshot.task.origin,
        attendance: snapshot.task.regime == .attended ? .attended : .unattended,
        exposure: snapshot.exposure, deviceId: store.deviceID, reasonCode: reason,
        policyVersion: version, argsHash: try Self.paramsHash(ToolJSON.application(arguments)))
    }
    try await store.completePolicyTool(
      completion, call: identity, fallbackDecision: fallback, fence: fence,
      at: IDGenerator.nowMilliseconds())
  }

  /// A host definition's or composed extension tool's trusted entry. It never connects a
  /// composition: an audit fallback reads only what this adapter already opened.
  private func policyEntry(named name: String, conversation: ConversationID) async throws
    -> ToolPolicyEntry?
  {
    if let definition = toolDefinitions.first(where: {
      $0.name == name && ($0.chatID.map { $0.rawValue == conversation.rawValue } ?? true)
    }) {
      return try ToolPolicyEntry(definition)
    }
    if RuntimeSubagents.names.contains(name), let configuration = extensionComposition.subagents,
      let tool = RuntimeSubagents.tools(configuration).first(where: { $0.name == name })
    {
      return try ToolPolicyEntry(tool)
    }
    guard let tool = try? await extensionSession?.value.tools.first(where: { $0.name == name })
    else { return nil }
    return try ToolPolicyEntry(tool)
  }

  private func isCodeMode(_ name: String, conversation: ConversationID) async throws -> Bool {
    try await policyEntry(named: name, conversation: conversation)?.source == .codeMode
  }

  /// A nested call's immediate parent tool, read from Pi's durable task and assistant entry.
  private func parentToolName(_ input: PiDurable.ToolTaskInput, thread: RuntimeThread)
    async throws -> String?
  {
    guard input.isNestedCall else { return nil }
    guard let parent = input.nestedParent, let record = try await thread.storage.task(parent),
      let parentInput = try record.input?.decode(PiDurable.ToolTaskInput.self)
    else { throw RuntimeError.projectionFailed }
    if parentInput.isNestedCall {
      guard let name = parentInput.nestedCall?.name else { throw RuntimeError.projectionFailed }
      return name.displayString
    }
    guard let assistant = parentInput.modelCall?.assistant,
      let entry = try await thread.storage.entry(conversationId: record.conversationId, assistant)?
        .entry,
      let call = entry.model?.compactMap(\.assistantMessage).flatMap(\.toolCalls)
        .first(where: { $0.id == parentInput.modelCall?.callId })
    else { throw RuntimeError.projectionFailed }
    return call.name.displayString
  }

  private func observedToolCall(
    _ task: PiDurable.TaskRecord, input: PiDurable.ToolTaskInput, thread: RuntimeThread
  ) async throws -> (
    id: PiCore.JSONString, name: PiCore.JSONString, arguments: PiCore.JSONValue, assistant: EntryId
  ) {
    var root = input
    var ancestors: Set<TaskId> = [task.id]
    while root.isNestedCall {
      guard let parent = root.nestedParent, ancestors.insert(parent).inserted,
        let record = try await thread.storage.task(parent), record.kind == "pi.tool",
        record.conversationId == task.conversationId,
        let parentInput = try record.input?.decode(PiDurable.ToolTaskInput.self)
      else { throw RuntimeError.projectionFailed }
      root = parentInput
    }
    guard let assistant = root.modelCall?.assistant,
      let entry = try await thread.storage.entry(conversationId: task.conversationId, assistant)?
        .entry,
      let model = entry.model?.first?.assistantMessage
    else { throw RuntimeError.projectionFailed }
    if let call = input.nestedCall {
      return (call.id, call.name, call.arguments, assistant)
    }
    guard let call = model.toolCalls.first(where: { $0.id == input.modelCall?.callId }) else {
      throw RuntimeError.projectionFailed
    }
    return (call.id, call.name, .object(call.arguments), assistant)
  }
}
