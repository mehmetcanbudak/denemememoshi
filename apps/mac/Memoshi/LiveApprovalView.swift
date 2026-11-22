import AppCore
import DesignSystem
import MemoshiProtocol
import SwiftUI

/// A standalone Waiting for You list with its own card focus, for hosts without a workspace.
struct LiveWaitingView: View {
  let model: LiveApprovalModel
  @FocusState private var focus: LiveWorkspaceFocus?

  var body: some View {
    LiveWaitingList(model: model, focus: $focus)
  }
}

struct LiveWaitingList: View {
  let model: LiveApprovalModel
  var focus: FocusState<LiveWorkspaceFocus?>.Binding
  @State private var showsRecordedDecisions = true

  var body: some View {
    VStack(spacing: DS.Space.s0) {
      LiveWaitingHeader(model: model)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: DS.Space.s6) {
          if let problem = model.problem {
            Text(verbatim: problem)
              .font(.callout)
              .foregroundStyle(DS.Colors.Text.secondary)
              .accessibilityIdentifier("approvals.error")
          }
          if !model.hasLoaded {
            ContentUnavailableView {
              Label("Approval State Not Loaded", systemImage: "arrow.triangle.2.circlepath")
            } description: {
              Text(
                "Connect to the authenticated local runner to load real approvals and cards. No sample request or permission is shown."
              )
              .foregroundStyle(DesignControlRoles.secondaryText)
            }
          } else if model.pendingGroups.isEmpty {
            ContentUnavailableView {
              Label("Nothing Waiting for You", systemImage: "hand.raised")
            } description: {
              Text(
                "There are no pending approval cards in the loaded runner state. Production tools and Apple connectors remain disabled."
              )
              .foregroundStyle(DesignControlRoles.secondaryText)
            }
          }
          ForEach(model.pendingGroups) { group in
            LiveApprovalGroupView(group: group, model: model, focus: focus)
          }
          ForEach(model.unmatchedResponseIDs, id: \.self) { id in
            LiveUnmatchedApprovalResponse(cardID: id, model: model)
          }
          if !model.recentGroups.isEmpty {
            DisclosureGroup(isExpanded: $showsRecordedDecisions) {
              LazyVStack(alignment: .leading, spacing: DS.Space.s6) {
                ForEach(model.recentGroups) { group in
                  LiveApprovalGroupView(group: group, model: model, focus: focus)
                }
              }
              .padding(.top, DS.Space.s4)
            } label: {
              Text("Recorded Decisions")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            }
          }
        }
        .frame(maxWidth: DS.Layout.Conversation.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(DS.Space.s6)
      }
    }
    .background(DS.Colors.Surface.window)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("approvals.waitingForYou")
  }
}

private struct LiveWaitingHeader: View {
  let model: LiveApprovalModel

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      HStack {
        Text("Waiting for You").font(.title2.weight(.semibold))
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: DS.Space.s3)
        if model.isLoading { ProgressView().controlSize(.small) }
        Button("Reload Review", systemImage: "arrow.clockwise") { model.refresh() }
          .disabled(model.isLoading || !model.isConnected)
          .accessibilityIdentifier("approvals.reload")
      }
      Text("\(model.pendingCount) pending · Allow once or Deny only")
        .font(.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
      Text(
        "A decision applies to one call. It does not enable production tools, standing rules or device-owner authentication."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      if let notice = model.synchronizationNotice {
        LiveApprovalSynchronizationNotice(notice: notice)
          .accessibilityIdentifier("approvals.unsynchronized")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DS.Space.s6)
  }
}

