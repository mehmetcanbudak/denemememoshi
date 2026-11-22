import Foundation
import MemoshiProtocol

extension Store {
  /// Reserves a host-chosen private-root name before admission creates any directory.
  /// This unfenced local metadata follows folder-grant ownership, not conversation execution.
  public func reserveWorkingCopy(
    chatID: ConversationID, grant: FolderGrantReference, containerRoot: String,
    containerIdentity: FolderSourceIdentity, at now: Int64
  ) throws -> WorkingCopyOwnership {
    try requireOpen()
    guard Self.validCopyPath(containerRoot, absolute: true), containerRoot != "/",
      containerIdentity.inode != 0
    else { throw WorkingCopyJournalError.invalidRequest }
    let ownership = try writer.transaction(write: true) {
      guard
        let rawBot = try writer.text(
          "SELECT bot_id FROM chats WHERE id = ?", [.text(chatID.rawValue)])
      else {
        throw WorkingCopyJournalError.unavailable
      }
      let bot = try BotID(rawBot)
      let source = try checkFolderGrant(grant, botID: bot, access: .read, at: now, database: writer)
        .get()
      let ownership = WorkingCopyOwnership(
        id: UUID(), chatID: chatID, botID: bot, deviceID: deviceID, grant: grant,
        sourceIdentity: source.sourceIdentity, containerRoot: containerRoot,
        containerIdentity: containerIdentity, workingIdentity: nil)
      let bytes = try encoder.encode(ownership)
      guard bytes.count <= 16_384 else { throw WorkingCopyJournalError.invalidRequest }
      try writer.execute(
        "INSERT INTO working_copies (id, chat_id, phase, record, created_at, updated_at) VALUES (?, ?, 'admitting', ?, ?, ?)",
        [
          .text(ownership.id.uuidString), .text(chatID.rawValue), .json(bytes), .integer(now),
          .integer(now),
        ])
      return ownership
    }
    currentWorkingCopies.insert(ownership.id)
    return ownership
  }

  /// Records the private inode only after the engine has verified its independent tree.
  public func activateWorkingCopy(
    _ id: UUID, workingIdentity: FolderSourceIdentity, at now: Int64
  ) throws {
    try requireOpen()
    guard currentWorkingCopies.contains(id) else { throw WorkingCopyJournalError.recoveryRequired }
    guard workingIdentity.inode != 0 else { throw WorkingCopyJournalError.invalidRequest }
    try writer.transaction(write: true) {
      guard var copy = try readWorkingCopy(id, database: writer) else {
        throw WorkingCopyJournalError.unavailable
      }
      guard copy.phase == .admitting else { throw WorkingCopyJournalError.recoveryRequired }
      _ = try checkFolderGrant(
        copy.ownership.grant, botID: copy.ownership.botID, access: .read, at: now, database: writer
      ).get()
      copy.ownership.workingIdentity = workingIdentity
      try writer.execute(
        "UPDATE working_copies SET phase = 'active', record = ?, updated_at = ? WHERE id = ?",
        [.json(try encoder.encode(copy.ownership)), .integer(now), .text(id.uuidString)])
    }
  }

