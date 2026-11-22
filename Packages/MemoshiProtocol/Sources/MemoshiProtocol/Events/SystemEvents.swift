/// `system.stopping` (D): the daemon begins a graceful shutdown.
public struct SystemStoppingPayload: EventPayload {
  /// `system.stopping`.
  public static let eventType = "system.stopping"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// Why the daemon is stopping.
  public var reason: SystemStoppingReason

  /// Creates a shutdown payload.
  public init(reason: SystemStoppingReason) {
    self.reason = reason
  }

  /// The typed event.
  public var asEvent: Event { .systemStopping(self) }
}

/// The catalogued causes of a graceful daemon shutdown.
public enum SystemStoppingReason: OpenEnum {
  case update
  case user
  case signal
  case unknown(String)

  /// The known wire values.
  public static let wireTable = OpenEnumTable<Self>([
    .update: "update", .user: "user", .signal: "signal",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// `system.app_connected` (D): the Mac application's capability channel connected.
public struct SystemAppConnectedPayload: EventPayload {
  /// `system.app_connected`.
  public static let eventType = "system.app_connected"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The connecting application's version.
  public var appVersion: String
  /// The capabilities actually negotiated for this channel.
  public var capabilities: [Capability]

  /// Creates a connection payload.
  public init(appVersion: String, capabilities: [Capability]) {
    self.appVersion = appVersion
    self.capabilities = capabilities
  }

  /// The typed event.
  public var asEvent: Event { .systemAppConnected(self) }
}

/// `system.app_disconnected` (D): the Mac application's capability channel disconnected.
public struct SystemAppDisconnectedPayload: EventPayload {
  /// `system.app_disconnected`.
  public static let eventType = "system.app_disconnected"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// A non-sensitive reason code, never a raw transport error or credential.
  public var reason: String

  /// Creates a disconnection payload.
  public init(reason: String) {
    self.reason = reason
  }

  /// The typed event.
  public var asEvent: Event { .systemAppDisconnected(self) }
}

/// `system.pruned` (D): the event log discarded an old retained prefix.
public struct SystemPrunedPayload: EventPayload {
  /// `system.pruned`.
  public static let eventType = "system.pruned"
  /// Version 1.
  public static let typeVersion = 1
  /// Durable.
  public static let eventClass = EventClass.durable

  /// The exclusive upper bound of the discarded prefix, now the oldest retained sequence.
  public var beforeSeq: Int64
  /// The number of events deleted by this batch.
  public var deleted: Int

  /// Creates a pruning payload.
  public init(beforeSeq: Int64, deleted: Int) {
    self.beforeSeq = beforeSeq
    self.deleted = deleted
  }

  /// The typed event.
  public var asEvent: Event { .systemPruned(self) }
}

/// `system.settings_changed` (A): named non-sensitive application settings changed.
public struct SystemSettingsChangedPayload: EventPayload {
  /// `system.settings_changed`.
  public static let eventType = "system.settings_changed"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited; callers commit the settings and event together.
  public static let eventClass = EventClass.audited

  /// The settings that changed.
  public var keys: [String]
  /// Their non-sensitive current values; secrets never belong here.
  public var values: [String: JSONValue]

  /// Creates a settings-change payload.
  public init(keys: [String], values: [String: JSONValue]) {
    self.keys = keys
    self.values = values
  }

  /// The typed event.
  public var asEvent: Event { .systemSettingsChanged(self) }
}

/// `system.migrated` (A): an existing store was backed up and upgraded.
public struct SystemMigratedPayload: EventPayload {
  /// `system.migrated`.
  public static let eventType = "system.migrated"
  /// Version 1.
  public static let typeVersion = 1
  /// Audited.
  public static let eventClass = EventClass.audited

  /// `memoshi` or the conversation whose store was upgraded.
  public var store: String
  /// The previous schema version.
  public var fromSchema: Int
  /// The installed schema version.
  public var toSchema: Int
  /// The actual pre-upgrade backup path.
  public var backupPath: String

  /// Creates a completed migration payload.
  public init(store: String, fromSchema: Int, toSchema: Int, backupPath: String) {
    self.store = store
    self.fromSchema = fromSchema
    self.toSchema = toSchema
    self.backupPath = backupPath
  }

  /// The typed event.
  public var asEvent: Event { .systemMigrated(self) }
}
