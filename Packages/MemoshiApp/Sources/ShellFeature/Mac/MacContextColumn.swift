#if os(macOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  struct MacContextColumn<Conversation: View, Activity: View, ResourceDetail: View>: View {
    @Bindable var workspace: PreviewWorkspace
    let liveAssistant: Bool
    let conversation: (PreviewBot) -> Conversation
    let activity: (PreviewBot) -> Activity
    let resourceDetail: (PreviewResource) -> ResourceDetail

    var body: some View {
      VStack(spacing: DS.Space.s0) {
        MacContextHeader(workspace: workspace)
        Divider()

        switch workspace.rightPane {
        case .activity:
          MacContextActivity(workspace: workspace, activity: activity)
        case .resource:
          MacContextResource(workspace: workspace, resourceDetail: resourceDetail)
        case .conversation:
          let bot = workspace.secondaryBot
          MacConversationColumn(
            bot: bot,
            isLive: liveAssistant && bot == .assistant,
            isSecondary: true,
            select: { workspace.secondaryBot = $0 },
            showActivity: { workspace.showActivity(for: bot) },
            openBeside: nil,
            conversation: conversation
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(DS.Colors.Surface.content)
      .accessibilityIdentifier("mac-context-pane")
    }
  }

  private struct MacContextHeader: View {
    @Bindable var workspace: PreviewWorkspace

    var body: some View {
      HStack(spacing: DS.Space.s4) {
        Picker(selection: $workspace.rightPane) {
          ForEach(PreviewRightPane.allCases) { pane in
            Label(pane.title, systemImage: pane.systemImage)
              .tag(pane)
          }
        } label: {
          Text("Context", bundle: #bundle)
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("preview.contextChooser")
        .help(
          Text(
            "Choose example Activity, sample resource details or a bot conversation",
            bundle: #bundle))

        Button {
          workspace.isInspectorPresented = false
        } label: {
          Label {
            Text("Close Context", bundle: #bundle)
          } icon: {
            Image(systemName: "xmark")
          }
          .labelStyle(.iconOnly)
          .frame(
            minWidth: DS.Layout.HitTarget.preferred,
            minHeight: DS.Layout.HitTarget.preferred
          )
        }
        .buttonStyle(.borderless)
        .help(Text("Close the context pane (⌃⌘I)", bundle: #bundle))
        .accessibilityIdentifier("preview.closeContext")
      }
      .padding(DS.Space.s5)
    }
  }

  private struct MacContextActivity<Activity: View>: View {
    let workspace: PreviewWorkspace
    let activity: (PreviewBot) -> Activity

    var body: some View {
      VStack(spacing: DS.Space.s0) {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
          Text("Example Activity", bundle: #bundle)
            .font(.headline)
          Picker(
            selection: Binding(
              get: { workspace.activityBot },
              set: { workspace.showActivity(for: $0) }
            )
          ) {
            ForEach(PreviewBot.allCases) { bot in
              Label(bot.name, systemImage: bot.systemImage)
                .tag(bot)
            }
          } label: {
            Text("Bot", bundle: #bundle)
          }
          .pickerStyle(.menu)
          .accessibilityIdentifier("preview.activityBot")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s6)
        Divider()
        activity(workspace.activityBot)
          .id(workspace.activityBot)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private struct MacContextResource<ResourceDetail: View>: View {
    let workspace: PreviewWorkspace
    let resourceDetail: (PreviewResource) -> ResourceDetail

    var body: some View {
      VStack(spacing: DS.Space.s0) {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
          Text("Sample Resource", bundle: #bundle)
            .font(.headline)
          Picker(
            selection: Binding(
              get: { workspace.selectedResource },
              set: { workspace.showResource($0) }
            )
          ) {
            ForEach(PreviewResource.allCases) { resource in
              Label(resource.title, systemImage: resource.systemImage)
                .tag(resource)
            }
          } label: {
            Text("Resource", bundle: #bundle)
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .accessibilityIdentifier("preview.resourceChooser")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s6)
        Divider()
        resourceDetail(workspace.selectedResource)
          .id(workspace.selectedResource)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
#endif
