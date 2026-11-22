import DesignSystem
import MemoshiProtocol
import MemoshiRuntime
import SwiftUI

struct LiveChatComposer: View {
  @Bindable var model: LiveChatModel
  let setup: ModelProviderSetup
  var isLiveBot: Bool = true
  var exampleBotName: String = "Proofer"
  var exampleModelName: String = "Claude Opus 5.5"
  var onOpenFolders: () -> Void = {}
  var onOpenModelSettings: () -> Void = {}
  var focus: FocusState<LiveWorkspaceFocus?>.Binding
  @State private var isDiscardingRecord = false
  @State private var isDiscardingRefused = false

  private var isComposerFocused: Bool { focus.wrappedValue == .composer }

  private var thinkingPillLabel: String {
    if isLiveBot && model.isSelectedModelLocal {
      return String(localized: "Default")
    }
    let effective = model.effectiveThinkingEffort
    if model.composerSpeedMode == .fast && effective != model.composerThinkingEffort {
      return "Fast · \(effective.composerDisplayName)"
    }
    return effective.composerDisplayName
  }

  private var displayedModelName: String {
    guard isLiveBot else { return exampleModelName }
    if let botModel = model.botModel {
      return botModel.ref.rawValue
    }
    if !setup.selectedModel.isEmpty {
      return setup.selectedModel
    }
    return String(localized: "Select Model")
  }

