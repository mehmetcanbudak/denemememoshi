import Foundation
import MemoshiProtocol

#if canImport(Security)
  import Security
#endif

// MARK: - Search Providers & Keychain Settings (D112, D120, D121)

/// Supported external web search providers on the user's own API key (`D120`).
/// Exa is the default external provider; Brave Search, Tavily, and Parallel are selectable.
public enum WebSearchProviderKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
  case exa
  case brave
  case tavily
  case parallel

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .exa: "Exa"
    case .brave: "Brave Search"
    case .tavily: "Tavily"
    case .parallel: "Parallel"
    }
  }

  public var connectorID: String { "search.\(rawValue)" }
}

/// Non-secret search provider selection persisted in `<dataDirectory>/SearchSettings.json`.
/// API keys live exclusively in Keychain via `ConnectorTokenKeychain`.
public struct SearchSettings: Codable, Equatable, Sendable {
  public var defaultWebProvider: WebSearchProviderKind

  public init(defaultWebProvider: WebSearchProviderKind = .exa) {
    self.defaultWebProvider = defaultWebProvider
  }
}

/// Normalized web or X search citation returned by `web_search` / `x_search` (`D112`).
public struct SearchCitation: Codable, Equatable, Hashable, Sendable {
  public let title: String
  public let url: String
  public let snippet: String

  public init(title: String, url: String, snippet: String) {
    self.title = title
    self.url = url
    self.snippet = snippet
  }
}

// MARK: - Built-in Connector Catalog & One-Tap Connect Cards (D112, CON-14)

public enum ConnectorCategory: String, Codable, CaseIterable, Hashable, Sendable {
  case search = "Search"
  case engineering = "Engineering"
  case knowledge = "Knowledge"
  case communication = "Communication"
  case design = "Design"
}

/// Static catalog entry for a built-in connector or search provider (`D112`, `CON-14`).
public struct BuiltInConnector: Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  public let name: String
  public let category: ConnectorCategory
  public let symbol: String
  public let summary: String
  public let authHint: String
  public let mcpEndpoint: String?

  public init(
    id: String, name: String, category: ConnectorCategory, symbol: String,
    summary: String, authHint: String, mcpEndpoint: String? = nil
  ) {
    self.id = id
    self.name = name
    self.category = category
    self.symbol = symbol
    self.summary = summary
    self.authHint = authHint
    self.mcpEndpoint = mcpEndpoint
  }
}

/// A one-tap connect card requested by a bot via `connector_request_connect` (`D112`, `CON-14`).
public struct ConnectorConnectCard: Codable, Identifiable, Equatable, Hashable, Sendable {
  public enum Status: String, Codable, Hashable, Sendable {
    case pending
    case connected
    case dismissed
  }

  public let id: String
  public let connectorID: String
  public let reason: String
  public let requestedByConversationID: String?
  public var status: Status
  public let createdAt: Date

  public init(
    id: String = UUID().uuidString,
    connectorID: String,
    reason: String,
    requestedByConversationID: String? = nil,
    status: Status = .pending,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.connectorID = connectorID
    self.reason = reason
    self.requestedByConversationID = requestedByConversationID
    self.status = status
    self.createdAt = createdAt
  }
}

/// Keychain storage for search provider keys and built-in connector tokens (never on disk).
public enum ConnectorTokenKeychain {
  private static let service = "com.mehmetcanbudak.memoshi.connectors.tokens"

  public static func readToken(for connectorID: String) -> String? {
    #if canImport(Security)
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: connectorID,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      guard status == errSecSuccess, let data = item as? Data else { return nil }
      return String(data: data, encoding: .utf8)
    #else
      return nil
    #endif
  }

  @discardableResult
  public static func saveToken(_ token: String, for connectorID: String) -> Bool {
    #if canImport(Security)
      let data = Data(token.utf8)
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: connectorID,
      ]
      SecItemDelete(query as CFDictionary)
      var addQuery = query
      addQuery[kSecValueData as String] = data
      addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    #else
      return false
    #endif
  }

  @discardableResult
  public static func deleteToken(for connectorID: String) -> Bool {
    #if canImport(Security)
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: connectorID,
      ]
      let status = SecItemDelete(query as CFDictionary)
      return status == errSecSuccess || status == errSecItemNotFound
    #else
      return false
    #endif
  }
}