struct LiveApprovalGroupView: View {
  let group: ApprovalReviewGroup
  let model: LiveApprovalModel
  var focus: FocusState<LiveWorkspaceFocus?>.Binding

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      if group.entries.count > 1
        || group.entries.contains(where: {
          $0.approval?.parentToolCallId != nil
        })
      {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
          Label("Related Tool Calls", systemImage: "point.3.connected.trianglepath.dotted")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
          Text("Parent call: \(group.id.rootCallId)")
            .font(DS.Typography.callout.monospaced())
            .foregroundStyle(DS.Colors.Text.secondary)
            .textSelection(.enabled)
            .environment(\.layoutDirection, .leftToRight)
        }
      }
      ForEach(group.entries) { entry in
        LiveApprovalCardView(entry: entry, model: model, focus: focus)
      }
    }
  }
}

/// These are the same card identities and actions in the transcript and Waiting for You.
/// Key handlers exist only on the actually focused card, never as window-global shortcuts.
struct LiveApprovalCardView: View {
  let entry: ApprovalReviewEntry
  let model: LiveApprovalModel
  var focus: FocusState<LiveWorkspaceFocus?>.Binding
  @Environment(\.effectiveIncreasedContrast) private var increasedContrast

  private var isCardFocused: Bool { focus.wrappedValue == .card(entry.id) }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      LiveApprovalHeader(entry: entry, model: model)
      if let approval = entry.approval {
        LiveApprovalDetails(approval: approval, argumentsPreview: entry.argumentsPreview)
        if !entry.hasValidBinding {
          Text(
            "The card and approval do not have a consistent binding. Decisions are disabled; reload authoritative review state."
          )
          .font(.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
        }
      } else {
        Text(
          "The approval details have not been loaded. This card cannot be answered until its matching approval is available."
        )
        .font(.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
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
      LiveApprovalActions(entry: entry, model: model)
    }
    .padding(DS.Space.s5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DS.Colors.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.card))
    .overlay {
      RoundedRectangle(cornerRadius: DS.Radius.card)
        .strokeBorder(
          isCardFocused
            ? DS.Colors.Text.primary
            : DesignControlRoles.boundary(
              standard: DS.Colors.Border.field, increasedContrast: increasedContrast))
    }
    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card))
    .focusable()
    .focused(focus, equals: .card(entry.id))
    .simultaneousGesture(TapGesture().onEnded { focus.wrappedValue = .card(entry.id) })
    .onKeyPress(.return, phases: .down) { press in
      guard isCardFocused, model.canRespond(to: entry), let tier = entry.approval?.tier.rawValue
      else { return .ignored }
      let allows =
        (tier == 1 || tier == 2) && press.modifiers.isEmpty
        || tier == 3 && press.modifiers == .command
      guard allows else { return .ignored }
      model.respond(to: entry, action: .allowOnce)
      return .handled
    }
    .onKeyPress(.escape, phases: .down) { press in
      guard isCardFocused, press.modifiers.isEmpty, model.canRespond(to: entry) else {
        return .ignored
      }
      model.respond(to: entry, action: .deny)
      return .handled
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("approval.card.\(entry.id.rawValue)")
  }
}

/// The card's first element: one grouped summary with its tier and named decisions (02 §13.2).
private struct LiveApprovalHeader: View {
  let entry: ApprovalReviewEntry
  let model: LiveApprovalModel

  var body: some View {
    let tier = entry.approval.flatMap { DesignRiskTier(level: Int($0.tier.rawValue)) }
    VStack(alignment: .leading, spacing: DS.Space.s2) {
      VStack(alignment: .leading, spacing: DS.Space.s2) {
        HStack(alignment: .firstTextBaseline) {
          Label("Approval", systemImage: "hand.raised")
            .font(DS.Typography.callout.weight(.semibold))
          Spacer(minLength: DS.Space.s3)
          Text(entry.reviewStatus(at: model.now))
            .font(DS.Typography.callout.weight(.medium))
        }
        Text(verbatim: entry.card.title.rawValue)
          .font(.headline)
          .textSelection(.enabled)
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
      .accessibilityIdentifier("approval.summary.\(entry.id.rawValue)")
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
        .textSelection(.enabled)
        // Tool names, IDs, arguments and targets stay left-to-right in mirrored chrome (L4).
        .environment(\.layoutDirection, .leftToRight)
      }
      if let expiresAt = entry.expiresAt {
        let expiry = Date(timeIntervalSince1970: Double(expiresAt) / 1_000)
        Text("Deadline: \(expiry, format: .dateTime.year().month().day().hour().minute().second())")
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
      }
      Text("Conversation: \(entry.card.conversationId.rawValue)")
        .font(DS.Typography.callout.monospaced())
        .foregroundStyle(DS.Colors.Text.secondary)
        .textSelection(.enabled)
        .environment(\.layoutDirection, .leftToRight)
    }
  }

