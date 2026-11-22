import Foundation

/// Encodes typed calls as JSON-RPC 2.0 frames and decodes the frames that answer them, for the
/// Mac client of memoshid (protocol.md §1). It owns no transport.
public struct JSONRPCCodec: Sendable {
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  /// Creates a codec.
  ///
  /// - Parameter diagnostics: Receives every event this build cannot read; such events decode
  ///   as ``Event/unknown(type:typeVersion:raw:)``. Without a sink they go to the unified log.
  public init(diagnostics: (any ProtocolDiagnosticsSink)? = nil) {
    encoder = ProtocolCoding.makeEncoder()
    decoder = ProtocolCoding.makeDecoder(diagnostics: diagnostics)
  }

  /// Encodes a request frame.
  public func encodeRequest<Method: RPCMethod>(
    _ method: Method.Type, id: JSONRPCID, params: Method.Params
  ) throws -> Data {
    try encoder.encode(JSONRPCRequest<Method>(id: id, params: params))
  }

  /// Decodes the response to a request for `method`: its result, or the error the engine
  /// reported.
  public func decodeResponse<Method: RPCMethod>(
    _ method: Method.Type, from frame: Data
  ) throws -> JSONRPCResponse<Method> {
    try decoder.decode(JSONRPCResponse<Method>.self, from: frame)
  }

  /// Decodes an `event` notification frame, or a batch array of them, in order.
  public func decodeEvents(from frame: Data) throws -> [EventEnvelope] {
    try decoder.decode(EventFrame.self, from: frame).events
  }

  /// Reads just enough of a frame to route it: a response by its `id`, a notification or
  /// request by its `method`, or a batch.
  public func inspect(_ frame: Data) throws -> JSONRPCFrameKind {
    try decoder.decode(FrameProbe.self, from: frame).kind
  }
}

/// What an inbound frame is, for routing.
public enum JSONRPCFrameKind: Hashable, Sendable {
  /// A response to the request with this ID; `nil` for an error about an unreadable request.
  case response(id: String?)
  /// A notification, such as `event`.
  case notification(method: String)
  /// A request from the other side, such as a daemon-to-app `host.*` call.
  case request(id: String, method: String)
  /// A batch array of this many frames.
  case batch(count: Int)
}

private struct EventFrame: Decodable {
  let events: [EventEnvelope]

  init(from decoder: any Decoder) throws {
    if var batch = try? decoder.unkeyedContainer() {
      var events: [EventEnvelope] = []
      while !batch.isAtEnd {
        events.append(try batch.decode(EventNotification.self).event)
      }
      self.events = events
    } else {
      events = [try EventNotification(from: decoder).event]
    }
  }
}

private struct FrameProbe: Decodable {
  let kind: JSONRPCFrameKind

  private enum CodingKeys: String, CodingKey {
    case id
    case method
    case result
    case error
  }

  init(from decoder: any Decoder) throws {
    if let batch = try? decoder.unkeyedContainer() {
      kind = .batch(count: batch.count ?? 0)
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decodeIfPresent(String.self, forKey: .id)
    if let method = try container.decodeIfPresent(String.self, forKey: .method) {
      kind = id.map { .request(id: $0, method: method) } ?? .notification(method: method)
    } else if container.contains(.result) || container.contains(.error) {
      kind = .response(id: id)
    } else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: [], debugDescription: "Not a JSON-RPC request, response or notification"))
    }
  }
}
