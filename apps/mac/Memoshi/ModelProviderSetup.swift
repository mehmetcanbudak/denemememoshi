import AppCore
import AppKit
import Foundation
import MemoshiClient
import MemoshiProtocol
import MemoshiRuntime
import Observation

/// Owns provider metadata and configuration intents. Key bytes never enter observable state or defaults.
@MainActor
@Observable
final class ModelProviderSetup {
  private(set) var providers: [ModelProviderConfiguration] = []
  private(set) var models: [AvailableModel] = []
  private(set) var isConfiguring = false
  /// Whether a saved configuration's delivery is not confirmed, readable or not.
  var hasUnconfirmedConfiguration: Bool { request.isUnconfirmed }
  /// Whether the latest attempt was refused or answered busy, so Retry sends a new request.
  var pendingWasRejected: Bool { request.wasRejected }
  /// Credentials that confirmed configurations replaced and that could not be removed yet.
  var keptCredentialCount: Int { request.keptCredentialCount }
  private(set) var problem: String?
  private(set) var isSigningIn = false
  private(set) var signInURL: URL?
  private(set) var acceptsSignInCallback = false
  var endpoint = "http://127.0.0.1:11434/v1"
  var selectedModel = "" {
    didSet { defaults.set(selectedModel, forKey: "text-chat.selected-model") }
  }

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var client: MemoshiClient?
  @ObservationIgnored private var actionTask: Task<Void, Never>?
  /// The saved configuration request and its retry and discard rules (AppCore, tested there).
  private let request: ModelSetupRequest
  @ObservationIgnored private var providersAsOf = SnapshotWatermark()
  @ObservationIgnored private var signInAttempt: UUID?
  private var hasLoadedProviders = false

  init(defaults: UserDefaults) {
    self.defaults = defaults
    request = ModelSetupRequest(defaults: defaults)
    selectedModel = defaults.string(forKey: "text-chat.selected-model") ?? ""
    if request.isUnreadable {
      problem = String(
        localized:
          "The saved provider configuration could not be read. Configuration and sending are blocked until its delivery can be resolved."
      )
    }
  }

  var selectedModelIsAvailable: Bool {
    models.contains { $0.ref.ref.rawValue == selectedModel }
  }

  /// The selected model's provider in the runtime's provider table, when this build has it.
  var selectedProvider: ModelProviderDefinition? {
    selectedModel.split(separator: "/", maxSplits: 1).first.flatMap {
      ModelProviderDefinition.named(String($0))
    }
  }

  /// What sending to the selected model means with its provider's configured credential.
  var selectedUsage: ModelUsageDisclosure? {
    selectedProvider.map { provider in
      provider.usage(secretRef: providers.first { $0.id == provider.id }?.secretRef)
    }
  }

  var usesChatGPT: Bool {
    guard let reference = providers.first(where: { $0.id == "openai" })?.secretRef else {
      return false
    }
    return ModelCredentialReference(rawValue: reference)?.kind == .chatGPT
  }
  var canRetryConfiguration: Bool { request.params != nil && !isConfiguring }
  /// A saved configuration that cannot be decoded, so it can never be retried.
  var hasUnreadableConfiguration: Bool { request.isUnreadable }
  /// Offered only after a provider list is loaded, so the current providers can be checked.
  var canDiscardUnreadableConfiguration: Bool {
    request.isUnreadable && hasLoadedProviders && !isConfiguring
  }
  /// Whether the runtime definitely refused the latest attempt of the saved configuration,
  /// so the person may abandon it instead of retrying.
  var canDiscardRefusedConfiguration: Bool { request.canDiscardRefused && !isConfiguring }
  /// What that discard does with the credential saved for the request, or nil when it is not
  /// offered: the same rule the discard then applies.
  var refusedDiscardPreview: ModelSetupRequest.RefusedDiscard? {
    request.discardPreview(configuredSecretRef: pendingProviderSecretRef)
  }
  /// The current credential of the saved request's provider.
  private var pendingProviderSecretRef: String? {
    request.params.flatMap { pending in providers.first { $0.id == pending.providerId }?.secretRef }
  }

  func attach(_ client: MemoshiClient) { self.client = client }
  func stop() { actionTask?.cancel() }

  func applyProviders(_ result: ModelsProvidersListResult) {
    guard providersAsOf.advance(to: result.asOf.seq) else { return }
    if providers != result.items { models = [] }
    providers = result.items
    hasLoadedProviders = true
    if let local = providers.first(where: { $0.id == ModelProviderDefinition.local.id }) {
      endpoint = local.baseUrl
    }
  }

  /// A resync replaces the provider list even when its position is below the old one.
  func prepareForResync() { providersAsOf.reset() }

