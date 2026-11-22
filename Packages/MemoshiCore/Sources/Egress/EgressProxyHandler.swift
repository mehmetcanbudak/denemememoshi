import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL

/// One proxy connection: its first request head is decided, then either tunneled (`CONNECT`) or
/// forwarded once with `Connection: close`. While a request is being decided the connection
/// stops reading, so no further client bytes are parsed or relayed before the verdict. A
/// forwarded body is then read only while its upstream can take it. Every refusal, including a
/// `407` challenge, closes the connection: at most one challenge each; so does a head that
/// does not arrive in time. NIO invokes every handler method on the owning channel's event loop.
final class EgressProxyHandler: ChannelDuplexHandler, RemovableChannelHandler,
  @unchecked Sendable
{
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundIn = Never
  typealias OutboundOut = HTTPServerResponsePart

  static let decoderName = "memoshi.egress.decoder"
  static let encoderName = "memoshi.egress.encoder"
  /// Request bytes already read when a decision started; reading stops until it is applied.
  static let pendingLimit = 1 << 20

  private enum Phase {
    case awaitingHead
    case deciding
    case forwarding(any Channel)
    case finished
  }

  private let core: EgressClientCore
  private let intercepted: EgressInterceptedTarget?
  private let endOfInput: EgressEndOfInput?
  private var phase = Phase.awaitingHead
  private var tunnel = false
  private var pending: [HTTPServerRequestPart] = []
  private var pendingBytes = 0
  private var decisionTask: Task<EgressVerdict, Never>?
  private var headDeadline: Scheduled<Void>?
  private var nativeDrain: EventLoopPromise<Void>?
  private var nativeConnecting = false
  private var nativeUpstream: (any Channel)?
  private var inactive = false

  init(
    core: EgressClientCore, intercepted: EgressInterceptedTarget? = nil,
    endOfInput: EgressEndOfInput? = nil
  ) {
    self.core = core
    self.intercepted = intercepted
    self.endOfInput = endOfInput
  }

  func handlerAdded(context: ChannelHandlerContext) {
    // Only the wait for the head is bounded; deciding it may take as long as policy needs.
    let bound = NIOLoopBound((self, context), eventLoop: context.eventLoop)
    headDeadline = context.eventLoop.scheduleTask(in: core.limits.headDeadline) {
      let (handler, context) = bound.value
      if case .awaitingHead = handler.phase { handler.finish(context: context) }
    }
  }

  func handlerRemoved(context: ChannelHandlerContext) {
    headDeadline?.cancel()
    headDeadline = nil
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let part = unwrapInboundIn(data)
    switch phase {
    case .awaitingHead:
      headDeadline?.cancel()
      headDeadline = nil
      guard case .head(let originalHead) = part else {
        finish(context: context)
        return
      }
      var head = originalHead
      if head.headers.contains(name: EgressFetchOperation.markerHeader) {
        let keys = head.headers[EgressFetchOperation.markerHeader]
        guard keys.count == 1,
          let operation = core.nativeFetches.withLock({ $0[keys[0]] })
        else {
          finish(context: context)
          return
        }
        let drained = context.eventLoop.makePromise(of: Void.self)
        guard operation.attachGateway(context.channel, drained: drained.futureResult) else {
          drained.succeed(())
          finish(context: context)
          return
        }
        nativeDrain = drained
        head.headers.remove(name: EgressFetchOperation.markerHeader)
      }
      decide(head, context: context)
    case .deciding:
      guard !tunnel else { return }
      if case .body(let buffer) = part { pendingBytes += buffer.readableBytes }
      guard pendingBytes <= Self.pendingLimit else {
        respond(.payloadTooLarge, context: context)
        return
      }
      pending.append(part)
    case .forwarding(let upstream):
      switch part {
      case .head:
        finish(context: context)
      case .body(let buffer):
        upstream.write(HTTPClientRequestPart.body(.byteBuffer(buffer)), promise: nil)
      case .end(let trailers):
        upstream.writeAndFlush(HTTPClientRequestPart.end(trailers), promise: nil)
      }
    case .finished:
      break
    }
  }

  func channelReadComplete(context: ChannelHandlerContext) {
    if case .forwarding(let upstream) = phase { upstream.flush() }
    context.fireChannelReadComplete()
  }

  /// Nothing is read while a request is being decided. A forwarded request is then read only
  /// while its upstream is writable, so an upload is buffered by the sender, not here; the
  /// upstream's relay asks again once it can take more.
  func read(context: ChannelHandlerContext) {
    switch phase {
    case .deciding: return
    case .forwarding(let upstream) where !upstream.isWritable: return
    default: context.read()
    }
  }

  func channelWritabilityChanged(context: ChannelHandlerContext) {
    // The client can take more of the response: let the upstream's relay read again.
    if context.channel.isWritable, case .forwarding(let upstream) = phase { upstream.read() }
    context.fireChannelWritabilityChanged()
  }

  func channelInactive(context: ChannelHandlerContext) {
    headDeadline?.cancel()
    headDeadline = nil
    decisionTask?.cancel()
    if let upstream = nativeUpstream {
      upstream.close(promise: nil)
    } else if case .forwarding(let upstream) = phase {
      upstream.close(promise: nil)
    }
    phase = .finished
    inactive = true
    pending.removeAll()
    completeNativeDrain()
    context.fireChannelInactive()
  }

  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    finish(context: context)
  }

  private func decide(_ head: HTTPRequestHead, context: ChannelHandlerContext) {
    phase = .deciding
    tunnel = head.method == .CONNECT
    // A tunnel's end of input waits for the verdict; see `EgressEndOfInput`.
    if tunnel { endOfInput?.hold() }
    try? context.channel.syncOptions?.setOption(.autoRead, value: false)
    let core = core
    let bound = NIOLoopBound((self, context), eventLoop: context.eventLoop)
    let intercepted = intercepted
    let channel = context.channel
    let task = Task { await core.decide(head, channel: channel, intercepted: intercepted) }
    decisionTask = task
    let decided = context.eventLoop.makeFutureWithTask { await task.value }
    decided.whenComplete { result in
      let (handler, context) = bound.value
      handler.decisionTask = nil
      defer { handler.completeNativeDrain() }
      switch result {
      case .success(.allow(let route)): handler.connect(route, context: context)
      case .success(.deny): handler.respond(.forbidden, context: context)
      case .success(.challenge): handler.respond(.proxyAuthenticationRequired, context: context)
      case .failure: handler.respond(.badGateway, context: context)
      }
    }
    // Registered after the handler's own callback, so a client that waits sees it applied.
    core.decisions.add(decided)
  }

  private func connect(_ route: EgressRoute, context: ChannelHandlerContext) {
    guard case .deciding = phase else { return }
    guard core.isActive(route.attribution) else {
      finish(context: context)
      return
    }
    if route.interception != nil {
      intercept(route, context: context)
      return
    }
    nativeConnecting = nativeDrain != nil
    dial(route, at: 0, until: .now() + .seconds(10), context: context)
  }

  /// Dials the route's checked addresses in order until one connects, sharing one connect
  /// deadline evenly among those not yet tried. Nothing is resolved again.
  private func dial(
    _ route: EgressRoute, at index: Int, until deadline: NIODeadline,
    context: ChannelHandlerContext
  ) {
    let downstream = NIOLoopBound(context, eventLoop: context.eventLoop)
    let forwarded = route.head
    let protections = route.protections
    let tlsContext = core.upstreamTLS
    let bound = NIOLoopBound((self, context), eventLoop: context.eventLoop)
    let remaining = max(0, (deadline - .now()).nanoseconds)
    let bootstrap = ClientBootstrap(group: context.eventLoop)
      .connectTimeout(.nanoseconds(remaining / Int64(route.addresses.count - index)))
      .channelOption(.allowRemoteHalfClosure, value: forwarded == nil)
      .channelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
          let (handler, _) = bound.value
          handler.trackNativeUpstream(channel)
          if let host = route.tlsHost {
            try channel.pipeline.syncOperations.addHandler(
              NIOSSLClientHandler(context: tlsContext, serverHostname: host))
          }
          guard let forwarded else { return }
          try channel.pipeline.syncOperations.addHTTPClientHandlers()
          try channel.pipeline.syncOperations.addHandler(
            EgressUpstreamRelay(
              downstream: downstream, protections: protections, requestMethod: forwarded.method))
        }
      }
    bootstrap.connect(to: core.dialed(route.addresses[index])).whenComplete { result in
      let (handler, context) = bound.value
      if case .failure = result, case .deciding = handler.phase,
        index + 1 < route.addresses.count, NIODeadline.now() < deadline,
        handler.core.isActive(route.attribution)
      {
        handler.dial(route, at: index + 1, until: deadline, context: context)
        return
      }
      handler.nativeConnecting = false
      defer { handler.completeNativeDrain() }
      switch result {
      case .success(let upstream):
        guard handler.core.isActive(route.attribution) else {
          upstream.close(promise: nil)
          handler.finish(context: context)
          return
        }
        route.attribution.live.connections.add(upstream)
        if let forwarded {
          handler.forward(forwarded, to: upstream, context: context)
        } else {
          handler.tunnel(to: upstream, context: context)
        }
      case .failure:
        handler.respond(.badGateway, context: context)
      }
    }
  }

  private func forward(
    _ head: HTTPRequestHead, to upstream: any Channel, context: ChannelHandlerContext
  ) {
    guard context.channel.isActive, case .deciding = phase else {
      upstream.close(promise: nil)
      return
    }
    phase = .forwarding(upstream)
    upstream.write(HTTPClientRequestPart.head(head), promise: nil)
    for part in pending {
      switch part {
      case .head: break
      case .body(let buffer):
        upstream.write(HTTPClientRequestPart.body(.byteBuffer(buffer)), promise: nil)
      case .end(let trailers):
        upstream.write(HTTPClientRequestPart.end(trailers), promise: nil)
      }
    }
    pending.removeAll()
    upstream.flush()
    try? context.channel.syncOptions?.setOption(.autoRead, value: true)
    read(context: context)
  }

  /// Replaces only a secret-bound CONNECT with a scoped TLS server. The decrypted connection
  /// gets a fresh HTTP decision for each request and is pinned to this CONNECT's exact host,
  /// port and live call. Supplied certificates never affect upstream verification.
  private func intercept(_ route: EgressRoute, context: ChannelHandlerContext) {
    guard let tls = route.interception, case .deciding = phase else { return }
    phase = .finished
    let operations = context.pipeline.syncOperations
    operations.removeHandler(name: Self.encoderName, promise: nil)
    context.writeAndFlush(
      NIOAny(
        context.channel.allocator.buffer(
          string: "HTTP/1.1 200 Connection Established\r\n\r\n")), promise: nil)
    do {
      try operations.addHandler(NIOSSLServerHandler(context: tls), position: .after(self))
      try operations.addHandler(
        ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .dropBytes)),
        name: "memoshi.egress.intercepted.decoder")
      try operations.addHandler(HTTPResponseEncoder(), name: Self.encoderName)
      try operations.addHandler(
        EgressProxyHandler(
          core: core,
          intercepted: EgressInterceptedTarget(
            host: route.host, port: route.port, attribution: route.attribution)))
      operations.removeHandler(context: context, promise: nil)
      let endOfInput = endOfInput
      operations.removeHandler(name: Self.decoderName).whenComplete { _ in endOfInput?.release() }
    } catch {
      context.close(promise: nil)
      return
    }
    try? context.channel.syncOptions?.setOption(.autoRead, value: true)
    context.channel.read()
  }

  /// Answers `200` without HTTP framing, then joins both connections byte for byte. The request
  /// decoder is removed last, forwarding anything the client sent after its request.
  private func tunnel(to upstream: any Channel, context: ChannelHandlerContext) {
    guard context.channel.isActive, case .deciding = phase else {
      upstream.close(promise: nil)
      return
    }
    phase = .finished
    let operations = context.pipeline.syncOperations
    // On the event loop the encoder leaves at once, so the raw answer below is not reframed.
    operations.removeHandler(name: Self.encoderName, promise: nil)
    context.writeAndFlush(
      NIOAny(
        context.channel.allocator.buffer(string: "HTTP/1.1 200 Connection Established\r\n\r\n")),
      promise: nil)
    let channel = context.channel
    let (local, peer) = EgressGlueHandler.matchedPair(
      flushDeadline: core.limits.flushDeadline, upstreamCountedIn: core.connections)
    do {
      try upstream.pipeline.syncOperations.addHandler(peer)
      try operations.addHandler(local, position: .after(self))
      operations.removeHandler(context: context, promise: nil)
    } catch {
      upstream.close(promise: nil)
      channel.close(promise: nil)
      return
    }
    let endOfInput = endOfInput
    operations.removeHandler(name: Self.decoderName).whenComplete { _ in
      upstream.flush()
      // After the bytes the client sent with its request, the end of input it sent with them.
      endOfInput?.release()
    }
    try? channel.syncOptions?.setOption(.autoRead, value: true)
    channel.read()
  }

  private func respond(_ status: HTTPResponseStatus, context: ChannelHandlerContext) {
    guard case .deciding = phase else { return }
    phase = .finished
    pending.removeAll()
    let text =
      switch status {
      case .forbidden: "Blocked by Memoshi egress policy.\n"
      case .proxyAuthenticationRequired: "Proxy authentication required.\n"
      default: "Unavailable.\n"
      }
    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "text/plain; charset=utf-8")
    headers.add(name: "content-length", value: String(text.utf8.count))
    if status == .proxyAuthenticationRequired {
      headers.add(name: "proxy-authenticate", value: "Basic realm=\"memoshi\"")
    }
    headers.add(name: "connection", value: "close")
    context.write(
      wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: status, headers: headers))),
      promise: nil)
    context.write(
      wrapOutboundOut(.body(.byteBuffer(context.channel.allocator.buffer(string: text)))),
      promise: nil)
    let channel = context.channel
    context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
      channel.close(promise: nil)
    }
  }

  private func finish(context: ChannelHandlerContext) {
    if case .forwarding(let upstream) = phase { upstream.close(promise: nil) }
    phase = .finished
    context.close(promise: nil)
  }

  private func trackNativeUpstream(_ channel: any Channel) {
    guard nativeDrain != nil else { return }
    nativeUpstream = channel
    let bound = NIOLoopBound(self, eventLoop: channel.eventLoop)
    channel.closeFuture.whenComplete { _ in
      let handler = bound.value
      // A failed attempt's channel closes after the next address has taken its place.
      if handler.nativeUpstream === channel { handler.nativeUpstream = nil }
      handler.completeNativeDrain()
    }
    if inactive { channel.close(promise: nil) }
  }

  private func completeNativeDrain() {
    guard inactive, decisionTask == nil, !nativeConnecting, nativeUpstream == nil,
      let drained = nativeDrain
    else { return }
    nativeDrain = nil
    drained.succeed(())
  }
}

