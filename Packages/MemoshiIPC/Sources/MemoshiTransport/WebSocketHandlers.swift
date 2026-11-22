import Foundation
import NIOCore
import NIOWebSocket

/// Validates fields that NIO intentionally leaves to applications/extensions.
/// It precedes aggregation so masking and RSV violations cannot be erased by it.
internal final class FrameValidationHandler: ChannelInboundHandler {
  typealias InboundIn = WebSocketFrame
  typealias InboundOut = WebSocketFrame
  private let state: ConnectionState

  init(state: ConnectionState) { self.state = state }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let frame = Self.unwrapInboundIn(data)
    guard !frame.rsv1, !frame.rsv2, !frame.rsv3, frame.extensionData == nil,
      (frame.maskKey != nil) == state.isServer
    else {
      state.close(code: 1002, reason: "Invalid WebSocket flags or masking")
      return
    }
    guard !state.closing else {
      if frame.opcode == .connectionClose { context.fireChannelRead(data) }
      return
    }
    switch frame.opcode {
    case .text, .continuation: break
    case .binary:
      state.close(code: 4400, reason: "Binary messages are reserved")
      return
    case .ping, .pong, .connectionClose:
      guard frame.fin, frame.length <= 125 else {
        state.close(code: 1002, reason: "Invalid control frame")
        return
      }
    default:
      state.close(code: 1002, reason: "Reserved WebSocket opcode")
      return
    }
    context.fireChannelRead(data)
  }
}

internal final class MessageHandler: ChannelInboundHandler {
  typealias InboundIn = WebSocketFrame
  private let state: ConnectionState

  init(state: ConnectionState) { self.state = state }

  func handlerAdded(context: ChannelHandlerContext) {
    state.startPings()
    state.readIfCapacity()
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let frame = Self.unwrapInboundIn(data)
    var payload = frame.unmaskedData
    switch frame.opcode {
    case .text:
      state.deliver(payload)
    case .ping:
      guard !state.closing else { return }
      let channel = context.channel
      state.writeControl(opcode: .pong, data: payload).whenFailure { _ in
        channel.close(promise: nil)
      }
    case .pong:
      if payload.readableBytes == 8, let sequence = payload.readInteger(as: UInt64.self),
        let index = state.unansweredPings.firstIndex(of: sequence)
      {
        state.unansweredPings.removeFirst(index + 1)
      }
    case .connectionClose:
      state.receivedClose(payload)
    default:
      state.close(code: 1002, reason: "Unexpected WebSocket fragment")
    }
  }

  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    switch error {
    case NIOWebSocketError.invalidFrameLength,
      NIOWebSocketFrameAggregator.Error.accumulatedFrameSizeIsTooLarge,
      NIOWebSocketFrameAggregator.Error.tooManyFragments:
      state.close(code: 1009, reason: "WebSocket message limit exceeded")
    case let error as IOError:
      state.fail(IPCError.systemCall(operation: "read Unix socket", code: error.errnoCode))
    default:
      state.close(code: 1002, reason: "Malformed WebSocket message")
    }
  }

  func channelReadComplete(context: ChannelHandlerContext) {
    state.readComplete()
    context.fireChannelReadComplete()
  }

  func channelInactive(context: ChannelHandlerContext) {
    state.didClose()
    context.fireChannelInactive()
  }
}

internal func installMessageHandlers(state: ConnectionState) throws {
  guard let options = state.channel.syncOptions else { throw IPCError.upgradeFailed }
  try options.setOption(.autoRead, value: false)
  state.upgraded = true
  let limit =
    state.isServer ? TransportLimits.serverMessageBytes : TransportLimits.clientMessageBytes
  let pipeline = state.channel.pipeline.syncOperations
  try pipeline.addHandler(FrameValidationHandler(state: state))
  try pipeline.addHandler(
    NIOWebSocketFrameAggregator(
      minNonFinalFragmentSize: 0,
      maxAccumulatedFrameCount: TransportLimits.fragments,
      maxAccumulatedFrameSize: limit))
  try pipeline.addHandler(MessageHandler(state: state))
}
