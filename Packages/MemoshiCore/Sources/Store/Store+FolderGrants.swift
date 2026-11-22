import Foundation
import MemoshiProtocol

extension Store {
  /// The most grant references one authority check or approval decision may depend on.
  static let folderGrantReferenceLimit = 64
  /// The most active folder grants one bot may hold on this device.
  static let activeFolderGrantLimit = 64
  /// The most grants one list returns: every active grant, then the latest ended ones.
  static let folderGrantListLimit = 200

  /// Persists one explicit user grant of an original folder root to one bot on this device.
  /// Trusted host code validates the physical root first; this keeps its captured identity and
  /// bookmark locally and audits `grant.granted` with identifiers only.
  public func grantFolder(
    botID: BotID, path: String, access: FolderGrantAccess, sourceIdentity: FolderSourceIdentity,
    bookmarkData: Data, expiresAt: Int64? = nil, actor: Actor, at now: Int64
  ) throws -> FolderGrantRecord {
    try requireOpen()
    guard actor.kind == .user else { throw FolderGrantError.forbidden }
    let inserted = try writer.transaction(write: true) {
      try insertFolderGrant(
        botID: botID, path: path, access: access, sourceIdentity: sourceIdentity,
        bookmarkData: bookmarkData, expiresAt: expiresAt, actor: actor, at: now)
    }
    eventBus.publish([inserted.fact])
    return inserted.grant
  }

  /// Reads one grant and its snapshot position. A grant whose deadline has passed is durably
  /// expired first, so a lapsed grant is never read back as active.
  public func folderGrant(
    _ id: GrantID, at now: Int64
  ) throws -> StoreSnapshot<FolderGrantRecord?> {
    try requireOpen()
    try expireFolderGrants([id], at: now)
    return try reader.transaction(write: false) {
      StoreSnapshot(
        value: try readFolderGrant(id, database: reader), asOf: try position(conversationID: nil))
    }
  }

  /// One bot's local folder grants: every active grant, then the most recently ended ones, at
  /// most `folderGrantListLimit` in GrantID order. Grants whose deadline has passed end durably
  /// first, each with its audited fact. Only a bot with a local Chat holds grants here.
  public func folderGrants(
    botID: BotID, at now: Int64
  ) throws -> StoreSnapshot<[FolderGrantRecord]> {
    try requireOpen()
    try expireLapsedFolderGrants(botID: botID, at: now)
    return try reader.transaction(write: false) {
      try requireLocalBot(botID, database: reader)
      let owner: [SQLiteConnection.Value] = [.text(botID.rawValue), .text(deviceID.rawValue)]
      let active = try reader.query(
        """
        SELECT \(Self.folderGrantColumns) FROM folder_grants
        WHERE bot_id = ? AND device_id = ? AND status = 'active' ORDER BY id
        """, owner, row: Self.decodeFolderGrant)
      let ended = try reader.query(
        """
        SELECT \(Self.folderGrantColumns) FROM folder_grants
        WHERE bot_id = ? AND device_id = ? AND status <> 'active'
        ORDER BY updated_at DESC, id DESC LIMIT ?
        """, owner + [.integer(Int64(max(0, Self.folderGrantListLimit - active.count)))],
        row: Self.decodeFolderGrant)
      return StoreSnapshot(
        value: (active + ended).sorted { $0.id.rawValue < $1.id.rawValue },
        asOf: try position(conversationID: nil))
    }
  }

  /// Checks every reference for one bot in one snapshot, after grants whose deadline has passed
  /// end durably with their audited facts. `write` needs write access; `read` accepts either.
  /// All or nothing: a missing, foreign, terminal or insufficient grant throws `unavailable`,
  /// and a changed revision throws `staleReference`. Records return in reference order.
  public func folderGrantAuthority(
    _ refs: [FolderGrantReference], botID: BotID, access: FolderGrantAccess, at now: Int64
  ) throws -> [FolderGrantRecord] {
    try requireOpen()
    guard !refs.isEmpty else { throw FolderGrantError.invalidRequest }
    try validateFolderGrantReferences(refs)
    try expireFolderGrants(refs.map(\.grantID), at: now)
    return try reader.transaction(write: false) {
      try refs.map {
        try checkFolderGrant($0, botID: botID, access: access, at: now, database: reader).get()
      }
    }
  }

