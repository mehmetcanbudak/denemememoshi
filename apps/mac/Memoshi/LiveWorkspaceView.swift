import AppKit
import AppCore
import DesignSystem
import MemoshiProtocol
import SwiftUI

/// Scene commands forwarded to the live workspace (02 §13.1). The menu and the window share
/// these requests; the window owns the actual keyboard focus.
@MainActor
@Observable
final class LiveWorkspaceNavigation {
  enum ContentDestination: Hashable {
    case conversation
    case today
    case waiting
    case bookmarks
    case myApps
  }

  var destination: ContentDestination = .conversation
  var selectedAppTab: BuiltInAppTab = .calendar
  var isCommandPalettePresented = false

  /// Whether the content pane shows Waiting for You instead of the selected conversation.
  var showsWaiting: Bool {
    get { destination == .waiting }
    set { destination = newValue ? .waiting : .conversation }
  }

  private(set) var nextCardRequest = 0
  private(set) var paneRequest = 0
  private(set) var paneRequestIsForward = true
  private(set) var trashRequest = 0

  /// Shows the active conversation pane.
  func showConversation() { destination = .conversation }

  /// Shows the live Today workspace pane.
  func showToday() { destination = .today }

  /// Shows Waiting for You without moving keyboard focus.
  func showWaiting() { destination = .waiting }

  /// Shows the saved Bookmarks pane.
  func showBookmarks() { destination = .bookmarks }

  /// Shows the My Apps hub, optionally selecting a specific built-in app tab.
  func showMyApps(_ tab: BuiltInAppTab? = nil) {
    if let tab { selectedAppTab = tab }
    destination = .myApps
  }

  /// Toggles the ⌘K Command Palette overlay.
  func toggleCommandPalette() { isCommandPalettePresented.toggle() }

  /// ⌘J: shows Waiting for You and focuses the next pending card, wrapping to the first.
  func focusNextCard() {
    destination = .waiting
    nextCardRequest += 1
  }

  /// F6 / ⌥⌘` (forward) and ⇧F6 / ⇧⌥⌘` (backward) cycle the panes.
  func cyclePane(forward: Bool) {
    paneRequestIsForward = forward
    paneRequest += 1
  }

  /// Opens the existing Move to Trash confirmation for the selected Session.
  func requestTrash() { trashRequest += 1 }
}

/// The one keyboard focus of a live workspace window: a sidebar, a card or the composer.
enum LiveWorkspaceFocus: Hashable {
  case sidebar
  case composer
  case card(CardID)
}

/// Translucent behind-window macOS sidebar material for both Light and Dark Mode.
struct SidebarVisualEffectBackdrop: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .sidebar
    view.blendingMode = .behindWindow
    view.state = .followsWindowActiveState
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Adaptive Light + Dark warm ivory/amber palette for the unified D144 shell.
enum WarmShellColors {
  private static func adaptive(light: NSColor, dark: NSColor) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
      }
    )
  }

  static let canvas = adaptive(
    light: NSColor(srgbRed: 0.984, green: 0.973, blue: 0.945, alpha: 1),       // #FBF8F1
    dark: NSColor(srgbRed: 0.082, green: 0.075, blue: 0.067, alpha: 1))        // #151311
  static let sidebarTint = adaptive(
    light: NSColor(srgbRed: 0.945, green: 0.910, blue: 0.855, alpha: 0.62),
    dark: NSColor(srgbRed: 0.095, green: 0.086, blue: 0.075, alpha: 0.48))
  static let codeBlockBg = adaptive(
    light: NSColor(srgbRed: 0.976, green: 0.976, blue: 0.973, alpha: 1),
    dark: NSColor(srgbRed: 0.106, green: 0.102, blue: 0.094, alpha: 1))
  static let divider = adaptive(
    light: NSColor(srgbRed: 0.898, green: 0.875, blue: 0.827, alpha: 0.9),
    dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
  static let pill = adaptive(
    light: NSColor(srgbRed: 0.918, green: 0.902, blue: 0.871, alpha: 0.85),
    dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.11))
  static let composerPill = adaptive(
    light: NSColor(srgbRed: 0.914, green: 0.906, blue: 0.886, alpha: 0.95),
    dark: NSColor(srgbRed: 0.180, green: 0.169, blue: 0.153, alpha: 0.95))
  static let card = adaptive(
    light: NSColor.white,
    dark: NSColor(srgbRed: 0.137, green: 0.129, blue: 0.118, alpha: 1))         // #23211E
  static let cardBorder = adaptive(
    light: NSColor(srgbRed: 0.914, green: 0.894, blue: 0.855, alpha: 1),
    dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.09))
  static let userBubble = adaptive(
    light: NSColor(srgbRed: 0.608, green: 0.388, blue: 0.094, alpha: 1),       // #9B6318
    dark: NSColor(srgbRed: 0.784, green: 0.565, blue: 0.212, alpha: 1))        // #C89036
  static let onUserBubble = adaptive(
    light: NSColor.white,
    dark: NSColor(srgbRed: 0.10, green: 0.08, blue: 0.04, alpha: 1))
  static let badgeFill = adaptive(
    light: NSColor(srgbRed: 0.984, green: 0.922, blue: 0.835, alpha: 1),
    dark: NSColor(srgbRed: 0.32, green: 0.21, blue: 0.08, alpha: 0.85))
  static let badgeText = adaptive(
    light: NSColor(srgbRed: 0.784, green: 0.424, blue: 0.090, alpha: 1),
    dark: NSColor(srgbRed: 0.98, green: 0.68, blue: 0.28, alpha: 1))
  static let pinnedSelected = adaptive(
    light: NSColor(srgbRed: 0.804, green: 0.843, blue: 0.898, alpha: 0.88),  // #CDD7E5
    dark: NSColor(srgbRed: 0.30, green: 0.36, blue: 0.46, alpha: 0.45))
  static let composerBg = adaptive(
    light: NSColor(srgbRed: 0.988, green: 0.980, blue: 0.961, alpha: 0.65),
    dark: NSColor(srgbRed: 0.137, green: 0.129, blue: 0.118, alpha: 0.75))
  static let mutedText = adaptive(
    light: NSColor(srgbRed: 0.486, green: 0.467, blue: 0.431, alpha: 1),
    dark: NSColor(srgbRed: 0.635, green: 0.608, blue: 0.569, alpha: 1))
  static let primaryText = adaptive(
    light: NSColor(srgbRed: 0.067, green: 0.067, blue: 0.063, alpha: 1),      // #111110
    dark: NSColor(srgbRed: 0.953, green: 0.937, blue: 0.910, alpha: 1))
}

/// Rich circular avatar matching the D144 visual grammar with Memoshi's own SF Symbol artwork.
struct ShellBotAvatar: View {
  let symbol: String
  let gradient: [Color]
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(
          LinearGradient(
            colors: gradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      Image(systemName: symbol)
        .font(.system(size: size * 0.42, weight: .semibold))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
    .frame(width: size, height: size)
    .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
  }
}

/// Clustered 3-bot group avatar matching the multi-bot room icon in the D144 reference.
struct ShellGroupAvatar: View {
  let members: [ShellExampleBot]
  let size: CGFloat

  var body: some View {
    let sub = size * 0.56
    ZStack {
      if members.indices.contains(0) {
        ShellBotAvatar(symbol: members[0].symbol, gradient: members[0].gradient, size: sub)
          .offset(x: 0, y: -size * 0.20)
      }
      if members.indices.contains(1) {
        ShellBotAvatar(symbol: members[1].symbol, gradient: members[1].gradient, size: sub)
          .offset(x: -size * 0.22, y: size * 0.16)
      }
      if members.indices.contains(2) {
        ShellBotAvatar(symbol: members[2].symbol, gradient: members[2].gradient, size: sub)
          .offset(x: size * 0.22, y: size * 0.16)
      }
    }
    .frame(width: size, height: size)
  }
}

struct ShellExampleBot: Identifiable, Hashable {
  let id: String
  let name: String
  let symbol: String
  let gradient: [Color]
  let isMacHosted: Bool
  let isLive: Bool
  let modelLabel: String
  let dateLabel: String
  let preview: String

