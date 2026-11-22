import CryptoKit
import Foundation
import MemoshiProtocol
import MemoshiRuntime
import MemoshiStore

/// The qualification host child process. It composes the real `MemoshiStore` and
/// `RuntimeAdapter` (and through it PiDurable at the pinned candidate) exactly as the
/// development runtime does, plus one trusted ledger-posting test tool. The driver controls it
/// over stdin/stdout JSON lines and kills it with SIGKILL; stdin EOF closes it normally.
package enum QualificationHost {
  /// The model-callable name of the qualification tool.
  package static let toolName = "qualification_effect"

  /// Runs one host life and returns its exit status.
  package static func run() async -> Int32 {
    let launched = ContinuousClock.now
    let output = LineWriter.standardOutput
    var lines = LineStream.lines(from: STDIN_FILENO, closeAtEnd: false).makeAsyncIterator()
    guard let first = await lines.next(),
      let configuration = try? JSONDecoder().decode(HostConfiguration.self, from: Data(first.utf8))
    else {
      output.write(HostMessage(event: "fatal", error: "configuration"))
      return 64
    }
    let session: HostSession
    do {
      session = try await HostSession.open(configuration, output: output)
    } catch {
      output.write(HostMessage(event: "fatal", error: describe(error)))
      return 1
    }
    output.write(
      HostMessage(
        event: "ready",
        fields: [
          "chatId": session.chatID.rawValue, "life": String(configuration.life),
          "pid": String(getpid()), "elapsedMs": String(milliseconds(since: launched)),
        ]))
    var shutdown: Int?
    // EOF means the owner is gone or asked for a normal stop.
    while let line = await lines.next() {
      guard let command = try? JSONDecoder().decode(HostCommand.self, from: Data(line.utf8))
      else {
        output.write(HostMessage(event: "rejected_command"))
        continue
      }
      if command.op == .shutdown {
        shutdown = command.id
        break
      }
      output.write(await session.handle(command))
    }
    do {
      try await session.close()
      if let shutdown { output.write(HostMessage(id: shutdown, ok: true)) }
      return 0
    } catch {
      if let shutdown { output.write(HostMessage(id: shutdown, ok: false, error: describe(error))) }
      return 1
    }
  }

  static func milliseconds(since start: ContinuousClock.Instant) -> Int64 {
    let elapsed = ContinuousClock.now - start
    return elapsed.components.seconds * 1000 + elapsed.components.attoseconds
      / 1_000_000_000_000_000
  }

  /// Runtime, store and transport errors are presentation-safe enums or loopback URLs.
  static func describe(_ error: any Error) -> String { String(describing: error) }
}

/// Holds the tool at a configured gate until the host is killed or `release` arrives.
actor ToolGateController {
  private let pause: ToolGate?
  private let output: LineWriter
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private var released = false

  init(pause: ToolGate?, output: LineWriter) {
    self.pause = pause
    self.output = output
  }

  func pass(_ gate: ToolGate) async {
    guard gate == pause, !released else { return }
    output.write(HostMessage(event: "paused", fields: ["gate": gate.rawValue]))
    await withCheckedContinuation { waiting.append($0) }
  }

  func release() {
    released = true
    for continuation in waiting { continuation.resume() }
    waiting.removeAll()
  }
}

/// Host failures that are not runtime errors.
enum HostError: Error, Equatable {
  case credentialRefused
  case noChat
  case invalidCommand
  case ledgerConflict
}

/// One opened host: store, runtime, store-event observer and tool gate.
final class HostSession: Sendable {
  let store: Store
  let runtime: RuntimeAdapter
  let chatID: ConversationID
  private let gate: ToolGateController
  private let observation: Task<Void, Never>

  private init(
    store: Store, runtime: RuntimeAdapter, chatID: ConversationID, gate: ToolGateController,
    observation: Task<Void, Never>
  ) {
    self.store = store
    self.runtime = runtime
    self.chatID = chatID
    self.gate = gate
    self.observation = observation
  }

