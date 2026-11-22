import MemoshiProtocol
import MemoshiStore

extension MemoshiClient {
  /// Generates a client-owned idempotency key with the existing canonical ULID generator.
  /// Retain it with the pending intent; generating another key is not a transport retry.
  public nonisolated static func requestID() throws -> ULID {
    try IDGenerator.shared.next()
  }
}
