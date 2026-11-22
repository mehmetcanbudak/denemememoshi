import AppCore
import AppKit
import Foundation
import MemoshiEgress
import MemoshiTransport
import WebKit

struct BrowserActionInfoPayload: Decodable {
  let docId: String
  let origin: String
  let destination: String?
  let method: String?
  let label: String
  let payment: Bool
  let link: Bool
  let file: Bool
}

struct BrowserPickerPayload: Decodable {
  let matches: Bool
  let docId: String
  let origin: String
}

/// Native review authority is separate from untrusted page facts and the normal tool set.
@MainActor
@Observable
final class BrowserSessionReview {
  enum Route: String, CaseIterable, Identifiable {
    case offline, directFixture, authenticatedProxy
    var id: Self { self }
  }

  struct SavedCard {
    let binding: BrowserAuthorization.DocumentBinding
    let usernameRef: String
    let passwordRef: String
    let account: BrowserLoginMetadata
  }

  weak var session: BrowserSession?
  let evidence: BrowserReviewEvidence
  private(set) var route = Route.offline
  private(set) var sites: [BrowserAuthorization.Site] = []
  private(set) var isConfiguring = false
  private(set) var problem: String?
  private(set) var savedLogin: BrowserLoginMetadata?
  private(set) var savedCard: SavedCard?
  private(set) var isFilling = false
  private(set) var isSavingLogin = false
  private(set) var stagedFileCount = 0
  private(set) var privateData = false
  /// The sites (scheme and registrable domain) whose pages this profile's own store has shown,
  /// kept with the profile. They tell which site a stored cookie can belong to (D136): WebKit
  /// keeps a cookie's domain, not the scheme of the page that set it.
  @ObservationIgnored private(set) var shownSites: Set<String> = []
  private(set) var lastSavedFillMatched: Bool?
  @ObservationIgnored private var gateway: (any BrowserReviewGateway)?
  /// A separate profile's route uses its owner's gateway (D136); only the owner closes it.
  @ObservationIgnored private var lentGateway: (any BrowserReviewGateway)?
  /// How this review starts its own gateway: the lab's, `BrowserGateway.starter` in the app.
  @ObservationIgnored private let startGateway: BrowserGatewayStarter
  @ObservationIgnored private var keychain: BrowserKeychain?
  @ObservationIgnored private var upload: BrowserUploadStaging?
  @ObservationIgnored private var uploadBinding: BrowserAuthorization.DocumentBinding?
  @ObservationIgnored private var form: BrowserAuthorization.FormPermit?
  @ObservationIgnored private var exposureConfirmation:
    (commit: Int, expires: ContinuousClock.Instant)?
  @ObservationIgnored private var credentialTask: Task<Void, Never>?
  @ObservationIgnored private var configurationTask: Task<Void, Never>?
  @ObservationIgnored private var gatewayTally = BrowserGatewayTally()
  @ObservationIgnored private var closed = false
  @ObservationIgnored private var downloadController: BrowserDownloadController?

  init(evidence: BrowserReviewEvidence, startGateway: @escaping BrowserGatewayStarter) {
    self.evidence = evidence
    self.startGateway = startGateway
  }

  var downloadCount: Int {
    guard let session else { return 0 }
    return evidence.contents.downloads.filter {
      $0.profileID == session.profile.id && $0.state == .completed
    }.count
  }

  func downloadOutcome(id: UUID) -> BrowserReviewEvidence.Download? {
    evidence.contents.downloads.first { $0.id == id && $0.profileID == session?.profile.id }
  }

  var hasCurrentExposureConfirmation: Bool {
    guard let session, let confirmation = exposureConfirmation else { return false }
    return confirmation.commit == session.commitCount && ContinuousClock.now < confirmation.expires
  }

  func markPrivateData() { privateData = true }

