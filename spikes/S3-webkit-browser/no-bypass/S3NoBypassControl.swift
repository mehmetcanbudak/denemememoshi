// S3 no-bypass qualification control driver. run-control.py compiles it together with the
// unmodified product browser sources (BrowserSession, BrowserSessionReview, BrowserGateway, ...)
// into an owned carrier app. It drives real WebKit against owned loopback fixtures only and
// writes a scenario timeline; only the independent sink logs and gateway decisions are evidence.
// The gateway separate-profile scenario injects an owned gateway route through the lab's
// `startGateway` seam; it uses `EgressGateway`'s test seam (resolve and route), so it imports
// MemoshiEgress as testable, which the carrier's debug build allows.
import AppCore
import AppKit
import Darwin
import Foundation
import NIOCore
import WebKit

@testable import MemoshiEgress

private struct ControlFailure: Error { let message: String }

@MainActor
private final class ControlDriver: NSObject, NSApplicationDelegate {
  let output: URL
  let ports: [String: Int]
  let fixture: String
  let probeJS: String
  let run: String
  /// This carrier's bundle identifier; a second lab's defaults are named after it.
  let bundle: String
  let lab: BrowserReviewLab
  let granted: BrowserAuthorization.Site
  let fixtureSite: BrowserAuthorization.Site
  /// The owned frame fixture's origin (run-control.py's `fixture-frame` port) and the owned
  /// fixture task suite, for the Lockdown compatibility control.
  let frameOrigin: String
  let suiteText: String
  /// One persistent `forIdentifier` store, seeded outside the product boundary and then
  /// reopened by a product session.
  let persistentID = UUID()
  /// D136: one persistent store seeded with cookies, storage, cache and a worker for the sink's
  /// two sites, then used by the product as the bot's signed-in profile.
  let signedInID = UUID()
  /// Owned markers: the cookie and storage values for sites A and B in the signed-in store, and
  /// the ones only a separate profile ever holds (searched on disk after it is discarded), on the
  /// owned-fixture route (`T`) and on the gateway route (`G`).
  var marks: [String: String] {
    ["A": "d136a-" + run, "B": "d136b-" + run, "T": "d136t-" + run, "G": "d136g-" + run]
  }
  /// The owned gateway routes the gateway separate-profile scenario's lab started, in order.
  var ownedRoutes: [OwnedGatewayRoute] = []
  var window: NSWindow?
  var scenarios: [[String: Any]] = []
  var failures: [String] = []
  let http = URLSession(configuration: .ephemeral)

