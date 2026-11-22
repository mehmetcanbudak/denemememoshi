import Foundation
import PiAI
import PiCore

// MARK: - Claude Code Binary Discovery & Status (D108, DIST-03)

/// Availability snapshot for the user's own unmodified Claude Code binary on this Mac (`D108`).
/// Memoshi never initiates an Anthropic sign-in flow and never reads, stores, or forwards
/// Anthropic credentials.
public struct ClaudeCodeStatus: Equatable, Sendable {
  public let executablePath: String?
  public let version: String?

  public var isInstalled: Bool { executablePath != nil }

  public init(executablePath: String?, version: String?) {
    self.executablePath = executablePath
    self.version = version
  }
}

/// Locates the user's unmodified `claude` CLI binary on macOS without invoking a shell (`D108`).
public enum ClaudeCodeLocator {
  /// Canonical provider endpoint stored in `ModelProviderConfiguration.baseUrl` for auto-detection.
  public static let defaultEndpoint = "claude-code://local"

  /// Validates that an endpoint is either the canonical auto-detect URI or a clean local `file://`
  /// path with no traversal, query, or fragment.
  public static func isValidEndpoint(_ value: String) -> Bool {
    if value == defaultEndpoint { return true }
    guard let components = URLComponents(string: value),
      components.scheme == "file",
      components.host == nil || components.host?.isEmpty == true,
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      let url = components.url
    else {
      return false
    }
    let path = url.path
    guard path.hasPrefix("/"), !path.isEmpty else { return false }
    let segments = path.split(separator: "/")
    return !segments.contains("..") && !segments.contains(".")
  }

  /// Extracts an explicit local binary path if the user configured a `file://` endpoint.
  public static func explicitBinaryPath(from endpoint: String) -> String? {
    guard endpoint != defaultEndpoint, isValidEndpoint(endpoint),
      let url = URL(string: endpoint), url.isFileURL
    else {
      return nil
    }
    return url.path
  }

  /// Resolves the unmodified `claude` executable on macOS. Always returns `nil` on iOS/iPadOS
  /// because Claude Code runs only on the user's Mac (`D108`).
  public static func resolveBinary(endpoint: String = defaultEndpoint) -> URL? {
    #if os(macOS)
      let fm = FileManager.default
      if let explicit = explicitBinaryPath(from: endpoint) {
        return fm.isExecutableFile(atPath: explicit) ? URL(fileURLWithPath: explicit) : nil
      }
      let home = NSHomeDirectory()
      let candidates = [
        "\(home)/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "\(home)/.npm-global/bin/claude",
        "\(home)/.volta/bin/claude",
        "\(home)/.asdf/shims/claude",
        "/usr/bin/claude",
      ]
      for path in candidates where fm.isExecutableFile(atPath: path) {
        return URL(fileURLWithPath: path)
      }
      return nil
    #else
      return nil
    #endif
  }

  /// Probes the unmodified binary path and version (`claude --version`) with a sanitized
  /// environment and bounded timeout. Never triggers login or reads Anthropic credentials.
  public static func probe(endpoint: String = defaultEndpoint) -> ClaudeCodeStatus {
    #if os(macOS)
      guard let binary = resolveBinary(endpoint: endpoint) else {
        return ClaudeCodeStatus(executablePath: nil, version: nil)
      }
      let process = Process()
      let pipe = Pipe()
      process.executableURL = binary
      process.arguments = ["--version"]
      process.environment = sanitizedEnvironment(for: binary)
      process.standardInput = FileHandle.nullDevice
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
      } catch {
        return ClaudeCodeStatus(executablePath: binary.path, version: nil)
      }
      let deadline = Date().addingTimeInterval(3.0)
      while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.02)
      }
      if process.isRunning {
        process.terminate()
        return ClaudeCodeStatus(executablePath: binary.path, version: nil)
      }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let raw = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let firstLine = raw?.split(whereSeparator: \.isNewline).first.map(String.init)
      return ClaudeCodeStatus(
        executablePath: binary.path,
        version: firstLine?.isEmpty == false ? firstLine : nil
      )
    #else
      return ClaudeCodeStatus(executablePath: nil, version: nil)
    #endif
  }

  /// Minimal allowlisted environment for spawning the user's own unmodified `claude` binary.
  /// Contains no Anthropic API keys or Memoshi secrets; preserves standard bin paths so
  /// Homebrew or Node-installed `claude` shims can locate their runtime.
  static func sanitizedEnvironment(for binary: URL) -> [String: String] {
    let binaryDir = binary.deletingLastPathComponent().path
    let home = NSHomeDirectory()
    let pathParts = [
      binaryDir,
      "\(home)/.local/bin",
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
      "/usr/sbin",
      "/sbin",
    ]
    var uniquePaths: [String] = []
    for part in pathParts where !uniquePaths.contains(part) {
      uniquePaths.append(part)
    }
    return [
      "PATH": uniquePaths.joined(separator: ":"),
      "HOME": home,
      "USER": NSUserName(),
      "LOGNAME": NSUserName(),
      "TMPDIR": FileManager.default.temporaryDirectory.path,
      "LANG": "en_US.UTF-8",
    ]
  }
}

