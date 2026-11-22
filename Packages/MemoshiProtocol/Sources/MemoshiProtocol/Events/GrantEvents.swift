/// `grant.granted` (A): the user granted a capability, or changed the terms of an active grant.
/// The envelope's subject is the grant and its scope names the bot.
public struct GrantGrantedPayload: EventPayload {
  /// `grant.granted`.
  public static let eventType = "grant.granted"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited

  /// The grant.
  public var grantId: GrantID
  /// Who granted it.
  public var grantedBy: Actor
  /// When it lapses; absent when it does not.
  public var expiresAt: Int64?

  /// Creates the payload.
  public init(grantId: GrantID, grantedBy: Actor, expiresAt: Int64? = nil) {
    self.grantId = grantId
    self.grantedBy = grantedBy
    self.expiresAt = expiresAt
  }

  /// `.grantGranted(self)`.
  public var asEvent: Event { .grantGranted(self) }
}

/// `grant.revoked` (A): the user withdrew an active grant. Revocation is terminal.
public struct GrantRevokedPayload: EventPayload {
  /// `grant.revoked`.
  public static let eventType = "grant.revoked"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited

  /// The grant.
  public var grantId: GrantID
  /// Who revoked it.
  public var by: Actor

  /// Creates the payload.
  public init(grantId: GrantID, by: Actor) {
    self.grantId = grantId
    self.by = by
  }

  /// `.grantRevoked(self)`.
  public var asEvent: Event { .grantRevoked(self) }
}

/// `grant.expired` (A): an active grant's `expiresAt` passed. Expiry is terminal.
public struct GrantExpiredPayload: EventPayload {
  /// `grant.expired`.
  public static let eventType = "grant.expired"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited

  /// The grant.
  public var grantId: GrantID

  /// Creates the payload.
  public init(grantId: GrantID) {
    self.grantId = grantId
  }

  /// `.grantExpired(self)`.
  public var asEvent: Event { .grantExpired(self) }
}
