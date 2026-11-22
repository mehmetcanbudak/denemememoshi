import CryptoKit
import Darwin
import Foundation
import MemoshiProtocol
import Security

/// A device's own identity: its device ID and its two key pairs, one to sign and one for key
/// agreement (protocol.md §12.1).
///
/// The Keychain owner below stores both private halves as one device-only item. Explicit
/// 0600-file import/export remains available only for synthetic qualification identities.
public struct DeviceIdentity: Sendable {
  /// The device's ID.
  public let deviceID: DeviceID
  /// The device's display name.
  public let name: String
  /// The device's platform.
  public let platform: DevicePlatform
  /// What other devices learn about this one.
  public let peer: DevicePeer
  private let signingKeyBytes: Data
  private let agreementKeyBytes: Data

  /// Generates fresh keys for a new device.
  public static func generate(
    name: String, platform: DevicePlatform, at now: Int64 = DeviceClock.wallMilliseconds()
  ) throws -> DeviceIdentity {
    try DeviceIdentity(
      deviceID: try DeviceID("dev_" + DeviceULID.make(at: now)), name: name, platform: platform,
      signingKeyBytes: Curve25519.Signing.PrivateKey().rawRepresentation,
      agreementKeyBytes: Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
  }

  /// Validates both private keys and derives the public identity.
  private init(
    deviceID: DeviceID, name: String, platform: DevicePlatform, signingKeyBytes: Data,
    agreementKeyBytes: Data
  ) throws {
    let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: signingKeyBytes)
    let agreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: agreementKeyBytes)
    self.deviceID = deviceID
    self.name = name
    self.platform = platform
    self.signingKeyBytes = signingKeyBytes
    self.agreementKeyBytes = agreementKeyBytes
    peer = DevicePeer(
      deviceID: deviceID, signingKey: signing.publicKey.rawRepresentation,
      agreementKey: agreement.publicKey.rawRepresentation)
  }

  /// The key-agreement key, Noise's static key.
  public func agreementKey() throws -> Curve25519.KeyAgreement.PrivateKey {
    try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: agreementKeyBytes)
  }

  /// Signs `data` with the device's signing key (Ed25519).
  public func sign(_ data: Data) throws -> Data {
    try Curve25519.Signing.PrivateKey(rawRepresentation: signingKeyBytes).signature(for: data)
  }

  /// Domain-separated local encryption, not a device-group or MLS key.
  func stateEncryptionKey() -> SymmetricKey {
    HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: agreementKeyBytes),
      salt: Data("memoshi.device-state.v1".utf8), info: Data(deviceID.rawValue.utf8),
      outputByteCount: 32)
  }

  /// A purpose-separated key for this device's encrypted local state, never MLS group
  /// encryption or an export of either signing/agreement private key.
  public func derivedStateEncryptionKey(purpose: String) throws -> SymmetricKey {
    guard !purpose.isEmpty, purpose.utf8.count <= 128,
      purpose.rangeOfCharacter(from: .controlCharacters) == nil
    else { throw DeviceLayerError.invalid("device state key purpose") }
    return HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: agreementKeyBytes),
      salt: Data("memoshi.device-derived-state.v1".utf8),
      info: Data((deviceID.rawValue + "\u{0}" + purpose).utf8), outputByteCount: 32)
  }

  fileprivate func encoded() throws -> Data {
    try JSONEncoder().encode(
      Stored(
        deviceId: deviceID, name: name, platform: platform, signingKey: signingKeyBytes,
        agreementKey: agreementKeyBytes))
  }

  fileprivate static func decoded(_ bytes: Data) throws -> DeviceIdentity {
    let stored = try JSONDecoder().decode(Stored.self, from: bytes)
    return try DeviceIdentity(
      deviceID: stored.deviceId, name: stored.name, platform: stored.platform,
      signingKeyBytes: stored.signingKey, agreementKeyBytes: stored.agreementKey)
  }

  private struct Stored: Codable {
    var deviceId: DeviceID
    var name: String
    var platform: DevicePlatform
    var signingKey: Data
    var agreementKey: Data
  }

  /// Writes the identity to a new 0600 file. Development and qualification use only.
  public func write(to url: URL) throws {
    let bytes = try encoded()
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw DeviceLayerError.io("create \(url.lastPathComponent)") }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try handle.write(contentsOf: bytes)
    try handle.synchronize()
  }

  /// Reads an identity written by ``write(to:)``; both keys are validated.
  public static func read(from url: URL) throws -> DeviceIdentity {
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else { throw DeviceLayerError.io("identity open") }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
      info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0, info.st_nlink == 1,
      info.st_size > 0, info.st_size <= 16_384
    else { throw DeviceLayerError.io("private qualification identity required") }
    return try decoded(handle.readToEnd() ?? Data())
  }
}

