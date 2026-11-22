import Chord
import Foundation
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable

/// The trusted policy the mandatory hooks apply to one tool, whoever registers it. A tool with
/// no entry is blocked by `beforeTool`; nothing derives an entry from a registration.
struct ToolPolicyEntry: Sendable {
  let name: String
  /// Nil for a host definition that `memoshi.policy` registers itself.
  let source: RuntimeExtensionTool.Source?
  let operation: ToolPolicyOperation
  let replaySafe: Bool
  let outputExposure: Exposure
  let parameters: MemoshiProtocol.JSONValue
  let authorize: @Sendable (MemoshiProtocol.JSONValue) async throws -> Bool
  let sourceTargets: (@Sendable (MemoshiProtocol.JSONValue) async throws -> [RuntimeSourceTarget])?
  /// Applied to the authorized arguments immediately before a wrapped extension tool runs.
  let prepare: (@Sendable (PiCore.JSONValue) throws -> PiCore.JSONValue)?
  let version: String

  init(_ definition: RuntimeToolDefinition) throws {
    name = definition.name
    source = nil
    operation = definition.operation
    replaySafe = definition.replaySafe
    outputExposure = definition.outputExposure
    parameters = definition.parameters
    authorize = definition.authorize
    sourceTargets = definition.sourceTargets
    prepare = nil
    version = try definition.policyVersion()
  }

  init(_ tool: RuntimeExtensionTool) throws {
    name = tool.name
    source = tool.source
    operation = tool.policy.operation
    replaySafe = tool.policy.replaySafe
    outputExposure = tool.policy.outputExposure
    parameters = tool.parameters
    authorize = tool.policy.authorize
    sourceTargets = nil
    prepare = tool.prepare
    version = try RuntimeAdapter.paramsHash([
      "policy": .string("memoshi-policy-matrix-1"), "tool": .string(tool.name),
      "operation": .string(tool.policy.operation.rawValue), "schema": tool.parameters,
      "replaySafe": .bool(tool.policy.replaySafe), "source": .string(tool.source.policyName),
    ])
  }
}

extension PolicyHooks {
  /// policy.md P1's channels. An MCP-bridge tool is `mcp` whoever calls it; another tool is
  /// `model` when the model called it and `code_mode` when a Code Mode script did. A call
  /// nested in any other host tool has no `via`.
  static func via(
    _ source: RuntimeExtensionTool.Source?, nested: Bool, parentIsCodeMode: Bool
  ) -> ToolCallVia? {
    if case .mcp? = source { return .mcp }
    if !nested { return .model }
    return parentIsCodeMode ? .codeMode : nil
  }

  /// Derives `via` from the hook's own parent call and the definition's source; the parent's
  /// tool name comes from Pi's durable task and assistant entry, never from a call ID shape.
  nonisolated(nonsending) func callVia(
    _ entry: ToolPolicyEntry, parent: PiDurable.ToolHookCall.Parent?, api: PiDurable.HookApi,
    context: Chord.Context
  ) async throws -> ToolCallVia? {
    guard let parent else { return Self.via(entry.source, nested: false, parentIsCodeMode: false) }
    if case .mcp? = entry.source {
      return Self.via(entry.source, nested: true, parentIsCodeMode: false)
    }
    guard let task = try await api.getTask(parent.taskId, context: context),
      task.kind == "pi.tool",
      let input = try task.input?.decode(PiDurable.ToolTaskInput.self)
    else { throw RuntimeToolError.notAuthorized }
    let name: PiCore.JSONString?
    switch input {
    case .nested(_, _, _, let call, _):
      name = call.name
    case .model(let assistant, let callId):
      guard let record = try await api.getEntry(assistant, context: context)
      else { throw RuntimeToolError.notAuthorized }
      name =
        record.model?.compactMap(\.assistantMessage).flatMap(\.toolCalls)
        .first(where: { $0.id == callId })?.name
    }
    guard let name else { throw RuntimeToolError.notAuthorized }
    return Self.via(
      entry.source, nested: true, parentIsCodeMode: isCodeMode(name.displayString))
  }

  /// True only for the installed Code Mode extension's tool, not a host tool of that name.
  func isCodeMode(_ name: String) -> Bool {
    entries[name]?.source == .codeMode
  }

  /// Pi applies every selected extension's wraps to the resolved tools. Each extension tool
  /// with an entry gets the host tools' dispatch-time recheck and unsafe-dispatch intent. A
  /// registration that no longer matches its reviewed entry throws, and Pi removes it.
  func extensionWraps() -> [PiDurable.Wrap] {
    extensionToolNames.compactMap { name in
      guard let entry = entries[name], entry.source != nil else { return nil }
      return .tool(PiCore.JSONString(name)) { registration in
        try wrapped(registration, entry: entry)
      }
    }
  }

  private func wrapped(_ registration: PiDurable.ToolRegistration, entry: ToolPolicyEntry) throws
    -> PiDurable.ToolRegistration
  {
    // A widened replay policy or a changed schema is not the reviewed tool.
    guard try ToolJSON.application(registration.parameters) == entry.parameters,
      !entry.replaySafe || registration.replay == .safe
    else { throw RuntimeToolError.invalidDefinition }
    var tool = registration
    tool.replay = entry.replaySafe ? .safe : .unsafe
    let execute = registration.execute
    tool.execute = { arguments, api, context in
      var dispatch: PolicyToolIdentity?
      do {
        let identity = try await recheck(
          entry, arguments: try ToolJSON.application(arguments), api: api, context: context)
        try context.throwIfAborted()
        try api.signal.throwIfAborted()
        let prepared = try entry.prepare?(arguments) ?? arguments
        if !entry.replaySafe {
          try await store.beginUnsafeToolDispatch(
            identity, fence: fence, at: IDGenerator.nowMilliseconds())
          dispatch = identity
        }
        let result = try await execute(prepared, api, context)
        if let dispatch {
          // An error result does not prove that nothing happened.
          try await store.finishUnsafeToolDispatch(
            dispatch, outcome: result.isError ? .unknown : .returned(ok: true), fence: fence,
            at: IDGenerator.nowMilliseconds())
        }
        return result
      } catch {
        if let dispatch {
          try? await store.finishUnsafeToolDispatch(
            dispatch, outcome: .unknown, fence: fence, at: IDGenerator.nowMilliseconds())
        }
        try api.signal.throwIfAborted()
        return PiDurable.ToolExecutionResult(
          output: [
            .text(.init(text: "The tool was not authorized or could not complete safely."))
          ], isError: true)
      }
    }
    return tool
  }
}