  /// Whether this profile holds private data now: the flag, or a cookie its store holds, read
  /// now. A page can set cookies after the review was configured (D136 review, spec gap 5), so
  /// every decision the flag affects reads the store while the flag is still false. Once seen,
  /// private data stays; an unreadable store counts as holding some.
  func holdsPrivateData() async -> Bool {
    guard !privateData else { return true }
    let cookies = (try? await storedCookies()) ?? .unreadable
    if cookies.holdsPrivate { privateData = true }
    return privateData
  }

  func requiresExposureConfirmation(_ ref: BrowserElementRef) async throws -> Bool {
    guard let session, await holdsPrivateData() else { return false }
    let (frame, _) = try session.resolve(ref)
    let info: BrowserActionInfoPayload = try await session.call(
      "actionInfo", session.input(for: ref), in: frame)
    guard !info.file else { return false }
    let action = BrowserAuthorization.Action(
      method: info.link ? "GET" : info.method,
      destination: info.destination.flatMap(URL.init(string:)), label: info.label,
      containsPaymentFields: info.payment, isForm: info.method != nil)
    return BrowserAuthorization.denial(
      action: action, sourceOrigin: info.origin, sites: sites,
      privateData: true, exposureConfirmed: hasCurrentExposureConfirmation)
      == .exposureConfirmationRequired
  }

  /// The store's cookies other than the isolation probe's: whether there are any, and their
  /// domains, which decide the profile a requested site opens in (D136).
  struct StoredCookies: Sendable {
    let holdsPrivate: Bool
    let domains: [String]
    /// An unreadable store counts as holding cookies for no known site.
    static let unreadable = StoredCookies(holdsPrivate: true, domains: [])
  }

  func storedCookies() async throws -> StoredCookies {
    guard let session else { throw BrowserActionError.sessionClosed }
    let store = session.webView.configuration.websiteDataStore
    let gate = BrowserResumeGate<StoredCookies>()
    return try await gate.value(
      timeout: .seconds(10), timeoutError: BrowserActionError.storeTimedOut
    ) {
      store.httpCookieStore.getAllCookies { cookies in
        let own = cookies.filter {
          !($0.name == BrowserIsolationProbe.cookieName
            && $0.domain.hasSuffix(BrowserIsolationProbe.cookieDomain))
        }
        gate.resume(.success(StoredCookies(holdsPrivate: !own.isEmpty, domains: own.map(\.domain))))
      }
    }
  }

  /// A configuration that did not settle on the requested sites and route.
  struct ConfigurationFailure: Error {
    let code: String
  }

  /// Configures a separate profile (D136) with its owner's sites and route and waits; a refusal
  /// throws its code. On the gateway route it uses the owner's gateway, so its requests leave as
  /// the same bot through the same client, and it never closes that gateway.
  func configureSeparate(from owner: BrowserSessionReview) async throws {
    if owner.route == .authenticatedProxy {
      guard let lent = owner.gateway, !lent.isClosed else {
        throw BrowserAuthorization.Denial.siteNotGranted
      }
      lentGateway = lent
    }
    configure(sites: owner.sites, route: owner.route)
    await configurationTask?.value
    guard problem == nil, sites == owner.sites, route == owner.route else {
      throw ConfigurationFailure(code: problem ?? "staleDocument")
    }
  }

  /// Closes a gateway this review started. A lent gateway stays open for its owner.
  private func closeOwned(_ candidate: (any BrowserReviewGateway)?) async {
    guard let candidate, candidate !== lentGateway else { return }
    await candidate.close()
  }

  func configure(sites: [BrowserAuthorization.Site], route: Route) {
    guard configurationTask == nil, let session, !session.isClosed,
      session.commitCount == 0 || session.isShowingLabPage
    else {
      problem = "closeBeforeConfiguration"
      return
    }
    configurationTask = Task {
      await applyConfiguration(sites: sites, route: route)
      configurationTask = nil
    }
  }

