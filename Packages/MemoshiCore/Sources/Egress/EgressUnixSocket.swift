import Darwin
import Foundation
import Synchronization

/// A host-owned short socket path, outside every bot-writable root. The sandbox receives an
/// exact network-outbound rule for this one path, never a localhost/IP/port allowance.
final class EgressUnixSocket: Sendable {
  let directory: String
  let path: String
  private let device: dev_t
  private let inode: ino_t
  private let publishedCA = Mutex<String?>(nil)

  var certificateBundlePath: String? { publishedCA.withLock { $0 } }

  init() throws {
    var template = Array("/private/tmp/memoshi-egress.XXXXXX".utf8CString)
    guard let created = template.withUnsafeMutableBufferPointer({ mkdtemp($0.baseAddress) }) else {
      throw EgressConfigurationError.unbound
    }
    let directory = String(cString: created)
    var info = stat()
    guard lstat(directory, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
      info.st_uid == geteuid(), info.st_mode & 0o777 == 0o700
    else {
      _ = rmdir(directory)
      throw EgressConfigurationError.unbound
    }
    self.directory = directory
    path = directory + "/proxy.sock"
    device = info.st_dev
    inode = info.st_ino
  }

  /// Binding precedes publication. Other users cannot traverse the directory at any point.
  func seal() throws {
    var info = stat()
    guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK,
      info.st_uid == geteuid(), chmod(path, 0o600) == 0
    else { throw EgressConfigurationError.unbound }
  }

  /// Writes public trust material only. The root stays host-owned and unwritable by the bot;
  /// a client that does not consume this scoped bundle fails certificate validation.
  func publishCertificateAuthorities(_ bytes: [UInt8]) throws {
    // Keep public HTTPS working for other allowed hosts too. These are additional scoped
    // anchors, not a replacement for the stock public roots used by command-line clients.
    let stock = try Data(contentsOf: URL(fileURLWithPath: "/private/etc/ssl/cert.pem"))
    guard stock.count <= 2 << 20 else { throw EgressConfigurationError.invalidTLS }
    let publicBundle = try EgressTLSInterception.publicCertificates(Array(stock) + bytes)
    let path = directory + "/ca.pem"
    let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o400)
    guard descriptor >= 0 else { throw EgressConfigurationError.invalidTLS }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try file.write(contentsOf: Data(publicBundle))
    try file.close()
    publishedCA.withLock { $0 = path }
  }

  func remove() {
    var info = stat()
    guard lstat(directory, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
      info.st_dev == device, info.st_ino == inode, info.st_uid == geteuid()
    else { return }
    _ = unlink(directory + "/ca.pem")
    _ = unlink(path)
    _ = rmdir(directory)
  }
}
