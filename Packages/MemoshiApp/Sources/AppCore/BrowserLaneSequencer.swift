import Foundation

/// The order of one bot session's D136 profile changes: opening a separate profile and
/// returning to the bot's own one. A change runs after every earlier one and checks its `Turn`
/// after every suspension and immediately before every load. `supersede()` (the separate
/// profile closed, the task ended, the grants changed) stops every change queued or running so
/// far, the latest and the earlier ones alike, so none of them loads anything afterwards;
/// `close()` stops them for good.
@MainActor
public final class BrowserLaneSequencer {
  /// One change's right to go on.
  public struct Turn: Sendable {
    fileprivate let sequencer: BrowserLaneSequencer
    fileprivate let generation: Int

    /// Whether nothing stopped this change and its task was not cancelled.
    @MainActor public var isCurrent: Bool {
      !Task.isCancelled && !sequencer.isClosed && sequencer.generation == generation
    }

    /// Throws `CancellationError` once the change must stop.
    @MainActor public func check() throws {
      guard isCurrent else { throw CancellationError() }
    }
  }

  /// A return under way (D136): the empty document of the separate page's origin, and the
  /// address its script navigates to.
  public struct Return: Equatable, Sendable {
    /// The empty document's address: the origin of the page that left.
    public let base: URL
    /// Where its script navigates.
    public let target: URL

    /// Describes one return.
    public init(base: URL, target: URL) {
      self.base = base
      self.target = target
    }
  }

  /// The return under way, if any. Disarmed when its target navigation is allowed, when the
  /// return ends in any way, and when the changes are stopped.
  public private(set) var pendingReturn: Return?
  /// The empty document of the latest return started, until the session shows another one. It
  /// outlives its return, so a stopped return's document is still known and moves nothing
  /// (D136 review F3).
  public private(set) var returnDocument: URL?
  /// Changes queued or running.
  public private(set) var unsettled = 0
  /// Profile decisions still reading the store's cookies.
  public private(set) var pendingDecisions = 0
  /// Every change ever queued; a load compares it to tell a move from a failure.
  public private(set) var moves = 0
  private var returnDocumentAdmitted = false
  /// Undoes the start of the arrival under way; nil once it ended.
  private var stopArrival: (@MainActor () -> Void)?
  private var failure: (any Error)?
  private var generation = 0
  private var isClosed = false
  private var tail: Task<Void, Never>?
  private var running: [Int: Task<Void, Never>] = [:]
  private var nextID = 0

  /// An idle sequencer.
  public init() {}

  /// Runs `change` after every change queued before it. It starts only if nothing stopped it
  /// meanwhile. A failure of a change that was still current is kept for `settle`.
  public func enqueue(_ change: @escaping @MainActor (Turn) async throws -> Void) {
    guard !isClosed else { return }
    moves += 1
    unsettled += 1
    let turn = Turn(sequencer: self, generation: generation)
    let previous = tail
    let id = nextID
    nextID += 1
    let task = Task { @MainActor in
      await previous?.value
      defer {
        self.unsettled -= 1
        self.running[id] = nil
      }
      do {
        try turn.check()
        try await change(turn)
        if turn.isCurrent { self.failure = nil }
      } catch {
        if !(error is CancellationError), turn.isCurrent { self.failure = error }
      }
    }
    running[id] = task
    tail = task
  }

  /// Stops every change queued or running: none passes another check, and a return under way
  /// is disarmed and its arrival's start undone at once. Changes queued later run normally.
  public func supersede() {
    generation += 1
    pendingReturn = nil
    for task in running.values { task.cancel() }
    let stop = stopArrival
    stopArrival = nil
    stop?()
  }

  /// Stops every change for good; nothing queued later runs.
  public func close() {
    isClosed = true
    supersede()
  }

  /// Waits until every change queued so far has ended.
  public func drain() async {
    await tail?.value
  }

  /// A profile decision started reading the store's cookies.
  public func beginDecision() { pendingDecisions += 1 }

  /// That decision ended.
  public func endDecision() { pendingDecisions -= 1 }

  /// Forgets a kept failure.
  public func clearFailure() { failure = nil }

  /// The session shows a document other than the return's.
  public func leftReturnDocument() { returnDocument = nil }

  /// Waits until every profile decision and change has settled, then rethrows the last failed
  /// change once.
  public func settle(timeout: Duration, timeoutError: any Error) async throws {
    let deadline = ContinuousClock.now + timeout
    while pendingDecisions > 0 || unsettled > 0 {
      try Task.checkCancellation()
      guard ContinuousClock.now < deadline else { throw timeoutError }
      try await Task.sleep(for: .milliseconds(50))
    }
    if let failure {
      self.failure = nil
      throw failure
    }
  }

  /// Performs a return's arrival: checks `turn`, arms `arrival`, starts the empty document with
  /// no suspension in between and waits until `arrived` reports it, rechecking `turn` after
  /// every wait. The return is disarmed on every exit, so a stopped, failed or timed-out return
  /// leaves nothing a later navigation decision could match. A stop (`supersede`, `close`) calls
  /// `stop` at once, before any await; a failed or timed-out arrival calls it on its way out.
  public func arrive(
    _ arrival: Return, turn: Turn, timeout: Duration, timeoutError: any Error,
    start: () throws -> Void, stop: @escaping @MainActor () -> Void,
    arrived: () throws -> Bool
  ) async throws {
    try turn.check()
    pendingReturn = arrival
    returnDocument = arrival.base
    returnDocumentAdmitted = false
    stopArrival = stop
    defer {
      pendingReturn = nil
      stopArrival = nil
    }
    do {
      try start()
      let deadline = ContinuousClock.now + timeout
      while try !arrived() {
        try await Task.sleep(for: .milliseconds(50))
        try turn.check()
        guard ContinuousClock.now < deadline else { throw timeoutError }
      }
    } catch {
      // Nil when a stop already undid the start.
      stopArrival?()
      throw error
    }
  }

  /// Whether a navigation decision may allow the return's own empty document: once per return,
  /// and never without one.
  public func admitReturnDocument() -> Bool {
    guard pendingReturn != nil, !returnDocumentAdmitted else { return false }
    returnDocumentAdmitted = true
    return true
  }

  /// The return's target navigation was allowed: nothing else matches it any more.
  public func returnArrived() { pendingReturn = nil }
}
