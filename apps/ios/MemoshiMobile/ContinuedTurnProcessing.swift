import AppCore
import BackgroundTasks
import Foundation
import MemoshiProtocol
import os

/// Extends a user-started turn with the system's visible continued-processing task. The
/// scheduler may refuse it. Expiration (including Cancel in its Live Activity) stops that turn;
/// an app-switcher kill delivers no callback, so committed work resumes at the next launch.
/// A turn that waits for the person's approval holds no task meanwhile (D130): the scheduler
/// expires tasks that report no progress, and that expiry would stop the turn.
///
/// Which turn has a task, which awaits one and when a task is completed is decided by
/// AppCore's `ContinuedTurnPlan`; this class carries out its commands on `BGTaskScheduler`
/// and on the system's task objects.
@MainActor
final class ContinuedTurnProcessing {
  /// Each submission's identifier is this prefix plus the turn's original request ID; Info.plist
  /// permits the matching wildcard, `$(PRODUCT_BUNDLE_IDENTIFIER).turn.*`.
  private let prefix = (Bundle.main.bundleIdentifier ?? "com.mehmetcanbudak.memoshi") + ".turn"
  private var plan = ContinuedTurnPlan()
  /// The launched tasks the plan has not completed yet.
  private var tasks: [ULID: BGContinuedProcessingTask] = [:]
  /// Stops the turn and returns once that Stop has settled, or cannot be sent. The host bounds
  /// the wait: the system allows an expired task only a short time to complete.
  var onExpiration: (@MainActor (ULID) async -> Void)?
  /// Fired when the last active `BGContinuedProcessingTask` completes or is relinquished, so a
  /// backgrounded host can close the in-process engine before suspension.
  var onAllTasksEnded: (@MainActor () -> Void)?
  /// Whether a continued-processing task currently holds background execution time.
  var hasActiveTask: Bool { !tasks.isEmpty }
  private let log = Logger(subsystem: "com.mehmetcanbudak.memoshi", category: "continued-turn")

  func handle(_ activity: TurnActivity) { perform(plan.handle(activity)) }

  private func perform(_ commands: [ContinuedTurnPlan.Command]) {
    for command in commands {
      switch command {
      case .register(let request): register(request)
      case .submit(let request): submit(request)
      case .start(let request, let units):
        // The model's final length is unknown. Report observed units, not an invented
        // percentage.
        tasks[request]?.progress.totalUnitCount = -1
        tasks[request]?.progress.completedUnitCount = units
      case .report(let request, let units):
        guard let task = tasks[request] else { continue }
        task.progress.completedUnitCount = units
        task.updateTitle(
          String(localized: "Memoshi is answering"),
          subtitle: String(localized: "\(Int(units)) characters so far"))
      case .complete(let request, let succeeded):
        guard let task = tasks.removeValue(forKey: request) else { continue }
        task.progress.totalUnitCount = max(1, task.progress.completedUnitCount)
        task.progress.completedUnitCount = task.progress.totalUnitCount
        task.setTaskCompleted(success: succeeded)
        log.notice(
          "continued turn completed: \(task.identifier, privacy: .public) success=\(succeeded, privacy: .public)"
        )
        if tasks.isEmpty { onAllTasksEnded?() }
      case .stop:
        // Only `plan.expired` returns it, and `expire` carries it out itself.
        break
      case .relinquish(let request):
        guard let task = tasks.removeValue(forKey: request) else { continue }
        task.setTaskCompleted(success: false)
        log.notice("continued turn expired: \(task.identifier, privacy: .public)")
        if tasks.isEmpty { onAllTasksEnded?() }
      }
    }
  }

  /// Continued-processing handlers may be registered after launch; the plan asks for each
  /// identifier once, however often it is submitted.
  private func register(_ request: ULID) {
    let identifier = prefix + "." + request.rawValue
    let accepted = BGTaskScheduler.shared.register(
      forTaskWithIdentifier: identifier, using: .main
    ) { [weak self] task in
      MainActor.assumeIsolated { self?.launched(task, request: request) }
    }
    if !accepted { log.error("continued turn not registered: \(identifier, privacy: .public)") }
    perform(plan.registered(request, accepted: accepted))
  }

  private func submit(_ request: ULID) {
    let identifier = prefix + "." + request.rawValue
    let log = log
    // The submission call must not run on the main thread (BGTaskScheduler.h).
    Task.detached { [weak self] in
      let submission = BGContinuedProcessingTaskRequest(
        identifier: identifier, title: String(localized: "Memoshi is answering"),
        subtitle: String(localized: "Starting"))
      submission.strategy = .fail
      do {
        try await BGTaskScheduler.shared.submitTaskRequest(submission)
        log.notice("continued turn submitted: \(identifier, privacy: .public)")
      } catch {
        let code = (error as NSError).code
        log.error(
          "continued turn submission refused: \(identifier, privacy: .public) code=\(code, privacy: .public)"
        )
        await self?.submissionRefused(request)
      }
    }
  }

  private func submissionRefused(_ request: ULID) { plan.submissionRefused(request) }

  private func launched(_ task: BGTask, request: ULID) {
    guard let task = task as? BGContinuedProcessingTask else {
      task.setTaskCompleted(success: false)
      return
    }
    log.notice("continued turn running: \(task.identifier, privacy: .public)")
    tasks[request] = task
    perform(plan.launched(request))
    // A turn that had already ended, or waits for approval, completed the task just now.
    guard tasks[request] != nil else { return }
    // The framework uses this callback for both resource expiry and the person's Cancel.
    // Stop the underlying turn before relinquishing its background opportunity.
    task.expirationHandler = { [weak self] in
      Task { @MainActor in await self?.expire(request) }
    }
  }

  /// The task is given back only after the Stop has been dispatched and has settled: once it
  /// is completed the system may suspend the app, and a Stop that was never sent would let the
  /// cancelled turn resume at the next launch. The plan keeps the task meanwhile, so the
  /// turn's own end may complete it first; it is completed exactly once either way.
  private func expire(_ request: ULID) async {
    guard plan.expired(request) == [.stop(request)] else { return }
    await onExpiration?(request)
    perform(plan.stopSettled(request))
  }
}