  private func summary(tier: DesignRiskTier?) -> DesignCardAccessibility {
    DesignCardAccessibility(
      kind: String(localized: "Approval"),
      origin: entry.approval.map { String(localized: $0.origin.kind.reviewLabel) }
        ?? String(localized: "an unloaded source"),
      tier: tier, title: entry.card.title.rawValue,
      state: String(localized: entry.reviewStatus(at: model.now)),
      remainingMilliseconds: entry.isPending ? entry.expiresAt.map { $0 - model.now } : nil)
  }
}

extension ApprovalReviewEntry {
  /// The visible and spoken card state.
  func reviewStatus(at now: Int64) -> LocalizedStringResource {
    switch state(at: now) {
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
}

private struct LiveApprovalDetails: View {
  let approval: Approval
  let argumentsPreview: String?

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      LabeledContent("Mode") {
        Text(approval.permissionMode.reviewLabel)
      }
      LabeledContent("Source") {
        Text(approval.origin.kind.reviewLabel)
      }
      if approval.origin.rootKind != approval.origin.kind || approval.origin.hops.rawValue > 0 {
        LabeledContent("Root source") {
          Text(approval.origin.rootKind.reviewLabel)
        }
        Text("Delegation hops: \(approval.origin.hops.rawValue)")
      }
      if let sourceID = approval.origin.id {
        Text("Source ID: \(sourceID)").textSelection(.enabled)
          .environment(\.layoutDirection, .leftToRight)
      }
      if let parent = approval.parentToolCallId {
        Text("Parent call: \(parent)").textSelection(.enabled)
          .environment(\.layoutDirection, .leftToRight)
      }
      Text("Call: \(approval.toolCallId)").textSelection(.enabled)
        .environment(\.layoutDirection, .leftToRight)
      if let argumentsPreview {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
          Text("Sanitized Arguments").font(DS.Typography.callout.weight(.semibold))
          Text(verbatim: argumentsPreview)
            .font(DS.Typography.callout.monospaced())
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.layoutDirection, .leftToRight)
        }
      } else {
        Text("Sanitized arguments are unavailable.")
      }
      VStack(alignment: .leading, spacing: DS.Space.s2) {
        Text("Sanitized Targets").font(DS.Typography.callout.weight(.semibold))
        if approval.targets.isEmpty {
          Text("No targets declared")
        } else {
          Text(verbatim: approval.targets.joined(separator: "\n"))
            .font(DS.Typography.callout.monospaced())
            .textSelection(.enabled)
            .environment(\.layoutDirection, .leftToRight)
        }
      }
      Text("Policy reason: \(approval.reasonCode)")
        .environment(\.layoutDirection, .leftToRight)
      if approval.tier.rawValue >= 4 {
        Text(
          "This tier needs device-owner authentication. This development profile cannot provide it; no authentication success is simulated."
        )
      }
    }
    .font(DS.Typography.callout)
    .foregroundStyle(DS.Colors.Text.secondary)
  }
}

private struct LiveApprovalActions: View {
  let entry: ApprovalReviewEntry
  let model: LiveApprovalModel

