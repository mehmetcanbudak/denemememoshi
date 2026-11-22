// Owned iOS Simulator carrier driver for the D101 browser boundary (spike only; never shipped).
// Compiled by run-sim.py together with the unmodified product apps/shared/MobileBrowserReview*.swift
// files. Only sink accepts, owned-server accepts and gateway decision counts are network evidence;
// page-side outcomes are informational. No real sites, accounts or credentials are involved.
import AppCore
import Darwin
import Foundation
import Synchronization
import UIKit
import WebKit

@main
final class S3SimAppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(
      name: "Default", sessionRole: connectingSceneSession.role)
    configuration.delegateClass = S3SimSceneDelegate.self
    return configuration
  }
}

final class S3SimSceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var started = false

  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let scene = scene as? UIWindowScene, !started else { return }
    started = true
    let window = UIWindow(windowScene: scene)
    let root = UIViewController()
    root.view.backgroundColor = .systemBackground
    window.rootViewController = root
    window.makeKeyAndVisible()
    self.window = window
    let host: UIView = root.view
    Task { await S3SimDriver(host: host).runAndExit() }
  }
}

// MARK: - Owned loopback listeners (the only network evidence besides gateway decisions)

private final class Counter: Sendable {
  let value = Mutex<[String: Int]>([:])
  func add(_ key: String) { value.withLock { $0[key, default: 0] += 1 } }
  var snapshot: [String: Int] { value.withLock { $0 } }
}

private enum Socket {
  /// Binds a TCP listener on 127.0.0.1 or ::1 (v6-only) at `port` (0 = ephemeral).
  static func listener(ipv6: Bool, port: UInt16) -> (Int32, UInt16)? {
    let fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var one: Int32 = 1
    var status: Int32
    if ipv6 {
      _ = setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &one, socklen_t(MemoryLayout<Int32>.size))
      var address = sockaddr_in6()
      address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
      address.sin6_family = sa_family_t(AF_INET6)
      address.sin6_addr = in6addr_loopback
      address.sin6_port = port.bigEndian
      status = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
        }
      }
    } else {
      var address = sockaddr_in()
      address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
      address.sin_family = sa_family_t(AF_INET)
      address.sin_addr.s_addr = inet_addr("127.0.0.1")
      address.sin_port = port.bigEndian
      status = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
    }
    guard status == 0, listen(fd, 64) == 0 else {
      close(fd)
      return nil
    }
    var storage = sockaddr_storage()
    var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
    _ = withUnsafeMutablePointer(to: &storage) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
    }
    let bound = withUnsafePointer(to: &storage) { pointer -> UInt16 in
      ipv6
        ? pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_port }
        : pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_port }
    }
    return (fd, UInt16(bigEndian: bound))
  }

  /// Binds 127.0.0.1 and ::1 on the same port number so every loopback spelling of that port,
  /// whichever family it resolves to, lands on this listener pair.
  static func pair() -> (Int32, Int32, UInt16)? {
    for _ in 0..<64 {
      guard let (fd4, port) = listener(ipv6: false, port: 0) else { return nil }
      if let (fd6, _) = listener(ipv6: true, port: port) { return (fd4, fd6, port) }
      close(fd4)
    }
    return nil
  }
}

/// Counts accepted TCP connections; never reads or answers them.
private final class LoopbackSink: @unchecked Sendable {
  let label: String
  let port: UInt16
  let target: String
  private let sources: [any DispatchSourceRead]
  private let counter: Counter

  private init(
    label: String, port: UInt16, target: String, sources: [any DispatchSourceRead],
    counter: Counter
  ) {
    self.label = label
    self.port = port
    self.target = target
    self.sources = sources
    self.counter = counter
  }

  var accepted: Int { counter.snapshot.values.reduce(0, +) }
  var byFamily: [String: Int] { counter.snapshot }

  /// Every loopback spelling the D101 deny-local and route lists must stop.
  static let spellings: [(String, @Sendable (UInt16) -> String)] = [
    ("ipv4", { "http://127.0.0.1:\($0)/" }),
    ("ipv6", { "http://[::1]:\($0)/" }),
    ("localhost", { "http://localhost:\($0)/" }),
    ("decimal2130706433", { "http://2130706433:\($0)/" }),
    ("short127.1", { "http://127.1:\($0)/" }),
    ("v4mapped", { "http://[::ffff:127.0.0.1]:\($0)/" }),
    ("userinfo", { "http://user@127.0.0.1:\($0)/" }),
    ("localhostDot", { "http://localhost.:\($0)/" }),
  ]