  static let pinned: [ShellExampleBot] = [
    ShellExampleBot(
      id: "johnny", name: "Johnny", symbol: "sparkles",
      gradient: [Color(red: 0.16, green: 0.68, blue: 0.56), Color(red: 0.10, green: 0.44, blue: 0.48)],
      isMacHosted: true, isLive: false, modelLabel: "Claude Opus 5.5",
      dateLabel: "Today", preview: "Standing by on this Mac"),
    ShellExampleBot(
      id: "weather", name: "WeatherBot", symbol: "cloud.sun.fill",
      gradient: [Color(red: 0.22, green: 0.52, blue: 0.88), Color(red: 0.14, green: 0.32, blue: 0.65)],
      isMacHosted: false, isLive: false, modelLabel: "GPT-6.1 Sol · Fast",
      dateLabel: "Nov 11", preview: "Tomorrow in Rome will be rainy: 94%..."),
    ShellExampleBot(
      id: "health", name: "HealthCoach", symbol: "heart.fill",
      gradient: [Color(red: 0.96, green: 0.27, blue: 0.44), Color(red: 0.82, green: 0.15, blue: 0.34)],
      isMacHosted: false, isLive: false, modelLabel: "Claude Opus 5.5",
      dateLabel: "Nov 8", preview: "Daily recovery & sleep summary"),
    ShellExampleBot(
      id: "researcher", name: "Researcher", symbol: "book.closed.fill",
      gradient: [Color(red: 0.95, green: 0.68, blue: 0.24), Color(red: 0.80, green: 0.48, blue: 0.14)],
      isMacHosted: false, isLive: false, modelLabel: "Gemini 4 Neon",
      dateLabel: "Yesterday", preview: "Collected 12 primary sources..."),
    ShellExampleBot(
      id: "builder", name: "Builder", symbol: "hammer.fill",
      gradient: [Color(red: 0.31, green: 0.40, blue: 0.85), Color(red: 0.18, green: 0.24, blue: 0.58)],
      isMacHosted: true, isLive: false, modelLabel: "Claude Opus 5.5",
      dateLabel: "Today", preview: "Merged PR #533 on Mac Studio"),
    ShellExampleBot(
      id: "proofer", name: "Proofer", symbol: "checkmark.seal.fill",
      gradient: [Color(red: 0.95, green: 0.82, blue: 0.18), Color(red: 0.32, green: 0.66, blue: 0.94)],
      isMacHosted: false, isLive: false, modelLabel: "Claude Opus 5.5",
      dateLabel: "5:01 PM", preview: "I fixed the draft and re-read the page..."),
    ShellExampleBot(
      id: "linker", name: "Linker", symbol: "link",
      gradient: [Color(red: 0.30, green: 0.50, blue: 0.95), Color(red: 0.20, green: 0.34, blue: 0.78)],
      isMacHosted: false, isLive: false, modelLabel: "Gemini 4 Neon",
      dateLabel: "Nov 19", preview: "Saved 7 App Debuts to Bookmarks"),
    ShellExampleBot(
      id: "coder", name: "Coder", symbol: "chevron.left.forwardslash.chevron.right",
      gradient: [Color(red: 0.52, green: 0.34, blue: 0.88), Color(red: 0.32, green: 0.18, blue: 0.62)],
      isMacHosted: true, isLive: false, modelLabel: "Claude Opus 5.5",
      dateLabel: "Today", preview: "Both fast-mode builds passed"),
    ShellExampleBot(
      id: "qa", name: "QA Bot", symbol: "magnifyingglass",
      gradient: [Color(red: 0.18, green: 0.66, blue: 0.62), Color(red: 0.12, green: 0.44, blue: 0.46)],
      isMacHosted: true, isLive: false, modelLabel: "Gemini 4 Neon",
      dateLabel: "Today", preview: "All 18 CI steps green"),
  ]

  static let sweMembers: [ShellExampleBot] = [
    pinned[3], // Researcher
    pinned[4], // Builder
    pinned[5], // Proofer
  ]

  static let bottomBots: [ShellExampleBot] = [
    pinned[1], // WeatherBot
    pinned[2], // HealthCoach
  ]
}

/// The three right-sidebar modes from the Oct 20 macOS captures (`2112555465313853810`).
enum RightSidebarMode: String, CaseIterable, Identifiable {
  case activity = "Activity"
  case links = "Links"
  case splitChat = "Split"

  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .activity: "clock.arrow.trianglehead.counterclockwise.rotate.90"
    case .links: "link"
    case .splitChat: "rectangle.split.2x1"
    }
  }
}

