import Foundation
import NIOCore
import NIOFoundationCompat
import NIOPosix
import NIOWebSocket
import Security
import Synchronization

/// Exactly one task may consume `messages`. Messages are complete UTF-8 text;
/// JSON-RPC decoding belongs to the protocol layer. Close always terminates it.
public struct LocalConnection: Sendable {
  /// The dynamically validated identity of the process on this connection.
  public let peer: PeerIdentity
  /// Complete text messages, ending with an explicit error on data loss or abnormal closure.
  public let messages: AsyncThrowingStream<Data, any Error>
  internal let state: ConnectionState
  private let resources: EventLoopOwner?

  internal init(peer: PeerIdentity, state: ConnectionState, resources: EventLoopOwner? = nil) {
    self.peer = peer
    self.state = state
    self.messages = state.stream
    self.resources = resources
  }

  /// Rechecks the running peer on this connection's same descriptor before releasing a secret.
  /// A cached handshake identity is not authority after a peer executable changes. The
  /// descriptor is read on the event loop; the code-signature check runs off it.
  public func revalidatePeer(policy: PeerPolicy) async throws -> PeerIdentity {
    try Task.checkCancellation()
    let state = state
    let expected = peer
    let guest = try await state.perform {
      guard !state.closing, state.channel.isActive else {
        throw IPCError.closed(code: 1001, reason: "Connection is closing")
      }
      return try PeerAuthentication.guest(channel: state.channel)
    }
    let current = try await PeerAuthentication.validating {
      try PeerAuthentication.validate(guest, policy: policy)
    }
    try Task.checkCancellation()
    guard current == expected else {
      throw IPCError.authenticationFailed(status: errSecAuthFailed)
    }
    return current
  }

  /// Completes only when the channel has drained this message to the socket.
  public func send(_ data: Data) async throws {
    try Task.checkCancellation()
    guard data.count <= TransportLimits.outboundFrameBytes else { throw IPCError.messageTooLarge }
    guard isValidUTF8(data) else {
      state.requestClose(code: 1007, reason: "Text must be UTF-8")
      throw IPCError.closed(code: 1007, reason: "Text must be UTF-8")
    }
    guard state.outbound.reserve(bytes: data.count + 14) else {
      state.requestClose(code: 4429, reason: "Outbound queue overflow")
      throw IPCError.outboundOverflow
    }
    defer { state.outbound.release(bytes: data.count + 14) }
    try await state.submit(data)
  }

  /// Performs the WebSocket closing handshake, with a bounded two-second drain.
  public func close(code: Int = 1000, reason: String = "") async {
    state.requestClose(code: code, reason: reason)
    await waitUntilClosed()
  }

  /// Includes owned client event-loop shutdown, not merely descriptor closure.
  public func waitUntilClosed() async {
    await state.closed.wait()
    if let resources { await resources.waitUntilStopped() }
  }
}

internal enum TransportLimits {
  static let serverMessageBytes = 1_048_576
  static let clientMessageBytes = 4_194_304
  static let outboundFrameBytes = 4_194_304
  static let queuedBytes = 8_388_608
  static let queuedFrames = 10_000
  /// One socket read: the fixed receive buffer, with one read per `read()`.
  static let receiveChunkBytes = 16_384
  /// Reads are gated per socket read, not per message. Just below this mark the largest
  /// message may still complete, in a read that also carries the messages after it, and the
  /// hard `queuedBytes` ceiling must hold all of that from a peer that obeys every limit.
  static let receiveHighBytes = queuedBytes - clientMessageBytes - receiveChunkBytes
  static let receiveHighFrames = 1_024
  static let fragments = 1_024
  static let handshakeBytes = 16_384
}

/// Counts reservations before crossing to the event loop, so concurrent callers
/// cannot hide an unbounded backlog in the event loop's task queue.
internal final class SendBudget: @unchecked Sendable {
  private let lock = NSLock()
  private var bytes = 0
  private var frames = 0

