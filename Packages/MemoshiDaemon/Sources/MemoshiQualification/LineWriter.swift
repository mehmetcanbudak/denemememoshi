import Foundation
import Synchronization

/// Writes whole JSON lines to one file handle; concurrent writers never interleave a line.
package final class LineWriter: Sendable {
  /// The process's standard output.
  package static let standardOutput = LineWriter(handle: .standardOutput)
  /// The process's standard error.
  package static let standardError = LineWriter(handle: .standardError)

  private let handle: Mutex<FileHandle>

  package init(handle: FileHandle) {
    self.handle = Mutex(handle)
  }

  /// Writes one value as a single JSON line.
  package func write(_ value: some Encodable) {
    guard var line = try? JSONLines.encoder.encode(value) else { return }
    line.append(UInt8(ascii: "\n"))
    handle.withLock { try? $0.write(contentsOf: line) }
  }

  /// Writes a flat string event, such as `{"event":"listening","port":"5"}`.
  package func emit(_ fields: [String: String]) { write(fields) }

  /// Writes a plain text line, for human progress on standard error.
  package func text(_ message: String) {
    handle.withLock { try? $0.write(contentsOf: Data((message + "\n").utf8)) }
  }
}

/// Reads newline-terminated lines from a descriptor on its own thread. Foundation's
/// `FileHandle.AsyncBytes` serializes every handle's blocking reads on one process-wide queue,
/// so a quiet pipe would starve every other pipe's reader; each stream here blocks only itself.
package enum LineStream {
  /// The lines read until EOF or a read error; `closeAtEnd` closes the descriptor afterwards.
  package static func lines(from descriptor: Int32, closeAtEnd: Bool) -> AsyncStream<String> {
    let (stream, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .unbounded)
    let thread = Thread {
      var pending = Data()
      var buffer = [UInt8](repeating: 0, count: 65_536)
      while true {
        let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { break }
        pending.append(contentsOf: buffer[0..<count])
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
          continuation.yield(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
          pending.removeSubrange(pending.startIndex...newline)
        }
      }
      if !pending.isEmpty { continuation.yield(String(decoding: pending, as: UTF8.self)) }
      if closeAtEnd { close(descriptor) }
      continuation.finish()
    }
    thread.start()
    return stream
  }
}

/// The harness's JSON line conventions: sorted keys and unescaped slashes.
package enum JSONLines {
  /// A fresh encoder with the harness's output formatting.
  package static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  /// Pretty, sorted output for report files.
  package static var prettyEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
    return encoder
  }
}
