import MemoshiProtocol

/// The decisions of continued processing for user-started turns on iPhone and iPad, without
/// the scheduler: each event returns the commands the host carries out. The host owns the
/// system's task objects and the `BGTaskScheduler` calls; this value owns which turn has a
/// task, which awaits one, and when a task is completed.
///
/// A turn's task is completed exactly once: by the turn's end, by its wait for the person's
/// approval (it holds no task while it waits, because the scheduler expires tasks that report
/// no progress and that expiry would stop the turn), or after an expiry or Cancel once the
/// turn's Stop has settled.
public struct ContinuedTurnPlan: Sendable {
  /// One thing the host does with the scheduler or with a turn.
  public enum Command: Equatable, Sendable {
    /// Register the turn's identifier with the scheduler, then answer with `registered`.
    case register(ULID)
    /// Submit a request for the turn's identifier. A refusal is answered with
    /// `submissionRefused`; a launch with `launched`.
    case submit(ULID)
    /// The launched task starts with this many units and an unknown total.
    case start(ULID, units: Int64)
    /// Show this many units on the running task.
    case report(ULID, units: Int64)
    /// Complete the task with this result, its units becoming its total.
    case complete(ULID, succeeded: Bool)
    /// Stop the turn; when the Stop has settled or cannot be sent, answer with `stopSettled`.
    case stop(ULID)
    /// Give the expired task back as failed, without touching its progress.
    case relinquish(ULID)
  }

  private var running: Set<ULID> = []
  private var registered: Set<ULID> = []
  /// Submitted and not yet launched or refused; only these can still launch late.
  private var awaitingLaunch: Set<ULID> = []
  private var units: [ULID: Int64] = [:]
  /// The result to complete a task with when it launches: its turn ended, or waits for
  /// approval, before the system launched it.
  private var atLaunch: [ULID: Bool] = [:]

  /// No turn has a task yet.
  public init() {}

  /// A turn's activity, as the chat model reports it.
  public mutating func handle(_ activity: TurnActivity) -> [Command] {
    switch activity {
    case .began(let request), .resumed(let request): begin(request)
    case .progressed(let request, let count): progress(request, units: Int64(count))
    case .waitingForApproval(let request): wait(request)
    case .ended(let request, let succeeded): end(request, succeeded: succeeded)
    }
  }

  /// The scheduler's answer to `register`. Each identifier is registered once, however often
  /// it is submitted. A refusal forgets the turn's pending task; the turn is unaffected.
  public mutating func registered(_ request: ULID, accepted: Bool) -> [Command] {
    guard accepted else {
      forget(request)
      return []
    }
    registered.insert(request)
    return [.submit(request)]
  }

  /// A refused submission never launches; the turn itself is unaffected.
  public mutating func submissionRefused(_ request: ULID) { forget(request) }

  /// The system launched the turn's task.
  public mutating func launched(_ request: ULID) -> [Command] {
    awaitingLaunch.remove(request)
    let start = Command.start(request, units: units[request] ?? 0)
    if let succeeded = atLaunch.removeValue(forKey: request) {
      return [start, .complete(request, succeeded: succeeded)]
    }
    running.insert(request)
    return [start]
  }

  /// The task's expiry callback, which the framework also uses for the person's Cancel. Only
  /// a running task stops its turn.
  public mutating func expired(_ request: ULID) -> [Command] {
    running.contains(request) ? [.stop(request)] : []
  }

  /// The Stop asked for by `expired` has settled. The task is given back only now: once it
  /// is, the system may suspend the app, and a Stop that was never sent would let the
  /// cancelled turn resume at the next launch. The turn's own end may have completed the task
  /// meanwhile; then nothing is left to do.
  public mutating func stopSettled(_ request: ULID) -> [Command] {
    guard running.remove(request) != nil else { return [] }
    forget(request)
    return [.relinquish(request)]
  }

  /// Also when the turn runs again after waiting for approval.
  private mutating func begin(_ request: ULID) -> [Command] {
    if awaitingLaunch.contains(request) {
      // A Retry of the same request, or the turn running again, before the system launched
      // its task: the earlier end or wait no longer describes this turn and must not complete
      // the task when it launches.
      atLaunch.removeValue(forKey: request)
      return []
    }
    guard !running.contains(request) else { return [] }
    // Also after a wait for approval: the reply that follows is counted from its own start.
    units[request] = 0
    awaitingLaunch.insert(request)
    return registered.contains(request) ? [.submit(request)] : [.register(request)]
  }

  /// UTF-16 units actually received. Only a higher count is reported.
  private mutating func progress(_ request: ULID, units count: Int64) -> [Command] {
    guard count > units[request] ?? 0 else { return [] }
    units[request] = count
    return running.contains(request) ? [.report(request, units: count)] : []
  }

  /// The turn waits for the person's approval: its task is completed now, as a success, and
  /// `begin` asks again when the turn runs. A task that has not launched yet is completed
  /// when it launches, unless the turn runs again first.
  private mutating func wait(_ request: ULID) -> [Command] {
    if running.remove(request) != nil { return [.complete(request, succeeded: true)] }
    if awaitingLaunch.contains(request) { atLaunch[request] = true }
    return []
  }

  private mutating func end(_ request: ULID, succeeded: Bool) -> [Command] {
    units.removeValue(forKey: request)
    if running.remove(request) != nil { return [.complete(request, succeeded: succeeded)] }
    // The system may launch the task after a short turn has already ended.
    if awaitingLaunch.contains(request) { atLaunch[request] = succeeded }
    return []
  }

  private mutating func forget(_ request: ULID) {
    awaitingLaunch.remove(request)
    units.removeValue(forKey: request)
    atLaunch.removeValue(forKey: request)
  }
}
