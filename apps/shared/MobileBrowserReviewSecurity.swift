#if os(iOS)
  import AppCore
  import Foundation
  import WebKit

  @MainActor
  extension MobileBrowserReviewSession {
    /// Only a person-selected file is an upload capability here; arbitrary bot paths are absent.
    /// WebKit never sees a picker source URL, only BrowserUploadStaging's one-use private copies.
    func stage(_ urls: [URL], for element: MobileBrowserReviewElement) async throws {
      guard site.interact else { throw BrowserAuthorization.Denial.interactRequired }
      let (binding, frame) = try await current(element)
      let info = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewAction.self,
        command: "actionInfo", input: input(binding), frame: frame, webView: webView)
      guard info.file, info.docId == binding.documentID, info.origin == site.origin,
        !networkFrozen, (1...10).contains(urls.count)
      else { throw BrowserUploadError.pickerMismatch }
      let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
      defer { for url in scoped { url.stopAccessingSecurityScopedResource() } }
      // Resolve only the user-authorized directory capability. The selected leaf itself is still
      // opened O_NOFOLLOW by the shared service, and hard links/nonregular files are refused.
      // The service walks from `/` without following symlinks, so the directory must be given
      // in its physical spelling: Foundation's resolution returns Darwin's `/var` alias for
      // `/private/var`, where an iPhone or iPad keeps picked files.
      let sources = try urls.map { url in
        guard let physical = realpath(url.deletingLastPathComponent().path, nil) else {
          throw BrowserUploadError.unsafeFile
        }
        defer { free(physical) }
        return BrowserUploadSource(
          root: URL(fileURLWithPath: String(cString: physical), isDirectory: true),
          relativePath: url.lastPathComponent)
      }
      let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
        "MobileBrowserReviewUploads", isDirectory: true)
      let staging = try BrowserUploadStaging(
        parentDirectory: parent, maximumBytes: 32 * 1024 * 1024)
      do {
        try await staging.stage(sources, binding: binding)
        let (currentBinding, _) = try await current(element)
        guard binding == currentBinding, !networkFrozen else {
          throw BrowserAuthorization.Denial.staleDocument
        }
        let previous = upload
        upload = staging
        uploadBinding = binding
        stagedCount = urls.count
        privateData = true
        await previous?.close()
        record(.upload, "selectedFilesCopiedToPrivateStaging", count: urls.count)
      } catch {
        await staging.close()
        throw error
      }
    }

    func openPanel(
      _ parameters: WKOpenPanelParameters, frame: WKFrameInfo,
      completion: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
      guard let staging = upload, let binding = uploadBinding, let handoff,
        handoff.binding == binding, !closed, active, site.interact, !networkFrozen,
        BrowserAuthorization.origin(of: frame.securityOrigin) == binding.origin,
        binding.commit == commit
      else {
        record(.upload, "unstagedPickerDenied")
        completion(nil)
        return
      }
      uploadBinding = nil
      stagedCount = 0
      let expectedRevision = revision
      Task {
        do {
          let target = try await MobileBrowserReviewScript.call(
            MobileBrowserReviewPicker.self,
            command: "pickerTarget", input: input(binding), frame: frame, webView: webView)
          guard target.matches, target.docId == binding.documentID, target.origin == binding.origin
          else {
            throw BrowserUploadError.pickerMismatch
          }
          let copies = try await staging.consume(
            binding: binding,
            allowsMultiple: parameters.allowsMultipleSelection,
            allowsDirectories: parameters.allowsDirectories)
          // Revalidate after the actor hop, then synchronously hand off only staged copies.
          let document = try await MobileBrowserReviewScript.call(
            MobileBrowserReviewDocument.self,
            command: "documentId", frame: frame, webView: webView)
          guard !closed, active, !networkFrozen, revision == expectedRevision,
            commit == binding.commit, document.docId == binding.documentID,
            self.handoff?.binding == binding, upload === staging
          else { throw BrowserAuthorization.Denial.staleDocument }
          record(.upload, "stagedCopiesReleasedToExactDocument", count: copies.count)
          completion(copies)
        } catch {
          await staging.discard()
          record(.upload, MobileBrowserReviewScript.code(error))
          completion(nil)
        }
      }
    }

    /// Generates only a synthetic test login. Nothing is sent to a page until a separate Card.
    func saveCanary() async throws {
      guard let broker else { throw MobileBrowserReviewFailure.keychainNotConfigured }
      guard site.signIn, account == nil, !closed, active else {
        throw BrowserAuthorization.Denial.siteNotGranted
      }
      let canary = BrowserReviewCanary.generate(origin: site.origin)
      let metadata = try await broker.put(
        origin: site.origin, username: canary.username,
        password: canary.password, thisDeviceOnly: true)
      guard !closed, active else {
        try? await broker.revoke(secretRef: metadata.secretRef)
        throw MobileBrowserReviewFailure.closed
      }
      account = metadata
      record(.secret, "syntheticDeviceOnlyAccountSavedNoValuesRecorded")
    }

    func offerLogin() async throws {
      guard let account, site.signIn, account.origin == site.origin,
        let snapshot, snapshot.commit == commit, !closed, active, !loading,
        !secretWasReleased, let main = snapshot.frames.first
      else { throw BrowserAuthorization.Denial.siteNotGranted }
      let fields = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewForm.self,
        command: "signInForm", input: ["snapshotId": snapshot.id], webView: webView)
      let document = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewDocument.self,
        command: "documentId", webView: webView)
      guard fields.origin == site.origin, document.docId == main.documentID,
        self.snapshot?.id == snapshot.id, commit == snapshot.commit, !closed, active, !loading
      else {
        throw BrowserAuthorization.Denial.staleDocument
      }
      loginCard = LoginCard(
        document: .init(
          origin: fields.origin, documentID: main.documentID,
          commit: commit, snapshotID: snapshot.id, reference: fields.passwordRef),
        fields: .init(
          origin: fields.origin, commit: commit,
          usernameField: fields.usernameRef, passwordField: fields.passwordRef), account: account)
      record(.secret, "originAndFieldsBoundCardOffered")
    }

    /// This qualification deliberately freezes networking before releasing bytes. A fill is NOT
    /// an authenticated-site workflow or a secrecy pass. Text snapshots stay unavailable until
    /// this whole isolated session is destroyed, including after navigation or broker failure.
    func fillLogin(_ card: LoginCard) async throws {
      guard let broker else { throw MobileBrowserReviewFailure.keychainNotConfigured }
      defer { loginCard = nil }
      try checkLogin(card)
      let fields = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewForm.self,
        command: "signInForm", input: ["snapshotId": card.document.snapshotID], webView: webView)
      if let refusal = BrowserSignIn.refusal(
        card: card.fields, credentialOrigin: card.account.origin,
        page: .init(
          origin: fields.origin, commit: commit, usernameField: fields.usernameRef,
          passwordField: fields.passwordRef))
      {
        record(.secret, refusal.rawValue)
        throw BrowserAuthorization.Denial.staleDocument
      }
      let freeze = try await Self.rules(origin: nil)
      ruleIdentifiers.append(freeze.identifier)
      try checkLogin(card)
      networkFrozen = true
      webView.stopLoading()
      webView.configuration.userContentController.removeAllContentRuleLists()
      webView.configuration.userContentController.add(freeze)
      // Block-all with no exemption replaces both lists; the boundary admits no load now.
      boundary.denyLocal = nil
      boundary.route = .init(identifier: freeze.identifier, kind: .ownedFixture, origins: [])
      boundary.gatewayApplied = false
      collectGateway()
      await gateway?.close()
      record(.secret, "networkFrozenBeforeBrokerReleaseNoLiveSignInClaim")
      try checkLogin(card)
      // No credential-bearing textual reply can be captured from this session again, even if
      // release fails or page script reflects/transforms the login into another field or frame.
      secretWasReleased = true
      privateData = true
      snapshot = nil
      selectedElementID = nil
      record(.secret, "brokerReleaseAuthorized")
      let release = try await broker.release(
        secretRef: card.account.secretRef, origin: card.document.origin)
      let document = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewDocument.self,
        command: "documentId", webView: webView)
      guard document.docId == card.document.documentID else {
        throw BrowserAuthorization.Denial.staleDocument
      }
      try await broker.validate(release, origin: card.document.origin)
      try checkLogin(card, afterRelease: true)
      let arguments: [String: Any] = try release.withValues(for: card.document.origin) {
        username, password in
        [
          "snapshotId": card.document.snapshotID, "usernameRef": card.fields.usernameField,
          "passwordRef": card.fields.passwordField, "username": username, "password": password,
          "origin": card.document.origin, "expectedDocument": card.document.documentID,
        ]
      }
      let filled = try await MobileBrowserReviewScript.call(
        MobileBrowserReviewFill.self,
        command: "fillCredential", input: arguments, webView: webView)
      guard filled.usernameMatches, filled.passwordMatches, filled.masked == 2 else {
        throw MobileBrowserReviewFailure.invalidResult
      }
      record(.secret, "brokerFillAndTwoMasksObservedNoSecrecyVerdict", count: filled.masked)
    }

    private func checkLogin(_ card: LoginCard, afterRelease: Bool = false) throws {
      try Task.checkCancellation()
      guard ContinuousClock.now < card.expires else { throw BrowserAuthorization.Denial.expired }
      guard !closed, active, !loading, handoff == nil, site.signIn,
        account == card.account, loginCard?.id == card.id,
        commit == card.document.commit,
        afterRelease || snapshot?.id == card.document.snapshotID,
        webView.url.flatMap(BrowserAuthorization.origin(of:)) == card.document.origin
      else {
        throw BrowserAuthorization.Denial.staleDocument
      }
    }

    func revokeAccount() async throws {
      loginCard = nil
      guard let account, let broker else { throw MobileBrowserReviewFailure.keychainNotConfigured }
      try await broker.revoke(secretRef: account.secretRef)
      self.account = nil
      record(.secret, "accountRevokedSessionRemainsFrozen")
    }

    /// Uses the shared suite/result types, but scores only this actual owned-fixture snapshot.
    /// Interactive recipes are not simulated or reported as completed on iOS.
    func runFixtureRecipe() async throws {
      guard route == .loopbackFixture else { throw MobileBrowserReviewFailure.unsupportedOperation }
      let bytes = try JSONSerialization.data(withJSONObject: [
        "id": "mobile-owned-snapshot",
        "sites": [
          [
            "origin": site.origin, "interact": site.interact,
            "signIn": false, "ownedFixture": true,
          ]
        ],
        "tasks": [
          [
            "id": "snapshot-has-count", "site": site.origin,
            "steps": [
              ["operation": "snapshot"],
              ["operation": "expect", "selector": ["role": "button", "name": "Count clicks"]],
            ],
          ]
        ],
      ])
      let suite = try BrowserTaskSuite.decode(bytes)
      var run = BrowserTaskRun(suite: suite, digest: BrowserTaskSuite.digest(bytes))
      let start = ContinuousClock.now
      do {
        let captured = try await capture()
        let milliseconds = measuredMilliseconds(since: start)
        run.steps.append(
          .init(
            taskID: "snapshot-has-count", index: 0, operation: "snapshot", succeeded: true,
            code: nil, durationMs: milliseconds))
        let assertionStart = ContinuousClock.now
        let matches =
          captured.elements.filter {
            $0.frameID == captured.frames.first?.documentID && $0.role == "button"
              && $0.name == "Count clicks"
          }.count == 1
        run.steps.append(
          .init(
            taskID: "snapshot-has-count", index: 1, operation: "expect", succeeded: matches,
            code: matches ? nil : "assertionFailed",
            durationMs: measuredMilliseconds(since: assertionStart)))
        if matches { run.successfulTasks = ["snapshot-has-count"] }
        run.state = .completed
        record(
          .recipe,
          matches ? "ownedSnapshotAssertionSatisfiedNotSiteGate" : "ownedSnapshotAssertionFailed",
          count: run.successfulTasks.count)
      } catch {
        run.steps.append(
          .init(
            taskID: "snapshot-has-count", index: 0, operation: "snapshot", succeeded: false,
            code: MobileBrowserReviewScript.code(error),
            durationMs: measuredMilliseconds(since: start)))
        run.state = error is CancellationError ? .cancelled : .completed
        run.endedAt = Date()
        taskRun = run
        throw error
      }
      run.endedAt = Date()
      taskRun = run
    }

    private func measuredMilliseconds(since start: ContinuousClock.Instant) -> Double {
      let elapsed = start.duration(to: .now)
      return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds)
        / 1e15
    }
  }
#endif
