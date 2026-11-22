import AppKit
import DesignSystem
import Foundation
import MemoshiProtocol
import Observation
import SwiftUI

/// A user-saved link or conversation message stored locally in the Mac workspace.
struct WorkspaceBookmark: Codable, Hashable, Identifiable, Sendable {
  enum Kind: String, Codable, Hashable, Sendable {
    case link
    case message
  }

  let id: String
  let kind: Kind
  let title: String
  let subtitle: String?
  let urlString: String?
  let botName: String
  let conversationID: String?
  let savedAt: Date

  var url: URL? {
    guard let urlString, let parsed = URL(string: urlString),
      let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https"
    else { return nil }
    return parsed
  }
}

/// Persisted bookmarks for links and messages surfaced across conversations and the Bookmarks pane.
@MainActor
@Observable
final class WorkspaceBookmarksStore {
  private static let storageKey = "workspace.bookmarks.v1"

  private(set) var items: [WorkspaceBookmark] = []
  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.storageKey),
      let decoded = try? JSONDecoder().decode([WorkspaceBookmark].self, from: data)
    {
      self.items = decoded.sorted { $0.savedAt > $1.savedAt }
    }
  }

  func isLinkBookmarked(_ url: URL) -> Bool {
    let key = Self.linkID(for: url)
    return items.contains { $0.id == key }
  }

  func isMessageBookmarked(_ messageID: String) -> Bool {
    let key = Self.messageIDKey(for: messageID)
    return items.contains { $0.id == key }
  }

  func toggleLink(
    url: URL, title: String? = nil, subtitle: String? = nil, botName: String,
    conversationID: String?
  ) {
    let key = Self.linkID(for: url)
    if let index = items.firstIndex(where: { $0.id == key }) {
      items.remove(at: index)
    } else {
      let host = url.host() ?? url.absoluteString
      let bookmark = WorkspaceBookmark(
        id: key,
        kind: .link,
        title: title?.isEmpty == false ? title! : host,
        subtitle: subtitle ?? url.absoluteString,
        urlString: url.absoluteString,
        botName: botName,
        conversationID: conversationID,
        savedAt: Date()
      )
      items.insert(bookmark, at: 0)
    }
    persist()
  }

  func toggleMessage(
    messageID: String, text: String, botName: String, conversationID: String?
  ) {
    let key = Self.messageIDKey(for: messageID)
    if let index = items.firstIndex(where: { $0.id == key }) {
      items.remove(at: index)
    } else {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
      let title = firstLine.count > 90 ? String(firstLine.prefix(90)) + "…" : firstLine
      let bookmark = WorkspaceBookmark(
        id: key,
        kind: .message,
        title: title.isEmpty ? String(localized: "Saved message") : title,
        subtitle: trimmed.count > 240 ? String(trimmed.prefix(240)) + "…" : trimmed,
        urlString: nil,
        botName: botName,
        conversationID: conversationID,
        savedAt: Date()
      )
      items.insert(bookmark, at: 0)
    }
    persist()
  }

  func remove(id: String) {
    items.removeAll { $0.id == id }
    persist()
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(items) {
      defaults.set(data, forKey: Self.storageKey)
    }
  }

  private static func linkID(for url: URL) -> String {
    "link:" + url.absoluteString.lowercased()
  }

  private static func messageIDKey(for messageID: String) -> String {
    "msg:" + messageID
  }
}

/// An HTTP/HTTPS URL extracted from live messages in the active conversation.
struct ExtractedConversationLink: Identifiable, Hashable, Sendable {
  let id: String
  let url: URL
  let host: String
  let displayPath: String
  let contextSnippet: String
  let senderLabel: String
  let timestamp: Date?

  static func extract(from messages: [ChatMessage], senderName: String)
    -> [ExtractedConversationLink]
  {
    guard
      let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue)
    else { return [] }

    var seen = Set<String>()
    var results: [ExtractedConversationLink] = []

