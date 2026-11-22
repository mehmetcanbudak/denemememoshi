import Synchronization

/// A value outside the limits its type declares.
public struct LimitError: Error, Hashable, Sendable, CustomStringConvertible {
  /// What is wrong, such as "Tier 7 is outside 0...5".
  public let description: String
}

// Each constrained field has a small value type that declares its limits once. The throwing
// initializer and strict decoding enforce them, so the engine builds and accepts only valid
// values; a lenient decoder keeps an out-of-limits value and reports it; and `wireShape` gives
// the same limits to the generated schema.

// MARK: - Integers

/// The allowed range of a ``BoundedInteger``.
public protocol IntegerBounds: Sendable {
  /// The allowed values.
  static var range: ClosedRange<Int> { get }
  /// The type's name in the schema, such as `Tier`.
  static var wireName: String { get }
}

/// An integer within a declared range.
public struct BoundedInteger<Bounds: IntegerBounds>: Hashable, Sendable, Codable,
  CustomStringConvertible, WireShaped, WireNamed
{
  /// The integer.
  public let rawValue: Int

  /// Validates and wraps an integer.
  public init(_ rawValue: Int) throws(LimitError) {
    if let violation = Self.violation(of: rawValue) {
      throw LimitError(description: violation)
    }
    self.rawValue = rawValue
  }

  fileprivate init(unchecked rawValue: Int) {
    self.rawValue = rawValue
  }

  /// Whether the value is within its range; only a lenient decoder keeps one that is not.
  public var isWithinLimits: Bool { Self.violation(of: rawValue) == nil }

  private static func violation(of value: Int) -> String? {
    guard !Bounds.range.contains(value) else { return nil }
    let range = "\(Bounds.range.lowerBound)...\(Bounds.range.upperBound)"
    return "\(Bounds.wireName) \(value) is outside \(range)"
  }

  /// Decodes the integer, enforcing its range as
  /// ``Decoder/handleConstraintViolation(_:wireType:)`` says.
  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(Int.self)
    if let violation = Self.violation(of: value) {
      try decoder.handleConstraintViolation(violation, wireType: Bounds.wireName)
    }
    self.init(unchecked: value)
  }

  /// Encodes the integer.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// The integer as text.
  public var description: String { String(rawValue) }

  /// The range as `minimum` and `maximum`.
  public static var wireShape: WireShape {
    .integer(minimum: Bounds.range.lowerBound, maximum: Bounds.range.upperBound)
  }

  /// The bounds' name.
  public static var wireName: String { Bounds.wireName }
}

/// A tool call's tier, T0 to T5 (object-model.md §4.19, policy.md).
public typealias Tier = BoundedInteger<TierBounds>
/// Bot-to-bot hops from the root of a delegation chain, at most 8 (object-model.md §3.3).
public typealias Hops = BoundedInteger<HopsBounds>
/// A page size, at most 200 (protocol.md §4).
public typealias PageLimit = BoundedInteger<PageLimitBounds>
/// A percentage, 0 to 100.
public typealias Percent = BoundedInteger<PercentBounds>
/// The event envelope's version, `1` in protocol version 1 (events.md §2, §10).
public typealias EnvelopeVersion = BoundedInteger<EnvelopeVersionBounds>

/// The bounds of ``Tier``: 0...5.
public enum TierBounds: IntegerBounds {
  /// 0...5.
  public static let range = 0...5
  /// `Tier`.
  public static let wireName = "Tier"
}

/// The bounds of ``Hops``: 0...8.
public enum HopsBounds: IntegerBounds {
  /// 0...8.
  public static let range = 0...8
  /// `Hops`.
  public static let wireName = "Hops"
}

/// The bounds of ``PageLimit``: 1...200.
public enum PageLimitBounds: IntegerBounds {
  /// 1...200.
  public static let range = 1...200
  /// `PageLimit`.
  public static let wireName = "PageLimit"
}

/// The bounds of ``Percent``: 0...100.
public enum PercentBounds: IntegerBounds {
  /// 0...100.
  public static let range = 0...100
  /// `Percent`.
  public static let wireName = "Percent"
}

