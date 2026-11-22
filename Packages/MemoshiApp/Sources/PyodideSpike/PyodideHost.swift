import Foundation
import WebKit

/// One explicitly created S6 interpreter for one bot's admitted private folder. The view is
/// never presented. This controller has no runtime/model/policy dependency and enables no tools.
@MainActor
public final class PyodideHost {
  /// In-memory interpreter lifecycle; bridge readiness is not script or tool authorization.
  public enum State: Sendable, Equatable {
    case idle
    case loading
    case ready
    case running(UUID)
    case failed(PyodideFailure)
    case closed
  }

  /// Caller-supplied bot attribution; the caller must supply that bot's matching admitted folder.
  public let botID: UUID
  /// Current lifecycle state; in-flight failures are not automatically retried.
  public private(set) var state: State = .idle
  /// Most recent successful startup sample, retained after failure or close; not live-readiness proof.
  public private(set) var startup: PyodideStartup?
  /// Accepted WebKit content-process termination callbacks, not an attributed jetsam count.
  public private(set) var contentTerminationCount = 0
  /// Time of the latest accepted executing script callback, reset when a new cell is admitted.
  /// It may outlive that run and is not proof that the interpreter is still executing.
  public private(set) var activeCellStartedAt: Date?

  private let folder: PyodideBotFolder
  private let network: PyodideNetworkSession
  private let limits: PyodideSessionLimits
  private var payload: PyodidePayload?
  private var payloadTask: Task<PyodidePayload, any Error>?
  private var webView: WKWebView?
  private var delegate: PyodideWebDelegate?
  private var generation = UUID()
  private var createdAt: ContinuousClock.Instant?
  private var coreReadySeconds: Double?
  private var startContinuation: CheckedContinuation<PyodideStartup, any Error>?
  private var runContinuation: CheckedContinuation<PyodideResult, any Error>?
  private var request: PyodideRequest?
  private var activeCellGeneration: UUID?
  private var finishingCell: UUID?
  private var deadline: Task<Void, Never>?
  private var disposal: (id: UUID, task: Task<Bool, Never>)?
  private var idleTimer: Task<Void, Never>?
  private var lifetimeTimer: Task<Void, Never>?
  private var lifetimeElapsed = false

  /// Retains the bot folder and optional caller-owned native transport without loading Python.
  /// Every realm keeps the same sealed asset-only CSP, with or without native networking. The
  /// limits discard a realm after idling or at its lifetime; see ``PyodideSessionLimits``.
  public init(
    botID: UUID, folder: PyodideBotFolder, network: (any PyodideNetworkTransport)? = nil,
    limits: PyodideSessionLimits = .standard
  ) {
    self.botID = botID
    self.folder = folder
    self.network = PyodideNetworkSession(transport: network)
    self.limits = limits
  }

  /// Payload hashing happens off the main actor. Startup measurements begin at web-view creation,
  /// not at manifest verification; the result separates core and scientific import timings.
  public func start(timeoutSeconds: Double = 60) async throws -> PyodideStartup {
    try await start(limitSeconds: timeoutSeconds, accepting: 1...180)
  }

