import Foundation
import MemoshiProtocol

/// A folder grant's authority over its original source: checked admission, or admission plus a
/// policy-gated export. Read-only is this access, never a permission mode.
public enum FolderGrantAccess: String, Codable, Sendable {
  case read
  case write
}

/// A folder grant's lifecycle. Revoked and expired are terminal: granting the folder again
/// creates a new grant with a new ID.
public enum FolderGrantStatus: String, Codable, Sendable {
  case active
  case revoked
  case expired
}

/// The physical identity of a granted root, captured by trusted host code. It stays in the
/// local store and never appears in an event payload.
public struct FolderSourceIdentity: Codable, Hashable, Sendable {
  /// The root's file-system device number.
  public let device: UInt64
  /// The root directory's inode number.
  public let inode: UInt64

  /// Captures one root's identity.
  public init(device: UInt64, inode: UInt64) {
    self.device = device
    self.inode = inode
  }
}

/// One exact grant revision that a decision or dispatch depends on. Any later change to the
/// grant makes the reference stale; a stale reference never regains authority.
public struct FolderGrantReference: Codable, Hashable, Sendable {
  /// The folder grant.
  public let grantID: GrantID
  /// The revision the dependent decision observed.
  public let revision: Int64

  /// References one grant revision.
  public init(grantID: GrantID, revision: Int64) {
    self.grantID = grantID
    self.revision = revision
  }
}

/// A store-local `folder` Grant held on this device, not a new domain object or Grant kind.
/// Its path is the original source root, not a sandbox allowance.
public struct FolderGrantRecord: Equatable, Sendable {
  /// The grant.
  public let id: GrantID
  /// The only bot it authorizes.
  public let botID: BotID
  /// The device that holds the folder.
  public let deviceID: DeviceID
  /// The original source root.
  public let path: String
  /// The current authority over the original source.
  public let access: FolderGrantAccess
  /// The lifecycle state.
  public let status: FolderGrantStatus
  /// Starts at 1 and increments with every change.
  public let revision: Int64
  /// The root's physical identity captured when it was granted.
  public let sourceIdentity: FolderSourceIdentity
  /// The bookmark captured when it was granted.
  public let bookmarkData: Data
  /// When it lapses; `nil` when it does not.
  public let expiresAt: Int64?
  /// When the user granted it.
  public let createdAt: Int64
  /// The latest change.
  public let updatedAt: Int64

  /// The reference to this exact revision.
  public var reference: FolderGrantReference {
    FolderGrantReference(grantID: id, revision: revision)
  }
}

/// Safe folder-grant failures; paths, source identities and bookmark bytes never appear here.
public enum FolderGrantError: Error, Equatable, Sendable {
  case notFound
  case invalidRequest
  case forbidden
  case unavailable
  case staleReference
  /// The bot already holds an active grant of this exact root.
  case alreadyGranted
  /// The bot already holds the most active folder grants this device keeps.
  case limitReached
}

extension FolderGrantAccess {
  /// The local access for a protocol value; an unknown value grants nothing.
  public init?(_ permission: FolderGrantPermission) {
    switch permission {
    case .read: self = .read
    case .write: self = .write
    case .unknown: return nil
    }
  }

  /// The protocol value of this access.
  public var permission: FolderGrantPermission {
    switch self {
    case .read: .read
    case .write: .write
    }
  }
}

extension FolderGrantRecord {
  /// The authenticated app's bounded projection, without bookmark bytes or source identity.
  /// `available` is the caller's own observation of the root, never a stored fact.
  public func summary(available: Bool) -> FolderGrantSummary {
    let state: FolderGrantState =
      switch status {
      case .active: .active
      case .revoked: .revoked
      case .expired: .expired
      }
    return FolderGrantSummary(
      id: id, botId: botID, path: path, deviceId: deviceID, access: access.permission,
      status: state, revision: revision, expiresAt: expiresAt, createdAt: createdAt,
      updatedAt: updatedAt, available: available)
  }
}
