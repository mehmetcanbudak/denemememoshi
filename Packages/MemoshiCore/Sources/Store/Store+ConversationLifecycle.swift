import Darwin
import Foundation
import MemoshiProtocol

/// A persisted, frozen purge selection. It is resumed before the runtime admits new work.
public struct SessionPurgeJob: Sendable {
  /// The original Empty Trash request reserved across retries and process restarts.
  public let requestId: ULID
  /// The caller-supplied parameter hash bound to that request; conflicting reuse is refused.
  public let paramsHash: String
  /// The frozen retained-Session selection, sorted by identifier for consistent lock acquisition.
  public let ids: [SessionID]
  /// `user` for explicit Empty Trash authority, or `system` for retention-expiry maintenance.
  public let by: String
}

extension Store {
  /// Retains a closed, idle Session for 30 days. The transcript is not unlinked here.
  /// The caller must close its Pi Harness first; the store checks idle state, no live runner
  /// and no open working copy before recording the deletion and request receipt atomically.
  /// Another device's lease always refuses. This device's own lease refuses only while its
  /// conversation lock is held: one left by an unclean exit ends here, keeping its epoch.
  /// `now` is Unix time in milliseconds. A matching original request replays its receipt.
  public func deleteSession(
    _ params: SessionsDeleteParams, paramsHash: String, at now: Int64
  ) throws -> LifecycleReceipt {
    try requireOpen()
    var events: [EventEnvelope] = []
    let result = try writer.transaction(write: true) {
      if var receipt = try requestResult(
        params.requestId, method: SessionsDelete.name, paramsHash: paramsHash,
        as: LifecycleReceipt.self)
      {
        receipt.replayed = true
        return receipt
      }
      let id = try ConversationID(params.sessionId.rawValue)
      guard let conversation = try readConversation(id, database: writer),
        conversation.kind == .session
      else { throw StoreError.chatNotFound }
      guard now >= 0, now <= Int64.max - Self.trashRetentionMilliseconds else {
        throw StoreError.invalidCommit("Invalid deletion timestamp")
      }
      guard try conversationIsIdle(id),
        try writer.integer(
          "SELECT COUNT(*) FROM working_copies WHERE chat_id = ? AND phase != 'closed'",
          [.text(id.rawValue)]) == 0
      else {
        throw StoreError.chatBusy
      }
      let runner = try readLease(id)?.runnerDeviceID
      guard runner == nil || runner == deviceID else { throw StoreError.chatBusy }
      let lock: FileLock
      do {
        lock = try directories.acquireConversationLock(id)
      } catch StoreError.conversationInUse where runner != nil {
        throw StoreError.chatBusy
      }
      defer { lock.release() }
      if runner != nil {
        // The free lock proves no process still runs this conversation.
        try writer.execute(
          "UPDATE leases SET runner_device_id = NULL, expires_at = NULL WHERE conversation_id = ?",
          [.text(id.rawValue)])
      }
      let purgeAfter = now + Self.trashRetentionMilliseconds
      try writer.execute(
        "UPDATE chats SET deleted_at = ?, purge_after = ? WHERE id = ?",
        [.integer(now), .integer(purgeAfter), .text(id.rawValue)])
      let event = try append(
        lifecycleDraft(conversation, at: now, event: .sessionDeleted(.init(purgeAfter: purgeAfter)))
      )
      events.append(event)
      let receipt = LifecycleReceipt(writtenSeq: try durableSequence(event), replayed: false)
      try saveRequest(
        params.requestId, method: SessionsDelete.name, paramsHash: paramsHash, result: receipt,
        at: now)
      return receipt
    }
    eventBus.publish(events)
    return result
  }

  /// Snapshots local retained Sessions in deletion-time/identifier order, excluding pending
  /// and completed purges. Expired entries remain listed until maintenance selects them,
  /// but are no longer eligible for restoration.
  public func sessionTrash() throws -> StoreSnapshot<[TrashedSession]> {
    try requireOpen()
    return try reader.transaction(write: false) {
      StoreSnapshot(
        value: try readSessionTrash(database: reader),
        asOf: try position(conversationID: nil))
    }
  }

