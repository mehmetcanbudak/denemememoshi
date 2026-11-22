import Foundation
import MemoshiProtocol
import PiAI
import PiCodeMode
import PiCore
import PiDurable
import PiMCP

/// A tool another extension registers, with the trusted policy the mandatory hooks apply to it.
struct RuntimeExtensionTool: Sendable {
  /// Where the registration comes from. It decides the call's `via` attribution.
  enum Source: Sendable, Equatable {
    case codeMode
    case toolSearch
    case mcp(server: String)
    case subagent

    var policyName: String {
      switch self {
      case .codeMode: "codemode"
      case .toolSearch: "tool_search"
      case .mcp(let server): "mcp:" + server
      case .subagent: "subagent"
      }
    }
  }

  let name: String
  let source: Source
  /// The registration's own input schema, part of the policy version.
  let parameters: MemoshiProtocol.JSONValue
  /// Offered to the model only after `tool_search` loads it.
  let deferred: Bool
  let policy: RuntimeExtensionToolPolicy
  /// Applied to the authorized arguments immediately before the wrapped tool runs.
  let prepare: (@Sendable (PiCore.JSONValue) throws -> PiCore.JSONValue)?
}

/// The live resources of an explicit development tool composition: one Code Mode sandbox and
/// the connected MCP clients. Every conversation the adapter opens shares them; the adapter
/// closes them once, after the last Harness that uses them.
final class RuntimeExtensionSession: Sendable {
  static let mcpExtensionName: PiCore.JSONString = "memoshi.mcp"

  /// Installed after `memoshi.policy`, whose hooks and wraps cover every tool listed here.
  let extensions: [PiDurable.Extension]
  let tools: [RuntimeExtensionTool]
  private let sandbox: CodemodeSandbox?
  private let clients: [McpClient]

  private init(
    extensions: [PiDurable.Extension], tools: [RuntimeExtensionTool], sandbox: CodemodeSandbox?,
    clients: [McpClient]
  ) {
    self.extensions = extensions
    self.tools = tools
    self.sandbox = sandbox
    self.clients = clients
  }

  /// Registers connector secrets for redaction before any server starts, then connects each
  /// server and lists its tools. A failure closes everything already started.
  static func open(
    _ composition: RuntimeExtensionComposition, credentials: ProviderCredentials
  ) async throws -> RuntimeExtensionSession {
    var names = Set<String>()
    for server in composition.mcpServers {
      guard names.insert(server.name).inserted else { throw RuntimeToolError.invalidDefinition }
      try validate(server)
      for secret in server.secrets.values { await credentials.registerRedaction(secret) }
    }
    for server in composition.mcpHTTPServers {
      guard names.insert(server.name).inserted else { throw RuntimeToolError.invalidDefinition }
      try validate(server)
    }
    var clients: [McpClient] = []
    do {
      var extensions: [PiDurable.Extension] = []
      var tools: [RuntimeExtensionTool] = []
      var registrations: [PiDurable.ToolRegistration] = []
      for server in composition.mcpServers {
        let client = McpClient(options: McpClientOptions(name: "memoshi", version: "1"))
        clients.append(client)
        for (registration, tool) in try await bridge(server, client: client) {
          registrations.append(registration)
          tools.append(tool)
        }
      }
      for server in composition.mcpHTTPServers {
        let client = McpClient(options: McpClientOptions(name: "memoshi", version: "1"))
        clients.append(client)
        for (registration, tool) in try await bridge(
          server, client: client, credentials: credentials)
        {
          registrations.append(registration)
          tools.append(tool)
        }
      }
      if !registrations.isEmpty {
        extensions.append(PiDurable.Extension(name: mcpExtensionName, tools: registrations))
        let search = PiDurable.createToolSearchExtension()
        extensions.append(search)
        tools.append(
          try extensionTool(
            in: search, named: PiDurable.toolSearchToolName, source: .toolSearch,
            // Ranked results quote server-authored MCP descriptions into the context.
            policy: RuntimeExtensionToolPolicy(
              operation: .selfState, replaySafe: true,
              outputExposure: Exposure(untrusted: true, privateData: false),
              authorize: { _ in true }), prepare: nil))
      }
      var sandbox: CodemodeSandbox?
      if let codeMode = composition.codeMode {
        guard codeMode.memoryLimitBytes > 0, codeMode.timeoutMs > 0,
          codeMode.timeoutMs <= 2_147_483_647
        else { throw RuntimeToolError.invalidDefinition }
        // Uses Pi_Swift's default wasm2c backend (D140), never WasmKit.
        let created = try CodemodeSandbox(
          options: CodemodeSandboxOptions(
            timeoutMs: Double(codeMode.timeoutMs), memoryLimitBytes: codeMode.memoryLimitBytes))
        sandbox = created
        let codemode = PiDurable.createCodemodeExtension(
          PiDurable.CodemodeToolOptions(sandbox: created, models: false, globals: []))
        extensions.append(codemode)
        let ceiling = codeMode.timeoutMs
        tools.append(
          try extensionTool(
            in: codemode, named: PiDurable.CODEMODE_TOOL_NAME, source: .codeMode,
            // Discovery globals return tool descriptions, MCP-authored ones included, without
            // a hooked nested call (E21); the script's output carries that exposure.
            policy: RuntimeExtensionToolPolicy(
              operation: .codeRun, replaySafe: true,
              outputExposure: Exposure(untrusted: !registrations.isEmpty, privateData: false),
              authorize: { _ in true }),
            prepare: { try CodeModeDeadline.bounded($0, ceilingMs: ceiling) }))
      }
      return RuntimeExtensionSession(
        extensions: extensions, tools: tools, sandbox: sandbox, clients: clients)
    } catch {
      for client in clients { try? await client.close() }
      throw error
    }
  }