// MARK: - Curated Claude Code Model Catalog (D108)

public enum ClaudeCodeModelCatalog {
  public struct Entry: Equatable, Sendable {
    public let id: String
    public let name: String
    public let contextWindow: Int
    public let maxTokens: Int

    public init(id: String, name: String, contextWindow: Int, maxTokens: Int) {
      self.id = id
      self.name = name
      self.contextWindow = contextWindow
      self.maxTokens = maxTokens
    }
  }

  /// Claude models relayed through the user's unmodified Claude Code binary on this Mac (`D108`).
  public static let models: [Entry] = [
    Entry(
      id: "claude-opus-4-6",
      name: "Claude Opus 4.6 (Claude Code)",
      contextWindow: 200_000,
      maxTokens: 32_000
    ),
    Entry(
      id: "claude-sonnet-4-6",
      name: "Claude Sonnet 4.6 (Claude Code)",
      contextWindow: 200_000,
      maxTokens: 16_000
    ),
    Entry(
      id: "claude-haiku-4-5",
      name: "Claude Haiku 4.5 (Claude Code)",
      contextWindow: 200_000,
      maxTokens: 8_192
    ),
  ]
}

// MARK: - OpenAI-Compatible Bridge Transport to Unmodified `claude` Binary (D108)

/// Translates `PiAI.openAICompatibleProvider` HTTP requests directly into invocations of the
/// user's unmodified `claude` CLI binary on macOS (`claude -p --output-format stream-json`),
/// with Claude Code's built-in tools disabled (`--tools ""`) so Memoshi's own policy hooks and
/// sandbox remain authoritative in Phase 1 (`D108`).
public enum ClaudeCodeTransport {
  /// Parsed request parameters extracted from an OpenAI Chat Completions payload.
  public struct PromptRequest: Equatable, Sendable {
    public let model: String
    public let systemPrompt: String?
    public let prompt: String
    public let stream: Bool

    public init(model: String, systemPrompt: String?, prompt: String, stream: Bool) {
      self.model = model
      self.systemPrompt = systemPrompt
      self.prompt = prompt
      self.stream = stream
    }
  }

  /// Parsed NDJSON event emitted by `claude -p --output-format stream-json --verbose`.
  public struct StreamEvent: Equatable, Sendable {
    public let textDelta: String?
    public let finalText: String?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheReadTokens: Int?
    public let cacheWriteTokens: Int?
    public let isResult: Bool
    public let isError: Bool
    public let errorMessage: String?

    public init(
      textDelta: String? = nil,
      finalText: String? = nil,
      inputTokens: Int? = nil,
      outputTokens: Int? = nil,
      cacheReadTokens: Int? = nil,
      cacheWriteTokens: Int? = nil,
      isResult: Bool = false,
      isError: Bool = false,
      errorMessage: String? = nil
    ) {
      self.textDelta = textDelta
      self.finalText = finalText
      self.inputTokens = inputTokens
      self.outputTokens = outputTokens
      self.cacheReadTokens = cacheReadTokens
      self.cacheWriteTokens = cacheWriteTokens
      self.isResult = isResult
      self.isError = isError
      self.errorMessage = errorMessage
    }
  }