  func reserve(bytes count: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard count >= 0, count <= TransportLimits.queuedBytes - bytes,
      frames < TransportLimits.queuedFrames
    else { return false }
    bytes += count
    frames += 1
    return true
  }

  func release(bytes count: Int) {
    lock.lock()
    bytes -= count
    frames -= 1
    lock.unlock()
  }
}

internal final class AsyncLatch: @unchecked Sendable {
  private let lock = NSLock()
  private var finished = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func finish() {
    let waiting = lock.withLock {
      finished = true
      let waiting = continuations
      continuations.removeAll()
      return waiting
    }
    for continuation in waiting { continuation.resume() }
  }

  func wait() async {
    await withCheckedContinuation { continuation in
      let alreadyFinished = lock.withLock {
        if finished { return true }
        continuations.append(continuation)
        return false
      }
      if alreadyFinished { continuation.resume() }
    }
  }
}

/// One owner per client connection or listener; shutdown starts exactly once.
internal final class EventLoopOwner: @unchecked Sendable {
  let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  private let lock = NSLock()
  private var stopping = false
  private let stopped = AsyncLatch()

  func stop() {
    let shouldStop = lock.withLock {
      if stopping { return false }
      stopping = true
      return true
    }
    if shouldStop { group.shutdownGracefully { [stopped] _ in stopped.finish() } }
  }

  func waitUntilStopped() async { await stopped.wait() }
}

/// Cancellation can revoke a queued write, but cannot retract bytes after writing starts.
private final class SendSubmission: Sendable {
  private enum State { case queued, started, canceled }
  private let state = Mutex(State.queued)

  func begin() -> Bool {
    state.withLock {
      guard case .queued = $0 else { return false }
      $0 = .started
      return true
    }
  }

  func cancel() {
    state.withLock {
      if case .queued = $0 { $0 = .canceled }
    }
  }
}

/// All mutable protocol state is confined to `channel.eventLoop`.
internal final class ConnectionState: @unchecked Sendable {
  let channel: any Channel
  let isServer: Bool
  let stream: AsyncThrowingStream<Data, any Error>
  let mailbox: ReceiveMailbox
  let outbound = SendBudget()
  let closed = AsyncLatch()
  private let submissionLock = NSLock()
  private var submissionsClosed = false
  var upgraded = false
  private var readOutstanding = false
  var closing = false
  var terminalError: (any Error)?
  var closeTimeout: Scheduled<Void>?
  var pingTask: RepeatedTask?
  var unansweredPings: [UInt64] = []
  var pingSequence: UInt64 = 0

  init(channel: any Channel, isServer: Bool) {
    self.channel = channel
    self.isServer = isServer
    let mailbox = ReceiveMailbox()
    self.mailbox = mailbox
    self.stream = AsyncThrowingStream(unfolding: { try await mailbox.next() })
    mailbox.configure(
      onDemand: { [weak self] in self?.requestRead() },
      onCancel: { [weak self] in
        self?.requestClose(code: 1001, reason: "Receive consumer cancelled")
      })
    channel.closeFuture.whenComplete { [weak self, closed] _ in
      if let self { self.submissionLock.withLock { self.submissionsClosed = true } }
      closed.finish()
    }
  }