/// The bounds of ``EnvelopeVersion``: exactly 1.
public enum EnvelopeVersionBounds: IntegerBounds {
  /// 1...1.
  public static let range = 1...1
  /// `EnvelopeVersion`.
  public static let wireName = "EnvelopeVersion"
}

extension BoundedInteger where Bounds == HopsBounds {
  /// No hops: the root of a delegation chain.
  public static var root: Hops { Hops(unchecked: 0) }
}

extension BoundedInteger where Bounds == EnvelopeVersionBounds {
  /// Version 1, the envelope this build writes.
  public static var current: EnvelopeVersion { EnvelopeVersion(unchecked: 1) }
}

// MARK: - Single-line text

/// The length limit of a ``BoundedText``.
public protocol TextBounds: Sendable {
  /// The most Unicode scalars allowed, the unit of JSON Schema's `maxLength`.
  static var maxLength: Int { get }
  /// The type's name in the schema, such as `Title`.
  static var wireName: String { get }
}

/// Single-line text with a length limit: `text(≤N)` in object-model.md §1.2.
public struct BoundedText<Bounds: TextBounds>: Hashable, Sendable, Codable,
  CustomStringConvertible, WireShaped, WireNamed
{
  /// The text.
  public let rawValue: String

  /// No carriage return or line feed.
  private static var singleLinePattern: String { "^[^\\r\\n]*$" }

  /// Validates and wraps text.
  public init(_ rawValue: String) throws(LimitError) {
    if let violation = Self.violation(of: rawValue) {
      throw LimitError(description: violation)
    }
    self.rawValue = rawValue
  }

  private init(unchecked rawValue: String) {
    self.rawValue = rawValue
  }

  /// Whether the text is within its limits; only a lenient decoder keeps text that is not.
  public var isWithinLimits: Bool { Self.violation(of: rawValue) == nil }

  private static func violation(of text: String) -> String? {
    let length = text.unicodeScalars.count
    if length > Bounds.maxLength {
      return "\(Bounds.wireName) has \(length) characters; the limit is \(Bounds.maxLength)"
    }
    if !PatternMatcher.wholeMatch(text, pattern: singleLinePattern) {
      return "\(Bounds.wireName) must be a single line"
    }
    return nil
  }

  /// Decodes the text, enforcing its limits as
  /// ``Decoder/handleConstraintViolation(_:wireType:)`` says.
  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    if let violation = Self.violation(of: text) {
      try decoder.handleConstraintViolation(violation, wireType: Bounds.wireName)
    }
    self.init(unchecked: text)
  }

  /// Encodes the text.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// The text.
  public var description: String { rawValue }

  /// The limit as `maxLength`, and the single line as a `pattern`.
  public static var wireShape: WireShape {
    .string(maxLength: Bounds.maxLength, pattern: singleLinePattern)
  }

  /// The bounds' name.
  public static var wireName: String { Bounds.wireName }
}

/// A task's or a card's title, at most 120 characters (object-model.md §4.7, §4.18).
public typealias Title = BoundedText<TitleBounds>
/// A task's one-line result, at most 500 characters (object-model.md §4.7).
public typealias Summary = BoundedText<SummaryBounds>
/// A device's name, at most 60 characters (object-model.md §4.26).
public typealias DeviceName = BoundedText<DeviceNameBounds>

/// The limit of ``Title``: 120.
public enum TitleBounds: TextBounds {
  /// 120.
  public static let maxLength = 120
  /// `Title`.
  public static let wireName = "Title"
}

/// The limit of ``Summary``: 500.
public enum SummaryBounds: TextBounds {
  /// 500.
  public static let maxLength = 500
  /// `Summary`.
  public static let wireName = "Summary"
}

/// The limit of ``DeviceName``: 60.
public enum DeviceNameBounds: TextBounds {
  /// 60.
  public static let maxLength = 60
  /// `DeviceName`.
  public static let wireName = "DeviceName"
}

