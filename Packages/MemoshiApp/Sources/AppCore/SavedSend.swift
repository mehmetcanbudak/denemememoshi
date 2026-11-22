import Foundation
import MemoshiProtocol

/// The Chat's saved Send in UI preferences (D130): its request, kept until a receipt or history
/// confirms it or the person discards it, and the engine's definite refusal of it on the latest
/// attempt. A relaunch then still offers Discard for a request the engine would refuse again.
/// The Mac and the in-process Chat keep it in this one shape.
public struct SavedSend {
  /// What a launch finds.
  public enum Record: Equatable, Sendable {
    /// A readable request and, when the engine refused it on its latest attempt, why.
    case readable(ChatsSendParams, refusal: String?)
    /// A record that could not be read. It can never be retried, only discarded.
    case unreadable
  }

  private static let requestKey = "text-chat.pending-send"
  private static let refusalKey = "text-chat.pending-send-refusal"
  private let defaults: UserDefaults

  /// The record lives in these UI preferences.
  public init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  /// The saved record, if there is one.
  public func load() -> Record? {
    guard let bytes = defaults.data(forKey: Self.requestKey) else { return nil }
    do {
      let request = try ProtocolCoding.makeDecoder(strict: true).decode(
        ChatsSendParams.self, from: bytes)
      return .readable(request, refusal: defaults.string(forKey: Self.refusalKey))
    } catch {
      return .unreadable
    }
  }

  /// Saves a new request, which the engine has not refused.
  public func save(_ request: ChatsSendParams) throws {
    let bytes = try ProtocolCoding.makeEncoder().encode(request)
    defaults.removeObject(forKey: Self.refusalKey)
    defaults.set(bytes, forKey: Self.requestKey)
  }

  /// Records why the engine refused the saved request on its latest attempt; nil while an
  /// attempt is in flight or when it was not refused.
  public func recordRefusal(_ reason: String?) {
    if let reason {
      defaults.set(reason, forKey: Self.refusalKey)
    } else {
      defaults.removeObject(forKey: Self.refusalKey)
    }
  }

  /// Removes the request and its refusal.
  public func remove() {
    defaults.removeObject(forKey: Self.requestKey)
    defaults.removeObject(forKey: Self.refusalKey)
  }
}
