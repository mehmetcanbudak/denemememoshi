#if os(iOS)
  import AppCore
  import Foundation
  import MemoshiEgress
  import Network
  import WebKit

  /// A real per-bot client. Configuring it is not proof that all WebKit transports use it.
  @MainActor
  final class MobileBrowserReviewGateway {
    private let gateway: EgressGateway
    private let client: EgressClient
    private let attribution: EgressCallAttribution
    private var closed = false
    /// Running totals of every decision already read.
    private var totals = (allowed: 0, denied: 0, unclassified: 0)
    private var tally = BrowserGatewayTally()

    private init(gateway: EgressGateway, client: EgressClient) {
      self.gateway = gateway
      self.client = client
      attribution = client.beginCall("mobile-browser-qualification")
    }

    static func start(bot: UUID, site: BrowserAuthorization.Site) async throws
      -> MobileBrowserReviewGateway
    {
      guard !site.ownedFixture, let url = URL(string: site.origin), url.scheme == "https",
        let host = url.host()
      else { throw BrowserAuthorization.Denial.invalidOrigin }
      let rule = try EgressHostRule(host, ports: [url.port ?? 443], write: site.interact)
      let gateway = try await EgressGateway.start()
      do {
        let client = try await gateway.openClient(
          EgressClientIdentity(
            bot: "mobile-review-" + bot.uuidString.lowercased(),
            conversation: "phase0-review", computer: "ios-webkit"),
          policy: EgressPolicy(hosts: [rule]))
        return MobileBrowserReviewGateway(gateway: gateway, client: client)
      } catch {
        await gateway.shutdown()
        throw error
      }
    }

    func apply(to store: WKWebsiteDataStore) throws {
      guard !closed else { throw EgressConfigurationError.closed }
      let binding = client.proxyConfiguration(attribution)
      guard binding.host == "127.0.0.1", let port = NWEndpoint.Port(rawValue: binding.port) else {
        throw EgressConfigurationError.unbound
      }
      var proxy = ProxyConfiguration(
        httpCONNECTProxy: .hostPort(host: .ipv4(.loopback), port: port))
      proxy.allowFailover = false
      proxy.applyCredential(username: binding.username, password: binding.password)
      store.proxyConfigurations = [proxy]
    }

    /// Totals over this gateway's lifetime. `EgressGateway.decisionWindow` is only its newest
    /// window, so each read adds the decisions recorded since the last one. `unclassified`
    /// counts decisions that had already left that window, which can no longer be told apart.
    func decisionCounts() -> (allowed: Int, denied: Int, unclassified: Int) {
      let window = gateway.decisionWindow
      let read = tally.take(window.decisions, recorded: window.recorded)
      let allowed = read.fresh.count(where: \.allowed)
      totals.allowed += allowed
      totals.denied += read.fresh.count - allowed
      totals.unclassified += read.uncounted
      return totals
    }

    func close() async {
      guard !closed else { return }
      closed = true
      client.endCall(attribution)
      await client.close()
      await gateway.shutdown()
    }
  }
#endif
