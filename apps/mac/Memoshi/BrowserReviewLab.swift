import AppCore
import AppKit
import Foundation
import WebKit

/// The Browser Review lab's app-lifetime owner. Creating it only reads the lab's own profile list
/// (UserDefaults keys under `browser-review.`); WebKit views and stores are created only when a
/// person opens a profile or runs a probe. Pages it started keep running while no window shows
/// them, and every measurement is kept as typed, page-text-free evidence for export.
@MainActor
@Observable
final class BrowserReviewLab {
  let evidence = BrowserReviewEvidence()
  let taskRunner: BrowserTaskRunner
  /// How each review profile's session starts its gateway: the product's own in the app; the
  /// S3 no-bypass control injects an owned gateway route here.
  @ObservationIgnored let startGateway: BrowserGatewayStarter
  private(set) var profiles: [BrowserReviewProfile] = []
  private(set) var sessions: [UUID: BrowserSession] = [:]
  var selectedProfileID: UUID?
  private(set) var parkingMode: BrowserParkingMode
  private(set) var schedulingForNewSessions: BrowserSchedulingPolicy
  /// Profiles the person parked even though the review window could show them.
  private(set) var parkedByPerson: Set<UUID> = []
  private(set) var pendingRemovals: Set<UUID> = []
  private(set) var registryProblem: String?
  private(set) var visibleReviewViews = 0
  private(set) var isCheckingIsolation = false
  private(set) var isWritingProbe = false
  private(set) var events: [BrowserLabEvent] = []
  private(set) var blockCounts: [BrowserBlockReason: Int] = [:]
  private(set) var snapshotTimings: [BrowserSnapshotTiming] = []
  private(set) var outcomes: [BrowserActionOutcome] = []
  private(set) var hostMoves: [BrowserHostMoveCheck] = []
  private(set) var isolationChecks: [BrowserIsolationCheck] = []
  private(set) var backgroundRuns: [BrowserBackgroundRunRecord] = []
  private(set) var navigations: [BrowserNavigationRecord] = []
  private(set) var signIns: [BrowserSignInOutcome] = []
  /// Profiles whose automation run keeps them in the visible one-point host window while no
  /// review window shows them, so WebKit does not treat their pages as hidden.
  private(set) var visibleHostProfiles: Set<UUID> = []
  let launchDate = Date()
  /// The site grants a person is choosing in the authorization panel, kept here so they survive
  /// the inspector's tab switches, with the route they are for.
  var siteGrantDraft = BrowserSiteGrantDraft()
  var siteGrantRoute = BrowserSessionReview.Route.authenticatedProxy

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let hostWindows = BrowserHostWindows()
  @ObservationIgnored private var registryReadable = true
  @ObservationIgnored private var runTask: Task<Void, Never>?
  @ObservationIgnored private var runActivity: (any NSObjectProtocol)?
  @ObservationIgnored private var runID: UUID?
  /// D136: removes the compiled lists a crash or a quit left behind; returns what it removed.
  @ObservationIgnored private(set) var startupSweep: Task<[String], Never>?

  private struct TimerBaseline {
    let docID: String
    let ticks: Int
    let at: ContinuousClock.Instant
  }

  private static let profilesKey = "browser-review.profiles"
  private static let parkingKey = "browser-review.parking"
  private static let schedulingKey = "browser-review.scheduling"