/// First in a proxy connection's pipeline. A client may end its input in the same breath as its
/// `CONNECT`; that event then arrives while the request is being decided, before any tunnel
/// exists to carry it. It is held here, ahead of the request decoder, and delivered once an
/// allowed tunnel is in place: the decoder still forwards the bytes sent with the request, and
/// the upstream sees the end of input after them. A refused request never delivers it.
/// NIO invokes every handler method on the owning channel's event loop.
final class EgressEndOfInput: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = ByteBuffer

  private var context: ChannelHandlerContext?
  private var holding = false
  private var held = false

  func handlerAdded(context: ChannelHandlerContext) { self.context = context }

  func handlerRemoved(context: ChannelHandlerContext) { self.context = nil }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    if holding, let event = event as? ChannelEvent, case .inputClosed = event {
      held = true
      return
    }
    context.fireUserInboundEventTriggered(event)
  }

  func hold() { holding = true }

  func release() {
    holding = false
    guard held, let context else { return }
    held = false
    context.fireUserInboundEventTriggered(ChannelEvent.inputClosed)
  }
}

/// Relays one upstream response to the proxy client, dropping secret-bearing header names and
/// scrubbing header values and the body before they reach the sandbox. The response is read
/// only while the client can take it. NIO invokes every handler method on the owning channel's
/// event loop, which the downstream connection shares.
final class EgressUpstreamRelay: ChannelDuplexHandler, @unchecked Sendable {
  typealias InboundIn = HTTPClientResponsePart
  typealias OutboundIn = HTTPClientRequestPart
  typealias OutboundOut = HTTPClientRequestPart

