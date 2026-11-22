import Foundation
import MemoshiProtocol

/// Only the first private-pipe line carries a credential. It is never copied to a log.
package struct S1HostConfiguration: Codable, Sendable {
  package var directory: String
  package var providerBaseURL: String
  package var providerSecretRef: String
  package var providerBearer: String
}

/// Qualification controls are explicitly outside the production JSON-RPC method catalogue.
package struct S1Control: Codable, Sendable {
  package var s1: String
  package var id: String
  package var requestIds: [ULID] = []
  package var after: Int64 = 0
  package var through: Int64?
  package var retentionDays: Int?
}

package struct S1EventPage: Codable, Sendable {
  package var head: Int64
  package var through: Int64
  package var nextAfter: Int64
  package var hasMore: Bool
  package var events: [EventEnvelope]
}

package struct S1ControlReply: Codable, Sendable {
  package var s1 = "reply"
  package var id: String
  package var ok: Bool
  package var error: String?
  package var reading: S1ProcessReading?
  package var page: S1EventPage?
  package var durationNs: Int64?
  package var committedEvents: Int?
}

/// Emitted separately, never smuggled into a typed production method result.
package struct S1CallMeasurement: Codable, Sendable {
  package var s1 = "measurement"
  package var id: String
  package var method: String
  package var durationNs: Int64
  package var openThreadsBefore: Int
  package var openThreadsAfter: Int
  package var liveRunsAfter: Int
}

package struct S1RPCReply: Sendable {
  package var frame: Data
  package var measurement: S1CallMeasurement?
}