  /// Extracts model, system prompt, conversation transcript prompt, and stream flag from an
  /// OpenAI Chat Completions JSON request body.
  public static func extractPrompt(from data: Data) throws -> PromptRequest {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw PiAI.HTTPTransportError("Invalid Claude Code completion request payload.")
    }
    let rawModel = (root["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let model = (rawModel?.isEmpty == false ? rawModel! : "claude-sonnet-4-6")
    let stream = (root["stream"] as? Bool) ?? true

    let messages = (root["messages"] as? [[String: Any]]) ?? []
    var systemParts: [String] = []
    var turns: [(role: String, text: String)] = []

    for msg in messages {
      let role = (msg["role"] as? String)?.lowercased() ?? "user"
      let text = extractTextContent(from: msg["content"])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      if role == "system" || role == "developer" {
        systemParts.append(text)
      } else {
        turns.append((role: role, text: text))
      }
    }

    let prompt: String
    if turns.count == 1 && turns[0].role == "user" {
      prompt = turns[0].text
    } else {
      prompt = turns.map { turn in
        switch turn.role {
        case "assistant":
          return "Assistant:\n\(turn.text)"
        case "tool":
          return "Tool result:\n\(turn.text)"
        default:
          return "User:\n\(turn.text)"
        }
      }.joined(separator: "\n\n")
    }

    let systemPrompt = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")
    return PromptRequest(
      model: model,
      systemPrompt: systemPrompt,
      prompt: prompt.isEmpty ? "Hello" : prompt,
      stream: stream
    )
  }

  /// Parses one NDJSON line emitted by `claude -p --output-format stream-json --verbose`.
  public static func parseStreamJSONLine(_ line: String) -> StreamEvent? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("{"),
      let data = trimmed.data(using: .utf8),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = root["type"] as? String
    else {
      return nil
    }

    switch type {
    case "stream_event":
      guard let event = root["event"] as? [String: Any],
        let eventType = event["type"] as? String
      else {
        return nil
      }
      if eventType == "content_block_delta",
        let delta = event["delta"] as? [String: Any],
        (delta["type"] as? String) == "text_delta",
        let text = delta["text"] as? String, !text.isEmpty
      {
        return StreamEvent(textDelta: text)
      }
      if eventType == "message_delta",
        let usage = event["usage"] as? [String: Any]
      {
        return StreamEvent(
          inputTokens: usage["input_tokens"] as? Int,
          outputTokens: usage["output_tokens"] as? Int,
          cacheReadTokens: usage["cache_read_input_tokens"] as? Int,
          cacheWriteTokens: usage["cache_creation_input_tokens"] as? Int
        )
      }
      return nil

    case "assistant":
      if let message = root["message"] as? [String: Any],
        let content = message["content"] as? [[String: Any]]
      {
        let combined = content.compactMap { block -> String? in
          guard (block["type"] as? String) == "text" else { return nil }
          return block["text"] as? String
        }.joined()
        let usage = message["usage"] as? [String: Any]
        return StreamEvent(
          finalText: combined.isEmpty ? nil : combined,
          inputTokens: usage?["input_tokens"] as? Int,
          outputTokens: usage?["output_tokens"] as? Int,
          cacheReadTokens: usage?["cache_read_input_tokens"] as? Int,
          cacheWriteTokens: usage?["cache_creation_input_tokens"] as? Int
        )
      }
      return nil

    case "result":
      let isError = (root["is_error"] as? Bool) ?? ((root["subtype"] as? String) == "error")
      let resultText = root["result"] as? String
      let usage = root["usage"] as? [String: Any]
      return StreamEvent(
        finalText: isError ? nil : resultText,
        inputTokens: usage?["input_tokens"] as? Int,
        outputTokens: usage?["output_tokens"] as? Int,
        cacheReadTokens: usage?["cache_read_input_tokens"] as? Int,
        cacheWriteTokens: usage?["cache_creation_input_tokens"] as? Int,
        isResult: true,
        isError: isError,
        errorMessage: isError ? (resultText ?? "Claude Code returned an error.") : nil
      )

    default:
      return nil
    }
  }

  /// Creates the `PiAI.FetchFunction` used by `ModelProviderDefinition.claudeCode`.
  static func makeFetch(endpoint: String) -> PiAI.FetchFunction {
    { request, signal in
      try Task.checkCancellation()
      try signal?.throwIfAborted()

      let path = request.url.path
      if path.hasSuffix("/models") {
        return try modelsResponse(url: request.url, endpoint: endpoint)
      }
      if path.hasSuffix("/chat/completions") {
        return try await completionsResponse(request: request, signal: signal, endpoint: endpoint)
      }
      return jsonResponse(
        status: 404,
        url: request.url,
        object: ["error": ["message": "Unsupported Claude Code bridge path."]]
      )
    }
  }

  private static func modelsResponse(url: URL, endpoint: String) throws -> PiAI.HTTPResponse {
    guard ClaudeCodeLocator.resolveBinary(endpoint: endpoint) != nil else {
      return jsonResponse(
        status: 503,
        url: url,
        object: [
          "error": [
            "message":
              "Claude Code binary not found on this Mac. Install Claude Code and run `claude auth login` in Terminal."
          ]
        ]
      )
    }
    let payload: [String: Any] = [
      "object": "list",
      "data": ClaudeCodeModelCatalog.models.map { entry in
        [
          "id": entry.id,
          "object": "model",
          "owned_by": "claude-code",
          "context_window": entry.contextWindow,
          "max_tokens": entry.maxTokens,
        ] as [String: Any]
      },
    ]
    return jsonResponse(status: 200, url: url, object: payload)
  }

