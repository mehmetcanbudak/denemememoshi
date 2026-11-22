import DesignSystem
import Foundation
import MemoshiProtocol
import SwiftUI

/// Local Session lifecycle proof. Bot/home-Chat deletion and device propagation are not enabled.
struct SessionTrashSheet: View {
  let directory: LiveConversationDirectory
  @Environment(\.dismiss) private var dismiss
  @State private var pendingPurge: [SessionID] = []

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      HStack {
        Text("Session Trash").font(.title2).accessibilityAddTraits(.isHeader)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text(
        "Development · Local Sessions only. Restore within 30 days, or permanently delete their local transcripts now."
      )
      .font(.callout).foregroundStyle(DS.Colors.Text.secondary)
      if directory.isLoadingTrash {
        ProgressView("Loading Trash")
      } else if directory.trash.isEmpty {
        ContentUnavailableView("Trash is Empty", systemImage: "trash")
      } else {
        List(directory.trash, id: \.id) { session in
          TrashedSessionRow(session: session, directory: directory) {
            pendingPurge = [session.id]
          }
        }
        .accessibilityIdentifier("trash.sessions")
      }
      if let problem = directory.trashProblem {
        Text(verbatim: problem).foregroundStyle(DS.Colors.Text.secondary)
      }
      ConversationDirectoryStatus(directory: directory)
      HStack {
        Button("Reload", systemImage: "arrow.clockwise") {
          Task { await directory.loadTrash() }
        }
        .disabled(directory.isLoadingTrash)
        Spacer()
        Button("Empty Session Trash", systemImage: "trash.fill", role: .destructive) {
          // The confirmation freezes the displayed IDs, not a later server-side selection.
          pendingPurge = directory.trash.map(\.id)
        }
        .disabled(directory.trash.isEmpty || directory.isChanging || directory.hasPendingChange)
        .accessibilityIdentifier("trash.empty")
      }
    }
    .padding(DS.Space.s6)
    .designSheetFrame(idealWidth: DS.Layout.Sheet.botProfileWidth)
    .task { await directory.loadTrash() }
    .confirmationDialog(
      "Permanently delete the selected Sessions?",
      isPresented: Binding(
        get: { !pendingPurge.isEmpty }, set: { if !$0 { pendingPurge = [] } }),
      titleVisibility: .visible
    ) {
      Button("Delete Permanently", role: .destructive) {
        directory.purgeSessions(pendingPurge)
        pendingPurge = []
      }
      Button("Cancel", role: .cancel) { pendingPurge = [] }
    } message: {
      Text(
        "Their local transcripts and Pi stores will be removed. This cannot be undone. Other Sessions and the daemon stay running."
      )
    }
  }
}

private struct TrashedSessionRow: View {
  let session: TrashedSession
  let directory: LiveConversationDirectory
  let purge: () -> Void

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: DS.Space.s1) {
        Text(session.title)
        Text(
          "Purges \(Date(timeIntervalSince1970: Double(session.purgeAfter) / 1_000), format: .dateTime.day().month().year())"
        )
        .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
      }
      Spacer()
      Button("Restore") { directory.restoreSession(session.id) }
        .accessibilityLabel("Restore \(session.title)")
        .accessibilityIdentifier("trash.restore." + session.id.rawValue)
      Button("Delete Permanently", systemImage: "trash", role: .destructive, action: purge)
        .labelStyle(.iconOnly)
        .accessibilityLabel("Delete \(session.title) Permanently")
        .accessibilityIdentifier("trash.purge." + session.id.rawValue)
    }
    .disabled(directory.isChanging || directory.hasPendingChange)
  }
}