  /// Stops running scripts and every server process. Idempotent.
  func close() async {
    await sandbox?.close()
    for client in clients { try? await client.close() }
  }

  private static func extensionTool(
    in item: PiDurable.Extension, named name: PiCore.JSONString,
    source: RuntimeExtensionTool.Source, policy: RuntimeExtensionToolPolicy,
    prepare: (@Sendable (PiCore.JSONValue) throws -> PiCore.JSONValue)?
  ) throws -> RuntimeExtensionTool {
    guard item.tools.count == 1, let registration = item.tools.first,
      registration.name == name, let native = name.nativeString
    else { throw RuntimeToolError.invalidDefinition }
    return RuntimeExtensionTool(
      name: native, source: source, parameters: try ToolJSON.application(registration.parameters),
      deferred: registration.deferred, policy: policy, prepare: prepare)
  }

  /// Turns each reviewed tool the server lists into one deferred, script-callable registration.
  private static func bridge(_ server: RuntimeMCPServerConfiguration, client: McpClient)
    async throws -> [(PiDurable.ToolRegistration, RuntimeExtensionTool)]
  {
    let transport = StdioTransport(
      options: StdioTransportOptions(
        command: server.command, args: server.arguments,
        env: server.environment.merging(server.secrets) { _, secret in secret },
        inheritEnv: false))
    _ = try await client.connect(transport)
    return try await registrations(
      for: client.listTools(), serverName: server.name, policies: server.tools, client: client)
  }

  /// A reconnect must match the exact reviewed table. A live list-change notification revokes
  /// every old binding; no model run may silently adopt new descriptions, schemas or effects.
  private static func bridge(
    _ server: RuntimeMCPHTTPServerConfiguration, client: McpClient,
    credentials: ProviderCredentials
  ) async throws -> [(PiDurable.ToolRegistration, RuntimeExtensionTool)] {
    let trust = RuntimeMCPToolTableTrust()
    let auth = RuntimeMCPAuthAdapter(server: server, credentials: credentials)
    let transport = StreamableHttpTransport(
      options: StreamableHttpTransportOptions(
        url: server.url, fetch: { try await auth.fetch($0, signal: $1) },
        authProvider: server.credentials == nil ? nil : auth,
        reconnect: StreamableHttpReconnectOptions(maxRetries: 0)))
    do {
      _ = await client.onNotification("notifications/tools/list_changed") { _ in trust.revoke() }
      _ = try await client.connect(transport)
      let listed = try await client.listTools()
      let table = try listed.sorted { $0.name < $1.name }.map {
        try ToolJSON.application($0.jsonValue)
      }
      let digest = mcpTokenDigest(MemoshiProtocol.JSONValue.array(table).canonicalText)
      guard digest == server.toolTableSHA256, trust.isTrusted else {
        throw RuntimeMCPError.toolTableChanged
      }
      var policies: [String: RuntimeExtensionToolPolicy] = [:]
      for (name, reviewed) in server.tools {
        policies[name] = RuntimeExtensionToolPolicy(
          operation: reviewed.operation, replaySafe: reviewed.replaySafe,
          outputExposure: reviewed.outputExposure,
          authorize: { arguments in
            guard trust.isTrusted else { return false }
            let authorized = try await reviewed.authorize(arguments)
            return authorized && trust.isTrusted
          })
      }
      var safe: [PiMCP.Tool] = []
      for tool in listed {
        if let source = server.credentials {
          let value = try await source.redact(ToolJSON.application(tool.jsonValue))
          guard let object = try ToolJSON.sdk(value).objectValue else {
            throw RuntimeMCPError.unavailable
          }
          safe.append(try PiMCP.Tool(rawValue: object))
        } else {
          safe.append(tool)
        }
      }
      guard trust.isTrusted else { throw RuntimeMCPError.toolTableChanged }
      return try await registrations(
        for: safe, serverName: server.name, policies: policies, client: client,
        redact: server.credentials?.redact, toolTableTrust: trust)
    } catch {
      if let safe = error as? RuntimeMCPError { throw safe }
      throw RuntimeMCPError.unavailable
    }
  }

