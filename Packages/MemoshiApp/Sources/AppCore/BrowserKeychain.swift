import Foundation
import LocalAuthentication
import Security

/// Nonsecret browser account metadata. Only this reference and origin may enter preferences.
public struct BrowserLoginMetadata: Codable, Equatable, Sendable {
  /// Browser-only opaque reference, not usable through the model-key broker.
  public let secretRef: String
  /// Exact HTTPS origin permitted to receive the login.
  public let origin: String
  /// Whether the item excludes iCloud Keychain synchronization.
  public let thisDeviceOnly: Bool
}

/// A transient browser-only release. It cannot be encoded into an event or report.
public struct BrowserCredentialRelease: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  /// Exact origin checked against the atomic Keychain result.
  public let origin: String
  /// The reference whose revocation must be rechecked immediately before fill.
  public let secretRef: String
  private let username: String
  private let password: String
  private let issuedAt: ContinuousClock.Instant
  private let lifetime: Duration

  init(
    secretRef: String, origin: String, username: String, password: String,
    issuedAt: ContinuousClock.Instant = .now, lifetime: Duration = .seconds(15)
  ) {
    self.secretRef = secretRef
    self.origin = origin
    self.username = username
    self.password = password
    self.issuedAt = issuedAt
    self.lifetime = lifetime
  }

  /// Uses the bytes synchronously, after validating the exact origin and monotonic expiry.
  /// The app must call the broker's `validate` immediately before this operation as well.
  public func withValues<Result>(for origin: String, _ body: (String, String) throws -> Result)
    throws -> Result
  {
    try Task.checkCancellation()
    try requireCurrent(origin: origin, now: .now)
    return try body(username, password)
  }

  func requireCurrent(origin: String, now: ContinuousClock.Instant) throws {
    guard self.origin == origin else { throw BrowserKeychainError.originMismatch }
    guard now >= issuedAt, now - issuedAt < lifetime else { throw BrowserKeychainError.expired }
  }

  /// Never prints account values, digests or references.
  public var description: String { "BrowserCredentialRelease(<redacted>)" }
  /// Never prints account values, digests or references.
  public var debugDescription: String { description }
  /// Prevents `dump` from exposing protected stored properties.
  public var customMirror: Mirror { Mirror(self, children: ["credential": "<redacted>"]) }
}

/// Sanitized failures never include Security diagnostics, account names or credential bytes.
public enum BrowserKeychainError: String, Error, Sendable {
  case invalidAccessGroup, invalidOrigin, invalidValue, invalidReference, originMismatch
  case expired, revoked, missingEntitlement, accessDenied, interactionNotAllowed, unavailable
  case itemNotFound, invalidItem, operationFailed
}

