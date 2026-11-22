/// One message of the device layer (protocol.md §12): `{msgId, type, from, to, sentAt,
/// payload}`. Every message travels encrypted to the device group, names its sender and
/// recipient, and applies once by `msgId`, whichever link delivers it (§12.1, §12.3).
///
/// A message type this build does not know decodes as
/// ``DeviceMessageBody/unknown(type:raw:)`` and is reported to the decoder's
/// ``ProtocolDiagnosticsSink``.
public struct DeviceMessage: Codable, Hashable, Sendable {
  /// The message's unique ID; a message that arrives twice applies once.
  public var msgId: ULID
  /// The sender: a device, or the lease authority for its compare-and-swap answers.
  public var from: DeviceAddress
  /// The recipient.
  public var to: DeviceAddress
  /// When it was sent, Unix milliseconds.
  public var sentAt: Int64
  /// The typed message.
  public var body: DeviceMessageBody

  /// Creates a device message.
  public init(
    msgId: ULID, from: DeviceAddress, to: DeviceAddress, sentAt: Int64, body: DeviceMessageBody
  ) {
    self.msgId = msgId
    self.from = from
    self.to = to
    self.sentAt = sentAt
    self.body = body
  }

  /// The message type, such as `lease.claim`.
  public var type: String { body.type }

  private enum CodingKeys: String, CodingKey {
    case msgId
    case type
    case from
    case to
    case sentAt
    case payload
  }

  /// Decodes a device message. An unknown type or undecodable payload becomes `.unknown` and a
  /// diagnostic, unless decoding is strict.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let msgId = try container.decode(ULID.self, forKey: .msgId)
    let from = try container.decode(DeviceAddress.self, forKey: .from)
    let to = try container.decode(DeviceAddress.self, forKey: .to)
    let sentAt = try container.decode(Int64.self, forKey: .sentAt)
    let type = try container.decode(String.self, forKey: .type)

    func keepUnknown(_ reason: ProtocolDiagnostic.Reason, _ detail: String) throws
      -> DeviceMessageBody
    {
      if decoder.isStrictProtocolDecoding {
        throw DecodingError.dataCorruptedError(
          forKey: .type, in: container, debugDescription: detail)
      }
      let raw = try container.decode(JSONValue.self, forKey: .payload)
      decoder.reportProtocolDiagnostic(
        ProtocolDiagnostic(
          reason: reason, type: type, typeVersion: nil, seq: nil, conversationId: nil,
          codingPath: decoder.protocolCodingPath,
          detail: detail))
      return .unknown(type: type, raw: raw)
    }

    let body: DeviceMessageBody
    if let payloadType = DeviceMessageRegistry.payloadType(for: type) {
      do {
        body = try Self.decodePayload(payloadType, from: container)
      } catch {
        body = try keepUnknown(.undecodableDeviceMessage, "\(type) payload: \(error)")
      }
    } else {
      body = try keepUnknown(.unknownDeviceMessageType, "Unknown device message type \(type)")
    }
    self.init(msgId: msgId, from: from, to: to, sentAt: sentAt, body: body)
  }

  private static func decodePayload<Payload: DeviceMessagePayload>(
    _ payloadType: Payload.Type, from container: KeyedDecodingContainer<CodingKeys>
  ) throws -> DeviceMessageBody {
    try container.decode(Payload.self, forKey: .payload).asBody
  }

  /// Encodes the message.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(msgId, forKey: .msgId)
    try container.encode(body.type, forKey: .type)
    try container.encode(from, forKey: .from)
    try container.encode(to, forKey: .to)
    try container.encode(sentAt, forKey: .sentAt)
    switch body {
    case .unknown(_, let raw):
      try container.encode(raw, forKey: .payload)
    default:
      if let payload = body.payload {
        try container.encode(payload, forKey: .payload)
      }
    }
  }
}

/// A sender or recipient on the device layer, tagged by `kind`: `{kind: "device", deviceId}`
/// names one device, and `{kind: "group"}`, `{kind: "authority"}` and `{kind: "relay"}` carry no
/// device.
public enum DeviceAddress: Hashable, Sendable {
  /// One device.
  case device(DeviceID)
  /// Every device in the device group.
  case group
  /// The lease authority: the user's CloudKit database, otherwise the relay.
  case authority
  /// The relay, as a store for effect intents or the mailbox.
  case relay
  /// A kind this build does not know, kept whole.
  case unknown(kind: String, raw: JSONValue)
}

extension DeviceAddress: Codable, WireShaped {
  private enum CodingKeys: String, CodingKey {
    case kind
  }

  /// The four kinds; only `device` has a field.
  public static var wireShape: WireShape {
    .union(
      discriminator: "kind",
      variants: [
        WireVariant(tag: "device", fields: [DeviceAddressTarget.self]),
        WireVariant(tag: "group", fields: []),
        WireVariant(tag: "authority", fields: []),
        WireVariant(tag: "relay", fields: []),
      ])
  }

