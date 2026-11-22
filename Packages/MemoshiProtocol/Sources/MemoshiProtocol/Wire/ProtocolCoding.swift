import Foundation

/// JSON coders configured for the protocol's wire form.
public enum ProtocolCoding {
  /// An encoder for frames: compact, keys sorted, slashes unescaped.
  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  /// A decoder for frames.
  ///
  /// - Parameters:
  ///   - diagnostics: Receives every event or device message kept as `.unknown`.
  ///   - strict: Decode as the engine does: reject what a lenient client would keep as
  ///     `.unknown`.
  public static func makeDecoder(
    diagnostics: (any ProtocolDiagnosticsSink)? = nil, strict: Bool = false
  ) -> JSONDecoder {
    let decoder = JSONDecoder()
    if let diagnostics {
      decoder.userInfo[.memoshiDiagnostics] = diagnostics
    }
    if strict {
      decoder.userInfo[.memoshiStrictDecoding] = true
    }
    return decoder
  }

  /// The value encoded as canonical JSON text (see ``JSONValue/canonicalText``).
  public static func canonicalText(of value: some Encodable) throws -> String {
    try JSONValue.parse(makeEncoder().encode(value)).canonicalText
  }
}
