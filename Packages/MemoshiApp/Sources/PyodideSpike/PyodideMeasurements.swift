import Darwin
import Foundation

/// Content-free S6 samples and caller-reported lifecycle events. This report contains neither
/// reference-device qualification nor externally attributed memory or network-confinement proof.
public struct PyodideMeasurementReport: Sendable, Codable {
  /// Calling app's platform and process attribution, not the WebContent process's identity.
  public struct Environment: Sendable, Codable {
    /// Platform-derived evidence label; physical-device status alone does not establish acceptance.
    public let evidenceClass: String
    /// Hardware identifier read from `hw.machine` for grouping comparable samples.
    public let machine: String
    /// Calling app's operating-system version string at report construction.
    public let os: String
    /// Calling app's process ID, not a WebKit worker or WebContent process ID.
    public let processID: Int32
  }

  /// One scenario sample, retaining measured duration and result counts without result content.
  public struct Observation: Sendable, Codable {
    /// Driver-assigned workload label, not a gate verdict.
    public let scenario: String
    /// Wall-clock timestamp when the completed or failed scenario was recorded.
    public let recordedAt: Date
    /// Native elapsed seconds from the scenario's timer start, separate from worker cell timing.
    public let seconds: Double
    /// Startup details for a startup scenario; nil for observations that did not supply them.
    public let startup: PyodideStartup?
    /// Observed failure, including expected timeout/cancellation outcomes; nil on recorded success.
    public let failure: PyodideFailure?
    /// Whether returned stdout was nonempty; nil when no cell result was recorded.
    public let textReturned: Bool?
    /// Returned table count, or nil without a recorded cell result; not a numerical-correctness score.
    public let tablesReturned: Int?
    /// Returned PNG figure count, or nil without a recorded cell result.
    public let pngFiguresReturned: Int?
    /// Exported artifact count, or nil without a recorded cell result.
    public let artifactsReturned: Int?
    /// Cumulative host termination-callback count at recording time, without a jetsam diagnosis.
    public let contentTerminations: Int
  }

  /// A lifecycle callback recorded by the caller, not independently observed scheduling evidence.
  public struct Lifecycle: Sendable, Codable {
    /// Raw value of the caller-supplied `LifecycleEvent`.
    public let event: String
    /// Wall-clock timestamp when the driver recorded that callback.
    public let at: Date
  }

  /// Report encoding revision; the current driver emits version 1.
  public let schema: Int
  /// Platform and calling-process metadata captured when this report was constructed.
  public let environment: Environment
  /// In-memory scenario samples, not aggregated percentiles or a reference-device gate decision.
  public let observations: [Observation]
  /// Caller-reported app/task events in recording order; no continued-task grant is inferred.
  public let lifecycle: [Lifecycle]
  /// These need externally attributed WebContent Instruments/jetsam evidence; app RSS is not it.
  public let unmeasured: [String]
}

/// A retained driver for the S6 host, callable by a real Mac/iPhone/iPad app entry. It never
/// auto-runs, changes system settings, installs anything or declares reference-device acceptance.
@MainActor
public final class PyodideMeasurementDriver {
  /// Retained interpreter exercised by explicit driver calls; no substitute host is created.
  public let host: PyodideHost
  private let folder: PyodideBotFolder
  private var observations: [PyodideMeasurementReport.Observation] = []
  private var lifecycle: [PyodideMeasurementReport.Lifecycle] = []
  private static var recordedStartupThisProcess = false

  /// Retains the host and its associated admitted folder for synthetic inputs and explicit report
  /// saves. The caller must supply the same folder used by the host; construction runs no workload.
  public init(host: PyodideHost, folder: PyodideBotFolder) {
    self.host = host
    self.folder = folder
  }