  /// Clears an unexpired Session's Trash markers and commits its restoration event and receipt.
  /// It does not open the retained Pi store or change its lease epoch. `now` is Unix time in
  /// milliseconds; missing, expired and purge-pending items throw `StoreError.chatNotFound`.
  /// A matching request/hash replays the historical result rather than restoring again.
  public func restoreSession(
    _ params: TrashRestoreParams, paramsHash: String, at now: Int64
  ) throws -> TrashRestoreResult {
    try requireOpen()
    var events: [EventEnvelope] = []
    let result = try writer.transaction(write: true) {
      if var receipt = try requestResult(
        params.requestId, method: TrashRestore.name, paramsHash: paramsHash,
        as: TrashRestoreResult.self)
      {
        receipt.replayed = true
        return receipt
      }
      guard params.kind == "session",
        let item = try readSessionTrash(database: writer).first(where: { $0.id == params.id })
      else { throw StoreError.chatNotFound }
      guard now < item.purgeAfter else { throw StoreError.chatNotFound }
      let id = try ConversationID(item.id.rawValue)
      try writer.execute(
        "UPDATE chats SET deleted_at = NULL, purge_after = NULL WHERE id = ?",
        [.text(id.rawValue)])
      guard let conversation = try readConversation(id, database: writer) else {
        throw StoreError.chatNotFound
      }
      events.append(
        try append(lifecycleDraft(conversation, at: now, event: .sessionRestored(.init()))))
      let receipt = TrashRestoreResult(
        session: Session(
          id: item.id, leadBotId: item.botId, title: item.title, createdAt: conversation.createdAt),
        replayed: false)
      try saveRequest(
        params.requestId, method: TrashRestore.name, paramsHash: paramsHash, result: receipt,
        at: now)
      return receipt
    }
    eventBus.publish(events)
    return result
  }

  /// Freezes exactly what an Empty Trash request selected before any filesystem mutation.
  /// Repeating a pending original request returns the same selection, even after restart.
  /// Nil `ids` captures the whole current local Session Trash, however large; explicit
  /// selections require at most 1,000 unique retained IDs. `by` must be `user` or `system`;
  /// only system selections must already be due at `now` (Unix milliseconds). A completed
  /// request returns nil, not a new job.
  public func prepareSessionPurge(
    _ params: TrashEmptyParams, paramsHash: String, by: String = "user", at now: Int64
  ) throws -> SessionPurgeJob? {
    try requireOpen()
    return try writer.transaction(write: true) {
      if try requestResult(
        params.requestId, method: TrashEmpty.name, paramsHash: paramsHash,
        as: LifecycleReceipt.self) != nil
      {
        return nil
      }
      if let job = try readSessionPurgeJobs().first(where: { $0.requestId == params.requestId }) {
        guard job.paramsHash == paramsHash, job.by == by else { throw StoreError.requestConflict }
        return job
      }
      guard by == "user" || by == "system" else {
        throw StoreError.invalidCommit("Unknown purge actor")
      }
      let retained = try readSessionTrash(database: writer)
      let selected = params.ids ?? retained.map(\.id)
      guard params.ids == nil || selected.count <= 1_000, Set(selected).count == selected.count
      else {
        throw StoreError.invalidCommit(
          "A purge selection must contain at most 1000 unique Sessions")
      }
      let available = Set(retained.map(\.id))
      guard selected.allSatisfy(available.contains) else { throw StoreError.chatNotFound }
      if by == "system" {
        let due = Set(retained.filter { $0.purgeAfter <= now }.map(\.id))
        guard selected.allSatisfy(due.contains) else {
          throw StoreError.invalidCommit("Session retention has not expired")
        }
      }
      let ids = selected.sorted { $0.rawValue < $1.rawValue }
      for id in ids {
        try writer.execute(
          "UPDATE chats SET purge_pending = 1 WHERE id = ?", [.text(id.rawValue)])
      }
      try writer.execute(
        "INSERT INTO session_purge_jobs (request_id, params_hash, session_ids, actor, created_at) VALUES (?, ?, ?, ?, ?)",
        [
          .text(params.requestId.rawValue), .text(paramsHash), .json(try encoder.encode(ids)),
          .text(by), .integer(now),
        ])
      return SessionPurgeJob(requestId: params.requestId, paramsHash: paramsHash, ids: ids, by: by)
    }
  }

  /// Replays a durable receipt without selecting or deleting anything again.
  public func sessionPurgeReceipt(_ params: TrashEmptyParams, paramsHash: String) throws
    -> LifecycleReceipt?
  {
    var receipt = try requestReceipt(
      params.requestId, method: TrashEmpty.name, paramsHash: paramsHash, as: LifecycleReceipt.self)
    receipt?.replayed = true
    return receipt
  }

  /// Loads durable unfinished jobs in creation-time/request-ID order without unlinking files.
  /// The runtime resumes these before opening any conversation's Pi store.
  public func pendingSessionPurges() throws -> [SessionPurgeJob] {
    try requireOpen()
    return try readSessionPurgeJobs()
  }