// MARK: - Formatted strings

/// The format of a ``FormattedString``.
public protocol StringFormat: Sendable {
  /// An anchored regular expression the whole string must match, valid in both Swift and
  /// ECMAScript, so the schema's `pattern` and the Swift check are the same rule.
  static var pattern: String { get }
  /// The type's name in the schema, such as `HelloToken`.
  static var wireName: String { get }
}

/// A string in a declared format.
public struct FormattedString<Format: StringFormat>: Hashable, Sendable, Codable,
  CustomStringConvertible, WireShaped, WireNamed
{
  /// The string.
  public let rawValue: String

  /// Validates and wraps a string.
  public init(_ rawValue: String) throws(LimitError) {
    if let violation = Self.violation(of: rawValue) {
      throw LimitError(description: violation)
    }
    self.rawValue = rawValue
  }

  private init(unchecked rawValue: String) {
    self.rawValue = rawValue
  }

  /// Whether the string is in its format; only a lenient decoder keeps one that is not.
  public var isWithinLimits: Bool { Self.violation(of: rawValue) == nil }

  /// The violation's text never repeats the string: it may be a secret, such as a hello token
  /// with one wrong character, and the text reaches errors, diagnostics and the unified log.
  private static func violation(of text: String) -> String? {
    guard !PatternMatcher.wholeMatch(text, pattern: Format.pattern) else { return nil }
    let length = text.unicodeScalars.count
    return "\(Format.wireName) has \(length) characters and does not match \(Format.pattern)"
  }

  /// Decodes the string, enforcing its format as
  /// ``Decoder/handleConstraintViolation(_:wireType:)`` says.
  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    if let violation = Self.violation(of: text) {
      try decoder.handleConstraintViolation(violation, wireType: Format.wireName)
    }
    self.init(unchecked: text)
  }

  /// Encodes the string.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// The string.
  public var description: String { rawValue }

  /// The format as a `pattern`.
  public static var wireShape: WireShape { .string(maxLength: nil, pattern: Format.pattern) }

  /// The format's name.
  public static var wireName: String { Format.wireName }
}

/// The token `system.hello` presents: the 64 lowercase hex characters of
/// `run/memoshid.token` (protocol.md §3.3).
public typealias HelloToken = FormattedString<HelloTokenFormat>
/// A capability, `name.vN`, such as `events.focus.v1` (protocol.md §3.5).
public typealias Capability = FormattedString<CapabilityFormat>
/// A JSON-RPC request `id`: `c:<n>` from a client, `d:<n>` from the daemon (protocol.md §4).
public typealias JSONRPCID = FormattedString<JSONRPCIDFormat>
/// A model reference: `provider/model`, or `default` (object-model.md §4.3).
public typealias ModelName = FormattedString<ModelNameFormat>
/// Binary data as padded base64 (protocol.md §12.1).
public typealias Base64Bytes = FormattedString<Base64Format>
/// The identity of an engine's event log, stated in `system.hello` (protocol.md §3.3, D131).
/// Clients treat it as opaque and only compare it for equality.
public typealias LogID = FormattedString<LogIDFormat>

/// The format of ``HelloToken``.
public enum HelloTokenFormat: StringFormat {
  /// 64 lowercase hex characters.
  public static let pattern = "^[0-9a-f]{64}$"
  /// `HelloToken`.
  public static let wireName = "HelloToken"
}

/// The format of ``Capability``.
public enum CapabilityFormat: StringFormat {
  /// Lowercase dotted names ending in `.v` and a version number.
  public static let pattern = "^[a-z][a-z0-9]*(\\.[a-z][a-z0-9]*)*\\.v[1-9][0-9]*$"
  /// `Capability`.
  public static let wireName = "Capability"
}

/// The format of ``JSONRPCID``.
public enum JSONRPCIDFormat: StringFormat {
  /// `c:` or `d:` and a number.
  public static let pattern = "^[cd]:[0-9]+$"
  /// `JSONRPCID`.
  public static let wireName = "JSONRPCID"
}