  private func applyConfiguration(sites: [BrowserAuthorization.Site], route: Route) async {
    guard let session else { return }
    isConfiguring = true
    problem = nil
    defer { isConfiguring = false }
    var candidateGateway: (any BrowserReviewGateway)?
    var cleared = false
    do {
      guard !sites.isEmpty, route != .offline else {
        throw BrowserAuthorization.Denial.siteNotGranted
      }
      // D136's site rule reads the bundled Public Suffix List. Without it no site is granted,
      // so a broken app bundle fails here, by name, instead of judging moves without the list.
      guard (try? PublicSuffixList.bundled()) != nil else {
        throw ConfigurationFailure(code: "publicSuffixListUnavailable")
      }
      if route == .directFixture {
        guard
          sites.allSatisfy({ site in
            guard site.ownedFixture, let host = URL(string: site.origin)?.host() else {
              return false
            }
            return ["127.0.0.1", "localhost", "::1", "[::1]", BrowserAutomationScript.labPageHost]
              .contains(host)
          })
        else { throw BrowserAuthorization.Denial.invalidOrigin }
      }
      let storedPrivate = try await storedCookies().holdsPrivate
      privateData = privateData || storedPrivate
      // Compile the route's list before touching the live session: block-all plus the exact
      // granted origins. A failed compile leaves the previous boundary in place.
      let origins = sites.map(\.origin)
      let kind: BrowserNetworkBoundary.RouteKind =
        route == .authenticatedProxy ? .gateway : .ownedFixture
      let routeRules = try await BrowserContentRuleStore.appContainer().compile(
        identifier: BrowserNetworkBoundary.routeListIdentifier(profile: session.profile.id),
        json: BrowserNetworkBoundary.allowlistJSON(origins: origins))
      try await session.awaitDenyLocal()
      let newGateway: (any BrowserReviewGateway)?
      if route != .authenticatedProxy {
        newGateway = nil
      } else if let lentGateway {
        newGateway = lentGateway
      } else {
        newGateway = try await startGateway(session.profile.id, sites)
      }
      candidateGateway = newGateway
      guard !closed, !Task.isCancelled, !session.isClosed,
        session.commitCount == 0 || session.isShowingLabPage
      else {
        await closeOwned(newGateway)
        throw BrowserAuthorization.Denial.staleDocument
      }
      // From here to success there is no suspension point: the old route is cleared, the
      // proxy is set, and the rules are installed before the route reports success.
      session.stopLoading()
      // A separate profile was opened under the previous grants (D136); it ends with them.
      session.closeSeparate()
      session.clearRoute()
      cleared = true
      if let newGateway {
        try newGateway.apply(to: session.webView.configuration.websiteDataStore)
      } else {
        session.webView.configuration.websiteDataStore.proxyConfigurations = []
      }
      try session.installRoute(
        routeRules, kind: kind, origins: origins, gatewayApplied: newGateway != nil)
      collectGatewayEvidence()
      let previousGateway = gateway
      gateway = newGateway
      candidateGateway = nil
      gatewayTally = BrowserGatewayTally()
      self.sites = sites
      self.route = route
      record(.configuration, true, route.rawValue)
      record(.configuration, true, session.boundary.evidenceCode)
      await closeOwned(previousGateway)
    } catch {
      await closeOwned(candidateGateway)
      if cleared {
        // A failure after the old route was cleared never leaves a half-installed route.
        let oldGateway = gateway
        collectGatewayEvidence()
        gateway = nil
        self.sites = []
        self.route = .offline
        await closeOwned(oldGateway)
      }
      problem = Self.code(error)
      record(.configuration, false, Self.code(error))
    }
  }

