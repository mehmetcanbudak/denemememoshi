import Darwin
import Foundation
import MemoshiDevice
import MemoshiProtocol
import Synchronization

/// `memoshi-qualification s2-relay`: the loopback relay and its lease authority as their own
/// process. Every payload the relay holds (forwarded link frames and, unless disabled, authority
/// messages and control frames with their replies) is appended verbatim to `relay-journal.bin`
/// for the content audit. stdin EOF stops it; it then writes `relay-summary.json` (counters,
/// every grant, CPU and memory use).
package enum S2RelayProcess {
  package static func run(directory: URL, journalAuthority: Bool, keepGrants: Bool) async -> Int32 {
    do {
      raiseDescriptorLimit()
      let journal = try S2Journal(directory.appendingPathComponent("relay-journal.bin"))
      return await run(
        directory: directory, journalAuthority: journalAuthority, keepGrants: keepGrants,
        journal: journal, input: { _ in LineStream.lines(from: STDIN_FILENO, closeAtEnd: false) },
        output: .standardOutput, errorOutput: .standardError)
    } catch {
      LineWriter.standardError.text("s2-relay: \(error)")
      return 1
    }
  }

  package static func run(
    directory: URL, journalAuthority: Bool, keepGrants: Bool, journal: S2Journal,
    input: @Sendable (RelayServer) -> AsyncStream<String>, output: LineWriter,
    errorOutput: LineWriter
  ) async -> Int32 {
    let out = output
    var authority: RelayLeaseAuthority?
    var server: RelayServer?
    var failures: [String] = []
    do {
      let leaseAuthority = try RelayLeaseAuthority(
        directory: directory.appendingPathComponent("durable-authority"), keepsGrants: keepGrants)
      authority = leaseAuthority
      let relay = try await RelayServer.start(
        authority: leaseAuthority,
        mailboxDirectory: directory.appendingPathComponent("durable-mailbox")
      ) { entry in
        guard journalAuthority || entry.kind == "send" else { return }
        journal.append(entry)
      }
      server = relay
      out.write(
        [
          "event": JSONValue.string("listening"), "port": .integer(Int64(relay.port)),
          "pid": .integer(Int64(getpid())),
        ])
      // This private, parent-owned pipe is the only enrollment control plane. A remote relay
      // hello can prove an enrolled key but can never create or replace that enrollment.
      for await line in input(relay) {
        guard let command = try? JSONDecoder().decode(S2Command.self, from: Data(line.utf8)) else {
          out.emit(["event": "badCommand"])
          continue
        }
        var reply: [String: JSONValue] = [
          "id": .integer(Int64(command.id)), "op": .string(command.op),
        ]
        do {
          switch command.op {
          case "enroll":
            guard let groupID = command.groupId, let peers = command.peers else {
              throw DriverError.invalid("enrollment command")
            }
            try await leaseAuthority.enroll(
              groupID: groupID, members: peers.map { try $0.devicePeer() },
              candidates: (command.candidates ?? []).map { try $0.devicePeer() })
          case "revokedProbe":
            guard let revoked = command.peer, let member = command.candidates?.first,
              let conversation = command.conversation, let epoch = command.epoch
            else { throw DriverError.invalid("revoked probe command") }
            let outcome = try await revokedProbe(
              authority: leaseAuthority, revoked: try DeviceID(revoked.deviceId),
              member: try DeviceID(member.deviceId),
              conversation: try ConversationID(conversation), epoch: epoch)
            for (key, value) in outcome { reply[key] = value }
          case "stats":
            // The relay's own counters now, so a probe can be tied to the refusal it caused.
            reply["statistics"] = try JSONValue.parse(JSONLines.encoder.encode(relay.statistics))
          default:
            throw DriverError.invalid("relay command")
          }
          reply["ok"] = .bool(true)
        } catch {
          reply["ok"] = .bool(false)
          reply["error"] = .string("\(error)")
        }
        out.write(reply)
      }
    } catch {
      failures.append("\(error)")
    }
    if let server { await server.close() }
    let journalOutcome = journal.close()
    if case .failed(_, let failure) = journalOutcome {
      failures.append(failure.description)
    }
    if let server, let authority {
      let grants = await authority.grants
      let unique = Set(grants.map { "\($0.conversationID.rawValue)#\($0.epoch)" })
      var usage = rusage()
      getrusage(RUSAGE_SELF, &usage)
      let summary = S2RelaySummary(
        statistics: server.statistics, counters: await authority.counters,
        grants: keepGrants ? grants.count : nil,
        duplicateGrants: keepGrants ? grants.count - unique.count : nil, journal: journalOutcome,
        cpuSeconds: Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
          + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000,
        maximumResidentBytes: Int64(usage.ru_maxrss), grantLog: keepGrants ? grants : [])
      do {
        try JSONLines.prettyEncoder.encode(summary).write(
          to: directory.appendingPathComponent("relay-summary.json"))
      } catch {
        failures.append("\(error)")
      }
    }
    if let authority { await authority.close() }
    guard failures.isEmpty else {
      for failure in failures { errorOutput.text("s2-relay: \(failure)") }
      out.emit(["event": "failed"])
      return 1
    }
    out.emit(["event": "stopped"])
    return 0
  }
}

