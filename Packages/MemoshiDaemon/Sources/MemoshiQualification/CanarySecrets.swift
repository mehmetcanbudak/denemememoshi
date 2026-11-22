import CryptoKit
import Foundation

/// A per-run, high-entropy synthetic secret with a recognizable prefix. Its value exists only in
/// memory and in the explicitly declared source file it stands for; any other occurrence on disk
/// is a leak.
package struct Canary: Hashable, Sendable {
  /// Every canary starts with this prefix, so a manual search can find stray copies too.
  package static let prefix = "mqcanary_"

  /// What the canary stands for, such as `provider-bearer`; never secret.
  package let label: String
  /// The secret value. Never log or persist it outside its declared source file.
  package let value: String

  package init(label: String, value: String) {
    self.label = label
    self.value = value
  }

  /// Draws 40 base62 characters (about 238 bits) from the system generator. The `/` and `+`
  /// separators are valid bearer-token characters that make the JSON-escaped and
  /// percent-encoded forms differ from the raw form, so the scanner checks them meaningfully.
  package static func generate(label: String) -> Canary {
    var generator = SystemRandomNumberGenerator()
    let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    func block(_ count: Int) -> String {
      String((0..<count).map { _ in alphabet[Int.random(in: 0..<62, using: &generator)] })
    }
    return Canary(label: label, value: prefix + block(24) + "/" + block(8) + "+" + block(8))
  }

  /// A short nonsecret digest prefix that identifies the canary in reports.
  package var fingerprint: String {
    SHA256.hash(data: Data(value.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
  }

  /// Every byte sequence whose presence on disk reveals this canary.
  package var needles: [CanaryNeedle] {
    let raw = Array(value.utf8)
    var needles: [CanaryNeedle] = [CanaryNeedle(encoding: "raw", bytes: raw)]
    func add(_ encoding: String, _ text: String) {
      let bytes = Array(text.utf8)
      guard !needles.contains(where: { $0.bytes == bytes }) else { return }
      needles.append(CanaryNeedle(encoding: encoding, bytes: bytes))
    }
    add("json-escaped-slash", value.replacingOccurrences(of: "/", with: "\\/"))
    add("json-unicode-lower", raw.map { String(format: "\\u%04x", $0) }.joined())
    add("json-unicode-upper", raw.map { String(format: "\\u%04X", $0) }.joined())
    // RFC 3986 unreserved characters stay literal in the reserved-only form.
    let unreserved = Set(
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".unicodeScalars)
    for (name, format) in [("lower", "%%%02x"), ("upper", "%%%02X")] {
      add("percent-all-" + name, raw.map { String(format: format, $0) }.joined())
      add(
        "percent-reserved-" + name,
        value.unicodeScalars.map { scalar in
          unreserved.contains(scalar) ? String(scalar) : String(format: format, scalar.value)
        }.joined())
    }
    for (index, core) in Self.base64Cores(raw).enumerated() {
      add("base64-shift-\(index)", core)
      add(
        "base64url-shift-\(index)",
        core.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_"))
    }
    add("hex-lower", raw.map { String(format: "%02x", $0) }.joined())
    add("hex-upper", raw.map { String(format: "%02X", $0) }.joined())
    return needles
  }

  /// Base64 output depends on where the secret starts inside the encoded stream. For each of the
  /// three byte alignments, keep only the 4-character groups made entirely of secret bytes: any
  /// unwrapped base64 encoding that contains the secret contains one of these cores.
  static func base64Cores(_ bytes: [UInt8]) -> [String] {
    (0..<3).map { shift in
      let encoded = Array(Data([UInt8](repeating: 0, count: shift) + bytes).base64EncodedString())
      let first = shift == 0 ? 0 : 1
      let end = (shift + bytes.count) / 3
      guard end > first else { return "" }
      return String(encoded[(4 * first)..<(4 * end)])
    }
  }
}

/// One encoded form of a canary.
package struct CanaryNeedle: Hashable, Sendable {
  /// Stable encoding label such as `base64url-shift-2`.
  package let encoding: String
  /// The exact bytes searched for.
  package let bytes: [UInt8]
}

/// One occurrence of a canary form on disk.
package struct CanaryHit: Codable, Equatable, Sendable {
  /// The canary label, never its value.
  package let canary: String
  /// The canary's nonsecret fingerprint.
  package let fingerprint: String
  /// The matched encoding.
  package let encoding: String
  /// The file path relative to its scan root, prefixed by the root's index.
  package let path: String
  /// Byte offset in the file, or -1 when the path name itself contains the form.
  package let offset: Int
}

/// What a scan covered and found. Zero hits is the only passing result.
package struct CanaryScanReport: Codable, Equatable, Sendable {
  /// Regular files read as raw bytes.
  package var filesScanned = 0
  /// Total bytes read.
  package var bytesScanned = 0
  /// Every occurrence found.
  package var hits: [CanaryHit] = []
  /// Declared secret source files skipped by exact path.
  package var excluded: [String] = []
  /// Symbolic links and special files, which are never followed or read.
  package var skipped: [String] = []

  package init() {}

  /// Merges another scan's coverage and findings.
  package mutating func merge(_ other: CanaryScanReport) {
    filesScanned += other.filesScanned
    bytesScanned += other.bytesScanned
    hits += other.hits
    excluded += other.excluded
    skipped += other.skipped
  }
}

/// Searches files as raw bytes (SQLite databases, WAL/SHM files, logs, JSONL transcripts and
/// diagnostics alike) for every encoded form of the given canaries. Symbolic links are not
/// followed. Compressed or MIME-wrapped encodings are not decoded. A root that is missing or
/// cannot be enumerated fails the scan: what was not read is never reported as clean.
package struct CanaryScanner: Sendable {
  private let canaries: [Canary]
  private let needles: [(Canary, CanaryNeedle)]

  /// Refuses a canary without a value: an empty needle matches nothing, so its scan would
  /// always look clean.
  package init(canaries: [Canary]) throws {
    guard canaries.allSatisfy({ !$0.value.isEmpty }) else {
      throw DriverError.invalid("Canary value is empty")
    }
    self.canaries = canaries
    needles = canaries.flatMap { canary in canary.needles.map { (canary, $0) } }
  }

  /// Scans every regular file below each root (or the root itself when it is a file), except
  /// paths in `excluding`, which must name declared secret source files exactly.
  package func scan(_ roots: [URL], excluding: Set<String> = []) throws -> CanaryScanReport {
    var report = CanaryScanReport()
    let excluded = Set(excluding.map { Self.canonical(URL(fileURLWithPath: $0)) })
    for (index, root) in roots.enumerated() {
      let root = URL(fileURLWithPath: Self.canonical(root))
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
        throw DriverError.invalid("Scan root \(index) does not exist")
      }
      let files: [URL]
      if isDirectory.boolValue {
        var unreadable = false
        guard
          let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in
              unreadable = true
              return false
            })
        else { throw DriverError.invalid("Scan root \(index) cannot be enumerated") }
        files = enumerator.compactMap { $0 as? URL }
        guard !unreadable else {
          throw DriverError.invalid("Scan root \(index) has an unreadable directory")
        }
      } else {
        files = [root]
      }
      for file in files {
        let path = Self.canonical(file)
        let relative =
          "\(index):"
          + (path.hasPrefix(root.path) ? String(path.dropFirst(root.path.count)) : path)
        try scanName(relative, into: &report)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true {
          report.skipped.append(relative)
          continue
        }
        guard values.isRegularFile == true else { continue }
        if excluded.contains(path) {
          report.excluded.append(relative)
          continue
        }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        report.filesScanned += 1
        report.bytesScanned += data.count
        scanBytes(data, path: relative, into: &report)
      }
    }
    return report
  }

  /// The path with its parent directories' symlinks resolved (`/tmp` → `/private/tmp`) but not
  /// the final component, so a symlink is compared and reported as itself.
  static func canonical(_ url: URL) -> String {
    let standardized = url.standardizedFileURL
    return standardized.deletingLastPathComponent().resolvingSymlinksInPath()
      .appendingPathComponent(standardized.lastPathComponent).path
  }

  /// Scans bytes that are not files, such as a captured stream.
  package func scanBytes(_ data: Data, path: String, into report: inout CanaryScanReport) {
    for (canary, needle) in needles {
      let pattern = Data(needle.bytes)
      var start = data.startIndex
      while start < data.endIndex,
        let range = data.range(of: pattern, options: [], in: start..<data.endIndex)
      {
        report.hits.append(
          CanaryHit(
            canary: canary.label, fingerprint: canary.fingerprint, encoding: needle.encoding,
            path: path, offset: range.lowerBound - data.startIndex))
        start = range.lowerBound + 1
      }
    }
  }

  private func scanName(_ name: String, into report: inout CanaryScanReport) throws {
    var found = CanaryScanReport()
    scanBytes(Data(name.utf8), path: name, into: &found)
    report.hits += found.hits.map {
      CanaryHit(
        canary: $0.canary, fingerprint: $0.fingerprint, encoding: $0.encoding, path: $0.path,
        offset: -1)
    }
  }
}
