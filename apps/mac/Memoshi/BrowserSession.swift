import AppCore
import AppKit
import DesignSystem
import Foundation
import WebKit

/// One review profile's persistent WebKit view, shared isolated automation world and native input.
/// Explicit review grants/gateway/accounts live in `review`; normal bot tools remain disconnected.
@MainActor
@Observable
final class BrowserSession {
  struct TakeoverStart: Sendable {
    let date: Date
    let commit: Int
    let host: String?
  }

  /// The change summary shown after Hand Back. Nothing about the person's session is recorded.
  struct HandBackSummary: Sendable {
    let duration: TimeInterval
    let navigations: Int
    let hostBefore: String?
    let hostAfter: String?
  }

  /// The viewport a page uses before it is first shown: the minimum window content size.
  static let initialViewport = CGSize(
    width: DS.Layout.Window.minWidth, height: DS.Layout.Window.minHeight)

  let profile: BrowserReviewProfile
  let scheduling: BrowserSchedulingPolicy
  @ObservationIgnored let webView: WKWebView
  let review: BrowserSessionReview

  private(set) var pageURL: URL?
  private(set) var pageTitle = ""
  private(set) var isLoading = false
  private(set) var progress = 0.0
  private(set) var canGoBack = false
  private(set) var canGoForward = false
  private(set) var navigation = BrowserNavigationState.idle
  private(set) var snapshot: BrowserPageSnapshot?
  private(set) var snapshotProblem: BrowserActionError?
  private(set) var isSnapshotting = false
  private(set) var isPerforming = false
  private(set) var lastOutcome: BrowserActionOutcome?
  private(set) var control = BrowserControl.watching
  private(set) var takeoverStart: TakeoverStart?
  private(set) var lastHandBack: HandBackSummary?
  private(set) var placement: BrowserPlacement
  private(set) var commitCount = 0
  private(set) var registeredFrameCount = 0
  private(set) var isClosed = false
  /// The latest `takeSnapshot` image, kept in memory only and never written or exported.
  private(set) var lastImage: NSImage?
  private(set) var lastImageAt: Date?
  /// The development sign-in Card on offer, if any. It holds refs and a binding, no credential.
  private(set) var signInCard: BrowserSignInCard?
  private(set) var lastSignIn: BrowserSignInOutcome?
  private(set) var signInProblem: BrowserActionError?
  /// What this web view has actually installed. Every load is refused until the boundary its
  /// route needs (gateway, deny-local list, route list, Lockdown) is complete.
  private(set) var boundary = BrowserNetworkBoundary.State()
  private(set) var boundaryProblem: BrowserNetworkBoundary.Denial?

  @ObservationIgnored weak var liveContainer: BrowserLiveContainerView?
  @ObservationIgnored private weak var lab: BrowserReviewLab?
  @ObservationIgnored private let contentController: WKUserContentController
  @ObservationIgnored private let delegate: BrowserSessionDelegate
  @ObservationIgnored private var observations: [NSKeyValueObservation] = []
  @ObservationIgnored private var subframes: [RegisteredFrame] = []
  @ObservationIgnored private var pendingNavigations: [ObjectIdentifier: PendingNavigation] = [:]
  @ObservationIgnored private var navigationWaiters: [ObjectIdentifier: BrowserResumeGate<Bool>] =
    [:]
  @ObservationIgnored private var knownDocument: KnownDocument?
  @ObservationIgnored private var nextSnapshotID = 0
  @ObservationIgnored private var pendingHTTPStatus: Int?
  @ObservationIgnored private var actionTask: Task<Void, Never>?
  @ObservationIgnored private var snapshotTask: Task<Void, Never>?
  @ObservationIgnored private var signInTask: Task<Void, Never>?
  @ObservationIgnored private var denyLocalTask: Task<Void, Never>?
  @ObservationIgnored private var denyLocalList: WKContentRuleList?
  @ObservationIgnored private var routeList: WKContentRuleList?
  @ObservationIgnored private var blockAllList: WKContentRuleList?
  /// D136: the separate, non-persistent profile this session opened for another site, if any.
  /// Only the bot's own session opens one; the bot works in `lane`.
  private(set) var separate: BrowserSession?
  /// For a separate profile: the bot's own session that opened it.
  @ObservationIgnored private(set) weak var owner: BrowserSession?
  /// Whether this session's store is a separate, non-persistent profile (D136).
  let isSeparateProfile: Bool
  /// The bot's own session's profile changes (D136), in order. A separate profile queues none.
  @ObservationIgnored private let lanes = BrowserLaneSequencer()
  /// A load whose profile its caller already chose (a load the bot or person asked for, a
  /// return, or a separate profile's first load); the policy check allows it as it is.
  @ObservationIgnored private var commandedRequest: URLRequest?
  /// A new-window link reloaded in place, with where its move comes from.
  @ObservationIgnored private var inPlaceSource: (url: URL, from: BrowserAuthorization.MoveSource)?
  /// The main frame's committed document: the page a move from this profile leaves (D136).
  @ObservationIgnored private var mainDocumentURL: URL?
  /// The main-frame URL allowed and not yet committed; a decision while it is set is a redirect.
  @ObservationIgnored private var provisionalMainURL: URL?
  /// How far this view's top-level navigations got: asked for, answered and started.
  @ObservationIgnored private var mainNavigations = BrowserNavigationProgress()

  private struct RegisteredFrame {
    let docID: String
    let info: WKFrameInfo
  }

  private struct PendingNavigation {
    let start: ContinuousClock.Instant
    let host: String?
  }

  private struct KnownDocument {
    let docID: String
    let commit: Int
  }

  private struct ActionResult {
    var observed: [BrowserObservedEvent] = []
    var verified: Bool?
    var scrolled: Double?
  }

  /// Creates the profile's web view with Lockdown set before creation and starts installing
  /// the fixed deny-local list. Nothing loads until the person navigates, and no load is
  /// admitted before the installed boundary is complete. With an `owner`, the view is that
  /// session's separate profile (D136): a non-persistent store, never the profile's own.
  init(
    profile: BrowserReviewProfile, scheduling: BrowserSchedulingPolicy,
    placement: BrowserPlacement, lab: BrowserReviewLab, owner: BrowserSession? = nil
  ) {
    let world = BrowserAutomationScript.world
    let controller = WKUserContentController()
    controller.addUserScript(
      WKUserScript(
        source: BrowserAutomationScript.library, injectionTime: .atDocumentStart,
        forMainFrameOnly: false, in: world))
    let preferences = WKPreferences()
    preferences.inactiveSchedulingPolicy = scheduling.webKitValue
    preferences.javaScriptCanOpenWindowsAutomatically = false
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore =
      owner == nil ? WKWebsiteDataStore(forIdentifier: profile.id) : .nonPersistent()
    configuration.userContentController = controller
    configuration.preferences = preferences
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    BrowserNetworkBoundary.applyLockdown(to: configuration)
    let delegate = BrowserSessionDelegate()
    self.profile = profile
    self.scheduling = scheduling
    self.placement = placement
    self.isSeparateProfile = owner != nil
    self.owner = owner
    self.lab = lab
    self.contentController = controller
    self.delegate = delegate
    self.review = BrowserSessionReview(evidence: lab.evidence, startGateway: lab.startGateway)
    self.webView = WKWebView(
      frame: CGRect(origin: .zero, size: BrowserSession.initialViewport),
      configuration: configuration)
    boundary.lockdown = BrowserNetworkBoundary.lockdownIsActive(on: webView)
    review.session = self
    if owner == nil {
      review.loadSavedLogin()
      review.loadShownSites()
    }
    delegate.session = self
    controller.add(delegate, contentWorld: world, name: BrowserAutomationScript.frameMessageName)
    webView.navigationDelegate = delegate
    webView.uiDelegate = delegate
    webView.allowsBackForwardNavigationGestures = true
    observeWebView()
    denyLocalTask = Task { [weak self] in await self?.installDenyLocal() }
    Self.liveProfiles.insert(profile.id)
  }

  /// Profiles with a session in this process. A startup sweep keeps their compiled lists.
  private(set) static var liveProfiles: Set<UUID> = []

  var pageHost: String? { pageURL?.host() }
  /// The session the bot works in now: the separate profile while one is open (D136).
  var lane: BrowserSession { separate ?? self }
  /// The bot's own session; a separate profile's owner.
  var root: BrowserSession { owner ?? self }
  var isShowingLabPage: Bool { pageHost == BrowserAutomationScript.labPageHost }
  var snapshotIsCurrent: Bool { snapshot.map { $0.commit == commitCount } ?? false }

  /// Whether the web view is in a window, and whether that window is on screen and unoccluded.
  var hostState: (inWindow: Bool, windowVisible: Bool) {
    guard let window = webView.window else { return (inWindow: false, windowVisible: false) }
    let visible = window.isVisible && window.occlusionState.contains(.visible)
    return (inWindow: true, windowVisible: visible)
  }

  // MARK: Navigation

  /// Loads an http or https address with GET. Invalid input changes nothing and is returned;
  /// so is a refusal by the network boundary (one not yet in place, or an address outside its
  /// route), which fails closed without starting a load. The bot's own session chooses the
  /// profile (D136); a separate profile hands the request to it.
  func navigate(to input: String) -> BrowserAddress.Problem? {
    if let owner { return owner.navigate(to: input) }
    switch BrowserAddress.resolve(input) {
    case .failure(let problem):
      return problem
    case .success(let url):
      guard !isClosed else { return nil }
      if let denial = refusal(url) {
        return denial.isIncompleteBoundary ? .networkBoundary : .outsideRoute
      }
      Task { try? await self.openCommanded(url) }
      return nil
    }
  }

  /// Loads the offline lab page from the app; no network request is made for it. It still
  /// needs Lockdown and an installed block list, because its page can start loads. It always
  /// opens in the bot's own profile, so a separate profile closes first.
  func loadLabPage() {
    if let owner { return owner.loadLabPage() }
    guard !isClosed, let url = BrowserAutomationScript.labPageURL, admits(url) else { return }
    closeSeparate()
    webView.loadHTMLString(BrowserAutomationScript.labPageHTML, baseURL: url)
  }

  func goBack() {
    guard webView.canGoBack, admits(webView.backForwardList.backItem?.url) else { return }
    webView.goBack()
  }

