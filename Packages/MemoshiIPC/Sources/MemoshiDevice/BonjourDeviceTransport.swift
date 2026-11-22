import Foundation
import Network
import Synchronization

/// Real Network.framework Bonjour discovery. Results are untrusted route hints, never peer
/// enrollment: DeviceNode still verifies Noise keys and fresh authority membership on connect.
/// The host must declare _memoshi._tcp and local-network usage before opting into this surface.
public final class DeviceBonjourBrowser: Sendable {
  /// Bonjour TCP service type browsed and advertised in the local domain.
  public static let serviceType = "_memoshi._tcp"

  /// Discovery snapshots or an unavailable browser state; neither grants peer authority.
  public enum Update: Sendable {
    /// Current untrusted service endpoints, replacing the previous snapshot.
    case services([NWEndpoint])
    /// Browsing is waiting or failed; a later snapshot may still arrive.
    case unavailable
  }

  /// Latest-only discovery stream, finished when the browser is cancelled or closed.
  public let updates: AsyncStream<Update>
  private let sink: AsyncStream<Update>.Continuation
  private let browser: NWBrowser

  /// Starts local-domain TCP browsing immediately; the owner must retain and close the browser.
  public init() {
    (updates, sink) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: "local."), using: .tcp)
    let sink = sink
    browser.browseResultsChangedHandler = { results, _ in
      sink.yield(.services(results.map(\.endpoint)))
    }
    browser.stateUpdateHandler = { state in
      switch state {
      case .waiting, .failed: sink.yield(.unavailable)
      case .cancelled: sink.finish()
      default: break
      }
    }
    browser.start(queue: DispatchQueue(label: "memoshi.device-bonjour"))
  }

  /// Cancels discovery and finishes the update stream; safe to call repeatedly.
  public func close() {
    browser.cancel()
    sink.finish()
  }

  deinit {
    browser.cancel()
    sink.finish()
  }
}

/// The same bounded 4-byte framing as TCPFrameChannel, using an actual discovered service
/// endpoint (or an explicitly supplied host/port) without a DNS-to-identity trust shortcut.
public final class NetworkDeviceFrameChannel: FrameChannel {
  private struct State {
    var closed = false
    var ready = false
  }

  private let connection: NWConnection
  private let state = Mutex(State())
  private let readiness = FrameQueue(maximumFrames: 1, maximumBytes: 0)
  private let inbound = FrameQueue()

  private init(_ connection: NWConnection) {
    self.connection = connection
    connection.stateUpdateHandler = { [weak self] status in
      guard let self else { return }
      switch status {
      case .ready:
        let first = state.withLock { state in
          guard !state.closed, !state.ready else { return false }
          state.ready = true
          return true
        }
        if first {
          switch readiness.offer(Data()) {
          case .accepted: receiveHeader()
          case .overflow, .terminated: close()
          }
        }
      case .failed, .cancelled: close()
      default: break
      }
    }
    connection.start(queue: DispatchQueue(label: "memoshi.device-network-frame"))
  }

