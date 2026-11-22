import CryptoKit
import Foundation

/// The Noise handshake patterns Memoshi's device layer uses (Noise revision 34, §7 and §9).
///
/// - ``pairing``: `Noise_IKpsk2_25519_ChaChaPoly_SHA256`, keyed by the QR code's one-time key
///   (D82): the new device knows the paired device's static key from the code and mixes the
///   code's key at the end of the second message.
/// - ``link``: `Noise_IK_25519_ChaChaPoly_SHA256` between two already paired devices.
public struct NoisePattern: Hashable, Sendable {
  enum Token: Hashable, Sendable {
    case e
    case s
    case ee
    case es
    case se
    case ss
    case psk
  }

  /// The pattern's name inside the protocol name, such as `IKpsk2`.
  public let name: String
  let initiatorPreMessage: [Token]
  let responderPreMessage: [Token]
  let messages: [[Token]]
  let cipher: NoiseCipher

  /// Pairing: IKpsk2 with ChaChaPoly and SHA-256.
  public static let pairing = NoisePattern(
    name: "IKpsk2", initiatorPreMessage: [], responderPreMessage: [.s],
    messages: [[.e, .es, .s, .ss], [.e, .ee, .se, .psk]], cipher: .chaChaPoly)

  /// Links between paired devices: IK with ChaChaPoly and SHA-256.
  public static let link = NoisePattern(
    name: "IK", initiatorPreMessage: [], responderPreMessage: [.s],
    messages: [[.e, .es, .s, .ss], [.e, .ee, .se]], cipher: .chaChaPoly)

  /// The full protocol name, such as `Noise_IKpsk2_25519_ChaChaPoly_SHA256`.
  public var protocolName: String { "Noise_\(name)_25519_\(cipher.rawValue)_SHA256" }

  var usesPSK: Bool { messages.contains { $0.contains(.psk) } }

  /// This pattern with another cipher; only the published-vector tests use AESGCM.
  func with(cipher: NoiseCipher) -> NoisePattern {
    NoisePattern(
      name: name, initiatorPreMessage: initiatorPreMessage,
      responderPreMessage: responderPreMessage, messages: messages, cipher: cipher)
  }

  /// One-way K (`-> s`, `<- s`, then `-> e, es, ss`), used only to check the published vector.
  static let oneWayK = NoisePattern(
    name: "K", initiatorPreMessage: [.s], responderPreMessage: [.s], messages: [[.e, .es, .ss]],
    cipher: .chaChaPoly)
}

/// One side of a Noise handshake (§5.3). Call ``writeMessage(payload:)`` and
/// ``readMessage(_:)`` in the pattern's order, then ``split()`` for the transport.
public struct NoiseHandshake: Sendable {
  /// Whether this side sent the first message.
  public let isInitiator: Bool
  private let pattern: NoisePattern
  private var symmetric: NoiseSymmetricState
  private let localStatic: Curve25519.KeyAgreement.PrivateKey
  private var localEphemeral: Curve25519.KeyAgreement.PrivateKey?
  private var remoteStaticBytes: Data?
  private var remoteEphemeralBytes: Data?
  private let psk: Data?
  private var messageIndex = 0

  /// Starts a handshake.
  ///
  /// - Parameters:
  ///   - pattern: ``NoisePattern/pairing`` or ``NoisePattern/link``.
  ///   - initiator: Whether this side sends the first message.
  ///   - prologue: Bytes both sides must agree on; a mismatch fails the handshake.
  ///   - localStatic: This device's key-agreement key.
  ///   - remoteStatic: The responder's static key, which an IK initiator must know.
  ///   - psk: The 32-byte pre-shared key, required by a PSK pattern and refused otherwise.
  public init(
    pattern: NoisePattern, initiator: Bool, prologue: Data,
    localStatic: Curve25519.KeyAgreement.PrivateKey,
    remoteStatic: Curve25519.KeyAgreement.PublicKey? = nil, psk: Data? = nil
  ) throws(NoiseError) {
    try self.init(
      pattern: pattern, initiator: initiator, prologue: prologue, localStatic: localStatic,
      remoteStatic: remoteStatic, psk: psk, fixedEphemeral: nil)
  }