  func goForward() {
    guard webView.canGoForward, admits(webView.backForwardList.forwardItem?.url) else { return }
    webView.goForward()
  }

  /// Reloads the page. The lab page is reloaded from the app, because its host never resolves.
  func reload() {
    if isShowingLabPage {
      loadLabPage()
    } else if admits(webView.url) {
      webView.reload()
    }
  }

  func stopLoading() {
    webView.stopLoading()
  }

  // MARK: Network boundary

  /// Why loading `url` must be refused now. The app-supplied lab document needs only Lockdown
  /// and a block list; every http(s) load needs its route's complete boundary.
  func boundaryDenial(for url: URL?) -> BrowserNetworkBoundary.Denial? {
    if let url, url.host() == BrowserAutomationScript.labPageHost,
      BrowserAuthorization.origin(of: url)
        == BrowserAutomationScript.labPageURL.flatMap(BrowserAuthorization.origin(of:))
    {
      return boundary.offlineDocumentDenial
    }
    return boundary.denial(loading: url)
  }

  /// Records and refuses a load the boundary does not admit. A closed view admits nothing: its
  /// policy delegate and content rule lists are gone.
  private func admits(_ url: URL?, mainFrame: Bool = true) -> Bool {
    !isClosed && refusal(url, mainFrame: mainFrame) == nil
  }

  /// Records and returns why the boundary refuses loading `url` now, or nil. The refusal says
  /// whether the boundary is not complete or refused an address outside its route.
  private func refusal(_ url: URL?, mainFrame: Bool = true) -> BrowserNetworkBoundary.Denial? {
    guard let denial = boundaryDenial(for: url) else { return nil }
    review.record(.navigation, false, "networkBoundary." + denial.rawValue)
    _ = block(
      denial.isIncompleteBoundary ? .networkBoundary : .outsideRoute, detail: denial.rawValue,
      mainFrame: mainFrame, host: url?.host())
    return denial
  }

  private func installDenyLocal() async {
    do {
      let store = try BrowserContentRuleStore.appContainer()
      let list = try await store.denyLocal()
      // Compiled up front: clearing a route installs it with no suspension point.
      let blockAll = try await store.compile(
        identifier: BrowserNetworkBoundary.blockAllIdentifier(profile: profile.id),
        json: BrowserNetworkBoundary.allowlistJSON(origins: []))
      guard !isClosed else { return }
      denyLocalList = list
      blockAllList = blockAll
      if boundary.route?.kind != .ownedFixture {
        contentController.add(list)
        boundary.denyLocal = list.identifier
      }
    } catch {
      boundaryProblem = .compileFailed
    }
  }

  /// Waits for the fixed deny-local list. Route changes need it before they start.
  func awaitDenyLocal() async throws(BrowserNetworkBoundary.Denial) {
    await denyLocalTask?.value
    guard !isClosed, denyLocalList != nil else { throw .denyLocalMissing }
  }

  /// Installs a compiled route list with no suspension point, so no load can start between
  /// the steps. The gateway route keeps deny-local ahead of its allowlist. The owned-fixture
  /// route replaces deny-local with its block-all list, which exempts only exact fixture
  /// origins and so blocks every other loopback target too.
  func installRoute(
    _ list: WKContentRuleList, kind: BrowserNetworkBoundary.RouteKind, origins: [String],
    gatewayApplied: Bool
  ) throws(BrowserNetworkBoundary.Denial) {
    guard !isClosed, let denyLocalList else { throw .denyLocalMissing }
    clearRoute()
    contentController.add(list)
    routeList = list
    if let blockAllList, boundary.blockAll != nil {
      contentController.remove(blockAllList)
      boundary.blockAll = nil
    }
    if kind == .ownedFixture {
      contentController.remove(denyLocalList)
      boundary.denyLocal = nil
    }
    boundary.route = .init(identifier: list.identifier, kind: kind, origins: origins)
    boundary.gatewayApplied = gatewayApplied
  }

  /// Removes the route list and gateway mark, restoring deny-local first, so loads fail
  /// closed and at least one block list stays installed throughout. A document that outlives
  /// its route gets the block-all list until the next route: deny-local alone would let its
  /// subresource and fetch loads reach public hosts directly.
  func clearRoute() {
    if let denyLocalList, boundary.denyLocal == nil, !isClosed {
      contentController.add(denyLocalList)
      boundary.denyLocal = denyLocalList.identifier
    }
    if let routeList {
      if let blockAllList, boundary.blockAll == nil, !isClosed {
        contentController.add(blockAllList)
        boundary.blockAll = blockAllList.identifier
      }
      contentController.remove(routeList)
    }
    routeList = nil
    boundary.route = nil
    boundary.gatewayApplied = false
  }

  // MARK: Snapshots

  /// Starts a bounded snapshot of visible elements in the main frame and registered frames.
  /// The session owns the work, so closing it cancels the snapshot.
  func startSnapshot(mode: BrowserSnapshotMode) {
    guard snapshotTask == nil, !isClosed else { return }
    snapshotTask = Task {
      await self.takeSnapshot(mode: mode)
      self.snapshotTask = nil
    }
  }

  private func takeSnapshot(mode: BrowserSnapshotMode) async {
    guard !isClosed, !isSnapshotting else { return }
    isSnapshotting = true
    defer { isSnapshotting = false }
    do {
      let captured = try await captureSnapshot(mode: mode, maxElements: 150)
      snapshot = captured
      snapshotProblem = nil
      lab?.recordSnapshot(captured, from: self)
    } catch {
      let problem = BrowserActionError(error)
      snapshotProblem = problem
      lab?.record(.snapshotFailed(problem), session: self)
    }
  }

  /// Captures a real runner snapshot with the same ref invalidation and evidence as UI work.
  func snapshotForSuite() async throws -> BrowserPageSnapshot {
    guard !isClosed, !isSnapshotting, !isPerforming else { throw BrowserActionError.busy }
    let captured = try await captureSnapshot(mode: .full, maxElements: 150)
    snapshot = captured
    snapshotProblem = nil
    lab?.recordSnapshot(captured, from: self, source: .taskSuite)
    return captured
  }

  /// Waits for the actual WebKit navigation; policy rejection never counts as success. The bot's
  /// own session chooses the profile (D136); a separate profile hands the request to it.
  func navigateForSuite(_ url: URL) async throws {
    if let owner { return try await owner.navigateForSuite(url) }
    guard !isClosed, control == .watching else { throw BrowserActionError.userInControl }
    guard admits(url) else { throw BrowserActionError.navigationNotStarted }
    try await openCommanded(url)
  }

  /// Loads `request` in this session's own profile and waits for the WebKit navigation. The
  /// caller already chose this profile, so the policy check allows the load itself; its
  /// redirects are judged again. Immediately before the load, with no suspension in between,
  /// the profile change's `turn` (when a change asked), the task's cancellation, the view and
  /// its boundary are checked again: nothing loads after the work was stopped or the view
  /// closed. Returns false when the load was cancelled because it moved to another profile
  /// (D136).
  private func loadInProfile(
    _ request: URLRequest, turn: BrowserLaneSequencer.Turn? = nil
  ) async throws -> Bool {
    let moves = root.lanes.moves
    let gate = BrowserResumeGate<Bool>()
    var waiter: ObjectIdentifier?
    // A load that timed out or was cancelled leaves no waiter behind.
    defer { if let waiter { navigationWaiters[waiter] = nil } }
    do {
      _ = try await gate.value(
        timeout: .seconds(30), timeoutError: BrowserActionError.navigationFailed
      ) {
        do { try turn?.check() } catch { return gate.resume(.failure(error)) }
        guard admits(request.url) else {
          return gate.resume(.failure(BrowserActionError.navigationNotStarted))
        }
        commandedRequest = request
        provisionalMainURL = nil
        guard let navigation = webView.load(request) else {
          return gate.resume(.failure(BrowserActionError.navigationNotStarted))
        }
        waiter = ObjectIdentifier(navigation)
        navigationWaiters[ObjectIdentifier(navigation)] = gate
      }
      return true
    } catch {
      // A redirect to another site cancels this load and opens there in another profile.
      guard root.lanes.moves != moves, !(error is CancellationError) else { throw error }
      return false
    }
  }

  // MARK: Separate profile (D136)

  /// A load the bot or person asked for: it opens in this profile when the profile holds no
  /// private data or holds a cookie of the site, otherwise in a separate profile.
  private func openCommanded(_ url: URL) async throws {
    let cookies = (try? await review.storedCookies()) ?? .unreadable
    try Task.checkCancellation()
    guard !isClosed else { throw BrowserActionError.sessionClosed }
    guard let destination = BrowserAuthorization.origin(of: url) else {
      throw BrowserAuthorization.Denial.invalidOrigin
    }
    let lane = BrowserAuthorization.profileLane(
      destination: destination, from: .commanded,
      holdsPrivateData: review.privateData || cookies.holdsPrivate,
      cookieDomains: cookies.domains, shownSites: review.shownSites)
    if lane == .separate, destination != Self.labOrigin {
      moveToSeparate(URLRequest(url: url))
      try await settleLanes()
      return
    }
    closeSeparate()
    let loaded = try await loadInProfile(URLRequest(url: url))
    if !loaded { try await settleLanes() }
  }

  private static let labOrigin = BrowserAutomationScript.labPageURL.flatMap(
    BrowserAuthorization.origin(of:))

  /// Records the move and hands `request` to the bot's own session to open separately.
  private func moveToSeparate(_ request: URLRequest) {
    review.record(.navigation, true, "separateProfile")
    lab?.record(.openedInSeparateProfile(host: request.url?.host()), session: self)
    root.changeLane { root, turn in try await root.replaceSeparate(loading: request, turn: turn) }
  }

  /// From a separate profile, back to the site the bot's own profile shows: the separate
  /// profile is discarded and the bot's own profile arrives at `url` as a browser's cross-site
  /// top-level navigation from `origin` would, carrying only the URL.
  private func returnToProfile(_ url: URL, from origin: URL) {
    review.record(.navigation, true, "separateProfileReturn")
    root.changeLane { root, turn in
      await root.dropSeparate()?.value
      try await root.arriveCrossSite(at: url, from: origin, turn: turn)
    }
  }

