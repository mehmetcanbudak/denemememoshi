/// A value that is not a well-formed identifier.
public struct IdentifierError: Error, Hashable, Sendable {
  /// The rejected value.
  public let value: String
  /// What was expected, for example `bot_<ULID>`.
  public let expected: String
}

/// A ULID: 26 uppercase Crockford base32 characters, the first `0`–`7`.
///
/// Used bare where the protocol wants a client-generated unique key, such as a mutating
/// method's `requestId` (protocol.md §9) or a device message's `msgId` (§12.1).
public struct ULID: Hashable, Sendable, Codable, CustomStringConvertible, WireShaped {
  /// The ULID's text.
  public let rawValue: String

  /// Validates and wraps a ULID string.
  public init(_ rawValue: String) throws(IdentifierError) {
    guard ULIDFormat.isValid(rawValue.utf8) else {
      throw IdentifierError(value: rawValue, expected: "a 26-character ULID")
    }
    self.rawValue = rawValue
  }

  /// Decodes and validates a ULID string.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    do {
      try self.init(raw)
    } catch {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a ULID: \(raw)")
    }
  }

  /// Encodes the ULID's text.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// The ULID's text.
  public var description: String { rawValue }

  /// A bare ULID.
  public static var wireShape: WireShape { .ulid }
}

/// The kind of object a prefixed ID names. Each kind is a caseless enum used as a phantom type.
public protocol ObjectIDKind: Sendable {
  /// The lowercase prefixes an ID of this kind may carry, without the underscore. More than one
  /// means a union, such as a conversation ID.
  static var idPrefixes: [String] { get }
}

/// A prefixed object ID, `<prefix>_<ULID>` (object-model.md §1.1), such as
/// `bot_01JC3F7Q9R2M8K4T6V5W0X1Y2Z`. The phantom `Kind` keeps a task ID from being passed
/// where a card ID belongs.
public struct ObjectID<Kind: ObjectIDKind>: Hashable, Sendable, Codable, CustomStringConvertible,
  WireShaped, WireNamed
{
  /// The ID's text.
  public let rawValue: String

  /// Validates and wraps an ID string.
  public init(_ rawValue: String) throws(IdentifierError) {
    let utf8 = rawValue.utf8
    let matches = Kind.idPrefixes.contains { prefix in
      utf8.count == prefix.utf8.count + 27
        && utf8.starts(with: prefix.utf8)
        && utf8.dropFirst(prefix.utf8.count).first == UInt8(ascii: "_")
        && ULIDFormat.isValid(utf8.dropFirst(prefix.utf8.count + 1))
    }
    guard matches else {
      let prefixes = Kind.idPrefixes.map { "\($0)_" }.joined(separator: " or ")
      throw IdentifierError(value: rawValue, expected: "\(prefixes) followed by a ULID")
    }
    self.rawValue = rawValue
  }

  /// Decodes and validates an ID string.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    do {
      try self.init(raw)
    } catch {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected \(error.expected), got \(raw)")
    }
  }

  /// Encodes the ID's text.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// The ID's text.
  public var description: String { rawValue }

  /// The ID's prefix, such as `bot`.
  public var prefix: Substring {
    rawValue.prefix { $0 != "_" }
  }

  /// A prefixed ULID with this kind's prefixes.
  public static var wireShape: WireShape { .prefixedID(Kind.idPrefixes) }

  /// The kind's name without its `Kind` suffix, such as `BotID`.
  public static var wireName: String {
    let kindName = String(describing: Kind.self)
    return kindName.hasSuffix("Kind") ? String(kindName.dropLast(4)) : kindName
  }
}

private enum ULIDFormat {
  static func isValid(_ utf8: some Collection<UInt8>) -> Bool {
    guard utf8.count == 26, let first = utf8.first,
      (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(first)
    else { return false }
    return utf8.allSatisfy(isCrockford)
  }

  /// Crockford base32: digits and uppercase letters except I, L, O and U.
  static func isCrockford(_ byte: UInt8) -> Bool {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "A")...UInt8(ascii: "H"),
      UInt8(ascii: "J"), UInt8(ascii: "K"), UInt8(ascii: "M"), UInt8(ascii: "N"),
      UInt8(ascii: "P")...UInt8(ascii: "T"), UInt8(ascii: "V")...UInt8(ascii: "Z"):
      true
    default:
      false
    }
  }
}