    for message in messages.reversed() {
      let text = message.content.reduce(into: "") { acc, part in
        if case .text(let t) = part { acc.append(t.text) }
      }
      guard !text.isEmpty else { continue }
      let nsText = text as NSString
      let range = NSRange(location: 0, length: nsText.length)
      let matches = detector.matches(in: text, options: [], range: range)
      for match in matches.reversed() {
        guard let url = match.url,
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https"
        else { continue }
        let normalized = url.absoluteString
        guard seen.insert(normalized.lowercased()).inserted else { continue }

        let host = url.host() ?? normalized
        let rawPath = url.path
        let displayPath: String
        if rawPath.isEmpty || rawPath == "/" {
          displayPath = host
        } else {
          let cleaned = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
          displayPath = cleaned.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        }

        let snippet = extractSnippet(around: match.range, in: nsText)
        let sender =
          message.role == .user ? String(localized: "Your message") : senderName
        let date =
          message.createdAt > 0
          ? Date(timeIntervalSince1970: TimeInterval(message.createdAt) / 1_000.0) : nil

        results.append(
          ExtractedConversationLink(
            id: "\(message.id.rawValue):\(normalized)",
            url: url,
            host: host,
            displayPath: displayPath,
            contextSnippet: snippet,
            senderLabel: sender,
            timestamp: date
          )
        )
      }
    }
    return results
  }

  private static func extractSnippet(around range: NSRange, in text: NSString) -> String {
    let start = max(0, range.location - 48)
    let end = min(text.length, range.location + range.length + 72)
    let raw = text.substring(with: NSRange(location: start, length: end - start))
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if start > 0 && end < text.length {
      return "…\(raw)…"
    } else if start > 0 {
      return "…\(raw)"
    } else if end < text.length {
      return "\(raw)…"
    }
    return raw
  }
}

/// Local avatar symbol and accent color customization per real bot (`BOT-03`).
struct BotAppearance: Codable, Hashable, Sendable {
  var symbol: String
  var paletteID: String
}

struct BotColorPalette: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  let topRed: Double
  let topGreen: Double
  let topBlue: Double
  let bottomRed: Double
  let bottomGreen: Double
  let bottomBlue: Double

  var gradient: [Color] {
    [
      Color(red: topRed, green: topGreen, blue: topBlue),
      Color(red: bottomRed, green: bottomGreen, blue: bottomBlue),
    ]
  }

  static let all: [BotColorPalette] = [
    BotColorPalette(
      id: "teal", name: "Teal",
      topRed: 0.16, topGreen: 0.68, topBlue: 0.56,
      bottomRed: 0.10, bottomGreen: 0.44, bottomBlue: 0.48),
    BotColorPalette(
      id: "cobalt", name: "Cobalt",
      topRed: 0.24, topGreen: 0.52, topBlue: 0.92,
      bottomRed: 0.16, bottomGreen: 0.34, bottomBlue: 0.72),
    BotColorPalette(
      id: "violet", name: "Violet",
      topRed: 0.52, topGreen: 0.34, topBlue: 0.88,
      bottomRed: 0.32, bottomGreen: 0.18, bottomBlue: 0.62),
    BotColorPalette(
      id: "amber", name: "Amber",
      topRed: 0.95, topGreen: 0.68, topBlue: 0.24,
      bottomRed: 0.80, bottomGreen: 0.48, bottomBlue: 0.14),
    BotColorPalette(
      id: "coral", name: "Coral",
      topRed: 0.96, topGreen: 0.27, topBlue: 0.44,
      bottomRed: 0.82, bottomGreen: 0.15, bottomBlue: 0.34),
    BotColorPalette(
      id: "emerald", name: "Emerald",
      topRed: 0.18, topGreen: 0.72, topBlue: 0.44,
      bottomRed: 0.10, bottomGreen: 0.48, bottomBlue: 0.30),
    BotColorPalette(
      id: "indigo", name: "Indigo",
      topRed: 0.31, topGreen: 0.40, topBlue: 0.85,
      bottomRed: 0.18, bottomGreen: 0.24, bottomBlue: 0.58),
    BotColorPalette(
      id: "slate", name: "Slate",
      topRed: 0.42, topGreen: 0.46, topBlue: 0.56,
      bottomRed: 0.28, bottomGreen: 0.30, bottomBlue: 0.38),
  ]

  static func named(_ id: String) -> BotColorPalette? {
    all.first { $0.id == id }
  }
}

