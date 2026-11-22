import Foundation

/// Any JSON value, kept exactly as received.
///
/// Fields whose shape the protocol leaves open use this type: an argument preview, a card's
/// display payload, a forwarded intent's params. An unknown event or device message also keeps
/// its raw payload in it, so nothing a newer peer sends is lost.
public enum JSONValue: Hashable, Sendable {
  case null
  case bool(Bool)
  /// A number that fits in 64 bits without a fraction.
  case integer(Int64)
  /// Any other number.
  case double(Double)
  case string(String)
  case array([JSONValue])
  /// An object. Key order carries no meaning.
  case object([String: JSONValue])
}

extension JSONValue: Codable {
  /// Decodes any JSON value. Integers stay exact; other numbers become `double`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
    }
  }

  /// Encodes the value as the JSON it holds.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }
}

extension JSONValue: WireShaped {
  /// Any JSON value is allowed.
  public static var wireShape: WireShape { .anyJSON }
}

extension JSONValue: ExpressibleByNilLiteral {
  /// Creates `null`.
  public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
  /// Creates a boolean.
  public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
  /// Creates an integer.
  public init(integerLiteral value: Int64) { self = .integer(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
  /// Creates a non-integer number.
  public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
  /// Creates a string.
  public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
  /// Creates an array.
  public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
  /// Creates an object. A repeated key keeps its last value.
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(elements) { _, last in last })
  }
}

extension JSONValue {
  /// Parses UTF-8 JSON text.
  public static func parse(_ data: Data) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: data)
  }

  /// The value as canonical JSON text: object keys sorted by their UTF-8 bytes, two-space
  /// indentation, `": "` between a key and its value, and a trailing newline. Equal values
  /// always produce identical bytes, which is what fixtures and the committed schema use.
  public var canonicalText: String {
    var output = ""
    write(into: &output, indentation: 0)
    output.append("\n")
    return output
  }

  private func write(into output: inout String, indentation: Int) {
    switch self {
    case .null: output.append("null")
    case .bool(let value): output.append(value ? "true" : "false")
    case .integer(let value): output.append(String(value))
    case .double(let value): output.append(String(describing: value))
    case .string(let value): Self.writeString(value, into: &output)
    case .array(let elements):
      guard !elements.isEmpty else {
        output.append("[]")
        return
      }
      output.append("[\n")
      for (index, element) in elements.enumerated() {
        output.append(String(repeating: " ", count: indentation + 2))
        element.write(into: &output, indentation: indentation + 2)
        output.append(index == elements.count - 1 ? "\n" : ",\n")
      }
      output.append(String(repeating: " ", count: indentation))
      output.append("]")
    case .object(let members):
      guard !members.isEmpty else {
        output.append("{}")
        return
      }
      let keys = members.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
      output.append("{\n")
      for (index, key) in keys.enumerated() {
        output.append(String(repeating: " ", count: indentation + 2))
        Self.writeString(key, into: &output)
        output.append(": ")
        members[key, default: .null].write(into: &output, indentation: indentation + 2)
        output.append(index == keys.count - 1 ? "\n" : ",\n")
      }
      output.append(String(repeating: " ", count: indentation))
      output.append("}")
    }
  }

  private static func writeString(_ value: String, into output: inout String) {
    output.append("\"")
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\"": output.append("\\\"")
      case "\\": output.append("\\\\")
      case "\n": output.append("\\n")
      case "\r": output.append("\\r")
      case "\t": output.append("\\t")
      case "\u{08}": output.append("\\b")
      case "\u{0C}": output.append("\\f")
      default:
        if scalar.value < 0x20 {
          let hex = String(scalar.value, radix: 16)
          output.append("\\u" + String(repeating: "0", count: 4 - hex.count) + hex)
        } else {
          output.unicodeScalars.append(scalar)
        }
      }
    }
    output.append("\"")
  }
}
