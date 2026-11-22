import DesignSystem
import Foundation
import MemoshiClient
import SwiftUI

struct DaemonStatusButton: View {
  let supervisor: DaemonSupervisor
  @State private var isPresented = false

  var body: some View {
    Button {
      supervisor.refreshRegistration()
      isPresented.toggle()
    } label: {
      Label(title, systemImage: supervisor.hasAuthenticatedDaemon ? "checkmark.shield" : "network")
    }
    .controlSize(.small)
    .help(
      supervisor.isDevelopmentChat
        ? "Authenticated development transport supports the app Keychain broker and approval review. Production tools and Apple connectors remain off."
        : "Authenticated local daemon transport and background service registration."
    )
    .accessibilityIdentifier("daemon.status")
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      DaemonStatusPopover(supervisor: supervisor)
    }
  }

  private var title: LocalizedStringResource {
    if supervisor.problem == .signingRequired || supervisor.clientStatus?.state == .signingRequired
    {
      return "Signing required"
    }
    if supervisor.problem == .versionMismatch || supervisor.clientStatus?.state == .versionMismatch
    {
      return "Update required"
    }
    if case .restarting = supervisor.helperRecovery, !supervisor.hasAuthenticatedDaemon {
      return "Restarting daemon…"
    }
    if supervisor.isBusy { return "Starting daemon…" }
    if supervisor.hasAuthenticatedDaemon { return "Daemon available" }
    if case .stopped = supervisor.helperRecovery { return "Daemon stopped" }
    if supervisor.clientStatus?.state == .daemonStopped { return "Daemon stopped" }
    return "Daemon not connected"
  }
}

private struct DaemonStatusPopover: View {
  let supervisor: DaemonSupervisor
  @State private var confirmDisable = false

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Text("Local Daemon")
        .font(.headline)
      Text(
        supervisor.isDevelopmentChat
          ? "Development chat and review · Production tools and Apple hosts off"
          : "Authenticated local engine · Keychain broker active"
      )
      .font(DS.Typography.callout)
      .foregroundStyle(.secondary)

      LabeledContent("Transport") {
        Text(supervisor.hasAuthenticatedDaemon ? "Authenticated" : "Not connected")
      }
      LabeledContent("Background registration") {
        Text(supervisor.isDevelopmentChat ? "Unavailable in development chat" : registrationTitle)
      }
      if let status = supervisor.daemonStatus {
        LabeledContent("Daemon RPC state") {
          Text(status.state.rawValue)
        }
      }
      if supervisor.hasAuthenticatedDaemon {
        Text(
          supervisor.isAppOwned
            ? "The authenticated helper is owned by this app and stops when Memoshi quits."
            : "A signed daemon answered hello. Registration alone is not evidence that a service is running."
        )
        .font(DS.Typography.callout)
        .foregroundStyle(.secondary)
      }
      if let hello = supervisor.clientStatus?.hello {
        Text(
          "Protocol \(hello.protocolVersion) · memoshid \(hello.daemon.version) (\(hello.daemon.build))"
        )
        .font(DS.Typography.callout.monospaced())
        if supervisor.clientStatus?.resync != nil {
          Text("Loading authoritative chat state before enabling Send.")
            .font(DS.Typography.callout)
        }
      }
      if let note = DaemonStatusNote(
        problem: supervisor.problem, wait: supervisor.wait, client: supervisor.clientStatus?.state)
      {
        Text(note.message)
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("daemon.note")
      }
      if case .restarting(let attempt) = supervisor.helperRecovery {
        Text(
          "Restarting the app-owned helper after an unexpected exit (attempt \(attempt) of \(DaemonSupervisor.crashLoopExits - 1))."
        )
        .font(DS.Typography.callout)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("daemon.restarting")
      }