  private let downstream: NIOLoopBound<ChannelHandlerContext>
  private let protections: EgressDecisionLog
  private let requestMethod: HTTPMethod
  private var scrubber = EgressEchoScrubber(values: [])
  private var protectionGeneration = 0
  private var ended = false

  init(
    downstream: NIOLoopBound<ChannelHandlerContext>, protections: EgressDecisionLog,
    requestMethod: HTTPMethod
  ) {
    self.downstream = downstream
    self.protections = protections
    self.requestMethod = requestMethod
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    protectionGeneration = protections.refreshResponseScrubber(
      &scrubber, since: protectionGeneration)
    let client = downstream.value
    switch unwrapInboundIn(data) {
    case .head(let head):
      // HEAD and bodyless status headers describe a representation, not compressed wire bytes.
      let bodyless =
        requestMethod == .HEAD || head.status.code == 204 || head.status.code == 205
        || head.status.code == 304
      // A compressed opaque entity cannot be scrubbed even when identity was requested.
      if !bodyless, !scrubber.isEmpty,
        head.headers["content-encoding"].contains(where: { $0.lowercased() != "identity" })
      {
        client.close(promise: nil)
        context.close(promise: nil)
        return
      }
      var headers = HTTPHeaders()
      let hopByHop: Set<String> = [
        "connection", "keep-alive", "proxy-authenticate", "proxy-connection", "upgrade",
      ]
      let listed = Set(
        head.headers["connection"].flatMap { $0.split(separator: ",") }.map {
          $0.trimmingCharacters(in: .whitespaces).lowercased()
        })
      for (name, value) in head.headers
      where !hopByHop.contains(name.lowercased()) && !listed.contains(name.lowercased()) {
        guard !scrubber.containsRecognizedForm(in: name, ignoringASCIICase: true) else { continue }
        headers.add(name: name, value: scrubber.scrub(value))
      }
      headers.add(name: "connection", value: "close")
      client.write(
        NIOAny(
          HTTPServerResponsePart.head(
            HTTPResponseHead(
              version: .http1_1, status: HTTPResponseStatus(statusCode: Int(head.status.code)),
              headers: headers))),
        promise: nil)
    case .body(let buffer):
      write(scrubber.push(buffer.readableBytesView), to: client)
    case .end:
      ended = true
      write(scrubber.finish(), to: client)
      let channel = client.channel
      client.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil))).whenComplete { _ in
        channel.close(promise: nil)
      }
      context.close(promise: nil)
    }
  }

  func channelReadComplete(context: ChannelHandlerContext) {
    downstream.value.flush()
  }

  /// A response is read only while the client is writable, so a download is buffered by the
  /// upstream, not here. The client's handler asks again once it can take more.
  func read(context: ChannelHandlerContext) {
    if downstream.value.channel.isWritable { context.read() }
  }

  func channelWritabilityChanged(context: ChannelHandlerContext) {
    // The upstream can take more of the request: let the client's handler read again.
    if context.channel.isWritable { downstream.value.channel.read() }
    context.fireChannelWritabilityChanged()
  }

  func channelInactive(context: ChannelHandlerContext) {
    if !ended { downstream.value.close(promise: nil) }
  }

  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    context.close(promise: nil)
  }

  private func write(_ bytes: [UInt8], to client: ChannelHandlerContext) {
    guard !bytes.isEmpty else { return }
    client.write(
      NIOAny(
        HTTPServerResponsePart.body(.byteBuffer(client.channel.allocator.buffer(bytes: bytes)))),
      promise: nil)
  }
}

