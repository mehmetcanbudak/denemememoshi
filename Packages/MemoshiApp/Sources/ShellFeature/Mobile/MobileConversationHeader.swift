#if os(iOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  struct MobileConversationHeader: View {
    let bot: PreviewBot
    /// The real in-process Chat rather than a local example.
    var isLive = false
    let selectableBots: [PreviewBot]
    let selectBot: @MainActor (PreviewBot) -> Void
    /// One line, for iPhone landscape: the detail is left out, and the badge too where the line
    /// is short. Both stay in the accessibility label and the Large Content Viewer.
    var compact = false

    var body: some View {
      if selectableBots.isEmpty {
        identity
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(disclosure)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("workspace.identity")
          .accessibilityShowsLargeContentViewer { largeContent }
      } else {
        Menu {
          Picker(selection: Binding(get: { bot }, set: selectBot)) {
            ForEach(selectableBots) { choice in
              Label(choice.name, systemImage: choice.systemImage)
                .tag(choice)
            }
          } label: {
            Text("Preview bot", bundle: #bundle)
          }
          .pickerStyle(.inline)
        } label: {
          HStack(spacing: DS.Space.s2) {
            identity
            Image(systemName: "chevron.down")
              .font(.subheadline)
              .foregroundStyle(DS.Colors.Text.secondary)
              .accessibilityHidden(true)
          }
          .frame(minHeight: DS.Layout.Composer.minHeight)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Choose preview bot", bundle: #bundle))
        .accessibilityValue(bot.name)
        .accessibilityHint(
          Text(
            "Switches the visible local conversation without clearing drafts.", bundle: #bundle)
        )
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("workspace.botChooser")
        .accessibilityShowsLargeContentViewer { largeContent }
      }
    }

    private var detail: String {
      isLive
        ? String(localized: "Engine on this device", bundle: #bundle)
        : String(localized: "Preview · Not connected", bundle: #bundle)
    }

    private var badge: String {
      isLive
        ? String(localized: "Development", bundle: #bundle)
        : String(localized: "Preview", bundle: #bundle)
    }

    /// Everything the identity discloses, also what the one-line form leaves out.
    private var disclosure: Text {
      Text("\(bot.name), \(badge), \(detail)", bundle: #bundle)
    }

    private var largeContent: some View {
      Label {
        disclosure
      } icon: {
        Image(systemName: bot.systemImage)
      }
    }

    @ViewBuilder private var identity: some View {
      if compact {
        HStack(spacing: DS.Space.s3) {
          Image(systemName: bot.systemImage)
          ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.s3) {
              name.fixedSize()
              FloatingBotBadge(badge)
            }
            name
          }
          Spacer(minLength: 0)
        }
        .foregroundStyle(DS.Colors.Text.primary)
      } else {
        FloatingBotIdentity(name: bot.name, symbol: bot.systemImage, detail: detail, badge: badge)
      }
    }

    private var name: some View {
      Text(verbatim: bot.name)
        .font(DS.Typography.headline)
        .lineLimit(1)
    }
  }
#endif
