import Foundation

/// An isolated review profile created by a Browser Review lab. Its UUID identifies its own
/// persistent `WKWebsiteDataStore`; the lab never opens or removes an unrelated store.
struct BrowserReviewProfile: Codable, Hashable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let createdAt: Date
  var probe: BrowserIsolationProbe?

  /// A short, non-secret suffix that distinguishes profiles with similar names.
  var shortID: String { String(id.uuidString.prefix(8)) }
}

/// A non-secret cookie that checks store isolation and retained-profile persistence.
struct BrowserIsolationProbe: Codable, Hashable, Sendable {
  static let cookieName = "memoshi_review_probe"
  /// `.invalid` never resolves (RFC 2606), so the probe cookie never reaches a real site.
  static let cookieDomain = "isolation-probe.memoshi.invalid"

  let nonce: String
  let setAt: Date
}