/// The Keychain calls the identity owner makes. Tests substitute an in-memory store with the same
/// matching rules; nothing else may.
struct DeviceKeychainCalls: Sendable {
  var add: @Sendable (_ item: [String: Any]) -> OSStatus
  var copy: @Sendable (_ query: [String: Any]) -> (status: OSStatus, item: [String: Any]?)
  var update: @Sendable (_ query: [String: Any], _ changes: [String: Any]) -> OSStatus
  var delete: @Sendable (_ query: [String: Any]) -> OSStatus

  static let system = DeviceKeychainCalls(
    add: { SecItemAdd($0 as CFDictionary, nil) },
    copy: { query in
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      return (status, result as? [String: Any])
    },
    update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
    delete: { SecItemDelete($0 as CFDictionary) })
}

/// Exact data-protection Keychain ownership for one local device identity. No synchronization,
/// default-Keychain fallback, prompting, silent replacement or on-disk private-key fallback.
public actor DeviceIdentityKeychain {
  private static let service = "com.mehmetcanbudak.memoshi.devices"
  /// Stored with a new identity until its first enrollment completes. Only an item that still
  /// carries it can be removed; an item without it (also one created before it existed) counts
  /// as enrolled.
  private static let pendingEnrollment = Data("memoshi.enrollment.pending".utf8)
  private static let completedEnrollment = Data("memoshi.enrollment.complete".utf8)
  private let accessGroup: String
  private let account: String
  private let calls: DeviceKeychainCalls

  /// The host supplies its validated, provisioned identity access group and a stable local name.
  public init(accessGroup: String, account: String = "primary-device") throws {
    try self.init(accessGroup: accessGroup, account: account, calls: .system)
  }

  init(accessGroup: String, account: String, calls: DeviceKeychainCalls) throws {
    let suffix = ".com.mehmetcanbudak.memoshi.devices"
    let team = accessGroup.dropLast(suffix.count).utf8
    guard accessGroup.hasSuffix(suffix), team.count == 10,
      team.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }),
      !account.isEmpty, account.utf8.count <= 128,
      account.rangeOfCharacter(from: .controlCharacters) == nil
    else { throw DeviceLayerError.invalid("device Keychain scope") }
    self.accessGroup = accessGroup
    self.account = account
    self.calls = calls
  }

  private var attributes: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrService as String: Self.service,
      kSecAttrAccessGroup as String: accessGroup,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
      kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
    ]
  }

  /// Loads the exact item, checking protection attributes from the same atomic result.
  public func load() throws -> DeviceIdentity {
    var query = attributes
    query[kSecReturnData as String] = true
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let result = calls.copy(query)
    try Self.requireSuccess(result.status)
    guard let item = result.item,
      item[kSecAttrAccessGroup as String] as? String == accessGroup,
      item[kSecAttrService as String] as? String == Self.service,
      item[kSecAttrAccount as String] as? String == account,
      item[kSecAttrSynchronizable as String] as? Bool == false,
      item[kSecAttrAccessible as String] as? String
        == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
      let data = item[kSecValueData as String] as? Data, data.count <= 16_384
    else { throw DeviceLayerError.invalid("device Keychain item") }
    return try DeviceIdentity.decoded(data)
  }

  /// Explicit first enrollment only. Duplicate, locked or unavailable items are not replaced.
  /// The new identity is marked as pending until ``completeEnrollment()``.
  public func create(name: String, platform: DevicePlatform) throws -> DeviceIdentity {
    let identity = try DeviceIdentity.generate(name: name, platform: platform)
    var item = attributes
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    item[kSecAttrGeneric as String] = Self.pendingEnrollment
    item[kSecValueData as String] = try identity.encoded()
    try Self.requireSuccess(calls.add(item))
    return identity
  }

  /// Records that this device's first enrollment completed: its durable device state exists
  /// and the identity must never be removed by ``removeUnenrolled()`` again. Call it once the
  /// enrollment that followed ``create(name:platform:)`` has succeeded. Idempotent; an identity
  /// that carries no pending mark already counts as enrolled.
  public func completeEnrollment() throws {
    var query = attributes
    query[kSecAttrGeneric as String] = Self.pendingEnrollment
    let status = calls.update(query, [kSecAttrGeneric as String: Self.completedEnrollment])
    guard status != errSecItemNotFound else { return }
    try Self.requireSuccess(status)
  }

  /// Removes the identity of a first enrollment that never completed, so that enrollment can
  /// start again; it also works after a restart. The delete matches only an item that is still
  /// marked pending, so an enrolled identity, one created before the mark existed, and an absent
  /// one are all refused with nothing removed. Device state already written for the removed
  /// identity is encrypted to it and unreadable afterwards: the host removes that directory.
  public func removeUnenrolled() throws {
    var query = attributes
    query[kSecAttrGeneric as String] = Self.pendingEnrollment
    let status = calls.delete(query)
    guard status != errSecItemNotFound else {
      throw DeviceLayerError.invalid("device identity is enrolled or absent")
    }
    try Self.requireSuccess(status)
  }

  private static func requireSuccess(_ status: OSStatus) throws {
    guard status == errSecSuccess else {
      // Status only: never private bytes, scope/account values or arbitrary Security text.
      throw DeviceLayerError.io("device Keychain status \(status)")
    }
  }
}

