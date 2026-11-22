#if os(macOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  /// Native workspace navigation with one resizable split and independently selected bot panes.
  public struct MacWorkspaceView<
    Conversation: View, Waiting: View, Activity: View, ResourceDetail: View
  >: View {
    @Bindable private var workspace: PreviewWorkspace
    @State private var searchText = ""

    private let liveAssistant: Bool
    private let pendingApprovalCount: Int
    private let waiting: () -> Waiting
    private let conversation: (PreviewBot) -> Conversation
    private let activity: (PreviewBot) -> Activity
    private let resourceDetail: (PreviewResource) -> ResourceDetail

    /// Composes local conversations, example Activity and original sample resources.
    ///
    /// Each conversation closure receives the bot actually displayed in that pane.
    /// Showing one bot in both panes mirrors its single conversation and draft.
    public init(
      workspace: PreviewWorkspace, liveAssistant: Bool, pendingApprovalCount: Int,
      @ViewBuilder conversation: @escaping (PreviewBot) -> Conversation,
      @ViewBuilder waiting: @escaping () -> Waiting,
      @ViewBuilder activity: @escaping (PreviewBot) -> Activity,
      @ViewBuilder resourceDetail: @escaping (PreviewResource) -> ResourceDetail
    ) {
      self.workspace = workspace
      self.liveAssistant = liveAssistant
      self.pendingApprovalCount = pendingApprovalCount
      self.waiting = waiting
      self.conversation = conversation
      self.activity = activity
      self.resourceDetail = resourceDetail
    }

    /// Presents searchable routes, primary content and an optional contextual column.
    public var body: some View {
      // Keep one native split: NavigationSplitView plus inspector previously caused
      // AppKit fitting-size cycles on macOS 27.0.1.
      HSplitView {
        if workspace.isSidebarPresented {
          MacRosterColumn(
            workspace: workspace, searchText: $searchText, liveAssistant: liveAssistant,
            pendingApprovalCount: pendingApprovalCount
          )
          .frame(
            minWidth: DS.Layout.Sidebar.min,
            idealWidth: DS.Layout.Sidebar.default,
            maxWidth: DS.Layout.Sidebar.max
          )
        }

        MacWorkspaceContent(
          workspace: workspace,
          liveAssistant: liveAssistant,
          conversation: conversation,
          waiting: waiting,
          activity: activity,
          resourceDetail: resourceDetail
        )
        .frame(
          minWidth: DS.Layout.Conversation.minWidth, maxWidth: .infinity, maxHeight: .infinity
        )

        if workspace.isInspectorPresented {
          MacContextColumn(
            workspace: workspace,
            liveAssistant: liveAssistant,
            conversation: conversation,
            activity: activity,
            resourceDetail: resourceDetail
          )
          .frame(
            minWidth: DS.Layout.Inspector.min,
            idealWidth: workspace.rightPane == .conversation
              ? DS.Layout.Conversation.minWidth : DS.Layout.Inspector.default,
            maxWidth: workspace.rightPane == .conversation
              ? DS.Layout.Conversation.contentMaxWidth : DS.Layout.Inspector.max
          )
        }
      }
      .frame(minWidth: DS.Layout.Window.minWidth, minHeight: DS.Layout.Window.minHeight)
      .navigationTitle(
        workspace.section == .conversation ? workspace.selectedBot.name : workspace.section.title
      )
      .navigationSubtitle(
        liveAssistant && workspace.section == .waitingForYou
          ? Text("Local approval review · Production tools disabled", bundle: #bundle)
          : liveAssistant && workspace.section == .conversation
            && workspace.selectedBot == .assistant
            ? Text("Development chat · Production tools disabled", bundle: #bundle)
            : Text("Design Preview · Not connected", bundle: #bundle)
      )
      .toolbar {
        MacWorkspaceToolbar(workspace: workspace)
      }
    }
  }
#endif
