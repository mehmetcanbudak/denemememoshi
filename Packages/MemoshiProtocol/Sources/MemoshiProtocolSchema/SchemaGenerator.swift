import MemoshiProtocol

/// Builds `$defs` from the Swift types. One instance builds one document.
final class SchemaGenerator {
  /// The definitions built so far, by name.
  private(set) var definitions: [String: JSONValue] = [:]
  /// What built each definition name: a type in a role, or `nil` for a registry definition. A
  /// type defined as a union variant carries the discriminator, so the same name can never
  /// stand for both the bare type and the tagged variant.
  private var owners: [String: DefinitionOwner?] = [:]

  private static let ulidPattern = "[0-7][0-9A-HJKMNP-TV-Z]{25}"

  private static let integerTypes: Set<ObjectIdentifier> = [
    ObjectIdentifier(Int.self), ObjectIdentifier(Int8.self), ObjectIdentifier(Int16.self),
    ObjectIdentifier(Int32.self), ObjectIdentifier(Int64.self), ObjectIdentifier(UInt.self),
    ObjectIdentifier(UInt8.self), ObjectIdentifier(UInt16.self), ObjectIdentifier(UInt32.self),
    ObjectIdentifier(UInt64.self),
  ]

  /// Defines every registered method, event and device message, and everything they reach.
  func defineEverything() throws {
    var requests: [JSONValue] = []
    var results: [JSONValue] = []
    for method in MethodRegistry.methods {
      let frames = try defineFrames(of: method)
      requests.append(frames.request)
      results.append(frames.taggedResult)
    }
    try defineSynthetic(
      "Request",
      [
        "description": "Any request this build models, discriminated by `method`.",
        "oneOf": .array(requests),
      ])
    try defineSynthetic(
      "MethodResult",
      [
        "description": .string(
          "Each method's result tagged with the method that produced it. A JSON-RPC response "
            + "carries only `result`; a receiver pairs it with its request by `id`."),
        "oneOf": .array(results),
      ])
    _ = try node(for: JSONRPCErrorResponse.self)
    _ = try node(for: EventNotification.self)
    _ = try node(for: SystemCancelNotification.self)
    _ = try node(for: DeviceMessage.self)
  }

  private func defineFrames<Method: RPCMethod>(of method: Method.Type) throws -> (
    request: JSONValue, taggedResult: JSONValue
  ) {
    let request = try node(for: JSONRPCRequest<Method>.self)
    _ = try node(for: JSONRPCSuccessResponse<Method>.self)
    let result = try node(for: Method.Result.self)
    let tagged = objectSchema(
      properties: ["method": ["const": .string(Method.name)], "result": result],
      required: ["method", "result"])
    return (request, tagged)
  }

  // MARK: Nodes

  /// The schema for a property of this type: inline for primitives and constants, otherwise a
  /// `$ref` to the type's definition, which is built on first use.
  func node(for type: Any.Type) throws -> JSONValue {
    if type == String.self { return ["type": "string"] }
    if type == Bool.self { return ["type": "boolean"] }
    if Self.integerTypes.contains(ObjectIdentifier(type)) { return ["type": "integer"] }
    if type == Double.self || type == Float.self { return ["type": "number"] }
    if let optional = type as? any SchemaOptional.Type {
      return Self.nullable(try node(for: optional.wrappedType))
    }
    if let array = type as? any SchemaArray.Type {
      return ["type": "array", "items": try node(for: array.elementType)]
    }
    if let dictionary = type as? any SchemaDictionary.Type {
      return ["type": "object", "additionalProperties": try node(for: dictionary.valueType)]
    }
    if type == EventEnvelope.self {
      return try define(type, named: "EventEnvelope") { try buildEventUnion() }
    }
    if type == DeviceMessage.self {
      return try define(type, named: "DeviceMessage") { try buildDeviceMessageUnion() }
    }
    if let shaped = type as? any WireShaped.Type {
      let shape = shaped.wireShape
      if let constant = Self.constant(of: shape) {
        return constant
      }
      let name = Self.name(of: type)
      return try define(type, named: name) { try schema(for: shape, named: name, of: type) }
    }
    if let decodable = type as? any Decodable.Type {
      return try define(type, named: Self.name(of: type)) { try recordObject(decodable) }
    }
    throw SchemaGenerationError(description: "\(type) is not Decodable")
  }