  /// Commits the exact content-free intent before any source effect. A current fence, the
  /// actual policy-bound Pi call, and current write-grant revision are all required.
  /// A journal row is historical evidence, never a substitute for mandatory policy or guards.
  public func beginWorkingCopyExport(
    _ id: UUID, contentHash: String, argumentsHash: String, changes: [WorkingCopyExportChange],
    runtimeTaskKey: String, callID: String, fence: ConversationFence, at now: Int64
  ) throws -> WorkingCopyExportAdmission {
    try requireOpen()
    guard currentWorkingCopies.contains(id) else { throw WorkingCopyJournalError.recoveryRequired }
    try Self.validateCopyChanges(changes, contentHash: contentHash, argumentsHash: argumentsHash)
    let bytes = try encoder.encode(changes)
    guard bytes.count <= 65_536 else { throw WorkingCopyJournalError.invalidRequest }
    return try writer.transaction(write: true) {
      try checkFence(fence, at: now)
      guard let copy = try readWorkingCopy(id, database: writer), copy.phase == .active,
        copy.ownership.chatID.rawValue == fence.conversationID.rawValue
      else { throw WorkingCopyJournalError.recoveryRequired }
      let source = try checkFolderGrant(
        copy.ownership.grant, botID: copy.ownership.botID, access: .write, at: now, database: writer
      ).get()
      guard source.sourceIdentity == copy.ownership.sourceIdentity,
        let call = try writer.query(
          """
          SELECT tool_call_id, tool, bot_id, decision_observed, completion_seq
          FROM policy_tool_calls WHERE conversation_id = ? AND runtime_task_key = ?
          """, [.text(fence.conversationID.rawValue), .text(runtimeTaskKey)],
          row: { row in
            try (
              row.requiredText(0), row.requiredText(1), row.requiredText(2), row.integer(3),
              row.optionalInteger(4)
            )
          }
        ).first,
        call.0 == callID, call.1 == WorkingCopyExportTool.name,
        call.2 == copy.ownership.botID.rawValue,
        call.3 == 1, call.4 == nil
      else { throw WorkingCopyJournalError.bindingConflict }
      if let previous = try readWorkingCopyExports(id, contentHash: contentHash, database: writer)
        .first
      {
        guard previous.argumentsHash == argumentsHash, previous.changes == changes else {
          throw WorkingCopyJournalError.bindingConflict
        }
        if previous.state == .applied { return .alreadyApplied }
        // Even a known no-effect refusal is not silently converted into another dispatch.
        throw WorkingCopyJournalError.recoveryRequired
      }
      let unresolved =
        try writer.integer(
          """
          SELECT COUNT(*) FROM working_copy_exports e JOIN working_copies c ON c.id = e.copy_id
          JOIN policy_tool_calls p ON p.conversation_id = e.conversation_id AND p.runtime_task_key = e.runtime_task_key
          WHERE c.chat_id = ? AND (e.state IN ('pending', 'unknown') OR
            (c.phase = 'closed' AND (\(Self.unsettledCopyExport))))
            AND NOT \(Self.answeredCopyExport)
          """, [.text(copy.ownership.chatID.rawValue)]) ?? 0
      guard unresolved == 0 else { throw WorkingCopyJournalError.recoveryRequired }
      let count =
        try writer.integer(
          "SELECT COUNT(*) FROM working_copy_exports WHERE copy_id = ?", [.text(id.uuidString)])
        ?? 0
      guard count < 64 else { throw WorkingCopyJournalError.invalidRequest }
      let empty = WorkingCopyExportProgress(completedPaths: [], remainingTemporaryPaths: [])
      try writer.execute(
        """
        INSERT INTO working_copy_exports
          (copy_id, content_hash, arguments_hash, conversation_id, runtime_task_key, state, changes, progress, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?)
        """,
        [
          .text(id.uuidString), .text(contentHash), .text(argumentsHash),
          .text(fence.conversationID.rawValue), .text(runtimeTaskKey), .json(bytes),
          .json(try encoder.encode(empty)), .integer(now), .integer(now),
        ])
      return .execute
    }
  }

  /// Commits only the host engine's known outcome. This records an already-started effect,
  /// so a subsequently revoked grant or expired lease cannot erase its historical receipt.
  public func finishWorkingCopyExport(
    _ id: UUID, contentHash: String, runtimeTaskKey: String, state: WorkingCopyExportState,
    completedPaths: [String] = [], remainingTemporaryPaths: [String] = [], at now: Int64
  ) throws {
    try requireOpen()
    guard currentWorkingCopies.contains(id) else { throw WorkingCopyJournalError.recoveryRequired }
    guard state != .pending, completedPaths.count <= 64, remainingTemporaryPaths.count <= 64,
      Set(completedPaths).count == completedPaths.count,
      Set(remainingTemporaryPaths).count == remainingTemporaryPaths.count,
      remainingTemporaryPaths.allSatisfy({
        Self.validCopyPath($0, absolute: false)
          && $0.split(separator: "/").last?.hasPrefix(".memoshi-export-") == true
      })
    else { throw WorkingCopyJournalError.invalidRequest }
    let progress = WorkingCopyExportProgress(
      completedPaths: completedPaths, remainingTemporaryPaths: remainingTemporaryPaths)
    let bytes = try encoder.encode(progress)
    guard bytes.count <= 65_536 else { throw WorkingCopyJournalError.invalidRequest }
    let settled = try writer.transaction(write: true) {
      guard let copy = try readWorkingCopy(id, database: writer), copy.phase != .interrupted,
        let previous = try readWorkingCopyExports(id, contentHash: contentHash, database: writer)
          .first,
        previous.runtimeTaskKey == runtimeTaskKey
      else { throw WorkingCopyJournalError.recoveryRequired }
      let paths = previous.changes.map(\.path)
      guard completedPaths.allSatisfy({ paths.contains($0) }),
        state != .applied || (completedPaths == paths && remainingTemporaryPaths.isEmpty),
        state != .notApplied || (completedPaths.isEmpty && remainingTemporaryPaths.isEmpty)
      else { throw WorkingCopyJournalError.invalidRequest }
      if previous.state != .pending {
        guard previous.state == state, previous.completedPaths == completedPaths,
          previous.remainingTemporaryPaths == remainingTemporaryPaths
        else { throw WorkingCopyJournalError.bindingConflict }
        return false
      }
      try writer.execute(
        "UPDATE working_copy_exports SET state = ?, progress = ?, updated_at = ? WHERE copy_id = ? AND content_hash = ?",
        [
          .text(state.rawValue), .json(bytes), .integer(now), .text(id.uuidString),
          .text(contentHash),
        ])
      return try removeSettledCopyIfClosed(id)
    }
    if settled { currentWorkingCopies.remove(id) }
  }

