import AppKit
import Carbon.HIToolbox
import DesignSystem
import Foundation
import MemoshiProtocol
import Observation
import SwiftUI

/// Optional system-wide hotkey (⌥⇧Space) that summons Memoshi Quick Entry without requiring
/// Accessibility permissions (D86).
@MainActor
@Observable
final class QuickEntryHotKeyManager {
  private static let preferenceKey = "quickEntry.globalHotKeyEnabled"
  private static let signature: OSType = 0x4D4D_5349 // "MMSI"
  private static let hotKeyIdentifier: UInt32 = 1
  private static weak var activeManager: QuickEntryHotKeyManager?

  var isEnabled: Bool {
    didSet {
      defaults.set(isEnabled, forKey: Self.preferenceKey)
      if isEnabled {
        registerIfNeeded()
      } else {
        unregister()
      }
    }
  }

  private(set) var isRegistered = false
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
  @ObservationIgnored private var handlerRef: EventHandlerRef?
  @ObservationIgnored private var onTrigger: (@MainActor () -> Void)?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if defaults.object(forKey: Self.preferenceKey) == nil {
      self.isEnabled = true
    } else {
      self.isEnabled = defaults.bool(forKey: Self.preferenceKey)
    }
  }

  func start(onTrigger: @escaping @MainActor () -> Void) {
    self.onTrigger = onTrigger
    Self.activeManager = self
    if isEnabled {
      registerIfNeeded()
    }
  }

  func stop() {
    unregister()
    if Self.activeManager === self {
      Self.activeManager = nil
    }
  }

  private static func handleHotKeyTriggered() {
    activeManager?.onTrigger?()
  }

  private func registerIfNeeded() {
    guard hotKeyRef == nil else { return }
    if handlerRef == nil {
      var eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
      )
      let handlerStatus = InstallEventHandler(
        GetApplicationEventTarget(),
        { _, _, _ in
          Task { @MainActor in
            QuickEntryHotKeyManager.handleHotKeyTriggered()
          }
          return noErr
        },
        1,
        &eventType,
        nil,
        &handlerRef
      )
      guard handlerStatus == noErr else { return }
    }

    let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyIdentifier)
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(kVK_Space),
      UInt32(optionKey | shiftKey),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &ref
    )
    if status == noErr, let ref {
      hotKeyRef = ref
      isRegistered = true
    } else {
      isRegistered = false
    }
  }

  private func unregister() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
    if let handlerRef {
      RemoveEventHandler(handlerRef)
      self.handlerRef = nil
    }
    isRegistered = false
  }
}

/// Compact floating Quick Entry window for dispatching a prompt to any bot from anywhere (D86).
struct QuickEntryWindowView: View {
  let model: LiveChatModel
  let supervisor: DaemonSupervisor
  let navigation: LiveWorkspaceNavigation
  let appearances: BotAppearanceStore
  let hotKeyManager: QuickEntryHotKeyManager

