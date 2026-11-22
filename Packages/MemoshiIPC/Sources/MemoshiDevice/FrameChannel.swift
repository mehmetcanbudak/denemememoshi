import Foundation
import NIOCore
import NIOPosix
import Synchronization

/// An ordered, reliable carrier of opaque frames. Pairing uses Noise; ordinary device messages
/// carry genuine MLS ciphertext inside Noise.
///
/// `send` enqueues synchronously, so frames leave in exactly the order `send` is called; that is
/// what keeps Noise's per-direction nonces in step without a lock around every await.
public protocol FrameChannel: Sendable {
  /// Enqueues one frame. Throws once the channel has closed.
  ///
  /// A throw means the channel took no byte of `frame`. `DeviceLink` relies on this: it advances
  /// its Noise send counter only when `send` returns, so an implementation that throws after
  /// handing over any part of the frame would make the link reuse a nonce.
  func send(_ frame: Data) throws
  /// The next frame, in order. Buffered frames precede closure or receive-overflow errors.
  func receive() async throws -> Data
  /// Closes the channel; pending and later receives end.
  func close()
}

/// A lock-protected value in a class, so escaping closures can share it.
final class Locked<Value: Sendable>: Sendable {
  private let mutex: Mutex<Value>

  init(_ value: Value) { mutex = Mutex(value) }

  func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    try mutex.withLock { try body(&$0) }
  }
}

/// One received frame with the receiving side's clock reading when the transport delivered it.
struct ReceivedFrame: Sendable {
  let bytes: Data
  /// The queue's arrival clock when the frame was offered; nil for a queue without one.
  let arrival: Int64?
}

/// A single-consumer queue of received frames with an async wait for the next one.
final class FrameQueue: Sendable {
  enum Offer { case accepted, overflow, terminated }

  private struct Waiter {
    let id: UUID
    let continuation: CheckedContinuation<ReceivedFrame, any Error>
  }

  private struct State {
    var frames = CircularBuffer<ReceivedFrame>(initialCapacity: 16)
    var bytes = 0
    var waiter: Waiter?
    var end: (any Error)?
  }

  private let state = Mutex(State())
  private let maximumFrames: Int
  private let maximumBytes: Int
  private let arrivalClock: (@Sendable () -> Int64)?

  /// `arrivalClock`, when given, stamps each frame as the transport hands it over, before any
  /// consumer queueing delay.
  init(
    maximumFrames: Int = 1_024, maximumBytes: Int = 8 * 1_024 * 1_024,
    arrivalClock: (@Sendable () -> Int64)? = nil
  ) {
    self.maximumFrames = maximumFrames
    self.maximumBytes = maximumBytes
    self.arrivalClock = arrivalClock
  }

  /// Refuses overflow without replacing the accepted FIFO prefix.
  func offer(_ frame: Data) -> Offer {
    let received = ReceivedFrame(bytes: frame, arrival: arrivalClock?())
    var waiter: CheckedContinuation<ReceivedFrame, any Error>?
    let result: Offer = state.withLock { state in
      guard state.end == nil else { return .terminated }
      if let waiting = state.waiter {
        state.waiter = nil
        waiter = waiting.continuation
        return .accepted
      }
      guard state.frames.count < maximumFrames, frame.count <= maximumBytes - state.bytes else {
        state.end = DeviceLayerError.receiveOverflow
        return .overflow
      }
      state.frames.append(received)
      state.bytes += frame.count
      return .accepted
    }
    waiter?.resume(returning: received)
    return result
  }

  /// Ends the stream after the frames already queued.
  func finish(_ error: any Error = DeviceLayerError.closed) {
    let waiter: CheckedContinuation<ReceivedFrame, any Error>? = state.withLock { state in
      guard state.end == nil else { return nil }
      state.end = error
      defer { state.waiter = nil }
      return state.waiter?.continuation
    }
    waiter?.resume(throwing: error)
  }

  /// The next frame; throws the end error once the queue is drained, or on cancellation.
  func next() async throws -> Data { try await nextReceived().bytes }

