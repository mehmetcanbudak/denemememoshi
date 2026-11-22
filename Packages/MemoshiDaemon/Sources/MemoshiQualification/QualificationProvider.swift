import Foundation
import MemoshiProtocol
import Synchronization

/// Request counts the provider observed for one run.
package struct ProviderCounts: Codable, Equatable, Sendable {
  /// `GET /v1/models` requests answered.
  package var models = 0
  /// Tool-call replies started.
  package var toolCallReplies = 0
  /// Final replies started after a tool result.
  package var finalReplies = 0
  /// Requests from a spawned child conversation, held or answered.
  package var childReplies = 0
  /// Subagent tool results that were not the child's scripted answer; the provider answered
  /// them without calling the effect tool.
  package var subagentResultMismatches = 0
  /// Streams paused for a streaming kill, and child requests held open for a subagent kill.
  package var pausedStreams = 0
  /// Requests refused for a missing or wrong bearer token.
  package var unauthorized = 0
  /// Unexpected paths, methods or models.
  package var other = 0
  /// Requests the real-model proxy could not complete upstream.
  package var upstreamErrors = 0

  package init() {}
}

/// The controlled external model: a loopback OpenAI-compatible server whose only scripted
/// behavior is the qualification turn. Requests still pass through PiAI's real HTTP client,
/// streaming parser and Memoshi's per-use credential checks; only the remote model is replaced.
///
/// Without a tool result in the request it streams three text deltas and calls the
/// qualification tool; with one it streams a final answer. A streaming kill arms a one-shot pause
/// that holds the next tool-call stream open after a seeded number of deltas.
///
/// The subagent script is a function of the conversation, so a request repeated after a restart
/// gets the same reply: no effect result yet and no subagent result means delegate; the child's
/// own answer as the subagent result (PiDurable's `<harness>` replay notes aside) means call the
/// effect tool; the effect result means answer. Any other subagent result, such as an error or
/// an unavailable result, is answered without the effect and counted as a mismatch.
package final class QualificationProvider: ChaosModel {
  /// The model identifier the provider lists.
  package static let modelID = "qualification-model"
  /// Text the first model reply streams before calling the tool.
  package static let leadDeltas = ["Recording ", "the qualification ", "effect now."]
  /// Text the final model reply streams after the tool result.
  package static let finalDeltas = ["The qualification ", "effect is recorded."]
  /// The final reply as the transcript should hold it.
  package static var finalText: String { finalDeltas.joined() }
  /// The answer to a subagent result that is not the child's: it calls no tool, and a run that
  /// ends with it fails its final-answer check.
  package static let mismatchText = "The child's answer did not arrive; no effect was recorded."
  /// The model-callable name of the runtime's foreground subagent tool.
  package static let subagentToolName = "subagent"
  /// The model-callable name of the runtime's Code Mode tool.
  package static let codeModeToolName = "codemode"
  /// The child task the parent delegates. It starts with the marker the child's own request
  /// carries and asks for no tool, so a real child is never told to run the parent's effect.
  package static func childTask(run: String) -> String {
    "subagent-task: reply with the single word done and call no tool (run \(run))"
  }
  /// The child's plain scripted answer; it calls no tool.
  package static let childAnswer = "done"
  /// The delegation call's ID: distinct from the effect call's, as a real provider's would be.
  package static func subagentCallID(run: String) -> String { "mq-\(run)-subagent" }

  package var modelID: String { Self.modelID }
  package var expectedFinalText: String? { Self.finalText }
  package var holdsChildStreams: Bool { true }

  /// `http://127.0.0.1:<port>/v1`.
  package let baseURL: String
  private let server: LoopbackHTTPServer
  private let state: Mutex<State>

  private struct State {
    var bearer: String?
    var run = ""
    var callID = ""
    var toolName = ""
    var subagents = false
    var codeMode = false
    var pauseAfterDeltas: Int?
    var pauseChild = false
    var counts = ProviderCounts()
    var replies = 0
  }

  private init(server: LoopbackHTTPServer) {
    self.server = server
    state = Mutex(State())
    baseURL = "http://127.0.0.1:\(server.port)/v1"
  }

  /// Starts on an OS-chosen loopback port. Every request is refused until a run is armed.
  package static func start() async throws -> QualificationProvider {
    let box = StateBox()
    let server = try await LoopbackHTTPServer.start { request, responder in
      await box.provider?.handle(request, responder)
    }
    let provider = QualificationProvider(server: server)
    box.provider = provider
    return provider
  }

  /// Selects the run whose bearer canary every request must present, and resets its counts.
  /// `subagents` selects the subagent script: the first reply calls the subagent tool, the
  /// child's own request is answered plain, then the effect tool, then the final answer.
  /// `codeMode` selects the nested Code Mode script: the first reply calls `codemode` with a
  /// script that invokes the effect tool once, then answers after the script completes.
  package func arm(
    run: String, bearer: String, toolName: String, callID: String, subagents: Bool,
    codeMode: Bool = false
  ) {
    state.withLock {
      $0 = State(
        bearer: bearer, run: run, callID: callID, toolName: toolName, subagents: subagents,
        codeMode: codeMode)
    }
  }

  /// Holds the next tool-call stream open after `deltas` text deltas until its client dies.
  package func pauseStreaming(afterDeltas deltas: Int) {
    state.withLock { $0.pauseAfterDeltas = max(1, min(deltas, Self.leadDeltas.count)) }
  }

  /// Holds the next child request open until its client dies, giving a subagent kill its
  /// deterministic window: the spawned child conversation is running inside the host.
  package func pauseChildStream() {
    state.withLock { $0.pauseChild = true }
  }

  /// Clears unused pauses, such as after a run ended early.
  package func clearPause() {
    state.withLock {
      $0.pauseAfterDeltas = nil
      $0.pauseChild = false
    }
  }

  /// The current run's request counts.
  package var counts: ProviderCounts { state.withLock { $0.counts } }

  /// Refuses everything until the next `arm`.
  package func disarm() { state.withLock { $0 = State() } }

  /// Stops listening and closes open streams.
  package func close() async { await server.close() }

  private func handle(_ request: LoopbackHTTPRequest, _ responder: LoopbackHTTPResponder) async {
    let authorized = state.withLock { state in
      guard let bearer = state.bearer else { return false }
      return request.header("Authorization") == "Bearer " + bearer
    }
    guard authorized else {
      state.withLock { $0.counts.unauthorized += 1 }
      await responder.json(
        401, Data(#"{"error":{"message":"unauthorized","type":"authentication_error"}}"#.utf8))
      return
    }
    switch (request.method, request.path) {
    case ("GET", "/v1/models"):
      state.withLock { $0.counts.models += 1 }
      await responder.json(
        200,
        Data(
          #"{"data":[{"id":"\#(Self.modelID)","context_window":8192,"max_tokens":256}]}"#.utf8))
    case ("POST", "/v1/chat/completions"):
      await complete(request, responder)
    default:
      state.withLock { $0.counts.other += 1 }
      await responder.json(404, Data(#"{"error":{"message":"not found"}}"#.utf8))
    }
  }

  /// One scripted reply shape.
  private enum Reply {
    /// A child conversation's own request: a plain answer, or a held stream for the kill.
    case child(hold: Bool)
    /// Streamed lead text, then one scripted tool call.
    case toolCall(id: String, name: String, arguments: JSONValue, pause: Int?)
    /// A plain answer: the final reply, or the refusal after a mismatched subagent result.
    case answer([String])

    /// The streamed finish reason: a tool call keeps the turn open, everything else stops.
    var finish: String {
      if case .toolCall = self { return "tool_calls" }
      return "stop"
    }
  }

  /// The reply the provider selected for one request, with the response identity.
  private struct Scripted {
    let run: String
    let reply: Reply
    let number: Int
  }

  private func complete(_ request: LoopbackHTTPRequest, _ responder: LoopbackHTTPResponder) async {
    let childTask = Self.childTaskText(request.body)
    let hasToolResult = Self.containsToolResult(request.body)
    let body = request.body
    let scripted = state.withLock { (state: inout State) -> Scripted in
      state.replies += 1
      let effectArguments: JSONValue = [
        "step": "effect-1", "note": .string("Qualification effect for \(state.run)"),
      ]
      let reply: Reply
      if childTask != nil {
        state.counts.childReplies += 1
        let hold = state.pauseChild
        if hold {
          state.pauseChild = false
          state.counts.pausedStreams += 1
        }
        reply = .child(hold: hold)
      } else if state.subagents {
        let delegation = Self.subagentCallID(run: state.run)
        if Self.toolResultText(body, callID: state.callID) != nil {
          state.counts.finalReplies += 1
          reply = .answer(Self.finalDeltas)
        } else if let result = Self.toolResultText(body, callID: delegation) {
          if Self.withoutHarnessNotes(result) == Self.childAnswer {
            state.counts.toolCallReplies += 1
            reply = .toolCall(
              id: state.callID, name: state.toolName, arguments: effectArguments, pause: nil)
          } else {
            state.counts.subagentResultMismatches += 1
            reply = .answer([Self.mismatchText])
          }
        } else {
          // A streaming pause is never armed in a subagent run; it is neither used nor counted.
          state.counts.toolCallReplies += 1
          reply = .toolCall(
            id: delegation, name: Self.subagentToolName,
            arguments: ["task": .string(Self.childTask(run: state.run))], pause: nil)
        }
      } else if state.codeMode {
        if Self.toolResultText(body, callID: state.callID) != nil {
          state.counts.finalReplies += 1
          reply = .answer(Self.finalDeltas)
        } else {
          state.counts.toolCallReplies += 1
          let script =
            "return await tools.\(state.toolName)("
            + "{ step: \"effect-1\", note: \"Qualification effect for \(state.run)\" });"
          reply = .toolCall(
            id: state.callID, name: Self.codeModeToolName,
            arguments: ["code": .string(script)], pause: nil)
        }
      } else if hasToolResult {
        state.counts.finalReplies += 1
        reply = .answer(Self.finalDeltas)
      } else {
        state.counts.toolCallReplies += 1
        let pause = state.pauseAfterDeltas
        state.pauseAfterDeltas = nil
        if pause != nil { state.counts.pausedStreams += 1 }
        reply = .toolCall(
          id: state.callID, name: state.toolName, arguments: effectArguments, pause: pause)
      }
      return Scripted(run: state.run, reply: reply, number: state.replies)
    }
    let responseID = "mq-\(scripted.run)-\(scripted.number)"
    do {
      try await responder.beginEvents()
      switch scripted.reply {
      case .child(let hold):
        try await responder.write(
          try Self.chunk(["content": .string(Self.childAnswer)], id: responseID))
        if hold {
          await Self.holdUntilClientCloses(responder)
          return
        }
      case .toolCall(let id, let name, let arguments, let pause):
        for (index, text) in Self.leadDeltas.enumerated() {
          try await responder.write(try Self.chunk(["content": .string(text)], id: responseID))
          if let pause, index + 1 == pause {
            await Self.holdUntilClientCloses(responder)
            return
          }
          try await Task.sleep(for: .milliseconds(15))
        }
        let encoded = String(
          decoding: try ProtocolCoding.makeEncoder().encode(arguments), as: UTF8.self)
        try await responder.write(
          try Self.chunk(
            [
              "tool_calls": [
                [
                  "index": 0, "id": .string(id), "type": "function",
                  "function": ["name": .string(name), "arguments": .string(encoded)],
                ]
              ]
            ], id: responseID))
      case .answer(let deltas):
        for text in deltas {
          try await responder.write(try Self.chunk(["content": .string(text)], id: responseID))
          try await Task.sleep(for: .milliseconds(15))
        }
      }
      try await responder.write(
        try Self.chunk([:], id: responseID, finish: scripted.reply.finish) + "data: [DONE]\n\n")
      try await responder.finishEvents()
    } catch {
      await responder.close()
    }
  }

  /// A streaming kill: keep the response open until the killed host's socket closes, bounded so
  /// a driver failure cannot leave the stream open forever.
  static func holdUntilClientCloses(_ responder: LoopbackHTTPResponder) async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await responder.closed() }
      group.addTask { try? await Task.sleep(for: .seconds(120)) }
      _ = await group.next()
      group.cancelAll()
      await responder.close()
    }
  }

  /// The child task text when the request's last user message is a subagent's own task. The
  /// parent's instruction names the marker but does not start with it, so only a child matches.
  static func childTaskText(_ body: Data) -> String? {
    guard case .object(let object)? = try? JSONValue.parse(body),
      case .array(let messages)? = object["messages"]
    else { return nil }
    for message in messages.reversed() {
      guard case .object(let fields) = message, fields["role"] == .string("user") else {
        continue
      }
      if case .string(let text)? = fields["content"], text.hasPrefix("subagent-task:") {
        return text
      }
      if case .array(let blocks)? = fields["content"] {
        for block in blocks {
          if case .object(let part) = block, case .string(let text)? = part["text"],
            text.hasPrefix("subagent-task:")
          {
            return text
          }
        }
      }
      return nil
    }
    return nil
  }

  /// Whether a completion request already carries a tool result.
  static func containsToolResult(_ body: Data) -> Bool {
    guard case .object(let object)? = try? JSONValue.parse(body),
      case .array(let messages)? = object["messages"]
    else { return false }
    return messages.contains { message in
      if case .object(let fields) = message, fields["role"] == .string("tool") { return true }
      return false
    }
  }

  /// The text of the last tool result answering `callID`, or nil when the request has none.
  static func toolResultText(_ body: Data, callID: String) -> String? {
    guard case .object(let object)? = try? JSONValue.parse(body),
      case .array(let messages)? = object["messages"]
    else { return nil }
    for message in messages.reversed() {
      guard case .object(let fields) = message, fields["role"] == .string("tool"),
        fields["tool_call_id"] == .string(callID)
      else { continue }
      switch fields["content"] {
      case .string(let text)?: return text
      case .array(let blocks)?:
        return blocks.compactMap { block -> String? in
          guard case .object(let part) = block, case .string(let text)? = part["text"] else {
            return nil
          }
          return text
        }.joined()
      default: return ""
      }
    }
    return nil
  }

  /// A tool result without the `<harness>…</harness>` diagnostic blocks PiDurable appends, such
  /// as its note that an interrupted replay-safe call ran again, trimmed. An unterminated block
  /// leaves the text unchanged, so it can never match an answer.
  static func withoutHarnessNotes(_ text: String) -> String {
    var remaining = Substring(text)
    var kept = ""
    while let open = remaining.range(of: "<harness>") {
      guard let close = remaining[open.upperBound...].range(of: "</harness>") else { return text }
      kept += remaining[..<open.lowerBound]
      remaining = remaining[close.upperBound...]
    }
    kept += remaining
    return kept.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func chunk(_ delta: JSONValue, id: String, finish: String? = nil) throws
    -> String
  {
    let value: JSONValue = [
      "id": .string(id), "object": "chat.completion.chunk", "created": 1,
      "model": .string(modelID),
      "choices": [
        ["index": 0, "delta": delta, "finish_reason": finish.map(JSONValue.string) ?? .null]
      ],
    ]
    return "data: "
      + String(decoding: try ProtocolCoding.makeEncoder().encode(value), as: UTF8.self)
      + "\n\n"
  }
}

/// Lets the server's handler reach the provider created after the server binds.
private final class StateBox: Sendable {
  private let value = Mutex<QualificationProvider?>(nil)

  var provider: QualificationProvider? {
    get { value.withLock { $0 } }
    set { value.withLock { $0 = newValue } }
  }
}