  /// Grant removal always stops the current page and invalidates pending native authority.
  func revokePermissions() {
    sites = []
    form = nil
    exposureConfirmation = nil
    savedCard = nil
    credentialTask?.cancel()
    configurationTask?.cancel()
    downloadController?.close(code: "permissionsRevoked")
    session?.stopLoading()
    let old = upload
    upload = nil
    uploadBinding = nil
    stagedFileCount = 0
    Task { await old?.close() }
    let oldGateway = gateway
    collectGatewayEvidence()
    gateway = nil
    route = .offline
    // Loads fail closed until a new route installs its rules: deny-local and block-all stay
    // installed, so the still-loaded document can start no load either.
    session?.clearRoute()
    // The task's separate profile ends with the grants (D136).
    session?.closeSeparate()
    Task { await closeOwned(oldGateway) }
    record(.configuration, false, "revoked")
    if let session { record(.configuration, false, session.boundary.evidenceCode) }
  }

  /// One exposure confirmation for the next form on the page the bot works in now: its
  /// separate profile's page while one is open (D136), otherwise this profile's.
  func confirmNextPrivateForm() {
    guard let lane = session?.lane else { return }
    lane.review.exposureConfirmation = (lane.commitCount, ContinuousClock.now + .seconds(30))
  }

  /// Ends the staged form permit: its form left for another profile or was refused (D136).
  func consumeFormPermit() { form = nil }

  func authorizeClick(_ ref: BrowserElementRef) async throws -> BrowserActionInfoPayload {
    guard let session else { throw BrowserActionError.sessionClosed }
    guard !evidence.storageProblem else { throw BrowserActionError.evidenceUnavailable }
    let (frame, _) = try session.resolve(ref)
    let info: BrowserActionInfoPayload = try await session.call(
      "actionInfo", session.input(for: ref), in: frame)
    // Read before the checks below: nothing suspends between them and the permit.
    let holdsPrivate = await holdsPrivateData()
    guard let snapshot = session.snapshot, snapshot.commit == session.commitCount,
      ref.frame < snapshot.frames.count, snapshot.frames[ref.frame].docID == info.docId
    else { throw BrowserAuthorization.Denial.staleDocument }
    // The built-in offline instrument keeps the historical safe non-submitting action paths.
    if session.isShowingLabPage && info.method == nil && !info.link && !info.file { return info }
    guard route != .offline, !isConfiguring else {
      throw BrowserAuthorization.Denial.siteNotGranted
    }
    if info.file {
      guard isStagedUpload(ref, documentID: info.docId),
        sites.contains(where: { $0.origin == info.origin })
      else {
        record(.upload, false, "unstagedPicker")
        throw BrowserActionError.uploadNotStaged
      }
      return info
    }
    let target = info.destination.flatMap(URL.init(string:))
    let confirmed = hasCurrentExposureConfirmation
    let action = BrowserAuthorization.Action(
      method: info.link ? "GET" : info.method,
      destination: target, label: info.label, containsPaymentFields: info.payment,
      isForm: info.method != nil)
    if let denial = BrowserAuthorization.denial(
      action: action, sourceOrigin: info.origin,
      sites: sites, privateData: holdsPrivate, exposureConfirmed: confirmed)
    {
      record(.click, false, denial.rawValue)
      throw denial
    }
    if let method = info.method, let target {
      form = BrowserAuthorization.FormPermit(
        source: info.origin, destination: target, method: method,
        commit: session.commitCount, expires: ContinuousClock.now + .seconds(5),
        exposureConfirmed: confirmed)
      exposureConfirmation = nil
    }
    record(.click, true, "allowed")
    guard !evidence.storageProblem else {
      form = nil
      throw BrowserActionError.evidenceUnavailable
    }
    return info
  }

  /// Why a navigation must be refused. `handedOff` is a form the bot's own profile authorized
  /// and handed to this separate profile (D136): it needs no permit here, only the site grant.
  func navigationDenial(
    url: URL?, method: String, sourceOrigin: String?, formRequest: Bool, mainFrame: Bool,
    handedOff: Bool = false
  ) -> String? {
    guard let session else { return "sessionClosed" }
    guard !evidence.storageProblem else { return "evidenceUnavailable" }
    return BrowserAuthorization.denial(
      navigation: BrowserAuthorization.Navigation(
        url: url, method: method, sourceOrigin: sourceOrigin, isForm: formRequest,
        isMainFrame: mainFrame, handedOff: handedOff),
      sites: route == .offline || isConfiguring ? [] : sites, privateData: privateData,
      permit: form, commit: session.commitCount,
      appPage: BrowserAutomationScript.labPageURL.flatMap(BrowserAuthorization.origin(of:))
    )?.rawValue
  }

