import DesignSystem
import MemoshiProtocol
import SwiftUI

/// Inspection never changes the active Chat or grants another tool capability.
struct TaskAttachmentView: View {
  let inspector: LiveTaskInspector
  @State private var isDiscardingRecord = false

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Text("Subagent history").font(.headline)
      if let snapshot = inspector.snapshot {
        HStack {
          Text(snapshot.background ? "Persistent background child" : "Foreground child")
          Spacer()
          Text(verbatim: snapshot.task.statusLabel)
        }
        .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
        Text(
          "Read-only attachment to this child's Pi history. Stop targets this task; it does not undo completed effects or stop unrelated background work."
        )
        .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
        HStack {
          if inspector.nextBefore != nil {
            Button("Load Earlier Messages") { inspector.loadEarlier() }
              .disabled(inspector.isLoading || inspector.isLoadingEarlier)
              .accessibilityIdentifier("tasks.child.loadEarlier")
          }
          Spacer()
          Button("Stop Subagent", systemImage: "stop.fill", role: .destructive) {
            inspector.stopSelected()
          }
          .disabled(!inspector.canStop)
          .accessibilityIdentifier("tasks.child.stop")
        }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: DS.Space.s4) {
            ForEach(inspector.items, id: \.entryId) { message in
              let speaker =
                message.role == .user ? String(localized: "Task") : String(localized: "Subagent")
              let content =
                message.text.isEmpty && message.stopReason == .toolUse
                ? String(localized: "Tool request") : message.text
              VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: speaker)
                  .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
                Text(verbatim: content).textSelection(.enabled)
                if message.stopReason == .aborted {
                  Text("Stopped").font(DS.Typography.callout).foregroundStyle(
                    DS.Colors.Text.secondary)
                } else if message.stopReason == .error {
                  Text("Response failed").font(DS.Typography.callout).foregroundStyle(
                    DS.Colors.Text.secondary)
                }
              }
              .accessibilityElement(children: .combine)
              .accessibilityLabel(Text(verbatim: content))
              .accessibilityValue(Text(verbatim: speaker))
              .accessibilityIdentifier("tasks.child.message." + message.entryId)
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let live = snapshot.liveText, !live.isEmpty {
              VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Responding…").font(DS.Typography.callout).foregroundStyle(
                  DS.Colors.Text.secondary)
                Text(verbatim: live).textSelection(.enabled)
              }
              .accessibilityElement(children: .combine)
              .accessibilityLabel(Text(verbatim: live))
              .accessibilityValue(Text("Responding"))
              .accessibilityIdentifier("tasks.child.live")
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        .accessibilityIdentifier("tasks.child.history")
      } else if inspector.isLoading {
        ProgressView("Reading child history…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView {
          Label("Inspect a Subagent", systemImage: "text.bubble")
        } description: {
          Text(
            "Select a subagent in the task tree. Its own history appears here without opening a new conversation."
          )
        }
      }
      if inspector.hasUnreadableStop {
        Text("A saved task Stop could not be read, so it cannot be retried.")
          .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
        Button("Discard Unreadable Stop…", role: .destructive) { isDiscardingRecord = true }
          .disabled(!inspector.canDiscardUnreadableStop)
          .accessibilityIdentifier("tasks.child.discardUnreadableStop")
      } else if inspector.hasPendingStop {
        Text("A task Stop is awaiting confirmation. Retry uses its original request and target.")
          .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
        Button("Retry Saved Stop") { inspector.retryStop() }
          .disabled(!inspector.canRetryStop)
          .accessibilityIdentifier("tasks.child.retryStop")
      }
      if let problem = inspector.problem {
        Text(verbatim: problem).font(DS.Typography.callout).foregroundStyle(
          DS.Colors.Text.secondary
        )
        .accessibilityIdentifier("tasks.child.problem")
      }
    }
    .padding(DS.Space.s5)
    .frame(
      minWidth: DS.Layout.Inspector.min, maxWidth: .infinity, maxHeight: .infinity,
      alignment: .topLeading
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("tasks.child.inspector")
    .confirmationDialog(
      "Discard Unreadable Saved Stop?", isPresented: $isDiscardingRecord,
      titleVisibility: .visible
    ) {
      Button("Discard", role: .destructive) { inspector.discardUnreadableStop() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "It cannot be read or retried. Discarding sends nothing and cannot undo a Stop the runtime already applied; check the task list before stopping the same work again."
      )
    }
  }
}