/// Built-in connector catalog, search provider selection, and pending Connect Cards (`D112`, `D120`).
public struct ConnectorCatalogStore: Sendable {
  public static let xaiSearchConnectorID = "search.xai"

  /// Curated Phase 1 built-in catalog: search providers (D120) + MCP / API connectors (D112).
  public static let catalog: [BuiltInConnector] = [
    BuiltInConnector(
      id: WebSearchProviderKind.exa.connectorID,
      name: "Exa Web Search",
      category: .search,
      symbol: "globe.americas.fill",
      summary: "Default neural web search with clean source citations (D120).",
      authHint: "Exa API Key"
    ),
    BuiltInConnector(
      id: WebSearchProviderKind.brave.connectorID,
      name: "Brave Search",
      category: .search,
      symbol: "safari.fill",
      summary: "Independent web search index with fast snippet results.",
      authHint: "Brave Search API Key"
    ),
    BuiltInConnector(
      id: WebSearchProviderKind.tavily.connectorID,
      name: "Tavily",
      category: .search,
      symbol: "magnifyingglass.circle.fill",
      summary: "Agent-optimized web search and grounded snippets.",
      authHint: "Tavily API Key"
    ),
    BuiltInConnector(
      id: WebSearchProviderKind.parallel.connectorID,
      name: "Parallel Search",
      category: .search,
      symbol: "sparkle.magnifyingglass",
      summary: "High-precision web search API for research workflows.",
      authHint: "Parallel API Key"
    ),
    BuiltInConnector(
      id: xaiSearchConnectorID,
      name: "xAI (X Search)",
      category: .search,
      symbol: "at.circle.fill",
      summary: "Live X / social search powered by xAI on your own API key (D112, D120).",
      authHint: "xAI API Key"
    ),
    BuiltInConnector(
      id: "github",
      name: "GitHub",
      category: .engineering,
      symbol: "chevron.left.forwardslash.chevron.right",
      summary: "Issues, pull requests, repositories, and code reviews over MCP.",
      authHint: "Personal Access Token or OAuth Token",
      mcpEndpoint: "https://api.githubcopilot.com/mcp/"
    ),
    BuiltInConnector(
      id: "linear",
      name: "Linear",
      category: .engineering,
      symbol: "checklist",
      summary: "Cycles, issues, roadmaps, and project triage over MCP.",
      authHint: "Linear API Key or OAuth Token",
      mcpEndpoint: "https://mcp.linear.app/sse"
    ),
    BuiltInConnector(
      id: "notion",
      name: "Notion",
      category: .knowledge,
      symbol: "doc.richtext",
      summary: "Workspace pages, wikis, and databases over MCP.",
      authHint: "Notion Integration Token",
      mcpEndpoint: "https://mcp.notion.com/mcp"
    ),
    BuiltInConnector(
      id: "slack",
      name: "Slack",
      category: .communication,
      symbol: "bubble.left.and.bubble.right.fill",
      summary: "Channel summaries, thread search, and draft replies.",
      authHint: "Slack User or Bot OAuth Token"
    ),
    BuiltInConnector(
      id: "figma",
      name: "Figma",
      category: .design,
      symbol: "paintbrush.pointed.fill",
      summary: "Design files, components, and comments over MCP.",
      authHint: "Figma Personal Access Token",
      mcpEndpoint: "https://mcp.figma.com/mcp"
    ),
    BuiltInConnector(
      id: "sentry",
      name: "Sentry",
      category: .engineering,
      symbol: "exclamationmark.triangle.fill",
      summary: "Crash reports, stack traces, and release health.",
      authHint: "Sentry Auth Token",
      mcpEndpoint: "https://mcp.sentry.dev/mcp"
    ),
  ]

  public let dataDirectory: URL

  public var settingsURL: URL {
    dataDirectory.appendingPathComponent("SearchSettings.json")
  }

