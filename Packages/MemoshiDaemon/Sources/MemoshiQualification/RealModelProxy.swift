import Foundation
import MemoshiProtocol
import Synchronization

/// The model behind the qualification host's `local` provider: the scripted provider or the
/// real-model proxy. The driver arms one run at a time.
package protocol ChaosModel: Sendable {
  /// `http://127.0.0.1:<port>/v1`, the endpoint the host configures as its `local` provider.
  var baseURL: String { get }
  /// The model each run selects under `local`.
  var modelID: String { get }
  /// The exact final answer a run must end with, or nil when a real model words it.
  var expectedFinalText: String? { get }
  /// Whether `pauseChildStream` really holds the child's request. Only then does a subagent
  /// kill wait for the held stream and a run check the exact number of child requests.
  var holdsChildStreams: Bool { get }
  /// The current run's request counts.
  var counts: ProviderCounts { get }
  /// Selects the run whose bearer canary every request must present, and resets its counts.
  /// `subagents` arms the subagent script, where the parent delegates to a spawned child;
  /// `codeMode` arms the nested Code Mode script, where the model runs a script calling the tool.
  func arm(
    run: String, bearer: String, toolName: String, callID: String, subagents: Bool,
    codeMode: Bool)
  /// Holds the next reply that streams text open after `deltas` text deltas until its client
  /// dies: the streaming kill point.
  func pauseStreaming(afterDeltas deltas: Int)
  /// Holds the next child conversation's request open until its client dies, giving the
  /// subagent kill point its window: the spawned child is running inside the host.
  func pauseChildStream()
  /// Clears an unused pause, such as after a run ended early.
  func clearPause()
  /// Refuses everything until the next `arm`.
  func disarm()
  /// Stops listening and closes open streams.
  func close() async
}

/// Real-model proxy failures.
package enum RealModelProxyError: Error, Equatable {
  /// The upstream is not a plain-HTTP loopback endpoint.
  case nonLoopbackUpstream
}

