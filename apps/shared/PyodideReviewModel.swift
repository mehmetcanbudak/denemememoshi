import Dispatch
import Foundation
import Observation
import PyodideSpike
import SwiftUI

@MainActor
@Observable
final class PyodideReviewModel {
  enum Action: String {
    case startup, bridge, timeout, cancellation, pandas, background, continuedBackground
  }

  private(set) var status: LocalizedStringResource =
    "Not started. No Python interpreter has been created."
  private(set) var failure: PyodideFailure?
  private(set) var evidenceProblem: LocalizedStringResource?
  private(set) var hostState: PyodideHost.State = .idle
  private(set) var startup: PyodideStartup?
  private(set) var cellStartedAt: Date?
  private(set) var isBusy = false
  private(set) var waitingForContinuedTask = false
  private(set) var continuedStatus: LocalizedStringResource =
    "No continued-processing task requested."
  private(set) var activeAction: Action?
  private(set) var bridgeCompleted = 0
  private(set) var bridgeRequested = 0
  private(set) var report: PyodideMeasurementReport?
  private(set) var files: [PyodideReviewFile] = []
  private(set) var events: [PyodideReviewEvent] = []
  private(set) var presentation: PyodideReviewResultPresentation?
  private(set) var directory: URL?
  private(set) var latestSnapshot: PyodideReviewFile?
  private(set) var omittedFileEntries = 0
  private(set) var omittedEvents = 0

  @ObservationIgnored private var evidence: PyodideReviewEvidence?
  @ObservationIgnored private var driver: PyodideMeasurementDriver?
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var monitor: Task<Void, Never>?
  @ObservationIgnored private var memoryPressure: (any DispatchSourceMemoryPressure)?
  @ObservationIgnored private var sessionID = UUID()
  @ObservationIgnored private var createdAt = Date()
  @ObservationIgnored private var operationID: UUID?
  @ObservationIgnored private var observedCellID: UUID?
  @ObservationIgnored private var scene = "unobserved"
  @ObservationIgnored private var actionCount = 0
  private static var attemptedFirstLaunch = false
  #if os(iOS)
    @ObservationIgnored private var continued: PyodideReviewContinuedProcessing?
  #endif

  var canRun: Bool {
    !isBusy && !waitingForContinuedTask && hostState == .ready && actionCount < 100
  }
  var canStart: Bool {
    !isBusy && !waitingForContinuedTask && hostState != .ready
      && (actionCount < 100 || hostState == .closed)
  }
  var canCancel: Bool { isBusy || waitingForContinuedTask || hostState == .ready }
  var canClose: Bool { driver != nil && hostState != .closed }

  /// The only path that creates storage, a PyodideBotFolder, the hidden host and the driver.
  func start() {
    guard canStart else { return }
    do {
      if driver == nil || hostState == .closed { try createSession() }
    } catch {
      failure = (error as? PyodideFailure) ?? .fileUnavailable
      status = "Could not create a private review directory. No interpreter was started."
      return
    }
    guard let driver else { return }
    let first = !Self.attemptedFirstLaunch
    if first { Self.attemptedFirstLaunch = true }
    run(.startup) { [self] in
      record(
        first ? "first-startup-attempt-this-app-launch" : "explicit-interpreter-recreation-not-cold"
      )
      if first {
        startup = try await driver.recordFirstLaunchStartup()
      } else {
        startup = try await driver.host.start()
      }
      status =
        first
        ? "This app launch's first interpreter is ready. This is one sample, not a p95."
        : "Interpreter ready. This recreation is not a cold app-launch sample."
    }
  }

  func runBridge(count: Int) {
    guard canRun, [1, 20].contains(count), let driver, let evidence else { return }
    bridgeCompleted = 0
    bridgeRequested = count
    run(.bridge) { [self] in
      for index in 1...count {
        try Task.checkCancellation()
        // One driver call at a time retains every successful return even if a later call fails.
        // Driver scenario labels are bridge-1; native events identify the actual call number.
        let results = try await driver.runBridgeCalls(count: 1)
        guard let result = results.first else { throw PyodideFailure.scriptFailed }
        record(
          "scientific-bridge-returned",
          detail: "call-\(index)-of-\(count);request-\(result.requestID)")
        let saved = try await Task.detached(priority: .utility) {
          var saved = [
            try evidence.saveJSON(result, category: "results", name: "scientific-result")
          ]
          for figure in result.figures {
            saved.append(
              try evidence.save(
                figure.png, category: "figures", name: "matplotlib", extension: "png"))
          }
          for artifact in result.artifacts {
            saved.append(try evidence.file(path: artifact.path, expectedSHA256: artifact.sha256))
          }
          return saved
        }.value
        saved.forEach(addFile)
        presentation = PyodideReviewResultPresentation(result: result)
        bridgeCompleted = index
        try checkpoint()
      }
      status =
        "Scientific bridge completed. Genuine text, native table, PNG and CSV evidence was saved."
    }
  }

