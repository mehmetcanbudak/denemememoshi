import AppCore
import DesignSystem
import MemoshiProtocol
import SwiftUI

/// One approval Card from the shared approval projection, the same entries and decisions the Mac
/// shows. Only Allow once and Deny exist in this development profile.
struct MobileApprovalCardView: View {
  let entry: ApprovalReviewEntry
  let model: LiveApprovalModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let tier = entry.approval.flatMap { DesignRiskTier(level: Int($0.tier.rawValue)) }
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      // One grouped summary heading with named decisions (02 §13.2, A4/A5).
      VStack(alignment: .leading, spacing: DS.Space.s4) {
        // Accessibility sizes stack the status under the kind; side by side, "Approval" was
        // squeezed until it broke mid-word (A24).
        let header =
          dynamicTypeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s2))
          : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        header {
          Label("Approval", systemImage: "hand.raised")
            .font(DS.Typography.callout.weight(.semibold))
          if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: DS.Space.s3) }
          Text(statusText)
            .font(DS.Typography.callout.weight(.medium))
        }
        Text(verbatim: entry.card.title.rawValue)
          .font(.headline)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(summary(tier: tier).label))
      .accessibilityValue(Text(summary(tier: tier).value))
      .accessibilityAddTraits(.isHeader)
      .accessibilityActions {
        if entry.isPending && model.canRespond(to: entry) {
          Button("Allow once") { model.respond(to: entry, action: .allowOnce) }
          Button("Deny") { model.respond(to: entry, action: .deny) }
        }
      }
      .accessibilityIdentifier("approval.status.\(entry.id.rawValue)")
      if let approval = entry.approval {
        Label {
          if let tier {
            Text("Tool: \(approval.tool) · \(String(localized: tier.badge))")
          } else {
            Text("Tool: \(approval.tool) · T\(approval.tier.rawValue)")
          }
        } icon: {
          Image(systemName: tier?.glyph ?? "questionmark.diamond")
        }
        .font(.subheadline.monospaced())
        .foregroundStyle(tier?.foreground ?? DS.Colors.Text.secondary)
        // Tool names, arguments and policy codes stay left-to-right in mirrored chrome (L4).
        .environment(\.layoutDirection, .leftToRight)
        if let preview = entry.argumentsPreview {
          Text(verbatim: preview)
            .font(DS.Typography.callout.monospaced())
            .foregroundStyle(DS.Colors.Text.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.layoutDirection, .leftToRight)
        }
        Text("Policy reason: \(approval.reasonCode)")
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
          .environment(\.layoutDirection, .leftToRight)
        if !entry.hasValidBinding {
          Text(
            "The card and approval do not match. Decisions are disabled until review state reloads."
          )
          .font(.callout)
        }
      } else {
        Text("The approval details have not loaded. This card cannot be answered yet.")
          .font(.callout)
      }
      if let issue = model.issues[entry.id] {
        Text(verbatim: issue)
          .font(.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
          .accessibilityIdentifier("approval.error.\(entry.id.rawValue)")
      }
      if let notice = model.notices[entry.id] {
        Text(verbatim: notice)
          .font(.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
      }
      actions.id(Self.actionsAnchor(entry.id))
    }
    .padding(DS.Space.s5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DS.Colors.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.card))
    .designBoundary(RoundedRectangle(cornerRadius: DS.Radius.card))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("approval.card.\(entry.id.rawValue)")
  }

  /// The scroll identity of the Card's buttons, which the Chat keeps in view while it is pending.
  static func actionsAnchor(_ card: CardID) -> String { "approval.actions." + card.rawValue }

  @ViewBuilder private var actions: some View {
    let hasUnconfirmedResponse = model.hasUnconfirmedResponse(for: entry.id)
    if hasUnconfirmedResponse || entry.isPending {
      VStack(alignment: .leading, spacing: DS.Space.s4) {
        if hasUnconfirmedResponse {
          HStack(spacing: DS.Space.s4) {
            Button("Retry Same Decision") { model.retry(entry) }
              .buttonStyle(.bordered)
              .controlSize(.large)
              .disabled(!model.canRetry(entry))
              .accessibilityIdentifier("approval.retry.\(entry.id.rawValue)")
            if model.sending.contains(entry.id) { ProgressView() }
          }
        } else {
          // Side by side when they fit; otherwise one per line, so neither title wraps. One
          // view tree: ViewThatFits's two copies were reported as Dynamic Type "partially
          // unsupported" on both buttons.
          DesignFittingStack(spacing: DS.Space.s4) { decisions }
        }
        // Disabled decisions say why while review state is not connected or not current.
        if let notice = model.synchronizationNotice {
          Label {
            Text(verbatim: notice)
          } icon: {
            Image(systemName: "network.slash")
          }
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("approval.unsynchronized.\(entry.id.rawValue)")
        }
      }
    }
  }

  @ViewBuilder private var decisions: some View {
    let notice = Text(verbatim: model.synchronizationNotice ?? "")
    Button("Deny", role: .destructive) { model.respond(to: entry, action: .deny) }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .disabled(!model.canRespond(to: entry))
      .accessibilityHint(notice)
      .accessibilityIdentifier("approval.deny.\(entry.id.rawValue)")
    Button("Allow once") { model.respond(to: entry, action: .allowOnce) }
      .buttonStyle(.designProminent(minimumSize: DS.Layout.Composer.minHeight))
      .disabled(!model.canRespond(to: entry))
      .accessibilityHint(notice)
      .accessibilityIdentifier("approval.allowOnce.\(entry.id.rawValue)")
  }

  private var statusText: LocalizedStringResource {
    switch entry.state(at: model.now) {
    case .allowedOnce: "Allowed once · execution not confirmed"
    case .allowed: "Allowed · execution not confirmed"
    case .denied: "Denied"
    case .resolved(let action?): "Resolved: \(action)"
    case .resolved(nil): "Resolved"
    case .expired: "Expired · not authorized"
    case .canceled: "Canceled · not authorized"
    case .deadlinePassed: "Deadline passed · awaiting runner state"
    case .pending: "Pending"
    case .unsupported: "Unsupported card state · decisions disabled"
    }
  }

  private func summary(tier: DesignRiskTier?) -> DesignCardAccessibility {
    DesignCardAccessibility(
      kind: String(localized: "Approval"),
      origin: entry.approval.map { String(localized: $0.origin.kind.summaryLabel) }
        ?? String(localized: "an unloaded source"),
      tier: tier, title: entry.card.title.rawValue, state: String(localized: statusText),
      remainingMilliseconds: entry.isPending ? entry.expiresAt.map { $0 - model.now } : nil)
  }
}

extension OriginKind {
  fileprivate var summaryLabel: LocalizedStringResource {
    switch self {
    case .user: "User"
    case .assistant: "Assistant"
    case .bot: "Bot"
    case .routine: "Routine"
    case .wake: "Wake"
    case .watch: "Watch"
    case .webhook: "Webhook"
    case .connectorEvent: "Connector event"
    case .intent: "Intent or Shortcut"
    case .app: "App"
    case .unknown: "Unsupported source"
    }
  }
}