  init(_ args: [String]) throws {
    guard args.count == 8 else { throw ControlFailure(message: "seven owned arguments required") }
    output = URL(fileURLWithPath: args[1], isDirectory: true)
    let portData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    ports = try JSONDecoder().decode([String: Int].self, from: portData)
    fixture = args[3]
    probeJS = try String(contentsOf: URL(fileURLWithPath: args[4]), encoding: .utf8)
    run = args[5]
    bundle = args[6]
    suiteText = try String(contentsOf: URL(fileURLWithPath: args[7]), encoding: .utf8)
    guard let framePort = ports["fixture-frame"] else {
      throw ControlFailure(message: "fixture frame port missing")
    }
    frameOrigin = "http://127.0.0.1:\(framePort)"
    try requireOwnedIsolation(fixture: fixture, bundle: args[6])
    guard let defaults = UserDefaults(suiteName: args[6] + ".lab") else {
      throw ControlFailure(message: "lab defaults refused")
    }
    lab = BrowserReviewLab(defaults: defaults)
    // Never requested: the gateway route's pages are app-supplied with this base URL.
    granted = try BrowserAuthorization.Site(
      origin: "http://granted.probe.memoshi.invalid", interact: true, signIn: false,
      ownedFixture: false)
    fixtureSite = try BrowserAuthorization.Site(
      origin: fixture, interact: true, signIn: false, ownedFixture: true)
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let host = NSWindow(
      contentRect: NSRect(x: 80, y: 80, width: 900, height: 650),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    host.title = "Owned S3 no-bypass control"
    host.isReleasedWhenClosed = false
    host.makeKeyAndOrderFront(nil)
    window = host
    NSApp.activate()
    Task {
      let steps: [(String, () async throws -> Void)] = [
        ("positive-direct", { try await self.plain("positive-direct", page: "probe.html") }),
        ("positive-direct-sw", { try await self.plain("positive-direct-sw", page: "sw.html") }),
        ("positive-gateway", { try await self.positiveGateway() }),
        (
          "positive-blank",
          { try await self.plain("positive-blank", page: "probe.html", only: "a-target-blank") }
        ),
        (
          "product-fixture",
          { try await self.productFixture("product-fixture", page: "probe.html") }
        ),
        (
          "product-fixture-sw",
          { try await self.productFixture("product-fixture-sw", page: "sw.html") }
        ),
        ("product-proxy", { try await self.productProxy("product-proxy") }),
        (
          "product-fixture-blank",
          {
            try await self.productFixture(
              "product-fixture-blank", page: "probe.html", only: "a-target-blank")
          }
        ),
        (
          "product-proxy-blank",
          { try await self.productProxy("product-proxy-blank", only: "a-target-blank") }
        ),
        ("fc-unconfigured-navigate", { try await self.unconfiguredNavigate() }),
        ("fc-unconfigured-suite", { try await self.unconfiguredSuite() }),
        ("fc-immediate-lab-page", { try await self.immediateLabPage() }),
        ("fc-revoked-fixture", { try await self.revokedFixture() }),
        ("fc-revoked-proxy", { try await self.revokedProxy() }),
        ("fc-gateway-shutdown", { try await self.gatewayShutdown() }),
        ("fc-local-name-grant", { try await self.localNameGrant() }),
        // Owner-free controls added 2026-11-14 (design §9).
        ("positive-native-blank", { try await self.nativeBlankPositive() }),
        ("product-fixture-native-blank", { try await self.nativeBlankFixture() }),
        ("product-proxy-native-blank", { try await self.nativeBlankProxy() }),
        ("positive-persistent-seed", { try await self.persistentSeed() }),
        ("positive-persistent-reopen", { try await self.persistentReopen() }),
        ("product-persistent-store", { try await self.persistentProduct() }),
        ("product-concurrent-bots", { try await self.concurrentBots() }),
        ("product-lockdown-suite", { try await self.lockdownSuite() }),
        // Separate profile for another site (D136).
        ("positive-shared-profile", { try await self.sharedProfilePositive() }),
        ("product-separate-profile", { try await self.separateProfile() }),
        ("product-separate-profile-gateway", { try await self.separateProfileGateway() }),
        ("product-separate-profile-edges", { try await self.separateProfileEdges() }),
        ("product-rule-list-sweep", { try await self.ruleListSweep() }),
      ]
      // run-control.py `--only`: a development run of some scenarios, never a complete control.
      let only = Self.scenarioFilter
      for (name, step) in steps where only?.contains(name) ?? true {
        do { try await step() } catch {
          failures.append(name + ": " + String(describing: error))
          record(
            ["name": name, "error": String(describing: error)], start: Date().timeIntervalSince1970)
        }
        window?.contentView = nil
        try? await Task.sleep(for: .seconds(1))
      }
      finish()
    }
  }

  /// The scenarios `S3_CONTROL_ONLY` names (comma-separated), or nil for all of them.
  static var scenarioFilter: Set<String>? {
    ProcessInfo.processInfo.environment["S3_CONTROL_ONLY"].map {
      Set($0.split(separator: ",").map(String.init))
    }
  }

  // MARK: Pages

  /// Pages probe only this Mac's own loopback, own-address and local-only named sinks; no other
  /// host's address or LAN name is ever loaded.
  private func params(
    _ scenario: String, noh: Bool, only: String? = nil, fetchTargets: [String]? = nil
  )
    -> [String: Any]
  {
    var value: [String: Any] = [
      "run": run, "scenario": scenario, "ports": ports, "noh": noh,
    ]
    if let only { value["only"] = only }
    if let fetchTargets { value["fetchTargets"] = fetchTargets }
    return value
  }

  private func servedURL(_ page: String, _ params: [String: Any]) throws -> URL {
    let data = try JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])
    guard var components = URLComponents(string: fixture + "/no-bypass/" + page) else {
      throw ControlFailure(message: "invalid fixture page URL")
    }
    components.queryItems = [URLQueryItem(name: "p", value: data.base64EncodedString())]
    guard let url = components.url else { throw ControlFailure(message: "invalid served URL") }
    return url
  }

  private func fixtureURL(_ path: String) throws -> URL {
    guard let url = URL(string: fixture + path) else {
      throw ControlFailure(message: "invalid fixture URL " + path)
    }
    return url
  }

  private func inlineHTML(_ params: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])
    return
      "<!doctype html><html lang='en'><meta charset='utf-8'><title>S3 no-bypass inline probe</title>"
      + "<body><p>S3 no-bypass control: app-supplied page on the gateway route.</p><script>window.__probeParams="
      + String(decoding: data, as: UTF8.self) + ";</script><script>" + probeJS
      + "</script></body></html>"
  }

  private func host(_ webView: WKWebView) {
    webView.frame = window?.contentLayoutRect ?? .zero
    webView.autoresizingMask = [.width, .height]
    window?.contentView = webView
  }

  private func plainView(
    proxy gateway: BrowserGateway? = nil, store: WKWebsiteDataStore = .nonPersistent()
  ) throws -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = store
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    try gateway?.apply(to: configuration.websiteDataStore)
    let view = WKWebView(frame: .zero, configuration: configuration)
    host(view)
    return view
  }

  /// Polls the page world for the probe's report. A missing report is recorded, never a pass.
  private func report(_ webView: WKWebView, seconds: Int = 150) async -> Any {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline {
      if let value = try? await webView.evaluateJavaScript(
        "window.__probeDone || null", in: nil, contentWorld: .page) as? String,
        let data = value.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data)
      {
        return object
      }
      try? await Task.sleep(for: .milliseconds(250))
    }
    return ["missing": true, "url": webView.url?.absoluteString ?? "none"]
  }

  /// Lets the page's trailing main-frame navigation and late sockets land in this window.
  private func settle() async { try? await Task.sleep(for: .milliseconds(3500)) }

  // MARK: Scenarios

  private func plain(_ name: String, page: String, only: String? = nil) async throws {
    let start = Date().timeIntervalSince1970
    let view = try plainView()
    view.load(URLRequest(url: try servedURL(page, params(name, noh: true, only: only))))
    let page = await report(view)
    await settle()
    view.stopLoading()
    record(["name": name, "kind": "positiveControl", "page": page], start: start)
  }

  private func positiveGateway() async throws {
    let start = Date().timeIntervalSince1970
    let gateway = try await BrowserGateway.start(profileID: UUID(), sites: [granted])
    let view = try plainView(proxy: gateway)
    view.loadHTMLString(
      try inlineHTML(params("positive-gateway", noh: false)),
      baseURL: URL(string: granted.origin + "/"))
    let page = await report(view)
    await settle()
    view.stopLoading()
    let decisions = gateway.decisionWindow.decisions
    await gateway.close()
    record(
      [
        "name": "positive-gateway", "kind": "positiveControl", "page": page,
        "gateway": try object(decisions),
      ], start: start)
  }

  private func session(
    _ name: String, id: UUID = UUID(), hosted: Bool = true, in lab: BrowserReviewLab? = nil
  ) -> BrowserSession {
    let profile = BrowserReviewProfile(id: id, name: name, createdAt: Date(), probe: nil)
    let session = BrowserSession(
      profile: profile, scheduling: .unthrottled, placement: .detached, lab: lab ?? self.lab)
    if hosted { host(session.webView) }
    return session
  }

  private func configure(
    _ session: BrowserSession, _ sites: [BrowserAuthorization.Site],
    _ route: BrowserSessionReview.Route
  ) async throws {
    session.review.configure(sites: sites, route: route)
    try await configured(session, route)
  }

  /// Waits for a configuration already started on `session` to settle on `route`.
  private func configured(_ session: BrowserSession, _ route: BrowserSessionReview.Route)
    async throws
  {
    let deadline = ContinuousClock.now + .seconds(20)
    while session.review.isConfiguring || session.review.route != route {
      guard ContinuousClock.now < deadline, session.review.problem == nil else {
        throw ControlFailure(message: "configuration " + (session.review.problem ?? "deadline"))
      }
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  private func productFixture(_ name: String, page: String, only: String? = nil) async throws {
    let start = Date().timeIntervalSince1970
    let active = session(name)
    try await configure(active, [fixtureSite], .directFixture)
    var navigation = "started"
    do {
      try await active.navigateForSuite(
        try servedURL(page, params(name, noh: true, only: only)))
    } catch { navigation = String(describing: error) }
    let page = await report(active.webView, seconds: navigation == "started" ? 150 : 2)
    await settle()
    record(
      close(
        active,
        [
          "name": name, "kind": "product", "route": "directFixture",
          "navigation": navigation, "page": page,
        ]), start: start)
  }

  private func productProxy(_ name: String, only: String? = nil) async throws {
    let start = Date().timeIntervalSince1970
    let active = session(name)
    try await configure(active, [granted], .authenticatedProxy)
    active.webView.loadHTMLString(
      try inlineHTML(params(name, noh: false, only: only)),
      baseURL: URL(string: granted.origin + "/"))
    let page = await report(active.webView)
    await settle()
    record(
      close(
        active, ["name": name, "kind": "product", "route": "authenticatedProxy", "page": page]),
      start: start)
  }

  private func unconfiguredNavigate() async throws {
    let start = Date().timeIntervalSince1970
    let active = session("fc-unconfigured-navigate")
    let before = try await receipts()
    // Immediately after creation, and again once the deny-local list has had time to install.
    let first = active.navigate(to: fixture + "/no-bypass/probe.html")
    try await Task.sleep(for: .seconds(2))
    let second = active.navigate(to: fixture + "/no-bypass/probe.html")
    try await Task.sleep(for: .seconds(2))
    let after = try await receipts()
    record(
      close(
        active,
        [
          "name": "fc-unconfigured-navigate", "kind": "failClosed",
          "immediateResult": first.map { String(describing: $0) } ?? "loadStarted",
          "laterResult": second.map { String(describing: $0) } ?? "loadStarted",
          "fixtureRequestsDuring": after - before,
          "url": active.webView.url?.absoluteString ?? "none",
        ]),
      start: start)
  }

  private func unconfiguredSuite() async throws {
    let start = Date().timeIntervalSince1970
    let active = session("fc-unconfigured-suite")
    let before = try await receipts()
    var outcome = "loaded"
    do { try await active.navigateForSuite(try fixtureURL("/no-bypass/probe.html")) } catch {
      outcome = String(describing: error)
    }
    try await Task.sleep(for: .seconds(1))
    let after = try await receipts()
    record(
      close(
        active,
        [
          "name": "fc-unconfigured-suite", "kind": "failClosed", "outcome": outcome,
          "fixtureRequestsDuring": after - before,
        ]), start: start)
  }

  private func immediateLabPage() async throws {
    let start = Date().timeIntervalSince1970
    let active = session("fc-immediate-lab-page")
    active.loadLabPage()
    let immediateStarted = active.webView.isLoading || active.webView.url != nil
    try await Task.sleep(for: .seconds(2))
    active.loadLabPage()
    try await Task.sleep(for: .seconds(2))
    record(
      close(
        active,
        [
          "name": "fc-immediate-lab-page", "kind": "failClosed",
          "immediateLoadStarted": immediateStarted,
          "laterURL": active.webView.url?.absoluteString ?? "none",
        ]), start: start)
  }

  private func revokedFixture() async throws {
    let start = Date().timeIntervalSince1970
    let active = session("fc-revoked-fixture")
    try await configure(active, [fixtureSite], .directFixture)
    active.review.revokePermissions()
    let before = try await receipts()
    var outcome = "loaded"
    do { try await active.navigateForSuite(try fixtureURL("/no-bypass/probe.html")) } catch {
      outcome = String(describing: error)
    }
    let address = active.navigate(to: fixture + "/no-bypass/probe.html")
    try await Task.sleep(for: .seconds(2))
    let after = try await receipts()
    record(
      close(
        active,
        [
          "name": "fc-revoked-fixture", "kind": "failClosed", "suiteOutcome": outcome,
          "addressResult": address.map { String(describing: $0) } ?? "loadStarted",
          "fixtureRequestsDuring": after - before,
        ]), start: start)
  }

  /// Revocation closes the gateway and removes the route: the granted site then loads neither
  /// through the product's own paths nor as an app-supplied page, and nothing reaches a sink.
  private func revokedProxy() async throws {
    let start = Date().timeIntervalSince1970
    let active = session("fc-revoked-proxy")
    try await configure(active, [granted], .authenticatedProxy)
    active.review.revokePermissions()
    let revokedBoundary = active.boundary.evidenceCode
    try await Task.sleep(for: .milliseconds(500))
    guard let grantedPage = URL(string: granted.origin + "/page") else {
      throw ControlFailure(message: "invalid granted URL")
    }
    var outcome = "loaded"
    do { try await active.navigateForSuite(grantedPage) } catch {
      outcome = String(describing: error)
    }
    let address = active.navigate(to: grantedPage.absoluteString)
    active.webView.loadHTMLString(
      try inlineHTML(params("fc-revoked-proxy", noh: false, only: "fetch")),
      baseURL: URL(string: granted.origin + "/"))
    let page = await report(active.webView, seconds: 20)
    await settle()
    record(
      close(
        active,
        [
          "name": "fc-revoked-proxy", "kind": "failClosed", "page": page,
          "revokedBoundary": revokedBoundary, "suiteOutcome": outcome,
          "addressResult": address.map { String(describing: $0) } ?? "loadStarted",
        ]), start: start)
  }

  /// allowFailover=false: with the gateway shut down, names it carried must not go direct.
  private func gatewayShutdown() async throws {
    let start = Date().timeIntervalSince1970
    let gateway = try await BrowserGateway.start(profileID: UUID(), sites: [granted])
    let view = try plainView(proxy: gateway)
    await gateway.close()
    let closedBeforeLoad = gateway.isClosed
    view.loadHTMLString(
      try inlineHTML(
        params("fc-gateway-shutdown", noh: false, only: "fetch", fetchTargets: ["sub", "h"])),
      baseURL: URL(string: granted.origin + "/"))
    let page = await report(view, seconds: 20)
    await settle()
    record(
      [
        "name": "fc-gateway-shutdown", "kind": "failClosed", "page": page,
        "gatewayClosedBeforeLoad": closedBeforeLoad,
        "gateway": try object(gateway.decisionWindow.decisions),
      ], start: start)
  }

  /// run-control.py's names: `mdns:<name>.local` are random local-only mDNS records for owned
  /// sinks.
  private func named(_ prefix: String) -> [(name: String, port: Int)] {
    ports.filter { $0.key.hasPrefix(prefix) }
      .map { (String($0.key.dropFirst(prefix.count)), $0.value) }
      .sorted { $0.name < $1.name }
  }

  /// A `.local` site cannot be granted: configuration fails closed and its loads reach nothing.
  private func localNameGrant() async throws {
    let start = Date().timeIntervalSince1970
    guard let target = named("mdns:").first else {
      record(
        ["name": "fc-local-name-grant", "kind": "skipped", "reason": "no mDNS name registered"],
        start: start)
      return
    }
    let site = try BrowserAuthorization.Site(
      origin: "http://\(target.name):\(target.port)", interact: true, signIn: false,
      ownedFixture: false)
    let active = session("fc-local-name-grant")
    var problem = "none"
    do { try await configure(active, [site], .authenticatedProxy) } catch {
      problem = String(describing: error)
    }
    active.webView.loadHTMLString(
      try inlineHTML(params("fc-local-name-grant", noh: false, only: "lan-fetch,lan-img")),
      baseURL: URL(string: site.origin + "/"))
    let page = await report(active.webView, seconds: 30)
    await settle()
    record(
      close(
        active,
        [
          "name": "fc-local-name-grant", "kind": "failClosed", "configurationProblem": problem,
          "page": page,
        ]), start: start)
  }

  // MARK: Owner-free controls (2026-11-14)

  /// Clicks every `target=_blank` anchor the probe placed with synthesized `NSEvent`s through
  /// the product's native input path, then reads back which clicks the page saw as trusted.
  private func clickNativeBlank(_ webView: WKWebView) async -> [String: Any] {
    struct Layout: Decodable {
      struct Anchor: Decodable {
        let t: String
        let x: Double
        let y: Double
      }
      let w: Double
      let h: Double
      let a: [Anchor]
    }
    let locate =
      "JSON.stringify({w: innerWidth, h: innerHeight, a: [...document.querySelectorAll("
      + "'a[data-native-blank]')].map((a) => { const r = a.getBoundingClientRect(); return "
      + "{t: a.dataset.nativeBlank, x: r.left + r.width / 2, y: r.top + r.height / 2}; })})"
    var attempts: [String] = []
    var errors: [String] = []
    if let text = try? await webView.evaluateJavaScript(locate, in: nil, contentWorld: .page)
      as? String,
      let layout = try? JSONDecoder().decode(Layout.self, from: Data(text.utf8))
    {
      for anchor in layout.a {
        do {
          try BrowserInputSynthesizer.click(
            at: CGPoint(x: anchor.x, y: anchor.y),
            viewport: CGSize(width: layout.w, height: layout.h),
            in: webView)
          attempts.append(anchor.t)
        } catch { errors.append(anchor.t + ": " + String(describing: error)) }
        try? await Task.sleep(for: .milliseconds(1500))
      }
    } else {
      errors.append("anchors not located")
    }
    try? await Task.sleep(for: .seconds(2))
    var clicks: Any = []
    if let text = try? await webView.evaluateJavaScript(
      "JSON.stringify(window.__nativeClicks || [])", in: nil, contentWorld: .page) as? String,
      let object = try? JSONSerialization.jsonObject(with: Data(text.utf8))
    {
      clicks = object
    }
    return ["nativeClicks": clicks, "nativeClickAttempts": attempts, "nativeClickErrors": errors]
  }

  private func nativeBlankPositive() async throws {
    let start = Date().timeIntervalSince1970
    let name = "positive-native-blank"
    let view = try plainView()
    view.load(
      URLRequest(
        url: try servedURL("probe.html", params(name, noh: true, only: "a-target-blank-native"))))
    let page = await report(view)
    var row: [String: Any] = ["name": name, "kind": "positiveControl", "page": page]
    row.merge(await clickNativeBlank(view)) { $1 }
    await settle()
    view.stopLoading()
    record(row, start: start)
  }

  private func nativeBlankFixture() async throws {
    let start = Date().timeIntervalSince1970
    let name = "product-fixture-native-blank"
    let active = session(name)
    try await configure(active, [fixtureSite], .directFixture)
    var navigation = "started"
    do {
      try await active.navigateForSuite(
        try servedURL("probe.html", params(name, noh: true, only: "a-target-blank-native")))
    } catch { navigation = String(describing: error) }
    let page = await report(active.webView, seconds: navigation == "started" ? 150 : 2)
    var row: [String: Any] = [
      "name": name, "kind": "product", "route": "directFixture", "navigation": navigation,
      "page": page,
    ]
    row.merge(await clickNativeBlank(active.webView)) { $1 }
    await settle()
    record(close(active, row), start: start)
  }

  private func nativeBlankProxy() async throws {
    let start = Date().timeIntervalSince1970
    let name = "product-proxy-native-blank"
    let active = session(name)
    try await configure(active, [granted], .authenticatedProxy)
    active.webView.loadHTMLString(
      try inlineHTML(params(name, noh: false, only: "a-target-blank-native")),
      baseURL: URL(string: granted.origin + "/"))
    let page = await report(active.webView)
    var row: [String: Any] = [
      "name": name, "kind": "product", "route": "authenticatedProxy", "page": page,
    ]
    row.merge(await clickNativeBlank(active.webView)) { $1 }
    await settle()
    record(close(active, row), start: start)
  }

  /// The seeded localStorage marker (and the page's cookies), read from the page world.
  private func storeMarker(_ webView: WKWebView) async -> [String: Any] {
    guard
      let text = try? await webView.evaluateJavaScript(
        "JSON.stringify({localStorage: (() => { try { return localStorage.getItem("
          + "'memoshi-s3-marker'); } catch (e) { return 'err:' + e; } })(), cookie: document.cookie})",
        in: nil, contentWorld: .page) as? String,
      let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    else { return ["unreadable": true] }
    return object
  }

  /// Outside the product boundary (no Lockdown, no rules): a persistent store gets a marker and
  /// a service worker that keeps firing at the http4 sink on every later navigation in scope.
  private func persistentSeed() async throws {
    let start = Date().timeIntervalSince1970
    let name = "positive-persistent-seed"
    let view = try plainView(store: WKWebsiteDataStore(forIdentifier: persistentID))
    var seed = params(name, noh: true)
    seed["keep"] = true
    view.load(URLRequest(url: try servedURL("sw.html", seed)))
    let page = await report(view)
    await settle()
    let marker = await storeMarker(view)
    view.stopLoading()
    record(
      [
        "name": name, "kind": "positiveControl", "page": page, "storeMarker": marker,
        "storeIdentifier": persistentID.uuidString,
      ], start: start)
  }

  /// The same store reopened outside the boundary: the seeded worker must fire again.
  private func persistentReopen() async throws {
    let start = Date().timeIntervalSince1970
    let name = "positive-persistent-reopen"
    let view = try plainView(store: WKWebsiteDataStore(forIdentifier: persistentID))
    view.load(URLRequest(url: try servedURL("probe.html", params(name, noh: true, only: "none"))))
    let page = await report(view)
    await settle()
    let marker = await storeMarker(view)
    view.stopLoading()
    record(
      [
        "name": name, "kind": "positiveControl", "page": page, "storeMarker": marker,
        "storeIdentifier": persistentID.uuidString,
      ], start: start)
  }

  /// The seeded store reopened by a product session: nothing may load before configuration,
  /// the store's data must still be there, and the full probe (inside the seeded worker's
  /// scope) must reach no sink.
  private func persistentProduct() async throws {
    let start = Date().timeIntervalSince1970
    let name = "product-persistent-store"
    let active = session(name, id: persistentID)
    let immediate = active.navigate(to: fixture + "/no-bypass/probe.html")
    try await configure(active, [fixtureSite], .directFixture)
    var navigation = "started"
    do {
      try await active.navigateForSuite(try servedURL("probe.html", params(name, noh: true)))
    } catch { navigation = String(describing: error) }
    let page = await report(active.webView, seconds: navigation == "started" ? 150 : 2)
    let marker = await storeMarker(active.webView)
    await settle()
    record(
      close(
        active,
        [
          "name": name, "kind": "product", "route": "directFixture", "navigation": navigation,
          "page": page, "storeMarker": marker,
          "reopenedImmediateResult": immediate.map { String(describing: $0) } ?? "loadStarted",
          "storeIdentifier": persistentID.uuidString,
        ]), start: start)
  }

  /// `report` for several views at once, with the time each one reported.
  private func reports(_ views: [WKWebView], seconds: Int = 150) async -> [(Any, TimeInterval)] {
    var found: [(Any, TimeInterval)?] = Array(repeating: nil, count: views.count)
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline, found.contains(where: { $0 == nil }) {
      for (index, view) in views.enumerated() where found[index] == nil {
        if let value = try? await view.evaluateJavaScript(
          "window.__probeDone || null", in: nil, contentWorld: .page) as? String,
          let object = try? JSONSerialization.jsonObject(with: Data(value.utf8))
        {
          found[index] = (object, Date().timeIntervalSince1970)
        }
      }
      try? await Task.sleep(for: .milliseconds(250))
    }
    return views.indices.map { index in
      found[index]
        ?? (
          ["missing": true, "url": views[index].url?.absoluteString ?? "none"],
          Date().timeIntervalSince1970
        )
    }
  }

  /// Two bots at once, one on each product route, side by side in one window: both are
  /// configured together and both full probes are in flight at the same time.
  private func concurrentBots() async throws {
    let start = Date().timeIntervalSince1970
    let first = session("product-concurrent-a", hosted: false)
    let second = session("product-concurrent-b", hosted: false)
    let pair = NSView(frame: window?.contentLayoutRect ?? .zero)
    let half = pair.bounds.width / 2
    first.webView.frame = NSRect(x: 0, y: 0, width: half, height: pair.bounds.height)
    second.webView.frame = NSRect(x: half, y: 0, width: half, height: pair.bounds.height)
    pair.addSubview(first.webView)
    pair.addSubview(second.webView)
    window?.contentView = pair
    // Both configurations start before either is awaited.
    first.review.configure(sites: [granted], route: .authenticatedProxy)
    second.review.configure(sites: [fixtureSite], route: .directFixture)
    try await configured(first, .authenticatedProxy)
    try await configured(second, .directFixture)
    let firstStarted = Date().timeIntervalSince1970
    first.webView.loadHTMLString(
      try inlineHTML(params("product-concurrent-a", noh: false)),
      baseURL: URL(string: granted.origin + "/"))
    let secondURL = try servedURL("probe.html", params("product-concurrent-b", noh: true))
    let secondStarted = Date().timeIntervalSince1970
    let navigation = Task { @MainActor () -> String in
      do {
        try await second.navigateForSuite(secondURL)
        return "started"
      } catch { return String(describing: error) }
    }
    let pages = await reports([first.webView, second.webView])
    let (firstPage, firstReported) = pages[0]
    let (secondPage, secondReported) = pages[1]
    let secondNavigation = await navigation.value
    await settle()
    let bots = [
      close(
        first,
        [
          "name": "product-concurrent-a", "route": "authenticatedProxy", "page": firstPage,
          "loadStarted": firstStarted, "reported": firstReported,
        ]),
      close(
        second,
        [
          "name": "product-concurrent-b", "route": "directFixture", "navigation": secondNavigation,
          "page": secondPage, "loadStarted": secondStarted, "reported": secondReported,
        ]),
    ]
    record(["name": "product-concurrent-bots", "kind": "product", "bots": bots], start: start)
  }

  /// The owned-fixture task suite, its origins moved to this run's fixture ports, run by the
  /// product task runner on a product session (Lockdown is always on there).
  private func lockdownSuite() async throws {
    let start = Date().timeIntervalSince1970
    let name = "product-lockdown-suite"
    let active = session(name)
    let text = suiteText.replacingOccurrences(of: "http://127.0.0.1:8765", with: fixture)
      .replacingOccurrences(of: "http://127.0.0.1:8766", with: frameOrigin)
    let runner = lab.taskRunner
    runner.select(data: Data(text.utf8))
    guard runner.candidate != nil else {
      throw ControlFailure(message: "suite refused: " + (runner.problem ?? "unknown"))
    }
    runner.approve(on: active)
    try await configured(active, .directFixture)
    runner.start(on: active)
    let finish = ContinuousClock.now + .seconds(600)
    while runner.isRunning, ContinuousClock.now < finish {
      try await Task.sleep(for: .milliseconds(250))
    }
    if runner.isRunning { runner.cancel() }
    let lockdown = active.boundary.lockdown
    await settle()
    record(
      close(
        active,
        [
          "name": name, "kind": "product", "route": "directFixture", "lockdownActive": lockdown,
          "suite": try runner.run.map { try object($0) } ?? NSNull(),
          "runnerProblem": runner.problem ?? "none",
        ]), start: start)
  }

  // MARK: Separate profile (D136)

  /// The cookie sink's listeners (run-control.py `profile-A`, `profile-A2`, `profile-B`): A and
  /// A2 are one site (127.0.0.1 on two ports); B, loaded as `localhost`, is another; `B6` is B's
  /// listener loaded as `[::1]`, a third site no cookie of the signed-in store names.
  private func profileOrigin(_ key: String) throws -> String {
    let listener = key == "B6" ? "B" : key
    guard let port = ports["profile-" + listener] else {
      throw ControlFailure(message: "profile sink port \(listener) missing")
    }
    let host = ["B": "localhost", "B6": "[::1]"][key] ?? "127.0.0.1"
    return "http://" + host + ":" + String(port)
  }

  /// A cookie-sink page (profile-sink.py `/page`).
  private func sinkPage(_ origin: String, _ task: String, mode: String? = nil, next: String? = nil)
    -> String
  {
    origin + "/page?task=" + task + (mode.map { "&mode=" + $0 } ?? "")
      + (next.map { "&next=" + escaped($0) } ?? "")
  }

  /// B's page with the marker only a separate profile ever holds.
  private func separatePage(_ task: String, mode: String? = nil, next: String? = nil) throws
    -> String
  {
    sinkPage(try profileOrigin("B"), task, mode: mode, next: next) + "&mark=" + (try mark("T"))
  }

  private func suiteStep(_ operation: String, _ role: String, _ label: String) -> [String: Any] {
    ["operation": operation, "selector": ["role": role, "name": label]]
  }

  private func fixtureSuiteSites(_ origins: [String]) -> [[String: Any]] {
    origins.map { ["origin": $0, "interact": true, "signIn": false, "ownedFixture": true] }
  }

  private func fixtureSites(_ origins: [String]) throws -> [BrowserAuthorization.Site] {
    try origins.map {
      try BrowserAuthorization.Site(origin: $0, interact: true, signIn: false, ownedFixture: true)
    }
  }

  /// The signed-in store's cookies were planted by a plain view outside the product
  /// (`positive-shared-profile`), so the product never saw its pages. A commanded open uses the
  /// profile only for a site it has shown (D136), as it would have after a person signed in on
  /// A, A2 and B in it; record those seeded pages as shown.
  private func showSeededSites(_ session: BrowserSession) throws {
    for key in ["A", "A2", "B"] {
      session.review.recordShownSite(of: URL(string: try profileOrigin(key) + "/seed"))
    }
  }

  /// Every decision recorded for `profile` since `began`, as `operation:allowed:code`.
  private func codes(of profile: UUID, since began: Date) -> [String] {
    lab.evidence.contents.decisions.filter { $0.profileID == profile && $0.at >= began }
      .map { "\($0.operation):\($0.allowed):\($0.code)" }
  }

  private func mark(_ key: String) throws -> String {
    guard let value = marks[key] else { throw ControlFailure(message: "marker \(key) missing") }
    return value
  }

  private func escaped(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
  }

  /// Waits for the sink page at `url` to publish what it saw. The report names its own address,
  /// so the previous page's report is never taken for this one. A missing report is recorded.
  private func sinkReport(_ view: WKWebView, at url: URL, seconds: Int = 20) async -> Any {
    let expected = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline {
      if let text = try? await view.evaluateJavaScript(
        "window.__d136 || null", in: nil, contentWorld: .page) as? String,
        let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
        let href = object["href"] as? String,
        let reported = URLComponents(string: href),
        reported.host == expected?.host, reported.port == expected?.port,
        reported.path == expected?.path,
        Set(reported.queryItems ?? []) == Set(expected?.queryItems ?? [])
      {
        return object
      }
      try? await Task.sleep(for: .milliseconds(250))
    }
    return ["missing": true, "url": view.url?.absoluteString ?? "none"]
  }

  private func loadReport(_ view: WKWebView, _ text: String) async throws -> Any {
    guard let url = URL(string: text) else { throw ControlFailure(message: "invalid sink URL") }
    view.load(URLRequest(url: url))
    return await sinkReport(view, at: url)
  }

  /// Outside the product boundary (no Lockdown, no rules), one persistent store gets cookies and
  /// storage for A and B, B's cacheable script and a worker at B; then a link from A to B in the
  /// same store must carry B's cookie, storage, cache and worker along. The product scenarios
  /// below use this store as the bot's signed-in profile.
  private func sharedProfilePositive() async throws {
    let start = Date().timeIntervalSince1970
    let a = try profileOrigin("A")
    let b = try profileOrigin("B")
    let view = try plainView(store: WKWebsiteDataStore(forIdentifier: signedInID))
    let seedA = try await loadReport(view, a + "/seed?v=" + mark("A"))
    let seedB = try await loadReport(view, b + "/seed?sw=1&v=" + mark("B"))
    let next = b + "/page?task=shared"
    let from = try await loadReport(view, a + "/page?task=shared-from&next=" + escaped(next))
    _ = try? await view.evaluateJavaScript(
      "document.getElementById('next').click(); null", in: nil, contentWorld: .page)
    guard let target = URL(string: next) else { throw ControlFailure(message: "invalid sink URL") }
    let shared = await sinkReport(view, at: target)
    await settle()
    view.stopLoading()
    record(
      [
        "name": "positive-shared-profile", "kind": "positiveControl", "marks": marks,
        "seedA": seedA, "seedB": seedB, "from": from, "shared": shared,
        "storeIdentifier": signedInID.uuidString,
      ], start: start)
  }

  /// The product on the seeded store, driven by the product task runner on the owned-fixture
  /// route, one task per way of moving: a same-site link; a link to B and a link back; a
  /// same-site redirect to B and an SSO-style redirect back with a code; B opened directly; a
  /// `_blank` link, a script move, `window.open`, a confirmed GET form and a confirmed POST form
  /// to B, and a POST form from B back to A (refused). The D136 review's follow-ups: a sandboxed
  /// frame's script move to B (F1; the store holds a cookie of B), a form to an origin no grant
  /// names (F4, refused at the click), the POST form replayed into a frame of the page left
  /// behind (F7), and native typing of 300 characters and into a field that doubles a space
  /// (F6). Afterwards: the separate profiles' recorded boundaries and opening times, when the
  /// runner reached each task, whether a separate profile is still open, and what of them is left
  /// on disk (their marker, their compiled rule lists, a store).
  private func separateProfile() async throws {
    let start = Date().timeIntervalSince1970
    let began = Date()
    let name = "product-separate-profile"
    let a = try profileOrigin("A")
    let a2 = try profileOrigin("A2")
    let b = try profileOrigin("B")
    let separateMark = try mark("T")
    func page(_ origin: String, _ task: String, mode: String? = nil, next: String? = nil) -> String
    {
      sinkPage(origin, task, mode: mode, next: next)
    }
    func onB(_ task: String, mode: String? = nil, next: String? = nil) -> String {
      page(b, task, mode: mode, next: next) + "&mark=" + separateMark
    }
    func step(_ operation: String, _ role: String, _ label: String) -> [String: Any] {
      suiteStep(operation, role, label)
    }
    func task(_ id: String, _ url: String, _ steps: [[String: Any]]) -> [String: Any] {
      ["id": id, "site": a, "steps": [["operation": "navigate", "url": url]] + steps]
    }
    let toB = [step("click", "link", "Next site"), step("expect", "heading", "Page B")]
    let back = [step("click", "link", "Next site"), step("expect", "heading", "Page A")]
    let sso = b + "/redirect?to=" + escaped(page(a, "sso") + "&code=d136-code")
    // Listener A by another name: an origin no grant of this suite names (F4).
    let ungranted = page(
      a.replacingOccurrences(of: "127.0.0.1", with: "localhost"), "ungranted")
    let typed = String(String(repeating: "memoshi ", count: 38).prefix(300))
    func type(_ text: String, expectedDenial: String? = nil) -> [String: Any] {
      var typing = step("type", "textbox", "Typed text")
      typing["text"] = text
      typing["nativeInput"] = true
      if let expectedDenial { typing["expectedDenial"] = expectedDenial }
      return typing
    }
    var refusedClick = step("click", "button", "Save other site")
    refusedClick["expectedDenial"] = "siteNotGranted"
    let suite: [String: Any] = [
      "id": "s3-d136-separate-profile",
      "sites": fixtureSuiteSites([a, a2, b]),
      "tasks": [
        task(
          "same-site", page(a, "same-from", next: page(a2, "same")),
          [step("click", "link", "Next site"), step("expect", "heading", "Page A2")]),
        task(
          "cross-site-link-and-return",
          page(a, "link-from", next: onB("link", next: page(a, "return"))), toB + back),
        task(
          "cross-site-redirect-and-sso-return",
          page(
            a, "redirect-from",
            next: a + "/redirect?to=" + escaped(onB("redirect", next: sso))), toB + back),
        [
          "id": "told-to-open", "site": b,
          "steps": [
            ["operation": "navigate", "url": page(b, "command")],
            step("expect", "heading", "Page B"),
          ],
        ],
        task("cross-site-blank", page(a, "blank-from", mode: "blank", next: onB("blank")), toB),
        task(
          "cross-site-script", page(a, "script-from", mode: "script", next: onB("script")),
          [step("click", "button", "Go by script"), step("expect", "heading", "Page B")]),
        task(
          "window-open", page(a, "open-from", mode: "open", next: page(b, "open")),
          [step("click", "button", "Open window"), step("expect", "heading", "Page A")]),
        task(
          "cross-site-form-get", page(a, "formget-from", mode: "formget", next: onB("formget")),
          [step("click", "button", "Search other site"), step("expect", "heading", "Page B")]),
        task(
          "cross-site-form-post", page(a, "formpost-from", mode: "formpost", next: onB("formpost")),
          [step("click", "button", "Save other site"), step("expect", "heading", "Page B")]),
        // From the separate profile, a POST form back to the first site: refused, never sent.
        task(
          "post-back-refused",
          page(a, "pb-from", next: onB("pbpage", mode: "formpost", next: page(a, "postback"))),
          toB + [step("click", "button", "Save other site"), step("expect", "heading", "Page B")]),
        // F1: a sandboxed srcdoc frame (opaque origin) on A moves the top level to B by script.
        // The store holds B's cookie, so the old frame-origin rule took it as a commanded open of
        // a cookie site and kept the profile; the page it is on decides now.
        task(
          "cross-site-sandboxed-frame",
          page(a, "sframe-from", mode: "sframe", next: onB("sframe")),
          [step("expect", "heading", "Page B")]),
        // F4: a form to an origin no grant names is refused at the click and sent nowhere.
        task(
          "cross-site-form-ungranted",
          page(a, "ungranted-from", mode: "formpost", next: ungranted),
          [refusedClick]),
        // F7: the POST form leaves for a separate profile with its body; the page left behind
        // submits it again into a frame of its own, which no permit covers any more.
        task(
          "cross-site-form-replay",
          page(a, "formreplay-from", mode: "formreplay", next: onB("formreplay")),
          [step("click", "button", "Save other site"), step("expect", "heading", "Page B")]),
        // F6: the typed value must be exactly the field's, at any length up to the limit.
        task(
          "type-long-native", page(a, "typed", mode: "typed"),
          [type(typed), step("expect", "heading", "Page A")]),
        task(
          "type-doubled-space", page(a, "typeddouble", mode: "typeddouble"),
          [type("hello world", expectedDenial: "invalidResult")]),
      ],
    ]
    let active = session(name, id: signedInID)
    try showSeededSites(active)
    let runner = lab.taskRunner
    runner.select(data: try JSONSerialization.data(withJSONObject: suite))
    guard runner.candidate != nil else {
      throw ControlFailure(message: "suite refused: " + (runner.problem ?? "unknown"))
    }
    runner.approve(on: active)
    try await configured(active, .directFixture)
    runner.start(on: active)
    // A form on a page holding private data waits for the person's exposure confirmation; the
    // control gives it, as a person would, each time the runner waits without one. It lands on
    // the profile the bot works in, a separate one included (D136 review F9).
    var confirmations = 0
    // When the runner reached each task, so each decision can be told to its task.
    var taskStarts: [[String: Any]] = []
    let finish = ContinuousClock.now + .seconds(900)
    while runner.isRunning, ContinuousClock.now < finish {
      // Every task the runner has recorded, in order, so a task shorter than one poll (a refused
      // click) is still listed; its start is the first poll that saw it.
      for step in runner.run?.steps ?? []
      where !taskStarts.contains(where: { $0["task"] as? String == step.taskID }) {
        taskStarts.append(["task": step.taskID, "at": Date().timeIntervalSince1970])
      }
      if runner.waitingForExposure, !active.lane.review.hasCurrentExposureConfirmation {
        active.review.confirmNextPrivateForm()
        confirmations += 1
      }
      try await Task.sleep(for: .milliseconds(5))
    }
    if runner.isRunning { runner.cancel() }
    let openAfterRun = active.separate != nil
    let decisions = lab.evidence.contents.decisions.filter { $0.at >= began }
    let separateIDs = Set(
      decisions.filter { $0.operation == .configuration && $0.code == "separateProfile" }
        .map(\.profileID))
    let profiles = separateIDs.sorted { $0.uuidString < $1.uuidString }.map { id in
      [
        "id": id.uuidString.lowercased(),
        "codes": decisions.filter { $0.profileID == id }
          .map { "\($0.operation):\($0.allowed):\($0.code)" },
        "openedAt": decisions.first {
          $0.profileID == id && $0.operation == .configuration && $0.code == "separateProfile"
        }.map { $0.at.timeIntervalSince1970 as Any } ?? NSNull(),
      ] as [String: Any]
    }
    // The signed-in store writes in the background; give it time before searching the disk.
    try await Task.sleep(for: .seconds(5))
    let kept = separateMark + "-kept"
    let disk = scanHome(for: [kept, try mark("B")])
    let identifiers = await WKWebsiteDataStore.allDataStoreIdentifiers
    record(
      close(
        active,
        [
          "name": name, "kind": "product", "route": "directFixture", "marks": marks,
          "profileID": active.profile.id.uuidString.lowercased(),
          "suite": try runner.run.map { try object($0) } ?? NSNull(),
          "suiteProblem": runner.problem ?? "none", "separateOpenAfterRun": openAfterRun,
          "exposureConfirmations": confirmations, "taskStarts": taskStarts,
          "profileDecisions": decisions.filter { $0.profileID == active.profile.id }.map {
            ["code": "\($0.operation):\($0.allowed):\($0.code)", "at": $0.at.timeIntervalSince1970]
          },
          "separateProfiles": profiles, "separateMarkOnDisk": disk[kept] ?? [],
          "profileMarkOnDisk": !(disk[try mark("B")] ?? []).isEmpty,
          "profileMarkFiles": disk[try mark("B")] ?? [],
          "separateRuleListsLeft": ruleListsLeft(for: separateIDs),
          "separateStoreIdentifiers": identifiers.filter(separateIDs.contains).map(\.uuidString),
        ]), start: start)
  }

  /// D136 on the gateway route, with pages at granted hosts. A lab of its own starts each bot
  /// profile's gateway as the product does (`BrowserGateway`), on an owned `EgressGateway`
  /// route (`OwnedGatewayRoute`): the bot's site `bot.d136.memoshi.test` is the cookie sink's
  /// A, `www.d136.memoshi.test` (the same registrable domain) is A2, and
  /// `other.d136.memoshi-other.test` (another site) is B. The bot's profile holds cookies of
  /// both sites, planted as a person's sign-ins would leave them. The product task runner, on
  /// the gateway route: a same-site link; a link to B and one back; a confirmed POST form to B;
  /// a form to an origin no grant names (refused at the click); the POST form replayed into a
  /// frame of the page left behind (refused); and a redirect to B whose separate opening the
  /// route refuses (D136 review F5: the runner reports the opening's own code at once). The
  /// cookie sink sees every page with its Host and Cookie headers, as a site would.
  private func separateProfileGateway() async throws {
    let start = Date().timeIntervalSince1970
    let began = Date()
    let name = "product-separate-profile-gateway"
    func listener(_ key: String) throws -> Int {
      guard let port = ports["profile-" + key] else {
        throw ControlFailure(message: "profile sink port \(key) missing")
      }
      return port
    }
    let hosts: [String: OwnedGatewayRoute.Target] = [
      GatewayHosts.bot: .init(address: "93.184.215.14", port: try listener("A")),
      GatewayHosts.sameSite: .init(address: "93.184.215.15", port: try listener("A2")),
      GatewayHosts.other: .init(address: "93.184.215.16", port: try listener("B")),
    ]
    guard let defaults = UserDefaults(suiteName: bundle + ".gateway-lab") else {
      throw ControlFailure(message: "gateway lab defaults refused")
    }
    let gatewayLab = BrowserReviewLab(defaults: defaults) { [weak self] id, sites in
      let route = try await OwnedGatewayRoute.start(profileID: id, sites: sites, hosts: hosts)
      self?.ownedRoutes.append(route)
      return route
    }
    // Its startup sweep must not race the profiles this scenario compiles lists for.
    _ = await gatewayLab.startupSweep?.value
    let active = session(name, in: gatewayLab)
    let store = active.webView.configuration.websiteDataStore
    let markA = try mark("A")
    let markB = try mark("B")
    let planted: [(name: String, value: String, domain: String, policy: HTTPCookieStringPolicy?)] =
      [
        ("d136", markA, "." + GatewayHosts.botDomain, nil),
        ("d136l", markA, "." + GatewayHosts.botDomain, .sameSiteLax),
        ("d136s", markA, "." + GatewayHosts.botDomain, .sameSiteStrict),
        ("d136", markB, GatewayHosts.other, nil),
      ]
    for cookie in planted {
      var properties: [HTTPCookiePropertyKey: Any] = [
        .name: cookie.name, .value: cookie.value, .domain: cookie.domain, .path: "/",
        .expires: Date().addingTimeInterval(3600),
      ]
      if let policy = cookie.policy { properties[.sameSitePolicy] = policy.rawValue }
      guard let made = HTTPCookie(properties: properties) else {
        throw ControlFailure(message: "cookie refused")
      }
      await store.httpCookieStore.setCookie(made)
    }
    // As after a person signed in there in this profile (D136's commanded-open rule).
    active.review.recordShownSite(of: URL(string: "http://" + GatewayHosts.bot + "/seed"))
    let a = "http://" + GatewayHosts.bot
    let a2 = "http://" + GatewayHosts.sameSite
    let b = "http://" + GatewayHosts.other
    let separateMark = try mark("G")
    func onB(_ task: String, mode: String? = nil, next: String? = nil) -> String {
      sinkPage(b, task, mode: mode, next: next) + "&mark=" + separateMark
    }
    func task(_ id: String, _ url: String, _ steps: [[String: Any]]) -> [String: Any] {
      ["id": id, "site": a, "steps": [["operation": "navigate", "url": url]] + steps]
    }
    let next = suiteStep("click", "link", "Next site")
    let save = suiteStep("click", "button", "Save other site")
    var refused = save
    refused["expectedDenial"] = "siteNotGranted"
    var failing = next
    failing["expectedDenial"] = OwnedGatewayRoute.refusal
    let suite: [String: Any] = [
      "id": "s3-d136-separate-profile-gateway",
      "sites": [a, a2, b].map {
        ["origin": $0, "interact": true, "signIn": false, "ownedFixture": false] as [String: Any]
      },
      "tasks": [
        task(
          "gw-same-site", sinkPage(a, "gw-same-from", next: sinkPage(a2, "gw-same")),
          [next, suiteStep("expect", "heading", "Page A2")]),
        task(
          "gw-link-and-return",
          sinkPage(a, "gw-link-from", next: onB("gw-link", next: sinkPage(a, "gw-return"))),
          [
            next, suiteStep("expect", "heading", "Page B"), next,
            suiteStep("expect", "heading", "Page A"),
          ]),
        task(
          "gw-form-post",
          sinkPage(a, "gw-formpost-from", mode: "formpost", next: onB("gw-formpost")),
          [save, suiteStep("expect", "heading", "Page B")]),
        task(
          "gw-form-ungranted",
          sinkPage(
            a, "gw-ungranted-from", mode: "formpost",
            next: sinkPage("http://" + GatewayHosts.ungranted, "gw-ungranted")), [refused]),
        task(
          "gw-form-replay",
          sinkPage(a, "gw-formreplay-from", mode: "formreplay", next: onB("gw-formreplay")),
          [save, suiteStep("expect", "heading", "Page B")]),
        task(
          "gw-opening-fails",
          sinkPage(a, "gw-fail-from", next: a + "/redirect?to=" + escaped(onB("gw-failed"))),
          [failing]),
      ],
    ]
    let runner = gatewayLab.taskRunner
    runner.select(data: try JSONSerialization.data(withJSONObject: suite))
    guard runner.candidate != nil else {
      throw ControlFailure(message: "suite refused: " + (runner.problem ?? "unknown"))
    }
    runner.approve(on: active)
    try await configured(active, .authenticatedProxy)
    guard let route = ownedRoutes.last else {
      throw ControlFailure(message: "the lab started no owned gateway route")
    }
    runner.start(on: active)
    var confirmations = 0
    var taskStarts: [[String: Any]] = []
    var armed = false
    // Each separate profile the bot worked in, and whether its store persists.
    var separateSeen: [UUID: Bool] = [:]
    let finish = ContinuousClock.now + .seconds(600)
    while runner.isRunning, ContinuousClock.now < finish {
      for step in runner.run?.steps ?? []
      where !taskStarts.contains(where: { $0["task"] as? String == step.taskID }) {
        taskStarts.append(["task": step.taskID, "at": Date().timeIntervalSince1970])
      }
      // F5: from its first step on, the route refuses the next store it is applied to, which
      // is the separate profile the redirect opens.
      if !armed, taskStarts.contains(where: { $0["task"] as? String == "gw-opening-fails" }) {
        route.refusesNextApply = true
        armed = true
      }
      if let lane = active.separate, separateSeen[lane.profile.id] == nil {
        separateSeen[lane.profile.id] = lane.webView.configuration.websiteDataStore.isPersistent
      }
      if runner.waitingForExposure, !active.lane.review.hasCurrentExposureConfirmation {
        active.review.confirmNextPrivateForm()
        confirmations += 1
      }
      try await Task.sleep(for: .milliseconds(5))
    }
    if runner.isRunning { runner.cancel() }
    let openAfterRun = active.separate != nil
    let decisions = gatewayLab.evidence.contents.decisions.filter { $0.at >= began }
    let separateIDs = Set(
      decisions.filter { $0.operation == .configuration && $0.code == "separateProfile" }
        .map(\.profileID))
    // Every profile but the bot's: those that opened and the one whose opening was refused.
    let otherIDs = Set(decisions.map(\.profileID)).subtracting([active.profile.id])
    let profiles = separateIDs.sorted { $0.uuidString < $1.uuidString }.map { id in
      [
        "id": id.uuidString.lowercased(),
        "codes": decisions.filter { $0.profileID == id }
          .map { "\($0.operation):\($0.allowed):\($0.code)" },
        "openedAt": decisions.first {
          $0.profileID == id && $0.operation == .configuration && $0.code == "separateProfile"
        }.map { $0.at.timeIntervalSince1970 as Any } ?? NSNull(),
      ] as [String: Any]
    }
    let separateBots = Set(otherIDs.map { "browser-review-" + $0.uuidString.lowercased() })
    try await Task.sleep(for: .seconds(5))
    let kept = separateMark + "-kept"
    let disk = scanHome(for: [kept])
    let identifiers = await WKWebsiteDataStore.allDataStoreIdentifiers
    record(
      close(
        active,
        [
          "name": name, "kind": "product", "route": "authenticatedProxy", "marks": marks,
          "profileID": active.profile.id.uuidString.lowercased(),
          "suite": try runner.run.map { try object($0) } ?? NSNull(),
          "suiteProblem": runner.problem ?? "none", "separateOpenAfterRun": openAfterRun,
          "exposureConfirmations": confirmations, "taskStarts": taskStarts,
          "refusedOpenings": ownedRoutes.map(\.refusedApplies).reduce(0, +),
          "profileDecisions": decisions.filter { $0.profileID == active.profile.id }.map {
            ["code": "\($0.operation):\($0.allowed):\($0.code)", "at": $0.at.timeIntervalSince1970]
          },
          "separateProfiles": profiles,
          "separateSeen": separateSeen.map {
            ["id": $0.key.uuidString.lowercased(), "persistent": $0.value] as [String: Any]
          },
          // The separate profiles use the bot's own gateway client (D136): nothing is attributed
          // to an identity of their own.
          "separateGateway":
            (try? object(
              gatewayLab.evidence.contents.gateway.filter { separateBots.contains($0.bot) })) ?? [],
          "separateMarkOnDisk": disk[kept] ?? [],
          "separateRuleListsLeft": ruleListsLeft(for: otherIDs),
          "separateStoreIdentifiers": identifiers.filter(otherIDs.contains).map(\.uuidString),
        ], in: gatewayLab), start: start)
    defaults.removePersistentDomain(forName: bundle + ".gateway-lab")
  }

  /// The D136 review's follow-ups the task runner cannot show alone, on the signed-in store and
  /// the owned-fixture route. F3: the runner is cancelled the moment a return to the bot's site
  /// is decided; the return must never arrive and nothing may commit in the bot's profile after
  /// the cancel. F8: a separate profile opened under broader grants (a commanded open of
  /// `[::1]`, a site no cookie of the store names) must close when the bot is re-authorized
  /// without that site. F9: a file staged for a form in a separate profile makes that profile
  /// hold private data; the person's exposure confirmation must reach it, so its form is allowed.
  /// Spec gap 5: a fresh profile, holding nothing when configured, loads a page that sets a
  /// cookie and embeds a frame of another granted origin; the frame must be refused, because the
  /// page now holds private data. F5 runs on the gateway route (`separateProfileGateway`).
  private func separateProfileEdges() async throws {
    let start = Date().timeIntervalSince1970
    let began = Date()
    let name = "product-separate-profile-edges"
    let a = try profileOrigin("A")
    let v6 = try profileOrigin("B6")
    let narrow = try [a, profileOrigin("A2"), profileOrigin("B")]
    let wide = try fixtureSites(narrow + [v6])
    func url(_ text: String) throws -> URL {
      guard let url = URL(string: text) else { throw ControlFailure(message: "invalid sink URL") }
      return url
    }
    var row: [String: Any] = [
      "name": name, "kind": "product", "route": "directFixture", "marks": marks,
      "gateway": [] as [Any],
    ]

    // F3: to B in a separate profile, then the link back; the cancel lands while the return is
    // decided but before it arrives.
    let cancelled = session(name + "-cancel", id: signedInID)
    try showSeededSites(cancelled)
    let suite: [String: Any] = [
      "id": "s3-d136-cancel-return", "sites": fixtureSuiteSites(narrow),
      "tasks": [
        [
          "id": "cancel-during-return", "site": a,
          "steps": [
            [
              "operation": "navigate",
              "url": sinkPage(
                a, "cancel-from",
                next: try separatePage("cancel", next: sinkPage(a, "cancelreturn"))),
            ],
            suiteStep("click", "link", "Next site"), suiteStep("expect", "heading", "Page B"),
            suiteStep("click", "link", "Next site"), suiteStep("expect", "heading", "Page A"),
          ],
        ]
      ],
    ]
    let runner = lab.taskRunner
    runner.select(data: try JSONSerialization.data(withJSONObject: suite))
    guard runner.candidate != nil else {
      throw ControlFailure(message: "suite refused: " + (runner.problem ?? "unknown"))
    }
    runner.approve(on: cancelled)
    try await configured(cancelled, .directFixture)
    runner.start(on: cancelled)
    var cancelAt: Date?
    var commitsAtCancel = 0
    let finish = ContinuousClock.now + .seconds(120)
    while runner.isRunning, ContinuousClock.now < finish {
      if cancelAt == nil,
        lab.evidence.contents.decisions.contains(where: {
          $0.at >= began && $0.allowed && $0.code == "separateProfileReturn"
        })
      {
        commitsAtCancel = cancelled.commitCount
        runner.cancel()
        cancelAt = Date()
      }
      try await Task.sleep(for: .milliseconds(5))
    }
    if runner.isRunning { runner.cancel() }
    let stopped = ContinuousClock.now + .seconds(30)
    while runner.isRunning, ContinuousClock.now < stopped {
      try await Task.sleep(for: .milliseconds(50))
    }
    // A return the cancel failed to stop would load and commit well within this.
    try await Task.sleep(for: .seconds(3))
    row["returnDecidedBeforeCancel"] = cancelAt != nil
    row["cancelRunStopped"] = !runner.isRunning
    row["cancelRunState"] = runner.run?.state.rawValue ?? "none"
    row["separateOpenAfterCancel"] = cancelled.separate != nil
    if let cancelAt {
      row["cancelAt"] = cancelAt.timeIntervalSince1970
      row["profileCommitsAfterCancel"] = cancelled.commitCount - commitsAtCancel
    }
    row["cancelProfileCodes"] = codes(of: cancelled.profile.id, since: began)
    cancelled.close()

    // F8: the bot's own page never committed, so it may be re-authorized.
    let reauthorized = session(name + "-reauthorize", id: signedInID)
    try showSeededSites(reauthorized)
    try await configure(reauthorized, wide, .directFixture)
    var opened = "opened"
    do { try await reauthorized.navigateForSuite(try url(sinkPage(v6, "reauthorize"))) } catch {
      opened = String(describing: error)
    }
    try? await reauthorized.settleLanes()
    row["reauthorizeOpen"] = opened
    row["reauthorizeSeparateBefore"] = reauthorized.separate != nil
    row["reauthorizeProfileCommits"] = reauthorized.commitCount
    let fewer = Array(wide.dropLast())
    reauthorized.review.configure(sites: fewer, route: .directFixture)
    let applied = ContinuousClock.now + .seconds(20)
    while reauthorized.review.isConfiguring || reauthorized.review.sites != fewer,
      reauthorized.review.problem == nil, ContinuousClock.now < applied
    {
      try await Task.sleep(for: .milliseconds(50))
    }
    row["reauthorizeApplied"] =
      reauthorized.review.sites == fewer && reauthorized.review.problem == nil
    row["reauthorizeProblem"] = reauthorized.review.problem ?? "none"
    row["reauthorizeSeparateAfter"] = reauthorized.separate != nil
    row["reauthorizeProfileCodes"] = codes(of: reauthorized.profile.id, since: began)
    await reauthorized.discardSeparate()
    reauthorized.close()

    // F9: the upload page opens in a separate profile; a staged file makes it hold private data.
    let uploading = session(name + "-upload", id: signedInID)
    try showSeededSites(uploading)
    try await configure(uploading, wide, .directFixture)
    let file = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      .appendingPathComponent("tmp/memoshi-s3-d136-upload.txt")
    try Data("Owned Memoshi S3 upload fixture.\n".utf8).write(to: file, options: .atomic)
    var uploadClick = "notRun"
    var lane: BrowserSession?
    do {
      try await uploading.navigateForSuite(
        try url(sinkPage(v6, "upload", mode: "upload", next: sinkPage(v6, "uploaded"))))
      try await uploading.settleLanes()
      lane = uploading.separate
      guard let lane else { throw ControlFailure(message: "the upload page opened in no separate") }
      let snapshot = try await lane.snapshotForSuite()
      guard
        let picker = snapshot.elements.first(where: {
          $0.role == "button" && $0.name == "Test file"
        }),
        let submit = snapshot.elements.first(where: {
          $0.role == "button" && $0.name == "Upload file"
        })
      else { throw ControlFailure(message: "upload form not in snapshot") }
      try await lane.review.stageUpload(
        ref: snapshot.reference(to: picker), urls: [file], userConfirmedDisclosure: true)
      // The person confirms the next private-data form, as the panel's button does.
      uploading.review.confirmNextPrivateForm()
      let outcome = try await lane.performForSuite(.click(snapshot.reference(to: submit), .script))
      uploadClick = outcome.error?.rawValue ?? "completed"
      let loaded = ContinuousClock.now + .seconds(10)
      while lane.isLoading, ContinuousClock.now < loaded {
        try await Task.sleep(for: .milliseconds(100))
      }
      try await Task.sleep(for: .seconds(1))
    } catch { uploadClick = String(describing: error) }
    row["uploadClick"] = uploadClick
    if let lane {
      row["uploadSeparateID"] = lane.profile.id.uuidString.lowercased()
      row["uploadSeparateCodes"] = codes(of: lane.profile.id, since: began)
    }
    await uploading.discardSeparate()
    uploading.close()
    try? FileManager.default.removeItem(at: file)

    let framing = session(name + "-frame")
    let embedded = try profileOrigin("B")
    try await configure(framing, try fixtureSites([a, embedded]), .directFixture)
    row["framePrivateAtConfiguration"] = framing.review.privateData
    var frameLoad = "loaded"
    do {
      try await framing.navigateForSuite(
        try url(
          sinkPage(a, "cookieframe", mode: "cookieframe", next: sinkPage(embedded, "embedded"))))
    } catch { frameLoad = String(describing: error) }
    // The frame's own navigation follows the page's commit.
    try await Task.sleep(for: .seconds(2))
    row["frameLoad"] = frameLoad
    row["frameProfileCodes"] = codes(of: framing.profile.id, since: began)
    framing.close()
    record(row, start: start)
  }

  /// What the T10 crash child left: the throwaway profile its lists belong to, and how it died
  /// and what that profile was, for the analyzer.
  private struct CrashedChild {
    let profile: UUID
    let facts: [String: Any]
  }

  /// Spawns this binary as the crash child and waits, bounded, for its death. A child that
  /// outlives the deadline is killed, and one that ended any way but by SIGKILL or left no
  /// complete marker fails the scenario.
  private func spawnCrashChild() async throws -> CrashedChild {
    guard let executable = Bundle.main.executableURL else {
      throw ControlFailure(message: "no executable for the crash child")
    }
    let marker = output.appendingPathComponent(CrashChild.markerName)
    guard !FileManager.default.fileExists(atPath: marker.path) else {
      throw ControlFailure(message: "a crash child marker already exists")
    }
    // The child writes this run's nonce into its marker: a marker without it is not its own.
    let nonce = UUID().uuidString
    let process = Process()
    process.executableURL = executable
    process.arguments = Array(CommandLine.arguments.dropFirst()) + [CrashChild.mode, nonce]
    try process.run()
    let deadline = ContinuousClock.now + .seconds(60)
    while process.isRunning, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(100))
    }
    if process.isRunning {
      Darwin.kill(process.processIdentifier, SIGKILL)
      process.waitUntilExit()
      throw ControlFailure(message: "crash child outlived its 60 s deadline and was killed")
    }
    process.waitUntilExit()
    guard process.terminationReason == .uncaughtSignal, process.terminationStatus == SIGKILL else {
      let how = process.terminationReason == .exit ? "exit status" : "signal"
      throw ControlFailure(
        message: "crash child ended by \(how) \(process.terminationStatus), not by SIGKILL")
    }
    let object =
      try JSONSerialization.jsonObject(with: Data(contentsOf: marker)) as? [String: Any] ?? [:]
    guard let id = object["profile"] as? String, let profile = UUID(uuidString: id),
      let page = object["page"] as? String, let nonPersistent = object["nonPersistent"] as? Bool,
      let lockdown = object["lockdown"] as? Bool
    else { throw ControlFailure(message: "crash child left no complete marker") }
    guard object["nonce"] as? String == nonce else {
      throw ControlFailure(message: "the crash child marker is not this child's")
    }
    return CrashedChild(
      profile: profile,
      facts: [
        "terminationSignal": Int(process.terminationStatus), "page": page,
        "nonPersistent": nonPersistent, "lockdown": lockdown, "markerNonceMatched": true,
      ])
  }

  /// A crash or a quit while a separate profile is open leaves its compiled lists. Lists are
  /// planted for a profile that no longer exists and for a saved one; then a lab is created as
  /// at the next start, with only the saved profile in its list, and its startup sweep runs.
  /// T10: a real app process (`CrashChild`) dies by SIGKILL while its throwaway profile shows
  /// an owned page; the parent records the profile and sweeps it at the next start.
  private func ruleListSweep() async throws {
    let start = Date().timeIntervalSince1970
    let crash = try await spawnCrashChild()
    let crashed = crash.profile
    let orphan = UUID()
    let saved = UUID()
    func lists(_ id: UUID) -> [String] {
      [
        BrowserNetworkBoundary.routeListIdentifier(profile: id),
        BrowserNetworkBoundary.blockAllIdentifier(profile: id),
      ]
    }
    let rules = try BrowserContentRuleStore.appContainer()
    let json = try BrowserNetworkBoundary.allowlistJSON(origins: [])
    for identifier in lists(orphan) + lists(saved) {
      _ = try await rules.compile(identifier: identifier, json: json)
    }
    let before = Set(await rules.identifiers())
    guard let bundle = Bundle.main.bundleIdentifier,
      let defaults = UserDefaults(suiteName: bundle + ".sweep")
    else { throw ControlFailure(message: "sweep defaults refused") }
    defaults.set(
      try JSONEncoder().encode([
        BrowserReviewProfile(id: saved, name: "Saved", createdAt: Date(), probe: nil)
      ]), forKey: "browser-review.profiles")
    let nextStart = BrowserReviewLab(defaults: defaults)
    let swept = await nextStart.startupSweep?.value ?? []
    let after = Set(await rules.identifiers())
    for identifier in lists(saved) { rules.remove(identifier: identifier) }
    defaults.removePersistentDomain(forName: bundle + ".sweep")
    record(
      [
        "name": "product-rule-list-sweep", "kind": "product", "gateway": [] as [Any],
        "orphanListsBefore": lists(orphan).filter(before.contains).count,
        "orphanListsAfter": lists(orphan).filter(after.contains).count,
        "keptListsAfter": lists(saved).filter(after.contains).count, "swept": swept,
        // T10: the child died by SIGKILL with its throwaway profile live; the relaunch's startup
        // sweep must remove its lists and leave no rule-list file for its profile.
        "crashChild": crash.facts,
        "crashListsBefore": lists(crashed).filter(before.contains).count,
        "crashListsAfter": lists(crashed).filter(after.contains).count,
        "crashFilesLeft":
          (try? FileManager.default.contentsOfDirectory(atPath: rules.directory.path))?
          .filter { $0.lowercased().contains(crashed.uuidString.lowercased()) }
          ?? ["storeUnreadable"],
      ], start: start)
  }

  private func cookieCount(_ store: WKWebsiteDataStore?) async -> Int {
    guard let store else { return -1 }
    return await store.httpCookieStore.allCookies().count
  }

  /// Files under this owned home holding any of `markers`, as UTF-8 or UTF-16 text.
  private func scanHome(for markers: [String]) -> [String: [String]] {
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
    var found: [String: [String]] = [:]
    let forms = markers.map { marker in
      (
        marker,
        [Data(marker.utf8)]
          + [String.Encoding.utf16LittleEndian, .utf16BigEndian].compactMap {
            marker.data(using: $0)
          }
      )
    }
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
    guard let walker = FileManager.default.enumerator(at: home, includingPropertiesForKeys: keys)
    else { return found }
    for case let url as URL in walker {
      guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
        (values.fileSize ?? 0) <= 64 << 20,
        let data = try? Data(contentsOf: url, options: .mappedIfSafe)
      else { continue }
      for (marker, encodings) in forms
      where encodings.contains(where: { data.range(of: $0) != nil }) {
        found[marker, default: []].append(
          String(url.standardizedFileURL.path.dropFirst(home.path.count)))
      }
    }
    return found
  }

  /// Compiled rule-list files still named for any of `ids` in the app's rule store.
  private func ruleListsLeft(for ids: Set<UUID>) -> [String] {
    guard let directory = try? BrowserContentRuleStore.appContainer().directory,
      let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
    else { return ["ruleStoreUnreadable"] }
    let lowered = ids.map { $0.uuidString.lowercased() }
    return names.filter { name in lowered.contains { name.lowercased().contains($0) } }.sorted()
  }

  // MARK: Evidence

  /// Closes `session` and adds its gateway decisions and recorded codes from `lab` (the
  /// driver's own unless the scenario made one).
  private func close(
    _ session: BrowserSession, _ row: [String: Any], in lab: BrowserReviewLab? = nil
  ) -> [String: Any] {
    let lab = lab ?? self.lab
    session.close()
    var row = row
    let bot = "browser-review-" + session.profile.id.uuidString.lowercased()
    row["gateway"] = (try? object(lab.evidence.contents.gateway.filter { $0.bot == bot })) ?? []
    row["configurationCodes"] = lab.evidence.contents.decisions
      .filter { $0.profileID == session.profile.id }
      .map { "\($0.operation):\($0.allowed):\($0.code)" }
    return row
  }

  private func receipts() async throws -> Int {
    var request = URLRequest(url: try fixtureURL("/receipts.json"))
    request.timeoutInterval = 5
    let (bytes, _) = try await http.data(for: request)
    let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
    let requests = object?["requests"] as? [String: [String: Any]] ?? [:]
    return requests.filter { $0.key.hasPrefix("GET /no-bypass/") }.values
      .reduce(0) { $0 + ($1["requests"] as? Int ?? 0) }
  }

  private func record(_ row: [String: Any], start: TimeInterval) {
    var row = row
    row["start"] = start
    row["end"] = Date().timeIntervalSince1970
    scenarios.append(row)
    try? write("timeline.json", ["scenarios": scenarios])
  }

  private func object<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
  }

  private func write(_ name: String, _ object: [String: Any]) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
      .write(to: output.appendingPathComponent(name), options: .atomic)
  }

  private func finish() {
    window?.contentView = nil
    window?.close()
    do {
      try write(
        "timeline.json",
        [
          "schema": "memoshi.s3-no-bypass-control/1", "run": run,
          "scenarios": scenarios, "failures": failures, "realSitesRequested": false,
          "only": Self.scenarioFilter.map { $0.sorted() as Any } ?? NSNull(),
        ])
    } catch {
      FileHandle.standardError.write(Data("control could not retain its timeline\n".utf8))
      Darwin.exit(2)
    }
    http.invalidateAndCancel()
    Darwin.exit(failures.isEmpty ? 0 : 1)
  }
}