/// A bot, the Assistant included: `bot_`.
public typealias BotID = ObjectID<BotIDKind>
/// A Chat: `cht_`.
public typealias ChatID = ObjectID<ChatIDKind>
/// Any conversation: a Chat, Session, Lane, Group or Side thread.
public typealias ConversationID = ObjectID<ConversationIDKind>
/// A Session: `ses_`.
public typealias SessionID = ObjectID<SessionIDKind>
/// A Project: `prj_`.
public typealias ProjectID = ObjectID<ProjectIDKind>
/// A Task: `tsk_`.
public typealias TaskID = ObjectID<TaskIDKind>
/// A Routine: `rtn_`.
public typealias RoutineID = ObjectID<RoutineIDKind>
/// A Watch: `wch_`.
public typealias WatchID = ObjectID<WatchIDKind>
/// A Wake: `wak_`.
public typealias WakeID = ObjectID<WakeIDKind>
/// A Handoff: `hnd_`.
public typealias HandoffID = ObjectID<HandoffIDKind>
/// A Card: `crd_`.
public typealias CardID = ObjectID<CardIDKind>
/// An Approval: `apr_`.
public typealias ApprovalID = ObjectID<ApprovalIDKind>
/// A Grant: `grt_`.
public typealias GrantID = ObjectID<GrantIDKind>
/// A Budget: `bud_`.
public typealias BudgetID = ObjectID<BudgetIDKind>
/// A message index row: `msg_`.
public typealias MessageID = ObjectID<MessageIDKind>
/// A paired device: `dev_`.
public typealias DeviceID = ObjectID<DeviceIDKind>
/// A side thread: `sth_`.
public typealias SideThreadID = ObjectID<SideThreadIDKind>
/// A program: a live card (`crd_`) or an App (`app_`).
public typealias ProgramID = ObjectID<ProgramIDKind>

/// The kind of ``BotID``.
public enum BotIDKind: ObjectIDKind {
  /// `bot`.
  public static let idPrefixes = ["bot"]
}

/// The kind of ``ChatID``.
public enum ChatIDKind: ObjectIDKind {
  /// `cht`.
  public static let idPrefixes = ["cht"]
}

/// The kind of ``ConversationID``: `ID<conversation>` in object-model.md §1.2.
public enum ConversationIDKind: ObjectIDKind {
  /// `cht`, `ses`, `lan`, `grp` (v1.1) and `sth`.
  public static let idPrefixes = ["cht", "ses", "lan", "grp", "sth"]
}

/// The kind of ``SessionID``.
public enum SessionIDKind: ObjectIDKind {
  /// `ses`.
  public static let idPrefixes = ["ses"]
}

/// The kind of ``ProjectID``.
public enum ProjectIDKind: ObjectIDKind {
  /// `prj`.
  public static let idPrefixes = ["prj"]
}

/// The kind of ``TaskID``.
public enum TaskIDKind: ObjectIDKind {
  /// `tsk`.
  public static let idPrefixes = ["tsk"]
}

/// The kind of ``RoutineID``.
public enum RoutineIDKind: ObjectIDKind {
  /// `rtn`.
  public static let idPrefixes = ["rtn"]
}

/// The kind of ``WatchID``.
public enum WatchIDKind: ObjectIDKind {
  /// `wch`.
  public static let idPrefixes = ["wch"]
}

/// The kind of ``WakeID``.
public enum WakeIDKind: ObjectIDKind {
  /// `wak`.
  public static let idPrefixes = ["wak"]
}

/// The kind of ``HandoffID``.
public enum HandoffIDKind: ObjectIDKind {
  /// `hnd`.
  public static let idPrefixes = ["hnd"]
}

/// The kind of ``CardID``.
public enum CardIDKind: ObjectIDKind {
  /// `crd`.
  public static let idPrefixes = ["crd"]
}

/// The kind of ``ApprovalID``.
public enum ApprovalIDKind: ObjectIDKind {
  /// `apr`.
  public static let idPrefixes = ["apr"]
}

/// The kind of ``GrantID``.
public enum GrantIDKind: ObjectIDKind {
  /// `grt`.
  public static let idPrefixes = ["grt"]
}

/// The kind of ``BudgetID``.
public enum BudgetIDKind: ObjectIDKind {
  /// `bud`.
  public static let idPrefixes = ["bud"]
}

/// The kind of ``MessageID``.
public enum MessageIDKind: ObjectIDKind {
  /// `msg`.
  public static let idPrefixes = ["msg"]
}

/// The kind of ``DeviceID``.
public enum DeviceIDKind: ObjectIDKind {
  /// `dev`.
  public static let idPrefixes = ["dev"]
}

/// The kind of ``SideThreadID``.
public enum SideThreadIDKind: ObjectIDKind {
  /// `sth`.
  public static let idPrefixes = ["sth"]
}

/// The kind of ``ProgramID``.
public enum ProgramIDKind: ObjectIDKind {
  /// `app` (an App) and `crd` (a live card).
  public static let idPrefixes = ["app", "crd"]
}
