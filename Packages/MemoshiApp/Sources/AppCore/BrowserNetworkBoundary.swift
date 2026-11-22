import Foundation
import WebKit

/// The bot browser's network boundary (2026-11-07 user decision): the authenticated gateway
/// route, a fixed deny-local content-rule list, a per-bot allowlist list, and Lockdown for every
/// bot page. Each part covers exits the others miss. WebKit sends loopback, IP-literal and
/// `localhost` loads directly even with a proxy set, so the deny-local list blocks them.
/// Lockdown is the only public switch that removes WebRTC and WebTransport, whose sockets skip
/// the proxy. A `target=_blank` activation still opens one payload-free connection to its
/// target; that is a known, reported residual, not something this type closes.
public enum BrowserNetworkBoundary {
  /// Stable identifier of the fixed deny-local list. Bump the version when its rules change.
  public static let denyLocalIdentifier = "memoshi.browser.deny-local.v1"
  private static let routeListPrefix = "memoshi.browser.route."
  private static let blockAllPrefix = "memoshi.browser.block-all."

  /// The compiled route list of one profile (a lab profile or a separate one, D136).
  public static func routeListIdentifier(profile: UUID) -> String {
    routeListPrefix + profile.uuidString.lowercased()
  }

  /// The compiled block-all list of one profile.
  public static func blockAllIdentifier(profile: UUID) -> String {
    blockAllPrefix + profile.uuidString.lowercased()
  }

  /// The profile a route or block-all list identifier belongs to, if it is one.
  static func profile(ofList identifier: String) -> UUID? {
    for prefix in [routeListPrefix, blockAllPrefix] where identifier.hasPrefix(prefix) {
      let suffix = identifier.dropFirst(prefix.count)
      guard let id = UUID(uuidString: String(suffix)), suffix == id.uuidString.lowercased()
      else { return nil }
      return id
    }
    return nil
  }

  /// Stable, content-free refusal codes for evidence and the address bar.
  public enum Denial: String, Error, Codable, Sendable {
    case lockdownMissing, denyLocalMissing, routeRulesMissing, gatewayMissing
    case originOutsideRoute, unsupportedScheme, invalidOrigin, compileFailed

    /// Whether a part of the boundary (Lockdown, a rule list, the route or its gateway) is
    /// missing. Otherwise the boundary refused the load itself: an origin outside its route, or
    /// an address it never loads.
    public var isIncompleteBoundary: Bool {
      switch self {
      case .lockdownMissing, .denyLocalMissing, .routeRulesMissing, .gatewayMissing, .compileFailed:
        true
      case .originOutsideRoute, .unsupportedScheme, .invalidOrigin: false
      }
    }
  }

  /// Which route list is installed. A fixture list exempts exact owned loopback origins.
  public enum RouteKind: String, Codable, Sendable {
    case gateway, ownedFixture
  }

  /// A compiled route list as installed on one web view.
  public struct RouteRules: Equatable, Codable, Sendable {
    /// The content-rule list identifier in the app-container store.
    public let identifier: String
    /// Which route this list belongs to.
    public let kind: RouteKind
    /// Exact canonical origins the list exempts from its block-all rule.
    public let origins: [String]

    /// Describes one compiled, installed route list.
    public init(identifier: String, kind: RouteKind, origins: [String]) {
      self.identifier = identifier
      self.kind = kind
      self.origins = origins
    }
  }

  /// What one web view has actually installed. Loads are refused unless every part needed for
  /// the load's route is present; nothing defaults to an open state.
  public struct State: Equatable, Codable, Sendable {
    /// Read back from the web view's configuration after it was created.
    public var lockdown = false
    /// Identifier of the installed deny-local list, when installed.
    public var denyLocal: String?
    /// The installed route list, when a route is configured.
    public var route: RouteRules?
    /// Identifier of the block-all list a host installs while a document outlives its route
    /// (for example after a revoke), when installed. Evidence only: it permits no load.
    public var blockAll: String?
    /// Whether the store's proxy configuration routes to the live authenticated gateway.
    public var gatewayApplied = false

    /// An empty state: nothing installed, so every load is refused.
    public init() {}