  func isStagedUpload(_ ref: BrowserElementRef, documentID: String? = nil) -> Bool {
    guard let session, let binding = uploadBinding else { return false }
    return binding.commit == session.commitCount && binding.snapshotID == ref.snapshotID
      && binding.reference == ref.ref && (documentID == nil || binding.documentID == documentID)
  }

  /// WKFormInfo's value dictionary is deliberately never accessed, copied or logged.
  func submit(_ info: WKFormInfo, continueSubmission: () -> Void) {
    let origin = BrowserAuthorization.origin(of: info.sourceFrame.securityOrigin)
    let denial = navigationDenial(
      url: info.submissionURL, method: info.httpMethod.uppercased(),
      sourceOrigin: origin, formRequest: true, mainFrame: info.targetFrame.isMainFrame)
    form = nil
    if let denial {
      session?.stopLoading()
      record(.form, false, denial)
      // This SDK has a continue-only callback. Dropping it holds the denied form; the
      // navigation delegate already cancels unstaged/unauthorized POSTs before this point.
      return
    }
    record(.form, true, "allowed")
    guard !evidence.storageProblem else {
      session?.stopLoading()
      return
    }
    continueSubmission()
  }

  @discardableResult
  func authorizeDownload() throws -> UUID {
    guard !evidence.storageProblem else { throw BrowserActionError.evidenceUnavailable }
    guard let session, let origin = session.pageURL.flatMap(BrowserAuthorization.origin(of:)),
      route != .offline, sites.contains(where: { $0.origin == origin })
    else { throw BrowserAuthorization.Denial.siteNotGranted }
    if downloadController == nil {
      downloadController = BrowserDownloadController(
        review: self, profileID: session.profile.id,
        directory: evidence.directory.appendingPathComponent(
          session.profile.id.uuidString + "/Downloads", isDirectory: true))
    }
    guard let downloadController else { throw BrowserActionError.sessionClosed }
    return try downloadController.authorize(origin: origin, commit: session.commitCount)
  }

  func mayDownload(_ url: URL?) -> Bool {
    guard let session, !evidence.storageProblem else { return false }
    return downloadController?.mayStart(url: url, commit: session.commitCount) == true
  }

  func becameDownload(_ download: WKDownload) {
    guard let downloadController else {
      download.cancel(nil)
      return
    }
    downloadController.start(download)
  }

  func allowsDownloadRedirect(_ url: URL?) -> Bool {
    guard let url, let origin = BrowserAuthorization.origin(of: url) else { return false }
    return sites.contains { $0.origin == origin }
  }

  func stageUpload(ref: BrowserElementRef, urls: [URL], userConfirmedDisclosure: Bool) async throws
  {
    guard let session, session.control == .watching else { throw BrowserActionError.userInControl }
    guard !evidence.storageProblem else { throw BrowserActionError.evidenceUnavailable }
    let (frame, _) = try session.resolve(ref)
    let info: BrowserActionInfoPayload = try await session.call(
      "actionInfo", session.input(for: ref), in: frame)
    let holdsPrivate = await holdsPrivateData()
    guard info.file, sites.contains(where: { $0.origin == info.origin }), route != .offline else {
      throw BrowserAuthorization.Denial.siteNotGranted
    }
    guard !holdsPrivate || userConfirmedDisclosure else {
      throw BrowserAuthorization.Denial.exposureConfirmationRequired
    }
    let binding = BrowserAuthorization.DocumentBinding(
      origin: info.origin, documentID: info.docId,
      commit: session.commitCount, snapshotID: ref.snapshotID, reference: ref.ref)
    if upload == nil {
      upload = try BrowserUploadStaging(
        parentDirectory: evidence.directory.appendingPathComponent("Uploads", isDirectory: true))
    }
    guard let staging = upload else { throw BrowserUploadError.unavailable }
    try await staging.stage(
      urls.map {
        BrowserUploadSource(
          root: $0.deletingLastPathComponent(), relativePath: $0.lastPathComponent)
      }, binding: binding)
    guard !session.isClosed, session.commitCount == binding.commit, upload === staging,
      sites.contains(where: { $0.origin == binding.origin })
    else {
      await staging.discard()
      throw BrowserAuthorization.Denial.staleDocument
    }
    uploadBinding = binding
    stagedFileCount = urls.count
    privateData = true
    record(.upload, true, "staged")
    guard !evidence.storageProblem else {
      uploadBinding = nil
      stagedFileCount = 0
      await staging.discard()
      throw BrowserActionError.evidenceUnavailable
    }
  }

