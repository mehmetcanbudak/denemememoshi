import AppKit
import SwiftUI

/// Keeps the normal app reachable when every review window is closed. It owns no web view,
/// browser profile or second daemon, and Quit uses the existing graceful shutdown delegate.
struct MemoshiMenuBarView: View {
  let chat: LiveChatModel
  let supervisor: DaemonSupervisor
  let navigation: LiveWorkspaceNavigation
  @Bindable var hotKeyManager: QuickEntryHotKeyManager
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(statusLabel)
      .foregroundStyle(.secondary)
    Divider()
    Button("Quick Entry…") {
      openWindow(id: "quick-entry")
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
    .accessibilityIdentifier("menubar.quickEntry")
    Button("Open Memoshi") {
      openMainWindow()
    }
    .accessibilityIdentifier("menubar.openMain")
    Button("Today") {
      navigation.showToday()
      openMainWindow()
    }
    .accessibilityIdentifier("menubar.openToday")
    if chat.reviews.pendingCount > 0 {
      Button("Waiting for You (\(chat.reviews.pendingCount))") {
        navigation.showWaiting()
        openMainWindow()
      }
      .accessibilityIdentifier("menubar.openWaiting")
    }
    Button("My Apps") {
      navigation.showMyApps()
      openMainWindow()
    }
    .accessibilityIdentifier("menubar.openMyApps")
    Button("Bookmarks") {
      navigation.showBookmarks()
      openMainWindow()
    }
    .accessibilityIdentifier("menubar.openBookmarks")
    Button("Tasks") { openWindow(id: "tasks") }
      .accessibilityIdentifier("menubar.openTasks")
    Divider()
    Toggle("Global Quick Entry (⌥⇧Space)", isOn: $hotKeyManager.isEnabled)
      .accessibilityIdentifier("menubar.toggleGlobalHotKey")
    if !supervisor.isDevelopmentChat {
      Divider()
      Text(backgroundServiceStatusLabel)
        .foregroundStyle(.secondary)
      switch supervisor.registration {
      case .notRegistered, .notFound:
        Button("Enable Background Service") {
          supervisor.enableBackgroundService()
        }
        .disabled(supervisor.isBusy)
        .accessibilityIdentifier("menubar.enableBackgroundService")
      case .requiresApproval:
        Button("Approve in System Settings…") {
          supervisor.openBackgroundSettings()
        }
        .accessibilityIdentifier("menubar.openBackgroundSettings")
      case .enabled:
        Button("Open Background Settings…") {
          supervisor.openBackgroundSettings()
        }
        .accessibilityIdentifier("menubar.openBackgroundSettings")
        Button("Disable Background Service") {
          supervisor.disableBackgroundService()
        }
        .disabled(supervisor.isBusy)
        .accessibilityIdentifier("menubar.disableBackgroundService")
      case .unknown:
        Button("Open Background Settings…") {
          supervisor.openBackgroundSettings()
        }
        .accessibilityIdentifier("menubar.openBackgroundSettings")
      }
    }
    #if DEBUG
      Divider()
      Button("Browser Review") { openWindow(id: "browser-review") }
        .accessibilityIdentifier("menubar.openBrowserReview")
      Button("Component Gallery") { openWindow(id: "component-gallery") }
        .accessibilityIdentifier("menubar.openGallery")
    #endif
    Divider()
    Button("Quit Memoshi") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("q")
  }

  private var statusLabel: String {
    if supervisor.hasAuthenticatedDaemon {
      return String(localized: "Runtime connected")
    }
    if supervisor.isBusy {
      return String(localized: "Connecting to runtime…")
    }
    return String(localized: "Runtime not connected")
  }

  private var backgroundServiceStatusLabel: String {
    switch supervisor.registration {
    case .enabled:
      return String(localized: "Background Service: Enabled")
    case .requiresApproval:
      return String(localized: "Background Service: Approval Required")
    case .notRegistered:
      return String(localized: "Background Service: Off")
    case .notFound:
      return String(localized: "Background Service: Not Found")
    case .unknown:
      return String(localized: "Background Service: Unavailable")
    }
  }

  private func openMainWindow() {
    openWindow(id: "main")
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
