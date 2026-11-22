import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import Synchronization

/// One HTTP response after the client's existing gateway authorization and secret scrubbing.
/// Redirects are returned unchanged; this value does not represent a followed request.
public struct EgressFetchResponse: Sendable {
  /// The actual HTTP status, including policy refusals and other non-success responses.
  public let status: Int
  /// Lowercase, comma-joined response fields, without cookies, proxy credentials or hop headers.
  public let headers: [String: String]
  /// The bounded response bytes, empty for HEAD and statuses that cannot carry a body.
  public let body: Data
}

extension EgressClient {
  /// Performs one HTTP(S) exchange through this client's exact owned gateway listener only.
  /// The gateway, not this adapter, authorizes, resolves, verifies TLS and scrubs secrets.
  /// Caller-supplied transport, Host, framing and hop-by-hop headers are ignored. The request
  /// body is limited to 1 MiB; `maxResponseBytes` must be in 1...16 MiB. Redirects and non-2xx
  /// responses are returned without retrying. Cancelling closes and drains this exchange's
  /// native channel, gateway decision, connection attempt and upstream before throwing.
  public func fetch(
    _ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data = Data(),
    attribution: EgressCallAttribution, maxResponseBytes: Int = 16 * 1024 * 1024
  ) async throws -> EgressFetchResponse {
    try Task.checkCancellation()
    let request = try EgressFetchRequest(
      url: url, method: method, headers: headers, bodyBytes: body.count,
      attribution: attribution, maxResponseBytes: maxResponseBytes)
    let (key, operation) = try registerFetch()
    defer { _ = core.nativeFetches.withLock { $0.removeValue(forKey: key) } }
    return try await withTaskCancellationHandler {
      do {
        try Task.checkCancellation()
        let isHead = request.head.method == .HEAD
        let bootstrap = ClientBootstrap(group: core.group)
          .connectTimeout(.seconds(10))
          .channelInitializer { channel in
            operation.attachClient(channel)
            return channel.eventLoop.makeCompletedFuture {
              try channel.pipeline.syncOperations.addHTTPClientHandlers()
              try channel.pipeline.syncOperations.addHandler(
                EgressFetchCollector(
                  operation: operation, maxBytes: maxResponseBytes, isHead: isHead))
            }
          }
        // Never dial the supplied URL or fall back from a missing confined socket to TCP.
        let channel = try await
          (socketPath.map { bootstrap.connect(unixDomainSocketPath: $0) }
          ?? bootstrap.connect(host: "127.0.0.1", port: port)).get()
        operation.finishConnecting()
        try Task.checkCancellation()
        var head = request.head
        head.headers.add(name: EgressFetchOperation.markerHeader, value: key)
        channel.write(HTTPClientRequestPart.head(head), promise: nil)
        if !body.isEmpty {
          channel.write(
            HTTPClientRequestPart.body(.byteBuffer(channel.allocator.buffer(bytes: body))),
            promise: nil)
        }
        try await channel.writeAndFlush(HTTPClientRequestPart.end(nil)).get()
        let response = try await operation.response.futureResult.get()
        await operation.drain()
        try Task.checkCancellation()
        return response
      } catch {
        operation.finishConnecting()
        let failure: any Error =
          error is EgressFetchError || error is EgressConfigurationError
          ? error : EgressFetchError.unavailable
        operation.fail(failure)
        await operation.drain()
        try Task.checkCancellation()
        throw failure
      }
    } onCancel: {
      operation.fail(CancellationError())
    }
  }
}

/// Content-free failures: no upstream URL, request header, credential or body is retained.
enum EgressFetchError: Error {
  case invalidRequest
  case responseTooLarge
  case invalidResponse
  case unavailable
}

private struct EgressFetchRequest {
  let head: HTTPRequestHead

