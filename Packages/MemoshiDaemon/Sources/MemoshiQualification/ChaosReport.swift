import Foundation

/// A run's verdict. Only `pass` counts toward S1.13's 50 of 50.
package enum RunOutcome: String, Codable, Sendable {
  /// Every check held.
  case pass
  /// At least one check failed; `failures` names each one.
  case fail
}

/// Whether a pending approval survived a kill as the same decision and card (S1.11).
package enum ApprovalReattach: String, Codable, Sendable {
  /// The run had no pending approval at a kill.
  case notApplicable = "n/a"
  /// After every restart the pending approval kept its ID and card, with no duplicate.
  case reattached
  /// A restart lost, replaced or duplicated the pending approval.
  case failed
}

/// The committed transcript compared with the scripted turn.
package struct TranscriptCheck: Codable, Equatable, Sendable {
  /// User messages in the Chat.
  package var userMessages = 0
  /// Bot messages in the Chat.
  package var botMessages = 0
  /// Bot messages whose text equals the scripted final answer.
  package var finalAnswers = 0
  /// Whether the last message is the scripted final answer.
  package var endsWithFinalAnswer = false
  /// Whether every message ID is unique.
  package var uniqueIDs = true

  package init() {}
}

/// One run's complete, nonsecret record: one JSON line in `results.jsonl`.
package struct RunResult: Codable, Equatable, Sendable {
  /// The run identifier.
  package var run: String
  /// The planned run.
  package var plan: PlannedRun
  /// The verdict.
  package var outcome: RunOutcome = .fail
  /// Every failed check, in the order observed.
  package var failures: [String] = []
  /// SIGKILLs delivered and observed as signal 9.
  package var killsDelivered = 0
  /// How each host life ended, in order.
  package var lifeExits: [String] = []
  /// Driver-measured spawn-to-ready time of each restarted life, in milliseconds.
  package var resumeToReadyMs: [Int64] = []
  /// Host-measured launch-to-ready time of every life, in milliseconds.
  package var hostReadyMs: [Int64] = []
  /// The final turn/task status.
  package var finalStatus: String?
  /// Whether every resubmission returned the original receipt.
  package var originalReceipts: Bool?
  /// Pending-approval reattachment across kills.
  package var approvalReattach: ApprovalReattach = .notApplicable
  /// Approval records in the conversation at the end.
  package var approvals = 0
  /// Approval cards in the conversation at the end.
  package var cards = 0
  /// Whether any effect was recorded before an approval decision.
  package var executedWithoutDecision = false
  /// Durable `tool.completed` facts for the qualification tool.
  package var toolCompletions = 0
  /// Durable `tool.completed` facts for the `subagent` delegation tool.
  package var subagentCompletions = 0
  /// The spawned children's task statuses at the end.
  package var childTaskStatuses: [String] = []
  /// What opened each subagent kill window: `held-child-stream` (the scripted provider held
  /// the child's own request) or `second-live-run` (a real model's child was a second live run).
  package var subagentKillWindows: [String] = []
  /// Ledger totals for this run.
  package var ledger = EffectTotals()
  /// The transcript comparison.
  package var transcript = TranscriptCheck()
  /// Canary scan coverage and hits for this run's directories.
  package var canaryFilesScanned = 0
  /// Bytes covered by the canary scan.
  package var canaryBytesScanned = 0
  /// Canary occurrences found (path, encoding, offset; never values).
  package var canaryHits: [CanaryHit] = []
  /// Provider request counts.
  package var provider = ProviderCounts()
  /// Wall time for the run, in milliseconds.
  package var durationMs: Int64 = 0

  package init(run: String, plan: PlannedRun) {
    self.run = run
    self.plan = plan
  }

  /// Records a failed check.
  package mutating func fail(_ reason: String) { failures.append(reason) }
}

/// Totals for one kill point.
package struct KillPointTotals: Codable, Equatable, Sendable {
  /// Runs planned at this point.
  package var runs = 0
  /// Runs that passed.
  package var passed = 0

  package init() {}
}

