import AppCore
import DesignSystem
import SwiftUI

/// A reviewable native conversation surface. Its examples never enter the protocol or engine.
public struct PreviewConversationView: View {
  private let bot: PreviewBot
  private let drafts: ComposerDrafts
  private let showActivity: () -> Void
  private let showResource: (PreviewResource) -> Void

  /// Composes an example transcript with local drafts and contextual Activity/resource actions.
  public init(
    bot: PreviewBot, drafts: ComposerDrafts,
    showActivity: @escaping () -> Void,
    showResource: @escaping (PreviewResource) -> Void
  ) {
    self.bot = bot
    self.drafts = drafts
    self.showActivity = showActivity
    self.showResource = showResource
  }

  /// Renders opaque native cards above the keyboard-aware local-draft composer.
  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DS.Layout.Message.turnSpacing) {
        DesignPreviewNotice()
        PreviewTranscript(bot: bot, showActivity: showActivity, showResource: showResource)
      }
      .frame(maxWidth: DS.Layout.Conversation.contentMaxWidth)
      .frame(maxWidth: .infinity)
      .padding(DS.Space.s6)
    }
    .background(DS.Colors.Surface.window)
    .safeAreaInset(edge: .bottom, spacing: DS.Space.s0) {
      PreviewComposer(bot: bot, drafts: drafts)
        .frame(maxWidth: DS.Layout.Conversation.contentMaxWidth)
        .padding(.horizontal, DS.Space.s6)
        .padding(.vertical, DS.Space.s5)
        .frame(maxWidth: .infinity)
        .background(DesignControlRoles.barBacking)
    }
    .accessibilityIdentifier("preview.conversation.\(bot.rawValue)")
  }
}

private struct PreviewTranscript: View {
  let bot: PreviewBot
  let showActivity: () -> Void
  let showResource: (PreviewResource) -> Void

  var body: some View {
    switch bot {
    case .assistant:
      PreviewMessage(
        text: LocalizedStringResource("What does tomorrow look like?", bundle: #bundle),
        isUser: true)
      PreviewWorkedChip(bot: bot, action: showActivity)
      PreviewMessage(
        text: LocalizedStringResource(
          "A mild start, with some cloud later. Here’s a sample forecast you can explore.",
          bundle: #bundle))
      PreviewWeatherCard(showDetails: { showResource(.forecast) })
      PreviewMessage(
        text: LocalizedStringResource(
          "Switch between Hours and Days to try the card. Activity keeps the details beside the conversation, instead of filling the chat.",
          bundle: #bundle)
      )
    case .researcher:
      PreviewMessage(
        text: LocalizedStringResource(
          "What makes an assistant feel at home on Apple devices?", bundle: #bundle), isUser: true)
      PreviewWorkedChip(bot: bot, action: showActivity)
      PreviewMessage(
        text: LocalizedStringResource(
          "Keep the conversation central, make important information tangible, and leave the details one click away.",
          bundle: #bundle)
      )
      PreviewResearchCard(showDetails: { showResource(.readingNote) })
      PreviewMessage(
        text: LocalizedStringResource(
          "This reading note is an example, not the result of a model or a web search. You can keep a separate local draft for each bot.",
          bundle: #bundle)
      )
    case .weather:
      PreviewMessage(
        text: LocalizedStringResource("Show me a compact forecast for the week.", bundle: #bundle),
        isUser: true)
      PreviewWorkedChip(bot: bot, action: showActivity)
      PreviewMessage(
        text: LocalizedStringResource(
          "Here’s the sample forecast. A card can carry the details without turning the whole conversation into a dashboard.",
          bundle: #bundle)
      )
      PreviewWeatherCard(showDetails: { showResource(.forecast) })
    }
  }
}

private struct PreviewMessage: View {
  let text: LocalizedStringResource
  var isUser = false

  var body: some View {
    HStack {
      if isUser { Spacer(minLength: DS.Space.s9) }
      Text(text)
        .font(.body)
        .foregroundStyle(isUser ? DS.Colors.Text.onUserBubble : DS.Colors.Text.primary)
        .textSelection(.enabled)
        .padding(.vertical, DS.Layout.Message.bubblePaddingV)
        .padding(.horizontal, DS.Layout.Message.bubblePaddingH)
        .background(
          isUser ? DS.Colors.Surface.userBubble : DS.Colors.Surface.raised,
          in: RoundedRectangle(cornerRadius: DS.Radius.bubble)
        )
      if !isUser { Spacer(minLength: DS.Space.s8) }
    }
    // Keep sender semantics off selectable Text: macOS 27.0.1 can recurse resolving its AX label.
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isStaticText)
    .accessibilityLabel(
      isUser
        ? Text("Example user message: \(String(localized: text))", bundle: #bundle)
        : Text("Example assistant message: \(String(localized: text))", bundle: #bundle))
  }
}

private struct PreviewWorkedChip: View {
  let bot: PreviewBot
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: DS.Space.s3) {
        Image(systemName: "list.bullet.rectangle")
        Text(
          "Example work · \(PreviewActivityStep.examples(for: bot).count) steps", bundle: #bundle)
        Image(systemName: "chevron.right")
      }
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      .padding(.horizontal, DS.Space.s5)
      .padding(.vertical, DS.Space.s3)
      .background(DS.Colors.Surface.card, in: Capsule())
      .frame(minHeight: DS.Layout.Composer.minHeight)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("Inspect example activity", bundle: #bundle))
    .accessibilityIdentifier("preview.openActivity")
  }
}
