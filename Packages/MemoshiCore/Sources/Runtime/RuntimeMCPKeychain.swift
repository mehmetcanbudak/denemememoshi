import Foundation
import Security

/// App-owned data-protection item for PiMCP state plus the token-redaction history. The SDK's
/// state-only Keychain adapter cannot retain historical token variants across a host restart;
/// both live state and that history must therefore be committed in one protected item here.
/// This is storage only, not another release broker or a helper Keychain entitlement.
actor RuntimeMCPKeychain {
  private let service: String
  private let account: String
  private let accessGroup: String

  init(service: String, account: String, accessGroup: String) {
    self.service = service
    self.account = account
    self.accessGroup = accessGroup
  }

  nonisolated var storage: RuntimeMCPOAuthStorage {
    RuntimeMCPOAuthStorage(
      load: { try await self.load() }, save: { try await self.save($0) },
      remove: { try await self.remove() })
  }

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessGroup as String: accessGroup,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrSynchronizable as String: false,
    ]
  }

  private func load() throws -> Data? {
    var query = query
    query[kSecReturnData as String] = true
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let attributes = item as? [String: Any],
      attributes[kSecAttrService as String] as? String == service,
      attributes[kSecAttrAccount as String] as? String == account,
      attributes[kSecAttrAccessGroup as String] as? String == accessGroup,
      attributes[kSecAttrSynchronizable as String] as? Bool == false,
      attributes[kSecAttrAccessible as String] as? String
        == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
      let data = attributes[kSecValueData as String] as? Data
    else { throw RuntimeMCPError.credentialUnavailable }
    return data
  }

  private func save(_ data: Data) throws {
    let values: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
    if status == errSecItemNotFound {
      var insertion = query
      insertion.merge(values) { _, value in value }
      guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
        throw RuntimeMCPError.credentialUnavailable
      }
    } else if status != errSecSuccess {
      throw RuntimeMCPError.credentialUnavailable
    }
  }

  private func remove() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw RuntimeMCPError.credentialUnavailable
    }
  }
}