    /// Why an http(s) load of `url` must be refused, or nil when the boundary is complete.
    /// Gateway routes need the gateway, the deny-local list, the allowlist and Lockdown. The
    /// owned-fixture route needs its block-all list, an exempt exact loopback origin, no
    /// gateway and Lockdown; its list blocks everything deny-local would.
    public func denial(loading url: URL?) -> Denial? {
      guard let url, let scheme = url.scheme?.lowercased() else { return .invalidOrigin }
      guard scheme == "http" || scheme == "https" else { return .unsupportedScheme }
      guard let origin = BrowserAuthorization.origin(of: url) else { return .invalidOrigin }
      guard lockdown else { return .lockdownMissing }
      guard let route else { return .routeRulesMissing }
      switch route.kind {
      case .gateway:
        guard denyLocal != nil else { return .denyLocalMissing }
        guard gatewayApplied else { return .gatewayMissing }
      case .ownedFixture:
        guard !gatewayApplied, BrowserNetworkBoundary.isLoopbackOrigin(origin) else {
          return .originOutsideRoute
        }
      }
      return route.origins.contains(origin) ? nil : .originOutsideRoute
    }

    /// Why an app-supplied offline document (no main-resource fetch) must be refused. Its
    /// page-initiated loads still meet at least one block list and Lockdown.
    public var offlineDocumentDenial: Denial? {
      guard lockdown else { return .lockdownMissing }
      guard denyLocal != nil || route != nil else { return .denyLocalMissing }
      return nil
    }

    /// A compact evidence code naming the active lists and restriction mode.
    public var evidenceCode: String {
      var parts = [lockdown ? "lockdown" : "noLockdown"]
      parts.append("denyLocal=" + (denyLocal ?? "none"))
      parts.append("route=" + (route.map { $0.kind.rawValue + ":" + $0.identifier } ?? "none"))
      if let blockAll { parts.append("blockAll=" + blockAll) }
      parts.append(gatewayApplied ? "gateway" : "noGateway")
      return "boundary:" + parts.joined(separator: ",")
    }
  }

  /// Loopback hosts accepted by the owned-fixture route.
  public static func isLoopbackOrigin(_ origin: String) -> Bool {
    guard let host = URL(string: origin)?.host()?.lowercased() else { return false }
    return ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
  }

  /// Fixed deny-local rules: every loopback, IPv4/IPv6 literal, `localhost` and `.local` URL,
  /// with optional userinfo and a trailing root dot. `url-filter` has no disjunction, so each
  /// class is its own block rule. WebKit matches the canonical URL, so numeric IPv4 spellings
  /// such as `2130706433` arrive as dotted quads.
  public static let denyLocalFilters = [
    #"^[a-z][a-z0-9+.-]*://([^/?#@]*@)?\["#,
    #"^[a-z][a-z0-9+.-]*://([^/?#@]*@)?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.?[:/?#]"#,
    #"^[a-z][a-z0-9+.-]*://([^/?#@]*@)?localhost\.?[:/?#]"#,
    #"^[a-z][a-z0-9+.-]*://([^/?#@]*@)?[^/?#@]*\.localhost\.?[:/?#]"#,
    #"^[a-z][a-z0-9+.-]*://([^/?#@]*@)?[^/?#@]*\.local\.?[:/?#]"#,
  ]

  /// The fixed deny-local filters encoded as a `WKContentRuleList` source.
  public static var denyLocalJSON: String {
    encode(denyLocalFilters.map { ["trigger": ["url-filter": $0], "action": ["type": "block"]] })
  }

  /// Block-all, then exact-origin exemptions for each canonical origin: its network URLs and
  /// its own `blob:` URLs. Used for the per-bot allowlist (gateway route) and the owned-fixture
  /// route. WebKit reads File and Blob contents (`File.text()`, `FileReader`, a fetched object
  /// URL) through blob: URL loads that content rules see, so without the second exemption a
  /// granted page cannot read a file the person chose. blob: data never leaves the device, and
  /// another origin's blobs stay blocked. Malformed origins are refused.
  public static func allowlistJSON(origins: [String]) throws(Denial) -> String {
    var rules: [[String: Any]] = [["trigger": ["url-filter": ".*"], "action": ["type": "block"]]]
    for origin in origins {
      guard BrowserAuthorization.canonicalOrigin(origin) == origin,
        let components = URLComponents(string: origin), let scheme = components.scheme,
        let host = URL(string: origin)?.host()
      else { throw .invalidOrigin }
      let authority = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
      let port = components.port.map { ":\($0)" } ?? ""
      let exact = scheme + "://" + NSRegularExpression.escapedPattern(for: authority + port) + "/"
      for prefix in ["^", "^blob:"] {
        rules.append([
          "trigger": ["url-filter": prefix + exact], "action": ["type": "ignore-previous-rules"],
        ])
      }
    }
    return encode(rules)
  }

