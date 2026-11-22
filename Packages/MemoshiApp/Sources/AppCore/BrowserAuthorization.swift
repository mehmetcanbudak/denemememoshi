import Foundation
import WebKit

/// Exact browser-site grants used by the explicit S3 lab and shared native browser hosts.
/// These are host-owned review permissions, not a replacement for the daemon policy engine.
public enum BrowserAuthorization {
  /// Stable, content-free denial codes suitable for a report.
  public enum Denial: String, Error, Codable, Sendable {
    case invalidOrigin, siteNotGranted, interactRequired, draftRequired, purchaseRequired
    case exposureConfirmationRequired, unsupportedMethod, staleDocument, expired, revoked
    /// A form or non-GET navigation without the one-use permit a bot click staged for it.
    case unstagedForm
  }

  /// Canonical origins reject credentials, paths, query strings and fragments. Sign-ins require
  /// HTTPS even on owned fixtures; plain HTTP is useful only for explicitly selected local tests.
  public static func canonicalOrigin(_ text: String, requireHTTPS: Bool = false) -> String? {
    guard let components = URLComponents(string: text), let url = components.url,
      components.user == nil, components.password == nil, components.query == nil,
      components.fragment == nil, components.path.isEmpty || components.path == "/",
      let scheme = components.scheme?.lowercased(),
      scheme == "https" || (!requireHTTPS && scheme == "http"),
      let host = url.host()?.lowercased(), !host.isEmpty,
      !host.hasSuffix("."), !host.contains("%"), !host.contains("*"), !host.contains("\\"),
      url.port.map({ (1...65_535).contains($0) }) ?? true
    else { return nil }
    let authority = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    let port = components.port
    let suffix = port.flatMap { $0 == (scheme == "https" ? 443 : 80) ? nil : ":\($0)" } ?? ""
    return "\(scheme)://\(authority)\(suffix)"
  }

  /// A URL's origin, excluding all page-controlled path, userinfo and query text.
  public static func origin(of url: URL) -> String? {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.user == nil, components.password == nil
    else { return nil }
    components.path = ""
    components.query = nil
    components.fragment = nil
    return components.string.flatMap { canonicalOrigin($0) }
  }

  /// A frame's security origin as a canonical origin. Nil for an opaque origin (a sandboxed,
  /// `srcdoc` or `data:` frame): no grant, permit or site comparison matches it.
  @MainActor
  public static func origin(of securityOrigin: WKSecurityOrigin) -> String? {
    origin(scheme: securityOrigin.protocol, host: securityOrigin.host, port: securityOrigin.port)
  }

  /// The canonical origin of a scheme, host and port as WebKit reports them: port 0 for the
  /// scheme's default, an IPv6 host without brackets.
  public static func origin(scheme: String, host: String, port: Int) -> String? {
    let authority = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    return canonicalOrigin("\(scheme)://\(authority)\(port == 0 ? "" : ":\(port)")")
  }

  /// A person-approved exact site, without wildcard interaction or credential authority.
  public struct Site: Codable, Equatable, Sendable, Identifiable {
    /// Exact canonical origin.
    public let origin: String
    /// Whether non-consequential POST forms and buttons may run.
    public let interact: Bool
    /// Whether a separately approved account may fill credentials here.
    public let signIn: Bool
    /// Synthetic/local sites never count toward the five-real-site gate.
    public let ownedFixture: Bool
    /// Stable identity.
    public var id: String { origin }

    /// Refuses malformed origins and non-HTTPS sign-in grants.
    public init(origin: String, interact: Bool, signIn: Bool, ownedFixture: Bool) throws {
      guard let normalized = BrowserAuthorization.canonicalOrigin(origin),
        !signIn || normalized.hasPrefix("https://")
      else { throw Denial.invalidOrigin }
      self.origin = normalized
      self.interact = interact
      self.signIn = signIn
      self.ownedFixture = ownedFixture
    }
  }