  private static func completionsResponse(
    request: PiAI.HTTPRequest,
    signal: PiCore.AbortSignal?,
    endpoint: String
  ) async throws -> PiAI.HTTPResponse {
    #if os(macOS)
      guard let binary = ClaudeCodeLocator.resolveBinary(endpoint: endpoint) else {
        return jsonResponse(
          status: 503,
          url: request.url,
          object: [
            "error": [
              "message":
                "Claude Code binary not found on this Mac. Install Claude Code and run `claude auth login` in Terminal."
            ]
          ]
        )
      }
      let promptRequest = try extractPrompt(from: request.body ?? Data())
      let completionID = "chatcmpl-cc-\(UUID().uuidString.prefix(12))"
      let created = Int(Date().timeIntervalSince1970)

      let process = Process()
      process.executableURL = binary
      var args = [
        "-p",
        "--output-format", "stream-json",
        "--verbose",
        "--include-partial-messages",
        "--model", promptRequest.model,
        "--tools", "",
        "--no-session-persistence",
      ]
      if let systemPrompt = promptRequest.systemPrompt, !systemPrompt.isEmpty {
        args.append(contentsOf: ["--system-prompt", systemPrompt])
      }
      process.arguments = args
      process.environment = ClaudeCodeLocator.sanitizedEnvironment(for: binary)

      let stdinPipe = Pipe()
      let stdoutPipe = Pipe()
      process.standardInput = stdinPipe
      process.standardOutput = stdoutPipe
      process.standardError = FileHandle.nullDevice

      let abortToken = signal?.addListener { _ in
        if process.isRunning { process.terminate() }
      }

      do {
        try process.run()
      } catch {
        if let abortToken { signal?.removeListener(abortToken) }
        return jsonResponse(
          status: 502,
          url: request.url,
          object: ["error": ["message": "Failed to launch unmodified Claude Code binary."]]
        )
      }

      // Feed the prompt on stdin and close EOF so `claude -p` begins generating immediately.
      if let promptData = promptRequest.prompt.data(using: .utf8) {
        try? stdinPipe.fileHandleForWriting.write(contentsOf: promptData)
      }
      try? stdinPipe.fileHandleForWriting.close()

      if promptRequest.stream {
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        continuation.onTermination = { _ in
          if process.isRunning { process.terminate() }
          if let abortToken { signal?.removeListener(abortToken) }
        }

        Task.detached {
          defer {
            if let abortToken { signal?.removeListener(abortToken) }
          }
          var emittedDelta = false
          var bufferedFallbackText = ""
          var inputTokens = 0
          var outputTokens = 0

          do {
            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
              if Task.isCancelled {
                if process.isRunning { process.terminate() }
                continuation.finish(throwing: CancellationError())
                return
              }
              guard let event = Self.parseStreamJSONLine(line) else { continue }
              if let inTok = event.inputTokens { inputTokens = max(inputTokens, inTok) }
              if let outTok = event.outputTokens { outputTokens = max(outputTokens, outTok) }
              if event.isError {
                continuation.finish(
                  throwing: PiAI.HTTPTransportError(
                    event.errorMessage ?? "Claude Code could not complete this request."
                  )
                )
                return
              }
              if let delta = event.textDelta, !delta.isEmpty {
                emittedDelta = true
                if let chunk = Self.sseChunk(
                  id: completionID, created: created, model: promptRequest.model,
                  deltaContent: delta, finishReason: nil, usage: nil)
                {
                  continuation.yield(chunk)
                }
              } else if let finalText = event.finalText, !finalText.isEmpty {
                bufferedFallbackText = finalText
              }
            }

            process.waitUntilExit()
            if process.terminationStatus != 0 && !emittedDelta && bufferedFallbackText.isEmpty {
              continuation.finish(
                throwing: PiAI.HTTPTransportError(
                  "Claude Code exited with status \(process.terminationStatus). Verify you are signed in with `claude auth login`."
                )
              )
              return
            }

            if !emittedDelta && !bufferedFallbackText.isEmpty,
              let chunk = Self.sseChunk(
                id: completionID, created: created, model: promptRequest.model,
                deltaContent: bufferedFallbackText, finishReason: nil, usage: nil)
            {
              continuation.yield(chunk)
            }

            let usageDict: [String: Any]? =
              (inputTokens > 0 || outputTokens > 0)
              ? [
                "prompt_tokens": inputTokens,
                "completion_tokens": outputTokens,
                "total_tokens": inputTokens + outputTokens,
              ] : nil
            if let doneChunk = Self.sseChunk(
              id: completionID, created: created, model: promptRequest.model,
              deltaContent: nil, finishReason: "stop", usage: usageDict)
            {
              continuation.yield(doneChunk)
            }
            continuation.yield(Data("data: [DONE]\n\n".utf8))
            continuation.finish()
          } catch {
            if process.isRunning { process.terminate() }
            continuation.finish(throwing: error)
          }
        }

        return PiAI.HTTPResponse(
          status: 200,
          headers: ["content-type": "text/event-stream"],
          url: request.url,
          body: PiAI.HTTPBody(stream)
        )
      } else {
        defer {
          if let abortToken { signal?.removeListener(abortToken) }
        }
        return try await withTaskCancellationHandler {
          let collected = try await Task.detached { () throws -> (String, Int, Int, Int32) in
            var fullText = ""
            var fallback = ""
            var inTok = 0
            var outTok = 0
            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
              guard let event = Self.parseStreamJSONLine(line) else { continue }
              if let i = event.inputTokens { inTok = max(inTok, i) }
              if let o = event.outputTokens { outTok = max(outTok, o) }
              if let delta = event.textDelta { fullText += delta }
              if let fin = event.finalText { fallback = fin }
            }
            process.waitUntilExit()
            let answer = fullText.isEmpty ? fallback : fullText
            return (answer, inTok, outTok, process.terminationStatus)
          }.value

          if collected.3 != 0 && collected.0.isEmpty {
            return jsonResponse(
              status: 502,
              url: request.url,
              object: [
                "error": [
                  "message":
                    "Claude Code exited with status \(collected.3). Verify you are signed in with `claude auth login`."
                ]
              ]
            )
          }
          let payload: [String: Any] = [
            "id": completionID,
            "object": "chat.completion",
            "created": created,
            "model": promptRequest.model,
            "choices": [
              [
                "index": 0,
                "message": ["role": "assistant", "content": collected.0],
                "finish_reason": "stop",
              ]
            ],
            "usage": [
              "prompt_tokens": collected.1,
              "completion_tokens": collected.2,
              "total_tokens": collected.1 + collected.2,
            ],
          ]
          return jsonResponse(status: 200, url: request.url, object: payload)
        } onCancel: {
          if process.isRunning { process.terminate() }
        }
      }
    #else
      return jsonResponse(
        status: 503,
        url: request.url,
        object: [
          "error": [
            "message":
              "Claude Code runs only on the user's Mac (D108). Connect to your Mac host to use this model."
          ]
        ]
      )
    #endif
  }

  private static func sseChunk(
    id: String,
    created: Int,
    model: String,
    deltaContent: String?,
    finishReason: String?,
    usage: [String: Any]?
  ) -> Data? {
    var delta: [String: Any] = [:]
    if let deltaContent {
      delta["role"] = "assistant"
      delta["content"] = deltaContent
    }
    var choice: [String: Any] = [
      "index": 0,
      "delta": delta,
    ]
    choice["finish_reason"] = finishReason ?? NSNull()
    var payload: [String: Any] = [
      "id": id,
      "object": "chat.completion.chunk",
      "created": created,
      "model": model,
      "choices": [choice],
    ]
    if let usage {
      payload["usage"] = usage
    }
    guard let json = try? JSONSerialization.data(withJSONObject: payload),
      let text = String(data: json, encoding: .utf8)
    else {
      return nil
    }
    return Data("data: \(text)\n\n".utf8)
  }

  private static func jsonResponse(
    status: Int, url: URL, object: [String: Any]
  ) -> PiAI.HTTPResponse {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    continuation.yield(data)
    continuation.finish()
    return PiAI.HTTPResponse(
      status: status,
      headers: ["content-type": "application/json"],
      url: url,
      body: PiAI.HTTPBody(stream)
    )
  }

  private static func extractTextContent(from raw: Any?) -> String {
    if let text = raw as? String {
      return text
    }
    if let parts = raw as? [[String: Any]] {
      return parts.compactMap { part -> String? in
        if let text = part["text"] as? String { return text }
        if let content = part["content"] as? String { return content }
        return nil
      }.joined(separator: "\n")
    }
    return ""
  }
}