  /// Returns retained, non-pending Session IDs whose deadline is at or before `now`, in Unix
  /// milliseconds. This query neither reserves a selection nor performs a purge.
  public func expiredSessionIDs(at now: Int64) throws -> [SessionID] {
    try requireOpen()
    return try readSessionTrash(database: reader).filter { $0.purgeAfter <= now }.map(\.id)
  }

  /// The most Sessions one purge step locks, unlinks and commits together. It bounds the open
  /// lock descriptors of a job of any size well below a daemon's default limit of 256.
  static let purgeBatchSize = 32

  /// Removes only these Sessions' closed Pi SQLite files, never a bot/project/source folder.
  /// The selection is purged in bounded batches, each under its own locks and transaction, so
  /// an interrupted job keeps what it finished and a retry of the same job continues after it.
  /// A failed unlink leaves the job durable and its remaining Sessions non-restorable until
  /// retried successfully. Only the batch that completes the selection records the aggregate
  /// fact and the original receipt at `now` (Unix milliseconds) and removes the job: no receipt
  /// exists while any selected Session remains. Audit history, request receipts and the
  /// conversation tombstone remain. Unlinking is not secure erase of SQLite pages, backups or
  /// other copies.
  public func finishSessionPurge(_ job: SessionPurgeJob, at now: Int64) throws -> LifecycleReceipt {
    try requireOpen()
    if var receipt = try requestResult(
      job.requestId, method: TrashEmpty.name, paramsHash: job.paramsHash,
      as: LifecycleReceipt.self)
    {
      receipt.replayed = true
      return receipt
    }
    guard let current = try readSessionPurgeJobs().first(where: { $0.requestId == job.requestId }),
      current.paramsHash == job.paramsHash, current.ids == job.ids, current.by == job.by
    else { throw StoreError.requestConflict }
    // Sessions an earlier, interrupted attempt already purged are not purged again.
    let pending = Set(
      try writer.query("SELECT id FROM chats WHERE purge_pending = 1") { try $0.requiredText(0) })
    let remaining = job.ids.filter { pending.contains($0.rawValue) }
    var start = remaining.startIndex
    while true {
      let end = min(start + Self.purgeBatchSize, remaining.endIndex)
      if let receipt = try purgeSessions(
        remaining[start..<end], of: job, completing: end == remaining.endIndex, at: now)
      {
        return receipt
      }
      start = end
    }
  }

  /// One bounded step of a purge job. Its facts are published once its transaction commits;
  /// the receipt is returned only by the step that completes the job.
  private func purgeSessions(
    _ sessions: ArraySlice<SessionID>, of job: SessionPurgeJob, completing: Bool, at now: Int64
  ) throws -> LifecycleReceipt? {
    var locks: [FileLock] = []
    defer { for lock in locks { lock.release() } }
    for session in sessions {
      let id = try ConversationID(session.rawValue)
      guard try readLease(id)?.runnerDeviceID == nil else { throw StoreError.chatBusy }
      locks.append(try directories.acquireConversationLock(id))
    }
    for session in sessions { try removePiFiles(for: session) }
    var events: [EventEnvelope] = []
    let receipt: LifecycleReceipt? = try writer.transaction(write: true) {
      for session in sessions {
        let id = try ConversationID(session.rawValue)
        let rows = try writer.query(
          "SELECT bot_id, title, created_at FROM chats WHERE id = ? AND purge_pending = 1",
          [.text(id.rawValue)]
        ) { row in
          ChatSummary(
            id: id, kind: .session, botId: try BotID(row.requiredText(0)),
            title: try row.requiredText(1), createdAt: row.integer(2))
        }
        guard let conversation = rows.first else { throw StoreError.chatNotFound }
        events += try flushGatewayAudit(conversationID: id, at: now)
        // A decided approval keeps its source-grant references, which name its binding.
        try writer.execute(
          "DELETE FROM approval_source_grants WHERE approval_id IN (SELECT id FROM approvals WHERE conversation_id = ?)",
          [.text(id.rawValue)])
        try writer.execute(
          "DELETE FROM approval_bindings WHERE approval_id IN (SELECT id FROM approvals WHERE conversation_id = ?)",
          [.text(id.rawValue)])
        for table in [
          "working_copy_exports", "unsafe_tool_dispatches", "resume_steps", "policy_tool_calls",
          "runtime_subagents", "chat_queued_inputs", "message_indexes", "chat_turns",
          "approvals", "cards", "tasks", "conversation_exposure",
        ] {
          try writer.execute("DELETE FROM \(table) WHERE conversation_id = ?", [.text(id.rawValue)])
        }
        try writer.execute("DELETE FROM working_copies WHERE chat_id = ?", [.text(id.rawValue)])
        // Sandbox attribution: the conversation's invocations and the denials linked to them.
        // Unattributed denials and reader gaps name no conversation.
        try writer.execute(
          "DELETE FROM sandbox_denials WHERE invocation_tag IN (SELECT tag FROM sandbox_invocations WHERE conversation_id = ?)",
          [.text(id.rawValue)])
        try writer.execute(
          "DELETE FROM sandbox_invocations WHERE conversation_id = ?", [.text(id.rawValue)])
        try writer.execute(
          "UPDATE chats SET title = '', purge_pending = 0, purged_at = ? WHERE id = ?",
          [.integer(now), .text(id.rawValue)])
        events.append(
          try append(
            lifecycleDraft(
              conversation, at: now, by: job.by,
              event: .sessionPurged(.init(by: job.by == "system" ? .system : .user)))))
      }
      guard completing else { return nil }
      let event = try append(
        EventDraft(
          ts: now, actor: Actor(kind: job.by == "system" ? .system : .user),
          subject: ObjectRef(kind: "system", id: "trash"),
          event: .trashEmptied(
            .init(
              count: job.ids.count, kinds: job.ids.isEmpty ? [] : ["session"],
              by: job.by == "system" ? .system : .user))))
      events.append(event)
      let result = LifecycleReceipt(writtenSeq: try durableSequence(event), replayed: false)
      try saveRequest(
        job.requestId, method: TrashEmpty.name, paramsHash: job.paramsHash, result: result, at: now)
      try writer.execute(
        "DELETE FROM session_purge_jobs WHERE request_id = ?", [.text(job.requestId.rawValue)])
      return result
    }
    eventBus.publish(events)
    return receipt
  }

