import AppKit

/// SwiftUI has no asynchronous application-termination veto. This narrow bridge keeps quit
/// pending until the app-owned child has ended; a registered LaunchAgent is never stopped.
@MainActor
final class MemoshiAppDelegate: NSObject, NSApplicationDelegate {
  weak var supervisor: DaemonSupervisor?
  weak var chat: LiveChatModel?
  weak var browserLab: BrowserReviewLab?
  private var terminationTask: Task<Void, Never>?

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let supervisor else {
      browserLab?.shutdown()
      return .terminateNow
    }
    guard terminationTask == nil else { return .terminateLater }
    terminationTask = Task { [weak self, supervisor] in
      let canQuit = await supervisor.stopForQuit()
      // A vetoed quit keeps the app open, so the chat model stays attached and truthful.
      if canQuit {
        self?.chat?.stop()
        self?.browserLab?.shutdown()
      }
      self?.terminationTask = nil
      sender.reply(toApplicationShouldTerminate: canQuit)
      if !canQuit {
        let alert = NSAlert()
        alert.messageText = String(localized: "Waiting for Local Daemon")
        alert.informativeText = String(
          localized:
            "The app-owned helper is still shutting down. Memoshi stayed open rather than leave it running or force-kill it. Wait, then quit again."
        )
        alert.addButton(withTitle: String(localized: "OK"))
        if let window = sender.keyWindow {
          alert.beginSheetModal(for: window) { _ in }
        } else {
          alert.runModal()
        }
      }
    }
    return .terminateLater
  }
}