/// Real conversations use stored IDs in the unified D144 warm shell.
struct LiveWorkspaceView: View {
  @Bindable var model: LiveChatModel
  let supervisor: DaemonSupervisor
  @Binding var isSidebarPresented: Bool
  @Bindable var navigation: LiveWorkspaceNavigation
  let appearances: BotAppearanceStore
  let hotKeyManager: QuickEntryHotKeyManager
  @State private var sheet: ConversationSheet?
  @State private var lastSheetTrigger: ConversationSheetTrigger?
  @State private var announcedCards: Set<CardID>?
  @State private var lastFocusedCard: CardID?
  @State private var isModelSetupPresented = false
  @State private var isFoldersPresented = false
  @State private var isActivityPresented = false
  @State private var selectedMockBot: ShellExampleBot? = nil // nil = live Assistant / real Bot / Session
  @State private var rightSidebarMode: RightSidebarMode? = .activity
  @State private var splitBot: ShellExampleBot = ShellExampleBot.pinned[4] // Builder
  @State private var bookmarks = WorkspaceBookmarksStore()
  @State private var remindersStore = LiveRemindersStore()
  @State private var calendarStore = LiveCalendarStore()
  @State private var contactsStore = LiveContactsStore()
  @State private var notesStore = NotesDocumentStore()
  @State private var mailStore = MailWorkspaceStore()
  @State private var connectorStore = ConnectorWorkspaceStore()
  @FocusState private var focus: LiveWorkspaceFocus?
  @AccessibilityFocusState private var sheetTrigger: ConversationSheetTrigger?
  @Environment(\.designAnnouncer) private var announcer
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    HStack(spacing: 0) {
      if isSidebarPresented {
        LiveConversationSidebar(
          model: model,
          supervisor: supervisor,
          navigation: navigation,
          bookmarks: bookmarks,
          appearances: appearances,
          isSidebarPresented: $isSidebarPresented,
          sheet: $sheet,
          isModelSetupPresented: $isModelSetupPresented,
          isFoldersPresented: $isFoldersPresented,
          isActivityPresented: $isActivityPresented,
          selectedMockBot: $selectedMockBot,
          rightSidebarMode: $rightSidebarMode,
          focus: $focus,
          sheetTrigger: $sheetTrigger
        )
        .frame(width: 268)
        Rectangle()
          .fill(WarmShellColors.divider)
          .frame(width: 1)
          .ignoresSafeArea(.container, edges: .top)
      }
      switch navigation.destination {
      case .waiting:
        LiveWaitingList(model: model.reviews, focus: $focus)
          .frame(minWidth: DS.Layout.Conversation.minWidth, maxWidth: .infinity)
          .background(WarmShellColors.canvas)
      case .today:
        TodayWorkspaceView(
          model: model,
          remindersStore: remindersStore,
          calendarStore: calendarStore,
          appearances: appearances,
          onOpenWaiting: { navigation.showWaiting() },
          onSelectConversation: { id in
            navigation.showConversation()
            selectedMockBot = nil
            Task { await model.selectConversation(id) }
          }
        )
        .frame(minWidth: DS.Layout.Conversation.minWidth, maxWidth: .infinity)
      case .bookmarks:
        BookmarksPaneView(
          bookmarks: bookmarks,
          onOpenConversation: { id in
            navigation.showConversation()
            selectedMockBot = nil
            Task { await model.selectConversation(id) }
          }
        )
        .frame(minWidth: DS.Layout.Conversation.minWidth, maxWidth: .infinity)
      case .myApps:
        MyAppsWorkspaceView(
          model: model,
          remindersStore: remindersStore,
          calendarStore: calendarStore,
          contactsStore: contactsStore,
          notesStore: notesStore,
          mailStore: mailStore,
          connectorStore: connectorStore,
          selectedTab: $navigation.selectedAppTab,
          onOpenFolders: { isFoldersPresented = true },
          onSelectConversation: { id in
            navigation.showConversation()
            selectedMockBot = nil
            Task { await model.selectConversation(id) }
          }
        )
        .onAppear {
          let root = supervisor.activeDataDirectory
          notesStore.setDirectory(root.appendingPathComponent("Notes", isDirectory: true))
          mailStore.setDataDirectory(root)
          connectorStore.setDataDirectory(root)
        }
        .frame(minWidth: DS.Layout.Conversation.minWidth, maxWidth: .infinity)
      case .conversation:
        LiveChatView(
          model: model,
          supervisor: supervisor,
          selectedMockBot: selectedMockBot,
          bookmarks: bookmarks,
          appearances: appearances,
          isSidebarPresented: $isSidebarPresented,
          isSetupPresented: $isModelSetupPresented,
          isFoldersPresented: $isFoldersPresented,
          isActivityPresented: $isActivityPresented,
          rightSidebarMode: $rightSidebarMode,
          onEditBot: { bot in sheet = .edit(bot) },
          onOpenConnectors: { navigation.showMyApps(.connectors) },
          focus: $focus
        )
        .frame(minWidth: DS.Layout.Conversation.minWidth, maxWidth: .infinity)
      }
      if let mode = rightSidebarMode {
        Rectangle()
          .fill(WarmShellColors.divider)
          .frame(width: 1)
          .ignoresSafeArea(.container, edges: .top)
        RightSidebarView(
          mode: mode,
          model: model,
          supervisor: supervisor,
          bookmarks: bookmarks,
          appearances: appearances,
          remindersStore: remindersStore,
          isLiveBot: selectedMockBot == nil,
          activeBotName: selectedMockBot?.name ?? model.chat?.title ?? String(localized: "Assistant"),
          activeBot: selectedMockBot ?? ShellExampleBot.pinned[0],
          splitBot: $splitBot,
          onSelectMode: { rightSidebarMode = $0 },
          onOpenFolders: { isFoldersPresented = true },
          onOpenModelSettings: { isModelSetupPresented = true },
          onClose: { withAnimation(.easeInOut(duration: 0.15)) { rightSidebarMode = nil } }
        )
        .frame(width: mode == .splitChat ? 360 : 320)
      }
    }
    .background(WarmShellColors.canvas)
    .ignoresSafeArea(.container, edges: .top)
    .frame(minWidth: DS.Layout.Window.minWidth, minHeight: DS.Layout.Window.minHeight)
    .overlay {
      if navigation.isCommandPalettePresented {
        CommandPaletteOverlay(
          model: model,
          navigation: navigation,
          isSidebarPresented: $isSidebarPresented,
          rightSidebarMode: $rightSidebarMode,
          selectedMockBot: $selectedMockBot,
          onNewBot: { sheet = .newBot },
          onNewSession: { sheet = .session },
          onOpenModelSettings: { isModelSetupPresented = true },
          onOpenFolders: { isFoldersPresented = true },
          onOpenTasks: { openWindow(id: "tasks") },
          onOpenQuickEntry: {
            openWindow(id: "quick-entry")
            NSApplication.shared.activate(ignoringOtherApps: true)
          },
          onOpenBackgroundSettings: {
            supervisor.refreshRegistration()
            if supervisor.registration == .notRegistered || supervisor.registration == .notFound {
              supervisor.enableBackgroundService()
            } else {
              supervisor.openBackgroundSettings()
            }
          },
          onDismiss: { navigation.isCommandPalettePresented = false }
        )
      }
    }
    .task {
      hotKeyManager.start {
        openWindow(id: "quick-entry")
        NSApplication.shared.activate(ignoringOtherApps: true)
      }
    }
    .sheet(item: $sheet, onDismiss: restoreSheetTrigger) { item in
      switch item {
      case .newBot:
        BotProfileEditor(
          directory: model.directory, models: model.providerSetup.models, bot: nil,
          appearances: appearances)
      case .edit(let bot):
        BotProfileEditor(
          directory: model.directory, models: model.providerSetup.models, bot: bot,
          appearances: appearances)
      case .session:
        SessionCreationSheet(directory: model.directory, selectedBot: model.chat?.botId)
      case .trash:
        SessionTrashSheet(directory: model.directory)
      }
    }
    .onChange(of: sheet?.id) { _, _ in
      if let sheet { lastSheetTrigger = sheet.trigger }
    }
    .onChange(of: model.directory.requestedSelection) { _, selected in
      guard let selected else { return }
      navigation.showConversation()
      selectedMockBot = nil
      Task { await model.selectConversation(selected) }
    }
    .onChange(of: model.chat?.id) { _, _ in
      // Arrow keys in the sidebar keep focus there; other switches start in the composer.
      if focus != .sidebar && navigation.destination == .conversation { focus = .composer }
    }
    .onChange(of: navigation.nextCardRequest) { _, _ in focusNextCard() }
    .onChange(of: navigation.paneRequest) { _, _ in cyclePane() }
    .onChange(of: model.reviews.hasLoaded, initial: true) { _, loaded in
      // Cards already pending when review state loads are history, not new arrivals.
      if loaded && announcedCards == nil { announcedCards = Set(pendingCardIDs) }
    }
    .onChange(of: pendingCardIDs) { _, current in announceNewCards(current) }
    .onChange(of: focus) { _, new in
      if case .card(let id) = new { lastFocusedCard = id }
    }
    .onChange(of: lastFocusedCardStatus) { old, new in
      // A decision on the card the person worked with is announced, even though the card
      // then moves from the pending list to Recorded Decisions (02 §13.2).
      guard let old, let new, old != new else { return }
      announcer.announce(new)
    }
  }

  private var lastFocusedCardStatus: String? {
    guard let lastFocusedCard,
      let entry = model.reviews.entries.first(where: { $0.id == lastFocusedCard })
    else { return nil }
    return String(localized: entry.reviewStatus(at: model.reviews.now))
  }

  private var pendingEntries: [ApprovalReviewEntry] {
    model.reviews.pendingGroups.flatMap(\.entries).filter(\.isPending)
  }

  private var pendingCardIDs: [CardID] { pendingEntries.map(\.id) }

  private func focusNextCard() {
    let entries = pendingEntries
    guard !entries.isEmpty else { return }
    var index = 0
    if case .card(let current) = focus,
      let position = entries.firstIndex(where: { $0.id == current })
    {
      index = (position + 1) % entries.count
    }
    let target = entries[index].id
    // The Waiting list may be created by this request; focus it once it exists.
    Task { @MainActor in focus = .card(target) }
  }

  private func cyclePane() {
    var panes: [LiveWorkspaceFocus] = isSidebarPresented ? [.sidebar] : []
    switch navigation.destination {
    case .waiting:
      if let first = pendingEntries.first { panes.append(.card(first.id)) }
    case .conversation:
      panes.append(.composer)
    case .today, .bookmarks, .myApps:
      break
    }
    guard !panes.isEmpty else { return }
    let current: Int? =
      switch focus {
      case .sidebar: panes.firstIndex(of: .sidebar)
      case .composer: panes.firstIndex(of: .composer)
      case .card: panes.firstIndex { if case .card = $0 { true } else { false } }
      case nil: nil
      }
    let step = navigation.paneRequestIsForward ? 1 : panes.count - 1
    // Focus outside the known panes (or not yet tracked) moves into the content pane first.
    let next = current.map { ($0 + step) % panes.count } ?? min(1, panes.count - 1)
    focus = panes[next]
  }

  private func restoreSheetTrigger() {
    guard let lastSheetTrigger else { return }
    Task { @MainActor in sheetTrigger = lastSheetTrigger }
  }

  /// Cards in the shown conversation announce at once; cards elsewhere coalesce (02 §13.2).
  private func announceNewCards(_ current: [CardID]) {
    guard model.reviews.hasLoaded else { return }
    guard let known = announcedCards else {
      announcedCards = Set(current)
      return
    }
    let new = current.filter { !known.contains($0) }
    announcedCards = known.union(current)
    for entry in pendingEntries where new.contains(entry.id) {
      let isShown =
        navigation.showsWaiting || entry.card.conversationId.rawValue == model.chat?.id.rawValue
      if isShown {
        let name =
          model.directory.bots.first { $0.id == entry.card.botId }?.name
          ?? String(localized: "A bot")
        announcer.announce(
          String(localized: "\(name) needs you: \(entry.card.title.rawValue)"))
      } else {
        announcer.noteElsewhere(id: entry.id.rawValue)
      }
    }
  }
}

enum ConversationSheet: Identifiable {
  case newBot
  case edit(Bot)
  case session
  case trash

  var id: String {
    switch self {
    case .newBot: "new-bot"
    case .edit(let bot): bot.id.rawValue
    case .session: "new-session"
    case .trash: "trash"
    }
  }

  var trigger: ConversationSheetTrigger {
    switch self {
    case .newBot: .newBot
    case .edit: .editBot
    case .session: .newSession
    case .trash: .trash
    }
  }
}

/// The control that opened a workspace sheet; VoiceOver focus returns to it on dismissal.
enum ConversationSheetTrigger: Hashable {
  case newBot, editBot, newSession, trash
}

private struct LiveConversationSidebar: View {
  let model: LiveChatModel
  let supervisor: DaemonSupervisor
  let navigation: LiveWorkspaceNavigation
  let bookmarks: WorkspaceBookmarksStore
  let appearances: BotAppearanceStore
  @Binding var isSidebarPresented: Bool
  @Binding var sheet: ConversationSheet?
  @Binding var isModelSetupPresented: Bool
  @Binding var isFoldersPresented: Bool
  @Binding var isActivityPresented: Bool
  @Binding var selectedMockBot: ShellExampleBot?
  @Binding var rightSidebarMode: RightSidebarMode?
  var focus: FocusState<LiveWorkspaceFocus?>.Binding
  var sheetTrigger: AccessibilityFocusState<ConversationSheetTrigger?>.Binding
  @State private var sessionToTrash: ChatSummary?
  @State private var searchQuery = ""
  @State private var selectedGroupID: String?
  @AppStorage("shell.pinnedConversationIDs") private var pinnedIDsStorage = ""

  private var pinnedLiveIDs: [String] {
    pinnedIDsStorage.split(separator: ",").map(String.init).filter { !$0.isEmpty }
  }

  private func isPinned(_ id: ConversationID) -> Bool {
    pinnedLiveIDs.contains(id.rawValue)
  }

  private func togglePin(_ id: ConversationID) {
    var list = pinnedLiveIDs
    if let idx = list.firstIndex(of: id.rawValue) {
      list.remove(at: idx)
    } else {
      list.append(id.rawValue)
    }
    pinnedIDsStorage = list.joined(separator: ",")
  }

  private var pinnedLiveBots: [ChatSummary] {
    let realBots = filteredLive(.bot)
    let byID = Dictionary(uniqueKeysWithValues: realBots.map { ($0.id.rawValue, $0) })
    return pinnedLiveIDs.compactMap { byID[$0] }
  }

