import CoreTransferable
import CryptoKit
import Darwin
import Foundation
import PyodideSpike
import UniformTypeIdentifiers

/// A fresh app-owned directory for one explicit session. Never adopts, chmods, replaces or
/// deletes an existing directory; a start that fails removes only the empty directory it just
/// created. The Python host receives no user-folder capability.
final class PyodideReviewEvidence: Sendable {
  let directory: URL
  let folder: PyodideBotFolder
  private let descriptor: Int32
  private static let maximumFileBytes = 64 * 1_024 * 1_024

  init() throws {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    // PyodideBotFolder walks from `/` without following symlinks, so it needs the physical
    // spelling. Foundation's own resolution returns Darwin's `/var` alias for `/private/var`,
    // which is where an iPhone or iPad keeps this container.
    guard let physical = realpath(support.path, nil) else { throw PyodideFailure.fileUnavailable }
    defer { free(physical) }
    let directory = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
      .appendingPathComponent(
        "Memoshi-Pyodide-Review-\(UUID().uuidString.lowercased())", isDirectory: true)
    guard mkdir(directory.path, 0o700) == 0 else { throw PyodideFailure.fileUnavailable }
    do {
      let folder = try PyodideBotFolder(ownedDirectory: directory)
      let descriptor = Darwin.open(
        directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard descriptor >= 0 else { throw PyodideFailure.unsafePath }
      var info = stat()
      guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(),
        info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
        info.st_mode & mode_t(0o7777) == mode_t(0o700)
      else {
        Darwin.close(descriptor)
        throw PyodideFailure.unsafePath
      }
      self.directory = directory
      self.folder = folder
      self.descriptor = descriptor
    } catch {
      // Nothing was staged yet: rmdir removes this call's own directory only while it is empty.
      rmdir(directory.path)
      throw error
    }
  }

  deinit { Darwin.close(descriptor) }

  func saveJSON<T: Encodable>(
    _ value: T, category: String, name: String
  ) throws -> PyodideReviewFile {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try save(encoder.encode(value), category: category, name: name, extension: "json")
  }

  func save(
    _ data: Data, category: String, name: String, extension suffix: String
  ) throws -> PyodideReviewFile {
    let path = "native-evidence/\(category)/\(UUID().uuidString.lowercased())-\(name).\(suffix)"
    try folder.stageInput(path: path, bytes: data)
    return try file(path: path)
  }

  func file(path: String, expectedSHA256: String? = nil) throws -> PyodideReviewFile {
    let bytes = try read(path: path)
    let digest = Self.digest(bytes)
    if let expectedSHA256, digest != expectedSHA256 { throw PyodideFailure.fileChanged }
    return PyodideReviewFile(path: path, bytes: bytes.count, sha256: digest, evidence: self)
  }

  /// Transfers re-read through the retained descriptor and check the original digest. An edit
  /// is refused, not exported under the hash of old evidence. No arbitrary URL is read here.
  func read(path: String, expectedSHA256: String? = nil) throws -> Data {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !parts.isEmpty, parts.count <= 32, path.utf8.count <= 1_024,
      parts.allSatisfy({
        !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") && !$0.contains("\\")
          && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      })
    else { throw PyodideFailure.unsafePath }
    var parent = dup(descriptor)
    guard parent >= 0 else { throw PyodideFailure.fileUnavailable }
    defer { Darwin.close(parent) }
    for part in parts.dropLast() {
      let next = openat(parent, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard next >= 0 else { throw PyodideFailure.unsafePath }
      Darwin.close(parent)
      parent = next
    }
    guard let name = parts.last else { throw PyodideFailure.unsafePath }
    let descriptor = openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw PyodideFailure.fileUnavailable }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var before = stat()
    guard fstat(descriptor, &before) == 0,
      before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
      before.st_uid == geteuid(), before.st_nlink == 1,
      before.st_mode & mode_t(0o7777) == mode_t(0o600),
      before.st_size >= 0, before.st_size <= Self.maximumFileBytes
    else { throw PyodideFailure.unsafePath }
    var data = Data()
    while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
      guard data.count + chunk.count <= Self.maximumFileBytes else {
        throw PyodideFailure.outputLimit
      }
      data.append(chunk)
    }
    var after = stat()
    guard fstat(descriptor, &after) == 0, before.st_dev == after.st_dev,
      before.st_ino == after.st_ino, before.st_size == after.st_size,
      data.count == after.st_size,
      before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
      before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
      before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
      before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec
    else { throw PyodideFailure.fileChanged }
    if let expectedSHA256, Self.digest(data) != expectedSHA256 {
      throw PyodideFailure.fileChanged
    }
    return data
  }

  private static func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

struct PyodideReviewFile: Identifiable, Sendable, Transferable {
  let path: String
  let bytes: Int
  let sha256: String
  let evidence: PyodideReviewEvidence

  var id: String { path }
  var name: String { URL(fileURLWithPath: path).lastPathComponent }
  var contentType: UTType {
    UTType(filenameExtension: URL(fileURLWithPath: name).pathExtension) ?? .data
  }

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .json) { file in try file.read() }
      .exportingCondition { $0.contentType == .json }
      .suggestedFileName { $0.name }
    DataRepresentation(exportedContentType: .png) { file in try file.read() }
      .exportingCondition { $0.contentType == .png }
      .suggestedFileName { $0.name }
    DataRepresentation(exportedContentType: .commaSeparatedText) { file in try file.read() }
      .exportingCondition { $0.contentType == .commaSeparatedText }
      .suggestedFileName { $0.name }
    DataRepresentation(exportedContentType: .data) { file in try file.read() }
      .suggestedFileName { $0.name }
  }

  private func read() throws -> Data {
    try evidence.read(path: path, expectedSHA256: sha256)
  }
}

struct PyodideReviewEvent: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let at: Date
  let event: String
  let operationID: UUID?
  let detail: String?

  init(_ event: String, operationID: UUID? = nil, detail: String? = nil) {
    id = UUID()
    at = Date()
    self.event = event
    self.operationID = operationID
    self.detail = detail
  }
}

struct PyodideReviewSnapshot: Encodable, Sendable {
  struct File: Encodable, Sendable {
    let path: String
    let bytes: Int
    let sha256: String
  }

  let schema = 1
  let purpose = "explicit-native-S6-development-measurement-not-a-gate-verdict"
  let sessionID: UUID
  let createdAt: Date
  let capturedAt: Date
  let appVersion: String
  let appBuild: String
  let hostState: String
  let startup: PyodideStartup?
  let measurements: PyodideMeasurementReport
  let nativeEvents: [PyodideReviewEvent]
  let omittedNativeEvents: Int
  let files: [File]
  let omittedFileEntries: Int
  let limitations: [String]
}
