import AppCore
import Foundation
import MemoshiProtocol
import MemoshiRuntime
import Testing

/// Model setup in the Mac app: the app's remover and what the setup says about a saved
/// configuration and about credentials a confirmed configuration replaced. The request's own
/// rules are AppCore's `ModelSetupRequest`, tested there.
@Suite("Mac model provider setup", .timeLimit(.minutes(1)))
@MainActor
struct ModelProviderSetupTests {
  private static let keptKey = "text-chat.replaced-credentials"
  private static let apiKey = "kc_22222222-2222-4222-8222-222222222222"
  private static let signedIn = "cg_33333333-3333-4333-8333-333333333333"

  private static func providers(secretRef: String? = nil, seq: Int64 = 1)
    -> ModelsProvidersListResult
  {
    ModelsProvidersListResult(
      items: [
        ModelProviderConfiguration(
          id: "openai", name: "OpenAI", baseUrl: "https://api.openai.com/v1", secretRef: secretRef)
      ], asOf: AsOf(seq: seq))
  }

  @Test("A removal this launch has no store for fails; no other store is used")
  func removalWithoutItsStoreFails() async throws {
    let remover = ModelCredentialRemover(keychain: nil, host: nil)
    await #expect(throws: ModelKeychainError.unavailable) {
      try await remover.remove(Self.apiKey)
    }
    await #expect(throws: ChatGPTSignInError.credentialUnavailable) {
      try await remover.remove(Self.signedIn)
    }
  }

  @Test("A replaced credential that still cannot be removed is named, not kept silently")
  func keptCredentialIsNamed() async throws {
    let store = TestDefaults()
    store.defaults.set([Self.apiKey, Self.signedIn], forKey: Self.keptKey)
    let setup = ModelProviderSetup(defaults: store.defaults)
    #expect(setup.keptCredentialCount == 2)
    // Whether something still names it cannot be checked before a provider list loads.
    setup.removeKeptCredentials(keychain: nil, host: nil)
    #expect(!setup.isConfiguring)
    #expect(setup.problem == nil)

    setup.applyProviders(Self.providers())
    setup.removeKeptCredentials(keychain: nil, host: nil)
    try await eventually("attempted") { !setup.isConfiguring }
    #expect(setup.keptCredentialCount == 2)
    #expect(setup.problem == ModelProviderSetup.keptCredentialNotice)
    #expect(store.defaults.stringArray(forKey: Self.keptKey) == [Self.apiKey, Self.signedIn])
  }

  @Test("A replaced credential a provider names again is dropped, never removed")
  func namedKeptCredentialIsDropped() async throws {
    let store = TestDefaults()
    store.defaults.set([Self.signedIn], forKey: Self.keptKey)
    let setup = ModelProviderSetup(defaults: store.defaults)
    setup.applyProviders(Self.providers(secretRef: Self.signedIn))
    // Without a ChatGPT host this launch, a removal attempt would fail and keep it.
    setup.removeKeptCredentials(keychain: nil, host: nil)
    try await eventually("settled") { !setup.isConfiguring }
    #expect(setup.keptCredentialCount == 0)
    #expect(setup.problem == nil)
    #expect(store.defaults.object(forKey: Self.keptKey) == nil)
  }

  @Test(
    "An unreadable saved configuration blocks until it is discarded after a provider list loads")
  func unreadableConfigurationIsDiscardedOnceProvidersLoad() {
    let store = TestDefaults()
    store.defaults.set(Data("not a request".utf8), forKey: "text-chat.pending-provider")
    let setup = ModelProviderSetup(defaults: store.defaults)
    #expect(setup.hasUnreadableConfiguration)
    #expect(setup.hasUnconfirmedConfiguration)
    #expect(!setup.canRetryConfiguration)
    #expect(setup.problem != nil)
    #expect(!setup.canDiscardUnreadableConfiguration)

    setup.applyProviders(Self.providers())
    #expect(setup.canDiscardUnreadableConfiguration)
    setup.discardUnreadableConfiguration()
    #expect(!setup.hasUnconfirmedConfiguration)
    #expect(store.defaults.object(forKey: "text-chat.pending-provider") == nil)
  }

  @Test("An older provider list never replaces a newer one until a resync")
  func olderProviderListIsIgnored() {
    let store = TestDefaults()
    let setup = ModelProviderSetup(defaults: store.defaults)
    setup.applyProviders(Self.providers(secretRef: Self.signedIn, seq: 5))
    #expect(setup.usesChatGPT)
    setup.applyProviders(Self.providers(seq: 4))
    #expect(setup.usesChatGPT)
    setup.prepareForResync()
    setup.applyProviders(Self.providers(seq: 4))
    #expect(!setup.usesChatGPT)
  }
}
