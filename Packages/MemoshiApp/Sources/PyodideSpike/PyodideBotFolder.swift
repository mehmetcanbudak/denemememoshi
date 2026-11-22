import CryptoKit
import Darwin
import Foundation

/// An app-created, existing private bot directory, anchored by descriptor for this host's lifetime.
/// No bookmark, user-selected folder or native path is ever passed into the JavaScript runtime.
/// Linked folders need the owning app's separate grant/admission boundary before this API is used.
public final class PyodideBotFolder: Sendable {
  private let root: PyodideDirectory

  /// Anchors an existing, current-user-owned directory with no group/other POSIX permission bits.
  /// Refuses root, traversal and symlinks in any component; unsafe or inaccessible directories throw.
  /// The caller supplies the canonical absolute file URL and prior admission; this creates no grant.
  public init(ownedDirectory: URL) throws {
    guard ownedDirectory.isFileURL, ownedDirectory.path != "/" else {
      throw PyodideFailure.unsafePath
    }
    let path = ownedDirectory.path
    let parts = path.split(separator: "/", omittingEmptySubsequences: true)
    guard path.hasPrefix("/"), !parts.contains("."), !parts.contains("..") else {
      throw PyodideFailure.unsafePath
    }
    var current = try PyodideDirectory(openingRoot: "/")
    for part in parts {
      current = try current.child(String(part), create: false, requireOwner: false)
    }
    var info = try current.metadata()
    guard info.st_uid == geteuid(), info.st_mode & mode_t(0o077) == 0 else {
      throw PyodideFailure.unsafePath
    }
    // Resolve no symlinks, including ancestors. A caller using /var's system alias must provide
    // its already-verified /private/var spelling instead of widening this boundary.
    guard fstat(current.descriptor, &info) == 0 else { throw PyodideFailure.fileUnavailable }
    root = current
  }

  /// Stage caller-supplied bytes without granting JavaScript a native filesystem capability.
  /// Existing inputs are never overwritten; the app remains responsible for source authorization.
  public func stageInput(path: String, bytes: Data) throws {
    guard bytes.count <= PyodideLimits.fileBytes else { throw PyodideFailure.outputLimit }
    let parts = try PyodidePath.components(path)
    let parent = try directory(parts.dropLast(), create: true)
    guard let name = parts.last else { throw PyodideFailure.unsafePath }
    let descriptor = openat(
      parent.descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw PyodideFailure.outputConflict }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do {
      try file.write(contentsOf: bytes)
      try file.synchronize()
    } catch {
      _ = unlinkat(parent.descriptor, name, 0)
      throw PyodideFailure.fileUnavailable
    }
  }

