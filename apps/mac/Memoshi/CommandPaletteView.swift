import AppKit
import DesignSystem
import Foundation
import MemoshiProtocol
import SwiftUI

/// Categories shown inside the ⌘K Command Palette (SH-09).
enum CommandPaletteCategory: String, CaseIterable, Hashable, Sendable {
  case ask = "Quick Ask"
  case conversations = "Conversations"
  case workspaces = "Workspaces"
  case apps = "My Apps"
  case actions = "Actions"
}

/// One searchable entry in the Command Palette.
struct CommandPaletteItem: Identifiable, Hashable, Sendable {
  let id: String
  let title: String
  let subtitle: String?
  let symbol: String
  let category: CommandPaletteCategory
  let keywords: [String]
}

/// Pure, deterministic matcher ranking exact and prefix hits ahead of substring matches.
enum CommandPaletteMatcher {
  static func filter(_ items: [CommandPaletteItem], query: String) -> [CommandPaletteItem] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return items }
    let needle = trimmed.lowercased()
    let scored: [(item: CommandPaletteItem, score: Int)] = items.compactMap { item in
      let title = item.title.lowercased()
      let subtitle = (item.subtitle ?? "").lowercased()
      let keywords = item.keywords.map { $0.lowercased() }
      if title == needle {
        return (item, 0)
      }
      if title.hasPrefix(needle) {
        return (item, 1)
      }
      if title.contains(needle) {
        return (item, 2)
      }
      if keywords.contains(where: { $0.hasPrefix(needle) }) {
        return (item, 3)
      }
      if subtitle.contains(needle) || keywords.contains(where: { $0.contains(needle) }) {
        return (item, 4)
      }
      return nil
    }
    return scored.sorted { lhs, rhs in
      if lhs.score != rhs.score { return lhs.score < rhs.score }
      return lhs.item.title.localizedCaseInsensitiveCompare(rhs.item.title) == .orderedAscending
    }.map(\.item)
  }
}

/// Floating ⌘K Command Palette overlay for switching conversations, apps, and workspace actions.
struct CommandPaletteOverlay: View {
  let model: LiveChatModel
  let navigation: LiveWorkspaceNavigation
  @Binding var isSidebarPresented: Bool
  @Binding var rightSidebarMode: RightSidebarMode?
  @Binding var selectedMockBot: ShellExampleBot?
  var onNewBot: () -> Void
  var onNewSession: () -> Void
  var onOpenModelSettings: () -> Void
  var onOpenFolders: () -> Void
  var onOpenTasks: () -> Void
  var onOpenQuickEntry: () -> Void
  var onOpenBackgroundSettings: (() -> Void)? = nil
  var onDismiss: () -> Void

  @State private var query = ""
  @State private var selectedIndex = 0
  @FocusState private var isSearchFocused: Bool

  private var activeBotName: String {
    model.chat?.title ?? String(localized: "Assistant")
  }

