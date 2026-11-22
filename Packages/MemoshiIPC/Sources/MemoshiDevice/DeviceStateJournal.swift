import CryptoKit
import Darwin
import Foundation
import Synchronization

/// The system calls that order a journal's writes on disk. Tests record or fail them.
struct DeviceJournalCalls: Sendable {
  /// `fcntl(descriptor, command)`, for `F_BARRIERFSYNC` and `F_FULLFSYNC`.
  var control: @Sendable (_ descriptor: Int32, _ command: Int32) -> Int32
  /// `fsync(descriptor)`.
  var synchronize: @Sendable (_ descriptor: Int32) -> Int32
  /// `renameat(directory, from, directory, to)`.
  var rename: @Sendable (_ directory: Int32, _ from: String, _ to: String) -> Int32

  static let system = DeviceJournalCalls(
    control: { fcntl($0, $1) }, synchronize: { fsync($0) },
    rename: { renameat($0, $1, $0, $2) })
}

/// Single-owner durable journal, or atomic latest-value checkpoint via ``replace(_:)``.
/// A stable private lock survives checkpoint renames. Torn append tails recover; complete
/// corruption fails closed. This is not rollback-resistant storage or a distributed authority.
public final class DeviceStateJournal: Sendable {
  private struct Entry: Codable {
    var version: Int
    var sequence: UInt64
    var previous: Data
    var payload: Data
    var digest: Data
  }

  private struct State {
    var handle: FileHandle?
    var lockHandle: FileHandle?
    var directoryHandle: FileHandle?
    var sequence: UInt64
    var digest: Data
    var failed = false
    var written: UInt64 = 0
    /// Whether the marker of a completed replacement is on disk (`guardsReplacement` only).
    var replacementMarked = false
  }

  private let recoveredRows: Mutex<[Data]>
  /// The on-disk length of each row recovered at open, line end included, in journal order.
  let recoveredRowBytes: [Int]
  private let state: Mutex<State>
  private let key: SymmetricKey?
  private let purpose: Data
  private let filename: String
  private let guardsReplacement: Bool
  private let calls: DeviceJournalCalls
  private static let maximumRecordBytes = 32 * 1024 * 1024

  /// Cross-module local state is always encrypted. The host owns a distinct purpose/key
  /// namespace and serializes its durable mutations; this journal never supplies a data key.
  ///
  /// `guardsReplacement` is for an owner that replaces its whole history from time to time
  /// (``replaceHistory(with:)``): once a replacement has completed, the file must open with a
  /// complete first row. A file that holds none, because a power loss kept the rename of a
  /// replacement but not its rows, fails closed instead of opening empty. `discardingHistory`
  /// opens without reading the rows at all, for an erasure that replaces them next and must
  /// work also when they can no longer be read; until that replacement nothing can be appended.
  public convenience init(
    url: URL, key: SymmetricKey, purpose: String, guardsReplacement: Bool = false,
    discardingHistory: Bool = false
  ) throws {
    try self.init(
      url: url, key: Optional(key), purpose: purpose, readsHistory: !discardingHistory,
      guardsReplacement: guardsReplacement)
  }