  private var filteredExamplePinned: [ShellExampleBot] {
    let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return ShellExampleBot.pinned }
    return ShellExampleBot.pinned.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
  }

  private var filteredExampleBottom: [ShellExampleBot] {
    let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return ShellExampleBot.bottomBots }
    return ShellExampleBot.bottomBots.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
  }

  private func filteredLive(_ kind: ConversationKind) -> [ChatSummary] {
    let all = conversations(kind)
    let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return all }
    return all.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
  }

  var body: some View {
    VStack(spacing: 0) {
      topHeaderBar
      searchField
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          utilityNavigation
          pinnedSection
          pinnedGroupsSection
          botsListSection
          sessionsListSection
          ConversationDirectoryStatus(directory: model.directory)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
      }
      .scrollIndicators(.hidden)
      .focused(focus, equals: .sidebar)
      .onDeleteCommand {
        if canTrash { trashSelectedSession() }
      }
      .disabled(model.isLoading || model.isSending || model.isStopping || model.hasUnconfirmedSend)
      .accessibilityIdentifier("conversation.sidebar")

      Rectangle()
        .fill(WarmShellColors.divider)
        .frame(height: 1)
      HStack {
        DaemonStatusButton(supervisor: supervisor)
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
    .background {
      ZStack {
        SidebarVisualEffectBackdrop()
        WarmShellColors.sidebarTint
      }
      .ignoresSafeArea(.container, edges: .top)
    }
    .onChange(of: navigation.trashRequest) { _, _ in
      if canTrash { trashSelectedSession() }
    }
    .confirmationDialog(
      "Move this Session to Trash?",
      isPresented: Binding(
        get: { sessionToTrash != nil },
        set: { if !$0 { sessionToTrash = nil } }),
      titleVisibility: .visible
    ) {
      Button("Move to Trash", role: .destructive) {
        if let sessionToTrash, let id = try? SessionID(sessionToTrash.id.rawValue) {
          model.directory.deleteSession(id)
        }
        sessionToTrash = nil
      }
      .accessibilityIdentifier("conversation.confirmTrash")
      Button("Cancel", role: .cancel) { sessionToTrash = nil }
    } message: {
      Text("You can restore it for 30 days. Stop its work and resolve pending approvals first.")
    }
  }

  private var topHeaderBar: some View {
    GlassEffectContainer(spacing: 8) {
      HStack(spacing: 8) {
        Spacer()
        Menu {
          if let bot = model.directory.bots.first(where: { $0.id == model.chat?.botId }) {
            Button("Edit Bot…", systemImage: "person.badge.gearshape") {
              sheet = .edit(bot)
            }
            .disabled(model.directory.isChanging)
          }
          Button("Model Settings…", systemImage: "slider.horizontal.3") {
            isModelSetupPresented = true
          }
          Button("Folder Grants…", systemImage: "folder") {
            isFoldersPresented = true
          }
          Button("Trash…", systemImage: "trash") {
            sheet = .trash
          }
          Divider()
          Button(
            supervisor.hasAuthenticatedDaemon ? "Runtime Connected" : "Retry Runtime Connection",
            systemImage: supervisor.hasAuthenticatedDaemon ? "checkmark.circle" : "arrow.clockwise"
          ) {
            if !supervisor.hasAuthenticatedDaemon { supervisor.retryConnection() }
          }
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular.interactive(), in: Circle())
        .help("Settings & Tools")
        .accessibilityIdentifier("conversation.moreMenu")

        Menu {
          Button("New Bot…", systemImage: "person.badge.plus") {
            sheet = .newBot
          }
          .accessibilityIdentifier("conversation.newBot")
          Button("New Session…", systemImage: "square.and.pencil") {
            sheet = .session
          }
          .accessibilityIdentifier("conversation.newSession")
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "plus")
              .font(.system(size: 15, weight: .regular))
            Image(systemName: "chevron.down")
              .font(.system(size: 9, weight: .semibold))
          }
          .foregroundStyle(WarmShellColors.primaryText)
          .padding(.horizontal, 11)
          .frame(height: 34)
          .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular.interactive(), in: Capsule())
        .help("New Bot or Session")

        Button {
          withAnimation(.easeInOut(duration: 0.15)) { isSidebarPresented.toggle() }
        } label: {
          Image(systemName: "sidebar.left")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(WarmShellColors.primaryText)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .help("Toggle Sidebar")
      }
    }
    .padding(.leading, 76)
    .padding(.trailing, 12)
    .padding(.top, 10)
    .padding(.bottom, 10)
  }

  private var searchField: some View {
    HStack(spacing: 7) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 13.5, weight: .regular))
        .foregroundStyle(WarmShellColors.mutedText)
      TextField(
        "Search Everything",
        text: $searchQuery,
        prompt: Text("Search Everything").foregroundStyle(WarmShellColors.mutedText)
      )
      .textFieldStyle(.plain)
      .font(.system(size: 13.5))
      .foregroundStyle(WarmShellColors.primaryText)
      .accessibilityIdentifier("conversation.search")
      if !searchQuery.isEmpty {
        Button {
          searchQuery = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 13))
            .foregroundStyle(WarmShellColors.mutedText)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 34)
    .glassEffect(.regular, in: Capsule())
    .padding(.horizontal, 12)
    .padding(.bottom, 12)
  }

  private var utilityNavigation: some View {
    let assistantChat = conversations(.assistant).first
    let isAssistantSelected =
      navigation.destination == .conversation && selectedMockBot == nil && selectedGroupID == nil
      && (model.chat?.kind == .assistant || model.chat == nil)
    return VStack(alignment: .leading, spacing: 1) {
      utilityRow(
        title: assistantChat?.title ?? "Assistant",
        symbol: "sparkles",
        isSelected: isAssistantSelected,
        badgeCount: 0
      ) {
        navigation.showConversation()
        selectedMockBot = nil
        selectedGroupID = nil
        if let assistantChat {
          Task { await model.selectConversation(assistantChat.id) }
        }
      }
      .accessibilityIdentifier("conversation.assistant")

      utilityRow(
        title: "Today",
        symbol: "sun.max",
        isSelected: navigation.destination == .today,
        badgeCount: 0
      ) {
        navigation.showToday()
      }
      .accessibilityIdentifier("conversation.today")

      utilityRow(
        title: "Waiting for You",
        symbol: "hand.raised",
        isSelected: navigation.destination == .waiting,
        badgeCount: model.reviews.pendingCount
      ) {
        navigation.showWaiting()
      }
      .accessibilityLabel("Waiting for You")
      .accessibilityValue("\(model.reviews.pendingCount) pending")
      .accessibilityIdentifier("conversation.waiting")

      utilityRow(
        title: "Library",
        symbol: "books.vertical",
        isSelected: navigation.destination == .myApps && navigation.selectedAppTab == .files,
        badgeCount: 0
      ) {
        navigation.showMyApps(.files)
      }
      .accessibilityIdentifier("conversation.library")

      utilityRow(
        title: "My Apps",
        symbol: "square.grid.2x2",
        isSelected: navigation.destination == .myApps && navigation.selectedAppTab != .files,
        badgeCount: 0
      ) {
        navigation.showMyApps()
      }
      .accessibilityIdentifier("conversation.myApps")

      utilityRow(
        title: "Bookmarks",
        symbol: "bookmark",
        isSelected: navigation.destination == .bookmarks,
        badgeCount: bookmarks.items.count
      ) {
        navigation.showBookmarks()
      }
      .accessibilityIdentifier("conversation.bookmarks")

      utilityRow(
        title: "Activity",
        symbol: "clock",
        isSelected: rightSidebarMode == .activity,
        badgeCount: 0
      ) {
        withAnimation(.easeInOut(duration: 0.15)) {
          rightSidebarMode = rightSidebarMode == .activity ? nil : .activity
        }
      }
      .accessibilityIdentifier("conversation.activityNav")
    }
  }

  private func utilityRow(
    title: String,
    symbol: String,
    isSelected: Bool,
    badgeCount: Int,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 14.5, weight: .regular))
          .foregroundStyle(WarmShellColors.primaryText)
          .frame(width: 20, alignment: .center)
        Text(title)
          .font(.system(size: 13.5, weight: isSelected ? .medium : .regular))
          .foregroundStyle(WarmShellColors.primaryText)
        Spacer()
        if badgeCount > 0 {
          Text("\(badgeCount)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(WarmShellColors.badgeText)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(WarmShellColors.badgeFill, in: Capsule())
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5.5)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: 9)
            .fill(WarmShellColors.pill)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var pinnedSection: some View {
    let livePinned = pinnedLiveBots
    let remainingMocks = Array(filteredExamplePinned.prefix(max(0, 9 - livePinned.count)))
    return VStack(alignment: .leading, spacing: 8) {
      Text("Pinned")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(WarmShellColors.mutedText)
        .padding(.horizontal, 6)

      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
        spacing: 10
      ) {
        ForEach(livePinned, id: \.id) { chat in
          livePinnedTile(chat)
        }
        ForEach(remainingMocks) { bot in
          examplePinnedTile(bot)
        }
      }
    }
  }

  private func livePinnedTile(_ chat: ChatSummary) -> some View {
    let isSelected =
      navigation.destination == .conversation && selectedMockBot == nil && selectedGroupID == nil
      && model.chat?.id == chat.id
    let style = appearances.appearance(for: chat.botId, isAssistant: chat.kind == .assistant)
    return Button {
      navigation.showConversation()
      selectedMockBot = nil
      selectedGroupID = nil
      Task { await model.selectConversation(chat.id) }
    } label: {
      VStack(spacing: 5) {
        ZStack(alignment: .bottomTrailing) {
          ShellBotAvatar(symbol: style.symbol, gradient: style.gradient, size: 62)
          Image(systemName: "desktopcomputer")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(.black, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
            .offset(x: 2, y: 2)
        }
        Text(verbatim: chat.title)
          .font(.system(size: 11.5, weight: .regular))
          .foregroundStyle(WarmShellColors.primaryText)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .padding(.horizontal, 4)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(WarmShellColors.pinnedSelected)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button("Unpin", systemImage: "pin.slash") { togglePin(chat.id) }
      if let bot = model.directory.bots.first(where: { $0.id == chat.botId }) {
        Button("Edit Bot…", systemImage: "person.badge.gearshape") { sheet = .edit(bot) }
      }
    }
    .accessibilityLabel(Text(verbatim: chat.title))
  }

  private func examplePinnedTile(_ bot: ShellExampleBot) -> some View {
    let isSelected =
      navigation.destination == .conversation && selectedGroupID == nil
      && selectedMockBot?.id == bot.id
    return Button {
      navigation.showConversation()
      selectedGroupID = nil
      selectedMockBot = bot
    } label: {
      VStack(spacing: 5) {
        ZStack(alignment: .bottomTrailing) {
          ShellBotAvatar(symbol: bot.symbol, gradient: bot.gradient, size: 62)
          if bot.isMacHosted {
            Image(systemName: "desktopcomputer")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 22, height: 22)
              .background(.black, in: Circle())
              .overlay(Circle().stroke(.white, lineWidth: 2.5))
              .offset(x: 2, y: 2)
          }
        }
        Text(verbatim: bot.name)
          .font(.system(size: 11.5, weight: .regular))
          .foregroundStyle(WarmShellColors.primaryText)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .padding(.horizontal, 4)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(WarmShellColors.pinnedSelected)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(verbatim: bot.name))
  }

  private var pinnedGroupsSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        navigation.showConversation()
        selectedMockBot = ShellExampleBot.pinned[5]
        selectedGroupID = "swe"
      } label: {
        HStack(spacing: 10) {
          ShellGroupAvatar(members: ShellExampleBot.sweMembers, size: 38)
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
              Text("SWE")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WarmShellColors.primaryText)
                .lineLimit(1)
              Spacer()
              Image(systemName: "pin.fill")
                .font(.system(size: 9))
                .foregroundStyle(WarmShellColors.badgeText)
              Text("Wednesday")
                .font(.system(size: 11))
                .foregroundStyle(WarmShellColors.mutedText)
            }
            Text("Builder: Finished PR checks and handed off…")
              .font(.system(size: 11.5))
              .foregroundStyle(WarmShellColors.mutedText)
              .lineLimit(1)
          }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background {
          if navigation.destination == .conversation && selectedGroupID == "swe" {
            RoundedRectangle(cornerRadius: 10)
              .fill(WarmShellColors.pill)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("conversation.group.swe")
    }
  }

  private var botsListSection: some View {
    let realBots = filteredLive(.bot).filter { !isPinned($0.id) }
    return VStack(alignment: .leading, spacing: 4) {
      Text("Bots")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(WarmShellColors.mutedText)
        .padding(.horizontal, 6)
        .padding(.bottom, 2)

      ForEach(realBots, id: \.id) { chat in
        let isSelected =
          navigation.destination == .conversation && selectedMockBot == nil
          && selectedGroupID == nil && model.chat?.id == chat.id
        let style = appearances.appearance(for: chat.botId, isAssistant: false)
        Button {
          navigation.showConversation()
          selectedMockBot = nil
          selectedGroupID = nil
          Task { await model.selectConversation(chat.id) }
        } label: {
          HStack(spacing: 10) {
            ShellBotAvatar(symbol: style.symbol, gradient: style.gradient, size: 34)
            VStack(alignment: .leading, spacing: 2) {
              HStack {
                Text(verbatim: chat.title)
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(WarmShellColors.primaryText)
                  .lineLimit(1)
                Spacer()
                Text("Live")
                  .font(.system(size: 10.5, weight: .medium))
                  .foregroundStyle(Color(red: 0.18, green: 0.65, blue: 0.36))
              }
              Text("Bot conversation")
                .font(.system(size: 11.5))
                .foregroundStyle(WarmShellColors.mutedText)
                .lineLimit(1)
            }
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 5)
          .background {
            if isSelected {
              RoundedRectangle(cornerRadius: 10)
                .fill(WarmShellColors.pill)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
          Button(
            isPinned(chat.id) ? "Unpin" : "Pin to Top",
            systemImage: isPinned(chat.id) ? "pin.slash" : "pin"
          ) {
            togglePin(chat.id)
          }
          if let bot = model.directory.bots.first(where: { $0.id == chat.botId }) {
            Button("Edit Bot…", systemImage: "person.badge.gearshape") {
              sheet = .edit(bot)
            }
          }
        }
      }

      ForEach(filteredExampleBottom) { bot in
        let isSelected =
          navigation.destination == .conversation && selectedGroupID == nil
          && selectedMockBot?.id == bot.id
        Button {
          navigation.showConversation()
          selectedGroupID = nil
          selectedMockBot = bot
        } label: {
          HStack(spacing: 10) {
            ShellBotAvatar(symbol: bot.symbol, gradient: bot.gradient, size: 34)
            VStack(alignment: .leading, spacing: 2) {
              HStack {
                Text(verbatim: bot.name)
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(WarmShellColors.primaryText)
                  .lineLimit(1)
                Spacer()
                Text(verbatim: bot.dateLabel)
                  .font(.system(size: 11))
                  .foregroundStyle(WarmShellColors.mutedText)
              }
              Text(verbatim: bot.preview)
                .font(.system(size: 11.5))
                .foregroundStyle(WarmShellColors.mutedText)
                .lineLimit(1)
            }
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 5)
          .background {
            if isSelected {
              RoundedRectangle(cornerRadius: 10)
                .fill(WarmShellColors.pill)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var sessionsListSection: some View {
    let realSessions = filteredLive(.session)
    return Group {
      if !realSessions.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Sessions")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WarmShellColors.mutedText)
            .padding(.horizontal, 6)
            .padding(.bottom, 2)

          ForEach(realSessions, id: \.id) { chat in
            let isSelected =
              navigation.destination == .conversation && selectedMockBot == nil
              && selectedGroupID == nil && model.chat?.id == chat.id
            Button {
              navigation.showConversation()
              selectedMockBot = nil
              selectedGroupID = nil
              Task { await model.selectConversation(chat.id) }
            } label: {
              HStack(spacing: 10) {
                ShellBotAvatar(
                  symbol: "text.bubble",
                  gradient: [Color(red: 0.42, green: 0.46, blue: 0.56), Color(red: 0.28, green: 0.30, blue: 0.38)],
                  size: 32)
                VStack(alignment: .leading, spacing: 2) {
                  HStack {
                    Text(verbatim: chat.title)
                      .font(.system(size: 13, weight: .medium))
                      .foregroundStyle(WarmShellColors.primaryText)
                      .lineLimit(1)
                    Spacer()
                    Text("Session")
                      .font(.system(size: 10.5))
                      .foregroundStyle(WarmShellColors.mutedText)
                  }
                  Text("Active session")
                    .font(.system(size: 11.5))
                    .foregroundStyle(WarmShellColors.mutedText)
                    .lineLimit(1)
                }
              }
              .padding(.horizontal, 6)
              .padding(.vertical, 5)
              .background {
                if isSelected {
                  RoundedRectangle(cornerRadius: 10)
                    .fill(WarmShellColors.pill)
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
              Button("Move Session to Trash", systemImage: "trash", role: .destructive) {
                sessionToTrash = chat
              }
              .disabled(!canTrash)
            }
          }
        }
      }
    }
  }

  private func conversations(_ kind: ConversationKind) -> [ChatSummary] {
    model.directory.conversations.filter { $0.kind == kind }
  }

  private var selectedSession: ChatSummary? {
    guard navigation.destination == .conversation, let chat = model.chat, chat.kind == .session
    else { return nil }
    return chat
  }

  private var canTrash: Bool {
    !model.directory.isChanging && !model.directory.hasPendingChange
  }

  private func trashSelectedSession() {
    if let selectedSession { sessionToTrash = selectedSession }
  }
}

struct ConversationDirectoryStatus: View {
  let directory: LiveConversationDirectory
  @State private var isDiscardingRecord = false

  var body: some View {
    if let problem = directory.problem {
      VStack(alignment: .leading, spacing: DS.Space.s2) {
        Text(verbatim: problem).font(DS.Typography.callout).foregroundStyle(
          DS.Colors.Text.secondary)
        if directory.hasUnreadableChange {
          Button("Discard Unreadable Change…", role: .destructive) { isDiscardingRecord = true }
            .disabled(!directory.canDiscardUnreadableChange)
            .accessibilityIdentifier("conversation.discardUnreadable")
        } else if directory.hasPendingChange {
          Button("Retry Saved Change") { directory.retryChange() }
            .disabled(directory.isChanging)
            .accessibilityIdentifier("conversation.retryChange")
        }
      }
      .padding(DS.Space.s4)
      .accessibilityIdentifier("conversation.changeError")
      .confirmationDialog(
        "Discard Unreadable Saved Change?", isPresented: $isDiscardingRecord,
        titleVisibility: .visible
      ) {
        Button("Discard", role: .destructive) { directory.discardUnreadableChange() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "It cannot be read or retried. Discarding sends nothing and cannot undo a change the runtime already applied; check the current bots and Sessions before making the same change again."
        )
      }
    }
  }
}

/// Right contextual sidebar matching Viticci's Oct 20 macOS captures (`2112555465313853810`):
/// Activity timeline, Links + preview popover, and Split second-bot chat with native resource cards.
private struct RightSidebarView: View {
  let mode: RightSidebarMode
  let model: LiveChatModel
  let supervisor: DaemonSupervisor
  let bookmarks: WorkspaceBookmarksStore
  let appearances: BotAppearanceStore
  let remindersStore: LiveRemindersStore
  let isLiveBot: Bool
  let activeBotName: String
  let activeBot: ShellExampleBot
  @Binding var splitBot: ShellExampleBot
  let onSelectMode: (RightSidebarMode) -> Void
  let onOpenFolders: () -> Void
  let onOpenModelSettings: () -> Void
  let onClose: () -> Void
  @State private var selectedLinkPopoverID: String?
  @State private var splitDraft = ""
  @State private var completedReminders: Set<String> = ["done-1"]
  @State private var splitLiveConversationID: ConversationID? = nil
  @State private var splitChat = LiveChatModel()
  @State private var splitOwner = UUID()

  var body: some View {
    VStack(spacing: 0) {
      topBar
      switch mode {
      case .activity:
        activityContent
      case .links:
        linksContent
      case .splitChat:
        splitChatContent
      }
    }
    .background(WarmShellColors.canvas)
    .ignoresSafeArea(.container, edges: .top)
    .onDisappear {
      Task {
        await splitChat.hide(owner: splitOwner)
        splitChat.stop()
      }
    }
  }

  private var topBar: some View {
    GlassEffectContainer(spacing: 8) {
      HStack(spacing: 6) {
        HStack(spacing: 2) {
          ForEach(RightSidebarMode.allCases) { tab in
            Button {
              onSelectMode(tab)
            } label: {
              Text(tab.rawValue)
                .font(.system(size: 11.5, weight: mode == tab ? .semibold : .regular))
                .foregroundStyle(
                  mode == tab ? WarmShellColors.primaryText : WarmShellColors.mutedText)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background {
                  if mode == tab {
                    Capsule().fill(WarmShellColors.pill)
                  }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(3)
        .glassEffect(.regular, in: Capsule())

        Spacer()

        Button(action: onClose) {
          Image(systemName: "chevron.right.2")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .help("Hide Right Sidebar")
      }
    }
    .padding(.horizontal, 14)
    .padding(.top, 12)
    .padding(.bottom, 10)
  }

  // MARK: - Mode 1: Activity (oct20_1.jpg)

  private var activeAvatarStyle: (symbol: String, gradient: [Color]) {
    if isLiveBot, let chat = model.chat {
      let style = appearances.appearance(for: chat.botId, isAssistant: chat.kind == .assistant)
      return chat.kind == .session ? ("text.bubble", style.gradient) : style
    }
    return (activeBot.symbol, activeBot.gradient)
  }

  private var liveActivitySummaryText: String {
    let eventCount = model.activityEvents.count
    var parts: [String] = []
    if let duration = model.lastTurn?.duration {
      let seconds =
        Double(duration.components.seconds)
        + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000.0
      parts.append(String(format: "Last turn %.1fs", seconds))
    }
    if eventCount > 0 {
      parts.append("\(eventCount) recorded event\(eventCount == 1 ? "" : "s")")
    }
    if parts.isEmpty {
      return model.isWorking ? "Working…" : "No activity recorded yet"
    }
    return parts.joined(separator: " · ")
  }

  private var activityContent: some View {
    let avatar = activeAvatarStyle
    return ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text("Activity")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
          Spacer()
          Button(action: onClose) {
            Image(systemName: "xmark")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(WarmShellColors.badgeText)
              .frame(width: 28, height: 28)
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .glassEffect(.regular.interactive(), in: Circle())
        }

        HStack(spacing: 10) {
          ShellBotAvatar(symbol: avatar.symbol, gradient: avatar.gradient, size: 38)
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: activeBotName)
              .font(.system(size: 13.5, weight: .semibold))
              .foregroundStyle(WarmShellColors.primaryText)
            Text(
              verbatim: isLiveBot
                ? liveActivitySummaryText
                : "Worked 11s · 2 steps"
            )
            .font(.system(size: 11.5))
            .foregroundStyle(WarmShellColors.mutedText)
            Text(
              isLiveBot
                ? (model.connection == .connected ? "Connected · Live" : "Offline")
                : "Example transcript"
            )
            .font(.system(size: 11))
            .foregroundStyle(WarmShellColors.mutedText.opacity(0.8))
          }
        }

        VStack(alignment: .leading, spacing: 0) {
          if isLiveBot {
            if !model.activityEvents.isEmpty {
              let recent = Array(model.activityEvents.reversed().prefix(20))
              ForEach(Array(recent.enumerated()), id: \.offset) { idx, ev in
                let formatted = formatActivityEvent(ev)
                activityStepRow(
                  symbol: formatted.symbol,
                  title: formatted.title,
                  detail: formatted.detail,
                  subtitle: formatted.subtitle,
                  duration: formatted.duration,
                  isLast: idx == recent.count - 1
                )
              }
            } else {
              VStack(alignment: .leading, spacing: 6) {
                Text("No tool, policy, or gateway events yet.")
                  .font(.system(size: 12.5, weight: .medium))
                  .foregroundStyle(WarmShellColors.primaryText)
                Text(
                  "Committed runtime events appear here automatically as \(activeBotName) works."
                )
                .font(.system(size: 12))
                .foregroundStyle(WarmShellColors.mutedText)
              }
              .padding(14)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                WarmShellColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .stroke(WarmShellColors.cardBorder, lineWidth: 1)
              )
            }
          } else {
            activityStepRow(
              symbol: "brain",
              title: "Thought",
              detail: "I'll inspect the workspace and fetch relevant context before editing.",
              subtitle: nil,
              duration: "4.3s",
              isLast: false)
            activityStepRow(
              symbol: "terminal",
              title: "Ran local tool check",
              detail: "Verified workspace permissions and read draft.md",
              subtitle: "Shell",
              duration: "0.7s",
              isLast: false)
            activityStepRow(
              symbol: "brain",
              title: "Thought",
              detail: "Applying grammar and link fixes while preserving existing formatting.",
              subtitle: nil,
              duration: "3.0s",
              isLast: false)
            activityStepRow(
              symbol: "curlybraces",
              title: "Ran a script",
              detail: "Code Mode · 2 calls",
              subtitle: nil,
              duration: "1.3s",
              isLast: false)
            activityStepRow(
              symbol: "brain",
              title: "Thought",
              detail: "Re-read the updated draft to confirm every change landed cleanly.",
              subtitle: nil,
              duration: "1.7s",
              isLast: true)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 20)
    }
    .scrollIndicators(.hidden)
  }

  private func formatActivityEvent(_ envelope: EventEnvelope) -> (
    symbol: String, title: String, detail: String, subtitle: String?, duration: String
  ) {
    let timeLabel = Date(timeIntervalSince1970: Double(envelope.ts) / 1_000)
      .formatted(.dateTime.hour().minute())
    switch envelope.event {
    case .toolCompleted(let value):
      let dur = value.durationMs > 0 ? "\(value.durationMs) ms" : timeLabel
      let sub =
        value.ok
        ? "\(value.outputBytes) bytes"
          + (value.redactions > 0 ? " · \(value.redactions) redacted" : "")
        : (value.errorCode ?? "Failed")
      return (
        symbol: value.ok ? "wrench.and.screwdriver" : "exclamationmark.triangle",
        title: value.ok ? "Ran \(value.tool)" : "Failed \(value.tool)",
        detail: value.ok ? "Committed tool result" : "Tool reported an error",
        subtitle: sub,
        duration: dur
      )
    case .policyDecided(let value):
      return (
        symbol: "checkmark.shield",
        title: "Policy · \(value.tool)",
        detail: "Decision: \(value.decision.rawValue) · Rule \(value.ruleId)",
        subtitle: value.via.map { "Via \($0.rawValue)" },
        duration: timeLabel
      )
    case .policyRedacted(let value):
      return (
        symbol: "eye.slash",
        title: "Output redacted",
        detail: "\(value.count) item(s) withheld",
        subtitle: value.kinds.isEmpty ? nil : value.kinds.joined(separator: ", "),
        duration: timeLabel
      )
    case .egressAllowed(let value):
      return (
        symbol: "network",
        title: "Connection admitted",
        detail: value.host,
        subtitle: "Computer \(value.computerId)",
        duration: timeLabel
      )
    case .egressBlocked(let value):
      return (
        symbol: "network.slash",
        title: "Connection refused",
        detail: value.host,
        subtitle: "Refusals: \(value.count)",
        duration: timeLabel
      )
    case .secretUsed(let value):
      return (
        symbol: "key",
        title: "Credential prepared",
        detail: value.host,
        subtitle: "\(value.secretRef) · \(value.purpose.rawValue)",
        duration: timeLabel
      )
    default:
      return (
        symbol: "bolt.horizontal.circle",
        title: envelope.type,
        detail: envelope.scope.taskId.map { "Task \($0.rawValue)" } ?? "Committed runtime event",
        subtitle: envelope.seq.map { "Seq \($0)" },
        duration: timeLabel
      )
    }
  }

  private func activityStepRow(
    symbol: String,
    title: String,
    detail: String,
    subtitle: String?,
    duration: String,
    isLast: Bool
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(spacing: 0) {
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(WarmShellColors.mutedText)
          .frame(width: 28, height: 28)
          .background(WarmShellColors.card, in: Circle())
          .overlay(Circle().stroke(WarmShellColors.cardBorder, lineWidth: 1))
        if !isLast {
          Rectangle()
            .fill(WarmShellColors.divider)
            .frame(width: 1)
            .frame(minHeight: 36)
        }
      }
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(verbatim: title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
            .lineLimit(2)
          Spacer()
          if !duration.isEmpty {
            Text(verbatim: duration)
              .font(.system(size: 11))
              .foregroundStyle(WarmShellColors.mutedText)
          }
        }
        Text(verbatim: detail)
          .font(.system(size: 12))
          .foregroundStyle(WarmShellColors.mutedText)
          .lineLimit(3)
        if let subtitle {
          Text(verbatim: subtitle)
            .font(.system(size: 11))
            .foregroundStyle(WarmShellColors.mutedText.opacity(0.8))
        }
      }
      .padding(.bottom, isLast ? 0 : 14)
    }
  }

  // MARK: - Mode 2: Live Extracted Links + Action Popover (oct20_2.jpg)

  private var displayedLinks: [ExtractedConversationLink] {
    if isLiveBot {
      return ExtractedConversationLink.extract(from: model.messages, senderName: activeBotName)
    }
    guard let exampleURL = URL(string: "https://memoshi.app/docs/building-native-apps-with-agents-and-simulators/")
    else { return [] }
    return [
      ExtractedConversationLink(
        id: "example-memoshi-docs",
        url: exampleURL,
        host: "memoshi.app",
        displayPath: "Building Native Apps with Multiple Agents & Simulators",
        contextSnippet: "Native SwiftUI shell, durable Pi runtime, and local model orchestration.",
        senderLabel: "Example message",
        timestamp: nil
      )
    ]
  }

  private var linksContent: some View {
    let links = displayedLinks
    return ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("\(links.count) Link\(links.count == 1 ? "" : "s")")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(WarmShellColors.primaryText)
            Text(isLiveBot ? "Extracted from \(activeBotName)" : "Example preview")
              .font(.system(size: 11.5))
              .foregroundStyle(WarmShellColors.mutedText)
          }
          Spacer()
          Button(action: onClose) {
            Image(systemName: "xmark")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(WarmShellColors.badgeText)
              .frame(width: 28, height: 28)
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .glassEffect(.regular.interactive(), in: Circle())
        }

        if links.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            Text("No links in this conversation yet.")
              .font(.system(size: 12.5, weight: .medium))
              .foregroundStyle(WarmShellColors.primaryText)
            Text("HTTP and HTTPS URLs shared by you or \(activeBotName) appear here automatically.")
              .font(.system(size: 12))
              .foregroundStyle(WarmShellColors.mutedText)
          }
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            WarmShellColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .stroke(WarmShellColors.cardBorder, lineWidth: 1)
          )
        } else {
          ForEach(links) { link in
            extractedLinkCard(link)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 20)
    }
    .scrollIndicators(.hidden)
  }

  private func extractedLinkCard(_ link: ExtractedConversationLink) -> some View {
    let isBookmarked = bookmarks.isLinkBookmarked(link.url)
    let isPresented = Binding<Bool>(
      get: { selectedLinkPopoverID == link.id },
      set: { presented in
        selectedLinkPopoverID = presented ? link.id : nil
      }
    )
    return Button {
      selectedLinkPopoverID = selectedLinkPopoverID == link.id ? nil : link.id
    } label: {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 5) {
            Image(systemName: "globe")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(Color(red: 0.16, green: 0.56, blue: 0.34))
            Text(verbatim: link.host)
              .font(.system(size: 11))
              .foregroundStyle(WarmShellColors.mutedText)
              .lineLimit(1)
            if isBookmarked {
              Image(systemName: "bookmark.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(WarmShellColors.badgeText)
            }
          }
          Text(verbatim: link.displayPath)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
          if !link.contextSnippet.isEmpty {
            Text(verbatim: link.contextSnippet)
              .font(.system(size: 11.5))
              .foregroundStyle(WarmShellColors.mutedText)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }
          HStack(spacing: 4) {
            Text(verbatim: link.senderLabel)
            if let timestamp = link.timestamp {
              Text("·")
              Text(timestamp, format: .dateTime.hour().minute())
            }
          }
          .font(.system(size: 10.5))
          .foregroundStyle(WarmShellColors.mutedText.opacity(0.85))
          .padding(.top, 2)
        }
        Spacer(minLength: 4)
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color(red: 0.22, green: 0.52, blue: 0.88),
                Color(red: 0.14, green: 0.32, blue: 0.65),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 44, height: 44)
          .overlay {
            Image(systemName: "link")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.white)
          }
      }
      .padding(12)
      .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(WarmShellColors.cardBorder, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .popover(isPresented: isPresented, arrowEdge: .leading) {
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 5) {
            Image(systemName: "globe")
              .font(.system(size: 10))
              .foregroundStyle(Color(red: 0.16, green: 0.56, blue: 0.34))
            Text(verbatim: link.host)
              .font(.system(size: 11.5))
              .foregroundStyle(WarmShellColors.mutedText)
          }
          Text(verbatim: link.displayPath)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
          Text(verbatim: link.url.absoluteString)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(WarmShellColors.mutedText)
            .lineLimit(3)
            .textSelection(.enabled)
        }
        HStack(spacing: 8) {
          linkActionPill(title: "Open", symbol: "safari") {
            NSWorkspace.shared.open(link.url)
            selectedLinkPopoverID = nil
          }
          linkActionPill(title: "Copy", symbol: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
          }
        }
        HStack(spacing: 8) {
          linkActionPill(
            title: isBookmarked ? "Saved" : "Bookmark",
            symbol: isBookmarked ? "bookmark.fill" : "bookmark"
          ) {
            bookmarks.toggleLink(
              url: link.url,
              title: link.displayPath,
              subtitle: link.contextSnippet,
              botName: activeBotName,
              conversationID: model.chat?.id.rawValue)
          }
          ShareLink(item: link.url) {
            HStack(spacing: 5) {
              Image(systemName: "square.and.arrow.up")
                .font(.system(size: 11, weight: .semibold))
              Text("Share")
                .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(WarmShellColors.badgeText)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(WarmShellColors.badgeFill, in: Capsule())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(14)
      .frame(width: 280)
      .background(WarmShellColors.canvas)
    }
  }

  private func linkActionPill(title: String, symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: symbol)
          .font(.system(size: 11, weight: .semibold))
        Text(title)
          .font(.system(size: 12, weight: .medium))
      }
      .foregroundStyle(WarmShellColors.badgeText)
      .frame(maxWidth: .infinity)
      .frame(height: 30)
      .background(WarmShellColors.badgeFill, in: Capsule())
    }
    .buttonStyle(.plain)
  }

  // MARK: - Mode 3: Split Second-Bot Chat + Reminders Card (oct20_3.jpg)

  private var splitChatContent: some View {
    let liveSplitConv =
      splitLiveConversationID.flatMap { id in
        model.directory.conversations.first(where: { $0.id == id })
      }
    let liveSplitTitle = liveSplitConv?.title
    let headerTitle = liveSplitTitle ?? splitBot.name
    let headerModel =
      liveSplitTitle != nil
      ? (splitChat.botModel?.ref.rawValue
        ?? (splitChat.providerSetup.selectedModel.isEmpty
          ? String(localized: "Select Model") : splitChat.providerSetup.selectedModel))
      : splitBot.modelLabel
    let splitAvatar: (symbol: String, gradient: [Color]) =
      if let conv = liveSplitConv {
        appearances.appearance(for: conv.botId, isAssistant: conv.kind == .assistant)
      } else {
        (splitBot.symbol, splitBot.gradient)
      }
    return VStack(spacing: 0) {
      HStack {
        Menu {
          if !model.directory.conversations.isEmpty {
            Section("Live Conversations") {
              ForEach(model.directory.conversations, id: \.id) { conv in
                Button {
                  splitLiveConversationID = conv.id
                  if let client = supervisor.authenticatedClient {
                    splitChat.attach(client)
                  }
                  Task {
                    await splitChat.show(owner: splitOwner)
                    await splitChat.selectConversation(conv.id)
                  }
                } label: {
                  if splitLiveConversationID == conv.id {
                    Label(conv.title, systemImage: "checkmark")
                  } else {
                    Text(verbatim: conv.title)
                  }
                }
              }
            }
          }
          Section("Placeholders") {
            ForEach(ShellExampleBot.pinned) { bot in
              Button {
                splitLiveConversationID = nil
                splitBot = bot
              } label: {
                if splitLiveConversationID == nil && splitBot.id == bot.id {
                  Label(bot.name, systemImage: "checkmark")
                } else {
                  Text(bot.name)
                }
              }
            }
          }
        } label: {
          HStack(spacing: 8) {
            ShellBotAvatar(symbol: splitAvatar.symbol, gradient: splitAvatar.gradient, size: 28)
            VStack(alignment: .leading, spacing: 1) {
              HStack(spacing: 5) {
                Text(verbatim: headerTitle)
                  .font(.system(size: 12.5, weight: .semibold))
                  .foregroundStyle(WarmShellColors.primaryText)
                Text(liveSplitTitle != nil ? "Live" : "Example")
                  .font(.system(size: 10, weight: .semibold))
                  .foregroundStyle(
                    liveSplitTitle != nil
                      ? Color(red: 0.18, green: 0.68, blue: 0.36) : WarmShellColors.badgeText)
                  .padding(.horizontal, 5)
                  .padding(.vertical, 1)
                  .background(
                    liveSplitTitle != nil ? Color.green.opacity(0.16) : WarmShellColors.badgeFill,
                    in: Capsule())
              }
              Text("On this Mac · \(headerModel)")
                .font(.system(size: 10.5))
                .foregroundStyle(WarmShellColors.mutedText)
                .lineLimit(1)
            }
            Image(systemName: "chevron.down")
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(WarmShellColors.mutedText)
          }
          .padding(.leading, 7)
          .padding(.trailing, 11)
          .padding(.vertical, 5)
          .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular.interactive(), in: Capsule())

        Spacer()

        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
      }
      .padding(.horizontal, 14)
      .padding(.bottom, 10)

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if liveSplitTitle != nil {
            // Live second-bot transcript
            ForEach(splitChat.messages, id: \.id) { msg in
              let isUser = msg.role == .user
              let body = LiveChatModel.text(msg)
              if !body.isEmpty {
                HStack {
                  if isUser { Spacer(minLength: 24) }
                  MarkdownMessageView(text: body, isUser: isUser)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                      isUser ? WarmShellColors.userBubble : WarmShellColors.card,
                      in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                  if !isUser { Spacer(minLength: 24) }
                }
              }
            }
            if let live = splitChat.live?.message {
              let body = LiveChatModel.text(live)
              if !body.isEmpty {
                MarkdownMessageView(text: body, isUser: false)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 9)
                  .background(
                    WarmShellColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
              }
            }
          }

          // Native Reminders Card (EventKit when authorized, sample fallback otherwise)
          VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                  Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .semibold))
                  Text("REMINDERS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                }
                .foregroundStyle(WarmShellColors.badgeText)
                Text("Today")
                  .font(.system(size: 17, weight: .bold))
                  .foregroundStyle(WarmShellColors.primaryText)
                Text(
                  remindersStore.isAuthorized
                    ? "\(remindersStore.items.count) live Apple Reminders"
                    : "4 reminders · 2 overdue · \(completedReminders.count) done"
                )
                .font(.system(size: 11.5))
                .foregroundStyle(WarmShellColors.mutedText)
              }
              Spacer()
              if !remindersStore.isAuthorized {
                Button("Connect") { remindersStore.requestAccess() }
                  .buttonStyle(.plain)
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(WarmShellColors.badgeText)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 4)
                  .background(WarmShellColors.badgeFill, in: Capsule())
              }
            }

            if remindersStore.isAuthorized {
              if remindersStore.items.isEmpty {
                Text("No open reminders in Apple Reminders.")
                  .font(.system(size: 12))
                  .foregroundStyle(WarmShellColors.mutedText)
                  .padding(.vertical, 6)
              } else {
                VStack(alignment: .leading, spacing: 8) {
                  ForEach(remindersStore.items) { item in
                    Button {
                      remindersStore.toggle(id: item.id)
                    } label: {
                      HStack(alignment: .top, spacing: 9) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                          .font(.system(size: 16))
                          .foregroundStyle(item.isCompleted ? Color.purple : WarmShellColors.mutedText)
                        VStack(alignment: .leading, spacing: 1) {
                          Text(verbatim: item.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(WarmShellColors.primaryText)
                          Text(verbatim: item.dueLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(item.isOverdue ? Color.red.opacity(0.85) : WarmShellColors.mutedText)
                        }
                        Spacer()
                      }
                      .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                  }
                }
              }
            } else {
              VStack(alignment: .leading, spacing: 8) {
                Text("WORK")
                  .font(.system(size: 10, weight: .bold))
                  .foregroundStyle(WarmShellColors.badgeText)
                reminderRow(id: "w1", title: "Review Phase 1 shell milestones", due: "Yesterday · Repeats", overdue: true)
                reminderRow(id: "w2", title: "Finalize right sidebar inspector", due: "Today, 2:00 PM", overdue: false)
              }

              VStack(alignment: .leading, spacing: 8) {
                Text("REMINDERS")
                  .font(.system(size: 10, weight: .bold))
                  .foregroundStyle(Color.purple)
                reminderRow(id: "done-1", title: "Verify Ollama local model streaming", due: "Done Today, 1:22 AM", overdue: false)
                reminderRow(id: "r2", title: "Check Dark Mode contrast", due: "Today, 10:00 PM", overdue: false)
              }
            }
          }
          .padding(14)
          .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .stroke(WarmShellColors.cardBorder, lineWidth: 1)
          )
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
      }
      .scrollIndicators(.hidden)

      // Compact split composer (wired to splitChat when a live conversation is chosen)
      VStack(alignment: .leading, spacing: 10) {
        TextField(
          "Message \(headerTitle)",
          text: liveSplitTitle != nil ? $splitChat.draft : $splitDraft,
          prompt: Text("Message \(headerTitle)").foregroundStyle(WarmShellColors.mutedText.opacity(0.75))
        )
        .textFieldStyle(.plain)
        .font(.system(size: 13.5))
        .foregroundStyle(WarmShellColors.primaryText)
        .onSubmit {
          if liveSplitTitle != nil, splitChat.canSend { splitChat.send() }
        }

        HStack(spacing: 6) {
          Button(action: onOpenFolders) {
            Image(systemName: "plus")
              .font(.system(size: 15))
              .foregroundStyle(WarmShellColors.primaryText)
              .frame(width: 26, height: 28)
          }
          .buttonStyle(.plain)
          .help("Folders & Attachments")

          Menu {
            ForEach(splitChat.providerSetup.models, id: \.ref.ref.rawValue) { entry in
              Button {
                splitChat.providerSetup.selectedModel = entry.ref.ref.rawValue
              } label: {
                if splitChat.providerSetup.selectedModel == entry.ref.ref.rawValue {
                  Label(entry.ref.ref.rawValue, systemImage: "checkmark")
                } else {
                  Text(verbatim: entry.ref.ref.rawValue)
                }
              }
            }
            if !splitChat.providerSetup.models.isEmpty { Divider() }
            Button("Model Settings…", systemImage: "slider.horizontal.3") {
              onOpenModelSettings()
            }
          } label: {
            HStack(spacing: 5) {
              Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
              Text(verbatim: headerModel)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            }
            .foregroundStyle(WarmShellColors.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(WarmShellColors.composerPill, in: Capsule())
          }
          .menuStyle(.button)
          .buttonStyle(.plain)
          .menuIndicator(.hidden)

          Spacer()
          if liveSplitTitle != nil, splitChat.isWorking {
            Button {
              splitChat.stopGeneration()
            } label: {
              Image(systemName: "stop.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(WarmShellColors.userBubble, in: Circle())
            }
            .buttonStyle(.plain)
          } else if liveSplitTitle != nil, splitChat.canSend {
            Button {
              splitChat.send()
            } label: {
              Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(WarmShellColors.userBubble, in: Circle())
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(
        WarmShellColors.composerBg,
        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
      )
      .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .padding(.horizontal, 14)
      .padding(.bottom, 14)
    }
  }

  private func reminderRow(id: String, title: String, due: String, overdue: Bool) -> some View {
    let isDone = completedReminders.contains(id)
    return Button {
      if isDone {
        completedReminders.remove(id)
      } else {
        completedReminders.insert(id)
      }
    } label: {
      HStack(alignment: .top, spacing: 9) {
        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 16))
          .foregroundStyle(isDone ? Color.purple : WarmShellColors.mutedText)
        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: title)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(isDone ? WarmShellColors.mutedText : WarmShellColors.primaryText)
            .strikethrough(isDone)
          Text(verbatim: due)
            .font(.system(size: 11))
            .foregroundStyle(overdue && !isDone ? Color.red.opacity(0.85) : WarmShellColors.mutedText)
        }
        Spacer()
        Image(systemName: "chevron.down")
          .font(.system(size: 10))
          .foregroundStyle(WarmShellColors.mutedText)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
