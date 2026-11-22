import Foundation
import MemoshiProtocol
import PiAI
import PiCore
import PiMCP

/// Native app-owned OAuth for one exact MCP endpoint/reference. Both platforms supply a native
/// authentication-session callback URL; neither a browser nor a callback listener starts by
/// itself. The daemon receives only the existing broker's bounded access-token result.
///
/// One native host owns this item. The pinned SDK's MCP Keychain adapter has no cross-process
/// refresh lock; do not share this host's item with another process or independent host.
public actor RuntimeMCPOAuthHost {
  /// The connector namespace required in every release's `mcp:<serverName>` purpose.
  public nonisolated let serverName: String
  /// The exact endpoint bound to the protected OAuth state and accepted refresh challenges.
  public nonisolated let serverURL: URL
  /// The opaque `kc_` reference required for releases; no token value is exposed by this property.
  public nonisolated let secretRef: String
  private let redirectURL: URL
  private let clientID: String?
  private let clientMetadataDocumentURL: URL?
  private let scope: String?
  private let network: RuntimeMCPHTTPNetwork
  private let store: any McpOAuthStateStore
  private let removeState: @Sendable () async throws -> Void
  private let authorizeRelease: @Sendable (HostKeychainGetParams) async throws -> Bool
  private let secrets: MCPHostSecretRegistry
  private var operation: (id: UUID, task: Task<Void, any Error>)?
  private var revoking = false
  private var credentialGeneration: UInt64 = 0
  private var signInAbort: AbortController?
  private var closed = false

  /// Uses the app's data-protection Keychain, AfterFirstUnlockThisDeviceOnly and no
  /// synchronizable fallback. State and historical redaction values share one atomic item.
  /// An entitled app access group is required; the helper must never own that entitlement.
  /// An optional client metadata URL must already be published with these exact redirect URIs;
  /// configuring a URL neither publishes it nor installs an associated-domain entitlement.
  public init(
    serverName: String, serverURL: URL, redirectURL: URL, secretRef: String,
    clientID: String? = nil, scope: String? = nil, clientMetadataDocumentURL: URL? = nil,
    accessGroup: String,
    network: RuntimeMCPHTTPNetwork,
    authorizeRelease: @escaping @Sendable (HostKeychainGetParams) async throws -> Bool
  ) throws {
    guard !accessGroup.isEmpty else { throw RuntimeMCPError.invalidConfiguration }
    try Self.validate(serverName, serverURL, redirectURL, secretRef, network)
    try Self.validateDocument(clientMetadataDocumentURL)
    let keychain = RuntimeMCPKeychain(
      service: "com.mehmetcanbudak.memoshi.mcp." + secretRef,
      account: serverURL.absoluteString, accessGroup: accessGroup)
    let secrets = MCPHostSecretRegistry()
    self.serverName = serverName
    self.serverURL = serverURL
    self.redirectURL = redirectURL
    self.secretRef = secretRef
    self.clientID = clientID
    self.clientMetadataDocumentURL = clientMetadataDocumentURL
    self.scope = scope
    self.network = network
    self.authorizeRelease = authorizeRelease
    self.secrets = secrets
    self.store = ProtectedMCPOAuthStore(storage: keychain.storage, secrets: secrets)
    self.removeState = keychain.storage.remove
  }

  /// An internal opaque storage seam for the owned encrypted reference fixture. Product
  /// composition cannot substitute memory/plaintext state or fall back when Keychain fails.
  init(
    serverName: String, serverURL: URL, redirectURL: URL, secretRef: String,
    clientID: String? = nil, scope: String? = nil, clientMetadataDocumentURL: URL? = nil,
    network: RuntimeMCPHTTPNetwork,
    storage: RuntimeMCPOAuthStorage,
    authorizeRelease: @escaping @Sendable (HostKeychainGetParams) async throws -> Bool
  ) throws {
    try Self.validate(serverName, serverURL, redirectURL, secretRef, network)
    try Self.validateDocument(clientMetadataDocumentURL)
    let secrets = MCPHostSecretRegistry()
    self.serverName = serverName
    self.serverURL = serverURL
    self.redirectURL = redirectURL
    self.secretRef = secretRef
    self.clientID = clientID
    self.clientMetadataDocumentURL = clientMetadataDocumentURL
    self.scope = scope
    self.network = network
    self.authorizeRelease = authorizeRelease
    self.secrets = secrets
    self.store = ProtectedMCPOAuthStore(storage: storage, secrets: secrets)
    self.removeState = storage.remove
  }

  /// Trusted composition supplies this source directly or routes `release` through the
  /// existing authenticated host.keychain.get broker. No new RPC or production opt-in exists.
  /// Its redactor loads protected token history after reopen and scrubs registered values,
  /// supported encodings and credential-like JSON. It is not arbitrary-transform detection
  /// or a guarantee that all untrusted server content is safe.
  public nonisolated func credentialSource() -> RuntimeMCPCredentialSource {
    RuntimeMCPCredentialSource(
      secretRef: secretRef, resolve: { try await self.release($0) },
      refresh: { try await self.refresh($0) }, redact: { try await self.redact($0) })
  }

  /// Explicit attended sign-in. The native interaction opens the provided URL and returns
  /// its callback; the host checks the exact redirect route, state, PKCE and issuer before
  /// redeeming the code. Browser URLs/codes never enter persisted runtime/model state.
  public func signIn(
    interact: @escaping @Sendable (URL) async throws -> URL
  ) async throws {
    guard !closed, !revoking else { throw RuntimeMCPError.cancelled }
    guard operation == nil else { throw RuntimeMCPError.busy }
    credentialGeneration &+= 1
    let abort = AbortController()
    signInAbort = abort
    defer { signInAbort = nil }
    try await withTaskCancellationHandler {
      try await exclusive {
        try await self.performSignIn(interact: interact, signal: abort.signal)
      }
    } onCancel: {
      abort.abort()
    }
  }

  /// Requests cancellation of the current attended sign-in, if any; it neither signs out nor
  /// cancels an admitted refresh rotation. The native interaction still owns its UI lifetime.
  public func cancelSignIn() { signInAbort?.abort() }

  /// Purpose/reference and current native authority are checked before each release. Refresh
  /// rotation is single-flight and saved before any access token is returned. A cancelled
  /// caller never receives a late token; an admitted refresh is allowed to finish saving.
  /// The returned `ttlMs` is at most 60,000 milliseconds and never exceeds known token lifetime.
  public func release(_ params: HostKeychainGetParams) async throws -> HostKeychainGetResult {
    do {
      try Task.checkCancellation()
      guard !closed, !revoking, params.secretRef == secretRef,
        params.purpose == "mcp:" + serverName, try await authorizeRelease(params)
      else { throw RuntimeMCPError.credentialUnavailable }
      if let operation { try await operation.task.value }
      guard !closed, !revoking else { throw RuntimeMCPError.credentialUnavailable }
      var generation = credentialGeneration
      var state = try await load()
      if let expiry = state.tokensExpireAt, expiry <= Double(unixMilliseconds()) {
        try await refreshStoredCredentials(challenge: nil)
        state = try await load()
        generation = credentialGeneration
      }
      try Task.checkCancellation()
      guard !closed, !revoking, try await authorizeRelease(params),
        let tokens = state.tokens, tokens.token_type.nativeString?.lowercased() == "bearer",
        let access = tokens.access_token.nativeString,
        !access.isEmpty, access.utf8.count <= 16 * 1024,
        !access.utf8.contains(where: { $0 < 0x21 || $0 == 0x7f })
      else { throw RuntimeMCPError.credentialUnavailable }
      let remaining = state.tokensExpireAt.map { $0 - Double(unixMilliseconds()) } ?? 60_000
      guard !closed, !revoking, generation == credentialGeneration,
        remaining.isFinite, remaining >= 1
      else { throw RuntimeMCPError.credentialUnavailable }
      return HostKeychainGetResult(value: access, ttlMs: Int64(min(60_000, remaining)))
    } catch {
      if Task.isCancelled { throw RuntimeMCPError.cancelled }
      throw RuntimeMCPError.credentialUnavailable
    }
  }

  /// Deletes this host's local protected OAuth item after admitted writes settle, preventing
  /// refresh from recreating it. This does not revoke the grant at the remote server.
  public func signOut() async throws {
    guard !closed, !revoking else { throw RuntimeMCPError.credentialUnavailable }
    revoking = true
    credentialGeneration &+= 1
    defer { revoking = false }
    signInAbort?.abort()
    if let operation { _ = await operation.task.result }
    do { try await removeState() } catch { throw RuntimeMCPError.credentialUnavailable }
  }

  /// Cancels attended interaction, then waits for admitted writes/refresh rotation. It never
  /// cancels a rotating refresh after the server may already have consumed its predecessor.
  public func close() async {
    closed = true
    revoking = true
    credentialGeneration &+= 1
    signInAbort?.abort()
    if let operation { _ = await operation.task.result }
  }

  private func performSignIn(
    interact: @escaping @Sendable (URL) async throws -> URL, signal: AbortSignal
  ) async throws {
    let capture = MCPAuthorizationCapture()
    let provider = provider(capture)
    do {
      var state = try await load()
      state.oauthState = nil
      state.codeVerifier = nil
      try await store.save(state)
      let first = try await authorizeMcp(
        provider,
        options: OAuthFlowOptions(
          serverUrl: serverURL, scope: scope.map(JSONString.init), fetch: network.fetch,
          signal: signal,
          skipRefresh: true))
      guard first == .redirect, let authorization = await capture.url else {
        throw RuntimeMCPError.authorizationFailed
      }
      try network.validate(authorization)
      let stateValue = try await provider.state()
      let receiver = OAuthCallbackReceiver(redirectUrl: redirectURL)
      let pending = try await receiver.prepareCallback(state: stateValue, path: redirectURL.path)
      do {
        let callbackURL = try await PiAI.withAbortSignal(signal) {
          try await interact(authorization)
        }
        guard Self.sameRedirect(callbackURL, redirectURL) else {
          throw RuntimeMCPError.authorizationFailed
        }
        let response = await receiver.receive(callbackURL)
        guard response.page.ok else { throw RuntimeMCPError.authorizationFailed }
        let callback = try await pending.value()
        await secrets.register(callback.code)
        try signal.throwIfAborted()
        let result = try await authorizeMcp(
          provider,
          options: OAuthFlowOptions(
            serverUrl: serverURL, authorizationCode: callback.code, iss: callback.iss,
            scope: scope.map(JSONString.init),
            fetch: network.fetch, signal: signal))
        guard result == .authorized else { throw RuntimeMCPError.authorizationFailed }
        await receiver.close()
      } catch {
        await receiver.close()
        throw error
      }
      try await clearPendingAuthorization()
    } catch {
      // Cleanup is not cancelled with the browser task and never erases a prior token grant.
      let cleanup = Task { try await self.clearPendingAuthorization() }
      _ = await cleanup.result
      if signal.isAborted || Task.isCancelled { throw RuntimeMCPError.cancelled }
      throw RuntimeMCPError.authorizationFailed
    }
  }

  private func refresh(_ challenge: RuntimeMCPOAuthChallenge) async throws {
    guard !closed, !revoking, challenge.serverURL == serverURL,
      [401, 403].contains(challenge.status)
    else {
      throw RuntimeMCPError.credentialUnavailable
    }
    let params = HostKeychainGetParams(secretRef: secretRef, purpose: "mcp:" + serverName)
    guard try await authorizeRelease(params) else { throw RuntimeMCPError.credentialUnavailable }
    try await refreshStoredCredentials(challenge: challenge)
  }

  private func refreshStoredCredentials(challenge: RuntimeMCPOAuthChallenge?) async throws {
    if let operation {
      try await operation.task.value
      return
    }
    guard !closed, !revoking else { throw RuntimeMCPError.credentialUnavailable }
    credentialGeneration &+= 1
    // Refresh is host-owned, not caller-owned: preserve rotated tokens even if the tool stops.
    try await exclusive(cancelWithCaller: false) {
      let stored = try await self.load()
      let parsed = parseWwwAuthenticate(challenge?.wwwAuthenticate)
      guard parsed.error != "insufficient_scope" else {
        throw RuntimeMCPError.authorizationRequired
      }
      if let rejected = challenge?.rejectedTokenSHA256,
        let current = stored.tokens?.access_token,
        current.nativeString.map(mcpTokenDigest) != rejected
      {
        return
      }
      guard stored.tokens?.refresh_token?.isEmpty == false else {
        throw RuntimeMCPError.authorizationRequired
      }
      let capture = MCPAuthorizationCapture()
      let provider = await self.provider(capture)
      let result = try await authorizeMcp(
        provider,
        options: OAuthFlowOptions(
          serverUrl: self.serverURL, scope: self.scope.map(JSONString.init),
          resourceMetadataUrl: parsed.resourceMetadataUrl,
          fetch: self.network.fetch))
      guard result == .authorized else {
        try await self.clearPendingAuthorization()
        throw RuntimeMCPError.authorizationRequired
      }
    }
  }

  private func provider(_ capture: MCPAuthorizationCapture) -> McpOAuthProvider {
    let documentURL = clientMetadataDocumentURL
    let redirect = redirectURL
    return McpOAuthProvider(
      options: McpOAuthProviderOptions(
        serverUrl: serverURL, redirectUrl: redirectURL,
        clientMetadata: OAuthClientMetadata(client_name: "Memoshi", scope: scope),
        clientMetadataDocument: { metadata in
          guard let documentURL, metadata?.client_id_metadata_document_supported == true else {
            return nil
          }
          return OAuthClientMetadataDocument(url: documentURL, redirectUrl: redirect)
        },
        clientId: clientID.map(JSONString.init), store: store,
        onRedirect: { await capture.record($0) }))
  }

  private static func validateDocument(_ url: URL?) throws {
    guard let url else { return }
    guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      !url.path.isEmpty, url.path != "/"
    else { throw RuntimeMCPError.invalidConfiguration }
  }

  private func load() async throws -> McpOAuthState {
    guard let state = try await store.load() else {
      return McpOAuthState(serverUrl: serverURL.absoluteString)
    }
    guard state.serverUrl == serverURL.absoluteString else {
      throw RuntimeMCPError.credentialUnavailable
    }
    return state
  }

  private func clearPendingAuthorization() async throws {
    var state = try await load()
    state.oauthState = nil
    state.codeVerifier = nil
    try await store.save(state)
  }

  private func redact(_ value: MemoshiProtocol.JSONValue) async throws -> MemoshiProtocol.JSONValue
  {
    // A reopened host first registers its protected tokens, not merely this life's releases.
    _ = try await load()
    return try await secrets.redact(value)
  }

  private func exclusive(
    cancelWithCaller: Bool = true, _ work: @escaping @Sendable () async throws -> Void
  ) async throws {
    let id = UUID()
    let task = Task {
      if cancelWithCaller {
        try await work()
      } else {
        // Native rotation owns its lifetime, not the tool's cancellation or revoked review.
        try await RuntimeMCPRequestContext.$current.withValue(nil) { try await work() }
      }
    }
    operation = (id, task)
    defer { if operation?.id == id { operation = nil } }
    do {
      try await withTaskCancellationHandler {
        try await task.value
        try Task.checkCancellation()
      } onCancel: {
        if cancelWithCaller { task.cancel() }
      }
    } catch {
      if Task.isCancelled { throw RuntimeMCPError.cancelled }
      if let safe = error as? RuntimeMCPError { throw safe }
      throw RuntimeMCPError.credentialUnavailable
    }
  }

  private static func validate(
    _ name: String, _ server: URL, _ redirect: URL, _ reference: String,
    _ network: RuntimeMCPHTTPNetwork
  ) throws {
    try network.validate(server)
    guard !name.isEmpty, name.utf8.count <= 32,
      name.utf8.first.map({ (97...122).contains($0) }) == true,
      name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) }),
      server.query == nil, reference.hasPrefix("kc_"),
      UUID(uuidString: String(reference.dropFirst(3))) != nil,
      let scheme = redirect.scheme?.lowercased(),
      !["javascript", "data", "file", "vbscript"].contains(scheme),
      redirect.user == nil, redirect.password == nil, redirect.fragment == nil,
      redirect.query == nil,
      !redirect.path.isEmpty
    else { throw RuntimeMCPError.invalidConfiguration }
    if scheme == "http" {
      guard ["127.0.0.1", "[::1]", "::1"].contains(redirect.host?.lowercased() ?? "") else {
        throw RuntimeMCPError.invalidConfiguration
      }
    }
  }

  private static func sameRedirect(_ actual: URL, _ expected: URL) -> Bool {
    actual.scheme?.lowercased() == expected.scheme?.lowercased()
      && actual.host?.lowercased() == expected.host?.lowercased()
      && actual.port == expected.port && actual.path == expected.path
      && actual.user == nil && actual.password == nil && actual.fragment == nil
  }
}