  func readInputs(_ paths: [String]) throws -> [PyodideInput] {
    var total = 0
    return try paths.map { path in
      let parts = try PyodidePath.components(path)
      let parent = try directory(parts.dropLast(), create: false)
      guard let name = parts.last else { throw PyodideFailure.unsafePath }
      let descriptor = openat(
        parent.descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
      guard descriptor >= 0 else { throw PyodideFailure.unsafePath }
      let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      var before = stat()
      guard fstat(descriptor, &before) == 0, Self.regular(before),
        before.st_size >= 0, before.st_size <= PyodideLimits.fileBytes
      else { throw PyodideFailure.unsafePath }
      var data = Data()
      while let chunk = try file.read(upToCount: 64 * 1_024), !chunk.isEmpty {
        guard data.count + chunk.count <= PyodideLimits.fileBytes else {
          throw PyodideFailure.outputLimit
        }
        data.append(chunk)
      }
      var after = stat()
      guard fstat(descriptor, &after) == 0, Self.regular(after),
        before.st_dev == after.st_dev, before.st_ino == after.st_ino,
        before.st_size == after.st_size, data.count == after.st_size,
        before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
        before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
        before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
        before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec
      else { throw PyodideFailure.fileChanged }
      total += data.count
      guard total <= PyodideLimits.totalFileBytes else { throw PyodideFailure.outputLimit }
      return PyodideInput(path: path, bytes: data)
    }
  }

  /// Whether `pyodide-results` exists in this folder. Compared before and after a failed run,
  /// it tells the caller whether that run created the directory. Any answer other than "no
  /// such entry" counts as present.
  public var hasResultsDirectory: Bool { entryExists("pyodide-results") }

  /// Whether a run directory for `requestID` exists, even an empty one that a part-way failed
  /// export left behind (it removes only the files it created). A `pyodide-results` entry that
  /// is not a real directory counts as present.
  public func hasResultDirectory(for requestID: UUID) -> Bool {
    var info = stat()
    guard fstatat(root.descriptor, "pyodide-results", &info, AT_SYMLINK_NOFOLLOW) == 0 else {
      return errno != ENOENT
    }
    guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { return true }
    return entryExists("pyodide-results/" + requestID.uuidString.lowercased())
  }

  private func entryExists(_ path: String) -> Bool {
    var info = stat()
    return fstatat(root.descriptor, path, &info, AT_SYMLINK_NOFOLLOW) == 0 || errno != ENOENT
  }

  /// A fresh run directory is a write-once result. Existing files are never replaced, and a
  /// failed export removes only files created by this invocation via retained parent descriptors.
  func export(_ outputs: [PyodideOutput], requestID: UUID) throws -> [PyodideArtifact] {
    guard outputs.count <= PyodideLimits.files,
      Set(outputs.map(\.path)).count == outputs.count,
      outputs.reduce(0, { $0 + $1.bytes.count }) <= PyodideLimits.totalFileBytes
    else { throw PyodideFailure.outputLimit }
    for output in outputs {
      _ = try PyodidePath.components(output.path)
      guard output.bytes.count <= PyodideLimits.fileBytes else { throw PyodideFailure.outputLimit }
    }
    guard !outputs.isEmpty else { return [] }
    let results = try root.child("pyodide-results", create: true)
    let name = requestID.uuidString.lowercased()
    guard mkdirat(results.descriptor, name, 0o700) == 0 else {
      throw PyodideFailure.outputConflict
    }
    let run = try results.child(name, create: false)
    var created: [(PyodideDirectory, String)] = []
    var finished = false
    defer {
      if !finished {
        for (parent, filename) in created.reversed() {
          _ = unlinkat(parent.descriptor, filename, 0)
        }
      }
    }
    var artifacts: [PyodideArtifact] = []
    for output in outputs {
      let parts = try PyodidePath.components(output.path)
      var parent = run
      for component in parts.dropLast() { parent = try parent.child(component, create: true) }
      guard let filename = parts.last else { throw PyodideFailure.unsafePath }
      let descriptor = openat(
        parent.descriptor, filename, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard descriptor >= 0 else { throw PyodideFailure.outputConflict }
      created.append((parent, filename))
      let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      try file.write(contentsOf: output.bytes)
      try file.synchronize()
      artifacts.append(
        PyodideArtifact(
          path: "pyodide-results/\(name)/\(output.path)", bytes: output.bytes.count,
          sha256: SHA256.hash(data: output.bytes).map { String(format: "%02x", $0) }.joined()))
    }
    finished = true
    return artifacts
  }

  private func directory(_ parts: ArraySlice<String>, create: Bool) throws -> PyodideDirectory {
    var current = root
    for component in parts { current = try current.child(component, create: create) }
    return current
  }

  private static func regular(_ info: stat) -> Bool {
    info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
      && info.st_nlink == 1 && info.st_uid == geteuid()
      && info.st_mode & mode_t(0o7000) == 0
  }
}

struct PyodideInput: Sendable, Codable {
  let path: String
  let bytes: Data
}

struct PyodideOutput: Sendable, Codable {
  let path: String
  let bytes: Data
}

private final class PyodideDirectory: Sendable {
  let descriptor: Int32

  init(openingRoot path: String) throws {
    descriptor = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw PyodideFailure.unsafePath }
  }

  private init(descriptor: Int32) { self.descriptor = descriptor }

  deinit { Darwin.close(descriptor) }

  func metadata() throws -> stat {
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { throw PyodideFailure.fileUnavailable }
    return info
  }

  func child(_ name: String, create: Bool, requireOwner: Bool = true) throws -> PyodideDirectory {
    let parts = try PyodidePath.components(name)
    guard parts.count == 1 else { throw PyodideFailure.unsafePath }
    if create, mkdirat(descriptor, name, 0o700) != 0, errno != EEXIST {
      throw PyodideFailure.fileUnavailable
    }
    let next = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard next >= 0 else { throw PyodideFailure.unsafePath }
    let child = PyodideDirectory(descriptor: next)
    let info = try child.metadata()
    guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
      !requireOwner || (info.st_uid == geteuid() && info.st_mode & mode_t(0o077) == 0)
    else { throw PyodideFailure.unsafePath }
    return child
  }
}
