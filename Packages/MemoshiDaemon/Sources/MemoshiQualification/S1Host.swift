import Foundation
import MemoshiProtocol
import MemoshiRuntime
import MemoshiStore
import Synchronization

/// A driver-owned runtime process, NOT memoshid and NOT a replacement transport. Genuine helper
/// signing is required by DaemonServer; this fixture does not import or bypass that guard.
package enum S1Host {
  package static func run() async -> Int32 {
    let launched = ContinuousClock.now
    let output = LineWriter.standardOutput
    var lines = LineStream.lines(from: STDIN_FILENO, closeAtEnd: false).makeAsyncIterator()
    guard let line = await lines.next(),
      let configuration = try? JSONDecoder().decode(S1HostConfiguration.self, from: Data(line.utf8))
    else {
      output.emit(["s1": "fatal", "error": "invalid host configuration"])
      return 64
    }
    let session: S1HostSession
    do {
      session = try await S1HostSession.open(configuration, output: output)
    } catch {
      output.emit(["s1": "fatal", "error": "runtime host startup failed"])
      return 1
    }
    do {
      let reading = try await session.reading([])
      output.write(
        S1ControlReply(
          id: "ready", ok: true, reading: reading,
          durationNs: S1Clock.nanoseconds(since: launched)))
    } catch {
      try? await session.close()
      output.emit(["s1": "fatal", "error": "runtime host initial inspection failed"])
      return 1
    }
    var shutdownID: String?
    // Real simultaneous admissions reach the actor; a finite cap bounds process-local requests.
    await withTaskGroup(of: Void.self) { group in
      var pending = 0
      while let line = await lines.next() {
        if let control = try? JSONDecoder().decode(S1Control.self, from: Data(line.utf8)) {
          if control.s1 == "shutdown" {
            shutdownID = control.id
            break
          }
          output.write(await session.control(control))
          continue
        }
        if pending == 32 {
          _ = await group.next()
          pending -= 1
        }
        group.addTask {
          do {
            let reply = try await session.rpc(Data(line.utf8))
            output.text(String(decoding: reply.frame, as: UTF8.self))
            if let measurement = reply.measurement { output.write(measurement) }
          } catch {
            session.failObservation()
            output.emit(["s1": "fatal", "error": "S1 response encoding failed"])
          }
        }
        pending += 1
      }
      await group.waitForAll()
    }
    do {
      try await session.close()
      if let shutdownID { output.write(S1ControlReply(id: shutdownID, ok: true)) }
      return 0
    } catch {
      if let shutdownID {
        output.write(S1ControlReply(id: shutdownID, ok: false, error: "runtime host close failed"))
      }
      return 1
    }
  }
}

