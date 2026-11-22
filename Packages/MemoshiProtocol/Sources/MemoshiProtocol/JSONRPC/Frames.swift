/// A JSON-RPC 2.0 request for one method: `{jsonrpc, id, method, params}`.
///
/// `params` is always present; a method without parameters sends `{}`.
public struct JSONRPCRequest<Method: RPCMethod>: Codable, Hashable, Sendable, WireNamed {
  /// The request ID, unique per direction on a connection: `c:<n>` from clients, `d:<n>` from
  /// the daemon (protocol.md §4).
  public var id: JSONRPCID
  /// The method's parameters.
  public var params: Method.Params

  /// Creates a request.
  public init(id: JSONRPCID, params: Method.Params) {
    self.id = id
    self.params = params
  }

  private enum CodingKeys: String, CodingKey {
    case jsonrpc
    case id
    case method
    case params
  }

  /// Decodes a request, requiring `jsonrpc` to be `"2.0"` and `method` to be this method.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    _ = try container.decode(JSONRPCVersion.self, forKey: .jsonrpc)
    _ = try container.decode(MethodNameConstant<Method>.self, forKey: .method)
    id = try container.decode(JSONRPCID.self, forKey: .id)
    params = try container.decode(Method.Params.self, forKey: .params)
  }

  /// Encodes the request frame.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(JSONRPCVersion.value, forKey: .jsonrpc)
    try container.encode(id, forKey: .id)
    try container.encode(Method.name, forKey: .method)
    try container.encode(params, forKey: .params)
  }

  /// `<Method>Request`, such as `ChatsSendRequest`.
  public static var wireName: String { "\(Method.self)Request" }
}

/// A successful JSON-RPC 2.0 response for one method: `{jsonrpc, id, result}`.
public struct JSONRPCSuccessResponse<Method: RPCMethod>: Codable, Hashable, Sendable, WireNamed {
  /// The ID of the request it answers.
  public var id: JSONRPCID
  /// The method's result.
  public var result: Method.Result

  /// Creates a success response.
  public init(id: JSONRPCID, result: Method.Result) {
    self.id = id
    self.result = result
  }

  private enum CodingKeys: String, CodingKey {
    case jsonrpc
    case id
    case result
  }

  /// Decodes a success response, requiring `jsonrpc` to be `"2.0"`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    _ = try container.decode(JSONRPCVersion.self, forKey: .jsonrpc)
    id = try container.decode(JSONRPCID.self, forKey: .id)
    result = try container.decode(Method.Result.self, forKey: .result)
  }

  /// Encodes the response frame.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(JSONRPCVersion.value, forKey: .jsonrpc)
    try container.encode(id, forKey: .id)
    try container.encode(result, forKey: .result)
  }

  /// `<Method>Response`, such as `ChatsSendResponse`.
  public static var wireName: String { "\(Method.self)Response" }
}

/// A JSON-RPC 2.0 error response: `{jsonrpc, id, error}`.
public struct JSONRPCErrorResponse: Codable, Hashable, Sendable {
  /// The ID of the request it answers; `null` when the request's ID could not be read, as for
  /// `parse_error`.
  public var id: JSONRPCID?
  /// The error.
  public var error: RPCError

  /// Creates an error response.
  public init(id: JSONRPCID?, error: RPCError) {
    self.id = id
    self.error = error
  }

  private enum CodingKeys: String, CodingKey {
    case jsonrpc
    case id
    case error
  }

  /// Decodes an error response. `id` must be present, even when it is `null`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    _ = try container.decode(JSONRPCVersion.self, forKey: .jsonrpc)
    id = try container.decode(JSONRPCID?.self, forKey: .id)
    error = try container.decode(RPCError.self, forKey: .error)
  }

  /// Encodes the response frame, writing `"id": null` when there is no ID.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(JSONRPCVersion.value, forKey: .jsonrpc)
    try container.encode(id, forKey: .id)
    try container.encode(error, forKey: .error)
  }
}