  func openPanel(
    parameters: WKOpenPanelParameters, frame: WKFrameInfo,
    completion: @escaping @MainActor @Sendable ([URL]?) -> Void
  ) {
    guard let session, let upload, let binding = uploadBinding else {
      record(.upload, false, "unstagedPicker")
      completion(nil)
      return
    }
    uploadBinding = nil
    stagedFileCount = 0
    Task {
      do {
        guard session.commitCount == binding.commit, session.control == .watching,
          BrowserAuthorization.origin(of: frame.securityOrigin) == binding.origin,
          sites.contains(where: { $0.origin == binding.origin })
        else { throw BrowserAuthorization.Denial.staleDocument }
        let target: BrowserPickerPayload = try await session.call(
          "pickerTarget",
          ["snapshotId": binding.snapshotID, "ref": binding.reference], in: frame)
        guard target.matches, target.docId == binding.documentID, target.origin == binding.origin
        else {
          throw BrowserUploadError.pickerMismatch
        }
        let files = try await upload.consume(
          binding: binding, allowsMultiple: parameters.allowsMultipleSelection,
          allowsDirectories: parameters.allowsDirectories)
        guard !session.isClosed, session.commitCount == binding.commit,
          sites.contains(where: { $0.origin == binding.origin })
        else { throw BrowserAuthorization.Denial.staleDocument }
        record(.upload, true, "released")
        completion(files)
      } catch {
        record(.upload, false, Self.code(error))
        completion(nil)
      }
    }
  }

  func saveLogin(username: String, password: String) async {
    guard !isSavingLogin else { return }
    guard savedLogin == nil else {
      problem = "revokeSavedLoginFirst"
      return
    }
    isSavingLogin = true
    defer { isSavingLogin = false }
    do {
      guard let session, let origin = session.pageURL.flatMap(BrowserAuthorization.origin(of:)),
        sites.contains(where: { $0.origin == origin && $0.signIn })
      else { throw BrowserAuthorization.Denial.siteNotGranted }
      let broker = try broker()
      let metadata = try await broker.put(
        origin: origin, username: username, password: password, thisDeviceOnly: true)
      savedLogin = metadata
      UserDefaults.standard.set(
        try JSONEncoder().encode(metadata), forKey: loginKey(session.profile.id))
      problem = nil
    } catch { problem = Self.code(error) }
  }

  func loadSavedLogin() {
    guard let session, let data = UserDefaults.standard.data(forKey: loginKey(session.profile.id)),
      let metadata = try? JSONDecoder().decode(BrowserLoginMetadata.self, from: data)
    else { return }
    savedLogin = metadata
  }

  func loadShownSites() {
    guard let session else { return }
    shownSites = Set(
      UserDefaults.standard.stringArray(forKey: Self.shownSitesKey(session.profile.id)) ?? [])
  }