/// Real Store/RuntimeAdapter composition with no tools, Code Mode, MCP, environment or subagents.
/// The single credential seam releases only the owned loopback provider's synthetic bearer.
package final class S1HostSession: Sendable {
  private let store: Store
  private let runtime: RuntimeAdapter
  private let configuration: S1HostConfiguration
  private let observation: Task<Void, Never>
  private let observationFailed: S1ObservationFailure

  private init(
    store: Store, runtime: RuntimeAdapter, configuration: S1HostConfiguration,
    observation: Task<Void, Never>, observationFailed: S1ObservationFailure
  ) {
    self.store = store
    self.runtime = runtime
    self.configuration = configuration
    self.observation = observation
    self.observationFailed = observationFailed
  }

  package static func open(_ configuration: S1HostConfiguration, output: LineWriter) async throws
    -> S1HostSession
  {
    guard let endpoint = URLComponents(string: configuration.providerBaseURL),
      endpoint.scheme == "http", endpoint.host == "127.0.0.1",
      let port = endpoint.port, (1...65535).contains(port), endpoint.path == "/v1",
      endpoint.user == nil, endpoint.password == nil, endpoint.query == nil,
      endpoint.fragment == nil, !configuration.providerBearer.isEmpty,
      ModelCredentialReference(rawValue: configuration.providerSecretRef)?.kind == .apiKey
    else { throw DriverError.invalid("S1 provider must be its owned loopback endpoint") }
    let store = try Store(
      directory: URL(fileURLWithPath: configuration.directory, isDirectory: true))
    do {
      // A restart may load only the same local configuration, never an upstream/provider fallback.
      let providers = try await store.modelProviders().value
      guard
        providers.allSatisfy({
          $0.id == "local" && $0.baseUrl == configuration.providerBaseURL
            && $0.secretRef == configuration.providerSecretRef
        })
      else { throw DriverError.invalid("unexpected provider in S1 root") }
      let failed = S1ObservationFailure()
      let events = try store.subscribeEvents(capacity: 4096)
      let observation = Task {
        do {
          for try await event in events { output.write(EventNotification(event: event)) }
        } catch {
          failed.mark()
          output.emit(["s1": "fatal", "error": "durable event observation failed"])
        }
      }
      let runtime = RuntimeAdapter(
        store: store,
        resolveCredential: { params in
          guard params.secretRef == configuration.providerSecretRef, params.purpose == "model:local"
          else { throw DriverError.invalid("S1 credential release refused") }
          return HostKeychainGetResult(value: configuration.providerBearer, ttlMs: 60_000)
        },
        publishLive: { event in
          var event = event
          event.after = try await store.replayBounds().head
          output.write(EventNotification(event: event))
        })
      let session = S1HostSession(
        store: store, runtime: runtime, configuration: configuration,
        observation: observation, observationFailed: failed)
      do {
        try await runtime.start()
        try await runtime.resume()
        return session
      } catch {
        try? await session.close()
        throw error
      }
    } catch {
      try? await store.close()
      throw error
    }
  }

  package func close() async throws {
    var failure: (any Error)?
    do { try await runtime.close() } catch { failure = error }
    do { try await store.close() } catch { failure = failure ?? error }
    await observation.value
    if observationFailed.value {
      failure = failure ?? DriverError.invalid("S1 event observation failed")
    }
    if let failure { throw failure }
  }

  package func failObservation() { observationFailed.mark() }

  /// Decodes real JSONRPCRequest types, then calls the same adapter methods as RPCSession.
  /// Its narrow dispatch table is a qualification carrier, not production RPCSession coverage.
  package func rpc(_ bytes: Data) async throws -> S1RPCReply {
    var id: JSONRPCID?
    var method: String?
    let before = await runtime.status()
    let start = ContinuousClock.now
    do {
      guard case .request(let rawID, let name) = try JSONRPCCodec().inspect(bytes),
        rawID.hasPrefix("c:")
      else { throw Self.error(.invalidRequest, "Invalid request.") }
      id = try JSONRPCID(rawID)
      method = name
      let result: S1RouteValue
      switch name {
      case BotsList.name:
        result = try await route(BotsList.self, bytes) { try await self.runtime.listBots($0) }
      case BotsCreate.name:
        result = try await route(BotsCreate.self, bytes) { try await self.runtime.createBot($0) }
      case SessionsCreate.name:
        result = try await route(SessionsCreate.self, bytes) {
          try await self.runtime.createSession($0)
        }
      case SessionsDelete.name:
        result = try await route(SessionsDelete.self, bytes) {
          try await self.runtime.deleteSession($0)
        }
      case TrashList.name:
        result = try await route(TrashList.self, bytes) { _ in try await self.runtime.listTrash() }
      case TrashRestore.name:
        result = try await route(TrashRestore.self, bytes) {
          try await self.runtime.restoreSession($0)
        }
      case TrashEmpty.name:
        result = try await route(TrashEmpty.self, bytes) { try await self.runtime.emptyTrash($0) }
      case ChatsList.name:
        result = try await route(ChatsList.self, bytes) { _ in try await self.runtime.listChats() }
      case ChatsHistory.name:
        result = try await route(ChatsHistory.self, bytes) { try await self.runtime.history($0) }
      case ChatsSend.name:
        result = try await route(ChatsSend.self, bytes) { try await self.runtime.send($0) }
      case ModelsProvidersList.name:
        result = try await route(ModelsProvidersList.self, bytes) { _ in
          try await self.runtime.providers()
        }
      case ModelsProvidersConfigure.name:
        result = try await route(ModelsProvidersConfigure.self, bytes) { params in
          guard params.providerId == "local", params.baseUrl == self.configuration.providerBaseURL,
            params.secretRef == self.configuration.providerSecretRef
          else { throw Self.error(.forbidden, "Only the owned S1 provider may be configured.") }
          return try await self.runtime.configure(params)
        }
      case ModelsList.name:
        result = try await route(ModelsList.self, bytes) { _ in try await self.runtime.modelsList()
        }
      default:
        throw Self.error(.methodNotFound, "Method is outside the S1 harness.")
      }
      let after = await runtime.status()
      return S1RPCReply(
        frame: result.frame,
        measurement: S1CallMeasurement(
          id: rawID, method: name, durationNs: result.durationNs,
          openThreadsBefore: before.openThreads, openThreadsAfter: after.openThreads,
          liveRunsAfter: after.liveRuns))
    } catch {
      let refusal: RPCError
      if error is DecodingError || error is IdentifierError {
        refusal = Self.error(
          .invalidParams(
            InvalidParamsDetails(issues: [
              ParamIssue(path: "/params", message: "Invalid parameters.")
            ])),
          "Parameters do not match the method.")
      } else {
        refusal =
          RuntimeRPCError.map(error)
          ?? Self.error(
            .internalError(InternalErrorDetails(incidentId: "s1-host")),
            "S1 runtime operation failed.")
      }
      let frame = try ProtocolCoding.makeEncoder().encode(
        JSONRPCErrorResponse(id: id, error: refusal))
      return S1RPCReply(
        frame: frame,
        measurement: id.map {
          S1CallMeasurement(
            id: $0.rawValue, method: method ?? "unreadable",
            durationNs: S1Clock.nanoseconds(since: start),
            openThreadsBefore: before.openThreads, openThreadsAfter: before.openThreads,
            liveRunsAfter: before.liveRuns)
        })
    }
  }

  private func route<Method: RPCMethod>(
    _ method: Method.Type, _ bytes: Data,
    _ operation: @Sendable (Method.Params) async throws -> Method.Result
  ) async throws -> S1RouteValue {
    let request = try ProtocolCoding.makeDecoder(strict: true).decode(
      JSONRPCRequest<Method>.self, from: bytes)
    let start = ContinuousClock.now
    let result = try await operation(request.params)
    let duration = S1Clock.nanoseconds(since: start)
    return S1RouteValue(
      frame: try ProtocolCoding.makeEncoder().encode(
        JSONRPCSuccessResponse<Method>(id: request.id, result: result)),
      durationNs: duration)
  }

  package func reading(_ requests: [ULID]) async throws -> S1ProcessReading {
    let status = await runtime.status()
    let footprint = S1Footprint.read()
    var turns: [TurnState] = []
    for request in requests {
      guard let turn = try await store.chatTurn(request) else {
        throw DriverError.invalid("missing S1 original turn")
      }
      turns.append(
        TurnState(
          requestId: turn.requestId.rawValue, messageId: turn.messageId.rawValue,
          assistantMessageId: turn.assistantMessageId.rawValue, taskId: turn.taskId.rawValue,
          status: turn.status.rawValue, writtenSeq: turn.writtenSeq,
          recoveryHeld: turn.recoveryStep != nil, errorCode: turn.error?.code))
    }
    return S1ProcessReading(
      pid: getpid(), openThreads: status.openThreads, liveRuns: status.liveRuns,
      awaitingModels: status.awaitingModels, footprintBytes: footprint.footprint,
      residentBytes: footprint.resident, maximumResidentBytes: footprint.peak,
      footprintError: footprint.error, turns: turns)
  }

  package func control(_ command: S1Control) async -> S1ControlReply {
    do {
      switch command.s1 {
      case "probe":
        return S1ControlReply(
          id: command.id, ok: true, reading: try await reading(command.requestIds))
      case "events":
        let page = try await store.replay(
          after: command.after, through: command.through, limit: 256)
        return S1ControlReply(
          id: command.id, ok: true,
          page: S1EventPage(
            head: page.bounds.head, through: page.through, nextAfter: page.nextAfter,
            hasMore: page.hasMore, events: page.events))
      case "commit":
        guard let days = command.retentionDays, days == 30 || days == 31 else {
          throw DriverError.invalid("S1 retention sample must select 30 or 31 days")
        }
        let before = await runtime.status()
        guard before.openThreads == 10, before.liveRuns == 8 else {
          throw DriverError.invalid("S1 commit sample requires 10 open / 8 streaming")
        }
        let timestamp = Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        let start = ContinuousClock.now
        let committed = try await store.setEventRetentionDays(days, at: timestamp)
        let elapsed = S1Clock.nanoseconds(since: start)
        guard committed.count == 1 else {
          throw DriverError.invalid("S1 commit sample was a no-op")
        }
        let after = await runtime.status()
        guard after.openThreads == 10, after.liveRuns == 8 else {
          throw DriverError.invalid("S1 stream concurrency changed during commit sample")
        }
        return S1ControlReply(
          id: command.id, ok: true, durationNs: elapsed, committedEvents: committed.count)
      default:
        throw DriverError.invalid("unknown S1 control")
      }
    } catch {
      return S1ControlReply(
        id: command.id, ok: false, error: "S1 control invariant or operation failed")
    }
  }

  private static func error(_ details: RPCErrorDetails, _ message: String) -> RPCError {
    RPCError(message: message, data: RPCErrorData(details: details))
  }
}

private struct S1RouteValue: Sendable {
  let frame: Data
  let durationNs: Int64
}

private final class S1ObservationFailure: Sendable {
  private let failed = Mutex(false)
  var value: Bool { failed.withLock { $0 } }
  func mark() { failed.withLock { $0 = true } }
}
