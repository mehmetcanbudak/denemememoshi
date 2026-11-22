/// A wire type whose JSON shape cannot be learned by decoding it alone.
///
/// The schema generator (`MemoshiProtocolSchema`) derives every struct's schema by running its
/// `init(from:)`. Leaf types that constrain the value itself (constants, open enums, prefixed
/// IDs, ULIDs, bounded values, any-JSON) and small tagged unions describe themselves here
/// instead. A shape is a description, not a hand-written schema: the generator turns it into
/// JSON Schema, and the type's own validation enforces the same limits when it decodes.
public protocol WireShaped {
  /// What values of this type look like on the wire.
  static var wireShape: WireShape { get }
}

/// The vocabulary a ``WireShaped`` type uses to describe itself.
public enum WireShape {
  /// Any JSON value.
  case anyJSON
  /// A string that must equal this value.
  case constant(String)
  /// An open string enum. The values are the known lower-snake-case cases; receivers decode any
  /// other value as `.unknown(String)`, but the engine never writes one.
  case stringEnum([String])
  /// A prefixed object ID, `<prefix>_<ULID>`, with any of these prefixes.
  case prefixedID([String])
  /// A bare ULID: 26 Crockford base32 characters.
  case ulid
  /// An integer within these bounds; equal bounds make it a constant.
  case integer(minimum: Int, maximum: Int)
  /// A string of at most `maxLength` Unicode scalars that matches `pattern`, an anchored
  /// regular expression valid in both Swift and ECMAScript.
  case string(maxLength: Int?, pattern: String?)
  /// An array of at most `maxItems` elements of one type.
  case array(element: any Decodable.Type, maxItems: Int)
  /// A tagged union. Each variant's fields sit beside the `discriminator` key, whose value is
  /// the variant's tag.
  case union(discriminator: String, variants: [WireVariant])
}

/// One variant of a ``WireShape/union(discriminator:variants:)``.
public struct WireVariant {
  /// The discriminator value that selects this variant.
  public let tag: String
  /// The types that decode the variant's fields from the same JSON object; their properties
  /// together are the variant's fields. A variant with no fields lists none.
  public let fields: [any Decodable.Type]
  /// Fields whose value the variant fixes, by name. The schema states each as a `const`; the
  /// type's decoder may still read any value of the field's type.
  public let constants: [String: JSONValue]

  /// Creates a variant.
  public init(
    tag: String, fields: [any Decodable.Type], constants: [String: JSONValue] = [:]
  ) {
    self.tag = tag
    self.fields = fields
    self.constants = constants
  }
}

/// A wire struct with a rule between two of its fields, which decoding it cannot show the
/// schema generator.
public protocol WireDependent {
  /// Optional fields that may be present only while another field is present and not `null`:
  /// each key is such a field, and its value names the field it depends on. The type's decoder
  /// enforces the same rule.
  static var wireDependencies: [String: String] { get }
}

/// A wire type whose schema definition name differs from its Swift type name, such as a
/// generic frame specialized for one method.
public protocol WireNamed {
  /// The name of the type's entry in the schema's `$defs`.
  static var wireName: String { get }
}