extension S2RelayProcess {
  /// Puts a device's own claim and renewal of `conversation` at `epoch` to the authority as
  /// that sender, through `handle(_:from:)`: the entry the relay uses for a connection it has
  /// authenticated. Over the network a revoked device never gets that far (the relay refuses
  /// its hello), so this asks the authority's own membership check directly. It reports what
  /// the authority answered, how many requests it counted as refused for a revoked sender,
  /// whether the lease record changed, and whether the same path grants `member` a fresh
  /// conversation (released again), which shows that the probe can see a grant.
  package static func revokedProbe(
    authority: RelayLeaseAuthority, revoked: DeviceID, member: DeviceID,
    conversation: ConversationID, epoch: Int64
  ) async throws -> [String: JSONValue] {
    func ask(_ body: DeviceMessageBody, as sender: DeviceID) async throws -> DeviceMessageBody? {
      await authority.handle(
        DeviceMessage(
          msgId: try ULID(DeviceULID.make()), from: .device(sender), to: .authority,
          sentAt: DeviceClock.wallMilliseconds(), body: body), from: sender)?.body
    }
    let now = DeviceClock.wallMilliseconds()
    let refusalsBefore = await authority.counters.revokedRefusals
    let before = await authority.record(conversation)
    let claim = try await ask(
      .leaseClaim(
        LeaseClaim(conversationId: conversation, expectedEpoch: epoch, expiresAt: now + 10_000)),
      as: revoked)
    let renewal = try await ask(
      .leaseRenew(LeaseRenew(conversationId: conversation, epoch: epoch, expiresAt: now + 10_000)),
      as: revoked)
    let after = await authority.record(conversation)
    let refusals = await authority.counters.revokedRefusals - refusalsBefore
    let fresh = try ConversationID("cht_" + DeviceULID.make())
    var memberGranted = false
    if case .leaseClaimResult(let control)? = try await ask(
      .leaseClaim(LeaseClaim(conversationId: fresh, expectedEpoch: nil, expiresAt: now + 10_000)),
      as: member), control.granted
    {
      memberGranted = true
      _ = try await ask(
        .leaseRelease(LeaseRelease(conversationId: fresh, epoch: control.epoch, lastRseq: 0)),
        as: member)
    }
    var claimGranted = false
    if case .leaseClaimResult(let result)? = claim { claimGranted = result.granted }
    var renewed = false
    if case .leaseRenewResult(let result)? = renewal { renewed = result.renewed }
    return [
      "isRevoked": .bool(await authority.isRevoked(revoked)),
      "revokedRefusals": .integer(Int64(refusals)),
      "claimAnswered": .bool(claim != nil), "claimGranted": .bool(claimGranted),
      "renewAnswered": .bool(renewal != nil), "renewed": .bool(renewed),
      "leaseUnchanged": .bool(
        before?.epoch == after?.epoch && before?.runner == after?.runner
          && before?.expiresAt == after?.expiresAt),
      "leaseEpoch": .integer(after?.epoch ?? 0),
      "leaseRunner": after?.runner.map { .string($0.rawValue) } ?? .null,
      "leaseExpiresAt": after?.expiresAt.map { .integer($0) } ?? .null,
      "leaseExpired": .bool((after?.expiresAt ?? .max) <= now),
      "memberClaimGranted": .bool(memberGranted),
    ]
  }
}

/// What the relay process reports when it stops.
package struct S2RelaySummary: Codable, Sendable {
  package var statistics: RelayStatistics
  package var counters: RelayLeaseAuthority.Counters
  /// The grants issued, and how many reissued a conversation epoch. Absent when the relay kept
  /// no grant log (`--no-grant-log`, the load relays): not measured, never 0.
  package var grants: Int?
  package var duplicateGrants: Int?
  package var journal: S2Journal.Outcome
  package var cpuSeconds: Double
  package var maximumResidentBytes: Int64
  package var grantLog: [RelayLeaseAuthority.Grant]
}

