import Darwin
import Foundation
import MemoshiDevice
import MemoshiProtocol
import MemoshiStore
import Network

/// One S2 command for a device process, read as a JSON line on stdin.
package struct S2Command: Codable, Sendable {
  package var id: Int
  package var op: String
  package var qr: String?
  package var codeId: String?
  package var peer: S2Peer?
  package var port: Int?
  package var route: String?
  package var conversation: String?
  package var ttlMs: Int64?
  package var everyMs: Int64?
  package var count: Int?
  package var intervalMs: Int?
  package var intervalUs: Int?
  package var durationMs: Int?
  package var timeoutMs: Int?
  package var requestId: String?
  package var text: String?
  package var label: String?
  package var groupId: String?
  package var peers: [S2Peer]?
  package var candidates: [S2Peer]?
  package var cardId: String?
  package var expiresAt: Int64?
  package var epoch: Int64?

  package init(id: Int, op: String) {
    self.id = id
    self.op = op
  }
}

/// A paired device's public identity as the driver passes it between processes.
package struct S2Peer: Codable, Hashable, Sendable {
  package var deviceId: String
  package var signingKey: String
  package var agreementKey: String

  package init(_ peer: DevicePeer) {
    deviceId = peer.deviceID.rawValue
    signingKey = peer.signingKey.base64EncodedString()
    agreementKey = peer.agreementKey.base64EncodedString()
  }

  package func devicePeer() throws -> DevicePeer {
    guard let signing = Data(base64Encoded: signingKey),
      let agreement = Data(base64Encoded: agreementKey)
    else { throw DriverError.invalid("peer keys") }
    return DevicePeer(
      deviceID: try DeviceID(deviceId), signingKey: signing, agreementKey: agreement)
  }
}

/// `s2-device` owns explicit qualification-only file identities, a real `MemoshiStore` under a
/// synthetic directory, and a durable native-MLS `DeviceNode`. JSON control/events remain local;
/// this harness identity storage is never a production Keychain fallback.
/// stdin EOF stops it.
package enum S2DeviceProcess {
  package static func run(directory: URL, name: String, platform: String) async -> Int32 {
    let out = LineWriter.standardOutput
    do {
      let devicePlatform = DevicePlatform(rawValue: platform)
      if case .unknown = devicePlatform { throw DriverError.invalid("platform \(platform)") }
      // This explicit qualification-only identity file is never a production Keychain fallback.
      let identityURL = directory.appendingPathComponent("identity.json")
      let identity: DeviceIdentity
      if FileManager.default.fileExists(atPath: identityURL.path) {
        identity = try DeviceIdentity.read(from: identityURL)
      } else {
        identity = try DeviceIdentity.generate(name: name, platform: devicePlatform)
        try identity.write(to: identityURL)
      }
      let storeDirectory = directory.appendingPathComponent("store", isDirectory: true)
      let store = try Store(directory: storeDirectory, deviceID: identity.deviceID)
      let node = try DeviceNode(
        identity: identity, store: S2StoreAdapter(store: store),
        directory: directory.appendingPathComponent("device-state"))
      let port = try await node.listen()
      let agent = try S2DeviceAgent(
        node: node, identity: identity, directory: directory, store: store,
        storeDirectory: storeDirectory)
      let events = Task {
        for await event in node.events {
          out.write(S2Line(event: event))
          if event.kind == "removedFromGroup" || event.kind == "removedDataDeleted" {
            await agent.eraseIfRemoved(out)
          }
        }
      }
      out.write(
        S2Ready(
          event: "ready", deviceId: identity.deviceID.rawValue, port: port, pid: getpid(),
          peer: S2Peer(identity.peer), groupId: await node.group.groupID))
      // A device removed in an earlier run deletes what it still holds.
      await agent.eraseIfRemoved(out)
      for await line in LineStream.lines(from: STDIN_FILENO, closeAtEnd: false) {
        guard let command = try? JSONDecoder().decode(S2Command.self, from: Data(line.utf8)) else {
          out.write(["event": JSONValue.string("badCommand"), "line": .string(line)])
          continue
        }
        Task {
          let reply = await agent.handle(command)
          out.write(reply)
        }
      }
      await node.stopAndWait()
      await events.value
      await agent.close()
      try await store.close()
      out.emit(["event": "stopped"])
      return 0
    } catch {
      LineWriter.standardError.text("s2-device: \(error)")
      return 1
    }
  }
}

