import AppCore
import Foundation

/// Runs only the suite a person selected and approved. Actions execute once; read-only assertions
/// may wait for real page state. Results survive app reopen, but interrupted work never resumes.
@MainActor
@Observable
final class BrowserTaskRunner {
  private(set) var candidate: BrowserTaskSuite?
  private(set) var suite: BrowserTaskSuite?
  private(set) var problem: String?
  private(set) var run: BrowserTaskRun?
  private(set) var isRunning = false
  private(set) var waitingForSignIn = false
  private(set) var waitingForExposure = false
  @ObservationIgnored private var digest: String?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private let evidence: BrowserReviewEvidence
  @ObservationIgnored private weak var session: BrowserSession?

  init(evidence: BrowserReviewEvidence) { self.evidence = evidence }

  func select(data: Data) {
    guard !isRunning else { return }
    do {
      candidate = try BrowserTaskSuite.decode(data)
      digest = BrowserTaskSuite.digest(data)
      suite = nil
      problem = nil
    } catch {
      candidate = nil
      suite = nil
      digest = nil
      problem = "invalidSuite"
    }
  }

  func approve(on session: BrowserSession) {
    guard let candidate, !isRunning else { return }
    let fixtures = candidate.sites.allSatisfy(\.ownedFixture)
    guard fixtures || candidate.sites.allSatisfy({ !$0.ownedFixture }) else {
      problem = "mixedRoutesRequireSeparateSuites"
      return
    }
    suite = candidate
    self.session = session
    session.review.configure(
      sites: candidate.sites, route: fixtures ? .directFixture : .authenticatedProxy)
  }

  func start(on session: BrowserSession) {
    guard task == nil, let suite, let digest, !session.isClosed,
      !session.review.isConfiguring, session.review.problem == nil,
      session.review.sites == suite.sites, self.session === session,
      session.review.route != .offline, !evidence.storageProblem
    else {
      problem = "suiteNotReady"
      return
    }
    let run = BrowserTaskRun(suite: suite, digest: digest)
    self.run = run
    problem = nil
    evidence.record(run)
    isRunning = true
    task = Task {
      await execute(suite, session: session)
      isRunning = false
      waitingForSignIn = false
      waitingForExposure = false
      task = nil
    }
  }

  /// Ends the run. Its profile changes stop at once, so nothing it decided, such as a return to
  /// the bot's site under way, loads after the cancel (D136 review F3); the run then winds down
  /// and discards its separate profile.
  func cancel() {
    guard let task else { return }
    task.cancel()
    session?.stopProfileChanges()
  }

  func cancel(ifUsing session: BrowserSession) {
    if self.session === session { cancel() }
  }

  private func execute(_ suite: BrowserTaskSuite, session: BrowserSession) async {
    do {
      for recipe in suite.tasks {
        try Task.checkCancellation()
        guard !session.isClosed else { throw BrowserActionError.sessionClosed }
        var succeeded = true
        for (index, step) in recipe.steps.enumerated() {
          try Task.checkCancellation()
          guard !evidence.storageProblem else { throw RunnerError(code: "evidenceUnavailable") }
          run?.steps.append(
            BrowserTaskRun.StepResult(
              taskID: recipe.id, index: index,
              operation: step.operation.rawValue, succeeded: false, code: "inFlight", durationMs: 0)
          )
          if let run { evidence.record(run) }
          guard !evidence.storageProblem else { throw RunnerError(code: "evidenceUnavailable") }
          let started = ContinuousClock.now
          var code: String?
          do { try await perform(step, session: session) } catch {
            code = (error as? RunnerError)?.code ?? BrowserSessionReview.code(error)
          }
          // The step's record says what it did: a step that finished keeps its result, one cut
          // off by the cancel keeps the code its error maps to. A cancel that landed inside the
          // step then ends the run as cancelled, not completed.
          let passed = step.expectedDenial.map { $0 == code } ?? (code == nil)
          if let last = run?.steps.indices.last {
            run?.steps[last] = BrowserTaskRun.StepResult(
              taskID: recipe.id, index: index,
              operation: step.operation.rawValue, succeeded: passed, code: code,
              durationMs: BrowserClock.milliseconds(since: started))
          }
          if let run { evidence.record(run) }
          try Task.checkCancellation()
          if !passed {
            succeeded = false
            break
          }
        }
        // D136: a separate profile lives for one task; it is discarded, data and all, before
        // the next task starts in the bot's own profile.
        await session.discardSeparate()
        if succeeded { run?.successfulTasks.append(recipe.id) }
        if let run { evidence.record(run) }
      }
      // A cancel during the last task's profile discard still ends the run as cancelled.
      try Task.checkCancellation()
      run?.state = .completed
    } catch {
      run?.state = Task.isCancelled ? .cancelled : .interrupted
      problem = (error as? RunnerError)?.code ?? BrowserSessionReview.code(error)
    }
    run?.endedAt = Date()
    // An interrupted or cancelled task's separate profile is discarded too.
    await session.discardSeparate()
    session.review.collectGatewayEvidence()
    if let run { evidence.record(run) }
  }

