import Foundation
import MemoshiProtocol
import PiCore
import PiDurable

struct ScrubbedToolOutput: Sendable {
  let result: PiDurable.ToolExecutionResult
  let count: Int64
  let kinds: [String]
}

/// Actor-confined in ProviderCredentials. Retained secret variants are for redaction only,
/// never credential reuse; HTTP authorization still requires a fresh, unexpired broker lease.
struct ToolOutputScrubber {
  private var secrets = Set<String>()
  private var bytes: [Data] = []
  private var hexValues: [String] = []
  private var variants: [String] = []
  private let matchers: Result<[String: NSRegularExpression], any Error> = Result {
    try [
      "provider_key": NSRegularExpression(pattern: #"\b(?:sk|pk)[-_][A-Za-z0-9_-]{16,}\b"#),
      "jwt": NSRegularExpression(
        pattern: #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#),
      "private_key": NSRegularExpression(
        pattern: #"(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----"#),
      "credential_assignment": NSRegularExpression(
        pattern:
          #"(?i)(?:api[_-]?key|access[_-]?token|password|secret)\s*[:=]\s*[\"']?[A-Za-z0-9_+/.=-]{16,}"#
      ),
      "encoded": NSRegularExpression(pattern: #"[A-Za-z0-9_+/-]{16,}={0,2}"#),
      "hex": NSRegularExpression(pattern: #"[A-Fa-f0-9]{16,}"#),
      "url": NSRegularExpression(pattern: #"https?://[^\s\"'<>]+"#),
    ]
  }

  mutating func register(_ value: String) {
    guard !value.isEmpty, secrets.insert(value).inserted else { return }
    let data = Data(value.utf8)
    bytes.append(data)
    let base64 = data.base64EncodedString()
    let hex = data.map { String(format: "%02x", $0) }.joined()
    hexValues.append(hex)
    var additions = Set([value, base64])
    let base64URL = base64.replacingOccurrences(of: "+", with: "-").replacingOccurrences(
      of: "/", with: "_")
    additions.insert(base64URL)
    additions.insert(base64URL.replacingOccurrences(of: "=", with: ""))
    additions.insert(hex)
    additions.insert(hex.uppercased())
    additions.insert(value.utf16.map { String(format: "\\u%04x", $0) }.joined())
    if let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
      additions.insert(encoded)
    }
    if let encoded = try? JSONEncoder().encode(value) {
      additions.insert(String(decoding: encoded.dropFirst().dropLast(), as: UTF8.self))
    }
    variants.append(contentsOf: additions.sorted { $0.utf16.count > $1.utf16.count })
  }

  func toolResult(_ result: PiDurable.ToolExecutionResult) -> ScrubbedToolOutput {
    do {
      var count: Int64 = 0
      var kinds = Set<String>()
      let value = try PiCore.JSONValue(encoding: result)
      let scrubbed = try visit(value, metadata: false, count: &count, kinds: &kinds)
      return ScrubbedToolOutput(
        result: count == 0 ? result : try scrubbed.decode(PiDurable.ToolExecutionResult.self),
        count: count, kinds: kinds.sorted())
    } catch {
      return ScrubbedToolOutput(result: Self.withheld, count: 1, kinds: ["withheld"])
    }
  }

  func metadata(_ value: MemoshiProtocol.JSONValue) throws -> MemoshiProtocol.JSONValue {
    var count: Int64 = 0
    var kinds = Set<String>()
    return try ToolJSON.application(
      visit(ToolJSON.sdk(value), metadata: true, count: &count, kinds: &kinds))
  }

  static var withheld: PiDurable.ToolExecutionResult {
    .init(
      output: [
        .text(.init(text: "Tool output was withheld because it could not be safely scrubbed."))
      ], isError: true)
  }

  private func visit(
    _ value: PiCore.JSONValue, metadata: Bool, count: inout Int64, kinds: inout Set<String>
  ) throws -> PiCore.JSONValue {
    switch value {
    case .string(let value):
      return .string(try text(value, metadata: metadata, count: &count, kinds: &kinds))
    case .stringUTF16(let value):
      guard let native = value.nativeString else { throw RuntimeToolError.invalidArguments }
      return .string(try text(native, metadata: metadata, count: &count, kinds: &kinds))
    case .array(let values):
      var output = values
      for index in values.indices {
        let before = count
        let cleaned = try visit(values[index], metadata: metadata, count: &count, kinds: &kinds)
        if count != before { output[index] = cleaned }
      }
      return .array(output)
    case .object(let values):
      var output = values
      for (key, child) in values {
        guard let native = key.nativeString else { throw RuntimeToolError.invalidArguments }
        let before = count
        let cleanedKey = try text(native, metadata: false, count: &count, kinds: &kinds)
        let normalized = native.lowercased().replacingOccurrences(of: "_", with: "")
          .replacingOccurrences(of: "-", with: "")
        let cleaned: PiCore.JSONValue
        if ["apikey", "accesstoken", "password", "secret", "authorization"].contains(normalized),
          child.stringValue?.isEmpty == false
        {
          cleaned = .string("[redacted]")
          count += 1
          kinds.insert("credential_field")
        } else {
          cleaned = try visit(child, metadata: metadata, count: &count, kinds: &kinds)
        }
        if cleanedKey != native {
          guard output[cleanedKey] == nil else { throw RuntimeToolError.invalidArguments }
          output.removeValue(forKey: key)
          output[cleanedKey] = cleaned
        } else if count != before {
          output[key] = cleaned
        }
      }
      return .object(output)
    default: return value
    }
  }

  private func text(
    _ value: String, metadata: Bool, count: inout Int64, kinds: inout Set<String>
  ) throws -> String {
    let expressions = try matchers.get()
    let output = NSMutableString(string: value)
    for variant in variants where !variant.isEmpty {
      var offset = 0
      while offset < output.length {
        let range = output.range(
          of: variant, options: [.literal],
          range: NSRange(location: offset, length: output.length - offset))
        if range.location == NSNotFound { break }
        output.replaceCharacters(in: range, with: "[redacted]")
        offset = range.location + 10
        count += 1
        kinds.insert("released_secret")
      }
    }
    if output.contains("%"),
      case let decoded = Self.percentDecoded(output as String),
      secrets.contains(where: { decoded.contains($0) })
    {
      count += 1
      kinds.insert("url_encoded_secret")
      return "[redacted]"
    }
    for kind in ["encoded", "hex", "provider_key", "jwt", "private_key", "credential_assignment"] {
      guard let expression = expressions[kind] else { throw RuntimeToolError.unavailable }
      let source = output as String
      for match in expression.matches(
        in: source, range: NSRange(location: 0, length: output.length)
      ).reversed() {
        let candidate = output.substring(with: match.range)
        let redact: Bool
        if kind == "encoded" {
          var encoded = candidate.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
            of: "_", with: "/")
          let remainder = encoded.utf8.count % 4
          if remainder != 0 { encoded += String(repeating: "=", count: 4 - remainder) }
          if let decoded = Data(base64Encoded: encoded) {
            redact = bytes.contains { decoded.range(of: $0) != nil }
          } else {
            redact = false
          }
        } else if kind == "hex" {
          let normalized = candidate.lowercased()
          redact = hexValues.contains { normalized.contains($0) }
        } else {
          redact = true
        }
        if redact {
          output.replaceCharacters(in: match.range, with: "[redacted]")
          count += 1
          kinds.insert(kind)
        }
      }
    }
    if metadata {
      guard let expression = expressions["url"] else { throw RuntimeToolError.unavailable }
      let source = output as String
      for match in expression.matches(
        in: source, range: NSRange(location: 0, length: output.length)
      ).reversed() {
        let candidate = output.substring(with: match.range)
        guard var components = URLComponents(string: candidate) else {
          throw RuntimeToolError.invalidArguments
        }
        if components.query != nil || components.fragment != nil || components.user != nil
          || components.password != nil
        {
          components.query = nil
          components.fragment = nil
          components.user = nil
          components.password = nil
          guard let sanitized = components.string else { throw RuntimeToolError.invalidArguments }
          output.replaceCharacters(in: match.range, with: sanitized)
          count += 1
          kinds.insert("url_metadata")
        }
      }
    }
    return output as String
  }

  /// Decodes every valid `%XX` and keeps any other `%` as written. Foundation's decoder
  /// returns nil for the whole string after one stray `%`, which would skip the check.
  private static func percentDecoded(_ value: String) -> String {
    func digit(_ byte: UInt8) -> UInt8? {
      switch byte {
      case 0x30...0x39: byte - 0x30
      case 0x41...0x46: byte - 0x41 + 10
      case 0x61...0x66: byte - 0x61 + 10
      default: nil
      }
    }
    let source = Array(value.utf8)
    var decoded: [UInt8] = []
    decoded.reserveCapacity(source.count)
    var index = 0
    while index < source.count {
      if source[index] == 0x25, index + 2 < source.count, let high = digit(source[index + 1]),
        let low = digit(source[index + 2])
      {
        decoded.append(high << 4 | low)
        index += 3
      } else {
        decoded.append(source[index])
        index += 1
      }
    }
    return String(decoding: decoded, as: UTF8.self)
  }
}