/// The gateway separate-profile scenario's names (run-control.py's `GATEWAY_*`), under the
/// reserved `.test` top-level domain (a task suite refuses `.invalid` sites). None resolves
/// anywhere; only `OwnedGatewayRoute` answers for the first three.
private enum GatewayHosts {
  /// The bot's signed-in site (the cookie sink's A).
  static let bot = "bot.d136.memoshi.test"
  /// The registrable domain the bot's site and `sameSite` share, which its cookies name.
  static let botDomain = "d136.memoshi.test"
  /// Another host of the same site (A2).
  static let sameSite = "www.d136.memoshi.test"
  /// Another site (B).
  static let other = "other.d136.memoshi-other.test"
  /// A site no grant names.
  static let ungranted = "ungranted.d136.memoshi-third.test"
}

/// The gateway separate-profile scenario's owned route: the product's `BrowserGateway` on an
/// `EgressGateway` built with its test seam, as `EgressWebKitGatewayTests` builds one. Each host
/// in `hosts` resolves to a fixed public address, and only the connection to that address is
/// then delivered to its owned loopback listener: every request still meets the gateway's name,
/// list and address checks. Any other name fails to resolve and any other address is delivered
/// to a closed loopback port, so nothing leaves this Mac. Armed, it refuses the next store it
/// is applied to, which is a separate profile's opening (D136 review F5).
@MainActor
private final class OwnedGatewayRoute: BrowserReviewGateway {
  struct Target: Sendable {
    /// The public address the gateway resolves the host to and checks.
    let address: String
    /// The owned loopback listener a connection to that address is delivered to.
    let port: Int
  }