  func reloadProvidersIfNewer(than sequence: Int64) async throws {
    guard !providersAsOf.covers(sequence) else { return }
    try await reloadProviders()
  }

  func reloadModels() async throws {
    guard let client else { throw ClientError.notSynchronized }
    do {
      let result = try await client.call(ModelsList.self, EmptyParams())
      models = result.items
      // An unavailable selection stays visible and cannot send. Never fall back to a paid model.
      if selectedModel.isEmpty {
        selectedModel =
          models.first(where: {
            $0.ref.ref.rawValue.hasPrefix(ModelProviderDefinition.local.id + "/")
          })?.ref.ref.rawValue ?? ""
      }
      if result.unavailableProviders?.isEmpty == false {
        problem = String(
          localized:
            "Some configured providers or their keys are unavailable. Only successfully refreshed models are offered; no substitute provider was selected."
        )
      }
    } catch {
      models = []
      throw error
    }
  }

  func configureEndpoint(keychain: ModelKeychain?, host: ChatGPTSubscription?) {
    guard client != nil, !isConfiguring, !hasUnconfirmedConfiguration else { return }
    do {
      let local = ModelProviderDefinition.local.id
      let params = ModelsProvidersConfigureParams(
        requestId: try MemoshiClient.requestID(), providerId: local, baseUrl: endpoint,
        secretRef: providers.first(where: { $0.id == local })?.secretRef)
      try request.save(params)
      configureRemembered(removing: ModelCredentialRemover(keychain: keychain, host: host))
    } catch { problem = Self.message(error) }
  }

  /// The caller owns and clears its SecureField. The task's temporary copy is dropped after SecItemAdd.
  func addKey(
    providerID: String, label: String, value: String, thisDeviceOnly: Bool,
    keychain: ModelKeychain, host: ChatGPTSubscription?,
    clearInput: @escaping @MainActor () -> Void
  ) {
    guard let client, !isConfiguring, !hasUnconfirmedConfiguration else { return }
    let baseURL = ModelProviderDefinition.named(providerID)?.fixedBaseURL ?? endpoint
    let remover = ModelCredentialRemover(keychain: keychain, host: host)
    var secret = value
    isConfiguring = true
    problem = nil
    actionTask = Task { [weak self, client] in
      guard let self else {
        secret = ""
        return
      }
      defer {
        secret = ""
        self.isConfiguring = false
        self.actionTask = nil
      }
      do {
        let status = await client.status()
        guard status.state == .connected,
          status.hello?.capabilities.contains(where: { $0.rawValue == "host.keychain.v1" }) == true
        else {
          throw RPCError(
            message: String(
              localized: "An authenticated app Keychain host is required before saving a model key."
            ),
            data: RPCErrorData(details: .hostUnavailable))
        }
        let metadata = try await keychain.put(
          providerID: providerID, label: label, value: secret, thisDeviceOnly: thisDeviceOnly)
        secret = ""
        clearInput()
        let params = ModelsProvidersConfigureParams(
          requestId: try MemoshiClient.requestID(), providerId: providerID,
          baseUrl: baseURL, secretRef: metadata.secretRef)
        let replaced = self.providers.first { $0.id == providerID }?.secretRef
        // Retain the exact metadata-only intent even if cancellation or disconnect follows the write.
        try self.request.save(params)
        if let replaced {
          // Removed once this configuration is confirmed: nothing names it any more.
          self.request.supersede(secretRef: replaced)
        }
        try Task.checkCancellation()
        try await self.commitRemembered(client, removing: remover)
      } catch { self.problem = Self.message(error) }
    }
  }
  /// The app hosts PiAI login and rotation. Only the resulting opaque reference enters an RPC.
  func signInWithChatGPT(_ host: ChatGPTSubscription, keychain: ModelKeychain?) {
    guard let client, !isConfiguring, !hasUnconfirmedConfiguration else { return }
    let replaced = providers.first { $0.id == "openai" }?.secretRef
    let remover = ModelCredentialRemover(keychain: keychain, host: host)
    let deviceID: UUID
    if let saved = defaults.string(forKey: "chatgpt.installation-id") {
      guard let parsed = UUID(uuidString: saved) else {
        problem = Self.message(ChatGPTSignInError.invalidConfiguration)
        return
      }
      deviceID = parsed
    } else {
      deviceID = UUID()
      defaults.set(deviceID.uuidString, forKey: "chatgpt.installation-id")
    }
    let attempt = UUID()
    signInAttempt = attempt
    isConfiguring = true
    isSigningIn = true
    problem = nil
    actionTask = Task { [weak self, client] in
      guard let self else { return }
      defer {
        self.signInAttempt = nil
        self.signInURL = nil
        self.acceptsSignInCallback = false
        self.isSigningIn = false
        self.isConfiguring = false
        self.actionTask = nil
      }
      do {
        let status = await client.status()
        guard status.state == .connected,
          status.hello?.capabilities.contains(where: { $0.rawValue == "host.keychain.v1" }) == true
        else { throw ChatGPTSignInError.invalidConfiguration }
        let reference = try await host.signIn(deviceID: deviceID) { [weak self] event in
          Task { @MainActor in
            guard let self, self.signInAttempt == attempt else { return }
            switch event {
            case .authorizationURL(let url):
              self.signInURL = url
              if !NSWorkspace.shared.open(url) {
                self.problem = String(localized: "The sign-in browser could not be opened.")
                await host.cancelSignIn()
              }
            case .waitingForBrowser:
              self.acceptsSignInCallback = true
            }
          }
        }
        try self.request.save(
          .init(
            requestId: MemoshiClient.requestID(), providerId: "openai",
            baseUrl: "https://api.openai.com/v1", secretRef: reference))
        if let replaced {
          // Removed once this configuration is confirmed: nothing names it any more.
          self.request.supersede(secretRef: replaced)
        }
        try Task.checkCancellation()
        try await self.commitRemembered(client, removing: remover)
      } catch { self.problem = Self.message(error) }
    }
  }