  /// Decodes an address by its `kind`. An unknown kind becomes `.unknown` unless decoding is
  /// strict.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(String.self, forKey: .kind)
    switch kind {
    case "device": self = .device(try DeviceAddressTarget(from: decoder).deviceId)
    case "group": self = .group
    case "authority": self = .authority
    case "relay": self = .relay
    default:
      if decoder.isStrictProtocolDecoding {
        throw DecodingError.dataCorruptedError(
          forKey: .kind, in: container, debugDescription: "Unknown device address kind \(kind)")
      }
      self = .unknown(kind: kind, raw: try JSONValue(from: decoder))
    }
  }

  /// Encodes the address's `kind` and, for a device, its `deviceId`.
  public func encode(to encoder: any Encoder) throws {
    let kind: String
    switch self {
    case .device(let deviceId):
      kind = "device"
      try DeviceAddressTarget(deviceId: deviceId).encode(to: encoder)
    case .group: kind = "group"
    case .authority: kind = "authority"
    case .relay: kind = "relay"
    case .unknown(_, let raw):
      try raw.encode(to: encoder)
      return
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
  }
}

/// The field a `device` address carries.
private struct DeviceAddressTarget: Codable {
  let deviceId: DeviceID
}

/// A typed device message payload. Each conforming type is one message of protocol.md §12.
public protocol DeviceMessagePayload: Codable, Hashable, Sendable {
  /// The message type, such as `lease.claim`.
  static var messageType: String { get }
  /// This payload wrapped as its ``DeviceMessageBody`` case.
  var asBody: DeviceMessageBody { get }
}

/// Every device message this build reads and writes.
public enum DeviceMessageRegistry {
  /// The registered payload types.
  public static let payloadTypes: [any DeviceMessagePayload.Type] = [
    DeviceHello.self,
    PairHello.self,
    PairWelcome.self,
    PairConfirm.self,
    GroupCommit.self,
    GroupCommitResult.self,
    LeaseRequest.self,
    LeaseHandOver.self,
    LeaseClaim.self,
    LeaseClaimResult.self,
    LeaseRenew.self,
    LeaseRenewResult.self,
    LeaseRelease.self,
    LeaseGranted.self,
    LeaseConfirmed.self,
    LeaseFenced.self,
    ReplicaSubscribe.self,
    ReplicaChange.self,
    ReplicaSnapshot.self,
    ReplicaAck.self,
    MessageForward.self,
    MessageForwardResult.self,
    IntentForward.self,
    IntentResult.self,
    EffectIntent.self,
    EffectAck.self,
  ]

  private static let payloadTypesByType: [String: any DeviceMessagePayload.Type] = Dictionary(
    uniqueKeysWithValues: payloadTypes.map { ($0.messageType, $0) })

  /// The payload type registered for a message type.
  public static func payloadType(for type: String) -> (any DeviceMessagePayload.Type)? {
    payloadTypesByType[type]
  }
}

/// A typed device message: one case per registered type, plus an explicit unknown case.
public enum DeviceMessageBody: Hashable, Sendable {
  case deviceHello(DeviceHello)
  case pairHello(PairHello)
  case pairWelcome(PairWelcome)
  case pairConfirm(PairConfirm)
  case groupCommit(GroupCommit)
  case groupCommitResult(GroupCommitResult)
  case leaseRequest(LeaseRequest)
  case leaseHandOver(LeaseHandOver)
  case leaseClaim(LeaseClaim)
  case leaseClaimResult(LeaseClaimResult)
  case leaseRenew(LeaseRenew)
  case leaseRenewResult(LeaseRenewResult)
  case leaseRelease(LeaseRelease)
  case leaseGranted(LeaseGranted)
  case leaseConfirmed(LeaseConfirmed)
  case leaseFenced(LeaseFenced)
  case replicaSubscribe(ReplicaSubscribe)
  case replicaChange(ReplicaChange)
  case replicaSnapshot(ReplicaSnapshot)
  case replicaAck(ReplicaAck)
  case messageForward(MessageForward)
  case messageForwardResult(MessageForwardResult)
  case intentForward(IntentForward)
  case intentResult(IntentResult)
  case effectIntent(EffectIntent)
  case effectAck(EffectAck)
  /// A message type this build does not know, or a payload that failed to decode.
  case unknown(type: String, raw: JSONValue)

  /// The typed payload; `nil` for `.unknown`.
  public var payload: (any DeviceMessagePayload)? {
    switch self {
    case .deviceHello(let payload): payload
    case .pairHello(let payload): payload
    case .pairWelcome(let payload): payload
    case .pairConfirm(let payload): payload
    case .groupCommit(let payload): payload
    case .groupCommitResult(let payload): payload
    case .leaseRequest(let payload): payload
    case .leaseHandOver(let payload): payload
    case .leaseClaim(let payload): payload
    case .leaseClaimResult(let payload): payload
    case .leaseRenew(let payload): payload
    case .leaseRenewResult(let payload): payload
    case .leaseRelease(let payload): payload
    case .leaseGranted(let payload): payload
    case .leaseConfirmed(let payload): payload
    case .leaseFenced(let payload): payload
    case .replicaSubscribe(let payload): payload
    case .replicaChange(let payload): payload
    case .replicaSnapshot(let payload): payload
    case .replicaAck(let payload): payload
    case .messageForward(let payload): payload
    case .messageForwardResult(let payload): payload
    case .intentForward(let payload): payload
    case .intentResult(let payload): payload
    case .effectIntent(let payload): payload
    case .effectAck(let payload): payload
    case .unknown: nil
    }
  }

  /// The message type, such as `lease.claim`.
  public var type: String {
    if case .unknown(let type, _) = self { return type }
    return payload.map { Swift.type(of: $0).messageType } ?? ""
  }
}