  /// The code an armed route's refusal records, and the F5 step expects.
  static let refusal = "controlRefusedSeparateGateway"
  private let gateway: BrowserGateway
  /// Set by the driver: the next `apply` fails, once.
  var refusesNextApply = false
  private(set) var refusedApplies = 0

  private init(gateway: BrowserGateway) { self.gateway = gateway }

  static func start(
    profileID: UUID, sites: [BrowserAuthorization.Site], hosts: [String: Target]
  ) async throws -> OwnedGatewayRoute {
    let closed = try SocketAddress(ipAddress: "127.0.0.1", port: 1)
    var delivered: [String: SocketAddress] = [:]
    for target in hosts.values {
      delivered[target.address] = try SocketAddress(ipAddress: "127.0.0.1", port: target.port)
    }
    let deliveries = delivered
    let gateway = try await BrowserGateway.start(profileID: profileID, sites: sites) {
      try await EgressGateway.start(
        decisionLog: nil,
        resolve: { host, port in
          guard let target = hosts[host] else { throw EgressResolver.Failure() }
          return [try SocketAddress(ipAddress: target.address, port: port)]
        },
        route: { address in address.ipAddress.flatMap { deliveries[$0] } ?? closed })
    }
    return OwnedGatewayRoute(gateway: gateway)
  }

