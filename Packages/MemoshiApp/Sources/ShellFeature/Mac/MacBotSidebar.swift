#if os(macOS)
  import AppCore
  import DesignSystem
  import Foundation
  import SwiftUI

  struct MacBotSidebar: View {
    @Bindable var workspace: PreviewWorkspace
    @Binding var searchText: String
    let liveAssistant: Bool
    let pendingApprovalCount: Int

    var body: some View {
      let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      let showsAssistant = Self.matches(.assistant, query: query)
      let otherBots = PreviewBot.allCases.filter {
        $0 != .assistant && Self.matches($0, query: query)
      }
      let resources =
        query.isEmpty
        ? []
        : PreviewResource.allCases.filter {
          $0.title.localizedStandardContains(query)
            || $0.subtitle.localizedStandardContains(query)
            || $0.shareText.localizedStandardContains(query)
        }

      List(selection: destination) {
        Section {
          ForEach(Self.routes) { section in
            Label(section.title, systemImage: section.systemImage)
              .badge(liveAssistant && section == .waitingForYou ? pendingApprovalCount : 0)
              .frame(minHeight: DS.Layout.Rows.sidebar, alignment: .leading)
              .tag(MacSidebarDestination.section(section))
              .accessibilityIdentifier("preview.route.\(section.rawValue)")
          }
        }

        Section {
          Label {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
              Text("Design review", bundle: #bundle)
              Text("Local preview", bundle: #bundle)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Colors.Text.secondary)
            }
          } icon: {
            Image(systemName: "folder")
          }
          .selectionDisabled()
          .accessibilityElement(children: .combine)
        } header: {
          Text("Projects", bundle: #bundle)
        }

        if showsAssistant {
          Section {
            MacSelectableBotRow(bot: .assistant, workspace: workspace)
              .tag(MacSidebarDestination.bot(.assistant))
          } header: {
            Text("Pinned", bundle: #bundle)
          }
        }

        if !otherBots.isEmpty {
          Section {
            ForEach(otherBots) { bot in
              MacSelectableBotRow(bot: bot, workspace: workspace)
                .tag(MacSidebarDestination.bot(bot))
            }
          } header: {
            Text("Bots", bundle: #bundle)
          }
        }

        if !resources.isEmpty {
          Section {
            ForEach(resources) { resource in
              Button {
                workspace.showResource(resource)
              } label: {
                Label {
                  VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(resource.title)
                      .lineLimit(2)
                    Text(resource.subtitle)
                      .font(DS.Typography.callout)
                      .foregroundStyle(DS.Colors.Text.secondary)
                      .lineLimit(2)
                  }
                } icon: {
                  Image(systemName: resource.systemImage)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(.plain)
              .help(Text("Open sample resource details beside the conversation", bundle: #bundle))
              .accessibilityIdentifier("preview.searchResource.\(resource.rawValue)")
            }
          } header: {
            Text("Sample Resources", bundle: #bundle)
          }
        }

        if !query.isEmpty && !showsAssistant && otherBots.isEmpty && resources.isEmpty {
          Section {
            MacSearchEmptyState(searchText: $searchText)
              .selectionDisabled()
          } header: {
            Text("Search Results", bundle: #bundle)
          }
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
      .background(DS.Colors.Surface.window)
      .accessibilityLabel(
        liveAssistant
          ? Text("Routes, bots and sample resources", bundle: #bundle)
          : Text("Preview routes, bots and resources", bundle: #bundle)
      )
      .accessibilityIdentifier("mac-bot-roster")
      .safeAreaInset(edge: .bottom, spacing: DS.Space.s0) {
        MacSidebarFooter(workspace: workspace, liveAssistant: liveAssistant)
      }
    }

    private var destination: Binding<MacSidebarDestination?> {
      Binding(
        get: {
          workspace.section == .conversation
            ? .bot(workspace.selectedBot) : .section(workspace.section)
        },
        set: { destination in
          switch destination {
          case .bot(let bot):
            workspace.select(bot)
          case .section(let section):
            workspace.section = section
          case nil:
            break
          }
        }
      )
    }

    private static let routes: [PreviewWorkspaceSection] = [
      .waitingForYou, .library, .pages, .activity,
    ]

    private static func matches(_ bot: PreviewBot, query: String) -> Bool {
      query.isEmpty
        || bot.name.localizedStandardContains(query)
        || bot.subtitle.localizedStandardContains(query)
    }
  }

  private enum MacSidebarDestination: Hashable {
    case section(PreviewWorkspaceSection)
    case bot(PreviewBot)
  }

  private struct MacSelectableBotRow: View {
    let bot: PreviewBot
    let workspace: PreviewWorkspace

    var body: some View {
      MacBotRow(bot: bot)
        .contextMenu {
          Button {
            workspace.select(bot)
          } label: {
            Label {
              Text("Open Conversation", bundle: #bundle)
            } icon: {
              Image(systemName: "bubble.left.and.bubble.right")
            }
          }
          Button {
            workspace.openBeside(bot)
          } label: {
            Label {
              Text("Open Beside", bundle: #bundle)
            } icon: {
              Image(systemName: "rectangle.split.2x1")
            }
          }
          Button {
            workspace.showActivity(for: bot)
          } label: {
            Label {
              Text("Show Example Activity", bundle: #bundle)
            } icon: {
              Image(systemName: PreviewRightPane.activity.systemImage)
            }
          }
        }
        .accessibilityAction(named: Text("Open Beside", bundle: #bundle)) {
          workspace.openBeside(bot)
        }
    }
  }

  private struct MacBotRow: View {
    let bot: PreviewBot

    var body: some View {
      HStack(spacing: DS.Space.s4) {
        BotAvatar(symbol: bot.systemImage, size: DS.Space.s7)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: DS.Space.s1) {
          Text(bot.name)
            .font(.body.weight(.medium))
            .lineLimit(1)
          Text(bot.subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .frame(minHeight: DS.Layout.Rows.sidebarBot, alignment: .leading)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("preview-bot-\(bot.rawValue)")
      .help(bot.subtitle)
    }
  }

  private struct MacSearchEmptyState: View {
    @Binding var searchText: String

    var body: some View {
      VStack(alignment: .leading, spacing: DS.Space.s4) {
        Text("No matching bots or sample resources.", bundle: #bundle)
          .font(.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button {
          searchText = ""
        } label: {
          Text("Clear Search", bundle: #bundle)
        }
      }
      .padding(.vertical, DS.Space.s4)
      .accessibilityIdentifier("bot-search-empty-state")
    }
  }

  private struct MacSidebarFooter: View {
    let workspace: PreviewWorkspace
    let liveAssistant: Bool

    var body: some View {
      VStack(alignment: .leading, spacing: DS.Space.s2) {
        Menu {
          ForEach(PreviewBot.allCases) { bot in
            Button {
              workspace.openBeside(bot)
            } label: {
              Label(bot.name, systemImage: bot.systemImage)
            }
          }
        } label: {
          Label {
            Text("Open Beside", bundle: #bundle)
          } icon: {
            Image(systemName: "rectangle.split.2x1")
          }
          .frame(minHeight: DS.Layout.HitTarget.preferred)
        }
        .menuStyle(.borderlessButton)
        .help(Text("Show a bot conversation without replacing the main selection", bundle: #bundle))
        .accessibilityIdentifier("preview.openBeside")

        Label {
          liveAssistant
            ? Text("Development chat and review", bundle: #bundle)
            : Text("Design Preview", bundle: #bundle)
        } icon: {
          Image(systemName: liveAssistant ? "desktopcomputer" : "pencil.and.outline")
        }
        .font(.callout.weight(.medium))

        (liveAssistant
          ? Text("Other bots and resources are examples", bundle: #bundle)
          : Text("Examples only · Not connected", bundle: #bundle))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(DS.Space.s6)
      .accessibilityElement(children: .contain)
    }
  }
#endif
