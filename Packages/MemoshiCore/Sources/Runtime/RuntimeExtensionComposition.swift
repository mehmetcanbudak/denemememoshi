import Foundation
import MemoshiProtocol

/// Explicit development and qualification composition of the Pi extensions that register tools
/// of their own: Code Mode, tool search and MCP bridges. The normal app and daemon pass
/// ``none``; no RPC, stored record or model input can select any of it.
public struct RuntimeExtensionComposition: Sendable {
  /// The production composition: no Code Mode, tool search or MCP tools.
  public static let none = RuntimeExtensionComposition()

  /// Installs the `codemode` tool, with `models: false` and no custom globals, when set.
  public var codeMode: RuntimeCodeModeConfiguration?
  /// Stdio MCP servers, connected before the first conversation opens. Their reviewed tools are
  /// deferred `mcp__<server>__<tool>` tools that the model finds through `tool_search`.
  public var mcpServers: [RuntimeMCPServerConfiguration]
  /// Reviewed Streamable HTTP MCP servers. OAuth state stays in the native app host; only
  /// bounded, purpose-bound access-token releases cross the existing credential boundary.
  public var mcpHTTPServers: [RuntimeMCPHTTPServerConfiguration]
  /// Actual task-owned Pi children. Only trusted host composition may opt in; the model may
  /// provide a task body, never a model, prompt, extension, tool set or background privilege.
  public var subagents: RuntimeSubagentConfiguration?

  /// Composes Code Mode and MCP servers for development and qualification only.
  public init(
    codeMode: RuntimeCodeModeConfiguration? = nil,
    mcpServers: [RuntimeMCPServerConfiguration] = [],
    mcpHTTPServers: [RuntimeMCPHTTPServerConfiguration] = [],
    subagents: RuntimeSubagentConfiguration? = nil
  ) {
    self.codeMode = codeMode
    self.mcpServers = mcpServers
    self.mcpHTTPServers = mcpHTTPServers
    self.subagents = subagents
  }

  var isEmpty: Bool {
    codeMode == nil && mcpServers.isEmpty && mcpHTTPServers.isEmpty && subagents == nil
  }
}

/// Qualification-only delegation. Children inherit the invoking model, effort and trusted
/// prompt sections. Tools are an intersection with their parent's callable set, with all
/// delegation tools removed. The defaults never change the production ``none`` composition.
public struct RuntimeSubagentConfiguration: Sendable {
  /// Registers task-owned foreground delegation in this explicit trusted composition.
  public let foreground: Bool
  /// Registers conversation-anchored background runs with durable run/report checkpoints.
  public let persistentBackground: Bool
  /// Nil inherits all reviewed parent tools; a list may only reduce that set.
  public let childTools: [String]?

  /// Selects delegation forms and an optional narrower inherited tool ceiling.
  public init(
    foreground: Bool = true, persistentBackground: Bool = true, childTools: [String]? = nil
  ) {
    self.foreground = foreground
    self.persistentBackground = persistentBackground
    self.childTools = childTools
  }
}

/// D98/D140 Code Mode sandbox limits on Pi_Swift's default `wasm2c` backend.
public struct RuntimeCodeModeConfiguration: Sendable {
  /// The QuickJS memory limit of each script's VM.
  public var memoryLimitBytes: Int
  /// The ceiling on one script's run time. A script's own `timeout_ms` may only shorten it.
  public var timeoutMs: Int

  /// Defaults to the accepted workload record: 268,435,456 bytes and 300,000 ms.
  public init(memoryLimitBytes: Int = 268_435_456, timeoutMs: Int = 300_000) {
    self.memoryLimitBytes = memoryLimitBytes
    self.timeoutMs = timeoutMs
  }
}

/// One stdio MCP server, started with an explicit environment and nothing inherited.
public struct RuntimeMCPServerConfiguration: Sendable {
  /// The `<server>` part of `mcp__<server>__<tool>`: a lowercase ASCII letter, then lowercase
  /// letters or digits.
  public var name: String
  /// The server executable's absolute path. There is no shell or `PATH` lookup.
  public var command: String
  /// The executable's arguments.
  public var arguments: [String]
  /// The child's whole environment apart from ``secrets``.
  public var environment: [String: String]
  /// Credentials the server reads from its environment, such as an OAuth access token. Each
  /// value is also registered with the tool-output scrubber before the server starts.
  public var secrets: [String: String]
  /// The reviewed tool table, keyed by the server's own tool name. A listed tool without an
  /// entry is never registered, offered or callable.
  public var tools: [String: RuntimeExtensionToolPolicy]

  /// Describes a stdio server and its reviewed tools.
  public init(
    name: String, command: String, arguments: [String] = [],
    environment: [String: String] = [:], secrets: [String: String] = [:],
    tools: [String: RuntimeExtensionToolPolicy]
  ) {
    self.name = name
    self.command = command
    self.arguments = arguments
    self.environment = environment
    self.secrets = secrets
    self.tools = tools
  }
}

/// Trusted Memoshi policy for one tool that another Pi extension registers. Like
/// ``RuntimeToolDefinition``, it is static host composition; tiers 4 and 5 are refused.
public struct RuntimeExtensionToolPolicy: Sendable {
  /// The trusted operation class and so its tier.
  public let operation: ToolPolicyOperation
  /// Whether Pi may run the call again after an interruption.
  public let replaySafe: Bool
  /// The context exposure the tool's output introduces, including partial error results.
  public let outputExposure: Exposure
  /// Re-reads real grant and target authority at authorization and again at dispatch.
  public let authorize: @Sendable (MemoshiProtocol.JSONValue) async throws -> Bool

  /// `authorize` must re-read actual authority on every call, including recovery.
  public init(
    operation: ToolPolicyOperation, replaySafe: Bool, outputExposure: Exposure,
    authorize: @escaping @Sendable (MemoshiProtocol.JSONValue) async throws -> Bool
  ) {
    self.operation = operation
    self.replaySafe = replaySafe
    self.outputExposure = outputExposure
    self.authorize = authorize
  }
}