  /// Shows an empty document with `origin` as its address and lets its script navigate to `url`,
  /// so WebKit itself treats the load as a cross-site navigation from that origin: SameSite=Strict
  /// cookies withheld, Lax ones sent, cross-site fetch metadata and at most that origin as
  /// Referer. Never a browser-initiated load of a URL a page chose. Waits for the arrival; the
  /// sequencer checks `turn` right before the load and disarms the return on every exit. A stop
  /// (a cancelled task, a closed separate profile, changed grants) or a failed arrival stops the
  /// load at once, so the stopped return neither commits nor navigates afterwards (review F3).
  private func arriveCrossSite(
    at url: URL, from origin: URL, turn: BrowserLaneSequencer.Turn
  ) async throws {
    guard let target = try? JSONEncoder().encode(url.absoluteString),
      let literal = String(data: target, encoding: .utf8)
    else { throw BrowserAuthorization.Denial.invalidOrigin }
    let commits = commitCount
    try await lanes.arrive(
      BrowserLaneSequencer.Return(base: origin, target: url), turn: turn,
      timeout: .seconds(30), timeoutError: BrowserActionError.navigationFailed
    ) {
      guard !isClosed else { throw BrowserActionError.sessionClosed }
      commandedRequest = nil
      provisionalMainURL = nil
      webView.loadHTMLString(
        "<!doctype html><meta charset=\"utf-8\"><script>location.replace(\(literal))</script>",
        baseURL: origin)
    } stop: { [weak self] in
      self?.webView.stopLoading()
    } arrived: {
      guard !isClosed else { throw BrowserActionError.sessionClosed }
      // Once the empty document committed and nothing loads, a failed or refused target
      // navigation ends the return at once.
      if !webView.isLoading, commitCount > commits {
        if case .failed = navigation { throw BrowserActionError.navigationFailed }
        if case .blocked = navigation { throw BrowserActionError.navigationFailed }
      }
      // Arrived: the empty document and the target both committed and nothing is loading.
      return lanes.pendingReturn == nil && !webView.isLoading && commitCount >= commits + 2
    }
  }

  private typealias LaneChange =
    @MainActor (BrowserSession, BrowserLaneSequencer.Turn) async throws -> Void

  /// Queues one profile change on the bot's own session after the earlier ones, so openings
  /// and returns happen in order; `settleLanes` waits for them. A failed change is recorded.
  private func changeLane(_ change: @escaping LaneChange) {
    guard owner == nil, !isClosed else { return }
    lanes.enqueue { [weak self] turn in
      guard let self else { throw CancellationError() }
      do {
        try await change(self, turn)
      } catch {
        // A stopped change ended with the task, the session or the grants: nothing to report.
        if !(error is CancellationError), turn.isCurrent {
          self.review.record(
            .navigation, false, "separateProfile." + BrowserSessionReview.code(error))
        }
        throw error
      }
    }
  }

  /// Creates the new profile with the same sites and route as this session (the same gateway
  /// route, deny-local rules and Lockdown, built by the same code), shows it where this
  /// session's page is shown, discards the previous one and loads `request`. After every
  /// suspension `turn` is checked again: a change stopped meanwhile (a closed separate
  /// profile, an ended task, changed grants, a closed session) shows and loads nothing.
  private func replaceSeparate(
    loading request: URLRequest, turn: BrowserLaneSequencer.Turn
  ) async throws {
    let sites = review.sites
    let route = review.route
    guard !isClosed, route != .offline, let lab else {
      throw BrowserAuthorization.Denial.siteNotGranted
    }
    let next = BrowserSession(
      profile: BrowserReviewProfile(id: UUID(), name: profile.name, createdAt: Date(), probe: nil),
      scheduling: scheduling, placement: placement, lab: lab, owner: self)
    do {
      try await next.review.configureSeparate(from: review)
      try turn.check()
      guard review.sites == sites, review.route == route else {
        throw BrowserAuthorization.Denial.staleDocument
      }
    } catch {
      next.close()
      await next.removeStoredData()
      throw error
    }
    next.review.record(.configuration, true, "separateProfile")
    let previous = separate
    separate = next
    host(next.webView, replacing: (previous ?? self).webView)
    if let previous {
      previous.close()
      await previous.removeStoredData()
    }
    // A stop while the previous profile's data was removed already closed `next`.
    try turn.check()
    _ = try await next.loadInProfile(request, turn: turn)
  }

  /// Stops every profile change queued or under way, a return included, at once; the separate
  /// profile stays shown until `discardSeparate` removes it. A cancelled task ends here (D136).
  func stopProfileChanges() { root.lanes.supersede() }

  /// Closes the separate profile now, stops every profile change queued or under way and shows
  /// this session's page again. Returns the removal of the closed profile's data.
  @discardableResult
  func closeSeparate() -> Task<Void, Never>? {
    lanes.supersede()
    return dropSeparate()
  }

  /// Closes the separate profile and shows this session's page again, leaving queued profile
  /// changes running. Returns the removal of the closed profile's data.
  private func dropSeparate() -> Task<Void, Never>? {
    guard let lane = separate else { return nil }
    separate = nil
    host(webView, replacing: lane.webView)
    lane.close()
    review.record(.navigation, true, "separateProfileDiscarded")
    return Task { await lane.removeStoredData() }
  }

  /// The task ended (D136): every profile change stops, the open separate profile closes and
  /// its data is removed before this returns.
  func discardSeparate() async {
    if let owner { return await owner.discardSeparate() }
    await closeSeparate()?.value
    await lanes.drain()
    // A change the bot's own page queued while the stopped ones wound down.
    await closeSeparate()?.value
    lanes.clearFailure()
  }

  /// Waits until every pending profile decision and profile change has settled, and rethrows
  /// a failed change.
  func settleLanes() async throws {
    try await root.lanes.settle(
      timeout: .seconds(90), timeoutError: BrowserActionError.navigationFailed)
  }

  /// Puts `next` where `current` is shown: the live container, a parking window or a plain view.
  private func host(_ next: WKWebView, replacing current: WKWebView) {
    guard next !== current else { return }
    if let container = liveContainer, current.superview === container {
      container.host(next)
    } else if let window = current.window, window.contentView === current {
      window.contentView = next
      return
    } else if let superview = current.superview {
      next.autoresizingMask = current.autoresizingMask
      next.frame = current.frame
      superview.addSubview(next, positioned: .above, relativeTo: current)
    }
    current.removeFromSuperview()
  }

