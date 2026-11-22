import Foundation
import LocalAuthentication
import Security

/// Nonsecret information that may be persisted or sent over the app/daemon protocol.
public struct ModelKeyMetadata: Codable, Equatable, Sendable {
  /// Opaque item identity; safe to retain instead of the credential value.
  public let secretRef: String
  /// The provider permitted by this model-key binding.
  public let providerID: String
  /// User-facing nonsecret name stored with the Keychain item.
  public let label: String
  /// Whether the item excludes iCloud Keychain synchronization.
  public let thisDeviceOnly: Bool

  /// Creates metadata without retaining the protected key bytes.
  public init(secretRef: String, providerID: String, label: String, thisDeviceOnly: Bool) {
    self.secretRef = secretRef
    self.providerID = providerID
    self.label = label
    self.thisDeviceOnly = thisDeviceOnly
  }
}

/// A memory-only release. Callers must discard the value when its TTL expires.
/// Deliberately not Codable: only ModelKeyMetadata belongs in preferences or durable state.
public struct ModelKeyRelease: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
  CustomReflectable
{
  /// Protected bytes released only for the authenticated request's purpose.
  public let value: String
  /// Maximum validity of this release in milliseconds, measured by its consumer.
  public let ttlMs: Int64

  /// Creates a temporary release; the value must never be encoded into durable state.
  public init(value: String, ttlMs: Int64) {
    self.value = value
    self.ttlMs = ttlMs
  }

  /// A printable representation that never contains the key.
  public var description: String { "ModelKeyRelease(<redacted>)" }
  /// The same redacted representation for debugger-oriented printing.
  public var debugDescription: String { description }
  /// Prevents `dump` and other reflection from exposing the key.
  public var customMirror: Mirror { Mirror(self, children: ["value": "<redacted>"]) }
}

/// Sanitized failures contain neither secret bytes nor raw Security diagnostics.
public enum ModelKeychainError: Error, Equatable, Sendable, LocalizedError {
  case invalidAccessGroup
  case invalidProviderID
  case invalidLabel
  case invalidValue
  case invalidSecretRef
  case unsupportedPurpose
  case purposeMismatch
  case missingEntitlement
  case accessDenied
  case interactionNotAllowed
  case unavailable
  case itemNotFound
  case invalidItem
  case duplicateItem
  case operationFailed