/// Native opaque storage is internal so the qualification vault can exercise reopen and
/// corruption without granting a test runner production Keychain access.
struct RuntimeMCPOAuthStorage: Sendable {
  let load: @Sendable () async throws -> Data?
  let save: @Sendable (Data) async throws -> Void
  let remove: @Sendable () async throws -> Void
}

private struct MCPProtectedOAuthEnvelope: Codable {
  let version: Int
  let state: McpOAuthState
  let redactions: [String]
}

private actor ProtectedMCPOAuthStore: McpOAuthStateStore {
  let storage: RuntimeMCPOAuthStorage
  let secrets: MCPHostSecretRegistry

  init(storage: RuntimeMCPOAuthStorage, secrets: MCPHostSecretRegistry) {
    self.storage = storage
    self.secrets = secrets
  }

  private func envelope() async throws -> MCPProtectedOAuthEnvelope? {
    guard let data = try await storage.load() else { return nil }
    let value = try PiCore.JSONValue(data: data).decode(MCPProtectedOAuthEnvelope.self)
    guard value.version == 1 else { throw RuntimeMCPError.credentialUnavailable }
    await secrets.register(value.redactions)
    return value
  }

  func load() async throws -> McpOAuthState? { try await envelope()?.state }

  func save(_ state: McpOAuthState) async throws {
    var history = Set(try await envelope()?.redactions ?? [])
    history.formUnion(
      [
        state.tokens?.access_token, state.tokens?.refresh_token, state.tokens?.id_token,
        state.clientInformation?.client_secret, state.codeVerifier, state.oauthState,
      ].compactMap { $0?.displayString })
    let values = history.sorted()
    await secrets.register(values)
    let protected = MCPProtectedOAuthEnvelope(version: 1, state: state, redactions: values)
    try await storage.save(PiCore.JSONValue(encoding: protected).encoded())
  }
}

private actor MCPAuthorizationCapture {
  private(set) var url: URL?
  func record(_ value: URL) { url = value }
}

private actor MCPHostSecretRegistry {
  private var scrubber = ToolOutputScrubber()
  func register(_ value: String) { scrubber.register(value) }
  func register(_ values: [String]) {
    for value in values { scrubber.register(value) }
  }
  func redact(_ value: MemoshiProtocol.JSONValue) throws -> MemoshiProtocol.JSONValue {
    try scrubber.metadata(value)
  }
}