  public var connectCardsURL: URL {
    dataDirectory.appendingPathComponent("ConnectCards.json")
  }

  public var connectedIDsURL: URL {
    dataDirectory.appendingPathComponent("ConnectedConnectors.json")
  }

  public init(dataDirectory: URL) {
    self.dataDirectory = dataDirectory.standardizedFileURL
  }

  public static func connector(id: String) -> BuiltInConnector? {
    let lower = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return catalog.first {
      $0.id.lowercased() == lower || $0.name.lowercased() == lower
    }
  }

  public func loadSearchSettings() -> SearchSettings {
    guard let data = try? Data(contentsOf: settingsURL),
      let decoded = try? JSONDecoder().decode(SearchSettings.self, from: data)
    else {
      return SearchSettings()
    }
    return decoded
  }

  public func saveSearchSettings(_ settings: SearchSettings) throws {
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(settings)
    try data.write(to: settingsURL, options: .atomic)
  }

  public func loadConnectedIDs() -> Set<String> {
    guard let data = try? Data(contentsOf: connectedIDsURL),
      let list = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return Set(list)
  }

  public func isConnected(_ connectorID: String) -> Bool {
    if let token = ConnectorTokenKeychain.readToken(for: connectorID), !token.isEmpty {
      return true
    }
    return loadConnectedIDs().contains(connectorID)
  }

  public func markConnected(_ connectorID: String, connected: Bool) throws {
    var ids = loadConnectedIDs()
    if connected {
      ids.insert(connectorID)
    } else {
      ids.remove(connectorID)
    }
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(ids.sorted())
    try data.write(to: connectedIDsURL, options: .atomic)
  }

  public func loadConnectCards() -> [ConnectorConnectCard] {
    guard let data = try? Data(contentsOf: connectCardsURL) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([ConnectorConnectCard].self, from: data)) ?? []
  }

  public func saveConnectCards(_ cards: [ConnectorConnectCard]) throws {
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(cards)
    try data.write(to: connectCardsURL, options: .atomic)
  }

  @discardableResult
  public func enqueueConnectCard(
    connectorID: String, reason: String, conversationID: String?
  ) throws -> ConnectorConnectCard {
    var cards = loadConnectCards()
    if let existing = cards.first(where: {
      $0.connectorID == connectorID && $0.status == .pending
    }) {
      return existing
    }
    let card = ConnectorConnectCard(
      connectorID: connectorID,
      reason: reason,
      requestedByConversationID: conversationID,
      status: .pending
    )
    cards.insert(card, at: 0)
    try saveConnectCards(cards)
    return card
  }

  public func updateConnectCard(id: String, status: ConnectorConnectCard.Status) throws {
    var cards = loadConnectCards()
    guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
    cards[idx].status = status
    try saveConnectCards(cards)
  }
}

// MARK: - Search HTTP Clients (Exa, Brave, Tavily, Parallel, xAI)

