import Foundation

/// One Seatbelt instance as the Store keeps it (S4.7): a command or a daemon life, registered
/// before its exec under the tag its profile makes the kernel print.
public struct SandboxInvocationRecord: Sendable, Equatable {
  /// `memoshi-inv-` and 128 random bits in lowercase hex.
  public let tag: String
  /// `command` or `daemon`.
  public let kind: String
  /// The bot of the computer.
  public let botID: String?
  /// The conversation of the computer.
  public let conversationID: String?
  /// The computer.
  public let computerID: String?
  /// The tool call whose command this is, when it has one.
  public let callID: String?
  /// SHA-256 of the argv, never its text.
  public let commandSHA256: String?
  /// Milliseconds since 1970, before the exec.
  public let startedAt: Int64
  /// When its leader exited; nil while running or when not observed.
  public var returnedAt: Int64?
  /// The leader's exit status, when the command produced one.
  public var exitCode: Int?

  /// A registered instance; `returnedAt` and `exitCode` are set by a later return.
  public init(
    tag: String, kind: String, botID: String?, conversationID: String?, computerID: String?,
    callID: String?, commandSHA256: String?, startedAt: Int64, returnedAt: Int64? = nil,
    exitCode: Int? = nil
  ) {
    self.tag = tag
    self.kind = kind
    self.botID = botID
    self.conversationID = conversationID
    self.computerID = computerID
    self.callID = callID
    self.commandSHA256 = commandSHA256
    self.startedAt = startedAt
    self.returnedAt = returnedAt
    self.exitCode = exitCode
  }
}

/// One kernel denial report read back, linked to its invocation or explicitly unattributed.
public struct SandboxDenialRecord: Sendable, Equatable {
  /// The tag the kernel printed, at most 256 bytes.
  public let tag: String
  /// The registered invocation's tag; nil when unattributed.
  public let invocationTag: String?
  /// Milliseconds since 1970 when the reader received it.
  public let receivedAt: Int64
  /// The log's own timestamp text.
  public let reportedAt: String?
  /// `unknown_tag`, `malformed_tag` or `truncated` (cut by the kernel before its tag line);
  /// nil when attributed.
  public let unattributed: String?
  /// The report without its tag line, at most 4096 bytes. The sandbox monitor writes none for
  /// `unknown_tag`, whose conversation no purge could reach.
  public let report: String
  /// For a coalesced "N duplicate reports" line, N; otherwise 0.
  public let duplicates: Int
  /// Received after the invocation's leader returned: from a descendant that outlived it. The
  /// tag names that process lineage, never a later command that may have driven it.
  public let afterReturn: Bool

  /// One denial; exactly one of `invocationTag` and `unattributed` is set.
  public init(
    tag: String, invocationTag: String?, receivedAt: Int64, reportedAt: String?,
    unattributed: String?, report: String, duplicates: Int, afterReturn: Bool = false
  ) {
    self.tag = tag
    self.invocationTag = invocationTag
    self.receivedAt = receivedAt
    self.reportedAt = reportedAt
    self.unattributed = unattributed
    self.report = report
    self.duplicates = duplicates
    self.afterReturn = afterReturn
  }
}

/// A time when denials could not be read; nothing the kernel reported then was kept.
public struct SandboxGapRecord: Sendable, Equatable {
  /// One monitor (host) life.
  public let life: String
  /// The gap's order within that life.
  public let sequence: Int
  /// Milliseconds since 1970 when reading stopped or was last confirmed.
  public let from: Int64
  /// Nil while it is still open.
  public let to: Int64?
  /// `reader_starting`, `reader_stopped`, `reader_idle`, `reader_silent`, `events_lost`,
  /// `report_truncated`, `report_burst`, `report_rate`, `reports_dropped`, `store_dropped` or
  /// `log_dropped`.
  public let reason: String
  /// Reports in a `report_truncated`, `report_burst` or `report_rate` stretch, probe reports
  /// missing for `reports_dropped`, or entries a `store_dropped` or `log_dropped` gap stands for.
  public let count: Int?

  /// A gap as opened, or the same gap (same life and sequence) closed or grown.
  public init(
    life: String, sequence: Int, from: Int64, to: Int64?, reason: String, count: Int? = nil
  ) {
    self.life = life
    self.sequence = sequence
    self.from = from
    self.to = to
    self.reason = reason
    self.count = count
  }
}

