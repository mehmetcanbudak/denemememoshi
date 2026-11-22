/// `lease.request`, the bot's home Mac (or another awake Mac while it is away) → the runner:
/// hand this idle conversation over (protocol.md §12.6).
public struct LeaseRequest: DeviceMessagePayload {
  /// `lease.request`.
  public static let messageType = "lease.request"

  /// The conversation.
  public var conversationId: ConversationID
  /// The observed current runner epoch. A delayed request must never move a newer lease.
  public var expectedEpoch: Int64
  /// Why: `rebalance`.
  public var reason: LeaseRequestReason

  /// Creates the payload.
  public init(conversationId: ConversationID, reason: LeaseRequestReason, expectedEpoch: Int64) {
    self.conversationId = conversationId
    self.expectedEpoch = expectedEpoch
    self.reason = reason
  }

  /// `.leaseRequest(self)`.
  public var asBody: DeviceMessageBody { .leaseRequest(self) }
}

/// `lease.handOver`, runner → the device taking over: the runner finished its step, stopped
/// writing and published every change up to `lastRseq`.
public struct LeaseHandOver: DeviceMessagePayload {
  /// `lease.handOver`.
  public static let messageType = "lease.handOver"

  /// The conversation.
  public var conversationId: ConversationID
  /// The runner's lease epoch, which the next claim expects.
  public var epoch: Int64
  /// The device taking over.
  public var toDeviceId: DeviceID
  /// The last replication sequence published.
  public var lastRseq: Int64

  /// Creates the payload.
  public init(conversationId: ConversationID, epoch: Int64, toDeviceId: DeviceID, lastRseq: Int64) {
    self.conversationId = conversationId
    self.epoch = epoch
    self.toDeviceId = toDeviceId
    self.lastRseq = lastRseq
  }

  /// `.leaseHandOver(self)`.
  public var asBody: DeviceMessageBody { .leaseHandOver(self) }
}

/// `lease.claim`, a device → the lease authority: a compare-and-swap that succeeds only while
/// the authority still holds `expectedEpoch`; the new epoch is `expectedEpoch + 1`.
public struct LeaseClaim: DeviceMessagePayload {
  /// `lease.claim`.
  public static let messageType = "lease.claim"

  /// The conversation.
  public var conversationId: ConversationID
  /// The epoch the claimant expects the authority to hold; `null` for a new conversation's
  /// first claim, which expects no record.
  public var expectedEpoch: Int64?
  /// When the new lease lapses unless renewed.
  public var expiresAt: Int64

  /// Creates the payload.
  public init(conversationId: ConversationID, expectedEpoch: Int64?, expiresAt: Int64) {
    self.conversationId = conversationId
    self.expectedEpoch = expectedEpoch
    self.expiresAt = expiresAt
  }

  private enum CodingKeys: String, CodingKey {
    case conversationId
    case expectedEpoch
    case expiresAt
  }

  /// Decodes the claim. `expectedEpoch` must be present, even when it is `null`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    conversationId = try container.decode(ConversationID.self, forKey: .conversationId)
    expectedEpoch = try container.decode(Int64?.self, forKey: .expectedEpoch)
    expiresAt = try container.decode(Int64.self, forKey: .expiresAt)
  }

  /// Encodes the claim, writing `"expectedEpoch": null` for a first claim.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(conversationId, forKey: .conversationId)
    try container.encode(expectedEpoch, forKey: .expectedEpoch)
    try container.encode(expiresAt, forKey: .expiresAt)
  }

  /// `.leaseClaim(self)`.
  public var asBody: DeviceMessageBody { .leaseClaim(self) }
}

/// `lease.claimResult`, the lease authority → the claimant: whether the compare-and-swap won,
/// and the record the authority now holds.
public struct LeaseClaimResult: DeviceMessagePayload {
  /// `lease.claimResult`.
  public static let messageType = "lease.claimResult"

