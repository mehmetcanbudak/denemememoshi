import DesignSystem
import MemoshiClient
import MemoshiProtocol
import SwiftUI

/// The development HUD: what this app's own client observed. It reads app state only and sends
/// nothing to memoshid. Turn timings are client-observed; daemon overhead is not invented.
struct DevelopmentHUDView: View {
  let supervisor: DaemonSupervisor
  let chat: LiveChatModel

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Grid(alignment: .leading, horizontalSpacing: DS.Space.s5, verticalSpacing: DS.Space.s2) {
        row("Protocol", protocolText, id: "hud.protocol")
        row("Schema", schemaText, id: "hud.schema")
        row("Connection", connectionText, id: "hud.connection")
        row("Helper", helperText, id: "hud.helper")
        row("Applied seq", appliedSeqText, id: "hud.seq")
        row("Applied events", appliedEventsText, id: "hud.appliedEvents")
        row("Pending", pendingText, id: "hud.pending")
        row("Injected latency", latencyText, id: "hud.latency")
        row("Time to first delta", firstDeltaText, id: "hud.firstDelta")
        row("Turn duration", turnDurationText, id: "hud.turnDuration")
        row(
          "memoshid overhead", String(localized: "Unavailable"), id: "hud.memoshidOverhead")
      }
      Text(
        "Timings run from Send in this app. The protocol carries no daemon-side provider request or first-byte times, so memoshid overhead cannot be separated from model time."
      )
      .font(DS.Typography.subheadline)
      .foregroundStyle(DS.Colors.Text.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .font(DS.Typography.callout.monospacedDigit())
    .padding(DS.Space.s5)
    .frame(width: DS.Layout.Inspector.default, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("hud.panel")
  }

  private func row(_ label: LocalizedStringKey, _ value: String, id: String) -> some View {
    GridRow {
      Text(label)
        .foregroundStyle(DS.Colors.Text.secondary)
        .accessibilityHidden(true)
      Text(verbatim: value)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: value))
        .accessibilityIdentifier(id)
    }
  }

  private var status: ClientStatus? { supervisor.clientStatus }

  private var protocolText: String {
    status?.hello.map { String($0.protocolVersion) } ?? "—"
  }

  /// The negotiated canonical-schema hash, shortened for display.
  private var schemaText: String {
    guard let hash = status?.hello?.schemaHash else { return "—" }
    let digest = hash.split(separator: ":").last.map(String.init) ?? hash
    return String(digest.prefix(12))
  }

  private var connectionText: String {
    guard let status else { return String(localized: "Not started") }
    var parts = [status.state.rawValue]
    if status.isSubscribed { parts.append(String(localized: "subscribed")) }
    if status.resync != nil { parts.append(String(localized: "loading snapshots")) }
    if chat.connectionCount > 0 {
      parts.append(String(localized: "connection \(chat.connectionCount)"))
    }
    return parts.joined(separator: " · ")
  }

  // Process IDs, exit codes and sequence numbers are identifiers: never locale-grouped.
  private var helperText: String {
    var parts: [String] = []
    if let pid = supervisor.ownedHelperPID {
      parts.append(String(localized: "PID \(String(pid)), app-owned"))
    } else if let pid = status?.hello?.daemon.pid {
      parts.append(String(localized: "PID \(String(pid)), not app-owned"))
    } else {
      parts.append(String(localized: "not connected"))
    }
    switch supervisor.helperRecovery {
    case .idle: break
    case .restarting(let attempt): parts.append(String(localized: "restarting, attempt \(attempt)"))
    case .stopped(let exits):
      parts.append(String(localized: "restarts stopped after \(exits) exits"))
    }
    if let exit = supervisor.lastHelperExit {
      parts.append(
        exit.signaled
          ? String(localized: "last exit signal \(String(exit.status))")
          : String(localized: "last exit status \(String(exit.status))"))
    }
    return parts.joined(separator: " · ")
  }

  private var appliedSeqText: String {
    guard let status else { return "—" }
    var parts = [status.lastAppliedSeq.map(String.init) ?? "—"]
    if let head = status.hello?.head {
      parts.append(String(localized: "hello head \(String(head))"))
    }
    return parts.joined(separator: " · ")
  }

  private var appliedEventsText: String {
    guard let applied = chat.appliedEvents else { return String(localized: "No baseline yet") }
    let baseline = String(applied.baseline)
    guard let last = applied.last else {
      return String(localized: "None since baseline \(baseline)")
    }
    let range = String(
      localized: "\(applied.count) after baseline \(baseline), through \(String(last))")
    return applied.isContiguous
      ? String(localized: "\(range), contiguous") : String(localized: "\(range), not contiguous")
  }

  private var pendingText: String {
    var parts = [
      String(localized: "\(status?.pendingCalls ?? 0) RPCs"),
      String(localized: "\(chat.reviews.pendingCount) approvals"),
      String(localized: "\(chat.queued.count) queued"),
    ]
    if chat.hasUnconfirmedSend { parts.append(String(localized: "send unconfirmed")) }
    return parts.joined(separator: " · ")
  }

  private var latencyText: String {
    guard supervisor.supportsLinkConditions else { return String(localized: "Unavailable") }
    guard supervisor.injectedLatency > .zero else { return String(localized: "Off") }
    return String(localized: "\(Self.milliseconds(supervisor.injectedLatency)) each way")
  }

  private var firstDeltaText: String {
    guard let turn = chat.lastTurn else { return String(localized: "No turn yet") }
    if let delta = turn.firstDelta { return Self.milliseconds(delta) }
    return turn.duration == nil
      ? String(localized: "Waiting") : String(localized: "No streamed delta observed")
  }

  private var turnDurationText: String {
    guard let turn = chat.lastTurn else { return String(localized: "No turn yet") }
    guard let duration = turn.duration else { return String(localized: "In progress") }
    let status = turn.status?.rawValue ?? ""
    return "\(Self.milliseconds(duration)) · \(status)"
  }

  /// Whole milliseconds without digit grouping, so a value can never read as a decimal.
  private static func milliseconds(_ duration: Duration) -> String {
    let value = Int((duration / .milliseconds(1)).rounded())
    return String(localized: "\(String(value)) ms")
  }
}
