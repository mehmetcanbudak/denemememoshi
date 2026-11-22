import Foundation

/// Nonsecret identity of one app-owned model credential. Its kind is fixed for its lifetime.
public struct ModelCredentialReference: RawRepresentable, Hashable, Sendable {
  /// Storage/authentication contract; neither case contains credential bytes.
  public enum Kind: Hashable, Sendable {
    case apiKey
    case chatGPT
  }

  /// Exact opaque identity retained by provider settings and idempotent requests.
  public let rawValue: String
  /// Whether the app releases a stored API key or derives a ChatGPT access token through PiAI.
  public let kind: Kind

  /// Parses only bounded, UUID-backed app-owned references.
  public init?(rawValue: String) {
    guard rawValue.utf8.count == 39,
      UUID(uuidString: String(rawValue.dropFirst(3))) != nil
    else { return nil }
    switch rawValue.prefix(3) {
    case "kc_": kind = .apiKey
    case "cg_": kind = .chatGPT
    default: return nil
    }
    self.rawValue = rawValue
  }

  /// Allocates an explicit reference before a user-initiated sign-in or Keychain write.
  public init(kind: Kind, id: UUID = UUID()) {
    self.kind = kind
    self.rawValue = (kind == .apiKey ? "kc_" : "cg_") + id.uuidString.lowercased()
  }
}