  /// The designated initializer. `fixedEphemeral` exists only for the published test vectors.
  init(
    pattern: NoisePattern, initiator: Bool, prologue: Data,
    localStatic: Curve25519.KeyAgreement.PrivateKey,
    remoteStatic: Curve25519.KeyAgreement.PublicKey?, psk: Data?,
    fixedEphemeral: Curve25519.KeyAgreement.PrivateKey?
  ) throws(NoiseError) {
    guard pattern.usesPSK == (psk != nil) else {
      throw .invalidState(pattern.usesPSK ? "This pattern needs a PSK" : "Unexpected PSK")
    }
    if let psk, psk.count != 32 { throw .invalidState("A PSK is 32 bytes") }
    let needsRemote =
      initiator
      ? pattern.responderPreMessage.contains(.s) : pattern.initiatorPreMessage.contains(.s)
    guard needsRemote == (remoteStatic != nil) else {
      throw .invalidState(needsRemote ? "Missing remote static key" : "Unexpected remote static")
    }
    self.isInitiator = initiator
    self.pattern = pattern
    self.localStatic = localStatic
    self.localEphemeral = fixedEphemeral
    self.remoteStaticBytes = remoteStatic?.rawRepresentation
    self.psk = psk
    symmetric = NoiseSymmetricState(protocolName: pattern.protocolName, cipher: pattern.cipher)
    symmetric.mixHash(prologue)
    // Pre-message keys: the initiator's first, then the responder's (§7.1).
    for (owner, tokens) in [
      (true, pattern.initiatorPreMessage), (false, pattern.responderPreMessage),
    ] {
      for token in tokens {
        guard token == .s else { throw .invalidState("Unsupported pre-message token") }
        if owner == initiator {
          symmetric.mixHash(localStatic.publicKey.rawRepresentation)
        } else if let remote = remoteStaticBytes {
          symmetric.mixHash(remote)
        }
      }
    }
  }

  /// Whether every handshake message has been written or read.
  public var isComplete: Bool { messageIndex == pattern.messages.count }

  /// Whether the next step is ``writeMessage(payload:)``.
  public var isMyTurn: Bool { !isComplete && (messageIndex % 2 == 0) == isInitiator }

  /// The transcript hash, for channel binding once the handshake is complete.
  public var handshakeHash: Data { symmetric.handshakeHash }

