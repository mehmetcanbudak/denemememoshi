import Foundation
import MemoshiProtocol

/// One serial writer and a read-only snapshot connection over SDK SQLite WAL. Tables are
/// current state; events are a prunable change feed. No transcript or Pi storage lives here.
public actor Store {
  /// The newest numbered application schema this build can open.
  public nonisolated static let schemaVersion = StoreMigrations.currentVersion
  /// The persisted device identity, preserved across store reopen.
  public nonisolated let deviceID: DeviceID
  /// The event log's identity: created with the log, kept in this database and never changed.
  /// A copy of the database carries it; a newly created one has another. Equality only.
  public nonisolated let logID: LogID
  /// The actual schema transition and pre-upgrade backup from this open.
  public nonisolated let migration: MigrationReport

  nonisolated let eventBus = EventBus()
  let directory: URL
  let directories: StoreDirectories
  let writer: SQLiteConnection
  let reader: SQLiteConnection
  let writerLock: FileLock
  let encoder = ProtocolCoding.makeEncoder()
  let decoder = ProtocolCoding.makeDecoder(strict: true)
  /// Copy capabilities are instance-bound; a reopened Store only reports earlier ownership.
  var currentWorkingCopies: Set<UUID> = []
  /// Process-owned intents remain live until their actual Pi result is committed.
  var currentUnsafeDispatches: [ConversationID: Set<String>] = [:]
  var parkedDispatchEpochs: [ConversationID: Int64] = [:]
  /// Turns recorded as resumed by this instance: a reopened Store follows a restart, whose
  /// continuation is recorded once (`recordTurnResumed`).
  var resumedTurns: Set<ULID> = []
  /// Subagent tasks whose automatic continuation after a restart was recorded once in this
  /// Store instance (`recordSubagentResumed`).
  var resumedSubagents: Set<TaskID> = []
  var isClosed = false

  /// The optional identity is only for first creation or an explicit identity assertion.
  /// Reopening without one always preserves the stored device ID.
  public init(directory: URL, deviceID: DeviceID? = nil) throws {
    try self.init(directory: directory, deviceID: deviceID, fullSync: DeviceDrain.fullSync)
  }

  /// `fullSync` drains the device after each durable commit; tests replace it.
  init(directory: URL, deviceID: DeviceID?, fullSync: @escaping DeviceDrain.FullSync) throws {
    let directory = directory.standardizedFileURL
    try StorePaths.prepare(directory)
    let directories = try StoreDirectories(directory)
    let lock = try directories.acquireWriterLock()
    let file = directory.appendingPathComponent("memoshi.sqlite")
    try StorePaths.databaseFile(file)
    let writer = try SQLiteConnection(
      url: file, drain: DeviceDrain(directories: directories, fullSync: fullSync))
    let opened = try StoreMigrations.apply(to: writer, directory: directory, deviceID: deviceID)
    let reader = try SQLiteConnection(url: file, readOnly: true)
    try Self.interruptPreviousWorkingCopies(writer)
    self.directory = directory
    self.directories = directories
    self.writer = writer
    self.reader = reader
    self.writerLock = lock
    self.deviceID = opened.deviceID
    self.logID = opened.logID
    self.migration = opened.report
  }

  deinit {
    eventBus.close()
    try? reader.close()
    try? writer.close()
    writerLock.release()
    directories.release()
  }

  /// Releases connections before the local writer lock. Existing ConversationOwnership values
  /// must still be released by their owners after closing their runtime harnesses.
  public func close() throws {
    guard isClosed == false else { return }
    try reader.close()
    try writer.close()
    isClosed = true
    eventBus.close()
    writerLock.release()
    directories.release()
  }

  /// Returns and publishes numbered envelopes only after COMMIT succeeds, before actor reentry.
  /// A failed transaction publishes nothing.
  public func commit(_ commit: StoreCommit, at now: Int64) throws -> [EventEnvelope] {
    try requireOpen()
    guard
      !commit.events.contains(where: {
        $0.event.type.hasPrefix("grant.") || $0.event.type.hasPrefix("bot.")
          || $0.event.type == "chat.created" || $0.event.type.hasPrefix("session.")
          || $0.event.type == "trash.emptied"
      })
    else {
      throw StoreError.invalidCommit("A lifecycle fact is written only with its object transition")
    }
    let committed = try writer.transaction(write: true) {
      var fences: [ConversationID: ConversationFence] = [:]
      for fence in commit.fences {
        guard fences.updateValue(fence, forKey: fence.conversationID) == nil else {
          throw StoreError.invalidCommit("Duplicate conversation fence")
        }
      }
      var conversations = Set(commit.records.map(\.conversationID))
      conversations.formUnion(commit.events.compactMap(\.scope.conversationId))
      for conversation in conversations {
        guard let fence = fences[conversation] else {
          throw StoreError.leaseFenced(
            conversationID: conversation, currentEpoch: try readLease(conversation)?.epoch)
        }
        try checkFence(fence, at: now)
      }
      for record in commit.records {
        guard
          commit.events.contains(where: {
            $0.subject == record.subject && $0.scope.conversationId == record.conversationID
          })
        else {
          throw StoreError.invalidCommit(
            "A changed record needs its subject event in this transaction")
        }
        try writeRecord(record)
      }
      var appended: [EventEnvelope] = []
      appended.reserveCapacity(commit.events.count)
      for draft in commit.events {
        appended.append(try append(draft))
      }
      return appended
    }
    eventBus.publish(committed)
    return committed
  }

  /// Subscribe before reading replay bounds; the buffered stream bridges replay into live.
  public nonisolated func subscribeEvents(
    conversationID: ConversationID? = nil, capacity: Int = 128
  ) throws -> AsyncThrowingStream<EventEnvelope, any Error> {
    try eventBus.subscribe(conversationID: conversationID, capacity: capacity)
  }

  func requireOpen() throws {
    guard isClosed == false else { throw StoreError.closed }
  }

  func validatedRecord<Value: Codable>(_ value: Value) throws -> Data {
    let bytes = try encoder.encode(value)
    _ = try decoder.decode(Value.self, from: bytes)
    return bytes
  }

  func append(_ draft: EventDraft) throws -> EventEnvelope {
    try EventPersistence.append(
      draft, deviceID: deviceID, database: writer, encoder: encoder, decoder: decoder)
  }

  func decodePayload<Payload: EventPayload>(_ type: Payload.Type, data: Data) throws -> Event {
    try EventPersistence.decodePayload(type, data: data, decoder: decoder)
  }
}