  private static func name(of type: Any.Type) -> String {
    (type as? any WireNamed.Type)?.wireName ?? String(describing: type)
  }

  /// The inline `const` of a shape that allows exactly one value; `nil` for any other shape.
  private static func constant(of shape: WireShape) -> JSONValue? {
    switch shape {
    case .constant(let value): ["const": .string(value)]
    case .integer(let minimum, let maximum) where minimum == maximum:
      ["const": .integer(Int64(minimum))]
    default: nil
    }
  }

  /// `budget_exhausted` → `BudgetExhausted`: the suffix of a union variant's definition name.
  private static func pascalCase(_ tag: String) -> String {
    tag.split(whereSeparator: { $0 == "_" || $0 == "." || $0 == "-" })
      .map { $0.prefix(1).uppercased() + $0.dropFirst() }
      .joined()
  }

  private static func reference(_ name: String) -> JSONValue {
    ["$ref": .string("#/$defs/\(name)")]
  }

  private static func nullable(_ node: JSONValue) -> JSONValue {
    if case .object(let members) = node, members.count == 1,
      case .string(let type)? = members["type"]
    {
      return ["type": [.string(type), "null"]]
    }
    return ["oneOf": [["type": "null"], node]]
  }

  private func define(
    _ type: Any.Type, named name: String, role: String = "", build: () throws -> JSONValue
  ) throws -> JSONValue {
    let owner = DefinitionOwner(type: ObjectIdentifier(type), role: role)
    if let existing = owners[name] {
      guard existing == owner else {
        throw SchemaGenerationError(
          description: "\(name) in $defs would describe two different shapes")
      }
      return Self.reference(name)
    }
    owners[name] = owner
    definitions[name] = try build()
    return Self.reference(name)
  }

  private func defineSynthetic(_ name: String, _ schema: JSONValue) throws {
    guard owners[name] == nil else {
      throw SchemaGenerationError(description: "\(name) is defined twice in $defs")
    }
    owners[name] = .some(nil)
    definitions[name] = schema
  }

  private func objectSchema(properties: [String: JSONValue], required: Set<String>) -> JSONValue {
    var schema: [String: JSONValue] = [
      "type": "object",
      "properties": .object(properties),
      "additionalProperties": false,
    ]
    if !required.isEmpty {
      schema["required"] = .array(
        required.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { .string($0) })
    }
    return .object(schema)
  }

  // MARK: Shapes

  /// The definition of a ``WireShaped`` type named `name`. A union's variants become their own
  /// definitions, `<name><Tag>`, owned by the union type.
  private func schema(for shape: WireShape, named name: String, of type: Any.Type) throws
    -> JSONValue
  {
    switch shape {
    case .anyJSON:
      return [:]
    case .constant(let value):
      return ["const": .string(value)]
    case .stringEnum(let values):
      return ["type": "string", "enum": .array(values.map { .string($0) })]
    case .prefixedID(let prefixes):
      let prefix = prefixes.count == 1 ? prefixes[0] : "(\(prefixes.joined(separator: "|")))"
      return ["type": "string", "pattern": .string("^\(prefix)_\(Self.ulidPattern)$")]
    case .ulid:
      return ["type": "string", "pattern": .string("^\(Self.ulidPattern)$")]
    case .integer(let minimum, let maximum):
      if let constant = Self.constant(of: shape) {
        return constant
      }
      return [
        "type": "integer", "minimum": .integer(Int64(minimum)),
        "maximum": .integer(Int64(maximum)),
      ]
    case .string(let maxLength, let pattern):
      var schema: [String: JSONValue] = ["type": "string"]
      if let maxLength {
        schema["maxLength"] = .integer(Int64(maxLength))
      }
      if let pattern {
        schema["pattern"] = .string(pattern)
      }
      return .object(schema)
    case .array(let element, let maxItems):
      return [
        "type": "array", "items": try node(for: element), "maxItems": .integer(Int64(maxItems)),
      ]
    case .union(let discriminator, let variants):
      var references: [JSONValue] = []
      for variant in variants {
        let variantName = name + Self.pascalCase(variant.tag)
        let reference = try define(type, named: variantName, role: "variant \(variant.tag)") {
          try variantSchema(variant, named: variantName, discriminator: discriminator)
        }
        references.append(reference)
      }
      return ["oneOf": .array(references)]
    }
  }

