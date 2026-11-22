#if os(iOS)
  import AppCore
  import DesignSystem
  import Foundation
  import Observation
  import SwiftUI
  import UniformTypeIdentifiers
  import WebKit

  /// Explicit Phase 0 development entrypoint. Nothing loads until a native approval button is
  /// pressed. The optional broker MUST be supplied by trusted, genuinely provisioned app
  /// composition; nil is an honest unavailable state, never a default-Keychain fallback.
  ///
  /// Requires AppCore, DesignSystem, MemoshiEgress; Apple WebKit, UIKit, Network and SwiftUI.
  /// Foreground only. No Pi/runtime tools, background scheduling, private touch injection,
  /// automatic action replay, real-site score or secrecy/gateway qualification is registered.
  struct MobileBrowserReviewView: View {
    @State private var model: MobileBrowserReviewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(keychain: BrowserKeychain? = nil) {
      _model = State(initialValue: MobileBrowserReviewModel(broker: keychain))
    }

    var body: some View {
      NavigationStack {
        GeometryReader { geometry in
          VStack(spacing: DS.Space.s0) {
            MobileBrowserReviewSetup(model: model)
            if let session = model.selected {
              MobileBrowserReviewToolbar(session: session)
              MobileBrowserReviewLiveView(session: session)
                .id(session.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // "<Name>'s browser, watching" / "…, you are in control" (02 §13.2, A10).
                .accessibilityElement(children: .contain)
                .accessibilityLabel(liveLabel(session))
                .accessibilityIdentifier("mobile-browser.live")
              MobileBrowserReviewInspector(session: session)
                .frame(
                  height: max(
                    DS.Layout.MobileBrowserReview.inspectorMinHeight,
                    geometry.size.height * DS.Layout.MobileBrowserReview.inspectorHeightFraction))
            } else {
              ContentUnavailableView(
                "Mobile Browser Qualification", systemImage: "globe",
                description: Text(
                  "Open an owned fixture or explicitly approve one HTTPS origin. Normal browser tools remain disabled."
                ))
            }
          }
          .background(DS.Colors.Surface.content)
        }
        .navigationTitle("Mobile Browser Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
              model.close()
              dismiss()
            }
          }
          ToolbarItem(placement: .primaryAction) {
            if model.sessions.count == 2 {
              Picker("Review profile", selection: $model.selectedID) {
                ForEach(model.sessions, id: \.id) { session in
                  Text("Review \(session.index)").tag(Optional(session.id))
                }
              }
              .pickerStyle(.menu)
              .accessibilityIdentifier("mobile-browser.profile")
              .disabled(model.selected?.handoff != nil)
            }
          }
        }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
        .onAppear { model.setActive(scenePhase == .active) }
        .onChange(of: model.selectedID) { old, _ in
          if let previous = model.sessions.first(where: { $0.id == old }) {
            previous.invalidate(cancelWork: true)
          }
        }
        .onDisappear { model.close() }
      }
    }

    private func liveLabel(_ session: MobileBrowserReviewSession) -> LocalizedStringResource {
      let name = session.profile?.name ?? session.site.origin
      return session.handoff == nil
        ? "\(name)'s browser, watching" : "\(name)'s browser, you are in control"
    }
  }

  @MainActor
  @Observable
  final class MobileBrowserReviewModel {
    var sessions: [MobileBrowserReviewSession] = []
    var selectedID: UUID?
    var configuring = false
    var checkingIsolation = false
    var problem: String?
    var active = true
    /// The saved probe record of the two fixture stores, oldest generation first.
    private(set) var probeGenerations: [MobileBrowserProbeRegistry.Generation] = []
    @ObservationIgnored let broker: BrowserKeychain?
    @ObservationIgnored private var fixture: MobileBrowserReviewFixture?
    @ObservationIgnored private var configurationTask: Task<Void, Never>?
    @ObservationIgnored private var isolationTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var fixtureRegistry: MobileBrowserProbeRegistry?

    private static let profilesKey = "mobile-browser-review.fixture-profiles"

    init(broker: BrowserKeychain?, defaults: UserDefaults = .standard) {
      self.broker = broker
      self.defaults = defaults
    }
    var selected: MobileBrowserReviewSession? { sessions.first { $0.id == selectedID } }

    func open(
      _ route: MobileBrowserReviewSession.Route, level: MobileBrowserReviewLevel,
      origin: String = ""
    ) {
      guard !configuring, active else { return }
      close()
      active = true
      configuring = true
      problem = nil
      let expectedGeneration = generation
      configurationTask = Task {
        var created: [MobileBrowserReviewSession] = []
        var candidateFixture: MobileBrowserReviewFixture?
        defer {
          configuring = false
          configurationTask = nil
        }
        do {
          let profiles = route == .loopbackFixture ? try ownedRegistry().profiles : []
          let exactOrigin: String
          switch route {
          case .loopbackFixture:
            let newFixture = try await MobileBrowserReviewFixture.start()
            candidateFixture = newFixture
            exactOrigin = try newFixture.origin
          case .offlineDocument:
            guard let url = BrowserAutomationScript.labPageURL else {
              throw MobileBrowserReviewFailure.fixtureUnavailable
            }
            exactOrigin = BrowserAuthorization.origin(of: url) ?? ""
          case .authenticatedGateway:
            guard
              let normalized = BrowserAuthorization.canonicalOrigin(
                origin.trimmingCharacters(in: .whitespacesAndNewlines), requireHTTPS: true)
            else {
              throw BrowserAuthorization.Denial.invalidOrigin
            }
            exactOrigin = normalized
          }
          let site = try BrowserAuthorization.Site(
            origin: exactOrigin, interact: level == .interact,
            signIn: level == .signIn, ownedFixture: route != .authenticatedGateway)
          for index in 1...2 {
            created.append(
              try await MobileBrowserReviewSession.open(
                index: index, site: site, route: route,
                broker: route == .loopbackFixture ? nil : broker,
                profile: route == .loopbackFixture ? profiles[index - 1] : nil))
          }
          try Task.checkCancellation()
          guard generation == expectedGeneration, active else {
            throw MobileBrowserReviewFailure.closed
          }
          fixture = candidateFixture
          sessions = created
          selectedID = created.first?.id
          for session in created { session.load() }
        } catch {
          for session in created { session.close() }
          candidateFixture?.close()
          problem = MobileBrowserReviewScript.code(error)
        }
      }
    }

    func checkIsolation() { runIsolation(reset: false) }

    /// Whether the two fixture stores are open and hold a generation of probes to replace.
    var canResetProbes: Bool {
      sessions.count == 2 && sessions.allSatisfy { $0.profile != nil } && !checkingIsolation
        && !configuring && !probeGenerations.isEmpty
    }

    /// Only the confirmed "Reset Cookie Probes…" action calls this (D131).
    func resetProbes() {
      guard canResetProbes else { return }
      runIsolation(reset: true)
    }

    private func runIsolation(reset: Bool) {
      guard sessions.count == 2, !checkingIsolation, !configuring else { return }
      let pair = sessions
      checkingIsolation = true
      isolationTask = Task {
        defer {
          checkingIsolation = false
          isolationTask = nil
        }
        do {
          if pair.allSatisfy({ $0.profile != nil }) {
            try await checkPersistentIsolation(pair, reset: reset)
            return
          }
          let values = [UUID().uuidString, UUID().uuidString]
          for (index, session) in pair.enumerated() {
            guard !session.closed, !session.webView.configuration.websiteDataStore.isPersistent,
              let cookie = HTTPCookie(properties: [
                .name: "memoshi_mobile_review_probe",
                .value: values[index], .domain: "mobile-store-probe.memoshi.invalid", .path: "/",
              ])
            else { throw MobileBrowserReviewFailure.unavailable }
            let gate = BrowserResumeGate<Bool>()
            _ = try await gate.value(
              timeout: .seconds(8), timeoutError: MobileBrowserReviewFailure.scriptTimedOut
            ) {
              session.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                gate.resume(.success(true))
              }
            }
          }
          for (index, session) in pair.enumerated() {
            let gate = BrowserResumeGate<Bool>()
            let isolated = try await gate.value(
              timeout: .seconds(8), timeoutError: MobileBrowserReviewFailure.scriptTimedOut
            ) {
              session.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
                cookies in
                let probes = cookies.filter {
                  $0.name == "memoshi_mobile_review_probe"
                    && $0.domain == "mobile-store-probe.memoshi.invalid"
                }
                gate.resume(
                  .success(
                    probes.contains { $0.value == values[index] }
                      && !probes.contains { $0.value == values[1 - index] }))
              }
            }
            guard !session.closed else { throw MobileBrowserReviewFailure.closed }
            session.record(
              .isolation,
              isolated ? "nonpersistentCookieIsolationObserved" : "cookieIsolationFailed",
              count: isolated ? 1 : 0)
          }
        } catch {
          for session in pair { session.record(.isolation, MobileBrowserReviewScript.code(error)) }
        }
      }
    }

    /// Reopens only the lab's two registered fixture stores; corrupt ownership is never replaced.
    private func ownedRegistry() throws -> MobileBrowserProbeRegistry {
      if let fixtureRegistry { return fixtureRegistry }
      if let stored = defaults.object(forKey: Self.profilesKey) {
        guard let data = stored as? Data, let registry = MobileBrowserProbeRegistry.decode(data)
        else { throw MobileBrowserReviewFailure.profileRegistryUnavailable }
        fixtureRegistry = registry
        probeGenerations = registry.generations
        return registry
      }
      let registry = MobileBrowserProbeRegistry(now: Date())
      try checkpoint(registry)
      return registry
    }

    /// One value holds the profiles, their expected probes and the verdict record.
    private func checkpoint(_ registry: MobileBrowserProbeRegistry) throws {
      defaults.set(try registry.encoded(), forKey: Self.profilesKey)
      fixtureRegistry = registry
      probeGenerations = registry.generations
    }

    /// A check reads the current generation's probes without rewriting them: a missing, foreign
    /// or unknown nonce is a failure, and a probe that is absent after its own expiry date is
    /// reported as expired, since that absence says nothing about the store. Only the first
    /// check and an explicit reset (D131) set probes, as a new numbered generation, and a reset
    /// first reads both stores under the generation it ends. Every verdict is saved under its
    /// generation before it is shown, and earlier generations are never rewritten, so a reset
    /// can neither turn an earlier failure into a pass nor hide a loss it would remove.
    private func checkPersistentIsolation(
      _ pair: [MobileBrowserReviewSession], reset: Bool
    ) async throws {
      var registry = try ownedRegistry()
      guard pair.map({ $0.profile?.id }) == registry.profiles.map({ Optional($0.id) }),
        pair.allSatisfy({ !$0.closed && $0.webView.configuration.websiteDataStore.isPersistent })
      else { throw MobileBrowserReviewFailure.profileRegistryUnavailable }
      let initializing = registry.current == nil
      guard !(reset && initializing) else { throw MobileBrowserReviewFailure.unsupportedOperation }
      if initializing {
        for session in pair {
          guard try await cookieProbeValues(in: session).isEmpty else {
            throw MobileBrowserReviewFailure.profileRegistryUnavailable
          }
        }
        guard registry.startFirstGeneration(at: Date()) != nil else {
          throw MobileBrowserReviewFailure.profileRegistryUnavailable
        }
        try checkpoint(registry)
      } else if reset {
        // Both stores are read under the generation that ends before its probes are replaced:
        // a probe lost since the last check is recorded, not removed unseen.
        var found: [Set<String>] = []
        for session in pair { found.append(try await cookieProbeValues(in: session)) }
        guard pair.allSatisfy({ !$0.closed }), let ended = registry.reset(found: found, at: Date())
        else { throw MobileBrowserReviewFailure.closed }
        try checkpoint(registry)
        for (session, closing) in zip(pair, ended.closing) {
          session.record(.isolation, closing.code, count: closing.verdict.isPass ? 1 : 0)
        }
      }
      if initializing || reset {
        // The expected probes and their generation were saved above, before any cookie changes.
        // An interruption then reads as a failure of the new generation; it cannot silently
        // reseed a lost probe.
        for (index, session) in pair.enumerated() {
          guard !session.closed, let probe = registry.profiles[index].probe,
            let cookie = HTTPCookie(properties: [
              .name: BrowserIsolationProbe.cookieName, .value: probe.nonce,
              .domain: BrowserIsolationProbe.cookieDomain, .path: "/", .secure: "TRUE",
              .expires: probe.setAt.addingTimeInterval(MobileBrowserProbeRegistry.probeLifetime),
            ])
          else { throw MobileBrowserReviewFailure.closed }
          if reset { try await removeProbeCookies(in: session) }
          let gate = BrowserResumeGate<Bool>()
          _ = try await gate.value(
            timeout: .seconds(8), timeoutError: MobileBrowserReviewFailure.scriptTimedOut
          ) {
            session.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
              gate.resume(.success(true))
            }
          }
        }
      }
      for (index, session) in pair.enumerated() {
        let values = try await cookieProbeValues(in: session)
        guard !session.closed,
          let result = registry.record(
            found: values, store: index, initializing: initializing || reset, at: Date())
        else { throw MobileBrowserReviewFailure.closed }
        try checkpoint(registry)
        session.record(.isolation, result.code, count: result.verdict.isPass ? 1 : 0)
      }
    }

    private func cookieProbeValues(in session: MobileBrowserReviewSession) async throws -> Set<
      String
    > {
      let gate = BrowserResumeGate<Set<String>>()
      return try await gate.value(
        timeout: .seconds(8), timeoutError: MobileBrowserReviewFailure.scriptTimedOut
      ) {
        session.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
          gate.resume(
            .success(
              Set(
                cookies.filter {
                  $0.name == BrowserIsolationProbe.cookieName
                    && $0.domain.hasSuffix(BrowserIsolationProbe.cookieDomain)
                }.map(\.value))))
        }
      }
    }

    /// Removes the earlier generation's probe cookies from one store, one at a time. A cookie
    /// that will not go is left for the read-back, which then records a failure.
    private func removeProbeCookies(in session: MobileBrowserReviewSession) async throws {
      let store = session.webView.configuration.websiteDataStore.httpCookieStore
      for _ in 0..<8 {
        let gate = BrowserResumeGate<Bool>()
        let removed = try await gate.value(
          timeout: .seconds(8), timeoutError: MobileBrowserReviewFailure.scriptTimedOut
        ) {
          store.getAllCookies { cookies in
            guard
              let probe = cookies.first(where: {
                $0.name == BrowserIsolationProbe.cookieName
                  && $0.domain.hasSuffix(BrowserIsolationProbe.cookieDomain)
              })
            else {
              gate.resume(.success(false))
              return
            }
            store.delete(probe) { gate.resume(.success(true)) }
          }
        }
        if !removed { return }
      }
    }

    func setActive(_ value: Bool) {
      active = value
      for session in sessions { session.setActive(value) }
      if !value {
        configurationTask?.cancel()
        isolationTask?.cancel()
      }
    }

    func close() {
      generation += 1
      configurationTask?.cancel()
      isolationTask?.cancel()
      for session in sessions { session.close() }
      sessions.removeAll()
      selectedID = nil
      fixture?.close()
      fixture = nil
    }
  }

  private struct MobileBrowserReviewSetup: View {
    @Bindable var model: MobileBrowserReviewModel
    @State private var expanded = true
    @State private var level = MobileBrowserReviewLevel.readOnly
    @State private var origin = "https://example.com"
    @State private var trustedNetworkApproval = false
    @State private var confirmingProbeReset = false

    var body: some View {
      DisclosureGroup(isExpanded: $expanded) {
        ScrollView {
          VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(
              "Development only · foreground only · two isolated review profiles · production tools: none"
            )
            .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
            Picker("Exact-site permission", selection: $level) {
              ForEach(MobileBrowserReviewLevel.allCases) { level in Text(level.title).tag(level) }
            }
            .pickerStyle(.segmented)
            HStack {
              Button("Owned Loopback Fixture") {
                model.open(.loopbackFixture, level: level)
                expanded = false
              }
              .disabled(level == .signIn)
              .accessibilityIdentifier("mobile-browser.fixture.open")
              Button("Offline Sign-in Document") {
                model.open(.offlineDocument, level: level)
                expanded = false
              }
              .accessibilityIdentifier("mobile-browser.offline.open")
            }
            Text(
              "Loopback is direct, not proxy-covered. The offline document has no live TLS or server. Sign In allows only reviewed credential fill; Interact never authorizes sends or purchases."
            )
            .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
            Text(
              "Only credential-free loopback fixtures retain their owned stores. Sign-in and HTTPS sessions remain ephemeral. Cookie checks initialize once, then read the same probes. Only an explicit reset replaces them, as a new numbered generation; earlier verdicts stay recorded."
            )
            .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
            TextField("Exact HTTPS origin", text: $origin)
              .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            Toggle(
              "I trust this exact origin and approve its network access",
              isOn: $trustedNetworkApproval)
            Button("Approve and Open Attributed HTTPS Gateway") {
              model.open(.authenticatedGateway, level: level, origin: origin)
              trustedNetworkApproval = false
              expanded = false
            }
            .disabled(!trustedNetworkApproval)
            Text(
              "A real authenticated MemoshiEgress client is installed per bot, with direct failover disabled. CONNECT sees hosts, not HTTPS methods. Coverage, DNS/QUIC leakage, five-site tasks and physical devices are not qualified here. Additional origins, including cross-origin subresources, are blocked."
            )
            .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
            Button("Check Both Cookie Stores") { model.checkIsolation() }
              .disabled(model.sessions.count != 2 || model.checkingIsolation)
              .accessibilityIdentifier("mobile-browser.isolation")
            Button("Reset Cookie Probes…", role: .destructive) { confirmingProbeReset = true }
              .disabled(!model.canResetProbes)
              .accessibilityIdentifier("mobile-browser.isolation.reset")
              .confirmationDialog(
                "Reset Cookie Probes?", isPresented: $confirmingProbeReset,
                titleVisibility: .visible
              ) {
                Button("Reset", role: .destructive) { model.resetProbes() }
                Button("Cancel", role: .cancel) {}
              } message: {
                Text(
                  "Records what both fixture stores hold now under the current generation, then replaces the probes with a new numbered generation. Earlier verdicts stay in the record under their own generation, so a reset is not a pass."
                )
              }
            ForEach(model.probeGenerations) { generation in
              Text("Probe generation \(generation.number)")
                .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
              ForEach(generation.tallies) { tally in
                Text("Store \(tally.store): \(tally.verdict.rawValue) × \(tally.count)")
                  .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
          .disabled(model.configuring)
        }
        .frame(maxHeight: DS.Layout.MobileBrowserReview.setupMaxHeight)
      } label: {
        // The label wraps at large text sizes instead of being clipped.
        Text("Trusted Setup and Limits").fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, DS.Space.s4)
      .padding(.vertical, DS.Space.s2)
      .overlay(alignment: .bottom) {
        if model.configuring {
          ProgressView().accessibilityLabel("Opening isolated review profiles")
        }
      }
      if let problem = model.problem {
        Text(verbatim: problem).font(DS.Typography.callout).foregroundStyle(
          DS.Colors.Status.Danger.fg)
      }
    }
  }

  private struct MobileBrowserReviewToolbar: View {
    @Bindable var session: MobileBrowserReviewSession
    var body: some View {
      HStack {
        // The fixed labels keep their size; the origin wraps in the space left (A20, L4).
        Text("Review \(session.index)").font(.headline).fixedSize()
        Text(verbatim: session.site.origin).font(DS.Typography.callout)
          .fixedSize(horizontal: false, vertical: true)
          .environment(\.layoutDirection, .leftToRight)
          .accessibilityLabel(Text("Reviewed origin"))
          .accessibilityValue(Text(verbatim: session.site.origin))
        Spacer()
        if session.loading { ProgressView().controlSize(.small) }
        Button("Reload") { session.reload() }.disabled(
          session.busy || session.handoff != nil || session.networkFrozen
        ).fixedSize()
        Button("Snapshot") { session.run(.snapshot) { _ = try await session.capture() } }
          .disabled(
            session.busy || session.handoff != nil || session.loading || session.secretWasReleased
          ).fixedSize()
      }
      .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s2)
    }
  }

  private struct MobileBrowserReviewLiveView: UIViewRepresentable {
    let session: MobileBrowserReviewSession
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
      uiView.isUserInteractionEnabled = false
      uiView.endEditing(true)
    }
  }

  private struct MobileBrowserReviewInspector: View {
    @Bindable var session: MobileBrowserReviewSession
    @State private var choosingFiles = false
    @State private var uploadElement: MobileBrowserReviewElement?

    var body: some View {
      Form {
        Section("Real Native Input") {
          if session.handoff != nil {
            Text(
              "Tap only the selected live-page control. Type with the real keyboard. No programmatic touch or trusted-event claim is manufactured; the handoff expires after 30 seconds."
            )
            Button("Finish Handoff and Observe Events") { Task { await session.finishHandoff() } }
          } else if let snapshot = session.snapshot {
            Text(
              "Captured frames: \(snapshot.frames.count) · Skipped: \(snapshot.skippedFrames) · Elements: \(snapshot.elements.count)"
            )
            .font(DS.Typography.callout)
            if snapshot.truncated {
              Text("Snapshot is bounded or incomplete.").font(DS.Typography.callout)
            }
            Picker("Fresh element", selection: $session.selectedElementID) {
              Text("Select an element").tag(String?.none)
              ForEach(snapshot.elements) { element in
                Text(
                  verbatim:
                    "\(element.frameID == snapshot.frames.first?.documentID ? "Main" : "Frame") · \(element.ref) · \(element.role) · \(element.name)"
                )
                .tag(Optional(element.id))
              }
            }
            if let element = session.selectedElement {
              Text(
                "Page labels are untrusted. Sends, purchases, credential-field taps and unstaged file pickers remain denied."
              )
              .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
              Button("Authorize Human Tap on Selected Control") {
                session.run(.input) { try await session.beginHandoff(element) }
              }
              .disabled(session.busy)
              if element.picker && !element.selectable {
                Button("Choose and Stage Files for This Document") {
                  uploadElement = element
                  choosingFiles = true
                }
                .disabled(session.busy || !session.site.interact)
                Text(
                  "Only your selected files are copied (32 MiB total); then authorize and tap the same file input. WebKit's picker receives staged copies only, never the original URLs."
                )
                .font(DS.Typography.callout)
              }
            }
            Text("\(session.stagedCount) files staged").font(DS.Typography.callout)
          } else {
            if session.secretWasReleased {
              Text(
                "Text snapshots are disabled after a secret-release attempt. Open fresh isolated bots to continue."
              )
            } else {
              Text("Capture a snapshot, select a control, then authorize a real human tap.")
            }
          }
        }
        .disabled(!session.active || session.closed)
        MobileBrowserReviewSecretSection(session: session)
        Section("Owned-fixture Recipe") {
          Button("Run Snapshot Assertion Only") {
            session.run(.recipe) { try await session.runFixtureRecipe() }
          }
          .disabled(session.busy || session.handoff != nil || session.loading)
          if let run = session.taskRun {
            Text(
              "Owned tasks: \(run.successfulTasks.count)/\(run.taskCount) · Real sites: \(run.realSiteCount)"
            )
          }
          Text(
            "No automated trusted input, interactive recipe runner, downloads, passkeys, background grant, or five-site score is claimed."
          )
          .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
        }
        Section("Observed Facts — No Page Text") {
          Text(
            "Commits: \(session.commit) · store: \(session.profile == nil ? "ephemeral" : "owned persistent fixture")"
          )
          .font(DS.Typography.callout)
          if session.route == .authenticatedGateway {
            Button("Refresh Gateway Counts") { session.collectGateway() }
            Text(
              "Gateway decisions: \(session.gatewayAllowed) allowed, \(session.gatewayDenied) denied. Counts are not a coverage pass."
            )
            .font(DS.Typography.callout)
          }
          if let problem = session.problem {
            Text(verbatim: problem).foregroundStyle(DS.Colors.Status.Danger.fg)
              .accessibilityIdentifier("mobile-browser.problem")
          }
          ForEach(session.observations.reversed()) { fact in
            VStack(alignment: .leading) {
              // A localized kind; the code and count stay left-to-right (L2, L4).
              Text("\(String(localized: fact.kind.label)): \(fact.code) · \(fact.count)").font(
                DS.Typography.callout.monospaced()
              )
              .environment(\.layoutDirection, .leftToRight)
              Text(fact.at, style: .time).font(DS.Typography.subheadline).foregroundStyle(
                DS.Colors.Text.secondary)
            }
          }
        }
      }
      .fileImporter(
        isPresented: $choosingFiles, allowedContentTypes: [.data], allowsMultipleSelection: true
      ) { result in
        guard let element = uploadElement else { return }
        uploadElement = nil
        if case .success(let urls) = result {
          session.run(.upload) { try await session.stage(urls, for: element) }
        } else {
          session.record(.upload, "nativeFileSelectionCancelledOrUnavailable")
        }
      }
    }
  }

  private struct MobileBrowserReviewSecretSection: View {
    @Bindable var session: MobileBrowserReviewSession
    var body: some View {
      Section("App-owned Keychain Review") {
        if session.broker == nil {
          Text(
            "Unavailable: trusted host composition did not supply a provisioned BrowserKeychain. No default or legacy Keychain is used."
          )
          .font(DS.Typography.callout)
        } else if !session.site.signIn {
          Text(
            "This exact site has no Sign In permission. Choose Sign In in Trusted Setup to create fresh bots."
          )
          .font(DS.Typography.callout)
        } else {
          Button("Save Synthetic Device-only Keychain Canary") {
            session.run(.secret) { try await session.saveCanary() }
          }
          .disabled(session.busy || session.account != nil)
          Button("Review Origin- and Document-bound Sign-in Card") {
            session.run(.secret) { try await session.offerLogin() }
          }
          .disabled(session.busy || session.account == nil || session.snapshot == nil)
          if let card = session.loginCard {
            Text(
              "Fill only into \(card.document.origin), main-document commit \(card.document.commit). Networking will be frozen before release. This is not a live website sign-in or a secret-secrecy qualification."
            )
            .font(DS.Typography.callout)
            Button("Use Keychain Once and Freeze Networking") {
              session.run(.secret) { try await session.fillLogin(card) }
            }
            .disabled(session.busy)
            Button("Decline", role: .cancel) {
              session.loginCard = nil
              session.record(.secret, "nativeSignInCardDeclined")
            }
          }
          if session.account != nil {
            Button("Revoke Synthetic Account", role: .destructive) {
              session.run(.secret) { try await session.revokeAccount() }
            }
            .disabled(session.busy || session.handoff != nil)
          }
        }
      }
    }
  }

  extension MobileBrowserReviewObservation.Kind {
    /// The reader-facing observation kind, never the raw value.
    fileprivate var label: LocalizedStringResource {
      switch self {
      case .route: "Route"
      case .navigation: "Navigation"
      case .snapshot: "Snapshot"
      case .input: "Input"
      case .upload: "Upload"
      case .secret: "Secret"
      case .lifecycle: "Lifecycle"
      case .isolation: "Isolation"
      case .recipe: "Recipe"
      }
    }
  }
#endif
