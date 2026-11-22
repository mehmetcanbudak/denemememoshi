import CryptoKit
import Foundation
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable

/// Resolves one explicitly configured reference through the authenticated app host, never a file or environment.
public typealias RuntimeCredentialResolver =
  @Sendable (HostKeychainGetParams) async throws -> HostKeychainGetResult

/// Pi's existing credential seam is read-only in the daemon. Values are resolved afresh for each use.
actor ProviderCredentials: PiAI.CredentialStore {
  let store: Store
  let resolve: RuntimeCredentialResolver?
  private struct Lease {
    let reference: String
    let digest: SHA256.Digest
    let expires: ContinuousClock.Instant
  }
  // Bounded by configured providers. Only fingerprints and expiry metadata are retained here.
  private var leases: [String: Lease] = [:]
  private var scrubber = ToolOutputScrubber()

  init(store: Store, resolve: RuntimeCredentialResolver?) {
    self.store = store
    self.resolve = resolve
  }

  func read(_ providerId: PiCore.JSONString, options: PiAI.AuthOperationOptions?) async throws
    -> PiAI.Credential?
  {
    try Task.checkCancellation()
    try options?.signal?.throwIfAborted()
    guard
      let provider = try await store.modelProviders().value.first(where: {
        $0.id == providerId.displayString
      })
    else {
      leases.removeValue(forKey: providerId.displayString)
      return nil
    }
    guard let reference = provider.secretRef else {
      leases.removeValue(forKey: provider.id)
      return nil
    }
    guard let resolve else { throw unavailable() }
    let release: HostKeychainGetResult
    do {
      let params = HostKeychainGetParams(secretRef: reference, purpose: "model:" + provider.id)
      release = try await PiAI.withAbortSignal(options?.signal) { try await resolve(params) }
    } catch {
      // A caller that gave up its own read learned nothing about the key: only the broker's
      // refusal ends the lease that another request in flight still depends on.
      try options?.signal?.throwIfAborted()
      try Task.checkCancellation()
      leases.removeValue(forKey: provider.id)
      throw unavailable()
    }
    try options?.signal?.throwIfAborted()
    try Task.checkCancellation()
    guard release.ttlMs > 0, release.ttlMs <= 600_000,
      !release.value.isEmpty, release.value.utf8.count <= 16 * 1024,
      !release.value.utf8.contains(where: { $0 < 0x21 || $0 == 0x7f })
    else {
      leases.removeValue(forKey: provider.id)
      throw unavailable()
    }
    scrubber.register(release.value)
    leases[provider.id] = Lease(
      reference: reference, digest: Self.digest(release.value[...]),
      expires: ContinuousClock.now.advanced(by: .milliseconds(release.ttlMs)))
    return .apiKey(PiAI.ApiKeyCredential(key: release.value))
  }

  /// SDK discovery can reuse its auth across fallback URLs. Every actual HTTP attempt must still
  /// match an unexpired release for this provider/reference, addressed to the provider's own
  /// origin, in its declared header and in no other credential header; an in-flight response
  /// may finish. This checks the first hop only: keyed providers' transport refuses redirects.
  func fetch(
    _ request: PiAI.HTTPRequest, signal: PiCore.AbortSignal?,
    provider: ModelProviderConfiguration, definition: ModelProviderDefinition,
    using transport: PiAI.FetchFunction
  ) async throws -> PiAI.HTTPResponse {
    try Task.checkCancellation()
    try signal?.throwIfAborted()
    if let reference = provider.secretRef {
      guard let lease = leases[provider.id], lease.reference == reference,
        Self.sameOrigin(request.url, definition.fixedBaseURL ?? provider.baseUrl),
        let key = Self.presentedKey(
          in: request.headers.lazy.map { (name: $0.name, value: $0.value) },
          declared: definition.credentialHeader),
        Self.digest(key) == lease.digest,
        ContinuousClock.now < lease.expires
      else { throw unavailable() }
    }
    return try await transport(request, signal)
  }

  /// Every header that can carry a model credential. Only the declared one may be present.
  private static let credentialFields: Set<String> = [
    "authorization", "proxy-authorization", "x-api-key", "api-key", "x-goog-api-key",
    "cf-aig-authorization",
  ]

  /// The key in the declared header, only when that header is the request's sole credential
  /// header and appears once. Header names compare case-insensitively.
  static func presentedKey<Headers: Sequence>(
    in headers: Headers, declared: ModelCredentialHeader
  ) -> Substring? where Headers.Element == (name: String, value: String) {
    var key: Substring?
    for (name, value) in headers where credentialFields.contains(name.lowercased()) {
      guard key == nil, name.lowercased() == declared.field else { return nil }
      switch declared {
      case .bearer:
        guard value.hasPrefix("Bearer ") else { return nil }
        key = value.dropFirst(7)
      case .apiKey:
        key = value[...]
      }
    }
    return key
  }

  /// The request's scheme, host and effective port equal the provider endpoint's.
  static func sameOrigin(_ url: URL, _ endpoint: String) -> Bool {
    guard let actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let allowed = URLComponents(string: endpoint),
      let scheme = actual.scheme?.lowercased(), scheme == allowed.scheme?.lowercased(),
      let host = actual.host?.lowercased(), host == allowed.host?.lowercased()
    else { return false }
    let standard = scheme == "https" ? 443 : 80
    return (actual.port ?? standard) == (allowed.port ?? standard)
  }

  func list(options: PiAI.AuthOperationOptions?) async throws -> [PiAI.CredentialInfo] {
    try options?.signal?.throwIfAborted()
    return try await store.modelProviders().value.compactMap { provider in
      provider.secretRef == nil
        ? nil : PiAI.CredentialInfo(providerId: PiCore.JSONString(provider.id), type: .apiKey)
    }
  }

  func modify(
    _ providerId: PiCore.JSONString, options: PiAI.AuthOperationOptions?,
    _ transform: @escaping @Sendable (PiAI.Credential?) async throws -> PiAI.Credential?
  ) async throws -> PiAI.Credential? {
    throw PiAI.ModelsError(.auth, "Model credentials can only be changed in the app Keychain.")
  }

  func delete(_ providerId: PiCore.JSONString, options: PiAI.AuthOperationOptions?) async throws {
    throw PiAI.ModelsError(.auth, "Model credentials can only be removed in the app Keychain.")
  }

  private static func digest(_ value: Substring) -> SHA256.Digest {
    var value = value
    return value.withUTF8 { bytes in
      var hash = SHA256()
      hash.update(bufferPointer: UnsafeRawBufferPointer(bytes))
      return hash.finalize()
    }
  }

  func scrubToolOutput(_ result: PiDurable.ToolExecutionResult) -> ScrubbedToolOutput {
    scrubber.toolResult(result)
  }

  func scrubPolicyMetadata(_ value: MemoshiProtocol.JSONValue) throws -> MemoshiProtocol.JSONValue {
    try scrubber.metadata(value)
  }

  /// Registers a non-model secret, such as an MCP connector token, for output redaction only.
  /// Nothing here can release it to a provider request.
  func registerRedaction(_ value: String) { scrubber.register(value) }

  private func unavailable() -> PiAI.ModelsError {
    PiAI.ModelsError(.auth, "The authenticated app could not release the configured model key.")
  }
}