  /// One union variant: the fields of every listed type, side by side with the discriminator.
  private func variantSchema(
    _ variant: WireVariant, named name: String, discriminator: String
  ) throws -> JSONValue {
    var properties: [String: JSONValue] = [:]
    var required: Set<String> = [discriminator]
    for fieldsType in variant.fields {
      let recorded = try record(fieldsType)
      guard recorded.usedKeyedContainer, recorded.singleValue == nil else {
        throw SchemaGenerationError(
          description: "\(fieldsType) in \(name) does not decode an object")
      }
      for (key, node) in recorded.properties {
        guard key != discriminator, properties[key].map({ $0 == node }) ?? true else {
          throw SchemaGenerationError(description: "\(name) would describe \(key) twice")
        }
        properties[key] = node
      }
      required.formUnion(recorded.required)
    }
    for (key, value) in variant.constants {
      guard properties[key] != nil else {
        throw SchemaGenerationError(description: "\(name) fixes \(key), which it does not have")
      }
      properties[key] = ["const": value]
    }
    properties[discriminator] = ["const": .string(variant.tag)]
    return objectSchema(properties: properties, required: required)
  }

  // MARK: Recording

  private func record(_ type: any Decodable.Type) throws -> ObjectRecorder {
    let recorder = ObjectRecorder()
    _ = try type.init(from: ShapeDecoder(generator: self, mode: .record(recorder)))
    return recorder
  }

  private func recordObject(_ type: any Decodable.Type) throws -> JSONValue {
    let recorder = try record(type)
    if let singleValue = recorder.singleValue {
      return singleValue
    }
    guard recorder.usedKeyedContainer else {
      throw SchemaGenerationError(description: "\(type) decodes neither an object nor a value")
    }
    let schema = objectSchema(properties: recorder.properties, required: recorder.required)
    guard let dependent = type as? any WireDependent.Type,
      !dependent.wireDependencies.isEmpty, case .object(var members) = schema
    else { return schema }
    var dependencies: [String: JSONValue] = [:]
    for (field, needed) in dependent.wireDependencies {
      guard recorder.properties[field] != nil, recorder.properties[needed] != nil else {
        throw SchemaGenerationError(
          description: "\(type) relates \(field) to \(needed), and does not have both")
      }
      dependencies[field] = [
        "properties": .object([needed: ["not": ["type": "null"]]]),
        "required": [.string(needed)],
      ]
    }
    members["dependentSchemas"] = .object(dependencies)
    return .object(members)
  }

  /// A value of `type` for a recording decoder to return: empty, zero, the first known case, or
  /// a well-formed identifier. Building it records nothing.
  func placeholder<T: Decodable>(_ type: T.Type) throws -> T {
    if let value = Self.primitivePlaceholder(type) as? T { return value }
    if let optional = T.self as? any SchemaOptional.Type, let value = optional.noneValue as? T {
      return value
    }
    if let array = T.self as? any SchemaArray.Type, let value = array.empty as? T { return value }
    if let dictionary = T.self as? any SchemaDictionary.Type, let value = dictionary.empty as? T {
      return value
    }
    if let shaped = T.self as? any WireShaped.Type {
      return try T(
        from: ShapeDecoder(generator: self, mode: Self.sampleMode(for: shaped.wireShape)))
    }
    return try T(from: ShapeDecoder(generator: self, mode: .placeholder(overrides: [:])))
  }

  private static func primitivePlaceholder(_ type: Any.Type) -> Any? {
    switch type {
    case is String.Type: ""
    case is Bool.Type: false
    case is Int.Type: Int(0)
    case is Int8.Type: Int8(0)
    case is Int16.Type: Int16(0)
    case is Int32.Type: Int32(0)
    case is Int64.Type: Int64(0)
    case is UInt.Type: UInt(0)
    case is UInt8.Type: UInt8(0)
    case is UInt16.Type: UInt16(0)
    case is UInt32.Type: UInt32(0)
    case is UInt64.Type: UInt64(0)
    case is Double.Type: Double(0)
    case is Float.Type: Float(0)
    default: nil
    }
  }