  /// One sample per app process. Repeated web-view creation in one process is not labelled cold.
  /// For p95, retain at least 20 separate app-launch reports and aggregate only matching hardware,
  /// OS, build, payload and evidence class. Simulator/Mac numbers cannot pass the iPhone gate.
  public func recordFirstLaunchStartup() async throws -> PyodideStartup {
    guard !Self.recordedStartupThisProcess, host.state == .idle else {
      throw PyodideFailure.invalidRequest
    }
    Self.recordedStartupThisProcess = true
    let started = ContinuousClock.now
    do {
      let result = try await host.start()
      append("first-interpreter-this-app-launch", started: started, startup: result)
      return result
    } catch {
      append("first-interpreter-this-app-launch", started: started, failure: failure(error))
      throw error
    }
  }

  /// Each call reads a unique real CSV from the owned bot folder, runs all four scientific
  /// libraries, returns text/native table/Agg PNG, and exports an independently written CSV.
  /// These are direct scientific bridge samples, not model turns or reference-device qualification.
  @discardableResult
  public func runBridgeCalls(count: Int = 20) async throws -> [PyodideResult] {
    guard (1...20).contains(count) else { throw PyodideFailure.invalidRequest }
    var results: [PyodideResult] = []
    for index in 0..<count {
      try Task.checkCancellation()
      if host.state != .ready { _ = try await host.start() }
      let path = "s6-inputs/\(UUID().uuidString.lowercased()).csv"
      try folder.stageInput(path: path, bytes: Data("x,y\n1,2\n2,4\n3,6\n".utf8))
      let request = PyodideRequest(
        code: Self.scientificCell(inputPath: path), inputPaths: [path], outputPaths: ["result.csv"],
        timeoutSeconds: 30)
      let started = ContinuousClock.now
      do {
        let result = try await host.execute(request)
        guard result.stdout.contains("S6 scientific bridge: 3 rows"), result.tables.count == 1,
          result.figures.count == 1, result.artifacts.count == 1
        else { throw PyodideFailure.scriptFailed }
        append("bridge-\(index + 1)", started: started, result: result)
        results.append(result)
      } catch {
        append("bridge-\(index + 1)", started: started, failure: failure(error))
        throw error
      }
    }
    return results
  }

  /// Runs an infinite cell with a 0.5-second deadline and accepts only `timedOut` as its sample.
  /// Returning does not assert worker-disposal acknowledgement or OS-process destruction.
  public func runTimeoutProbe() async throws {
    if host.state != .ready { _ = try await host.start() }
    let request = PyodideRequest(code: "while True:\n    pass", timeoutSeconds: 0.5)
    let started = ContinuousClock.now
    do {
      _ = try await host.execute(request)
      throw PyodideFailure.scriptFailed
    } catch {
      let observed = failure(error)
      append("timeout-infinite-cell", started: started, failure: observed)
      guard observed == .timedOut else { throw error }
    }
  }

  /// Waits up to five seconds for the executing script callback, then awaits `host.cancel` and
  /// requires the cell to fail as `cancelled`. The sample does not prove OS-process destruction.
  public func runCancellationProbe() async throws {
    if host.state != .ready { _ = try await host.start() }
    let request = PyodideRequest(code: "while True:\n    pass", timeoutSeconds: 30)
    let started = ContinuousClock.now
    let running = Task { try await host.execute(request) }
    do {
      while host.state != .running(request.id) || host.activeCellStartedAt == nil {
        guard started.duration(to: .now) < .seconds(5) else { throw PyodideFailure.timedOut }
        if case .failed(let error) = host.state { throw error }
        try await Task.sleep(for: .milliseconds(10))
      }
      await host.cancel(requestID: request.id)
      switch await running.result {
      case .success:
        append("cancel-infinite-cell", started: started, failure: .scriptFailed)
        throw PyodideFailure.scriptFailed
      case .failure(let error):
        let observed = failure(error)
        append("cancel-infinite-cell", started: started, failure: observed)
        guard observed == .cancelled else { throw error }
      }
    } catch {
      await host.cancel(requestID: request.id)
      _ = await running.result
      throw error
    }
  }