  private static func registrations(
    for listed: [PiMCP.Tool], serverName: String,
    policies: [String: RuntimeExtensionToolPolicy], client: McpClient,
    redact: (@Sendable (MemoshiProtocol.JSONValue) async throws -> MemoshiProtocol.JSONValue)? =
      nil,
    toolTableTrust: RuntimeMCPToolTableTrust? = nil
  ) async throws -> [(PiDurable.ToolRegistration, RuntimeExtensionTool)] {
    var seen = Set<String>()
    var bridged: [(PiDurable.ToolRegistration, RuntimeExtensionTool)] = []
    for tool in listed {
      guard seen.insert(tool.name).inserted else { throw RuntimeToolError.invalidDefinition }
      guard let policy = policies[tool.name] else { continue }
      let name = "mcp__" + serverName + "__" + tool.name
      var parameters = tool.inputSchema
      parameters["type"] = "object"
      if parameters["properties"] == nil { parameters["properties"] = .object([:]) }
      let remote = tool.nameValue
      let structured = tool.outputSchema != nil
      let registration = PiDurable.ToolRegistration(
        name: PiCore.JSONString(name),
        description: PiCore.JSONString(tool.description ?? tool.title ?? "MCP tool " + tool.name),
        parameters: .object(parameters), replay: policy.replaySafe ? .safe : .unsafe,
        structuredOutputSchema: tool.outputSchema.map(PiCore.JSONValue.object),
        callers: [.model, .tools], deferred: true,
        execute: { arguments, api, _ in
          guard let object = arguments.objectValue else { throw RuntimeToolError.invalidArguments }
          do {
            let dispatch = RuntimeMCPRequestContext(
              signal: api.signal, toolTableTrust: toolTableTrust)
            return try await RuntimeMCPRequestContext.$current.withValue(dispatch) {
              var result = try await client.callTool(
                remote, arguments: object, options: McpRequestOptions(signal: api.signal))
              let stripped = RuntimeMCPHostRedaction.removingServerMarkers(result.jsonValue)
              guard let raw = stripped.objectValue else { return ToolOutputScrubber.withheld }
              result = try CallToolResult(rawValue: raw)
              var hostRedacted = false
              if let redact {
                let original = try ToolJSON.application(result.jsonValue)
                let value = try await redact(original)
                hostRedacted = value != original
                guard let object = try ToolJSON.sdk(value).objectValue else {
                  return ToolOutputScrubber.withheld
                }
                result = try CallToolResult(rawValue: object)
              }
              let output = try toLlmContent(result).map { content -> PiAI.ContentBlock in
                switch content {
                case .text(let text): .text(PiAI.TextContent(text: text))
                case .image(let data, let mimeType):
                  .image(PiAI.ImageContent(data: data, mimeType: mimeType))
                }
              }
              return PiDurable.ToolExecutionResult(
                output: output, structuredOutput: structured ? result.structuredContent : nil,
                isError: result.isError == true,
                details: hostRedacted ? RuntimeMCPHostRedaction.details : nil)
            }
          } catch {
            try api.signal.throwIfAborted()
            // PiMCP errors can contain response bodies, request URLs and echoed credentials.
            // The outer mandatory afterTool still processes this presentation-safe result.
            return PiDurable.ToolExecutionResult(
              output: [.text(.init(text: "The MCP connector could not complete this request."))],
              isError: true)
          }
        })
      bridged.append(
        (
          registration,
          RuntimeExtensionTool(
            name: name, source: .mcp(server: serverName),
            parameters: try ToolJSON.application(.object(parameters)), deferred: true,
            policy: policy, prepare: nil)
        ))
    }
    return bridged
  }

