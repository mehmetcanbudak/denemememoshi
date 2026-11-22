import Foundation

/// One external-effect request from a qualification tool: the idempotency key and the run/step
/// slot it claims. The ledger never receives credentials; `payloadHash` covers the effect body.
package struct EffectAttempt: Codable, Equatable, Sendable {
  /// The idempotency key, derived by the tool from the durable task/call identity.
  package var key: String
  /// The qualification run.
  package var run: String
  /// The logical step within the run; at most one effect may exist per run/step.
  package var step: String
  /// The digest of the effect body; a reused key with a different body is a conflict.
  package var payloadHash: String
  /// The Pi call ID the tool observed.
  package var callID: String?
  /// The durable `<conversation>:<Pi task>` identity the key was derived from.
  package var taskKey: String?
  /// The host life (1 = first process) that posted.
  package var life: Int?
  /// The posting host's process ID.
  package var pid: Int32?

  package init(
    key: String, run: String, step: String, payloadHash: String, callID: String? = nil,
    taskKey: String? = nil, life: Int? = nil, pid: Int32? = nil
  ) {
    self.key = key
    self.run = run
    self.step = step
    self.payloadHash = payloadHash
    self.callID = callID
    self.taskKey = taskKey
    self.life = life
    self.pid = pid
  }
}

/// What the ledger did with one attempt.
package enum EffectDisposition: String, Codable, Sendable {
  /// A new key: the effect happened now.
  case recorded
  /// The key was already recorded with the same body: deduplicated, no new effect.
  case replayed
  /// The key was already recorded with a different body: refused.
  case conflict
}

/// One durable journal line: every attempt is kept, in arrival order.
package struct EffectLedgerRecord: Codable, Equatable, Sendable {
  /// One-based attempt sequence.
  package var seq: Int
  /// Arrival time in Unix milliseconds.
  package var receivedAt: Int64
  /// The attempt as received.
  package var attempt: EffectAttempt
  /// The ledger's decision.
  package var disposition: EffectDisposition
  /// The sequence of the attempt that originally recorded this key.
  package var effectSeq: Int
}

/// Totals over attempts. `duplicates` counts effects beyond the first for one run/step, the
/// S1.13 "duplicated external effects" measure; replays are deduplicated retries, not effects.
package struct EffectTotals: Codable, Equatable, Sendable {
  /// Every attempt received.
  package var attempts = 0
  /// Distinct keys recorded, that is, effects that happened.
  package var effects = 0
  /// Same-key, same-body retries that caused no new effect.
  package var replays = 0
  /// Same-key, different-body attempts that were refused.
  package var conflicts = 0
  /// Recorded effects beyond the first for the same run/step.
  package var duplicates = 0

  package init() {}
}

/// Totals for the whole ledger and for each run.
package struct EffectLedgerSummary: Codable, Equatable, Sendable {
  /// Totals across every run.
  package var total: EffectTotals
  /// Totals per run, keyed by run identifier.
  package var runs: [String: EffectTotals]
}

/// The in-memory index over the append-only journal. Deterministic and I/O-free.
package struct EffectLedgerState: Sendable {
  private(set) var records: [EffectLedgerRecord] = []
  private var recordedByKey: [String: Int] = [:]

  package init() {}

  /// Decides one attempt and returns the record that must be journaled before replying.
  package func decide(_ attempt: EffectAttempt, at time: Int64) -> EffectLedgerRecord {
    let seq = records.count + 1
    let record: EffectLedgerRecord
    if let index = recordedByKey[attempt.key] {
      let original = records[index]
      record = EffectLedgerRecord(
        seq: seq, receivedAt: time, attempt: attempt,
        disposition: original.attempt.payloadHash == attempt.payloadHash ? .replayed : .conflict,
        effectSeq: original.seq)
    } else {
      record = EffectLedgerRecord(
        seq: seq, receivedAt: time, attempt: attempt, disposition: .recorded, effectSeq: seq)
    }
    return record
  }

  /// Adds a decided or reloaded record. Reloaded journals must be gap-free and consistent.
  package mutating func apply(_ record: EffectLedgerRecord) throws {
    guard record.seq == records.count + 1 else { throw EffectLedgerError.corruptJournal }
    switch record.disposition {
    case .recorded:
      guard recordedByKey[record.attempt.key] == nil, record.effectSeq == record.seq else {
        throw EffectLedgerError.corruptJournal
      }
      recordedByKey[record.attempt.key] = records.count
    case .replayed, .conflict:
      guard let index = recordedByKey[record.attempt.key], records[index].seq == record.effectSeq
      else { throw EffectLedgerError.corruptJournal }
    }
    records.append(record)
  }

  /// Every attempt for one run, in arrival order.
  package func attempts(run: String) -> [EffectLedgerRecord] {
    records.filter { $0.attempt.run == run }
  }

  package func summary() -> EffectLedgerSummary {
    Self.summarize(records)
  }

  /// Computes totals from any record sequence, including one read back from disk.
  package static func summarize(_ records: [EffectLedgerRecord]) -> EffectLedgerSummary {
    var total = EffectTotals()
    var runs: [String: EffectTotals] = [:]
    var effectsPerSlot: [String: [String: Int]] = [:]
    for record in records {
      let run = record.attempt.run
      var totals = runs[run] ?? EffectTotals()
      totals.attempts += 1
      total.attempts += 1
      switch record.disposition {
      case .recorded:
        totals.effects += 1
        total.effects += 1
        let prior = effectsPerSlot[run, default: [:]][record.attempt.step, default: 0]
        effectsPerSlot[run, default: [:]][record.attempt.step] = prior + 1
        if prior > 0 {
          totals.duplicates += 1
          total.duplicates += 1
        }
      case .replayed:
        totals.replays += 1
        total.replays += 1
      case .conflict:
        totals.conflicts += 1
        total.conflicts += 1
      }
      runs[run] = totals
    }
    return EffectLedgerSummary(total: total, runs: runs)
  }
}

