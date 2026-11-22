import Foundation
import MemoshiProtocol
import MemoshiTransport

/// The app-owned Keychain broker. Values returned here must remain memory-only.
/// The client authenticates the current carrier immediately before and after this operation.
public typealias KeychainHostHandler =
  @Sendable (HostKeychainGetParams) async throws -> HostKeychainGetResult

/// Values from the actual app/CLI bundle, never a fabricated daemon or model identity.
public struct ClientConfiguration: Sendable {
  /// This user's device-local Memoshi data root.
  public let dataDirectory: URL
  /// The trusted helper team and sealed identifier allowlist.
  public let peerPolicy: PeerPolicy
  /// The real connecting application or CLI build identity.
  public let client: ClientInfo
  /// The locale advertised in hello.
  public let locale: String
  /// The time-zone identifier advertised in hello.
  public let timeZone: String
  /// The deadline for one request, without automatic mutator retries.
  public let requestTimeout: Duration
  /// Whether unexpected transport loss schedules reconnect attempts.
  public let automaticallyReconnect: Bool

  /// Configures the authenticated local client and its request/reconnect policy.
  public init(
    dataDirectory: URL, peerPolicy: PeerPolicy, client: ClientInfo,
    locale: String = Locale.current.identifier,
    timeZone: String = TimeZone.current.identifier,
    requestTimeout: Duration = .seconds(30), automaticallyReconnect: Bool = true
  ) {
    self.dataDirectory = dataDirectory
    self.peerPolicy = peerPolicy
    self.client = client
    self.locale = locale
    self.timeZone = timeZone
    self.requestTimeout = requestTimeout
    self.automaticallyReconnect = automaticallyReconnect
  }
}

/// Local infrastructure state only. Even `.connected` says nothing about model availability.
public enum ClientConnectionState: String, Hashable, Sendable {
  case disconnected
  case connecting
  case syncing
  case connected
  case reconnecting
  case daemonStopped
  case versionMismatch
  case signingRequired
  case failed
}

/// Local lifecycle, protocol, synchronization and admission failures.
public enum ClientError: Error, Hashable, Sendable {
  case notConnected
  case notSynchronized
  case subscriptionBusy
  case disconnected
  case requestTimedOut(method: String)
  case inFlightLimit(Int)
  case versionMismatch(selected: Int)
  case protocolViolation(String)
  case eventConsumerAlreadyAttached
  case staleAcknowledgment
  case invalidResyncWatermark(expected: Int64, actual: Int64)
  case eventBufferOverflow
  case connectionClosed(code: Int, reason: String)
}

/// Non-sensitive failure classification. `connect()` still throws the original typed error; a
/// pending `call` is told `ClientError.connectionClosed` for a plain loss.
public enum ClientFailure: Hashable, Sendable {
  case transport
  case daemonStopped
  case signingRequired
  case versionMismatch
  case protocolViolation
  case eventBufferOverflow
}

/// An in-memory view of transport readiness, applied cursor and required bootstrap work.
public struct ClientStatus: Hashable, Sendable {
  /// Infrastructure readiness, not model or connector availability.
  public var state: ClientConnectionState
  /// The accepted hello for the current live connection.
  public var hello: SystemHelloResult?
  /// The last consumer-applied durable sequence; never persisted on disk.
  public var lastAppliedSeq: Int64?
  /// Requests currently awaiting a response or cancellation.
  public var pendingCalls: Int
  /// The current snapshot barrier that the consumer must actually satisfy.
  public var resync: ResyncRequest?
  /// The latest non-sensitive connection failure classification.
  public var failure: ClientFailure?
  /// Whether the current connection has an event subscription.
  public var isSubscribed: Bool
}

/// A receipt for one durable event. Call `acknowledgeApplied` only after the consumer has
/// applied it to its real in-memory stores, including retaining/diagnosing unknown events.
/// Receipts become invalid on disconnect or a full resync; delivery alone never advances seq.
public struct EventDelivery: Hashable, Sendable {
  /// The unique receipt, invalidated by disconnect or resync.
  public let id: UUID
  /// The durable fact the consumer must apply before acknowledging.
  public let envelope: EventEnvelope

  init(envelope: EventEnvelope) {
    id = UUID()
    self.envelope = envelope
  }
}

/// A list-then-watch barrier, not a fabricated domain snapshot. Load every participating
/// domain using its real list/history `asOf`, retain those per-domain watermarks, and reconcile
/// events against them. Only then acknowledge this baseline with `completeResync`.
public struct ResyncRequest: Hashable, Sendable {
  /// Why the consumer must replace its domain snapshots.
  public enum Reason: String, Hashable, Sendable {
    case coldStart
    case cursorExpired
    case serverRequested
  }

  /// The identity of this specific bootstrap barrier.
  public let id: UUID
  /// The exact global baseline to acknowledge after snapshots cover it.
  public let head: Int64
  /// The server's oldest retained global sequence at the barrier.
  public let minRetainedSeq: Int64
  /// The condition that invalidated the previous baseline.
  public let reason: Reason
  /// The original server control event, including an unknown payload, when it caused resync.
  public let trigger: EventEnvelope?
  /// The daemon's `ts` for the event at `head`, kept with the cursor once this is completed.
  let headTs: Int64?

  init(
    head: Int64, minRetainedSeq: Int64, reason: Reason, trigger: EventEnvelope? = nil,
    headTs: Int64? = nil
  ) {
    id = UUID()
    self.head = head
    self.minRetainedSeq = minRetainedSeq
    self.reason = reason
    self.trigger = trigger
    self.headTs = headTs
  }
}

/// A durable delivery receipt, ephemeral frame or explicit snapshot requirement.
public enum ClientEvent: Hashable, Sendable {
  case event(EventDelivery)
  /// UI-only events carry `after`, not a cursor to acknowledge.
  case transient(EventEnvelope)
  case resyncRequired(ResyncRequest)
}

/// A bounded FIFO that releases consumed payloads without shifting every remaining event.
struct EventBuffer {
  struct Entry: Sendable {
    let envelope: EventEnvelope
    let bytes: Int
  }

  private var storage: [Entry?] = []
  private var start = 0
  private(set) var bytes = 0
  var count: Int { storage.count - start }
  var first: Entry? { start < storage.count ? storage[start] : nil }

  mutating func append(_ entry: Entry) {
    storage.append(entry)
    bytes += entry.bytes
  }

  mutating func popFirst() -> Entry? {
    guard start < storage.count, let entry = storage[start] else { return nil }
    storage[start] = nil
    start += 1
    bytes -= entry.bytes
    if start == storage.count {
      storage.removeAll(keepingCapacity: true)
      start = 0
    } else if start >= 1024, start >= storage.count / 2 {
      storage.removeFirst(start)
      start = 0
    }
    return entry
  }

  mutating func removeAll() {
    storage.removeAll(keepingCapacity: false)
    start = 0
    bytes = 0
  }
}