/// Batch totals in the shape of phase-0 S1's measurement table.
package struct ChaosSummary: Codable, Equatable, Sendable {
  /// Runs executed.
  package var runs = 0
  /// Runs that passed every check.
  package var passed = 0
  /// Runs with at least one failed check.
  package var failed = 0
  /// Per kill point, keyed by its raw value.
  package var byKillPoint: [String: KillPointTotals] = [:]
  /// Duplicated external effects across the batch (S1 pass: 0).
  package var duplicates = 0
  /// Refused same-key, different-body attempts.
  package var conflicts = 0
  /// Deduplicated retries, which caused no effect.
  package var replays = 0
  /// Runs whose approval was pending at a kill.
  package var approvalKillRuns = 0
  /// Of those, runs where it reattached to the same decision and card.
  package var approvalsReattached = 0
  /// Runs where an effect preceded its approval decision (S1 pass: 0).
  package var executedWithoutDecision = 0
  /// Canary hits across the batch (pass: 0).
  package var canaryHits = 0
  /// Restarted lives measured.
  package var resumeSamples = 0
  /// Median spawn-to-ready time after a kill.
  package var resumeToReadyP50Ms: Int64?
  /// Nearest-rank 95th percentile spawn-to-ready time after a kill (S1: p95 < 2 s).
  package var resumeToReadyP95Ms: Int64?
  /// Slowest spawn-to-ready time after a kill.
  package var resumeToReadyMaxMs: Int64?

  package init() {}

  /// Aggregates per-run results.
  package static func aggregate(_ results: [RunResult]) -> ChaosSummary {
    var summary = ChaosSummary()
    var samples: [Int64] = []
    for result in results {
      summary.runs += 1
      var totals = summary.byKillPoint[result.plan.killPoint.rawValue] ?? KillPointTotals()
      totals.runs += 1
      if result.outcome == .pass {
        summary.passed += 1
        totals.passed += 1
      } else {
        summary.failed += 1
      }
      summary.byKillPoint[result.plan.killPoint.rawValue] = totals
      summary.duplicates += result.ledger.duplicates
      summary.conflicts += result.ledger.conflicts
      summary.replays += result.ledger.replays
      if result.approvalReattach != .notApplicable {
        summary.approvalKillRuns += 1
        if result.approvalReattach == .reattached { summary.approvalsReattached += 1 }
      }
      if result.executedWithoutDecision { summary.executedWithoutDecision += 1 }
      summary.canaryHits += result.canaryHits.count
      samples += result.resumeToReadyMs
    }
    samples.sort()
    summary.resumeSamples = samples.count
    summary.resumeToReadyP50Ms = percentile(samples, 0.50)
    summary.resumeToReadyP95Ms = percentile(samples, 0.95)
    summary.resumeToReadyMaxMs = samples.last
    return summary
  }

  /// Nearest-rank percentile of ascending samples.
  package static func percentile(_ sorted: [Int64], _ fraction: Double) -> Int64? {
    guard !sorted.isEmpty else { return nil }
    let rank = Int((fraction * Double(sorted.count)).rounded(.up))
    return sorted[min(max(rank, 1), sorted.count) - 1]
  }
}

/// The batch-level outcome the published table states, as known when the table is rendered.
package struct ChaosVerdict: Sendable {
  /// Whether every batch check passed: runs, ledger, scans, retention and cleanup.
  package var passed: Bool
  /// How the ledger process ended, or `not started`.
  package var ledgerExit: String
  /// Whether the live and journal ledger summaries agree.
  package var ledgerJournalConsistent: Bool
  /// Whether the work directory was cleaned up.
  package var workCleanup: Bool
  /// Whether the scan of every output file found no canary.
  package var outputClean: Bool
  /// Batch startup, capture, retention, publication and cleanup failures.
  package var failures: [String]

  package init(
    passed: Bool, ledgerExit: String, ledgerJournalConsistent: Bool, workCleanup: Bool,
    outputClean: Bool, failures: [String]
  ) {
    self.passed = passed
    self.ledgerExit = ledgerExit
    self.ledgerJournalConsistent = ledgerJournalConsistent
    self.workCleanup = workCleanup
    self.outputClean = outputClean
    self.failures = failures
  }
}