  var isClosed: Bool { gateway.isClosed }
  var decisionWindow: (decisions: [EgressDecision], recorded: Int) { gateway.decisionWindow }

  func apply(to store: WKWebsiteDataStore) throws {
    if refusesNextApply {
      refusesNextApply = false
      refusedApplies += 1
      throw BrowserSessionReview.ConfigurationFailure(code: Self.refusal)
    }
    try gateway.apply(to: store)
  }

  func close() async { await gateway.close() }
}

/// T10: the child a crash sweep spawns (`crash-open-separate`). It creates no lab, so no
/// startup sweep runs in it. It opens a throwaway profile as the product opens a separate one
/// on the owned-fixture route: the profile's route and block-all lists compiled into the app's
/// rule store, and a non-persistent store under Lockdown with the route list installed. Once an
/// owned fixture page has loaded there, it writes the profile to its marker and kills itself
/// with SIGKILL, so the profile dies live with no cleanup. Any error ends it with exit status 1,
/// which the parent records as a failure.
@MainActor
private final class CrashChild: NSObject, NSApplicationDelegate {
  static let mode = "crash-open-separate"
  static let markerName = "crash-profile.json"
  let output: URL
  let fixture: String
  /// The parent's nonce for this run, written into the marker.
  let nonce: String
  var window: NSWindow?