  static func open(_ configuration: HostConfiguration, output: LineWriter) async throws
    -> HostSession
  {
    let gate = ToolGateController(pause: configuration.pause, output: output)
    let store = try Store(
      directory: URL(fileURLWithPath: configuration.dataDirectory, isDirectory: true))
    let observation: Task<Void, Never>
    do {
      observation = try observe(store, output: output)
    } catch {
      try? await store.close()
      throw error
    }
    let reference = configuration.providerSecretRef
    let bearer = configuration.providerBearer
    // Subagent and Code Mode runs compose the real task-owned extensions; every other run keeps
    // the production composition. The model may only delegate a task body. The child gets no
    // tools, so it can never run the parent's effect, and no background form is offered.
    let extensions = RuntimeExtensionComposition(
      codeMode: configuration.codeMode ? RuntimeCodeModeConfiguration() : nil,
      subagents: configuration.subagents
        ? RuntimeSubagentConfiguration(
          foreground: true, persistentBackground: false, childTools: [])
        : nil)
    let runtime = RuntimeAdapter(
      store: store,
      resolveCredential: { params in
        // The only release this host performs: its configured local-provider reference.
        guard params.secretRef == reference, params.purpose == "model:local" else {
          throw HostError.credentialRefused
        }
        return HostKeychainGetResult(value: bearer, ttlMs: 60_000)
      },
      tools: [effectTool(configuration, gate: gate, output: output)],
      extensions: extensions,
      publishLive: { envelope in
        guard case .messageDelta(let delta) = envelope.event else { return }
        output.write(
          HostMessage(
            event: "delta",
            fields: [
              "messageId": delta.messageId.rawValue, "offset": String(delta.offsetUtf16),
              "length": String(delta.text.utf16.count),
            ]))
      })
    do {
      try await runtime.start()
      if configuration.configureProvider {
        _ = try await runtime.configure(
          ModelsProvidersConfigureParams(
            requestId: try IDGenerator.shared.next(), providerId: "local",
            baseUrl: configuration.providerBaseURL, secretRef: configuration.providerSecretRef))
      }
      switch configuration.startup {
      case .discoverThenResume:
        _ = try await runtime.modelsList()
        try await runtime.resume()
      case .daemon:
        try await runtime.resume()
        _ = try await runtime.modelsList()
      }
      guard let chat = try await runtime.listChats().items.first else { throw HostError.noChat }
      return HostSession(
        store: store, runtime: runtime, chatID: chat.id, gate: gate, observation: observation)
    } catch {
      try? await runtime.close()
      try? await store.close()
      await observation.value
      throw error
    }
  }

  /// Normal close: the runtime quiesces and closes Pi storage, then the store closes.
  func close() async throws {
    await gate.release()
    var failure: (any Error)?
    do { try await runtime.close() } catch { failure = error }
    do { try await store.close() } catch { failure = failure ?? error }
    await observation.value
    if let failure { throw failure }
  }

  func handle(_ command: HostCommand) async -> HostMessage {
    do {
      switch command.op {
      case .send:
        guard let params = command.send else { throw HostError.invalidCommand }
        return HostMessage(id: command.id, ok: true, receipt: try await runtime.send(params))
      case .respond:
        guard let params = command.respond else { throw HostError.invalidCommand }
        let result = try await runtime.respondToCard(params)
        return HostMessage(
          id: command.id, ok: true,
          fields: [
            "card": result.card.status.rawValue, "writtenSeq": String(result.writtenSeq),
          ])
      case .inspect:
        return HostMessage(id: command.id, ok: true, snapshot: try await inspect(command.requestId))
      case .release:
        await gate.release()
        return HostMessage(id: command.id, ok: true)
      case .shutdown:
        throw HostError.invalidCommand
      }
    } catch {
      return HostMessage(id: command.id, ok: false, error: QualificationHost.describe(error))
    }
  }

  private func inspect(_ requestID: ULID?) async throws -> HostSnapshot {
    let conversation = chatID
    var turn: TurnState?
    var task: TaskState?
    var children: [ChildTaskState] = []
    if let requestID, let stored = try await store.chatTurn(requestID) {
      turn = TurnState(
        requestId: stored.requestId.rawValue, messageId: stored.messageId.rawValue,
        assistantMessageId: stored.assistantMessageId.rawValue, taskId: stored.taskId.rawValue,
        status: stored.status.rawValue, writtenSeq: stored.writtenSeq,
        recoveryHeld: stored.recoveryStep != nil, errorCode: stored.error?.code)
      if let details = try await store.taskDetails(stored.taskId) {
        task = TaskState(
          status: details.task.status.rawValue, waitingOn: details.task.waitingOn?.rawValue,
          resumeMode: details.task.resumeMode.rawValue)
      }
      let bindings = try await store.runtimeSubagents(conversation)
      children = try await store.taskGraph(conversation).value
        .filter { $0.parentTaskId == stored.taskId }
        .map { child in
          ChildTaskState(
            id: child.id.rawValue, status: child.status.rawValue,
            toolNames: bindings.first { $0.taskId == child.id }?.toolNames)
        }
    }
    let approvals = try await store.approvals(conversationID: conversation).value.map {
      ApprovalState(
        id: $0.id.rawValue, status: $0.status.rawValue, taskId: $0.taskId.rawValue,
        toolCallId: $0.toolCallId, decidedBy: $0.decidedBy?.kind.rawValue)
    }
    var cards: [CardState] = []
    var after: CardID?
    repeat {
      let page = try await store.cardsPage(
        conversationID: conversation, after: after, limit: try PageLimit(200))
      cards += page.items.map {
        CardState(id: $0.id.rawValue, status: $0.status.rawValue, subjectId: $0.subject?.id)
      }
      after = try page.nextCursor.map { try CardID($0) }
    } while after != nil
    let history = try await runtime.history(ChatsHistoryParams(chatId: chatID, limit: 200))
    let messages = history.items.map { message in
      MessageState(
        id: message.id.rawValue, role: message.role.rawValue,
        text: message.content.map { part -> String in
          if case .text(let text) = part { return text.text }
          return ""
        }.joined(),
        requestId: message.requestId?.rawValue, stopReason: message.stopReason?.rawValue)
    }
    var completions: [ToolCompletionState] = []
    var delegations: [ToolCompletionState] = []
    var codeModes: [ToolCompletionState] = []
    var cursor: Int64 = 0
    while true {
      let page = try await store.auditEvents(after: cursor, limit: try PageLimit(200)).value
      for envelope in page {
        guard case .toolCompleted(let value) = envelope.event else { continue }
        let completion = ToolCompletionState(
          toolCallId: value.toolCallId, ok: value.ok, errorCode: value.errorCode)
        if value.tool == QualificationHost.toolName {
          completions.append(completion)
        } else if value.tool == QualificationProvider.subagentToolName {
          delegations.append(completion)
        } else if value.tool == QualificationProvider.codeModeToolName {
          codeModes.append(completion)
        }
      }
      guard page.count == 200, let last = page.last?.seq else { break }
      cursor = last
    }
    return HostSnapshot(
      chatId: chatID.rawValue, turn: turn, task: task, approvals: approvals, cards: cards,
      messages: messages, live: history.live != nil, recoveryHold: history.recovery != nil,
      queued: history.queued?.count ?? 0, toolCompletions: completions,
      subagentCompletions: delegations, codeModeCompletions: codeModes, childTasks: children,
      liveRuns: await runtime.status().liveRuns)
  }

