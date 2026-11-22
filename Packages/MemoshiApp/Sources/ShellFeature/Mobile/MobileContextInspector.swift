#if os(iOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  struct MobileContextInspector<Conversation: View, Activity: View, ResourceDetail: View>: View {
    @Bindable var workspace: PreviewWorkspace
    @ViewBuilder let conversation: (PreviewBot) -> Conversation
    @ViewBuilder let activity: (PreviewBot) -> Activity
    @ViewBuilder let resourceDetail: (PreviewResource) -> ResourceDetail

    private var title: String {
      switch workspace.rightPane {
      case .activity: String(localized: "Sample Activity", bundle: #bundle)
      case .resource: String(localized: "Sample Details", bundle: #bundle)
      case .conversation: String(localized: "Preview Chat", bundle: #bundle)
      }
    }

    var body: some View {
      NavigationStack {
        VStack(spacing: DS.Space.s0) {
          switch workspace.rightPane {
          case .activity:
            activity(workspace.activityBot)
          case .resource:
            resourceDetail(workspace.selectedResource)
          case .conversation:
            conversation(workspace.secondaryBot)
              .safeAreaBar(edge: .top) {
                MobileConversationHeader(
                  bot: workspace.secondaryBot,
                  selectableBots: PreviewBot.allCases,
                  selectBot: { workspace.secondaryBot = $0 }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DS.Space.s5)
                .padding(.vertical, DS.Space.s3)
                // As in the main conversation: scrolled text stops at the header.
                .background(
                  DesignControlRoles.barBacking, ignoresSafeAreaEdges: [.top, .horizontal])
              }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Colors.Surface.inspector)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button {
              workspace.isInspectorPresented = false
            } label: {
              Text("Done", bundle: #bundle)
                .frame(
                  minWidth: DS.Layout.Composer.minHeight,
                  minHeight: DS.Layout.Composer.minHeight
                )
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("\(workspace.rightPane.rawValue).done")
          }
        }
      }
    }
  }
#endif