  init(_ args: [String]) throws {
    guard args.count == 10, args[8] == Self.mode, UUID(uuidString: args[9]) != nil else {
      throw ControlFailure(message: "crash child arguments refused")
    }
    output = URL(fileURLWithPath: args[1], isDirectory: true)
    fixture = args[3]
    nonce = args[9]
    try requireOwnedIsolation(fixture: fixture, bundle: args[6])
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    Task {
      do { try await openAndDie() } catch {
        FileHandle.standardError.write(Data("crash child failed: \(error)\n".utf8))
        Darwin.exit(1)
      }
    }
  }

  private func openAndDie() async throws {
    let profile = UUID()
    let rules = try BrowserContentRuleStore.appContainer()
    let route = try await rules.compile(
      identifier: BrowserNetworkBoundary.routeListIdentifier(profile: profile),
      json: BrowserNetworkBoundary.allowlistJSON(origins: [fixture]))
    _ = try await rules.compile(
      identifier: BrowserNetworkBoundary.blockAllIdentifier(profile: profile),
      json: BrowserNetworkBoundary.allowlistJSON(origins: []))
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.userContentController.add(route)
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    BrowserNetworkBoundary.applyLockdown(to: configuration)
    let view = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 900, height: 650), configuration: configuration)
    // Read back from the created view, as the product does.
    let lockdown = BrowserNetworkBoundary.lockdownIsActive(on: view)
    let nonPersistent = !view.configuration.websiteDataStore.isPersistent
    guard lockdown, nonPersistent else {
      throw ControlFailure(message: "the throwaway profile is not non-persistent under Lockdown")
    }
    let host = NSWindow(
      contentRect: NSRect(x: 120, y: 120, width: 900, height: 650), styleMask: [.titled],
      backing: .buffered, defer: false)
    host.title = "Owned S3 crash child"
    host.isReleasedWhenClosed = false
    host.contentView = view
    host.orderFront(nil)
    window = host
    guard let page = URL(string: fixture + "/page2") else {
      throw ControlFailure(message: "invalid fixture page URL")
    }
    view.load(URLRequest(url: page))
    // Bounded: the owned page must have loaded in the live throwaway profile before the kill.
    let deadline = ContinuousClock.now + .seconds(20)
    var state: String?
    while state != "complete /page2" {
      guard ContinuousClock.now < deadline else {
        throw ControlFailure(
          message: "the throwaway profile's page did not load: \(state ?? "none")")
      }
      try await Task.sleep(for: .milliseconds(100))
      state =
        try? await view.evaluateJavaScript(
          "document.readyState + ' ' + location.pathname", in: nil, contentWorld: .page) as? String
    }
    let marker: [String: Any] = [
      "profile": profile.uuidString, "page": view.url?.absoluteString ?? "",
      "nonPersistent": nonPersistent, "lockdown": lockdown, "nonce": nonce,
    ]
    try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])
      .write(to: output.appendingPathComponent(Self.markerName), options: .atomic)
    raise(SIGKILL)
  }
}

