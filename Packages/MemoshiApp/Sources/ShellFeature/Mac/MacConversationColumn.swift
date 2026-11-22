#if os(macOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  struct MacConversationColumn<Conversation: View>: View {
    let bot: PreviewBot
    let isLive: Bool
    let isSecondary: Bool
    let select: @MainActor (PreviewBot) -> Void
    let showActivity: () -> Void
    let openBeside: (() -> Void)?
    let conversation: (PreviewBot) -> Conversation

    var body: some View {
      VStack(spacing: DS.Space.s0) {
        MacConversationHeader(
          bot: bot,
          isLive: isLive,
          isSecondary: isSecondary,
          select: select,
          showActivity: showActivity,
          openBeside: openBeside
        )
        conversation(bot)
          .id(bot)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .background(DS.Colors.Surface.window)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(isSecondary ? "mac-conversation-secondary" : "mac-conversation-main")
    }
  }

  private struct MacConversationHeader: View {
    let bot: PreviewBot
    let isLive: Bool
    let isSecondary: Bool
    let select: @MainActor (PreviewBot) -> Void
    let showActivity: () -> Void
    let openBeside: (() -> Void)?
    @State private var isBotPickerPresented = false

    var body: some View {
      VStack(alignment: .leading, spacing: DS.Space.s3) {
        if isSecondary {
          Text("Bot conversation", bundle: #bundle)
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
        }

        HStack(spacing: DS.Space.s4) {
          Button {
            isBotPickerPresented.toggle()
          } label: {
            HStack(spacing: DS.Space.s3) {
              FloatingBotIdentity(
                name: bot.name, symbol: bot.systemImage,
                detail: isLive
                  ? String(
                    localized: "Development chat · Production tools disabled", bundle: #bundle)
                  : String(localized: "Design Preview · Not connected", bundle: #bundle),
                badge: isLive
                  ? String(localized: "Local", bundle: #bundle)
                  : String(localized: "Preview", bundle: #bundle))
              Image(systemName: "chevron.down")
                .font(DS.Typography.subheadline)
                .foregroundStyle(DS.Colors.Text.secondary)
            }
          }
          .buttonStyle(.plain)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityLabel(Text("Bot conversation: \(bot.name)", bundle: #bundle))
          .accessibilityHint(Text("Choose a bot or inspect its example activity.", bundle: #bundle))
          .accessibilityIdentifier(isSecondary ? "preview.secondaryBot" : "preview.primaryBot")
          .popover(isPresented: $isBotPickerPresented) {
            MacConversationOptions(
              bot: bot, select: select,
              showActivity: showActivity, openBeside: openBeside,
              isPresented: $isBotPickerPresented
            )
          }

          if let openBeside {
            Button(action: openBeside) {
              Label {
                Text("Open Beside", bundle: #bundle)
              } icon: {
                Image(systemName: "rectangle.split.2x1")
              }
              .labelStyle(.iconOnly)
              .frame(
                minWidth: DS.Layout.HitTarget.preferred,
                minHeight: DS.Layout.HitTarget.preferred
              )
            }
            .buttonStyle(.borderless)
            .help(Text("Open this bot conversation beside the main pane", bundle: #bundle))
            .accessibilityIdentifier("preview.openCurrentBeside")
          }
        }
      }
      .padding(.horizontal, DS.Space.s6)
      .padding(.vertical, DS.Space.s5)
    }
  }

  private struct MacConversationOptions: View {
    let bot: PreviewBot
    let select: @MainActor (PreviewBot) -> Void
    let showActivity: () -> Void
    let openBeside: (() -> Void)?
    @Binding var isPresented: Bool

    var body: some View {
      VStack(alignment: .leading, spacing: DS.Space.s5) {
        Text("Bot conversation", bundle: #bundle)
          .font(.headline)
        Picker(
          selection: Binding(
            get: { bot },
            set: { choice in
              select(choice)
              isPresented = false
            }
          )
        ) {
          ForEach(PreviewBot.allCases) { choice in
            Label(choice.name, systemImage: choice.systemImage).tag(choice)
          }
        } label: {
          Text("Bot", bundle: #bundle)
        }
        .pickerStyle(.radioGroup)
        Divider()
        Button {
          isPresented = false
          showActivity()
        } label: {
          Label {
            Text("Show Example Activity", bundle: #bundle)
          } icon: {
            Image(systemName: PreviewRightPane.activity.systemImage)
          }
        }
        if let openBeside {
          Button {
            isPresented = false
            openBeside()
          } label: {
            Label {
              Text("Open Beside", bundle: #bundle)
            } icon: {
              Image(systemName: "rectangle.split.2x1")
            }
          }
        }
      }
      .padding(DS.Space.s6)
      .frame(minWidth: DS.Layout.Sidebar.min, alignment: .leading)
    }
  }
#endif
