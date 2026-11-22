import Darwin
import Foundation
import MemoshiProtocol
import Synchronization

/// The process keeps this value alive for its entire daemon lifetime. The lock file is never
/// unlinked: unlinking a held flock would let another process lock a different inode.
public final class DaemonLock: Sendable {
  private let lock: FileLock

  private init(lock: FileLock) { self.lock = lock }

  /// Acquires the process-lifetime singleton lock or throws `alreadyRunning`.
  public static func acquire(in directory: URL) throws -> DaemonLock {
    try StorePaths.prepare(directory)
    try StorePaths.privateDirectory(directory.appendingPathComponent("run", isDirectory: true))
    let url = directory.appendingPathComponent("run/memoshid.lock")
    return try DaemonLock(lock: FileLock.acquire(url, conflict: .alreadyRunning))
  }

  /// Releases the singleton lock without unlinking its inode.
  public func release() { lock.release() }
}

/// Owns a local per-conversation lock and reserves the path that Pi_Swift will open. This does
/// not create a Pi database or enforce Pi's still-separate engine-level fencing contract.
/// Recheck the fence with Store before each app-store commit and runtime write admission.
public final class ConversationOwnership: Sendable {
  /// The local epoch to revalidate at each runtime or application-store write.
  public let fence: ConversationFence
  /// The reserved per-conversation path for the real Pi runtime.
  public let fileURL: URL
  private let lock: FileLock

  init(fence: ConversationFence, fileURL: URL, lock: FileLock) {
    self.fence = fence
    self.fileURL = fileURL
    self.lock = lock
  }

  /// Releases this file's exclusive local ownership.
  public func release() { lock.release() }
}

final class FileLock: Sendable {
  private let descriptor: Mutex<Int32?>

  private init(descriptor: Int32) { self.descriptor = Mutex(descriptor) }

  deinit { release() }

  static func acquire(_ url: URL, conflict: StoreError) throws -> FileLock {
    try acquire(
      descriptor: Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600),
      path: url.path, conflict: conflict)
  }

  static func acquire(_ name: String, in directory: Int32, conflict: StoreError) throws -> FileLock
  {
    try acquire(
      descriptor: openat(directory, name, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600),
      path: name, conflict: conflict)
  }

  private static func acquire(descriptor: Int32, path: String, conflict: StoreError) throws
    -> FileLock
  {
    guard descriptor >= 0 else { throw StoreError.unsafePath(path) }
    do {
      var info = stat()
      guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
        info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
        fchmod(descriptor, 0o600) == 0
      else { throw StoreError.unsafePath(path) }
      guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
        if errno == EWOULDBLOCK || errno == EAGAIN { throw conflict }
        throw StoreError.storage(code: errno, operation: "flock")
      }
      return FileLock(descriptor: descriptor)
    } catch {
      Darwin.close(descriptor)
      throw error
    }
  }

  func release() {
    descriptor.withLock { value in
      guard let descriptor = value else { return }
      // A fork/dup reference can outlive this logical owner. Relinquish the shared flock
      // explicitly rather than waiting for every descriptor reference to close.
      while flock(descriptor, LOCK_UN) != 0 && errno == EINTR {}
      Darwin.close(descriptor)
      value = nil
    }
  }
}

/// Store-lifetime directory ownership. Every lock and unlink uses these opened objects, never
/// a fresh resolution of a directory pathname that may now name an unrelated tree.
final class StoreDirectories: Sendable {
  private struct Descriptors: Sendable {
    let root: Int32
    let pi: Int32
    let run: Int32?
  }

  private let directory: URL
  private let descriptors: Mutex<Descriptors?>

  init(_ directory: URL) throws {
    let root = try Self.openDirectory(directory.path, in: AT_FDCWD)
    var pi: Int32?
    var run: Int32?
    do {
      let openedPi = try Self.openDirectory("pi", in: root)
      pi = openedPi
      #if os(macOS)
        run = try Self.openDirectory("run", in: root)
      #endif
      self.directory = directory
      self.descriptors = Mutex(Descriptors(root: root, pi: openedPi, run: run))
    } catch {
      if let run { Darwin.close(run) }
      if let pi { Darwin.close(pi) }
      Darwin.close(root)
      throw error
    }
  }

  deinit { release() }

