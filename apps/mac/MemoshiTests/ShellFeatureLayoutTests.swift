import AppCore
import DesignSystem
import ShellFeature
import SwiftUI
import Testing

/// Layout invariants and pane-state rules for `ShellFeature` and the `DS.Layout` tokens it sizes
/// from.
@Suite("ShellFeature layout values and workspace pane state", .timeLimit(.minutes(1)))
@MainActor
struct ShellFeatureLayoutTests {
  @Test("Sidebar, inspector, conversation and window layout bounds stay internally consistent")
  func layoutBoundsAreConsistent() {
    #expect(DS.Layout.Sidebar.rail > 0)
    #expect(DS.Layout.Sidebar.rail < DS.Layout.Sidebar.snapToRailBelow)
    #expect(DS.Layout.Sidebar.snapToRailBelow < DS.Layout.Sidebar.min)
    #expect(DS.Layout.Sidebar.min <= DS.Layout.Sidebar.default)
    #expect(DS.Layout.Sidebar.default <= DS.Layout.Sidebar.max)

    #expect(DS.Layout.Inspector.min <= DS.Layout.Inspector.default)
    #expect(DS.Layout.Inspector.default <= DS.Layout.Inspector.max)

    #expect(DS.Layout.Conversation.minWidth > 0)
    #expect(DS.Layout.Conversation.minWidth <= DS.Layout.Conversation.contentMaxWidth)

    #expect(DS.Layout.Window.minWidth >= DS.Layout.Sidebar.min + DS.Layout.Conversation.minWidth)
    #expect(DS.Layout.Window.minHeight >= 600)

    #expect(DS.Layout.Card.padding > 0)
    #expect(DS.Layout.Card.maxWidth >= DS.Layout.Conversation.minWidth)
    #expect(DS.Layout.Composer.controlSize > 0)
    #expect(DS.Layout.Composer.minHeight >= DS.Layout.Composer.controlSize)
  }

  @Test("MacWorkspaceView composes with PreviewWorkspace pane toggles without crashing")
  func macWorkspacePaneState() {
    let workspace = PreviewWorkspace()
    #expect(workspace.isSidebarPresented)
    workspace.select(.researcher)
    #expect(workspace.selectedBot == .researcher)
    workspace.showActivity(for: .researcher)
    #expect(workspace.isInspectorPresented)
    workspace.showResource(.readingNote)
    #expect(workspace.isInspectorPresented)

    let view = MacWorkspaceView(
      workspace: workspace, liveAssistant: true, pendingApprovalCount: 2,
      conversation: { _ in EmptyView() },
      waiting: { EmptyView() },
      activity: { _ in EmptyView() },
      resourceDetail: { _ in EmptyView() })
    _ = view.body
  }
}