/// The isolation both the driver and its crash child require before WebKit starts: an owned
/// loopback fixture origin, this carrier's own bundle and the owned scratch home.
@MainActor
private func requireOwnedIsolation(fixture: String, bundle: String) throws {
  guard URL(string: fixture)?.host() == "127.0.0.1",
    BrowserAuthorization.canonicalOrigin(fixture) == fixture,
    Bundle.main.bundleIdentifier == bundle, bundle.hasPrefix("com.memoshi.s3-no-bypass."),
    URL(fileURLWithPath: NSHomeDirectory()).lastPathComponent == "home",
    URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent().lastPathComponent
      .hasPrefix("S3NoBypass-")
  else { throw ControlFailure(message: "owned home, bundle or fixture isolation refused") }
}

@main
@MainActor
private struct S3NoBypassControl {
  static func main() {
    do {
      // The crash child (T10) is this binary run with one more argument; it never creates the
      // driver or its lab.
      let delegate: any NSApplicationDelegate
      if CommandLine.arguments.count > 8, CommandLine.arguments[8] == CrashChild.mode {
        delegate = try CrashChild(CommandLine.arguments)
      } else {
        delegate = try ControlDriver(CommandLine.arguments)
      }
      let app = NSApplication.shared
      app.setActivationPolicy(.regular)
      app.delegate = delegate
      withExtendedLifetime(delegate) { app.run() }
    } catch {
      FileHandle.standardError.write(Data(("control setup refused: \(error)\n").utf8))
      Darwin.exit(2)
    }
  }
}
