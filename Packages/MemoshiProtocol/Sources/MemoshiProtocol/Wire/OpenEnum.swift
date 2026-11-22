/// A protocol enum that stays open to values a newer peer may send.
///
/// Every protocol enum has known cases plus `case unknown(String)`. On the wire a value is its
/// lower-snake-case string (`needs_you`); in Swift it is a camelCase case (`.needsYou`). A value
/// this build does not know decodes as `.unknown(raw)` and encodes back unchanged
/// (protocol.md §3.5, events.md §10). Enums are open in clients and closed in the engine: the
/// generated schema lists only the known values.
public protocol OpenEnum: Codable, Hashable, Sendable, WireShaped {
  /// The known cases and their wire strings, in declaration order.
  static var wireTable: OpenEnumTable<Self> { get }

  /// The case that carries an unrecognized wire value.
  static func unknown(_ rawValue: String) -> Self

  /// The unrecognized wire value when this is `.unknown`, otherwise `nil`.
  var unknownRawValue: String? { get }
}

extension OpenEnum {
  /// The value's wire string.
  public var rawValue: String {
    unknownRawValue ?? Self.wireTable.rawValue(of: self)
  }

  /// Whether this build knows the value.
  public var isKnown: Bool { unknownRawValue == nil }

  /// The case for a wire string; `.unknown(rawValue)` when this build does not know it.
  public init(rawValue: String) {
    self = Self.wireTable.value(for: rawValue) ?? .unknown(rawValue)
  }

  /// Decodes the wire string. Unknown values become `.unknown(raw)` unless the decoder is
  /// strict (``CodingUserInfoKey/memoshiStrictDecoding``), as the engine is.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    guard let value = Self.wireTable.value(for: raw) else {
      if decoder.isStrictProtocolDecoding {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Unknown \(Self.self) value \"\(raw)\"")
      }
      self = .unknown(raw)
      return
    }
    self = value
  }

  /// Encodes the wire string. A known case missing from ``wireTable`` has none, so encoding
  /// it fails here instead of writing an empty string for the peer to reject.
  public func encode(to encoder: any Encoder) throws {
    let raw = rawValue
    guard !raw.isEmpty || !isKnown else {
      throw EncodingError.invalidValue(
        self,
        EncodingError.Context(
          codingPath: encoder.codingPath,
          debugDescription: "A \(Self.self) case is missing from its wireTable"))
    }
    var container = encoder.singleValueContainer()
    try container.encode(raw)
  }

  /// The known wire strings.
  public static var wireShape: WireShape { .stringEnum(wireTable.rawValues) }
}

/// The known cases of an ``OpenEnum`` and their wire strings.
public struct OpenEnumTable<Value: Hashable & Sendable>: Sendable {
  /// The known wire strings, in declaration order.
  public let rawValues: [String]
  private let rawValueByCase: [Value: String]
  private let caseByRawValue: [String: Value]

  /// Creates a table from `case: "wire_string"` pairs, in declaration order.
  public init(_ pairs: KeyValuePairs<Value, String>) {
    var rawValues: [String] = []
    var rawValueByCase: [Value: String] = [:]
    var caseByRawValue: [String: Value] = [:]
    for (value, raw) in pairs {
      rawValues.append(raw)
      rawValueByCase[value] = raw
      caseByRawValue[raw] = value
    }
    self.rawValues = rawValues
    self.rawValueByCase = rawValueByCase
    self.caseByRawValue = caseByRawValue
  }

  /// The wire string of a known case; empty for a case missing from the table.
  public func rawValue(of value: Value) -> String {
    rawValueByCase[value] ?? ""
  }

  /// The known case for a wire string.
  public func value(for rawValue: String) -> Value? {
    caseByRawValue[rawValue]
  }
}