  var body: some View {
    // Disabled decisions say why, here and in the transcript, not only in Waiting for You.
    let notice = model.synchronizationNotice
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      if model.hasUnconfirmedResponse(for: entry.id) {
        if model.pendingAction(for: entry.id) == .allowOnce {
          Text("Saved Allow once decision. Retrying preserves the exact original request.")
            .font(DS.Typography.callout)
        } else {
          Text("Saved Deny decision. Retrying preserves the exact original request.")
            .font(DS.Typography.callout)
        }
        HStack(spacing: DS.Space.s4) {
          Button("Retry Same Decision") { model.retry(entry) }
            .disabled(!model.canRetry(entry))
            .help(
              "Reuses the original request. A terminal card can only return its receipt or refuse the answer; it cannot be reopened."
            )
            .accessibilityIdentifier("approval.retry.\(entry.id.rawValue)")
          if model.sending.contains(entry.id) { ProgressView().controlSize(.small) }
        }
      } else if entry.isPending {
        HStack(spacing: DS.Space.s4) {
          Button("Allow once") { model.respond(to: entry, action: .allowOnce) }
            .disabled(!model.canRespond(to: entry))
            .help(Text(verbatim: notice ?? ""))
            .accessibilityIdentifier("approval.allowOnce.\(entry.id.rawValue)")
          Button("Deny", role: .destructive) { model.respond(to: entry, action: .deny) }
            .disabled(!model.canRespond(to: entry))
            .help(Text(verbatim: notice ?? ""))
            .accessibilityIdentifier("approval.deny.\(entry.id.rawValue)")
        }
        if let tier = entry.approval?.tier.rawValue, tier == 1 || tier == 2 {
          Text("Focused card: Return allows once · Esc denies")
            .font(DS.Typography.subheadline)
            .foregroundStyle(DS.Colors.Text.secondary)
        } else if entry.approval?.tier.rawValue == 3 {
          Text("Focused card: ⌘Return allows once · Esc denies")
            .font(DS.Typography.subheadline)
            .foregroundStyle(DS.Colors.Text.secondary)
        }
      }
      if let notice, entry.isPending || model.hasUnconfirmedResponse(for: entry.id) {
        LiveApprovalSynchronizationNotice(notice: notice)
          .foregroundStyle(DS.Colors.Text.secondary)
          .accessibilityIdentifier("approval.unsynchronized.\(entry.id.rawValue)")
      }
    }
  }
}

/// Why decisions are disabled while review state is not connected or not current.
private struct LiveApprovalSynchronizationNotice: View {
  let notice: String

  var body: some View {
    Label {
      Text(verbatim: notice)
    } icon: {
      Image(systemName: "network.slash")
    }
    .font(DS.Typography.callout)
  }
}

private struct LiveUnmatchedApprovalResponse: View {
  let cardID: CardID
  let model: LiveApprovalModel

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Text("Decision Receipt Review").font(.headline).accessibilityAddTraits(.isHeader)
      Text("Card: \(cardID.rawValue)")
        .font(DS.Typography.callout.monospaced())
        .textSelection(.enabled)
        .environment(\.layoutDirection, .leftToRight)
      Text(
        "No matching card is present in the loaded runner state. When a saved decision exists, checking its receipt sends exactly the original opaque request, never a replacement answer."
      )
      .font(.callout)
      if let issue = model.issues[cardID] { Text(verbatim: issue).font(.callout) }
      if model.hasUnconfirmedResponse(for: cardID) {
        Button("Check Saved Receipt") { model.retrySavedResponse(for: cardID) }
          .disabled(!model.canRetrySavedResponse(for: cardID))
          .accessibilityIdentifier("approval.recover.\(cardID.rawValue)")
      }
    }
    .padding(DS.Space.s5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DS.Colors.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.card))
  }
}

extension PermissionMode {
  fileprivate var reviewLabel: LocalizedStringResource {
    switch self {
    case .askFirst: "Ask first"
    case .auto: "Auto"
    case .bypass: "Bypass"
    case .unknown: "Unsupported mode"
    }
  }
}

extension OriginKind {
  fileprivate var reviewLabel: LocalizedStringResource {
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