  func cancelChatGPTSignIn(_ host: ChatGPTSubscription) {
    Task { await host.cancelSignIn() }
  }

  func submitChatGPTCallback(
    _ value: String, host: ChatGPTSubscription, clearInput: @escaping @MainActor () -> Void
  ) {
    Task { [weak self] in
      do {
        try await host.submitCallback(value)
        clearInput()
      } catch { self?.problem = Self.message(error) }
    }
  }

  func signOutOfChatGPT(_ host: ChatGPTSubscription) {
    guard !isConfiguring, !hasUnconfirmedConfiguration,
      let reference = providers.first(where: { $0.id == "openai" })?.secretRef,
      ModelCredentialReference(rawValue: reference)?.kind == .chatGPT
    else { return }
    isConfiguring = true
    problem = nil
    actionTask = Task { [weak self] in
      guard let self else { return }
      defer {
        self.isConfiguring = false
        self.actionTask = nil
      }
      do {
        try await host.signOut(secretRef: reference)
        try await self.reloadModels()
        self.problem = String(
          localized:
            "ChatGPT credentials were removed. No API key or substitute model was selected.")
      } catch { self.problem = Self.message(error) }
    }
  }

  func retryConfiguration(keychain: ModelKeychain?, host: ChatGPTSubscription?) {
    guard let pending = request.params, !isConfiguring else { return }
    do {
      if request.wasRejected {
        // Only a rejection permits editing the endpoint and allocating a new intent.
        let loopback = ModelProviderDefinition.named(pending.providerId)?.endpoint == .loopback
        try request.save(
          .init(
            requestId: MemoshiClient.requestID(), providerId: pending.providerId,
            baseUrl: loopback ? endpoint : pending.baseUrl, secretRef: pending.secretRef),
          continuing: true)
      }
      configureRemembered(removing: ModelCredentialRemover(keychain: keychain, host: host))
    } catch { problem = Self.message(error) }
  }

  func refreshModels() {
    guard client != nil, !isConfiguring else { return }
    isConfiguring = true
    problem = nil
    actionTask = Task { [weak self] in
      guard let self else { return }
      defer {
        self.isConfiguring = false
        self.actionTask = nil
      }
      do { try await self.reloadModels() } catch { self.problem = Self.message(error) }
    }
  }

  private func configureRemembered(removing remover: ModelCredentialRemover) {
    guard let client, request.params != nil, !isConfiguring else { return }
    isConfiguring = true
    problem = nil
    actionTask = Task { [weak self, client] in
      guard let self else { return }
      defer {
        self.isConfiguring = false
        self.actionTask = nil
      }
      do {
        try await self.commitRemembered(client, removing: remover)
      } catch { self.problem = Self.message(error) }
    }
  }

  /// Sends the saved request. Its confirmation removes, through `remover`, the credentials
  /// that nothing names any more.
  private func commitRemembered(
    _ client: MemoshiClient, removing remover: ModelCredentialRemover
  ) async throws {
    guard request.params != nil else { return }
    try await request.attempt(removing: remover) {
      _ = try await client.call(ModelsProvidersConfigure.self, $0)
    }
    try await reloadProviders()
    try await reloadModels()
    noteKeptCredentials()
  }

  /// Says that a credential a newer configuration replaced is still saved, after every attempt
  /// that leaves one: a removal that keeps failing is never silent.
  static let keptCredentialNotice = String(
    localized:
      "A credential that a newer configuration replaced could not be removed yet. It stays in the Keychain but is not used; Memoshi tries to remove it again each time Model Settings open and after the next confirmed configuration."
  )