/// Appends `[kind][4-byte length][bytes]` records; the raw bytes are what the canary scan reads.
/// Kinds: 1 `send`, 2 `authority`, 3 `authorityReply`, 4 `control`, 5 `controlReply`. A record
/// of any other kind is not written under another kind's byte: it fails the journal.
///
/// Writes run in append order on one background queue, so a stalled volume never blocks the
/// relay's serve loop (and with it every lease renewal behind that frame). `close()` drains the
/// queue first. Counts cover only completed writes; after the first failure nothing more is
/// written, and that first failure survives into the terminal outcome. The backlog is held in
/// memory until written.
package final class S2Journal: Sendable {
  package struct Counts: Codable, Equatable, Sendable {
    package let bytes: Int
    package let entries: Int
  }

  package enum Failure: Error, Codable, Equatable, Sendable, CustomStringConvertible {
    case write(String)
    case close(String)
    case appendAfterClose
    case unknownKind

    package var description: String {
      switch self {
      case .write(let error): "journal write: \(error)"
      case .close(let error): "journal close: \(error)"
      case .appendAfterClose: "journal append after close"
      case .unknownKind: "journal record of an unknown kind"
      }
    }
  }

  package enum Outcome: Codable, Equatable, Sendable {
    case closed(counts: Counts)
    case failed(counts: Counts, failure: Failure)

    package var counts: Counts {
      switch self {
      case .closed(let counts), .failed(let counts, _): counts
      }
    }

    package func requireClosed() throws {
      if case .failed(_, let failure) = self { throw failure }
    }
  }

  private struct State {
    let handle: FileHandle
    /// Completed writes only.
    var counts = Counts(bytes: 0, entries: 0)
    /// The first write, append-after-close or close failure.
    var failure: Failure?
    var closing = false
    var outcome: Outcome?
  }

  private let state: Mutex<State>
  /// Serializes `close()` callers, so a second close waits for the first and returns its result.
  private let closer = Mutex(())
  private let writer = DispatchQueue(label: "memoshi.qualification.s2-relay-journal")
  private let closeHandle: @Sendable (FileHandle) throws -> Void
  private let writeRecord: @Sendable (FileHandle, Data) throws -> Void

  package convenience init(_ url: URL) throws {
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw DriverError.invalid("journal \(url.path)") }
    try self.init(owning: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
  }

  /// Takes ownership of a real handle for a private regular journal file.
  package init(
    owning handle: FileHandle,
    write: @escaping @Sendable (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) },
    closeHandle: @escaping @Sendable (FileHandle) throws -> Void = { try $0.close() }
  ) throws {
    var info = stat()
    guard fstat(handle.fileDescriptor, &info) == 0, info.st_uid == getuid(),
      info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0, info.st_nlink == 1
    else { throw DriverError.invalid("private relay journal required") }
    state = Mutex(State(handle: handle))
    self.closeHandle = closeHandle
    self.writeRecord = write
  }

  private static let kinds: [String: UInt8] = [
    "send": 1, "authority": 2, "authorityReply": 3, "control": 4, "controlReply": 5,
  ]

  /// Queues one record without waiting for storage.
  package func append(_ entry: RelayJournalEntry) {
    let kind = Self.kinds[entry.kind]
    var framed = Data([kind ?? 0])
    withUnsafeBytes(of: UInt32(entry.bytes.count).bigEndian) { framed.append(contentsOf: $0) }
    framed.append(entry.bytes)
    let record = framed
    let payloadBytes = entry.bytes.count
    state.withLock { state in
      guard !state.closing else {
        if case .closed(let counts)? = state.outcome {
          state.outcome = .failed(counts: counts, failure: .appendAfterClose)
        } else if state.outcome == nil, state.failure == nil {
          state.failure = .appendAfterClose
        }
        return
      }
      guard state.failure == nil else { return }
      // Enqueued under the lock: close() cannot start draining between the check and the enqueue.
      guard kind != nil else {
        // In append order, so every earlier record is still written and counted.
        writer.async { self.fail(.unknownKind) }
        return
      }
      writer.async { self.write(record, payloadBytes: payloadBytes) }
    }
  }

  private func fail(_ failure: Failure) {
    state.withLock { state in
      if state.failure == nil { state.failure = failure }
    }
  }

  private func write(_ record: Data, payloadBytes: Int) {
    guard let handle = state.withLock({ $0.failure == nil ? $0.handle : nil }) else { return }
    do {
      try writeRecord(handle, record)
      state.withLock { state in
        state.counts = Counts(
          bytes: state.counts.bytes + payloadBytes, entries: state.counts.entries + 1)
      }
    } catch {
      state.withLock { state in
        if state.failure == nil { state.failure = .write(String(reflecting: error)) }
      }
    }
  }

  /// Drains every queued write in order, then closes the handle once.
  @discardableResult
  package func close() -> Outcome {
    closer.withLock { _ in
      let started: (handle: FileHandle, outcome: Outcome?) = state.withLock { state in
        if let outcome = state.outcome { return (state.handle, outcome) }
        state.closing = true
        return (state.handle, nil)
      }
      if let outcome = started.outcome { return outcome }
      writer.sync {}
      var closeFailure: Failure?
      do { try closeHandle(started.handle) } catch {
        closeFailure = .close(String(reflecting: error))
      }
      return state.withLock { state in
        let outcome: Outcome
        if let failure = state.failure ?? closeFailure {
          outcome = .failed(counts: state.counts, failure: failure)
        } else {
          outcome = .closed(counts: state.counts)
        }
        state.outcome = outcome
        return outcome
      }
    }
  }
}

/// Lets a process hold many loopback connections (one per simulated device).
func raiseDescriptorLimit() {
  var limit = rlimit()
  guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return }
  limit.rlim_cur = min(limit.rlim_max, 10_240)
  setrlimit(RLIMIT_NOFILE, &limit)
}
