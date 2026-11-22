import CSQLite
import Foundation

// Connections are used only by Store's serial actor (or synchronously during initialization).
// FULLMUTEX additionally protects the C handle; no handle or statement crosses the public seam.
final class SQLiteConnection: @unchecked Sendable {
  enum Value {
    case text(String)
    case json(Data)
    case blob(Data)
    case integer(Int64)
    case null

    init(_ value: String?) {
      self = value.map(Self.text) ?? .null
    }
  }

  private var handle: OpaquePointer?
  /// How a durable commit reaches permanent storage; nil on a connection that never makes one.
  private let drain: DeviceDrain?

  init(url: URL, readOnly: Bool = false, drain: DeviceDrain? = nil) throws {
    var opened: OpaquePointer?
    let flags =
      (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
      | SQLITE_OPEN_FULLMUTEX
    let code = sqlite3_open_v2(url.path, &opened, flags, nil)
    guard code == SQLITE_OK, let opened else {
      if let opened { sqlite3_close_v2(opened) }
      throw StoreError.storage(code: code, operation: "open")
    }
    handle = opened
    self.drain = drain
    sqlite3_extended_result_codes(opened, 1)
    do {
      try check(sqlite3_busy_timeout(opened, 5_000), operation: "busy_timeout")
      try execute("PRAGMA foreign_keys = ON")
      if readOnly { try execute("PRAGMA query_only = ON") }
    } catch {
      sqlite3_close_v2(opened)
      handle = nil
      throw error
    }
  }

  deinit {
    if let handle { sqlite3_close_v2(handle) }
  }

  func close() throws {
    guard let handle else { return }
    try check(sqlite3_close(handle), operation: "close")
    self.handle = nil
  }

  private func check(_ code: Int32, operation: String) throws {
    guard code == SQLITE_OK else {
      throw StoreError.storage(code: code, operation: operation)
    }
  }

  func executeScript(_ sql: String) throws {
    guard let handle else { throw StoreError.closed }
    // Only bundled, numbered migrations use sqlite3_exec; all values elsewhere are bound.
    try check(sqlite3_exec(handle, sql, nil, nil, nil), operation: "migration")
  }

  func execute(_ sql: String, _ values: [Value] = []) throws {
    try statement(sql, values) { statement in
      let code = sqlite3_step(statement.pointer)
      guard code == SQLITE_DONE else {
        throw StoreError.storage(code: code, operation: "write")
      }
    }
  }

  func query<Result>(
    _ sql: String, _ values: [Value] = [], row: (SQLiteRow) throws -> Result
  ) throws -> [Result] {
    try statement(sql, values) { statement in
      var rows: [Result] = []
      while true {
        let code = sqlite3_step(statement.pointer)
        if code == SQLITE_DONE { return rows }
        guard code == SQLITE_ROW else {
          throw StoreError.storage(code: code, operation: "read")
        }
        rows.append(try row(statement))
      }
    }
  }

  func integer(_ sql: String, _ values: [Value] = []) throws -> Int64? {
    try query(sql, values) { $0.optionalInteger(0) }.first ?? nil
  }

  func text(_ sql: String, _ values: [Value] = []) throws -> String? {
    try query(sql, values) { $0.text(0) }.first ?? nil
  }

  var lastInsertID: Int64 {
    get throws {
      guard let handle else { throw StoreError.closed }
      return sqlite3_last_insert_rowid(handle)
    }
  }

  var changedRows: Int {
    get throws {
      guard let handle else { throw StoreError.closed }
      return Int(sqlite3_changes(handle))
    }
  }

  /// `durable` commits with `synchronous = FULL`, so SQLite syncs the WAL before COMMIT returns,
  /// then drains the device's cache (`DeviceDrain`) before this returns: the commit survives power
  /// loss, as far as the device honours the drain. A refused drain throws `DeviceDrain.refused`
  /// after the commit was published; the caller must not act on it. Every other commit keeps
  /// `NORMAL`, which survives a process kill only.
  func transaction<Result>(write: Bool, durable: Bool = false, _ body: () throws -> Result)
    throws -> Result
  {
    if durable {
      guard drain != nil else {
        throw StoreError.invalidCommit("No device drain for a durable commit")
      }
      try execute("PRAGMA synchronous = FULL")
    }
    defer { if durable { try? execute("PRAGMA synchronous = NORMAL") } }
    try execute(write ? "BEGIN IMMEDIATE" : "BEGIN DEFERRED")
    let result: Result
    do {
      result = try body()
      try execute("COMMIT")
    } catch {
      if let handle, sqlite3_get_autocommit(handle) == 0 {
        try execute("ROLLBACK")
      }
      throw error
    }
    if durable { try drain?.drain() }
    return result
  }

  private func statement<Result>(
    _ sql: String, _ values: [Value], _ body: (SQLiteRow) throws -> Result
  ) throws -> Result {
    guard let handle else { throw StoreError.closed }
    var prepared: OpaquePointer?
    try check(sqlite3_prepare_v2(handle, sql, -1, &prepared, nil), operation: "prepare")
    guard let prepared else { throw StoreError.invalidSchema("Empty SQL statement") }
    defer { sqlite3_finalize(prepared) }
    guard Int(sqlite3_bind_parameter_count(prepared)) == values.count else {
      throw StoreError.invalidSchema("Incorrect binding count")
    }
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      let code: Int32
      switch value {
      case .integer(let value):
        code = sqlite3_bind_int64(prepared, index, value)
      case .null:
        code = sqlite3_bind_null(prepared, index)
      case .text(let value):
        let count = value.utf8.count
        guard count <= Int32.max else {
          throw StoreError.invalidCommit("SQLite text exceeds the supported size")
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        code = value.withCString { sqlite3_bind_text(prepared, index, $0, Int32(count), transient) }
      case .json(let value):
        guard value.isEmpty == false, value.count <= Int32.max else {
          throw StoreError.invalidCommit("Invalid SQLite JSON byte count")
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        code = value.withUnsafeBytes {
          sqlite3_bind_text(
            prepared, index, $0.baseAddress?.assumingMemoryBound(to: CChar.self),
            Int32(value.count), transient)
        }
      case .blob(let value):
        guard value.isEmpty == false, value.count <= Int32.max else {
          throw StoreError.invalidCommit("Invalid SQLite blob byte count")
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        code = value.withUnsafeBytes {
          sqlite3_bind_blob(prepared, index, $0.baseAddress, Int32(value.count), transient)
        }
      }
      try check(code, operation: "bind")
    }
    return try body(SQLiteRow(pointer: prepared))
  }
}

/// Pi_Swift ADR-0001: Apple's system SQLite was observed issuing `F_BARRIERFSYNC`, not
/// `F_FULLFSYNC`, with `PRAGMA fullfsync = ON`; that orders writes but leaves them in the drive's
/// cache. A durable commit is therefore followed by its own `F_FULLFSYNC` on a descriptor of the
/// database's directory, as Pi_Swift's power-loss VFS does (`CChordSQLite/PowerLoss.c`): it does
/// what fsync does for the directory, then drains the whole device queue, so the WAL frames
/// SQLite synced before it are on permanent storage when it returns. A directory descriptor
/// holds no SQLite lock. A failed drain fails the commit's caller; there is no fallback to
/// `F_BARRIERFSYNC` or fsync.
struct DeviceDrain: Sendable {
  /// Drains the device behind a descriptor: 0, or the failure's nonzero errno.
  typealias FullSync = @Sendable (Int32) -> Int32

  /// What a refused drain throws, like Pi_Swift's refused strict sync: `SQLITE_IOERR_FSYNC`
  /// (1034), which Swift cannot import as a macro.
  static let refused = StoreError.storage(code: SQLITE_IOERR | (4 << 8), operation: "drain")

  /// `F_FULLFSYNC`, restarted after EINTR; a failure that leaves errno 0 is reported as EIO.
  static let fullSync: FullSync = { descriptor in
    while true {
      if fcntl(descriptor, F_FULLFSYNC) == 0 { return 0 }
      let error = errno
      if error != EINTR { return error != 0 ? error : EIO }
    }
  }

  let directories: StoreDirectories
  let fullSync: FullSync

  func drain() throws {
    try directories.withRootDirectory { descriptor in
      guard fullSync(descriptor) == 0 else { throw Self.refused }
    }
  }
}

struct SQLiteRow {
  let pointer: OpaquePointer

  func optionalInteger(_ index: Int32) -> Int64? {
    sqlite3_column_type(pointer, index) == SQLITE_NULL ? nil : sqlite3_column_int64(pointer, index)
  }

  func integer(_ index: Int32) -> Int64 {
    sqlite3_column_int64(pointer, index)
  }

  func text(_ index: Int32) -> String? {
    guard let bytes = sqlite3_column_text(pointer, index) else { return nil }
    let count = Int(sqlite3_column_bytes(pointer, index))
    return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
  }

  func data(_ index: Int32) -> Data? {
    guard sqlite3_column_type(pointer, index) != SQLITE_NULL else { return nil }
    let count = Int(sqlite3_column_bytes(pointer, index))
    guard let bytes = sqlite3_column_blob(pointer, index) else { return Data() }
    return Data(bytes: bytes, count: count)
  }

  func requiredData(_ index: Int32) throws -> Data {
    guard let value = data(index) else {
      throw StoreError.invalidSchema("Unexpected NULL JSON")
    }
    return value
  }

  func requiredText(_ index: Int32) throws -> String {
    guard let value = text(index) else {
      throw StoreError.invalidSchema("Unexpected NULL text")
    }
    return value
  }
}