  func acquireWriterLock() throws -> FileLock {
    try descriptors.withLock { value in
      guard let value else { throw StoreError.closed }
      #if os(macOS)
        let name = "memoshi-store.lock"
      #else
        let name = ".memoshi-store.lock"
      #endif
      return try FileLock.acquire(name, in: value.run ?? value.root, conflict: .alreadyOpen)
    }
  }

  func acquireConversationLock(_ id: ConversationID) throws -> FileLock {
    try descriptors.withLock { value in
      guard let value else { throw StoreError.closed }
      return try FileLock.acquire(
        id.rawValue + ".lock", in: value.run ?? value.pi, conflict: .conversationInUse(id))
    }
  }

  /// Pi's SDK still opens a path. Refuse a known replacement before handing that path out;
  /// locks and purge themselves never rely on this point-in-time pathname check.
  func checkConversationFile(_ file: URL) throws {
    try descriptors.withLock { value in
      guard let value else { throw StoreError.closed }
      var root = stat()
      var namedRoot = stat()
      guard fstat(value.root, &root) == 0, lstat(directory.path, &namedRoot) == 0,
        Self.sameDirectory(root, namedRoot)
      else { throw StoreError.unsafePath(directory.path) }
      var pi = stat()
      var namedPi = stat()
      guard fstat(value.pi, &pi) == 0,
        fstatat(value.root, "pi", &namedPi, AT_SYMLINK_NOFOLLOW) == 0,
        Self.sameDirectory(pi, namedPi)
      else { throw StoreError.unsafePath(directory.appendingPathComponent("pi").path) }
      try StorePaths.checkConversationFile(file, in: value.pi)
    }
  }

  func withPiDirectory<Value>(_ body: (Int32) throws -> Value) throws -> Value {
    try descriptors.withLock { value in
      guard let value else { throw StoreError.closed }
      return try body(value.pi)
    }
  }

  /// The store directory, which holds the database (`DeviceDrain`).
  func withRootDirectory<Value>(_ body: (Int32) throws -> Value) throws -> Value {
    try descriptors.withLock { value in
      guard let value else { throw StoreError.closed }
      return try body(value.root)
    }
  }

  func release() {
    descriptors.withLock { value in
      guard let opened = value else { return }
      value = nil
      if let run = opened.run { Darwin.close(run) }
      Darwin.close(opened.pi)
      Darwin.close(opened.root)
    }
  }

  private static func openDirectory(_ name: String, in parent: Int32) throws -> Int32 {
    let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw StoreError.unsafePath(name) }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
      info.st_mode & S_IFMT == S_IFDIR, fchmod(descriptor, 0o700) == 0
    else {
      Darwin.close(descriptor)
      throw StoreError.unsafePath(name)
    }
    return descriptor
  }

  private static func sameDirectory(_ opened: stat, _ named: stat) -> Bool {
    named.st_mode & S_IFMT == S_IFDIR && opened.st_dev == named.st_dev
      && opened.st_ino == named.st_ino && named.st_uid == getuid()
  }
}

enum StorePaths {
  static func prepare(_ directory: URL) throws {
    guard directory.isFileURL else { throw StoreError.unsafePath(directory.absoluteString) }
    try privateDirectory(directory)
    for child in ["pi", "backups"] {
      try privateDirectory(directory.appendingPathComponent(child, isDirectory: true))
    }
    #if os(macOS)
      try privateDirectory(directory.appendingPathComponent("run", isDirectory: true))
    #endif
  }

  static func privateDirectory(_ url: URL) throws {
    var info = stat()
    if lstat(url.path, &info) != 0 {
      guard errno == ENOENT else { throw StoreError.unsafePath(url.path) }
      try FileManager.default.createDirectory(
        at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      guard lstat(url.path, &info) == 0 else { throw StoreError.unsafePath(url.path) }
    }
    guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR,
      chmod(url.path, 0o700) == 0
    else { throw StoreError.unsafePath(url.path) }
  }

  static func databaseFile(_ url: URL) throws {
    let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw StoreError.unsafePath(url.path) }
    defer { Darwin.close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
      info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
      fchmod(descriptor, 0o600) == 0
    else { throw StoreError.unsafePath(url.path) }
  }

  static func checkConversationFile(_ url: URL, in directory: Int32) throws {
    var info = stat()
    if fstatat(directory, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) != 0 {
      guard errno == ENOENT else { throw StoreError.unsafePath(url.path) }
      return
    }
    guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
      throw StoreError.unsafePath(url.path)
    }
  }
}
