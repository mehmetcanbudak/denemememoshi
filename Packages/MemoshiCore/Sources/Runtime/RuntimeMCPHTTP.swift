import CryptoKit
import Foundation
import MemoshiProtocol
import PiAI
import PiCore
import PiMCP
import Synchronization

/// Safe host errors; raw OAuth/HTTP errors and server response bodies never cross this boundary.
public enum RuntimeMCPError: Error, Equatable, Sendable {
  case invalidConfiguration
  case credentialUnavailable
  case authorizationRequired
  case authorizationFailed
  case busy
  case cancelled
  case unavailable
  case toolTableChanged
}

/// Explicit chosen origins and a live host authority check for every HTTP attempt, including
/// OAuth metadata, registration and token requests. This is a host-networking seam, not a
/// claim of the sandbox computer gateway's method/body inspection or TLS termination.
public struct RuntimeMCPHTTPNetwork: Sendable {
  private let origins: Set<MCPHTTPOrigin>
  private let allowLoopbackHTTP: Bool
  private let authorize: @Sendable (URL) async throws -> Bool
  private let transport: RedirectRefusingFetch

  /// Plain HTTP is available only for an explicitly opted-in, literal-loopback reference peer.
  /// Redirects are always refused, including same-origin ones, before credentials can move.
  public init(
    origins: [URL], allowLoopbackHTTP: Bool = false,
    authorize: @escaping @Sendable (URL) async throws -> Bool
  ) throws {
    guard !origins.isEmpty else { throw RuntimeMCPError.invalidConfiguration }
    let parsed = try origins.map { url -> MCPHTTPOrigin in
      guard let origin = MCPHTTPOrigin(url),
        Self.secure(url, allowLoopbackHTTP: allowLoopbackHTTP)
      else { throw RuntimeMCPError.invalidConfiguration }
      return origin
    }
    self.origins = Set(parsed)
    self.allowLoopbackHTTP = allowLoopbackHTTP
    self.authorize = authorize
    self.transport = RedirectRefusingFetch()
  }

  func validate(_ url: URL) throws {
    guard Self.secure(url, allowLoopbackHTTP: allowLoopbackHTTP),
      let origin = MCPHTTPOrigin(url), origins.contains(origin)
    else { throw RuntimeMCPError.invalidConfiguration }
  }

  var fetch: McpFetch { { request, signal in try await send(request, signal: signal) } }

  func send(
    _ request: URLRequest, signal: AbortSignal?, leaseExpires: ContinuousClock.Instant? = nil,
    toolTableTrust: RuntimeMCPToolTableTrust? = nil
  ) async throws -> McpHTTPResponse {
    try Task.checkCancellation()
    try signal?.throwIfAborted()
    guard let url = request.url else { throw RuntimeMCPError.invalidConfiguration }
    try validate(url)
    guard try await authorize(url) else { throw RuntimeMCPError.unavailable }
    try Task.checkCancellation()
    try signal?.throwIfAborted()
    try RuntimeMCPRequestContext.current?.signal.throwIfAborted()
    if let toolTableTrust, !toolTableTrust.isTrusted {
      throw RuntimeMCPError.toolTableChanged
    }
    if let leaseExpires, ContinuousClock.now >= leaseExpires {
      throw RuntimeMCPError.credentialUnavailable
    }
    let abort = AbortController()
    let combined = AbortSignal.any(
      [signal, RuntimeMCPRequestContext.current?.signal, abort.signal].compactMap { $0 })
    let response = try await transport.fetch(
      PiAI.HTTPRequest(
        url: url, method: request.httpMethod ?? "GET", headers: request.allHTTPHeaderFields ?? [:],
        body: request.httpBody, timeoutMs: 30_000), combined)
    let pair = AsyncThrowingStream<Data, any Error>.makeStream()
    let pump = Task {
      do {
        for try await chunk in response.body { pair.continuation.yield(chunk) }
        pair.continuation.finish()
      } catch { pair.continuation.finish(throwing: RuntimeMCPError.unavailable) }
    }
    pair.continuation.onTermination = { termination in
      if case .cancelled = termination {
        abort.abort()
        pump.cancel()
      }
    }
    return McpHTTPResponse(
      status: response.status, headers: response.headers, body: pair.stream,
      cancel: {
        abort.abort()
        pump.cancel()
      })
  }