/// Renders the per-run table the S1 report needs, followed by the batch totals, the batch
/// verdict and every batch failure.
package enum ChaosMarkdown {
  package static func render(
    _ results: [RunResult], summary: ChaosSummary, ledger: EffectLedgerSummary?,
    verdict: ChaosVerdict, header: [String]
  ) -> String {
    var lines = header
    lines.append("")
    lines.append(
      "| Run | Kill point | Kills | Outcome | Duplicates | Approval reattach | Resume to ready (ms) | Ledger attempts / effects / replays | Notes |"
    )
    lines.append("|---|---|---:|---|---:|---|---:|---|---|")
    for result in results {
      let resume =
        result.resumeToReadyMs.isEmpty
        ? "—" : result.resumeToReadyMs.map(String.init).joined(separator: ", ")
      let notes =
        result.failures.isEmpty
        ? "final \(result.finalStatus ?? "?")"
        : result.failures.joined(separator: "; ").replacingOccurrences(of: "|", with: "/")
      lines.append(
        "| \(result.run) | \(result.plan.killPoint.rawValue) | \(result.killsDelivered) | "
          + "\(result.outcome.rawValue) | \(result.ledger.duplicates) | "
          + "\(result.approvalReattach.rawValue) | \(resume) | "
          + "\(result.ledger.attempts) / \(result.ledger.effects) / \(result.ledger.replays) | "
          + "\(notes) |")
    }
    lines.append("")
    lines.append("| Measurement | Observed |")
    lines.append("|---|---|")
    lines.append("| Batch verdict | \(verdict.passed ? "pass" : "fail") |")
    lines.append("| Kill/resume runs correct | \(summary.passed) of \(summary.runs) |")
    lines.append("| Duplicated external effects (ledger) | \(summary.duplicates) |")
    lines.append(
      "| Approvals pending at a kill that reattached | "
        + "\(summary.approvalsReattached) of \(summary.approvalKillRuns) |")
    lines.append("| Effects before an approval decision | \(summary.executedWithoutDecision) |")
    lines.append("| Canary hits | \(summary.canaryHits) |")
    let p95 = summary.resumeToReadyP95Ms.map { "\($0) ms" } ?? "—"
    let p50 = summary.resumeToReadyP50Ms.map { "\($0) ms" } ?? "—"
    let maximum = summary.resumeToReadyMaxMs.map { "\($0) ms" } ?? "—"
    lines.append(
      "| Resume to ready after a kill (\(summary.resumeSamples) samples) | "
        + "p50 \(p50), p95 \(p95), max \(maximum) |")
    if let ledger {
      lines.append(
        "| Ledger totals | \(ledger.total.attempts) attempts, \(ledger.total.effects) effects, "
          + "\(ledger.total.replays) replays, \(ledger.total.conflicts) conflicts, "
          + "\(ledger.total.duplicates) duplicates |")
    }
    for (point, totals) in summary.byKillPoint.sorted(by: { $0.key < $1.key }) {
      lines.append("| Kill point \(point) | \(totals.passed) of \(totals.runs) |")
    }
    lines.append("| Ledger process exit | \(verdict.ledgerExit) |")
    lines.append(
      "| Live and journal ledger summaries agree | "
        + "\(verdict.ledgerJournalConsistent ? "yes" : "no") |")
    lines.append("| Work cleanup | \(verdict.workCleanup ? "complete" : "incomplete") |")
    lines.append("| Output canary scan | \(verdict.outputClean ? "clean" : "failed") |")
    if !verdict.failures.isEmpty {
      lines.append("")
      lines.append("Batch failures:")
      lines.append("")
      for failure in verdict.failures {
        lines.append("- " + failure.replacingOccurrences(of: "\n", with: " "))
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }
}