/// Joins two connections byte for byte, honoring each side's writability and half-closure.
/// NIO invokes every handler method on the owning channel's event loop, which both share.
final class EgressGlueHandler: ChannelDuplexHandler, @unchecked Sendable {
  typealias InboundIn = NIOAny
  typealias OutboundIn = NIOAny
  typealias OutboundOut = NIOAny

  private var partner: EgressGlueHandler?
  private var context: ChannelHandlerContext?
  private var pendingRead = false
  private let flushDeadline: TimeAmount
  /// The upstream side only: its client's open connections, which it joins if it outlives
  /// the client's own connection.
  private let clientConnections: EgressConnections?

  private init(flushDeadline: TimeAmount, clientConnections: EgressConnections?) {
    self.flushDeadline = flushDeadline
    self.clientConnections = clientConnections
  }

  /// The client's side and the upstream's side of one tunnel.
  static func matchedPair(
    flushDeadline: TimeAmount, upstreamCountedIn connections: EgressConnections
  ) -> (EgressGlueHandler, EgressGlueHandler) {
    let first = EgressGlueHandler(flushDeadline: flushDeadline, clientConnections: nil)
    let second = EgressGlueHandler(flushDeadline: flushDeadline, clientConnections: connections)
    first.partner = second
    second.partner = first
    return (first, second)
  }

