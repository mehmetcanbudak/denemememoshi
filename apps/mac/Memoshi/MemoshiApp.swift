import AppCore
import ConversationFeature
import DesignSystem
import ShellFeature
import SwiftUI

/// Real development chat/review in the unified native shell (D144).
@main
struct MemoshiApp: App {
  @NSApplicationDelegateAdaptor(MemoshiAppDelegate.self) private var appDelegate
  @State private var daemon = DaemonSupervisor(developmentChat: true)
  @State private var isSidebarPresented = true
  @State private var chat = LiveChatModel()
  @State private var browserLab = BrowserReviewLab()
  @State private var isHUDVisible = false
  @State private var navigation = LiveWorkspaceNavigation()

  var body: some Scene {
    Window("Memoshi", id: "main") {
      LiveWorkspaceView(
        model: chat, supervisor: daemon, isSidebarPresented: $isSidebarPresented,
        navigation: navigation)
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
            navigation.showsWaiting || chat.chat?.kind != .session
              || chat.directory.isChanging || chat.directory.hasPendingChange)
      }

      CommandMenu("Bots") {
        Button("Waiting for You") { navigation.showWaiting() }
        // ⌘J moves to the next card that needs you, then Return/Esc on it (02 §13.1).
        Button("Next Card Needing You") { navigation.focusNextCard() }
          .keyboardShortcut("j", modifiers: .command)
          .disabled(chat.reviews.pendingCount == 0)
        Divider()
        ForEach(chat.directory.conversations, id: \.id) { conversation in
          Button(conversation.title) {
            navigation.showsWaiting = false
            Task { await chat.selectConversation(conversation.id) }
          }
        }
      }
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

    MenuBarExtra("Memoshi", systemImage: "bubble.left.and.bubble.right") {
      MemoshiMenuBarView()
    }
  }

  /// F6 as a menu key equivalent: AppKit's function-key code point (NSF6FunctionKey, U+F709).
  private static let functionKey6 = KeyEquivalent("\u{F709}")
}