  /// The trusted test tool: a T3 reach-out (`net.fetch`) that asks in Ask first, declared
  /// replay-safe because it sends an idempotency key the ledger deduplicates (04 §4.11).
  private static func effectTool(
    _ configuration: HostConfiguration, gate: ToolGateController, output: LineWriter
  ) -> RuntimeToolDefinition {
    let ledger = EffectLedgerClient(port: configuration.ledgerPort)
    let run = configuration.run
    let life = configuration.life
    let tokenFile = configuration.ledgerTokenFile
    return RuntimeToolDefinition(
      name: QualificationHost.toolName,
      description: "Record exactly one qualification effect in the external effect ledger.",
      parameters: [
        "type": "object",
        "properties": ["step": ["type": "string"], "note": ["type": "string"]],
        "required": ["step"], "additionalProperties": false,
      ],
      operation: .networkFetch, replaySafe: true,
      authorize: { _ in
        // The run's ledger credential source must still exist at authorization and dispatch.
        FileManager.default.isReadableFile(atPath: tokenFile)
      },
      execute: { arguments, invocation in
        let taskKey = invocation.effectKey
        let callID = invocation.callID
        guard case .object(let values) = arguments, case .string(let step)? = values["step"],
          !step.isEmpty
        else { throw RuntimeToolError.invalidArguments }
        let note: String
        if case .string(let value)? = values["note"] { note = value } else { note = "" }
        let key = "mq1:\(run):\(taskKey):\(callID)"
        return try await invocation.runCancellable {
          output.write(
            HostMessage(
              event: "tool_executing", fields: ["key": key, "callId": callID, "taskKey": taskKey]))
          await gate.pass(.toolExecuting)
          try Task.checkCancellation()
          let token = try String(contentsOfFile: tokenFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
          let payload = Data(SHA256.hash(data: Data((step + "\n" + note).utf8))).hexadecimal
          let receipt = try await ledger.post(
            EffectAttempt(
              key: key, run: run, step: step, payloadHash: payload, callID: callID,
              taskKey: taskKey, life: life, pid: getpid()),
            bearer: token)
          output.write(
            HostMessage(
              event: "effect_posted",
              fields: [
                "key": key, "disposition": receipt.disposition.rawValue, "seq": String(receipt.seq),
              ]))
          guard receipt.disposition != .conflict else { throw HostError.ledgerConflict }
          await gate.pass(.effectPosted)
          // A real model reads this result; it must answer rather than call the tool again.
          return RuntimeToolResult(
            text: "The qualification effect is recorded. Do not call \(QualificationHost.toolName) "
              + "again; reply with one short sentence confirming it.")
        }
      })
  }

  private static func observe(_ store: Store, output: LineWriter) throws -> Task<Void, Never> {
    let stream = try store.subscribeEvents(capacity: 4096)
    return Task {
      do {
        for try await envelope in stream {
          switch envelope.event {
          case .approvalRequested(let value):
            output.write(
              HostMessage(
                event: "approval_requested",
                fields: [
                  "approvalId": value.approvalId.rawValue, "cardId": value.cardId.rawValue,
                  "toolCallId": value.toolCallId,
                ]))
          case .approvalResolved:
            output.write(HostMessage(event: "approval_resolved"))
          case .toolCompleted(let value) where value.tool == QualificationHost.toolName:
            output.write(
              HostMessage(
                event: "tool_completed",
                fields: ["toolCallId": value.toolCallId, "ok": String(value.ok)]))
          case .taskFinished(let value):
            output.write(
              HostMessage(
                event: "task_finished",
                fields: ["taskId": value.taskId.rawValue, "status": value.status.rawValue]))
          default:
            break
          }
        }
      } catch {
        output.write(HostMessage(event: "observer_ended", error: QualificationHost.describe(error)))
      }
    }
  }
}
