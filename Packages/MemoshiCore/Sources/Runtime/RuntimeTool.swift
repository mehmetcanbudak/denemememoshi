import Chord
import Foundation
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable

/// Static host composition, never an RPC/model-supplied tool or authority declaration.
/// Production daemon composition supplies no tools until their platform gates are met.
public struct RuntimeToolDefinition: Sendable {
  /// The unique model-callable and nested-call name.
  public let name: String
  /// The trusted description offered to the model.
  public let description: String
  /// The object argument schema; target fields may carry `x-memoshi-role`.
  public let parameters: MemoshiProtocol.JSONValue
  /// The required schema when returning structured user-visible data.
  public let resultSchema: MemoshiProtocol.JSONValue?
  /// A trusted local conversation restriction. Nil keeps an ordinary shared tool definition.
  /// Scoped definitions are not offered or registered in another conversation.
  public let chatID: ConversationID?
  /// The trusted operation class; this adapter rejects T4/T5 definitions.
  public let operation: ToolPolicyOperation
  /// Whether Pi may replay execution after interruption; unsafe by default.
  public let replaySafe: Bool
  /// The context exposure introduced by tool output, including partial error results.
  public let outputExposure: Exposure
  /// Re-reads real grant and target authority at authorization and dispatch.
  public let authorize: @Sendable (MemoshiProtocol.JSONValue) async throws -> Bool
  /// Required for file tools: host-captured original targets, revalidated independently of `authorize`.
  /// No model-supplied class, grant or staging path can replace these source capabilities.
  public let sourceTargets:
    (@Sendable (MemoshiProtocol.JSONValue) async throws -> [RuntimeSourceTarget])?
  /// Executes on Pi's invocation executor only after fresh authorization.
  /// Computer handles bind cancellation themselves. Bind other asynchronous host work with
  /// `invocation.runCancellable`; keep nested `callTool` on this invocation's executor.
  public let execute:
    nonisolated(nonsending) @Sendable (MemoshiProtocol.JSONValue, RuntimeToolInvocation)
      async throws -> RuntimeToolResult

  /// `authorize` must re-read actual grants/target guards on every call, including recovery.
  public init(
    name: String, description: String, parameters: MemoshiProtocol.JSONValue,
    resultSchema: MemoshiProtocol.JSONValue? = nil, chatID: ConversationID? = nil,
    operation: ToolPolicyOperation,
    replaySafe: Bool = false,
    outputExposure: Exposure = Exposure(untrusted: false, privateData: false),
    authorize: @escaping @Sendable (MemoshiProtocol.JSONValue) async throws -> Bool,
    sourceTargets:
      (@Sendable (MemoshiProtocol.JSONValue) async throws -> [RuntimeSourceTarget])? = nil,
    execute:
      nonisolated(nonsending) @escaping @Sendable (MemoshiProtocol.JSONValue, RuntimeToolInvocation)
      async throws -> RuntimeToolResult
  ) {
    self.name = name
    self.description = description
    self.parameters = parameters
    self.resultSchema = resultSchema
    self.operation = operation
    self.chatID = chatID
    self.replaySafe = replaySafe
    self.outputExposure = Exposure(
      untrusted: outputExposure.untrusted,
      privateData: outputExposure.privateData || operation == .fileRead)
    self.authorize = authorize
    self.sourceTargets = sourceTargets
    self.execute = execute
  }

  func policyVersion() throws -> String {
    var identity: [String: MemoshiProtocol.JSONValue] = [
      "policy": .string("memoshi-policy-matrix-1"),
      "tool": .string(name), "operation": .string(operation.rawValue),
      "schema": parameters, "replaySafe": .bool(replaySafe),
      "sourcePolicy": .bool(sourceTargets != nil),
    ]
    if let chatID { identity["chatID"] = .string(chatID.rawValue) }
    return try RuntimeAdapter.paramsHash(identity)
  }
}