  func handlerAdded(context: ChannelHandlerContext) { self.context = context }

  func handlerRemoved(context: ChannelHandlerContext) {
    self.context = nil
    partner = nil
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) { partner?.partnerWrite(data) }

  func channelReadComplete(context: ChannelHandlerContext) { partner?.partnerFlush() }

  func channelInactive(context: ChannelHandlerContext) { partner?.partnerFinished() }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    if let event = event as? ChannelEvent, case .inputClosed = event { partner?.partnerWriteEOF() }
    context.fireUserInboundEventTriggered(event)
  }

  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    partner?.partnerCloseFull()
  }

  func channelWritabilityChanged(context: ChannelHandlerContext) {
    if context.channel.isWritable { partner?.partnerBecameWritable() }
    context.fireChannelWritabilityChanged()
  }

  func read(context: ChannelHandlerContext) {
    if let partner, partner.partnerWritable {
      context.read()
    } else {
      pendingRead = true
    }
  }

  private func partnerWrite(_ data: NIOAny) { context?.write(data, promise: nil) }

  private func partnerFlush() { context?.flush() }

  private func partnerWriteEOF() { context?.close(mode: .output, promise: nil) }

  /// The other side closed in order: what it had already sent is written out before this side
  /// closes too; a full close at once would cancel those pending writes. The client's side
  /// waits for its client to read, for as long as the client stays: it is inside the client's
  /// connection cap. An upstream left behind by its client joins that cap until it closes, and
  /// is given up at the flush deadline if it does not take what is left.
  private func partnerFinished() {
    guard let context else { return }
    let channel = context.channel
    var deadline: Scheduled<Void>?
    if let clientConnections {
      clientConnections.add(channel)
      deadline = context.eventLoop.scheduleTask(in: flushDeadline) {
        channel.close(promise: nil)
      }
    }
    let abandoned = deadline
    context.writeAndFlush(NIOAny(channel.allocator.buffer(capacity: 0))).whenComplete { _ in
      abandoned?.cancel()
      channel.close(promise: nil)
    }
  }

  private func partnerCloseFull() { context?.close(promise: nil) }

  private func partnerBecameWritable() {
    if pendingRead {
      pendingRead = false
      context?.read()
    }
  }

  private var partnerWritable: Bool { context?.channel.isWritable ?? false }
}
