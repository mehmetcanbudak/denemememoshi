import CryptoKit
import Foundation
import MemoshiDevice
import Network
import Synchronization

/// Noise authenticates the already-paired peer on the outer socket. It is NOT MLS. Every
/// application payload inside this carrier must already be sealed by DeviceApplicationTransport.
public enum AppleDirectCarrier {
  private static let prologue = Data("memoshi.mls-carrier.v1".utf8)
  /// The initiator's first transport frame. A recorded IK initiation can be replayed and the
  /// responder's answer does not prove a live initiator; this frame needs the handshake's
  /// fresh ephemeral key, so only the live initiator can produce it.
  private static let keyConfirmation = Data([0x20])

  /// Different service instance from Node's pairing/control port, with the same declared
  /// _memoshi._tcp service type. Both full peer identities remain authenticated cryptographically.
  public static func serviceName(local: DevicePeer, peer: DevicePeer) -> String {
    "memoshi-data-"
      + SHA256.hash(data: Data((local.deviceID.rawValue + ":" + peer.deviceID.rawValue).utf8))
      .prefix(12).map { String(format: "%02x", $0) }.joined()
  }

  /// Defers Bonjour connection and Noise authentication to the race attempt. The supplied
  /// paired peer, not the discovered service name, determines the authenticated identity.
  public static func bonjourCandidate(
    identity: DeviceIdentity, group: DeviceGroup, peer: DevicePeer
  ) -> DeviceRouteCandidate {
    DeviceRouteCandidate(route: .direct) {
      let channel = try await NetworkDeviceFrameChannel.connect(
        endpoint: .service(
          name: serviceName(local: peer, peer: identity.peer),
          type: DeviceBonjourBrowser.serviceType,
          domain: "local.", interface: nil))
      return try await initiate(identity: identity, group: group, peer: peer, channel: channel)
    }
  }

  /// An explicit tailnet/VPN/user-reachable address; never a source of enrollment authority.
  public static func connect(
    identity: DeviceIdentity, group: DeviceGroup, peer: DevicePeer, host: String, port: Int
  ) async throws -> DeviceRouteEndpoint {
    let channel = try await TCPFrameChannel.connect(host: host, port: port)
    return try await initiate(identity: identity, group: group, peer: peer, channel: channel)
  }

  /// Reuse the host's real relay FrameChannel implementation. Resolving/registering a relay
  /// remains explicit; the same Noise IK authenticates the paired peer before MLS bytes flow.
  public static func relayCandidate(
    identity: DeviceIdentity, group: DeviceGroup, peer: DevicePeer,
    connect: @escaping @Sendable () async throws -> any FrameChannel
  ) -> DeviceRouteCandidate {
    DeviceRouteCandidate(route: .relay) {
      try await initiate(identity: identity, group: group, peer: peer, channel: connect())
    }
  }

  /// Explicit opt-in only. Native host must declare local-network usage and _memoshi._tcp.
  public static func listenBonjour(
    identity: DeviceIdentity, group: DeviceGroup, peer: DevicePeer,
    onEndpoint: @escaping @Sendable (DeviceRouteEndpoint) async -> Void
  ) async throws -> DeviceBonjourListener {
    let handshakes = Mutex(0)
    return try await DeviceBonjourListener.start(
      name: serviceName(local: identity.peer, peer: peer)
    ) { channel in
      let admitted = handshakes.withLock { count in
        guard count < 16 else { return false }
        count += 1
        return true
      }
      guard admitted else {
        channel.close()
        return
      }
      Task {
        defer { handshakes.withLock { $0 -= 1 } }
        do {
          await onEndpoint(
            try await accept(identity: identity, group: group, peer: peer, channel: channel))
        } catch { channel.close() }
      }
    }
  }

  /// Initiates Noise authentication on the supplied channel for an existing group member.
  /// Failure, cancellation, or the ten-second deadline closes the channel; a returned endpoint
  /// owns its carrier until closed. Application bytes must already be sealed by MLS.
  public static func initiate(
    identity: DeviceIdentity, group: DeviceGroup, peer: DevicePeer, channel: any FrameChannel
  ) async throws -> DeviceRouteEndpoint {
    try await authenticate(
      identity: identity, group: group, peer: peer, channel: channel, initiator: true)
  }

  /// Responds to Noise authentication for the supplied paired peer, checking membership before
  /// and after the handshake and requiring the initiator's key confirmation, so a replayed
  /// initiation never yields an endpoint. Failure or cancellation closes the channel; the returned
  /// endpoint owns the authenticated carrier but grants no enrollment or application authority.
  public static func accept(
    identity: DeviceIdentity, group: DeviceGroup, peer: DevicePeer, channel: any FrameChannel
  ) async throws -> DeviceRouteEndpoint {
    try await authenticate(
      identity: identity, group: group, peer: peer, channel: channel, initiator: false)
  }