/// Ledger failures.
package enum EffectLedgerError: Error, Equatable {
  /// A complete journal line is out of order, inconsistent or undecodable.
  case corruptJournal
  /// The journal could not be written durably.
  case writeFailed
}

/// Append-only JSONL persistence: one record per line, flushed with `fsync` before the ledger
/// replies, so an acknowledged effect survives a kill of any process. A torn final line (no
/// newline) can only belong to an unacknowledged attempt and is truncated on open.
package final class EffectLedgerJournal {
  /// The journal file.
  package let url: URL
  private let handle: FileHandle
  private let encoder: JSONEncoder

  /// Opens or creates the journal and returns every complete record it already holds.
  package init(url: URL) throws {
    self.url = url
    if !FileManager.default.fileExists(atPath: url.path) {
      guard
        FileManager.default.createFile(
          atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
      else { throw EffectLedgerError.writeFailed }
    }
    handle = try FileHandle(forUpdating: url)
    encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  }

  deinit { try? handle.close() }

  /// Reads complete lines, truncates a torn tail and positions writes at the end.
  package func load() throws -> [EffectLedgerRecord] {
    try handle.seek(toOffset: 0)
    let data = try handle.readToEnd() ?? Data()
    var records: [EffectLedgerRecord] = []
    var complete = 0
    let decoder = JSONDecoder()
    var lineStart = data.startIndex
    while let newline = data[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
      let line = data[lineStart..<newline]
      if !line.isEmpty {
        do {
          records.append(try decoder.decode(EffectLedgerRecord.self, from: line))
        } catch {
          throw EffectLedgerError.corruptJournal
        }
      }
      lineStart = data.index(after: newline)
      complete = lineStart - data.startIndex
    }
    if complete < data.count { try handle.truncate(atOffset: UInt64(complete)) }
    try handle.seekToEnd()
    return records
  }

  /// Appends one record and flushes it to stable storage before returning.
  package func append(_ record: EffectLedgerRecord) throws {
    var line = try encoder.encode(record)
    line.append(UInt8(ascii: "\n"))
    do {
      try handle.write(contentsOf: line)
      try handle.synchronize()
    } catch {
      throw EffectLedgerError.writeFailed
    }
  }

  /// Reads a journal without opening it for writing, for offline summaries.
  package static func read(_ url: URL) throws -> [EffectLedgerRecord] {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    var records: [EffectLedgerRecord] = []
    var lineStart = data.startIndex
    while let newline = data[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
      let line = data[lineStart..<newline]
      if !line.isEmpty { records.append(try decoder.decode(EffectLedgerRecord.self, from: line)) }
      lineStart = data.index(after: newline)
    }
    return records
  }
}

/// The ledger's single writer: decide, journal durably, then publish to the in-memory index.
package actor EffectLedgerStore {
  private var state = EffectLedgerState()
  private let journal: EffectLedgerJournal
  private let now: @Sendable () -> Int64

  /// Opens the journal in `directory` and replays it into the index.
  package init(
    directory: URL,
    now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
  ) throws {
    let journal = try EffectLedgerJournal(url: directory.appendingPathComponent("effects.jsonl"))
    var state = EffectLedgerState()
    for record in try journal.load() { try state.apply(record) }
    self.journal = journal
    self.state = state
    self.now = now
  }

  /// Records or deduplicates one attempt; the result is durable before this returns.
  package func submit(_ attempt: EffectAttempt) throws -> EffectLedgerRecord {
    let record = state.decide(attempt, at: now())
    try journal.append(record)
    try state.apply(record)
    return record
  }

  package func attempts(run: String) -> [EffectLedgerRecord] { state.attempts(run: run) }

  package func summary() -> EffectLedgerSummary { state.summary() }
}