  /// policy.md §3.3.1: one `mcp__<server>__` namespace per server, an explicit executable and
  /// environment, and only tier 0–3 reviewed entries in this profile.
  private static func validate(_ server: RuntimeMCPServerConfiguration) throws {
    let lowercase = UInt8(ascii: "a")...UInt8(ascii: "z")
    let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
    let name = Array(server.name.utf8)
    guard (1...32).contains(name.count), lowercase.contains(name[0]),
      name.allSatisfy({ lowercase.contains($0) || digits.contains($0) }),
      server.command.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: server.command),
      Set(server.environment.keys).isDisjoint(with: server.secrets.keys),
      !server.secrets.values.contains(where: \.isEmpty)
    else { throw RuntimeToolError.invalidDefinition }
    for (key, value) in server.environment.merging(server.secrets, uniquingKeysWith: { $1 }) {
      guard !key.isEmpty, !key.utf8.contains(UInt8(ascii: "=")), !key.utf8.contains(0),
        !value.utf8.contains(0)
      else { throw RuntimeToolError.invalidDefinition }
    }
    try validateTools(server.name, server.tools)
  }

  private static func validate(_ server: RuntimeMCPHTTPServerConfiguration) throws {
    try server.network.validate(server.url)
    guard server.url.query == nil,
      server.toolTableSHA256.utf8.count == 64,
      server.toolTableSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      server.credentials.map({ !$0.secretRef.isEmpty }) ?? true
    else { throw RuntimeMCPError.invalidConfiguration }
    try validateTools(server.name, server.tools)
  }

  private static func validateTools(
    _ serverName: String, _ policies: [String: RuntimeExtensionToolPolicy]
  ) throws {
    let lowercase = UInt8(ascii: "a")...UInt8(ascii: "z")
    let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
    let name = Array(serverName.utf8)
    guard (1...32).contains(name.count), lowercase.contains(name[0]),
      name.allSatisfy({ lowercase.contains($0) || digits.contains($0) })
    else { throw RuntimeToolError.invalidDefinition }
    for (tool, policy) in policies {
      let full = "mcp__" + serverName + "__" + tool
      guard !tool.isEmpty, full.utf8.count <= 64, policy.operation.tier < 4,
        tool.utf8.allSatisfy({
          lowercase.contains($0) || digits.contains($0) || $0 == UInt8(ascii: "_")
            || $0 == UInt8(ascii: "-") || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains($0)
        })
      else { throw RuntimeToolError.invalidDefinition }
    }
  }
}

/// D98's ceiling on a durable script's run time. At the pinned candidate a durable script runs
/// with no deadline unless its own `// @options` line sets `timeout_ms`; the sandbox's
/// `timeoutMs` applies only to `CodemodeSandbox.execute`. The host therefore writes the
/// ceiling into the options line, keeping a shorter one. The rewrite is deterministic, so a
/// script resumed after a restart sees the same source and journal.
///
/// Pi records the deadline as wall-clock start + ceiling, so it bounds the whole script, waits
/// included, and both interactions fail closed: a nested call whose approval is still pending
/// at the deadline is aborted with its script, which cancels the card before the call runs
/// (an attended card's own 30-minute expiry never applies inside a script); and a host that
/// returns after the deadline ends the script with an error instead of continuing it.
/// Finished nested calls are never rerun. A longer ceiling would only let a stuck script hold
/// a VM longer; D98's 300,000 ms stays the bound.
enum CodeModeDeadline {
  static func bounded(_ arguments: PiCore.JSONValue, ceilingMs: Int) throws -> PiCore.JSONValue {
    // Malformed input reaches the codemode tool unchanged; it reports its own error.
    guard case .object(var object) = arguments, let source = object["code"]?.textValue,
      let parsed = try? parseCodemodeSource(source)
    else { return arguments }
    if let timeout = parsed.options.timeoutMs, timeout <= ceilingMs { return arguments }
    var options: PiCore.JSONObject = ["timeout_ms": .number(Double(ceilingMs))]
    if let tokens = parsed.options.maxOutputTokens {
      options["max_output_tokens"] = .number(Double(tokens))
    }
    let header =
      PiCore.JSONString(CODEMODE_OPTIONS_PREFIX + " ")
      + (try PiCore.JSONValue.object(options).jsonString())
    // With an options line, the parsed code keeps its leading newline; without one, the whole
    // source follows the new first line.
    let hadOptions = parsed.code != source
    object["code"] = .string(header + (hadOptions ? parsed.code : "\n" + source))
    return .object(object)
  }
}