  /// Fixed 30-day retention interval in milliseconds; deletion adds it to Unix-millisecond time.
  public static let trashRetentionMilliseconds: Int64 = 30 * 24 * 60 * 60 * 1_000

  private func readSessionTrash(database: SQLiteConnection) throws -> [TrashedSession] {
    try database.query(
      "SELECT id, title, bot_id, deleted_at, purge_after FROM chats WHERE kind = 'session' AND deleted_at IS NOT NULL AND purged_at IS NULL AND purge_pending = 0 ORDER BY deleted_at, id"
    ) { row in
      TrashedSession(
        id: try SessionID(row.requiredText(0)), title: try row.requiredText(1),
        botId: try BotID(row.requiredText(2)), deletedAt: row.integer(3),
        purgeAfter: row.integer(4),
        deletedOnDeviceId: deviceID)
    }
  }

  private func readSessionPurgeJobs() throws -> [SessionPurgeJob] {
    try writer.query(
      "SELECT request_id, params_hash, session_ids, actor FROM session_purge_jobs ORDER BY created_at, request_id"
    ) { row in
      SessionPurgeJob(
        requestId: try ULID(row.requiredText(0)), paramsHash: try row.requiredText(1),
        ids: try decoder.decode([SessionID].self, from: row.requiredData(2)),
        by: try row.requiredText(3))
    }
  }

  private func lifecycleDraft(
    _ conversation: ChatSummary, at now: Int64, by: String = "user", event: Event
  ) -> EventDraft {
    EventDraft(
      ts: now, actor: Actor(kind: by == "system" ? .system : .user),
      subject: ObjectRef(kind: "session", id: conversation.id.rawValue),
      scope: EventScope(botId: conversation.botId, conversationId: conversation.id), event: event)
  }

  private func durableSequence(_ event: EventEnvelope) throws -> Int64 {
    guard let seq = event.seq else {
      throw StoreError.invalidCommit("A lifecycle fact must be durable")
    }
    return seq
  }

  private func removePiFiles(for session: SessionID) throws {
    try directories.withPiDirectory { pi in
      // SQLite is already closed and the original conversation flock is held. The Pi
      // descriptor stays attached to the Store's original directory even after a rename.
      for suffix in [".sqlite-wal", ".sqlite-shm", ".sqlite-journal", ".sqlite"] {
        let name = session.rawValue + suffix
        var info = stat()
        if fstatat(pi, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
          if errno == ENOENT { continue }
          throw StoreError.storage(code: errno, operation: "purge stat")
        }
        guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
          throw StoreError.unsafePath(name)
        }
        guard unlinkat(pi, name, 0) == 0 else {
          throw StoreError.storage(code: errno, operation: "purge unlink")
        }
      }
      guard fsync(pi) == 0 else {
        throw StoreError.storage(code: errno, operation: "purge directory sync")
      }
    }
  }
}