  /// One explicit user change to an active grant's access. A real change increments the
  /// revision, so earlier references become stale and their pending approvals are canceled in
  /// the same transaction; repeating the current access changes nothing.
  public func setFolderGrantAccess(
    _ id: GrantID, access: FolderGrantAccess, actor: Actor, at now: Int64
  ) throws -> FolderGrantRecord {
    try requireOpen()
    guard actor.kind == .user else { throw FolderGrantError.forbidden }
    try expireFolderGrants([id], at: now)
    var events: [EventEnvelope] = []
    let grant = try writer.transaction(write: true) {
      guard let grant = try readFolderGrant(id, database: writer) else {
        throw FolderGrantError.notFound
      }
      guard grant.status == .active else { throw FolderGrantError.unavailable }
      guard grant.access != access else { return grant }
      let change = try changeFolderGrant(
        grant, access: access, status: .active, actor: actor,
        event: .grantGranted(.init(grantId: id, grantedBy: actor, expiresAt: grant.expiresAt)),
        at: now)
      events = change.events
      return change.grant
    }
    eventBus.publish(events)
    return grant
  }

  /// One explicit user revocation. It is terminal and cancels the pending approvals that depend
  /// on the grant in the same transaction; terminal decisions keep their now-stale references.
  /// Repeating it, or revoking a grant that already expired, returns the record without effects.
  public func revokeFolderGrant(
    _ id: GrantID, actor: Actor, at now: Int64
  ) throws -> FolderGrantRecord {
    try requireOpen()
    guard actor.kind == .user else { throw FolderGrantError.forbidden }
    try expireFolderGrants([id], at: now)
    var events: [EventEnvelope] = []
    let grant = try writer.transaction(write: true) {
      guard let grant = try readFolderGrant(id, database: writer) else {
        throw FolderGrantError.notFound
      }
      guard grant.status == .active else { return grant }
      let change = try changeFolderGrant(
        grant, access: grant.access, status: .revoked, actor: actor,
        event: .grantRevoked(.init(grantId: id, by: actor)), at: now)
      events = change.events
      return change.grant
    }
    eventBus.publish(events)
    return grant
  }

  /// `bots.grants.update` for a newly chosen root: the grant, its audited fact and the request's
  /// receipt commit together, for a bot with a local Chat. Trusted host code proves the physical
  /// root and bookmark first. A retry returns the original receipt, so an uncertain create never
  /// allocates a second grant; a new request for a root the bot already holds is refused.
  public func createFolderGrant(
    _ params: BotsGrantsUpdateParams, paramsHash: String, sourceIdentity: FolderSourceIdentity,
    bookmarkData: Data, actor: Actor, at now: Int64
  ) throws -> BotsGrantsUpdateResult {
    try requireOpen()
    guard actor.kind == .user else { throw FolderGrantError.forbidden }
    let change = params.grant
    guard change.id == nil, change.expectedRevision == nil,
      let access = FolderGrantAccess(change.access)
    else { throw FolderGrantError.invalidRequest }
    try expireLapsedFolderGrants(botID: params.botId, at: now)
    var events: [EventEnvelope] = []
    let receipt = try writer.transaction(write: true) {
      if var previous = try requestResult(
        params.requestId, method: BotsGrantsUpdate.name, paramsHash: paramsHash,
        as: BotsGrantsUpdateResult.self)
      {
        previous.replayed = true
        return previous
      }
      try requireLocalBot(params.botId, database: writer)
      let held = try writer.query(
        """
        SELECT path, source_device, source_inode FROM folder_grants
        WHERE bot_id = ? AND device_id = ? AND status = 'active'
        """, [.text(params.botId.rawValue), .text(deviceID.rawValue)]
      ) { row in
        (
          path: try row.requiredText(0),
          identity: FolderSourceIdentity(
            device: UInt64(bitPattern: row.integer(1)), inode: UInt64(bitPattern: row.integer(2)))
        )
      }
      guard
        !held.contains(where: {
          $0.identity == sourceIdentity && $0.path.utf8.elementsEqual(change.path.utf8)
        })
      else { throw FolderGrantError.alreadyGranted }
      guard held.count < Self.activeFolderGrantLimit else { throw FolderGrantError.limitReached }
      let inserted = try insertFolderGrant(
        botID: params.botId, path: change.path, access: access, sourceIdentity: sourceIdentity,
        bookmarkData: bookmarkData, expiresAt: change.expiresAt, actor: actor, at: now)
      guard let writtenSeq = inserted.fact.seq else {
        throw StoreError.invalidCommit("A folder grant fact must be durable")
      }
      events = [inserted.fact]
      let receipt = BotsGrantsUpdateResult(
        grant: inserted.grant.summary(available: true), writtenSeq: writtenSeq, replayed: false)
      try saveRequest(
        params.requestId, method: BotsGrantsUpdate.name, paramsHash: paramsHash, result: receipt,
        at: now)
      return receipt
    }
    eventBus.publish(events)
    return receipt
  }