/// The existing app-only broker boundary, scoped to browser logins in its own service. It uses
/// the same validated secret access group as ModelKeychain, never a default/legacy Keychain.
/// No browser credential is forwarded to memoshid. Valid operations require the signed app.
public actor BrowserKeychain {
  private static let service = "com.mehmetcanbudak.memoshi.browser-logins"
  private static let suffix = ".com.mehmetcanbudak.memoshi.secrets"
  private let accessGroup: String?
  private var revoked: Set<String> = []

  /// Accepts only the group derived by the app from its authenticated signing team.
  public init(accessGroup: String) {
    let team = accessGroup.dropLast(Self.suffix.count).utf8
    self.accessGroup =
      accessGroup.hasSuffix(Self.suffix) && team.count == 10
        && team.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) ? accessGroup : nil
  }

  /// Saves a user-entered test account, bound to one exact HTTPS origin. This does not grant
  /// permission to use it; a matching site/account authorization and sign-in Card are separate.
  public func put(
    origin: String, username: String, password: String,
    thisDeviceOnly: Bool = false
  ) throws -> BrowserLoginMetadata {
    try Task.checkCancellation()
    guard let origin = BrowserAuthorization.canonicalOrigin(origin, requireHTTPS: true) else {
      throw BrowserKeychainError.invalidOrigin
    }
    // Only the password is secret: a user name often matches part of its site's host.
    guard !username.isEmpty, !password.isEmpty, username.utf8.count <= 16_384,
      password.utf8.count <= 16_384, !origin.contains(password)
    else { throw BrowserKeychainError.invalidValue }
    let reference = "bkc_" + UUID().uuidString.lowercased()
    let metadata = BrowserLoginMetadata(
      secretRef: reference, origin: origin, thisDeviceOnly: thisDeviceOnly)
    var attributes = try identity(reference)
    attributes[kSecAttrGeneric as String] = try JSONEncoder().encode(metadata)
    attributes[kSecValueData as String] = try JSONEncoder().encode(
      Payload(username: username, password: password))
    attributes[kSecAttrSynchronizable as String] = !thisDeviceOnly
    attributes[kSecAttrAccessible as String] =
      thisDeviceOnly
      ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlock
    try Self.requireSuccess(SecItemAdd(attributes as CFDictionary, nil))
    return metadata
  }

  /// Releases just before native fill, without prompting or falling back to another Keychain.
  public func release(secretRef: String, origin: String) throws -> BrowserCredentialRelease {
    try Task.checkCancellation()
    try Self.requireReference(secretRef)
    guard let origin = BrowserAuthorization.canonicalOrigin(origin, requireHTTPS: true) else {
      throw BrowserKeychainError.invalidOrigin
    }
    guard !revoked.contains(secretRef) else { throw BrowserKeychainError.revoked }
    var query = try identity(secretRef)
    query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnAttributes as String] = true
    query[kSecReturnData as String] = true
    var result: CFTypeRef?
    try Self.requireSuccess(SecItemCopyMatching(query as CFDictionary, &result))
    try Task.checkCancellation()
    guard let attributes = result as? [String: Any],
      let binding = attributes[kSecAttrGeneric as String] as? Data,
      let metadata = try? JSONDecoder().decode(BrowserLoginMetadata.self, from: binding),
      metadata.secretRef == secretRef,
      BrowserAuthorization.canonicalOrigin(metadata.origin, requireHTTPS: true) == metadata.origin,
      attributes[kSecAttrService as String] as? String == Self.service,
      attributes[kSecAttrAccount as String] as? String == secretRef,
      attributes[kSecAttrAccessGroup as String] as? String == accessGroup,
      attributes[kSecAttrSynchronizable as String] as? Bool == !metadata.thisDeviceOnly,
      let accessibility = attributes[kSecAttrAccessible as String] as? String,
      accessibility
        == (metadata.thisDeviceOnly
        ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlock)
        as String,
      let bytes = attributes[kSecValueData as String] as? Data, bytes.count <= 200_000,
      let payload = try? JSONDecoder().decode(Payload.self, from: bytes),
      !payload.username.isEmpty, !payload.password.isEmpty,
      payload.username.utf8.count <= 16_384, payload.password.utf8.count <= 16_384
    else { throw BrowserKeychainError.invalidItem }
    guard metadata.origin == origin else { throw BrowserKeychainError.originMismatch }
    return BrowserCredentialRelease(
      secretRef: secretRef, origin: origin,
      username: payload.username, password: payload.password)
  }

  /// Rechecks local revocation, cancellation and TTL after asynchronous document checks and
  /// immediately before dispatching the isolated-world fill. A release is never cached.
  public func validate(_ release: BrowserCredentialRelease, origin: String) throws {
    try Task.checkCancellation()
    guard !revoked.contains(release.secretRef) else { throw BrowserKeychainError.revoked }
    try release.requireCurrent(origin: origin, now: .now)
  }

  /// Revokes outstanding releases before attempting deletion. A failed OS delete cannot make
  /// an already released value usable again in this process. Retry deletion explicitly.
  public func revoke(secretRef: String) throws {
    try Task.checkCancellation()
    try Self.requireReference(secretRef)
    revoked.insert(secretRef)
    var query = try identity(secretRef)
    query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecItemNotFound { try Self.requireSuccess(status) }
  }

  private func identity(_ reference: String) throws -> [String: Any] {
    guard let accessGroup else { throw BrowserKeychainError.invalidAccessGroup }
    let authentication = LAContext()
    authentication.interactionNotAllowed = true
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service, kSecAttrAccount as String: reference,
      kSecAttrAccessGroup as String: accessGroup, kSecUseDataProtectionKeychain as String: true,
      kSecUseAuthenticationContext as String: authentication,
    ]
  }

  private static func requireReference(_ reference: String) throws {
    guard reference.hasPrefix("bkc_"), reference.utf8.count == 40,
      UUID(uuidString: String(reference.dropFirst(4))) != nil
    else { throw BrowserKeychainError.invalidReference }
  }

  private static func requireSuccess(_ status: OSStatus) throws {
    switch status {
    case errSecSuccess: return
    case errSecMissingEntitlement: throw BrowserKeychainError.missingEntitlement
    case errSecAuthFailed, errSecRestrictedAPI, errSecNoAccessForItem, errSecUserCanceled:
      throw BrowserKeychainError.accessDenied
    case errSecInteractionNotAllowed, errSecInteractionRequired:
      throw BrowserKeychainError.interactionNotAllowed
    case errSecNotAvailable, errSecServiceNotAvailable, errSecDataNotAvailable:
      throw BrowserKeychainError.unavailable
    case errSecItemNotFound: throw BrowserKeychainError.itemNotFound
    case errSecDecode: throw BrowserKeychainError.invalidItem
    default: throw BrowserKeychainError.operationFailed
    }
  }

  private struct Payload: Codable {
    let username: String
    let password: String
  }
}