  /// `accepting` bounds the start limit; tests pass a wider range to make a start miss it.
  func start(limitSeconds timeoutSeconds: Double, accepting range: ClosedRange<Double>)
    async throws -> PyodideStartup
  {
    if case .ready = state, let startup { return startup }
    guard state != .closed else { throw PyodideFailure.hostClosed }
    guard state != .loading, request == nil else { throw PyodideFailure.busy }
    guard timeoutSeconds.isFinite, range.contains(timeoutSeconds) else {
      throw PyodideFailure.invalidRequest
    }
    // A call stopped before its start begins leaves the host, and any discarded realm, as it is.
    guard !Task.isCancelled else { throw PyodideFailure.cancelled }
    discardView()
    state = .loading
    let currentGeneration = UUID()
    generation = currentGeneration
    do {
      guard await finishDisposal() else { throw PyodideFailure.scriptFailed }
      guard generation == currentGeneration, state == .loading else { throw endedStart }
      let verified: PyodidePayload
      if let payload {
        verified = payload
      } else {
        let task = Task<PyodidePayload, any Error> { try await PyodidePayload.bundled() }
        payloadTask = task
        defer { if payloadTask == task { payloadTask = nil } }
        verified = try await withTaskCancellationHandler {
          try await task.value
        } onCancel: {
          task.cancel()
        }
      }
      guard generation == currentGeneration, state == .loading else { throw endedStart }
      guard !Task.isCancelled else { throw PyodideFailure.cancelled }
      payload = verified
      let configuration = WKWebViewConfiguration()
      // Python computes in a deliberately hidden view; WebKit's idle suspension is not a tool
      // timeout or an iOS background grant. Native cancellation/expiration still owns its life.
      configuration.preferences.inactiveSchedulingPolicy = .none
      guard !configuration.defaultWebpagePreferences.isLockdownModeEnabled else {
        throw PyodideFailure.lockdownRequiresMac
      }
      configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
      configuration.defaultWebpagePreferences.allowsContentJavaScript = true
      configuration.setURLSchemeHandler(
        PyodideSchemeHandler(payload: verified),
        forURLScheme: PyodideSchemeHandler.scheme)
      let delegate = PyodideWebDelegate(host: self, generation: currentGeneration)
      configuration.userContentController.add(delegate, name: "memoshiPyodide")
      configuration.userContentController.addScriptMessageHandler(
        delegate, contentWorld: .page, name: "memoshiPyodideNetwork")
      self.delegate = delegate
      createdAt = .now
      coreReadySeconds = nil
      let view = WKWebView(frame: .zero, configuration: configuration)
      view.isInspectable = false
      view.navigationDelegate = delegate
      webView = view
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          startContinuation = continuation
          armDeadline(
            seconds: timeoutSeconds, failure: .startTimedOut, generation: currentGeneration)
          view.load(URLRequest(url: PyodideSchemeHandler.hostURL))
        }
      } onCancel: {
        Task { @MainActor [weak self] in
          // A cancellation that lands once the realm is ready leaves that realm, and any cell
          // already running in it, alone.
          guard let self, self.state == .loading else { return }
          self.interrupt(.cancelled, generation: currentGeneration)
        }
      }
    } catch {
      let failure = state == .closed ? .hostClosed : ((error as? PyodideFailure) ?? .startupFailed)
      if generation == currentGeneration, state != .closed {
        interrupt(failure, generation: currentGeneration)
      }
      _ = await finishDisposal()
      throw failure
    }
  }

  /// What ended a start while it awaited its disposal or payload check: Close, Stop or the
  /// interruption that discarded it, so a closed host reports `hostClosed` in every phase.
  private var endedStart: PyodideFailure {
    switch state {
    case .closed: .hostClosed
    case .failed(let failure): failure
    default: .cancelled
    }
  }

  /// S6's registry route is strictly the bundled, hash-pinned closure. There is no runtime CDN,
  /// PyPI install or lazy download fallback. Phase 3's policy-approved registry host is separate.
  public func requireBundledPackages(_ names: [String]) throws -> [String: String] {
    guard let startup, state == .ready else { throw PyodideFailure.notReady }
    var selected: [String: String] = [:]
    for name in names {
      let normalized = name.lowercased().replacingOccurrences(of: "_", with: "-")
      guard let version = startup.packageVersions[normalized] else {
        throw PyodideFailure.packageUnavailable
      }
      selected[normalized] = version
    }
    return selected
  }

  /// Runs one bounded cell on a ready host; the caller owns script and folder authorization.
  /// Inputs are copied before dispatch. Completion requires a matching script reply and successful
  /// write-once export of every declared output, not merely JavaScript dispatch completion.
  /// In-flight cancellation or failure discards the realm without retry; use `cancel(requestID:)`
  /// to await native-send drain and the pending worker-disposal acknowledgement.
  public func execute(_ request: PyodideRequest) async throws -> PyodideResult {
    guard state != .closed else { throw PyodideFailure.hostClosed }
    guard state == .ready else {
      if case .running = state { throw PyodideFailure.busy }
      throw PyodideFailure.notReady
    }
    try PyodideLimits.validate(request)
    guard !Task.isCancelled else { throw PyodideFailure.cancelled }
    let currentGeneration = generation
    let cellGeneration = UUID()
    self.request = request
    activeCellGeneration = cellGeneration
    finishingCell = nil
    activeCellStartedAt = nil
    state = .running(request.id)
    idleTimer?.cancel()
    idleTimer = nil
    do {
      let folder = folder
      let inputs = try await Task.detached(priority: .userInitiated) {
        try folder.readInputs(request.inputPaths)
      }.value
      guard generation == currentGeneration, activeCellGeneration == cellGeneration,
        state == .running(request.id), let view = webView
      else {
        throw PyodideFailure.cancelled
      }
      guard !Task.isCancelled else { throw PyodideFailure.cancelled }
      let command = PyodideCommand(
        id: request.id, generation: cellGeneration, code: request.code, inputs: inputs,
        outputs: request.outputPaths)
      let bytes = try JSONEncoder().encode(command)
      let arguments = try JSONSerialization.jsonObject(with: bytes)
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          runContinuation = continuation
          do {
            try network.begin(cellID: request.id, generation: cellGeneration)
          } catch {
            interrupt(.scriptFailed, generation: currentGeneration)
            return
          }
          // The cell's own limit runs from its dispatch, after the realm started and the inputs
          // were copied, never from the start of the caller's call.
          armDeadline(
            seconds: request.timeoutSeconds, failure: .timedOut, generation: currentGeneration)
          view.callAsyncJavaScript(
            "window.memoshiPyodideExecute(request); return true;",
            arguments: ["request": arguments], in: nil, in: .page
          ) { [weak self] result in
            if case .failure = result, self?.activeCellGeneration == cellGeneration {
              self?.interrupt(.scriptFailed, generation: currentGeneration)
            }
          }
        }
      } onCancel: {
        Task { @MainActor [weak self] in
          guard self?.activeCellGeneration == cellGeneration else { return }
          self?.interrupt(.cancelled, generation: currentGeneration)
        }
      }
    } catch {
      let failure = (error as? PyodideFailure) ?? .fileUnavailable
      if generation == currentGeneration, activeCellGeneration == cellGeneration {
        interrupt(failure, generation: currentGeneration)
      }
      _ = await finishDisposal()
      throw failure
    }
  }

  /// Interrupts a matching cell and awaits native-send drain and control-page worker-termination
  /// acknowledgement. A failed acknowledgement sets `failed(scriptFailed)`; this does not prove
  /// OS WebContent-process destruction.
  public func cancel(requestID: UUID) async {
    if request?.id == requestID { interrupt(.cancelled, generation: generation) }
    guard request == nil else { return }
    if !(await finishDisposal()), state != .closed { state = .failed(.scriptFailed) }
  }

  /// Interrupts only a loading startup and schedules realm teardown; this synchronous entrypoint
  /// does not wait for worker-termination acknowledgement.
  public func cancelStartup() {
    guard state == .loading else { return }
    interrupt(.cancelled, generation: generation)
  }

  /// Call when continued processing expires, on memory pressure, or when the owning bot closes.
  /// Ordinary background entry need not call this when the app owns a live continued task.
  public func suspend(reason: PyodideFailure = .backgroundInterrupted) {
    guard state != .closed else { return }
    interrupt(reason, generation: generation)
  }

  /// Permanently closes this controller and immediately cancels native sends. Teardown drains those
  /// sends asynchronously; an awaited `cancel(requestID:)` also waits after close.
  public func close() {
    interrupt(.hostClosed, generation: generation)
    state = .closed
    payload = nil
  }

  fileprivate func receive(_ message: WKScriptMessage, generation incoming: UUID) {
    guard accepts(message, generation: incoming) else { return }
    guard let text = message.body as? String else {
      interrupt(.scriptFailed, generation: incoming)
      return
    }
    guard text.utf8.count <= PyodideLimits.resultBytes else {
      interrupt(.outputLimit, generation: incoming)
      return
    }
    guard let data = text.data(using: .utf8),
      let reply = try? JSONDecoder().decode(PyodideReply.self, from: data)
    else {
      interrupt(.scriptFailed, generation: incoming)
      return
    }
    if let id = reply.id {
      guard id == request?.id, let activeCellGeneration,
        reply.generation == activeCellGeneration
      else { return }
    } else if reply.generation != nil {
      return
    }
    switch reply.kind {
    case "coreReady":
      guard state == .loading, let createdAt else { return }
      coreReadySeconds = createdAt.duration(to: .now).pyodideSeconds
    case "executing":
      guard let request, state == .running(request.id), reply.id == request.id else { return }
      activeCellStartedAt = Date()
    case "ready":
      guard state == .loading, let payload, let createdAt,
        let core = coreReadySeconds, core.isFinite, core >= 0,
        let stack = reply.scientificStackSeconds, stack.isFinite, stack >= 0,
        let versions = reply.versions,
        versions
          == Dictionary(
            uniqueKeysWithValues: payload.manifest.packages.map { ($0.name, $0.version) })
      else {
        interrupt(.startupFailed, generation: incoming)
        return
      }
      let elapsed = createdAt.duration(to: .now).pyodideSeconds
      let startup = PyodideStartup(
        coreSeconds: core, scientificStackSeconds: stack, webViewToReadySeconds: elapsed,
        bundledBytes: payload.manifest.bundledBytes, pyodideVersion: payload.manifest.pyodide,
        packageVersions: versions, networkConfigured: network.isConfigured, lockdownEnabled: false)
      self.startup = startup
      state = .ready
      deadline?.cancel()
      deadline = nil
      armLifetime(generation: incoming)
      armIdle(generation: incoming)
      let continuation = startContinuation
      startContinuation = nil
      continuation?.resume(returning: startup)
    case "result":
      guard let request, state == .running(request.id), reply.id == request.id,
        finishingCell == nil
      else { return }
      finishingCell = request.id
      let drain = network.end()
      Task { @MainActor [weak self] in
        await drain.value
        guard let self, self.generation == incoming, self.state == .running(request.id),
          self.finishingCell == request.id
        else { return }
        do {
          let result = try reply.result(for: request, folder: self.folder)
          self.deadline?.cancel()
          self.deadline = nil
          self.request = nil
          self.activeCellGeneration = nil
          self.finishingCell = nil
          self.state = .ready
          let continuation = self.runContinuation
          self.runContinuation = nil
          continuation?.resume(returning: result)
          // The result is delivered first; a realm past its lifetime is then discarded.
          if self.lifetimeElapsed {
            self.interrupt(.lifetimeExpired, generation: incoming)
          } else {
            self.armIdle(generation: incoming)
          }
        } catch {
          self.interrupt((error as? PyodideFailure) ?? .scriptFailed, generation: incoming)
        }
      }
    case "failure":
      guard request == nil || reply.id == request?.id else { return }
      let failure = reply.failure.flatMap(PyodideFailure.init(rawValue:)) ?? .scriptFailed
      interrupt(failure, generation: incoming)
    default: break
    }
  }

  private func accepts(_ message: WKScriptMessage, generation incoming: UUID) -> Bool {
    guard let webView else { return false }
    return generation == incoming && message.webView === webView && message.frameInfo.isMainFrame
      && message.frameInfo.request.url == PyodideSchemeHandler.hostURL
  }

  fileprivate func receiveNetwork(
    _ message: WKScriptMessage, generation incoming: UUID,
    replyHandler: @escaping @MainActor (Any?, String?) -> Void
  ) {
    guard accepts(message, generation: incoming), let text = message.body as? String,
      text.utf8.count <= PyodideHTTPLimits.messageBytes,
      let data = text.data(using: .utf8),
      let call = try? JSONDecoder().decode(PyodideNetworkMessage.self, from: data),
      call.generation == activeCellGeneration, request?.id == call.cellID,
      state == .running(call.cellID),
      !call.requestID.isEmpty, call.requestID.utf8.count <= 64
    else {
      replyHandler(nil, "Network request failed")
      return
    }
    do {
      switch call.kind {
      case "send":
        guard let url = call.url, let method = call.method, let headers = call.headers,
          let body = call.body
        else { throw PyodideFailure.invalidRequest }
        let task = try network.send(
          .init(url: url, method: method, headers: headers, body: body),
          requestID: call.requestID, cellID: call.cellID, generation: call.generation)
        Task { @MainActor [weak self] in
          do {
            let response = try await task.value
            guard let self, self.generation == incoming,
              self.activeCellGeneration == call.generation,
              self.network.isActive(cellID: call.cellID, generation: call.generation),
              self.state == .running(call.cellID), self.finishingCell == nil
            else { throw PyodideFailure.cancelled }
            // WKScriptMessageHandlerWithReply supports strings/collections, not Data.
            replyHandler(
              [
                "status": response.status, "headers": response.headers,
                "body": response.body.base64EncodedString(),
              ], nil)
          } catch {
            replyHandler(nil, "Network request failed")
          }
        }
      case "cancel":
        let drain = try network.cancel(
          requestID: call.requestID, cellID: call.cellID, generation: call.generation)
        Task { @MainActor in
          await drain.value
          replyHandler(true, nil)
        }
      case "end":
        let drain = network.end()
        Task { @MainActor in
          await drain.value
          replyHandler(true, nil)
        }
      default:
        throw PyodideFailure.invalidRequest
      }
    } catch {
      replyHandler(nil, "Network request failed")
    }
  }

  fileprivate func terminated(generation: UUID) {
    guard self.generation == generation else { return }
    contentTerminationCount += 1
    interrupt(.webContentTerminated, generation: generation)
  }

  fileprivate func failed(generation: UUID) {
    interrupt(.startupFailed, generation: generation)
  }

  /// A start that misses its limit fails as `startTimedOut`, a cell past its own as `timedOut`.
  private func armDeadline(seconds: Double, failure: PyodideFailure, generation: UUID) {
    deadline?.cancel()
    deadline = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
      guard !Task.isCancelled else { return }
      self?.interrupt(failure, generation: generation)
    }
  }

  private func armIdle(generation: UUID) {
    idleTimer?.cancel()
    idleTimer = nil
    guard let seconds = limits.idleSeconds else { return }
    idleTimer = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
      guard let self, self.generation == generation, self.state == .ready else { return }
      self.interrupt(.idleExpired, generation: generation)
    }
  }

  private func armLifetime(generation: UUID) {
    lifetimeTimer?.cancel()
    lifetimeTimer = nil
    lifetimeElapsed = false
    guard let seconds = limits.lifetimeSeconds else { return }
    lifetimeTimer = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
      guard let self, self.generation == generation else { return }
      if self.state == .ready {
        self.interrupt(.lifetimeExpired, generation: generation)
      } else {
        self.lifetimeElapsed = true
      }
    }
  }

  private func interrupt(_ failure: PyodideFailure, generation incoming: UUID) {
    guard generation == incoming else { return }
    generation = UUID()
    payloadTask?.cancel()
    payloadTask = nil
    deadline?.cancel()
    deadline = nil
    idleTimer?.cancel()
    idleTimer = nil
    lifetimeTimer?.cancel()
    lifetimeTimer = nil
    lifetimeElapsed = false
    let start = startContinuation
    let run = runContinuation
    startContinuation = nil
    runContinuation = nil
    request = nil
    activeCellGeneration = nil
    finishingCell = nil
    state = .failed(failure)
    discardView()
    start?.resume(throwing: failure)
    run?.resume(throwing: failure)
  }

  private func discardView() {
    let retired = webView
    let previous = disposal?.task
    let nativeDrain = network.end()
    webView = nil
    retired?.configuration.userContentController.removeScriptMessageHandler(
      forName: "memoshiPyodide")
    retired?.configuration.userContentController.removeScriptMessageHandler(
      forName: "memoshiPyodideNetwork", contentWorld: .page)
    retired?.navigationDelegate = nil
    delegate = nil
    disposal = (
      UUID(),
      Task { @MainActor in
        var acknowledged = true
        if let retired {
          do {
            let result = try await retired.callAsyncJavaScript(
              "return typeof window.memoshiPyodideTerminate === 'function' ? window.memoshiPyodideTerminate() : true;",
              arguments: [:], in: nil, contentWorld: .page)
            acknowledged = result as? Bool == true
          } catch {
            acknowledged = false
          }
          retired.stopLoading()
        }
        await nativeDrain.value
        let previousAcknowledged = await previous?.value ?? true
        return acknowledged && previousAcknowledged
      }
    )
  }

  private func finishDisposal() async -> Bool {
    guard let pending = disposal else { return true }
    let acknowledged = await pending.task.value
    if disposal?.id == pending.id { disposal = nil }
    return acknowledged
  }
}

