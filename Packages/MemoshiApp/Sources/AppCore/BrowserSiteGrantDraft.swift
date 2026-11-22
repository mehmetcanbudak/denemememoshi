/// The sites a person is choosing for a review session before authorizing them. The Mac lab
/// keeps it, so the fields survive the inspector's tab switches; any change to the list
/// withdraws the person's approval of it.
public struct BrowserSiteGrantDraft: Equatable, Sendable {
  /// The origin being entered.
  public var origin = ""
  /// Whether the entered site may run non-consequential POSTs and buttons.
  public var interact = false
  /// Whether a separately approved saved test account may fill credentials there.
  public var signIn = false
  /// Whether the entered site is an owned synthetic or local fixture.
  public var ownedFixture = false
  /// The sites chosen so far, one per exact origin.
  public private(set) var sites: [BrowserAuthorization.Site] = []
  /// The person's approval of exactly `sites` and their listed test effects.
  public var approved = false

  /// An empty draft.
  public init() {}

  /// Adds the entered site, replacing one of the same origin, and withdraws the approval. An
  /// origin that is not exact, or a sign-in grant without HTTPS, throws and changes nothing.
  public mutating func addSite() throws {
    let site = try BrowserAuthorization.Site(
      origin: origin, interact: interact, signIn: signIn, ownedFixture: ownedFixture)
    sites.removeAll { $0.origin == site.origin }
    sites.append(site)
    approved = false
  }

  /// Removes the site of `origin` and withdraws the approval.
  public mutating func removeSite(origin: String) {
    sites.removeAll { $0.origin == origin }
    approved = false
  }
}