/// The format of ``ModelName``.
public enum ModelNameFormat: StringFormat {
  /// `default`, or a provider and a model separated by a slash.
  public static let pattern = "^(default|[^/\\s]+/\\S+)$"
  /// `ModelName`.
  public static let wireName = "ModelName"
}

/// The format of ``LogID``.
public enum LogIDFormat: StringFormat {
  /// 1 to 64 letters, digits, underscores or hyphens.
  public static let pattern = "^[A-Za-z0-9_-]{1,64}$"
  /// `LogID`.
  public static let wireName = "LogID"
}

/// The format of ``Base64Bytes``.
public enum Base64Format: StringFormat {
  /// Standard base64 with padding.
  public static let pattern =
    "^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$"
  /// `Base64Bytes`.
  public static let wireName = "Base64Bytes"
}

// MARK: - Lists

/// The size limit of a ``BoundedList``.
public protocol ListBounds: Sendable {
  /// The most elements allowed.
  static var maxItems: Int { get }
  /// The type's name in the schema, such as `FocusList`.
  static var wireName: String { get }
}

/// A list with at most a declared number of elements.
public struct BoundedList<Element: Codable & Hashable & Sendable, Bounds: ListBounds>: Hashable,
  Sendable, Codable, WireShaped, WireNamed
{
  /// The elements.
  public let elements: [Element]

  /// Validates and wraps a list.
  public init(_ elements: [Element]) throws(LimitError) {
    if let violation = Self.violation(of: elements) {
      throw LimitError(description: violation)
    }
    self.elements = elements
  }

  private init(unchecked elements: [Element]) {
    self.elements = elements
  }

  /// Whether the list is within its limit; only a lenient decoder keeps one that is not.
  public var isWithinLimits: Bool { Self.violation(of: elements) == nil }

  private static func violation(of elements: [Element]) -> String? {
    guard elements.count > Bounds.maxItems else { return nil }
    return "\(Bounds.wireName) has \(elements.count) items; the limit is \(Bounds.maxItems)"
  }

  /// Decodes the list, enforcing its limit as
  /// ``Decoder/handleConstraintViolation(_:wireType:)`` says.
  public init(from decoder: any Decoder) throws {
    let elements = try decoder.singleValueContainer().decode([Element].self)
    if let violation = Self.violation(of: elements) {
      try decoder.handleConstraintViolation(violation, wireType: Bounds.wireName)
    }
    self.init(unchecked: elements)
  }

  /// Encodes the list.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(elements)
  }

  /// The limit as `maxItems`.
  public static var wireShape: WireShape {
    .array(element: Element.self, maxItems: Bounds.maxItems)
  }

  /// The bounds' name.
  public static var wireName: String { Bounds.wireName }
}

/// The conversations a connection focuses, at most 8 (protocol.md §5.1, §11).
public typealias FocusList = BoundedList<ConversationID, FocusListBounds>

/// The limit of ``FocusList``: 8.
public enum FocusListBounds: ListBounds {
  /// 8.
  public static let maxItems = 8
  /// `FocusList`.
  public static let wireName = "FocusList"
}

// MARK: - Pattern matching

/// Matches strings against the formats' patterns, compiling each pattern once.
private enum PatternMatcher {
  private static let compiled = Mutex<[String: Regex<AnyRegexOutput>]>([:])

  /// Whether the whole of `text` matches `pattern`, Unicode scalar by Unicode scalar as JSON
  /// Schema's ECMAScript patterns match. A pattern that does not compile matches nothing, so
  /// every value of its type fails validation and the tests catch it.
  static func wholeMatch(_ text: String, pattern: String) -> Bool {
    let regex: Regex<AnyRegexOutput>? = compiled.withLock { cache in
      if let regex = cache[pattern] {
        return regex
      }
      guard let regex = try? Regex(pattern).matchingSemantics(.unicodeScalar) else { return nil }
      cache[pattern] = regex
      return regex
    }
    guard let regex else { return false }
    return (try? regex.wholeMatch(in: text)) != nil
  }
}