  func runTimeout() {
    guard canRun, let driver else { return }
    run(.timeout) { [self] in
      try await driver.runTimeoutProbe()
      status = "Timeout observed on the infinite cell. The realm was discarded; restart explicitly."
    }
  }

  func runCancellation() {
    guard canRun, let driver else { return }
    run(.cancellation) { [self] in
      try await driver.runCancellationProbe()
      status = "Cancellation observed after the infinite cell started. The realm was discarded."
    }
  }

  func runPandas(runs: Int) {
    guard canRun, [1, 5].contains(runs), let driver else { return }
    run(.pandas) { [self] in
      try await driver.runPandasMemoryWorkload(runs: runs, secondsPerRun: 600)
      status =
        "Pandas measurement finished. WebContent peak footprint and jetsam still require external evidence."
    }
  }

  func runBackground() {
    guard canRun, let driver else { return }
    run(.background) { [self] in
      try await driver.runBackgroundWorkload(insideContinuedTask: false)
      status =
        "Background probe returned. Inspect the lifecycle events; no continued-processing grant was used."
    }
  }

  #if os(iOS)
    func requestContinuedBackground() {
      guard canRun else { return }
      if continued == nil { continued = PyodideReviewContinuedProcessing() }
      waitingForContinuedTask = true
      failure = nil
      continuedStatus = "Requesting a task. No grant has been observed."
      status =
        "Waiting for an actual continued-processing launch callback; no workload has started."
      continued?.request { [weak self] event in self?.continuedEvent(event) }
    }

    private func continuedEvent(_ event: PyodideReviewContinuedProcessing.Event) {
      switch event {
      case .requested(let identifier):
        record("continued-task-requested-not-granted", detail: identifier)
      case .submitted:
        record("continued-task-submission-accepted-not-a-grant")
        if waitingForContinuedTask {
          continuedStatus = "Submission accepted. Launch callback not yet observed."
        }
      case .granted:
        waitingForContinuedTask = false
        driver?.recordLifecycle(.continuedTaskStarted)
        record("continued-task-framework-launch-callback")
        continuedStatus =
          "Framework launch callback observed. A continued-processing task is active."
        guard let driver, hostState == .ready else {
          continued?.finish(success: false)
          return
        }
        run(.continuedBackground) { [self] in
          try await driver.runBackgroundWorkload(insideContinuedTask: true)
          continued?.cellReturned()
          status =
            "Continued-processing probe returned. Inspect actual lifecycle events and external WebContent evidence."
        }
      case .expired:
        waitingForContinuedTask = false
        driver?.continuedTaskExpired()
        work?.cancel()
        refresh()
        record("continued-task-expiration-callback")
        continuedStatus =
          "Framework expiration or user cancellation observed; Python was torn down."
      case .refused(let code):
        waitingForContinuedTask = false
        record("continued-task-submission-refused", detail: "scheduler-error-\(code)")
        continuedStatus = "The scheduler refused this request. No continued workload ran."
        status = "Continued processing unavailable for this request. Nothing was retried."
      case .configurationMissing:
        waitingForContinuedTask = false
        record("continued-task-permitted-identifier-missing")
        continuedStatus =
          "The app does not declare its matching .python.* identifier. No request was submitted."
      case .registrationRefused:
        waitingForContinuedTask = false
        record("continued-task-registration-refused")
        continuedStatus = "Task registration was refused. No continued workload ran."
      case .launchNotObserved:
        waitingForContinuedTask = false
        record("continued-task-launch-not-observed-within-20s")
        continuedStatus =
          "No launch callback arrived within 20 seconds. Only this pending request was cancelled."
      case .cancelled:
        waitingForContinuedTask = false
        record("continued-task-pending-request-cancelled")
        continuedStatus = "Pending request cancelled. No continued-processing grant is claimed."
      case .completed(let success):
        record("continued-task-completed", detail: success ? "success" : "unsuccessful")
        continuedStatus = "The observed continued-processing task has ended."
      }
      checkpointSafely()
    }
  #endif