  static func start(label: String, spelling: (UInt16) -> String) throws -> LoopbackSink {
    guard let (fd4, fd6, port) = Socket.pair() else { throw POSIXError(.EADDRNOTAVAIL) }
    let counter = Counter()
    let queue = DispatchQueue(label: "s3sim.sink." + label)
    let sources = [(fd4, "v4"), (fd6, "v6")].map { fd, family -> any DispatchSourceRead in
      let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
      source.setEventHandler {
        let client = accept(fd, nil, nil)
        if client >= 0 {
          counter.add(family)
          close(client)
        }
      }
      source.setCancelHandler { close(fd) }
      source.resume()
      return source
    }
    return LoopbackSink(
      label: label, port: port, target: spelling(port), sources: sources, counter: counter)
  }

  func stop() { for source in sources { source.cancel() } }
}

/// The owned, CSP-free origin served on 127.0.0.1 that the counting fixture route loads. Counts
/// every accepted connection and every parsed request path.
private final class CountingServer: @unchecked Sendable {
  let port: UInt16
  private let source: any DispatchSourceRead
  private let accepts: Counter
  private let paths: Counter

  private init(port: UInt16, source: any DispatchSourceRead, accepts: Counter, paths: Counter) {
    self.port = port
    self.source = source
    self.accepts = accepts
    self.paths = paths
  }

  var accepted: Int { accepts.snapshot["tcp", default: 0] }
  var requests: [String: Int] { paths.snapshot }

  static let page =
    "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>S3 iOS owned origin</title></head><body>owned counting origin</body></html>"

  static func start() throws -> CountingServer {
    guard let (fd, port) = Socket.listener(ipv6: false, port: 0) else {
      throw POSIXError(.EADDRNOTAVAIL)
    }
    let accepts = Counter()
    let paths = Counter()
    let queue = DispatchQueue(label: "s3sim.server")
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler {
      let client = accept(fd, nil, nil)
      guard client >= 0 else { return }
      accepts.add("tcp")
      DispatchQueue.global().async { serve(client, paths: paths) }
    }
    source.setCancelHandler { close(fd) }
    source.resume()
    return CountingServer(port: port, source: source, accepts: accepts, paths: paths)
  }

  private static func serve(_ client: Int32, paths: Counter) {
    defer { close(client) }
    var one: Int32 = 1
    _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: 3, tv_usec: 0)
    _ = setsockopt(
      client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var request = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while request.count < 16_384, request.range(of: Data("\r\n\r\n".utf8)) == nil {
      let count = read(client, &buffer, buffer.count)
      guard count > 0 else { break }
      request.append(contentsOf: buffer[0..<count])
    }
    let line = String(decoding: request.prefix(1024), as: UTF8.self)
      .components(separatedBy: "\r\n")[0].split(separator: " ")
    let path = line.count == 3 ? String(line[0]) + " " + String(line[1]) : "unparsed"
    paths.add(path)
    let body = path == "GET /" ? page : "ok"
    let type = path == "GET /" ? "text/html; charset=utf-8" : "text/plain"
    let response = Data(
      ("HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.utf8.count)\r\n"
        + "Cache-Control: no-store\r\nConnection: close\r\n\r\n" + body).utf8)
    response.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      _ = write(client, base, raw.count)
    }
  }

  func stop() { source.cancel() }
}

// MARK: - A plain web view for controls and cross-origin blob checks

@MainActor
private final class PlainProbe: NSObject, WKNavigationDelegate {
  let webView: WKWebView
  private var loading: CheckedContinuation<Void, any Error>?

  init(lists: [WKContentRuleList], lockdown: Bool, host: UIView) {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    for list in lists { configuration.userContentController.add(list) }
    if lockdown { BrowserNetworkBoundary.applyLockdown(to: configuration) }
    webView = WKWebView(
      frame: CGRect(x: 0, y: 400, width: 390, height: 200), configuration: configuration)
    super.init()
    webView.navigationDelegate = self
    host.addSubview(webView)
  }

  func load(base: URL) async throws {
    defer { loading = nil }
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      loading = continuation
      webView.loadHTMLString(S3SimDriver.shell, baseURL: base)
    }
  }

  func close() {
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.removeFromSuperview()
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    loading?.resume()
    loading = nil
  }

  func webView(
    _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error
  ) {
    loading?.resume(throwing: error)
    loading = nil
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: any Error
  ) {
    loading?.resume(throwing: error)
    loading = nil
  }
}

// MARK: - Driver

@MainActor
final class S3SimDriver {
  enum Status: String { case pass, fail, notExercised }

  static let shell =
    "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>S3 iOS probe</title></head><body>probe</body></html>"

