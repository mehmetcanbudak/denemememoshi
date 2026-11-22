import Dispatch
import Foundation
import Synchronization

/// Runs every append to one ``DeviceStateJournal`` on a single serial lane, in the order the
/// owner issued them. An owner can wait for an append in place (``appendNow(_:)``), suspend
/// until it is durable (``enqueue(_:)`` then ``PendingJournalWrite/value()``), or let it finish
/// in the background. Every append still runs after every append issued before it, so the
/// journal's record order is always the owner's decision order.
final class OrderedJournalWriter: Sendable {
  private let journal: DeviceStateJournal
  private let lane = DispatchQueue(label: "memoshi.device-journal")
  /// Runs on the lane just before each append; tests use it to hold a write the way a stalled
  /// `fsync` holds one, or to fail it the way an I/O error does.
  let willAppend = Mutex<(@Sendable () throws -> Void)?>(nil)
  /// Set by ``replaceNow(_:)``: every later append is refused.
  private let replaced = Mutex(false)

  init(journal: DeviceStateJournal) { self.journal = journal }

  /// Transfers the rows recovered when the journal was opened.
  func takeRecovered() -> [Data] { journal.takeRecovered() }

  /// Appends after every earlier append and blocks the calling thread until it is durable.
  func appendNow<T: Encodable & Sendable>(_ value: T) throws {
    try lane.sync { try write(value) }
  }

  /// Issues an append after every earlier append and returns without waiting for it.
  func enqueue<T: Encodable & Sendable>(_ value: T) -> PendingJournalWrite {
    let pending = PendingJournalWrite()
    lane.async { [self] in
      do {
        try write(value)
        pending.finish(.success(()))
      } catch {
        pending.finish(.failure(error))
      }
    }
    return pending
  }

  /// After every earlier append, replaces the whole journal with `value` alone (the journal's
  /// own replace: written beside it, synchronized, renamed over it, directory synchronized), so
  /// no byte of an earlier record is in the file when this returns. Every append issued after
  /// it is refused, never written.
  func replaceNow<T: Encodable & Sendable>(_ value: T) throws {
    try lane.sync {
      try journal.replace(value)
      replaced.withLock { $0 = true }
    }
  }

  /// Waits for every issued append, then closes the journal.
  func close() async {
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      lane.async { [journal] in
        journal.close()
        done.resume()
      }
    }
  }

  private func write<T: Encodable>(_ value: T) throws {
    guard !replaced.withLock({ $0 }) else { throw DeviceLayerError.closed }
    try willAppend.withLock { $0 }?()
    try journal.append(value)
  }
}

/// The outcome of one ``OrderedJournalWriter/enqueue(_:)`` append.
final class PendingJournalWrite: Sendable {
  private struct State {
    var result: Result<Void, any Error>?
    var waiters: [CheckedContinuation<Void, any Error>] = []
  }

  private let state = Mutex(State())

  fileprivate func finish(_ result: Result<Void, any Error>) {
    let waiters = state.withLock { state in
      state.result = result
      defer { state.waiters.removeAll() }
      return state.waiters
    }
    for waiter in waiters { waiter.resume(with: result) }
  }

  /// Returns once the append is durable; rethrows its failure.
  func value() async throws {
    try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, any Error>) in
      let finished = state.withLock { state -> Result<Void, any Error>? in
        if state.result == nil { state.waiters.append(waiter) }
        return state.result
      }
      if let finished { waiter.resume(with: finished) }
    }
  }
}