/// One attribution fact written after its invocation: a return, a denial or a gap.
public enum SandboxAttributionWrite: Sendable, Equatable {
  /// An invocation's leader exited. A pruned invocation is left pruned.
  case returned(tag: String, at: Int64, exitCode: Int?)
  /// A denial; an attributed one carries its invocation, which is written again when
  /// retention already removed it, so the link always resolves. A denial whose invocation
  /// names a purged or purging conversation is dropped with it, so a purge stays complete.
  case denial(SandboxDenialRecord, invocation: SandboxInvocationRecord?)
  /// A gap as opened, or the same gap closed or grown.
  case gap(SandboxGapRecord)
}

/// Row-count bounds of the attribution tables. The newest rows are kept. An invocation that a
/// retained denial names is kept with it, so invocations stay below `invocations + denials`.
public struct SandboxAttributionRetention: Sendable, Equatable {
  /// Denial rows kept.
  public let denials: Int
  /// Closed gap rows kept for each reason. A gap still open is always kept, so a flood of one
  /// reason never erases the record of another outage.
  public let gaps: Int
  /// Invocation rows kept beyond those a retained denial names.
  public let invocations: Int

  /// 10,000 denials, 1,000 closed gaps of each reason and 10,000 invocations.
  public static let standard = SandboxAttributionRetention(
    denials: 10_000, gaps: 1_000, invocations: 10_000)

  /// Each bound is at least 1.
  public init(denials: Int, gaps: Int, invocations: Int) {
    self.denials = max(1, denials)
    self.gaps = max(1, gaps)
    self.invocations = max(1, invocations)
  }
}

/// Every retained attribution row, oldest first.
public struct SandboxAttributionSnapshot: Sendable, Equatable {
  /// Retained invocations.
  public let invocations: [SandboxInvocationRecord]
  /// Retained denials.
  public let denials: [SandboxDenialRecord]
  /// Retained gaps.
  public let gaps: [SandboxGapRecord]
}

extension Store {
  /// Records an invocation before its exec; a duplicate tag, or a conversation that is purged
  /// or being purged, fails.
  public func recordSandboxInvocation(
    _ invocation: SandboxInvocationRecord, retention: SandboxAttributionRetention = .standard
  ) throws {
    try requireOpen()
    try writer.transaction(write: true) {
      if let conversation = invocation.conversationID,
        try sandboxConversationPurged(conversation)
      {
        throw StoreError.invalidCommit("The conversation was purged")
      }
      try insertSandboxInvocation(invocation, ignoringDuplicate: false)
      try pruneSandboxInvocations(retention)
    }
  }