  /// `session` is the bot's own session. Each step works in the profile the bot is in now: a
  /// separate one after a move to another site (D136), opened and loaded before the step ends.
  private func perform(_ step: BrowserTaskSuite.Step, session root: BrowserSession) async throws {
    guard root.control == .watching else { throw BrowserActionError.userInControl }
    try await root.settleLanes()
    let session = root.lane
    switch step.operation {
    case .navigate:
      guard let text = step.url, let url = URL(string: text) else {
        throw BrowserActionError.invalidResult
      }
      try await root.navigateForSuite(url)
    case .snapshot:
      _ = try await session.snapshotForSuite()
    case .expect:
      try await assertPage(step, session: root)
    case .signIn:
      waitingForSignIn = true
      defer { waitingForSignIn = false }
      _ = try await session.snapshotForSuite()
      session.review.offerSavedLogin()
      let deadline = ContinuousClock.now + .seconds(120)
      while true {
        try Task.checkCancellation()
        if session.review.lastSavedFillMatched == true && session.review.savedCard == nil { return }
        if let problem = session.review.problem { throw RunnerError(code: problem) }
        guard ContinuousClock.now < deadline else { throw BrowserActionError.scriptTimedOut }
        try await Task.sleep(for: .milliseconds(100))
      }
    case .click, .download, .type, .select:
      guard let selector = step.selector else { throw BrowserActionError.unknownRef }
      let (snapshot, element) = try await locate(selector, session: root)
      // `locate` may have waited for a move to settle; act where the snapshot was taken.
      let session = root.lane
      guard session.snapshot?.id == snapshot.id else { throw BrowserActionError.staleSnapshot }
      let reference = snapshot.reference(to: element)
      let path: BrowserInputPath = step.nativeInput == true ? .native : .script
      let beforeCommit = session.commitCount
      var downloadID: UUID?
      let request: BrowserActionRequest
      switch step.operation {
      case .click, .download:
        try await waitForExposureIfRequired(reference, snapshot: snapshot, session: session)
        if step.operation == .download { downloadID = try session.review.authorizeDownload() }
        request = .click(reference, path)
      case .type:
        guard let text = step.text else { throw BrowserActionError.emptyText }
        request = .type(reference, text: text, replace: true, path)
      case .select:
        guard let text = step.text, let options = element.options else {
          throw BrowserActionError.optionUnavailable
        }
        let matches = options.indices.filter { options[$0].label == text && !options[$0].disabled }
        guard matches.count == 1, let index = matches.first else {
          throw BrowserActionError.optionUnavailable
        }
        request = .select(reference, optionIndex: index, optionLabel: text)
      default: throw BrowserActionError.invalidResult
      }
      let result = try await session.performForSuite(request)
      if step.operation == .download {
        // A completed/quarantined file is authoritative even if the old JS context disappeared
        // after starting it. No action is retried to obtain this outcome.
        let deadline = ContinuousClock.now + .seconds(30)
        guard let downloadID else { throw BrowserActionError.invalidResult }
        while true {
          try Task.checkCancellation()
          if let receipt = session.review.downloadOutcome(id: downloadID),
            receipt.state != .authorized
          {
            guard receipt.state == .completed, receipt.quarantined else {
              throw RunnerError(code: receipt.code ?? "downloadFailed")
            }
            break
          }
          if let error = result.error, error != .scriptFailed && error != .frameUnavailable {
            throw error
          }
          guard ContinuousClock.now < deadline else { throw BrowserActionError.scriptTimedOut }
          try await Task.sleep(for: .milliseconds(100))
        }
      } else {
        if let error = result.error {
          // An action that replaced its own JS context is never rerun. Only the actual
          // completed WebKit navigation can settle that outcome; a later expect step still
          // checks the requested page content before the task can be counted successful.
          guard result.navigationStarted, error == .scriptFailed || error == .frameUnavailable
          else { throw error }
          let deadline = ContinuousClock.now + .seconds(30)
          while session.isLoading {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw error }
            try await Task.sleep(for: .milliseconds(50))
          }
          guard session.commitCount > beforeCommit, case .finished = session.navigation else {
            throw error
          }
        } else if result.verified == false {
          // The native path verifies with a separate JS call after the last observed key-up;
          // a slow web process can still be inserting the typed characters when that read
          // runs (one-off 2026-11-14 `type:invalidResult` whose event wait timed out first).
          // Settle with a waiting read of the live page: the typed value must actually be in
          // the field, otherwise the step still fails. This is not an action retry.
          guard step.nativeInput == true, step.operation == .type, let text = step.text else {
            throw BrowserActionError.invalidResult
          }
          try await waitForTypedValue(text, selector: selector, root: root)
        }
        if step.nativeInput == true {
          let events = result.nativeInputEvents.filter(\.onTarget)
          guard !events.isEmpty, events.allSatisfy(\.trusted) else {
            throw RunnerError(code: "untrustedInput")
          }
        }
        if result.navigationStarted || session.isLoading || session.commitCount != beforeCommit {
          // A navigation the action started is settled once nothing loads any more: it
          // committed and finished, failed, or a policy decision stopped it without a commit.
          // A step that returns earlier lets the next waiting read straddle the commit and
          // throw staleSnapshot. A move to another profile (D136) settles on the lane change;
          // `settleLanes` reports its outcome at once, a failed opening's own code included.
          let deadline = ContinuousClock.now + .seconds(30)
          while session === root.lane, session.isLoading {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw BrowserActionError.navigationFailed }
            try await Task.sleep(for: .milliseconds(50))
          }
          try await root.settleLanes()
          if session === root.lane {
            if case .failed = session.navigation { throw BrowserActionError.navigationFailed }
            if case .blocked = session.navigation { throw BrowserActionError.navigationFailed }
            // Stopped without a commit and without a move: what the step asked for never loaded.
            if result.navigationStarted, session.commitCount == beforeCommit {
              throw BrowserActionError.navigationFailed
            }
          }
        }
      }
      // A link to another site opened in a separate profile; its load must have succeeded.
      try await root.settleLanes()
    }
  }

  private func waitForExposureIfRequired(
    _ reference: BrowserElementRef,
    snapshot: BrowserPageSnapshot, session: BrowserSession
  ) async throws {
    let required = try await session.review.requiresExposureConfirmation(reference)
    guard required else { return }
    waitingForExposure = true
    defer { waitingForExposure = false }
    let deadline = ContinuousClock.now + .seconds(120)
    while !session.review.hasCurrentExposureConfirmation {
      try Task.checkCancellation()
      guard !session.isClosed, session.commitCount == snapshot.commit,
        ContinuousClock.now < deadline
      else { throw BrowserActionError.staleSnapshot }
      try await Task.sleep(for: .milliseconds(100))
    }
  }

  /// A waiting read, not an action retry: the one-shot action is over, this only settles its
  /// reported verification against the live page. The field must hold exactly `text`: the
  /// isolated world compares its live value and answers only whether it matches, never with
  /// the value, whose snapshot form is cleaned and capped. A commit landing during a capture is
  /// a settling read too, never a failed step.
  private func waitForTypedValue(
    _ text: String, selector: BrowserTaskSuite.Selector, root: BrowserSession
  ) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while true {
      try Task.checkCancellation()
      try await root.settleLanes()
      let lane = root.lane
      do {
        let snapshot = try await lane.snapshotForSuite()
        if let element = try? match(selector, in: snapshot),
          (try? await lane.fieldHolds(text, at: snapshot.reference(to: element))) == true
        {
          return
        }
      } catch BrowserActionError.staleSnapshot {}
      guard ContinuousClock.now < deadline else { throw BrowserActionError.invalidResult }
      try await Task.sleep(for: .milliseconds(100))
    }
  }

  private func assertPage(_ step: BrowserTaskSuite.Step, session root: BrowserSession) async throws
  {
    let deadline = ContinuousClock.now + .seconds(10)
    while true {
      try Task.checkCancellation()
      try await root.settleLanes()
      // A commit landing between a capture's commit read and its page calls is a settling
      // read, not a failed assertion; the loop re-captures and still requires the content.
      let snapshot: BrowserPageSnapshot
      do {
        snapshot = try await root.lane.snapshotForSuite()
      } catch BrowserActionError.staleSnapshot {
        guard ContinuousClock.now < deadline else { throw BrowserActionError.staleSnapshot }
        try await Task.sleep(for: .milliseconds(100))
        continue
      }
      if let selector = step.selector, let element = try? match(selector, in: snapshot) {
        if step.text == nil || element.value == step.text || element.name == step.text { return }
      } else if step.selector == nil, let text = step.text,
        snapshot.elements.contains(where: { $0.name == text || $0.value == text })
      {
        return
      }
      guard ContinuousClock.now < deadline else { throw RunnerError(code: "assertionNotSatisfied") }
      try await Task.sleep(for: .milliseconds(100))
    }
  }

  /// Waiting reads are not retries of an action. Missing/delayed frame registrations and live
  /// page content can settle, but ambiguous selectors never dispatch input.
  private func locate(_ selector: BrowserTaskSuite.Selector, session root: BrowserSession)
    async throws -> (BrowserPageSnapshot, BrowserElement)
  {
    let deadline = ContinuousClock.now + .seconds(10)
    while true {
      try Task.checkCancellation()
      try await root.settleLanes()
      // Same settling-read rule as `assertPage`: a commit landing during a capture is
      // retried, never dispatched into.
      let snapshot: BrowserPageSnapshot
      do {
        snapshot = try await root.lane.snapshotForSuite()
      } catch BrowserActionError.staleSnapshot {
        guard ContinuousClock.now < deadline else { throw BrowserActionError.staleSnapshot }
        try await Task.sleep(for: .milliseconds(100))
        continue
      }
      do { return (snapshot, try match(selector, in: snapshot)) } catch BrowserActionError
        .unknownRef
      {
        guard ContinuousClock.now < deadline else { throw BrowserActionError.unknownRef }
        try await Task.sleep(for: .milliseconds(100))
      }
    }
  }

  private func match(_ selector: BrowserTaskSuite.Selector, in snapshot: BrowserPageSnapshot) throws
    -> BrowserElement
  {
    let matches = snapshot.elements.filter { element in
      guard element.role == selector.role, element.name == selector.name else { return false }
      if let origin = selector.frameOrigin {
        return element.frame > 0 && element.frame < snapshot.frames.count
          && snapshot.frames[element.frame].origin == origin
      }
      return element.frame == 0
    }
    guard matches.count <= 1 else { throw RunnerError(code: "ambiguousSelector") }
    guard matches.count == 1, let element = matches.first else {
      throw BrowserActionError.unknownRef
    }
    return element
  }

  private struct RunnerError: Error { let code: String }
}