  /// Page-derived hints only add friction. They never authorize a POST by themselves.
  public struct Action: Sendable {
    /// HTTP method for a form; nil for a non-form button.
    public let method: String?
    /// Exact form/link destination.
    public let destination: URL?
    /// Accessible name and action path, inspected only to add restrictions.
    public let label: String
    /// Whether the form contains payment-card fields.
    public let containsPaymentFields: Bool
    /// Forms always require fresh exposure confirmation once a page holds private data.
    public let isForm: Bool

    /// Creates untrusted action facts, never a permission.
    public init(
      method: String?, destination: URL?, label: String, containsPaymentFields: Bool,
      isForm: Bool = false
    ) {
      self.method = method
      self.destination = destination
      self.label = label
      self.containsPaymentFields = containsPaymentFields
      self.isForm = isForm
    }
  }

  /// Checks source and destination grants, operation class and private-data exposure at dispatch.
  public static func denial(
    action: Action, sourceOrigin: String, sites: [Site], privateData: Bool,
    exposureConfirmed: Bool = false
  ) -> Denial? {
    guard let source = sites.first(where: { $0.origin == sourceOrigin }) else {
      return .siteNotGranted
    }
    let path = action.destination?.path ?? ""
    let words = (action.label + " " + path).lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    let money: Set<String> = [
      "pay", "buy", "purchase", "order", "checkout", "transfer", "subscribe", "book", "donate",
      "bid",
    ]
    let consequential: Set<String> = [
      "send", "post", "publish", "reply", "comment", "share", "invite", "delete", "confirm",
      "apply", "signup",
    ]
    if action.containsPaymentFields || words.contains(where: money.contains) {
      return .purchaseRequired
    }
    if words.contains(where: consequential.contains)
      || words.joined(separator: " ").contains("sign up")
    {
      return .draftRequired
    }
    if let destination = action.destination {
      guard let target = origin(of: destination), sites.contains(where: { $0.origin == target })
      else {
        return .siteNotGranted
      }
      // A link to another site opens there in a separate, empty profile (D136), so only forms,
      // which carry page data, wait for exposure confirmation.
      if privateData && !exposureConfirmed && action.isForm {
        return .exposureConfirmationRequired
      }
    } else if action.isForm {
      // A page controls whether its form action parses. Without a destination neither the site
      // grant nor the private-data exposure can be checked, at any method.
      return .siteNotGranted
    }
    if let method = action.method?.uppercased() {
      if method == "GET" || method == "HEAD" { return nil }
      guard method == "POST" else { return .unsupportedMethod }
      guard source.interact,
        action.destination.flatMap(origin(of:)).flatMap({ target in
          sites.first { $0.origin == target }
        })?.interact == true
      else { return .interactRequired }
    } else if !source.interact {
      return .interactRequired
    }
    return nil
  }

  /// A navigation WebKit asks about, as the host observed it.
  public struct Navigation: Sendable {
    /// The requested address.
    public let url: URL?
    /// The uppercased HTTP method.
    public let method: String
    /// The origin of the frame that started it; nil for an opaque origin.
    public let sourceOrigin: String?
    /// Whether WebKit reports a form submission.
    public let isForm: Bool
    /// Whether it loads in the main frame.
    public let isMainFrame: Bool
    /// A form the bot's own profile authorized and handed to this separate profile (D136):
    /// it needs the site grant here, not a permit of its own.
    public let handedOff: Bool

    /// Describes one navigation from host-observed facts.
    public init(
      url: URL?, method: String, sourceOrigin: String?, isForm: Bool, isMainFrame: Bool,
      handedOff: Bool = false
    ) {
      self.url = url
      self.method = method
      self.sourceOrigin = sourceOrigin
      self.isForm = isForm
      self.isMainFrame = isMainFrame
      self.handedOff = handedOff
    }
  }

