import AppCore
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The typed results export: raw evidence from one launch of the review lab, never an S3 verdict.
/// It contains no page text, typed text, screenshots or URLs beyond page hosts.
struct BrowserReviewReport: Codable, Sendable {
  struct Environment: Codable, Sendable {
    let appVersion: String
    let appBuild: String
    let operatingSystem: String
    let hardwareModel: String?
    let physicalMemoryBytes: UInt64
  }

  struct Profile: Codable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let probeSetAt: Date?
    let openAtExport: Bool
  }

  /// One S3 question: what this lab observed, and what it cannot establish here.
  struct Row: Codable, Sendable {
    enum Status: String, Codable, Sendable {
      /// The export contains this launch's raw evidence for the question.
      case observedHere = "observed_here"
      /// The lab can measure it, but no evidence was gathered in this launch.
      case notExercised = "not_exercised"
      /// A prerequisite outside this lab is missing.
      case unavailable
    }

    let id: String
    let question: String
    let status: Status
    let evidence: String
    let missing: String
  }

  /// One background run scored in each closed-window case it has samples in. Rates are the
  /// samples' own `timerHz`; percentiles are nearest-rank.
  struct RunSummary: Codable, Sendable {
    let runID: UUID
    let profileName: String
    let scheduling: BrowserSchedulingPolicy
    let configuration: BrowserBackgroundConfiguration
    let state: BrowserBackgroundRunState
    let thresholdHz: Double
    let maximumGapSeconds: Double
    let firstSampleSeconds: Double?
    let lastSampleSeconds: Double?
    /// Visible-host samples whose one-point window was occluded or not visible at the time.
    let occludedVisibleHostSamples: Int
    /// Keyed by `BrowserClosedWindowCase` raw value; cases without samples are absent.
    let cases: [String: BrowserContinuity.Summary]
  }

  let schema: String
  let note: String
  let generatedAt: Date
  let launchStartedAt: Date
  let environment: Environment
  let network: String
  let parkingMode: BrowserParkingMode
  let schedulingForNewSessions: BrowserSchedulingPolicy
  let profiles: [Profile]
  let blockedCounts: [String: Int]
  let rows: [Row]
  let isolationChecks: [BrowserIsolationCheck]
  let snapshotTimings: [BrowserSnapshotTiming]
  let actions: [BrowserActionOutcome]
  let hostMoves: [BrowserHostMoveCheck]
  let backgroundRuns: [BrowserBackgroundRunRecord]
  let runSummaries: [RunSummary]
  let navigations: [BrowserNavigationRecord]
  let signIns: [BrowserSignInOutcome]
  let reviewEvidence: BrowserReviewEvidence.Contents
}

/// The encoded report, handed to the system save panel as a JSON file.
struct BrowserReviewExport: Transferable, Sendable {
  let data: Data

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .json) { export in export.data }
  }
}

