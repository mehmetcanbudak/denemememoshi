import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import Synchronization

/// One complete HTTP/1.1 request. Bodies are bounded; every connection serves one request.
package struct LoopbackHTTPRequest: Sendable {
  /// The request method, such as `GET`.
  package let method: String
  /// The path without its query.
  package let path: String
  /// Decoded query items; the last value of a repeated name wins.
  package let query: [String: String]
  /// The request headers.
  package let headers: HTTPHeaders
  /// The complete request body.
  package let body: Data

  /// The first value of one header, compared case-insensitively.
  package func header(_ name: String) -> String? { headers.first(name: name) }
}

/// Writes one response to its own connection, then closes it.
package struct LoopbackHTTPResponder: Sendable {
  let channel: any Channel

  /// Sends a complete JSON response.
  package func json(_ status: Int, _ body: Data) async {
    let head = HTTPResponseHead(
      version: .http1_1, status: HTTPResponseStatus(statusCode: status),
      headers: HTTPHeaders([
        ("Content-Type", "application/json"), ("Content-Length", String(body.count)),
        ("Connection", "close"),
      ]))
    channel.write(HTTPServerResponsePart.head(head), promise: nil)
    channel.write(
      HTTPServerResponsePart.body(.byteBuffer(channel.allocator.buffer(bytes: body))),
      promise: nil)
    try? await channel.writeAndFlush(HTTPServerResponsePart.end(nil)).get()
    try? await channel.close().get()
  }

  /// Encodes a value as the JSON response body.
  package func json(_ status: Int, encoding value: some Encodable) async {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    await json(status, (try? encoder.encode(value)) ?? Data("{}".utf8))
  }

  /// Starts a chunked server-sent-event stream.
  package func beginEvents() async throws {
    let head = HTTPResponseHead(
      version: .http1_1, status: .ok,
      headers: HTTPHeaders([
        ("Content-Type", "text/event-stream"), ("Transfer-Encoding", "chunked"),
        ("Connection", "close"),
      ]))
    try await channel.writeAndFlush(HTTPServerResponsePart.head(head)).get()
  }

  /// Writes and flushes one stream chunk.
  package func write(_ text: String) async throws {
    let buffer = channel.allocator.buffer(string: text)
    try await channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buffer))).get()
  }

  /// Ends the stream and closes the connection.
  package func finishEvents() async throws {
    try await channel.writeAndFlush(HTTPServerResponsePart.end(nil)).get()
    try await channel.close().get()
  }

  /// Closes the connection without completing the response.
  package func close() async {
    try? await channel.close().get()
  }

  /// Completes when the peer or this server closes the connection, such as a killed client.
  package func closed() async {
    try? await channel.closeFuture.get()
  }
}

/// A loopback-only HTTP/1.1 listener on an OS-chosen port. Each request runs in its own task.
package final class LoopbackHTTPServer: Sendable {
  /// The bound port on 127.0.0.1.
  package let port: Int
  private let group: MultiThreadedEventLoopGroup
  private let listener: any Channel
  private let connections: Connections
  private let shutdown = Mutex<Task<Void, Never>?>(nil)

  private init(
    port: Int, group: MultiThreadedEventLoopGroup, listener: any Channel, connections: Connections
  ) {
    self.port = port
    self.group = group
    self.listener = listener
    self.connections = connections
  }

  /// Binds 127.0.0.1 port 0 and serves until `close()`.
  package static func start(
    maximumBodyBytes: Int = 4 * 1024 * 1024,
    handler: @escaping @Sendable (LoopbackHTTPRequest, LoopbackHTTPResponder) async -> Void
  ) async throws -> LoopbackHTTPServer {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let connections = Connections()
    do {
      let listener = try await ServerBootstrap(group: group)
        .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
        .childChannelInitializer { channel in
          guard connections.add(channel) else {
            return channel.eventLoop.makeFailedFuture(LoopbackHTTPError.closed)
          }
          return channel.eventLoop.makeCompletedFuture {
            try channel.pipeline.syncOperations.configureHTTPServerPipeline(
              withPipeliningAssistance: false)
            try channel.pipeline.syncOperations.addHandler(
              RequestCollector(
                maximumBodyBytes: maximumBodyBytes, connections: connections, handler: handler))
          }
        }
        .bind(host: "127.0.0.1", port: 0).get()
      guard let port = listener.localAddress?.port else { throw LoopbackHTTPError.unbound }
      return LoopbackHTTPServer(
        port: port, group: group, listener: listener, connections: connections)
    } catch {
      try? await group.shutdownGracefully()
      throw error
    }
  }

  /// Stops admission, cancels and drains owned requests, then stops the event loop.
  package func close() async {
    let task = shutdown.withLock { shutdown in
      if let shutdown { return shutdown }
      let task = Task<Void, Never> { [listener, group, connections] in
        let owned = connections.stop()
        for request in owned.requests { request.cancel() }
        try? await listener.close().get()
        for channel in owned.channels { try? await channel.close().get() }
        // Handlers can still close/write their channel while cancellation unwinds.
        // The loop must remain alive until every handler has returned.
        for request in owned.requests { await request.value }
        try? await group.shutdownGracefully()
      }
      shutdown = task
      return task
    }
    await task.value
  }
}

