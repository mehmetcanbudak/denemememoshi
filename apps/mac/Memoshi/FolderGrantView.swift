import DesignSystem
import MemoshiProtocol
import SwiftUI
import UniformTypeIdentifiers

/// The Assistant's local folder grants. The system folder panel only opens a review; granting,
/// changing access and revoking are separate, explicitly confirmed runtime requests.
struct FolderGrantView: View {
  let folders: FolderGrantSetup
  @Environment(\.dismiss) private var dismiss
  @State private var isChoosingFolder = false
  @State private var revocation: FolderGrantSummary? = nil
  @State private var isDiscardingRecord = false

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      FolderGrantHeader(folders: folders) { isChoosingFolder = true }
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: DS.Space.s5) {
            FolderGrantMessages(problem: folders.problem, outcome: folders.outcome)
            FolderSavedRequests(folders: folders) { isDiscardingRecord = true }
            if let review = folders.review {
              FolderGrantReviewCard(review: review, folders: folders)
                .id(Self.reviewAnchor)
            }
            FolderGrantList(folders: folders) { revocation = $0 }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A review opened from a lower row is brought into view; nothing is submitted.
        .onChange(of: folders.review) { _, review in
          if review != nil { proxy.scrollTo(Self.reviewAnchor, anchor: .top) }
        }
      }
      HStack {
        if folders.isLoading || folders.isUpdating { ProgressView().controlSize(.small) }
        Spacer()
        // Done is the default action only while no review is open; then the review's own
        // ⌘Return confirmation owns the decision.
        if folders.review == nil {
          Button("Done") { dismiss() }
            .designDefaultAction()
            .disabled(folders.isUpdating)
            .accessibilityIdentifier("folders.done")
        } else {
          Button("Done") { dismiss() }
            .disabled(folders.isUpdating)
            .accessibilityIdentifier("folders.done")
        }
      }
    }
    .padding(DS.Space.s6)
    .designSheetFrame(idealWidth: DS.Layout.Conversation.minWidth)
    .background(DS.Colors.Surface.window)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("folders.sheet")
    .interactiveDismissDisabled(folders.isUpdating)
    .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
      switch result {
      case .success(let url): folders.choose(url)
      case .failure: folders.choiceFailed()
      }
    }
    .fileDialogMessage(
      "Choose a folder for the Assistant. Nothing is granted until you review and confirm it."
    )
    .fileDialogConfirmationLabel("Review Folder")
    .confirmationDialog(
      "Revoke Folder Access?", item: $revocation, titleVisibility: .visible
    ) { grant in
      Button("Revoke", role: .destructive) { folders.revoke(grant) }
      Button("Cancel", role: .cancel) {}
    } message: { grant in
      Text(
        "The Assistant loses access to \(grant.path) on this Mac. Revocation is final: this grant cannot be restored, and choosing the folder again makes a new grant."
      )
    }
    .confirmationDialog(
      "Discard Unreadable Saved Request?", isPresented: $isDiscardingRecord,
      titleVisibility: .visible
    ) {
      Button("Discard", role: .destructive) { folders.discardUnreadableRecords() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "It cannot be read or retried. Discarding sends nothing and cannot undo a request the runtime already applied; check the current list before granting the same folder again."
      )
    }
    .onAppear { folders.sheetAppeared() }
    .onDisappear { folders.cancelReview() }
  }

  private static let reviewAnchor = "folders.review.anchor"
}

private struct FolderGrantHeader: View {
  let folders: FolderGrantSetup
  let choose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
        Text("Folders").font(.title2.weight(.semibold))
        Spacer(minLength: DS.Space.s3)
        Button("Refresh", systemImage: "arrow.clockwise") { folders.refresh() }
          .disabled(!folders.canRefresh)
          .help("Reload the Assistant's folder grants from the local runtime.")
          .accessibilityIdentifier("folders.refresh")
        Button("Choose Folder…", systemImage: "folder.badge.plus", action: choose)
          .disabled(!folders.canChoose)
          .help(
            "Opens the system folder panel. Choosing a folder only starts a review; nothing is granted until you confirm."
          )
          .accessibilityIdentifier("folders.choose")
      }
      FolderAssistantIdentity(name: folders.botName, botID: folders.botID)
      VStack(alignment: .leading, spacing: DS.Space.s1) {
        Label("Tools stay disabled", systemImage: "lock")
          .font(.callout.weight(.medium))
        Text(
          "A grant records what the Assistant may use later. In this development build no model or tool can read, list or change files in these folders."
        )
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("folders.toolsDisabled")
      if !folders.isSynchronized && folders.support != .unsupported {
        Label(
          "Folder state is not synchronized. Folder changes are disabled.",
          systemImage: "network.slash"
        )
        .font(DS.Typography.callout)
        .accessibilityIdentifier("folders.unsynchronized")
      }
    }
  }
}

