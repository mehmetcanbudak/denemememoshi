import Foundation
import MemoshiProtocol
import MemoshiStore

/// Durable audit record for a live bot-to-bot message or Assistant handoff (`D109`, `GR-06`).
public struct BotHandoffRecord: Codable, Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  public let sourceBotID: String
  public let sourceBotName: String
  public let sourceConversationID: String
  public let targetBotID: String
  public let targetBotName: String
  public let targetConversationID: String
  public let summary: String
  public let hopDepth: Int
  public let targetTaskID: String?
  public let targetMessageID: String?
  public let createdAt: Date

  public init(
    id: String = UUID().uuidString,
    sourceBotID: String,
    sourceBotName: String,
    sourceConversationID: String,
    targetBotID: String,
    targetBotName: String,
    targetConversationID: String,
    summary: String,
    hopDepth: Int,
    targetTaskID: String? = nil,
    targetMessageID: String? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.sourceBotID = sourceBotID
    self.sourceBotName = sourceBotName
    self.sourceConversationID = sourceConversationID
    self.targetBotID = targetBotID
    self.targetBotName = targetBotName
    self.targetConversationID = targetConversationID
    self.summary = summary
    self.hopDepth = hopDepth
    self.targetTaskID = targetTaskID
    self.targetMessageID = targetMessageID
    self.createdAt = createdAt
  }
}

/// Persists live bot-to-bot handoff records in `<dataDirectory>/BotHandoffs.jsonl` so both the
/// sending and receiving Chats render visible `Messaged <Bot>` handoff cards (`D109`).
public struct BotHandoffStore: Sendable {
  /// Hard hop limit preventing runaway bot-to-bot ping-pong loops (`D109`, `GR-06`).
  public static let maxHopDepth = 8

  public let dataDirectory: URL

  public var fileURL: URL {
    dataDirectory.appendingPathComponent("BotHandoffs.jsonl")
  }

  public init(dataDirectory: URL) {
    self.dataDirectory = dataDirectory.standardizedFileURL
  }

  public func append(_ record: BotHandoffRecord) throws {
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var line = try encoder.encode(record)
    line.append(0x0A)
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: fileURL)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
  }

  public func loadAll(limit: Int = 100) -> [BotHandoffRecord] {
    guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let records = raw.split(whereSeparator: \.isNewline).compactMap { line -> BotHandoffRecord? in
      guard let data = String(line).data(using: .utf8) else { return nil }
      return try? decoder.decode(BotHandoffRecord.self, from: data)
    }
    return Array(records.suffix(limit).reversed())
  }

  public func load(forConversation conversationID: String, limit: Int = 20) -> [BotHandoffRecord] {
    let matches = loadAll(limit: 200).filter {
      $0.sourceConversationID == conversationID || $0.targetConversationID == conversationID
    }
    return Array(matches.prefix(limit))
  }
}

/// Real bot-to-bot messaging & Assistant handoff tools (`D109`, `GR-06`, `AS-08`).
///
/// Delivers real prompts into another bot's conversation via `RuntimeAdapter.send`, enforcing the
/// 8-hop cap, preventing self-handoffs, and recording visible `Messaged <Bot>` handoff cards.
public enum BotHandoffTools {
  public typealias DeliverChat = @Sendable (ChatsSendParams) async throws -> ChatsSendResult

  public static func definitions(
    dataDirectory: URL,
    store: Store,
    deliver: @escaping DeliverChat
  ) -> [RuntimeToolDefinition] {
    let handoffStore = BotHandoffStore(dataDirectory: dataDirectory)
    return [
      botsListTool(store: store),
      messageBotTool(store: store, handoffStore: handoffStore, deliver: deliver),
    ]
  }