  private static func secure(_ url: URL, allowLoopbackHTTP: Bool) -> Bool {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      url.host?.isEmpty == false, url.user == nil, url.password == nil, url.fragment == nil
    else { return false }
    return scheme == "https"
      || (allowLoopbackHTTP
        && ["127.0.0.1", "[::1]", "::1"].contains(url.host?.lowercased() ?? ""))
  }
}

private struct MCPHTTPOrigin: Hashable, Sendable {
  let scheme: String
  let host: String
  let port: Int

  init?(_ url: URL) {
    guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
      let host = url.host?.lowercased(), !host.isEmpty,
      url.user == nil, url.password == nil
    else { return nil }
    self.scheme = scheme
    self.host = host
    self.port = url.port ?? (scheme == "https" ? 443 : 80)
  }
}

/// An HTTP challenge contains no access token, only its digest for concurrent-rotation checks.
/// Native authorization UI is never opened automatically in response to a model tool call.
public struct RuntimeMCPOAuthChallenge: Sendable {
  /// The exact configured MCP endpoint whose request was challenged, not a discovered redirect.
  public let serverURL: URL
  /// The HTTP response status supplied to the host's refresh decision.
  public let status: Int
  /// The server's untrusted challenge header, for host parsing rather than user/model display.
  public let wwwAuthenticate: String?
  /// The rejected access token's SHA-256 hex digest; a newer stored token need not rotate again.
  public let rejectedTokenSHA256: String?
}

/// The existing purpose-bound app broker convention, with host-only refresh and scrubbing.
/// Only short-lived access tokens are released; the host retains refresh tokens, PKCE state,
/// client secrets and historical token variants needed to scrub later connector output.
public struct RuntimeMCPCredentialSource: Sendable {
  /// An opaque broker reference, requested with the connector-specific `mcp:<name>` purpose.
  public let secretRef: String
  let resolve: RuntimeCredentialResolver
  let refresh: @Sendable (RuntimeMCPOAuthChallenge) async throws -> Void
  let redact: @Sendable (MemoshiProtocol.JSONValue) async throws -> MemoshiProtocol.JSONValue

  /// Retains host callbacks without resolving or persisting a credential. `resolve` must
  /// release only an access token with `ttlMs` in 1...60,000; dispatch enforces that lease.
  /// `refresh` must keep OAuth state and attended sign-in in the host. `redact` processes
  /// tool metadata/results and must throw rather than return unsafe raw output on failure.
  /// JSON redaction does not guarantee recognition of arbitrary encodings or unknown secrets.
  public init(
    secretRef: String, resolve: @escaping RuntimeCredentialResolver,
    refresh: @escaping @Sendable (RuntimeMCPOAuthChallenge) async throws -> Void,
    redact:
      @escaping @Sendable (MemoshiProtocol.JSONValue) async throws -> MemoshiProtocol.JSONValue
  ) {
    self.secretRef = secretRef
    self.resolve = resolve
    self.refresh = refresh
    self.redact = redact
  }
}

/// One reviewed, remote Streamable HTTP MCP connector. Explicit trusted composition connects
/// and reviews it lazily on first conversation use, never merely by creating the runtime. It
/// is available on macOS and iOS, never a model-selectable endpoint or production configuration.
public struct RuntimeMCPHTTPServerConfiguration: Sendable {
  /// The reviewed connector namespace used in tool names and credential purpose binding.
  public var name: String
  /// The exact MCP HTTP endpoint, validated against `network` before connector use.
  public var url: URL
  /// The host-selected origins and live authority check for MCP and OAuth HTTP attempts.
  public var network: RuntimeMCPHTTPNetwork
  /// The host's leased access-token and redaction seam, or nil for an unauthenticated connector.
  public var credentials: RuntimeMCPCredentialSource?
  /// SHA-256 of the canonical JSON array of all server tool objects sorted by `name`.
  /// The host reviews the table outside a model run; first-use and reconnect changes fail closed.
  public var toolTableSHA256: String
  /// Reviewed policies keyed by remote tool name; unlisted server tools are not registered.
  public var tools: [String: RuntimeExtensionToolPolicy]