  func submit(_ data: Data) async throws {
    let submission = SendSubmission()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let scheduled = submissionLock.withLock {
          guard !submissionsClosed else { return false }
          channel.eventLoop.execute {
            guard submission.begin() else {
              continuation.resume(throwing: CancellationError())
              return
            }
            self.send(data).whenComplete { continuation.resume(with: $0) }
          }
          return true
        }
        if !scheduled {
          continuation.resume(throwing: IPCError.closed(code: 1006, reason: "Connection closed"))
        }
      }
    } onCancel: {
      submission.cancel()
    }
  }

  /// Runs `body` on the event loop. Like `submit`, it fails once the channel has closed instead
  /// of handing work to an owned loop that may have stopped: a stopped loop drops the task.
  func perform<Value: Sendable>(
    _ body: @escaping @Sendable () throws -> Value
  ) async throws -> Value {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Value, any Error>) in
      let scheduled = submissionLock.withLock {
        guard !submissionsClosed else { return false }
        channel.eventLoop.execute { continuation.resume(with: Result { try body() }) }
        return true
      }
      if !scheduled {
        continuation.resume(throwing: IPCError.closed(code: 1006, reason: "Connection closed"))
      }
    }
  }

  func requestClose(code: Int, reason: String) {
    submissionLock.withLock {
      guard !submissionsClosed else { return }
      channel.eventLoop.execute { self.close(code: code, reason: reason) }
    }
  }

  private func requestRead() {
    submissionLock.withLock {
      guard !submissionsClosed else { return }
      channel.eventLoop.execute { self.readIfCapacity() }
    }
  }

  func readIfCapacity() {
    channel.eventLoop.assertInEventLoop()
    guard upgraded, !closing, !readOutstanding, mailbox.canRead else { return }
    readOutstanding = true
    channel.read()
  }

  func readComplete() {
    channel.eventLoop.assertInEventLoop()
    readOutstanding = false
    if closing { channel.read() } else { readIfCapacity() }
  }

  func send(_ data: Data) -> EventLoopFuture<Void> {
    channel.eventLoop.assertInEventLoop()
    guard !closing, channel.isActive else {
      return channel.eventLoop.makeFailedFuture(
        terminalError ?? IPCError.closed(code: 1006, reason: "Connection closed"))
    }
    var payload = channel.allocator.buffer(capacity: data.count)
    payload.writeBytes(data)
    return channel.writeAndFlush(frame(opcode: .text, data: payload))
  }

  func frame(opcode: WebSocketOpcode, data: ByteBuffer) -> WebSocketFrame {
    WebSocketFrame(fin: true, opcode: opcode, maskKey: isServer ? nil : .random(), data: data)
  }

  @discardableResult
  func writeControl(opcode: WebSocketOpcode, data: ByteBuffer) -> EventLoopFuture<Void> {
    channel.eventLoop.assertInEventLoop()
    let bytes = data.readableBytes + 14
    guard outbound.reserve(bytes: bytes) else {
      terminalError = IPCError.outboundOverflow
      mailbox.finish(IPCError.outboundOverflow)
      channel.close(promise: nil)
      return channel.eventLoop.makeFailedFuture(IPCError.outboundOverflow)
    }
    let result = channel.writeAndFlush(frame(opcode: opcode, data: data))
    result.whenComplete { [outbound] _ in outbound.release(bytes: bytes) }
    return result
  }

  func deliver(_ payload: ByteBuffer) {
    channel.eventLoop.assertInEventLoop()
    guard !closing else { return }
    guard isValidUTF8(payload.readableBytesView) else {
      close(code: 1007, reason: "Invalid UTF-8")
      return
    }
    guard
      let data = payload.getData(
        at: payload.readerIndex, length: payload.readableBytes, byteTransferStrategy: .noCopy)
    else {
      close(code: 4500, reason: "Invalid payload buffer")
      return
    }
    switch mailbox.offer(data) {
    case .enqueued: break
    case .overflow:
      terminalError = IPCError.receiveOverflow
      close(code: 4429, reason: "Receive queue overflow")
    case .terminated:
      close(code: 1001, reason: "Receive consumer ended")
    }
  }

  func close(code requested: Int, reason: String) {
    channel.eventLoop.assertInEventLoop()
    guard !closing else { return }
    closing = true
    pingTask?.cancel()
    pingTask = nil
    let code = Self.isValidCloseCode(requested) ? requested : 1002
    let reason = Self.closeReason(reason)
    let error = terminalError ?? IPCError.closed(code: code, reason: reason)
    terminalError = error
    mailbox.finish(error)
    guard upgraded, channel.isActive else {
      channel.close(promise: nil)
      return
    }
    channel.read()
    var data = channel.allocator.buffer(capacity: 125)
    data.writeInteger(UInt16(code))
    data.writeString(reason)
    let channel = self.channel
    closeTimeout = channel.eventLoop.scheduleTask(in: .seconds(2)) { channel.close(promise: nil) }
    writeControl(opcode: .connectionClose, data: data).whenFailure { _ in
      channel.close(promise: nil)
    }
  }

  /// A failed socket cannot carry a closing handshake, and the failure is not the peer's
  /// protocol violation: the stream ends with the system error.
  func fail(_ error: IPCError) {
    channel.eventLoop.assertInEventLoop()
    guard !closing else { return }
    closing = true
    pingTask?.cancel()
    pingTask = nil
    terminalError = error
    mailbox.finish(error)
    channel.close(promise: nil)
  }

  func receivedClose(_ payload: ByteBuffer) {
    channel.eventLoop.assertInEventLoop()
    var content = payload
    guard content.readableBytes != 1 else {
      close(code: 1002, reason: "Malformed close payload")
      return
    }
    let code = content.readInteger(as: UInt16.self).map(Int.init) ?? 1005
    guard code == 1005 && payload.readableBytes == 0 || Self.isValidCloseCode(code) else {
      close(code: 1002, reason: "Invalid close status")
      return
    }
    guard let reason = String(bytes: content.readableBytesView, encoding: .utf8) else {
      close(code: 1007, reason: "Invalid close reason")
      return
    }
    closeTimeout?.cancel()
    closeTimeout = nil
    pingTask?.cancel()
    pingTask = nil
    if closing {
      channel.close(promise: nil)
      return
    }
    closing = true
    let error = IPCError.closed(code: code, reason: reason)
    terminalError = error
    mailbox.finish(error)
    let channel = self.channel
    closeTimeout = channel.eventLoop.scheduleTask(in: .seconds(2)) { channel.close(promise: nil) }
    writeControl(opcode: .connectionClose, data: payload).whenComplete { _ in
      channel.close(promise: nil)
    }
  }

  func didClose() {
    channel.eventLoop.assertInEventLoop()
    closing = true
    pingTask?.cancel()
    pingTask = nil
    closeTimeout?.cancel()
    closeTimeout = nil
    mailbox.finish(terminalError ?? IPCError.closed(code: 1006, reason: "Peer disconnected"))
  }

  func startPings() {
    channel.eventLoop.assertInEventLoop()
    guard isServer, pingTask == nil, !closing else { return }
    pingTask = channel.eventLoop.scheduleRepeatedTask(
      initialDelay: .seconds(15), delay: .seconds(15)
    ) {
      [weak self] _ in
      guard let self, !self.closing else { return }
      if self.unansweredPings.count == 2 {
        self.close(code: 1001, reason: "Two missed pongs")
        return
      }
      self.pingSequence &+= 1
      self.unansweredPings.append(self.pingSequence)
      var data = self.channel.allocator.buffer(capacity: 8)
      data.writeInteger(self.pingSequence)
      let channel = self.channel
      self.writeControl(opcode: .ping, data: data).whenFailure { _ in
        channel.close(promise: nil)
      }
    }
  }

  static func isValidCloseCode(_ code: Int) -> Bool {
    (1000...1003).contains(code) || (1007...1014).contains(code) || (3000...4999).contains(code)
  }

  private static func closeReason(_ value: String) -> String {
    var result = ""
    var count = 0
    for scalar in value.unicodeScalars {
      let number = scalar.value
      let size = number < 0x80 ? 1 : number < 0x800 ? 2 : number < 0x10000 ? 3 : 4
      if count + size > 123 { break }
      result.unicodeScalars.append(scalar)
      count += size
    }
    return result
  }
}

/// Strict decoding without materializing a second, unused String allocation.
internal func isValidUTF8<Bytes: Sequence>(_ bytes: Bytes) -> Bool where Bytes.Element == UInt8 {
  var iterator = bytes.makeIterator()
  var decoder = Unicode.UTF8()
  while true {
    switch decoder.decode(&iterator) {
    case .scalarValue: continue
    case .emptyInput: return true
    case .error: return false
    }
  }
}