  func cancel() {
    guard driver != nil else { return }
    record("explicit-cancel")
    work?.cancel()
    switch driver?.host.state {
    case .loading: driver?.host.cancelStartup()
    case .running(let id):
      if let host = driver?.host {
        Task { [weak self] in
          await host.cancel(requestID: id)
          self?.refresh()
          self?.checkpointSafely()
        }
      }
    case .closed: break
    default: driver?.host.suspend(reason: .cancelled)
    }
    #if os(iOS)
      continued?.cancel()
    #endif
    waitingForContinuedTask = false
    refresh()
    status =
      "Cancellation requested. The interpreter will not be reused; no operation is retried automatically."
    checkpointSafely()
  }

  func close() {
    guard let driver, driver.host.state != .closed else { return }
    record("review-owner-closed")
    work?.cancel()
    driver.host.close()
    #if os(iOS)
      continued?.cancel()
    #endif
    waitingForContinuedTask = false
    memoryPressure?.cancel()
    memoryPressure = nil
    refresh()
    status =
      "Interpreter closed. Saved evidence is retained; a new session needs an explicit Start."
    checkpointSafely()
  }

  func sceneChanged(_ phase: ScenePhase, isTransition: Bool = true) {
    scene =
      switch phase {
      case .active: "active"
      case .inactive: "inactive"
      case .background: "background"
      @unknown default: "unknown"
      }
    guard isTransition, let driver else { return }
    record("scene-\(scene)")
    switch phase {
    case .background: driver.recordLifecycle(.enteredBackground)
    case .active: driver.recordLifecycle(.enteredForeground)
    default: break
    }
    // Do not manufacture a background interruption or grant. This explicit probe observes
    // WebKit's real outcome, including suspension and an unknown outcome after process death.
    checkpointSafely()
  }

  func receivedMemoryPressure() {
    guard let driver, driver.host.state != .closed else { return }
    driver.recordLifecycle(.memoryPressure)
    record("system-memory-pressure-callback")
    driver.host.suspend(reason: .backgroundInterrupted)
    work?.cancel()
    #if os(iOS)
      continued?.cancel()
    #endif
    refresh()
    status =
      "System memory pressure observed. The interpreter was discarded; this does not identify jetsam."
    checkpointSafely()
  }

  func saveSnapshot() {
    guard driver != nil else { return }
    record("explicit-save-snapshot")
    evidenceProblem = nil
    do {
      try checkpoint()
      status =
        isBusy
        ? "Current report snapshot saved. The measurement continues."
        : "Current report snapshot saved in the private session directory."
    } catch {
      evidenceProblem = "The current report could not be saved. Existing evidence is unchanged."
    }
  }

  func exportFinished(_ result: Result<URL, any Error>) {
    switch result {
    case .success: status = "The system exported the selected evidence file."
    case .failure:
      evidenceProblem =
        "The system could not export this file. The private saved evidence is unchanged."
    }
  }

  private func createSession() throws {
    let evidence = try PyodideReviewEvidence()
    let sessionID = UUID()
    let host = PyodideHost(botID: sessionID, folder: evidence.folder)
    driver = PyodideMeasurementDriver(host: host, folder: evidence.folder)
    self.evidence = evidence
    self.sessionID = sessionID
    createdAt = Date()
    directory = evidence.directory
    files = []
    events = []
    omittedEvents = 0
    omittedFileEntries = 0
    latestSnapshot = nil
    presentation = nil
    startup = nil
    failure = nil
    evidenceProblem = nil
    observedCellID = nil
    actionCount = 0
    hostState = .idle
    record(
      "explicit-private-session-created", detail: "initial-scene-\(scene);network-offline-no-proxy")
    #if os(macOS)
      let pressure = DispatchSource.makeMemoryPressureSource(
        eventMask: [.warning, .critical], queue: .main)
      pressure.setEventHandler { [weak self] in
        MainActor.assumeIsolated { self?.receivedMemoryPressure() }
      }
      pressure.resume()
      memoryPressure = pressure
    #endif
  }