private struct FolderAssistantIdentity: View {
  let name: String?
  let botID: BotID?

  var body: some View {
    if let name, let botID {
      VStack(alignment: .leading, spacing: DS.Space.s1) {
        Text("Grants for \(name)").font(.callout)
        Text(verbatim: botID.rawValue)
          .font(DS.Typography.callout.monospaced())
          .foregroundStyle(DS.Colors.Text.secondary)
          .textSelection(.enabled)
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("folders.assistant")
    } else {
      Text("The Assistant is not loaded, so no folder grants are shown.")
        .font(.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
        .accessibilityIdentifier("folders.assistant")
    }
  }
}

private struct FolderGrantMessages: View {
  let problem: String?
  let outcome: String?

  var body: some View {
    if let problem {
      Text(verbatim: problem)
        .font(.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("folders.error")
    }
    if let outcome {
      Text(verbatim: outcome)
        .font(.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("folders.outcome")
    }
  }
}

/// Saved requests stay visible until the runtime answers them. Retrying resends only the exact
/// original request; nothing here creates a replacement.
private struct FolderSavedRequests: View {
  let folders: FolderGrantSetup
  let discard: () -> Void

  var body: some View {
    if folders.support == .unsupported
      && (folders.pendingUpdate != nil || !folders.pendingRevocations.isEmpty)
    {
      Text(
        "The connected runtime does not support folder management, so saved requests cannot be retried now. They stay saved on this Mac."
      )
      .font(.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
    }
    if folders.hasUnreadableRecord {
      VStack(alignment: .leading, spacing: DS.Space.s3) {
        Text("Unreadable Saved Request").font(.headline)
        Text(
          "A saved folder request could not be read, so it cannot be retried. New folder changes stay blocked until it is discarded after the current list loads."
        )
        Button("Discard Unreadable Request…", role: .destructive, action: discard)
          .disabled(!folders.canDiscardUnreadableRecord)
          .accessibilityIdentifier("folders.discardUnreadable")
      }
      .font(.callout)
      .folderCard()
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("folders.unreadable")
    }
    if let change = folders.pendingUpdate?.grant {
      FolderPendingUpdate(change: change, folders: folders)
    }
    ForEach(folders.unmatchedRevocations, id: \.self) { id in
      VStack(alignment: .leading, spacing: DS.Space.s3) {
        Text("Saved Revocation").font(.headline)
        Text(verbatim: id.rawValue)
          .font(DS.Typography.callout.monospaced())
          .textSelection(.enabled)
        Text("This grant is not in the loaded list.")
        if let message = folders.grantOutcomes[id] { Text(verbatim: message) }
        FolderPendingRevocation(id: id, folders: folders)
      }
      .font(.callout)
      .folderCard()
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("folders.savedRevocation.\(id.rawValue)")
    }
  }
}

private struct FolderPendingUpdate: View {
  let change: FolderGrantChange
  let folders: FolderGrantSetup

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Text(change.id == nil ? "Saved Grant Request" : "Saved Access Change").font(.headline)
      Text(verbatim: change.path)
        .font(.callout.monospaced())
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.layoutDirection, .leftToRight)
      LabeledContent("Requested access") { Text(change.access.reviewLabel) }
      if folders.isUpdating {
        Text("Sending this exact request…")
      } else {
        Text(
          "Delivery is unconfirmed. Retrying sends exactly this original request to recover its answer; it never creates a second grant or asks for wider access. New folder changes wait until it is answered."
        )
      }
      HStack(spacing: DS.Space.s4) {
        Button("Retry Original Request") { folders.retryPendingUpdate() }
          .disabled(!folders.canRetryPendingUpdate)
          .accessibilityIdentifier("folders.retry")
        if folders.isUpdating { ProgressView().controlSize(.small) }
      }
    }
    .font(.callout)
    .folderCard()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("folders.pending")
  }
}

private struct FolderPendingRevocation: View {
  let id: GrantID
  let folders: FolderGrantSetup

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s2) {
      if folders.revoking.contains(id) {
        Text("Sending this exact revocation…")
      } else {
        Text(
          "Revocation delivery is unconfirmed. Retrying sends exactly the original revocation, never a different request."
        )
      }
      HStack(spacing: DS.Space.s4) {
        Button("Retry Revocation") { folders.retryRevocation(id) }
          .disabled(!folders.canRetryRevocation(id))
          .accessibilityIdentifier("folders.retryRevoke.\(id.rawValue)")
        if folders.revoking.contains(id) { ProgressView().controlSize(.small) }
      }
    }
    .font(.callout)
  }
}