  /// The one-use authority a bot click stages for its form: exactly that destination, method
  /// and source origin, on that main-document commit, for a few seconds. The submission, a new
  /// document or the form's move to another profile (D136) ends it.
  public struct FormPermit: Sendable {
    /// The origin of the frame holding the form.
    public let source: String
    /// The form's action.
    public let destination: URL
    /// The form's method.
    public let method: String
    /// The main-document commit the click saw.
    public let commit: Int
    /// When the permit lapses.
    public let expires: ContinuousClock.Instant
    /// Whether the person confirmed private-data exposure for this form.
    public let exposureConfirmed: Bool

    /// Stages a permit for one clicked form.
    public init(
      source: String, destination: URL, method: String, commit: Int,
      expires: ContinuousClock.Instant, exposureConfirmed: Bool
    ) {
      self.source = source
      self.destination = destination
      self.method = method
      self.commit = commit
      self.expires = expires
      self.exposureConfirmed = exposureConfirmed
    }

    /// Whether it covers `navigation` to `url` on `commit` at `now`: from its source origin,
    /// with its method, to exactly its destination, or for a GET form to its origin and path.
    func covers(
      _ navigation: Navigation, url: URL, commit: Int, now: ContinuousClock.Instant
    ) -> Bool {
      guard self.commit == commit, now < expires, method == navigation.method,
        source == navigation.sourceOrigin
      else { return false }
      if method != "GET" { return destination == url }
      return BrowserAuthorization.origin(of: destination) == BrowserAuthorization.origin(of: url)
        && destination.path == url.path
    }
  }

  /// Why a navigation must be refused, or nil. Every destination needs a grant of its exact
  /// origin (`sites`, empty while no route is configured), except a GET of the app's own lab
  /// page (`appPage`). An ungranted origin is refused before any form logic, and no profile,
  /// the throwaway one (D136) included, loads it: the network boundary refuses it even earlier.
  /// A form or non-GET navigation also needs the click's staged `permit`, unless it was handed
  /// off. In a page holding private data, a frame of another origin waits for exposure
  /// confirmation.
  public static func denial(
    navigation: Navigation, sites: [Site], privateData: Bool, permit: FormPermit?,
    commit: Int, appPage: String?, now: ContinuousClock.Instant = .now
  ) -> Denial? {
    guard let url = navigation.url, let target = origin(of: url) else { return .invalidOrigin }
    if target == appPage, navigation.method == "GET", !navigation.isForm { return nil }
    guard sites.contains(where: { $0.origin == target }) else { return .siteNotGranted }
    if navigation.isForm || navigation.method != "GET", !navigation.handedOff {
      guard let permit, permit.covers(navigation, url: url, commit: commit, now: now) else {
        return .unstagedForm
      }
      let action = Action(
        method: navigation.method, destination: url, label: "", containsPaymentFields: false,
        isForm: true)
      return denial(
        action: action, sourceOrigin: permit.source, sites: sites, privateData: privateData,
        exposureConfirmed: permit.exposureConfirmed)
    }
    // A top-level move to another site opens in a separate profile (D136); a frame cannot, so
    // a page holding private data embeds no other origin.
    if privateData, !navigation.isMainFrame, target != navigation.sourceOrigin {
      return .exposureConfirmationRequired
    }
    return nil
  }

  /// Whether `denial(navigation:…)` can decide `navigation` differently once the page holds
  /// private data: a form or non-GET navigation not handed off (its exposure check), or a frame
  /// of another origin (the frame rule). A page can set cookies after its review was configured,
  /// so a host reads its store before it decides such a navigation while its flag is false.
  public static func dependsOnPrivateData(_ navigation: Navigation) -> Bool {
    if navigation.isForm || navigation.method != "GET" { return !navigation.handedOff }
    guard !navigation.isMainFrame else { return false }
    return navigation.url.flatMap { origin(of: $0) } != navigation.sourceOrigin
  }

  /// Which profile a top-level move opens in (D136).
  public enum ProfileLane: String, Sendable {
    /// The bot's own profile, with its cookies and storage.
    case profile
    /// Inside a separate profile: stay in it (a same-site move there).
    case current
    /// A new separate, empty, non-persistent profile on the same route, discarded when the task
    /// ends.
    case separate
  }