  /// A safe user-facing explanation without input values or raw Security diagnostics.
  public var errorDescription: String? {
    switch self {
    case .invalidAccessGroup:
      String(
        localized:
          "The model Keychain access group is not configured for the validated signing team.",
        bundle: #bundle)
    case .invalidProviderID:
      String(localized: "The model provider identifier is invalid.", bundle: #bundle)
    case .invalidLabel:
      String(
        localized: "Enter a nonempty label without control characters or the model key.",
        bundle: #bundle)
    case .invalidValue:
      String(localized: "Enter a nonempty model key no larger than 16 KiB.", bundle: #bundle)
    case .invalidSecretRef:
      String(localized: "The model key reference is invalid.", bundle: #bundle)
    case .unsupportedPurpose:
      String(
        localized: "This Keychain store only releases keys for model providers.", bundle: #bundle)
    case .purposeMismatch:
      String(
        localized: "The model key is not authorized for the requested provider.", bundle: #bundle)
    case .missingEntitlement:
      String(
        localized:
          "Model Keychain access requires the app's authorized access-group entitlement and provisioning profile.",
        bundle: #bundle)
    case .accessDenied:
      String(localized: "The system denied access to the model Keychain.", bundle: #bundle)
    case .interactionNotAllowed:
      String(
        localized:
          "The model Keychain requires an unlock or system authentication before it is available.",
        bundle: #bundle)
    case .unavailable:
      String(
        localized: "The data protection Keychain is unavailable in this user session.",
        bundle: #bundle)
    case .itemNotFound:
      String(
        localized: "The model key was not found in the configured Keychain access group.",
        bundle: #bundle)
    case .invalidItem:
      String(
        localized: "The stored model key or its authorization metadata is invalid.", bundle: #bundle
      )
    case .duplicateItem:
      String(localized: "The model key reference already exists.", bundle: #bundle)
    case .operationFailed:
      String(localized: "The model Keychain operation failed.", bundle: #bundle)
    }
  }
}

/// Owns only model-provider secrets in the data protection Keychain.
/// SecItem operations run in this actor, not on MainActor, and never fall back to another store.
/// The caller authenticates its peer before reading and again before forwarding a release.
public actor ModelKeychain {
  private static let service = "com.mehmetcanbudak.memoshi.models"
  private static let accessGroupSuffix = ".com.mehmetcanbudak.memoshi.secrets"
  private static let maximumValueBytes = 16 * 1024
  private let accessGroup: String?

  /// The app supplies the group derived from its validated signing team, never a default group.
  public init(accessGroup: String) {
    self.accessGroup = Self.isAccessGroup(accessGroup) ? accessGroup : nil
  }

  /// Creates a new opaque reference; the value is used only as the item's protected data.
  public func put(
    providerID: String,
    label: String,
    value: String,
    thisDeviceOnly: Bool = false
  ) async throws -> ModelKeyMetadata {
    try Task.checkCancellation()
    guard Self.isProviderID(providerID) else { throw ModelKeychainError.invalidProviderID }
    guard Self.isValue(value) else { throw ModelKeychainError.invalidValue }
    guard providerID.contains(value) == false else { throw ModelKeychainError.invalidProviderID }
    guard
      label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
      label.rangeOfCharacter(from: .controlCharacters) == nil,
      label.contains(value) == false
    else { throw ModelKeychainError.invalidLabel }

    let secretRef = "kc_\(UUID().uuidString.lowercased())"
    let binding = Binding(
      version: 1,
      scope: "model",
      providerID: providerID,
      purpose: "model:\(providerID)",
      thisDeviceOnly: thisDeviceOnly
    )
    guard let bindingData = try? JSONEncoder().encode(binding) else {
      throw ModelKeychainError.operationFailed
    }
    var attributes = try identityAttributes(secretRef: secretRef)
    attributes[kSecAttrLabel as String] = label
    attributes[kSecAttrGeneric as String] = bindingData
    attributes[kSecAttrSynchronizable as String] = thisDeviceOnly == false
    attributes[kSecAttrAccessible as String] =
      thisDeviceOnly
      ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlock
    attributes[kSecValueData as String] = Data(value.utf8)
    try Self.requireSuccess(SecItemAdd(attributes as CFDictionary, nil))
    return ModelKeyMetadata(
      secretRef: secretRef,
      providerID: providerID,
      label: label,
      thisDeviceOnly: thisDeviceOnly
    )
  }

  /// Releases only the exact stored model-provider purpose, without prompting for authentication.
  public func get(secretRef: String, purpose: String) async throws -> ModelKeyRelease {
    try Task.checkCancellation()
    try Self.requireSecretRef(secretRef)
    guard purpose.hasPrefix("model:"), Self.isProviderID(String(purpose.dropFirst(6))) else {
      throw ModelKeychainError.unsupportedPurpose
    }
    var query = try identityAttributes(secretRef: secretRef)
    query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnAttributes as String] = true
    query[kSecReturnData as String] = true
    var result: CFTypeRef?
    try Self.requireSuccess(SecItemCopyMatching(query as CFDictionary, &result))
    try Task.checkCancellation()

    // Check authorization and scope from the same atomic result as the protected data.
    guard
      let attributes = result as? [String: Any],
      let bindingData = attributes[kSecAttrGeneric as String] as? Data,
      let binding = try? JSONDecoder().decode(Binding.self, from: bindingData),
      binding.version == 1,
      binding.scope == "model",
      Self.isProviderID(binding.providerID),
      binding.purpose == "model:\(binding.providerID)",
      attributes[kSecAttrService as String] as? String == Self.service,
      attributes[kSecAttrAccount as String] as? String == secretRef,
      attributes[kSecAttrAccessGroup as String] as? String == accessGroup,
      let synchronizable = attributes[kSecAttrSynchronizable as String] as? Bool,
      synchronizable == (binding.thisDeviceOnly == false),
      let accessibility = attributes[kSecAttrAccessible as String] as? String
    else { throw ModelKeychainError.invalidItem }
    let expectedAccessibility =
      binding.thisDeviceOnly
      ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlock
    guard accessibility == expectedAccessibility as String else {
      throw ModelKeychainError.invalidItem
    }
    guard purpose == binding.purpose else { throw ModelKeychainError.purposeMismatch }
    guard
      let data = attributes[kSecValueData as String] as? Data,
      data.isEmpty == false,
      data.count <= Self.maximumValueBytes,
      let value = String(data: data, encoding: .utf8)
    else { throw ModelKeychainError.invalidItem }
    return ModelKeyRelease(value: value, ttlMs: 60_000)
  }

  /// Deleting a synchronizable key removes its synced copies as well. Deleting an absent key
  /// succeeds, so a delete whose outcome was uncertain can be repeated.
  public func delete(secretRef: String) async throws {
    try Task.checkCancellation()
    try Self.requireSecretRef(secretRef)
    var query = try identityAttributes(secretRef: secretRef)
    query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecItemNotFound { try Self.requireSuccess(status) }
  }

  private func identityAttributes(secretRef: String) throws -> [String: Any] {
    guard let accessGroup else { throw ModelKeychainError.invalidAccessGroup }
    let authentication = LAContext()
    authentication.interactionNotAllowed = true
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: secretRef,
      kSecAttrAccessGroup as String: accessGroup,
      kSecUseDataProtectionKeychain as String: true,
      kSecUseAuthenticationContext as String: authentication,
    ]
  }

  private static func isAccessGroup(_ value: String) -> Bool {
    guard value.hasSuffix(accessGroupSuffix) else { return false }
    let team = value.dropLast(accessGroupSuffix.count).utf8
    return team.count == 10 && team.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
  }

  private static func isProviderID(_ value: String) -> Bool {
    let bytes = value.utf8
    guard (1...128).contains(bytes.count), let first = bytes.first else { return false }
    func isAlphanumeric(_ byte: UInt8) -> Bool {
      (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
    }
    return isAlphanumeric(first)
      && bytes.allSatisfy { isAlphanumeric($0) || $0 == 45 || $0 == 46 || $0 == 95 }
  }

  private static func isValue(_ value: String) -> Bool {
    value.isEmpty == false && value.utf8.count <= maximumValueBytes
  }

  private static func requireSecretRef(_ value: String) throws {
    guard
      value.hasPrefix("kc_"),
      value.utf8.count == 39,
      UUID(uuidString: String(value.dropFirst(3))) != nil
    else { throw ModelKeychainError.invalidSecretRef }
  }

  private static func requireSuccess(_ status: OSStatus) throws {
    switch status {
    case errSecSuccess: return
    case errSecMissingEntitlement: throw ModelKeychainError.missingEntitlement
    case errSecAuthFailed, errSecRestrictedAPI, errSecNoAccessForItem, errSecUserCanceled:
      throw ModelKeychainError.accessDenied
    case errSecInteractionNotAllowed, errSecInteractionRequired:
      throw ModelKeychainError.interactionNotAllowed
    case errSecNotAvailable, errSecServiceNotAvailable, errSecDataNotAvailable:
      throw ModelKeychainError.unavailable
    case errSecItemNotFound: throw ModelKeychainError.itemNotFound
    case errSecDecode: throw ModelKeychainError.invalidItem
    case errSecDuplicateItem: throw ModelKeychainError.duplicateItem
    default: throw ModelKeychainError.operationFailed
    }
  }

  private struct Binding: Codable {
    let version: Int
    let scope: String
    let providerID: String
    let purpose: String
    let thisDeviceOnly: Bool
  }
}