/// The real-model mode's controlled external model: a loopback proxy in front of a local
/// OpenAI-compatible server such as Ollama. Requests still pass through PiAI's real HTTP client
/// and Memoshi's per-use credential checks: every request must present the run's bearer canary,
/// which is checked here and never forwarded. Only the configured model is listed or served.
///
/// A streaming kill arms a one-shot pause. The next reply that streams text stops being relayed
/// at its N-th text delta, or at its first other chunk after some text (such as a tool call or
/// the finish), whichever comes first; the upstream request is canceled and the response stays
/// open until the killed host's socket closes.
package final class RealModelProxy: ChaosModel {
  /// `http://127.0.0.1:<port>/v1`.
  package let baseURL: String
  /// The one upstream model this proxy lists and serves.
  package let modelID: String
  private let upstream: URL
  private let server: LoopbackHTTPServer
  private let session: URLSession
  private let state = Mutex(State())

  private struct State {
    var bearer: String?
    var pauseAfterDeltas: Int?
    var counts = ProviderCounts()
  }

  /// A real model words its own answer.
  package var expectedFinalText: String? { nil }
  /// The proxy cannot hold a real child's request; see `pauseChildStream`.
  package var holdsChildStreams: Bool { false }

  private init(server: LoopbackHTTPServer, upstream: URL, modelID: String) {
    self.server = server
    self.upstream = upstream
    self.modelID = modelID
    let configuration = URLSessionConfiguration.ephemeral
    // A small local model can think for a while before its first token.
    configuration.timeoutIntervalForRequest = 600
    session = URLSession(configuration: configuration)
    baseURL = "http://127.0.0.1:\(server.port)/v1"
  }

  /// Starts on an OS-chosen loopback port in front of `upstream`, such as
  /// `http://127.0.0.1:11434/v1`. Every request is refused until a run is armed.
  package static func start(upstream: URL, modelID: String) async throws -> RealModelProxy {
    guard upstream.scheme == "http",
      ["127.0.0.1", "localhost", "::1"].contains(upstream.host?.lowercased() ?? ""),
      upstream.user == nil, upstream.password == nil, upstream.query == nil, !modelID.isEmpty
    else { throw RealModelProxyError.nonLoopbackUpstream }
    let box = ProxyBox()
    let server = try await LoopbackHTTPServer.start { request, responder in
      await box.proxy?.handle(request, responder)
    }
    let proxy = RealModelProxy(server: server, upstream: upstream, modelID: modelID)
    box.proxy = proxy
    return proxy
  }

  package func arm(
    run: String, bearer: String, toolName: String, callID: String, subagents: Bool,
    codeMode: Bool = false
  ) {
    state.withLock { $0 = State(bearer: bearer) }
  }

  package func pauseStreaming(afterDeltas deltas: Int) {
    state.withLock { $0.pauseAfterDeltas = max(1, deltas) }
  }

  /// A real model's child cannot be held by the proxy; the driver falls back to the host's
  /// live-run snapshot for the subagent kill point.
  package func pauseChildStream() {}

  package func clearPause() { state.withLock { $0.pauseAfterDeltas = nil } }

  package var counts: ProviderCounts { state.withLock { $0.counts } }

  package func disarm() { state.withLock { $0 = State() } }

  package func close() async {
    session.invalidateAndCancel()
    await server.close()
  }

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
      await listModels(responder)
    case ("POST", "/v1/chat/completions"):
      await complete(request, responder)
    default:
      state.withLock { $0.counts.other += 1 }
      await responder.json(404, Data(#"{"error":{"message":"not found"}}"#.utf8))
    }
  }

  /// The upstream list, reduced to the configured model.
  private func listModels(_ responder: LoopbackHTTPResponder) async {
    do {
      let (data, response) = try await session.data(from: upstream.appendingPathComponent("models"))
      guard (response as? HTTPURLResponse)?.statusCode == 200,
        case .object(var list) = try JSONValue.parse(data), case .array(let rows)? = list["data"]
      else { throw URLError(.badServerResponse) }
      list["data"] = .array(
        rows.filter { row in
          if case .object(let fields) = row { return fields["id"] == .string(modelID) }
          return false
        })
      await responder.json(200, try ProtocolCoding.makeEncoder().encode(JSONValue.object(list)))
    } catch {
      state.withLock { $0.counts.upstreamErrors += 1 }
      await responder.json(502, Data(#"{"error":{"message":"upstream model list failed"}}"#.utf8))
    }
  }

  private func complete(_ request: LoopbackHTTPRequest, _ responder: LoopbackHTTPResponder) async {
    guard case .object(let body)? = try? JSONValue.parse(request.body),
      body["model"] == .string(modelID)
    else {
      state.withLock { $0.counts.other += 1 }
      await responder.json(404, Data(#"{"error":{"message":"model not available"}}"#.utf8))
      return
    }
    let final = QualificationProvider.containsToolResult(request.body)
    let child = QualificationProvider.childTaskText(request.body) != nil
    state.withLock {
      if child {
        $0.counts.childReplies += 1
      } else if final {
        $0.counts.finalReplies += 1
      } else {
        $0.counts.toolCallReplies += 1
      }
    }
    var forward = URLRequest(url: upstream.appendingPathComponent("chat/completions"))
    forward.httpMethod = "POST"
    forward.httpBody = request.body
    forward.setValue("application/json", forHTTPHeaderField: "Content-Type")
    forward.setValue(
      request.header("Accept") ?? "text/event-stream", forHTTPHeaderField: "Accept")
    let bytes: URLSession.AsyncBytes
    let head: HTTPURLResponse
    do {
      let (stream, response) = try await session.bytes(for: forward)
      guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
      bytes = stream
      head = response
    } catch {
      state.withLock { $0.counts.upstreamErrors += 1 }
      await responder.json(502, Data(#"{"error":{"message":"upstream request failed"}}"#.utf8))
      return
    }
    guard head.statusCode == 200,
      head.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true
    else {
      // Errors and non-streaming replies are relayed whole, unchanged.
      if head.statusCode >= 400 { state.withLock { $0.counts.upstreamErrors += 1 } }
      var data = Data()
      do {
        for try await byte in bytes { data.append(byte) }
      } catch {
        state.withLock { $0.counts.upstreamErrors += 1 }
      }
      await responder.json(head.statusCode, data)
      return
    }
    do {
      try await responder.beginEvents()
      var texts = 0
      for try await line in bytes.lines where line.hasPrefix("data:") {
        let text = Self.isTextDelta(line)
        if !text, claimPause(texts: texts, atNonText: true) {
          bytes.task.cancel()
          await QualificationProvider.holdUntilClientCloses(responder)
          return
        }
        try await responder.write(line + "\n\n")
        guard text else { continue }
        texts += 1
        if claimPause(texts: texts, atNonText: false) {
          bytes.task.cancel()
          await QualificationProvider.holdUntilClientCloses(responder)
          return
        }
      }
      try await responder.finishEvents()
    } catch {
      bytes.task.cancel()
      await responder.close()
    }
  }

  /// Claims the armed pause once this stream has relayed some text: at its N-th text delta or
  /// before its first other chunk, whichever comes first.
  private func claimPause(texts: Int, atNonText: Bool) -> Bool {
    state.withLock { state in
      guard let limit = state.pauseAfterDeltas, texts >= 1, atNonText || texts >= limit else {
        return false
      }
      state.pauseAfterDeltas = nil
      state.counts.pausedStreams += 1
      return true
    }
  }

  /// A chunk whose only change is visible reply text: no tool call, reasoning or finish.
  static func isTextDelta(_ line: String) -> Bool {
    let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
    guard case .object(let chunk)? = try? JSONValue.parse(Data(payload.utf8)),
      case .array(let choices)? = chunk["choices"], choices.count == 1,
      case .object(let choice) = choices[0],
      choice["finish_reason"] == nil || choice["finish_reason"] == .null,
      case .object(let delta)? = choice["delta"],
      case .string(let content)? = delta["content"], !content.isEmpty
    else { return false }
    return delta.allSatisfy { key, value in
      ["content", "role"].contains(key) || value == .null || value == .string("")
    }
  }
}

/// Lets the server's handler reach the proxy created after the server binds.
private final class ProxyBox: Sendable {
  private let value = Mutex<RealModelProxy?>(nil)

  var proxy: RealModelProxy? {
    get { value.withLock { $0 } }
    set { value.withLock { $0 = newValue } }
  }
}
