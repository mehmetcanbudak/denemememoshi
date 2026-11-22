import MemoshiProtocol

/// A `Decoder` that feeds a type's `init(from:)` well-formed stand-in values instead of JSON.
///
/// In `record` mode it notes every key the type decodes, with the key's type and whether it is
/// required (`decode`) or optional (`decodeIfPresent`); a `decode` of an `Optional` means
/// required but nullable. In `placeholder` mode it only answers, so the generator can build a
/// value to return to the type being recorded. In `sample` mode it answers a single value: a
/// string a ``WireShaped`` type accepts, or `null`.
struct ShapeDecoder: Decoder {
  enum Mode {
    case record(ObjectRecorder)
    case placeholder(overrides: [String: String])
    /// A single string, or `nil` for JSON `null`.
    case sample(String?)
  }

  let generator: SchemaGenerator
  let mode: Mode
  var codingPath: [any CodingKey] = []

  /// Unknown-event diagnostics raised while recording are expected and discarded.
  var userInfo: [CodingUserInfoKey: Any] {
    [.memoshiDiagnostics: DiscardingDiagnosticsSink()]
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    switch mode {
    case .record(let recorder):
      recorder.usedKeyedContainer = true
      return KeyedDecodingContainer(
        ShapeKeyedContainer<Key>(generator: generator, recorder: recorder, overrides: [:]))
    case .placeholder(let overrides):
      return KeyedDecodingContainer(
        ShapeKeyedContainer<Key>(generator: generator, recorder: nil, overrides: overrides))
    case .sample:
      throw SchemaGenerationError(description: "A sampled value has no keyed container")
    }
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    throw SchemaGenerationError(
      description: "Unkeyed containers are not supported; use Array properties")
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    ShapeSingleValueContainer(generator: generator, mode: mode)
  }
}

private final class DiscardingDiagnosticsSink: ProtocolDiagnosticsSink {
  func report(_ diagnostic: ProtocolDiagnostic) {}
}

private struct ShapeKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let generator: SchemaGenerator
  let recorder: ObjectRecorder?
  let overrides: [String: String]
  var codingPath: [any CodingKey] = []
  var allKeys: [Key] { [] }

  init(generator: SchemaGenerator, recorder: ObjectRecorder?, overrides: [String: String]) {
    self.generator = generator
    self.recorder = recorder
    self.overrides = overrides
  }

  func contains(_ key: Key) -> Bool { false }

  func decodeNil(forKey key: Key) throws -> Bool { false }

  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    if let override = overrides[key.stringValue], let value = override as? T {
      return value
    }
    if let recorder {
      recorder.record(key: key.stringValue, node: try generator.node(for: T.self), isRequired: true)
    }
    return try generator.placeholder(T.self)
  }

  func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
    if let recorder {
      recorder.record(
        key: key.stringValue, node: try generator.node(for: T.self), isRequired: false)
    }
    return nil
  }

  func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try decode(type, key) }
  func decode(_ type: String.Type, forKey key: Key) throws -> String { try decode(type, key) }
  func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try decode(type, key) }
  func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try decode(type, key) }
  func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try decode(type, key) }
  func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try decode(type, key) }
  func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try decode(type, key) }
  func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try decode(type, key) }
  func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try decode(type, key) }
  func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try decode(type, key) }
  func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try decode(type, key) }
  func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try decode(type, key) }
  func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try decode(type, key) }
  func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try decode(type, key) }

  func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: Float.Type, forKey key: Key) throws -> Float? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: Int8.Type, forKey key: Key) throws -> Int8? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: Int16.Type, forKey key: Key) throws -> Int16? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: Int32.Type, forKey key: Key) throws -> Int32? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws -> Int64? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: UInt.Type, forKey key: Key) throws -> UInt? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: UInt8.Type, forKey key: Key) throws -> UInt8? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: UInt16.Type, forKey key: Key) throws -> UInt16? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: UInt32.Type, forKey key: Key) throws -> UInt32? {
    try decodeIfPresent(type, key)
  }
  func decodeIfPresent(_ type: UInt64.Type, forKey key: Key) throws -> UInt64? {
    try decodeIfPresent(type, key)
  }

  private func decode<T: Decodable>(_ type: T.Type, _ key: Key) throws -> T {
    try decode(type, forKey: key)
  }

  private func decodeIfPresent<T: Decodable>(_ type: T.Type, _ key: Key) throws -> T? {
    try decodeIfPresent(type, forKey: key)
  }

  func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type, forKey key: Key
  ) throws -> KeyedDecodingContainer<NestedKey> {
    throw SchemaGenerationError(
      description: "Nested containers are not supported (\(key.stringValue)); use a struct")
  }

  func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
    throw SchemaGenerationError(
      description: "Nested containers are not supported (\(key.stringValue)); use an Array")
  }

  func superDecoder() throws -> any Decoder {
    throw SchemaGenerationError(description: "superDecoder is not supported")
  }

  func superDecoder(forKey key: Key) throws -> any Decoder {
    throw SchemaGenerationError(description: "superDecoder is not supported")
  }
}

private struct ShapeSingleValueContainer: SingleValueDecodingContainer {
  let generator: SchemaGenerator
  let mode: ShapeDecoder.Mode
  var codingPath: [any CodingKey] = []

  init(generator: SchemaGenerator, mode: ShapeDecoder.Mode) {
    self.generator = generator
    self.mode = mode
  }

  func decodeNil() -> Bool {
    if case .sample(nil) = mode { true } else { false }
  }

  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    switch mode {
    case .sample(let sample):
      guard let sample, let value = sample as? T else {
        throw DecodingError.typeMismatch(
          type, DecodingError.Context(codingPath: codingPath, debugDescription: "Sampled value"))
      }
      return value
    case .record(let recorder):
      recorder.singleValue = try generator.node(for: T.self)
      return try generator.placeholder(T.self)
    case .placeholder:
      return try generator.placeholder(T.self)
    }
  }

  func decode(_ type: Bool.Type) throws -> Bool { try decodeValue(type) }
  func decode(_ type: String.Type) throws -> String { try decodeValue(type) }
  func decode(_ type: Double.Type) throws -> Double { try decodeValue(type) }
  func decode(_ type: Float.Type) throws -> Float { try decodeValue(type) }
  func decode(_ type: Int.Type) throws -> Int { try decodeValue(type) }
  func decode(_ type: Int8.Type) throws -> Int8 { try decodeValue(type) }
  func decode(_ type: Int16.Type) throws -> Int16 { try decodeValue(type) }
  func decode(_ type: Int32.Type) throws -> Int32 { try decodeValue(type) }
  func decode(_ type: Int64.Type) throws -> Int64 { try decodeValue(type) }
  func decode(_ type: UInt.Type) throws -> UInt { try decodeValue(type) }
  func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeValue(type) }
  func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeValue(type) }
  func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeValue(type) }
  func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeValue(type) }

  private func decodeValue<T: Decodable>(_ type: T.Type) throws -> T {
    try decode(type)
  }
}
