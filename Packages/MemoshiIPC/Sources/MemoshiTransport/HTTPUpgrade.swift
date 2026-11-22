import NIOCore
import NIOHTTP1
import NIOWebSocket

/// Event-loop confined, including all promise completions and the deadline.
internal final class UpgradeHandshake: @unchecked Sendable {
  let channel: any Channel
  let ready = AsyncResult<Void>()
  private var completed = false
  private var timeout: Scheduled<Void>?

  init(channel: any Channel) {
    self.channel = channel
  }

  func start() {
    channel.eventLoop.assertInEventLoop()
    timeout = channel.eventLoop.scheduleTask(in: .seconds(5)) { [weak self] in
      self?.fail(IPCError.timedOut)
    }
  }

  func succeed() {
    channel.eventLoop.assertInEventLoop()
    guard !completed else { return }
    completed = true
    timeout?.cancel()
    timeout = nil
    ready.complete(.success(()))
  }

  func fail(_ error: any Error) {
    channel.eventLoop.assertInEventLoop()
    guard !completed else { return }
    completed = true
    timeout?.cancel()
    timeout = nil
    ready.complete(.failure(error))
    channel.close(promise: nil)
  }
}

internal final class HandshakeByteBudget: ChannelInboundHandler, RemovableChannelHandler {
  typealias InboundIn = ByteBuffer
  typealias InboundOut = ByteBuffer
  private let handshake: UpgradeHandshake
  private var bytes = 0

  init(handshake: UpgradeHandshake) { self.handshake = handshake }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let buffer = Self.unwrapInboundIn(data)
    guard buffer.readableBytes <= TransportLimits.handshakeBytes - bytes else {
      handshake.fail(IPCError.upgradeFailed)
      return
    }
    bytes += buffer.readableBytes
    context.fireChannelRead(data)
  }

  func channelInactive(context: ChannelHandlerContext) {
    handshake.fail(IPCError.upgradeFailed)
    context.fireChannelInactive()
  }

  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    handshake.fail(IPCError.upgradeFailed)
  }
}

internal final class HTTPUpgradeFallback<Part>: ChannelInboundHandler, RemovableChannelHandler {
  typealias InboundIn = Part
  private let handshake: UpgradeHandshake

  init(handshake: UpgradeHandshake) { self.handshake = handshake }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    handshake.fail(IPCError.upgradeFailed)
  }
  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    handshake.fail(IPCError.upgradeFailed)
  }
  func channelInactive(context: ChannelHandlerContext) {
    handshake.fail(IPCError.upgradeFailed)
    context.fireChannelInactive()
  }
}

internal func configureClientUpgrade(state: ConnectionState, handshake: UpgradeHandshake) throws {
  let channel = state.channel
  handshake.start()
  try channel.pipeline.syncOperations.addHandler(
    HandshakeByteBudget(handshake: handshake), name: "handshake-budget")
  let upgrader = NIOWebSocketClientUpgrader(
    maxFrameSize: TransportLimits.clientMessageBytes,
    automaticErrorHandling: false,
    upgradePipelineHandler: { channel, response in
      let protocols = response.headers["Sec-WebSocket-Protocol"]
      guard response.headers["Sec-WebSocket-Extensions"].isEmpty,
        protocols.isEmpty || protocols == ["memoshi.v1"]
      else {
        handshake.fail(IPCError.upgradeFailed)
        return channel.eventLoop.makeFailedFuture(IPCError.upgradeFailed)
      }
      return channel.pipeline.removeHandler(name: "handshake-budget").flatMap {
        channel.eventLoop.makeCompletedFuture {
          try installMessageHandlers(state: state)
          handshake.succeed()
        }
      }
      .flatMapError { error in
        handshake.fail(error)
        return channel.eventLoop.makeFailedFuture(error)
      }
    })
  try channel.pipeline.syncOperations.addHTTPClientHandlers(
    leftOverBytesStrategy: .forwardBytes,
    withClientUpgrade: (
      upgraders: [upgrader],
      completionHandler: { context in
        context.pipeline.syncOperations.removeHandler(name: "http-fallback", promise: nil)
      }
    ))
  try channel.pipeline.syncOperations.addHandler(
    HTTPUpgradeFallback<HTTPClientResponsePart>(handshake: handshake), name: "http-fallback")
}

internal func configureServerUpgrade(
  state: ConnectionState, handshake: UpgradeHandshake,
  didUpgrade: @escaping @Sendable () -> Void
) throws {
  let channel = state.channel
  handshake.start()
  try channel.pipeline.syncOperations.addHandler(
    HandshakeByteBudget(handshake: handshake), name: "handshake-budget")
  let upgrader = NIOWebSocketServerUpgrader(
    maxFrameSize: TransportLimits.serverMessageBytes,
    automaticErrorHandling: false,
    shouldUpgrade: { channel, request in
      guard request.method == .GET, request.version == .http1_1, request.uri == "/",
        request.headers["Transfer-Encoding"].isEmpty,
        request.headers["Content-Length"].allSatisfy({ $0 == "0" })
      else { return channel.eventLoop.makeSucceededFuture(nil) }
      var headers = HTTPHeaders()
      if request.headers[canonicalForm: "Sec-WebSocket-Protocol"].contains("memoshi.v1") {
        headers.add(name: "Sec-WebSocket-Protocol", value: "memoshi.v1")
      }
      return channel.eventLoop.makeSucceededFuture(headers)
    },
    upgradePipelineHandler: { channel, _ in
      channel.pipeline.removeHandler(name: "handshake-budget").flatMap {
        channel.eventLoop.makeCompletedFuture {
          try installMessageHandlers(state: state)
          handshake.succeed()
          // Leave NIO's upgrade callback stack before exposing sends to the owner.
          channel.eventLoop.execute(didUpgrade)
        }
      }
      .flatMapError { error in
        handshake.fail(error)
        return channel.eventLoop.makeFailedFuture(error)
      }
    })
  try channel.pipeline.syncOperations.configureHTTPServerPipeline(
    withPipeliningAssistance: false,
    withServerUpgrade: (
      upgraders: [upgrader],
      completionHandler: { context in
        context.pipeline.syncOperations.removeHandler(name: "http-fallback", promise: nil)
      }
    ),
    withErrorHandling: false)
  try channel.pipeline.syncOperations.addHandler(
    HTTPUpgradeFallback<HTTPServerRequestPart>(handshake: handshake), name: "http-fallback")
}
