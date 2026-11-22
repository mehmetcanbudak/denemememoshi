/// A local folder grant's access to its original source: `read` admits checked reads, and
/// `write` also admits policy-gated writes. It is this bounded profile's access, not a mode.
public enum FolderGrantPermission: OpenEnum {
  case read
  case write
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([.read: "read", .write: "write"])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// A local folder grant's lifecycle. Revoked and expired are terminal: granting the folder
/// again creates a new grant with a new ID.
public enum FolderGrantState: OpenEnum {
  case active
  case revoked
  case expired
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .active: "active", .revoked: "revoked", .expired: "expired",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// The bounded local projection of one `folder` Grant held on this device (D96). It is not the
/// full generic Grant and carries no bookmark bytes, source identity or raw filesystem error.
public struct FolderGrantSummary: Codable, Hashable, Sendable {
  /// The grant.
  public var id: GrantID
  /// The only bot it authorizes.
  public var botId: BotID
  /// The original source root the user chose.
  public var path: String
  /// The device that holds the folder.
  public var deviceId: DeviceID
  /// The current access.
  public var access: FolderGrantPermission
  /// The lifecycle state.
  public var status: FolderGrantState
  /// Starts at 1 and increments with every change; a change names the revision it expects.
  public var revision: Int64
  /// When it lapses; absent when it does not.
  public var expiresAt: Int64?
  /// When the user granted it.
  public var createdAt: Int64
  /// The latest change.
  public var updatedAt: Int64
  /// Whether it was active and its root still proved the identity it captured when observed.
  public var available: Bool

  /// Creates a projection.
  public init(
    id: GrantID, botId: BotID, path: String, deviceId: DeviceID, access: FolderGrantPermission,
    status: FolderGrantState, revision: Int64, expiresAt: Int64? = nil, createdAt: Int64,
    updatedAt: Int64, available: Bool
  ) {
    self.id = id
    self.botId = botId
    self.path = path
    self.deviceId = deviceId
    self.access = access
    self.status = status
    self.revision = revision
    self.expiresAt = expiresAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.available = available
  }
}

/// `bots.grants.list`: one bot's local folder grants (protocol.md §5.2). It needs the
/// negotiated `bots.grants.folder.v1`; this profile lists no standing `tool_rule` grants.
public enum BotsGrantsList: RPCMethod {
  /// The bot.
  public typealias Params = BotsGrantsListParams
  /// Its folder grants and the snapshot position.
  public typealias Result = BotsGrantsListResult
  /// `bots.grants.list`.
  public static let name = "bots.grants.list"
  /// Read-only, apart from durably ending grants whose deadline has passed.
  public static let isMutating = false
}

/// `bots.grants.update`: grants a newly chosen folder, or changes an existing grant's access.
/// User origin only, never from a run (protocol.md §5.2).
public enum BotsGrantsUpdate: RPCMethod {
  /// The bot and the change.
  public typealias Params = BotsGrantsUpdateParams
  /// The grant as the request left it.
  public typealias Result = BotsGrantsUpdateResult
  /// `bots.grants.update`.
  public static let name = "bots.grants.update"
  /// Changes a grant.
  public static let isMutating = true
}

/// `bots.grants.revoke`: ends a grant from the next call. Revocation is terminal.
public enum BotsGrantsRevoke: RPCMethod {
  /// The grant.
  public typealias Params = BotsGrantsRevokeParams
  /// Nothing; read the grant's ended state with `bots.grants.list`.
  public typealias Result = EmptyParams
  /// `bots.grants.revoke`.
  public static let name = "bots.grants.revoke"
  /// Ends a grant.
  public static let isMutating = true
}

/// The parameters of `bots.grants.list`.
public struct BotsGrantsListParams: Codable, Hashable, Sendable {
  /// The bot.
  public var botId: BotID

  /// Creates list parameters.
  public init(botId: BotID) {
    self.botId = botId
  }
}

/// Every active folder grant, then the most recently ended ones, at most 200 in GrantID order.
public struct BotsGrantsListResult: Codable, Hashable, Sendable {
  /// The grants.
  public var items: [FolderGrantSummary]
  /// The snapshot position.
  public var asOf: AsOf

