import Foundation
import MemoshiTransport

/// An authenticated, message-oriented carrier. Implementations must finish their peer checks
/// on the connected descriptor before returning, and before reading or sending any frames.
/// There is one receive consumer; cancellation/close must release the carrier's resources.
public protocol ClientConnection: Sendable {
  var peer: PeerIdentity { get }
  var messages: AsyncThrowingStream<Data, any Error> { get }
  /// Reauthenticates the running peer on this connection's actual connected descriptor.
  /// Returning the cached handshake identity without repeating the OS checks is not sufficient.
  func revalidatePeer(policy: PeerPolicy) async throws -> PeerIdentity
  func send(_ data: Data) async throws
  func close(code: Int, reason: String) async
  func waitUntilClosed() async
}

extension LocalConnection: ClientConnection {}

/// A seam for another authenticated carrier, not a token-only or unsigned local fallback.
public protocol ClientTransport: Sendable {
  func connect(at paths: IPCPaths, policy: PeerPolicy) async throws -> any ClientConnection
}

/// The production carrier: verified AF_UNIX, SwiftNIO HTTP upgrade and WebSocket framing.
public struct UnixWebSocketTransport: ClientTransport {
  /// Creates the production Unix WebSocket carrier.
  public init() {}

  /// Returns only after the actual helper's peer identity and WebSocket upgrade succeed.
  public func connect(at paths: IPCPaths, policy: PeerPolicy) async throws -> any ClientConnection {
    try await LocalWebSocket.connect(at: paths, policy: policy)
  }
}
