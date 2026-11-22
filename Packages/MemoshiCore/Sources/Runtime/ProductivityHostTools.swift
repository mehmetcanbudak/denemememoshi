import Foundation
import MemoshiProtocol

#if canImport(Security)
  import Security
#endif

// MARK: - Notes Host Store (AP-19, D116)

/// Safe, canonical-path-confined Markdown notes store shared between Memoshi's Notes pane
/// (`~/Library/Application Support/Memoshi/Notes`) and the `notes_*` bot tools.
public struct NotesHostStore: Sendable {
  public struct NoteSummary: Equatable, Hashable, Sendable {
    public let filename: String
    public let title: String
    public let byteCount: Int
    public let modifiedAt: Date
  }

  public let directoryURL: URL

  public init(directoryURL: URL) {
    self.directoryURL = directoryURL.standardizedFileURL
  }

  /// Resolves a note filename strictly inside `directoryURL`, rejecting path separators,
  /// parent traversal (`..`), NUL bytes, or symlinks that escape the Notes root.
  public func validatedURL(for rawFilename: String) throws -> URL {
    let trimmed = rawFilename.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      !trimmed.contains("/"),
      !trimmed.contains("\\"),
      !trimmed.contains("\0"),
      trimmed != ".",
      trimmed != "..",
      !trimmed.hasPrefix(".")
    else {
      throw RuntimeToolError.invalidArguments
    }
    let normalizedName: String
    let lower = trimmed.lowercased()
    if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") || lower.hasSuffix(".txt") {
      normalizedName = trimmed
    } else {
      normalizedName = trimmed + ".md"
    }
    let root = directoryURL.resolvingSymlinksInPath().standardizedFileURL
    let candidate = root.appendingPathComponent(normalizedName).standardizedFileURL
    guard candidate.deletingLastPathComponent().path == root.path else {
      throw RuntimeToolError.invalidArguments
    }
    if FileManager.default.fileExists(atPath: candidate.path) {
      let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
      guard resolved.deletingLastPathComponent().path == root.path else {
        throw RuntimeToolError.notAuthorized
      }
    }
    return candidate
  }

  public func list(query: String? = nil) throws -> [NoteSummary] {
    let fm = FileManager.default
    try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let urls = try fm.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    )
    let allowed: Set<String> = ["md", "markdown", "txt"]
    let filter = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var summaries: [NoteSummary] = []
    for url in urls where allowed.contains(url.pathExtension.lowercased()) {
      let values = try? url.resourceValues(forKeys: [
        .contentModificationDateKey, .fileSizeKey, .isRegularFileKey,
      ])
      guard values?.isRegularFile != false else { continue }
      let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
      let filename = url.lastPathComponent
      let title = Self.extractTitle(from: content, fallbackFilename: filename)
      if !filter.isEmpty {
        let matched =
          filename.localizedCaseInsensitiveContains(filter)
          || title.localizedCaseInsensitiveContains(filter)
          || content.localizedCaseInsensitiveContains(filter)
        if !matched { continue }
      }
      summaries.append(
        NoteSummary(
          filename: filename,
          title: title,
          byteCount: values?.fileSize ?? content.utf8.count,
          modifiedAt: values?.contentModificationDate ?? Date.distantPast
        )
      )
    }
    return summaries.sorted { lhs, rhs in
      if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
      return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
    }
  }

  public func read(filename: String) throws -> (filename: String, content: String) {
    let url = try validatedURL(for: filename)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw RuntimeToolError.unavailable
    }
    let content = try String(contentsOf: url, encoding: .utf8)
    return (url.lastPathComponent, content)
  }

  public func save(filename: String, content: String) throws -> (filename: String, byteCount: Int) {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let url = try validatedURL(for: filename)
    guard let data = content.data(using: .utf8) else {
      throw RuntimeToolError.invalidArguments
    }
    try data.write(to: url, options: .atomic)
    return (url.lastPathComponent, data.count)
  }

  public static func extractTitle(from content: String, fallbackFilename: String) -> String {
    for rawLine in content.split(whereSeparator: \.isNewline) {
      let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      let stripped = trimmed.drop(while: { $0 == "#" || $0 == " " })
      if !stripped.isEmpty { return String(stripped.prefix(80)) }
    }
    return (fallbackFilename as NSString).deletingPathExtension
  }
}

// MARK: - Mail Provider Configuration, Draft Store & Organize Audit (D116, D118, CON-08)

/// Supported built-in mail providers over their own interfaces (never Apple Mail / Apple Events).
public enum MailProviderKind: String, Codable, CaseIterable, Hashable, Sendable {
  case gmail
  case microsoft365

