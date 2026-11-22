import CryptoKit
import Darwin
import Foundation

/// Verified private directories. A client never repairs permissions or creates files.
public struct IPCPaths: Sendable {
  /// The verified Unix endpoint, including the short-path fallback when necessary.
  public let socketURL: URL
  /// The private token path in the data root's run directory.
  public let tokenURL: URL
  private let rootURL: URL

  /// Resolves verified paths; only a server explicitly requesting creation may make directories.
  public init(directory: URL, createDirectories: Bool = false) throws {
    try self.init(
      directory: directory, createDirectories: createDirectories,
      temporaryDirectory: Self.userTemporaryDirectory)
  }

  /// The temporary folder is a parameter only so that tests can present an unsafe one.
  internal init(
    directory: URL, createDirectories: Bool, temporaryDirectory: () throws -> URL
  ) throws {
    guard directory.isFileURL, !directory.path.utf8.contains(0), directory.lastPathComponent != "/"
    else {
      throw IPCError.unsafePath(directory.path)
    }
    // Canonicalize ancestors, not the protected final component. In particular,
    // /tmp's standard system symlink is allowed; a symlink named Memoshi is not.
    let root = directory.deletingLastPathComponent().resolvingSymlinksInPath()
      .appendingPathComponent(directory.lastPathComponent, isDirectory: true)
    rootURL = root
    let rootFD = try PrivateFileSystem.openDirectory(root, create: createDirectories)
    defer { Darwin.close(rootFD) }
    let run = root.appendingPathComponent("run", isDirectory: true)
    let runFD = try PrivateFileSystem.openChildDirectory(
      "run", at: rootFD, displayPath: run.path, create: createDirectories)
    defer { Darwin.close(runFD) }
    tokenURL = run.appendingPathComponent("memoshid.token")
    let preferred = run.appendingPathComponent("memoshid.sock")
    if preferred.path.utf8.count <= 100 {
      socketURL = preferred
    } else {
      // A long data root falls back to the user's private temporary folder, where no other
      // account can create an entry (D130). Neither side creates or repairs that folder. The
      // socket name carries a digest of the canonical root, so two data roots never share one
      // endpoint.
      let fallback = try temporaryDirectory()
      let fallbackFD = try PrivateFileSystem.openDirectory(fallback)
      Darwin.close(fallbackFD)
      socketURL = fallback.appendingPathComponent("memoshid-\(Self.rootDigest(root)).sock")
      guard socketURL.path.utf8.count <= Self.socketPathLimit else {
        throw IPCError.systemCall(operation: "resolve socket path", code: ENAMETOOLONG)
      }
    }
    try PrivateFileSystem.validateExisting(socketURL, kind: S_IFSOCK, mode: 0o600)
    try PrivateFileSystem.validateExisting(tokenURL, kind: S_IFREG, mode: 0o600)
  }

  /// The first 16 hexadecimal digits of the SHA-256 of the canonical data root's path.
  static func rootDigest(_ root: URL) -> String {
    SHA256.hash(data: Data(root.path.utf8)).prefix(8)
      .map { String(format: "%02x", $0) }.joined()
  }

  /// `sun_path` holds 104 bytes including its terminator.
  static let socketPathLimit = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

  /// The folder the system keeps for this user alone, with its symlinked ancestors resolved.
  /// App and helper run as the same unsandboxed user, so both resolve the same folder.
  static func userTemporaryDirectory() throws -> URL {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    errno = 0
    let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
    guard length > 1, length <= buffer.count else {
      throw IPCError.systemCall(
        operation: "resolve user temporary directory",
        code: length == 0 && errno != 0 ? errno : ENOENT)
    }
    let path = String(
      decoding: buffer.prefix(length - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    return URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
  }

  internal func validateSocket() throws {
    try validateDirectories()
    let parent = try PrivateFileSystem.openDirectory(socketURL.deletingLastPathComponent())
    defer { Darwin.close(parent) }
    try PrivateFileSystem.validateExisting(socketURL, kind: S_IFSOCK, mode: 0o600, required: true)
  }

  internal func validateDirectories() throws {
    let root = try PrivateFileSystem.openDirectory(rootURL)
    defer { Darwin.close(root) }
    let run = try PrivateFileSystem.openChildDirectory(
      "run", at: root, displayPath: tokenURL.deletingLastPathComponent().path, create: false)
    defer { Darwin.close(run) }
    if socketURL.deletingLastPathComponent() != tokenURL.deletingLastPathComponent() {
      let fallback = try PrivateFileSystem.openDirectory(socketURL.deletingLastPathComponent())
      Darwin.close(fallback)
    }
  }
}

internal enum PrivateFileSystem {
  static func failure(_ operation: String) -> IPCError {
    .systemCall(operation: operation, code: errno)
  }

  static func openDirectory(_ url: URL, create: Bool = false) throws -> CInt {
    guard url.isFileURL, !url.path.utf8.contains(0) else { throw IPCError.unsafePath(url.path) }
    let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
    let parentFD = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard parentFD >= 0 else { throw failure("open directory parent") }
    defer { Darwin.close(parentFD) }
    return try openChildDirectory(
      url.lastPathComponent, at: parentFD, displayPath: url.path, create: create)
  }

  static func openChildDirectory(
    _ name: String, at parent: CInt, displayPath: String, create: Bool
  ) throws -> CInt {
    if create && mkdirat(parent, name, 0o700) != 0 && errno != EEXIST {
      throw failure("mkdir private directory")
    }
    let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    guard fd >= 0 else {
      if errno == ELOOP || errno == ENOTDIR { throw IPCError.unsafePath(displayPath) }
      throw failure("open private directory")
    }
    do {
      try validate(fd, path: displayPath, kind: S_IFDIR, mode: 0o700)
      return fd
    } catch {
      Darwin.close(fd)
      throw error
    }
  }

  static func validate(_ fd: CInt, path: String, kind: mode_t, mode: mode_t) throws {
    var info = stat()
    guard fstat(fd, &info) == 0 else { throw failure("fstat private file") }
    guard info.st_uid == geteuid(), info.st_mode & S_IFMT == kind,
      info.st_mode & 0o7777 == mode,
      kind == S_IFDIR || info.st_nlink == 1
    else { throw IPCError.unsafePath(path) }
  }

  static func validateExisting(
    _ url: URL, kind: mode_t, mode: mode_t, required: Bool = false
  ) throws {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
      if errno == ENOENT && !required { return }
      throw failure("lstat private file")
    }
    guard info.st_uid == geteuid(), info.st_mode & S_IFMT == kind,
      info.st_mode & 0o7777 == mode, info.st_nlink == 1
    else { throw IPCError.unsafePath(url.path) }
  }

  static func sameNode(_ first: stat, _ second: stat) -> Bool {
    first.st_dev == second.st_dev && first.st_ino == second.st_ino
  }
}
