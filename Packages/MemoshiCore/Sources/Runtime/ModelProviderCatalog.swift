import Foundation
import MemoshiProtocol
import PiAI
import PiCore

/// How a provider's key travels on the wire. The per-use lease accepts this header and no other.
public enum ModelCredentialHeader: Sendable, Hashable {
  /// `Authorization: Bearer <key>`.
  case bearer
  /// `x-api-key: <key>`.
  case apiKey

  /// Lowercased header name.
  var field: String {
    switch self {
    case .bearer: "authorization"
    case .apiKey: "x-api-key"
    }
  }
}

/// What a person is told before a message leaves this device, and whether requests are priced.
public enum ModelUsageDisclosure: Sendable, Hashable {
  /// A loopback server on this Mac. Requests have no catalog price.
  case onDevice
  /// The provider bills the configured API key for each request, at catalog prices when known.
  case apiUsage
  /// Sign in with ChatGPT plan access (D54): account usage limits, no per-request price.
  case subscription
}

/// One configurable model provider. Configuration validation, the Store's provider name, PiAI
/// construction, model discovery, the credential lease and the app's provider choices all read
/// this one table; an id that is not listed here cannot be configured.
public struct ModelProviderDefinition: Sendable, Identifiable {
  /// Where this provider's requests and credential may go.
  public enum Endpoint: Sendable, Hashable {
    /// An OpenAI-compatible server on this Mac, chosen by the user; models are discovered there.
    case loopback
    /// The provider's fixed HTTPS API; PiAI's catalog lists its models once a key is released.
    case fixed(String)
  }

  /// Provider identity and the prefix of every model reference.
  public let id: String
  /// Human-readable provider label.
  public let name: String
  /// The only origin this provider's credential may reach.
  public let endpoint: Endpoint
  /// The header that carries this provider's key.
  public let credentialHeader: ModelCredentialHeader
  /// Whether Sign in with ChatGPT may supply the credential (D54); otherwise only API keys.
  public let acceptsChatGPT: Bool
  /// The disclosure with an API key, or without a key for a loopback server.
  let keyUsage: ModelUsageDisclosure
  /// PiAI wire API of every offered model. Catalog models on another API, which would send the
  /// key in another header, are never listed or admitted.
  let api: PiAI.Api
  /// Builds PiAI's provider on the lease-checked transport.
  let makeProvider:
    @Sendable (ModelProviderConfiguration, @escaping PiAI.FetchFunction) throws -> PiAI.Provider

  /// The fixed HTTPS base URL, or nil for the user's loopback server.
  public var fixedBaseURL: String? {
    if case .fixed(let url) = endpoint { url } else { nil }
  }

  /// A fixed cloud API always needs an app-Keychain reference; a loopback server may be keyless.
  public var requiresCredential: Bool { fixedBaseURL != nil }

  /// The disclosure for one configured credential reference.
  public func usage(secretRef: String?) -> ModelUsageDisclosure {
    acceptsChatGPT
      && secretRef.flatMap(ModelCredentialReference.init(rawValue:))?.kind == .chatGPT
      ? .subscription : keyUsage
  }

  /// The definition for a provider id, or nil when this build cannot configure it.
  public static func named(_ id: String) -> ModelProviderDefinition? {
    all.first { $0.id == id }
  }

  /// Every provider this build can configure, in presentation order: cloud APIs, then this Mac.
  public static let all: [ModelProviderDefinition] = [openAI, anthropic, openRouter, local]

  /// Ollama, LM Studio or another OpenAI-compatible server on this Mac, optionally keyed.
  public static let local = ModelProviderDefinition(
    id: "local", name: "Local", endpoint: .loopback, credentialHeader: .bearer,
    acceptsChatGPT: false, keyUsage: .onDevice, api: "openai-completions"
  ) { configuration, fetch in
    try PiAI.openAICompatibleProvider(
      baseUrl: configuration.baseUrl, id: PiCore.JSONString(configuration.id),
      name: PiCore.JSONString(configuration.name), fetch: fetch)
  }

  /// OpenAI's Responses API, with an API key or Sign in with ChatGPT.
  public static let openAI = ModelProviderDefinition(
    id: "openai", name: "OpenAI", endpoint: .fixed("https://api.openai.com/v1"),
    credentialHeader: .bearer, acceptsChatGPT: true, keyUsage: .apiUsage,
    api: "openai-responses"
  ) { _, fetch in try PiAI.openaiProvider(fetch: fetch) }

  /// Anthropic's Messages API with an API key. Its subscription sign-in is never built (E11).
  public static let anthropic = ModelProviderDefinition(
    id: "anthropic", name: "Anthropic", endpoint: .fixed("https://api.anthropic.com"),
    credentialHeader: .apiKey, acceptsChatGPT: false, keyUsage: .apiUsage,
    api: "anthropic-messages"
  ) { _, fetch in try PiAI.anthropicProvider(fetch: fetch) }

  /// OpenRouter's OpenAI-compatible API with a usage-billed key.
  public static let openRouter = ModelProviderDefinition(
    id: "openrouter", name: "OpenRouter", endpoint: .fixed("https://openrouter.ai/api/v1"),
    credentialHeader: .bearer, acceptsChatGPT: false, keyUsage: .apiUsage,
    api: "openai-completions"
  ) { _, fetch in try PiAI.openrouterProvider(fetch: fetch) }
}