  /// Records the site of a page this profile's own store committed. A separate profile's store
  /// is discarded, so it records nothing.
  func recordShownSite(of url: URL?) {
    guard let session, !session.isSeparateProfile,
      let origin = url.flatMap(BrowserAuthorization.origin(of:)),
      let site = BrowserAuthorization.site(of: origin), shownSites.insert(site).inserted
    else { return }
    UserDefaults.standard.set(shownSites.sorted(), forKey: Self.shownSitesKey(session.profile.id))
  }

  /// Where a profile's shown sites are kept; removed with the profile's store.
  static func shownSitesKey(_ id: UUID) -> String {
    "browser-review.shown-sites." + id.uuidString
  }

  func revokeSavedLogin() async {
    guard let savedLogin else { return }
    savedCard = nil
    credentialTask?.cancel()
    do {
      try await broker().revoke(secretRef: savedLogin.secretRef)
      if let session { UserDefaults.standard.removeObject(forKey: loginKey(session.profile.id)) }
      self.savedLogin = nil
      problem = nil
    } catch { problem = Self.code(error) }
  }

  func offerSavedLogin() {
    guard credentialTask == nil else { return }
    lastSavedFillMatched = nil
    problem = nil
    credentialTask = Task {
      defer { credentialTask = nil }
      do {
        guard let session, let snapshot = session.snapshot, session.snapshotIsCurrent,
          let account = savedLogin,
          let origin = session.pageURL.flatMap(BrowserAuthorization.origin(of:)),
          origin == account.origin, sites.contains(where: { $0.origin == origin && $0.signIn })
        else { throw BrowserAuthorization.Denial.siteNotGranted }
        let form: BrowserSignInFormPayload = try await session.call(
          "signInForm", ["snapshotId": snapshot.id], in: nil)
        guard session.commitCount == snapshot.commit, form.origin == origin else {
          throw BrowserAuthorization.Denial.staleDocument
        }
        savedCard = SavedCard(
          binding: BrowserAuthorization.DocumentBinding(
            origin: origin,
            documentID: snapshot.frames[0].docID, commit: snapshot.commit, snapshotID: snapshot.id,
            reference: form.passwordRef), usernameRef: form.usernameRef,
          passwordRef: form.passwordRef, account: account)
        problem = nil
      } catch { problem = Self.code(error) }
    }
  }

  func declineSavedLogin() {
    savedCard = nil
    lastSavedFillMatched = false
    problem = "signInDeclined"
    record(.signIn, false, "declined")
  }

  func fillSavedLogin() {
    guard credentialTask == nil, let card = savedCard else { return }
    credentialTask = Task {
      isFilling = true
      defer {
        isFilling = false
        savedCard = nil
        credentialTask = nil
      }
      do {
        guard let session else { throw BrowserActionError.sessionClosed }
        try check(card, session: session)
        let current: BrowserSignInFormPayload = try await session.call(
          "signInForm", ["snapshotId": card.binding.snapshotID], in: nil)
        guard current.usernameRef == card.usernameRef, current.passwordRef == card.passwordRef,
          current.origin == card.binding.origin
        else { throw BrowserAuthorization.Denial.staleDocument }
        let broker = try broker()
        guard !evidence.storageProblem else { throw BrowserActionError.evidenceUnavailable }
        record(.signIn, true, "keychainReleaseAuthorized")
        guard !evidence.storageProblem else { throw BrowserActionError.evidenceUnavailable }
        let release = try await broker.release(
          secretRef: card.account.secretRef, origin: card.binding.origin)
        let document: BrowserDocumentPayload = try await session.call("documentId", [:], in: nil)
        guard document.docId == card.binding.documentID else {
          throw BrowserAuthorization.Denial.staleDocument
        }
        try await broker.validate(release, origin: card.binding.origin)
        try check(card, session: session)
        let input: [String: Any] = try release.withValues(for: card.binding.origin) {
          username, password in
          [
            "snapshotId": card.binding.snapshotID, "usernameRef": card.usernameRef,
            "passwordRef": card.passwordRef,
            "username": username, "password": password, "origin": card.binding.origin,
            "expectedDocument": card.binding.documentID,
          ]
        }
        let fill: BrowserFillPayload = try await session.call("fillCredential", input, in: nil)
        privateData = true
        lastSavedFillMatched = fill.usernameMatches && fill.passwordMatches && fill.masked == 2
        guard lastSavedFillMatched == true else { throw BrowserActionError.invalidResult }
        record(
          .signIn, true,
          sites.first(where: { $0.origin == card.binding.origin })?.ownedFixture == true
            ? "keychainFilledOwnedFixture" : "keychainFilledPublicSite")
        problem = nil
      } catch {
        lastSavedFillMatched = false
        problem = Self.code(error)
        record(.signIn, false, Self.code(error))
      }
    }
  }

