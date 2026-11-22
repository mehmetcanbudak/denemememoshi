import Foundation
import MemoshiProtocol

// Pattern re-implemented from Memoshi-Plan ce39f8a7ca324ce1c2473518593b1fb4f96ebe4b,
// sidecar/src/store/db.ts and store/migrations.ts. Draft 4's storage contract governs.
enum StoreMigrations {
  static let currentVersion = 15
  private static let files = [
    "001_event_log", "002_records_and_ownership", "003_text_chat", "004_policy_and_approvals",
    "005_policy_tool_audit", "006_folder_grants", "007_working_copy_journal",
    "008_chat_recovery", "009_conversations_and_bots", "010_runtime_subagents",
    "011_conversation_lifecycle", "012_gateway_audit", "013_log_identity",
    "014_resume_steps", "015_sandbox_attribution",
  ]

  struct Opened {
    let report: MigrationReport
    let deviceID: DeviceID
    let logID: LogID
  }

  static func apply(
    to database: SQLiteConnection, directory: URL, deviceID: DeviceID?
  ) throws -> Opened {
    let found = Int(try database.integer("PRAGMA user_version") ?? 0)
    guard found >= 0 else { throw StoreError.invalidSchema("Negative schema version") }
    guard found <= currentVersion else {
      throw StoreError.schemaTooNew(found: found, supported: currentVersion)
    }
    try quickCheck(database)
    if found == 0 {
      let count = try database.integer(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
      guard count == 0 else {
        throw StoreError.invalidSchema("Unversioned database already contains application tables")
      }
    } else {
      let versions = try database.query("SELECT version FROM schema_migrations ORDER BY version") {
        Int($0.integer(0))
      }
      guard versions == Array(1...found) else {
        throw StoreError.invalidSchema("Migration journal disagrees with user_version")
      }
    }
    guard try database.text("PRAGMA journal_mode = WAL")?.lowercased() == "wal" else {
      throw StoreError.invalidSchema("WAL journal mode is unavailable")
    }
    try database.execute("PRAGMA synchronous = NORMAL")
    // Under NORMAL only checkpoints sync. Apple's system SQLite makes these full syncs
    // F_BARRIERFSYNC (Pi_Swift ADR-0001): ordered, not drained to permanent storage. A durable
    // commit (`SQLiteConnection.transaction(durable:)`) therefore drains the device itself
    // (`DeviceDrain`); the ordering keeps a later checkpoint's database writes ahead of the WAL
    // reset that reuses that commit's frames.
    try database.execute("PRAGMA fullfsync = ON")
    try database.execute("PRAGMA checkpoint_fullfsync = ON")
    _ = try database.integer("PRAGMA journal_size_limit = 67108864")

    var backupURL: URL?
    var migrated = false
    defer {
      // A backup that failed its own check is no backup, and a rolled-back upgrade leaves the
      // store exactly as its backup copied it: the next attempt takes its own, so keeping
      // this one would add a full copy for every failed open.
      if !migrated, let backupURL { try? FileManager.default.removeItem(at: backupURL) }
    }
    if found > 0 && found < currentVersion {
      var url = directory.appendingPathComponent("backups/pre-\(currentVersion).sqlite")
      if FileManager.default.fileExists(atPath: url.path) {
        let suffix = try IDGenerator.shared.next().rawValue
        url = directory.appendingPathComponent("backups/pre-\(currentVersion)-\(suffix).sqlite")
      }
      backupURL = url
      try database.execute("VACUUM INTO ?", [.text(url.path)])
      try StorePaths.databaseFile(url)
      let backup = try SQLiteConnection(url: url, readOnly: true)
      try quickCheck(backup)
      try backup.close()
    }

    let (identity, logID) = try database.transaction(write: true) {
      if found < currentVersion {
        for version in (found + 1)...currentVersion {
          guard
            let resource = Bundle.module.url(
              forResource: files[version - 1], withExtension: "sql", subdirectory: "Migrations")
          else { throw StoreError.invalidSchema("Missing numbered migration \(version)") }
          let sql = try String(contentsOf: resource, encoding: .utf8)
          try database.executeScript(sql)
          let violations = try database.query("PRAGMA foreign_key_check") { _ in true }
          guard violations.isEmpty else {
            throw StoreError.integrityFailed("Migration \(version) failed foreign_key_check")
          }
          try database.execute(
            "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
            [.integer(Int64(version)), .integer(IDGenerator.nowMilliseconds())])
          try database.execute("PRAGMA user_version = \(version)")
        }
      }
      let identity: DeviceID
      if let raw = try database.text("SELECT value FROM meta WHERE key = 'device_id'") {
        identity = try DeviceID(raw)
        guard deviceID == nil || deviceID == identity else {
          throw StoreError.deviceIdentityMismatch
        }
      } else {
        guard found == 0 else {
          throw StoreError.invalidSchema("An existing store lost its stable device identity")
        }
        identity = try deviceID ?? IDGenerator.shared.objectID(DeviceIDKind.self)
        try database.execute(
          "INSERT INTO meta (key, value) VALUES ('device_id', ?)", [.text(identity.rawValue)])
      }
      if let backupURL {
        _ = try EventPersistence.append(
          EventDraft(
            ts: IDGenerator.nowMilliseconds(), actor: Actor(kind: .system),
            subject: ObjectRef(kind: "system", id: "memoshi"),
            event: .systemMigrated(
              SystemMigratedPayload(
                store: "memoshi", fromSchema: found, toSchema: currentVersion,
                backupPath: backupURL.path))),
          deviceID: identity, database: database, encoder: ProtocolCoding.makeEncoder(),
          decoder: ProtocolCoding.makeDecoder(strict: true))
      }
      // Migration 13 minted the log's identity; nothing else writes it, and a store that lost
      // it is refused rather than given another.
      guard let raw = try database.text("SELECT value FROM meta WHERE key = 'log_id'"),
        raw.utf8.count == 32,
        raw.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) })
      else { throw StoreError.invalidSchema("The event log has no valid identity") }
      return (identity, try LogID(raw))
    }
    migrated = true
    try quickCheck(database)
    return Opened(
      report: MigrationReport(fromVersion: found, toVersion: currentVersion, backupURL: backupURL),
      deviceID: identity, logID: logID)
  }

  private static func quickCheck(_ database: SQLiteConnection) throws {
    let results = try database.query("PRAGMA quick_check") { try $0.requiredText(0) }
    guard results == ["ok"] else {
      throw StoreError.integrityFailed("quick_check failed")
    }
    let violations = try database.query("PRAGMA foreign_key_check") { _ in true }
    guard violations.isEmpty else {
      throw StoreError.integrityFailed("foreign_key_check failed")
    }
  }
}