private struct PyodideNetworkMessage: Decodable {
  let kind: String
  let requestID: String
  let cellID: UUID
  let generation: UUID
  let url: String?
  let method: String?
  let headers: [String: String]?
  let body: Data?
}

private struct PyodideCommand: Encodable {
  let id: UUID
  let generation: UUID
  let code: String
  let inputs: [PyodideInput]
  let outputs: [String]
}

private struct PyodideReply: Decodable {
  let kind: String
  let id: UUID?
  let generation: UUID?
  let failure: String?
  let coreSeconds: Double?
  let scientificStackSeconds: Double?
  let versions: [String: String]?
  let stdout: String?
  let stderr: String?
  let tables: [PyodideTable]?
  let figures: [PyodideFigure]?
  let files: [PyodideOutput]?
  let elapsedSeconds: Double?

  func result(for request: PyodideRequest, folder: PyodideBotFolder) throws -> PyodideResult {
    guard let stdout, let stderr, let tables, let figures, let files, let elapsedSeconds,
      elapsedSeconds.isFinite, elapsedSeconds >= 0,
      stdout.utf8.count + stderr.utf8.count <= PyodideLimits.textBytes,
      tables.count <= 8, figures.count <= 8,
      Set(files.map(\.path)) == Set(request.outputPaths), files.count == request.outputPaths.count
    else { throw PyodideFailure.outputLimit }
    let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])
    guard
      figures.allSatisfy({ $0.png.count <= 8 * 1_024 * 1_024 && $0.png.starts(with: pngSignature) }
      ),
      figures.reduce(0, { $0 + $1.png.count }) <= PyodideLimits.totalFileBytes
    else { throw PyodideFailure.outputLimit }
    for table in tables {
      guard table.totalRows >= 0, table.columns.count <= 512,
        table.jsonRows.utf8.count <= 8 * 1_024 * 1_024,
        let data = table.jsonRows.data(using: .utf8),
        let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]],
        rows.count <= 100, rows.count <= table.totalRows,
        rows.allSatisfy({ $0.count == table.columns.count })
      else { throw PyodideFailure.outputLimit }
    }
    let artifacts = try folder.export(files, requestID: request.id)
    return PyodideResult(
      requestID: request.id, stdout: stdout, stderr: stderr, tables: tables, figures: figures,
      artifacts: artifacts, elapsedSeconds: elapsedSeconds)
  }
}

extension Duration {
  var pyodideSeconds: Double {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}

@MainActor
private final class PyodideWebDelegate: NSObject, WKNavigationDelegate, WKScriptMessageHandler,
  WKScriptMessageHandlerWithReply
{
  weak var host: PyodideHost?
  let generation: UUID

  init(host: PyodideHost, generation: UUID) {
    self.host = host
    self.generation = generation
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    host?.receive(message, generation: generation)
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
    replyHandler: @escaping @MainActor (Any?, String?) -> Void
  ) {
    guard let host else {
      replyHandler(nil, "Network request failed")
      return
    }
    host.receiveNetwork(message, generation: generation, replyHandler: replyHandler)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    host?.terminated(generation: generation)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error)
  {
    host?.failed(generation: generation)
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: any Error
  ) {
    host?.failed(generation: generation)
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
  ) {
    decisionHandler(
      navigationAction.targetFrame?.isMainFrame == true
        && navigationAction.request.url == PyodideSchemeHandler.hostURL ? .allow : .cancel)
  }
}
