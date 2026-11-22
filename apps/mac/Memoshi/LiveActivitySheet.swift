import DesignSystem
import Foundation
import MemoshiProtocol
import SwiftUI

/// A bounded live projection, not the historical or tamper-verified audit service.
struct LiveActivitySheet: View {
  let events: [EventEnvelope]
  let baseline: Int64?
  let omittedCount: Int
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      HStack {
        Text("Live Activity").font(.title2).accessibilityAddTraits(.isHeader)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text(
        "Development · Committed metadata received by this app across the connected daemon. No argument, output or credential inspection."
      )
      .font(.callout).foregroundStyle(DS.Colors.Text.secondary)
      if events.isEmpty {
        ContentUnavailableView(
          "No Live Activity Received", systemImage: "list.bullet.rectangle",
          description: Text(
            "Policy, tool and gateway events appear here after the current snapshot."))
      } else {
        List {
          ForEach(events.reversed(), id: \.seq) { envelope in
            LiveActivityRow(envelope: envelope)
          }
        }
        .accessibilityIdentifier("activity.events")
      }
      if let baseline {
        Text("Live projection starts after snapshot sequence \(baseline).")
          .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
      }
      if omittedCount > 0 {
        Text("\(omittedCount) earlier events omitted from this bounded view.")
          .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
      }
      Text(
        "Resynchronizing clears this view. Historical audit and tamper verification are not loaded here; missing rows do not prove that no activity occurred."
      )
      .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
    }
    .padding(DS.Space.s6)
    .designSheetFrame(idealWidth: DS.Layout.Sheet.botProfileWidth)
  }
}

private struct LiveActivityRow: View {
  let envelope: EventEnvelope

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s2) {
      HStack {
        Text(eventName).font(.headline)
        Spacer()
        Text(
          Date(timeIntervalSince1970: Double(envelope.ts) / 1_000),
          format: .dateTime.hour().minute().second()
        )
        .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
      }
      eventContent
      VStack(alignment: .leading, spacing: DS.Space.s1) {
        if let bot = envelope.scope.botId { Text("Bot: \(bot.rawValue)") }
        if let conversation = envelope.scope.conversationId {
          Text("Conversation: \(conversation.rawValue)")
        }
        if let task = envelope.scope.taskId {
          Text("Task: \(task.rawValue)")
        } else {
          Text("Task: not attributed")
        }
        if let seq = envelope.seq { Text("Sequence: \(seq)") }
      }
      .font(DS.Typography.callout.monospaced()).foregroundStyle(DS.Colors.Text.secondary)
      // Identifiers stay left-to-right in mirrored chrome (L4).
      .environment(\.layoutDirection, .leftToRight)
    }
    .textSelection(.enabled)
    // One stop per event: its name, subject, time and attribution read together (A25).
    .accessibilityElement(children: .combine)
  }

  /// A localized event name; unprojected wire types fall back to the raw type.
  private var eventName: LocalizedStringResource {
    switch envelope.event {
    case .egressAllowed: "Connection admitted"
    case .egressBlocked: "Connection refused"
    case .secretUsed: "Credential prepared"
    case .policyDecided: "Policy decision"
    case .policyRedacted: "Output redacted"
    case .toolCompleted: "Tool completed"
    default: "Event \(envelope.type)"
    }
  }

  @ViewBuilder private var eventContent: some View {
    switch envelope.event {
    case .egressAllowed(let value):
      Label("Connection admitted, not delivery confirmed", systemImage: "network")
      Text(verbatim: value.host).environment(\.layoutDirection, .leftToRight)
      Text("Computer: \(value.computerId)").font(DS.Typography.callout)
    case .egressBlocked(let value):
      Label("Connection refused", systemImage: "network.slash")
      Text(verbatim: value.host).environment(\.layoutDirection, .leftToRight)
      Text("Computer: \(value.computerId) · Refusals represented: \(value.count)").font(
        DS.Typography.callout)
    case .secretUsed(let value):
      Label("Credential association prepared, not delivery confirmed", systemImage: "key")
      Text(verbatim: value.host).environment(\.layoutDirection, .leftToRight)
      Text("Association: \(value.secretRef) · Purpose: \(String(localized: value.purpose.label))")
        .font(DS.Typography.callout)
    case .policyDecided(let value):
      Label("Policy decision", systemImage: "checkmark.shield")
      Text(verbatim: value.tool).environment(\.layoutDirection, .leftToRight)
      Text("Decision: \(String(localized: value.decision.label)) · Rule: \(value.ruleId)").font(
        DS.Typography.callout)
      if let via = value.via {
        Text("Via: \(String(localized: via.label))").font(DS.Typography.callout)
      }
      callIdentity(value.toolCallId, parent: value.parentToolCallId)
    case .policyRedacted(let value):
      Label("Output redacted", systemImage: "eye.slash")
      Text("Redactions or withheld result: \(value.count)").font(DS.Typography.callout)
      if !value.kinds.isEmpty {
        Text(verbatim: value.kinds.joined(separator: ", ")).font(DS.Typography.callout)
      }
      callIdentity(value.toolCallId, parent: nil)
    case .toolCompleted(let value):
      Label(value.ok ? "Tool result committed" : "Tool failure committed", systemImage: "wrench")
      Text(verbatim: value.tool).environment(\.layoutDirection, .leftToRight)
      if let code = value.errorCode { Text("Error category: \(code)").font(DS.Typography.callout) }
      if value.durationMs > 0 {
        Text("Reported SDK execution: \(value.durationMs) ms").font(DS.Typography.callout)
      } else {
        Text("SDK execution measurement unavailable").font(DS.Typography.callout)
      }
      Text("Output bytes: \(value.outputBytes) · Redactions: \(value.redactions)")
        .font(DS.Typography.callout)
      callIdentity(value.toolCallId, parent: value.parentToolCallId)
    default:
      Text("This event is outside the live policy, tool and gateway projection.")
        .foregroundStyle(DS.Colors.Text.secondary)
    }
  }

  private func callIdentity(_ call: String, parent: String?) -> some View {
    VStack(alignment: .leading, spacing: DS.Space.s1) {
      Text("Call: \(call)")
      if let parent { Text("Parent call: \(parent)") }
    }
    .font(DS.Typography.callout.monospaced()).foregroundStyle(DS.Colors.Text.secondary)
    .environment(\.layoutDirection, .leftToRight)
  }
}

extension SecretUsePurpose {
  fileprivate var label: LocalizedStringResource {
    switch self {
    case .browserFill: "Browser fill"
    case .egressPlaceholder: "Gateway placeholder"
    case .execEnv: "Command environment"
    case .unknown(let raw): "Unrecognized (\(raw))"
    }
  }
}

extension PolicyDecisionKind {
  fileprivate var label: LocalizedStringResource {
    switch self {
    case .allow: "Allow"
    case .ask: "Ask"
    case .draft: "Draft"
    case .deny: "Deny"
    case .rewrite: "Rewrite"
    case .unknown(let raw): "Unrecognized (\(raw))"
    }
  }
}

extension ToolCallVia {
  fileprivate var label: LocalizedStringResource {
    switch self {
    case .model: "Model"
    case .codeMode: "Code Mode"
    case .mcp: "MCP"
    case .unknown(let raw): "Unrecognized (\(raw))"
    }
  }
}
