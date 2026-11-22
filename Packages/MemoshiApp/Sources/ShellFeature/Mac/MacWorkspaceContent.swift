#if os(macOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  struct MacWorkspaceContent<
    Conversation: View, Waiting: View, Activity: View, ResourceDetail: View
  >: View {
    @Bindable var workspace: PreviewWorkspace
    let liveAssistant: Bool
    let conversation: (PreviewBot) -> Conversation
    let waiting: () -> Waiting
    let activity: (PreviewBot) -> Activity
    let resourceDetail: (PreviewResource) -> ResourceDetail

    var body: some View {
      switch workspace.section {
      case .conversation:
        let bot = workspace.selectedBot
        MacConversationColumn(
          bot: bot,
          isLive: liveAssistant && bot == .assistant,
          isSecondary: false,
          select: { workspace.select($0) },
          showActivity: { workspace.showActivity(for: bot) },
          openBeside: { workspace.openBeside(bot) },
          conversation: conversation
        )
      case .waitingForYou:
        if liveAssistant {
          waiting()
        } else {
          MacWaitingPage(workspace: workspace)
        }
      case .library:
        MacResourceLibrary(workspace: workspace)
      case .pages:
        MacSamplePage(workspace: workspace, resourceDetail: resourceDetail)
      case .activity:
        let bot = workspace.selectedBot
        MacActivityPage(
          bot: bot,
          openBeside: { workspace.showActivity(for: bot) },
          activity: activity
        )
      }
    }
  }

  private struct MacWaitingPage: View {
    @Bindable var workspace: PreviewWorkspace

    var body: some View {
      ContentUnavailableView {
        Label {
          Text("Nothing Waiting for You", bundle: #bundle)
        } icon: {
          Image(systemName: "hand.raised")
        }
      } description: {
        Text(
          "No connected bots or pending requests. This design preview does not request or grant approvals.",
          bundle: #bundle
        )
      } actions: {
        Button {
          workspace.section = .library
        } label: {
          Text("Explore Sample Resources", bundle: #bundle)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(DS.Colors.Surface.window)
      .accessibilityIdentifier("preview.waitingForYou")
    }
  }

  private struct MacSamplePage<ResourceDetail: View>: View {
    let workspace: PreviewWorkspace
    let resourceDetail: (PreviewResource) -> ResourceDetail

    var body: some View {
      VStack(spacing: DS.Space.s0) {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
          Text("Pages", bundle: #bundle)
            .font(.largeTitle.weight(.semibold))
          Text("One original sample note · not a synced page", bundle: #bundle)
            .font(.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
          Button {
            workspace.showResource(.readingNote)
          } label: {
            Label {
              Text("Open Details Beside", bundle: #bundle)
            } icon: {
              Image(systemName: "sidebar.trailing")
            }
          }
          .accessibilityIdentifier("preview.page.openBeside")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s8)
        Divider()
        resourceDetail(.readingNote)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .background(DS.Colors.Surface.window)
      .accessibilityIdentifier("preview.pages")
    }
  }

  private struct MacActivityPage<Activity: View>: View {
    let bot: PreviewBot
    let openBeside: () -> Void
    let activity: (PreviewBot) -> Activity

    var body: some View {
      VStack(spacing: DS.Space.s0) {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
          Text("Example Activity", bundle: #bundle)
            .font(.largeTitle.weight(.semibold))
          Text("Sample work for \(bot.name) · no model or tool has run", bundle: #bundle)
            .font(.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
          Button(action: openBeside) {
            Label {
              Text("Open Activity Beside", bundle: #bundle)
            } icon: {
              Image(systemName: "sidebar.trailing")
            }
          }
          .accessibilityIdentifier("preview.activity.openBeside")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s8)
        Divider()
        activity(bot)
          .id(bot)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .background(DS.Colors.Surface.window)
      .accessibilityIdentifier("preview.activityPage")
    }
  }
#endif