  /// Removes again, through the app's remover, the credentials confirmed configurations
  /// replaced and earlier removals could not remove. One that a provider names again is in use
  /// and is only no longer tracked. Runs once a provider list is loaded, so that can be checked,
  /// and while no other setup action runs; Model Settings call it each time they open.
  func removeKeptCredentials(keychain: ModelKeychain?, host: ChatGPTSubscription?) {
    guard hasLoadedProviders, !isConfiguring, request.keptCredentialCount > 0 else { return }
    let remover = ModelCredentialRemover(keychain: keychain, host: host)
    let inUse = Set(providers.compactMap(\.secretRef))
    isConfiguring = true
    actionTask = Task { [weak self] in
      guard let self else { return }
      defer {
        self.isConfiguring = false
        self.actionTask = nil
      }
      await self.request.removeKept(removing: remover, inUse: inUse)
      self.noteKeptCredentials()
    }
  }

  private func noteKeptCredentials() {
    if request.keptCredentialCount > 0 {
      problem = Self.keptCredentialNotice
    } else if problem == Self.keptCredentialNotice {
      problem = nil
    }
  }

  /// Removes only a record that can never be read or retried. Nothing is sent.
  func discardUnreadableConfiguration() {
    guard canDiscardUnreadableConfiguration else { return }
    request.discardUnreadable()
    problem = String(
      localized:
        "The unreadable saved provider configuration was discarded without sending anything. Check the provider list before configuring the same provider again."
    )
  }

  /// D130: abandons a configuration the runtime definitely refused. `ModelSetupRequest`
  /// decides whether the credential saved for it is removed first or kept.
  func discardRefusedConfiguration(keychain: ModelKeychain?, host: ChatGPTSubscription?) {
    guard canDiscardRefusedConfiguration else { return }
    let configured = pendingProviderSecretRef
    let remover = ModelCredentialRemover(keychain: keychain, host: host)
    isConfiguring = true
    problem = nil
    actionTask = Task { [weak self] in
      guard let self else { return }
      defer {
        self.isConfiguring = false
        self.actionTask = nil
      }
      do {
        let outcome = try await self.request.discardRefused(
          configuredSecretRef: configured, removing: remover)
        switch outcome {
        case .removedCredential:
          self.problem = String(
            localized:
              "The refused configuration was discarded and the credential saved only for it was removed. The provider list is unchanged."
          )
        case .keptCredential:
          self.problem = String(
            localized:
              "The refused configuration was discarded. The credential saved for it was kept, because an earlier attempt had no definite answer and may still be applied; check the provider list."
          )
        case .noCredential:
          self.problem = String(
            localized: "The refused configuration was discarded. The provider list is unchanged.")
        case nil:
          break
        }
      } catch { self.problem = Self.message(error) }
    }
  }

  private func reloadProviders() async throws {
    guard let client else { throw ClientError.notSynchronized }
    applyProviders(try await client.call(ModelsProvidersList.self, EmptyParams()))
  }

  private static func message(_ error: any Error) -> String {
    if let error = error as? ModelKeychainError { return error.localizedDescription }
    if let error = error as? RPCError { return error.message }
    if let error = error as? ChatGPTSignInError {
      switch error {
      case .cancelled:
        return String(localized: "ChatGPT sign-in was canceled.")
      case .busy:
        return String(localized: "A ChatGPT sign-in is already in progress.")
      case .invalidConfiguration:
        return String(
          localized:
            "ChatGPT sign-in requires the authenticated app host, a stable installation ID and its loopback callback."
        )
      case .signInFailed:
        return String(
          localized:
            "ChatGPT sign-in did not finish. Close other pending ChatGPT sign-ins and try again. No API-key fallback was selected."
        )
      case .credentialUnavailable:
        return String(
          localized:
            "The app could not release the ChatGPT credential. Unlock the Mac or reconnect ChatGPT; no alternate credential was used."
        )
      }
    }
    return String(
      localized:
        "Provider setup did not finish. Reconnect or refresh models; if configuration is unconfirmed, retry its saved request. Key bytes are not stored in app settings."
    )
  }
}

extension ModelCredentialRemover {
  /// Deletes API keys from `keychain` and signs out of ChatGPT through `host`. A removal whose
  /// store this launch lacks fails; no other store is used.
  init(keychain: ModelKeychain?, host: ChatGPTSubscription?) {
    self.init(
      apiKey: { reference in
        guard let keychain else { throw ModelKeychainError.unavailable }
        try await keychain.delete(secretRef: reference)
      },
      chatGPT: { reference in
        guard let host else { throw ChatGPTSignInError.credentialUnavailable }
        try await host.signOut(secretRef: reference)
      })
  }
}