  /// Writes `writes` in order in one transaction, then applies retention once.
  public func recordSandboxAttribution(
    _ writes: [SandboxAttributionWrite], retention: SandboxAttributionRetention = .standard
  ) throws {
    try requireOpen()
    for case .denial(let denial, let invocation) in writes {
      guard (invocation == nil) == (denial.invocationTag == nil),
        invocation.map({ $0.tag == denial.invocationTag }) ?? true
      else { throw StoreError.invalidCommit("A denial names exactly its own invocation") }
    }
    try writer.transaction(write: true) {
      var purged: [String: Bool] = [:]
      for write in writes {
        switch write {
        case .returned(let tag, let at, let exitCode):
          try writer.execute(
            "UPDATE sandbox_invocations SET returned_at = ?, exit_code = ? WHERE tag = ? AND returned_at IS NULL",
            [.integer(at), exitCode.map { .integer(Int64($0)) } ?? .null, .text(tag)])
        case .denial(let denial, let invocation):
          // A late or already queued denial never brings a purged conversation back.
          if let conversation = invocation?.conversationID {
            let gone = try purged[conversation] ?? sandboxConversationPurged(conversation)
            purged[conversation] = gone
            if gone { continue }
          }
          if let invocation { try insertSandboxInvocation(invocation, ignoringDuplicate: true) }
          try writer.execute(
            """
            INSERT INTO sandbox_denials
              (tag, invocation_tag, received_at, reported_at, unattributed, report, duplicates,
               after_return)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
              .text(denial.tag), .init(denial.invocationTag), .integer(denial.receivedAt),
              .init(denial.reportedAt), .init(denial.unattributed), .text(denial.report),
              .integer(Int64(denial.duplicates)), .integer(denial.afterReturn ? 1 : 0),
            ])
        case .gap(let gap):
          try writer.execute(
            """
            INSERT INTO sandbox_attribution_gaps
              (life, sequence, started_at, ended_at, reason, count)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (life, sequence) DO UPDATE
              SET ended_at = excluded.ended_at, count = excluded.count
              WHERE started_at = excluded.started_at AND reason = excluded.reason
            """,
            [
              .text(gap.life), .integer(Int64(gap.sequence)), .integer(gap.from),
              gap.to.map(SQLiteConnection.Value.integer) ?? .null, .text(gap.reason),
              gap.count.map { .integer(Int64($0)) } ?? .null,
            ])
        }
      }
      try writer.execute(
        """
        DELETE FROM sandbox_denials WHERE id <=
          (SELECT id FROM sandbox_denials ORDER BY id DESC LIMIT 1 OFFSET ?)
        """, [.integer(Int64(retention.denials))])
      try writer.execute(
        """
        DELETE FROM sandbox_attribution_gaps WHERE rowid IN
          (SELECT rowid FROM
            (SELECT rowid, row_number() OVER (PARTITION BY reason ORDER BY rowid DESC) AS newer
              FROM sandbox_attribution_gaps WHERE ended_at IS NOT NULL)
            WHERE newer > ?)
        """, [.integer(Int64(retention.gaps))])
      try pruneSandboxInvocations(retention)
    }
  }

  /// Every retained invocation, denial and gap, each oldest first.
  public func sandboxAttribution() throws -> SandboxAttributionSnapshot {
    try requireOpen()
    return try reader.transaction(write: false) {
      let invocations = try reader.query(
        """
        SELECT tag, kind, bot_id, conversation_id, computer_id, call_id, command_sha256,
          started_at, returned_at, exit_code
        FROM sandbox_invocations ORDER BY rowid
        """
      ) { row in
        SandboxInvocationRecord(
          tag: try row.requiredText(0), kind: try row.requiredText(1), botID: row.text(2),
          conversationID: row.text(3), computerID: row.text(4), callID: row.text(5),
          commandSHA256: row.text(6), startedAt: row.integer(7),
          returnedAt: row.optionalInteger(8), exitCode: row.optionalInteger(9).map { Int($0) })
      }
      let denials = try reader.query(
        """
        SELECT tag, invocation_tag, received_at, reported_at, unattributed, report, duplicates,
          after_return
        FROM sandbox_denials ORDER BY id
        """
      ) { row in
        SandboxDenialRecord(
          tag: try row.requiredText(0), invocationTag: row.text(1), receivedAt: row.integer(2),
          reportedAt: row.text(3), unattributed: row.text(4), report: try row.requiredText(5),
          duplicates: Int(row.integer(6)), afterReturn: row.integer(7) == 1)
      }
      let gaps = try reader.query(
        """
        SELECT life, sequence, started_at, ended_at, reason, count
        FROM sandbox_attribution_gaps ORDER BY rowid
        """
      ) { row in
        SandboxGapRecord(
          life: try row.requiredText(0), sequence: Int(row.integer(1)), from: row.integer(2),
          to: row.optionalInteger(3), reason: try row.requiredText(4),
          count: row.optionalInteger(5).map { Int($0) })
      }
      return SandboxAttributionSnapshot(invocations: invocations, denials: denials, gaps: gaps)
    }
  }

  private func insertSandboxInvocation(
    _ invocation: SandboxInvocationRecord, ignoringDuplicate: Bool
  ) throws {
    try writer.execute(
      """
      INSERT \(ignoringDuplicate ? "OR IGNORE " : "")INTO sandbox_invocations
        (tag, kind, bot_id, conversation_id, computer_id, call_id, command_sha256, started_at,
         returned_at, exit_code)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        .text(invocation.tag), .text(invocation.kind), .init(invocation.botID),
        .init(invocation.conversationID), .init(invocation.computerID), .init(invocation.callID),
        .init(invocation.commandSHA256), .integer(invocation.startedAt),
        invocation.returnedAt.map(SQLiteConnection.Value.integer) ?? .null,
        invocation.exitCode.map { .integer(Int64($0)) } ?? .null,
      ])
  }

  /// Removes the oldest invocations beyond the bound that no retained denial names.
  private func pruneSandboxInvocations(_ retention: SandboxAttributionRetention) throws {
    try writer.execute(
      """
      DELETE FROM sandbox_invocations WHERE rowid <=
        (SELECT rowid FROM sandbox_invocations ORDER BY rowid DESC LIMIT 1 OFFSET ?)
        AND NOT EXISTS
          (SELECT 1 FROM sandbox_denials d WHERE d.invocation_tag = sandbox_invocations.tag)
      """, [.integer(Int64(retention.invocations))])
  }

  /// Whether `conversation` is purged or selected by a purge job still under way.
  private func sandboxConversationPurged(_ conversation: String) throws -> Bool {
    try !writer.query(
      "SELECT 1 FROM chats WHERE id = ? AND (purged_at IS NOT NULL OR purge_pending = 1)",
      [.text(conversation)]
    ) { _ in true }.isEmpty
  }
}