  static let probeScript = """
    const wait = (ms) => new Promise((r) => setTimeout(r, ms));
    const bounded = (p) => Promise.race([p.then(() => 'ok', () => 'error'), wait(1500).then(() => 'timeout')]);
    const out = [];
    for (const url of targets) {
      const f = await bounded(fetch(url + 'fetch', { mode: 'no-cors', cache: 'no-store' }));
      const i = await bounded(new Promise((res, rej) => { const im = new Image(); im.onload = res; im.onerror = rej; im.src = url + 'img'; }));
      const w = await bounded(new Promise((res, rej) => { try { const s = new WebSocket(url.replace(/^http/, 'ws') + 'ws'); s.onopen = res; s.onerror = rej; } catch (e) { rej(e); } }));
      out.push({ url, fetch: f, img: i, ws: w });
    }
    await wait(500);
    return JSON.stringify(out);
    """

  static let featureScript =
    "return JSON.stringify({rtc: typeof RTCPeerConnection, webTransport: typeof WebTransport});"

  static let blobScript = """
    const attempt = async (f) => { try { await f(); return 'ok'; } catch { return 'error'; } };
    const file = new File(['owned canary'], 'owned.txt');
    const text = await attempt(() => file.text());
    const url = URL.createObjectURL(file);
    const fetched = await attempt(async () => (await fetch(url)).text());
    return 'text:' + text + ',fetch:' + fetched;
    """

  static let fetchScript = """
    const wait = (ms) => new Promise((r) => setTimeout(r, ms));
    return await Promise.race([fetch(target, { cache: 'no-store' }).then((r) => 'status:' + r.status, () => 'error'), wait(8000).then(() => 'timeout')]);
    """

  private let host: UIView
  private var checks: [[String: Any]] = []
  private var scenarios: [String: Any] = [:]
  private var sinks: [LoopbackSink] = []
  private let runID = UUID().uuidString.prefix(8).lowercased()

  init(host: UIView) { self.host = host }