  /// Where a top-level move comes from (D136).
  public enum MoveSource: Equatable, Sendable {
    /// The bot or the person asked for the site: an address, a suite step, or a link the app's
    /// own lab page follows. The profile is used only for a site its cookies belong to.
    case commanded
    /// A move from a page: the origin of the page the profile shows, or of the URL a redirect
    /// leaves. Nil when that origin cannot be read; such a move never shares the profile.
    case page(String?)

    /// Whether a move to `destination` stays within one readable site, so the profile it is
    /// in keeps it without a choice. Never for a commanded open or an unreadable page.
    public func isSameSite(as destination: String) -> Bool {
      guard case .page(let origin) = self else { return false }
      return BrowserAuthorization.isSameSite(origin, destination)
    }
  }

  /// Where a top-level move comes from (D136): the URL a redirect leaves, the page a new-window
  /// link was on (`newWindow`, recorded when it was clicked), otherwise the page the profile
  /// shows (`topDocument`). Never the frame that started the move (`initiator`): an embedded
  /// or opaque-origin frame can make a move neither same-site nor commanded. A link the app's
  /// own lab page follows itself (`appPage` as both page and initiator) counts as commanded.
  public static func moveSource(
    redirecting: URL?, newWindow: MoveSource?, topDocument: URL?, initiator: String?,
    appPage: String?
  ) -> MoveSource {
    if let redirecting { return .page(origin(of: redirecting)) }
    if let newWindow { return newWindow }
    let page = topDocument.flatMap(origin(of:))
    if let appPage, page == appPage, initiator == appPage { return .commanded }
    return .page(page)
  }

  /// A canonical origin's site: its scheme and registrable domain (eTLD+1, from the bundled
  /// Public Suffix List). The port is dropped, as cookies drop it. An IP literal, a single-label
  /// name such as `localhost` and a public suffix itself are their own site. Nil when it cannot
  /// be read: an invalid origin, an empty label, or a DNS name without the list. Only the
  /// profile choice uses sites; grants and content rules stay per exact origin (D101).
  public static func site(
    of origin: String, suffixes: PublicSuffixList? = try? .bundled()
  ) -> String? {
    guard let canonical = canonicalOrigin(origin), let url = URL(string: canonical),
      let scheme = url.scheme, let host = url.host(percentEncoded: false),
      let siteHost = siteHost(of: host, suffixes: suffixes)
    else { return nil }
    return "\(scheme)://\(siteHost.contains(":") ? "[\(siteHost)]" : siteHost)"
  }

  /// Whether two origins are the same site. An origin whose site cannot be read is the same
  /// site as nothing, itself included, so an unreadable side never keeps a move in a profile.
  public static func isSameSite(
    _ first: String?, _ second: String?, suffixes: PublicSuffixList? = try? .bundled()
  ) -> Bool {
    guard let first, let second, let site = site(of: first, suffixes: suffixes) else {
      return false
    }
    return site == self.site(of: second, suffixes: suffixes)
  }

  /// The host part of a site, or nil when it cannot be read (then nothing shares a profile). An
  /// IP address is its own site, with or without the list.
  static func siteHost(
    of host: String, suffixes: PublicSuffixList? = try? .bundled()
  ) -> String? {
    let bare = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    if PublicSuffixList.isIPAddress(bare) { return bare }
    guard let ascii = PublicSuffixList.asciiHost(bare), let suffixes else { return nil }
    return suffixes.registrableDomain(of: ascii) ?? ascii
  }