/// Another device's public identity: its ID and its two public keys.
public struct DevicePeer: Hashable, Sendable, Codable {
  /// The device's ID.
  public let deviceID: DeviceID
  /// The Ed25519 public signing key, 32 bytes.
  public let signingKey: Data
  /// The X25519 public key-agreement key, 32 bytes; Noise's static key.
  public let agreementKey: Data

  /// Wraps raw public keys.
  public init(deviceID: DeviceID, signingKey: Data, agreementKey: Data) {
    self.deviceID = deviceID
    self.signingKey = signingKey
    self.agreementKey = agreementKey
  }

  /// Reads the protocol's base64 public keys.
  public init(deviceID: DeviceID, publicKeys: DevicePublicKeys) throws {
    guard let signing = Data(base64Encoded: publicKeys.signing.rawValue),
      let agreement = Data(base64Encoded: publicKeys.agreement.rawValue),
      signing.count == 32, agreement.count == 32
    else { throw DeviceLayerError.invalid("public keys") }
    self.init(deviceID: deviceID, signingKey: signing, agreementKey: agreement)
  }

  /// The protocol's base64 form of the public keys.
  public var publicKeys: DevicePublicKeys {
    get throws {
      DevicePublicKeys(
        signing: try Base64Bytes(signingKey.base64EncodedString()),
        agreement: try Base64Bytes(agreementKey.base64EncodedString()))
    }
  }

  /// The key-agreement key as a CryptoKit key.
  public var agreementPublicKey: Curve25519.KeyAgreement.PublicKey {
    get throws { try Curve25519.KeyAgreement.PublicKey(rawRepresentation: agreementKey) }
  }

  /// Whether `signature` is this device's Ed25519 signature over `data`.
  public func verify(_ signature: Data, over data: Data) -> Bool {
    guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: signingKey) else {
      return false
    }
    return key.isValidSignature(signature, for: data)
  }
}

/// Device-layer failures outside the Noise state machine.
public enum DeviceLayerError: Error, Equatable, Sendable {
  /// A value failed validation.
  case invalid(String)
  /// A file or socket operation failed.
  case io(String)
  /// The link or relay closed.
  case closed
  /// The receive queue refused a frame at its aggregate byte or count limit.
  case receiveOverflow
  /// A bounded wait expired.
  case timeout(String)
  /// A frame exceeded the framing limit.
  case frameTooLarge(Int)
  /// The peer is not, or no longer, a paired device.
  case unknownPeer
  /// The peer broke the protocol.
  case protocolViolation(String)
  /// A membership change of this device is not complete yet, so nothing may be sealed now:
  /// the change itself, or the host's completion of an add whose final hello must be the
  /// device's first seal of the new group state. Nothing was sealed; retry later.
  case membershipChangePending
}

/// Monotonic ULID text for message IDs and generated device IDs.
public enum DeviceULID {
  private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)

  /// A ULID: 48 bits of Unix milliseconds, then 80 random bits.
  public static func make(at milliseconds: Int64 = DeviceClock.wallMilliseconds()) -> String {
    var value = [UInt8](repeating: 0, count: 16)
    let time = UInt64(max(0, min(milliseconds, 0xFFFF_FFFF_FFFF)))
    for index in 0..<6 { value[index] = UInt8(truncatingIfNeeded: time >> (8 * (5 - index))) }
    var random = SystemRandomNumberGenerator()
    for index in 6..<16 { value[index] = UInt8.random(in: .min ... .max, using: &random) }
    // 128 bits as 26 base32 characters: the first carries the top 3 bits.
    var characters = [UInt8](repeating: 0, count: 26)
    var high = UInt64(0)
    var low = UInt64(0)
    for index in 0..<8 { high = high << 8 | UInt64(value[index]) }
    for index in 8..<16 { low = low << 8 | UInt64(value[index]) }
    for position in (0..<26).reversed() {
      characters[position] = alphabet[Int(low & 31)]
      low = low >> 5 | (high & 31) << 59
      high >>= 5
    }
    return String(decoding: characters, as: UTF8.self)
  }

  /// A fresh message ID.
  public static func next() throws -> ULID { try ULID(make()) }
}

/// Clocks the device layer uses.
public enum DeviceClock {
  /// Wall time in Unix milliseconds: lease expiry, QR expiry and message timestamps.
  public static func wallMilliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  /// System-wide monotonic nanoseconds (`CLOCK_UPTIME_RAW`), comparable across processes on one
  /// Mac; the measurement timestamps.
  public static func monotonicNanoseconds() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
  }
}
