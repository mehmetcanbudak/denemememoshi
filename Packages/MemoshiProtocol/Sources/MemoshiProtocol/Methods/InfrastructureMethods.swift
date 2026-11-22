/// `system.ping`: liveness above the WebSocket keepalive (protocol.md §5.1).
public enum SystemPing: RPCMethod {
  /// Empty parameters.
  public typealias Params = EmptyParams
  /// The daemon's clock.
  public typealias Result = SystemPingResult
  /// `system.ping`.
  public static let name = "system.ping"
  /// Does not mutate durable state.
  public static let isMutating = false
}

/// The daemon's current Unix time in milliseconds.
public struct SystemPingResult: Codable, Hashable, Sendable {
  /// The response time in Unix milliseconds.
  public var serverTime: Int64

  /// Creates a clock response.
  public init(serverTime: Int64) {
    self.serverTime = serverTime
  }
}

/// `events.focus`: choose the conversations receiving live-only content.
public enum EventsFocus: RPCMethod {
  /// The replacement focus set.
  public typealias Params = EventsFocusParams
  /// An empty acknowledgment.
  public typealias Result = EmptyParams
  /// `events.focus`.
  public static let name = "events.focus"
  /// Changes only connection-local routing.
  public static let isMutating = false
}

/// The bounded replacement focus set, not an additional subscription.
public struct EventsFocusParams: Codable, Hashable, Sendable {
  /// At most eight conversations whose live-only content is requested.
  public var conversationIds: FocusList

  /// Creates a bounded replacement focus set.
  public init(conversationIds: FocusList) {
    self.conversationIds = conversationIds
  }
}

/// `events.unsubscribe`: stop this connection's event stream.
public enum EventsUnsubscribe: RPCMethod {
  /// Empty parameters.
  public typealias Params = EmptyParams
  /// An empty acknowledgment.
  public typealias Result = EmptyParams
  /// `events.unsubscribe`.
  public static let name = "events.unsubscribe"
  /// Changes only the connection's subscription.
  public static let isMutating = false
}