  public var displayName: String {
    switch self {
    case .gmail: "Gmail"
    case .microsoft365: "Microsoft 365"
    }
  }
}

/// Non-secret account metadata stored on disk; OAuth access tokens stay in macOS Keychain only.
public struct MailAccountRecord: Codable, Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  public let provider: MailProviderKind
  public let emailAddress: String
  public let displayName: String
  public let createdAt: Date

  public init(
    id: String = UUID().uuidString,
    provider: MailProviderKind,
    emailAddress: String,
    displayName: String,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.provider = provider
    self.emailAddress = emailAddress
    self.displayName = displayName
    self.createdAt = createdAt
  }
}

/// A draft staged by a bot or user for explicit human review and send (`D116` draft-before-send).
public struct MailDraftRecord: Codable, Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  public var accountID: String?
  public var to: [String]
  public var cc: [String]
  public var subject: String
  public var body: String
  public var replyToMessageID: String?
  public var remoteDraftID: String?
  public let createdAt: Date
  public var updatedAt: Date

  public init(
    id: String = UUID().uuidString,
    accountID: String? = nil,
    to: [String],
    cc: [String] = [],
    subject: String,
    body: String,
    replyToMessageID: String? = nil,
    remoteDraftID: String? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.accountID = accountID
    self.to = to
    self.cc = cc
    self.subject = subject
    self.body = body
    self.replyToMessageID = replyToMessageID
    self.remoteDraftID = remoteDraftID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

/// Reversible mailbox organization actions permitted under `mail.organize` (`D118`).
public enum MailOrganizeAction: String, Codable, CaseIterable, Hashable, Sendable {
  case archive
  case unarchive
  case markRead = "mark_read"
  case markUnread = "mark_unread"
  case star
  case unstar

  public var inverse: MailOrganizeAction {
    switch self {
    case .archive: .unarchive
    case .unarchive: .archive
    case .markRead: .markUnread
    case .markUnread: .markRead
    case .star: .unstar
    case .unstar: .star
    }
  }
}

/// Durable audit row for every reversible `mail_organize` action (`D118`).
public struct MailOrganizeAuditEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  public let accountID: String
  public let messageID: String
  public let action: MailOrganizeAction
  public let inverseAction: MailOrganizeAction
  public let timestamp: Date

  public init(
    id: String = UUID().uuidString,
    accountID: String,
    messageID: String,
    action: MailOrganizeAction,
    timestamp: Date = Date()
  ) {
    self.id = id
    self.accountID = accountID
    self.messageID = messageID
    self.action = action
    self.inverseAction = action.inverse
    self.timestamp = timestamp
  }
}

/// Keychain storage for mail OAuth Bearer tokens (never written to plaintext JSON files).
public enum MailTokenKeychain {
  private static let service = "com.mehmetcanbudak.memoshi.mail.tokens"

  public static func readToken(for accountID: String) -> String? {
    #if canImport(Security)
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: accountID,
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
  public static func saveToken(_ token: String, for accountID: String) -> Bool {
    #if canImport(Security)
      let data = Data(token.utf8)
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: accountID,
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
  public static func deleteToken(for accountID: String) -> Bool {
    #if canImport(Security)
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: accountID,
      ]
      let status = SecItemDelete(query as CFDictionary)
      return status == errSecSuccess || status == errSecItemNotFound
    #else
      return false
    #endif
  }
}

/// Manages staged mail drafts, non-secret mail account descriptors, and `mail_organize` audit logs.
public struct MailHostStore: Sendable {
  public let dataDirectory: URL

  public var draftsDirectory: URL {
    dataDirectory.appendingPathComponent("MailDrafts", isDirectory: true)
  }

  public var accountsFileURL: URL {
    dataDirectory.appendingPathComponent("MailAccounts.json")
  }

  public var organizeAuditURL: URL {
    dataDirectory.appendingPathComponent("MailOrganizeAudit.jsonl")
  }

  public init(dataDirectory: URL) {
    self.dataDirectory = dataDirectory.standardizedFileURL
  }

  public func loadAccounts() -> [MailAccountRecord] {
    guard let data = try? Data(contentsOf: accountsFileURL) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([MailAccountRecord].self, from: data)) ?? []
  }

  public func saveAccounts(_ accounts: [MailAccountRecord]) throws {
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(accounts)
    try data.write(to: accountsFileURL, options: .atomic)
  }

  public func resolveAccount(_ requestedIDOrEmail: String?) -> MailAccountRecord? {
    let accounts = loadAccounts()
    guard let requested = requestedIDOrEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
      !requested.isEmpty
    else {
      return accounts.first
    }
    return accounts.first {
      $0.id == requested
        || $0.emailAddress.localizedCaseInsensitiveCompare(requested) == .orderedSame
    }
  }

