/// Who caused something: `{kind, id?}` (object-model.md §1.2, events.md §2).
public struct Actor: Codable, Hashable, Sendable {
  /// The kind of actor.
  public var kind: ActorKind
  /// The actor's ID: `usr_`, `bot_`, or for a trigger the `rtn_`, `wch_` or `wak_` that fired.
  public var id: String?

  /// Creates an actor.
  public init(kind: ActorKind, id: String? = nil) {
    self.kind = kind
    self.id = id
  }
}

/// A reference to one object: `{kind, id}`, where `kind` is an object name from
/// object-model.md (`task`, `approval`, …) or `system`.
public struct ObjectRef: Codable, Hashable, Sendable {
  /// The object's kind.
  public var kind: String
  /// The object's ID, or a fixed name such as `memoshid` for `system`.
  public var id: String

  /// Creates a reference.
  public init(kind: String, id: String) {
    self.kind = kind
    self.id = id
  }
}

/// Why work exists (object-model.md §3.3).
public struct Origin: Codable, Hashable, Sendable {
  /// The immediate origin.
  public var kind: OriginKind
  /// The origin's ID: `usr_`, `bot_`, `rtn_`, `wak_` or `wch_`; for `webhook` and
  /// `connector_event` the routine whose trigger fired; for `app` the program; absent for
  /// `intent`.
  public var id: String?
  /// The origin at the root of the delegation chain.
  public var rootKind: OriginKind
  /// Bot-to-bot hops from the root, 0 at the root and at most 8.
  public var hops: Hops

  /// Creates an origin.
  public init(kind: OriginKind, id: String? = nil, rootKind: OriginKind, hops: Hops = .root) {
    self.kind = kind
    self.id = id
    self.rootKind = rootKind
    self.hops = hops
  }
}

/// Token use and cost (object-model.md §4.7 `usage`).
public struct Usage: Codable, Hashable, Sendable {
  /// Input tokens.
  public var inputTokens: Int64
  /// Output tokens.
  public var outputTokens: Int64
  /// Input tokens served from the provider's cache.
  public var cacheReadTokens: Int64
  /// Input tokens written to the provider's cache.
  public var cacheWriteTokens: Int64
  /// Cost in integer micro-USD.
  public var costMicroUsd: Int64
  /// Whether the cost is known; a model without prices reports `false`.
  public var costKnown: Bool

  /// Creates a usage record.
  public init(
    inputTokens: Int64, outputTokens: Int64, cacheReadTokens: Int64, cacheWriteTokens: Int64,
    costMicroUsd: Int64, costKnown: Bool
  ) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.cacheReadTokens = cacheReadTokens
    self.cacheWriteTokens = cacheWriteTokens
    self.costMicroUsd = costMicroUsd
    self.costKnown = costKnown
  }
}

/// The snapshot position of a list or get result: `{seq, cseq?}` (protocol.md §8).
public struct AsOf: Codable, Hashable, Sendable {
  /// The device log's `seq` the result reflects.
  public var seq: Int64
  /// The conversation's `cseq`, for conversation-scoped results.
  public var cseq: Int64?

  /// Creates a snapshot position.
  public init(seq: Int64, cseq: Int64? = nil) {
    self.seq = seq
    self.cseq = cseq
  }
}

/// The policy exposure flags of a call (policy.md).
public struct Exposure: Codable, Hashable, Sendable {
  /// The context holds untrusted content.
  public var untrusted: Bool
  /// The context holds private data.
  public var privateData: Bool

  /// Creates exposure flags.
  public init(untrusted: Bool, privateData: Bool) {
    self.untrusted = untrusted
    self.privateData = privateData
  }
}

/// A range of protocol major versions: `{min, max}` (protocol.md §3.5).
public struct ProtocolRange: Codable, Hashable, Sendable {
  /// The oldest version supported.
  public var min: Int
  /// The newest version supported.
  public var max: Int

  /// Creates a range.
  public init(min: Int, max: Int) {
    self.min = min
    self.max = max
  }
}

/// A model choice: `{ref, effort?}`, where `ref` is `provider/model` or `default`
/// (object-model.md §4.3 `model`).
public struct ModelRef: Codable, Hashable, Sendable {
  /// `provider/model`, or `default`.
  public var ref: ModelName
  /// The thinking level.
  public var effort: ThinkingEffort?

  /// Creates a model choice.
  public init(ref: ModelName, effort: ThinkingEffort? = nil) {
    self.ref = ref
    self.effort = effort
  }
}

/// A device's proof that it checked its owner with Face ID, Touch ID or the passcode before a
/// T4 or T5 decision (protocol.md §5.6, policy.md §10.1). The signature covers the decision, so
/// the runner can verify it came from that device.
public struct DeviceAuthProof: Codable, Hashable, Sendable {
  /// How the owner was checked.
  public var method: DeviceAuthMethod
  /// The device that checked.
  public var deviceId: DeviceID
  /// When it checked.
  public var checkedAt: Int64
  /// The device's signature over the decision.
  public var signature: Base64Bytes

  /// Creates a proof.
  public init(
    method: DeviceAuthMethod, deviceId: DeviceID, checkedAt: Int64, signature: Base64Bytes
  ) {
    self.method = method
    self.deviceId = deviceId
    self.checkedAt = checkedAt
    self.signature = signature
  }
}

/// Parameters for methods that take none. Always encoded as `{}`.
public struct EmptyParams: Codable, Hashable, Sendable {
  private enum CodingKeys: CodingKey {}

  /// Creates empty parameters.
  public init() {}

  /// Requires a JSON object.
  public init(from decoder: any Decoder) throws {
    _ = try decoder.container(keyedBy: CodingKeys.self)
  }

  /// Encodes `{}`.
  public func encode(to encoder: any Encoder) throws {
    _ = encoder.container(keyedBy: CodingKeys.self)
  }
}