/// The final review: the exact path, the Assistant, an explicit access choice and, for a whole
/// personal folder, typed confirmation. Only its action button sends a request.
private struct FolderGrantReviewCard: View {
  let review: FolderGrantReview
  @Bindable var folders: FolderGrantSetup

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Text(isNewFolder ? "Review Folder Grant" : "Review Access Change").font(.headline)
      if let name = folders.botName {
        LabeledContent("Assistant") { Text(verbatim: name) }
      }
      VStack(alignment: .leading, spacing: DS.Space.s2) {
        Text("Folder").font(DS.Typography.callout.weight(.semibold))
        Text(verbatim: review.path)
          .font(.callout.monospaced())
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .environment(\.layoutDirection, .leftToRight)
          .accessibilityIdentifier("folders.review.path")
      }
      if case .existing(_, _, let current) = review.subject {
        LabeledContent("Current access") { Text(current.reviewLabel) }
      }
      Picker("Access", selection: $folders.access) {
        Text("Read only").tag(FolderGrantPermission.read)
        Text("Read and write").tag(FolderGrantPermission.write)
      }
      .pickerStyle(.radioGroup)
      .disabled(folders.isUpdating)
      .accessibilityIdentifier("folders.review.access")
      Text(
        folders.access == .write
          ? "Read and write also allows approved changes to files in this folder. Each change still needs policy review."
          : "Read only never allows changes to files in this folder."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      if folders.requiresConfirmation {
        FolderConfirmationField(
          path: review.path, isBroad: review.isBroad, confirmation: $folders.confirmation)
      }
      Text(
        "Tools stay disabled. Granting records permission only; nothing in this folder is read, listed or changed now."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      HStack(spacing: DS.Space.s4) {
        Button("Cancel") { folders.cancelReview() }
          .keyboardShortcut(.cancelAction)
          .disabled(folders.isUpdating)
          .accessibilityIdentifier("folders.review.cancel")
        Spacer()
        if folders.isUpdating { ProgressView().controlSize(.small) }
        Button(actionTitle) { folders.submitReview() }
          .keyboardShortcut(.return, modifiers: .command)
          .disabled(!folders.canSubmitReview)
          .accessibilityIdentifier("folders.review.grant")
      }
      Text("⌘Return confirms · Esc cancels the review")
        .font(DS.Typography.subheadline)
        .foregroundStyle(DS.Colors.Text.secondary)
    }
    .folderCard()
    .overlay {
      RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Colors.Border.field)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("folders.review")
  }

  private var isNewFolder: Bool {
    if case .newFolder = review.subject { return true }
    return false
  }

  private var actionTitle: LocalizedStringKey {
    switch (isNewFolder, folders.access) {
    case (true, .write): "Grant Read and Write"
    case (true, _): "Grant Read Only"
    case (false, .write): "Change to Read and Write"
    case (false, _): "Change to Read Only"
    }
  }
}

/// Typed confirmation only confirms the reviewed path; it never selects a folder.
private struct FolderConfirmationField: View {
  let path: String
  let isBroad: Bool
  @Binding var confirmation: String

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s2) {
      Text(
        isBroad
          ? "This is an entire personal folder. Type its exact path to confirm."
          : "The runtime requires typed confirmation for this folder. Type its exact path to confirm."
      )
      .font(.callout.weight(.medium))
      TextField("Exact folder path", text: $confirmation)
        .textFieldStyle(.roundedBorder)
        .font(.callout.monospaced())
        .autocorrectionDisabled()
        .accessibilityIdentifier("folders.review.confirmation")
      if !confirmation.isEmpty && confirmation != path {
        Text("The typed path does not exactly match the folder path.")
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
      }
    }
  }
}

private struct FolderGrantList: View {
  let folders: FolderGrantSetup
  let revoke: (FolderGrantSummary) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Text("Granted Folders").font(.headline)
      if folders.support == .unsupported {
        ContentUnavailableView {
          Label("Folder Management Unavailable", systemImage: "folder.badge.questionmark")
        } description: {
          Text(
            "The connected runtime did not negotiate folder management. No list is shown, because an empty list would not mean that nothing is granted."
          )
        }
        .accessibilityIdentifier("folders.unsupported")
      } else if !folders.hasLoaded {
        ContentUnavailableView {
          Label("Folder Grants Not Loaded", systemImage: "arrow.triangle.2.circlepath")
        } description: {
          Text(
            "Connect to the authenticated local runtime to load the Assistant's folder grants. No sample folder is shown."
          )
        }
        .accessibilityIdentifier("folders.notLoaded")
      } else if folders.grants.isEmpty {
        ContentUnavailableView {
          Label("No Folders Granted", systemImage: "folder")
        } description: {
          Text(
            "The Assistant has no folder grants on this Mac. Choose a folder to review it before granting access."
          )
        }
        .accessibilityIdentifier("folders.empty")
      }
      ForEach(folders.grants, id: \.id) { grant in
        FolderGrantRow(grant: grant, folders: folders, revoke: revoke)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("folders.list")
  }
}

