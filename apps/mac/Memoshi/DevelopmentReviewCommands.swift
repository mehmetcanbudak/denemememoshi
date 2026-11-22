import AppKit
import SwiftUI

/// Explicit development entry points: the isolated browser spike, provisional component review,
/// the Tasks stub and the P0-09 debug controls. None of these appear in normal user flows, and
/// quitting or stopping the helper never uses the kill action here.
struct DevelopmentReviewCommands: Commands {
  let daemon: DaemonSupervisor
  @Binding var isHUDVisible: Bool
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow

  var body: some Commands {
    CommandMenu("Development") {
      Button("Browser Review") { openWindow(id: "browser-review") }
        .keyboardShortcut("b", modifiers: [.command, .option])
      Button("Python Review") { openWindow(id: "python-review") }
      Button("Device Pairing Review") { openWindow(id: "device-pairing-review") }
      Button("Component Gallery") { openWindow(id: "component-gallery") }
        .keyboardShortcut("g", modifiers: [.command, .option])
      Button("Tasks") { openWindow(id: "tasks") }

      Divider()
      Toggle("Show HUD", isOn: hudBinding)
      Picker("Inject Latency", selection: latencyBinding) {
        ForEach(InjectedLatency.allCases) { choice in
          Text(choice.title).tag(choice)
        }
      }
      .disabled(!daemon.supportsLinkConditions)
      Button("Drop Connection") { daemon.dropConnectionForDevelopment() }
        .disabled(!daemon.supportsLinkConditions || !daemon.hasAuthenticatedDaemon)
      Button("Kill memoshid…") { confirmKill() }
        .disabled(daemon.ownedHelperPID == nil)
    }
  }

  private var hudBinding: Binding<Bool> {
    Binding(
      get: { isHUDVisible },
      set: { show in
        if show {
          openWindow(id: "development-hud")
        } else {
          dismissWindow(id: "development-hud")
        }
      })
  }

  private var latencyBinding: Binding<InjectedLatency> {
    Binding(
      get: { InjectedLatency(daemon.injectedLatency) },
      set: { daemon.setInjectedLatency($0.duration) })
  }

  /// Names the exact app-owned PID; the supervisor refuses if that helper changed meanwhile.
  @MainActor
  private func confirmKill() {
    guard let pid = daemon.ownedHelperPID else { return }
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = String(localized: "Kill memoshid?")
    alert.informativeText = String(
      localized:
        "Development only. Sends SIGKILL to this app's own authenticated helper, PID \(String(pid)). Work in flight is interrupted; Memoshi restarts the helper and replays from the last applied event. Quit and Stop never do this."
    )
    let kill = alert.addButton(withTitle: String(localized: "Kill memoshid"))
    kill.hasDestructiveAction = true
    kill.keyEquivalent = ""
    let cancel = alert.addButton(withTitle: String(localized: "Cancel"))
    cancel.keyEquivalent = "\r"
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    daemon.killOwnedHelperForDevelopment(confirmedPID: pid)
  }
}

/// The debug menu's per-session delay choices, applied to each frame in each direction.
enum InjectedLatency: Int, CaseIterable, Identifiable {
  case off = 0
  case short = 100
  case medium = 500
  case long = 2_000

  init(_ duration: Duration) {
    self =
      Self.allCases.first { $0.duration == duration } ?? .off
  }

  var id: Int { rawValue }
  var duration: Duration { .milliseconds(rawValue) }

  var title: String {
    self == .off
      ? String(localized: "Off")
      : duration.formatted(.units(allowed: [.milliseconds], width: .abbreviated))
  }
}