  private func run(_ action: Action, operation: @escaping @MainActor () async throws -> Void) {
    guard !isBusy, !waitingForContinuedTask, let driver else { return }
    isBusy = true
    activeAction = action
    failure = nil
    evidenceProblem = nil
    actionCount += 1
    operationID = UUID()
    record("operation-started", detail: action.rawValue)
    status = "Measurement in progress. Stop discards the realm; it never retries the operation."
    startMonitor()
    work = Task { [self] in
      #if os(iOS)
        var succeeded = false
      #endif
      do {
        // Retain a pre-dispatch record. A last record with no completion is unknown, not success.
        try checkpoint()
        try Task.checkCancellation()
        try await operation()
        try Task.checkCancellation()
        record("operation-returned", detail: action.rawValue)
        #if os(iOS)
          succeeded = true
        #endif
      } catch {
        let observed =
          (error as? PyodideFailure) ?? (error is CancellationError ? .cancelled : .fileUnavailable)
        failure = observed
        record("operation-failed", detail: observed.rawValue)
        status =
          "The operation stopped. Inspect the recorded error; no fallback or retry was attempted."
      }
      refresh()
      checkpointSafely()
      #if os(iOS)
        if action == .continuedBackground {
          continued?.finish(success: succeeded && evidenceProblem == nil)
        }
      #endif
      monitor?.cancel()
      monitor = nil
      isBusy = false
      activeAction = nil
      operationID = nil
      work = nil
      if actionCount >= 100 {
        status =
          "This bounded review session reached 100 actions. Save evidence, close it and explicitly start a new session."
      }
      // Keep the actual driver alive for reports after an expected timeout/cancel probe.
      report = driver.report()
    }
  }

  private func startMonitor() {
    monitor?.cancel()
    monitor = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        self.refresh()
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      }
    }
  }

  private func refresh() {
    guard let driver else { return }
    hostState = driver.host.state
    if case .running = hostState {
      cellStartedAt = driver.host.activeCellStartedAt
    } else {
      cellStartedAt = nil
    }
    if let actual = driver.host.startup { startup = actual }
    if case .running(let id) = hostState, cellStartedAt != nil, observedCellID != id {
      observedCellID = id
      record("bridge-executing-callback-observed", detail: id.uuidString.lowercased())
      #if os(iOS)
        if activeAction == .continuedBackground { continued?.cellStarted() }
      #endif
      checkpointSafely()
    }
  }

  private func record(_ event: String, detail: String? = nil) {
    events.append(PyodideReviewEvent(event, operationID: operationID, detail: detail))
    if events.count > 256 {
      omittedEvents += events.count - 256
      events.removeFirst(events.count - 256)
    }
  }

  private func addFile(_ file: PyodideReviewFile) {
    files.append(file)
    if files.count > 200 {
      omittedFileEntries += files.count - 200
      files.removeFirst(files.count - 200)
    }
  }

  private func checkpointSafely() {
    do { try checkpoint() } catch {
      evidenceProblem =
        "Evidence could not be saved. Existing files are retained; no operation is repeated."
    }
  }

  private func checkpoint() throws {
    guard let driver, let evidence else { return }
    let actualReport = driver.report()
    report = actualReport
    addFile(try evidence.file(path: driver.saveReport()))
    let snapshot = PyodideReviewSnapshot(
      sessionID: sessionID, createdAt: createdAt, capturedAt: Date(),
      appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "unavailable",
      appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ?? "unavailable",
      hostState: Self.stateCode(driver.host.state), startup: startup,
      measurements: actualReport, nativeEvents: events, omittedNativeEvents: omittedEvents,
      files: files.map { .init(path: $0.path, bytes: $0.bytes, sha256: $0.sha256) },
      omittedFileEntries: omittedFileEntries,
      limitations: [
        "Development measurements, never an S6 or reference-device verdict.",
        "No production Python/engine tool, user-folder grant, network, gateway or remote-Mac fallback is enabled.",
        "A recorded start without a returned/failed event has an unknown outcome. It is never retried automatically.",
        "Process death may deliver no lifecycle callback. No app-kill, OS suspension or jetsam cause is inferred.",
        "Peak WebContent footprint, device jetsam, install/download delta, physical Lockdown Mode and external gateway captures are not measured here.",
        "Cold p95 requires at least 20 separately launched matching-hardware/build/payload reports; interpreter recreation is not a cold launch.",
        "Reports are content-free metadata. Result JSON, PNG and CSV files contain the actual scientific output and are shared only by an explicit action.",
      ])
    let file = try evidence.saveJSON(snapshot, category: "reports", name: "native-review-report")
    addFile(file)
    latestSnapshot = file
  }

  static func stateCode(_ state: PyodideHost.State) -> String {
    switch state {
    case .idle: "idle"
    case .loading: "loading"
    case .ready: "ready"
    case .running(let id): "running:\(id.uuidString.lowercased())"
    case .failed(let failure): "failed:\(failure.rawValue)"
    case .closed: "closed"
    }
  }
}