  /// Creates a list result.
  public init(items: [FolderGrantSummary], asOf: AsOf) {
    self.items = items
    self.asOf = asOf
  }
}

/// One local folder change, not the full generic Grant value. Without `id` it grants a newly
/// chosen root; with `id` it changes that grant's access at exactly `expectedRevision`.
public struct FolderGrantChange: Codable, Hashable, Sendable {
  /// The existing grant; absent for a newly chosen root.
  public var id: GrantID?
  /// The root's physical path. An existing grant's path never changes.
  public var path: String
  /// The requested access.
  public var access: FolderGrantPermission
  /// The revision the change expects: required with `id` and absent without it.
  public var expectedRevision: Int64?
  /// The exact path the user typed; required to grant or widen a whole personal folder.
  public var confirmationText: String?
  /// When a new grant lapses. An existing grant keeps its deadline.
  public var expiresAt: Int64?
  /// The physical identity of the directory the user reviewed: required without `id`, absent
  /// with it. The helper grants nothing unless its own capture names the same directory.
  public var selectionIdentity: FolderGrantSelectionIdentity?

  /// Creates a change.
  public init(
    id: GrantID? = nil, path: String, access: FolderGrantPermission,
    expectedRevision: Int64? = nil, confirmationText: String? = nil, expiresAt: Int64? = nil,
    selectionIdentity: FolderGrantSelectionIdentity? = nil
  ) {
    self.id = id
    self.path = path
    self.access = access
    self.expectedRevision = expectedRevision
    self.confirmationText = confirmationText
    self.expiresAt = expiresAt
    self.selectionIdentity = selectionIdentity
  }
}

/// A reviewed directory's device and inode numbers as canonical decimal text, so no JSON
/// integer width is assumed. Metadata only: no bookmark, path content or file data.
public struct FolderGrantSelectionIdentity: Codable, Hashable, Sendable {
  /// The file-system device number, `String(UInt64)`.
  public var device: String
  /// The directory's inode number, `String(UInt64)`.
  public var inode: String

  /// Creates an identity from canonical decimal text.
  public init(device: String, inode: String) {
    self.device = device
    self.inode = inode
  }
}

/// The parameters of `bots.grants.update`.
public struct BotsGrantsUpdateParams: Codable, Hashable, Sendable, IdempotentParams {
  /// The client's idempotency key.
  public var requestId: ULID
  /// The bot the grant authorizes.
  public var botId: BotID
  /// The change.
  public var grant: FolderGrantChange

  /// Creates update parameters.
  public init(requestId: ULID, botId: BotID, grant: FolderGrantChange) {
    self.requestId = requestId
    self.botId = botId
    self.grant = grant
  }
}

/// The result of `bots.grants.update`: a historical receipt, not current state.
public struct BotsGrantsUpdateResult: Codable, Hashable, Sendable {
  /// The grant as this request left it; a replay returns it unchanged.
  public var grant: FolderGrantSummary
  /// The highest `seq` the request wrote, or the head it observed when nothing changed.
  public var writtenSeq: Int64
  /// `true` when this is the stored result of an earlier request with the same `requestId`.
  public var replayed: Bool?

  /// Creates an update result.
  public init(grant: FolderGrantSummary, writtenSeq: Int64, replayed: Bool? = nil) {
    self.grant = grant
    self.writtenSeq = writtenSeq
    self.replayed = replayed
  }
}

/// The parameters of `bots.grants.revoke`.
public struct BotsGrantsRevokeParams: Codable, Hashable, Sendable, IdempotentParams {
  /// The client's idempotency key.
  public var requestId: ULID
  /// The grant to end.
  public var grantId: GrantID

  /// Creates revoke parameters.
  public init(requestId: ULID, grantId: GrantID) {
    self.requestId = requestId
    self.grantId = grantId
  }
}
