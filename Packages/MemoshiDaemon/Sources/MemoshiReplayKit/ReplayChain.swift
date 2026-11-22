import CryptoKit
import Foundation
import MemoshiProtocol

/// How one durable event relates to the chain it is applied to.
package enum ReplayOrder: Sendable { case next, duplicate, gap }

/// A hash chain over durable events in sequence order. Every participant of the replay
/// qualification (the daemon's commit receipts, the live client, the seq-0 rebuild, a fresh
/// store fold) folds with this one type, so equal chains mean the same facts in the same order.
package struct ReplayChain: Sendable {
  package private(set) var head: Int64 = 0
  package private(set) var count = 0
  private var state = Data(count: 32)

  package init() {}

  /// The chain as lowercase hexadecimal.
  package var hex: String { state.map { String(format: "%02x", $0) }.joined() }

  /// Folds `envelope` in when it is the next sequence; a repeat or a gap leaves the chain as it was.
  package mutating func append(_ envelope: EventEnvelope) throws -> ReplayOrder {
    guard let seq = envelope.seq else { throw ReplayError.notDurable }
    if seq <= head { return .duplicate }
    if seq != head + 1 { return .gap }
    var hasher = SHA256()
    hasher.update(data: state)
    withUnsafeBytes(of: seq.bigEndian) { hasher.update(bufferPointer: $0) }
    hasher.update(data: Data(SHA256.hash(data: try ProtocolCoding.makeEncoder().encode(envelope))))
    state = Data(hasher.finalize())
    head = seq
    count += 1
    return .next
  }
}

package enum ReplayError: Error {
  case notDurable
  case badLine(String)
}

/// One envelope as a single stdout line (`COMMIT <base64>`), for the daemon helper's receipts.
package enum ReplayWire {
  /// The envelope as base64 of its canonical JSON.
  package static func encode(_ envelope: EventEnvelope) throws -> String {
    try ProtocolCoding.makeEncoder().encode(envelope).base64EncodedString()
  }

  /// Reads an envelope back from `encode`'s line.
  package static func decode(_ text: String) throws -> EventEnvelope {
    guard let data = Data(base64Encoded: text) else { throw ReplayError.badLine(text) }
    return try ProtocolCoding.makeDecoder(strict: true).decode(EventEnvelope.self, from: data)
  }
}