  /// D136. While the bot's profile holds private data (cookies, a filled sign-in or staged files):
  /// - a site the bot is told to open (`.commanded`) uses the profile only when the profile
  ///   holds a cookie of that site (`holdsCookie`);
  /// - a move in the bot's own profile (`profilePage` nil) stays only within the same site;
  /// - a move in a separate profile (`profilePage` is the origin the bot's own profile shows)
  ///   returns to the profile when it goes back to that site, stays for a same-site move, and
  ///   otherwise opens a new separate profile.
  /// Anything unreadable never shares the profile.
  public static func profileLane(
    destination: String, from source: MoveSource, holdsPrivateData: Bool,
    cookieDomains: [String], shownSites: Set<String> = [], profilePage: String? = nil
  ) -> ProfileLane {
    guard holdsPrivateData else { return .profile }
    guard site(of: destination) != nil else { return .separate }
    guard case .page(let from) = source else {
      return holdsCookie(of: destination, cookieDomains: cookieDomains, shownSites: shownSites)
        ? .profile : .separate
    }
    let sameSite = isSameSite(from, destination)
    guard let profilePage else { return sameSite ? .profile : .separate }
    if isSameSite(profilePage, destination) { return .profile }
    return sameSite ? .current : .separate
  }

  /// Whether the profile holds a cookie of `destination`'s site: its scheme and registrable
  /// domain (D136). WebKit keeps a cookie's domain, not the scheme of the page that set it, so
  /// a cookie of the registrable domain counts for this site only when the profile's own store
  /// has shown pages of this site (`shownSites`) and none of the same domain under the other
  /// scheme. An https page's cookie never goes out over http, nor an http page's to https; a
  /// domain whose pages the profile never showed has cookies of no known site.
  public static func holdsCookie(
    of destination: String, cookieDomains: [String], shownSites: Set<String>
  ) -> Bool {
    guard let target = site(of: destination),
      let host = URL(string: destination)?.host(percentEncoded: false),
      let wanted = siteHost(of: host)
    else { return false }
    let authority = wanted.contains(":") ? "[\(wanted)]" : wanted
    let shown = ["http", "https"].map { "\($0)://\(authority)" }.filter(shownSites.contains)
    return shown == [target]
      && cookieDomains.contains { siteHost(of: String($0.drop { $0 == "." })) == wanted }
  }

  /// A one-use file/form authorization is tied to the precise document and expires quickly.
  public struct DocumentBinding: Equatable, Sendable {
    /// Exact origin of the requesting frame.
    public let origin: String
    /// Isolated-world random document identity, never page text.
    public let documentID: String
    /// Main-document commit counter.
    public let commit: Int
    /// Latest snapshot identity.
    public let snapshotID: Int
    /// Target element reference in that snapshot.
    public let reference: String

    /// Creates a binding from observed native/isolated-world state.
    public init(origin: String, documentID: String, commit: Int, snapshotID: Int, reference: String)
    {
      self.origin = origin
      self.documentID = documentID
      self.commit = commit
      self.snapshotID = snapshotID
      self.reference = reference
    }
  }

  /// Revocable host-only lease. Consumption is fail-closed on navigation, expiry or reuse.
  public struct OneUsePermit: Sendable {
    private let binding: DocumentBinding
    private let expiresAt: Date
    private let issuedAt: Date
    private let expiresInstant: ContinuousClock.Instant
    private var consumed = false

    /// Issues a short, explicit lease; no page-supplied confirmation can create one.
    public init(binding: DocumentBinding, now: Date = Date(), duration: TimeInterval = 30) {
      self.binding = binding
      let lifetime = duration.isFinite ? min(60, max(0, duration)) : 0
      issuedAt = now
      expiresAt = now.addingTimeInterval(lifetime)
      expiresInstant = ContinuousClock.now + .seconds(lifetime)
    }

    /// Invalidates the permit, including when the corresponding grant is removed.
    public mutating func revoke() { consumed = true }

    /// Returns only once and only for the document/element the person approved.
    public mutating func consume(for current: DocumentBinding, now: Date = Date()) throws {
      guard !consumed else { throw Denial.revoked }
      consumed = true
      guard now >= issuedAt, now < expiresAt, ContinuousClock.now < expiresInstant else {
        throw Denial.expired
      }
      guard current == binding else { throw Denial.staleDocument }
    }
  }
}
