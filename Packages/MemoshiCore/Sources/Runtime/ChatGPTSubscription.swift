import Foundation
import MemoshiProtocol
import PiAI
import PiCore

/// Ephemeral presentation only. Authorization URLs and callback input never belong in settings or events.
public enum ChatGPTSignInEvent: Sendable {
  case authorizationURL(URL)
  case waitingForBrowser
}

/// Presentation-safe failures; underlying OAuth responses may contain credentials and are never forwarded.
public enum ChatGPTSignInError: Error, Equatable, Sendable {
  case invalidConfiguration
  case busy
  case cancelled
  case signInFailed
  case credentialUnavailable
}

/// Runs in Memoshi.app, not memoshid. PiAI owns OAuth, refresh locking and Keychain serialization.
/// The existing authenticated broker receives only a short-lived access token, never refresh tokens.
/// This development host uses the SDK's explicitly device-only credential store, not iCloud sync.
public actor ChatGPTSubscription {
  typealias CredentialFactory =
    @Sendable (ModelCredentialReference) throws -> any PiAI.CredentialStore

  private let makeCredentials: CredentialFactory
  private let fetch: PiAI.FetchFunction
  private struct CredentialContext: Sendable {
    let reference: ModelCredentialReference
    let credentials: any PiAI.CredentialStore
    let models: PiAI.ModelsRegistry
  }
  // One configured OpenAI credential. In-flight work retains its own context when this changes.
  private var cachedContext: CredentialContext?
  private var loginAbort: PiCore.AbortController?
  private var callbackInput: SubscriptionCallbackInput?
  private var operations: [UUID: Task<Void, Never>] = [:]
  private var closed = false

  /// The signing identity and private, app-owned lock directory come from the trusted native host.
  /// Each opaque reference gets a separate service, so reconnecting never changes an old reference's account.
  public init(accessGroup: String, lockDirectory: URL) {
    self.makeCredentials = { reference in
      try PiAI.KeychainCredentialStore(
        service: "com.mehmetcanbudak.memoshi.models.chatgpt." + reference.rawValue,
        accessGroup: accessGroup, lockDirectory: lockDirectory)
    }
    self.fetch = PiAI.URLSessionFetch(configuration: .ephemeral).fetch
  }

  /// Internal dependency seam for an isolated consumer smoke; production never injects a credential source.
  init(makeCredentials: @escaping CredentialFactory, fetch: @escaping PiAI.FetchFunction) {
    self.makeCredentials = makeCredentials
    self.fetch = fetch
  }

  /// Starts only after a native user action. The UUID is stable for this installation, not an account id.
  public func signIn(
    deviceID: UUID, onEvent: @escaping @Sendable (ChatGPTSignInEvent) -> Void
  ) async throws -> String {
    guard !closed else { throw ChatGPTSignInError.cancelled }
    guard loginAbort == nil else { throw ChatGPTSignInError.busy }
    // This SDK flow consults this non-secret binding override. Never permit a non-loopback listener.
    let callbackHost = PiAI.getProviderEnvValue("PI_OAUTH_CALLBACK_HOST")
    guard callbackHost == nil || callbackHost == "127.0.0.1" else {
      throw ChatGPTSignInError.invalidConfiguration
    }
    let reference = ModelCredentialReference(kind: .chatGPT)
    let abort = PiCore.AbortController()
    let input = SubscriptionCallbackInput()
    loginAbort = abort
    callbackInput = input
    defer {
      loginAbort = nil
      callbackInput = nil
    }
    let context: CredentialContext
    do { context = try credentialContext(reference) } catch {
      throw ChatGPTSignInError.signInFailed
    }
    return try await tracked {
      let models = context.models
      let signal = try PiCore.AbortSignal.any([
        abort.signal, PiCore.AbortSignal.timeout(milliseconds: 300_000),
      ])
      return try await withTaskCancellationHandler {
        do {
          _ = try await models.login(
            "openai", type: .oauth,
            interaction: PiAI.AuthInteraction(
              signal: signal,
              prompt: { prompt in
                guard case .manualCode = prompt.kind else {
                  throw ChatGPTSignInError.invalidConfiguration
                }
                onEvent(.waitingForBrowser)
                return PiCore.JSONString(try await input.wait(signal: prompt.signal ?? signal))
              },
              notify: { event in
                guard case .authURL(let value, _) = event else { return }
                guard let url = URL(string: value), url.scheme == "https",
                  url.host == "auth.openai.com", url.path == "/api/accounts/authorize",
                  url.user == nil, url.password == nil, url.port == nil, url.fragment == nil
                else {
                  abort.abort()
                  return
                }
                onEvent(.authorizationURL(url))
              }),
            options: PiAI.LoginOptions(getDeviceId: { deviceID.uuidString }, agentName: "Memoshi"))
          // login waits for the SDK's admitted Keychain write; retain its reference even if quit follows.
          return reference.rawValue
        } catch {
          // Only this attempt's new item is removed. An admitted SDK write/rotation must settle first.
          let cleanup = Task { try await models.logout("openai") }
          _ = await cleanup.result
          if signal.isAborted || Task.isCancelled { throw ChatGPTSignInError.cancelled }
          throw ChatGPTSignInError.signInFailed
        }
      } onCancel: {
        abort.abort()
      }
    }
  }

  /// Optional browser fallback. SDK validation still checks the callback route, state and issued client id.
  public func submitCallback(_ value: String) throws {
    guard !closed, let callbackInput,
      !value.isEmpty, value.utf8.count <= 16 * 1024
    else { throw ChatGPTSignInError.invalidConfiguration }
    try callbackInput.submit(value)
  }

  /// Cancels only the current sign-in, never a model turn or another stored credential.
  public func cancelSignIn() { loginAbort?.abort() }

  /// Called only by the authenticated app broker. Tokens are refreshed/persisted by PiAI before release.
  public func release(_ params: HostKeychainGetParams) async throws -> HostKeychainGetResult {
    guard !closed, params.purpose == "model:openai",
      let reference = ModelCredentialReference(rawValue: params.secretRef),
      reference.kind == .chatGPT
    else { throw ChatGPTSignInError.credentialUnavailable }
    let context: CredentialContext
    do { context = try credentialContext(reference) } catch {
      throw ChatGPTSignInError.credentialUnavailable
    }
    return try await tracked {
      do {
        try Task.checkCancellation()
        // PiAI finishes a refresh it has started even after a cancelled getAuth returns. Caller
        // cancellation never reaches this task, so close() waits until that refresh is saved.
        let resolution = Task {
          let credentials = context.credentials
          let models = context.models
          guard let result = try await models.getAuth("openai"),
            let access = result.auth.apiKey,
            let credential = try await credentials.read("openai"),
            case .oauth(let stored) = credential,
            access == stored.access
          else { throw ChatGPTSignInError.credentialUnavailable }
          return (access, stored.expires)
        }
        let (access, expires) = try await resolution.value
        // PiAI keeps OAuth expiry as a Double (Number); only whole remaining milliseconds count.
        let remaining = (expires - Double(PiCore.unixMilliseconds())).rounded(.down)
        guard remaining.isFinite, remaining >= 1,
          !access.isEmpty, access.utf8.count <= 16 * 1024,
          !access.utf8.contains(where: { $0 < 0x21 || $0 == 0x7f })
        else { throw ChatGPTSignInError.credentialUnavailable }
        try Task.checkCancellation()
        return HostKeychainGetResult(value: access, ttlMs: Int64(min(60_000, remaining)))
      } catch {
        throw ChatGPTSignInError.credentialUnavailable
      }
    }
  }

  /// Removes this exact app-owned account; a provider selection never silently changes to an API key.
  public func signOut(secretRef: String) async throws {
    guard !closed,
      let reference = ModelCredentialReference(rawValue: secretRef), reference.kind == .chatGPT
    else { throw ChatGPTSignInError.credentialUnavailable }
    let context: CredentialContext
    do { context = try credentialContext(reference) } catch {
      throw ChatGPTSignInError.credentialUnavailable
    }
    try await tracked {
      do { try await context.models.logout("openai") } catch {
        throw ChatGPTSignInError.credentialUnavailable
      }
    }
    if cachedContext?.reference == reference { cachedContext = nil }
  }

  /// Normal app quit cancels login and awaits admitted refresh/write operations; no process is killed.
  public func close() async {
    closed = true
    loginAbort?.abort()
    for operation in Array(operations.values) { await operation.value }
    cachedContext = nil
  }

  /// A vetoed application quit may reopen the host only after the prior operations have settled.
  public func resumeAfterQuitVeto() {
    guard operations.isEmpty else { return }
    closed = false
  }

  private func tracked<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let id = UUID()
    let work = Task { try await operation() }
    operations[id] = Task { _ = await work.result }
    defer { operations.removeValue(forKey: id) }
    return try await withTaskCancellationHandler {
      try await work.value
    } onCancel: {
      work.cancel()
    }
  }
  private func credentialContext(_ reference: ModelCredentialReference) throws -> CredentialContext
  {
    if let cachedContext, cachedContext.reference == reference { return cachedContext }
    let credentials = try makeCredentials(reference)
    let context = CredentialContext(
      reference: reference, credentials: credentials,
      models: try Self.registry(credentials: credentials, fetch: fetch))
    cachedContext = context
    return context
  }

  private nonisolated static func registry(
    credentials: any PiAI.CredentialStore, fetch: @escaping PiAI.FetchFunction
  ) throws -> PiAI.ModelsRegistry {
    let models = PiAI.createModels(
      .init(credentials: credentials, authContext: PiAI.StaticAuthContext()))
    models.setProvider(try PiAI.openaiProvider(fetch: fetch))
    return models
  }
}
