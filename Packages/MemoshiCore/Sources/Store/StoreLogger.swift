import Darwin
import Foundation
import MemoshiProtocol
import Synchronization

/// Severity used to filter metadata-only local JSONL diagnostics.
public enum LogLevel: String, Sendable {
  case debug, info, warn, error

  fileprivate var weight: Int {
    switch self {
    case .debug: 10
    case .info: 20
    case .warn: 30
    case .error: 40
    }
  }
}

/// Re-expressed from Draft 3 sidecar/src/log.ts at ce39f8a7ca324ce1c2473518593b1fb4f96ebe4b.
/// JSONL goes to stderr and memoshid.jsonl; five rotated files are retained at 10 MiB each.
/// Callers log metadata only. Redaction is defense in depth, not permission to log transcripts.
public final class StoreLogger: Sendable {
  private struct State {
    var handle: FileHandle?
    var closed = false
    let formatter = ISO8601DateFormatter()
  }

  private let state = Mutex(State())
  private let file: URL
  private let level: LogLevel
  private let rotationBytes: UInt64
  private let redactor: LogRedactor

  /// Configures a private, redacting logger and its bounded file rotation.
  public init(directory: URL, level: LogLevel = .info, rotationBytes: UInt64 = 10 * 1_024 * 1_024)
    throws
  {
    guard rotationBytes > 0 else { throw StoreError.invalidCommit("Zero log rotation size") }
    try StorePaths.privateDirectory(directory)
    self.file = directory.appendingPathComponent("memoshid.jsonl")
    self.level = level
    self.rotationBytes = rotationBytes
    self.redactor = try LogRedactor()
    // A closed stderr pipe must not turn a diagnostic into a process-killing SIGPIPE.
    _ = fcntl(STDERR_FILENO, F_SETNOSIGPIPE, 1)
  }

  deinit { close() }

  /// Redacts a metadata entry before writing it to stderr and the rotating file.
  public func log(
    _ level: LogLevel, _ message: String, fields: [String: JSONValue] = [:],
    at now: Int64 = IDGenerator.nowMilliseconds()
  ) {
    guard level.weight >= self.level.weight else { return }
    state.withLock { state in
      guard state.closed == false else { return }
      var entry = fields
      entry["ts"] = .string(
        state.formatter.string(from: Date(timeIntervalSince1970: Double(now) / 1_000)))
      entry["level"] = .string(level.rawValue)
      entry["msg"] = .string(message)
      do {
        let safe = redactor.redact(.object(entry))
        var bytes = try ProtocolCoding.makeEncoder().encode(safe)
        bytes.append(0x0A)
        try? FileHandle.standardError.write(contentsOf: bytes)
        do {
          if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
            let size = attributes[.size] as? NSNumber, size.uint64Value >= rotationBytes
          {
            try state.handle?.close()
            state.handle = nil
            try rotate()
          }
          if state.handle == nil { state.handle = try openFile() }
          try state.handle?.write(contentsOf: bytes)
        } catch {
          try? state.handle?.close()
          state.handle = nil
          // The already-redacted stderr record remains; diagnostics never fail the writer.
        }
      } catch {
        // JSONValue may contain a non-finite double. Never fall back to logging raw fields.
      }
    }
  }

  /// Releases the current log file and stops accepting entries.
  public func close() {
    state.withLock { state in
      try? state.handle?.close()
      state.handle = nil
      state.closed = true
    }
  }

  private func openFile() throws -> FileHandle {
    let descriptor = Darwin.open(
      file.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw StoreError.unsafePath(file.path) }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
      info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, fchmod(descriptor, 0o600) == 0
    else {
      Darwin.close(descriptor)
      throw StoreError.unsafePath(file.path)
    }
    return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  }

  private func rotate() throws {
    for number in stride(from: 4, through: 1, by: -1) {
      let source = file.path + ".\(number)"
      let destination = file.path + ".\(number + 1)"
      if Darwin.rename(source, destination) != 0 && errno != ENOENT {
        throw StoreError.storage(code: errno, operation: "rotate_log")
      }
    }
    if Darwin.rename(file.path, file.path + ".1") != 0 && errno != ENOENT {
      throw StoreError.storage(code: errno, operation: "rotate_log")
    }
  }
}

private struct LogRedactor: Sendable {
  let secretKey: NSRegularExpression
  let secretValue: NSRegularExpression
  let assignment: NSRegularExpression
  let url: NSRegularExpression

  init() throws {
    secretKey = try NSRegularExpression(
      pattern: "token|authorization|api[_-]?key|secret|password|credential",
      options: .caseInsensitive)
    secretValue = try NSRegularExpression(
      pattern: #"\b(sk-[A-Za-z0-9_-]{12,}|Bearer\s+[A-Za-z0-9._-]{12,}|[a-f0-9]{64})\b"#)
    assignment = try NSRegularExpression(
      pattern:
        #"\b(api[_-]?key|access[_-]?token|token|secret|password|passwd|pwd|auth)\b\s*[:=]\s*("[^"]*"|'[^']*'|[^\s,;]+)"#,
      options: .caseInsensitive)
    url = try NSRegularExpression(pattern: #"https?://[^\s"'<>]+"#, options: .caseInsensitive)
  }

  func redact(_ value: JSONValue) -> JSONValue {
    switch value {
    case .string(let raw):
      var text = raw
      for match in url.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
        guard let range = Range(match.range, in: text) else { return .string("[redacted]") }
        guard var components = URLComponents(string: String(text[range])) else {
          text.replaceSubrange(range, with: "[redacted]")
          continue
        }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        text.replaceSubrange(range, with: components.string ?? "[redacted]")
      }
      text = secretValue.stringByReplacingMatches(
        in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[redacted]")
      text = assignment.stringByReplacingMatches(
        in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1=[redacted]")
      return .string(text)
    case .array(let values):
      return .array(values.map(redact))
    case .object(let values):
      var safe: [String: JSONValue] = [:]
      safe.reserveCapacity(values.count)
      for (key, value) in values {
        let sensitive =
          secretKey.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
        safe[key] = sensitive ? .string("[redacted]") : redact(value)
      }
      return .object(safe)
    default:
      return value
    }
  }
}
