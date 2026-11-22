#if os(iOS)
  import AppCore
  import Foundation
  import Observation
  import UIKit
  import WebKit

  /// One isolated review session. Only the credential-free owned fixture may retain its store.
  @MainActor
  @Observable
  final class MobileBrowserReviewSession {
    enum Route: Equatable { case loopbackFixture, offlineDocument, authenticatedGateway }
    struct Registration {
      let document: String
      let handle: WKJSHandle
      let info: WKFrameInfo
    }
    struct Handoff {
      let binding: BrowserAuthorization.DocumentBinding
      let frame: WKFrameInfo?
      let mark: Int
    }
    struct FormPermit {
      let binding: BrowserAuthorization.DocumentBinding
      let destination: URL
      let method: String
      let expires: ContinuousClock.Instant
      var permit: BrowserAuthorization.OneUsePermit
      var navigationApproved = false
    }
    struct LoginCard: Identifiable {
      let expires = ContinuousClock.now + .seconds(30)
      let id = UUID()
      let document: BrowserAuthorization.DocumentBinding
      let fields: BrowserSignIn.CardBinding
      let account: BrowserLoginMetadata
    }

    let id: UUID
    let index: Int
    let profile: BrowserReviewProfile?
    let site: BrowserAuthorization.Site
    let route: Route
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored let broker: BrowserKeychain?
    @ObservationIgnored let delegate: MobileBrowserReviewDelegate
    @ObservationIgnored var gateway: MobileBrowserReviewGateway? {
      // The uncounted total below belongs to one gateway.
      didSet { gatewayUnclassified = 0 }
    }
    @ObservationIgnored var registrations: [Registration] = []
    @ObservationIgnored var work: Task<Void, Never>?
    @ObservationIgnored var handoffTimer: Task<Void, Never>?
    @ObservationIgnored var upload: BrowserUploadStaging?
    @ObservationIgnored var uploadBinding: BrowserAuthorization.DocumentBinding?
    @ObservationIgnored var formPermit: FormPermit?
    @ObservationIgnored var ruleIdentifiers: [String]
    @ObservationIgnored var revision = 0
    @ObservationIgnored var nextSnapshot = 0
    @ObservationIgnored var allowingOfflineLoad = false

    var snapshot: MobileBrowserReviewSnapshot?
    var selectedElementID: String?
    var handoff: Handoff?
    var loginCard: LoginCard?
    var account: BrowserLoginMetadata?
    var observations: [MobileBrowserReviewObservation] = []
    var taskRun: BrowserTaskRun?
    var problem: String?
    var commit = 0
    var loading = false
    var busy = false
    var active = true
    var closed = false
    var stagedCount = 0
    var privateData = false
    var secretWasReleased = false
    var networkFrozen = false
    var gatewayAllowed = 0
    var gatewayDenied = 0
    @ObservationIgnored var gatewayUnclassified = 0
    /// What this web view has installed; `load` and `reload` refuse until it is complete.
    var boundary = BrowserNetworkBoundary.State()

    var selectedElement: MobileBrowserReviewElement? {
      snapshot?.elements.first { $0.id == selectedElementID }
    }

    private init(
      id: UUID, index: Int, site: BrowserAuthorization.Site, route: Route,
      broker: BrowserKeychain?, profile: BrowserReviewProfile?,
      gateway: MobileBrowserReviewGateway?, rules: WKContentRuleList,
      denyLocal: WKContentRuleList?
    ) {
      self.id = id
      self.index = index
      self.profile = profile
      self.site = site
      self.route = route
      self.broker = broker
      self.gateway = gateway
      ruleIdentifiers = [rules.identifier]
      let controller = WKUserContentController()
      for source in [BrowserAutomationScript.library, MobileBrowserReviewInput.library] {
        controller.addUserScript(
          WKUserScript(
            source: source, injectionTime: .atDocumentStart,
            forMainFrameOnly: false, in: BrowserAutomationScript.world))
      }
      // Both lists are installed before the web view exists: deny-local first (not on the
      // owned loopback fixture, whose block-all list exempts only its exact origin), then the
      // route's block-all list with its exact origin.
      if let denyLocal { controller.add(denyLocal) }
      controller.add(rules)
      let configuration = WKWebViewConfiguration()
      if let profile {
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profile.id)
      } else {
        // Credential-bearing and approved-network routes always start in independent ephemeral stores.
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
      }
      configuration.userContentController = controller
      configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
      configuration.mediaTypesRequiringUserActionForPlayback = .all
      configuration.allowsInlineMediaPlayback = false
      BrowserNetworkBoundary.applyLockdown(to: configuration)
      delegate = MobileBrowserReviewDelegate()
      webView = WKWebView(frame: .zero, configuration: configuration)
      boundary.lockdown = BrowserNetworkBoundary.lockdownIsActive(on: webView)
      boundary.denyLocal = denyLocal?.identifier
      boundary.route = .init(
        identifier: rules.identifier,
        kind: route == .authenticatedGateway ? .gateway : .ownedFixture,
        origins: route == .offlineDocument ? [] : [site.origin])
      webView.isUserInteractionEnabled = false
      webView.allowsLinkPreview = false
      webView.allowsBackForwardNavigationGestures = false
      webView.isInspectable = false
      delegate.session = self
      webView.navigationDelegate = delegate
      webView.uiDelegate = delegate
      controller.add(
        delegate, contentWorld: BrowserAutomationScript.world,
        name: BrowserAutomationScript.frameMessageName)
    }

    static func open(
      index: Int, site: BrowserAuthorization.Site, route: Route,
      broker: BrowserKeychain?, profile: BrowserReviewProfile? = nil
    ) async throws -> MobileBrowserReviewSession {
      guard profile == nil || (route == .loopbackFixture && !site.signIn && broker == nil) else {
        throw MobileBrowserReviewFailure.unsupportedOperation
      }
      let id = UUID()
      let store = try BrowserContentRuleStore.appContainer()
      let denyLocal = route == .loopbackFixture ? nil : try await store.denyLocal()
      let rules = try await rules(origin: route == .offlineDocument ? nil : site.origin)
      var gateway: MobileBrowserReviewGateway?
      do {
        if route == .authenticatedGateway {
          gateway = try await MobileBrowserReviewGateway.start(bot: id, site: site)
        }
        try Task.checkCancellation()
        let session = MobileBrowserReviewSession(
          id: id, index: index, site: site, route: route,
          broker: broker, profile: profile, gateway: gateway, rules: rules, denyLocal: denyLocal)
        try gateway?.apply(to: session.webView.configuration.websiteDataStore)
        session.boundary.gatewayApplied = gateway != nil
        session.record(
          .route,
          route == .authenticatedGateway
            ? "authenticatedProxyConfiguredNotQualified"
            : route == .loopbackFixture
              ? "ownedLoopbackDirectNotProxyCovered" : "ownedOfflineDocumentNoNetwork")
        session.record(.route, session.boundary.evidenceCode)
        return session
      } catch {
        await gateway?.close()
        store.remove(identifier: rules.identifier)
        throw error
      }
    }

    /// Block-all plus the exact origin, compiled into the app-container store.
    static func rules(origin: String?) async throws -> WKContentRuleList {
      try await BrowserContentRuleStore.appContainer().compile(
        identifier: "mobile-browser-review-" + UUID().uuidString,
        json: BrowserNetworkBoundary.allowlistJSON(origins: origin.map { [$0] } ?? []))
    }

    /// Why `load` or `reload` must refuse now; nil only when the whole boundary is in place.
    var boundaryDenial: BrowserNetworkBoundary.Denial? {
      route == .offlineDocument
        ? boundary.offlineDocumentDenial : boundary.denial(loading: URL(string: site.origin + "/"))
    }

    func record(_ kind: MobileBrowserReviewObservation.Kind, _ code: String, count: Int = 0) {
      observations.append(MobileBrowserReviewObservation(kind: kind, code: code, count: count))
      if observations.count > 250 { observations.removeFirst(observations.count - 250) }
    }

    func run(
      _ kind: MobileBrowserReviewObservation.Kind,
      _ operation: @escaping @MainActor () async throws -> Void
    ) {
      guard !closed, active, work == nil, handoff == nil else {
        problem = closed ? "closed" : !active ? "inactive" : "busy"
        return
      }
      busy = true
      problem = nil
      work = Task {
        defer {
          busy = false
          work = nil
        }
        do { try await operation() } catch {
          problem = MobileBrowserReviewScript.code(error)
          record(kind, MobileBrowserReviewScript.code(error))
        }
      }
    }

    func load() {
      guard !closed, active, !networkFrozen else {
        problem = "unavailable"
        return
      }
      if let denial = boundaryDenial {
        problem = "networkBoundary." + denial.rawValue
        record(.navigation, problem ?? "networkBoundary")
        return
      }
      invalidate(cancelWork: true)
      formPermit = nil
      if route == .offlineDocument, let base = BrowserAutomationScript.labPageURL {
        allowingOfflineLoad = true
        webView.loadHTMLString(BrowserAutomationScript.labPageHTML, baseURL: base)
      } else if let url = URL(string: site.origin + "/") {
        webView.load(URLRequest(url: url))
      }
    }

    func reload() {
      guard !closed, active, !networkFrozen else {
        problem = "unavailable"
        return
      }
      if let denial = boundaryDenial {
        problem = "networkBoundary." + denial.rawValue
        record(.navigation, problem ?? "networkBoundary")
        return
      }
      if route == .offlineDocument {
        load()
        return
      }
      invalidate(cancelWork: true)
      formPermit = nil
      webView.reload()
    }

    func invalidate(cancelWork: Bool) {
      revision += 1
      if cancelWork { work?.cancel() }
      webView.isUserInteractionEnabled = false
      webView.endEditing(true)
      handoffTimer?.cancel()
      handoffTimer = nil
      let oldHandoff = handoff
      handoff = nil
      if let oldHandoff {
        record(.input, "humanHandoffInvalidatedOutcomeNotObserved")
        Task {
          _ = try? await MobileBrowserReviewScript.call(
            MobileBrowserReviewOK.self,
            command: "disarm", frame: oldHandoff.frame, webView: webView, guardCall: true)
        }
      }
      snapshot = nil
      selectedElementID = nil
      loginCard = nil
      stagedCount = 0
      uploadBinding = nil
      let oldUpload = upload
      upload = nil
      Task { await oldUpload?.close() }
    }

    func setActive(_ value: Bool) {
      guard active != value else { return }
      active = value
      if !value {
        invalidate(cancelWork: true)
        formPermit = nil
        webView.stopLoading()
      }
      record(
        .lifecycle, value ? "foregroundObservedNoBackgroundGrant" : "inactiveObservedWorkStopped")
    }

    func close() {
      guard !closed else { return }
      closed = true
      invalidate(cancelWork: true)
      formPermit = nil
      webView.stopLoading()
      webView.navigationDelegate = nil
      webView.uiDelegate = nil
      webView.configuration.userContentController.removeScriptMessageHandler(
        forName: BrowserAutomationScript.frameMessageName,
        contentWorld: BrowserAutomationScript.world)
      collectGateway()
      let gateway = gateway
      self.gateway = nil
      let account = account
      self.account = nil
      let broker = broker
      Task {
        await gateway?.close()
        if let account, let broker { try? await broker.revoke(secretRef: account.secretRef) }
      }
      let store = try? BrowserContentRuleStore.appContainer()
      for identifier in ruleIdentifiers { store?.remove(identifier: identifier) }
      registrations.removeAll()
    }

    func receive(_ message: WKScriptMessage) {
      // Only the main frame's registration is ever read; child frames are enumerated from the
      // live frame tree. Keeping theirs would let them evict the main frame's at the cap.
      guard !closed, message.webView === webView, message.world === BrowserAutomationScript.world,
        message.frameInfo.isMainFrame,
        let body = message.body as? [String: Any], body["kind"] as? String == "frame",
        let document = body["docId"] as? String, (1...150).contains(document.utf8.count),
        let handle = body["handle"] as? WKJSHandle,
        handle.contentWorld === BrowserAutomationScript.world
      else { return }
      registrations.removeAll { $0.document == document }
      if registrations.count == 24 { registrations.removeFirst() }
      registrations.append(
        Registration(document: document, handle: handle, info: message.frameInfo))
    }

    func capture() async throws -> MobileBrowserReviewSnapshot {
      guard !closed, active, !loading else { throw MobileBrowserReviewFailure.busy }
      guard !secretWasReleased else {
        throw MobileBrowserReviewFailure.snapshotsDisabledAfterSecretRelease
      }
      let expectedRevision = revision
      let expectedCommit = commit
      snapshot = nil
      selectedElementID = nil
      loginCard = nil
      if uploadBinding != nil {
        let previousUpload = upload
        upload = nil
        uploadBinding = nil
        stagedCount = 0
        await previousUpload?.close()
      }
      // A consumed upload keeps its private copies until navigation/close, not merely until
      // the next snapshot; WebKit can read selected File bytes lazily.
      nextSnapshot += 1
      let snapshotID = nextSnapshot
      let input: [String: Any] = ["snapshotId": snapshotID, "maxElements": 100, "mode": "full"]
      let main = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewSnapshotPayload.self,
        command: "snapshot", input: input, webView: webView)
      guard
        let mainRegistration = registrations.last(where: {
          $0.info.isMainFrame && $0.document == main.docId
        }),
        BrowserAuthorization.origin(of: mainRegistration.info.securityOrigin) == site.origin
      else { throw MobileBrowserReviewFailure.originMismatch }
      var frames = [
        MobileBrowserReviewSnapshot.Frame(
          documentID: main.docId, origin: site.origin, info: nil, ancestors: [])
      ]
      var elements = main.elements.map { element in
        var value = element
        value.frameID = main.docId
        return value
      }
      var skipped = 0
      var truncated = main.truncated
      // Enumerate the actual current frame tree with SDK-27 WindowProxy handles. Registrations
      // alone are not a frame inventory: detached or navigated frames must not remain targetable.
      var pending: [(WKFrameInfo?, String, [MobileBrowserReviewSnapshot.Ancestor], Int)] = [
        (nil, main.docId, [], 0)
      ]
      while let (parent, parentDocument, ancestors, depth) = pending.popLast() {
        guard depth < 4 else {
          skipped += 1
          truncated = true
          continue
        }
        let children: [WKJSHandle]
        do {
          children = try await MobileBrowserReviewScript.children(frame: parent, webView: webView)
        } catch {
          skipped += 1
          continue
        }
        if children.count == 16 { truncated = true }
        for child in children {
          guard frames.count < 24 else {
            skipped += 1
            truncated = true
            continue
          }
          do {
            let gate = BrowserResumeGate<WKFrameInfo?>()
            let resolved = try await gate.value(
              timeout: .seconds(3), timeoutError: MobileBrowserReviewFailure.scriptTimedOut
            ) {
              child.getWindowProxyFrame { gate.resume(.success($0)) }
            }
            guard let frame = resolved,
              BrowserAuthorization.origin(of: frame.securityOrigin) == site.origin
            else {
              skipped += 1
              continue
            }
            let payload = try await MobileBrowserReviewScript.call(
              MobileBrowserReviewSnapshotPayload.self,
              command: "snapshot", input: input, frame: frame, webView: webView)
            let chain =
              ancestors + [.init(parent: parent, parentDocumentID: parentDocument, child: child)]
            frames.append(
              .init(documentID: payload.docId, origin: site.origin, info: frame, ancestors: chain))
            elements.append(
              contentsOf: payload.elements.map { element in
                var value = element
                value.frameID = payload.docId
                return value
              })
            truncated = truncated || payload.truncated
            pending.append((frame, payload.docId, chain, depth + 1))
          } catch { skipped += 1 }
        }
      }
      let finalMain = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewDocument.self,
        command: "documentId", webView: webView)
      guard finalMain.docId == main.docId else { throw MobileBrowserReviewFailure.staleDocument }
      guard !closed, active, !loading, revision == expectedRevision, commit == expectedCommit else {
        throw MobileBrowserReviewFailure.staleDocument
      }
      let result = MobileBrowserReviewSnapshot(
        id: snapshotID, commit: expectedCommit, frames: frames,
        elements: elements, skippedFrames: skipped, truncated: truncated || skipped > 0)
      snapshot = result
      selectedElementID = nil
      loginCard = nil
      record(
        .snapshot, skipped == 0 ? "isolatedSnapshotCaptured" : "isolatedSnapshotPartialFrames",
        count: elements.count)
      collectGateway()
      return result
    }

    func current(_ element: MobileBrowserReviewElement) async throws -> (
      BrowserAuthorization.DocumentBinding, WKFrameInfo?
    ) {
      guard !closed, active, !loading, let snapshot, snapshot.commit == commit,
        snapshot.elements.contains(element),
        let frame = snapshot.frames.first(where: { $0.documentID == element.frameID })
      else { throw MobileBrowserReviewFailure.staleDocument }
      try await verifyAncestors(frame, scroll: false)
      let document = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewDocument.self,
        command: "documentId", frame: frame.info, webView: webView)
      guard document.docId == frame.documentID, self.snapshot?.id == snapshot.id,
        commit == snapshot.commit,
        !closed, active, !loading,
        frame.info.map({ BrowserAuthorization.origin(of: $0.securityOrigin) == frame.origin })
          ?? true
      else { throw MobileBrowserReviewFailure.staleDocument }
      return (
        BrowserAuthorization.DocumentBinding(
          origin: frame.origin, documentID: frame.documentID,
          commit: snapshot.commit, snapshotID: snapshot.id, reference: element.ref), frame.info
      )
    }

    func input(_ binding: BrowserAuthorization.DocumentBinding) -> [String: Any] {
      [
        "snapshotId": binding.snapshotID, "ref": binding.reference,
        "expectedDocument": binding.documentID,
      ]
    }
    func verifyAncestors(_ frame: MobileBrowserReviewSnapshot.Frame, scroll: Bool) async throws {
      for ancestor in frame.ancestors {
        try await MobileBrowserReviewScript.verifyFrame(ancestor, scroll: scroll, webView: webView)
      }
    }

    func beginHandoff(_ element: MobileBrowserReviewElement) async throws {
      guard webView.window != nil, !networkFrozen else {
        throw MobileBrowserReviewFailure.nativeHandoffRequired
      }
      guard !element.sensitive, !element.masked else {
        throw MobileBrowserReviewFailure.credentialField
      }
      if let frame = snapshot?.frames.first(where: { $0.documentID == element.frameID }) {
        try await verifyAncestors(frame, scroll: true)
      }
      let (binding, frame) = try await current(element)
      let info = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewAction.self,
        command: "actionInfo", input: input(binding), frame: frame, webView: webView)
      guard info.docId == binding.documentID, info.origin == binding.origin else {
        throw MobileBrowserReviewFailure.originMismatch
      }
      if info.file {
        guard site.interact, uploadBinding == binding, stagedCount > 0 else {
          throw MobileBrowserReviewFailure.uploadNotStaged
        }
      } else {
        let action = BrowserAuthorization.Action(
          method: info.link ? "GET" : info.method,
          destination: info.destination.flatMap(URL.init(string:)), label: info.label,
          containsPaymentFields: info.payment, isForm: info.method != nil)
        if let denial = BrowserAuthorization.denial(
          action: action, sourceOrigin: binding.origin,
          sites: [site], privateData: privateData)
        {
          throw denial
        }
      }
      let target = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewTarget.self,
        command: "target", input: input(binding), frame: frame, webView: webView)
      guard !target.sensitive else { throw MobileBrowserReviewFailure.credentialField }
      guard !target.picker || target.file || element.selectable else {
        throw MobileBrowserReviewFailure.unsupportedOperation
      }
      let mark = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewMark.self,
        command: "mark", input: input(binding), frame: frame, webView: webView)
      var args = input(binding)
      args["origin"] = binding.origin
      args["label"] = info.label
      args["destination"] = info.destination.map { $0 as Any } ?? NSNull()
      args["method"] = info.method.map { $0 as Any } ?? NSNull()
      let armed = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewOK.self,
        command: "arm", input: args, frame: frame, webView: webView, guardCall: true)
      guard armed.ok, !closed, active, commit == binding.commit, snapshot?.id == binding.snapshotID
      else {
        throw MobileBrowserReviewFailure.staleDocument
      }
      if let method = info.method, let destination = info.destination.flatMap(URL.init(string:)) {
        formPermit = FormPermit(
          binding: binding, destination: destination, method: method,
          expires: .now + .seconds(30), permit: .init(binding: binding))
      }
      handoff = Handoff(binding: binding, frame: frame, mark: mark.mark)
      webView.isUserInteractionEnabled = true
      record(.input, "humanNativeHandoffArmedNoSyntheticInput")
      handoffTimer = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(30)) } catch { return }
        await self?.finishHandoff(expired: true)
      }
    }

    func finishHandoff(expired: Bool = false) async {
      guard let handoff else { return }
      self.handoff = nil
      webView.isUserInteractionEnabled = false
      webView.endEditing(true)
      if !expired { handoffTimer?.cancel() }
      handoffTimer = nil
      record(.input, expired ? "humanHandoffExpired" : "humanHandoffEnded")
      do {
        _ = try await MobileBrowserReviewScript.call(
          MobileBrowserReviewOK.self, command: "disarm",
          frame: handoff.frame, webView: webView, guardCall: true)
        let document = try await MobileBrowserReviewScript.call(
          MobileBrowserReviewDocument.self,
          command: "documentId", frame: handoff.frame, webView: webView)
        guard document.docId == handoff.binding.documentID, commit == handoff.binding.commit else {
          throw MobileBrowserReviewFailure.staleDocument
        }
        let observed = try await MobileBrowserReviewScript.call(
          MobileBrowserReviewEvents.self,
          command: "observed", input: ["since": handoff.mark], frame: handoff.frame,
          webView: webView)
        let types: Set<String> = [
          "pointerdown", "pointerup", "mousedown", "mouseup", "click", "keydown", "keyup",
          "beforeinput", "input", "change",
        ]
        let trusted = observed.events.filter {
          $0.trusted && $0.onTarget && types.contains($0.type)
        }
        record(.input, "observedEventCount", count: observed.events.count)
        record(
          .input, trusted.isEmpty ? "noTrustedTargetEventObserved" : "trustedTargetEventsObserved",
          count: trusted.count)
      } catch { record(.input, MobileBrowserReviewScript.code(error)) }
      formPermit = nil
      snapshot = nil
      selectedElementID = nil
    }

    func collectGateway() {
      guard let counts = gateway?.decisionCounts() else { return }
      gatewayAllowed = counts.allowed
      gatewayDenied = counts.denied
      if counts.unclassified > gatewayUnclassified {
        gatewayUnclassified = counts.unclassified
        record(.route, "gatewayDecisionsLeftRetainedWindowUncounted", count: counts.unclassified)
      }
    }
  }
#endif
