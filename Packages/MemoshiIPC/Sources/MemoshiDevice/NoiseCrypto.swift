import CryptoKit
import Foundation

/// Noise protocol failures (revision 34). Every failure aborts the handshake or link it occurs on.
public enum NoiseError: Error, Equatable, Sendable {
  /// A received message or field had the wrong length.
  case malformedMessage
  /// Authenticated decryption failed: a wrong key, a tampered, replayed or reordered message.
  case decryptFailed
  /// A Diffie-Hellman input was not a usable X25519 public key.
  case invalidPublicKey
  /// A message would exceed Noise's 65,535-byte limit.
  case messageTooLarge
  /// The 64-bit nonce is exhausted; the session must end.
  case nonceExhausted
  /// A handshake step was called out of order, or a required key is missing.
  case invalidState(String)
}

/// The AEAD cipher functions this build implements. Memoshi uses ChaChaPoly; AESGCM exists only so
/// the published cacophony vectors, which use it, can check the shared handshake code.
enum NoiseCipher: String, Sendable {
  case chaChaPoly = "ChaChaPoly"
  case aesGCM = "AESGCM"
}

/// The largest Noise message, ciphertext and tag included.
let noiseMaximumMessage = 65_535
/// The ChaChaPoly and AESGCM tag length.
let noiseTagLength = 16
/// SHA-256's output length, Noise's HASHLEN.
let noiseHashLength = 32
/// X25519's public key length, Noise's DHLEN.
let noiseKeyLength = 32

/// One direction's cipher state: a key and a 64-bit message counter (Noise §5.1).
struct NoiseCipherState: Sendable {
  let cipher: NoiseCipher
  private(set) var key: SymmetricKey?
  private(set) var nonce: UInt64 = 0

  init(cipher: NoiseCipher, key: SymmetricKey? = nil) {
    self.cipher = cipher
    self.key = key
  }

  var hasKey: Bool { key != nil }

  mutating func initializeKey(_ key: SymmetricKey) {
    self.key = key
    nonce = 0
  }

  /// Encrypts with the current nonce, then increments it. Without a key the plaintext passes
  /// through, as Noise specifies for the start of a handshake.
  mutating func encrypt(ad: Data, plaintext: Data) throws(NoiseError) -> Data {
    guard let key else { return plaintext }
    guard nonce < UInt64.max else { throw .nonceExhausted }
    let sealed: Data
    do {
      switch cipher {
      case .chaChaPoly:
        let box = try ChaChaPoly.seal(
          plaintext, using: key, nonce: ChaChaPoly.Nonce(data: nonceBytes()), authenticating: ad)
        sealed = box.ciphertext + box.tag
      case .aesGCM:
        let box = try AES.GCM.seal(
          plaintext, using: key, nonce: AES.GCM.Nonce(data: nonceBytes()), authenticating: ad)
        sealed = box.ciphertext + box.tag
      }
    } catch {
      throw .invalidState("AEAD seal failed: \(error)")
    }
    nonce += 1
    return sealed
  }

  /// Decrypts and authenticates with the current nonce. A failure leaves the nonce unchanged.
  mutating func decrypt(ad: Data, ciphertext: Data) throws(NoiseError) -> Data {
    guard let key else { return ciphertext }
    guard nonce < UInt64.max else { throw .nonceExhausted }
    guard ciphertext.count >= noiseTagLength else { throw .malformedMessage }
    let body = ciphertext.prefix(ciphertext.count - noiseTagLength)
    let tag = ciphertext.suffix(noiseTagLength)
    let opened: Data
    do {
      switch cipher {
      case .chaChaPoly:
        let box = try ChaChaPoly.SealedBox(
          nonce: ChaChaPoly.Nonce(data: nonceBytes()), ciphertext: body, tag: tag)
        opened = try ChaChaPoly.open(box, using: key, authenticating: ad)
      case .aesGCM:
        let box = try AES.GCM.SealedBox(
          nonce: AES.GCM.Nonce(data: nonceBytes()), ciphertext: body, tag: tag)
        opened = try AES.GCM.open(box, using: key, authenticating: ad)
      }
    } catch {
      throw .decryptFailed
    }
    nonce += 1
    return opened
  }

  /// 32 zero bits, then the counter: little-endian for ChaChaPoly, big-endian for AESGCM.
  private func nonceBytes() -> Data {
    var bytes = Data(count: 4)
    switch cipher {
    case .chaChaPoly: withUnsafeBytes(of: nonce.littleEndian) { bytes.append(contentsOf: $0) }
    case .aesGCM: withUnsafeBytes(of: nonce.bigEndian) { bytes.append(contentsOf: $0) }
    }
    return bytes
  }
}

/// The handshake's chaining key, transcript hash and current cipher state (Noise §5.2).
struct NoiseSymmetricState: Sendable {
  private(set) var chainingKey: Data
  private(set) var handshakeHash: Data
  private(set) var cipherState: NoiseCipherState

  init(protocolName: String, cipher: NoiseCipher) {
    let name = Data(protocolName.utf8)
    let hash =
      name.count <= noiseHashLength
      ? name + Data(count: noiseHashLength - name.count) : NoiseHash.sha256(name)
    chainingKey = hash
    handshakeHash = hash
    cipherState = NoiseCipherState(cipher: cipher)
  }

  mutating func mixKey(_ input: Data) {
    let outputs = NoiseHash.hkdf(chainingKey: chainingKey, input: input, count: 2)
    chainingKey = outputs[0]
    cipherState.initializeKey(SymmetricKey(data: outputs[1]))
  }

  mutating func mixHash(_ data: Data) {
    handshakeHash = NoiseHash.sha256(handshakeHash + data)
  }

  mutating func mixKeyAndHash(_ input: Data) {
    let outputs = NoiseHash.hkdf(chainingKey: chainingKey, input: input, count: 3)
    chainingKey = outputs[0]
    mixHash(outputs[1])
    cipherState.initializeKey(SymmetricKey(data: outputs[2]))
  }

  mutating func encryptAndHash(_ plaintext: Data) throws(NoiseError) -> Data {
    let ciphertext = try cipherState.encrypt(ad: handshakeHash, plaintext: plaintext)
    mixHash(ciphertext)
    return ciphertext
  }

  mutating func decryptAndHash(_ ciphertext: Data) throws(NoiseError) -> Data {
    let plaintext = try cipherState.decrypt(ad: handshakeHash, ciphertext: ciphertext)
    mixHash(ciphertext)
    return plaintext
  }

  /// The two transport cipher states: initiator to responder first.
  func split() -> (NoiseCipherState, NoiseCipherState) {
    let outputs = NoiseHash.hkdf(chainingKey: chainingKey, input: Data(), count: 2)
    return (
      NoiseCipherState(cipher: cipherState.cipher, key: SymmetricKey(data: outputs[0])),
      NoiseCipherState(cipher: cipherState.cipher, key: SymmetricKey(data: outputs[1]))
    )
  }
}

/// SHA-256, HMAC-SHA256 and Noise's HKDF (§4.3).
enum NoiseHash {
  static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

  static func hmac(key: Data, data: Data) -> Data {
    Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
  }

  /// Two or three 32-byte outputs.
  static func hkdf(chainingKey: Data, input: Data, count: Int) -> [Data] {
    let temporary = hmac(key: chainingKey, data: input)
    var outputs: [Data] = []
    var previous = Data()
    for index in 1...count {
      previous = hmac(key: temporary, data: previous + Data([UInt8(index)]))
      outputs.append(previous)
    }
    return outputs
  }
}
