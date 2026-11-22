import AppCore
import DesignSystem
import SwiftUI

/// Inspectable example work; no row represents an actual model or tool execution.
public struct PreviewActivityView: View {
  private let bot: PreviewBot

  /// Selects the example steps corresponding to the displayed bot.
  public init(bot: PreviewBot) {
    self.bot = bot
  }

  /// Renders a scrollable list with native, keyboard-accessible step disclosures.
  public var body: some View {
    let steps = PreviewActivityStep.examples(for: bot)
    ScrollView {
      VStack(alignment: .leading, spacing: DS.Space.s8) {
        HStack(spacing: DS.Space.s5) {
          BotAvatar(symbol: bot.systemImage)
          VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(verbatim: bot.name)
              .font(.headline)
            Text("Example activity · \(steps.count) steps", bundle: #bundle)
              .font(.subheadline)
              .foregroundStyle(DS.Colors.Text.secondary)
          }
        }
        Text("These are design examples. No model or tool has run.", bundle: #bundle)
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
        ForEach(steps) { step in
          PreviewActivityRow(step: step)
        }
      }
      .padding(DS.Space.s6)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(DS.Colors.Surface.content)
    .accessibilityIdentifier("preview.activity.\(bot.rawValue)")
  }
}

/// One example step. Its texts are catalog lookups; `id` and `symbol` are not shown as text.
struct PreviewActivityStep: Identifiable, Sendable {
  let id: String
  let title: LocalizedStringResource
  let symbol: String
  let subtitle: LocalizedStringResource
  let detail: LocalizedStringResource

  static func examples(for bot: PreviewBot) -> [Self] {
    switch bot {
    case .assistant, .weather:
      forecast
    case .researcher:
      research
    }
  }

  private static let forecast = [
    Self(
      id: "request", title: LocalizedStringResource("Understand the request", bundle: #bundle),
      symbol: "text.bubble",
      subtitle: LocalizedStringResource("Example · planning", bundle: #bundle),
      detail: LocalizedStringResource(
        "Identify the requested place and period. This row illustrates where a concise work summary would appear; it is not model reasoning or a recorded run.",
        bundle: #bundle)
    ),
    Self(
      id: "resource", title: LocalizedStringResource("Read the forecast", bundle: #bundle),
      symbol: "cloud.sun",
      subtitle: LocalizedStringResource("Example · Apple resource", bundle: #bundle),
      detail: LocalizedStringResource(
        "A connected run would read an authorized weather source. The visible card instead uses bundled illustrative values and has not contacted WeatherKit.",
        bundle: #bundle)
    ),
    Self(
      id: "result", title: LocalizedStringResource("Present a native card", bundle: #bundle),
      symbol: "rectangle.on.rectangle",
      subtitle: LocalizedStringResource("Example · result", bundle: #bundle),
      detail: LocalizedStringResource(
        "The sample card is rendered by native SwiftUI. Hours and Days change the local presentation, without a model call or external effect.",
        bundle: #bundle)
    ),
  ]

  private static let research = [
    Self(
      id: "request", title: LocalizedStringResource("Frame the question", bundle: #bundle),
      symbol: "text.bubble",
      subtitle: LocalizedStringResource("Example · planning", bundle: #bundle),
      detail: LocalizedStringResource(
        "Clarify the question before collecting information. This is example presentation text, not a model-generated thought.",
        bundle: #bundle)
    ),
    Self(
      id: "sources", title: LocalizedStringResource("Inspect sources", bundle: #bundle),
      symbol: "doc.text.magnifyingglass",
      subtitle: LocalizedStringResource("Example · research", bundle: #bundle),
      detail: LocalizedStringResource(
        "A connected research run would show actual source calls and outcomes here. No web search, browser or filesystem tool runs in this preview.",
        bundle: #bundle)
    ),
    Self(
      id: "note", title: LocalizedStringResource("Keep a useful note", bundle: #bundle),
      symbol: "note.text",
      subtitle: LocalizedStringResource("Example · result", bundle: #bundle),
      detail: LocalizedStringResource(
        "Keep the answer short and the supporting detail inspectable. The reading note in this example is bundled sample text, not a saved research artifact.",
        bundle: #bundle)
    ),
  ]
}

private struct PreviewActivityRow: View {
  let step: PreviewActivityStep

  var body: some View {
    DisclosureGroup {
      Text(step.detail)
        .font(.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DS.Space.s4)
    } label: {
      HStack(alignment: .top, spacing: DS.Space.s5) {
        Image(systemName: step.symbol)
          .foregroundStyle(DS.Colors.Text.secondary)
          .frame(width: DS.Layout.Composer.controlSize)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: DS.Space.s2) {
          Text(step.title)
            .font(.headline)
          Text(step.subtitle)
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
        }
      }
      .padding(.vertical, DS.Space.s4)
    }
    .accessibilityIdentifier("preview.activityStep.\(step.id)")
  }
}