private struct S2Ready: Encodable {
  let event: String
  let deviceId: String
  let port: Int
  let pid: Int32
  let peer: S2Peer
  let groupId: String
}

/// A node event as one stdout line.
package struct S2Line: Codable, Sendable {
  package var event = "node"
  package var kind: String
  package var at: UInt64
  package var conversation: String?
  package var epoch: Int64?
  package var rseq: Int64?
  package var peer: String?
  package var route: String?
  package var detail: String?

  init(event node: NodeEvent) {
    kind = node.kind
    at = node.at
    conversation = node.conversation
    epoch = node.epoch
    rseq = node.rseq
    peer = node.peer
    route = node.route
    detail = node.detail
  }
}

private actor S2DeviceAgent {
  let node: DeviceNode
  let identity: DeviceIdentity
  private var pairingProbes: [DeviceIdentity] = []
  private var nextPairingProbe = 0
  private var probeByCode: [Data: Int] = [:]
  private var probeGroups: [Int: DeviceGroup] = [:]
  private var approvalMailbox: OfflineApprovalMailbox
  private let directory: URL
  private var discoveredEndpoints: [DeviceID: NWEndpoint] = [:]
  private let store: Store
  private let storeDirectory: URL
  private var removalAnnounced = false

  init(
    node: DeviceNode, identity: DeviceIdentity, directory: URL, store: Store, storeDirectory: URL
  ) throws {
    self.node = node
    self.identity = identity
    self.directory = directory
    self.store = store
    self.storeDirectory = storeDirectory
    approvalMailbox = try OfflineApprovalMailbox(
      identity: identity, directory: directory.appendingPathComponent("approval-state"))
  }

  /// D133: after a verified removal, deletes the approval answers and the conversation store
  /// (``s2EraseRemovedData(node:approvals:store:storeDirectory:)``) and logs it once.
  func eraseIfRemoved(_ out: LineWriter) async {
    let outcome = await s2EraseRemovedData(
      node: node, approvals: approvalMailbox, store: store, storeDirectory: storeDirectory)
    switch outcome {
    case .member: return
    case .deleted:
      guard !removalAnnounced else { return }
      removalAnnounced = true
      out.write([
        "event": JSONValue.string("hostDataDeleted"),
        "detail": .string(
          "This device was removed from your devices. Data it received from them was deleted."),
      ])
    case .incomplete:
      out.write([
        "event": JSONValue.string("hostDataDeletionIncomplete"),
        "detail": .string(
          "This device was removed from your devices. Some data it received from them is not deleted yet."
        ),
      ])
    }
  }

  func close() async {
    await approvalMailbox.close()
    for group in probeGroups.values { await group.close() }
    probeGroups.removeAll()
  }

  func handle(_ command: S2Command) async -> [String: JSONValue] {
    var reply: [String: JSONValue] = ["id": .integer(Int64(command.id)), "op": .string(command.op)]
    do {
      for (key, value) in try await perform(command) { reply[key] = value }
      reply["ok"] = .bool(true)
    } catch {
      reply["ok"] = .bool(false)
      reply["error"] = .string("\(error)")
    }
    return reply
  }

  private func conversation(_ command: S2Command) throws -> ConversationID {
    guard let raw = command.conversation else { throw DriverError.invalid("conversation") }
    return try ConversationID(raw)
  }

  private func now() -> UInt64 { DeviceClock.monotonicNanoseconds() }

  private func perform(_ command: S2Command) async throws -> [String: JSONValue] {
    switch command.op {
    case "invite":
      let invitation = try await node.invite()
      return [
        "qr": .string(invitation.text), "codeId": .string(invitation.codeID.base64EncodedString()),
        "expiresAt": .integer(invitation.expiresAt),
      ]
    case "void":
      guard let raw = command.codeId, let codeID = Data(base64Encoded: raw) else {
        throw DriverError.invalid("codeId")
      }
      node.book.void(codeID)
      return [:]
    case "pair":
      let started = now()
      let result = try await node.pair(using: try PairingInvitation(text: command.qr ?? ""))
      return [
        "peer": .string(result.peer.deviceID.rawValue), "groupEpoch": .integer(result.groupEpoch),
        "totalNs": .integer(Int64(result.timings.paired - started)),
      ]
    case "preparePairProbes":
      guard let count = command.count, (1...64).contains(count), pairingProbes.isEmpty else {
        throw DriverError.invalid("pairing probes must be prepared once before trusted enrollment")
      }
      pairingProbes = try (0..<count).map {
        try DeviceIdentity.generate(name: "Pairing probe \($0 + 1)", platform: .iphone)
      }
      for probe in pairingProbes {
        let probeDirectory = directory.appendingPathComponent("pairing-probes", isDirectory: true)
          .appendingPathComponent(probe.deviceID.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(
          at: probeDirectory, withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
        try probe.write(to: probeDirectory.appendingPathComponent("identity.json"))
      }
      return [
        "peers": try JSONValue.parse(
          JSONLines.encoder.encode(pairingProbes.map { S2Peer($0.peer) }))
      ]
    case "pairProbe":
      return try await pairProbe(try PairingInvitation(text: command.qr ?? ""))
    case "relayConnect":
      try await node.connectRelay(port: command.port ?? 0)
      return [:]
    case "recover":
      try await node.recover()
      return [:]
    case "bonjourListen":
      return ["port": .integer(Int64(try await node.listenBonjour()))]
    case "bonjourDiscover":
      let peer = try (command.peer ?? S2Peer(identity.peer)).devicePeer()
      let browser = DeviceBonjourBrowser()
      do {
        let endpoint = try await withDeadline(
          .milliseconds(command.timeoutMs ?? 15_000), "Bonjour discovery"
        ) {
          for await update in browser.updates {
            if case .services(let endpoints) = update,
              let endpoint = endpoints.first(where: {
                if case .service(let name, _, _, _) = $0 { return name == peer.deviceID.rawValue }
                return false
              })
            {
              return endpoint
            }
          }
          throw DeviceLayerError.closed
        }
        browser.close()
        discoveredEndpoints[peer.deviceID] = endpoint
        return ["discovered": .bool(true)]
      } catch {
        browser.close()
        throw error
      }
    case "bonjourLink":
      let peer = try (command.peer ?? S2Peer(identity.peer)).devicePeer()
      guard let endpoint = discoveredEndpoints[peer.deviceID] else {
        throw DriverError.invalid("peer was not discovered through Bonjour")
      }
      let started = now()
      try await node.connect(to: peer, endpoint: endpoint)
      return ["handshakeNs": .integer(Int64(now() - started))]
    case "approvalQueue":
      let params = CardsRespondParams(
        requestId: try ULID(command.requestId ?? ""),
        cardId: try CardID(command.cardId ?? ""), action: "allow_once", surface: .ui)
      try await approvalMailbox.enqueue(
        conversationID: try conversation(command), params: params,
        expiresAt: command.expiresAt ?? 0, at: DeviceClock.wallMilliseconds())
      return [:]
    case "approvalSelect":
      let pending = try await approvalMailbox.pending(at: DeviceClock.wallMilliseconds())
      let notices = await approvalMailbox.expiryNotices()
      return [
        "pending": .array(pending.map { .string($0.params.requestId.rawValue) }),
        "expired": .array(notices.map { .string($0.requestID.rawValue) }),
      ]
    case "approvalReopen":
      await approvalMailbox.close()
      approvalMailbox = try OfflineApprovalMailbox(
        identity: identity, directory: directory.appendingPathComponent("approval-state"))
      return [:]
    case "relayLink":
      let peer = try (command.peer ?? S2Peer(identity.peer)).devicePeer()
      let started = now()
      try await node.openRelayLink(to: peer)
      return ["handshakeNs": .integer(Int64(now() - started))]
    case "directLink":
      let peer = try (command.peer ?? S2Peer(identity.peer)).devicePeer()
      let started = now()
      try await node.connect(to: peer, port: command.port ?? 0)
      return ["handshakeNs": .integer(Int64(now() - started))]
    case "dropLinks":
      let peer = try DeviceID(command.peer?.deviceId ?? "")
      await node.dropLinks(to: peer, route: command.route.flatMap(LinkRoute.init(rawValue:)))
      return [:]
    case "routes":
      let peer = try DeviceID(command.peer?.deviceId ?? "")
      return ["routes": .array(await node.routes(to: peer).map { .string($0.rawValue) })]
    case "claim":
      let started = now()
      let result = try await node.claim(try conversation(command), ttl: command.ttlMs)
      return [
        "granted": .bool(result.granted), "epoch": .integer(result.epoch),
        "rttNs": .integer(Int64(now() - started)),
      ]
    case "renew":
      await node.startRenewing(try conversation(command), every: command.everyMs)
      return [:]
    case "stopRenew":
      await node.stopRenewing(try conversation(command))
      return [:]
    case "configure":
      await node.configure(
        leaseMilliseconds: command.ttlMs ?? 10_000, renewMilliseconds: command.everyMs ?? 3_000,
        answerChunks: command.count ?? 3)
      return [:]
    case "commitStream":
      return try await commitStream(command)
    case "writeLoop":
      return try await writeLoop(command)
    case "rebalance":
      let started = now()
      let epoch = try await node.rebalance(
        try conversation(command), timeout: .milliseconds(command.timeoutMs ?? 10_000))
      return [
        "epoch": .integer(epoch), "durationNs": .integer(Int64(now() - started)),
        "startedAt": .integer(Int64(started)),
      ]
    case "takeOver":
      let started = now()
      let result = try await node.takeOver(
        try conversation(command),
        deadline: started + UInt64(command.timeoutMs ?? 30_000) * 1_000_000)
      return [
        "epoch": .integer(result.epoch), "durationNs": .integer(Int64(now() - started)),
        "startedAt": .integer(Int64(started)),
      ]
    case "staleWrite":
      let refused = await node.attemptStaleWrite(
        try conversation(command), label: command.label ?? "stale")
      return ["storeRefused": .bool(refused)]
    case "forward":
      let started = now()
      let result = try await node.forward(
        try conversation(command), requestID: try ULID(command.requestId ?? ""),
        text: command.text ?? "", prefer: command.route.flatMap(LinkRoute.init(rawValue:)),
        timeout: .milliseconds(command.timeoutMs ?? 10_000))
      return [
        "rttNs": .integer(Int64(now() - started)), "startedAt": .integer(Int64(started)),
        "messageId": result.messageId.map { .string($0.rawValue) } ?? .null,
        "taskId": result.taskId.map { .string($0.rawValue) } ?? .null,
        "error": result.error.map { .string($0.message) } ?? .null,
      ]
    case "relayOffline":
      await node.relayOffline()
      return [:]
    case "relayOnline":
      let started = now()
      try await node.relayOnline()
      return ["reconnectNs": .integer(Int64(now() - started))]
    case "revoke":
      try await node.revoke(try DeviceID(command.peer?.deviceId ?? ""))
      return ["groupEpoch": .integer(await node.group.epoch)]
    // The three raw probes skip the guards this node applies to itself once it learns it was
    // revoked: the relay, the authority and the peer must each refuse without its cooperation.
    case "rawRelayHello":
      do {
        let client = try await RelayClient.connect(port: command.port ?? 0, identity: identity) {
          $0.close()
        }
        client.close()
        return ["accepted": .bool(true)]
      } catch DeviceLayerError.closed {
        // The TCP connection opened and the relay ended it instead of authenticating.
        return ["accepted": .bool(false)]
      } catch DeviceLayerError.protocolViolation {
        return ["accepted": .bool(false)]
      }
    case "rawClaim":
      let answer = try await s2RawAuthority(
        node: node,
        .leaseClaim(
          LeaseClaim(
            conversationId: try conversation(command), expectedEpoch: nil,
            expiresAt: DeviceClock.wallMilliseconds() + (command.ttlMs ?? 10_000))))
      guard let answer else { return ["answered": .bool(false)] }
      guard case .leaseClaimResult(let result) = answer else {
        throw DriverError.invalid("raw claim answer")
      }
      return ["answered": .bool(true), "granted": .bool(result.granted)]
    case "rawRenew":
      let answer = try await s2RawAuthority(
        node: node,
        .leaseRenew(
          LeaseRenew(
            conversationId: try conversation(command), epoch: command.epoch ?? 0,
            expiresAt: DeviceClock.wallMilliseconds() + (command.ttlMs ?? 10_000))))
      guard let answer else { return ["answered": .bool(false)] }
      guard case .leaseRenewResult(let result) = answer else {
        throw DriverError.invalid("raw renewal answer")
      }
      return ["answered": .bool(true), "renewed": .bool(result.renewed)]
    // The control for the revocation probe's raw claim: the same path, from a member, must be
    // granted. The relay gives the raw connection this device's session and ends it with the
    // probe, so the device reconnects before it releases the lease (`released`: the release
    // was sent; it has no answer).
    case "rawClaimAndRelease":
      let id = try conversation(command)
      let answer = try await s2RawAuthority(
        node: node,
        .leaseClaim(
          LeaseClaim(
            conversationId: id, expectedEpoch: nil,
            expiresAt: DeviceClock.wallMilliseconds() + (command.ttlMs ?? 10_000))))
      guard let answer else { return ["answered": .bool(false)] }
      guard case .leaseClaimResult(let result) = answer else {
        throw DriverError.invalid("raw claim answer")
      }
      guard result.granted else { return ["answered": .bool(true), "granted": .bool(false)] }
      try await node.relayOnline()
      _ = try await node.requestAuthority(
        .leaseRelease(LeaseRelease(conversationId: id, epoch: result.epoch, lastRseq: 0)))
      return [
        "answered": .bool(true), "granted": .bool(true), "epoch": .integer(result.epoch),
        "released": .bool(true),
      ]
    case "rawLink":
      let peer = try (command.peer ?? S2Peer(identity.peer)).devicePeer()
      return await s2RawLink(node: node, peer: peer, port: command.port ?? 0)
    case "group":
      return [
        "devices": .integer(Int64(await node.group.members.count)),
        "epoch": .integer(await node.group.epoch),
      ]
    case "lease":
      let id = try conversation(command)
      let lease = await node.lease(of: id)
      return [
        "epoch": .integer(lease.epoch),
        "runner": lease.runner.map { .string($0.rawValue) } ?? .null,
        "lastRseq": .integer(await node.lastRseq(of: id)),
      ]
    case "leaseBench":
      return try await leaseBench(count: command.count ?? 100, ttl: command.ttlMs ?? 10_000)
    default:
      throw DriverError.invalid("unknown op \(command.op)")
    }
  }

  /// A pre-enrolled throwaway identity pairs over a fresh TCP connection. Retries of one code
  /// retain the same private identity, including a wrong-key attempt followed by its right key.
  private func pairProbe(_ invitation: PairingInvitation) async throws -> [String: JSONValue] {
    guard let hint = invitation.hints.first(where: { $0.hasPrefix("tcp:") }),
      let port = Int(hint.split(separator: ":").last ?? "")
    else { throw DriverError.invalid("pairing hint") }
    let index: Int
    if let assigned = probeByCode[invitation.codeID] {
      index = assigned
    } else {
      guard nextPairingProbe < pairingProbes.count else {
        throw DriverError.invalid("pairing probe identity was not pre-enrolled")
      }
      index = nextPairingProbe
      nextPairingProbe += 1
      probeByCode[invitation.codeID] = index
    }
    let probe = pairingProbes[index]
    let group: DeviceGroup
    if let existing = probeGroups[index] {
      group = existing
    } else {
      group = try DeviceGroup(
        identity: probe,
        directory: directory.appendingPathComponent("pairing-probes")
          .appendingPathComponent(probe.deviceID.rawValue).appendingPathComponent("membership"))
      probeGroups[index] = group
    }
    let started = now()
    let channel = try await TCPFrameChannel.connect(host: "127.0.0.1", port: port)
    let connected = now()
    do {
      let result = try await PairingExchange.join(
        invitation: invitation, identity: probe, group: group, channel: channel)
      await result.link.close()
      return [
        "paired": .bool(true), "connectNs": .integer(Int64(connected - started)),
        "handshakeNs": .integer(Int64(result.timings.handshakeDone - connected)),
        "totalNs": .integer(Int64(result.timings.paired - started)),
      ]
    } catch {
      return ["paired": .bool(false), "refusal": .string("\(error)")]
    }
  }

  /// Commits `count` changes and reports how each ended (``S2CommitTally``).
  private func commitStream(_ command: S2Command) async throws -> [String: JSONValue] {
    let id = try conversation(command)
    var tally = S2CommitTally()
    let label = command.label ?? "stream"
    for index in 0..<(command.count ?? 1) {
      do {
        try await node.commit(id, label: "\(label) \(index)")
        tally.accept()
      } catch {
        tally.record(error, removed: await node.membership == .removed)
      }
      if let interval = command.intervalMs, interval > 0 {
        try await Task.sleep(for: .milliseconds(interval))
      }
    }
    return tally.reply
  }

  /// Commits for `durationMs` and reports how each commit ended (``S2CommitTally``).
  private func writeLoop(_ command: S2Command) async throws -> [String: JSONValue] {
    let id = try conversation(command)
    let end = now() + UInt64(command.durationMs ?? 1_000) * 1_000_000
    var tally = S2CommitTally()
    var index = 0
    while now() < end {
      index += 1
      do {
        try await node.commit(id, label: "\(command.label ?? "write") \(index)")
        tally.accept()
      } catch {
        tally.record(error, removed: await node.membership == .removed)
      }
      try await Task.sleep(for: .microseconds(command.intervalUs ?? 500))
    }
    return tally.reply
  }

  /// Claim, renew, release and re-claim on fresh conversations, straight to the authority.
  private func leaseBench(count: Int, ttl: Int64) async throws -> [String: JSONValue] {
    var claims: [JSONValue] = []
    var renewals: [JSONValue] = []
    var reclaims: [JSONValue] = []
    for _ in 0..<count {
      let id = try ConversationID("cht_" + DeviceULID.make())
      var started = now()
      guard
        case .leaseClaimResult(let claimed)? = try await node.requestAuthority(
          .leaseClaim(
            LeaseClaim(
              conversationId: id, expectedEpoch: nil,
              expiresAt: DeviceClock.wallMilliseconds() + ttl))), claimed.granted
      else { throw DriverError.invalid("bench claim refused") }
      claims.append(.integer(Int64(now() - started)))
      started = now()
      guard
        case .leaseRenewResult(let renewed)? = try await node.requestAuthority(
          .leaseRenew(
            LeaseRenew(
              conversationId: id, epoch: claimed.epoch,
              expiresAt: DeviceClock.wallMilliseconds() + ttl))), renewed.renewed
      else { throw DriverError.invalid("bench renew refused") }
      renewals.append(.integer(Int64(now() - started)))
      _ = try await node.requestAuthority(
        .leaseRelease(LeaseRelease(conversationId: id, epoch: claimed.epoch, lastRseq: 0)))
      started = now()
      guard
        case .leaseClaimResult(let again)? = try await node.requestAuthority(
          .leaseClaim(
            LeaseClaim(
              conversationId: id, expectedEpoch: claimed.epoch,
              expiresAt: DeviceClock.wallMilliseconds() + ttl))), again.granted,
        again.epoch == claimed.epoch + 1
      else { throw DriverError.invalid("bench re-claim refused") }
      reclaims.append(.integer(Int64(now() - started)))
    }
    return ["claimNs": .array(claims), "renewNs": .array(renewals), "reclaimNs": .array(reclaims)]
  }
}

/// How a run of this device's own commits ended, as `commitStream` and `writeLoop` report it:
/// accepted; refused by the fence or by this device's membership (``S2CommitRefusal``,
/// `refused` and `refusedBy`); or failed for any other reason, such as a closed store or a lost
/// relay, which refused nothing (`failed`, with the first ``describedFailures`` errors in
/// `errors`).
package struct S2CommitTally: Sendable {
  /// How many failures `errors` describes; `failed` counts every one.
  package static let describedFailures = 10

  package private(set) var accepted = 0
  package private(set) var refusedBy = Dictionary(
    uniqueKeysWithValues: S2CommitRefusal.allCases.map { ($0, 0) })
  package private(set) var failed = 0
  package private(set) var errors: [String] = []

  package init() {}

  package mutating func accept() { accepted += 1 }

  /// Records one commit's error; `removed` as for ``S2CommitRefusal/init(_:removed:)``.
  package mutating func record(_ error: any Error, removed: Bool) {
    if let refusal = S2CommitRefusal(error, removed: removed) {
      refusedBy[refusal, default: 0] += 1
      return
    }
    failed += 1
    if errors.count < Self.describedFailures { errors.append("\(error)") }
  }

  package var reply: [String: JSONValue] {
    var kinds: [String: JSONValue] = [:]
    for (refusal, count) in refusedBy { kinds[refusal.rawValue] = .integer(Int64(count)) }
    return [
      "accepted": .integer(Int64(accepted)),
      "refused": .integer(Int64(refusedBy.values.reduce(0, +))), "refusedBy": .object(kinds),
      "failed": .integer(Int64(failed)), "errors": .array(errors.map(JSONValue.string)),
    ]
  }
}

/// What refused one of this device's own commits: its fence, or its membership (D133). Any
/// other failure, such as a closed store or a lost relay, refused nothing.
package enum S2CommitRefusal: String, CaseIterable, Sendable {
  /// The store's fence or the authority's lease record: the epoch is not this device's.
  case fence
  /// This device is not, or no longer, a member of its group.
  case membership

  /// `removed`: whether the node's own group state showed this device removed when the commit
  /// failed.
  package init?(_ error: any Error, removed: Bool) {
    if error is FenceError {
      self = .fence
      return
    }
    switch error as? DeviceLayerError {
    case .unknownPeer?:
      self = .membership
    // The node's guard once it knows it was removed. It gives the same reason while stopping,
    // after a persistence failure or awaiting recovery, so only a removed device's counts.
    case .io("device authority recovery required")? where removed:
      self = .membership
    default:
      return nil
    }
  }
}

/// The revocation probe's raw link: this device presents its own key to `peer`'s direct
/// listener without its own membership guard (a revoked device knows it was removed, D133), so
/// only the peer's answer counts. `linked` is true if the peer answered the handshake.
package func s2RawLink(node: DeviceNode, peer: DevicePeer, port: Int) async -> [String: JSONValue] {
  do {
    return ["linked": .bool(try await node.attemptUnguardedLink(to: peer, port: port))]
  } catch {
    return ["linked": .bool(false), "refusal": .string("\(error)")]
  }
}

/// The revocation probe's raw authority request, sent over a fresh relay connection past the
/// device's own guards and relay client (a revoked device knows it was removed, D133): nil when
/// the relay ended it unanswered, so only the relay or the authority can refuse it.
package func s2RawAuthority(node: DeviceNode, _ body: DeviceMessageBody) async throws
  -> DeviceMessageBody?
{
  try await node.attemptUnguardedAuthority(body)
}

/// What the S2 host found and deleted after a check of its device's removal (D133, host side).
package enum S2RemovedData: String, Sendable {
  /// The device is in its group, also when a relay only refused it: nothing was deleted.
  case member
  /// The device was removed and everything it received through the group is deleted.
  case deleted
  /// The device was removed, but something is not deleted yet; the next check tries again.
  case incomplete
}

/// D133, host side of S2: once the node's own group state shows this device removed (only a
/// verified removal commit does that, never a relay's refusal), deletes what the S2 host holds
/// from the group: its offline approval answers (``OfflineApprovalMailbox/erase()``) and its
/// conversation store (closed, its directory deleted, the parent directory synchronized). The
/// node deletes its own state; `.deleted` means that is done too. Every step runs even when an
/// earlier one failed; a repeated check finds nothing left.
package func s2EraseRemovedData(
  node: DeviceNode, approvals: OfflineApprovalMailbox, store: Store, storeDirectory: URL
) async -> S2RemovedData {
  guard await node.membership == .removed else { return .member }
  var complete = await node.deletedRemovedData
  do { try await approvals.erase() } catch { complete = false }
  do {
    try await store.close()
    if FileManager.default.fileExists(atPath: storeDirectory.path) {
      try FileManager.default.removeItem(at: storeDirectory)
    }
    let parent = open(storeDirectory.deletingLastPathComponent().path, O_RDONLY | O_CLOEXEC)
    guard parent >= 0 else { throw DriverError.invalid("store parent directory") }
    defer { close(parent) }
    guard fsync(parent) == 0 else { throw DriverError.invalid("store parent directory sync") }
  } catch {
    complete = false
  }
  return complete ? .deleted : .incomplete
}