  /// Default is the actual S6.2 workload: five separately started 600-second million-row pandas
  /// cells. Instruments must attach to this host's WebContent process throughout each run;
  /// record peak physical footprint and inspect device jetsam logs separately. A terminated
  /// content process is counted truthfully, not presumed to have been killed by jetsam.
  public func runPandasMemoryWorkload(runs: Int = 5, secondsPerRun: Int = 600) async throws {
    guard (1...5).contains(runs), (1...600).contains(secondsPerRun) else {
      throw PyodideFailure.invalidRequest
    }
    for index in 0..<runs {
      try Task.checkCancellation()
      if host.state != .ready { _ = try await host.start() }
      let started = ContinuousClock.now
      do {
        let result = try await host.execute(
          PyodideRequest(
            code: Self.pandasCell(seconds: secondsPerRun),
            timeoutSeconds: Double(secondsPerRun + 60)))
        append(
          "pandas-1000000-rows-\(secondsPerRun)s-\(index + 1)", started: started, result: result)
      } catch {
        append(
          "pandas-1000000-rows-\(secondsPerRun)s-\(index + 1)", started: started,
          failure: failure(error))
        throw error
      }
    }
  }

  /// Run once outside, then once inside the app's genuine BGContinuedProcessingTask. The app's
  /// scene/task callbacks call recordLifecycle; an expiration handler calls continuedTaskExpired.
  /// This driver does not register a fake continued task or infer that WebKit kept running.
  public func runBackgroundWorkload(insideContinuedTask: Bool) async throws {
    if host.state != .ready { _ = try await host.start() }
    let scenario =
      insideContinuedTask ? "background-with-continued-task" : "background-without-continued-task"
    let started = ContinuousClock.now
    do {
      let result = try await host.execute(
        PyodideRequest(code: Self.pandasCell(seconds: 60), timeoutSeconds: 120))
      append(scenario, started: started, result: result)
    } catch {
      append(scenario, started: started, failure: failure(error))
      throw error
    }
  }

  /// Events the app's real scene, continued-task and memory-pressure callbacks can report.
  public enum LifecycleEvent: String, Sendable {
    case enteredBackground
    case enteredForeground
    case continuedTaskStarted
    case continuedTaskExpired
    case memoryPressure
  }

  /// Appends a timestamped callback only; it does not change host state or obtain background time.
  public func recordLifecycle(_ event: LifecycleEvent) {
    lifecycle.append(.init(event: event.rawValue, at: Date()))
  }

  /// Records a genuine continued-task expiration and interrupts the host as `backgroundInterrupted`.
  /// The interruption schedules teardown without synchronously awaiting worker acknowledgement.
  public func continuedTaskExpired() {
    recordLifecycle(.continuedTaskExpired)
    host.suspend(reason: .backgroundInterrupted)
  }

  /// An explicit controlled URL only. Native gateway decisions and independent sink/packet evidence
  /// establish routing/no-bypass; an HTTP response by itself is never confinement proof.
  public func runGatewayCanary(url: URL) async throws {
    guard let scheme = url.scheme, ["https", "http"].contains(scheme),
      url.host != nil, url.user == nil, url.password == nil,
      url.absoluteString.utf8.count <= 2_048
    else { throw PyodideFailure.invalidRequest }
    if host.state != .ready { _ = try await host.start() }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let encoded = try encoder.encode(url.absoluteString)
    let literal = String(decoding: encoded, as: UTF8.self)
    let started = ContinuousClock.now
    let code =
      "from pyodide.http import pyfetch\nresponse = await pyfetch(\(literal))\nprint('S6 gateway status:', response.status)"
    do {
      let result = try await host.execute(PyodideRequest(code: code))
      append("controlled-gateway-request", started: started, result: result)
    } catch {
      append("controlled-gateway-request", started: started, failure: failure(error))
      throw error
    }
  }

