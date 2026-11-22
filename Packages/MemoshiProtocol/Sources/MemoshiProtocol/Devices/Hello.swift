/// `device.hello`, each device → the other: the first message on every link connection
/// (protocol.md §12.9). It states the app version and build, the device protocol versions, the
/// device capabilities and the oldest app version that can still read and run this device's
/// stores. The peers use the highest protocol version both support, and a sender uses a new
/// device-message type only once the peer's hello shows it understands it.
public struct DeviceHello: DeviceMessagePayload {
  /// `device.hello`.
  public static let messageType = "device.hello"

  /// The app's marketing version.
  public var appVersion: String
  /// The app's build number.
  public var appBuild: String
  /// The device protocol versions this device supports.
  public var protocolRange: ProtocolRange
  /// The device capabilities this device offers.
  public var capabilities: [Capability]
  /// The oldest app version that can still read and run this device's stores; an older peer
  /// is a read-only replica.
  public var oldestRunnableAppVersion: String

  /// Creates the payload.
  public init(
    appVersion: String, appBuild: String, protocolRange: ProtocolRange,
    capabilities: [Capability], oldestRunnableAppVersion: String
  ) {
    self.appVersion = appVersion
    self.appBuild = appBuild
    self.protocolRange = protocolRange
    self.capabilities = capabilities
    self.oldestRunnableAppVersion = oldestRunnableAppVersion
  }

  private enum CodingKeys: String, CodingKey {
    case appVersion
    case appBuild
    case protocolRange = "protocol"
    case capabilities
    case oldestRunnableAppVersion
  }

  /// `.deviceHello(self)`.
  public var asBody: DeviceMessageBody { .deviceHello(self) }
}