  init(
    url: URL, method: String, headers: [String: String], bodyBytes: Int,
    attribution: EgressCallAttribution, maxResponseBytes: Int
  ) throws {
    guard (1...(16 * 1024 * 1024)).contains(maxResponseBytes),
      bodyBytes <= EgressProxyHandler.pendingLimit,
      Self.isToken(method), !["CONNECT", "TRACE", "TRACK"].contains(method.uppercased()),
      var components = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: true),
      let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
      let host = components.percentEncodedHost, !host.isEmpty,
      components.user == nil, components.password == nil,
      (1...65_535).contains(components.port ?? (scheme == "https" ? 443 : 80))
    else { throw EgressFetchError.invalidRequest }
    components.fragment = nil
    guard let target = components.string,
      target.utf8.allSatisfy({ $0 > 0x20 && $0 != 0x7f })
    else { throw EgressFetchError.invalidRequest }
    for (name, value) in headers {
      guard Self.isToken(name),
        !value.utf8.contains(where: { ($0 < 0x20 && $0 != 0x09) || $0 == 0x7f })
      else { throw EgressFetchError.invalidRequest }
    }
    let listed = Set(
      headers.filter { $0.key.lowercased() == "connection" }.values.flatMap {
        $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
      })
    var forwarded = HTTPHeaders()
    for (name, value) in headers {
      let lower = name.lowercased()
      guard !Self.ownedHeaders.contains(lower), !listed.contains(lower) else { continue }
      forwarded.add(name: name, value: value)
    }
    let credential = Data(("memoshi:" + attribution.token).utf8).base64EncodedString()
    forwarded.add(name: "proxy-authorization", value: "Basic " + credential)
    forwarded.add(name: "host", value: host + (components.port.map { ":" + String($0) } ?? ""))
    forwarded.add(name: "content-length", value: String(bodyBytes))
    forwarded.add(name: "connection", value: "close")
    head = HTTPRequestHead(
      version: .http1_1, method: HTTPMethod(rawValue: method), uri: target, headers: forwarded)
  }

  private static let ownedHeaders: Set<String> = [
    "host", "content-length", "connection", "keep-alive", "proxy-authorization",
    "proxy-authenticate", "proxy-connection", "transfer-encoding", "te", "trailer", "upgrade",
    "expect", EgressFetchOperation.markerHeader,
  ]

  private static func isToken(_ value: String) -> Bool {
    !value.isEmpty
      && value.utf8.allSatisfy {
        switch $0 {
        case 0x30...0x39, 0x41...0x5a, 0x61...0x7a,
          0x21, 0x23...0x27, 0x2a, 0x2b, 0x2d, 0x2e, 0x5e, 0x5f, 0x60, 0x7c, 0x7e:
          true
        default:
          false
        }
      }
  }
}

/// An unforwarded random marker pairs a native request with its accepted gateway handler, so
/// cancellation can await that exact handler's work even over an unnamed Unix-socket peer.
/// The marker never substitutes for the request's ordinary live proxy attribution.
final class EgressFetchOperation: Sendable {
  static let markerHeader = "x-memoshi-native-exchange"

  private struct Gateway: Sendable {
    let channel: any Channel
    let drained: EventLoopFuture<Void>
  }

  private struct State: Sendable {
    var stopped = false
    var responded = false
    var connecting = true
    var client: (any Channel)?
    var gateway: Gateway?
  }

  let response: EventLoopPromise<EgressFetchResponse>
  private let state = Mutex(State())
  private let connected: EventLoopPromise<Void>

  init(eventLoop: any EventLoop) {
    response = eventLoop.makePromise(of: EgressFetchResponse.self)
    connected = eventLoop.makePromise(of: Void.self)
  }

  func attachClient(_ channel: any Channel) {
    let stopped = state.withLock {
      $0.client = channel
      return $0.stopped
    }
    if stopped { channel.close(promise: nil) }
  }

  func attachGateway(_ channel: any Channel, drained: EventLoopFuture<Void>) -> Bool {
    state.withLock {
      guard !$0.stopped, $0.gateway == nil else { return false }
      $0.gateway = Gateway(channel: channel, drained: drained)
      return true
    }
  }

  func finishConnecting() {
    let deliver = state.withLock {
      guard $0.connecting else { return false }
      $0.connecting = false
      return true
    }
    if deliver { connected.succeed(()) }
  }