      Divider()
      HStack {
        Button(supervisor.hasAuthenticatedDaemon ? "Reconnect" : "Start Daemon") {
          supervisor.retryConnection()
        }
        .disabled(supervisor.isBusy)
        if supervisor.isBusy {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Connecting to local daemon")
        }
      }
      backgroundControls
      Text(
        supervisor.isDevelopmentChat
          ? "This isolated development helper runs only while the app is open. Production background registration is not changed."
          : "Background registration changes only when you choose Enable or Disable. Without it, a helper may run only while this app is open."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(.secondary)
    }
    .padding(DS.Space.s4)
    .frame(width: DS.Layout.Inspector.default)
    .confirmationDialog("Disable background service?", isPresented: $confirmDisable) {
      Button("Disable Background Service", role: .destructive) {
        supervisor.disableBackgroundService()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "macOS will stop the registered daemon. Memoshi can use its own helper while the app stays open."
      )
    }
  }

  @ViewBuilder
  private var backgroundControls: some View {
    if supervisor.isDevelopmentChat {
      Text("Background execution is not enabled for this development slice.")
        .font(DS.Typography.callout)
    } else {
      switch supervisor.registration {
      case .notRegistered:
        Button("Enable Background Service") { supervisor.enableBackgroundService() }
          .disabled(supervisor.isBusy)
      case .enabled:
        Button("Disable Background Service…") { confirmDisable = true }
          .disabled(supervisor.isBusy)
      case .requiresApproval:
        Text(
          "Approval is required in System Settings. Until then the app can own a foreground helper."
        )
        .font(DS.Typography.callout)
        Button("Open Background Settings") { supervisor.openBackgroundSettings() }
        Button("Disable Background Service…") { confirmDisable = true }
          .disabled(supervisor.isBusy)
      case .notFound:
        Text(
          "macOS could not find the background service. A complete signed app can still run its helper while open."
        )
        .font(DS.Typography.callout)
        Button("Enable Background Service") { supervisor.enableBackgroundService() }
          .disabled(supervisor.isBusy)
        Button("Reveal App") { supervisor.revealAppForRepair() }
      case .unknown:
        Text("Background service status is unavailable. No background registration was changed.")
          .font(DS.Typography.callout)
        Button("Reveal App") { supervisor.revealAppForRepair() }
      }
    }
  }

  private var registrationTitle: LocalizedStringResource {
    switch supervisor.registration {
    case .notRegistered: "Not registered"
    case .enabled: "Enabled (eligible to run)"
    case .requiresApproval: "Approval required"
    case .notFound: "Not found"
    case .unknown: "Unavailable"
    }
  }
}

extension DaemonSupervisionError {
  var message: LocalizedStringResource {
    switch self {
    case .signingRequired:
      "Sign Memoshi and its bundled helper with matching Apple-issued Team IDs and hardened runtime. Ad-hoc builds cannot authenticate."
    case .versionMismatch:
      "Install a matching signed Memoshi app and helper. The daemon and app have no shared protocol version."
    case .damagedBundle:
      "The app or helper bundle is incomplete. Restore a complete signed Memoshi app, then try again."
    case .unsafeDataDirectory:
      "The daemon data directory has unsafe ownership, permissions or a symlink. Repair it before reconnecting; this app will not silently change permissions."
    case .authenticationFailed:
      "The daemon's running-code identity could not be verified. Check that the bundled helper and app are signed by the same expected team."
    case .startServiceFailed:
      "The registered service could not be started. Check Background Settings or restore a matching signed app bundle. No existing daemon was killed."
    case .registrationFailed:
      "Background registration could not be changed. Check System Settings and the app's signature, then try the explicit action again."
    case .existingDaemonNotOwned:
      "A signed daemon is already running outside this app's ownership. Stop it using its owner before enabling background service. Memoshi will not kill it or launch a duplicate."
    case .connectionFailed:
      "The daemon did not complete a usable connection. Retry; preview examples are not connected models or canonical state."
    case .helperExited(let status):
      "The app-owned helper exited with status \(status). Restore the signed helper or retry starting it."
    case .helperTerminated(let signal):
      "The app-owned helper was terminated by signal \(signal). Memoshi is restarting it and will reconnect from the last applied event."
    case .restartLimitReached(let exits):
      "The app-owned helper stopped unexpectedly \(exits) times within five minutes, so automatic restarts stopped. Choose Start Daemon to try again."
    case .quitBlocked:
      "The app-owned helper has not finished shutting down. Memoshi will stay open rather than leave a stray process or force-kill it. Wait and quit again."
    case .agentStillRunning:
      "The background service's daemon has not stopped. Memoshi will not start its own helper beside it or force it to quit. Wait, then choose Start Daemon."
    }
  }
}

extension DaemonStatusNote {
  var message: LocalizedStringResource {
    switch self {
    case .problem(let problem): problem.message
    case .waiting(.connecting): "Connecting to the local daemon…"
    case .waiting(.helperStarting):
      "The daemon is starting. Memoshi connects as soon as it is ready."
    case .waiting(.agentStopping):
      "The background service is stopping. Memoshi starts its own helper once it has exited."
    case .daemonStopped:
      "The daemon is stopped. Start it without changing background registration."
    case .versionMismatch:
      "Install a matching signed Memoshi app and bundled helper. No protocol version is shared."
    case .signingRequired: DaemonSupervisionError.signingRequired.message
    }
  }
}