  @State private var promptText = ""
  @State private var selectedConversationID: ConversationID?
  @State private var isDispatching = false
  @State private var statusNote: String?
  @FocusState private var isInputFocused: Bool
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismiss) private var dismiss

  private var targetConversation: ChatSummary? {
    if let selectedConversationID,
      let match = model.directory.conversations.first(where: { $0.id == selectedConversationID })
    {
      return match
    }
    return model.chat ?? model.directory.conversations.first
  }

  private var canSubmit: Bool {
    !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && model.connection == .connected
      && !isDispatching
      && !model.isSending
      && !model.hasUnconfirmedSend
      && !model.hasUnreadableSend
      && targetConversation != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      headerRow
      promptInput
      footerRow
    }
    .padding(16)
    .frame(width: 560)
    .background(WarmShellColors.canvas)
    .accessibilityIdentifier("window.quickEntry")
    .onAppear {
      if selectedConversationID == nil {
        selectedConversationID = model.chat?.id ?? model.directory.conversations.first?.id
      }
      isInputFocused = true
    }
    .onKeyPress(.escape) {
      dismiss()
      return .handled
    }
  }

  private var headerRow: some View {
    let target = targetConversation
    let style: (symbol: String, gradient: [Color]) =
      target.map { conv in
        let custom = appearances.appearance(for: conv.botId, isAssistant: conv.kind == .assistant)
        return conv.kind == .session ? ("text.bubble", custom.gradient) : custom
      } ?? ("sparkles", BotColorPalette.all[0].gradient)

    return HStack(spacing: 10) {
      Menu {
        ForEach(model.directory.conversations, id: \.id) { conv in
          Button {
            selectedConversationID = conv.id
            statusNote = nil
          } label: {
            Text(verbatim: conv.title)
          }
        }
      } label: {
        HStack(spacing: 8) {
          ShellBotAvatar(symbol: style.symbol, gradient: style.gradient, size: 26)
          Text(verbatim: target?.title ?? String(localized: "Assistant"))
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
          Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(WarmShellColors.mutedText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(WarmShellColors.card, in: Capsule())
        .overlay(Capsule().stroke(WarmShellColors.cardBorder, lineWidth: 1))
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)

      if !model.isSelectedModelLocal {
        HStack(spacing: 4) {
          Image(systemName: model.composerSpeedMode == .fast ? "bolt.fill" : "brain")
            .font(.system(size: 10, weight: .semibold))
          Text(
            model.composerSpeedMode == .fast
              ? "Fast · \(model.effectiveThinkingEffort.composerDisplayName)"
              : model.effectiveThinkingEffort.composerDisplayName
          )
          .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(WarmShellColors.badgeText)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(WarmShellColors.badgeFill, in: Capsule())
      }

      Spacer()

      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(WarmShellColors.mutedText)
          .frame(width: 26, height: 26)
          .background(WarmShellColors.pill, in: Circle())
      }
      .buttonStyle(.plain)
      .help("Close Quick Entry (Esc)")
    }
  }

  private var promptInput: some View {
    TextField(
      "Ask anything…",
      text: $promptText,
      prompt: Text("Ask \(targetConversation?.title ?? "Memoshi") anything…")
        .foregroundStyle(WarmShellColors.mutedText),
      axis: .vertical
    )
    .textFieldStyle(.plain)
    .font(.system(size: 15))
    .foregroundStyle(WarmShellColors.primaryText)
    .lineLimit(2...6)
    .focused($isInputFocused)
    .padding(12)
    .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(WarmShellColors.cardBorder, lineWidth: 1)
    )
    .onSubmit {
      submit(openMainAfter: true)
    }
    .accessibilityIdentifier("quickEntry.input")
  }

  private var footerRow: some View {
    HStack(spacing: 10) {
      if let statusNote {
        Text(verbatim: statusNote)
          .font(.system(size: 11.5))
          .foregroundStyle(WarmShellColors.badgeText)
          .lineLimit(1)
      } else if !supervisor.hasAuthenticatedDaemon || model.connection != .connected {
        Text("Connecting to local runtime…")
          .font(.system(size: 11.5))
          .foregroundStyle(WarmShellColors.mutedText)
      } else if model.recovery != nil && targetConversation?.id == model.chat?.id {
        Text("Recovery needed — message will queue until resolved.")
          .font(.system(size: 11.5))
          .foregroundStyle(WarmShellColors.mutedText)
      } else if model.isWorking && targetConversation?.id == model.chat?.id {
        Text("Bot is busy — your message will queue as a follow-up.")
          .font(.system(size: 11.5))
          .foregroundStyle(WarmShellColors.mutedText)
      } else {
        Text(hotKeyManager.isEnabled ? "Shortcut: ⌥⇧Space" : "Global shortcut off")
          .font(.system(size: 11.5))
          .foregroundStyle(WarmShellColors.mutedText)
      }

      Spacer()

      Button("Send") {
        submit(openMainAfter: false)
      }
      .buttonStyle(.plain)
      .font(.system(size: 12.5, weight: .medium))
      .foregroundStyle(WarmShellColors.primaryText)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(WarmShellColors.pill, in: Capsule())
      .disabled(!canSubmit)

      Button {
        submit(openMainAfter: true)
      } label: {
        Label("Send & Open", systemImage: "arrow.up.circle.fill")
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 13)
          .padding(.vertical, 6)
          .background(
            canSubmit ? WarmShellColors.userBubble : WarmShellColors.mutedText.opacity(0.4),
            in: Capsule()
          )
      }
      .buttonStyle(.plain)
      .disabled(!canSubmit)
      .keyboardShortcut(.return, modifiers: .command)
    }
  }

  private func submit(openMainAfter: Bool) {
    let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let targetID = targetConversation?.id else { return }
    isDispatching = true
    statusNote = nil
    Task {
      let sent = await model.sendQuickPrompt(text, to: targetID)
      isDispatching = false
      if sent {
        promptText = ""
        if openMainAfter {
          navigation.showConversation()
          openWindow(id: "main")
          NSApplication.shared.activate(ignoringOtherApps: true)
        }
        dismiss()
      } else {
        statusNote =
          model.problem
          ?? String(localized: "Unable to send right now. Check model settings or wait for the active turn.")
      }
    }
  }
}
