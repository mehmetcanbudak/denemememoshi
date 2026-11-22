import DesignSystem
import MemoshiProtocol
import SwiftUI

struct ChatRecoveryNotice: View {
  let model: LiveChatModel
  let recovery: ChatRecoveryHold

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Label("Recovery required · this chat is paused", systemImage: "exclamationmark.triangle")
        .font(.headline)
      Text(
        "A tool may already have changed something. No new model turn or tool call can start while its outcome is unresolved."
      )
      .font(.callout)
      ForEach(recovery.steps, id: \.self) { held in
        if let step = held.step {
          VStack(alignment: .leading, spacing: DS.Space.s2) {
            Label(step.tool, systemImage: "pause.circle")
              .font(.callout.monospaced())
              .accessibilityLabel("\(step.tool), outcome unresolved")
            if let card = step.cardId, let choices = model.resumeChoices[card], !choices.isEmpty {
              ResumeChoiceButtons(model: model, card: card, choices: choices)
            }
          }
        }
      }
      // Only the choices some held step offers now are described.
      let offered = Set(model.resumeChoices.values.joined())
      VStack(alignment: .leading, spacing: DS.Space.s2) {
        if offered.contains(.runAgain) { Text("Run Again runs the step once more.") }
        if offered.contains(.skip) {
          Text("Skip leaves it as it is and does not run it again.")
        }
        if offered.contains(.markDone) { Text("Mark as Done tells the bot that it happened.") }
        Text(
          "You can also queue or cancel new messages. Stop does not undo an uncertain effect.")
      }
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DS.Space.s5)
    .background(DS.Colors.Surface.raised)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("chat.recoveryRequired")
  }
}

/// The choices a held step's Resume card offers now (D51).
private struct ResumeChoiceButtons: View {
  let model: LiveChatModel
  let card: CardID
  let choices: [ResumeAction]

  var body: some View {
    HStack(spacing: DS.Space.s3) {
      ForEach(choices, id: \.self) { choice in
        Button(Self.title(choice)) { model.answerResume(card, choice) }
          .disabled(model.connection != .connected || model.answeringResume.contains(card))
          .accessibilityIdentifier("chat.resume.\(choice.rawValue).\(card.rawValue)")
      }
      if model.answeringResume.contains(card) { ProgressView().controlSize(.small) }
    }
  }

  private static func title(_ choice: ResumeAction) -> LocalizedStringKey {
    switch choice {
    case .runAgain: "Run Again"
    case .skip: "Skip"
    case .markDone: "Mark as Done"
    case .unknown: ""
    }
  }
}

struct QueuedChatInputsView: View {
  let model: LiveChatModel

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Label("Queued messages", systemImage: "tray.full")
        .font(.headline)
      Text(
        "Saved on this Mac, not added to the model's conversation. They wait for recovery to settle."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      ForEach(model.queued, id: \.requestId) { input in
        VStack(alignment: .leading, spacing: DS.Space.s3) {
          Text(
            verbatim: input.content.reduce(into: "") { result, part in
              if case .text(let text) = part { result.append(text.text) }
            }
          )
          .font(.body)
          .textSelection(.enabled)
          HStack {
            Text(verbatim: input.model.ref.rawValue)
              .font(DS.Typography.callout.monospaced())
              .foregroundStyle(DS.Colors.Text.secondary)
            Spacer(minLength: DS.Space.s3)
            Button(
              model.cancelingQueued.contains(input.requestId) ? "Canceling…" : "Cancel Message"
            ) {
              model.cancelQueued(input)
            }
            .disabled(
              model.connection != .connected || model.cancelingQueued.contains(input.requestId)
            )
            .accessibilityIdentifier("chat.cancelQueued.\(input.requestId.rawValue)")
          }
        }
        .padding(DS.Space.s4)
        .background(DS.Colors.Surface.content, in: RoundedRectangle(cornerRadius: DS.Radius.bubble))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.queued.\(input.requestId.rawValue)")
      }
    }
    .padding(DS.Space.s5)
    .background(DS.Colors.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.bubble))
    .accessibilityIdentifier("chat.queuedMessages")
  }
}