  private static func botsListTool(store: Store) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "bots_list",
      description:
        "List all real bots available in Memoshi along with their role, job summary, and chat ID.",
      parameters: [
        "type": "object",
        "properties": [:],
        "additionalProperties": false,
      ],
      operation: .selfState,
      replaySafe: true,
      outputExposure: Exposure(untrusted: false, privateData: false),
      authorize: { _ in true },
      execute: { _, _ in
        let bots = try await store.bots().value
        let chats = try await store.chats().value
        if bots.isEmpty {
          return RuntimeToolResult(text: "No bots are configured yet.")
        }
        let lines = bots.map { bot -> String in
          let primaryChat = chats.first {
            $0.botId == bot.id && ($0.kind == .bot || $0.kind == .assistant)
          }
          let chatPart = primaryChat.map { "chatId: \($0.id.rawValue)" } ?? "no primary chat"
          let jobPart = bot.job.isEmpty ? "" : " — \(bot.job)"
          return "- \(bot.name) (id: \(bot.id.rawValue), role: \(bot.role.rawValue), \(chatPart))\(jobPart)"
        }
        return RuntimeToolResult(
          text: "Available bots (\(bots.count)):\n" + lines.joined(separator: "\n")
        )
      }
    )
  }

  private static func messageBotTool(
    store: Store,
    handoffStore: BotHandoffStore,
    deliver: @escaping DeliverChat
  ) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "message_bot",
      description:
        "Send a visible handoff or brief to another Memoshi bot by name or ID. Enforces the 8-hop cap (D109) and logs a `Messaged <Bot>` card in both chats.",
      parameters: [
        "type": "object",
        "properties": [
          "bot": [
            "type": "string",
            "minLength": 1,
            "maxLength": 120,
            "description": "Target bot name (case-insensitive) or bot ID.",
          ],
          "message": [
            "type": "string",
            "minLength": 1,
            "maxLength": 12_000,
            "description": "The brief, context, or task to hand off to the target bot.",
          ],
          "hop": [
            "type": "integer",
            "minimum": 1,
            "maximum": 8,
            "description": "Current hop number in a delegation chain (default 1, max 8).",
          ],
        ],
        "required": ["bot", "message"],
        "additionalProperties": false,
      ],
      operation: .connectorStage,
      replaySafe: false,
      outputExposure: Exposure(untrusted: false, privateData: true),
      authorize: { _ in true },
      execute: { arguments, invocation in
        guard case .object(let values) = arguments,
          let targetQuery = stringArg(values["bot"])?.trimmingCharacters(
            in: .whitespacesAndNewlines),
          !targetQuery.isEmpty,
          let message = stringArg(values["message"])?.trimmingCharacters(
            in: .whitespacesAndNewlines),
          !message.isEmpty
        else {
          throw RuntimeToolError.invalidArguments
        }
        let hop = intArg(values["hop"]) ?? 1
        guard hop >= 1 && hop <= BotHandoffStore.maxHopDepth else {
          return RuntimeToolResult(
            text:
              "Handoff blocked: hop \(hop) exceeds Memoshi's \(BotHandoffStore.maxHopDepth)-hop safety limit (D109).",
            isError: true,
            effectOutcome: .notApplied
          )
        }

        let sourceConversationID = invocation.fence.conversationID
        let bots = try await store.bots().value
        let chats = try await store.chats().value

        let sourceChat = chats.first { $0.id == sourceConversationID }
        let sourceBot = sourceChat.flatMap { sc in bots.first { $0.id == sc.botId } }
        let sourceBotID = sourceBot?.id.rawValue ?? "unknown"
        let sourceBotName = sourceBot?.name ?? sourceChat?.title ?? "Assistant"

        guard
          let targetBot = bots.first(where: {
            $0.id.rawValue == targetQuery
              || $0.name.localizedCaseInsensitiveCompare(targetQuery) == .orderedSame
          })
        else {
          let available = bots.map(\.name).joined(separator: ", ")
          return RuntimeToolResult(
            text: "No bot named '\(targetQuery)' was found. Available bots: \(available).",
            isError: true,
            effectOutcome: .notApplied
          )
        }

        guard
          let targetChat = chats.first(where: {
            $0.botId == targetBot.id && ($0.kind == .bot || $0.kind == .assistant)
          })
        else {
          return RuntimeToolResult(
            text: "Bot '\(targetBot.name)' has no active Chat to receive handoffs.",
            isError: true,
            effectOutcome: .notApplied
          )
        }

        if targetChat.id == sourceConversationID {
          return RuntimeToolResult(
            text: "A bot cannot hand off to its own active conversation.",
            isError: true,
            effectOutcome: .notApplied
          )
        }

        let requestID = try IDGenerator.shared.next()
        let framedPrompt =
          "[Handoff from \(sourceBotName) · hop \(hop)/\(BotHandoffStore.maxHopDepth)]\n\n\(message)"
        let sendParams = ChatsSendParams(
          requestId: requestID,
          chatId: targetChat.id,
          content: [.text(TextPart(text: framedPrompt))],
          whenBusy: .followUp,
          model: nil,
          surface: .ui
        )

        let receipt = try await invocation.runCancellable {
          try await deliver(sendParams)
        }

        let summary = String(message.replacingOccurrences(of: "\n", with: " ").prefix(200))
        let record = BotHandoffRecord(
          sourceBotID: sourceBotID,
          sourceBotName: sourceBotName,
          sourceConversationID: sourceConversationID.rawValue,
          targetBotID: targetBot.id.rawValue,
          targetBotName: targetBot.name,
          targetConversationID: targetChat.id.rawValue,
          summary: summary,
          hopDepth: hop,
          targetTaskID: receipt.taskId.rawValue,
          targetMessageID: receipt.messageId.rawValue
        )
        try? handoffStore.append(record)

        return RuntimeToolResult(
          text:
            "Messaged \(targetBot.name) (chat: \(targetChat.id.rawValue), task: \(receipt.taskId.rawValue), hop \(hop)/\(BotHandoffStore.maxHopDepth)): \(summary)"
        )
      }
    )
  }

  private static func stringArg(_ value: MemoshiProtocol.JSONValue?) -> String? {
    guard case .string(let s)? = value else { return nil }
    return s
  }

  private static func intArg(_ value: MemoshiProtocol.JSONValue?) -> Int? {
    switch value {
    case .integer(let i)?: return Int(i)
    case .double(let d)?: return Int(d)
    default: return nil
    }
  }
}
