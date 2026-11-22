import CryptoKit
import Darwin
import Foundation
import MemoshiDevice

/// A single-owner `DeviceStateJournal` whose whole history can be replaced by one snapshot.
/// The snapshot replaces the history in one atomic step (`DeviceStateJournal.replaceHistory`):
/// its rows are on disk, behind a write barrier, before they are renamed over the journal, so
/// a kill or a power loss leaves either the complete old history or the complete snapshot,
/// never a mixture. A journal that has had a snapshot and opens without one (a power loss the
/// file system did not order) refuses to open instead of opening empty. A journal written
/// before this type existed has no snapshot and is read as entries only.
struct DeviceCompactingJournal {
  private struct Chunk: Codable {
    let index: Int
    let count: Int
    let bytes: Data
  }
  private struct ChunkRow: Codable { let snapshotChunk: Chunk }

  private let journal: DeviceStateJournal
  private let url: URL
  private var entriesSinceSnapshot: Int
  private var recovered: (snapshot: Data?, entries: [Data])
  private let compactionBytes: UInt64
  private let ceilingBytes: UInt64
  /// The file's size after the last snapshot, or when it was opened.
  private var baselineBytes: UInt64

  /// One journal record is limited to 32 MiB; a snapshot is split well below that.
  private static let chunkBytes = 4 * 1024 * 1024
  /// A rewrite is due after this many appended entries.
  private static let compactionEntries = 4_096
  private static let chunkPrefix = Data(#"{"snapshotChunk""#.utf8)

  /// A rewrite is also due once the file has grown by `compactionBytes` since its last
  /// snapshot, so that a large retained state is not rewritten for every few entries, and at
  /// every size check once the file has reached `ceilingBytes`, which keeps it below the
  /// 512 MiB that a journal may have when it is opened.
  init(
    url: URL, key: SymmetricKey, purpose: String, compactionBytes: UInt64 = 64 * 1024 * 1024,
    ceilingBytes: UInt64 = 384 * 1024 * 1024
  ) throws {
    try self.init(
      journal: DeviceStateJournal(url: url, key: key, purpose: purpose, guardsReplacement: true),
      url: url, compactionBytes: compactionBytes, ceilingBytes: ceilingBytes)
  }

  /// Opens the journal at `url` without reading what it holds, for an erasure that replaces
  /// it by one snapshot (``compact(_:)``) next and must work also when that history can no
  /// longer be read.
  static func discardingHistory(url: URL, key: SymmetricKey, purpose: String) throws
    -> DeviceCompactingJournal
  {
    try DeviceCompactingJournal(
      journal: DeviceStateJournal(
        url: url, key: key, purpose: purpose, guardsReplacement: true, discardingHistory: true),
      url: url)
  }

  /// `journal` is the one opened on `url`, guarding its replacements; tests pass one whose
  /// system calls they observe.
  init(
    journal: DeviceStateJournal, url: URL, compactionBytes: UInt64 = 64 * 1024 * 1024,
    ceilingBytes: UInt64 = 384 * 1024 * 1024
  ) throws {
    self.journal = journal
    self.url = url
    self.compactionBytes = compactionBytes
    self.ceilingBytes = ceilingBytes
    baselineBytes = Self.size(of: url)
    // A rewrite by an earlier version that a kill interrupted before its rename left only
    // this file; the journal itself is still the complete old history.
    let unfinished = url.path + ".compact"
    _ = unlink(unfinished)
    _ = unlink(unfinished + ".lock")
    var parts: [Data] = []
    var entries: [Data] = []
    var expected: Int?
    for row in journal.takeRecovered() {
      guard row.starts(with: Self.chunkPrefix) else {
        guard expected == nil || parts.count == expected else {
          throw AppleDeviceError.invalidState("journal snapshot")
        }
        entries.append(row)
        continue
      }
      let chunk = try JSONDecoder().decode(ChunkRow.self, from: row).snapshotChunk
      guard entries.isEmpty, chunk.count > 0, chunk.index == parts.count,
        chunk.count == expected ?? chunk.count, chunk.index < chunk.count
      else { throw AppleDeviceError.invalidState("journal snapshot") }
      expected = chunk.count
      parts.append(chunk.bytes)
    }
    guard expected == nil || parts.count == expected else {
      throw AppleDeviceError.invalidState("journal snapshot")
    }
    recovered = (expected == nil ? nil : parts.reduce(into: Data()) { $0.append($1) }, entries)
    entriesSinceSnapshot = entries.count
  }

  /// Transfers what was read at open: the snapshot, if the journal starts with one, and the
  /// entries appended after it, in order. Later calls return nothing.
  mutating func takeRecovered() -> (snapshot: Data?, entries: [Data]) {
    defer { recovered = (nil, []) }
    return recovered
  }

  /// Appends one entry and synchronizes it before returning.
  mutating func append<T: Encodable>(_ value: T) throws {
    try journal.append(value)
    entriesSinceSnapshot += 1
  }

  /// Whether enough history has accumulated since the last snapshot to rewrite the journal.
  var needsCompaction: Bool {
    if entriesSinceSnapshot >= Self.compactionEntries { return true }
    guard entriesSinceSnapshot > 0, entriesSinceSnapshot.isMultiple(of: 64) else { return false }
    let size = Self.size(of: url)
    return size >= ceilingBytes || size - min(size, baselineBytes) >= compactionBytes
  }

  private static func size(of url: URL) -> UInt64 {
    var info = stat()
    return stat(url.path, &info) == 0 ? UInt64(max(0, info.st_size)) : 0
  }

  /// Replaces the journal's history by `snapshot`. Returns `false` when nothing was changed
  /// because the new file could not be written, synchronized or renamed: the old history is
  /// then still complete and in use. A throw means the replacement happened but could not be
  /// made durable, and the owner must fail closed.
  mutating func compact(_ snapshot: Data) throws -> Bool {
    let count = max(1, (snapshot.count + Self.chunkBytes - 1) / Self.chunkBytes)
    let rows = (0..<count).map { index in
      let start = snapshot.startIndex + index * Self.chunkBytes
      let end = min(snapshot.endIndex, start + Self.chunkBytes)
      return ChunkRow(
        snapshotChunk: Chunk(index: index, count: count, bytes: snapshot[start..<end]))
    }
    guard try journal.replaceHistory(with: rows) else { return false }
    entriesSinceSnapshot = 0
    baselineBytes = Self.size(of: url)
    return true
  }

  func close() { journal.close() }
}
