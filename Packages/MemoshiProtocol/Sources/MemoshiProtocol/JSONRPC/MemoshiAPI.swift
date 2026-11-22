/// The typed API every client uses to call the engine (D78).
///
/// On iPhone and iPad the engine runs in the app and conforms directly: a call is a Swift
/// function call, with no JSON, socket, token or peer check. On the Mac a client conforms by
/// encoding each call with ``JSONRPCCodec`` over its socket to memoshid. Callers write the same
/// code either way:
///
/// ```swift
/// let sent = try await api.call(ChatsSend.self, params)
/// ```
public protocol MemoshiAPI: Sendable {
  /// Calls one method and returns its result.
  ///
  /// - Throws: ``RPCError`` when the engine refuses or fails the call; a client may also throw
  ///   its own transport errors.
  func call<Method: RPCMethod>(
    _ method: Method.Type, _ params: Method.Params
  ) async throws -> Method.Result
}