  private static func sampleMode(for shape: WireShape) -> ShapeDecoder.Mode {
    let zeros = String(repeating: "0", count: 26)
    switch shape {
    case .anyJSON: return .sample(nil)
    case .constant(let value): return .sample(value)
    case .stringEnum(let values): return .sample(values.first ?? "")
    case .prefixedID(let prefixes): return .sample("\(prefixes.first ?? "id")_\(zeros)")
    case .ulid: return .sample(zeros)
    case .integer, .string, .array: return .placeholder(overrides: [:])
    case .union(let discriminator, let variants):
      return .placeholder(overrides: [discriminator: variants.first?.tag ?? ""])
    }
  }

  // MARK: Registry unions

  private func buildEventUnion() throws -> JSONValue {
    let base = try record(EventEnvelope.self)
    var references: [JSONValue] = []
    for payloadType in EventRegistry.payloadTypes {
      let name = ProtocolSchema.eventDefinitionName(for: payloadType.eventType)
      var properties = base.properties
      var required = base.required
      properties["type"] = ["const": .string(payloadType.eventType)]
      properties["typeVersion"] = ["const": .integer(Int64(payloadType.typeVersion))]
      properties["payload"] = try node(for: payloadType)
      switch payloadType.eventClass {
      case .uiOnly:
        properties["seq"] = ["type": "null"]
        properties.removeValue(forKey: "cseq")
        required.insert("after")
      case .durable, .audited:
        properties["seq"] = ["type": "integer"]
        properties.removeValue(forKey: "after")
      }
      guard case .object(var variant) = objectSchema(properties: properties, required: required)
      else { continue }
      variant["description"] = .string(
        "The `\(payloadType.eventType)` event, typeVersion \(payloadType.typeVersion), class "
          + "\(payloadType.eventClass) (events.md §5).")
      try defineSynthetic(name, .object(variant))
      references.append(Self.reference(name))
    }
    return [
      "description": "Any event this build models, discriminated by `type` (events.md §2).",
      "oneOf": .array(references),
    ]
  }

  private func buildDeviceMessageUnion() throws -> JSONValue {
    let base = try record(DeviceMessage.self)
    var references: [JSONValue] = []
    for payloadType in DeviceMessageRegistry.payloadTypes {
      let name = ProtocolSchema.deviceMessageDefinitionName(for: payloadType.messageType)
      var properties = base.properties
      properties["type"] = ["const": .string(payloadType.messageType)]
      properties["payload"] = try node(for: payloadType)
      guard
        case .object(var variant) = objectSchema(properties: properties, required: base.required)
      else { continue }
      variant["description"] = .string(
        "The `\(payloadType.messageType)` device message (protocol.md §12).")
      try defineSynthetic(name, .object(variant))
      references.append(Self.reference(name))
    }
    return [
      "description": "Any device message this build models, discriminated by `type`.",
      "oneOf": .array(references),
    ]
  }
}

/// The type, and the role it plays, behind one `$defs` entry.
struct DefinitionOwner: Hashable {
  let type: ObjectIdentifier
  /// Empty for the type's own shape; otherwise, such as for a union variant, what changes it.
  let role: String
}

/// What a recording decoder learned about one type.
final class ObjectRecorder {
  var properties: [String: JSONValue] = [:]
  var required: Set<String> = []
  var singleValue: JSONValue?
  var usedKeyedContainer = false

  func record(key: String, node: JSONValue, isRequired: Bool) {
    properties[key] = node
    if isRequired {
      required.insert(key)
    }
  }
}

/// `Optional`, seen through an existential.
protocol SchemaOptional {
  static var wrappedType: Any.Type { get }
  static var noneValue: Any { get }
}

extension Optional: SchemaOptional where Wrapped: Decodable {
  static var wrappedType: Any.Type { Wrapped.self }
  static var noneValue: Any {
    let none: Wrapped? = nil
    return none as Any
  }
}

/// `Array`, seen through an existential.
protocol SchemaArray {
  static var elementType: Any.Type { get }
  static var empty: Any { get }
}

extension Array: SchemaArray where Element: Decodable {
  static var elementType: Any.Type { Element.self }
  static var empty: Any { [Element]() }
}

/// A string-keyed `Dictionary`, seen through an existential.
protocol SchemaDictionary {
  static var valueType: Any.Type { get }
  static var empty: Any { get }
}

extension Dictionary: SchemaDictionary where Key == String, Value: Decodable {
  static var valueType: Any.Type { Value.self }
  static var empty: Any { [String: Value]() }
}