/// Server failures.
package enum LoopbackHTTPError: Error, Equatable {
  /// The listener has no local port.
  case unbound
  /// Shutdown has closed admission.
  case closed
}

private final class Connections: Sendable {
  private struct State {
    var channels: [ObjectIdentifier: any Channel] = [:]
    var requests: [ObjectIdentifier: Task<Void, Never>] = [:]
    var closing = false
  }
  private let state = Mutex(State())

  func add(_ channel: any Channel) -> Bool {
    let id = ObjectIdentifier(channel)
    let accepted = state.withLock { state in
      guard !state.closing else { return false }
      state.channels[id] = channel
      return true
    }
    guard accepted else { return false }
    channel.closeFuture.whenComplete { [weak self] _ in
      _ = self?.state.withLock { $0.channels.removeValue(forKey: id) }
    }
    return true
  }

  func startRequest(
    on channel: any Channel, operation: @escaping @Sendable () async -> Void
  ) {
    let id = ObjectIdentifier(channel)
    state.withLock { state in
      guard !state.closing, state.channels[id] != nil, state.requests[id] == nil else { return }
      state.requests[id] = Task {
        await operation()
        self.finished(id)
      }
    }
  }

  private func finished(_ id: ObjectIdentifier) {
    _ = state.withLock { $0.requests.removeValue(forKey: id) }
  }

  func stop() -> (channels: [any Channel], requests: [Task<Void, Never>]) {
    state.withLock { state in
      state.closing = true
      defer {
        state.channels.removeAll()
        state.requests.removeAll()
      }
      return (Array(state.channels.values), Array(state.requests.values))
    }
  }
}

/// NIO invokes every handler method on the owning channel's event loop.
private final class RequestCollector: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart

  private let maximumBodyBytes: Int
  private let handler: @Sendable (LoopbackHTTPRequest, LoopbackHTTPResponder) async -> Void
  private let connections: Connections
  private var head: HTTPRequestHead?
  private var body = Data()
  private var rejected = false

  init(
    maximumBodyBytes: Int,
    connections: Connections,
    handler: @escaping @Sendable (LoopbackHTTPRequest, LoopbackHTTPResponder) async -> Void
  ) {
    self.maximumBodyBytes = maximumBodyBytes
    self.connections = connections
    self.handler = handler
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch unwrapInboundIn(data) {
    case .head(let head):
      self.head = head
      body.removeAll(keepingCapacity: true)
    case .body(let chunk):
      guard !rejected else { return }
      if body.count + chunk.readableBytes > maximumBodyBytes {
        rejected = true
        context.close(promise: nil)
        return
      }
      body.append(contentsOf: chunk.readableBytesView)
    case .end:
      guard let head, !rejected else { return }
      self.head = nil
      rejected = true
      let components = URLComponents(string: head.uri)
      var query: [String: String] = [:]
      for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
      let request = LoopbackHTTPRequest(
        method: head.method.rawValue, path: components?.path ?? head.uri, query: query,
        headers: head.headers, body: body)
      let responder = LoopbackHTTPResponder(channel: context.channel)
      let handler = handler
      connections.startRequest(on: context.channel) { await handler(request, responder) }
    }
  }

  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    context.close(promise: nil)
  }
}