  /// The next frame with its arrival stamp.
  func nextReceived() async throws -> ReceivedFrame {
    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<ReceivedFrame, any Error>) in
        enum Action {
          case deliver(ReceivedFrame)
          case fail(any Error)
          case wait
        }
        let action: Action = state.withLock { state in
          if Task.isCancelled { return .fail(CancellationError()) }
          if !state.frames.isEmpty {
            let frame = state.frames.removeFirst()
            state.bytes -= frame.bytes.count
            return .deliver(frame)
          }
          if let end = state.end { return .fail(end) }
          if state.waiter != nil { return .fail(DeviceLayerError.invalid("concurrent receive")) }
          state.waiter = Waiter(id: id, continuation: continuation)
          return .wait
        }
        switch action {
        case .deliver(let frame): continuation.resume(returning: frame)
        case .fail(let error): continuation.resume(throwing: error)
        case .wait: break
        }
      }
    } onCancel: {
      let waiter: CheckedContinuation<ReceivedFrame, any Error>? = state.withLock { state in
        guard state.waiter?.id == id else { return nil }
        defer { state.waiter = nil }
        return state.waiter?.continuation
      }
      waiter?.resume(throwing: CancellationError())
    }
  }
}

/// Two in-process channels joined back to back; tests insert themselves between them.
public final class MemoryFrameChannel: FrameChannel {
  private let inbound = FrameQueue()
  private let peer = Mutex<MemoryFrameChannel?>(nil)
  private let closed = Mutex(false)

  private init() {}

  /// A connected pair.
  public static func pair() -> (MemoryFrameChannel, MemoryFrameChannel) {
    let first = MemoryFrameChannel()
    let second = MemoryFrameChannel()
    first.peer.withLock { $0 = second }
    second.peer.withLock { $0 = first }
    return (first, second)
  }

  /// Delivers to the other end.
  public func send(_ frame: Data) throws {
    guard closed.withLock({ !$0 }), let peer = peer.withLock({ $0 }) else {
      throw DeviceLayerError.closed
    }
    switch peer.inbound.offer(frame) {
    case .accepted:
      return
    case .overflow:
      close()
      peer.close()
      throw DeviceLayerError.receiveOverflow
    case .terminated:
      close()
      throw DeviceLayerError.closed
    }
  }

  /// The next frame from the other end.
  public func receive() async throws -> Data { try await inbound.next() }

  /// Closes both directions.
  public func close() {
    closed.withLock { $0 = true }
    inbound.finish()
    let other = peer.withLock { peer in
      defer { peer = nil }
      return peer
    }
    other?.inbound.finish()
  }
}

/// A TCP connection carrying 4-byte big-endian length-prefixed frames.
public final class TCPFrameChannel: FrameChannel {
  /// The largest frame either side accepts: one Noise message plus a small header.
  public static let maximumFrame = 70_000

  private let channel: any Channel
  private let inbound: FrameQueue
  /// Whether `close()` was called. A send and the close both take this lock, so a frame is
  /// either handed to the connection before its close or refused: the close itself runs
  /// later, on the event loop, and a frame handed over after it would be dropped unseen.
  private let closed = Mutex(false)

  init(channel: any Channel, inbound: FrameQueue) {
    self.channel = channel
    self.inbound = inbound
  }

  private struct ConnectState {
    var channel: (any Channel)?
    var continuation: CheckedContinuation<TCPFrameChannel, any Error>?
    var cancelled = false
  }

  /// Connects to `host:port`.
  public static func connect(host: String, port: Int) async throws -> TCPFrameChannel {
    let queue = FrameQueue()
    let pending = Locked(ConnectState())
    let connected = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<TCPFrameChannel, any Error>) in
        let start = pending.withLock { state in
          guard !state.cancelled else { return false }
          state.continuation = continuation
          return true
        }
        guard start else {
          continuation.resume(throwing: CancellationError())
          return
        }
        let future = ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
          .channelOption(.socketOption(.tcp_nodelay), value: 1)
          .channelInitializer { channel in
            channel.eventLoop.makeCompletedFuture {
              let allowed = pending.withLock { state in
                guard !state.cancelled else { return false }
                state.channel = channel
                return true
              }
              guard allowed else {
                channel.close(promise: nil)
                throw CancellationError()
              }
              try FrameCodec.install(on: channel, queue: queue)
            }
          }
          .connect(host: host, port: port)
        future.whenComplete { result in
          let waiter = pending.withLock { state in
            defer { state.continuation = nil }
            return state.continuation
          }
          switch result {
          case .success(let channel):
            if let waiter {
              waiter.resume(returning: TCPFrameChannel(channel: channel, inbound: queue))
            } else {
              channel.close(promise: nil)
            }
          case .failure(let error): waiter?.resume(throwing: error)
          }
        }
      }
    } onCancel: {
      let (channel, waiter) = pending.withLock { state in
        state.cancelled = true
        defer { state.continuation = nil }
        return (state.channel, state.continuation)
      }
      channel?.close(promise: nil)
      queue.finish(CancellationError())
      waiter?.resume(throwing: CancellationError())
    }
    guard !Task.isCancelled else {
      connected.close()
      throw CancellationError()
    }
    return connected
  }

  /// Enqueues one length-prefixed frame.
  public func send(_ frame: Data) throws {
    guard frame.count <= Self.maximumFrame else {
      throw DeviceLayerError.frameTooLarge(frame.count)
    }
    guard channel.isActive else { throw DeviceLayerError.closed }
    var buffer = channel.allocator.buffer(capacity: 4 + frame.count)
    buffer.writeInteger(UInt32(frame.count))
    buffer.writeBytes(frame)
    try closed.withLock { closed in
      guard !closed else { throw DeviceLayerError.closed }
      channel.writeAndFlush(buffer, promise: nil)
    }
  }

  /// The next frame.
  public func receive() async throws -> Data { try await inbound.next() }

  /// The next frame with the arrival stamp its listener's clock took on the event loop.
  func receiveWithArrival() async throws -> ReceivedFrame { try await inbound.nextReceived() }

  /// Closes the connection. Frames sent before this call are written first.
  public func close() {
    closed.withLock { closed in
      closed = true
      channel.close(promise: nil)
    }
    inbound.finish()
  }

  /// The peer's address, for diagnostics.
  public var remoteDescription: String { channel.remoteAddress?.description ?? "unknown" }
}