/// Response identifiers, native failure reasons and diagnostics may echo Authorization values.
/// Keep transcript content and typed accounting, not opaque provider metadata, before Pi sees them.
func sanitizingProviderEvents(_ source: PiAI.AssistantMessageEventStream)
  -> PiAI.AssistantMessageEventStream
{
  let output = PiAI.AssistantMessageEventStream()
  Task {
    for await event in source {
      let original = event.message
      let message = PiAI.AssistantMessage(
        content: sanitizedProviderContent(original.content),
        api: original.api, provider: original.provider, model: original.model,
        thinkingLevel: original.thinkingLevel, usage: original.usage,
        stopReason: original.stopReason,
        errorMessage: original.stopReason == .error || original.stopReason == .aborted
          ? "The model provider could not complete this request." : nil,
        endTurn: original.endTurn, timestamp: original.timestamp, durationMs: original.durationMs)
      let sanitized: PiAI.AssistantMessageEvent
      switch event {
      case .start:
        sanitized = .start(partial: message)
      case .textStart(let index, _):
        sanitized = .textStart(contentIndex: index, partial: message)
      case .textDelta(let index, let delta, _):
        sanitized = .textDelta(contentIndex: index, delta: delta, partial: message)
      case .textEnd(let index, let content, _):
        sanitized = .textEnd(contentIndex: index, content: content, partial: message)
      case .thinkingStart(let index, _):
        sanitized = .thinkingStart(contentIndex: index, partial: message)
      case .thinkingDelta(let index, let delta, _):
        sanitized = .thinkingDelta(contentIndex: index, delta: delta, partial: message)
      case .thinkingEnd(let index, let content, _):
        sanitized = .thinkingEnd(contentIndex: index, content: content, partial: message)
      case .toolcallStart(let index, _):
        sanitized = .toolcallStart(contentIndex: index, partial: message)
      case .toolcallDelta(let index, let delta, _):
        sanitized = .toolcallDelta(contentIndex: index, delta: delta, partial: message)
      case .toolcallEnd(let index, var toolCall, _):
        toolCall.thoughtSignature = nil
        sanitized = .toolcallEnd(contentIndex: index, toolCall: toolCall, partial: message)
      case .done(let reason, _):
        sanitized = .done(reason: reason, message: message)
      case .error(let reason, _):
        sanitized = .error(reason: reason, error: message)
      }
      output.push(sanitized)
    }
    output.end()
  }
  return output
}

private func sanitizedProviderContent(_ original: [PiAI.AssistantContentBlock])
  -> [PiAI.AssistantContentBlock]
{
  var content = original
  for index in content.indices {
    switch content[index] {
    case .text(var text):
      if text.textSignature != nil {
        text.textSignature = nil
        content[index] = .text(text)
      }
    case .thinking(var thinking):
      if let signature = thinking.thinkingSignature {
        // Only the plain field tags used by this chat-completions profile are replayed.
        // Serialized/encrypted provider payloads are opaque metadata, not transcript text.
        switch signature.displayString {
        case "reasoning", "reasoning_content", "reasoning_text": break
        default:
          thinking.thinkingSignature = nil
          content[index] = .thinking(thinking)
        }
      }
    case .toolCall(var toolCall):
      if toolCall.thoughtSignature != nil {
        toolCall.thoughtSignature = nil
        content[index] = .toolCall(toolCall)
      }
    }
  }
  return content
}