@MainActor
@Observable
final class BotAppearanceStore {
  private static let storageKey = "workspace.botAppearances.v1"

  static let symbolOptions: [String] = [
    "sparkles",
    "brain",
    "hammer.fill",
    "book.closed.fill",
    "checkmark.seal.fill",
    "chevron.left.forwardslash.chevron.right",
    "magnifyingglass",
    "link",
    "envelope.fill",
    "calendar",
    "checklist",
    "heart.fill",
    "cloud.sun.fill",
    "terminal.fill",
  ]

  private(set) var appearances: [String: BotAppearance] = [:]
  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.storageKey),
      let decoded = try? JSONDecoder().decode([String: BotAppearance].self, from: data)
    {
      self.appearances = decoded
    }
  }

  func appearance(for botID: BotID, isAssistant: Bool = false) -> (symbol: String, gradient: [Color])
  {
    if let saved = appearances[botID.rawValue] {
      let palette = BotColorPalette.named(saved.paletteID) ?? defaultPalette(for: botID.rawValue)
      return (saved.symbol, palette.gradient)
    }
    if isAssistant {
      return ("sparkles", BotColorPalette.all[0].gradient)
    }
    return ("sparkles", defaultPalette(for: botID.rawValue).gradient)
  }

  func savedAppearance(for botID: BotID, isAssistant: Bool = false) -> BotAppearance {
    if let saved = appearances[botID.rawValue] { return saved }
    let palette = isAssistant ? BotColorPalette.all[0] : defaultPalette(for: botID.rawValue)
    return BotAppearance(symbol: "sparkles", paletteID: palette.id)
  }

  func setAppearance(_ appearance: BotAppearance, for botID: BotID) {
    appearances[botID.rawValue] = appearance
    if let data = try? JSONEncoder().encode(appearances) {
      defaults.set(data, forKey: Self.storageKey)
    }
  }

  private func defaultPalette(for key: String) -> BotColorPalette {
    let sum = key.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
    return BotColorPalette.all[abs(sum) % BotColorPalette.all.count]
  }
}

/// Full native Bookmarks pane wired from the left sidebar (`SH-07`).
struct BookmarksPaneView: View {
  let bookmarks: WorkspaceBookmarksStore
  var onOpenConversation: (ConversationID) -> Void

  enum Filter: String, CaseIterable, Identifiable {
    case all = "All"
    case links = "Links"
    case messages = "Messages"
    var id: String { rawValue }
  }

  @State private var filter: Filter = .all
  @State private var searchQuery = ""

