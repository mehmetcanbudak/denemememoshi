import AppKit
import SwiftUI

/// Keeps the normal app reachable when every review window is closed. It owns no web view,
/// browser profile or second daemon, and Quit uses the existing graceful shutdown delegate.
struct MemoshiMenuBarView: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Open Memoshi") { openWindow(id: "main") }
      .accessibilityIdentifier("menubar.openMain")
    Button("Tasks") { openWindow(id: "tasks") }
      .accessibilityIdentifier("menubar.openTasks")
    Button("Browser Review") { openWindow(id: "browser-review") }
      .accessibilityIdentifier("menubar.openBrowserReview")
    Button("Component Gallery") { openWindow(id: "component-gallery") }
      .accessibilityIdentifier("menubar.openGallery")
    Divider()
    Button("Quit Memoshi") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("q")
  }
}