/// A loopback TCP listener that hands each accepted connection to a handler.
public final class TCPFrameListener: Sendable {
  /// The bound port.
  public let port: Int
  private let listener: any Channel

  private init(port: Int, listener: any Channel) {
    self.port = port
    self.listener = listener
  }

  /// Binds `host` (loopback by default) on an OS-chosen port unless one is given.
  /// `arrivalClock`, when given, stamps every accepted connection's frames as NIO reads them.
  public static func bind(
    host: String = "127.0.0.1", port: Int = 0,
    arrivalClock: (@Sendable () -> Int64)? = nil,
    onConnection: @escaping @Sendable (TCPFrameChannel) -> Void
  ) async throws -> TCPFrameListener {
    let listener = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
      .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
      .childChannelOption(.socketOption(.tcp_nodelay), value: 1)
      .childChannelInitializer { channel in
        let queue = FrameQueue(arrivalClock: arrivalClock)
        return channel.eventLoop.makeCompletedFuture {
          try FrameCodec.install(on: channel, queue: queue)
        }.map {
          onConnection(TCPFrameChannel(channel: channel, inbound: queue))
        }
      }
      .bind(host: host, port: port).get()
    guard let bound = listener.localAddress?.port else {
      listener.close(promise: nil)
      throw DeviceLayerError.io("listener has no port")
    }
    return TCPFrameListener(port: bound, listener: listener)
  }

  /// Stops accepting; existing connections stay open.
  public func close() async {
    try? await listener.close().get()
  }
}

enum FrameCodec {
  static func install(on channel: any Channel, queue: FrameQueue) throws {
    try channel.pipeline.syncOperations.addHandler(
      ByteToMessageHandler(LengthPrefixedDecoder(maximum: TCPFrameChannel.maximumFrame)))
    try channel.pipeline.syncOperations.addHandler(FrameSink(queue: queue))
  }
}

private struct LengthPrefixedDecoder: ByteToMessageDecoder {
  typealias InboundOut = ByteBuffer
  let maximum: Int

  mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws
    -> DecodingState
  {
    guard let length = buffer.getInteger(at: buffer.readerIndex, as: UInt32.self) else {
      return .needMoreData
    }
    guard Int(length) <= maximum else { throw DeviceLayerError.frameTooLarge(Int(length)) }
    guard buffer.readableBytes >= 4 + Int(length) else { return .needMoreData }
    buffer.moveReaderIndex(forwardBy: 4)
    guard let frame = buffer.readSlice(length: Int(length)) else { return .needMoreData }
    context.fireChannelRead(wrapInboundOut(frame))
    return .continue
  }
}

/// NIO calls every method on the channel's event loop.
private final class FrameSink: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = ByteBuffer
  private let queue: FrameQueue
  private var stopped = false

  init(queue: FrameQueue) { self.queue = queue }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    guard !stopped else { return }
    let buffer = unwrapInboundIn(data)
    switch queue.offer(Data(buffer.readableBytesView)) {
    case .accepted:
      break
    case .overflow, .terminated:
      stopped = true
      context.close(promise: nil)
    }
  }

  func channelInactive(context: ChannelHandlerContext) {
    stopped = true
    queue.finish()
    context.fireChannelInactive()
  }

  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    stopped = true
    queue.finish(error)
    context.close(promise: nil)
  }
}