  func succeed(_ response: EgressFetchResponse) {
    let deliver = state.withLock {
      guard !$0.responded, !$0.stopped else { return false }
      $0.responded = true
      return true
    }
    if deliver { self.response.succeed(response) }
  }

  func fail(_ error: any Error) {
    let snapshot = state.withLock { state in
      let deliver = !state.responded
      state.responded = true
      state.stopped = true
      return (deliver, state.client, state.gateway)
    }
    if snapshot.0 { response.fail(error) }
    snapshot.1?.close(promise: nil)
    snapshot.2?.channel.close(promise: nil)
  }

  func drain() async {
    let snapshot = state.withLock {
      $0.stopped = true
      return ($0.client, $0.gateway)
    }
    snapshot.0?.close(promise: nil)
    snapshot.1?.channel.close(promise: nil)
    // Closure may race the bootstrap's initializer. Wait for that finite connection attempt
    // before taking the final snapshot, including a channel attached after stop was requested.
    try? await connected.futureResult.get()
    let attached = state.withLock { ($0.client, $0.gateway) }
    attached.0?.close(promise: nil)
    attached.1?.channel.close(promise: nil)
    try? await attached.0?.closeFuture.get()
    try? await attached.1?.drained.get()
    try? await attached.1?.channel.closeFuture.get()
  }
}

/// NIO invokes collector callbacks on the owning channel's event loop. Only the operation's
/// synchronized completion/drain state is shared with Swift tasks and the gateway channel.
private final class EgressFetchCollector: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = HTTPClientResponsePart

  private let operation: EgressFetchOperation
  private let maxBytes: Int
  private let isHead: Bool
  private var head: HTTPResponseHead?
  private var body = Data()

  init(operation: EgressFetchOperation, maxBytes: Int, isHead: Bool) {
    self.operation = operation
    self.maxBytes = maxBytes
    self.isHead = isHead
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch unwrapInboundIn(data) {
    case .head(let head):
      guard self.head == nil, head.status.code >= 200 else {
        operation.fail(EgressFetchError.invalidResponse)
        return
      }
      self.head = head
      if !isHead, head.status != .noContent, head.status != .notModified,
        let text = head.headers.first(name: "content-length"), let length = Int(text)
      {
        guard length >= 0, length <= maxBytes else {
          operation.fail(EgressFetchError.responseTooLarge)
          return
        }
        body.reserveCapacity(length)
      }
    case .body(let buffer):
      guard head != nil, buffer.readableBytes <= maxBytes - body.count else {
        operation.fail(EgressFetchError.responseTooLarge)
        return
      }
      body.append(contentsOf: buffer.readableBytesView)
    case .end:
      guard let head else {
        operation.fail(EgressFetchError.invalidResponse)
        return
      }
      let listed = Set(
        head.headers["connection"].flatMap { $0.split(separator: ",") }.map {
          $0.trimmingCharacters(in: .whitespaces).lowercased()
        })
      var headers: [String: String] = [:]
      for (name, value) in head.headers {
        let lower = name.lowercased()
        guard !Self.forbiddenHeaders.contains(lower), !listed.contains(lower) else { continue }
        if let previous = headers[lower] {
          headers[lower] = previous + ", " + value
        } else {
          headers[lower] = value
        }
      }
      operation.succeed(
        EgressFetchResponse(status: Int(head.status.code), headers: headers, body: body))
      context.close(promise: nil)
    }
  }

  func channelInactive(context: ChannelHandlerContext) {
    operation.fail(EgressFetchError.unavailable)
    context.fireChannelInactive()
  }

  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    operation.fail(EgressFetchError.invalidResponse)
  }

  private static let forbiddenHeaders: Set<String> = [
    "set-cookie", "set-cookie2", "proxy-authorization", "proxy-authenticate", "connection",
    "keep-alive", "proxy-connection", "transfer-encoding", "te", "trailer", "upgrade",
    EgressFetchOperation.markerHeader,
  ]
}