  /// Records the result of descriptor-owned cleanup. It performs no filesystem removal.
  /// Unknown/pending source outcomes survive even when private data was removed successfully.
  public func finishWorkingCopyCleanup(_ id: UUID, removed: Bool, at now: Int64) throws {
    try requireOpen()
    let settled = try writer.transaction(write: true) {
      guard let copy = try readWorkingCopy(id, database: writer) else { return true }
      guard currentWorkingCopies.contains(id), copy.phase != .interrupted else {
        throw WorkingCopyJournalError.recoveryRequired
      }
      try writer.execute(
        "UPDATE working_copies SET phase = ?, updated_at = ? WHERE id = ?",
        [.text(removed ? "closed" : "cleanup_required"), .integer(now), .text(id.uuidString)])
      return removed ? try removeSettledCopyIfClosed(id) : false
    }
    if settled { currentWorkingCopies.remove(id) }
  }

  /// Reads previous-instance copies, failed cleanup and unresolved effects in one snapshot.
  /// Does not access source/staging paths, refresh grants, attach copies or infer success.
  public func workingCopyRecoveries(chatID: ConversationID) throws -> [WorkingCopyRecovery] {
    try requireOpen()
    return try reader.transaction(write: false) {
      let ids = try reader.query(
        """
        SELECT c.id FROM working_copies c WHERE c.chat_id = ? AND
          (c.phase IN ('interrupted', 'cleanup_required') OR EXISTS (
            SELECT 1 FROM working_copy_exports e JOIN policy_tool_calls p
              ON p.conversation_id = e.conversation_id AND p.runtime_task_key = e.runtime_task_key
            WHERE e.copy_id = c.id AND (e.state = 'unknown' OR
              (c.phase = 'closed' AND (\(Self.unsettledCopyExport))))
              AND NOT \(Self.answeredCopyExport)))
        ORDER BY c.created_at, c.id
        """, [.text(chatID.rawValue)], row: { try $0.requiredText(0) })
      return try ids.map { raw in
        guard let id = UUID(uuidString: raw), let copy = try readWorkingCopy(id, database: reader)
        else {
          throw StoreError.invalidSchema("Invalid working-copy identity")
        }
        return try WorkingCopyRecovery(
          ownership: copy.ownership, phase: copy.phase,
          exports: readWorkingCopyExports(id, database: reader))
      }
    }
  }

  /// Runs only while opening the exclusively locked Store, before a new registration exists.
  /// WAL NORMAL provides process-restart evidence, not an OS-crash/power-loss guarantee.
  static func interruptPreviousWorkingCopies(_ database: SQLiteConnection) throws {
    try database.transaction(write: true) {
      try database.execute(
        "UPDATE working_copy_exports SET state = 'unknown' WHERE state = 'pending'")
      try database.execute(
        "UPDATE working_copies SET phase = 'interrupted' WHERE phase IN ('admitting', 'active')")
      try database.execute(
        """
        DELETE FROM working_copies WHERE phase = 'closed' AND NOT EXISTS (
          SELECT 1 FROM working_copy_exports e JOIN policy_tool_calls p
            ON p.conversation_id = e.conversation_id AND p.runtime_task_key = e.runtime_task_key
          WHERE e.copy_id = working_copies.id AND (\(unsettledCopyExport)))
        """)
    }
  }

  private struct CopyRow {
    var ownership: WorkingCopyOwnership
    let phase: WorkingCopyPhase
  }

  private func readWorkingCopy(_ id: UUID, database: SQLiteConnection) throws -> CopyRow? {
    try database.query(
      "SELECT chat_id, phase, record FROM working_copies WHERE id = ?", [.text(id.uuidString)]
    ) { row in
      let ownership = try decoder.decode(WorkingCopyOwnership.self, from: row.requiredData(2))
      guard let phase = WorkingCopyPhase(rawValue: try row.requiredText(1)), ownership.id == id,
        ownership.chatID.rawValue == (try row.requiredText(0)), ownership.deviceID == deviceID
      else { throw StoreError.invalidSchema("Invalid working-copy ownership") }
      return CopyRow(ownership: ownership, phase: phase)
    }.first
  }

