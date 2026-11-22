import Foundation

/// Main-actor ownership matches the WebKit controller. Admission happens synchronously, before any
/// send Task can yield, so an immediately following abort cannot race an unregistered request.
@MainActor
final class PyodideNetworkSession {
  private struct Binding: Equatable {
    let cellID: UUID
    let generation: UUID
  }

  private struct Pending {
    let token: UUID
    let task: Task<PyodideHTTPResponse, any Error>
  }

  private let transport: (any PyodideNetworkTransport)?
  private var binding: Binding?
  private var pending: [String: Pending] = [:]
  private var draining: (id: UUID, task: Task<Void, Never>)?

  init(transport: (any PyodideNetworkTransport)?) {
    self.transport = transport
  }

  var isConfigured: Bool { transport != nil }

  func isActive(cellID: UUID, generation: UUID) -> Bool {
    binding == Binding(cellID: cellID, generation: generation)
  }

  func begin(cellID: UUID, generation: UUID) throws {
    guard binding == nil, pending.isEmpty, draining == nil else { throw PyodideFailure.busy }
    binding = Binding(cellID: cellID, generation: generation)
  }

  func send(
    _ request: PyodideHTTPRequest, requestID: String, cellID: UUID, generation: UUID
  ) throws -> Task<PyodideHTTPResponse, any Error> {
    let current = Binding(cellID: cellID, generation: generation)
    guard binding == current else { throw PyodideFailure.cancelled }
    guard !requestID.isEmpty, requestID.utf8.count <= 64, pending[requestID] == nil else {
      throw PyodideFailure.invalidRequest
    }
    try PyodideHTTPLimits.validate(request)
    guard pending.count < 8 else { throw PyodideFailure.busy }
    guard let transport else { throw PyodideFailure.networkFailed }
    let token = UUID()
    let task = Task { @MainActor in
      defer {
        if self.pending[requestID]?.token == token {
          self.pending.removeValue(forKey: requestID)
        }
      }
      do {
        try Task.checkCancellation()
        let response = try await transport.send(request, cellID: cellID)
        guard self.binding == current, !Task.isCancelled else { throw PyodideFailure.cancelled }
        return try PyodideHTTPLimits.checked(response, method: request.method)
      } catch {
        guard self.binding == current, !Task.isCancelled else { throw PyodideFailure.cancelled }
        throw PyodideFailure.networkFailed
      }
    }
    pending[requestID] = Pending(token: token, task: task)
    return task
  }

  func cancel(requestID: String, cellID: UUID, generation: UUID) throws -> Task<Void, Never> {
    guard binding == Binding(cellID: cellID, generation: generation) else {
      throw PyodideFailure.cancelled
    }
    let task = pending[requestID]?.task
    task?.cancel()
    return Task { _ = await task?.result }
  }

  /// Invalidates admission before cancelling anything. Awaiting the returned task includes the
  /// transport's actual cancellation completion; a late successful transport result cannot escape.
  func end() -> Task<Void, Never> {
    binding = nil
    if let draining { return draining.task }
    let tasks = pending.values.map(\.task)
    for task in tasks { task.cancel() }
    let id = UUID()
    let task = Task { @MainActor in
      for task in tasks { _ = await task.result }
      if self.draining?.id == id { self.draining = nil }
    }
    draining = (id, task)
    return task
  }
}

enum PyodideHTTPLimits {
  static let urlBytes = 8_192
  static let headerCount = 64
  static let headerBytes = 64 * 1_024
  static let requestBytes = 1_024 * 1_024
  static let responseBytes = 16 * 1_024 * 1_024
  // Base64 request body, JSON-escaped bounded headers and URL, plus envelope fields.
  static let messageBytes = 2 * 1_024 * 1_024
  private static let transportHeaders: Set<String> = [
    "proxy-authorization", "proxy-authenticate", "proxy-connection", "host", "content-length",
    "connection", "keep-alive", "transfer-encoding", "upgrade", "te", "trailer",
  ]
  private static let hiddenResponseHeaders: Set<String> = [
    "set-cookie", "set-cookie2", "proxy-authorization", "proxy-authenticate", "proxy-connection",
    "connection", "keep-alive", "transfer-encoding", "upgrade", "te", "trailer",
  ]

  static func validate(_ request: PyodideHTTPRequest) throws {
    let method = request.method.uppercased()
    guard !request.url.isEmpty, request.url.utf8.count <= urlBytes,
      !request.url.utf8.contains(where: { $0 <= 32 || $0 == 127 }),
      let url = URLComponents(string: request.url),
      url.scheme == "https" || url.scheme == "http",
      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
      url.fragment == nil, url.url != nil,
      token(request.method),
      !["CONNECT", "TRACE", "TRACK"].contains(method),
      request.body.count <= requestBytes,
      !["GET", "HEAD"].contains(method) || request.body.isEmpty,
      validHeaders(request.headers),
      !request.headers.keys.contains(where: { transportHeaders.contains($0.lowercased()) })
    else { throw PyodideFailure.invalidRequest }
  }

  static func checked(_ response: PyodideHTTPResponse, method: String) throws -> PyodideHTTPResponse
  {
    let bodyless =
      method.uppercased() == "HEAD" || response.status == 204 || response.status == 205
      || response.status == 304
    guard (200...599).contains(response.status), response.body.count <= responseBytes,
      validHeaders(response.headers),
      !bodyless || response.body.isEmpty
    else { throw PyodideFailure.networkFailed }
    // Bodyless replies may describe an encoded representation without carrying compressed bytes.
    // Actual entities must use the identity encoding promised by this bounded fetch adapter.
    if !bodyless,
      let encoding = response.headers.first(where: { $0.key.lowercased() == "content-encoding" })
    {
      guard encoding.value.trimmingCharacters(in: .whitespaces).lowercased() == "identity" else {
        throw PyodideFailure.networkFailed
      }
    }
    var headers = response.headers
    for name in response.headers.keys where hiddenResponseHeaders.contains(name.lowercased()) {
      headers.removeValue(forKey: name)
    }
    return .init(status: response.status, headers: headers, body: response.body)
  }

  private static func validHeaders(_ headers: [String: String]) -> Bool {
    guard headers.count <= headerCount else { return false }
    var bytes = 0
    var names: Set<String> = []
    for (name, value) in headers {
      bytes += name.utf8.count + value.utf8.count
      guard bytes <= headerBytes, token(name), names.insert(name.lowercased()).inserted,
        !value.utf8.contains(where: { $0 < 32 || $0 == 127 })
      else { return false }
    }
    return true
  }

  private static func token(_ value: String) -> Bool {
    !value.isEmpty
      && value.utf8.allSatisfy {
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
          || "!#$%&'*+-.^_`|~".utf8.contains($0)
      }
  }
}
