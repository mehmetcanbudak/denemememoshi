/// The kind of an ``Actor`` (events.md §2).
public enum ActorKind: OpenEnum {
  case user
  case assistant
  case bot
  /// A routine, watch or wake that fired.
  case trigger
  case system
  /// An external coding agent (v1.1).
  case externalAgent
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .user: "user", .assistant: "assistant", .bot: "bot", .trigger: "trigger",
    .system: "system", .externalAgent: "external_agent",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// The kind of an ``Origin`` (object-model.md §3.3).
public enum OriginKind: OpenEnum {
  case user
  case assistant
  case bot
  case routine
  case wake
  case watch
  case webhook
  case connectorEvent
  /// App Intents and Shortcuts.
  case intent
  /// A live card's or App's own call outside a user gesture.
  case app
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .user: "user", .assistant: "assistant", .bot: "bot", .routine: "routine", .wake: "wake",
    .watch: "watch", .webhook: "webhook", .connectorEvent: "connector_event",
    .intent: "intent", .app: "app",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// How attended a run is, derived from its origin (object-model.md §3.3).
public enum Regime: OpenEnum {
  case attended
  case unattended
  case untrusted
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .attended: "attended", .unattended: "unattended", .untrusted: "untrusted",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// Whether the user is present for an approval or policy decision (object-model.md §3.3).
public enum Attendance: OpenEnum {
  case attended
  case unattended
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .attended: "attended", .unattended: "unattended",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// A bot's permission mode (D52).
public enum PermissionMode: OpenEnum {
  case askFirst
  case auto
  case bypass
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .askFirst: "ask_first", .auto: "auto", .bypass: "bypass",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// The kind of a Computer (object-model.md §4.13).
public enum ComputerKind: OpenEnum {
  /// This Mac (sandboxed).
  case macSandbox
  /// The in-app environment on iPhone and iPad.
  case inApp
  /// Emulated Linux (iSH) on iPhone and iPad, Phase 3.
  case linuxEmulated
  /// A Bot computer, v1.1.
  case botVm
  /// A Remote machine, v1.1.
  case remoteSsh
  /// A Cloud computer, v2.
  case cloud
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .macSandbox: "mac_sandbox", .inApp: "in_app", .linuxEmulated: "linux_emulated",
    .botVm: "bot_vm", .remoteSsh: "remote_ssh", .cloud: "cloud",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// Where a mutating request came from; policy and audit derive its origin from it
/// (protocol.md §3.4). Absent means `ui`.
public enum RequestSurface: OpenEnum {
  case ui
  case notification
  case menuBar
  case intent
  case cli
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .ui: "ui", .notification: "notification", .menuBar: "menu_bar", .intent: "intent",
    .cli: "cli",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// How a device checked its owner for a T4 or T5 decision (D75).
public enum DeviceAuthMethod: OpenEnum {
  case faceId
  case touchId
  case passcode
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .faceId: "face_id", .touchId: "touch_id", .passcode: "passcode",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// A model's thinking level: PiAI's levels (object-model.md §4.3).
public enum ThinkingEffort: OpenEnum {
  case off
  case minimal
  case low
  case medium
  case high
  case xhigh
  case max
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .off: "off", .minimal: "minimal", .low: "low", .medium: "medium", .high: "high",
    .xhigh: "xhigh", .max: "max",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}

/// What a send does while its conversation is busy (protocol.md §5.3).
public enum WhenBusy: OpenEnum {
  /// Queue the input after the current turn.
  case followUp
  /// Steer the current turn.
  case steer
  /// Fail with `busy`.
  case reject
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .followUp: "follow_up", .steer: "steer", .reject: "reject",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