  /// A separate profile's discard: its store's data and its compiled rule lists are removed.
  /// Its store was never persistent, so nothing of it was written to disk.
  private func removeStoredData() async {
    guard isSeparateProfile else { return }
    await webView.configuration.websiteDataStore.removeData(
      ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    guard let rules = try? BrowserContentRuleStore.appContainer() else { return }
    rules.remove(identifier: BrowserNetworkBoundary.routeListIdentifier(profile: profile.id))
    rules.remove(identifier: BrowserNetworkBoundary.blockAllIdentifier(profile: profile.id))
  }

  /// Executes one action once; uncertainty is reported, never retried by the suite runner.
  func performForSuite(_ request: BrowserActionRequest) async throws -> BrowserActionOutcome {
    guard actionTask == nil, signInTask == nil, !isPerforming, !review.isFilling else {
      throw BrowserActionError.busy
    }
    let previous = lastOutcome?.id
    await perform(request)
    guard let outcome = lastOutcome, outcome.id != previous else { throw BrowserActionError.busy }
    return outcome
  }

  /// A full snapshot pass used only for timing; it keeps the person's current refs valid.
  func measureSnapshot() async throws -> (ms: Double, elements: Int) {
    let started = ContinuousClock.now
    let input: [String: Any] = [
      "snapshotId": 0, "maxElements": 150, "mode": BrowserSnapshotMode.interactive.rawValue,
      "measureOnly": true,
    ]
    let payload: BrowserFramePayload = try await call(
      "snapshot", input, in: nil, timeout: .seconds(5))
    return (ms: BrowserClock.milliseconds(since: started), elements: payload.elements.count)
  }

  /// Takes a `takeSnapshot` image and returns its duration. The image stays in memory only.
  func captureImage(width: Double) async throws -> Double {
    guard !isClosed else { throw BrowserActionError.sessionClosed }
    let configuration = WKSnapshotConfiguration()
    configuration.snapshotWidth = NSNumber(value: width)
    let started = ContinuousClock.now
    let gate = BrowserResumeGate<Bool>()
    _ = try await gate.value(
      timeout: .seconds(10), timeoutError: BrowserActionError.imageSnapshotFailed
    ) {
      webView.takeSnapshot(with: configuration) { [weak self] image, _ in
        guard let image else {
          gate.resume(.failure(BrowserActionError.imageSnapshotFailed))
          return
        }
        self?.lastImage = image
        self?.lastImageAt = Date()
        gate.resume(.success(true))
      }
    }
    return BrowserClock.milliseconds(since: started)
  }

  private func captureSnapshot(mode: BrowserSnapshotMode, maxElements: Int) async throws
    -> BrowserPageSnapshot
  {
    nextSnapshotID += 1
    let id = nextSnapshotID
    let commit = commitCount
    let started = ContinuousClock.now
    let main: BrowserFramePayload = try await call(
      "snapshot", ["snapshotId": id, "maxElements": maxElements, "mode": mode.rawValue], in: nil)
    var elements = main.elements
    var frames = [
      BrowserPageSnapshot.Frame(
        index: 0, docID: main.docId, origin: String(localized: "Main frame"),
        elementCount: main.elements.count, total: main.total, truncated: main.truncated)
    ]
    var skipped = 0
    for registered in subframes {
      let remaining = maxElements - elements.count
      guard remaining > 0 else {
        skipped += 1
        continue
      }
      do {
        let input: [String: Any] = [
          "snapshotId": id, "maxElements": min(50, remaining), "mode": mode.rawValue,
        ]
        let payload: BrowserFramePayload = try await call("snapshot", input, in: registered.info)
        guard payload.docId == registered.docID else {
          subframes.removeAll { $0.docID == registered.docID }
          registeredFrameCount = subframes.count
          skipped += 1
          continue
        }
        let index = frames.count
        frames.append(
          BrowserPageSnapshot.Frame(
            index: index, docID: payload.docId,
            origin: BrowserSession.originLabel(registered.info.securityOrigin),
            elementCount: payload.elements.count, total: payload.total,
            truncated: payload.truncated))
        for element in payload.elements {
          var element = element
          element.frame = index
          elements.append(element)
        }
      } catch {
        skipped += 1
        if BrowserActionError(error) == .frameUnavailable {
          subframes.removeAll { $0.docID == registered.docID }
          registeredFrameCount = subframes.count
        }
      }
    }
    guard commitCount == commit else { throw BrowserActionError.staleSnapshot }
    knownDocument = KnownDocument(docID: main.docId, commit: commit)
    return BrowserPageSnapshot(
      id: id, capturedAt: Date(), durationMs: BrowserClock.milliseconds(since: started),
      commit: commit, mode: mode, pageURL: main.url, title: main.title, frames: frames,
      elements: elements, skippedFrames: skipped)
  }

  private static func originLabel(_ origin: WKSecurityOrigin) -> String {
    BrowserAuthorization.origin(of: origin) ?? String(localized: "Opaque-origin frame")
  }

  // MARK: Actions

  /// Starts one validated action; its typed outcome is recorded when it ends. The session owns
  /// the work, so closing it cancels the action. Typed text is never recorded.
  func start(_ request: BrowserActionRequest) {
    guard actionTask == nil, signInTask == nil, !isClosed, !review.isFilling else { return }
    actionTask = Task {
      await self.perform(request)
      self.actionTask = nil
    }
  }

  private func perform(_ request: BrowserActionRequest) async {
    guard !isPerforming else { return }
    isPerforming = true
    defer { isPerforming = false }
    let started = ContinuousClock.now
    let startDate = Date()
    let host = hostState
    let placementAtStart = placement
    let navigationsBefore = mainNavigations.started
    var result = ActionResult()
    var failure: BrowserActionError?
    do {
      result = try await run(request)
    } catch {
      failure = BrowserActionError(error)
    }
    if request.path == .native { root.restoreShield() }
    let outcome = BrowserActionOutcome(
      id: UUID(), profileName: profile.name, kind: request.kind, path: request.path,
      frame: request.reference?.frame, placement: placementAtStart, inWindow: host.inWindow,
      windowVisible: host.windowVisible, pageHost: pageHost, startedAt: startDate,
      durationMs: BrowserClock.milliseconds(since: started), error: failure,
      verified: result.verified, textLength: request.textLength,
      scrolledPoints: result.scrolled,
      navigationStarted: mainNavigations.started > navigationsBefore,
      observed: result.observed)
    lastOutcome = outcome
    lab?.recordOutcome(outcome)
  }

  /// Every input action refuses credential fields, checked against the snapshot and again in the
  /// live page before any input; scrolling one into view stays allowed.
  private func run(_ request: BrowserActionRequest) async throws -> ActionResult {
    guard !isClosed else { throw BrowserActionError.sessionClosed }
    // A person who took over the bot's session holds its separate profile too (D136).
    guard root.control == .watching else { throw BrowserActionError.userInControl }
    guard !review.evidence.storageProblem else { throw BrowserActionError.evidenceUnavailable }
    switch request {
    case .scroll(let direction, let points):
      guard (1...5_000).contains(points) else { throw BrowserActionError.invalidAmount }
      let offset = direction.offset(points: points)
      let payload: BrowserScrollPayload = try await call(
        "scrollBy", ["dx": offset.dx, "dy": offset.dy], in: nil)
      return ActionResult(verified: payload.moved > 0, scrolled: payload.moved)
    case .scrollTo(let ref):
      let (frame, _) = try resolve(ref)
      let payload: BrowserScrollPayload = try await call("scrollTo", input(for: ref), in: frame)
      return ActionResult(scrolled: payload.moved)
    case .click(let ref, let path):
      let (frame, element) = try resolve(ref)
      guard !element.sensitive else { throw BrowserActionError.credentialField }
      let info = try await review.authorizeClick(ref)
      let navigations = mainNavigations
      let result =
        path == .native
        ? try await nativeClick(ref, element: element)
        : try await scriptClick(ref, frame: frame)
      if info.link || info.method != nil { await awaitNavigation(since: navigations) }
      return result
    case .type(let ref, let text, let replace, let path):
      try validate(text)
      let (frame, element) = try resolve(ref)
      guard element.editable else { throw BrowserActionError.notEditable }
      guard !element.sensitive else { throw BrowserActionError.credentialField }
      if path == .native {
        return try await nativeType(ref, text: text, replace: replace)
      }
      return try await scriptType(ref, text: text, replace: replace, frame: frame)
    case .select(let ref, let index, let label):
      let (frame, element) = try resolve(ref)
      guard element.selectable else { throw BrowserActionError.notSelectable }
      guard !element.sensitive else { throw BrowserActionError.credentialField }
      return try await scriptSelect(ref, index: index, label: label, frame: frame)
    }
  }

  /// WebKit asks for a clicked link's or form's navigation after the click returns, and starts a
  /// navigation it allowed after that. This waits, at most a second, until it has asked and
  /// answered, and at most two more until a navigation it allowed has started. A move to a
  /// separate profile (D136), decided now or at a redirect of the allowed load, is then pending
  /// or loading when the action reports, so `settleLanes` and the suite runner's loading wait see
  /// it and a refused opening reaches the step (D136 review F5).
  private func awaitNavigation(since mark: BrowserNavigationProgress) async {
    let decided = ContinuousClock.now + .seconds(1)
    let started = decided + .seconds(2)
    while !isClosed {
      switch mainNavigations.wait(since: mark) {
      case .none: return
      case .decision: guard ContinuousClock.now < decided else { return }
      case .start: guard ContinuousClock.now < started else { return }
      }
      // A cancelled action stops waiting: a sleep that throws at once would spin the main actor.
      guard (try? await Task.sleep(for: .milliseconds(20))) != nil else { return }
    }
  }

  func resolve(_ ref: BrowserElementRef) throws -> (WKFrameInfo?, BrowserElement) {
    guard let snapshot else { throw BrowserActionError.noSnapshot }
    guard snapshot.commit == commitCount, ref.snapshotID == snapshot.id else {
      throw BrowserActionError.staleSnapshot
    }
    guard let element = snapshot.element(for: ref) else { throw BrowserActionError.unknownRef }
    guard ref.frame > 0 else { return (nil, element) }
    guard ref.frame < snapshot.frames.count else { throw BrowserActionError.frameUnavailable }
    let docID = snapshot.frames[ref.frame].docID
    guard let registered = subframes.first(where: { $0.docID == docID }) else {
      throw BrowserActionError.frameUnavailable
    }
    return (registered.info, element)
  }

  func input(for ref: BrowserElementRef) -> [String: Any] {
    ["snapshotId": ref.snapshotID, "ref": ref.ref]
  }

  private func validate(_ text: String) throws {
    guard !text.isEmpty else { throw BrowserActionError.emptyText }
    guard text.count <= 500 else { throw BrowserActionError.textTooLong }
    let hasControl = text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    guard !hasControl else { throw BrowserActionError.unsupportedText }
  }

  private func nativeClick(_ ref: BrowserElementRef, element: BrowserElement) async throws
    -> ActionResult
  {
    guard webView.window != nil else { throw BrowserActionError.nativeInputNeedsWindow }
    guard !element.picker || review.isStagedUpload(ref) else {
      throw BrowserActionError.nativePickerBlocked
    }
    let (frame, _) = try resolve(ref)
    let target: BrowserTargetPayload = try await call("target", input(for: ref), in: frame)
    guard !target.picker || (target.file && review.isStagedUpload(ref)) else {
      throw BrowserActionError.nativePickerBlocked
    }
    guard !target.sensitive else { throw BrowserActionError.credentialField }
    let mark: BrowserMarkPayload = try await call("mark", input(for: ref), in: frame)
    let mapped = try await nativePoint(target, ref: ref)
    try BrowserInputSynthesizer.click(at: mapped.point, viewport: mapped.viewport, in: webView)
    let events = try await observedEvents(since: mark.mark, timeout: .seconds(1), frame: frame) {
      events in
      events.contains { $0.type == "click" && $0.onTarget }
    }
    return ActionResult(
      observed: events, verified: events.contains { $0.type == "click" && $0.onTarget })
  }

  private func nativeType(_ ref: BrowserElementRef, text: String, replace: Bool) async throws
    -> ActionResult
  {
    guard webView.window != nil else { throw BrowserActionError.nativeInputNeedsWindow }
    let (frame, _) = try resolve(ref)
    let target: BrowserTargetPayload = try await call("target", input(for: ref), in: frame)
    guard target.editable else { throw BrowserActionError.notEditable }
    guard !target.sensitive else { throw BrowserActionError.credentialField }
    let mark: BrowserMarkPayload = try await call("mark", input(for: ref), in: frame)
    // Key events reach the focused element only while the web view is its window's first
    // responder; a click at the field's centre focuses it the way a person would.
    guard let window = webView.window else { throw BrowserActionError.nativeInputNeedsWindow }
    window.makeFirstResponder(webView)
    let mapped = try await nativePoint(target, ref: ref)
    try BrowserInputSynthesizer.click(at: mapped.point, viewport: mapped.viewport, in: webView)
    guard try await waitForFocus(ref) else { throw BrowserActionError.focusFailed }
    if replace {
      try BrowserInputSynthesizer.selectAllAndDelete(in: webView)
    } else {
      // A click lands mid-text in longer values; appending starts from the end.
      let _: BrowserOKPayload = try await call("caretToEnd", input(for: ref), in: frame)
    }
    try BrowserInputSynthesizer.type(text, in: webView)
    let expectedKeyUps = text.count + (replace ? 1 : 0)
    let timeout = Duration.milliseconds(1_000 + 40 * text.count)
    let events = try await observedEvents(since: mark.mark, timeout: timeout, frame: frame) {
      events in
      events.filter { $0.type == "keyup" && $0.onTarget }.count >= expectedKeyUps
    }
    var verifyInput = input(for: ref)
    verifyInput["text"] = text
    verifyInput["replace"] = replace
    let verification: BrowserVerifyPayload = try await call("verifyText", verifyInput, in: frame)
    return ActionResult(observed: events, verified: verification.matches)
  }

  /// Whether the field `ref` names holds exactly `text` now. The isolated world compares the
  /// live value, unredacted and uncapped, and answers only with the comparison; credential
  /// fields are never read.
  func fieldHolds(_ text: String, at ref: BrowserElementRef) async throws -> Bool {
    let (frame, _) = try resolve(ref)
    var verifyInput = input(for: ref)
    verifyInput["text"] = text
    verifyInput["replace"] = true
    let verification: BrowserVerifyPayload = try await call("verifyText", verifyInput, in: frame)
    return verification.matches
  }

  private func nativePoint(_ target: BrowserTargetPayload, ref: BrowserElementRef) async throws
    -> (point: CGPoint, viewport: CGSize)
  {
    guard ref.frame > 0 else {
      return (
        CGPoint(x: target.x, y: target.y),
        CGSize(width: target.viewportWidth, height: target.viewportHeight)
      )
    }
    guard let snapshot, ref.frame < snapshot.frames.count else {
      throw BrowserActionError.frameUnavailable
    }
    return try await BrowserFrameTargeting.target(
      target, documentID: snapshot.frames[ref.frame].docID, in: webView)
  }

  private func scriptClick(_ ref: BrowserElementRef, frame: WKFrameInfo?) async throws
    -> ActionResult
  {
    let mark: BrowserMarkPayload = try await call("mark", input(for: ref), in: frame)
    var authorizedInput = input(for: ref)
    authorizedInput["allowSubmit"] = true
    let _: BrowserOKPayload = try await call("scriptClick", authorizedInput, in: frame)
    let payload: BrowserObservedPayload = try await call(
      "observed", ["since": mark.mark], in: frame)
    return ActionResult(observed: payload.events)
  }

  private func scriptType(
    _ ref: BrowserElementRef, text: String, replace: Bool, frame: WKFrameInfo?
  ) async throws -> ActionResult {
    let mark: BrowserMarkPayload = try await call("mark", input(for: ref), in: frame)
    var typeInput = input(for: ref)
    typeInput["text"] = text
    typeInput["replace"] = replace
    let verification: BrowserVerifyPayload = try await call("scriptType", typeInput, in: frame)
    let payload: BrowserObservedPayload = try await call(
      "observed", ["since": mark.mark], in: frame)
    return ActionResult(observed: payload.events, verified: verification.matches)
  }

  private func scriptSelect(
    _ ref: BrowserElementRef, index: Int, label: String, frame: WKFrameInfo?
  ) async throws -> ActionResult {
    let mark: BrowserMarkPayload = try await call("mark", input(for: ref), in: frame)
    var selectInput = input(for: ref)
    selectInput["index"] = index
    selectInput["label"] = label
    let verification: BrowserVerifyPayload = try await call("scriptSelect", selectInput, in: frame)
    let payload: BrowserObservedPayload = try await call(
      "observed", ["since": mark.mark], in: frame)
    return ActionResult(observed: payload.events, verified: verification.matches)
  }

  /// Polls the isolated world's observer until the expected events arrive or the time is up.
  private func observedEvents(
    since mark: Int, timeout: Duration, frame: WKFrameInfo? = nil,
    until isComplete: ([BrowserObservedEvent]) -> Bool
  ) async throws -> [BrowserObservedEvent] {
    let deadline = ContinuousClock.now + timeout
    while true {
      let payload: BrowserObservedPayload = try await call(
        "observed", ["since": mark], in: frame, timeout: .seconds(2))
      if isComplete(payload.events) || ContinuousClock.now >= deadline { return payload.events }
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  private func waitForFocus(_ ref: BrowserElementRef) async throws -> Bool {
    let (frame, _) = try resolve(ref)
    let deadline = ContinuousClock.now + .seconds(1)
    while true {
      let focus: BrowserFocusPayload = try await call("focusState", input(for: ref), in: frame)
      if focus.focused || ContinuousClock.now >= deadline { return focus.focused }
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  // MARK: Sign-in Card (development review)

  /// Names the review harness's canary file. Without it, each fill generates an in-memory canary.
  /// Either way the Card fills only the offline lab page, never a real site or credential.
  static let canaryFileVariable = "MEMOSHI_BROWSER_REVIEW_SIGNIN_CANARY"

  /// Where the next fill's canary comes from: the harness file when the environment names one.
  static var canarySource: BrowserCanarySource {
    ProcessInfo.processInfo.environment[canaryFileVariable] == nil ? .ephemeral : .harnessFile
  }

  /// Offers a sign-in Card for the login form in the current snapshot of the lab page, standing
  /// in for `browser_sign_in`. Nothing is filled until the person chooses to fill it.
  func offerSignIn() {
    guard signInTask == nil, actionTask == nil, !isClosed, control == .watching else { return }
    signInTask = Task {
      await self.prepareSignInCard()
      self.signInTask = nil
    }
  }

  /// Fills the Card's canary from the isolated world if the page still has the Card's origin and
  /// fields. The credential exists only during the fill and is never recorded.
  func fillSignIn() {
    guard signInTask == nil, actionTask == nil, !isClosed, signInCard?.state == .offered else {
      return
    }
    signInTask = Task {
      await self.performSignInFill()
      self.signInTask = nil
    }
  }

  func declineSignIn() {
    guard signInTask == nil, let card = signInCard, card.state == .offered else { return }
    finishSignIn(card, result: .declined, refusal: nil, started: nil)
  }

  private func prepareSignInCard() async {
    signInProblem = nil
    guard let snapshot, snapshot.commit == commitCount else {
      signInProblem = snapshot == nil ? .noSnapshot : .staleSnapshot
      return
    }
    guard isShowingLabPage, let url = pageURL, let origin = BrowserAuthorization.origin(of: url)
    else {
      signInProblem = .notLabPage
      return
    }
    do {
      let form: BrowserSignInFormPayload = try await call(
        "signInForm", ["snapshotId": snapshot.id], in: nil)
      guard form.origin == origin, commitCount == snapshot.commit else {
        throw BrowserActionError.signInOriginMismatch
      }
      let card = BrowserSignInCard(
        id: UUID(),
        binding: BrowserSignIn.CardBinding(
          origin: origin, commit: snapshot.commit,
          usernameField: "\(snapshot.id):\(form.usernameRef)",
          passwordField: "\(snapshot.id):\(form.passwordRef)"),
        host: url.host() ?? origin, snapshotID: snapshot.id, usernameRef: form.usernameRef,
        passwordRef: form.passwordRef, source: Self.canarySource, offeredAt: Date(),
        state: .offered)
      signInCard = card
      lab?.record(.signInOffered(host: card.host), session: self)
    } catch {
      signInProblem = BrowserActionError(error)
    }
  }

  private func performSignInFill() async {
    guard var card = signInCard, card.state == .offered else { return }
    card.state = .filling
    signInCard = card
    let started = ContinuousClock.now
    let credential: BrowserReviewCanary
    do {
      credential = try Self.loadCanary(for: card.binding.origin, source: card.source)
    } catch {
      finishSignIn(
        card, result: .refused, refusal: BrowserActionError.canarySourceInvalid.rawValue,
        started: started)
      return
    }
    if let refusal = await signInRefusal(for: card, credential: credential) {
      finishSignIn(
        card, result: .refused, refusal: refusal, started: started, credential: credential)
      return
    }
    do {
      let input: [String: Any] = [
        "snapshotId": card.snapshotID, "usernameRef": card.usernameRef,
        "passwordRef": card.passwordRef, "username": credential.username,
        "password": credential.password, "origin": card.binding.origin,
      ]
      let fill: BrowserFillPayload = try await call("fillCredential", input, in: nil)
      let receipt = await signInReceipt(matching: credential)
      let containsCanary = try? await snapshotContains(credential)
      finishSignIn(
        card, result: .filled, refusal: nil, started: started, credential: credential,
        check: SignInCheck(
          domMatched: fill.usernameMatches && fill.passwordMatches,
          pageReceiptMatched: receipt.matched, pageInputEvents: receipt.events,
          masked: fill.masked, snapshotContainsCanary: containsCanary))
    } catch {
      let code =
        switch BrowserActionError(error) {
        case .signInOriginMismatch: BrowserSignIn.Refusal.originMismatch.rawValue
        case .signInFieldsChanged: BrowserSignIn.Refusal.fieldsChanged.rawValue
        case let other: other.rawValue
        }
      finishSignIn(card, result: .refused, refusal: code, started: started, credential: credential)
    }
  }

  /// The Card's rule, checked against the page as it is now: its origin, its commit and the login
  /// pair a fresh look at the current snapshot finds. The isolated world checks again on fill.
  private func signInRefusal(for card: BrowserSignInCard, credential: BrowserReviewCanary) async
    -> String?
  {
    guard control == .watching else { return BrowserActionError.userInControl.rawValue }
    var fields: (username: String?, password: String?) = (nil, nil)
    if let snapshot, snapshot.commit == commitCount {
      let form: BrowserSignInFormPayload? = try? await call(
        "signInForm", ["snapshotId": snapshot.id], in: nil)
      if let form {
        fields = ("\(snapshot.id):\(form.usernameRef)", "\(snapshot.id):\(form.passwordRef)")
      }
    }
    let page = BrowserSignIn.PageState(
      origin: pageURL.flatMap(BrowserAuthorization.origin(of:)), commit: commitCount,
      usernameField: fields.username, passwordField: fields.password)
    return BrowserSignIn.refusal(
      card: card.binding, credentialOrigin: credential.origin, page: page)?.rawValue
  }

  /// Polls the lab page's own receipt until the digests its script computed match the canary's,
  /// for up to two seconds. Nil when the page could not compute digests.
  private func signInReceipt(matching credential: BrowserReviewCanary) async -> (
    matched: Bool?, events: Int?
  ) {
    let username = BrowserReviewCanary.sha256Hex(credential.username)
    let password = BrowserReviewCanary.sha256Hex(credential.password)
    let deadline = ContinuousClock.now + .seconds(2)
    var last: BrowserSignInReceiptPayload?
    while true {
      let receipt: BrowserSignInReceiptPayload? = try? await call(
        "labSignInReceipt", [:], in: nil, timeout: .seconds(2))
      if let receipt {
        last = receipt
        guard receipt.digests else { return (nil, receipt.inputEvents) }
        if receipt.usernameDigest == username, receipt.passwordDigest == password {
          return (true, receipt.inputEvents)
        }
      }
      if ContinuousClock.now >= deadline { return (last.map { _ in false }, last?.inputEvents) }
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  /// A full snapshot pass after the fill that keeps the person's refs: does any name, value,
  /// option, title or URL it returns contain a canary value? This is what a model would see.
  private func snapshotContains(_ credential: BrowserReviewCanary) async throws -> Bool {
    let input: [String: Any] = [
      "snapshotId": 0, "maxElements": 500, "mode": BrowserSnapshotMode.full.rawValue,
      "measureOnly": true,
    ]
    let payload: BrowserFramePayload = try await call(
      "snapshot", input, in: nil, timeout: .seconds(5))
    let texts =
      payload.elements.flatMap { [$0.name, $0.value ?? ""] + ($0.options ?? []).map(\.label) }
      + [payload.title, payload.url]
    return texts.contains { $0.contains(credential.username) || $0.contains(credential.password) }
  }

  /// What the fill verified, as booleans and counts.
  private struct SignInCheck {
    let domMatched: Bool
    let pageReceiptMatched: Bool?
    let pageInputEvents: Int?
    let masked: Int
    let snapshotContainsCanary: Bool?
  }

  private func finishSignIn(
    _ card: BrowserSignInCard, result: BrowserSignInOutcome.Result, refusal: String?,
    started: ContinuousClock.Instant?, credential: BrowserReviewCanary? = nil,
    check: SignInCheck? = nil
  ) {
    let outcome = BrowserSignInOutcome(
      id: card.id, profileName: profile.name, pageHost: card.host, offeredAt: card.offeredAt,
      endedAt: Date(), result: result, refusal: refusal, source: started == nil ? nil : card.source,
      usernameFingerprint: credential?.usernameFingerprint,
      passwordFingerprint: credential?.passwordFingerprint, domMatched: check?.domMatched,
      pageReceiptMatched: check?.pageReceiptMatched, pageInputEvents: check?.pageInputEvents,
      maskedFieldsAfterFill: check?.masked, snapshotContainsCanary: check?.snapshotContainsCanary,
      durationMs: started.map { BrowserClock.milliseconds(since: $0) })
    signInCard = nil
    lastSignIn = outcome
    lab?.recordSignIn(outcome)
  }

  /// The Card's canary: the review harness's file when the environment names one, otherwise a
  /// fresh in-memory pair. The file must be this user's regular file, unreadable by others, at
  /// most 4 KiB, and hold a canary for exactly this origin. Symbolic links are refused.
  private static func loadCanary(for origin: String, source: BrowserCanarySource) throws
    -> BrowserReviewCanary
  {
    guard source == .harnessFile else { return BrowserReviewCanary.generate(origin: origin) }
    guard let path = ProcessInfo.processInfo.environment[canaryFileVariable], path.hasPrefix("/")
    else { throw BrowserActionError.canarySourceInvalid }
    let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw BrowserActionError.canarySourceInvalid }
    defer { _ = Darwin.close(descriptor) }
    var status = stat()
    guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == getuid(), status.st_mode & 0o077 == 0, status.st_size <= 4_096
    else { throw BrowserActionError.canarySourceInvalid }
    var bytes = [UInt8](repeating: 0, count: 4_097)
    let count = Darwin.read(descriptor, &bytes, bytes.count)
    guard count > 0, count <= 4_096 else { throw BrowserActionError.canarySourceInvalid }
    do {
      return try BrowserReviewCanary.parse(Data(bytes.prefix(count)), expectedOrigin: origin)
    } catch {
      throw BrowserActionError.canarySourceInvalid
    }
  }

  // MARK: Probes

  func startTimerProbe() async throws -> BrowserTimerPayload {
    try await call("timerStart", ["intervalMs": 100], in: nil, timeout: .seconds(5))
  }

  func readTimerProbe() async throws -> BrowserTimerPayload {
    try await call("timerRead", [:], in: nil, timeout: .seconds(5))
  }

  func stopTimerProbe() async {
    let _: BrowserTimerPayload? = try? await call("timerStop", [:], in: nil, timeout: .seconds(5))
  }

  /// Reloads the lab page from the app and waits for the main frame to finish loading.
  func reloadLabPageAndWait(timeout: Duration) async throws -> Double {
    guard !isClosed, isShowingLabPage, let url = BrowserAutomationScript.labPageURL else {
      throw BrowserActionError.notLabPage
    }
    guard admits(url) else { throw BrowserActionError.navigationNotStarted }
    let started = ContinuousClock.now
    let gate = BrowserResumeGate<Bool>()
    _ = try await gate.value(timeout: timeout, timeoutError: BrowserActionError.navigationFailed) {
      guard
        let navigation = webView.loadHTMLString(
          BrowserAutomationScript.labPageHTML, baseURL: url)
      else {
        gate.resume(.failure(BrowserActionError.navigationNotStarted))
        return
      }
      navigationWaiters[ObjectIdentifier(navigation)] = gate
    }
    return BrowserClock.milliseconds(since: started)
  }

  // MARK: Placement and takeover

  /// Records a host move and checks, asynchronously, that the same document answers afterwards.
  func didMove(from: BrowserPlacement, to: BrowserPlacement) {
    placement = to
    separate?.placement = to
    guard from != to else { return }
    lab?.record(.moved(from: from, to: to), session: self)
    // Before the first load there is no document whose survival could be checked.
    guard commitCount > 0 else { return }
    let baseline = knownDocument
    let commit = commitCount
    Task { [weak self] in
      await self?.verifyMove(from: from, to: to, baseline: baseline, commit: commit)
    }
  }

  private func verifyMove(
    from: BrowserPlacement, to: BrowserPlacement, baseline: KnownDocument?, commit: Int
  ) async {
    guard let baseline, baseline.commit == commit else {
      lab?.recordHostMove(from: from, to: to, result: .noBaseline, session: self)
      return
    }
    let result: BrowserHostMoveResult
    do {
      let identity: BrowserDocumentPayload = try await call(
        "documentId", [:], in: nil, timeout: .seconds(5))
      if commitCount != commit {
        result = .navigationDuringCheck
      } else {
        result = identity.docId == baseline.docID ? .sameDocument : .documentChanged
      }
    } catch {
      result = commitCount != commit ? .navigationDuringCheck : .checkFailed
    }
    lab?.recordHostMove(from: from, to: to, result: result, session: self)
  }

  /// The person takes the page; lab actions are held until Hand Back.
  func takeOver() {
    guard !isClosed, control == .watching else { return }
    control = .user
    takeoverStart = TakeoverStart(date: Date(), commit: commitCount, host: pageHost)
    lab?.record(.takeoverStarted, session: self)
  }

  /// Returns control to the lab with a change summary; no keystrokes or screenshots are kept.
  func handBack() {
    guard control == .user else { return }
    control = .watching
    // Takeover may have signed in using cookies or local storage the lab cannot classify.
    review.markPrivateData()
    if let start = takeoverStart {
      let navigations = commitCount - start.commit
      lastHandBack = HandBackSummary(
        duration: Date().timeIntervalSince(start.date), navigations: navigations,
        hostBefore: start.host, hostAfter: pageHost)
      lab?.record(.takeoverEnded(navigations: navigations), session: self)
    }
    takeoverStart = nil
    restoreShield()
  }

  /// While watching, the shield takes keyboard focus back so a person's keys don't reach the page.
  private func restoreShield() {
    guard control == .watching, placement == .reviewWindow else { return }
    liveContainer?.focusShield()
  }

  // MARK: Lifecycle

  /// Releases the web view and every WebKit callback. The profile's store stays on disk; a
  /// separate profile's data is removed (D136).
  func close() {
    guard !isClosed else { return }
    closeSeparate()
    lanes.close()
    isClosed = true
    Self.liveProfiles.remove(profile.id)
    actionTask?.cancel()
    snapshotTask?.cancel()
    signInTask?.cancel()
    signInCard = nil
    review.close()
    for observation in observations { observation.invalidate() }
    observations.removeAll()
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    contentController.removeAllScriptMessageHandlers()
    contentController.removeAllUserScripts()
    denyLocalTask?.cancel()
    contentController.removeAllContentRuleLists()
    webView.removeFromSuperview()
    liveContainer = nil
    for waiter in navigationWaiters.values {
      waiter.resume(.failure(BrowserActionError.sessionClosed))
    }
    navigationWaiters.removeAll()
    subframes.removeAll()
    registeredFrameCount = 0
    lastImage = nil
    delegate.session = nil
  }

  private func observeWebView() {
    let refresh = { @Sendable [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.syncFromWebView()
      }
    }
    observations = [
      webView.observe(\.url) { _, _ in refresh() },
      webView.observe(\.title) { _, _ in refresh() },
      webView.observe(\.isLoading) { _, _ in refresh() },
      webView.observe(\.estimatedProgress) { _, _ in refresh() },
      webView.observe(\.canGoBack) { _, _ in refresh() },
      webView.observe(\.canGoForward) { _, _ in refresh() },
    ]
  }

  private func syncFromWebView() {
    let url = webView.url
    if pageURL != url { pageURL = url }
    let title = webView.title ?? ""
    if pageTitle != title { pageTitle = title }
    if isLoading != webView.isLoading { isLoading = webView.isLoading }
    if progress != webView.estimatedProgress { progress = webView.estimatedProgress }
    if canGoBack != webView.canGoBack { canGoBack = webView.canGoBack }
    if canGoForward != webView.canGoForward { canGoForward = webView.canGoForward }
  }

  func call<Payload: Decodable>(
    _ command: String, _ input: [String: Any], in frame: WKFrameInfo?,
    timeout: Duration = .seconds(10)
  ) async throws -> Payload {
    guard !isClosed else { throw BrowserActionError.sessionClosed }
    let json = try await BrowserScriptCall.run(
      command: command, input: input, frame: frame, in: webView, timeout: timeout)
    return try BrowserScriptCall.decode(Payload.self, from: json)
  }

  // MARK: WebKit callbacks (BrowserSessionDelegate)

  /// A navigation decision, or what it still needs read first: whether the page's own store
  /// holds private data its review has not seen yet, or the bot's store's cookie facts that
  /// choose a profile (D136).
  private enum ActionDecision {
    case decided(WKNavigationActionPolicy)
    case needsPrivateData
    case needsCookies
  }

  /// Both delegates recheck exact host-owned site permissions. No page gets an ambient network,
  /// form, file-picker or credential authority just because it is visible. A form, or a frame
  /// of another origin, in a page whose review holds no private data yet first reads that page's
  /// store, which may have gained cookies since configuration. A top-level move to another site
  /// first reads the bot's own store's cookies, then opens in the bot's profile, stays in a
  /// separate one, or opens in a new separate one (D136). Every check is repeated after a read.
  func decidePolicy(
    for action: WKNavigationAction,
    decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
  ) {
    let main = action.targetFrame?.isMainFrame ?? true
    // A click waits for a navigation it allowed to start (D136 review F5); WebKit starts none for
    // a move within the shown document.
    let loads = main && !Self.movesInDocument(action.request, from: webView.url)
    if main { mainNavigations.ask() }
    let answer: @MainActor @Sendable (WKNavigationActionPolicy) -> Void = { [weak self] policy in
      if main { self?.mainNavigations.answer(allowed: loads && policy == .allow) }
      decisionHandler(policy)
    }
    let first = decide(action, cookies: nil, storeRead: false)
    if case .decided(let policy) = first {
      answer(policy)
      return
    }
    let root = self.root
    root.lanes.beginDecision()
    Task { [weak self] in
      defer { root.lanes.endDecision() }
      guard let self else { return answer(.cancel) }
      var next = first
      var cookies: BrowserSessionReview.StoredCookies?
      var storeRead = false
      while true {
        switch next {
        case .decided(let policy):
          return answer(policy)
        case .needsPrivateData:
          guard !storeRead else { return answer(.cancel) }
          _ = await self.review.holdsPrivateData()
          storeRead = true
        case .needsCookies:
          guard cookies == nil else { return answer(.cancel) }
          // An unreadable store counts as holding cookies: the move then opens separately.
          cookies = (try? await root.review.storedCookies()) ?? .unreadable
        }
        next = self.decide(action, cookies: cookies, storeRead: storeRead)
      }
    }
  }

  private func decide(
    _ action: WKNavigationAction, cookies: BrowserSessionReview.StoredCookies?, storeRead: Bool
  ) -> ActionDecision {
    // A decision that waited for a store read may finish after the session closed.
    guard !isClosed else { return .decided(.cancel) }
    let url = action.request.url
    let scheme = url?.scheme?.lowercased() ?? ""
    let method = (action.request.httpMethod ?? "GET").uppercased()
    let main = action.targetFrame?.isMainFrame ?? true
    if !main, ["about", "data", "blob"].contains(scheme) { return .decided(.allow) }
    guard scheme == "https" || scheme == "http" else {
      return .decided(block(.scheme, detail: nil, mainFrame: main, host: url?.host()))
    }
    // Content rules already block subresources; this refuses navigations, including
    // page-initiated ones, while the boundary is incomplete.
    guard admits(url, mainFrame: main) else { return .decided(.cancel) }
    let form = action.navigationType == .formSubmitted || action.navigationType == .formResubmitted
    let source = BrowserAuthorization.origin(of: action.sourceFrame.securityOrigin)
    // A load whose profile its caller chose; a form handed over from the bot's own profile was
    // authorized there and needs no permit of its own here.
    let commanded = main && commandedRequest.map { Self.sameTarget($0, action.request) } == true
    // A decision the private-data flag could change waits for a fresh read of this page's store
    // while the flag is false: a page may have set cookies since configuration.
    if !storeRead, !review.privateData,
      BrowserAuthorization.dependsOnPrivateData(
        BrowserAuthorization.Navigation(
          url: url, method: method, sourceOrigin: source, isForm: form, isMainFrame: main,
          handedOff: commanded))
    {
      return .needsPrivateData
    }
    if let denial = review.navigationDenial(
      url: url, method: method, sourceOrigin: source, formRequest: form, mainFrame: main,
      handedOff: commanded)
    {
      review.record(form || method != "GET" ? .form : .navigation, false, denial)
      return .decided(
        block(
          form || method != "GET" ? .formSubmission : .siteGrant,
          detail: denial, mainFrame: main, host: url?.host()))
    }
    if action.shouldPerformDownload {
      return .decided(
        review.mayDownload(url)
          ? .download
          : block(.download, detail: nil, mainFrame: main, host: url?.host()))
    }
    // The bot's own page, hidden behind its separate profile, moves nothing: its timers and
    // scripts would replace the profile the bot works in.
    if main, owner == nil, separate != nil, !commanded {
      review.record(.navigation, false, "separateProfileShown")
      return .decided(.cancel)
    }
    guard action.targetFrame != nil else {
      if action.navigationType == .linkActivated, method == "GET", let url {
        lab?.record(.openedInPlace(host: url.host()), session: self)
        // Judged later from the page the link was on, not from the frame that holds it.
        let from = BrowserAuthorization.moveSource(
          redirecting: nil, newWindow: nil, topDocument: mainDocumentURL, initiator: source,
          appPage: Self.labOrigin)
        Task { [weak self] in self?.loadInPlace(url, from: from) }
      }
      return .decided(.cancel)
    }
    guard main, let url, let destination = BrowserAuthorization.origin(of: url),
      destination != Self.labOrigin
    else { return .decided(.allow) }
    if commanded {
      // A load its caller chose replaces a stopped return's empty document.
      if owner == nil { lanes.leftReturnDocument() }
      provisionalMainURL = url
      return .decided(.allow)
    }
    // A return's empty document (D136), from its start until another document commits: loaded
    // once from the app with no network request, then only its script's navigation, allowed as
    // the cross-site arrival it is. Nothing else, and nothing once its return stopped (review
    // F3): that document is the app's, and a stopped return's navigation is never decided again
    // as a move of the page, which would open the return's target in a new separate profile.
    if owner == nil, let document = lanes.returnDocument {
      let loadsDocument = Self.sameTarget(URLRequest(url: document), action.request)
      if loadsDocument || isReturnDocument(mainDocumentURL) {
        if let pending = lanes.pendingReturn {
          if loadsDocument, lanes.admitReturnDocument() { return .decided(.allow) }
          if !loadsDocument, method == "GET",
            Self.sameTarget(URLRequest(url: pending.target), action.request),
            source == BrowserAuthorization.origin(of: pending.base)
          {
            lanes.returnArrived()
            provisionalMainURL = url
            return .decided(.allow)
          }
        }
        review.record(.navigation, false, "separateProfileReturnStopped")
        return .decided(.cancel)
      }
    }
    let from = BrowserAuthorization.moveSource(
      redirecting: provisionalMainURL,
      newWindow: inPlaceSource.flatMap { $0.url == url ? $0.from : nil },
      topDocument: mainDocumentURL, initiator: source, appPage: Self.labOrigin)
    if !from.isSameSite(as: destination) {
      guard let cookies else { return .needsCookies }
      let lane = BrowserAuthorization.profileLane(
        destination: destination, from: from,
        holdsPrivateData: root.review.privateData || cookies.holdsPrivate,
        cookieDomains: cookies.domains, shownSites: root.review.shownSites,
        profilePage: owner.map {
          $0.mainDocumentURL.flatMap(BrowserAuthorization.origin(of:)) ?? ""
        })
      switch lane {
      case .current:
        break
      case .profile where owner == nil:
        break
      case .profile:
        // Back to the bot's own site, only as a top-level GET, arriving cross-site from the
        // page that left: no POST, and nothing a normal cross-site link would not carry.
        guard method == "GET" else { return refuseMove("separateProfileReturnWithBody", url) }
        // The arrival needs the empty document's script; without one, or without the leaving
        // page's origin, there is no cross-site return and the move stays here, signed out.
        guard case .page(let leaving?) = from, let origin = URL(string: leaving + "/"),
          root.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript
        else { break }
        if form { review.consumeFormPermit() }
        returnToProfile(url, from: origin)
        return .decided(.cancel)
      case .separate:
        var handoff = URLRequest(url: url)
        if method != "GET" {
          // A confirmed form opens in the separate profile with its body, never in this one.
          guard action.request.httpBody != nil else {
            return refuseMove("separateProfileFormBodyUnavailable", url)
          }
          handoff = action.request
          handoff.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        // The form's one-use permit goes with it: the page left behind cannot submit it again.
        if form || method != "GET" { review.consumeFormPermit() }
        moveToSeparate(handoff)
        return .decided(.cancel)
      }
    }
    provisionalMainURL = url
    return .decided(.allow)
  }

  /// Refuses a form's move; its one-use permit ends with it.
  private func refuseMove(_ code: String, _ url: URL) -> ActionDecision {
    review.consumeFormPermit()
    review.record(.form, false, code)
    return .decided(block(.formSubmission, detail: code, mainFrame: true, host: url.host()))
  }

  /// The same method and address, ignoring a fragment and an empty path WebKit may normalize.
  private static func sameTarget(_ chosen: URLRequest, _ asked: URLRequest) -> Bool {
    func key(_ request: URLRequest) -> String? {
      guard let url = request.url,
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      else { return nil }
      if components.path.isEmpty { components.path = "/" }
      components.fragment = nil
      return (request.httpMethod ?? "GET").uppercased() + " " + (components.string ?? "")
    }
    return key(chosen) != nil && key(chosen) == key(asked)
  }

  /// A GET of the shown address with a fragment: WebKit scrolls within the document it shows and
  /// starts no load.
  private static func movesInDocument(_ request: URLRequest, from shown: URL?) -> Bool {
    guard let url = request.url, url.fragment != nil, let shown else { return false }
    return sameTarget(URLRequest(url: shown), request)
  }

  /// Whether `url` is the empty document of the return (D136) the bot's own profile started last
  /// and has not left since.
  private func isReturnDocument(_ url: URL?) -> Bool {
    guard let document = lanes.returnDocument, let url else { return false }
    return Self.sameTarget(URLRequest(url: document), URLRequest(url: url))
  }

  func decidePolicy(for response: WKNavigationResponse) -> WKNavigationResponsePolicy {
    let attachment =
      (response.response as? HTTPURLResponse)?
      .value(forHTTPHeaderField: "Content-Disposition")?.lowercased().hasPrefix("attachment")
      == true
    if !response.canShowMIMEType || attachment {
      guard review.mayDownload(response.response.url) else {
        lab?.record(.blocked(.download, detail: nil), session: self)
        return .cancel
      }
      return .download
    }
    if response.isForMainFrame, let http = response.response as? HTTPURLResponse {
      pendingHTTPStatus = http.statusCode
    }
    return .allow
  }

  func navigationStarted(_ navigation: WKNavigation?) {
    mainNavigations.start()
    if let navigation {
      pendingNavigations[ObjectIdentifier(navigation)] = PendingNavigation(
        start: ContinuousClock.now, host: webView.url?.host())
    }
    self.navigation = .loading
    pendingHTTPStatus = nil
  }

  func navigationCommitted() {
    commitCount += 1
    mainDocumentURL = webView.url
    // The return's empty document (D136) carries the leaving page's origin and sets nothing; any
    // other document leaves it.
    if owner == nil, !isReturnDocument(mainDocumentURL) {
      lanes.leftReturnDocument()
      review.recordShownSite(of: mainDocumentURL)
    }
    provisionalMainURL = nil
    commandedRequest = nil
    inPlaceSource = nil
    review.documentChanged()
    subframes.removeAll()
    registeredFrameCount = 0
    knownDocument = nil
  }

  func navigationFinished(_ navigation: WKNavigation?) {
    let pending = navigation.flatMap {
      pendingNavigations.removeValue(forKey: ObjectIdentifier($0))
    }
    let duration = pending.map { BrowserClock.milliseconds(since: $0.start) }
    self.navigation = .finished(ms: duration)
    lab?.recordNavigation(
      host: pageHost, result: .finished, durationMs: duration, httpStatus: pendingHTTPStatus,
      failure: nil, blockReason: nil, session: self)
    lab?.record(.navigationFinished(host: pageHost, ms: duration), session: self)
    review.collectGatewayEvidence()
    pendingHTTPStatus = nil
    refreshDocumentIdentity()
    if let navigation {
      navigationWaiters.removeValue(forKey: ObjectIdentifier(navigation))?.resume(.success(true))
    }
  }

  func navigationFailed(_ navigation: WKNavigation?, error: any Error) {
    let failure = BrowserNavigationFailure(error)
    var host = pageHost
    if let navigation {
      let identifier = ObjectIdentifier(navigation)
      if let pending = pendingNavigations.removeValue(forKey: identifier) { host = pending.host }
      navigationWaiters.removeValue(forKey: identifier)?.resume(
        .failure(BrowserActionError.navigationFailed))
    }
    // A replaced load fails while its successor loads; that successor keeps its markers.
    if !webView.isLoading {
      provisionalMainURL = nil
      commandedRequest = nil
      inPlaceSource = nil
    }
    switch failure.kind {
    case .cancelled, .interruptedByPolicy:
      // A newer navigation replaced this one and reports its own result, or a policy decision
      // stopped it and recorded why (a refusal, or a move to another profile, D136). Either way
      // nothing loads here any more.
      if self.navigation == .loading, !webView.isLoading { self.navigation = .idle }
    default:
      self.navigation = .failed(failure)
      lab?.recordNavigation(
        host: host, result: .failed, durationMs: nil, httpStatus: nil, failure: failure,
        blockReason: nil, session: self)
      lab?.record(.navigationFailed(host: host, failure), session: self)
    }
  }

  func contentProcessTerminated() {
    navigation = .terminated
    commitCount += 1
    // The process took its navigations with it; none of them reports an end.
    pendingNavigations.removeAll()
    for waiter in navigationWaiters.values {
      waiter.resume(.failure(BrowserActionError.contentProcessUnavailable))
    }
    navigationWaiters.removeAll()
    provisionalMainURL = nil
    commandedRequest = nil
    inPlaceSource = nil
    review.documentChanged()
    subframes.removeAll()
    registeredFrameCount = 0
    knownDocument = nil
    lab?.record(.contentProcessTerminated, session: self)
  }

  /// Registers a subframe's isolated world. Only this world can post here; the body is still
  /// validated because a compromised content process could send anything.
  func receive(_ message: WKScriptMessage) {
    guard message.name == BrowserAutomationScript.frameMessageName,
      !message.frameInfo.isMainFrame,
      let body = message.body as? [String: Any], body["kind"] as? String == "frame",
      let docID = body["docId"] as? String, (1...64).contains(docID.count),
      let handle = body["handle"] as? WKJSHandle,
      handle.contentWorld === BrowserAutomationScript.world,
      subframes.count < 24, !subframes.contains(where: { $0.docID == docID })
    else { return }
    let commit = commitCount
    handle.getWindowProxyFrame { [weak self] frame in
      guard let self, let frame, !frame.isMainFrame, !self.isClosed,
        self.commitCount == commit, self.subframes.count < 24,
        !self.subframes.contains(where: { $0.docID == docID })
      else { return }
      self.subframes.append(RegisteredFrame(docID: docID, info: frame))
      self.registeredFrameCount = self.subframes.count
    }
  }

  func recordDenied(_ kind: BrowserLabEvent.Kind) {
    lab?.record(kind, session: self)
  }

  private func block(
    _ reason: BrowserBlockReason, detail: String?, mainFrame: Bool, host: String?
  ) -> WKNavigationActionPolicy {
    lab?.record(.blocked(reason, detail: detail), session: self)
    if mainFrame {
      navigation = .blocked(reason)
      lab?.recordNavigation(
        host: host, result: .blocked, durationMs: nil, httpStatus: nil, failure: nil,
        blockReason: reason, session: self)
    }
    return .cancel
  }

  /// A new-window link loads in this view instead; its move is judged from the page it was on.
  private func loadInPlace(_ url: URL, from: BrowserAuthorization.MoveSource) {
    guard admits(url) else { return }
    inPlaceSource = (url, from)
    webView.load(URLRequest(url: url))
  }

  private func refreshDocumentIdentity() {
    let commit = commitCount
    Task { [weak self] in
      guard let self else { return }
      do {
        let identity: BrowserDocumentPayload = try await self.call(
          "documentId", [:], in: nil, timeout: .seconds(5))
        if self.commitCount == commit {
          self.knownDocument = KnownDocument(docID: identity.docId, commit: commit)
        }
      } catch {
        // Documents without the automation world (error pages, PDFs) have no identity.
      }
    }
  }
}

/// WebKit's navigation, UI and frame-registration callbacks. WebKit retains the content
/// controller's handler, so this object holds the session weakly.
@MainActor
final class BrowserSessionDelegate: NSObject, WKNavigationDelegate, WKUIDelegate,
  WKScriptMessageHandler
{
  weak var session: BrowserSession?

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
  ) {
    guard let session else { return decisionHandler(.cancel) }
    session.decidePolicy(for: navigationAction, decisionHandler: decisionHandler)
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
  ) {
    decisionHandler(session?.decidePolicy(for: navigationResponse) ?? .cancel)
  }

  func webView(
    _ webView: WKWebView, willSubmitForm formInfo: WKFormInfo,
    submissionHandler: @escaping @MainActor @Sendable () -> Void
  ) {
    session?.review.submit(formInfo, continueSubmission: submissionHandler)
  }

  func webView(
    _ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload
  ) {
    session?.review.becameDownload(download)
  }

  func webView(
    _ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload
  ) {
    session?.review.becameDownload(download)
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
    session?.navigationStarted(navigation)
  }

  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
    session?.navigationCommitted()
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
    session?.navigationFinished(navigation)
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?,
    withError error: any Error
  ) {
    session?.navigationFailed(navigation, error: error)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error)
  {
    session?.navigationFailed(navigation, error: error)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    session?.contentProcessTerminated()
  }

  /// Server trust uses WebKit's normal validation; every credential request is refused, so the
  /// lab never signs in with a stored or personal credential.
  func webView(
    _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @MainActor @Sendable (
        URLSession.AuthChallengeDisposition, URLCredential?
      ) -> Void
  ) {
    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
      completionHandler(.performDefaultHandling, nil)
    } else {
      session?.recordDenied(.authenticationDeclined)
      completionHandler(.rejectProtectionSpace, nil)
    }
  }

  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    // Not a network control: WebKit preconnects a `target=_blank` link's target before any
    // delegate runs (2026-11-07 boundary prototype finding 5), so returning nil only stops
    // the window, not that payload-free connection.
    nil
  }

  func webView(
    _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor @Sendable () -> Void
  ) {
    session?.recordDenied(.dialogDismissed)
    completionHandler()
  }

  func webView(
    _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
  ) {
    session?.recordDenied(.dialogDismissed)
    completionHandler(false)
  }

  func webView(
    _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?, initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor @Sendable (String?) -> Void
  ) {
    session?.recordDenied(.dialogDismissed)
    completionHandler(nil)
  }

  func webView(
    _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
  ) {
    guard let session else {
      completionHandler(nil)
      return
    }
    session.review.openPanel(parameters: parameters, frame: frame, completion: completionHandler)
  }

  func webView(
    _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
    decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
  ) {
    session?.recordDenied(.permissionDenied)
    decisionHandler(.deny)
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    session?.receive(message)
  }
}

/// Calls the isolated world's dispatcher with data arguments and decodes its JSON reply.
@MainActor
enum BrowserScriptCall {
  static func run(
    command: String, input: [String: Any], frame: WKFrameInfo?, in webView: WKWebView,
    timeout: Duration
  ) async throws -> String {
    let gate = BrowserResumeGate<String>()
    let arguments: [String: Any] = ["command": command, "input": input]
    return try await gate.value(
      timeout: timeout, timeoutError: BrowserActionError.scriptTimedOut
    ) {
      webView.callAsyncJavaScript(
        BrowserAutomationScript.dispatchBody, arguments: arguments, in: frame,
        in: BrowserAutomationScript.world
      ) { result in
        switch result {
        case .success(let value):
          if let json = value as? String {
            gate.resume(.success(json))
          } else {
            gate.resume(.failure(BrowserActionError.invalidResult))
          }
        case .failure(let error):
          gate.resume(.failure(BrowserActionError(scriptError: error)))
        }
      }
    }
  }

  static func decode<Payload: Decodable>(_ type: Payload.Type, from json: String) throws
    -> Payload
  {
    guard json.utf8.count <= 4_000_000 else { throw BrowserActionError.invalidResult }
    let data = Data(json.utf8)
    let decoder = JSONDecoder()
    if let failure = try? decoder.decode(BrowserScriptErrorPayload.self, from: data),
      let code = failure.error
    {
      throw BrowserActionError(scriptCode: code)
    }
    do {
      return try decoder.decode(type, from: data)
    } catch {
      throw BrowserActionError.invalidResult
    }
  }
}