  /// Snapshots the retained samples and current calling environment without writing files or
  /// declaring a gate outcome; explicitly lists evidence this driver cannot measure.
  public func report() -> PyodideMeasurementReport {
    PyodideMeasurementReport(
      schema: 1, environment: Self.environment(), observations: observations, lifecycle: lifecycle,
      unmeasured: [
        "Peak physical footprint of the attributed WebContent process (not this app's RSS).",
        "Device jetsam logs distinguishing memory termination from another WebKit process failure.",
        "App download and installed-size delta against the same build without the scientific payload.",
        "Independent sink/packet evidence proving native gateway routing and denial of direct WebKit HTTP, DNS and QUIC paths.",
        "Physical Lockdown Mode setting/change and outcome; the host refuses enabled mode without silently executing a fallback.",
      ])
  }

  /// Content-free metadata only: no code, CSV/table values, stdout, figure pixels or credentials.
  public func saveReport() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let path = "s6-reports/\(UUID().uuidString.lowercased()).json"
    try folder.stageInput(path: path, bytes: encoder.encode(report()))
    return path
  }

  private func append(
    _ scenario: String, started: ContinuousClock.Instant, startup: PyodideStartup? = nil,
    result: PyodideResult? = nil, failure: PyodideFailure? = nil
  ) {
    observations.append(
      .init(
        scenario: scenario, recordedAt: Date(), seconds: started.duration(to: .now).pyodideSeconds,
        startup: startup, failure: failure, textReturned: result.map { !$0.stdout.isEmpty },
        tablesReturned: result?.tables.count, pngFiguresReturned: result?.figures.count,
        artifactsReturned: result?.artifacts.count,
        contentTerminations: host.contentTerminationCount))
  }

  private func failure(_ error: any Error) -> PyodideFailure {
    if error is CancellationError { return .cancelled }
    return (error as? PyodideFailure) ?? .scriptFailed
  }

  private static func environment() -> PyodideMeasurementReport.Environment {
    var size = 0
    _ = sysctlbyname("hw.machine", nil, &size, nil, 0)
    var bytes = [UInt8](repeating: 0, count: max(1, size))
    _ = sysctlbyname("hw.machine", &bytes, &size, nil, 0)
    let machine = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    let evidenceClass: String
    #if targetEnvironment(simulator)
      evidenceClass = "simulator-not-reference-hardware"
    #elseif os(macOS)
      evidenceClass = "development-Mac-not-reference-iPhone"
    #else
      evidenceClass = "physical-device-hardware-and-OS-must-match-D80"
    #endif
    return .init(
      evidenceClass: evidenceClass, machine: machine,
      os: ProcessInfo.processInfo.operatingSystemVersionString, processID: getpid())
  }

  private static func scientificCell(inputPath: String) -> String {
    """
    import numpy as np
    import pandas as pd
    import scipy.linalg
    import matplotlib.pyplot as plt
    frame = pd.read_csv('\(inputPath)')
    assert len(frame) == 3
    solution = scipy.linalg.solve(np.array([[3., 1.], [1., 2.]]), np.array([9., 8.]))
    assert np.allclose(solution, [2., 3.])
    memoshi_table(frame)
    figure, axes = plt.subplots(figsize=(4, 3))
    axes.plot(frame['x'], frame['y'])
    axes.set_title('S6 scientific bridge')
    memoshi_figure(figure)
    frame.to_csv('result.csv', index=False)
    print('S6 scientific bridge: 3 rows')
    """
  }

  private static func pandasCell(seconds: Int) -> String {
    """
    import time
    import numpy as np
    import pandas as pd
    frame = pd.DataFrame({'key': np.arange(1_000_000) % 100, 'value': np.arange(1_000_000, dtype=np.float64)})
    deadline = time.perf_counter() + \(seconds)
    iterations = 0
    while time.perf_counter() < deadline:
        grouped = frame.groupby('key')['value'].agg(['sum', 'mean', 'std'])
        rolling = frame['value'].rolling(100).mean()
        iterations += 1
    memoshi_table(grouped.head())
    print('S6 pandas rows:', len(frame), 'iterations:', iterations)
    """
  }
}
