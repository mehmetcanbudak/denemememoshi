import Darwin
import Foundation

/// A file selected under an already authorized root. Browser tools must resolve their own bot
/// home/granted-folder authority before constructing this value; it does not create a grant.
public struct BrowserUploadSource: Sendable {
  /// Authorized directory capability, never a model-selected ambient root.
  public let root: URL
  /// Relative path inside that root; symlinks, traversal and hard links are refused.
  public let relativePath: String

  /// Creates an authorized source selection.
  public init(root: URL, relativePath: String) {
    self.root = root
    self.relativePath = relativePath
  }
}

/// Stable upload failures; file paths and contents are never included.
public enum BrowserUploadError: String, Error, Sendable {
  case invalidPath, unavailable, unsafeFile, tooLarge, changedDuringCopy, pickerMismatch
}

/// Copies approved files into an app-owned private directory. A page only receives these copies,
/// once, for the exact frame/document/input that was staged. This actor is shared by Mac/mobile.
public actor BrowserUploadStaging {
  private let directory: URL
  private let maximumBytes: Int64
  private var files: [URL] = []
  private var permit: BrowserAuthorization.OneUsePermit?

  /// Creates a fresh private staging directory beneath an app-owned directory.
  public init(parentDirectory: URL, maximumBytes: Int64 = 1_073_741_824) throws {
    guard parentDirectory.isFileURL, maximumBytes > 0 else { throw BrowserUploadError.invalidPath }
    try FileManager.default.createDirectory(
      at: parentDirectory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    directory = parentDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    self.maximumBytes = maximumBytes
  }

  /// Replaces any earlier staged upload after copying every approved file without following
  /// symlinks. A partial failure discards all of this staging operation, never a subset upload.
  public func stage(
    _ sources: [BrowserUploadSource], binding: BrowserAuthorization.DocumentBinding,
    now: Date = Date()
  ) throws {
    try Task.checkCancellation()
    clear()
    guard (1...10).contains(sources.count) else { throw BrowserUploadError.invalidPath }
    do {
      var total: Int64 = 0
      for source in sources {
        try Task.checkCancellation()
        let (url, count) = try copy(source, remaining: maximumBytes - total)
        files.append(url)
        total += count
      }
      permit = BrowserAuthorization.OneUsePermit(binding: binding, now: now)
    } catch {
      clear()
      throw error
    }
  }

  /// The only path a WebKit open-panel callback uses. Unstaged, stale, reused, directory and
  /// mismatched-multiple pickers return no files. Consumed copies live until navigation/close.
  public func consume(
    binding: BrowserAuthorization.DocumentBinding, allowsMultiple: Bool,
    allowsDirectories: Bool, now: Date = Date()
  ) throws -> [URL] {
    try Task.checkCancellation()
    guard var permit else { throw BrowserUploadError.pickerMismatch }
    self.permit = nil
    guard !allowsDirectories, allowsMultiple || files.count == 1 else {
      throw BrowserUploadError.pickerMismatch
    }
    try permit.consume(for: binding, now: now)
    return files
  }

  /// Navigation, revocation and session close remove only the copies this actor created.
  public func discard() { clear() }

  /// Ends this staging session and removes its own directory.
  public func close() {
    clear()
    try? FileManager.default.removeItem(at: directory)
  }

  private func clear() {
    permit = nil
    for file in files { try? FileManager.default.removeItem(at: file) }
    files.removeAll()
  }

  private static func directoryDescriptor(_ path: String) throws -> Int32 {
    guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw BrowserUploadError.invalidPath }
    var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard descriptor >= 0 else { throw BrowserUploadError.unavailable }
    do {
      for component in path.split(separator: "/") {
        guard component != ".", component != ".." else { throw BrowserUploadError.invalidPath }
        let next = openat(
          descriptor, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard next >= 0 else { throw BrowserUploadError.unsafeFile }
        _ = Darwin.close(descriptor)
        descriptor = next
      }
      return descriptor
    } catch {
      _ = Darwin.close(descriptor)
      throw error
    }
  }

  private func copy(_ source: BrowserUploadSource, remaining: Int64) throws -> (URL, Int64) {
    guard source.root.isFileURL, source.root.path.hasPrefix("/"),
      !source.relativePath.hasPrefix("/"), !source.relativePath.utf8.contains(0)
    else { throw BrowserUploadError.invalidPath }
    let components = source.relativePath.split(separator: "/", omittingEmptySubsequences: false)
    guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
    else { throw BrowserUploadError.invalidPath }
    var descriptor = try Self.directoryDescriptor(source.root.path)
    defer { _ = Darwin.close(descriptor) }
    for component in components.dropLast() {
      let next = openat(
        descriptor, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard next >= 0 else { throw BrowserUploadError.unsafeFile }
      _ = Darwin.close(descriptor)
      descriptor = next
    }
    let input = openat(
      descriptor, String(components[components.count - 1]),
      O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard input >= 0 else { throw BrowserUploadError.unsafeFile }
    defer { _ = Darwin.close(input) }
    var before = stat()
    guard fstat(input, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
      before.st_nlink == 1, before.st_size >= 0
    else { throw BrowserUploadError.unsafeFile }
    guard before.st_size <= remaining else { throw BrowserUploadError.tooLarge }
    let ext = URL(fileURLWithPath: source.relativePath).pathExtension
    let safeExtension =
      !ext.isEmpty && ext.utf8.count <= 12
        && ext.utf8.allSatisfy({
          (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        })
      ? "." + ext : ""
    let destination = directory.appendingPathComponent(UUID().uuidString + safeExtension)
    let output = Darwin.open(
      destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard output >= 0 else { throw BrowserUploadError.unavailable }
    var succeeded = false
    defer {
      _ = Darwin.close(output)
      if !succeeded { _ = Darwin.unlink(destination.path) }
    }
    var buffer = [UInt8](repeating: 0, count: 65_536)
    var copied: Int64 = 0
    while true {
      try Task.checkCancellation()
      let count = Darwin.read(input, &buffer, buffer.count)
      if count < 0 && errno == EINTR { continue }
      guard count >= 0 else { throw BrowserUploadError.unavailable }
      if count == 0 { break }
      copied += Int64(count)
      guard copied <= remaining else { throw BrowserUploadError.tooLarge }
      try buffer.withUnsafeBytes { bytes in
        guard let baseAddress = bytes.baseAddress else { throw BrowserUploadError.unavailable }
        var offset = 0
        while offset < count {
          let written = Darwin.write(output, baseAddress.advanced(by: offset), count - offset)
          if written < 0 && errno == EINTR { continue }
          guard written > 0 else { throw BrowserUploadError.unavailable }
          offset += written
        }
      }
    }
    var after = stat()
    guard fstat(input, &after) == 0, copied == before.st_size, after.st_size == before.st_size,
      after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
      after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec, after.st_nlink == 1,
      fsync(output) == 0
    else { throw BrowserUploadError.changedDuringCopy }
    succeeded = true
    return (destination, copied)
  }
}
