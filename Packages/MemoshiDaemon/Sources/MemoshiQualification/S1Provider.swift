import Foundation
import MemoshiProtocol
import Synchronization

/// Counters are content-free except for synthetic turn tokens and conversation identities.
package struct S1ProviderSummary: Codable, Sendable {
  package var modelLists = 0
  package var completions = 0
  package var unauthorized = 0
  package var unexpected = 0
  package var contextIsolationFailures = 0
  package var requestSecretHits = 0
  package var maximumConcurrent = 0
  package var attempts: [String: Int] = [:]
  package var pacedDeltas: [String: Int] = [:]
}

/// Only the external model is scripted. PiAI performs actual authenticated HTTP/SSE requests;
/// PiDurable and the runtime remain real. This server cannot contact any upstream.
package final class S1Provider: Sendable {
  package static let modelID = "s1-scripted"
  private static let answerPadding = String(repeating: "stream-data-", count: 32)
  package let baseURL: String
  private let server: LoopbackHTTPServer
  private let box: S1ProviderBox
  private let state: Mutex<State>
  private let scanner: CanaryScanner

  private struct State {
    let bearer: Canary
    var owners: [String: String] = [:]
    var pauseOnce: Set<String> = []
    var held: Set<String> = []
    var released: Set<String> = []
    var active = 0
    var summary = S1ProviderSummary()
  }

  private init(
    server: LoopbackHTTPServer, bearer: Canary, scanner: CanaryScanner, box: S1ProviderBox
  ) {
    self.server = server
    self.box = box
    self.baseURL = "http://127.0.0.1:\(server.port)/v1"
    self.state = Mutex(State(bearer: bearer))
    self.scanner = scanner
  }

  package static func start(bearer: Canary) async throws -> S1Provider {
    let scanner = try CanaryScanner(canaries: [bearer])
    let box = S1ProviderBox()
    let server = try await LoopbackHTTPServer.start { request, response in
      await box.value?.handle(request, response)
    }
    let provider = S1Provider(server: server, bearer: bearer, scanner: scanner, box: box)
    box.value = provider
    return provider
  }

  package static func userText(_ token: String) -> String { "s1-token:" + token }
  package static func finalText(_ token: String) -> String {
    "S1 settled \(token). " + answerPadding
  }

  /// Every token belongs to exactly one conversation; a cross-conversation context is refused.
  package func register(_ token: String, conversation: ConversationID, pause: Bool) throws {
    try state.withLock { state in
      guard state.owners[token] == nil else { throw DriverError.invalid("duplicate S1 token") }
      state.owners[token] = conversation.rawValue
      if pause { state.pauseOnce.insert(token) }
    }
  }

  package func release(_ tokens: Set<String>) { state.withLock { $0.released.formUnion(tokens) } }
  package var held: Set<String> { state.withLock { $0.held } }
  package var summary: S1ProviderSummary { state.withLock { $0.summary } }

  package func waitUntilHeld(_ tokens: Set<String>, timeout: Duration = .seconds(30)) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      try Task.checkCancellation()
      if held.isSuperset(of: tokens) { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    throw DriverError.timeout("S1 provider held streams")
  }

  package func close() async {
    box.value = nil
    await server.close()
  }

  private func handle(_ request: LoopbackHTTPRequest, _ response: LoopbackHTTPResponder) async {
    let canary = state.withLock { $0.bearer }
    guard request.header("Authorization") == "Bearer " + canary.value else {
      state.withLock { $0.summary.unauthorized += 1 }
      await response.json(401, Data(#"{"error":{"message":"unauthorized"}}"#.utf8))
      return
    }
    var scan = CanaryScanReport()
    scanner.scanBytes(request.body, path: "provider-request", into: &scan)
    guard scan.hits.isEmpty else {
      state.withLock { $0.summary.requestSecretHits += scan.hits.count }
      await response.json(400, Data(#"{"error":{"message":"secret in model request"}}"#.utf8))
      return
    }
    switch (request.method, request.path) {
    case ("GET", "/v1/models"):
      state.withLock { $0.summary.modelLists += 1 }
      await response.json(
        200,
        Data(#"{"data":[{"id":"\#(Self.modelID)","context_window":32768,"max_tokens":256}]}"#.utf8))
    case ("POST", "/v1/chat/completions"):
      await complete(request, response)
    default:
      state.withLock { $0.summary.unexpected += 1 }
      await response.json(404, Data(#"{"error":{"message":"not found"}}"#.utf8))
    }
  }

  private func complete(_ request: LoopbackHTTPRequest, _ response: LoopbackHTTPResponder) async {
    guard let value = try? JSONValue.parse(request.body),
      value["model"]?.string == Self.modelID,
      value["tools"]?.array?.isEmpty != false,
      let messages = value["messages"]?.array
    else {
      state.withLock { $0.summary.unexpected += 1 }
      await response.json(400, Data(#"{"error":{"message":"unexpected completion shape"}}"#.utf8))
      return
    }
    let tokens = messages.filter { $0["role"]?.string == "user" }.compactMap { message in
      Self.token(in: Self.text(message["content"]))
    }
    guard let token = tokens.last else {
      state.withLock { $0.summary.unexpected += 1 }
      await response.json(400, Data(#"{"error":{"message":"missing synthetic turn token"}}"#.utf8))
      return
    }
    let admitted: (pause: Bool, bearer: String)? = state.withLock { state in
      guard let owner = state.owners[token], tokens.allSatisfy({ state.owners[$0] == owner }) else {
        state.summary.contextIsolationFailures += 1
        return nil
      }
      state.summary.completions += 1
      state.summary.attempts[token, default: 0] += 1
      state.active += 1
      state.summary.maximumConcurrent = max(state.summary.maximumConcurrent, state.active)
      return (state.pauseOnce.remove(token) != nil, state.bearer.value)
    }
    guard let admitted else {
      await response.json(
        400, Data(#"{"error":{"message":"conversation context isolation failed"}}"#.utf8))
      return
    }
    defer {
      state.withLock {
        $0.active -= 1
        $0.held.remove(token)
      }
    }
    do {
      try await response.beginEvents()
      // Deliberately hostile opaque provider metadata. It must never enter logs or storage;
      // only safe text is allowed through the production provider scrubber.
      try await response.write(try Self.chunk("S1 settled ", responseID: admitted.bearer))
      let suffix = Array(Self.finalText(token).dropFirst("S1 settled ".count))
      var sent = 0
      if admitted.pause {
        state.withLock { _ = $0.held.insert(token) }
        let limit = ContinuousClock.now + .seconds(120)
        var nextDelta = ContinuousClock.now + .milliseconds(20)
        while !state.withLock({ $0.released.contains(token) }) {
          try Task.checkCancellation()
          guard response.channel.isActive else {
            throw DriverError.childEnded("S1 streaming HTTP peer")
          }
          guard ContinuousClock.now < limit else {
            throw DriverError.timeout("S1 held provider stream")
          }
          if sent < suffix.count, ContinuousClock.now >= nextDelta {
            try await response.write(
              try Self.chunk(String(suffix[sent]), responseID: admitted.bearer))
            sent += 1
            state.withLock { $0.summary.pacedDeltas[token, default: 0] += 1 }
            nextDelta = ContinuousClock.now + .milliseconds(20)
          }
          try await Task.sleep(for: .milliseconds(5))
        }
      }
      try await response.write(
        try Self.chunk(String(suffix.dropFirst(sent)), responseID: admitted.bearer))
      try await response.write(
        try Self.chunk(nil, responseID: admitted.bearer, finished: true) + "data: [DONE]\n\n")
      try await response.finishEvents()
    } catch {
      await response.close()
    }
  }

  package static func token(in text: String) -> String? {
    guard text.hasPrefix("s1-token:") else { return nil }
    let token = String(text.dropFirst("s1-token:".count))
    guard !token.isEmpty,
      token.utf8.allSatisfy({ byte in
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
          || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
          || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || byte == UInt8(ascii: "-")
      })
    else { return nil }
    return token
  }

  private static func text(_ content: JSONValue?) -> String {
    if let text = content?.string { return text }
    return content?.array?.compactMap { $0["text"]?.string }.joined() ?? ""
  }

  private static func chunk(_ text: String?, responseID: String, finished: Bool = false) throws
    -> String
  {
    let delta: JSONValue = text.map { ["content": .string($0)] } ?? [:]
    let value: JSONValue = [
      "id": .string(responseID), "object": "chat.completion.chunk", "created": 1,
      "model": .string(modelID), "system_fingerprint": .string(responseID),
      "choices": [["index": 0, "delta": delta, "finish_reason": finished ? "stop" : .null]],
    ]
    return "data: "
      + String(decoding: try ProtocolCoding.makeEncoder().encode(value), as: UTF8.self)
      + "\n\n"
  }
}

private final class S1ProviderBox: Sendable {
  private let storage = Mutex<S1Provider?>(nil)
  var value: S1Provider? {
    get { storage.withLock { $0 } }
    set { storage.withLock { $0 = newValue } }
  }
}
