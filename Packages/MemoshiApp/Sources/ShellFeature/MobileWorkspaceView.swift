#if os(iOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  /// A native tabbed host for chats and adaptive contextual details. With `liveAssistant`, the
  /// Memoshi tab is the real in-process Assistant Chat; the other bots stay local examples.
  public struct MobileWorkspaceView<Conversation: View, Activity: View, ResourceDetail: View>: View
  {
    @Bindable private var workspace: PreviewWorkspace
    @State private var selectedTab: MobileWorkspaceTab
    @State private var otherBot: PreviewBot
    @State private var rosterSearchText = ""
    @State private var searchText = ""

    private let liveAssistant: Bool
    private let pendingApprovalCount: Int
    private let conversation: (PreviewBot) -> Conversation
    private let activity: (PreviewBot) -> Activity
    private let resourceDetail: (PreviewResource) -> ResourceDetail

    /// Composes native phone tabs, an adaptive iPad sidebar and dismissible sample details.
    public init(
      workspace: PreviewWorkspace, liveAssistant: Bool, pendingApprovalCount: Int,
      @ViewBuilder conversation: @escaping (PreviewBot) -> Conversation,
      @ViewBuilder activity: @escaping (PreviewBot) -> Activity,
      @ViewBuilder resourceDetail: @escaping (PreviewResource) -> ResourceDetail
    ) {
      self.workspace = workspace
      self.liveAssistant = liveAssistant
      self.pendingApprovalCount = pendingApprovalCount
      self.conversation = conversation
      self.activity = activity
      self.resourceDetail = resourceDetail
      _selectedTab = State(
        initialValue: workspace.selectedBot == .assistant ? .memoshi : .others
      )
      _otherBot = State(
        initialValue: workspace.selectedBot == .assistant ? .researcher : workspace.selectedBot
      )
    }

    /// Keeps each tab's local state while routing details from their actual requesting context.
    public var body: some View {
      TabView(selection: tabSelection) {
        Tab(
          String(localized: "Bots", bundle: #bundle), systemImage: "bubble.left.and.bubble.right",
          value: .bots
        ) {
          NavigationStack {
            MobileBotRoster(
              selection: workspace.selectedBot,
              searchText: $rosterSearchText,
              isSearch: false,
              select: selectConversation
            )
          }
        }

        Tab(
          String(localized: "Memoshi", bundle: #bundle),
          systemImage: PreviewBot.assistant.systemImage, value: .memoshi
        ) {
          NavigationStack {
            MobileConversationScreen(
              bot: .assistant,
              isLive: liveAssistant,
              selectableBots: [],
              selectBot: selectConversation,
              showActivity: { workspace.showActivity(for: .assistant) },
              conversation: conversation
            )
          }
        }
        .badge(liveAssistant ? pendingApprovalCount : 0)

        Tab(String(localized: "Others", bundle: #bundle), systemImage: "person.2", value: .others) {
          NavigationStack {
            MobileConversationScreen(
              bot: otherBot,
              isLive: false,
              selectableBots: MobileWorkspaceTab.otherBots,
              selectBot: selectConversation,
              showActivity: { workspace.showActivity(for: otherBot) },
              conversation: conversation
            )
          }
        }

        Tab(
          String(localized: "Search", bundle: #bundle), systemImage: "magnifyingglass",
          value: .search, role: .search
        ) {
          NavigationStack {
            MobileBotRoster(
              selection: workspace.selectedBot,
              searchText: $searchText,
              isSearch: true,
              select: selectConversation
            )
          }
        }
      }
      .tabViewStyle(.sidebarAdaptable)
      .inspector(isPresented: $workspace.isInspectorPresented) {
        MobileContextInspector(
          workspace: workspace,
          conversation: conversation,
          activity: activity,
          resourceDetail: resourceDetail
        )
        .inspectorColumnWidth(
          min: DS.Layout.Inspector.min,
          ideal: DS.Layout.Inspector.default,
          max: DS.Layout.Inspector.max
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
      .onChange(of: workspace.selectedBot) { _, bot in
        selectConversation(bot)
      }
    }

    private var tabSelection: Binding<MobileWorkspaceTab> {
      Binding(
        get: { selectedTab },
        set: { tab in
          selectedTab = tab
          switch tab {
          case .memoshi:
            workspace.select(.assistant)
          case .others:
            workspace.select(otherBot)
          case .bots, .search:
            break
          }
        }
      )
    }

    private func selectConversation(_ bot: PreviewBot) {
      if bot == .assistant {
        selectedTab = .memoshi
      } else {
        otherBot = bot
        selectedTab = .others
      }
      workspace.select(bot)
    }
  }

  private enum MobileWorkspaceTab: Hashable {
    case bots, memoshi, others, search

    static let otherBots: [PreviewBot] = [.researcher, .weather]
  }
#endif