/// Model-visible and user-visible output are both scrubbed before Pi may persist either form.
public struct RuntimeToolResult: Equatable, Sendable {
  /// Model-visible UTF-8 text.
  public var text: String
  /// Optional user-visible data, validated against the definition's result schema.
  public var data: MemoshiProtocol.JSONValue?
  /// Whether execution failed, without exposing a raw host exception.
  public var isError: Bool
  /// Trusted effect knowledge. Error output alone never proves a rollback.
  public var effectOutcome: RuntimeToolEffectOutcome
  /// Creates both output representations for mandatory result scrubbing.
  public init(
    text: String, data: MemoshiProtocol.JSONValue? = nil, isError: Bool = false,
    effectOutcome: RuntimeToolEffectOutcome? = nil
  ) {
    self.text = text
    self.data = data
    self.isError = isError
    self.effectOutcome = effectOutcome ?? (isError ? .unknown : .completed)
  }
}

/// Invocation-bound nested calls stay on Pi's executor and cannot escape as an ambient API.
public final class RuntimeToolInvocation {
  private let api: PiDurable.ToolExecutionApi
  private let context: Chord.Context
  private let policy: PolicyHooks
  /// Host-captured execution fencing, never accepted from tool arguments.
  let fence: ConversationFence
  var runtimeTaskKey: String { String(api.taskId.rawValue) }
  /// The actual Pi call ID for this invocation.
  public var callID: String { api.callId.displayString }
  /// The durable `<conversation>:<Pi tool task>` identity (architecture §4.11's effects-ledger
  /// key). A restarted replay of the same task keeps it, while a later task differs even when
  /// the provider reuses its call ID; host tools derive external idempotency keys from it.
  public var effectKey: String { fence.conversationID.rawValue + ":" + runtimeTaskKey }
  /// The computer this call's conversation resolved through the Harness `env` hook (S1.12), or
  /// nil when its bot has none, as in the app and daemon.
  public var computer: RuntimeComputerHandle? {
    api.env.map {
      RuntimeComputerHandle(environment: $0, call: runtimeTaskKey, signal: api.signal)
    }
  }
  /// Runs host-owned work in a Swift task canceled by this Pi invocation's abort signal.
  /// Capture only Sendable host state; use `callTool` outside this closure on the original
  /// executor. The SDK invocation itself never moves into the host task.
  nonisolated(nonsending) public func runCancellable<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await PiAI.withAbortSignal(api.signal) {
      try Task.checkCancellation()
      return try await operation()
    }
  }

  init(
    api: PiDurable.ToolExecutionApi, context: Chord.Context,
    fence: ConversationFence, policy: PolicyHooks
  ) {
    self.api = api
    self.context = context
    self.fence = fence
    self.policy = policy
  }

  /// Each nested call is a real Pi tool task and re-enters the same mandatory policy hooks.
  nonisolated(nonsending) public func callTool(
    _ name: String, arguments: MemoshiProtocol.JSONValue, key: String
  ) async throws -> RuntimeToolResult {
    let result = try await api.executeTool(
      PiCore.JSONString(name), arguments: ToolJSON.sdk(arguments),
      options: .init(key: PiCore.JSONString(key)), context: context)
    try await policy.observeCommittedNestedResult(
      result, api: api, context: context, fence: fence)
    try await policy.waitForRecovery(signal: api.signal, context: context)
    let data = try result.structuredOutput.map(ToolJSON.application)
    let text: String
    if case .string(let value) = data {
      text = value
    } else if let data {
      text = data.canonicalText
    } else {
      text = result.isError ? "The nested tool did not complete." : "The nested tool completed."
    }
    return RuntimeToolResult(text: text, data: data, isError: result.isError)
  }
}

/// Presentation-safe failures. Tool/provider error descriptions are never forwarded.
public enum RuntimeToolError: Error, Equatable, Sendable {
  case invalidDefinition
  case invalidArguments
  case notAuthorized
  case unavailable
}