  /// Reads only the lab's saved profile list and choices; it creates no web view or store. When
  /// the list is readable, it sweeps the compiled rule lists of profiles that no longer exist.
  init(
    defaults: UserDefaults = .standard,
    startGateway: @escaping BrowserGatewayStarter = BrowserGateway.starter
  ) {
    taskRunner = BrowserTaskRunner(evidence: evidence)
    self.startGateway = startGateway
    self.defaults = defaults
    let savedParking = defaults.string(forKey: BrowserReviewLab.parkingKey)
    parkingMode = savedParking.flatMap(BrowserParkingMode.init(rawValue:)) ?? .detached
    let savedScheduling = defaults.string(forKey: BrowserReviewLab.schedulingKey)
    schedulingForNewSessions =
      savedScheduling.flatMap(BrowserSchedulingPolicy.init(rawValue:)) ?? .unthrottled
    if let data = defaults.data(forKey: BrowserReviewLab.profilesKey) {
      do {
        profiles = try JSONDecoder().decode([BrowserReviewProfile].self, from: data)
      } catch {
        registryReadable = false
        registryProblem = String(
          localized:
            "The saved review profile list could not be read. It is left unchanged, and creating or removing profiles is disabled."
        )
      }
    }
    selectedProfileID = profiles.first?.id
    guard registryReadable else { return }
    let saved = Set(profiles.map(\.id))
    startupSweep = Task {
      guard let rules = try? BrowserContentRuleStore.existingAppContainer() else { return [] }
      return await rules.sweepProfileLists {
        saved.contains($0) || BrowserSession.liveProfiles.contains($0)
      }
    }
  }

  var selectedProfile: BrowserReviewProfile? {
    profiles.first { $0.id == selectedProfileID }
  }

  var selectedSession: BrowserSession? {
    selectedProfileID.flatMap { sessions[$0] }
  }

  /// The selected bot's page as it is now: its separate profile while one is open (D136).
  var selectedLane: BrowserSession? { selectedSession?.lane }

  var canEditProfiles: Bool { registryReadable }
  var activeRun: BrowserBackgroundRunRecord? { backgroundRuns.first { $0.state == .running } }

  func isPresentingLive(_ session: BrowserSession) -> Bool {
    !parkedByPerson.contains(session.profile.id)
  }

  // MARK: Review window

  /// Tracks review visibility only; WebKit starts when a person opens or probes an owned profile.
  func reviewViewAppeared() {
    visibleReviewViews += 1
  }

  func reviewViewDisappeared() {
    visibleReviewViews = max(0, visibleReviewViews - 1)
  }

  // MARK: Profiles

  func createProfile() {
    guard registryReadable else { return }
    let profile = BrowserReviewProfile(
      id: UUID(), name: nextProfileName(), createdAt: Date(), probe: nil)
    profiles.append(profile)
    saveProfiles()
    selectedProfileID = profile.id
    record(.profileCreated, profileName: profile.name)
  }

  /// Deletes the profile's own WebKit store after its web view is released, then forgets it.
  func remove(_ profile: BrowserReviewProfile) {
    guard registryReadable, !pendingRemovals.contains(profile.id) else { return }
    if let session = sessions[profile.id] { close(session) }
    pendingRemovals.insert(profile.id)
    Task {
      // WebKit refuses to remove a store while a web view still uses it.
      try? await Task.sleep(for: .milliseconds(300))
      // A cold static removal crashes in WebKit's uninitialized callback RunLoop on macOS 27.
      // Initialize through this exact owned store, then release it before removing the store.
      // No view, unrelated identifier or enumeration is needed.
      autoreleasepool { _ = WKWebsiteDataStore(forIdentifier: profile.id) }
      let gate = BrowserResumeGate<Bool>()
      do {
        _ = try await gate.value(
          timeout: .seconds(15), timeoutError: BrowserActionError.storeTimedOut
        ) {
          WKWebsiteDataStore.remove(forIdentifier: profile.id) { error in
            if let error {
              gate.resume(.failure(error))
            } else {
              gate.resume(.success(true))
            }
          }
        }
        self.finishRemoval(of: profile, error: nil)
      } catch {
        self.finishRemoval(of: profile, error: error)
      }
    }
  }

  private func finishRemoval(of profile: BrowserReviewProfile, error: (any Error)?) {
    pendingRemovals.remove(profile.id)
    if let error {
      record(.profileRemovalFailed(error as? BrowserActionError), profileName: profile.name)
      return
    }
    profiles.removeAll { $0.id == profile.id }
    // The store and its cookies are gone, so is the record of which sites set them (D136).
    UserDefaults.standard.removeObject(forKey: BrowserSessionReview.shownSitesKey(profile.id))
    parkedByPerson.remove(profile.id)
    if selectedProfileID == profile.id { selectedProfileID = profiles.first?.id }
    saveProfiles()
    record(.profileRemoved, profileName: profile.name)
  }