  /// The conversation.
  public var conversationId: ConversationID
  /// Whether the claimant now holds the lease.
  public var granted: Bool
  /// The epoch the authority holds now: the new epoch when granted, otherwise the current one.
  public var epoch: Int64
  /// The device that holds the lease; absent while the lease is free.
  public var runnerDeviceId: DeviceID?
  /// When the held lease lapses; absent while the lease is free.
  public var expiresAt: Int64?

  /// Creates the payload.
  public init(
    conversationId: ConversationID, granted: Bool, epoch: Int64, runnerDeviceId: DeviceID? = nil,
    expiresAt: Int64? = nil
  ) {
    self.conversationId = conversationId
    self.granted = granted
    self.epoch = epoch
    self.runnerDeviceId = runnerDeviceId
    self.expiresAt = expiresAt
  }

  /// `.leaseClaimResult(self)`.
  public var asBody: DeviceMessageBody { .leaseClaimResult(self) }
}

/// `lease.renew`, runner → the lease authority: keep the lease; fails once the epoch has moved
/// on. Renewals emit no event.
public struct LeaseRenew: DeviceMessagePayload {
  /// `lease.renew`.
  public static let messageType = "lease.renew"

  /// The conversation.
  public var conversationId: ConversationID
  /// The runner's epoch.
  public var epoch: Int64
  /// The new expiry.
  public var expiresAt: Int64

  /// Creates the payload.
  public init(conversationId: ConversationID, epoch: Int64, expiresAt: Int64) {
    self.conversationId = conversationId
    self.epoch = epoch
    self.expiresAt = expiresAt
  }

  /// `.leaseRenew(self)`.
  public var asBody: DeviceMessageBody { .leaseRenew(self) }
}

/// `lease.renewResult`, the lease authority → runner: whether the renewal applied.
public struct LeaseRenewResult: DeviceMessagePayload {
  /// `lease.renewResult`.
  public static let messageType = "lease.renewResult"

  /// The conversation.
  public var conversationId: ConversationID
  /// Whether the lease was renewed; `false` means the runner is fenced.
  public var renewed: Bool
  /// The epoch the authority holds now.
  public var epoch: Int64
  /// When the lease the authority holds lapses.
  public var expiresAt: Int64

  /// Creates the payload.
  public init(conversationId: ConversationID, renewed: Bool, epoch: Int64, expiresAt: Int64) {
    self.conversationId = conversationId
    self.renewed = renewed
    self.epoch = epoch
    self.expiresAt = expiresAt
  }

  /// `.leaseRenewResult(self)`.
  public var asBody: DeviceMessageBody { .leaseRenewResult(self) }
}

/// `lease.release`, runner → the lease authority: give the lease up with no successor named,
/// after publishing every change up to `lastRseq`, so the next claim need not wait for expiry.
public struct LeaseRelease: DeviceMessagePayload {
  /// `lease.release`.
  public static let messageType = "lease.release"

  /// The conversation.
  public var conversationId: ConversationID
  /// The runner's epoch; the release applies only while the authority still holds it.
  public var epoch: Int64
  /// The last replication sequence published.
  public var lastRseq: Int64

  /// Creates the payload.
  public init(conversationId: ConversationID, epoch: Int64, lastRseq: Int64) {
    self.conversationId = conversationId
    self.epoch = epoch
    self.lastRseq = lastRseq
  }

  /// `.leaseRelease(self)`.
  public var asBody: DeviceMessageBody { .leaseRelease(self) }
}

/// `lease.granted`, the new runner → every device: the conversation's new runner and epoch.
public struct LeaseGranted: DeviceMessagePayload {
  /// `lease.granted`.
  public static let messageType = "lease.granted"

  /// The conversation.
  public var conversationId: ConversationID
  /// The new fencing epoch.
  public var epoch: Int64
  /// The new runner.
  public var runnerDeviceId: DeviceID
  /// When the lease lapses unless renewed.
  public var expiresAt: Int64
  /// Why the lease moved.
  public var reason: LeaseGrantReason