  /// The peer's static key, once it has been received or was known in advance.
  public var remoteStatic: Curve25519.KeyAgreement.PublicKey? {
    remoteStaticBytes.flatMap { try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: $0) }
  }

  /// Writes the next handshake message carrying `payload`.
  public mutating func writeMessage(payload: Data = Data()) throws(NoiseError) -> Data {
    guard isMyTurn else { throw .invalidState("Not this side's message") }
    var message = Data()
    for token in pattern.messages[messageIndex] {
      switch token {
      case .e:
        let ephemeral = localEphemeral ?? Curve25519.KeyAgreement.PrivateKey()
        localEphemeral = ephemeral
        let bytes = ephemeral.publicKey.rawRepresentation
        message.append(bytes)
        symmetric.mixHash(bytes)
        if pattern.usesPSK { symmetric.mixKey(bytes) }
      case .s:
        message.append(try symmetric.encryptAndHash(localStatic.publicKey.rawRepresentation))
      case .psk:
        guard let psk else { throw .invalidState("Missing PSK") }
        symmetric.mixKeyAndHash(psk)
      case .ee, .es, .se, .ss:
        symmetric.mixKey(try agreement(token))
      }
    }
    message.append(try symmetric.encryptAndHash(payload))
    guard message.count <= noiseMaximumMessage else { throw .messageTooLarge }
    messageIndex += 1
    return message
  }

  /// Reads the peer's next handshake message and returns its payload.
  public mutating func readMessage(_ message: Data) throws(NoiseError) -> Data {
    guard !isComplete, !isMyTurn else { throw .invalidState("Not the peer's message") }
    guard message.count <= noiseMaximumMessage else { throw .messageTooLarge }
    var rest = message[...]
    for token in pattern.messages[messageIndex] {
      switch token {
      case .e:
        guard rest.count >= noiseKeyLength else { throw .malformedMessage }
        let bytes = Data(rest.prefix(noiseKeyLength))
        rest = rest.dropFirst(noiseKeyLength)
        remoteEphemeralBytes = bytes
        symmetric.mixHash(bytes)
        if pattern.usesPSK { symmetric.mixKey(bytes) }
      case .s:
        let length = noiseKeyLength + (symmetric.cipherState.hasKey ? noiseTagLength : 0)
        guard rest.count >= length else { throw .malformedMessage }
        let encrypted = Data(rest.prefix(length))
        rest = rest.dropFirst(length)
        remoteStaticBytes = try symmetric.decryptAndHash(encrypted)
      case .psk:
        guard let psk else { throw .invalidState("Missing PSK") }
        symmetric.mixKeyAndHash(psk)
      case .ee, .es, .se, .ss:
        symmetric.mixKey(try agreement(token))
      }
    }
    let payload = try symmetric.decryptAndHash(Data(rest))
    messageIndex += 1
    return payload
  }

  /// The transport session; valid only once the handshake is complete.
  public func split() throws(NoiseError) -> NoiseTransport {
    guard isComplete else { throw .invalidState("The handshake is not complete") }
    let (initiatorToResponder, responderToInitiator) = symmetric.split()
    return NoiseTransport(
      handshakeHash: symmetric.handshakeHash,
      sender: isInitiator ? initiatorToResponder : responderToInitiator,
      receiver: isInitiator ? responderToInitiator : initiatorToResponder)
  }

  /// X25519 for `ee`, `es`, `se` or `ss`; the first letter is the initiator's key (§7.3).
  private func agreement(_ token: NoisePattern.Token) throws(NoiseError) -> Data {
    let (initiatorKey, responderKey): (Character, Character) =
      switch token {
      case .ee: ("e", "e")
      case .es: ("e", "s")
      case .se: ("s", "e")
      default: ("s", "s")
      }
    let localKind = isInitiator ? initiatorKey : responderKey
    let remoteKind = isInitiator ? responderKey : initiatorKey
    guard let local = localKind == "e" ? localEphemeral : localStatic else {
      throw .invalidState("Missing local ephemeral key")
    }
    guard let remoteBytes = remoteKind == "e" ? remoteEphemeralBytes : remoteStaticBytes else {
      throw .invalidState("Missing remote key")
    }
    do {
      let remote = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteBytes)
      let shared = try local.sharedSecretFromKeyAgreement(with: remote)
      let bytes = shared.withUnsafeBytes { Data($0) }
      // A low-order point yields all zeros; never mix that into the key schedule.
      guard bytes.contains(where: { $0 != 0 }) else { throw NoiseError.invalidPublicKey }
      return bytes
    } catch {
      throw .invalidPublicKey
    }
  }
}

/// A completed handshake's transport: one cipher state per direction, with empty associated data
/// (§5.1). Messages must be opened in the order they were sealed; any tampered, replayed,
/// reordered or truncated message fails authentication.
public struct NoiseTransport: Sendable {
  /// The handshake's transcript hash, for channel binding.
  public let handshakeHash: Data
  private var sender: NoiseCipherState
  private var receiver: NoiseCipherState

  init(handshakeHash: Data, sender: NoiseCipherState, receiver: NoiseCipherState) {
    self.handshakeHash = handshakeHash
    self.sender = sender
    self.receiver = receiver
  }

  /// The largest plaintext one message can carry.
  public static let maximumPlaintext = noiseMaximumMessage - noiseTagLength

  /// Encrypts the next outgoing message.
  public mutating func seal(_ plaintext: Data) throws(NoiseError) -> Data {
    guard plaintext.count <= Self.maximumPlaintext else { throw .messageTooLarge }
    return try sender.encrypt(ad: Data(), plaintext: plaintext)
  }

  /// Encrypts the next outgoing message and hands it to `send`. The message uses up its
  /// counter only when `send` returns: one the carrier refused never left this device, so the
  /// next message takes its place and the peer stays in step.
  ///
  /// `send` must throw only when it took no byte of the message (`FrameChannel.send`'s
  /// contract). A `send` that throws after handing over any part would make the next message
  /// reuse this counter under the same key.
  mutating func seal(_ plaintext: Data, send: (Data) throws -> Void) throws {
    var next = sender
    guard plaintext.count <= Self.maximumPlaintext else { throw NoiseError.messageTooLarge }
    let sealed = try next.encrypt(ad: Data(), plaintext: plaintext)
    try send(sealed)
    sender = next
  }

  /// Decrypts the next incoming message.
  public mutating func open(_ ciphertext: Data) throws(NoiseError) -> Data {
    guard ciphertext.count <= noiseMaximumMessage else { throw .messageTooLarge }
    return try receiver.decrypt(ad: Data(), ciphertext: ciphertext)
  }
}