/// One authoritative grant record. Actions use the same GrantID-based identifiers everywhere.
private struct FolderGrantRow: View {
  let grant: FolderGrantSummary
  let folders: FolderGrantSetup
  let revoke: (FolderGrantSummary) -> Void

  var body: some View {
    let pastDeadline = folders.isPastDeadline(grant)
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      HStack(alignment: .firstTextBaseline) {
        Label {
          Text(grant.access.reviewLabel)
        } icon: {
          Image(systemName: grant.access == .write ? "square.and.pencil" : "eye")
        }
        .font(DS.Typography.callout.weight(.semibold))
        Spacer(minLength: DS.Space.s3)
        FolderGrantStatusLabel(
          status: grant.status, available: grant.available, pastDeadline: pastDeadline
        )
        .font(DS.Typography.callout.weight(.medium))
      }
      Text(verbatim: grant.path)
        .font(.callout.monospaced())
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.layoutDirection, .leftToRight)
      FolderGrantDates(
        expiresAt: grant.expiresAt, createdAt: grant.createdAt, updatedAt: grant.updatedAt,
        revision: grant.revision)
      if grant.status == .active && !grant.available {
        Text(
          "This folder is unavailable: it may have been moved, renamed, deleted or replaced, or its volume is not connected. Memoshi never relinks or renews a grant automatically. Restore the folder or reconnect its volume, or revoke this grant and choose the folder again. Reducing access and revoking still work; write access cannot be added."
        )
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("folders.unavailable.\(grant.id.rawValue)")
      }
      if pastDeadline {
        Text(
          "The expiry has passed. The runtime ends this grant when it next checks it; it is never renewed automatically."
        )
        .font(.callout)
      }
      if let message = folders.grantOutcomes[grant.id] {
        Text(verbatim: message)
          .font(.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("folders.outcome.\(grant.id.rawValue)")
      }
      if folders.pendingRevocations[grant.id] != nil {
        FolderPendingRevocation(id: grant.id, folders: folders)
      } else if grant.status == .active {
        HStack(spacing: DS.Space.s4) {
          Button("Change Access…") { folders.reviewChange(of: grant) }
            .disabled(!folders.canChangeAccess(grant))
            .help(
              "Review a change between read only and read and write. Adding write access needs the folder to be available."
            )
            .accessibilityIdentifier("folders.access.\(grant.id.rawValue)")
          Button("Revoke…", role: .destructive) { revoke(grant) }
            .disabled(!folders.canRevoke(grant))
            .help("Ends this grant permanently after confirmation.")
            .accessibilityIdentifier("folders.revoke.\(grant.id.rawValue)")
        }
      } else if grant.status == .revoked || grant.status == .expired {
        Text(
          "This grant has ended and cannot be restored. Choose the folder again to make a new grant."
        )
        .font(.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
      }
    }
    .folderCard()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("folders.row.\(grant.id.rawValue)")
  }
}

private struct FolderGrantStatusLabel: View {
  let status: FolderGrantState
  let available: Bool
  let pastDeadline: Bool

  var body: some View {
    switch status {
    case .active:
      if !available {
        Text("Active · folder unavailable")
      } else if pastDeadline {
        Text("Expiry passed · awaiting runtime state")
      } else {
        Text("Active")
      }
    case .revoked:
      Text("Revoked")
    case .expired:
      Text("Expired")
    default:
      Text("Unsupported state · no actions")
    }
  }
}

private struct FolderGrantDates: View {
  let expiresAt: Int64?
  let createdAt: Int64
  let updatedAt: Int64
  let revision: Int64

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s1) {
      if let expiresAt {
        Text("Expiry: \(Self.date(expiresAt), format: Self.format)")
      } else {
        Text("No expiry")
      }
      Text("Granted: \(Self.date(createdAt), format: Self.format)")
      Text("Updated: \(Self.date(updatedAt), format: Self.format) · Revision \(revision)")
    }
    .font(DS.Typography.callout)
    .foregroundStyle(DS.Colors.Text.secondary)
  }

  private static let format: Date.FormatStyle = .dateTime.year().month().day().hour().minute()

  private static func date(_ milliseconds: Int64) -> Date {
    Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
  }
}

extension View {
  fileprivate func folderCard() -> some View {
    padding(DS.Space.s5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(DS.Colors.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.card))
  }
}

extension FolderGrantPermission {
  fileprivate var reviewLabel: LocalizedStringResource {
    switch self {
    case .read: "Read only"
    case .write: "Read and write"
    default: "Unsupported access"
    }
  }
}
