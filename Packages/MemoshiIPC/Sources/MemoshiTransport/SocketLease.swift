import Darwin
import Foundation
import NIOCore

/// Keeps a directory descriptor and inode identity, so closure never unlinks a
/// replacement listener. The daemon's separate process lock owns startup order.
///
/// The lease binds the socket itself, under a staging name, and renames it to `url` only once
/// it is 0600. The published name therefore never carries the umask mode, and NIO, which
/// adopts the descriptor, has no pathname of its own to unlink when the channel closes.
internal final class SocketLease: @unchecked Sendable {
  let url: URL
  private let staging: URL
  private let lock = NSLock()
  private var parent: CInt
  private var node: stat?
  private var published = false

  /// The same length as a `.sock` name, so it fits `sun_path` wherever the published name does.
  static func stagingURL(for url: URL) -> URL {
    url.deletingPathExtension().appendingPathExtension("bind")
  }

  init(url: URL) throws {
    self.url = url
    staging = Self.stagingURL(for: url)
    parent = try PrivateFileSystem.openDirectory(url.deletingLastPathComponent())
    do { try removeStaleSocket() } catch {
      Darwin.close(parent)
      parent = -1
      throw error
    }
  }

  deinit { release() }

  private func removeStaleSocket() throws {
    var original = stat()
    guard fstatat(parent, url.lastPathComponent, &original, AT_SYMLINK_NOFOLLOW) == 0 else {
      if errno == ENOENT { return }
      throw PrivateFileSystem.failure("stat existing socket")
    }
    guard original.st_uid == geteuid(), original.st_mode & S_IFMT == S_IFSOCK,
      original.st_mode & 0o7777 == 0o600, original.st_nlink == 1
    else { throw IPCError.unsafePath(url.path) }
    try requireUnused(url)
    var current = stat()
    guard fstatat(parent, url.lastPathComponent, &current, AT_SYMLINK_NOFOLLOW) == 0,
      PrivateFileSystem.sameNode(original, current)
    else { throw IPCError.unsafePath(url.path) }
    guard unlinkat(parent, url.lastPathComponent, 0) == 0 else {
      throw PrivateFileSystem.failure("remove stale Unix socket")
    }
  }

  /// Throws EADDRINUSE when a listener still accepts connections at `target`. Only a refused
  /// connection shows that the entry was left behind.
  private func requireUnused(_ target: URL) throws {
    let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard probe >= 0 else { throw PrivateFileSystem.failure("create socket probe") }
    defer { Darwin.close(probe) }
    guard fcntl(probe, F_SETFD, FD_CLOEXEC) == 0 else {
      throw PrivateFileSystem.failure("protect socket probe descriptor")
    }
    guard fcntl(probe, F_SETFL, O_NONBLOCK) == 0 else {
      throw PrivateFileSystem.failure("make socket probe nonblocking")
    }
    let address = try SocketAddress(unixDomainSocketPath: target.path)
    let result = address.withSockAddr { pointer, size in
      Darwin.connect(probe, pointer, socklen_t(size))
    }
    if result == 0 { throw IPCError.systemCall(operation: "bind Unix socket", code: EADDRINUSE) }
    let code = errno
    guard code == ECONNREFUSED else {
      throw IPCError.systemCall(operation: "probe existing Unix socket", code: code)
    }
  }

  /// Returns a new listening socket bound under the staging name with mode 0600; the caller
  /// owns the descriptor. A listener killed before `publish()` leaves only that staging entry,
  /// which was never a public endpoint and which the next bind removes. The socket listens
  /// before this returns, so a second starter finds it in use instead of taking its name.
  func bind() throws -> CInt {
    let name = staging.lastPathComponent
    var leftover = stat()
    if fstatat(parent, name, &leftover, AT_SYMLINK_NOFOLLOW) == 0 {
      guard leftover.st_uid == geteuid(), leftover.st_mode & S_IFMT == S_IFSOCK else {
        throw IPCError.unsafePath(staging.path)
      }
      try requireUnused(staging)
      var current = stat()
      guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
        PrivateFileSystem.sameNode(leftover, current)
      else { throw IPCError.unsafePath(staging.path) }
      guard unlinkat(parent, name, 0) == 0 else {
        throw PrivateFileSystem.failure("remove unpublished Unix socket")
      }
    } else if errno != ENOENT {
      throw PrivateFileSystem.failure("stat unpublished Unix socket")
    }
    let address = try SocketAddress(unixDomainSocketPath: staging.path)
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw PrivateFileSystem.failure("create Unix socket") }
    do {
      guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else {
        throw PrivateFileSystem.failure("protect Unix socket descriptor")
      }
      let bound = address.withSockAddr { pointer, size in
        Darwin.bind(fd, pointer, socklen_t(size))
      }
      guard bound == 0 else { throw PrivateFileSystem.failure("bind Unix socket") }
      var info = stat()
      guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw PrivateFileSystem.failure("stat bound Unix socket")
      }
      guard info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFSOCK, info.st_nlink == 1 else {
        throw IPCError.unsafePath(staging.path)
      }
      lock.withLock { node = info }
      guard fchmodat(parent, name, 0o600, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw PrivateFileSystem.failure("secure bound Unix socket")
      }
      try PrivateFileSystem.validateExisting(staging, kind: S_IFSOCK, mode: 0o600, required: true)
      var current = stat()
      guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
        PrivateFileSystem.sameNode(info, current)
      else { throw IPCError.unsafePath(staging.path) }
      // Only now, private and verified. The adopting NIO channel does not accept until its
      // autoRead is enabled, after `publish()`.
      guard Darwin.listen(fd, 128) == 0 else {
        throw PrivateFileSystem.failure("listen Unix socket")
      }
      return fd
    } catch {
      Darwin.close(fd)
      throw error
    }
  }

  /// Called while the NIO listening channel still has autoRead disabled: no connection can be
  /// accepted until the secured socket has its public name.
  func publish() throws {
    lock.lock()
    defer { lock.unlock() }
    var current = stat()
    guard let node, fstatat(parent, staging.lastPathComponent, &current, AT_SYMLINK_NOFOLLOW) == 0,
      PrivateFileSystem.sameNode(node, current)
    else { throw IPCError.unsafePath(staging.path) }
    // Exclusive, like the bind it replaces: an entry that appeared meanwhile is never replaced.
    guard
      renameatx_np(
        parent, staging.lastPathComponent, parent, url.lastPathComponent, UInt32(RENAME_EXCL)) == 0
    else { throw PrivateFileSystem.failure("publish Unix socket") }
    published = true
    try PrivateFileSystem.validateExisting(url, kind: S_IFSOCK, mode: 0o600, required: true)
    guard fstatat(parent, url.lastPathComponent, &current, AT_SYMLINK_NOFOLLOW) == 0,
      PrivateFileSystem.sameNode(node, current)
    else { throw IPCError.unsafePath(url.path) }
  }

  func release() {
    lock.lock()
    defer { lock.unlock() }
    guard parent >= 0 else { return }
    if let node {
      let name = (published ? url : staging).lastPathComponent
      var current = stat()
      if fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
        PrivateFileSystem.sameNode(node, current), current.st_mode & S_IFMT == S_IFSOCK,
        current.st_uid == geteuid()
      {
        unlinkat(parent, name, 0)
      }
    }
    Darwin.close(parent)
    parent = -1
  }
}