  private var staticItems: [CommandPaletteItem] {
    var items: [CommandPaletteItem] = []

    for conv in model.directory.conversations {
      let subtitle: String =
        switch conv.kind {
        case .assistant: String(localized: "Assistant")
        case .bot: String(localized: "Bot")
        case .session: String(localized: "Session")
        case .unknown(let raw): raw
        }
      let symbol = conv.kind == .session ? "text.bubble" : "sparkles"
      items.append(
        CommandPaletteItem(
          id: "conv:\(conv.id.rawValue)",
          title: conv.title,
          subtitle: subtitle,
          symbol: symbol,
          category: .conversations,
          keywords: ["chat", "bot", "conversation", subtitle]
        )
      )
    }

    items.append(contentsOf: [
      CommandPaletteItem(
        id: "ws:today",
        title: String(localized: "Today"),
        subtitle: String(localized: "Calendar, Reminders, and active tasks"),
        symbol: "sun.max",
        category: .workspaces,
        keywords: ["schedule", "agenda", "morning", "daily"]
      ),
      CommandPaletteItem(
        id: "ws:waiting",
        title: String(localized: "Waiting for You"),
        subtitle: "\(model.reviews.pendingCount) pending",
        symbol: "hand.raised",
        category: .workspaces,
        keywords: ["approvals", "cards", "review", "pending"]
      ),
      CommandPaletteItem(
        id: "ws:bookmarks",
        title: String(localized: "Bookmarks"),
        subtitle: String(localized: "Saved links and messages"),
        symbol: "bookmark",
        category: .workspaces,
        keywords: ["saved", "links", "stars"]
      ),
      CommandPaletteItem(
        id: "ws:myApps",
        title: String(localized: "My Apps"),
        subtitle: String(localized: "Mail, Calendar, Reminders, Contacts, Notes, Files, Connectors"),
        symbol: "square.grid.2x2",
        category: .workspaces,
        keywords: ["apps", "hub", "apple", "mail", "connectors", "search"]
      ),
    ])

    for tab in BuiltInAppTab.allCases {
      items.append(
        CommandPaletteItem(
          id: "app:\(tab.rawValue)",
          title: tab.rawValue,
          subtitle: String(localized: "My Apps"),
          symbol: tab.symbol,
          category: .apps,
          keywords: ["app", "my apps", tab.rawValue]
        )
      )
    }

    items.append(contentsOf: [
      CommandPaletteItem(
        id: "act:quickEntry",
        title: String(localized: "Open Quick Entry"),
        subtitle: "⌥⇧Space",
        symbol: "bolt.fill",
        category: .actions,
        keywords: ["prompt", "floating", "hotkey", "capture"]
      ),
      CommandPaletteItem(
        id: "act:newBot",
        title: String(localized: "New Bot…"),
        subtitle: String(localized: "Create a bot profile"),
        symbol: "person.badge.plus",
        category: .actions,
        keywords: ["create", "bot", "agent"]
      ),
      CommandPaletteItem(
        id: "act:newSession",
        title: String(localized: "New Session…"),
        subtitle: String(localized: "Start a separate conversation thread"),
        symbol: "square.and.pencil",
        category: .actions,
        keywords: ["create", "thread", "chat"]
      ),
      CommandPaletteItem(
        id: "act:modelSettings",
        title: String(localized: "Model Settings…"),
        subtitle: String(localized: "Providers, Claude Code, API keys, and default model"),
        symbol: "slider.horizontal.3",
        category: .actions,
        keywords: ["openai", "anthropic", "claude", "claude-code", "gemini", "provider", "key"]
      ),
      CommandPaletteItem(
        id: "act:backgroundService",
        title: String(localized: "Background Service Settings…"),
        subtitle: String(localized: "Manage memoshid LaunchAgent persistence"),
        symbol: "checkmark.shield",
        category: .actions,
        keywords: ["launchagent", "smappservice", "daemon", "background", "login items"]
      ),
      CommandPaletteItem(
        id: "act:folders",
        title: String(localized: "Folder Grants…"),
        subtitle: String(localized: "Manage folders shared with your Assistant"),
        symbol: "folder.badge.gearshape",
        category: .actions,
        keywords: ["files", "library", "permissions", "disk"]
      ),
      CommandPaletteItem(
        id: "act:tasks",
        title: String(localized: "Open Tasks Window"),
        subtitle: String(localized: "Inspect durable task graphs"),
        symbol: "list.bullet.indent",
        category: .actions,
        keywords: ["jobs", "graph", "background"]
      ),
      CommandPaletteItem(
        id: "act:toggleSidebar",
        title: isSidebarPresented
          ? String(localized: "Hide Left Sidebar") : String(localized: "Show Left Sidebar"),
        subtitle: "⌃⌘S",
        symbol: "sidebar.left",
        category: .actions,
        keywords: ["panel", "navigation"]
      ),
      CommandPaletteItem(
        id: "act:rightActivity",
        title: String(localized: "Show Activity Sidebar"),
        subtitle: String(localized: "Recent runtime steps and reminders"),
        symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
        category: .actions,
        keywords: ["right", "inspector", "log"]
      ),
      CommandPaletteItem(
        id: "act:rightLinks",
        title: String(localized: "Show Links Sidebar"),
        subtitle: String(localized: "Extracted links from this chat"),
        symbol: "link",
        category: .actions,
        keywords: ["urls", "right", "web"]
      ),
      CommandPaletteItem(
        id: "act:rightSplit",
        title: String(localized: "Show Split Chat Sidebar"),
        subtitle: String(localized: "Side-by-side bot view"),
        symbol: "rectangle.split.2x1",
        category: .actions,
        keywords: ["split", "duo", "two"]
      ),
    ])

    return items
  }

  private var visibleItems: [CommandPaletteItem] {
    var filtered = CommandPaletteMatcher.filter(staticItems, query: query)
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty && model.connection == .connected {
      let askItem = CommandPaletteItem(
        id: "ask:\(trimmed)",
        title: String(localized: "Ask \(activeBotName): “\(trimmed)”"),
        subtitle: String(localized: "Send directly to active conversation"),
        symbol: "paperplane.fill",
        category: .ask,
        keywords: []
      )
      filtered.append(askItem)
    }
    return filtered
  }

