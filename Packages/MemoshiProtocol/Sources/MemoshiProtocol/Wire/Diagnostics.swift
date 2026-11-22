import Foundation
import Synchronization
import os

/// Something a decoder kept instead of dropping or rejecting: an event or device message this
/// build cannot read, an event whose envelope breaks its class's rules, or a value outside the
/// limits its type declares. An unreadable event or message decodes as an explicit `.unknown`
/// case and an out-of-limits value is kept as received; this record says why, so the app can
/// count it in Developer diagnostics and resync the affected scope (events.md §10).
public struct ProtocolDiagnostic: Hashable, Sendable {
  /// Why the value was reported.
  public enum Reason: String, Hashable, Sendable {
    /// An event `type` this build does not know.
    case unknownEventType = "unknown_event_type"
    /// A known event `type` at a `typeVersion` this build cannot read.
    case unsupportedEventVersion = "unsupported_event_version"
    /// A known event whose payload failed to decode.
    case undecodableEventPayload = "undecodable_event_payload"
    /// A known event whose `seq`, `after` or `cseq` disagree with its class: a UI-only frame
    /// carries `seq: null` and `after`, a durable one a `seq` (events.md §2). The event is kept.
    case inconsistentEventClass = "inconsistent_event_class"
    /// A device message `type` this build does not know.
    case unknownDeviceMessageType = "unknown_device_message_type"
    /// A known device message whose payload failed to decode.
    case undecodableDeviceMessage = "undecodable_device_message"
    /// A value outside the limits its type declares, such as a tier of 7 or a title over 120
    /// characters. The value is kept as received.
    case constraintViolated = "constraint_violated"
  }

  /// Why the value was reported.
  public let reason: Reason
  /// The event or device message `type`; for ``Reason/constraintViolated``, the value's wire
  /// type, such as `Tier`.
  public let type: String
  /// The event's `typeVersion`; `nil` otherwise.
  public let typeVersion: Int?
  /// The event's `seq`; `nil` for a UI-only frame and for anything that is not an event.
  public let seq: Int64?
  /// The conversation the value belongs to, when it names one.
  public let conversationId: String?
  /// The coding path of the value inside its frame.
  public let codingPath: String
  /// A human-readable explanation, such as the payload's decoding error.
  public let detail: String

  /// Creates a diagnostic.
  public init(
    reason: Reason, type: String, typeVersion: Int?, seq: Int64?, conversationId: String?,
    codingPath: String, detail: String
  ) {
    self.reason = reason
    self.type = type
    self.typeVersion = typeVersion
    self.seq = seq
    self.conversationId = conversationId
    self.codingPath = codingPath
    self.detail = detail
  }
}

/// Receives ``ProtocolDiagnostic``s from a decoder. Install one with
/// ``CodingUserInfoKey/memoshiDiagnostics`` in `JSONDecoder.userInfo`.
public protocol ProtocolDiagnosticsSink: AnyObject, Sendable {
  /// Records one diagnostic. Called synchronously during decoding.
  func report(_ diagnostic: ProtocolDiagnostic)
}

/// A thread-safe sink that keeps every diagnostic it receives.
public final class ProtocolDiagnosticsLog: ProtocolDiagnosticsSink {
  private let entries = Mutex<[ProtocolDiagnostic]>([])

  /// Creates an empty log.
  public init() {}

  /// Appends the diagnostic.
  public func report(_ diagnostic: ProtocolDiagnostic) {
    entries.withLock { $0.append(diagnostic) }
  }

  /// Every diagnostic received so far, in order.
  public var diagnostics: [ProtocolDiagnostic] {
    entries.withLock { $0 }
  }
}

extension CodingUserInfoKey {
  /// The ``ProtocolDiagnosticsSink`` that receives unknown and undecodable events and device
  /// messages, and values outside their limits. Without one, diagnostics go to the unified log,
  /// so nothing passes silently.
  public static let memoshiDiagnostics = protocolKey("com.mehmetcanbudak.memoshi.diagnostics")

  /// `true` makes decoding strict, as the engine decodes: unknown event and device message
  /// types, undecodable payloads, unknown enum values and union kinds, values outside their
  /// limits and envelope inconsistencies throw instead of being kept.
  public static let memoshiStrictDecoding = protocolKey("com.mehmetcanbudak.memoshi.strict")

  private static func protocolKey(_ rawValue: String) -> CodingUserInfoKey {
    guard let key = CodingUserInfoKey(rawValue: rawValue) else {
      preconditionFailure("Invalid CodingUserInfoKey \(rawValue)")
    }
    return key
  }
}

private let diagnosticsLogger = Logger(
  subsystem: "com.mehmetcanbudak.memoshi", category: "protocol")

extension Decoder {
  /// Whether this decoder decodes strictly (``CodingUserInfoKey/memoshiStrictDecoding``).
  public var isStrictProtocolDecoding: Bool {
    userInfo[.memoshiStrictDecoding] as? Bool ?? false
  }

  /// The coding path as dotted text, with array positions as numbers, such as `1.params`.
  public var protocolCodingPath: String {
    codingPath.map { key in key.intValue.map(String.init) ?? key.stringValue }
      .joined(separator: ".")
  }

  /// Sends a diagnostic to the installed sink, or to the unified log when none is installed.
  public func reportProtocolDiagnostic(_ diagnostic: ProtocolDiagnostic) {
    if let sink = userInfo[.memoshiDiagnostics] as? any ProtocolDiagnosticsSink {
      sink.report(diagnostic)
    } else {
      let summary = "\(diagnostic.reason.rawValue) \(diagnostic.type): \(diagnostic.detail)"
      diagnosticsLogger.error("\(summary, privacy: .public)")
    }
  }

  /// Handles a value outside its type's limits: a strict decoder throws, and a lenient one
  /// keeps the value and reports ``ProtocolDiagnostic/Reason/constraintViolated``.
  ///
  /// - Parameters:
  ///   - detail: What is wrong, such as "Tier 7 is outside 0...5".
  ///   - wireType: The value's type name in the schema, such as `Tier`.
  public func handleConstraintViolation(_ detail: String, wireType: String) throws {
    if isStrictProtocolDecoding {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: codingPath, debugDescription: detail))
    }
    reportProtocolDiagnostic(
      ProtocolDiagnostic(
        reason: .constraintViolated, type: wireType, typeVersion: nil, seq: nil,
        conversationId: nil, codingPath: protocolCodingPath, detail: detail))
  }
}