  private var activeBotName: String {
    isLiveBot ? (model.chat?.title ?? String(localized: "Assistant")) : exampleBotName
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let explanation = model.unreadableSendExplanation {
        HStack {
          Text(verbatim: explanation)
            .font(DS.Typography.callout)
            .foregroundStyle(WarmShellColors.mutedText)
            .accessibilityIdentifier("chat.unreadableSendExplanation")
          Spacer()
          Button("Discard Unreadable Record…", role: .destructive) { isDiscardingRecord = true }
            .disabled(!model.canDiscardUnreadableSend)
            .accessibilityIdentifier("chat.discardUnreadableSend")
        }
      } else if model.hasUnconfirmedSend {
        HStack {
          if let reason = model.refusedSendReason {
            Text(verbatim: reason)
              .font(DS.Typography.callout)
              .foregroundStyle(WarmShellColors.mutedText)
              .accessibilityIdentifier("chat.refusedSendReason")
          } else {
            Text("Delivery unconfirmed · original request preserved")
              .font(DS.Typography.callout)
              .foregroundStyle(WarmShellColors.mutedText)
          }
          Spacer()
          Button("Retry Same Message") { model.retrySend() }
            .disabled(!model.canRetrySend)
            .accessibilityIdentifier("chat.retrySend")
          if model.refusedSendReason != nil {
            Button("Discard Refused Message…", role: .destructive) { isDiscardingRefused = true }
              .disabled(!model.canDiscardRefusedSend)
              .accessibilityIdentifier("chat.discardRefusedSend")
          }
        }
      }
      TextField(
        "Message \(activeBotName)", text: $model.draft,
        prompt: Text("Message \(activeBotName)")
          .foregroundStyle(WarmShellColors.mutedText.opacity(0.75)),
        axis: .vertical
      )
      .textFieldStyle(.plain)
      .font(.system(size: 14.5))
      .foregroundStyle(WarmShellColors.primaryText)
      .lineLimit(1...6)
      .frame(minHeight: 22, alignment: .topLeading)
      // A draft is saved per conversation, so nothing is typed before one is selected.
      .disabled(model.isSending || model.hasUnconfirmedSend || model.chat == nil)
      .focused(focus, equals: .composer)
      .onKeyPress(.return, phases: .down) { press in
        guard isComposerFocused else { return .ignored }
        if press.modifiers == .command {
          if model.canSend {
            model.send()
            return .handled
          }
          if model.canQueueWhileWorking {
            model.send(whenBusy: .followUp)
            return .handled
          }
        } else if press.modifiers == [.command, .shift], model.canQueueWhileWorking {
          model.send(whenBusy: .steer)
          return .handled
        }
        return .ignored
      }
      .accessibilityLabel("Message \(activeBotName)")
      .accessibilityHint(
        "Saved as a local draft. Use Send or Command Return to submit to the explicitly selected model."
      )
      .accessibilityIdentifier("chat.composer")

      HStack(spacing: 8) {
        Button(action: onOpenFolders) {
          Image(systemName: "plus")
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(WarmShellColors.primaryText)
            .frame(width: 32, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Folders & Attachments")
        .accessibilityIdentifier("chat.attach")

        if let botModel = model.botModel {
          HStack(spacing: 6) {
            Image(systemName: "sparkles")
              .font(.system(size: 13, weight: .semibold))
            Text(verbatim: botModel.ref.rawValue)
              .font(.system(size: 13.5, weight: .medium))
              .lineLimit(1)
          }
          .foregroundStyle(WarmShellColors.primaryText)
          .padding(.horizontal, 14)
          .frame(height: 34)
          .background(WarmShellColors.composerPill, in: Capsule())
          .environment(\.layoutDirection, .leftToRight)
          .help("This bot's model and effort. Change them in Edit Bot.")
          .accessibilityLabel("Model")
          .accessibilityValue(Text(verbatim: botModel.ref.rawValue))
          .accessibilityIdentifier("chat.botModel")
        } else {
          Menu {
            ForEach(setup.models, id: \.ref.ref.rawValue) { entry in
              Button {
                setup.selectedModel = entry.ref.ref.rawValue
              } label: {
                if setup.selectedModel == entry.ref.ref.rawValue {
                  Label(entry.ref.ref.rawValue, systemImage: "checkmark")
                } else {
                  Text(verbatim: entry.ref.ref.rawValue)
                }
              }
            }
            if !setup.models.isEmpty { Divider() }
            Button("Model Settings…", systemImage: "slider.horizontal.3") {
              onOpenModelSettings()
            }
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WarmShellColors.primaryText)
              Text(verbatim: displayedModelName)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(WarmShellColors.primaryText)
                .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(WarmShellColors.composerPill, in: Capsule())
            .contentShape(Capsule())
          }
          .menuStyle(.button)
          .buttonStyle(.plain)
          .menuIndicator(.hidden)
          .disabled(model.isWorking || model.hasUnconfirmedSend || setup.isConfiguring)
          .accessibilityIdentifier("chat.modelPicker")
        }

        Menu {
          ForEach(ThinkingEffort.composerChoices, id: \.rawValue) { level in
            Button {
              model.composerThinkingEffort = level
            } label: {
              if model.composerThinkingEffort == level {
                Label(level.composerDisplayName, systemImage: "checkmark")
              } else {
                Text(verbatim: level.composerDisplayName)
              }
            }
          }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.67percent")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(
                model.isSelectedModelLocal
                  ? WarmShellColors.mutedText : WarmShellColors.badgeText)
            Text(verbatim: thinkingPillLabel)
              .font(.system(size: 13.5, weight: .medium))
              .foregroundStyle(
                model.isSelectedModelLocal
                  ? WarmShellColors.mutedText : WarmShellColors.primaryText)
          }
          .padding(.horizontal, 14)
          .frame(height: 34)
          .background(WarmShellColors.composerPill, in: Capsule())
          .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(
          model.isWorking || model.hasUnconfirmedSend || (isLiveBot && model.isSelectedModelLocal))
        .help(
          model.isSelectedModelLocal
            ? "Local server models use the server's default reasoning configuration."
            : "Reasoning effort sent to the selected model."
        )
        .accessibilityIdentifier("chat.thinkingPicker")

        Menu {
          ForEach(ComposerSpeedMode.allCases) { mode in
            Button {
              model.composerSpeedMode = mode
            } label: {
              if model.composerSpeedMode == mode {
                Label(mode.rawValue, systemImage: "checkmark")
              } else {
                Text(verbatim: mode.rawValue)
              }
            }
          }
        } label: {
          HStack(spacing: 5) {
            Image(systemName: model.composerSpeedMode == .fast ? "bolt.fill" : "bolt")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(
                model.composerSpeedMode == .fast
                  ? WarmShellColors.badgeText : WarmShellColors.primaryText)
            Text(verbatim: model.composerSpeedMode.rawValue)
              .font(.system(size: 13.5, weight: .medium))
              .foregroundStyle(WarmShellColors.primaryText)
          }
          .padding(.horizontal, 14)
          .frame(height: 34)
          .background(
            model.composerSpeedMode == .fast
              ? WarmShellColors.composerPill.opacity(0.85) : WarmShellColors.composerPill,
            in: Capsule())
          .overlay {
            if model.composerSpeedMode == .fast {
              Capsule().fill(Color.black.opacity(0.06))
            }
          }
          .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(model.isWorking || model.hasUnconfirmedSend)
        .help(
          model.composerSpeedMode == .fast
            ? "Fast mode: caps reasoning effort to Low for quicker replies."
            : "Standard mode: uses your chosen thinking level."
        )
        .accessibilityIdentifier("chat.speedPicker")

        Spacer(minLength: 6)

        if model.isWorking {
          if model.canQueueWhileWorking {
            Button {
              model.send(whenBusy: .followUp)
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "text.badge.plus")
                  .font(.system(size: 11.5, weight: .semibold))
                Text("Queue")
                  .font(.system(size: 12, weight: .semibold))
              }
              .foregroundStyle(WarmShellColors.primaryText)
              .padding(.horizontal, 11)
              .frame(height: 32)
              .background(WarmShellColors.composerPill, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Queue follow-up after this turn finishes (⌘Return)")
            .accessibilityIdentifier("chat.queueFollowUp")

            Button {
              model.send(whenBusy: .steer)
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                  .font(.system(size: 12, weight: .semibold))
                Text("Steer")
                  .font(.system(size: 12, weight: .semibold))
              }
              .foregroundStyle(WarmShellColors.badgeText)
              .padding(.horizontal, 11)
              .frame(height: 32)
              .background(WarmShellColors.badgeFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Stop this turn and redirect with your message (⇧⌘Return)")
            .accessibilityIdentifier("chat.steerTurn")
          }

          Button {
            model.stopGeneration()
          } label: {
            Image(systemName: "stop.fill")
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(.white)
              .frame(width: 32, height: 32)
              .background(WarmShellColors.userBubble, in: Circle())
          }
          .buttonStyle(.plain)
          .disabled(model.isStopping || model.connection != .connected)
          .help(model.isStopping ? "Stopping…" : "Stop")
          .accessibilityLabel(model.isStopping ? "Stopping…" : "Stop")
          .accessibilityIdentifier("chat.stop")
        } else {
          Button {} label: {
            Image(systemName: "waveform")
              .font(.system(size: 16, weight: .regular))
              .foregroundStyle(WarmShellColors.mutedText.opacity(0.65))
              .frame(width: 32, height: 34)
          }
          .buttonStyle(.plain)
          .disabled(true)
          .help("Voice Mode (available in Phase 2)")
          .accessibilityIdentifier("chat.voiceMode")

          Button {} label: {
            Image(systemName: "mic")
              .font(.system(size: 16, weight: .regular))
              .foregroundStyle(WarmShellColors.mutedText.opacity(0.65))
              .frame(width: 32, height: 34)
          }
          .buttonStyle(.plain)
          .disabled(true)
          .help("On-device Dictation (available in Phase 2)")
          .accessibilityIdentifier("chat.dictation")

          if model.canSend {
            Button {
              model.send()
            } label: {
              Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(WarmShellColors.userBubble, in: Circle())
            }
            .buttonStyle(.plain)
            .help(model.recovery == nil ? "Send" : "Queue Message")
            .accessibilityLabel(model.recovery == nil ? "Send" : "Queue Message")
            .accessibilityIdentifier("chat.send")
          }
        }
      }
      if let provider = model.sendProvider, let usage = model.sendUsage,
        usage != .onDevice
      {
        Group {
          if usage == .subscription {
            Text(
              "Messages go to \(provider.name) using your ChatGPT subscription. Account usage limits apply."
            )
          } else {
            Text("Messages go to \(provider.name) and may incur API usage charges.")
          }
        }
        .font(.system(size: 11))
        .foregroundStyle(WarmShellColors.mutedText)
        .accessibilityIdentifier("chat.remoteProviderNotice")
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 10)
    .background(
      WarmShellColors.composerBg.opacity(0.65),
      in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .confirmationDialog(
      "Discard Unreadable Delivery Record?", isPresented: $isDiscardingRecord,
      titleVisibility: .visible
    ) {
      Button("Discard", role: .destructive) { model.discardUnreadableSend() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "It cannot be read or retried. Discarding sends nothing and cannot undo a message the runtime already accepted; check this conversation before sending the same message again."
      )
    }
    .confirmationDialog(
      "Discard Refused Message?", isPresented: $isDiscardingRefused, titleVisibility: .visible
    ) {
      Button("Discard", role: .destructive) { model.discardRefusedSend() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "The runtime refused it, so it was not delivered. Discarding removes only the saved request; your draft stays and nothing is sent."
      )
    }
  }
}