  private static func authenticate(
    identity: DeviceIdentity, group: DeviceGroup, peer: DevicePeer, channel: any FrameChannel,
    initiator: Bool
  ) async throws -> DeviceRouteEndpoint {
    do {
      return try await withTaskCancellationHandler {
        try await withThrowingTaskGroup(of: DeviceRouteEndpoint.self) { tasks in
          tasks.addTask {
            guard await group.member(peer.deviceID, agreementKey: peer.agreementKey) == peer else {
              throw AppleDeviceError.revoked
            }
            var handshake = try NoiseHandshake(
              pattern: .link, initiator: initiator, prologue: prologue,
              localStatic: identity.agreementKey(),
              remoteStatic: initiator
                ? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer.agreementKey) : nil)
            if initiator {
              try channel.send(
                Data([0x71])
                  + handshake.writeMessage(payload: Data(identity.deviceID.rawValue.utf8)))
              let response = try await channel.receive()
              guard response.first == 0x72,
                try handshake.readMessage(Data(response.dropFirst()))
                  == Data(peer.deviceID.rawValue.utf8)
              else {
                throw AppleDeviceError.conflictingReplay
              }
            } else {
              let first = try await channel.receive()
              guard first.first == 0x71,
                try handshake.readMessage(Data(first.dropFirst()))
                  == Data(peer.deviceID.rawValue.utf8),
                handshake.remoteStatic?.rawRepresentation == peer.agreementKey
              else {
                throw AppleDeviceError.conflictingReplay
              }
              try channel.send(
                Data([0x72])
                  + handshake.writeMessage(payload: Data(identity.deviceID.rawValue.utf8)))
            }
            var transport = try handshake.split()
            if initiator {
              try channel.send(transport.seal(keyConfirmation))
            } else {
              guard try transport.open(try await channel.receive()) == keyConfirmation else {
                throw AppleDeviceError.conflictingReplay
              }
            }
            guard await group.member(peer.deviceID, agreementKey: peer.agreementKey) == peer else {
              throw AppleDeviceError.revoked
            }
            return makeEndpoint(transport: transport, channel: channel, group: group, peer: peer)
          }
          tasks.addTask {
            try await Task.sleep(for: .seconds(10))
            channel.close()  // Unblock a receive even when its carrier ignores task cancellation.
            throw DeviceLayerError.timeout("direct-data authentication")
          }
          defer { tasks.cancelAll() }
          guard let result = try await tasks.next() else { throw AppleDeviceError.closed }
          return result
        }
      } onCancel: {
        channel.close()
      }
    } catch {
      channel.close()
      throw error
    }
  }

  private static func makeEndpoint(
    transport: NoiseTransport, channel: any FrameChannel, group: DeviceGroup, peer: DevicePeer
  ) -> DeviceRouteEndpoint {
    let connectionID = transport.handshakeHash
    let carrier = PeerNoiseCarrier(transport: transport, channel: channel, group: group, peer: peer)
    let (frames, continuation) = AsyncThrowingStream<Data, any Error>.makeStream(
      bufferingPolicy: .bufferingOldest(256))
    let reader = Task {
      do {
        while !Task.isCancelled {
          let frame = try await carrier.receive()
          if case .dropped = continuation.yield(frame) {
            throw AppleDeviceError.invalidState("direct-data backpressure")
          }
        }
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
        await carrier.close()
      }
    }
    return DeviceRouteEndpoint(
      frames: frames, connectionID: connectionID,
      send: { try await carrier.send($0) },
      close: {
        reader.cancel()
        await carrier.close()
        continuation.finish()
      })
  }
}

private actor PeerNoiseCarrier {
  private var transport: NoiseTransport
  private let channel: any FrameChannel
  private let group: DeviceGroup
  private let peer: DevicePeer
  private var closed = false

  init(transport: NoiseTransport, channel: any FrameChannel, group: DeviceGroup, peer: DevicePeer) {
    self.transport = transport
    self.channel = channel
    self.group = group
    self.peer = peer
  }

  func send(_ packet: Data) async throws {
    guard !closed, await group.member(peer.deviceID, agreementKey: peer.agreementKey) == peer else {
      close()
      throw AppleDeviceError.revoked
    }
    guard !packet.isEmpty, packet.count <= 1_048_576 else {
      throw AppleDeviceError.invalidState("direct packet size")
    }
    // Noise's transport limit is 65519 bytes. Ordered authenticated fragments preserve the
    // opaque original MLS packet, including larger bounded replica/snapshot messages.
    let chunkSize = NoiseTransport.maximumPlaintext - 1
    var offset = 0
    while offset < packet.count {
      let end = min(packet.count, offset + chunkSize)
      var fragment = Data([end == packet.count ? 1 : 0])
      fragment.append(packet[offset..<end])
      try channel.send(transport.seal(fragment))
      offset = end
    }
  }

  func receive() async throws -> Data {
    guard !closed else { throw AppleDeviceError.closed }
    var packet = Data()
    while true {
      let frame = try await channel.receive()
      guard !closed, await group.member(peer.deviceID, agreementKey: peer.agreementKey) == peer
      else {
        close()
        throw AppleDeviceError.revoked
      }
      let fragment = try transport.open(frame)
      guard let final = fragment.first, final <= 1,
        packet.count + fragment.count - 1 <= 1_048_576
      else {
        close()
        throw AppleDeviceError.invalidState("direct fragment")
      }
      packet.append(fragment.dropFirst())
      if final == 1 { return packet }
    }
  }

  func close() {
    closed = true
    channel.close()
  }
}