extension BrowserReviewLab {
  var exportFilename: String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return "memoshi-s3-browser-review-\(formatter.string(from: Date())).json"
  }

  func makeExport() throws -> BrowserReviewExport {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return BrowserReviewExport(data: try encoder.encode(makeReport()))
  }

  func exportFinished(_ result: Result<URL, any Error>) {
    switch result {
    case .success: record(.exportWritten, profileName: nil)
    case .failure: record(.exportFailed, profileName: nil)
    }
  }

  func makeReport() -> BrowserReviewReport {
    for session in sessions.values { session.review.collectGatewayEvidence() }
    return BrowserReviewReport(
      schema: "memoshi.s3-browser-review/3",
      note:
        "Raw evidence from one launch of the Browser Review lab. It is not an S3 pass or fail: the gate review scores these measurements against the phase-0 S3 thresholds on the reference Mac.",
      generatedAt: Date(), launchStartedAt: launchDate, environment: Self.environment(),
      network:
        "offline by default; per-session authenticated proxy or explicitly selected direct loopback-fixture mode. Gateway decisions are not packet-capture coverage.",
      parkingMode: parkingMode, schedulingForNewSessions: schedulingForNewSessions,
      profiles: profiles.map { profile in
        BrowserReviewReport.Profile(
          id: profile.id, name: profile.name, createdAt: profile.createdAt,
          probeSetAt: profile.probe?.setAt, openAtExport: sessions[profile.id] != nil)
      },
      blockedCounts: Dictionary(
        uniqueKeysWithValues: blockCounts.map { ($0.key.rawValue, $0.value) }),
      rows: [
        isolationRow(), trustedInputRow(), taskSuccessRow(), closedWindowsRow(),
        closedWindowsFallbackRow(), snapshotSpeedRow(), proxyRow(), secretRow(), framesRow(),
        formGateRow(), liveViewRow(), mobileRow(),
      ],
      isolationChecks: isolationChecks, snapshotTimings: snapshotTimings, actions: outcomes,
      hostMoves: hostMoves, backgroundRuns: backgroundRuns,
      runSummaries: backgroundRuns.map(Self.runSummary), navigations: navigations,
      signIns: signIns, reviewEvidence: evidence.contents)
  }

  private func isolationRow() -> BrowserReviewReport.Row {
    let comparisons = isolationChecks.filter(\.hasComparison)
    let missing =
      "Safari is compared by hand: Safari › Settings › Privacy › Manage Website Data must not list “memoshi.invalid”. The iOS store checks (S3.8, rows 10–14) are outside this Mac lab."
    guard let latest = comparisons.first else {
      return BrowserReviewReport.Row(
        id: "S3.1 · row 5", question: "Per-profile store isolation and relaunch persistence",
        status: .notExercised,
        evidence: "No check has compared two or more review profiles with a probe set.",
        missing: missing)
    }
    let leaks = latest.observations.filter(\.foundForeignProbe).count
    let unreadable = latest.observations.filter(\.readFailed).count
    let lost = latest.observations.filter {
      !$0.readFailed && $0.expectsOwnProbe && !$0.foundOwnProbe
    }.count
    let persisted = latest.observations.filter {
      $0.expectsOwnProbe && $0.foundOwnProbe && $0.probeSetBeforeThisLaunch == true
    }.count
    return BrowserReviewReport.Row(
      id: "S3.1 · row 5", question: "Per-profile store isolation and relaunch persistence",
      status: .observedHere,
      evidence:
        "Latest of \(comparisons.count) comparisons: \(latest.metCount)/\(latest.observations.count) profiles met expectations; profiles seeing another profile's probe: \(leaks); own probe missing: \(lost); stores that did not answer: \(unreadable); own probe found after a relaunch: \(persisted).",
      missing: missing)
  }

  private func trustedInputRow() -> BrowserReviewReport.Row {
    let native = outcomes.filter { $0.path == .native && $0.error == nil }
    let onScreen = native.filter { $0.placement == .reviewWindow && $0.windowVisible }
    let hiddenWindows = native.filter {
      $0.placement == .offscreenWindow || $0.placement == .onePointWindow
    }
    let refusals = outcomes.filter { $0.error == .nativeInputNeedsWindow }.count
    let missing =
      "Native clicks and keys on three pages, on screen and in a hidden host window. A view in no window cannot receive NSEvents, so the detached case has no native-input result."
    guard !onScreen.isEmpty || !hiddenWindows.isEmpty else {
      return BrowserReviewReport.Row(
        id: "S3.2 · row 2", question: "Synthesized NSEvent input arrives as trusted input",
        status: .notExercised,
        evidence: "No completed native action yet; detached refusals: \(refusals).",
        missing: missing)
    }
    return BrowserReviewReport.Row(
      id: "S3.2 · row 2", question: "Synthesized NSEvent input arrives as trusted input",
      status: .observedHere,
      evidence:
        "On screen: \(Self.inputSummary(onScreen)). Hidden host windows (experiment): \(Self.inputSummary(hiddenWindows)). Detached refusals: \(refusals).",
      missing: missing)
  }

  private func taskSuccessRow() -> BrowserReviewReport.Row {
    let runs = evidence.contents.runs
    return BrowserReviewReport.Row(
      id: "S3.3 · row 1", question: "Share of 20 scripted tasks on 5 real sites",
      status: runs.isEmpty ? .notExercised : .observedHere,
      evidence: runs.last.map {
        "Latest durable run: \($0.state.rawValue), \($0.successfulTasks.count)/\($0.taskCount) tasks, \($0.steps.count) attempted steps, \($0.realSiteCount) declared real sites. Owned fixtures are excluded from that count; declarations are not independent site/account authorization proof."
      } ?? "No selected, explicitly approved recipe has run.",
      missing:
        "Five explicitly selected safe real sites and owned test accounts, the 20-task matrix, and qualifying reference-hardware/network evidence. No gate pass follows from local fixture successes."
    )
  }

  private func closedWindowsRow() -> BrowserReviewReport.Row {
    let id = "S3.5 · row 3"
    let question = "A WKWebView in no window keeps running with windows closed"
    let missing =
      "The detached view (no window) is the gate case. WebKit aligns a hidden page's repeating timers to one second whatever the inactive scheduling policy, so sub-second timers run at 1 Hz here. The MenuBarExtra scene provides reopening with every document window closed. Qualification requires timers ≥ 1 Hz and working takeSnapshot for 10 minutes, including on the reference Mac."
    guard let best = longestRun(in: .detached) else {
      return BrowserReviewReport.Row(
        id: id, question: question, status: .notExercised,
        evidence: "No detached samples with every app window closed.", missing: missing)
    }
    return BrowserReviewReport.Row(
      id: id, question: question, status: .observedHere,
      evidence: Self.caseEvidence(best.run, best.summary, label: "detached"), missing: missing)
  }

  private func closedWindowsFallbackRow() -> BrowserReviewReport.Row {
    let id = "S3.5 · row 3 fallback"
    let question = "A visible one-point host window keeps the page running with windows closed"
    let missing =
      "06's row-3 fallback, not the detached gate case. WebKit treats the page as visible only while its window is visible and unoccluded, so a sleeping display, a locked screen or a covering window would throttle it again; the reference Mac must repeat this run."
    guard let best = longestRun(in: .visibleHost) else {
      return BrowserReviewReport.Row(
        id: id, question: question, status: .notExercised,
        evidence: "No visible-host samples with every app window closed.", missing: missing)
    }
    let occluded = best.run.samples.filter {
      BrowserClosedWindowCase.visibleHost.contains($0) && !$0.windowVisible
    }.count
    return BrowserReviewReport.Row(
      id: id, question: question, status: .observedHere,
      evidence: Self.caseEvidence(best.run, best.summary, label: "visible-host")
        + " Samples with the host window occluded or not visible: \(occluded).",
      missing: missing)
  }

  /// The run whose samples in the case span longest, with its summary.
  private func longestRun(in closedCase: BrowserClosedWindowCase) -> (
    run: BrowserBackgroundRunRecord, summary: BrowserContinuity.Summary
  )? {
    backgroundRuns.map { (run: $0, summary: $0.summary(of: closedCase)) }
      .filter { $0.summary.samples > 0 }
      .max { $0.summary.longestCaseSpanSeconds < $1.summary.longestCaseSpanSeconds }
  }

  private func snapshotSpeedRow() -> BrowserReviewReport.Row {
    let measured = snapshotTimings.filter { $0.source != .background }
    let durations = measured.map(\.durationMs)
    let missing =
      "Thirty real pages on the reference 16 GB M1 Mac; developer machines show spread only."
    guard let p50 = BrowserClock.percentile(durations, 0.5),
      let p90 = BrowserClock.percentile(durations, 0.9)
    else {
      return BrowserReviewReport.Row(
        id: "row 4", question: "Page snapshot p50 over 30 real pages", status: .notExercised,
        evidence: "No snapshots yet.", missing: missing)
    }
    let hosts = Set(measured.compactMap(\.pageHost)).count
    return BrowserReviewReport.Row(
      id: "row 4", question: "Page snapshot p50 over 30 real pages", status: .observedHere,
      evidence:
        "\(measured.count) UI/recipe snapshots on \(hosts) page hosts: p50 \(Int(p50.rounded())) ms, p90 \(Int(p90.rounded())) ms. Repeated reads are samples, not distinct real pages.",
      missing: missing)
  }

  private func proxyRow() -> BrowserReviewReport.Row {
    let decisions = evidence.contents.gateway
    return BrowserReviewReport.Row(
      id: "S3.6 · row 6", question: "Every request goes through the egress gateway",
      status: decisions.isEmpty ? .notExercised : .observedHere,
      evidence:
        "Durable gateway decisions: \(decisions.count); allowed: \(decisions.filter(\.allowed).count). Public review sessions configure authenticated proxies before loading. Direct loopback-fixture mode is not proxy evidence. CONNECT observes hosts/ports, not encrypted HTTP methods or credentials.",
      missing:
        "Packet capture over 20 authorized sites proving coverage, no direct QUIC or DNS, and reference Mac/mobile runs. Seeing gateway requests is not proof of no bypass."
    )
  }

  private func secretRow() -> BrowserReviewReport.Row {
    let id = "S3.4 · row 7"
    let question = "Sign-in fill keeps the secret out of transcripts and logs"
    let missing =
      "The origin-bound app Keychain path still requires entitled signed-app/owned-account proof, and an external canary scan of transcripts, event log, unified logs and crash reports. No browser_eval API is exposed in this review lab."
    let filled = signIns.filter { $0.result == .filled }
    let brokerFills = evidence.contents.decisions.filter {
      $0.operation == .signIn && $0.allowed && $0.code.hasPrefix("keychainFilled")
    }.count
    guard !filled.isEmpty || brokerFills > 0 else {
      return BrowserReviewReport.Row(
        id: id, question: question, status: .notExercised,
        evidence:
          "No development sign-in Card has filled. Lab actions refuse credential fields; HTTP authentication is declined. Refused or declined Cards: \(signIns.count).",
        missing: missing)
    }
    let receipts = filled.filter { $0.pageReceiptMatched == true }.count
    let dom = filled.filter { $0.domMatched == true }.count
    let masked = filled.filter { $0.maskedFieldsAfterFill == 2 }.count
    let leaked = filled.filter { $0.snapshotContainsCanary != false }.count
    let harness = filled.filter { $0.source == .harnessFile }.count
    let refusals = signIns.filter { $0.result == .refused }.compactMap(\.refusal)
    return BrowserReviewReport.Row(
      id: id, question: question, status: .observedHere,
      evidence:
        "Broker fills verified in the isolated world (durable): \(brokerFills). Development canary Card fills on the offline lab page this launch: \(filled.count) (harness file: \(harness)). Page-script canary receipts matched: \(receipts)/\(filled.count); DOM equal: \(dom)/\(filled.count); both fields masked: \(masked)/\(filled.count); verification snapshots containing a canary or unchecked: \(leaked). Refusals: \(refusals.isEmpty ? "none" : refusals.joined(separator: ", ")). External transcript/log/crash scanning is separate and not inferred.",
      missing: missing)
  }

  private func framesRow() -> BrowserReviewReport.Row {
    let framed = snapshotTimings.filter { $0.source != .background && $0.frames > 1 }.count
    let frameActions = outcomes.filter { ($0.frame ?? 0) > 0 && $0.error == nil }.count
    return BrowserReviewReport.Row(
      id: "row 8", question: "Cross-origin frame snapshot and click",
      status: framed > 0 ? .observedHere : .notExercised,
      evidence:
        "Snapshots including registered subframes: \(framed); completed input actions inside frames: \(frameActions).",
      missing:
        "Real cross-site frame/native-input exercises on the reference hardware. WKJSHandle-backed frame lookup and guarded native coordinate mapping are implemented; unsupported transforms fail closed."
    )
  }

  private func formGateRow() -> BrowserReviewReport.Row {
    let decisions = evidence.contents.decisions.filter {
      $0.operation == .form || $0.code == "interactRequired"
    }
    return BrowserReviewReport.Row(
      id: "row 9", question: "A POST on a site without interact is blocked",
      status: decisions.isEmpty ? .notExercised : .observedHere,
      evidence:
        "Durable form decisions: \(decisions.count); denied: \(decisions.filter { !$0.allowed }.count). The navigation policy rechecks current site/Interact/document authority for every form navigation; the willSubmitForm handler rechecks too, but WebKit on macOS 27.0.1 was not observed calling it (2026-11-19). WKFormInfo.formValues is never read. Nonconsequential forms require a staged action; consequential/money actions are refused.",
      missing:
        "Exercise both authorized and denied POSTs against owned fixtures, then authorized real sites. Reference hardware and request-receipt evidence are still required."
    )
  }

  private func liveViewRow() -> BrowserReviewReport.Row {
    let checked = hostMoves.filter { $0.result != .noBaseline }
    let same = checked.filter { $0.result == .sameDocument }.count
    let replaced = checked.filter { $0.result == .documentChanged }.count
    let intoLive = checked.filter { $0.to == .reviewWindow && $0.result == .sameDocument }.count
    return BrowserReviewReport.Row(
      id: "S3.7", question: "The same view moves into live view and takeover without reloading",
      status: checked.isEmpty ? .notExercised : .observedHere,
      evidence:
        "Moves checked: \(checked.count); same document: \(same) (into the live view: \(intoLive)); replaced document: \(replaced); inconclusive: \(checked.count - same - replaced).",
      missing:
        "Per-profile memory cost needs an external measurement of each WebContent process, which this report cannot make; WebKit has no public API for it."
    )
  }

  private func mobileRow() -> BrowserReviewReport.Row {
    BrowserReviewReport.Row(
      id: "S3.8 · rows 10–14",
      question: "iPhone and iPad isolation, input, background, proxy and uploads",
      status: .unavailable, evidence: "This is a Mac lab.",
      missing: "Runs on the user's iPhone 14 Pro and iPad Pro under the device hold.")
  }

  private static func inputSummary(_ outcomes: [BrowserActionOutcome]) -> String {
    let events = outcomes.flatMap(\.nativeInputEvents).filter(\.onTarget)
    let trusted = events.filter(\.trusted).count
    let hosts = Set(outcomes.compactMap(\.pageHost)).count
    return
      "\(outcomes.count) actions on \(hosts) page hosts, \(trusted)/\(events.count) target key and mouse events trusted"
  }

  /// A run scored in every closed-window case it has samples in.
  private static func runSummary(_ run: BrowserBackgroundRunRecord)
    -> BrowserReviewReport
    .RunSummary
  {
    var cases: [String: BrowserContinuity.Summary] = [:]
    for closedCase in BrowserClosedWindowCase.allCases {
      let summary = run.summary(of: closedCase)
      if summary.samples > 0 { cases[closedCase.rawValue] = summary }
    }
    return BrowserReviewReport.RunSummary(
      runID: run.id, profileName: run.profileName, scheduling: run.scheduling,
      configuration: run.configuration, state: run.state,
      thresholdHz: BrowserClosedWindowCase.thresholdHz, maximumGapSeconds: run.maximumGapSeconds,
      firstSampleSeconds: run.samples.first?.elapsedSeconds,
      lastSampleSeconds: run.samples.last?.elapsedSeconds,
      occludedVisibleHostSamples: run.samples.filter {
        BrowserClosedWindowCase.visibleHost.contains($0) && !$0.windowVisible
      }.count,
      cases: cases)
  }

  /// One case's raw numbers, with three decimals so a rate just under 1 Hz never rounds up.
  private static func caseEvidence(
    _ run: BrowserBackgroundRunRecord, _ summary: BrowserContinuity.Summary, label: String
  ) -> String {
    func hertz(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "none" }
    let span = String(format: "%.1f", summary.longestCaseSpanSeconds)
    let passing = String(format: "%.1f", summary.longestPassingSpanSeconds)
    let gap = String(format: "%.2f", summary.largestGapSeconds)
    return
      "Run of \(run.configuration.minutes) min sampled every \(run.configuration.sampleSeconds) s, scheduling \(run.scheduling.rawValue), \(run.state.rawValue): \(summary.samples) \(label) samples with every app window closed. Longest continuous span \(span) s (gaps up to \(Int(run.maximumGapSeconds)) s; largest gap \(gap) s), of which \(passing) s with every sample at or above 1 Hz and both snapshots working. Timer rate (10 Hz target) min \(hertz(summary.minimumHz)), median \(hertz(summary.medianHz)), p95 \(hertz(summary.p95Hz)), max \(hertz(summary.maximumHz)) Hz; \(summary.samplesBelowThreshold)/\(summary.rates) samples below 1 Hz. takeSnapshot and DOM snapshot both succeeded \(summary.snapshotSuccesses)/\(summary.samples)."
  }

  private static func environment() -> BrowserReviewReport.Environment {
    let info = Bundle.main.infoDictionary ?? [:]
    return BrowserReviewReport.Environment(
      appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
      appBuild: info["CFBundleVersion"] as? String ?? "unknown",
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      hardwareModel: hardwareModel(), physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
  }

  private static func hardwareModel() -> String? {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return nil }
    return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
  }
}