  /// `bots.grants.update` for an existing grant: one access change at exactly its expected
  /// revision. The change, its audited fact, the cancellation of pending dependents and the
  /// request's receipt commit together; repeating the current access stores a receipt without
  /// effects. A retry returns the original receipt and never undoes a later change. Trusted host
  /// code proves the root again before widening; `available` is its observation for the receipt.
  public func changeFolderGrantAccess(
    _ params: BotsGrantsUpdateParams, paramsHash: String, available: Bool, actor: Actor,
    at now: Int64
  ) throws -> BotsGrantsUpdateResult {
    try requireOpen()
    guard actor.kind == .user else { throw FolderGrantError.forbidden }
    let change = params.grant
    guard let id = change.id, let expected = change.expectedRevision, expected > 0,
      let access = FolderGrantAccess(change.access)
    else { throw FolderGrantError.invalidRequest }
    try expireFolderGrants([id], at: now)
    var events: [EventEnvelope] = []
    let receipt = try writer.transaction(write: true) {
      if var previous = try requestResult(
        params.requestId, method: BotsGrantsUpdate.name, paramsHash: paramsHash,
        as: BotsGrantsUpdateResult.self)
      {
        previous.replayed = true
        return previous
      }
      guard let grant = try readFolderGrant(id, database: writer), grant.botID == params.botId,
        grant.deviceID == deviceID
      else { throw FolderGrantError.notFound }
      guard grant.path.utf8.elementsEqual(change.path.utf8),
        change.expiresAt == nil || change.expiresAt == grant.expiresAt
      else { throw FolderGrantError.invalidRequest }
      guard grant.status == .active else { throw FolderGrantError.unavailable }
      guard grant.revision == expected else { throw FolderGrantError.staleReference }
      var result = grant
      var writtenSeq =
        try writer.integer("SELECT seq FROM sqlite_sequence WHERE name = 'events'") ?? 0
      if grant.access != access {
        let changed = try changeFolderGrant(
          grant, access: access, status: .active, actor: actor,
          event: .grantGranted(.init(grantId: id, grantedBy: actor, expiresAt: grant.expiresAt)),
          at: now)
        guard let last = changed.events.compactMap(\.seq).max() else {
          throw StoreError.invalidCommit("A folder grant change must be durable")
        }
        events = changed.events
        result = changed.grant
        writtenSeq = last
      }
      let receipt = BotsGrantsUpdateResult(
        grant: result.summary(available: available), writtenSeq: writtenSeq, replayed: false)
      try saveRequest(
        params.requestId, method: BotsGrantsUpdate.name, paramsHash: paramsHash, result: receipt,
        at: now)
      return receipt
    }
    eventBus.publish(events)
    return receipt
  }

  /// `bots.grants.revoke`. It needs no filesystem access, so unavailable authority can always
  /// end. The revocation, its audited fact, the cancellation of pending dependents and the
  /// request's receipt commit together; ending an already ended grant stores a receipt without
  /// effects, and a retry returns the original receipt.
  public func revokeFolderGrant(
    _ params: BotsGrantsRevokeParams, paramsHash: String, actor: Actor, at now: Int64
  ) throws {
    try requireOpen()
    guard actor.kind == .user else { throw FolderGrantError.forbidden }
    try expireFolderGrants([params.grantId], at: now)
    let events = try writer.transaction(write: true) { () throws -> [EventEnvelope] in
      let previous = try requestResult(
        params.requestId, method: BotsGrantsRevoke.name, paramsHash: paramsHash,
        as: EmptyParams.self)
      guard previous == nil else { return [] }
      guard let grant = try readFolderGrant(params.grantId, database: writer),
        grant.deviceID == deviceID
      else { throw FolderGrantError.notFound }
      var ended: [EventEnvelope] = []
      if grant.status == .active {
        ended = try changeFolderGrant(
          grant, access: grant.access, status: .revoked, actor: actor,
          event: .grantRevoked(.init(grantId: grant.id, by: actor)), at: now
        ).events
      }
      try saveRequest(
        params.requestId, method: BotsGrantsRevoke.name, paramsHash: paramsHash,
        result: EmptyParams(), at: now)
      return ended
    }
    eventBus.publish(events)
  }

