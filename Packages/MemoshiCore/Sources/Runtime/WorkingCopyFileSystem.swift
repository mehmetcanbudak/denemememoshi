import CryptoKit
import Darwin
import Foundation

/// One owned descriptor. Handles never leave the private working-copy engine; the unchecked
/// sendability only lets the actor's nonisolated initializer and deinitializer own them.
final class WorkingCopyHandle: @unchecked Sendable {
  private(set) var value: Int32

  init(_ value: Int32) { self.value = value }

  /// Closes once and reports a failed close; later calls do nothing.
  func close() throws {
    guard value >= 0 else { return }
    let descriptor = value
    value = -1
    guard Darwin.close(descriptor) == 0 else { throw WorkingCopyFS.failure("close descriptor") }
  }

  deinit {
    if value >= 0 { Darwin.close(value) }
  }
}

/// One file-system object's physical identity.
struct WorkingCopyObjectID: Hashable, Sendable {
  let device: UInt64
  let inode: UInt64

  init(_ metadata: stat) {
    device = UInt64(bitPattern: Int64(metadata.st_dev))
    inode = UInt64(metadata.st_ino)
  }
}

/// No-follow regular-file metadata. A replacement, link, mode, owner, size or content change
/// alters at least one field, so equality detects a concurrent writer between observations.
struct WorkingCopyFileState: Equatable, Sendable {
  let identity: WorkingCopyObjectID
  let mode: mode_t
  let owner: uid_t
  let group: gid_t
  let flags: UInt32
  let links: UInt64
  let size: Int64
  let modifiedSeconds: Int64
  let modifiedNanoseconds: Int64
  let changedSeconds: Int64
  let changedNanoseconds: Int64

  init(_ metadata: stat) {
    identity = WorkingCopyObjectID(metadata)
    mode = metadata.st_mode
    owner = metadata.st_uid
    group = metadata.st_gid
    flags = metadata.st_flags
    links = UInt64(metadata.st_nlink)
    size = Int64(metadata.st_size)
    modifiedSeconds = Int64(metadata.st_mtimespec.tv_sec)
    modifiedNanoseconds = Int64(metadata.st_mtimespec.tv_nsec)
    changedSeconds = Int64(metadata.st_ctimespec.tv_sec)
    changedNanoseconds = Int64(metadata.st_ctimespec.tv_nsec)
  }

  var permissions: mode_t { mode & 0o7777 }
}

/// One scanned regular file: its metadata and the SHA-256 of the exact bytes read.
struct WorkingCopyFileRecord: Equatable, Sendable {
  let state: WorkingCopyFileState
  let hash: String
}

/// One scanned directory. Its entries are compared by name while it is scanned, so times are
/// omitted: a directory changed only by an exported file is still the admitted directory.
struct WorkingCopyDirectoryRecord: Equatable, Sendable {
  let identity: WorkingCopyObjectID
  let permissions: mode_t
  let owner: uid_t
  let group: gid_t
  let flags: UInt32

  init(_ metadata: stat) {
    identity = WorkingCopyObjectID(metadata)
    permissions = metadata.st_mode & 0o7777
    owner = metadata.st_uid
    group = metadata.st_gid
    flags = metadata.st_flags
  }
}

/// An absolute directory reached one no-follow component at a time from `/`.
struct WorkingCopyRoot {
  let handle: WorkingCopyHandle
  let path: String
  let metadata: stat
  /// Every directory on the path, the opened directory included.
  let ancestors: Set<WorkingCopyObjectID>
}

/// Descriptor-relative primitives for the private working-copy engine. Each name is one
/// validated component opened without following links, and each descriptor is close-on-exec and
/// checked against its expected kernel path and identity. Raw diagnostics stay in the engine.
enum WorkingCopyFS {
  /// A system failure whose `errno` is captured before the operation text is built.
  static func failure(_ operation: @autoclosure () -> String) -> WorkingCopyFailure {
    let code = errno
    return .system(operation: operation(), code: code)
  }

  static func metadata(_ fd: Int32) throws -> stat {
    var result = stat()
    guard Darwin.fstat(fd, &result) == 0 else { throw failure("fstat") }
    return result
  }

  /// No-follow metadata for one name in a directory, or `nil` only when the name is absent.
  static func metadataAt(_ fd: Int32, _ name: String) throws -> stat? {
    var result = stat()
    if Darwin.fstatat(fd, name, &result, AT_SYMLINK_NOFOLLOW) == 0 { return result }
    let code = errno
    if code == ENOENT { return nil }
    throw WorkingCopyFailure.system(operation: "fstatat \(name)", code: code)
  }