  /// Records explicit host composition without connecting, signing in or reading credentials.
  /// Configuration and the full tool-table digest are checked when the connector is opened;
  /// this value alone neither enables production tools nor grants a model endpoint choice.
  public init(
    name: String, url: URL, network: RuntimeMCPHTTPNetwork,
    credentials: RuntimeMCPCredentialSource? = nil, toolTableSHA256: String,
    tools: [String: RuntimeExtensionToolPolicy]
  ) {
    self.name = name
    self.url = url
    self.network = network
    self.credentials = credentials
    self.toolTableSHA256 = toolTableSHA256
    self.tools = tools
  }
}

/// Task-local context survives PiMCP's request-send task. The pinned transport passes fetch
/// only its session signal, so the host carries tool cancellation and the exact table review
/// through credential resolution, authorization refresh and network-authority awaits.
struct RuntimeMCPRequestContext: Sendable {
  let signal: AbortSignal
  let toolTableTrust: RuntimeMCPToolTableTrust?
  @TaskLocal static var current: RuntimeMCPRequestContext?
}

/// Pi's token adapter never persists tokens. Every SDK request obtains a fresh app release;
/// its HTTP dispatch rechecks the exact token's monotonic lease, chosen origin and tool review.
actor RuntimeMCPAuthAdapter: AuthProvider {
  private let server: RuntimeMCPHTTPServerConfiguration
  private let credentials: ProviderCredentials
  private var leases: [String: ContinuousClock.Instant] = [:]

  init(server: RuntimeMCPHTTPServerConfiguration, credentials: ProviderCredentials) {
    self.server = server
    self.credentials = credentials
  }

  func token() async throws -> JSONString? {
    try await releasedToken().map(JSONString.init)
  }

  /// Our releases are checked printable ASCII, so they are always native strings.
  private func releasedToken() async throws -> String? {
    guard let source = server.credentials else { return nil }
    let signal = RuntimeMCPRequestContext.current?.signal
    do {
      try Task.checkCancellation()
      try signal?.throwIfAborted()
      let release = try await PiAI.withAbortSignal(signal) {
        try await source.resolve(
          HostKeychainGetParams(secretRef: source.secretRef, purpose: "mcp:" + self.server.name))
      }
      let releasedAt = ContinuousClock.now
      // Protect even a malformed or late release before considering whether it is usable.
      await credentials.registerRedaction(release.value)
      try Task.checkCancellation()
      try signal?.throwIfAborted()
      guard release.ttlMs > 0, release.ttlMs <= 60_000,
        !release.value.isEmpty, release.value.utf8.count <= 16 * 1024,
        !release.value.utf8.contains(where: { $0 < 0x21 || $0 == 0x7f })
      else { throw RuntimeMCPError.credentialUnavailable }
      let now = ContinuousClock.now
      let expires = releasedAt.advanced(by: .milliseconds(release.ttlMs))
      guard now < expires else { throw RuntimeMCPError.credentialUnavailable }
      leases = leases.filter { $0.value > now }
      leases[mcpTokenDigest(release.value)] = expires
      return release.value
    } catch {
      if Task.isCancelled || signal?.isAborted == true { throw RuntimeMCPError.cancelled }
      throw RuntimeMCPError.credentialUnavailable
    }
  }

  func onUnauthorized(_ context: UnauthorizedContext) async throws {
    guard let source = server.credentials, context.serverUrl == server.url else {
      throw RuntimeMCPError.credentialUnavailable
    }
    let signal = RuntimeMCPRequestContext.current?.signal
    do {
      try await PiAI.withAbortSignal(signal) {
        try await source.refresh(
          RuntimeMCPOAuthChallenge(
            serverURL: self.server.url, status: context.response.status,
            wwwAuthenticate: context.response["www-authenticate"],
            rejectedTokenSHA256: context.token?.nativeString.map(mcpTokenDigest)))
      }
      try signal?.throwIfAborted()
      try Task.checkCancellation()
    } catch {
      if Task.isCancelled || signal?.isAborted == true { throw RuntimeMCPError.cancelled }
      throw RuntimeMCPError.authorizationRequired
    }
  }

  func fetch(_ original: URLRequest, signal: AbortSignal?) async throws -> McpHTTPResponse {
    var request = original
    guard request.url == server.url else { throw RuntimeMCPError.invalidConfiguration }
    // Control traffic may finish after a review is revoked, but no old tool binding may
    // dispatch, including an OAuth-challenged request's second HTTP attempt.
    let dispatchTrust =
      request.httpMethod == "DELETE" ? nil : RuntimeMCPRequestContext.current?.toolTableTrust
    guard dispatchTrust?.isTrusted != false else { throw RuntimeMCPError.toolTableChanged }
    // The SDK's best-effort DELETE reuses lastToken. Teardown gets its own current release,
    // never a cached or expired token; a revoked broker therefore cannot send that DELETE.
    if request.httpMethod == "DELETE", let token = try await releasedToken() {
      request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    }
    var leaseExpires: ContinuousClock.Instant?
    if server.credentials != nil {
      guard let header = request.value(forHTTPHeaderField: "Authorization"),
        header.hasPrefix("Bearer "),
        let expires = leases[mcpTokenDigest(String(header.dropFirst(7)))],
        ContinuousClock.now < expires
      else { throw RuntimeMCPError.credentialUnavailable }
      leaseExpires = expires
    } else if request.value(forHTTPHeaderField: "Authorization") != nil {
      throw RuntimeMCPError.credentialUnavailable
    }
    try RuntimeMCPRequestContext.current?.signal.throwIfAborted()
    return try await server.network.send(
      request, signal: signal, leaseExpires: leaseExpires, toolTableTrust: dispatchTrust)
  }
}