  private func check(_ card: SavedCard, session: BrowserSession) throws {
    try Task.checkCancellation()
    guard !closed, !session.isClosed, !session.isPerforming, session.control == .watching,
      session.commitCount == card.binding.commit, session.snapshot?.id == card.binding.snapshotID,
      session.pageURL.flatMap(BrowserAuthorization.origin(of:)) == card.binding.origin,
      savedLogin == card.account,
      sites.contains(where: { $0.origin == card.binding.origin && $0.signIn })
    else { throw BrowserAuthorization.Denial.staleDocument }
  }

  private func broker() throws -> BrowserKeychain {
    if let keychain { return keychain }
    let identity = try PeerAuthentication.currentIdentity()
    guard identity.signingIdentifier == "com.mehmetcanbudak.memoshi.mac" else {
      throw BrowserKeychainError.accessDenied
    }
    let broker = BrowserKeychain(
      accessGroup: identity.teamID + ".com.mehmetcanbudak.memoshi.secrets")
    keychain = broker
    return broker
  }

  private func loginKey(_ id: UUID) -> String { "browser-review.login." + id.uuidString }

  func documentChanged() {
    form = nil
    exposureConfirmation = nil
    uploadBinding = nil
    stagedFileCount = 0
    savedCard = nil
    credentialTask?.cancel()
    let old = upload
    upload = nil
    Task { await old?.close() }
  }

  func close() {
    closed = true
    configurationTask?.cancel()
    credentialTask?.cancel()
    documentChanged()
    downloadController?.close()
    collectGatewayEvidence()
    let old = gateway
    gateway = nil
    Task { await closeOwned(old) }
  }

  func collectGatewayEvidence() {
    // A lent gateway's decisions are its owner's to collect, once.
    guard let gateway, gateway !== lentGateway else { return }
    let window = gateway.decisionWindow
    let read = gatewayTally.take(window.decisions, recorded: window.recorded)
    evidence.record(gateway: read.fresh)
    // Decisions that left the window before this read are gone: this gateway has no log file
    // or sink. Their number is recorded, never guessed as allowed or denied.
    if read.uncounted > 0 {
      record(
        .configuration, false, "gatewayDecisionsLeftRetainedWindowUncounted=\(read.uncounted)")
    }
  }

  func record(
    _ operation: BrowserReviewEvidence.Decision.Operation, _ allowed: Bool, _ code: String
  ) {
    guard let session else { return }
    evidence.record(
      profileID: session.profile.id, operation: operation, allowed: allowed, code: code)
  }

  static func code(_ error: any Error) -> String {
    if let error = error as? BrowserAuthorization.Denial { return error.rawValue }
    if let error = error as? ConfigurationFailure { return error.code }
    if let error = error as? BrowserActionError { return error.rawValue }
    if let error = error as? BrowserKeychainError { return error.rawValue }
    if let error = error as? BrowserUploadError { return error.rawValue }
    if let error = error as? BrowserNetworkBoundary.Denial {
      return "networkBoundary." + error.rawValue
    }
    // A grant the gateway refuses names its reason, such as a `.local` site (`invalidRule`).
    if let error = error as? EgressConfigurationError { return "egress.\(error)" }
    if error is CancellationError { return "cancelled" }
    return "hostOperationFailed"
  }
}