  /// Durably ends each named active grant whose deadline has passed. Its audited fact and the
  /// cancellation of its pending dependents commit together, in a transaction of their own that
  /// commits before the caller's decision reads current authority.
  func expireFolderGrants(_ ids: [GrantID], at now: Int64) throws {
    guard !ids.isEmpty else { return }
    let events = try writer.transaction(write: true) {
      var expired: [EventEnvelope] = []
      for id in ids {
        guard let grant = try readFolderGrant(id, database: writer), grant.status == .active,
          let expiresAt = grant.expiresAt, expiresAt <= now
        else { continue }
        expired += try changeFolderGrant(
          grant, access: grant.access, status: .expired, actor: Actor(kind: .system),
          event: .grantExpired(.init(grantId: id)), at: now
        ).events
      }
      return expired
    }
    eventBus.publish(events)
  }

  /// Bounded, positive revisions and each grant named once; emptiness is the caller's rule.
  func validateFolderGrantReferences(_ refs: [FolderGrantReference]) throws {
    guard refs.count <= Self.folderGrantReferenceLimit, refs.allSatisfy({ $0.revision > 0 }),
      Set(refs.map(\.grantID)).count == refs.count
    else { throw FolderGrantError.invalidRequest }
  }

  /// One reference's complete current check inside the caller's snapshot: this device, the
  /// bot, active and unexpired, and the exact revision. `access` is the authority the use
  /// needs; `nil` checks only that the referenced revision is still current.
  func checkFolderGrant(
    _ reference: FolderGrantReference, botID: BotID, access: FolderGrantAccess?, at now: Int64,
    database: SQLiteConnection
  ) throws -> Result<FolderGrantRecord, FolderGrantError> {
    guard let grant = try readFolderGrant(reference.grantID, database: database),
      grant.botID == botID, grant.deviceID == deviceID, grant.status == .active,
      grant.expiresAt.map({ $0 > now }) ?? true
    else { return .failure(.unavailable) }
    guard grant.revision == reference.revision else { return .failure(.staleReference) }
    guard access != .write || grant.access == .write else { return .failure(.unavailable) }
    return .success(grant)
  }

  func readFolderGrant(_ id: GrantID, database: SQLiteConnection) throws -> FolderGrantRecord? {
    try database.query(
      "SELECT \(Self.folderGrantColumns) FROM folder_grants WHERE id = ?", [.text(id.rawValue)],
      row: Self.decodeFolderGrant
    ).first
  }

  /// The `folder_grants` columns `decodeFolderGrant(_:)` reads, in order.
  private static let folderGrantColumns = """
    id, bot_id, device_id, path, access, status, revision, source_device, source_inode,
    bookmark, expires_at, created_at, updated_at
    """

  private static func decodeFolderGrant(_ row: SQLiteRow) throws -> FolderGrantRecord {
    guard let access = FolderGrantAccess(rawValue: try row.requiredText(4)),
      let status = FolderGrantStatus(rawValue: try row.requiredText(5))
    else { throw StoreError.invalidSchema("Unknown folder grant state") }
    return FolderGrantRecord(
      id: try GrantID(row.requiredText(0)), botID: try BotID(row.requiredText(1)),
      deviceID: try DeviceID(row.requiredText(2)), path: try row.requiredText(3), access: access,
      status: status, revision: row.integer(6),
      sourceIdentity: FolderSourceIdentity(
        device: UInt64(bitPattern: row.integer(7)), inode: UInt64(bitPattern: row.integer(8))),
      bookmarkData: try row.requiredData(9), expiresAt: row.optionalInteger(10),
      createdAt: row.integer(11), updatedAt: row.integer(12))
  }

