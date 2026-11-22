import CMemoshiSecurity
import Darwin
import Foundation
import MemoshiProtocol
import Security

/// Rotates and reads private bearer tokens; code-signature peer authentication is still required.
public enum DaemonToken {
  /// Rotates the daemon-start bearer token with an atomic, private replacement.
  public static func mint(at url: URL) throws -> HelloToken {
    guard url.isFileURL, !url.path.utf8.contains(0) else { throw IPCError.unsafePath(url.path) }
    let parent = try PrivateFileSystem.openDirectory(url.deletingLastPathComponent())
    defer { Darwin.close(parent) }
    try validateDestination(url.lastPathComponent, parent: parent, path: url.path)
    var bytes = [UInt8](repeating: 0, count: 64)
    let status = bytes.withUnsafeMutableBytes {
      guard let address = $0.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, 32, address)
    }
    guard status == errSecSuccess else {
      throw IPCError.systemCall(operation: "secure random", code: status)
    }
    for index in stride(from: 31, through: 0, by: -1) {
      let byte = bytes[index]
      let high = byte >> 4
      let low = byte & 15
      bytes[index * 2] = high < 10 ? 48 + high : 87 + high
      bytes[index * 2 + 1] = low < 10 ? 48 + low : 87 + low
    }
    let temporary = ".memoshid-token-\(UUID().uuidString)"
    let fd = openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw PrivateFileSystem.failure("create token replacement") }
    defer {
      Darwin.close(fd)
      unlinkat(parent, temporary, 0)
    }
    guard fchmod(fd, 0o600) == 0 else { throw PrivateFileSystem.failure("set token permissions") }
    try PrivateFileSystem.validate(fd, path: url.path, kind: S_IFREG, mode: 0o600)
    try bytes.withUnsafeBytes { buffer in
      guard let address = buffer.baseAddress else { throw IPCError.invalidToken }
      var offset = 0
      while offset < buffer.count {
        let count = Darwin.write(
          fd, address.advanced(by: offset), buffer.count - offset)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw PrivateFileSystem.failure("write token replacement") }
        offset += count
      }
    }
    guard fsync(fd) == 0 else { throw PrivateFileSystem.failure("sync token replacement") }
    try validateDestination(url.lastPathComponent, parent: parent, path: url.path)
    guard renameat(parent, temporary, parent, url.lastPathComponent) == 0 else {
      throw PrivateFileSystem.failure("replace daemon token")
    }
    return try HelloToken(String(decoding: bytes, as: UTF8.self))
  }

  /// Reads exactly 64 lowercase hex bytes from a verified private, single-link file.
  public static func read(from url: URL) throws -> HelloToken {
    guard url.isFileURL, !url.path.utf8.contains(0) else { throw IPCError.unsafePath(url.path) }
    let parent = try PrivateFileSystem.openDirectory(url.deletingLastPathComponent())
    defer { Darwin.close(parent) }
    let fd = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else {
      if errno == ELOOP { throw IPCError.unsafePath(url.path) }
      throw PrivateFileSystem.failure("open daemon token")
    }
    defer { Darwin.close(fd) }
    try PrivateFileSystem.validate(fd, path: url.path, kind: S_IFREG, mode: 0o600)
    var info = stat()
    guard fstat(fd, &info) == 0 else { throw PrivateFileSystem.failure("stat daemon token") }
    guard info.st_size == 64 else { throw IPCError.invalidToken }
    var bytes = [UInt8](repeating: 0, count: 65)
    let count = try bytes.withUnsafeMutableBytes { buffer in
      guard let address = buffer.baseAddress else { throw IPCError.invalidToken }
      var offset = 0
      while offset < buffer.count {
        let count = Darwin.read(fd, address.advanced(by: offset), buffer.count - offset)
        if count < 0 && errno == EINTR { continue }
        guard count >= 0 else { throw PrivateFileSystem.failure("read daemon token") }
        if count == 0 { break }
        offset += count
      }
      return offset
    }
    guard count == 64,
      bytes.prefix(64).allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else {
      throw IPCError.invalidToken
    }
    // A malformed file is the fixed `invalidToken` above, never a protocol format error.
    return try HelloToken(String(decoding: bytes.prefix(64), as: UTF8.self))
  }

  /// Compares canonical token bytes without exiting early at a differing byte.
  public static func matches(_ first: HelloToken, _ second: HelloToken) -> Bool {
    var left = first.rawValue
    var right = second.rawValue
    return left.withUTF8 { left in
      right.withUTF8 { right in
        guard left.count == 64, right.count == 64,
          let leftAddress = left.baseAddress, let rightAddress = right.baseAddress
        else { return false }
        return MMSConstantTimeEqual(leftAddress, rightAddress, 64) != 0
      }
    }
  }

  private static func validateDestination(_ name: String, parent: CInt, path: String) throws {
    var info = stat()
    guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
      if errno == ENOENT { return }
      throw PrivateFileSystem.failure("stat token destination")
    }
    guard info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFREG,
      info.st_mode & 0o7777 == 0o600, info.st_nlink == 1
    else { throw IPCError.unsafePath(path) }
  }
}