  private func nextProfileName() -> String {
    let used = Set(profiles.map(\.name))
    for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
      let name = String(localized: "Review \(String(letter))")
      if !used.contains(name) { return name }
    }
    return String(localized: "Review \(profiles.count + 1)")
  }

  private func saveProfiles() {
    guard registryReadable else { return }
    do {
      let data = try JSONEncoder().encode(profiles)
      defaults.set(data, forKey: BrowserReviewLab.profilesKey)
    } catch {
      registryProblem = String(localized: "The review profile list could not be saved.")
    }
  }

  // MARK: Sessions and placement

  /// Creates the profile's web view on explicit request. It loads nothing until navigation.
  func open(_ profile: BrowserReviewProfile) {
    guard sessions[profile.id] == nil, !pendingRemovals.contains(profile.id) else { return }
    let session = BrowserSession(
      profile: profile, scheduling: schedulingForNewSessions, placement: parkingMode.placement,
      lab: self)
    sessions[profile.id] = session
    parkedByPerson.remove(profile.id)
    hostWindows.park(session.webView, mode: parkingMode)
    record(.sessionOpened(session.scheduling), session: session)
  }

  /// Releases the web view; the profile's store and its data stay on disk.
  func close(_ session: BrowserSession) {
    if activeRun?.profileID == session.profile.id { stopBackgroundRun() }
    taskRunner.cancel(ifUsing: session)
    session.close()
    sessions[session.profile.id] = nil
    hostWindows.orderOutEmptyWindows()
    record(.sessionClosed, session: session)
  }

  /// Moves the existing web view into a live container. No reload: the same view moves.
  func attach(_ session: BrowserSession, to container: BrowserLiveContainerView) {
    guard sessions[session.profile.id] === session, !session.isClosed else { return }
    let from = session.placement
    // The page the bot works in now: its separate profile while one is open (D136).
    container.host(session.lane.webView)
    session.liveContainer = container
    hostWindows.orderOutEmptyWindows()
    session.didMove(from: from, to: .reviewWindow)
  }

  /// Parks a view leaving a live container, unless another container already took it.
  func releaseLiveView(of session: BrowserSession, from container: BrowserLiveContainerView) {
    guard session.lane.webView.superview === container else { return }
    park(session)
  }

  func showLive(_ session: BrowserSession) {
    parkedByPerson.remove(session.profile.id)
  }

  /// Parks the page while the review window stays open; the live view leaves and parks it.
  func parkFromReview(_ session: BrowserSession) {
    parkedByPerson.insert(session.profile.id)
  }

  func setParkingMode(_ mode: BrowserParkingMode) {
    guard mode != parkingMode else { return }
    parkingMode = mode
    defaults.set(mode.rawValue, forKey: BrowserReviewLab.parkingKey)
    for session in sessions.values where session.placement != .reviewWindow {
      park(session)
    }
  }

  func setSchedulingForNewSessions(_ policy: BrowserSchedulingPolicy) {
    schedulingForNewSessions = policy
    defaults.set(policy.rawValue, forKey: BrowserReviewLab.schedulingKey)
  }

  /// Where a page goes when no review window shows it: the visible one-point host window while
  /// its automation run asks for one, otherwise the person's parking choice.
  private func parkingMode(for session: BrowserSession) -> BrowserParkingMode {
    visibleHostProfiles.contains(session.profile.id) ? .onePointWindow : parkingMode
  }

  private func park(_ session: BrowserSession) {
    guard !session.isClosed else { return }
    let from = session.placement
    let mode = parkingMode(for: session)
    session.liveContainer = nil
    hostWindows.park(session.lane.webView, mode: mode)
    hostWindows.orderOutEmptyWindows()
    session.didMove(from: from, to: mode.placement)
  }

  // MARK: Isolation and persistence probe

  /// Stores a fresh non-secret probe cookie for a domain that never resolves in this profile.
  func setProbe(in profile: BrowserReviewProfile) {
    guard registryReadable, !isCheckingIsolation, !isWritingProbe else { return }
    let properties: [HTTPCookiePropertyKey: Any] = [
      .name: BrowserIsolationProbe.cookieName,
      .value: UUID().uuidString,
      .domain: BrowserIsolationProbe.cookieDomain,
      .path: "/",
      .secure: "TRUE",
      .expires: Date().addingTimeInterval(30 * 24 * 60 * 60),
    ]
    guard let cookie = HTTPCookie(properties: properties) else {
      record(.probeFailed, profileName: profile.name)
      return
    }
    let nonce = cookie.value
    let store = dataStore(for: profile)
    isWritingProbe = true
    Task {
      let gate = BrowserResumeGate<Bool>()
      do {
        _ = try await gate.value(
          timeout: .seconds(10), timeoutError: BrowserActionError.storeTimedOut
        ) {
          store.httpCookieStore.setCookie(cookie) { gate.resume(.success(true)) }
        }
        self.finishProbe(in: profile, nonce: nonce)
      } catch {
        self.record(.probeFailed, profileName: profile.name)
      }
      self.isWritingProbe = false
    }
  }

  /// Reads every review profile's cookies: its own probe should be present, no other profile's.
  func checkIsolation() {
    guard !isCheckingIsolation, !isWritingProbe, !profiles.isEmpty else { return }
    isCheckingIsolation = true
    let checked = profiles
    Task {
      var observations: [BrowserIsolationObservation] = []
      for profile in checked {
        observations.append(await self.observeIsolation(of: profile, among: checked))
      }
      self.isCheckingIsolation = false
      let check = BrowserIsolationCheck(id: UUID(), date: Date(), observations: observations)
      BrowserReviewLab.prepend(check, to: &self.isolationChecks, limit: 20)
      self.record(
        .isolationChecked(met: check.metCount, of: observations.count), profileName: nil)
    }
  }

  private func finishProbe(in profile: BrowserReviewProfile, nonce: String) {
    guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
    profiles[index].probe = BrowserIsolationProbe(nonce: nonce, setAt: Date())
    saveProfiles()
    record(.probeSet, profileName: profile.name)
  }

  private func observeIsolation(
    of profile: BrowserReviewProfile, among checked: [BrowserReviewProfile]
  ) async -> BrowserIsolationObservation {
    let store = dataStore(for: profile)
    let own = profile.probe?.nonce
    let foreign = Set(checked.filter { $0.id != profile.id }.compactMap { $0.probe?.nonce })
    let persistedBefore = profile.probe.map { $0.setAt < launchDate }
    do {
      let values = try await probeValues(in: store)
      let records = try await dataRecordCount(in: store)
      var unregistered = values.subtracting(foreign)
      if let own { unregistered.remove(own) }
      return BrowserIsolationObservation(
        profileID: profile.id, profileName: profile.name, expectsOwnProbe: own != nil,
        foundOwnProbe: own.map { values.contains($0) } ?? false,
        foundForeignProbe: !values.isDisjoint(with: foreign),
        foundUnregisteredProbe: !unregistered.isEmpty, probeSetBeforeThisLaunch: persistedBefore,
        dataRecordCount: records, readFailed: false)
    } catch {
      return BrowserIsolationObservation(
        profileID: profile.id, profileName: profile.name, expectsOwnProbe: own != nil,
        foundOwnProbe: false, foundForeignProbe: false, foundUnregisteredProbe: false,
        probeSetBeforeThisLaunch: persistedBefore, dataRecordCount: 0, readFailed: true)
    }
  }

  /// The values of probe cookies in a store. Cookie store calls can stall before WebKit's
  /// network process starts, so each read is bounded.
  private func probeValues(in store: WKWebsiteDataStore) async throws -> Set<String> {
    let gate = BrowserResumeGate<Set<String>>()
    return try await gate.value(
      timeout: .seconds(10), timeoutError: BrowserActionError.storeTimedOut
    ) {
      store.httpCookieStore.getAllCookies { cookies in
        let probes = cookies.filter {
          $0.name == BrowserIsolationProbe.cookieName
            && $0.domain.hasSuffix(BrowserIsolationProbe.cookieDomain)
        }
        gate.resume(.success(Set(probes.map(\.value))))
      }
    }
  }

  private func dataRecordCount(in store: WKWebsiteDataStore) async throws -> Int {
    let gate = BrowserResumeGate<Int>()
    return try await gate.value(
      timeout: .seconds(10), timeoutError: BrowserActionError.storeTimedOut
    ) {
      store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
        gate.resume(.success(records.count))
      }
    }
  }

  private func dataStore(for profile: BrowserReviewProfile) -> WKWebsiteDataStore {
    sessions[profile.id]?.webView.configuration.websiteDataStore
      ?? WKWebsiteDataStore(forIdentifier: profile.id)
  }

  // MARK: Background runs

  /// Samples a started page on a fixed cadence wherever it lives, holding an App Nap activity.
  /// With `keepsPageVisible`, a page that no review window shows waits in the visible one-point
  /// host window for the run's duration (06's row-3 fallback) instead of its parking place.
  func startBackgroundRun(
    for session: BrowserSession, configuration: BrowserBackgroundConfiguration
  ) {
    guard runTask == nil, !session.isClosed else { return }
    runActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated], reason: "Memoshi Browser Review background run")
    if configuration.keepsPageVisible {
      visibleHostProfiles.insert(session.profile.id)
      if session.placement != .reviewWindow { park(session) }
    }
    let run = BrowserBackgroundRunRecord(
      id: UUID(), profileID: session.profile.id, profileName: session.profile.name,
      scheduling: session.scheduling, configuration: configuration, startedAt: Date(),
      endedAt: nil, state: .running, samples: [])
    BrowserReviewLab.prepend(run, to: &backgroundRuns, limit: 10)
    record(.backgroundRunStarted(session.placement), session: session)
    runID = run.id
    runTask = Task {
      let state = await self.execute(runID: run.id, session: session, configuration: configuration)
      self.finishRun(run.id, profileName: session.profile.name, state: state)
    }
  }

  func stopBackgroundRun() {
    runTask?.cancel()
  }

  /// Samples on a fixed cadence counted from the start, so the sampling period, not the work done
  /// per sample, sets the interval. A late sample is followed at once, never by a burst.
  private func execute(
    runID: UUID, session: BrowserSession, configuration: BrowserBackgroundConfiguration
  ) async -> BrowserBackgroundRunState {
    let clock = ContinuousClock()
    let start = clock.now
    let end = start + .seconds(configuration.minutes * 60)
    let interval = Duration.seconds(max(1, configuration.sampleSeconds))
    let navigationEvery = max(1, 60 / max(1, configuration.sampleSeconds))
    var baseline = try? await startTimer(on: session, clock: clock)
    var cycle = 0
    var deadline = start
    do {
      while true {
        deadline += interval
        if deadline < clock.now { deadline = clock.now }
        guard deadline <= end else { break }
        try await clock.sleep(until: deadline, tolerance: .milliseconds(10))
        guard !session.isClosed else { return .sessionClosed }
        cycle += 1
        let includesNavigation = configuration.includesNavigation && cycle % navigationEvery == 0
        let sample = await takeSample(
          of: session, baseline: &baseline, includesNavigation: includesNavigation,
          elapsed: clock.now - start, clock: clock)
        guard let index = backgroundRuns.firstIndex(where: { $0.id == runID }) else {
          return .cancelled
        }
        backgroundRuns[index].samples.append(sample)
      }
      await session.stopTimerProbe()
      return .completed
    } catch {
      if !session.isClosed { await session.stopTimerProbe() }
      return session.isClosed ? .sessionClosed : .cancelled
    }
  }

  private func takeSample(
    of session: BrowserSession, baseline: inout TimerBaseline?, includesNavigation: Bool,
    elapsed: Duration, clock: ContinuousClock
  ) async -> BrowserBackgroundSample {
    let host = session.hostState
    let placement = session.placement
    var failures: [String] = []
    var visibility: String?
    var timerTicks: Int?
    var timerHz: Double?
    var documentChanged = false
    do {
      let reading = try await session.readTimerProbe()
      visibility = reading.visibility
      timerTicks = reading.ticks
      let now = clock.now
      if let current = baseline, current.docID == reading.docId, reading.running {
        let seconds = BrowserClock.milliseconds(now - current.at) / 1_000
        if seconds > 0 { timerHz = Double(reading.ticks - current.ticks) / seconds }
        baseline = TimerBaseline(docID: reading.docId, ticks: reading.ticks, at: now)
      } else {
        documentChanged = baseline != nil
        baseline = try await startTimer(on: session, clock: clock)
      }
    } catch {
      failures.append("timer:" + BrowserActionError(error).rawValue)
    }
    var domMs: Double?
    var domElements: Int?
    do {
      let measured = try await session.measureSnapshot()
      domMs = measured.ms
      domElements = measured.elements
    } catch {
      failures.append("dom:" + BrowserActionError(error).rawValue)
    }
    var imageMs: Double?
    do {
      imageMs = try await session.captureImage(width: 480)
    } catch {
      failures.append("image:" + BrowserActionError(error).rawValue)
    }
    var navigationMs: Double?
    if includesNavigation {
      do {
        navigationMs = try await session.reloadLabPageAndWait(timeout: .seconds(30))
        baseline = try await startTimer(on: session, clock: clock)
        documentChanged = true
      } catch {
        failures.append("navigation:" + BrowserActionError(error).rawValue)
      }
    }
    return BrowserBackgroundSample(
      elapsedSeconds: BrowserClock.milliseconds(elapsed) / 1_000, placement: placement,
      inWindow: host.inWindow, windowVisible: host.windowVisible,
      reviewWindowShown: visibleReviewViews > 0, otherVisibleWindows: otherVisibleWindowCount(),
      appActive: NSApplication.shared.isActive, documentVisibility: visibility,
      timerTicks: timerTicks, timerHz: timerHz, domSnapshotMs: domMs,
      domSnapshotElements: domElements,
      imageSnapshotMs: imageMs, navigationMs: navigationMs, documentChanged: documentChanged,
      failures: failures)
  }

  private func startTimer(on session: BrowserSession, clock: ContinuousClock) async throws
    -> TimerBaseline
  {
    let started = try await session.startTimerProbe()
    return TimerBaseline(docID: started.docId, ticks: started.ticks, at: clock.now)
  }

  private func finishRun(_ id: UUID, profileName: String, state: BrowserBackgroundRunState) {
    guard let index = backgroundRuns.firstIndex(where: { $0.id == id }),
      backgroundRuns[index].state == .running
    else { return }
    backgroundRuns[index].state = state
    backgroundRuns[index].endedAt = Date()
    if runID == id { endRunOwnership() }
    releaseVisibleHost(for: backgroundRuns[index].profileID)
    record(.backgroundRunEnded(state), profileName: profileName)
  }

  /// Ends a run's claim on the visible host window; a page still parked goes back to the person's
  /// parking choice.
  private func releaseVisibleHost(for profileID: UUID) {
    guard visibleHostProfiles.remove(profileID) != nil, let session = sessions[profileID],
      session.placement != .reviewWindow
    else { return }
    park(session)
  }

  private func endRunOwnership() {
    if let runActivity { ProcessInfo.processInfo.endActivity(runActivity) }
    runActivity = nil
    runTask = nil
    runID = nil
  }

  // MARK: Quit

  /// Stops everything the lab started, for a normal app quit: the sampler, in-flight actions,
  /// loads and every page, and its host windows. Profiles, probes and their WebKit stores stay
  /// on disk. Synchronous and safe to call more than once; a cancelled quit can reopen profiles.
  func shutdown() {
    runTask?.cancel()
    taskRunner.cancel()
    for index in backgroundRuns.indices where backgroundRuns[index].state == .running {
      backgroundRuns[index].state = .cancelled
      backgroundRuns[index].endedAt = Date()
    }
    endRunOwnership()
    visibleHostProfiles.removeAll()
    for session in sessions.values { session.close() }
    sessions.removeAll()
    parkedByPerson.removeAll()
    hostWindows.closeAll()
  }

  /// Visible titled app windows other than the lab's host windows.
  private func otherVisibleWindowCount() -> Int {
    NSApplication.shared.windows.filter { window in
      window.isVisible && window.styleMask.contains(.titled) && !hostWindows.contains(window)
    }.count
  }

  // MARK: Evidence

  func record(_ kind: BrowserLabEvent.Kind, session: BrowserSession) {
    record(kind, profileName: session.profile.name)
  }

  func record(_ kind: BrowserLabEvent.Kind, profileName: String?) {
    if case .blocked(let reason, _) = kind { blockCounts[reason, default: 0] += 1 }
    let event = BrowserLabEvent(id: UUID(), date: Date(), profileName: profileName, kind: kind)
    BrowserReviewLab.prepend(event, to: &events, limit: 300)
  }

  func recordSnapshot(
    _ snapshot: BrowserPageSnapshot, from session: BrowserSession,
    source: BrowserSnapshotTiming.Source = .manual
  ) {
    let timing = BrowserSnapshotTiming(
      date: Date(), profileName: session.profile.name, pageHost: session.pageHost,
      placement: session.placement, source: source, durationMs: snapshot.durationMs,
      elements: snapshot.elements.count, frames: snapshot.frames.count,
      skippedFrames: snapshot.skippedFrames, truncated: snapshot.truncated)
    BrowserReviewLab.prepend(timing, to: &snapshotTimings, limit: 500)
    record(
      .snapshotTaken(
        elements: snapshot.elements.count, frames: snapshot.frames.count, ms: snapshot.durationMs),
      session: session)
  }

  func recordOutcome(_ outcome: BrowserActionOutcome) {
    BrowserReviewLab.prepend(outcome, to: &outcomes, limit: 200)
    evidence.record(outcome)
    record(.action(outcome.kind, outcome.path, outcome.error), profileName: outcome.profileName)
  }

  /// Keeps a sign-in Card's typed outcome: fingerprints, booleans and counts, never a value.
  func recordSignIn(_ outcome: BrowserSignInOutcome) {
    BrowserReviewLab.prepend(outcome, to: &signIns, limit: 100)
    record(
      .signInEnded(outcome.result, refusal: outcome.refusal), profileName: outcome.profileName)
  }

  func recordHostMove(
    from: BrowserPlacement, to: BrowserPlacement, result: BrowserHostMoveResult,
    session: BrowserSession
  ) {
    let check = BrowserHostMoveCheck(
      id: UUID(), date: Date(), profileName: session.profile.name, from: from, to: to,
      result: result)
    BrowserReviewLab.prepend(check, to: &hostMoves, limit: 100)
    record(.moveChecked(result), session: session)
  }

  func recordNavigation(
    host: String?, result: BrowserNavigationRecord.Result, durationMs: Double?,
    httpStatus: Int?, failure: BrowserNavigationFailure?, blockReason: BrowserBlockReason?,
    session: BrowserSession
  ) {
    let navigation = BrowserNavigationRecord(
      date: Date(), profileName: session.profile.name, host: host, result: result,
      durationMs: durationMs, httpStatus: httpStatus, failure: failure, blockReason: blockReason)
    BrowserReviewLab.prepend(navigation, to: &navigations, limit: 300)
  }

  private static func prepend<Element>(_ element: Element, to array: inout [Element], limit: Int) {
    array.insert(element, at: 0)
    if array.count > limit { array.removeLast(array.count - limit) }
  }
}