  public func loadDrafts() -> [MailDraftRecord] {
    let fm = FileManager.default
    guard let urls = try? fm.contentsOfDirectory(
      at: draftsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    ) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return urls
      .filter { $0.pathExtension.lowercased() == "json" }
      .compactMap { url -> MailDraftRecord? in
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(MailDraftRecord.self, from: data)
      }
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  @discardableResult
  public func saveDraft(_ draft: MailDraftRecord) throws -> MailDraftRecord {
    try FileManager.default.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(draft)
    let safeID = draft.id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    let filename = (safeID.isEmpty ? UUID().uuidString : safeID) + ".json"
    let url = draftsDirectory.appendingPathComponent(filename)
    try data.write(to: url, options: .atomic)
    return draft
  }

  public func deleteDraft(id: String) throws {
    let safeID = id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    guard !safeID.isEmpty else { return }
    let url = draftsDirectory.appendingPathComponent(safeID + ".json")
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  public func appendOrganizeAudit(_ entry: MailOrganizeAuditEntry) throws {
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var line = try encoder.encode(entry)
    line.append(0x0A)
    if !FileManager.default.fileExists(atPath: organizeAuditURL.path) {
      FileManager.default.createFile(atPath: organizeAuditURL.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: organizeAuditURL)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
  }

  public func loadOrganizeAudit(limit: Int = 50) -> [MailOrganizeAuditEntry] {
    guard let raw = try? String(contentsOf: organizeAuditURL, encoding: .utf8) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let entries = raw.split(whereSeparator: \.isNewline).compactMap { line -> MailOrganizeAuditEntry? in
      guard let data = String(line).data(using: .utf8) else { return nil }
      return try? decoder.decode(MailOrganizeAuditEntry.self, from: data)
    }
    return Array(entries.suffix(limit).reversed())
  }
}

/// Real REST provider adapter for Gmail API v1 and Microsoft Graph Mail API v1.0.
enum MailProviderHTTPClient {
  struct MessageSummary: Sendable {
    let id: String
    let from: String
    let subject: String
    let date: String
    let snippet: String
  }

  static func listMessages(
    account: MailAccountRecord, token: String, query: String?, limit: Int
  ) async throws -> [MessageSummary] {
    switch account.provider {
    case .gmail:
      var components = URLComponents(
        string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
      var items = [URLQueryItem(name: "maxResults", value: String(limit))]
      if let query, !query.isEmpty {
        items.append(URLQueryItem(name: "q", value: query))
      }
      components.queryItems = items
      let data = try await sendRequest(url: components.url!, method: "GET", token: token, body: nil)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let refs = root["messages"] as? [[String: Any]]
      else {
        return []
      }
      var summaries: [MessageSummary] = []
      for ref in refs.prefix(limit) {
        guard let id = ref["id"] as? String else { continue }
        if let detail = try? await readGmailSummary(id: id, token: token) {
          summaries.append(detail)
        }
      }
      return summaries

    case .microsoft365:
      var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/messages")!
      var items = [
        URLQueryItem(name: "$top", value: String(limit)),
        URLQueryItem(
          name: "$select", value: "id,subject,from,receivedDateTime,bodyPreview"),
      ]
      if let query, !query.isEmpty {
        let escaped = query.replacingOccurrences(of: "\"", with: "")
        items.append(URLQueryItem(name: "$search", value: "\"\(escaped)\""))
      } else {
        items.append(URLQueryItem(name: "$orderby", value: "receivedDateTime desc"))
      }
      components.queryItems = items
      let data = try await sendRequest(url: components.url!, method: "GET", token: token, body: nil)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let values = root["value"] as? [[String: Any]]
      else { return [] }
      return values.compactMap { row -> MessageSummary? in
        guard let id = row["id"] as? String else { return nil }
        let subject = (row["subject"] as? String) ?? "(No Subject)"
        let fromDict = (row["from"] as? [String: Any])?["emailAddress"] as? [String: Any]
        let from = (fromDict?["address"] as? String) ?? (fromDict?["name"] as? String) ?? "Unknown"
        let date = (row["receivedDateTime"] as? String) ?? ""
        let snippet = (row["bodyPreview"] as? String) ?? ""
        return MessageSummary(id: id, from: from, subject: subject, date: date, snippet: snippet)
      }
    }
  }

  static func readMessage(
    account: MailAccountRecord, token: String, messageID: String
  ) async throws -> String {
    let encodedID = messageID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageID
    switch account.provider {
    case .gmail:
      let url = URL(
        string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(encodedID)?format=full")!
      let data = try await sendRequest(url: url, method: "GET", token: token, body: nil)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw RuntimeToolError.unavailable
      }
      let payload = root["payload"] as? [String: Any]
      let headers = (payload?["headers"] as? [[String: Any]]) ?? []
      let from = headerValue("From", in: headers) ?? "Unknown"
      let to = headerValue("To", in: headers) ?? ""
      let subject = headerValue("Subject", in: headers) ?? "(No Subject)"
      let date = headerValue("Date", in: headers) ?? ""
      let snippet = (root["snippet"] as? String) ?? ""
      let bodyText = extractGmailPlainText(payload) ?? snippet
      return """
        From: \(from)
        To: \(to)
        Date: \(date)
        Subject: \(subject)

        \(String(bodyText.prefix(8_000)))
        """

    case .microsoft365:
      let url = URL(
        string:
          "https://graph.microsoft.com/v1.0/me/messages/\(encodedID)?$select=id,subject,from,toRecipients,receivedDateTime,body,bodyPreview"
      )!
      let data = try await sendRequest(url: url, method: "GET", token: token, body: nil)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw RuntimeToolError.unavailable
      }
      let subject = (root["subject"] as? String) ?? "(No Subject)"
      let fromDict = (root["from"] as? [String: Any])?["emailAddress"] as? [String: Any]
      let from = (fromDict?["address"] as? String) ?? "Unknown"
      let date = (root["receivedDateTime"] as? String) ?? ""
      let body = (root["body"] as? [String: Any])?["content"] as? String
        ?? (root["bodyPreview"] as? String) ?? ""
      return """
        From: \(from)
        Date: \(date)
        Subject: \(subject)

        \(String(body.prefix(8_000)))
        """
    }
  }

  static func createRemoteDraft(
    account: MailAccountRecord, token: String, draft: MailDraftRecord
  ) async throws -> String? {
    switch account.provider {
    case .gmail:
      var mimeLines = [
        "To: \(draft.to.joined(separator: ", "))",
        "Subject: \(draft.subject)",
        "Content-Type: text/plain; charset=\"UTF-8\"",
      ]
      if !draft.cc.isEmpty {
        mimeLines.insert("Cc: \(draft.cc.joined(separator: ", "))", at: 1)
      }
      let rawMime = mimeLines.joined(separator: "\r\n") + "\r\n\r\n" + draft.body
      let rawEncoded = Data(rawMime.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
      var messageObj: [String: Any] = ["raw": rawEncoded]
      if let replyID = draft.replyToMessageID, !replyID.isEmpty {
        messageObj["threadId"] = replyID
      }
      let bodyData = try JSONSerialization.data(withJSONObject: ["message": messageObj])
      let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/drafts")!
      let data = try await sendRequest(url: url, method: "POST", token: token, body: bodyData)
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      return root?["id"] as? String

    case .microsoft365:
      let payload: [String: Any] = [
        "subject": draft.subject,
        "body": ["contentType": "Text", "content": draft.body],
        "toRecipients": draft.to.map { ["emailAddress": ["address": $0]] },
        "ccRecipients": draft.cc.map { ["emailAddress": ["address": $0]] },
      ]
      let bodyData = try JSONSerialization.data(withJSONObject: payload)
      let url = URL(string: "https://graph.microsoft.com/v1.0/me/messages")!
      let data = try await sendRequest(url: url, method: "POST", token: token, body: bodyData)
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      return root?["id"] as? String
    }
  }

  static func organizeMessage(
    account: MailAccountRecord, token: String, messageID: String, action: MailOrganizeAction
  ) async throws {
    let encodedID = messageID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageID
    switch account.provider {
    case .gmail:
      let addLabels: [String]
      let removeLabels: [String]
      switch action {
      case .archive: (addLabels, removeLabels) = ([], ["INBOX"])
      case .unarchive: (addLabels, removeLabels) = (["INBOX"], [])
      case .markRead: (addLabels, removeLabels) = ([], ["UNREAD"])
      case .markUnread: (addLabels, removeLabels) = (["UNREAD"], [])
      case .star: (addLabels, removeLabels) = (["STARRED"], [])
      case .unstar: (addLabels, removeLabels) = ([], ["STARRED"])
      }
      let payload: [String: Any] = [
        "addLabelIds": addLabels,
        "removeLabelIds": removeLabels,
      ]
      let bodyData = try JSONSerialization.data(withJSONObject: payload)
      let url = URL(
        string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(encodedID)/modify")!
      _ = try await sendRequest(url: url, method: "POST", token: token, body: bodyData)

    case .microsoft365:
      switch action {
      case .archive:
        let bodyData = try JSONSerialization.data(withJSONObject: ["destinationId": "archive"])
        let url = URL(string: "https://graph.microsoft.com/v1.0/me/messages/\(encodedID)/move")!
        _ = try await sendRequest(url: url, method: "POST", token: token, body: bodyData)
      case .unarchive:
        let bodyData = try JSONSerialization.data(withJSONObject: ["destinationId": "inbox"])
        let url = URL(string: "https://graph.microsoft.com/v1.0/me/messages/\(encodedID)/move")!
        _ = try await sendRequest(url: url, method: "POST", token: token, body: bodyData)
      case .markRead, .markUnread:
        let bodyData = try JSONSerialization.data(
          withJSONObject: ["isRead": action == .markRead])
        let url = URL(string: "https://graph.microsoft.com/v1.0/me/messages/\(encodedID)")!
        _ = try await sendRequest(url: url, method: "PATCH", token: token, body: bodyData)
      case .star, .unstar:
        let bodyData = try JSONSerialization.data(
          withJSONObject: ["flag": ["flagStatus": action == .star ? "flagged" : "notFlagged"]])
        let url = URL(string: "https://graph.microsoft.com/v1.0/me/messages/\(encodedID)")!
        _ = try await sendRequest(url: url, method: "PATCH", token: token, body: bodyData)
      }
    }
  }

  private static func readGmailSummary(id: String, token: String) async throws -> MessageSummary {
    let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    let url = URL(
      string:
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(encodedID)?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date"
    )!
    let data = try await sendRequest(url: url, method: "GET", token: token, body: nil)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw RuntimeToolError.unavailable
    }
    let headers = ((root["payload"] as? [String: Any])?["headers"] as? [[String: Any]]) ?? []
    return MessageSummary(
      id: id,
      from: headerValue("From", in: headers) ?? "Unknown",
      subject: headerValue("Subject", in: headers) ?? "(No Subject)",
      date: headerValue("Date", in: headers) ?? "",
      snippet: (root["snippet"] as? String) ?? ""
    )
  }

  private static func sendRequest(
    url: URL, method: String, token: String, body: Data?
  ) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 20
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
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

  private static func headerValue(_ name: String, in headers: [[String: Any]]) -> String? {
    headers.first {
      ($0["name"] as? String)?.localizedCaseInsensitiveCompare(name) == .orderedSame
    }?["value"] as? String
  }

  private static func extractGmailPlainText(_ payload: [String: Any]?) -> String? {
    guard let payload else { return nil }
    if let mime = payload["mimeType"] as? String, mime.lowercased() == "text/plain",
      let body = payload["body"] as? [String: Any],
      let data = body["data"] as? String,
      let decoded = decodeBase64URL(data)
    {
      return decoded
    }
    if let parts = payload["parts"] as? [[String: Any]] {
      for part in parts {
        if let found = extractGmailPlainText(part) { return found }
      }
    }
    return nil
  }

  private static func decodeBase64URL(_ raw: String) -> String? {
    var base64 = raw.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder != 0 {
      base64.append(String(repeating: "=", count: 4 - remainder))
    }
    guard let data = Data(base64Encoded: base64) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

// MARK: - Productivity & Personal Host Tool Composition (`D116`, `D118`, `AP-14`)

/// Composes Memoshi's Phase 1 Mac personal & productivity host tools:
/// - Apple EventKit (`calendar_list`, `calendar_create`, `reminders_list`, `reminders_create`,
///   `reminders_complete`) and Apple Contacts (`contacts_search`)
/// - Local Markdown Notes (`notes_list`, `notes_read`, `notes_save`)
/// - Draft-safe Mail (`mail_list`, `mail_search`, `mail_read`, `mail_draft`, `mail_organize`)
public enum PersonalHostTools {
  /// Returns all built-in personal and productivity `RuntimeToolDefinition`s rooted at `dataDirectory`.
  public static func all(dataDirectory: URL) -> [RuntimeToolDefinition] {
    var tools = ApplePersonalTools.definitions()
    tools.append(contentsOf: notesDefinitions(dataDirectory: dataDirectory))
    tools.append(contentsOf: mailDefinitions(dataDirectory: dataDirectory))
    return tools
  }

  public static func notesDefinitions(dataDirectory: URL) -> [RuntimeToolDefinition] {
    let notesStore = NotesHostStore(
      directoryURL: dataDirectory.appendingPathComponent("Notes", isDirectory: true))
    return [
      notesListTool(store: notesStore),
      notesReadTool(store: notesStore),
      notesSaveTool(store: notesStore),
    ]
  }

  public static func mailDefinitions(dataDirectory: URL) -> [RuntimeToolDefinition] {
    let mailStore = MailHostStore(dataDirectory: dataDirectory)
    return [
      mailListTool(store: mailStore),
      mailSearchTool(store: mailStore),
      mailReadTool(store: mailStore),
      mailDraftTool(store: mailStore),
      mailOrganizeTool(store: mailStore),
    ]
  }

  // MARK: - Notes Tools

  private static func notesListTool(store: NotesHostStore) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "notes_list",
      description: "List Markdown notes in Memoshi's Notes folder, optionally filtered by a query.",
      parameters: [
        "type": "object",
        "properties": [
          "query": ["type": "string", "maxLength": 160],
        ],
        "additionalProperties": false,
      ],
      operation: .selfState,
      replaySafe: true,
      outputExposure: Exposure(untrusted: false, privateData: true),
      authorize: { _ in true },
      execute: { arguments, _ in
        guard case .object(let values) = arguments else {
          throw RuntimeToolError.invalidArguments
        }
        let query = stringArg(values["query"])
        let items = try store.list(query: query)
        if items.isEmpty {
          return RuntimeToolResult(text: "No Markdown notes found in Memoshi Notes.")
        }
        let lines = items.map { item in
          "- \(item.filename) — \(item.title) (\(item.byteCount) bytes)"
        }
        return RuntimeToolResult(
          text: "Found \(items.count) note(s):\n" + lines.joined(separator: "\n")
        )
      }
    )
  }

  private static func notesReadTool(store: NotesHostStore) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "notes_read",
      description: "Read the Markdown contents of a note in Memoshi's Notes folder by filename.",
      parameters: [
        "type": "object",
        "properties": [
          "filename": ["type": "string", "minLength": 1, "maxLength": 120],
        ],
        "required": ["filename"],
        "additionalProperties": false,
      ],
      operation: .selfState,
      replaySafe: true,
      outputExposure: Exposure(untrusted: false, privateData: true),
      authorize: { _ in true },
      execute: { arguments, _ in
        guard case .object(let values) = arguments,
          let filename = stringArg(values["filename"])
        else {
          throw RuntimeToolError.invalidArguments
        }
        do {
          let (resolvedName, content) = try store.read(filename: filename)
          return RuntimeToolResult(text: "# \(resolvedName)\n\n\(content)")
        } catch RuntimeToolError.unavailable {
          return RuntimeToolResult(
            text: "Note '\(filename)' does not exist in Memoshi Notes.",
            isError: true,
            effectOutcome: .notApplied
          )
        }
      }
    )
  }

  private static func notesSaveTool(store: NotesHostStore) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "notes_save",
      description: "Create or update a Markdown note in Memoshi's Notes folder.",
      parameters: [
        "type": "object",
        "properties": [
          "filename": [
            "type": "string",
            "minLength": 1,
            "maxLength": 120,
            "description": "Filename inside Memoshi Notes (e.g. 'project-plan.md').",
          ],
          "content": ["type": "string", "maxLength": 200_000],
        ],
        "required": ["filename", "content"],
        "additionalProperties": false,
      ],
      operation: .connectorStage,
      replaySafe: false,
      outputExposure: Exposure(untrusted: false, privateData: true),
      authorize: { _ in true },
      execute: { arguments, _ in
        guard case .object(let values) = arguments,
          let filename = stringArg(values["filename"]),
          let content = stringArg(values["content"])
        else {
          throw RuntimeToolError.invalidArguments
        }
        let saved = try store.save(filename: filename, content: content)
        return RuntimeToolResult(
          text: "Saved note '\(saved.filename)' (\(saved.byteCount) bytes) in Memoshi Notes."
        )
      }
    )
  }

