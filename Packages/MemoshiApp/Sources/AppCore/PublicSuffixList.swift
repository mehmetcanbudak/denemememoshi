import Foundation

/// The registrable domain (eTLD+1) of a host, from the bundled Public Suffix List, ICANN and
/// private sections (D136's site rule). The list is `Resources/public_suffix_list.dat`, the
/// unmodified copy published at https://publicsuffix.org/list/public_suffix_list.dat (MPL-2.0;
/// provenance in NOTICE). Update: replace the file with a newly published copy and change
/// `bundledSHA256` and `bundledVersion` to its digest and `// VERSION:` line.
public struct PublicSuffixList: Sendable {
  /// SHA-256 of the bundled file.
  public static let bundledSHA256 =
    "8576b335b871dea99dc0fccd04138311bd43f7a8da256c31bf964f11e2f7c179"
  /// The bundled file's `// VERSION:` line (publicsuffix/list commit 71c235dd).
  public static let bundledVersion = "2026-11-13_14-44-35_UTC"

  private let rules: Set<String>
  /// `*.example` rules, stored as `example`.
  private let wildcards: Set<String>
  /// `!www.example` rules, stored as `www.example`.
  private let exceptions: Set<String>

  /// Parses list text: one rule per line, comments and blank lines skipped, IDN rules encoded
  /// as hosts arrive from URLs.
  public init(text: String) {
    var rules = Set<String>()
    var wildcards = Set<String>()
    var exceptions = Set<String>()
    for line in text.split(whereSeparator: \.isNewline) {
      guard let word = line.split(whereSeparator: \.isWhitespace).first, !word.hasPrefix("//")
      else { continue }
      if word.hasPrefix("!") {
        if let host = Self.asciiHost(String(word.dropFirst())) { exceptions.insert(host) }
      } else if word.hasPrefix("*.") {
        if let host = Self.asciiHost(String(word.dropFirst(2))) { wildcards.insert(host) }
      } else if let host = Self.asciiHost(String(word)) {
        rules.insert(host)
      }
    }
    self.rules = rules
    self.wildcards = wildcards
    self.exceptions = exceptions
  }

  /// The bundled file's bytes.
  public static func bundledData() throws -> Data {
    guard let url = Bundle.module.url(forResource: "public_suffix_list", withExtension: "dat")
    else { throw CocoaError(.fileNoSuchFile) }
    return try Data(contentsOf: url)
  }

  /// The bundled list, parsed once per process. A missing or unreadable file throws.
  public static func bundled() throws -> PublicSuffixList {
    guard let shared else { throw CocoaError(.fileReadCorruptFile) }
    return shared
  }

  private static let shared: PublicSuffixList? = try? PublicSuffixList(
    text: String(decoding: bundledData(), as: UTF8.self))

  /// The registrable domain of `host`, or nil when the host is itself a public suffix, an IP
  /// address, or not a valid host name (empty labels, a leading dot).
  public func registrableDomain(of host: String) -> String? {
    guard !Self.isIPAddress(host), let ascii = Self.asciiHost(host) else { return nil }
    let labels = ascii.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    func joined(from index: Int) -> String { labels[index...].joined(separator: ".") }
    // An exception rule prevails over every other matching rule; its public suffix is the rule
    // without its leftmost label.
    var suffixStart: Int?
    for index in labels.indices where exceptions.contains(joined(from: index)) {
      suffixStart = index + 1
      break
    }
    if suffixStart == nil {
      for index in labels.indices {
        let wildcard = index + 1 < labels.count && wildcards.contains(joined(from: index + 1))
        if rules.contains(joined(from: index)) || wildcard {
          suffixStart = index
          break
        }
      }
    }
    // The default rule `*`: the last label is the public suffix.
    let start = suffixStart ?? labels.count - 1
    guard start > 0 else { return nil }
    return joined(from: start - 1)
  }

  /// Whether `host` is an IP address, not a domain name: an IPv6 literal, with or without
  /// brackets, or a host whose last label is a number (decimal, or hexadecimal after `0x`),
  /// which URL parsers read as an IPv4 address. An address has no public suffix and no
  /// registrable domain.
  public static func isIPAddress(_ host: String) -> Bool {
    if host.contains(":") { return true }
    guard let last = host.lowercased().split(separator: ".").last else { return false }
    if last.allSatisfy({ ("0"..."9").contains($0) }) { return true }
    return last.hasPrefix("0x") && last.dropFirst(2).allSatisfy(\.isHexDigit)
  }

  /// A host lowercased, with each non-ASCII label Punycode-encoded (`xn--`), as URL hosts are
  /// given. Nil for an empty host or an empty label.
  public static func asciiHost(_ host: String) -> String? {
    let labels = host.lowercased().split(separator: ".", omittingEmptySubsequences: false)
    guard !host.isEmpty, labels.allSatisfy({ !$0.isEmpty }) else { return nil }
    var encoded: [String] = []
    for label in labels {
      guard let ascii = punycode(String(label)) else { return nil }
      encoded.append(ascii)
    }
    return encoded.joined(separator: ".")
  }

  /// RFC 3492 encoding of one label; an ASCII label is returned unchanged.
  static func punycode(_ label: String) -> String? {
    let input = label.unicodeScalars.map(\.value)
    guard input.contains(where: { $0 >= 0x80 }) else { return label }
    let base = 36
    let tMin = 1
    let tMax = 26
    func digit(_ value: Int) -> Character {
      Character(UnicodeScalar(UInt8(value < 26 ? 97 + value : 22 + value)))
    }
    func adapt(_ delta: Int, _ points: Int, _ first: Bool) -> Int {
      var delta = first ? delta / 700 : delta / 2
      delta += delta / points
      var k = 0
      while delta > ((base - tMin) * tMax) / 2 {
        delta /= base - tMin
        k += base
      }
      return k + (base - tMin + 1) * delta / (delta + 38)
    }
    var output = String(input.filter { $0 < 0x80 }.map { Character(UnicodeScalar(UInt8($0))) })
    let basic = output.count
    if basic > 0 { output.append("-") }
    var n = 128
    var delta = 0
    var bias = 72
    var handled = basic
    while handled < input.count {
      guard let next = input.map(Int.init).filter({ $0 >= n }).min() else { return nil }
      let (step, overflow) = (next - n).multipliedReportingOverflow(by: handled + 1)
      guard !overflow else { return nil }
      delta += step
      n = next
      for value in input.map(Int.init) {
        if value < n { delta += 1 }
        guard value == n else { continue }
        var q = delta
        var k = base
        while true {
          let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
          if q < t { break }
          output.append(digit(t + (q - t) % (base - t)))
          q = (q - t) / (base - t)
          k += base
        }
        output.append(digit(q))
        bias = adapt(delta, handled + 1, handled == basic)
        delta = 0
        handled += 1
      }
      delta += 1
      n += 1
    }
    return "xn--" + output
  }
}