enum SearchProviderHTTPClient {
  static func webSearch(
    provider: WebSearchProviderKind, apiKey: String, query: String, limit: Int
  ) async throws -> [SearchCitation] {
    switch provider {
    case .exa:
      let url = URL(string: "https://api.exa.ai/search")!
      let body = try JSONSerialization.data(withJSONObject: [
        "query": query,
        "numResults": limit,
        "contents": ["highlights": ["numSentences": 2]],
      ])
      let data = try await sendJSON(
        url: url, method: "POST", headers: ["x-api-key": apiKey], body: body)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let results = root["results"] as? [[String: Any]]
      else { return [] }
      return results.compactMap { row in
        guard let link = row["url"] as? String, !link.isEmpty else { return nil }
        let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let highlights = (row["highlights"] as? [String])?.joined(separator: " ")
        let text = (row["text"] as? String)
        let snippet = highlights ?? text ?? ""
        return SearchCitation(
          title: (title?.isEmpty == false ? title! : link),
          url: link,
          snippet: String(snippet.prefix(260))
        )
      }

    case .brave:
      var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
      components.queryItems = [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "count", value: String(limit)),
      ]
      let data = try await sendJSON(
        url: components.url!, method: "GET",
        headers: ["X-Subscription-Token": apiKey], body: nil)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let web = root["web"] as? [String: Any],
        let results = web["results"] as? [[String: Any]]
      else { return [] }
      return results.compactMap { row in
        guard let link = row["url"] as? String, !link.isEmpty else { return nil }
        let title = (row["title"] as? String) ?? link
        let desc = (row["description"] as? String) ?? ""
        return SearchCitation(title: title, url: link, snippet: String(desc.prefix(260)))
      }

    case .tavily:
      let url = URL(string: "https://api.tavily.com/search")!
      let body = try JSONSerialization.data(withJSONObject: [
        "api_key": apiKey,
        "query": query,
        "max_results": limit,
        "search_depth": "basic",
      ])
      let data = try await sendJSON(url: url, method: "POST", headers: [:], body: body)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let results = root["results"] as? [[String: Any]]
      else { return [] }
      return results.compactMap { row in
        guard let link = row["url"] as? String, !link.isEmpty else { return nil }
        let title = (row["title"] as? String) ?? link
        let content = (row["content"] as? String) ?? ""
        return SearchCitation(title: title, url: link, snippet: String(content.prefix(260)))
      }

    case .parallel:
      let url = URL(string: "https://api.parallel.ai/v1beta/search")!
      let body = try JSONSerialization.data(withJSONObject: [
        "objective": query,
        "max_results": limit,
      ])
      let data = try await sendJSON(
        url: url, method: "POST", headers: ["x-api-key": apiKey], body: body)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let results = root["results"] as? [[String: Any]]
      else { return [] }
      return results.compactMap { row in
        guard let link = row["url"] as? String, !link.isEmpty else { return nil }
        let title = (row["title"] as? String) ?? link
        let excerpts = (row["excerpts"] as? [String])?.joined(separator: " ") ?? ""
        return SearchCitation(title: title, url: link, snippet: String(excerpts.prefix(260)))
      }
    }
  }

  static func xSearch(
    apiKey: String, query: String, limit: Int
  ) async throws -> (summary: String, citations: [SearchCitation]) {
    let url = URL(string: "https://api.x.ai/v1/chat/completions")!
    let payload: [String: Any] = [
      "model": "grok-3-mini",
      "messages": [
        [
          "role": "system",
          "content":
            "Search X posts and return up to \(limit) concise, factual findings with handles and links.",
        ],
        ["role": "user", "content": query],
      ],
      "search_parameters": [
        "mode": "on",
        "return_citations": true,
        "max_search_results": limit,
        "sources": [["type": "x"]],
      ],
    ]
    let body = try JSONSerialization.data(withJSONObject: payload)
    let data = try await sendJSON(
      url: url, method: "POST",
      headers: ["Authorization": "Bearer \(apiKey)"], body: body)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw RuntimeToolError.unavailable
    }
    let choices = (root["choices"] as? [[String: Any]]) ?? []
    let content =
      ((choices.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
    let rawCitations = (root["citations"] as? [String]) ?? []
    let citations = rawCitations.prefix(limit).map { link in
      SearchCitation(
        title: URL(string: link)?.host ?? "X Post",
        url: link,
        snippet: ""
      )
    }
    return (content, Array(citations))
  }

  private static func sendJSON(
    url: URL, method: String, headers: [String: String], body: Data?
  ) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 25
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    for (k, v) in headers {
      request.setValue(v, forHTTPHeaderField: k)
    }
    if let body {
      request.httpBody = body
      request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw RuntimeToolError.unavailable
    }
    return data
  }
}

// MARK: - Search & Connector Host Tool Definitions (`D112`, `D120`, `D121`)

public enum SearchAndConnectorTools {
  /// Returns `web_search`, `x_search`, `connectors_catalog`, and `connector_request_connect`.
  public static func all(dataDirectory: URL) -> [RuntimeToolDefinition] {
    let store = ConnectorCatalogStore(dataDirectory: dataDirectory)
    return [
      webSearchTool(store: store),
      xSearchTool(store: store),
      connectorsCatalogTool(store: store),
      connectorRequestConnectTool(store: store),
    ]
  }