  // MARK: - Mail Tools (Draft-Safe, Provider REST Only, Untrusted Exposure per D116/D118)

  private static func mailListTool(store: MailHostStore) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "mail_list",
      description:
        "List recent email messages from a connected Gmail or Microsoft 365 account (read-only).",
      parameters: [
        "type": "object",
        "properties": [
          "account": ["type": "string", "maxLength": 160],
          "limit": ["type": "integer", "minimum": 1, "maximum": 30],
        ],
        "additionalProperties": false,
      ],
      operation: .mailRead,
      replaySafe: true,
      outputExposure: Exposure(untrusted: true, privateData: true),
      authorize: { _ in true },
      execute: { arguments, invocation in
        guard case .object(let values) = arguments else {
          throw RuntimeToolError.invalidArguments
        }
        let limit = max(1, min(30, intArg(values["limit"]) ?? 10))
        guard let account = store.resolveAccount(stringArg(values["account"])),
          let token = MailTokenKeychain.readToken(for: account.id), !token.isEmpty
        else {
          return RuntimeToolResult(
            text:
              "No Gmail or Microsoft 365 account token is connected yet. Ask the user to connect an account in My Apps → Mail.",
            isError: true,
            effectOutcome: .notApplied
          )
        }
        return try await invocation.runCancellable {
          let messages = try await MailProviderHTTPClient.listMessages(
            account: account, token: token, query: nil, limit: limit)
          if messages.isEmpty {
            return RuntimeToolResult(text: "No messages found in \(account.emailAddress).")
          }
          let lines = messages.map { msg in
            "- [\(msg.id)] \(msg.subject) | From: \(msg.from) | \(msg.date)\n  \(String(msg.snippet.prefix(160)))"
          }
          return RuntimeToolResult(
            text: "Recent messages in \(account.emailAddress):\n" + lines.joined(separator: "\n")
          )
        }
      }
    )
  }

  private static func mailSearchTool(store: MailHostStore) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "mail_search",
      description: "Search email messages in a connected Gmail or Microsoft 365 account.",
      parameters: [
        "type": "object",
        "properties": [
          "query": ["type": "string", "minLength": 1, "maxLength": 240],
          "account": ["type": "string", "maxLength": 160],
          "limit": ["type": "integer", "minimum": 1, "maximum": 30],
        ],
        "required": ["query"],
        "additionalProperties": false,
      ],
      operation: .mailRead,
      replaySafe: true,
      outputExposure: Exposure(untrusted: true, privateData: true),
      authorize: { _ in true },
      execute: { arguments, invocation in
        guard case .object(let values) = arguments,
          let query = stringArg(values["query"])?.trimmingCharacters(in: .whitespacesAndNewlines),
          !query.isEmpty
        else {
          throw RuntimeToolError.invalidArguments
        }
        let limit = max(1, min(30, intArg(values["limit"]) ?? 10))
        guard let account = store.resolveAccount(stringArg(values["account"])),
          let token = MailTokenKeychain.readToken(for: account.id), !token.isEmpty
        else {
          return RuntimeToolResult(
            text:
              "No Gmail or Microsoft 365 account token is connected yet. Ask the user to connect an account in My Apps → Mail.",
            isError: true,
            effectOutcome: .notApplied
          )
        }
        return try await invocation.runCancellable {
          let messages = try await MailProviderHTTPClient.listMessages(
            account: account, token: token, query: query, limit: limit)
          if messages.isEmpty {
            return RuntimeToolResult(text: "No messages matched '\(query)'.")
          }
          let lines = messages.map { msg in
            "- [\(msg.id)] \(msg.subject) | From: \(msg.from) | \(msg.date)\n  \(String(msg.snippet.prefix(160)))"
          }
          return RuntimeToolResult(
            text: "Found \(messages.count) message(s) for '\(query)':\n"
              + lines.joined(separator: "\n")
          )
        }
      }
    )
  }

  private static func mailReadTool(store: MailHostStore) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "mail_read",
      description: "Read a single email message by ID from a connected Gmail or Microsoft 365 account.",
      parameters: [
        "type": "object",
        "properties": [
          "messageId": ["type": "string", "minLength": 1, "maxLength": 240],
          "account": ["type": "string", "maxLength": 160],
        ],
        "required": ["messageId"],
        "additionalProperties": false,
      ],
      operation: .mailRead,
      replaySafe: true,
      outputExposure: Exposure(untrusted: true, privateData: true),
      authorize: { _ in true },
      execute: { arguments, invocation in
        guard case .object(let values) = arguments,
          let messageID = stringArg(values["messageId"])?.trimmingCharacters(
            in: .whitespacesAndNewlines),
          !messageID.isEmpty
        else {
          throw RuntimeToolError.invalidArguments
        }
        guard let account = store.resolveAccount(stringArg(values["account"])),
          let token = MailTokenKeychain.readToken(for: account.id), !token.isEmpty
        else {
          return RuntimeToolResult(
            text:
              "No Gmail or Microsoft 365 account token is connected yet. Ask the user to connect an account in My Apps → Mail.",
            isError: true,
            effectOutcome: .notApplied
          )
        }
        return try await invocation.runCancellable {
          let body = try await MailProviderHTTPClient.readMessage(
            account: account, token: token, messageID: messageID)
          return RuntimeToolResult(text: body)
        }
      }
    )
  }

  private static func mailDraftTool(store: MailHostStore) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "mail_draft",
      description:
        "Prepare a reviewable email draft (never sends automatically). Saves to Memoshi's Mail pane and, when connected, creates a remote Draft in Gmail or Microsoft 365.",
      parameters: [
        "type": "object",
        "properties": [
          "to": [
            "type": "array",
            "items": ["type": "string", "minLength": 3, "maxLength": 240],
            "minItems": 1,
            "maxItems": 25,
          ],
          "cc": [
            "type": "array",
            "items": ["type": "string", "minLength": 3, "maxLength": 240],
            "maxItems": 25,
          ],
          "subject": ["type": "string", "minLength": 1, "maxLength": 300],
          "body": ["type": "string", "minLength": 1, "maxLength": 50_000],
          "replyToMessageId": ["type": "string", "maxLength": 240],
          "account": ["type": "string", "maxLength": 160],
        ],
        "required": ["to", "subject", "body"],
        "additionalProperties": false,
      ],
      operation: .mailStage,
      replaySafe: false,
      outputExposure: Exposure(untrusted: true, privateData: true),
      authorize: { _ in true },
      execute: { arguments, invocation in
        guard case .object(let values) = arguments,
          let toList = stringArrayArg(values["to"]), !toList.isEmpty,
          let subject = stringArg(values["subject"])?.trimmingCharacters(in: .whitespacesAndNewlines),
          !subject.isEmpty,
          let body = stringArg(values["body"])
        else {
          throw RuntimeToolError.invalidArguments
        }
        let ccList = stringArrayArg(values["cc"]) ?? []
        let replyID = stringArg(values["replyToMessageId"])
        let account = store.resolveAccount(stringArg(values["account"]))

        return try await invocation.runCancellable {
          var draft = MailDraftRecord(
            accountID: account?.id,
            to: toList,
            cc: ccList,
            subject: subject,
            body: body,
            replyToMessageID: replyID
          )
          var remoteNote = "Saved locally in My Apps → Mail for your review (not sent)."
          if let account, let token = MailTokenKeychain.readToken(for: account.id), !token.isEmpty {
            if let remoteID = try? await MailProviderHTTPClient.createRemoteDraft(
              account: account, token: token, draft: draft)
            {
              draft.remoteDraftID = remoteID
              remoteNote =
                "Saved as a \(account.provider.displayName) Draft (remote id: \(remoteID)) and in My Apps → Mail (not sent)."
            }
          }
          try store.saveDraft(draft)
          return RuntimeToolResult(
            text:
              "Staged draft '\(subject)' to \(toList.joined(separator: ", ")) (draft id: \(draft.id)). \(remoteNote)"
          )
        }
      }
    )
  }

  private static func mailOrganizeTool(store: MailHostStore) -> RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: "mail_organize",
      description:
        "Perform a reversible mailbox tidy action (archive, unarchive, mark_read, mark_unread, star, unstar) and record an undoable audit entry.",
      parameters: [
        "type": "object",
        "properties": [
          "messageId": ["type": "string", "minLength": 1, "maxLength": 240],
          "action": [
            "type": "string",
            "enum": ["archive", "unarchive", "mark_read", "mark_unread", "star", "unstar"],
          ],
          "account": ["type": "string", "maxLength": 160],
        ],
        "required": ["messageId", "action"],
        "additionalProperties": false,
      ],
      operation: .mailOrganize,
      replaySafe: false,
      outputExposure: Exposure(untrusted: true, privateData: true),
      authorize: { _ in true },
      execute: { arguments, invocation in
        guard case .object(let values) = arguments,
          let messageID = stringArg(values["messageId"])?.trimmingCharacters(
            in: .whitespacesAndNewlines),
          !messageID.isEmpty,
          let rawAction = stringArg(values["action"]),
          let action = MailOrganizeAction(rawValue: rawAction)
        else {
          throw RuntimeToolError.invalidArguments
        }
        guard let account = store.resolveAccount(stringArg(values["account"])),
          let token = MailTokenKeychain.readToken(for: account.id), !token.isEmpty
        else {
          return RuntimeToolResult(
            text:
              "No Gmail or Microsoft 365 account token is connected yet. Connect an account in My Apps → Mail before organizing messages.",
            isError: true,
            effectOutcome: .notApplied
          )
        }
        return try await invocation.runCancellable {
          try await MailProviderHTTPClient.organizeMessage(
            account: account, token: token, messageID: messageID, action: action)
          let audit = MailOrganizeAuditEntry(
            accountID: account.id, messageID: messageID, action: action)
          try? store.appendOrganizeAudit(audit)
          return RuntimeToolResult(
            text:
              "Applied '\(action.rawValue)' to message \(messageID) in \(account.emailAddress) (reversible via '\(action.inverse.rawValue)', audit id: \(audit.id))."
          )
        }
      }
    )
  }

  // MARK: - Argument Helpers

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

  private static func stringArrayArg(_ value: MemoshiProtocol.JSONValue?) -> [String]? {
    guard case .array(let items)? = value else { return nil }
    var result: [String] = []
    for item in items {
      guard case .string(let s) = item else { return nil }
      let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { result.append(trimmed) }
    }
    return result
  }
}