  private static func encode(_ rules: [[String: Any]]) -> String {
    // Fixed string dictionaries always serialize.
    let data =
      (try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])) ?? Data()
    return String(decoding: data, as: UTF8.self)
  }

  /// Sets Lockdown on a configuration before its web view is created. Callers must read the
  /// mode back from the created web view's configuration; only that read-back counts.
  @MainActor
  public static func applyLockdown(to configuration: WKWebViewConfiguration) {
    configuration.defaultWebpagePreferences.securityRestrictionMode = .lockdown
  }

  /// Whether the created web view actually runs in Lockdown Mode, read from its configuration.
  @MainActor
  public static func lockdownIsActive(on webView: WKWebView) -> Bool {
    webView.configuration.defaultWebpagePreferences.securityRestrictionMode == .lockdown
  }
}

/// Compiled content-rule lists in an app-container directory, never `WKContentRuleListStore`'s
/// shared default store.
@MainActor
public final class BrowserContentRuleStore {
  /// The directory backing this store's compiled lists.
  public let directory: URL
  private let store: WKContentRuleListStore
  private var denyLocalTask: Task<WKContentRuleList, any Error>?

  /// The app's own store under Application Support, created owner-only on first use.
  public static func appContainer() throws -> BrowserContentRuleStore {
    if let shared { return shared }
    let store = try BrowserContentRuleStore(directory: appContainerDirectory())
    shared = store
    return store
  }

  /// The app's store if it was ever created; nil otherwise, without creating anything.
  public static func existingAppContainer() throws -> BrowserContentRuleStore? {
    if let shared { return shared }
    guard FileManager.default.fileExists(atPath: try appContainerDirectory().path) else {
      return nil
    }
    return try appContainer()
  }

  private static func appContainerDirectory() throws -> URL {
    try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    ).appendingPathComponent("Memoshi Development/Browser Content Rules", isDirectory: true)
  }

  private static var shared: BrowserContentRuleStore?

  /// Opens (creating owner-only if needed) a store in `directory`.
  public init(directory: URL) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    self.directory = directory
    store = WKContentRuleListStore(url: directory)
  }

  /// Compiles (or replaces) one list. A nil or failed compile never yields an open list.
  public func compile(identifier: String, json: String) async throws(BrowserNetworkBoundary.Denial)
    -> WKContentRuleList
  {
    let list: WKContentRuleList?
    do {
      list = try await store.compileContentRuleList(
        forIdentifier: identifier, encodedContentRuleList: json)
    } catch { throw .compileFailed }
    guard let list, list.identifier == identifier else { throw .compileFailed }
    return list
  }

  /// The fixed deny-local list, compiled once per store and process.
  public func denyLocal() async throws(BrowserNetworkBoundary.Denial) -> WKContentRuleList {
    let task =
      denyLocalTask
      ?? Task<WKContentRuleList, any Error> { @MainActor in
        try await self.compile(
          identifier: BrowserNetworkBoundary.denyLocalIdentifier,
          json: BrowserNetworkBoundary.denyLocalJSON)
      }
    denyLocalTask = task
    do { return try await task.value } catch {
      denyLocalTask = nil
      throw .compileFailed
    }
  }

  /// Removes one compiled route list from the store. The shared deny-local list is never removed.
  public func remove(identifier: String) {
    guard identifier != BrowserNetworkBoundary.denyLocalIdentifier else { return }
    store.removeContentRuleList(forIdentifier: identifier) { _ in }
  }

  /// Every compiled list's identifier.
  public func identifiers() async -> [String] {
    await withCheckedContinuation { continuation in
      store.getAvailableContentRuleListIdentifiers { continuation.resume(returning: $0 ?? []) }
    }
  }

  /// Removes the route and block-all lists of every profile `keeps` does not claim: the lists a
  /// crash or a quit left behind, a separate profile's above all (D136). `keeps` is asked when
  /// each list is reached, so a profile opened meanwhile keeps its lists. Other lists stay.
  /// Returns the identifiers removed.
  public func sweepProfileLists(keeping keeps: @MainActor (UUID) -> Bool) async -> [String] {
    var removed: [String] = []
    for identifier in await identifiers() {
      guard let profile = BrowserNetworkBoundary.profile(ofList: identifier), !keeps(profile)
      else { continue }
      let done: Bool = await withCheckedContinuation { continuation in
        store.removeContentRuleList(forIdentifier: identifier) {
          continuation.resume(returning: $0 == nil)
        }
      }
      if done { removed.append(identifier) }
    }
    return removed
  }
}