  func runAndExit() async {
    var failure: String?
    do { try await run() } catch { failure = String(describing: error) }
    let counts = Dictionary(grouping: checks, by: { $0["status"] as? String ?? "?" })
      .mapValues(\.count)
    let result: [String: Any] = [
      "schema": "memoshi.s3.ios-simulator.v1",
      "runID": String(runID),
      "environment": [
        "system": UIDevice.current.systemName + " " + UIDevice.current.systemVersion,
        "model": UIDevice.current.model,
        "simulatorModel": ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "",
        "head": ProcessInfo.processInfo.environment["S3_HEAD"] ?? "",
        "bundle": Bundle.main.bundleIdentifier ?? "",
        "appTransportSecurity": Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity")
          as? [String: Any] ?? [:],
      ],
      "error": failure ?? NSNull(),
      "counts": counts,
      "checks": checks,
      "scenarios": scenarios,
    ]
    let name = "s3-ios-sim-result.json"
    do {
      let data = try JSONSerialization.data(
        withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
      let documents = try FileManager.default.url(
        for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      try data.write(to: documents.appendingPathComponent(name), options: .withoutOverwriting)
    } catch {
      print("S3SIM-WRITE-FAILED \(error)")
    }
    print("S3SIM-RESULT error=\(failure ?? "none") counts=\(counts)")
    fflush(stdout)
    exit(failure == nil ? 0 : 2)
  }

  private func check(_ name: String, _ status: Status, _ evidence: [String: Any]) {
    checks.append(["name": name, "status": status.rawValue, "evidence": evidence])
    print("S3SIM-CHECK \(status.rawValue) \(name)")
  }

  private var sinkTotals: [String: Int] {
    Dictionary(uniqueKeysWithValues: sinks.map { ($0.label, $0.accepted) })
  }

  private func evaluate(_ webView: WKWebView, _ script: String, _ arguments: [String: Any] = [:])
    async -> String
  {
    do {
      let value = try await webView.callAsyncJavaScript(
        script, arguments: arguments, in: nil, contentWorld: .page)
      return value as? String ?? "nonString"
    } catch { return "scriptError" }
  }

  /// Runs every loopback spelling against its own sink and returns per-spelling sink deltas.
  private func probeSinks(_ webView: WKWebView) async -> (deltas: [String: Int], page: String) {
    let before = sinkTotals
    let page = await evaluate(webView, Self.probeScript, ["targets": sinks.map(\.target)])
    try? await Task.sleep(for: .seconds(1))
    let after = sinkTotals
    var deltas: [String: Int] = [:]
    for sink in sinks {
      deltas[sink.label] = after[sink.label, default: 0] - before[sink.label, default: 0]
    }
    return (deltas, page)
  }

  private func observationCodes(_ session: MobileBrowserReviewSession) -> [String] {
    session.observations.map { $0.count == 0 ? $0.code : "\($0.code)#\($0.count)" }
  }

  private func awaitNavigation(_ session: MobileBrowserReviewSession, from mark: Int) async
    -> String
  {
    let deadline = ContinuousClock.now + .seconds(20)
    while ContinuousClock.now < deadline {
      let codes = session.observations.dropFirst(mark).map(\.code)
      if codes.contains("navigationFinishedObserved") { return "finished" }
      if codes.contains("navigationFailedNoAutomaticRetry") { return "failed" }
      try? await Task.sleep(for: .milliseconds(100))
    }
    return "timeout"
  }

  private func attach(_ webView: WKWebView, slot: Int) {
    webView.frame = CGRect(x: 0, y: 60 + slot * 10, width: 390, height: 300)
    host.addSubview(webView)
  }

  private func readBack(_ session: MobileBrowserReviewSession) -> [String: Any] {
    [
      "lockdownField": session.boundary.lockdown,
      "lockdownIsActive": BrowserNetworkBoundary.lockdownIsActive(on: session.webView),
      "denyLocal": session.boundary.denyLocal ?? NSNull(),
      "routeKind": session.boundary.route?.kind.rawValue ?? NSNull(),
      "routeOrigins": session.boundary.route?.origins ?? [],
      "gatewayApplied": session.boundary.gatewayApplied,
      "proxyConfigurations": session.webView.configuration.websiteDataStore.proxyConfigurations
        .count,
      "evidenceCode": session.boundary.evidenceCode,
      "boundaryDenial": session.boundaryDenial?.rawValue ?? NSNull(),
    ]
  }

  private func features(_ webView: WKWebView) async -> [String: String] {
    let json = await evaluate(webView, Self.featureScript)
    let decoded =
      (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: String] ?? [:]
    return decoded.isEmpty ? ["raw": json] : decoded
  }

  private func blobs(_ webView: WKWebView) async -> String {
    await evaluate(webView, Self.blobScript)
  }

  private func controlRun(base: String) async throws -> [String: Int] {
    let probe = PlainProbe(lists: [], lockdown: false, host: host)
    defer { probe.close() }
    guard let url = URL(string: base) else { throw URLError(.badURL) }
    try await probe.load(base: url)
    let feature = await features(probe.webView)
    let (deltas, page) = await probeSinks(probe.webView)
    let exercised = sinks.allSatisfy { deltas[$0.label, default: 0] > 0 }
    check(
      "positiveControl.plainWebView.\(base)", exercised ? .pass : .notExercised,
      [
        "sinkAcceptDeltas": deltas,
        "lockdownIsActive": BrowserNetworkBoundary.lockdownIsActive(
          on: probe.webView),
        "pageFeatures": feature, "pageOutcomes": page,
        "meaning": "plain WKWebView, no lists, no Lockdown; >0 accepts per spelling = exercised",
      ])
    return deltas
  }

  /// Product probe: every sink delta must be zero; spellings the matching control did not
  /// reach are reported as not exercised, never as passing. Neither are zero deltas from a
  /// probe that did not run: the script must report one outcome per sink target, from a
  /// document whose navigation finished. `extra` is evaluated after the probes.
  private func productProbe(
    _ name: String, webView: WKWebView, control: [String: Int], navigation: String,
    extra: () -> [String: Any] = { [:] }
  ) async {
    let (deltas, page) = await probeSinks(webView)
    let leaked = deltas.filter { $0.value > 0 }
    let unexercised = sinks.map(\.label).filter { control[$0, default: 0] == 0 }
    let outcomes = (try? JSONSerialization.jsonObject(with: Data(page.utf8))) as? [[String: Any]]
    let probed = navigation == "finished" && outcomes?.count == sinks.count
    let status: Status =
      !leaked.isEmpty ? .fail : unexercised.isEmpty && probed ? .pass : .notExercised
    var evidence: [String: Any] = [
      "sinkAcceptDeltas": deltas, "targets": sinks.map(\.target),
      "controlUnexercised": unexercised, "pageOutcomes": page,
      "navigation": navigation, "probeRan": probed,
    ]
    evidence.merge(extra()) { $1 }
    check(name, status, evidence)
  }

  private struct Mutation {
    let label: String
    let expected: String
    let apply: (inout BrowserNetworkBoundary.State) -> Void
  }

  /// Mutates the installed boundary, calls the real `load()` and `reload()`, and requires the
  /// exact refusal plus zero new owned-network effects; the original boundary is restored.
  private func failClosed(
    _ session: MobileBrowserReviewSession, route: String, mutations: [Mutation],
    effects: () -> [String: Int]
  ) async {
    let original = session.boundary
    for mutation in mutations {
      for operation in ["load", "reload"] {
        session.boundary = original
        mutation.apply(&session.boundary)
        session.problem = nil
        let mark = session.observations.count
        let before = effects()
        let sinkBefore = sinkTotals.values.reduce(0, +)
        if operation == "load" { session.load() } else { session.reload() }
        let problem = session.problem
        try? await Task.sleep(for: .milliseconds(1500))
        let after = effects()
        let sinkAfter = sinkTotals.values.reduce(0, +)
        let changed = after.filter { before[$0.key, default: 0] != $0.value }
        let started = session.observations.dropFirst(mark).map(\.code)
          .contains("provisionalStartObserved")
        let pass =
          problem == "networkBoundary." + mutation.expected && changed.isEmpty
          && sinkAfter == sinkBefore && !started
        check(
          "failClosed.\(route).\(mutation.label).\(operation)", pass ? .pass : .fail,
          [
            "problem": problem ?? NSNull(), "expected": "networkBoundary." + mutation.expected,
            "effectsBefore": before, "effectsAfter": after,
            "sinkAcceptDelta": sinkAfter - sinkBefore,
            "provisionalNavigationStarted": started,
          ])
      }
    }
    session.boundary = original
    session.problem = nil
  }

  private func run() async throws {
    for (label, spelling) in LoopbackSink.spellings {
      sinks.append(try LoopbackSink.start(label: label, spelling: spelling))
    }
    let server = try CountingServer.start()
    defer {
      server.stop()
      for sink in sinks { sink.stop() }
    }
    scenarios["sinks"] = sinks.map {
      ["label": $0.label, "port": Int($0.port), "target": $0.target]
    }

    // 1. Positive controls: the same probes from an unrestricted web view must reach every sink.
    let controlHTTP = try await controlRun(base: "http://control-\(runID).memoshi.invalid/")
    let controlHTTPS = try await controlRun(base: "https://control-\(runID).memoshi.invalid/")
    let afterControls = sinkTotals
    let unlocked = PlainProbe(lists: [], lockdown: false, host: host)
    if let url = URL(string: "http://control-\(runID).memoshi.invalid/") {
      try await unlocked.load(base: url)
    }
    let unlockedFeatures = await features(unlocked.webView)
    unlocked.close()
    check(
      "positiveControl.featuresWithoutLockdown",
      unlockedFeatures["rtc"] == "function" ? .pass : .notExercised,
      ["pageFeatures": unlockedFeatures, "meaning": "RTCPeerConnection exists without Lockdown"])

    // 2. Product loopback fixture route against the product MobileBrowserReviewFixture.
    let fixture = try await MobileBrowserReviewFixture.start()
    defer { fixture.close() }
    let fixtureOrigin = try fixture.origin
    let fixtureSite = try BrowserAuthorization.Site(
      origin: fixtureOrigin, interact: false, signIn: false, ownedFixture: true)
    let productFixture = try await MobileBrowserReviewSession.open(
      index: 1, site: fixtureSite, route: .loopbackFixture, broker: nil)
    defer { productFixture.close() }
    attach(productFixture.webView, slot: 0)
    let fixtureReadBack = readBack(productFixture)
    var mark = productFixture.observations.count
    productFixture.load()
    let fixtureLoad = await awaitNavigation(productFixture, from: mark)
    let fixtureTitle = await evaluate(productFixture.webView, "return document.title;")
    let fixtureFeatures = await features(productFixture.webView)
    check(
      "lockdown.loopbackFixture.productFixture",
      fixtureReadBack["lockdownField"] as? Bool == true
        && fixtureReadBack["lockdownIsActive"] as? Bool == true
        && fixtureFeatures["rtc"] == "undefined" && fixtureFeatures["webTransport"] == "undefined"
        ? .pass : .fail,
      ["readBack": fixtureReadBack, "pageFeatures": fixtureFeatures])
    check(
      "load.loopbackFixture.productFixture",
      fixtureLoad == "finished" && fixtureTitle == "Owned mobile browser fixture"
        && fixtureReadBack["denyLocal"] is NSNull
        && fixtureReadBack["routeKind"] as? String == "ownedFixture" ? .pass : .fail,
      ["navigation": fixtureLoad, "title": fixtureTitle, "origin": fixtureOrigin])
    // The product fixture page carries a connect-src 'none' CSP, so probes run in an
    // app-supplied document with the same granted origin in the same session web view.
    if let base = URL(string: fixtureOrigin + "/") {
      mark = productFixture.observations.count
      productFixture.webView.loadHTMLString(Self.shell, baseURL: base)
      let shellLoad = await awaitNavigation(productFixture, from: mark)
      await productProbe(
        "routeLists.loopbackFixture.productFixture.sinks", webView: productFixture.webView,
        control: controlHTTP, navigation: shellLoad)
      let blob = await blobs(productFixture.webView)
      check(
        "blob.loopbackFixture.productFixture.ownOrigin",
        blob == "text:ok,fetch:ok" ? .pass : .fail, ["page": blob, "origin": fixtureOrigin])
    }
    scenarios["productFixture"] = ["observations": observationCodes(productFixture)]

    // 3. Loopback fixture route against the owned CSP-free counting origin: real load(), probes
    //    from the loaded page, then fail-closed load()/reload() with zero new server accepts.
    let ownedOrigin = "http://127.0.0.1:\(server.port)"
    let ownedSite = try BrowserAuthorization.Site(
      origin: ownedOrigin, interact: false, signIn: false, ownedFixture: true)
    let owned = try await MobileBrowserReviewSession.open(
      index: 2, site: ownedSite, route: .loopbackFixture, broker: nil)
    defer { owned.close() }
    attach(owned.webView, slot: 1)
    let ownedReadBack = readBack(owned)
    let acceptsBeforeLoad = server.accepted
    mark = owned.observations.count
    owned.load()
    let ownedLoad = await awaitNavigation(owned, from: mark)
    let ownedTitle = await evaluate(owned.webView, "return document.title;")
    let ownedFeatures = await features(owned.webView)
    check(
      "lockdown.loopbackFixture.ownedOrigin",
      ownedReadBack["lockdownField"] as? Bool == true
        && ownedReadBack["lockdownIsActive"] as? Bool == true
        && ownedFeatures["rtc"] == "undefined" && ownedFeatures["webTransport"] == "undefined"
        ? .pass : .fail,
      ["readBack": ownedReadBack, "pageFeatures": ownedFeatures])
    check(
      "load.loopbackFixture.ownedOrigin",
      ownedLoad == "finished" && ownedTitle == "S3 iOS owned origin"
        && server.accepted > acceptsBeforeLoad ? .pass : .fail,
      [
        "navigation": ownedLoad, "title": ownedTitle,
        "serverAcceptsDelta":
          server.accepted - acceptsBeforeLoad, "serverRequests": server.requests,
      ])
    await productProbe(
      "routeLists.loopbackFixture.ownedOrigin.sinks", webView: owned.webView, control: controlHTTP,
      navigation: ownedLoad)
    let sameBefore = server.requests["GET /same-origin", default: 0]
    let same = await evaluate(
      owned.webView, Self.fetchScript, ["target": ownedOrigin + "/same-origin"])
    let sameDelta = server.requests["GET /same-origin", default: 0] - sameBefore
    check(
      "routeLists.loopbackFixture.ownedOrigin.exactOriginReachable",
      sameDelta == 1 ? .pass : .fail,
      ["page": same, "serverRequestDelta": sameDelta, "meaning": "probe JS runs; exemption works"])
    let ownedBlob = await blobs(owned.webView)
    check(
      "blob.loopbackFixture.ownedOrigin.ownOrigin",
      ownedBlob == "text:ok,fetch:ok" ? .pass : .fail, ["page": ownedBlob, "origin": ownedOrigin])
    let ownedRoute = owned.boundary.route
    await failClosed(
      owned, route: "loopbackFixture",
      mutations: [
        Mutation(label: "lockdownRemoved", expected: "lockdownMissing") { $0.lockdown = false },
        Mutation(label: "routeRemoved", expected: "routeRulesMissing") { $0.route = nil },
        Mutation(label: "gatewayClaimedOnFixture", expected: "originOutsideRoute") {
          $0.gatewayApplied = true
        },
        Mutation(label: "originNotInRoute", expected: "originOutsideRoute") {
          $0.route = ownedRoute.map { .init(identifier: $0.identifier, kind: $0.kind, origins: []) }
        },
        Mutation(label: "gatewayKindWithoutDenyLocal", expected: "denyLocalMissing") {
          $0.route = ownedRoute.map {
            .init(identifier: $0.identifier, kind: .gateway, origins: $0.origins)
          }
        },
        Mutation(label: "emptyState", expected: "lockdownMissing") {
          $0 = BrowserNetworkBoundary.State()
        },
      ],
      effects: { ["serverAccepts": server.accepted] })
    // Restored boundary: reload() must reach the owned server, proving the refusals above were
    // the boundary and not an unreachable server.
    let acceptsBeforeReload = server.accepted
    mark = owned.observations.count
    owned.reload()
    let reloadOutcome = await awaitNavigation(owned, from: mark)
    check(
      "failClosed.loopbackFixture.restoredReloadReachesServer",
      reloadOutcome == "finished" && server.accepted > acceptsBeforeReload ? .pass : .fail,
      [
        "navigation": reloadOutcome, "serverAcceptsDelta": server.accepted - acceptsBeforeReload,
        "problem": owned.problem ?? NSNull(),
      ])
    scenarios["ownedOrigin"] = [
      "observations": observationCodes(owned), "serverRequests": server.requests,
      "serverAccepts": server.accepted,
    ]

    // 4. Authenticated gateway route with a never-real granted origin. The gateway accepts only
    //    https origins (MobileBrowserReviewGateway.start), so the grant is https.
    let gatewayOrigin = "https://s3sim-\(runID).memoshi.invalid"
    let gatewaySite = try BrowserAuthorization.Site(
      origin: gatewayOrigin, interact: false, signIn: false, ownedFixture: false)
    let gateway = try await MobileBrowserReviewSession.open(
      index: 3, site: gatewaySite, route: .authenticatedGateway, broker: nil)
    defer { gateway.close() }
    attach(gateway.webView, slot: 2)
    let gatewayReadBack = readBack(gateway)
    func decisions() -> [String: Int] {
      let counts =
        gateway.gateway?.decisionCounts() ?? (allowed: -1, denied: -1, unclassified: 0)
      return ["gatewayAllowed": counts.allowed, "gatewayDenied": counts.denied]
    }
    let beforeMainLoad = decisions()
    mark = gateway.observations.count
    gateway.load()
    let gatewayLoad = await awaitNavigation(gateway, from: mark)
    let afterMainLoad = decisions()
    check(
      "load.authenticatedGateway.mainResourceViaGateway",
      (afterMainLoad["gatewayAllowed", default: 0] + afterMainLoad["gatewayDenied", default: 0])
        > (beforeMainLoad["gatewayAllowed", default: 0]
          + beforeMainLoad["gatewayDenied", default: 0]) ? .pass : .fail,
      [
        "navigation": gatewayLoad, "decisionsBefore": beforeMainLoad,
        "decisionsAfter": afterMainLoad,
        "meaning":
          "the granted .invalid host never resolves; a new gateway decision shows the main load used the authenticated proxy",
      ])
    if let base = URL(string: gatewayOrigin + "/") {
      mark = gateway.observations.count
      gateway.webView.loadHTMLString(Self.shell, baseURL: base)
      let shellLoad = await awaitNavigation(gateway, from: mark)
      let gatewayFeatures = await features(gateway.webView)
      check(
        "lockdown.authenticatedGateway",
        gatewayReadBack["lockdownField"] as? Bool == true
          && gatewayReadBack["lockdownIsActive"] as? Bool == true
          && gatewayFeatures["rtc"] == "undefined"
          && gatewayFeatures["webTransport"] == "undefined" ? .pass : .fail,
        [
          "readBack": gatewayReadBack, "pageFeatures": gatewayFeatures,
          "shellNavigation": shellLoad,
        ])
      check(
        "routeLists.authenticatedGateway.installed",
        gatewayReadBack["denyLocal"] as? String == BrowserNetworkBoundary.denyLocalIdentifier
          && gatewayReadBack["routeKind"] as? String == "gateway"
          && gatewayReadBack["gatewayApplied"] as? Bool == true
          && gatewayReadBack["proxyConfigurations"] as? Int == 1 ? .pass : .fail,
        ["readBack": gatewayReadBack])
      let beforeProbe = decisions()
      await productProbe(
        "routeLists.authenticatedGateway.sinks", webView: gateway.webView, control: controlHTTPS,
        navigation: shellLoad
      ) { ["decisionsBefore": beforeProbe, "decisionsAfter": decisions()] }
      let beforeGranted = decisions()
      let granted = await evaluate(
        gateway.webView, Self.fetchScript, ["target": gatewayOrigin + "/s3sim-granted"])
      try? await Task.sleep(for: .milliseconds(500))
      let afterGranted = decisions()
      let other = await evaluate(
        gateway.webView, Self.fetchScript,
        ["target": "https://other-\(runID).memoshi.invalid/s3sim-other"])
      try? await Task.sleep(for: .milliseconds(500))
      let afterOther = decisions()
      check(
        "routeLists.authenticatedGateway.grantedViaGatewayOtherBlocked",
        afterGranted != beforeGranted && afterOther == afterGranted ? .pass : .fail,
        [
          "grantedPage": granted, "otherPage": other, "before": beforeGranted,
          "afterGranted": afterGranted, "afterOther": afterOther,
          "meaning":
            "granted-origin fetch produces a gateway decision; another origin is stopped by the allowlist before the gateway",
        ])
      let gatewayBlob = await blobs(gateway.webView)
      check(
        "blob.authenticatedGateway.ownOrigin", gatewayBlob == "text:ok,fetch:ok" ? .pass : .fail,
        ["page": gatewayBlob, "origin": gatewayOrigin])
    }
    let gatewayRoute = gateway.boundary.route
    await failClosed(
      gateway, route: "authenticatedGateway",
      mutations: [
        Mutation(label: "denyLocalRemoved", expected: "denyLocalMissing") { $0.denyLocal = nil },
        Mutation(label: "gatewayRemoved", expected: "gatewayMissing") { $0.gatewayApplied = false },
        Mutation(label: "lockdownRemoved", expected: "lockdownMissing") { $0.lockdown = false },
        Mutation(label: "routeRemoved", expected: "routeRulesMissing") { $0.route = nil },
        Mutation(label: "originNotInRoute", expected: "originOutsideRoute") {
          $0.route = gatewayRoute.map {
            .init(identifier: $0.identifier, kind: $0.kind, origins: [])
          }
        },
        Mutation(label: "fixtureKindForRealOrigin", expected: "originOutsideRoute") {
          $0.route = gatewayRoute.map {
            .init(identifier: $0.identifier, kind: .ownedFixture, origins: $0.origins)
          }
        },
        Mutation(label: "emptyState", expected: "lockdownMissing") {
          $0 = BrowserNetworkBoundary.State()
        },
      ],
      effects: { decisions().merging(["serverAccepts": server.accepted]) { $1 } })
    scenarios["gateway"] = [
      "observations": observationCodes(gateway), "decisions": decisions(),
      "origin": gatewayOrigin,
    ]

    // 5. Offline document route: read-back and fail-closed (no network by design).
    guard let labURL = BrowserAutomationScript.labPageURL,
      let labOrigin = BrowserAuthorization.origin(of: labURL)
    else { throw URLError(.badURL) }
    let offline = try await MobileBrowserReviewSession.open(
      index: 4,
      site: try BrowserAuthorization.Site(
        origin: labOrigin, interact: false, signIn: false, ownedFixture: true),
      route: .offlineDocument, broker: nil)
    defer { offline.close() }
    attach(offline.webView, slot: 3)
    let offlineReadBack = readBack(offline)
    mark = offline.observations.count
    offline.load()
    let offlineLoad = await awaitNavigation(offline, from: mark)
    let offlineFeatures = await features(offline.webView)
    check(
      "lockdown.offlineDocument",
      offlineReadBack["lockdownField"] as? Bool == true
        && offlineReadBack["lockdownIsActive"] as? Bool == true
        && offlineReadBack["denyLocal"] as? String == BrowserNetworkBoundary.denyLocalIdentifier
        && offlineFeatures["rtc"] == "undefined" && offlineFeatures["webTransport"] == "undefined"
        ? .pass : .fail,
      ["readBack": offlineReadBack, "pageFeatures": offlineFeatures, "navigation": offlineLoad])
    await productProbe(
      "routeLists.offlineDocument.sinks", webView: offline.webView, control: controlHTTPS,
      navigation: offlineLoad)
    await failClosed(
      offline, route: "offlineDocument",
      mutations: [
        Mutation(label: "lockdownRemoved", expected: "lockdownMissing") { $0.lockdown = false },
        Mutation(label: "bothListsRemoved", expected: "denyLocalMissing") {
          $0.denyLocal = nil
          $0.route = nil
        },
      ],
      effects: { ["serverAccepts": server.accepted] })
    scenarios["offline"] = ["observations": observationCodes(offline)]

    // 6. Another origin's blobs stay blocked under each granted origin's route list.
    let store = try BrowserContentRuleStore.appContainer()
    let denyLocal = try await store.denyLocal()
    for (label, origin, extra) in [
      ("loopbackFixture", fixtureOrigin, [WKContentRuleList]()),
      ("authenticatedGateway", gatewayOrigin, [denyLocal]),
    ] {
      let list = try await MobileBrowserReviewSession.rules(origin: origin)
      defer { store.remove(identifier: list.identifier) }
      var outcomes: [String: String] = [:]
      for (key, base) in [
        ("own", origin + "/"), ("other", "http://other-blob-\(runID).memoshi.invalid/"),
      ] {
        let probe = PlainProbe(lists: extra + [list], lockdown: true, host: host)
        if let url = URL(string: base) {
          do {
            try await probe.load(base: url)
            outcomes[key] = await blobs(probe.webView)
          } catch { outcomes[key] = "loadFailed" }
        }
        probe.close()
      }
      check(
        "blob.\(label).otherOriginBlocked",
        outcomes["own"] == "text:ok,fetch:ok" && outcomes["other"] == "text:error,fetch:error"
          ? .pass : .fail,
        ["outcomes": outcomes, "grantedOrigin": origin])
    }

    // Every sink accept after the controls is a leak.
    let finalTotals = sinkTotals
    let leaks = finalTotals.filter { afterControls[$0.key, default: 0] != $0.value }
    check(
      "sinks.noAcceptsOutsideControls", leaks.isEmpty ? .pass : .fail,
      [
        "afterControls": afterControls, "final": finalTotals,
        "byFamily": Dictionary(uniqueKeysWithValues: sinks.map { ($0.label, $0.byFamily) }),
      ])
  }
}