  private var filteredItems: [WorkspaceBookmark] {
    let byKind: [WorkspaceBookmark] =
      switch filter {
      case .all: bookmarks.items
      case .links: bookmarks.items.filter { $0.kind == .link }
      case .messages: bookmarks.items.filter { $0.kind == .message }
      }
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return byKind }
    return byKind.filter { item in
      item.title.localizedCaseInsensitiveContains(query)
        || (item.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        || item.botName.localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Bookmarks")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
          Text("\(bookmarks.items.count) saved")
            .font(.system(size: 12))
            .foregroundStyle(WarmShellColors.mutedText)
        }
        Spacer()
        Picker("Filter", selection: $filter) {
          ForEach(Filter.allCases) { tab in
            Text(tab.rawValue).tag(tab)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
      }
      .padding(.horizontal, 28)
      .padding(.top, 22)
      .padding(.bottom, 14)

      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 13))
          .foregroundStyle(WarmShellColors.mutedText)
        TextField(
          "Filter bookmarks", text: $searchQuery,
          prompt: Text("Filter bookmarks").foregroundStyle(WarmShellColors.mutedText)
        )
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(WarmShellColors.primaryText)
        if !searchQuery.isEmpty {
          Button {
            searchQuery = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 12.5))
              .foregroundStyle(WarmShellColors.mutedText)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 12)
      .frame(height: 34)
      .background(WarmShellColors.card, in: Capsule())
      .overlay(Capsule().stroke(WarmShellColors.cardBorder, lineWidth: 1))
      .padding(.horizontal, 28)
      .padding(.bottom, 16)

      Divider().overlay(WarmShellColors.divider)

      if filteredItems.isEmpty {
        ContentUnavailableView {
          Label(
            bookmarks.items.isEmpty ? "No Bookmarks Yet" : "No Matching Bookmarks",
            systemImage: "bookmark")
        } description: {
          Text(
            bookmarks.items.isEmpty
              ? "Bookmark messages from any conversation or links from the Links sidebar to keep them here."
              : "Try a different filter or search query."
          )
          .foregroundStyle(WarmShellColors.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(filteredItems) { item in
              bookmarkCard(item)
            }
          }
          .frame(maxWidth: 720)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 28)
          .padding(.vertical, 18)
        }
      }
    }
    .background(WarmShellColors.canvas)
    .accessibilityIdentifier("workspace.bookmarks")
  }

  private func bookmarkCard(_ item: WorkspaceBookmark) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: item.kind == .link ? "link" : "text.quote")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(WarmShellColors.badgeText)
          .frame(width: 28, height: 28)
          .background(WarmShellColors.badgeFill, in: Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(verbatim: item.title)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
            .lineLimit(2)
          if let subtitle = item.subtitle, !subtitle.isEmpty {
            Text(verbatim: subtitle)
              .font(.system(size: 12))
              .foregroundStyle(WarmShellColors.mutedText)
              .lineLimit(3)
          }
          HStack(spacing: 6) {
            Text(verbatim: item.botName)
            Text("·")
            Text(item.savedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
          }
          .font(.system(size: 11))
          .foregroundStyle(WarmShellColors.mutedText.opacity(0.85))
          .padding(.top, 2)
        }
        Spacer(minLength: 8)
      }

      HStack(spacing: 8) {
        if let url = item.url {
          Button {
            NSWorkspace.shared.open(url)
          } label: {
            Label("Open", systemImage: "safari")
              .font(.system(size: 11.5, weight: .medium))
          }
          .buttonStyle(.plain)
          .foregroundStyle(WarmShellColors.badgeText)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(WarmShellColors.badgeFill, in: Capsule())
        }

        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(
            item.urlString ?? item.subtitle ?? item.title, forType: .string)
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
            .font(.system(size: 11.5, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(WarmShellColors.primaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(WarmShellColors.pill, in: Capsule())

        if let rawID = item.conversationID, let convID = try? ConversationID(rawID) {
          Button {
            onOpenConversation(convID)
          } label: {
            Label("Go to Chat", systemImage: "arrow.right.circle")
              .font(.system(size: 11.5, weight: .medium))
          }
          .buttonStyle(.plain)
          .foregroundStyle(WarmShellColors.primaryText)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(WarmShellColors.pill, in: Capsule())
        }

        Spacer()

        Button(role: .destructive) {
          bookmarks.remove(id: item.id)
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 12))
            .foregroundStyle(WarmShellColors.mutedText)
        }
        .buttonStyle(.plain)
        .help("Remove Bookmark")
      }
    }
    .padding(14)
    .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(WarmShellColors.cardBorder, lineWidth: 1)
    )
  }
}
