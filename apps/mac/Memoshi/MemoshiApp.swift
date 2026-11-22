import AppCore
import AppKit
import ConversationFeature
import DesignSystem
import ShellFeature
import SwiftUI

/// Unified native Mac workspace (D144) backed by the production SMAppService LaunchAgent supervisor (D143).
@main
struct MemoshiApp: App {
  @NSApplicationDelegateAdaptor(MemoshiAppDelegate.self) private var appDelegate
  @State private var daemon = MemoshiApp.makeDefaultDaemonSupervisor()
  @State private var isSidebarPresented = true
  @State private var chat = LiveChatModel()

  static func makeDefaultDaemonSupervisor() -> DaemonSupervisor {
    #if DEBUG
      let isolated = CommandLine.arguments.contains("--isolated-development-chat")
      return DaemonSupervisor(developmentChat: isolated)
    #else
      return DaemonSupervisor(developmentChat: false)
    #endif
  }
  @State private var browserLab = BrowserReviewLab()
  @State private var isHUDVisible = false
  @State private var navigation = LiveWorkspaceNavigation()
  @State private var appearances = BotAppearanceStore()
  @State private var quickEntryHotKey = QuickEntryHotKeyManager()

  var body: some Scene {
    Window("Memoshi", id: "main") {
      LiveWorkspaceView(
        model: chat, supervisor: daemon, isSidebarPresented: $isSidebarPresented,
        navigation: navigation, appearances: appearances, hotKeyManager: quickEntryHotKey)
      .task {
        appDelegate.supervisor = daemon
        appDelegate.chat = chat
        appDelegate.browserLab = browserLab
        // The supervisor, not this window's view update, attaches the app-lifetime consumer.
        daemon.onAuthenticated = { [chat] client in chat.attach(client) }
        daemon.start()
      }
      .previewAppearance()
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(
      width: 1080,
      height: 760
    )
    .windowResizability(.contentMinSize)
    .defaultLaunchBehavior(.presented)
    .commands {
      CommandGroup(after: .sidebar) {
        Toggle("Show Sidebar", isOn: $isSidebarPresented)
          .keyboardShortcut("s", modifiers: [.control, .command])
        Divider()
        // F6 and ⌥⌘` cycle panes, as in Xcode (02 §13.1, D85).
        Button("Move Focus to Next Pane") { navigation.cyclePane(forward: true) }
          .keyboardShortcut(Self.functionKey6, modifiers: [])
        Button("Move Focus to Previous Pane") { navigation.cyclePane(forward: false) }
          .keyboardShortcut(Self.functionKey6, modifiers: .shift)
        Button("Next Pane") { navigation.cyclePane(forward: true) }
          .keyboardShortcut("`", modifiers: [.option, .command])
        Button("Previous Pane") { navigation.cyclePane(forward: false) }
          .keyboardShortcut("`", modifiers: [.shift, .option, .command])
      }

      CommandGroup(after: .pasteboard) {
        // The same confirmation as the row's context menu and the Delete key.
        Button("Move Session to Trash…") { navigation.requestTrash() }
          .disabled(
            navigation.destination != .conversation || chat.chat?.kind != .session
              || chat.directory.isChanging || chat.directory.hasPendingChange)
      }

      CommandMenu("Bots") {
        Button("Command Palette…") { navigation.toggleCommandPalette() }
          .keyboardShortcut("k", modifiers: .command)
        Divider()
        Button("Today") { navigation.showToday() }
        Button("Waiting for You") { navigation.showWaiting() }
        Button("My Apps") { navigation.showMyApps() }
        Button("Bookmarks") { navigation.showBookmarks() }
        // ⌘J moves to the next card that needs you, then Return/Esc on it (02 §13.1).
        Button("Next Card Needing You") { navigation.focusNextCard() }
          .keyboardShortcut("j", modifiers: .command)
          .disabled(chat.reviews.pendingCount == 0)
        Divider()
        ForEach(chat.directory.conversations, id: \.id) { conversation in
          Button(conversation.title) {
            navigation.showConversation()
            Task { await chat.selectConversation(conversation.id) }
          }
        }
      }
      WorkspaceQuickCommands()
      DevelopmentReviewCommands(daemon: daemon, isHUDVisible: $isHUDVisible)
    }

    Window("Browser Review", id: "browser-review") {
      BrowserReviewView()
        .environment(browserLab)
        .previewAppearance()
        .task { appDelegate.browserLab = browserLab }
    }
    .defaultSize(
      width: DS.Layout.Sidebar.default
        + DS.Layout.Conversation.minWidth
        + DS.Layout.Inspector.default,
      height: DS.Layout.Window.minHeight + DS.Space.s12
    )
    .windowResizability(.contentMinSize)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)

    Window("Python Review", id: "python-review") {
      PyodideReviewView().previewAppearance()
    }
    .defaultSize(
      width: DS.Layout.Gallery.defaultWidth, height: DS.Layout.Gallery.defaultHeight
    )
    .windowResizability(.contentMinSize)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)

    Window("Device Pairing Review", id: "device-pairing-review") {
      DevicePairingReviewView().previewAppearance()
    }
    .defaultSize(
      width: DS.Layout.Gallery.defaultWidth, height: DS.Layout.Gallery.defaultHeight
    )
    .windowResizability(.contentMinSize)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)

    Window("Component Gallery", id: "component-gallery") {
      ComponentGalleryView()
    }
    .defaultSize(
      width: DS.Layout.Gallery.defaultWidth, height: DS.Layout.Gallery.defaultHeight
    )
    .windowResizability(.contentMinSize)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)

    Window("Tasks", id: "tasks") {
      TasksWindowView(model: chat)
        .previewAppearance()
    }
    .defaultSize(
      width: DS.Layout.Conversation.minWidth + DS.Layout.Inspector.min,
      height: DS.Layout.Window.minHeight
    )
    .windowResizability(.contentMinSize)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)

    // A small floating development panel; it observes app state and sends nothing.
    Window("Development HUD", id: "development-hud") {
      DevelopmentHUDView(supervisor: daemon, chat: chat)
        .previewAppearance()
        .onAppear { isHUDVisible = true }
        .onDisappear { isHUDVisible = false }
    }
    .windowLevel(.floating)
    .windowResizability(.contentSize)
    .defaultPosition(.topTrailing)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)

    Window("Quick Entry", id: "quick-entry") {
      QuickEntryWindowView(
        model: chat,
        supervisor: daemon,
        navigation: navigation,
        appearances: appearances,
        hotKeyManager: quickEntryHotKey
      )
      .previewAppearance()
    }
    .windowStyle(.hiddenTitleBar)
    .windowLevel(.floating)
    .windowResizability(.contentSize)
    .defaultPosition(.center)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)

    MenuBarExtra("Memoshi", systemImage: "bubble.left.and.bubble.right") {
      MemoshiMenuBarView(
        chat: chat,
        supervisor: daemon,
        navigation: navigation,
        hotKeyManager: quickEntryHotKey
      )
    }
  }

  /// F6 as a menu key equivalent: AppKit's function-key code point (NSF6FunctionKey, U+F709).
  private static let functionKey6 = KeyEquivalent("\u{F709}")
}

/// App-level Quick Entry menu command wired to SwiftUI's `openWindow` environment.
private struct WorkspaceQuickCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Quick Entry…") {
        openWindow(id: "quick-entry")
        NSApplication.shared.activate(ignoringOtherApps: true)
      }
      .keyboardShortcut(.space, modifiers: [.option, .command])
    }
  }
}