  /// Creates the payload.
  public init(
    conversationId: ConversationID, epoch: Int64, runnerDeviceId: DeviceID, expiresAt: Int64,
    reason: LeaseGrantReason
  ) {
    self.conversationId = conversationId
    self.epoch = epoch
    self.runnerDeviceId = runnerDeviceId
    self.expiresAt = expiresAt
    self.reason = reason
  }

  /// `.leaseGranted(self)`.
  public var asBody: DeviceMessageBody { .leaseGranted(self) }
}

/// `lease.confirmed`, the authority's record → the runner and every device: a lease taken by
/// direct hand-over is confirmed, so the runner is no longer provisional (D73).
public struct LeaseConfirmed: DeviceMessagePayload {
  /// `lease.confirmed`.
  public static let messageType = "lease.confirmed"

  /// The conversation.
  public var conversationId: ConversationID
  /// The confirmed epoch.
  public var epoch: Int64
  /// Where the confirmation was decided.
  public var authority: LeaseAuthority

  /// Creates the payload.
  public init(conversationId: ConversationID, epoch: Int64, authority: LeaseAuthority) {
    self.conversationId = conversationId
    self.epoch = epoch
    self.authority = authority
  }

  /// `.leaseConfirmed(self)`.
  public var asBody: DeviceMessageBody { .leaseConfirmed(self) }
}

/// `lease.fenced`, a store, replica or executing device → the sender of something stamped with
/// an older epoch: it was rejected with `lease_fenced`.
public struct LeaseFenced: DeviceMessagePayload {
  /// `lease.fenced`.
  public static let messageType = "lease.fenced"

  /// The conversation.
  public var conversationId: ConversationID
  /// The rejected epoch.
  public var staleEpoch: Int64
  /// The newest epoch the rejecting device has seen.
  public var currentEpoch: Int64
  /// The runner at the current epoch.
  public var runnerDeviceId: DeviceID
  /// What was rejected.
  public var what: FencedOperation

  /// Creates the payload.
  public init(
    conversationId: ConversationID, staleEpoch: Int64, currentEpoch: Int64,
    runnerDeviceId: DeviceID, what: FencedOperation
  ) {
    self.conversationId = conversationId
    self.staleEpoch = staleEpoch
    self.currentEpoch = currentEpoch
    self.runnerDeviceId = runnerDeviceId
    self.what = what
  }

  /// `.leaseFenced(self)`.
  public var asBody: DeviceMessageBody { .leaseFenced(self) }
}

/// Why a device asks for a lease.
public enum LeaseRequestReason: OpenEnum {
  /// An idle conversation returns to an awake Mac.
  case rebalance
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.rebalance: "rebalance"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// Why a lease moved (object-model.md §4.27 `reason`).
public enum LeaseGrantReason: OpenEnum {
  /// A new conversation's first lease.
  case created
  /// The runner was unreachable past `expiresAt`.
  case expired
  /// The runner was revoked.
  case revoked
  /// An idle conversation returned to an awake Mac.
  case rebalanced
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .created: "created", .expired: "expired", .revoked: "revoked", .rebalanced: "rebalanced",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// Where a lease grant was decided (object-model.md §4.27 `authority`).
public enum LeaseAuthority: OpenEnum {
  /// A compare-and-swap in the user's CloudKit database.
  case icloud
  /// A compare-and-swap on the relay.
  case relay
  /// A hand-over between two directly connected devices.
  case direct
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .icloud: "icloud", .relay: "relay", .direct: "direct",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// What a fencing check rejected (events.md §5.18 `lease.fenced`).
public enum FencedOperation: OpenEnum {
  /// A store write.
  case write
  /// A cross-device call.
  case toolCall
  /// A replicated change.
  case change
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .write: "write", .toolCall: "tool_call", .change: "change",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