/// Either response to a request for one method.
public enum JSONRPCResponse<Method: RPCMethod>: Hashable, Sendable {
  case success(JSONRPCSuccessResponse<Method>)
  case failure(JSONRPCErrorResponse)

  /// The ID of the request it answers.
  public var id: JSONRPCID? {
    switch self {
    case .success(let response): response.id
    case .failure(let response): response.id
    }
  }

  /// The result, or the error the engine reported.
  public func get() throws(RPCError) -> Method.Result {
    switch self {
    case .success(let response): return response.result
    case .failure(let response): throw response.error
    }
  }
}

extension JSONRPCResponse: Decodable {
  private enum CodingKeys: String, CodingKey {
    case error
  }

  /// Decodes an error response when the frame has `error`, otherwise a success response.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.error) {
      self = .failure(try JSONRPCErrorResponse(from: decoder))
    } else {
      self = .success(try JSONRPCSuccessResponse<Method>(from: decoder))
    }
  }
}

/// The `event` notification: one event envelope as `params` (protocol.md §7.1). Several may
/// arrive in one batch array.
public struct EventNotification: Codable, Hashable, Sendable {
  /// The notification's method name.
  public static let method = "event"

  /// The event.
  public var event: EventEnvelope

  /// Creates a notification.
  public init(event: EventEnvelope) {
    self.event = event
  }

  private enum CodingKeys: String, CodingKey {
    case jsonrpc
    case method
    case params
  }

  /// Decodes the notification, requiring `jsonrpc` to be `"2.0"` and `method` to be `event`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    _ = try container.decode(JSONRPCVersion.self, forKey: .jsonrpc)
    _ = try container.decode(EventMethodConstant.self, forKey: .method)
    event = try container.decode(EventEnvelope.self, forKey: .params)
  }

  /// Encodes the notification frame.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(JSONRPCVersion.value, forKey: .jsonrpc)
    try container.encode(Self.method, forKey: .method)
    try container.encode(event, forKey: .params)
  }
}

/// The `system.cancel` notification: cancels the pending request with this `id`, in either
/// direction (protocol.md §4). The target then answers that request with `canceled`.
public struct SystemCancelNotification: Codable, Hashable, Sendable {
  /// The notification's method name.
  public static let method = "system.cancel"

  /// The ID of the request to cancel: `c:<n>` for a client's, `d:<n>` for the daemon's.
  public var id: JSONRPCID

  /// Creates a notification.
  public init(id: JSONRPCID) {
    self.id = id
  }

  private enum CodingKeys: String, CodingKey {
    case jsonrpc
    case method
    case params
  }

  /// Decodes the notification, requiring `jsonrpc` to be `"2.0"` and `method` to be
  /// `system.cancel`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    _ = try container.decode(JSONRPCVersion.self, forKey: .jsonrpc)
    _ = try container.decode(SystemCancelMethodConstant.self, forKey: .method)
    id = try container.decode(SystemCancelParams.self, forKey: .params).id
  }

  /// Encodes the notification frame.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(JSONRPCVersion.value, forKey: .jsonrpc)
    try container.encode(Self.method, forKey: .method)
    try container.encode(SystemCancelParams(id: id), forKey: .params)
  }
}

/// `system.cancel`'s parameters: `{id}`.
private struct SystemCancelParams: Codable {
  let id: JSONRPCID
}

/// A string that must equal one value; decodes only that value.
private protocol StringConstant: Decodable, WireShaped {
  static var value: String { get }
  init()
}

extension StringConstant {
  static var wireShape: WireShape { .constant(value) }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    guard raw == Self.value else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected \"\(Self.value)\", got \"\(raw)\"")
    }
    self.init()
  }
}

private struct JSONRPCVersion: StringConstant {
  static let value = "2.0"
}

private struct MethodNameConstant<Method: RPCMethod>: StringConstant {
  static var value: String { Method.name }
}

private struct EventMethodConstant: StringConstant {
  static var value: String { EventNotification.method }
}

private struct SystemCancelMethodConstant: StringConstant {
  static var value: String { SystemCancelNotification.method }
}