  var body: some View {
    ZStack(alignment: .top) {
      Color.black.opacity(0.24)
        .ignoresSafeArea()
        .onTapGesture { onDismiss() }

      VStack(spacing: 0) {
        searchRow
        Divider().overlay(WarmShellColors.divider)
        resultsList
        Divider().overlay(WarmShellColors.divider)
        footerHints
      }
      .frame(width: 560)
      .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(WarmShellColors.cardBorder, lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
      .padding(.top, 76)
      .accessibilityIdentifier("workspace.commandPalette")
    }
    .onAppear {
      selectedIndex = 0
      isSearchFocused = true
    }
    .onChange(of: query) { _, _ in
      selectedIndex = 0
    }
    .onKeyPress(.escape) {
      onDismiss()
      return .handled
    }
    .onKeyPress(.downArrow) {
      moveSelection(by: 1)
      return .handled
    }
    .onKeyPress(.upArrow) {
      moveSelection(by: -1)
      return .handled
    }
  }

  private var searchRow: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(WarmShellColors.badgeText)
      TextField(
        "Jump to bot, app, or action…",
        text: $query,
        prompt: Text("Jump to bot, app, or action…").foregroundStyle(WarmShellColors.mutedText)
      )
      .textFieldStyle(.plain)
      .font(.system(size: 15))
      .foregroundStyle(WarmShellColors.primaryText)
      .focused($isSearchFocused)
      .onSubmit {
        let items = visibleItems
        guard items.indices.contains(selectedIndex) else { return }
        execute(items[selectedIndex])
      }
      .accessibilityIdentifier("commandPalette.field")

      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 13))
            .foregroundStyle(WarmShellColors.mutedText)
        }
        .buttonStyle(.plain)
      }

      Text("⌘K")
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(WarmShellColors.mutedText)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(WarmShellColors.pill, in: RoundedRectangle(cornerRadius: 6))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
  }

  private var resultsList: some View {
    let items = visibleItems
    return Group {
      if items.isEmpty {
        Text("No matching commands or conversations.")
          .font(.system(size: 13))
          .foregroundStyle(WarmShellColors.mutedText)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 30)
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
              ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isSelected = index == selectedIndex
                Button {
                  execute(item)
                } label: {
                  HStack(spacing: 11) {
                    Image(systemName: item.symbol)
                      .font(.system(size: 13.5, weight: .medium))
                      .foregroundStyle(
                        isSelected ? WarmShellColors.badgeText : WarmShellColors.mutedText
                      )
                      .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                      Text(verbatim: item.title)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(WarmShellColors.primaryText)
                        .lineLimit(1)
                      if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle)
                          .font(.system(size: 11.5))
                          .foregroundStyle(WarmShellColors.mutedText)
                          .lineLimit(1)
                      }
                    }
                    Spacer()
                    Text(item.category.rawValue)
                      .font(.system(size: 10.5, weight: .medium))
                      .foregroundStyle(WarmShellColors.mutedText)
                  }
                  .padding(.horizontal, 12)
                  .padding(.vertical, 8)
                  .background(
                    isSelected ? WarmShellColors.badgeFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10)
                  )
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(item.id)
                .onHover { hovering in
                  if hovering { selectedIndex = index }
                }
              }
            }
            .padding(8)
          }
          .frame(maxHeight: 340)
          .onChange(of: selectedIndex) { _, newIndex in
            if items.indices.contains(newIndex) {
              proxy.scrollTo(items[newIndex].id, anchor: .center)
            }
          }
        }
      }
    }
  }

  private var footerHints: some View {
    HStack(spacing: 14) {
      Text("↑↓ Navigate")
      Text("↵ Open")
      Text("Esc Close")
      Spacer()
      Text("\(visibleItems.count) items")
    }
    .font(.system(size: 11))
    .foregroundStyle(WarmShellColors.mutedText)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  private func moveSelection(by delta: Int) {
    let count = visibleItems.count
    guard count > 0 else { return }
    selectedIndex = (selectedIndex + delta + count) % count
  }

  private func execute(_ item: CommandPaletteItem) {
    onDismiss()
    if item.id.hasPrefix("conv:") {
      let rawID = String(item.id.dropFirst("conv:".count))
      if let convID = try? ConversationID(rawID) {
        navigation.showConversation()
        selectedMockBot = nil
        Task { await model.selectConversation(convID) }
      }
      return
    }
    if item.id.hasPrefix("app:") {
      let rawTab = String(item.id.dropFirst("app:".count))
      if let tab = BuiltInAppTab(rawValue: rawTab) {
        navigation.showMyApps(tab)
      }
      return
    }
    if item.id.hasPrefix("ask:") {
      let prompt = String(item.id.dropFirst("ask:".count))
      navigation.showConversation()
      selectedMockBot = nil
      Task { _ = await model.sendQuickPrompt(prompt, to: nil) }
      return
    }
    switch item.id {
    case "ws:today":
      navigation.showToday()
    case "ws:waiting":
      navigation.showWaiting()
    case "ws:bookmarks":
      navigation.showBookmarks()
    case "ws:myApps":
      navigation.showMyApps()
    case "act:quickEntry":
      onOpenQuickEntry()
    case "act:newBot":
      onNewBot()
    case "act:newSession":
      onNewSession()
    case "act:modelSettings":
      onOpenModelSettings()
    case "act:backgroundService":
      onOpenBackgroundSettings?()
    case "act:folders":
      onOpenFolders()
    case "act:tasks":
      onOpenTasks()
    case "act:toggleSidebar":
      withAnimation(.easeInOut(duration: 0.15)) { isSidebarPresented.toggle() }
    case "act:rightActivity":
      withAnimation(.easeInOut(duration: 0.15)) { rightSidebarMode = .activity }
    case "act:rightLinks":
      withAnimation(.easeInOut(duration: 0.15)) { rightSidebarMode = .links }
    case "act:rightSplit":
      withAnimation(.easeInOut(duration: 0.15)) { rightSidebarMode = .splitChat }
    default:
      break
    }
  }
}