  /// Opens a TCP route and waits up to ten seconds for readiness, closing it on failure.
  /// The returned channel is unauthenticated; Noise and membership checks belong to its caller.
  public static func connect(endpoint: NWEndpoint) async throws -> NetworkDeviceFrameChannel {
    let channel = NetworkDeviceFrameChannel(NWConnection(to: endpoint, using: .tcp))
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { _ = try await channel.readiness.next() }
        group.addTask {
          try await Task.sleep(for: .seconds(10))
          throw DeviceLayerError.timeout("device network connection")
        }
        defer { group.cancelAll() }
        _ = try await group.next()
      }
      return channel
    } catch {
      channel.close()
      throw error
    }
  }

  fileprivate static func accept(_ connection: NWConnection) -> NetworkDeviceFrameChannel {
    NetworkDeviceFrameChannel(connection)
  }

  /// Enqueues a size-bounded, big-endian length-prefixed frame in send order.
  /// Throws for oversize/closed channels; return is not remote delivery acknowledgement.
  public func send(_ frame: Data) throws {
    guard frame.count <= TCPFrameChannel.maximumFrame else {
      throw DeviceLayerError.frameTooLarge(frame.count)
    }
    var bytes = Data()
    withUnsafeBytes(of: UInt32(frame.count).bigEndian) { bytes.append(contentsOf: $0) }
    bytes.append(frame)
    try state.withLock { state in
      guard !state.closed else { throw DeviceLayerError.closed }
      // Calls are enqueued under one lock to preserve Noise's per-direction nonce ordering.
      connection.send(
        content: bytes,
        completion: .contentProcessed { [weak self] error in
          if error != nil { self?.close() }
        })
    }
  }

  /// Waits for the next complete frame; malformed framing or connection closure ends reception.
  public func receive() async throws -> Data { try await inbound.next() }

  /// Idempotently cancels the connection and finishes pending readiness/receive queues.
  public func close() {
    let first = state.withLock { state in
      defer { state.closed = true }
      return !state.closed
    }
    guard first else { return }
    connection.cancel()
    readiness.finish()
    inbound.finish()
  }

  private func receiveHeader() {
    connection.receive(minimumIncompleteLength: 4, maximumLength: 4) {
      [weak self] bytes, _, end, error in
      guard let self else { return }
      guard error == nil, let bytes, bytes.count == 4 else {
        close()
        return
      }
      let length = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
      guard length <= UInt32(TCPFrameChannel.maximumFrame) else {
        close()
        return
      }
      if length == 0 {
        switch inbound.offer(Data()) {
        case .accepted:
          if end { close() } else { receiveHeader() }
        case .overflow, .terminated:
          close()
        }
      } else {
        receiveBody(Int(length))
      }
    }
  }

  private func receiveBody(_ length: Int) {
    connection.receive(minimumIncompleteLength: length, maximumLength: length) {
      [weak self] bytes, _, end, error in
      guard let self else { return }
      guard error == nil, let bytes, bytes.count == length else {
        close()
        return
      }
      switch inbound.offer(bytes) {
      case .accepted:
        if end { close() } else { receiveHeader() }
      case .overflow, .terminated:
        close()
      }
    }
  }

  deinit {
    connection.cancel()
    readiness.finish()
    inbound.finish()
  }
}

/// An opt-in real TCP listener published through Bonjour. Only a public device/service name
/// is advertised, never keys, enrollment authority or secrets.
public final class DeviceBonjourListener: Sendable {
  /// OS-assigned TCP listening port, in host-order integer form.
  public let port: Int
  private let listener: NWListener

  private init(listener: NWListener, port: Int) {
    self.listener = listener
    self.port = port
  }

  /// Advertises a nonempty UTF-8 name of at most 63 bytes without automatic renaming and
  /// waits up to ten seconds for readiness. The callback owns each accepted channel and
  /// must authenticate it; listener startup failure cancels the underlying listener.
  public static func start(
    name: String, onConnection: @escaping @Sendable (NetworkDeviceFrameChannel) -> Void
  ) async throws -> DeviceBonjourListener {
    guard !name.isEmpty, name.utf8.count <= 63 else {
      throw DeviceLayerError.invalid("Bonjour service name")
    }
    let listener = try NWListener(using: .tcp)
    var service = NWListener.Service(
      name: name, type: DeviceBonjourBrowser.serviceType, domain: "local.", txtRecord: nil as Data?)
    service.noAutoRename = true
    listener.service = service
    let ready = FrameQueue(maximumFrames: 1, maximumBytes: 0)
    listener.newConnectionHandler = { onConnection(NetworkDeviceFrameChannel.accept($0)) }
    listener.stateUpdateHandler = { state in
      switch state {
      case .ready:
        switch ready.offer(Data()) {
        case .accepted: break
        case .overflow, .terminated: listener.cancel()
        }
      case .failed, .cancelled: ready.finish()
      default: break
      }
    }
    listener.start(queue: DispatchQueue(label: "memoshi.device-bonjour-listener"))
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { _ = try await ready.next() }
        group.addTask {
          try await Task.sleep(for: .seconds(10))
          throw DeviceLayerError.timeout("Bonjour device listener")
        }
        defer { group.cancelAll() }
        _ = try await group.next()
      }
      guard let port = listener.port else {
        throw DeviceLayerError.invalid("Bonjour listener port")
      }
      return DeviceBonjourListener(listener: listener, port: Int(port.rawValue))
    } catch {
      listener.cancel()
      throw error
    }
  }

  /// Stops advertising and accepting connections; previously accepted channels remain owned
  /// by their callback recipients.
  public func close() { listener.cancel() }
  deinit { listener.cancel() }
}
