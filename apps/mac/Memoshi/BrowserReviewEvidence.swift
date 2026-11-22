import AppCore
import Darwin
import Foundation
import MemoshiEgress

/// Only typed, content-free review facts are durable. Recipes, page text, credentials and proxy
/// authentication never enter this file. The previous persistent-profile evidence stays intact.
@MainActor
@Observable
final class BrowserReviewEvidence {
  struct Decision: Codable, Sendable, Identifiable {
    enum Operation: String, Codable, Sendable {
      case configuration, click, form, navigation, upload, signIn
    }
    let id: UUID
    let at: Date
    let profileID: UUID
    let operation: Operation
    let allowed: Bool
    let code: String
  }

  struct Download: Codable, Sendable, Identifiable {
    enum State: String, Codable, Sendable { case authorized, completed, refused, failed, cancelled }
    let id: UUID
    let profileID: UUID
    let at: Date
    let state: State
    let bytes: Int64?
    let quarantined: Bool
    let code: String?
  }

  struct Contents: Codable, Sendable {
    var schema = "memoshi.s3-browser-evidence/1"
    var decisions: [Decision] = []
    var downloads: [Download] = []
    var gateway: [EgressDecision] = []
    var runs: [BrowserTaskRun] = []
    var actions: [BrowserActionOutcome] = []
  }

  private(set) var contents = Contents()
  private(set) var storageProblem = false
  let directory: URL
  private let file: URL

  init() {
    directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Memoshi Development/Browser Review", isDirectory: true)
    file = directory.appendingPathComponent("evidence.json")
    let descriptor = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else {
      storageProblem = errno != ENOENT
      return
    }
    defer { _ = Darwin.close(descriptor) }
    var status = stat()
    guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == getuid(), status.st_mode & 0o077 == 0, status.st_size <= 10_000_000
    else {
      storageProblem = true
      return
    }
    do {
      let data =
        try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).read(
          upToCount: 10_000_001) ?? Data()
      guard data.count <= 10_000_000 else {
        storageProblem = true
        return
      }
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      contents = try decoder.decode(Contents.self, from: data)
      guard contents.schema == "memoshi.s3-browser-evidence/1" else {
        storageProblem = true
        return
      }
      var interrupted = false
      for index in contents.runs.indices where contents.runs[index].state == .running {
        contents.runs[index].interruptIfRunning()
        interrupted = true
      }
      for index in contents.downloads.indices where contents.downloads[index].state == .authorized {
        let download = contents.downloads[index]
        contents.downloads[index] = Download(
          id: download.id, profileID: download.profileID,
          at: Date(), state: .failed, bytes: nil, quarantined: false,
          code: "interruptedOutcomeUnknown")
        interrupted = true
      }
      if interrupted { persist() }
    } catch { storageProblem = true }
  }

  func record(profileID: UUID, operation: Decision.Operation, allowed: Bool, code: String) {
    contents.decisions.append(
      Decision(
        id: UUID(), at: Date(), profileID: profileID,
        operation: operation, allowed: allowed, code: code))
    if contents.decisions.count > 1_000 { contents.decisions.removeFirst() }
    persist()
  }

  func record(_ download: Download) {
    if let index = contents.downloads.firstIndex(where: { $0.id == download.id }) {
      contents.downloads[index] = download
    } else {
      contents.downloads.append(download)
    }
    if contents.downloads.count > 200 { contents.downloads.removeFirst() }
    persist()
  }

  func record(_ action: BrowserActionOutcome) {
    contents.actions.append(action)
    if contents.actions.count > 200 { contents.actions.removeFirst() }
    persist()
  }

  func record(gateway decisions: [EgressDecision]) {
    guard !decisions.isEmpty else { return }
    contents.gateway.append(contentsOf: decisions)
    if contents.gateway.count > 2_000 {
      contents.gateway.removeFirst(contents.gateway.count - 2_000)
    }
    persist()
  }

  func record(_ run: BrowserTaskRun) {
    if let index = contents.runs.firstIndex(where: { $0.id == run.id }) {
      contents.runs[index] = run
    } else {
      contents.runs.append(run)
    }
    if contents.runs.count > 20 { contents.runs.removeFirst() }
    persist()
  }

  private func persist() {
    guard !storageProblem else { return }
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(contents)
      // A fresh private temporary file avoids the default 0644 window of Data.write(.atomic).
      let temporary = directory.appendingPathComponent(UUID().uuidString)
      let fd = Darwin.open(
        temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
      defer { _ = Darwin.close(fd) }
      do {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        guard Darwin.rename(temporary.path, file.path) == 0 else {
          throw CocoaError(.fileWriteUnknown)
        }
      } catch {
        _ = Darwin.unlink(temporary.path)
        throw error
      }
    } catch { storageProblem = true }
  }
}
