import Foundation
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable

extension RuntimeAdapter {
  func receive(_ events: [PiDurable.AgentEvent], conversationID: ConversationID) async throws {
    guard let thread = threads[conversationID], !thread.failed else { return }
    // Pi activity, such as a turn settling, restarts the idle close's measure.
    thread.lastUsed = .now
    for event in events {
      switch event.type {
      case "submission":
        if let value = event["record"] {
          try await project(value.decode(PiDurable.SubmissionRecord.self), thread: thread)
        }
      case "tool_execution_end", "task_failed":
        if let value = event["taskId"],
          let task = try await thread.storage.task(TaskId(try value.decode(Int.self))),
          task.kind == "pi.tool", task.status == .terminal
        {
          try await projectToolOutcome(task, thread: thread)
        }
      case "message_start":
        guard let value = event["message"],
          let message = try value.decode(PiAI.Message.self).assistantMessage,
          let key = thread.activeRequest, let turn = try await store.chatTurn(key),
          !turn.isTerminal, turn.recoveryStep == nil
        else { continue }
        _ = try await store.projectChatTurn(
          key, assistantStarted: true, status: .running,
          fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
        let text = Self.text(message)
        if thread.textUTF16Count > 0 {
          // A later assistant message of the same turn (a tool loop, or the retry after a
          // restart converted a partial) is another stream under the same message ID. `live`
          // now holds this message alone, so clients refetch it instead of receiving offsets
          // that restart inside text they already hold.
          try await resetPartial(thread, to: text)
        } else {
          try await replacePartial(text, turn: turn, thread: thread)
        }
      case "message_update":
        guard let key = thread.activeRequest, let turn = try await store.chatTurn(key),
          !turn.isTerminal, turn.recoveryStep == nil
        else { continue }
        for change in event["changes"]?.arrayValue ?? [] {
          switch change["type"]?.stringValue {
          case "text_delta":
            if let delta = change["delta"]?.stringValue {
              try await appendPartial(delta, turn: turn, thread: thread)
            }
          case "text_start":
            if let text = change["block"]?["text"]?.stringValue, !text.isEmpty {
              try await appendPartial(text, turn: turn, thread: thread)
            }
          case "message":
            if let value = change["message"] {
              try await replacePartial(
                Self.text(value.decode(PiAI.AssistantMessage.self)), turn: turn, thread: thread)
            }
          case "block":
            // A replacement is not an append. Re-read the committed live snapshot rather than
            // treating offsets as character counts or fabricating an incremental delta.
            try await resetPartial(thread)
          default:
            break  // Thinking and tool-call arguments are not displayed as text replies.
          }
        }
      case "message_end":
        guard let value = event["entry"] else { continue }
        let entry = try value.decode(PiDurable.EntryRecord.self)
        if entry.model?.first?.toolResultMessage != nil {
          try await projectToolEntry(entry, thread: thread)
        }
        if let key = entry.data?["memoshiRequestId"]?.stringValue,
          let request = try? ULID(key),
          let record = try await thread.storage.submissionByRequest(
            .root, requestId: PiCore.JSONString(request.rawValue))
        {
          try await project(record, thread: thread)
        }
        // The reply is bound once its submission settles (`project`, `settledRun`), never here:
        // a partial that a restart converted before retrying is committed like any other entry.
        if let assistant = entry.model?.first?.assistantMessage, !assistant.toolCalls.isEmpty,
          assistant.stopReason != .aborted, toolDefinitions.isEmpty, extensionComposition.isEmpty,
          let key = thread.activeRequest, let turn = try await store.chatTurn(key),
          !turn.isTerminal
        {
          // No tool is installed or offered. Stop an unexpected tool-requesting run; do not
          // turn this development chat into an unqualified tool execution path. A partial that
          // a stop or a restart converted is no request: it must not stop the retry.
          if let engine = thread.engine {
            try await abortRootRun(engine, holding: turn.piSubmissionId.map { SubmissionId($0) })
          }
        }
      case "snapshot":
        try await drainToolOutcomes(thread)
        try await reconcile(thread)
        try await resetPartial(thread)
      default:
        break
      }
    }
    try await drainQueuedInputs(thread, join: false)
  }

  func appendPartial(_ text: String, turn: StoredChatTurn, thread: RuntimeThread) async throws {
    guard !text.isEmpty else { return }
    let offset = thread.textUTF16Count
    thread.text.append(text)
    thread.textUTF16Count += Int64(text.utf16.count)
    let frame = EventEnvelope(
      seq: nil, ts: IDGenerator.nowMilliseconds(), deviceId: store.deviceID,
      actor: Actor(kind: .bot, id: thread.botID.rawValue),
      subject: ObjectRef(kind: "message", id: turn.assistantMessageId.rawValue),
      scope: EventScope(
        botId: thread.botID, conversationId: thread.ownership.fence.conversationID,
        taskId: turn.taskId),
      origin: Origin(kind: .user, rootKind: .user),
      event: .messageDelta(
        MessageDeltaPayload(
          messageId: turn.assistantMessageId,
          channel: .text, offsetUtf16: offset, text: text)))
    // The daemon stamps `after` from its actual current log head before encoding this draft.
    try await publishLive(frame)
  }

  func replacePartial(_ text: String, turn: StoredChatTurn, thread: RuntimeThread) async throws {
    if text.utf16.starts(with: thread.text.utf16) {
      let suffix = text.utf16.dropFirst(Int(thread.textUTF16Count))
      try await appendPartial(String(decoding: suffix, as: UTF16.self), turn: turn, thread: thread)
    } else {
      try await resetPartial(thread)
    }
  }

  /// Tells clients to refetch `live`. The stream continues from `text` when this event carries
  /// the message's own text, else from the committed live snapshot.
  func resetPartial(_ thread: RuntimeThread, to text: String? = nil) async throws {
    if let text {
      thread.text = text
    } else {
      let live = try await thread.engine?.harness.snapshot(
        PiDurable.liveDoc, owner: ConversationId.root.rawValue)
      thread.text = live?.generation?.message.map(Self.text) ?? ""
    }
    thread.textUTF16Count = Int64(thread.text.utf16.count)
    let conversation = thread.ownership.fence.conversationID
    try await publishLive(
      EventEnvelope(
        seq: nil, ts: IDGenerator.nowMilliseconds(), deviceId: store.deviceID,
        actor: Actor(kind: .system), subject: ObjectRef(kind: "system", id: "runtime"),
        scope: EventScope(botId: thread.botID, conversationId: conversation),
        event: .systemResyncRequired(
          SystemResyncRequiredPayload(
            scope: ResyncScope(conversationId: conversation), reason: .projectorReset))))
  }

  static func text(_ message: PiAI.AssistantMessage) -> String {
    message.content.compactMap { $0.textContent?.text.displayString }.joined()
  }

  static func content(_ message: PiAI.Message) -> [MemoshiProtocol.ContentPart] {
    let text: String
    switch message {
    case .user(let value):
      text = value.content.blocks.compactMap { $0.textContent?.text.displayString }.joined()
    case .assistant(let value):
      text = Self.text(value)
    default:
      text = ""
    }
    return [.text(TextPart(text: text))]
  }

  static func stopReason(_ value: PiAI.StopReason) -> MemoshiProtocol.StopReason {
    switch value {
    case .stop: .stop
    case .length: .length
    case .toolUse: .toolUse
    case .aborted: .aborted
    case .error, .deferred, .pending: .error
    }
  }

  /// One turn's usage across every model request of its run, in commit order: tool-loop
  /// requests and failed or aborted attempts count, as they do in Pi's `pi.usage`. The cost is
  /// known only when every request was billed per token at nonzero catalog prices; a loopback
  /// model or ChatGPT plan access leaves it unknown rather than reporting a guess.
  func runUsage(_ messages: [PiAI.AssistantMessage]) async throws -> MemoshiProtocol.Usage? {
    guard !messages.isEmpty else { return nil }
    let providers = try await store.modelProviders().value
    var total = PiAI.Usage()
    var priced = true
    for message in messages {
      PiDurable.addUsage(&total, message.usage)
      priced = priced && pricedPerToken(message, providers: providers)
    }
    return Self.usage(total, costKnown: priced)
  }

  /// The request's provider bills its configured key per token and the catalog prices its model.
  private func pricedPerToken(
    _ message: PiAI.AssistantMessage, providers: [ModelProviderConfiguration]
  ) -> Bool {
    let id = message.provider.displayString
    guard let configuration = providers.first(where: { $0.id == id }),
      ModelProviderDefinition.named(id)?.usage(secretRef: configuration.secretRef) == .apiUsage,
      let cost = modelRegistry.getModel(message.provider, message.model)?.cost
    else { return false }
    return [cost.input, cost.output, cost.cacheRead, cost.cacheWrite].contains { $0 > 0 }
      || cost.tiers?.isEmpty == false
  }

  static func usage(_ value: PiAI.Usage, costKnown: Bool) -> MemoshiProtocol.Usage {
    // Pi retains the exact fractional counters. The app protocol exposes integral counters;
    // round tokens upward rather than silently undercounting. Pi prices each request in USD
    // from the catalog; whole micro-USD round to nearest, so float noise adds nothing.
    func tokens(_ value: Double) -> Int64 {
      guard value.isFinite, value > 0 else { return 0 }
      return Int64(exactly: value.rounded(.up)) ?? Int64.max
    }
    let micros = value.cost.total * 1_000_000
    let known = costKnown && micros.isFinite && micros >= 0
    return MemoshiProtocol.Usage(
      inputTokens: tokens(value.input), outputTokens: tokens(value.output),
      cacheReadTokens: tokens(value.cacheRead), cacheWriteTokens: tokens(value.cacheWrite),
      costMicroUsd: known ? Int64(exactly: micros.rounded()) ?? Int64.max : 0, costKnown: known)
  }
}