  /// Formats search citations as Markdown source links so chat transcripts and the Links sidebar
  /// automatically render clickable source chips (`D112`).
  public static func formatCitationsMarkdown(
    header: String, citations: [SearchCitation]
  ) -> String {
    guard !citations.isEmpty else { return header }
    let lines = citations.enumerated().map { idx, item -> String in
      let cleanTitle = item.title.replacingOccurrences(of: "]", with: ")")
      var row = "\(idx + 1). [\(cleanTitle)](\(item.url))"
      let trimmedSnippet = item.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmedSnippet.isEmpty {
        row += " — \(trimmedSnippet)"
      }
      return row
    }
    return header + "\n" + lines.joined(separator: "\n")
  }

  private static func webSearchTool(store: ConnectorCatalogStore) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "web_search",
      description:
        "Search the public web using the configured search provider (Exa default; Brave, Tavily, or Parallel selectable) and return cited source links.",
      parameters: [
        "type": "object",
        "properties": [
          "query": ["type": "string", "minLength": 1, "maxLength": 300],
          "provider": [
            "type": "string",
            "enum": ["exa", "brave", "tavily", "parallel"],
          ],
          "limit": ["type": "integer", "minimum": 1, "maximum": 10],
        ],
        "required": ["query"],
        "additionalProperties": false,
      ],
      operation: .searchWeb,
      replaySafe: true,
      outputExposure: Exposure(untrusted: true, privateData: false),
      authorize: { _ in true },
      execute: { arguments, invocation in
        guard case .object(let values) = arguments,
          let query = stringArg(values["query"])?.trimmingCharacters(in: .whitespacesAndNewlines),
          !query.isEmpty
        else {
          throw RuntimeToolError.invalidArguments
        }
        let limit = max(1, min(10, intArg(values["limit"]) ?? 5))
        let requestedProvider = stringArg(values["provider"]).flatMap(WebSearchProviderKind.init)
        let selectedProvider = requestedProvider ?? store.loadSearchSettings().defaultWebProvider

        // Pick the selected provider if keyed, else fall back to any other keyed web search provider.
        let orderedCandidates: [WebSearchProviderKind] =
          [selectedProvider] + WebSearchProviderKind.allCases.filter { $0 != selectedProvider }
        var resolved: (WebSearchProviderKind, String)?
        for candidate in orderedCandidates {
          if let key = ConnectorTokenKeychain.readToken(for: candidate.connectorID), !key.isEmpty {
            resolved = (candidate, key)
            break
          }
        }
        guard let (provider, apiKey) = resolved else {
          return RuntimeToolResult(
            text:
              "No web search API key is configured yet (default: \(selectedProvider.displayName)). Ask the user to add an Exa, Brave, Tavily, or Parallel key in My Apps → Connectors.",
            isError: true,
            effectOutcome: .notApplied
          )
        }
        return try await invocation.runCancellable {
          let results = try await SearchProviderHTTPClient.webSearch(
            provider: provider, apiKey: apiKey, query: query, limit: limit)
          if results.isEmpty {
            return RuntimeToolResult(
              text: "No web results found via \(provider.displayName) for '\(query)'.")
          }
          let formatted = formatCitationsMarkdown(
            header: "Web search results via \(provider.displayName) for '\(query)':",
            citations: results
          )
          return RuntimeToolResult(text: formatted)
        }
      }
    )
  }

  private static func xSearchTool(store: ConnectorCatalogStore) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "x_search",
      description:
        "Search live posts and discussions on X using the user's xAI API key and return cited source links.",
      parameters: [
        "type": "object",
        "properties": [
          "query": ["type": "string", "minLength": 1, "maxLength": 300],
          "limit": ["type": "integer", "minimum": 1, "maximum": 10],
        ],
        "required": ["query"],
        "additionalProperties": false,
      ],
      operation: .searchWeb,
      replaySafe: true,
      outputExposure: Exposure(untrusted: true, privateData: false),
      authorize: { _ in true },
      execute: { arguments, invocation in
        guard case .object(let values) = arguments,
          let query = stringArg(values["query"])?.trimmingCharacters(in: .whitespacesAndNewlines),
          !query.isEmpty
        else {
          throw RuntimeToolError.invalidArguments
        }
        let limit = max(1, min(10, intArg(values["limit"]) ?? 5))
        guard
          let apiKey = ConnectorTokenKeychain.readToken(
            for: ConnectorCatalogStore.xaiSearchConnectorID),
          !apiKey.isEmpty
        else {
          return RuntimeToolResult(
            text:
              "No xAI API key is configured for x_search. Ask the user to connect xAI in My Apps → Connectors.",
            isError: true,
            effectOutcome: .notApplied
          )
        }
        return try await invocation.runCancellable {
          let (summary, citations) = try await SearchProviderHTTPClient.xSearch(
            apiKey: apiKey, query: query, limit: limit)
          let header =
            summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "X search results for '\(query)':"
            : summary
          let output =
            citations.isEmpty
            ? header
            : formatCitationsMarkdown(header: header + "\n\nSources:", citations: citations)
          return RuntimeToolResult(text: output)
        }
      }
    )
  }

  private static func connectorsCatalogTool(store: ConnectorCatalogStore) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "connectors_catalog",
      description:
        "List Memoshi's built-in search providers and MCP connectors with their current connection status.",
      parameters: [
        "type": "object",
        "properties": [
          "category": [
            "type": "string",
            "enum": ["Search", "Engineering", "Knowledge", "Communication", "Design"],
          ],
        ],
        "additionalProperties": false,
      ],
      operation: .selfState,
      replaySafe: true,
      outputExposure: Exposure(untrusted: false, privateData: false),
      authorize: { _ in true },
      execute: { arguments, _ in
        guard case .object(let values) = arguments else {
          throw RuntimeToolError.invalidArguments
        }
        let categoryFilter = stringArg(values["category"]).flatMap(ConnectorCategory.init)
        let items = ConnectorCatalogStore.catalog.filter { item in
          categoryFilter == nil || item.category == categoryFilter
        }
        let lines = items.map { item -> String in
          let connected = store.isConnected(item.id) ? "connected" : "not connected"
          return "- \(item.name) (`\(item.id)`) [\(item.category.rawValue)] — \(connected): \(item.summary)"
        }
        return RuntimeToolResult(
          text: "Built-in connector catalog (\(items.count)):\n" + lines.joined(separator: "\n")
        )
      }
    )
  }

  private static func connectorRequestConnectTool(
    store: ConnectorCatalogStore
  ) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "connector_request_connect",
      description:
        "Create a one-tap Connect Card asking the user to connect a built-in search provider or MCP connector.",
      parameters: [
        "type": "object",
        "properties": [
          "connectorId": ["type": "string", "minLength": 1, "maxLength": 80],
          "reason": ["type": "string", "minLength": 1, "maxLength": 240],
        ],
        "required": ["connectorId", "reason"],
        "additionalProperties": false,
      ],
      operation: .selfPropose,
      replaySafe: false,
      outputExposure: Exposure(untrusted: false, privateData: false),
      authorize: { _ in true },
      execute: { arguments, invocation in
        guard case .object(let values) = arguments,
          let rawID = stringArg(values["connectorId"]),
          let connector = ConnectorCatalogStore.connector(id: rawID),
          let reason = stringArg(values["reason"])?.trimmingCharacters(in: .whitespacesAndNewlines),
          !reason.isEmpty
        else {
          throw RuntimeToolError.invalidArguments
        }
        if store.isConnected(connector.id) {
          return RuntimeToolResult(
            text: "\(connector.name) (`\(connector.id)`) is already connected."
          )
        }
        let card = try store.enqueueConnectCard(
          connectorID: connector.id,
          reason: reason,
          conversationID: invocation.fence.conversationID.rawValue
        )
        return RuntimeToolResult(
          text:
            "Created one-tap Connect Card for \(connector.name) (card id: \(card.id)). The user can connect it in My Apps → Connectors."
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