final class RuntimeMCPToolTableTrust: Sendable {
  private let trusted = Mutex(true)
  func revoke() { trusted.withLock { $0 = false } }
  var isTrusted: Bool { trusted.withLock { $0 } }
}

/// Trusted bridge-only receipt, never copied from an MCP response's `_meta` or content.
/// Mandatory afterTool merges it into policy.redacted and removes it before persistence.
/// The count is changed result envelopes, not secret occurrences inside that envelope.
enum RuntimeMCPHostRedaction {
  static let detailsKey: PiCore.JSONString = "memoshi.hostRedaction"
  static var details: PiCore.JSONValue {
    .object([
      detailsKey: .object(["count": .number(1), "kinds": .array([.string("mcp_host_secret")])])
    ])
  }

  /// Reserved host metadata is discarded recursively before any trusted receipt is created.
  /// Plain text is untrusted content, never interpreted as an audit receipt.
  static func removingServerMarkers(_ value: PiCore.JSONValue) -> PiCore.JSONValue {
    switch value {
    case .object(let object):
      var cleaned = object
      for (key, child) in object {
        if key.nativeString?.hasPrefix("memoshi.") == true {
          cleaned.removeValue(forKey: key)
        } else {
          let safe = removingServerMarkers(child)
          if safe != child { cleaned[key] = safe }
        }
      }
      return .object(cleaned)
    case .array(let array):
      var cleaned = array
      for index in array.indices {
        let safe = removingServerMarkers(array[index])
        if safe != array[index] { cleaned[index] = safe }
      }
      return .array(cleaned)
    default:
      return value
    }
  }
}

func mcpTokenDigest(_ value: String) -> String {
  var value = value
  let digest = value.withUTF8 { bytes in
    var hash = SHA256()
    hash.update(bufferPointer: UnsafeRawBufferPointer(bytes))
    return hash.finalize()
  }
  let digits: StaticString = "0123456789abcdef"
  return digits.withUTF8Buffer { alphabet in
    String(unsafeUninitializedCapacity: 64) { output in
      var index = 0
      for byte in digest {
        output[index] = alphabet[Int(byte >> 4)]
        output[index + 1] = alphabet[Int(byte & 0x0f)]
        index += 2
      }
      return index
    }
  }
}
