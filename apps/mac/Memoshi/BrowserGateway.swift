import AppCore
import Foundation
import MemoshiEgress
import Network
import WebKit

/// What a review session needs of its gateway: it is applied to a store before an external page
/// loads, its decisions are read as evidence, and it is closed with the session or its grants.
/// `BrowserGateway` is the product's. Another one comes only from the lab's `startGateway`,
/// through which the S3 no-bypass control injects its own owned gateway route.
@MainActor
protocol BrowserReviewGateway: AnyObject {
  var isClosed: Bool { get }
  /// The retained decisions (a bounded window, oldest first) with the cumulative count they
  /// end at, read by the gateway at one moment.
  var decisionWindow: (decisions: [EgressDecision], recorded: Int) { get }
  /// Applied before an external page loads in `store`.
  func apply(to store: WKWebsiteDataStore) throws
  func close() async
}

/// Starts one review profile's gateway for its granted sites.
typealias BrowserGatewayStarter =
  @MainActor (_ profileID: UUID, _ sites: [BrowserAuthorization.Site]) async throws ->
  any BrowserReviewGateway

/// One explicitly authorized review session's gateway. It is never enabled in normal tools.
@MainActor
final class BrowserGateway: BrowserReviewGateway {
  private let gateway: EgressGateway
  private let client: EgressClient
  private let attribution: EgressCallAttribution
  private(set) var isClosed = false

  /// The product's starter: a gateway of its own per review profile.
  static let starter: BrowserGatewayStarter = { try await start(profileID: $0, sites: $1) }

  private init(gateway: EgressGateway, client: EgressClient, attribution: EgressCallAttribution) {
    self.gateway = gateway
    self.client = client
    self.attribution = attribution
  }

  /// Opens the profile's client, allowed only the granted sites' hosts and ports, on the
  /// gateway `egress` starts: a new `EgressGateway` unless the S3 control supplies its own.
  static func start(
    profileID: UUID, sites: [BrowserAuthorization.Site],
    egress: @Sendable () async throws -> EgressGateway = { try await EgressGateway.start() }
  ) async throws -> BrowserGateway {
    let rules = try sites.map { site -> EgressHostRule in
      guard let url = URL(string: site.origin), let host = url.host(), !site.ownedFixture else {
        throw EgressConfigurationError.invalidRule
      }
      return try EgressHostRule(host, ports: [url.port ?? (url.scheme == "https" ? 443 : 80)])
    }
    let gateway = try await egress()
    do {
      let client = try await gateway.openClient(
        EgressClientIdentity(
          bot: "browser-review-" + profileID.uuidString.lowercased(),
          conversation: "s3-review", computer: "app-webkit"), policy: EgressPolicy(hosts: rules))
      return BrowserGateway(
        gateway: gateway, client: client, attribution: client.beginCall("s3-browser-session"))
    } catch {
      await gateway.shutdown()
      throw error
    }
  }

  /// Applied before an external page loads. The password is never encoded or added to a URL.
  /// The proxy alone is not the boundary: WebKit sends loopback, IP-literal and `localhost`
  /// loads directly and WebRTC skips it, so the session also installs its deny-local and
  /// allowlist rule lists and Lockdown, and records them in its configuration evidence.
  func apply(to store: WKWebsiteDataStore) throws {
    guard !isClosed else { throw EgressConfigurationError.closed }
    let binding = client.proxyConfiguration(attribution)
    guard binding.host == "127.0.0.1", let port = NWEndpoint.Port(rawValue: binding.port) else {
      throw EgressConfigurationError.unbound
    }
    var proxy = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: .ipv4(.loopback), port: port))
    proxy.allowFailover = false
    proxy.applyCredential(username: binding.username, password: binding.password)
    store.proxyConfigurations = [proxy]
  }

  var decisionWindow: (decisions: [EgressDecision], recorded: Int) { gateway.decisionWindow }

  func close() async {
    guard !isClosed else { return }
    isClosed = true
    client.endCall(attribution)
    await client.close()
    await gateway.shutdown()
  }
}
