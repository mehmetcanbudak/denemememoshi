import Foundation
import MemoshiProtocol
import Synchronization

/// Re-expressed from Draft 3 sidecar/src/ids.ts at ce39f8a7ca324ce1c2473518593b1fb4f96ebe4b.
/// Draft 4 object-model.md §1.1 replaces that reference's UUID fragments with monotonic ULIDs.
public final class IDGenerator: Sendable {
  /// The process-wide monotonic generator.
  public static let shared = IDGenerator()

  private struct State: Sendable {
    var timestamp: UInt64?
    var randomness: [UInt8] = Array(repeating: 0, count: 10)
  }

  private let state = Mutex(State())
  private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)

  /// Creates an independent monotonic sequence.
  public init() {}

  /// The current wall-clock time in Unix milliseconds.
  public static func nowMilliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  /// Monotonic within this generator even if the wall clock moves backwards.
  public func next(at milliseconds: Int64 = IDGenerator.nowMilliseconds()) throws -> ULID {
    guard milliseconds >= 0, milliseconds <= 0xFFFF_FFFF_FFFF else {
      throw StoreError.sequenceExhausted
    }
    return try state.withLock { state in
      let requested = UInt64(milliseconds)
      if let previous = state.timestamp, requested <= previous {
        var carried = true
        for index in state.randomness.indices.reversed() {
          if state.randomness[index] == 255 {
            state.randomness[index] = 0
          } else {
            state.randomness[index] += 1
            carried = false
            break
          }
        }
        if carried {
          guard previous < 0xFFFF_FFFF_FFFF else {
            for index in state.randomness.indices { state.randomness[index] = 255 }
            throw StoreError.sequenceExhausted
          }
          state.timestamp = previous + 1
        }
      } else {
        state.timestamp = requested
        var random = SystemRandomNumberGenerator()
        for index in state.randomness.indices {
          state.randomness[index] = UInt8.random(in: .min ... .max, using: &random)
        }
      }
      let timestamp = state.timestamp ?? requested
      let encoded = String(unsafeUninitializedCapacity: 26) { encoded in
        for index in 0..<10 {
          let shift = (9 - index) * 5
          encoded[index] = Self.alphabet[Int((timestamp >> shift) & 31)]
        }
        // Eighty random bits encode as sixteen base32 digits with no padding.
        var accumulator: UInt32 = 0
        var bits = 0
        var output = 10
        for byte in state.randomness {
          accumulator = (accumulator << 8) | UInt32(byte)
          bits += 8
          while bits >= 5 {
            bits -= 5
            encoded[output] = Self.alphabet[Int((accumulator >> bits) & 31)]
            output += 1
          }
          accumulator &= (1 << bits) - 1
        }
        return 26
      }
      return try ULID(encoded)
    }
  }

  /// Multi-prefix kinds (notably ConversationIDKind) require an explicit valid prefix.
  public func objectID<Kind: ObjectIDKind>(
    _ kind: Kind.Type, prefix: String? = nil,
    at milliseconds: Int64 = IDGenerator.nowMilliseconds()
  ) throws -> ObjectID<Kind> {
    guard let selected = prefix ?? (Kind.idPrefixes.count == 1 ? Kind.idPrefixes.first : nil),
      Kind.idPrefixes.contains(selected)
    else {
      throw StoreError.invalidIDPrefix(prefix ?? "")
    }
    return try ObjectID<Kind>("\(selected)_\(next(at: milliseconds).rawValue)")
  }
}
