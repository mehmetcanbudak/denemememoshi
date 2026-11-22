/// `host.keychain.get`: a memory-only secret release from the authenticated app broker.
public enum HostKeychainGet: RPCMethod {
  /// The opaque reference and its exact intended use.
  public typealias Params = HostKeychainGetParams
  /// The released value and its maximum in-memory lifetime.
  public typealias Result = HostKeychainGetResult
  /// `host.keychain.get`.
  public static let name = "host.keychain.get"
  /// Does not mutate a Keychain item.
  public static let isMutating = false
}

/// A bounded reference and purpose, not a secret value (protocol.md §6).
public struct HostKeychainGetParams: Codable, Hashable, Sendable {
  /// The opaque Keychain reference; never a key's bytes.
  public var secretRef: String
  /// The exact authorized use, such as `model:openai`.
  public var purpose: String

  /// Creates a broker request. The receiving broker strictly validates its wire bounds.
  public init(secretRef: String, purpose: String) {
    self.secretRef = secretRef
    self.purpose = purpose
  }

  private enum CodingKeys: String, CodingKey {
    case secretRef
    case purpose
  }

  /// Decodes the bounded fields, ignoring unknown fields as required by protocol §3.5.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    secretRef = try container.decode(
      BoundedText<HostSecretReferenceBounds>.self, forKey: .secretRef
    ).rawValue
    purpose = try container.decode(
      BoundedText<HostSecretPurposeBounds>.self, forKey: .purpose
    ).rawValue
  }
}

/// Secret bytes are usable only in memory; they must never enter logs, events or storage.
public struct HostKeychainGetResult: Codable, Hashable, Sendable {
  /// The released value, bounded to 16 KiB by the broker before transmission.
  public var value: String
  /// The maximum in-memory lifetime in milliseconds; not permission to persist the value.
  public var ttlMs: Int64

  /// Creates a memory-only release.
  public init(value: String, ttlMs: Int64) {
    self.value = value
    self.ttlMs = ttlMs
  }
}

private enum HostSecretReferenceBounds: TextBounds {
  static let maxLength = 512
  static let wireName = "HostSecretReference"
}

private enum HostSecretPurposeBounds: TextBounds {
  static let maxLength = 512
  static let wireName = "HostSecretPurpose"
}