  private func readWorkingCopyExports(
    _ id: UUID, contentHash: String? = nil, database: SQLiteConnection
  ) throws -> [WorkingCopyExportReceipt] {
    let filter = contentHash == nil ? "" : " AND e.content_hash = ?"
    var values: [SQLiteConnection.Value] = [.text(id.uuidString)]
    if let contentHash { values.append(.text(contentHash)) }
    return try database.query(
      """
      SELECT e.content_hash, e.arguments_hash, e.runtime_task_key, p.tool_call_id, p.task_id,
        e.changes, e.state, e.progress
      FROM working_copy_exports e JOIN policy_tool_calls p
        ON p.conversation_id = e.conversation_id AND p.runtime_task_key = e.runtime_task_key
      WHERE e.copy_id = ?\(filter) ORDER BY e.created_at, e.content_hash
      """, values
    ) { row in
      guard let state = WorkingCopyExportState(rawValue: try row.requiredText(6)) else {
        throw StoreError.invalidSchema("Invalid working-copy export state")
      }
      let progress = try decoder.decode(WorkingCopyExportProgress.self, from: row.requiredData(7))
      return try WorkingCopyExportReceipt(
        contentHash: row.requiredText(0), argumentsHash: row.requiredText(1),
        runtimeTaskKey: row.requiredText(2),
        callID: row.requiredText(3), taskID: TaskID(row.requiredText(4)),
        changes: decoder.decode([WorkingCopyExportChange].self, from: row.requiredData(5)),
        state: state,
        completedPaths: progress.completedPaths,
        remainingTemporaryPaths: progress.remainingTemporaryPaths)
    }
  }

  private func removeSettledCopyIfClosed(_ id: UUID) throws -> Bool {
    try writer.execute(
      """
      DELETE FROM working_copies WHERE id = ? AND phase = 'closed' AND NOT EXISTS (
        SELECT 1 FROM working_copy_exports e JOIN policy_tool_calls p
          ON p.conversation_id = e.conversation_id AND p.runtime_task_key = e.runtime_task_key
        WHERE e.copy_id = working_copies.id AND (\(Self.unsettledCopyExport)))
      """, [.text(id.uuidString)])
    return try writer.integer("SELECT changes()") == 1
  }

  /// A known file effect must outlive private cleanup until Pi's successful result is committed.
  /// A failed/missing Pi result still needs this positive evidence during reconciliation.
  /// An effect the user settled on its Resume card (D51) no longer holds anything.
  static let unsettledCopyExport = """
    (e.state IN ('pending', 'unknown') OR (e.state = 'applied' AND
      (p.completion_seq IS NULL OR json_extract(p.completion_input, '$.ok') IS NOT 1)))
      AND NOT \(answeredCopyExport)
    """

  /// The user answered this export's step on its Resume card. Its source files are left as
  /// they are: Skip and Mark as done record the user's account; neither changes a file.
  static let answeredCopyExport = """
    EXISTS (SELECT 1 FROM resume_steps r WHERE r.conversation_id = e.conversation_id
      AND r.runtime_task_key = e.runtime_task_key AND r.action IS NOT NULL)
    """

  private static func validateCopyChanges(
    _ changes: [WorkingCopyExportChange], contentHash: String, argumentsHash: String
  ) throws {
    guard validCopyHash(contentHash), validCopyHash(argumentsHash),
      (1...64).contains(changes.count),
      Set(changes.map(\.path)).count == changes.count,
      changes.allSatisfy({ change in
        guard validCopyPath(change.path, absolute: false) else { return false }
        switch change.operation {
        case "create": return change.baseHash == nil && change.newHash.map(validCopyHash) == true
        case "replace":
          return change.baseHash.map(validCopyHash) == true
            && change.newHash.map(validCopyHash) == true
        case "delete": return change.baseHash.map(validCopyHash) == true && change.newHash == nil
        default: return false
        }
      })
    else { throw WorkingCopyJournalError.invalidRequest }
  }

  private static func validCopyHash(_ hash: String) -> Bool {
    hash.utf8.count == 64
      && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  private static func validCopyPath(_ path: String, absolute: Bool) -> Bool {
    guard !path.isEmpty, path.utf8.count <= 4096, (path.utf8.first == 47) == absolute,
      !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { return false }
    let components = (absolute ? path.dropFirst() : path[...]).split(
      separator: "/", omittingEmptySubsequences: false)
    return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
  }
}