  /// `createsFile: false` is for a latest-value checkpoint: the file is opened only when a
  /// checkpoint was already written, and the first ``replace(_:)`` creates it atomically.
  init(
    url: URL, key: SymmetricKey? = nil, purpose: String, createsFile: Bool = true,
    readsHistory: Bool = true, guardsReplacement: Bool = false,
    calls: DeviceJournalCalls = .system
  ) throws {
    self.key = key
    let purposeData = Data(purpose.utf8)
    self.purpose = purposeData
    filename = url.lastPathComponent
    self.guardsReplacement = guardsReplacement
    self.calls = calls
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    guard parent >= 0 else { throw DeviceLayerError.io("device journal directory") }
    let directoryHandle = FileHandle(fileDescriptor: parent, closeOnDealloc: true)
    var initialized = false
    defer { if !initialized { try? directoryHandle.close() } }
    var directoryInfo = stat()
    guard fstat(parent, &directoryInfo) == 0, directoryInfo.st_uid == getuid(),
      directoryInfo.st_mode & 0o077 == 0
    else { throw DeviceLayerError.io("private device journal directory required") }
    let lockDescriptor = openat(
      parent, url.lastPathComponent + ".lock", O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard lockDescriptor >= 0 else { throw DeviceLayerError.io("device journal lock") }
    let lockHandle = FileHandle(fileDescriptor: lockDescriptor, closeOnDealloc: true)
    defer { if !initialized { try? lockHandle.close() } }
    var lockInfo = stat()
    guard fstat(lockDescriptor, &lockInfo) == 0, lockInfo.st_uid == getuid(),
      lockInfo.st_mode & S_IFMT == S_IFREG, lockInfo.st_mode & 0o077 == 0, lockInfo.st_nlink == 1,
      flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0
    else { throw DeviceLayerError.io("exclusive private device journal lock required") }
    let marked = guardsReplacement ? try Self.hasReplacementMarker(filename, in: parent) : false
    let descriptor =
      readsHistory
      ? openat(
        parent, url.lastPathComponent,
        O_RDWR | (createsFile ? O_CREAT : 0) | O_CLOEXEC | O_NOFOLLOW, 0o600) : -1
    guard descriptor >= 0 else {
      if readsHistory {
        guard !createsFile, errno == ENOENT else {
          throw DeviceLayerError.io("device journal open")
        }
        guard !marked else { throw Self.lostReplacement }
      }
      recoveredRows = Mutex([])
      recoveredRowBytes = []
      state = Mutex(
        State(
          handle: nil, lockHandle: lockHandle, directoryHandle: directoryHandle,
          sequence: 0, digest: Data(repeating: 0, count: 32), replacementMarked: marked))
      initialized = true
      return
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do {
      var info = stat()
      guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
        info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0, info.st_nlink == 1,
        info.st_size <= 512 * 1024 * 1024,
        flock(descriptor, LOCK_EX | LOCK_NB) == 0
      else { throw DeviceLayerError.io("exclusive private device journal required") }
      let bytes = try handle.readToEnd() ?? Data()
      var recovered: [Data] = []
      var rowBytes: [Int] = []
      var sequence: UInt64 = 0
      var digest = Data(repeating: 0, count: 32)
      var offset = bytes.startIndex
      while let newline = bytes[offset...].firstIndex(of: 0x0A) {
        let line = bytes[offset..<newline]
        guard !line.isEmpty, line.count <= Self.maximumRecordBytes,
          let entry = try? JSONDecoder().decode(Entry.self, from: Data(line)),
          entry.version == 1, entry.sequence == sequence + 1, entry.previous == digest,
          entry.digest == Self.digest(entry.payload, sequence: entry.sequence, previous: digest)
        else { throw DeviceLayerError.invalid("corrupt device journal") }
        let authentication = Self.authentication(
          purpose: purposeData, sequence: entry.sequence, previous: digest)
        if let key {
          let box = try AES.GCM.SealedBox(combined: entry.payload)
          recovered.append(try AES.GCM.open(box, using: key, authenticating: authentication))
        } else {
          recovered.append(entry.payload)
        }
        sequence = entry.sequence
        digest = entry.digest
        rowBytes.append(line.count + 1)
        offset = bytes.index(after: newline)
      }
      // A completed replacement left at least one complete row. A file without one lost it
      // after its rename reached the disk: refused before anything is truncated.
      guard !marked || !recovered.isEmpty else { throw Self.lostReplacement }
      if offset != bytes.endIndex {
        guard ftruncate(descriptor, off_t(offset)) == 0 else {
          throw DeviceLayerError.io("device journal tail recovery")
        }
        try handle.synchronize()
      }
      try handle.seekToEnd()
      guard calls.synchronize(parent) == 0 else {
        throw DeviceLayerError.io("device journal directory sync")
      }
      recoveredRows = Mutex(recovered)
      recoveredRowBytes = rowBytes
      state = Mutex(
        State(
          handle: handle, lockHandle: lockHandle, directoryHandle: directoryHandle,
          sequence: sequence, digest: digest, replacementMarked: marked))
      initialized = true
    } catch {
      try? handle.close()
      throw error
    }
  }

  private static let lostReplacement = DeviceLayerError.invalid(
    "device journal lost its replaced history")

  /// The marker a guarded journal leaves beside its file once a replacement has completed.
  private static func replacementMarker(_ filename: String) -> String { filename + ".replaced" }

  private static func hasReplacementMarker(_ filename: String, in parent: Int32) throws -> Bool {
    var info = stat()
    if fstatat(parent, replacementMarker(filename), &info, AT_SYMLINK_NOFOLLOW) == 0 {
      return true
    }
    guard errno == ENOENT else { throw DeviceLayerError.io("device journal replacement marker") }
    return false
  }

  /// Transfers the authenticated/decrypted rows recovered at open, in journal order.
  /// Drains only the in-memory recovery buffer; later calls return empty until a new open.
  public func takeRecovered() -> [Data] {
    recoveredRows.withLock { rows in
      defer { rows.removeAll(keepingCapacity: false) }
      return rows
    }
  }

  /// Bytes this owner has written and synchronized since it opened the journal.
  var bytesWritten: UInt64 { state.withLock { $0.written } }

  /// Encodes, encrypts and appends one chained record, synchronizing it before success.
  /// Failure inside the append boundary poisons further writes; an uncertain write must be
  /// reconciled by reopening, which discards only an incomplete final line.
  public func append<T: Encodable>(_ value: T) throws {
    try append(value, endsAfterSynchronizing: false)
  }

  /// `endsAfterSynchronizing` writes the record without its line end, synchronizes it behind a
  /// write barrier, then writes and synchronizes the line end: a complete line was on disk in
  /// full before it ended, also after a power loss, so a crash at any point leaves at most an
  /// unended last line, which reopening discards.
  func append<T: Encodable>(_ value: T, endsAfterSynchronizing: Bool) throws {
    let plaintext = try JSONEncoder().encode(value)
    try state.withLock { state in
      guard let handle = state.handle, !state.failed else {
        throw DeviceLayerError.io("device journal unavailable")
      }
      do {
        let sequence = state.sequence + 1
        let entry = try encodedRecord(plaintext, sequence: sequence, previous: state.digest)
        if endsAfterSynchronizing {
          // The barrier orders the row before its line end, and before anything written
          // after it (also another file's next row); the line end itself needs no barrier.
          try handle.write(contentsOf: entry.bytes.dropLast())
          try synchronizeInOrder(handle.fileDescriptor)
          try handle.write(contentsOf: entry.bytes.suffix(1))
        } else {
          try handle.write(contentsOf: entry.bytes)
        }
        try handle.synchronize()
        state.written += UInt64(entry.bytes.count)
        state.sequence = sequence
        state.digest = entry.digest
      } catch {
        state.failed = true
        throw error
      }
    }
  }

  /// Atomically replaces the last checkpoint, unlinking historical secret snapshots. The
  /// bounded `.next` file is private and at most one interrupted replacement survives a kill.
  /// This does not promise secure erasure from flash, filesystem snapshots or external backups.
  /// Any failure poisons the journal.
  public func replace<T: Encodable>(_ value: T) throws {
    let plaintext = try JSONEncoder().encode(value)
    try state.withLock { state in
      _ = try replaceHoldingLock(&state, rows: [plaintext], keepsHistoryOnFailure: false)
    }
  }

  /// Replaces the whole history by `rows`, in order, in one atomic step, as ``replace(_:)``
  /// replaces a checkpoint: they are written to the private `.next` file and synchronized
  /// behind a write barrier before it is renamed over the journal, and the directory is
  /// synchronized after; later appends follow them. Returns false when the new file could not
  /// be written or renamed: nothing changed, and the old history is still complete and in use.
  /// A throw means the replacement happened but could not be made durable; the journal then
  /// takes no more writes and its owner must fail closed.
  public func replaceHistory<T: Encodable>(with rows: [T]) throws -> Bool {
    guard !rows.isEmpty else { throw DeviceLayerError.invalid("empty device journal history") }
    let plaintexts: [Data]
    do {
      let encoder = JSONEncoder()
      plaintexts = try rows.map { try encoder.encode($0) }
    } catch {
      return false
    }
    return try state.withLock { state in
      try replaceHoldingLock(&state, rows: plaintexts, keepsHistoryOnFailure: true)
    }
  }

  private func replaceHoldingLock(
    _ state: inout State, rows plaintexts: [Data], keepsHistoryOnFailure: Bool
  ) throws -> Bool {
    guard let directory = state.directoryHandle, !state.failed else {
      throw DeviceLayerError.io("device journal unavailable")
    }
    let parent = directory.fileDescriptor
    let pending = filename + ".next"
    var replacement: FileHandle?
    var safePending = false
    var sequence: UInt64 = 0
    var digest = Data(repeating: 0, count: 32)
    var written: UInt64 = 0
    do {
      let descriptor = openat(parent, pending, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
      guard descriptor >= 0 else { throw DeviceLayerError.io("device checkpoint open") }
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      replacement = handle
      var info = stat()
      guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
        info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0, info.st_nlink == 1,
        flock(descriptor, LOCK_EX | LOCK_NB) == 0, ftruncate(descriptor, 0) == 0
      else { throw DeviceLayerError.io("private device checkpoint required") }
      safePending = true
      for plaintext in plaintexts {
        let entry = try encodedRecord(plaintext, sequence: sequence + 1, previous: digest)
        try handle.write(contentsOf: entry.bytes)
        sequence += 1
        digest = entry.digest
        written += UInt64(entry.bytes.count)
      }
      // The new rows reach the disk before the rename that makes them the journal, also on
      // power loss; otherwise the journal could be renamed into place without them.
      try synchronizeInOrder(descriptor)
      guard calls.rename(parent, pending, filename) == 0 else {
        throw DeviceLayerError.io("device checkpoint replacement")
      }
    } catch {
      try? replacement?.close()
      if safePending { _ = unlinkat(parent, pending, 0) }
      if keepsHistoryOnFailure { return false }
      state.failed = true
      throw error
    }
    do {
      guard calls.synchronize(parent) == 0 else {
        throw DeviceLayerError.io("device checkpoint directory sync")
      }
      try markReplacement(&state, in: parent)
      try state.handle?.close()
    } catch {
      state.failed = true
      try? replacement?.close()
      throw error
    }
    state.handle = replacement
    state.sequence = sequence
    state.digest = digest
    state.written += written
    recoveredRows.withLock { $0.removeAll(keepingCapacity: false) }
    return true
  }

  /// Leaves, once, the marker that a replacement has completed, behind a write barrier on the
  /// directory: the rename it follows reaches the disk first, also on power loss, so the
  /// marker never outlives a replacement that is not on disk.
  private func markReplacement(_ state: inout State, in parent: Int32) throws {
    guard guardsReplacement, !state.replacementMarked else { return }
    guard calls.control(parent, F_BARRIERFSYNC) == 0 || calls.control(parent, F_FULLFSYNC) == 0
    else { throw DeviceLayerError.io("device journal directory sync") }
    let descriptor = openat(
      parent, Self.replacementMarker(filename), O_WRONLY | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
      0o600)
    guard descriptor >= 0 else { throw DeviceLayerError.io("device journal replacement marker") }
    _ = Darwin.close(descriptor)
    guard calls.synchronize(parent) == 0 else {
      throw DeviceLayerError.io("device journal directory sync")
    }
    state.replacementMarked = true
  }

  /// Whether the file exists (it was opened, or created by a replacement), and not removed.
  var exists: Bool { state.withLock { $0.handle != nil } }

  /// Deletes the file durably (unlinked, directory synchronized) and keeps the lock, behind a
  /// write barrier: everything written before (another file's rename) is on disk first. Later
  /// appends fail; a later ``replace(_:)`` creates the file again. A guarded journal's
  /// replacement marker goes first, so a missing file is never taken for a lost replacement.
  func remove() throws {
    try state.withLock { state in
      guard let directory = state.directoryHandle, !state.failed else {
        throw DeviceLayerError.io("device journal unavailable")
      }
      do {
        // What was renamed in this directory before (the state that no longer names this
        // file) reaches the disk before the unlink, also on power loss.
        let parent = directory.fileDescriptor
        guard
          calls.control(parent, F_BARRIERFSYNC) == 0 || calls.control(parent, F_FULLFSYNC) == 0
        else { throw DeviceLayerError.io("device journal directory sync") }
        if state.replacementMarked {
          guard unlinkat(parent, Self.replacementMarker(filename), 0) == 0 || errno == ENOENT
          else { throw DeviceLayerError.io("device journal replacement marker") }
          state.replacementMarked = false
        }
        if unlinkat(parent, filename, 0) != 0, errno != ENOENT {
          throw DeviceLayerError.io("device journal removal")
        }
        guard calls.synchronize(parent) == 0 else {
          throw DeviceLayerError.io("device journal directory sync")
        }
        try? state.handle?.close()
        state.handle = nil
        state.sequence = 0
        state.digest = Data(repeating: 0, count: 32)
      } catch {
        state.failed = true
        throw error
      }
    }
  }

  /// Synchronizes behind a write barrier: what was written before this call reaches the disk
  /// before anything written after it, also on power loss, which plain `fsync` does not
  /// promise (`man 2 fsync`). Where the file system has no barriers, `F_FULLFSYNC` flushes
  /// the drive, which orders as well; plain `fsync` is the last resort.
  private func synchronizeInOrder(_ descriptor: Int32) throws {
    if calls.control(descriptor, F_BARRIERFSYNC) == 0 { return }
    if calls.control(descriptor, F_FULLFSYNC) == 0 { return }
    guard calls.synchronize(descriptor) == 0 else {
      throw DeviceLayerError.io("device journal synchronization")
    }
  }

  private func encodedRecord(
    _ plaintext: Data, sequence: UInt64, previous: Data
  ) throws -> (bytes: Data, digest: Data) {
    let payload: Data
    if let key {
      let box = try AES.GCM.seal(
        plaintext, using: key,
        authenticating: Self.authentication(
          purpose: purpose, sequence: sequence, previous: previous))
      guard let combined = box.combined else {
        throw DeviceLayerError.invalid("local device encryption")
      }
      payload = combined
    } else {
      payload = plaintext
    }
    let digest = Self.digest(payload, sequence: sequence, previous: previous)
    let entry = Entry(
      version: 1, sequence: sequence, previous: previous, payload: payload, digest: digest)
    var bytes = try JSONEncoder().encode(entry)
    guard bytes.count <= Self.maximumRecordBytes else {
      throw DeviceLayerError.frameTooLarge(bytes.count)
    }
    bytes.append(0x0A)
    return (bytes, digest)
  }

  /// Releases file and ownership-lock handles and clears the recovered-row buffer.
  /// Idempotent; does not unlink persisted records or erase their filesystem history.
  public func close() {
    state.withLock { state in
      try? state.handle?.close()
      state.handle = nil
      try? state.lockHandle?.close()
      state.lockHandle = nil
      try? state.directoryHandle?.close()
      state.directoryHandle = nil
    }
    recoveredRows.withLock { $0.removeAll(keepingCapacity: false) }
  }

  private static func authentication(purpose: Data, sequence: UInt64, previous: Data) -> Data {
    var bytes = purpose
    withUnsafeBytes(of: sequence.bigEndian) { bytes.append(contentsOf: $0) }
    bytes.append(previous)
    return bytes
  }

  private static func digest(_ payload: Data, sequence: UInt64, previous: Data) -> Data {
    Data(
      SHA256.hash(
        data: authentication(purpose: Data(), sequence: sequence, previous: previous) + payload))
  }
}