  static func requireCloexec(_ fd: Int32) throws {
    let flags = Darwin.fcntl(fd, F_GETFD)
    guard flags >= 0 else { throw failure("fcntl F_GETFD") }
    guard flags & FD_CLOEXEC != 0 else {
      throw WorkingCopyFailure.refused("descriptor is not close-on-exec")
    }
  }

  /// Calls `body` with the descriptor's current absolute kernel path, without its NUL.
  static func withDescriptorPath<Value>(
    _ fd: Int32, _ body: (UnsafeBufferPointer<UInt8>) throws -> Value
  ) throws -> Value {
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: Int(MAXPATHLEN)) { buffer in
      buffer.initialize(repeating: 0)
      guard let base = buffer.baseAddress, Darwin.fcntl(fd, F_GETPATH, base) == 0 else {
        throw failure("fcntl F_GETPATH")
      }
      guard let end = buffer.firstIndex(of: 0), end > 0, buffer[0] == 47 else {
        throw WorkingCopyFailure.refused("descriptor has no verified absolute path")
      }
      return try body(UnsafeBufferPointer(rebasing: buffer[..<end]))
    }
  }

  static func rawDescriptorPath(_ fd: Int32) throws -> [UInt8] {
    try withDescriptorPath(fd) { Array($0) }
  }

  static func descriptorPath(_ fd: Int32) throws -> String {
    try withDescriptorPath(fd) { raw in
      guard let path = String(validating: raw, as: UTF8.self) else {
        throw WorkingCopyFailure.refused("descriptor path is not valid UTF-8")
      }
      return path
    }
  }

  /// Requires a close-on-exec descriptor still at `expected`. Like source-root verification, a
  /// canonically equivalent spelling of the same path is accepted, never a different path.
  static func verifyPath(_ fd: Int32, _ expected: String) throws {
    let same: Bool = try withDescriptorPath(fd) { raw in
      if raw.elementsEqual(expected.utf8) { return true }
      return String(validating: raw, as: UTF8.self) == expected
    }
    guard same else {
      throw WorkingCopyFailure.refused("descriptor moved away from verified path \(expected)")
    }
    try requireCloexec(fd)
  }

  /// Refuses any spelling that could denote more or less than one directory entry. Separators
  /// are matched by scalar, so a combining mark cannot hide one inside a grapheme.
  static func component(_ name: String) throws {
    let unsafeScalar = name.unicodeScalars.contains {
      $0 == "/" || $0 == "\\" || $0 == ":" || CharacterSet.controlCharacters.contains($0)
    }
    guard !unsafeScalar, !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255,
      name.lowercased() != "..namedfork"
    else {
      throw WorkingCopyFailure.refused("unsafe path component \(String(reflecting: name))")
    }
  }

  /// Splits a nonempty relative path by scalar into validated components.
  static func relativeComponents(_ path: String) throws -> [String] {
    guard let first = path.unicodeScalars.first, first != "/" else {
      throw WorkingCopyFailure.refused("expected a nonempty relative path")
    }
    let parts = path.unicodeScalars.split(separator: "/", omittingEmptySubsequences: false).map {
      String(Substring($0))
    }
    for part in parts { try component(part) }
    return parts
  }

  static func childPath(_ parent: String, _ name: String) -> String {
    parent == "/" ? "/" + name : parent + "/" + name
  }

  /// Whether `child` is `parent` or lies beneath it, by exact bytes or by canonical spelling.
  static func isWithin(_ child: String, _ parent: String) -> Bool {
    let prefix = parent == "/" ? "/" : parent + "/"
    if child.utf8.elementsEqual(parent.utf8) || child.utf8.starts(with: prefix.utf8) {
      return true
    }
    return child == parent || child.hasPrefix(prefix)
  }

  static func requireDirectory(_ metadata: stat, path: String, device: UInt64? = nil) throws {
    guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
      throw WorkingCopyFailure.refused("not a real directory: \(path)")
    }
    if let device, WorkingCopyObjectID(metadata).device != device {
      throw WorkingCopyFailure.refused("mount or device crossing: \(path)")
    }
  }

  static func requireOwnedDirectory(
    _ metadata: stat, path: String, privateContainer: Bool = false
  ) throws {
    try requireDirectory(metadata, path: path)
    guard metadata.st_uid == geteuid() else {
      throw WorkingCopyFailure.refused("directory is not owned by the effective user: \(path)")
    }
    guard metadata.st_mode & 0o7000 == 0 else {
      throw WorkingCopyFailure.refused("special directory permission bits: \(path)")
    }
    if privateContainer, metadata.st_mode & 0o022 != 0 {
      throw WorkingCopyFailure.refused("container is group or other writable: \(path)")
    }
  }

  /// A single-link regular file owned by this user on `device`, without special mode bits.
  static func requireRegular(_ metadata: stat, path: String, device: UInt64) throws {
    guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      throw WorkingCopyFailure.refused("symlink or non-regular entry: \(path)")
    }
    guard metadata.st_nlink == 1 else {
      throw WorkingCopyFailure.refused("multiply-linked regular file: \(path)")
    }
    guard WorkingCopyObjectID(metadata).device == device, metadata.st_uid == geteuid(),
      metadata.st_size >= 0, metadata.st_mode & 0o7000 == 0
    else {
      throw WorkingCopyFailure.refused("unsafe file device, owner, size or mode bits: \(path)")
    }
  }

  /// Opens one existing child directory without following a link and proves the opened object
  /// is the named one, at its expected path and, when given, on the expected device.
  static func openDirectory(
    _ parent: Int32, name: String, expectedPath: String, device: UInt64? = nil
  ) throws -> WorkingCopyHandle {
    try component(name)
    guard let named = try metadataAt(parent, name) else {
      throw WorkingCopyFailure.refused("directory disappeared: \(expectedPath)")
    }
    try requireDirectory(named, path: expectedPath, device: device)
    let raw = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard raw >= 0 else { throw failure("openat directory \(expectedPath)") }
    let handle = WorkingCopyHandle(raw)
    let opened = try metadata(handle.value)
    try requireDirectory(opened, path: expectedPath, device: device)
    guard WorkingCopyObjectID(named) == WorkingCopyObjectID(opened) else {
      throw WorkingCopyFailure.refused("directory changed during open: \(expectedPath)")
    }
    try verifyPath(handle.value, expectedPath)
    return handle
  }

  /// Opens an absolute directory from `/`, one validated no-follow component at a time.
  static func openAbsoluteDirectory(_ input: String) throws -> WorkingCopyRoot {
    guard input.unicodeScalars.first == "/" else {
      throw WorkingCopyFailure.refused("root path must be absolute")
    }
    var path = input
    while path.utf8.count > 1, path.utf8.last == 47 { path.unicodeScalars.removeLast() }
    var names: [String] = []
    if path != "/" {
      // The scalar split refuses an empty, dot or unsafe component, as for relative paths.
      names = try relativeComponents(String(Substring(path.unicodeScalars.dropFirst())))
    }
    let raw = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard raw >= 0 else { throw failure("open filesystem root") }
    var current = WorkingCopyHandle(raw)
    var currentPath = "/"
    try verifyPath(current.value, currentPath)
    var ancestors: Set<WorkingCopyObjectID> = [WorkingCopyObjectID(try metadata(current.value))]
    for name in names {
      currentPath = childPath(currentPath, name)
      current = try openDirectory(current.value, name: name, expectedPath: currentPath)
      ancestors.insert(WorkingCopyObjectID(try metadata(current.value)))
    }
    let opened = try metadata(current.value)
    try requireDirectory(opened, path: path)
    try verifyPath(current.value, path)
    return WorkingCopyRoot(handle: current, path: path, metadata: opened, ancestors: ancestors)
  }

  /// Every entry except dot entries, as validated UTF-8 components in byte order. An unreadable,
  /// unsafe or ambiguous name refuses instead of being skipped.
  static func entryNames(
    _ fd: Int32, maximumEntries: Int = WorkingCopyLimits.standard.maximumEntries
  ) throws -> [String] {
    let raw = Darwin.openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard raw >= 0 else { throw failure("openat directory enumeration") }
    guard let stream = fdopendir(raw) else {
      let code = errno
      Darwin.close(raw)
      throw WorkingCopyFailure.system(operation: "fdopendir", code: code)
    }
    defer { closedir(stream) }
    try requireCloexec(raw)
    var names: [String] = []
    var seen: Set<String> = []
    while true {
      try Task.checkCancellation()
      errno = 0
      guard let entry = readdir(stream) else {
        if errno != 0 { throw failure("readdir") }
        break
      }
      let length = Int(entry.pointee.d_namlen)
      let decoded = withUnsafeBytes(of: &entry.pointee.d_name) { bytes in
        String(validating: bytes.prefix(length), as: UTF8.self)
      }
      guard let name = decoded else {
        throw WorkingCopyFailure.refused("directory entry is not valid UTF-8")
      }
      if name == "." || name == ".." { continue }
      guard names.count < maximumEntries else { throw WorkingCopyFailure.resourceLimitExceeded }
      try component(name)
      // Canonically equivalent names would be one tree key, so both refuse as ambiguous.
      guard seen.insert(name).inserted else {
        throw WorkingCopyFailure.refused("ambiguous duplicate directory entry: \(name)")
      }
      names.append(name)
    }
    names.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    return names
  }

  static func writeAll(_ fd: Int32, _ bytes: UnsafeRawBufferPointer) throws {
    guard let base = bytes.baseAddress else { return }
    var offset = 0
    while offset < bytes.count {
      let count = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
      if count < 0 {
        if errno == EINTR { continue }
        throw failure("write private or temporary file")
      }
      guard count > 0 else {
        throw WorkingCopyFailure.refused("zero-length write before completion")
      }
      offset += count
    }
  }

  /// Streams one regular file through SHA-256 with the caller's reusable buffer, optionally
  /// copying the same bytes to an owned descriptor or capturing them. Any change to the file
  /// between its first no-follow observation and the end of the read refuses.
  static func readFile(
    parent: Int32, name: String, expectedPath: String, device: UInt64, buffer: inout [UInt8],
    copyTo destination: Int32? = nil, capture: Bool = false,
    maximumBytes: Int64 = WorkingCopyLimits.standard.maximumFileBytes
  ) throws -> (file: WorkingCopyFileRecord, contents: Data?) {
    guard let named = try metadataAt(parent, name) else {
      throw WorkingCopyFailure.refused("file disappeared: \(expectedPath)")
    }
    try requireRegular(named, path: expectedPath, device: device)
    guard named.st_size <= maximumBytes else { throw WorkingCopyFailure.resourceLimitExceeded }
    // O_NONBLOCK keeps a file-to-FIFO race from blocking before the opened object is checked.
    let raw = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    guard raw >= 0 else { throw failure("openat file \(expectedPath)") }
    let handle = WorkingCopyHandle(raw)
    let before = try metadata(handle.value)
    try requireRegular(before, path: expectedPath, device: device)
    guard WorkingCopyFileState(before) == WorkingCopyFileState(named) else {
      throw WorkingCopyFailure.refused("file changed during open: \(expectedPath)")
    }
    try verifyPath(handle.value, expectedPath)
    try requireContentOnlyMetadata(handle.value, metadata: before)
    guard before.st_size <= maximumBytes else { throw WorkingCopyFailure.resourceLimitExceeded }
    var hasher = SHA256()
    var contents: Data?
    if capture {
      guard let capacity = Int(exactly: before.st_size) else {
        throw WorkingCopyFailure.refused("file cannot fit proposal data: \(expectedPath)")
      }
      contents = Data(capacity: capacity)
    }
    var total: Int64 = 0
    while true {
      try Task.checkCancellation()
      let count = try buffer.withUnsafeMutableBytes { storage -> Int in
        guard let base = storage.baseAddress else {
          throw WorkingCopyFailure.refused("working-copy I/O buffer is empty")
        }
        var amount: Int
        repeat {
          amount = Darwin.read(handle.value, base, storage.count)
        } while amount < 0 && errno == EINTR
        guard amount >= 0 else { throw failure("read \(expectedPath)") }
        if amount > 0 {
          guard Int64(amount) <= maximumBytes - total else {
            throw WorkingCopyFailure.resourceLimitExceeded
          }
          total += Int64(amount)
          let bytes = UnsafeRawBufferPointer(start: base, count: amount)
          hasher.update(bufferPointer: bytes)
          if let destination { try writeAll(destination, bytes) }
          contents?.append(bytes.assumingMemoryBound(to: UInt8.self))
        }
        return amount
      }
      if count == 0 { break }
    }
    let after = try metadata(handle.value)
    try requireRegular(after, path: expectedPath, device: device)
    try requireContentOnlyMetadata(handle.value, metadata: after)
    guard WorkingCopyFileState(before) == WorkingCopyFileState(after),
      total == Int64(after.st_size),
      let current = try metadataAt(parent, name),
      WorkingCopyFileState(current) == WorkingCopyFileState(after)
    else {
      throw WorkingCopyFailure.refused("file changed while reading: \(expectedPath)")
    }
    try verifyPath(handle.value, expectedPath)
    let file = WorkingCopyFileRecord(
      state: WorkingCopyFileState(after), hash: hex(hasher.finalize()))
    return (file, contents)
  }

  /// Lowercase hexadecimal SHA-256.
  static func hex(_ digest: SHA256.Digest) -> String {
    let digits: StaticString = "0123456789abcdef"
    return digits.withUTF8Buffer { alphabet in
      String(unsafeUninitializedCapacity: SHA256.byteCount * 2) { output in
        for (index, byte) in digest.enumerated() {
          output[index * 2] = alphabet[Int(byte >> 4)]
          output[index * 2 + 1] = alphabet[Int(byte & 15)]
        }
        return SHA256.byteCount * 2
      }
    }
  }
}