  /// Inside the caller's writer transaction: inserts one new active grant at revision 1 and
  /// appends its audited `grant.granted` fact, which carries identifiers only.
  private func insertFolderGrant(
    botID: BotID, path: String, access: FolderGrantAccess, sourceIdentity: FolderSourceIdentity,
    bookmarkData: Data, expiresAt: Int64?, actor: Actor, at now: Int64
  ) throws -> (grant: FolderGrantRecord, fact: EventEnvelope) {
    guard path.hasPrefix("/"), path.utf8.count <= 4_096, !path.utf8.contains(0),
      !bookmarkData.isEmpty, bookmarkData.count <= 65_536, expiresAt.map({ $0 > now }) ?? true
    else { throw FolderGrantError.invalidRequest }
    let grant = FolderGrantRecord(
      id: try IDGenerator.shared.objectID(GrantIDKind.self), botID: botID, deviceID: deviceID,
      path: path, access: access, status: .active, revision: 1, sourceIdentity: sourceIdentity,
      bookmarkData: bookmarkData, expiresAt: expiresAt, createdAt: now, updatedAt: now)
    try writer.execute(
      """
      INSERT INTO folder_grants (id, bot_id, device_id, path, access, status, revision,
        source_device, source_inode, bookmark, expires_at, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, 'active', 1, ?, ?, ?, ?, ?, ?)
      """,
      [
        .text(grant.id.rawValue), .text(botID.rawValue), .text(deviceID.rawValue),
        .text(path), .text(access.rawValue), .integer(Int64(bitPattern: sourceIdentity.device)),
        .integer(Int64(bitPattern: sourceIdentity.inode)), .blob(bookmarkData),
        expiresAt.map(SQLiteConnection.Value.integer) ?? .null, .integer(now), .integer(now),
      ])
    let fact = try append(
      grantEvent(
        grant, actor: actor, at: now,
        event: .grantGranted(.init(grantId: grant.id, grantedBy: actor, expiresAt: expiresAt))))
    return (grant, fact)
  }

  /// Ends every active grant this bot holds here whose deadline has passed.
  private func expireLapsedFolderGrants(botID: BotID, at now: Int64) throws {
    let lapsed = try reader.transaction(write: false) {
      try reader.query(
        """
        SELECT id FROM folder_grants WHERE bot_id = ? AND device_id = ? AND status = 'active'
          AND expires_at IS NOT NULL AND expires_at <= ? ORDER BY id
        """, [.text(botID.rawValue), .text(deviceID.rawValue), .integer(now)]
      ) { try GrantID($0.requiredText(0)) }
    }
    try expireFolderGrants(lapsed, at: now)
  }

  /// This bounded profile manages folders only for a bot with a local Chat.
  private func requireLocalBot(_ botID: BotID, database: SQLiteConnection) throws {
    let chats = try database.integer(
      "SELECT COUNT(*) FROM chats WHERE bot_id = ? AND kind != 'session'",
      [.text(botID.rawValue)])
    guard chats == 1 else { throw FolderGrantError.notFound }
  }

  /// Inside the caller's writer transaction: advances the revision, appends the audited fact,
  /// then ends every pending approval that depended on an earlier revision. Terminal decisions,
  /// including historical allowed ones, are left unchanged.
  private func changeFolderGrant(
    _ grant: FolderGrantRecord, access: FolderGrantAccess, status: FolderGrantStatus,
    actor: Actor, event: Event, at now: Int64
  ) throws -> (grant: FolderGrantRecord, events: [EventEnvelope]) {
    guard grant.revision < Int64.max else { throw StoreError.sequenceExhausted }
    let changed = FolderGrantRecord(
      id: grant.id, botID: grant.botID, deviceID: grant.deviceID, path: grant.path,
      access: access, status: status, revision: grant.revision + 1,
      sourceIdentity: grant.sourceIdentity, bookmarkData: grant.bookmarkData,
      expiresAt: grant.expiresAt, createdAt: grant.createdAt, updatedAt: now)
    try writer.execute(
      """
      UPDATE folder_grants SET access = ?, status = ?, revision = ?, updated_at = ?
      WHERE id = ? AND revision = ?
      """,
      [
        .text(access.rawValue), .text(status.rawValue), .integer(changed.revision),
        .integer(now), .text(grant.id.rawValue), .integer(grant.revision),
      ])
    guard try writer.changedRows == 1 else {
      throw StoreError.invalidCommit("A folder grant changed outside its transition")
    }
    var events = [try append(grantEvent(changed, actor: actor, at: now, event: event))]
    let dependents = try writer.query(
      """
      SELECT s.approval_id FROM approval_source_grants s JOIN approvals a ON a.id = s.approval_id
      WHERE s.grant_id = ? AND a.status = 'pending' ORDER BY s.approval_id
      """, [.text(grant.id.rawValue)]
    ) { try ApprovalID($0.requiredText(0)) }
    events += try cancelPendingApprovals(dependents, reason: .grantRevoked, at: now)
    return (changed, events)
  }

  private func grantEvent(
    _ grant: FolderGrantRecord, actor: Actor, at now: Int64, event: Event
  ) -> EventDraft {
    EventDraft(
      ts: now, actor: actor, subject: ObjectRef(kind: "grant", id: grant.id.rawValue),
      scope: EventScope(botId: grant.botID), event: event)
  }
}
