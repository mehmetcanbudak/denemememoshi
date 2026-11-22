/// `pair.hello`, new device → paired device, inside the Noise IKpsk2 handshake keyed by the QR
/// code's one-time key: the new device, its public keys and its MLS key package
/// (protocol.md §12.2).
public struct PairHello: DeviceMessagePayload {
  /// `pair.hello`.
  public static let messageType = "pair.hello"

  /// The new device.
  public var deviceId: DeviceID
  /// Its name, at most 60 characters.
  public var name: DeviceName
  /// Its platform.
  public var platform: DevicePlatform
  /// Its OS version.
  public var osVersion: String
  /// Its app version.
  public var appVersion: String
  /// Its public keys.
  public var publicKeys: DevicePublicKeys
  /// Its MLS key package.
  public var keyPackage: Base64Bytes

  /// Creates the payload.
  public init(
    deviceId: DeviceID, name: DeviceName, platform: DevicePlatform, osVersion: String,
    appVersion: String, publicKeys: DevicePublicKeys, keyPackage: Base64Bytes
  ) {
    self.deviceId = deviceId
    self.name = name
    self.platform = platform
    self.osVersion = osVersion
    self.appVersion = appVersion
    self.publicKeys = publicKeys
    self.keyPackage = keyPackage
  }

  /// `.pairHello(self)`.
  public var asBody: DeviceMessageBody { .pairHello(self) }
}

/// `pair.welcome`, paired device → new device: the MLS Welcome and the signed device list, at
/// the group epoch the authority granted.
public struct PairWelcome: DeviceMessagePayload {
  /// `pair.welcome`.
  public static let messageType = "pair.welcome"

  /// The device group.
  public var groupId: String
  /// The group epoch after the add.
  public var epoch: Int64
  /// The MLS Welcome.
  public var welcome: Base64Bytes
  /// The signed list of the group's devices.
  public var devices: SignedDeviceList

  /// Creates the payload.
  public init(groupId: String, epoch: Int64, welcome: Base64Bytes, devices: SignedDeviceList) {
    self.groupId = groupId
    self.epoch = epoch
    self.welcome = welcome
    self.devices = devices
  }

  /// `.pairWelcome(self)`.
  public var asBody: DeviceMessageBody { .pairWelcome(self) }
}

/// `pair.confirm`, new device → paired device: its public keys, signed under the new group
/// epoch. The paired device then retires the one-time key.
public struct PairConfirm: DeviceMessagePayload {
  /// `pair.confirm`.
  public static let messageType = "pair.confirm"

  /// The new device.
  public var deviceId: DeviceID
  /// Its public keys.
  public var publicKeys: DevicePublicKeys
  /// The group epoch it signs under.
  public var epoch: Int64
  /// Its signature over its keys and the epoch.
  public var signature: Base64Bytes

  /// Creates the payload.
  public init(
    deviceId: DeviceID, publicKeys: DevicePublicKeys, epoch: Int64, signature: Base64Bytes
  ) {
    self.deviceId = deviceId
    self.publicKeys = publicKeys
    self.epoch = epoch
    self.signature = signature
  }

  /// `.pairConfirm(self)`.
  public var asBody: DeviceMessageBody { .pairConfirm(self) }
}

/// `group.commit`, device → lease authority: a compare-and-swap on the device group's epoch for
/// an MLS commit that adds, removes or updates a device (protocol.md §12.2, §12.4).
public struct GroupCommit: DeviceMessagePayload {
  /// `group.commit`.
  public static let messageType = "group.commit"

  /// The device group.
  public var groupId: String
  /// The epoch the commit builds on; it applies only while the authority still holds it.
  public var fromEpoch: Int64
  /// What the commit changes.
  public var change: GroupChange
  /// The device added, removed or updated.
  public var subjectDeviceId: DeviceID
  /// The MLS commit.
  public var commit: Base64Bytes

  /// Creates the payload.
  public init(
    groupId: String, fromEpoch: Int64, change: GroupChange, subjectDeviceId: DeviceID,
    commit: Base64Bytes
  ) {
    self.groupId = groupId
    self.fromEpoch = fromEpoch
    self.change = change
    self.subjectDeviceId = subjectDeviceId
    self.commit = commit
  }

  /// `.groupCommit(self)`.
  public var asBody: DeviceMessageBody { .groupCommit(self) }
}

/// `group.commitResult`, lease authority → device: whether the compare-and-swap won, and the
/// group epoch the authority now holds. A commit that lost is rebuilt on that epoch.
public struct GroupCommitResult: DeviceMessagePayload {
  /// `group.commitResult`.
  public static let messageType = "group.commitResult"

  /// The device group.
  public var groupId: String
  /// Whether the commit applied.
  public var accepted: Bool
  /// The group epoch the authority holds now.
  public var epoch: Int64

  /// Creates the payload.
  public init(groupId: String, accepted: Bool, epoch: Int64) {
    self.groupId = groupId
    self.accepted = accepted
    self.epoch = epoch
  }

  /// `.groupCommitResult(self)`.
  public var asBody: DeviceMessageBody { .groupCommitResult(self) }
}

/// A device's public keys, base64. The private halves never leave its Keychain.
public struct DevicePublicKeys: Codable, Hashable, Sendable {
  /// The signing key; also the device's credential in the group.
  public var signing: Base64Bytes
  /// The key-agreement key.
  public var agreement: Base64Bytes

  /// Creates public keys.
  public init(signing: Base64Bytes, agreement: Base64Bytes) {
    self.signing = signing
    self.agreement = agreement
  }
}

/// The device group's member list, signed by the device that sent it.
public struct SignedDeviceList: Codable, Hashable, Sendable {
  /// The group epoch the list describes.
  public var epoch: Int64
  /// The members.
  public var devices: [DeviceListEntry]
  /// The signing device.
  public var signerDeviceId: DeviceID
  /// The signature over the epoch and the members.
  public var signature: Base64Bytes

  /// Creates a signed list.
  public init(
    epoch: Int64, devices: [DeviceListEntry], signerDeviceId: DeviceID, signature: Base64Bytes
  ) {
    self.epoch = epoch
    self.devices = devices
    self.signerDeviceId = signerDeviceId
    self.signature = signature
  }
}

/// One member of a ``SignedDeviceList``.
public struct DeviceListEntry: Codable, Hashable, Sendable {
  /// The device.
  public var deviceId: DeviceID
  /// Its name, at most 60 characters.
  public var name: DeviceName
  /// Its platform.
  public var platform: DevicePlatform
  /// Its public keys.
  public var publicKeys: DevicePublicKeys
  /// Its leaf in the MLS tree.
  public var leafIndex: Int

  /// Creates a member entry.
  public init(
    deviceId: DeviceID, name: DeviceName, platform: DevicePlatform, publicKeys: DevicePublicKeys,
    leafIndex: Int
  ) {
    self.deviceId = deviceId
    self.name = name
    self.platform = platform
    self.publicKeys = publicKeys
    self.leafIndex = leafIndex
  }
}

/// A device's platform (object-model.md §4.26).
public enum DevicePlatform: OpenEnum {
  case mac
  case iphone
  case ipad
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .mac: "mac", .iphone: "iphone", .ipad: "ipad",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// What a device group commit changes.
public enum GroupChange: OpenEnum {
  case add
  case remove
  /// A key update.
  case update
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .add: "add", .remove: "remove", .update: "update",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
