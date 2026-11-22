import AVFoundation
import AppKit
import AppCore
import DesignSystem
import MemoshiProtocol
import MemoshiRuntime
import SwiftUI

/// Real text chat in the unified D144 warm shell.
struct LiveChatView: View {
  @Bindable var model: LiveChatModel
  let supervisor: DaemonSupervisor
  let selectedMockBot: ShellExampleBot?
  let bookmarks: WorkspaceBookmarksStore
  let appearances: BotAppearanceStore
  @Binding var isSidebarPresented: Bool
  @Binding var isSetupPresented: Bool
  @Binding var isFoldersPresented: Bool
  @Binding var isActivityPresented: Bool
  @Binding var rightSidebarMode: RightSidebarMode?
  var onEditBot: (Bot) -> Void
  var onOpenConnectors: (() -> Void)? = nil
  var focus: FocusState<LiveWorkspaceFocus?>.Binding
  @State private var focusOwner = UUID()
  @State private var liveMessageID: MessageID?
  @State private var isSearchVisible = false
  @State private var transcriptSearchQuery = ""
  @State private var handoffs: [BotHandoffRecord] = []
  @State private var pendingConnectCards: [ConnectorConnectCard] = []
  @AccessibilityFocusState private var sheetTrigger: ChatSheetTrigger?
  @Environment(\.designAnnouncer) private var announcer

  var body: some View {
    let isLiveBot = selectedMockBot == nil
    let senderName =
      if let mock = selectedMockBot {
        mock.name
      } else {
        model.directory.bots.first { $0.id == model.chat?.botId }?.name
          ?? model.chat?.title
          ?? String(localized: "Assistant")
      }
    VStack(spacing: 0) {
      ZStack(alignment: .topLeading) {
        ScrollViewReader { proxy in
          ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
              if isLiveBot, let recovery = model.recovery {
                ChatRecoveryNotice(model: model, recovery: recovery)
                  .padding(.top, 56)
              }
              ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                  if let mock = selectedMockBot {
                    ProoferReferenceTranscript(
                      bot: mock,
                      onOpenLinks: {
                        withAnimation(.easeInOut(duration: 0.15)) { rightSidebarMode = .links }
                      },
                      onOpenActivity: {
                        withAnimation(.easeInOut(duration: 0.15)) { rightSidebarMode = .activity }
                      }
                    )
                  } else {
                    if model.nextBefore != nil {
                      Button("Load Earlier Messages") { model.loadOlder() }
                        .disabled(model.isLoading)
                        .accessibilityIdentifier("chat.loadEarlier")
                    }
                    if model.messages.isEmpty && model.live == nil && model.recovery == nil
                      && model.queued.isEmpty
                      && !model.reviews.entries.contains(where: {
                        $0.card.conversationId.rawValue == model.chat?.id.rawValue
                      })
                    {
                      emptyState
                    }
                    if !model.activityEvents.isEmpty {
                      Button {
                        withAnimation(.easeInOut(duration: 0.15)) { rightSidebarMode = .activity }
                      } label: {
                        HStack(spacing: 6) {
                          Image(systemName: "brain")
                          Image(systemName: "curlybraces")
                          Text("Worked · \(model.activityEvents.count) steps")
                          Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(WarmShellColors.mutedText)
                      }
                      .buttonStyle(.plain)
                      .accessibilityIdentifier("chat.workSummary")
                    }
                    LiveChatTranscript(
                      model: model,
                      senderName: senderName,
                      searchQuery: isSearchVisible ? transcriptSearchQuery : "",
                      bookmarks: bookmarks,
                      onOpenLinks: {
                        withAnimation(.easeInOut(duration: 0.15)) { rightSidebarMode = .links }
                      },
                      focus: focus)
                    if !handoffs.isEmpty {
                      BotHandoffCardsSection(
                        handoffs: handoffs,
                        activeConversationID: model.chat?.id.rawValue,
                        onOpenConversation: { rawID in
                          if let target = try? ConversationID(rawID) {
                            Task { await model.selectConversation(target) }
                          }
                        }
                      )
                    }
                    if !pendingConnectCards.isEmpty {
                      ChatConnectCardsSection(
                        cards: pendingConnectCards,
                        onOpenConnectors: onOpenConnectors
                      )
                    }
                    if !model.queued.isEmpty { QueuedChatInputsView(model: model) }
                    if let message = model.live?.message,
                      !model.messages.contains(where: { $0.id == message.id })
                    {
                      LiveMessageBubble(
                        message: message, isStreaming: model.task?.status != .waiting,
                        senderName: senderName,
                        bookmarks: bookmarks,
                        conversationID: model.chat?.id.rawValue)
                    }
                    if model.recovery == nil && model.task?.status == .waiting {
                      Label("Waiting for a decision", systemImage: "hand.raised")
                        .font(.callout)
                        .foregroundStyle(WarmShellColors.mutedText)
                        .accessibilityIdentifier("chat.waitingForApproval")
                    } else if model.isWorking && model.live == nil {
                      HStack(spacing: DS.Space.s3) {
                        ProgressView().controlSize(.small)
                        Text("Working…").font(.callout).foregroundStyle(WarmShellColors.mutedText)
                      }
                      .accessibilityIdentifier("chat.working")
                    }
                  }
                  Color.clear.frame(height: DS.Layout.Conversation.scrollAnchorHeight).id("chat.bottom")
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.top, 72)
                .padding(.bottom, 128)
              }
              .defaultScrollAnchor(.bottom)
              .id(selectedMockBot?.id ?? model.chat?.id.rawValue ?? "default")
              .onChange(of: model.messages.last?.id) { _, _ in
                proxy.scrollTo("chat.bottom", anchor: .bottom)
              }
            }

            // Floating Liquid Glass composer + scroll-to-bottom button over the scrolling transcript
            VStack(spacing: 8) {
              HStack {
                Spacer()
                Button {
                  withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("chat.bottom", anchor: .bottom)
                  }
                } label: {
                  Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WarmShellColors.badgeText)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .help("Scroll to Bottom")
              }
              .padding(.trailing, 18)

              if isLiveBot, let problem {
                Text(verbatim: problem)
                  .font(.callout)
                  .foregroundStyle(WarmShellColors.mutedText)
                  .frame(maxWidth: 720, alignment: .leading)
                  .padding(.horizontal, 28)
                  .accessibilityIdentifier("chat.error")
              }

              LiveChatComposer(
                model: model,
                setup: model.providerSetup,
                isLiveBot: isLiveBot,
                exampleBotName: senderName,
                exampleModelName: selectedMockBot?.modelLabel ?? "Claude Opus 5.5",
                onOpenFolders: { isFoldersPresented = true },
                onOpenModelSettings: { isSetupPresented = true },
                focus: focus
              )
              .frame(maxWidth: 720)
              .padding(.horizontal, 28)
              .padding(.bottom, 16)
              .frame(maxWidth: .infinity)
            }
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .center) {
            floatingBotHeader(senderName: senderName, isLiveBot: isLiveBot)
            Spacer()
            GlassEffectContainer(spacing: 8) {
              HStack(spacing: 6) {
                if isLiveBot {
                  Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                      isSearchVisible.toggle()
                      if !isSearchVisible { transcriptSearchQuery = "" }
                    }
                  } label: {
                    Image(systemName: "magnifyingglass")
                      .font(.system(size: 13, weight: .medium))
                      .foregroundStyle(
                        isSearchVisible ? WarmShellColors.badgeText : WarmShellColors.primaryText)
                      .frame(width: 34, height: 34)
                      .contentShape(Circle())
                  }
                  .buttonStyle(.plain)
                  .glassEffect(.regular.interactive(), in: Circle())
                  .help("Find in Conversation")
                  .accessibilityIdentifier("chat.findButton")
                }
                if rightSidebarMode == nil {
                  Button {
                    withAnimation(.easeInOut(duration: 0.15)) { rightSidebarMode = .activity }
                  } label: {
                    Image(systemName: "sidebar.right")
                      .font(.system(size: 13.5, weight: .regular))
                      .foregroundStyle(WarmShellColors.primaryText)
                      .frame(width: 34, height: 34)
                      .contentShape(Circle())
                  }
                  .buttonStyle(.plain)
                  .glassEffect(.regular.interactive(), in: Circle())
                  .help("Show Right Sidebar")
                }
              }
            }
          }
          if isLiveBot && isSearchVisible {
            transcriptSearchBar
          }
        }
        .padding(.top, 14)
        .padding(.leading, isSidebarPresented ? 18 : 82)
        .padding(.trailing, 16)
      }
    }
    .background(WarmShellColors.canvas)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("chat.realConversation")
    .task {
      await model.show(owner: focusOwner)
      reloadConversationCards()
    }
    .onChange(of: model.chat?.id) { _, _ in reloadConversationCards() }
    .onChange(of: model.messages.count) { _, _ in reloadConversationCards() }
    .onChange(of: model.activityEvents.count) { _, _ in reloadConversationCards() }
    .onDisappear { Task { await model.hide(owner: focusOwner) } }
    .onChange(of: problem) { _, problem in
      if let problem { announcer.announce(problem) }
    }
    .onChange(of: model.live?.message?.id, initial: true) { _, id in
      if let id { liveMessageID = id }
    }
    .onChange(of: model.messages.last?.id) { _, _ in announceFinishedMessage(senderName) }
    .sheet(isPresented: $isSetupPresented, onDismiss: restore(.modelSettings)) {
      ModelSetupView(model: model, supervisor: supervisor)
    }
    .sheet(isPresented: $isFoldersPresented, onDismiss: restore(.folders)) {
      FolderGrantView(folders: model.folders)
    }
    .sheet(isPresented: $isActivityPresented, onDismiss: restore(.activity)) {
      LiveActivitySheet(
        events: model.activityEvents,
        baseline: model.activityBaseline, omittedCount: model.activityOmittedCount)
    }
  }

  private var problem: String? {
    model.problem ?? model.reviews.problem ?? model.providerSetup.problem
      ?? model.task?.error?.message
  }

  /// A streamed reply is announced once, when it settles into the transcript (02 §13.2).
  private func announceFinishedMessage(_ senderName: String) {
    guard let liveMessageID, let message = model.messages.last, message.id == liveMessageID,
      message.role != .user
    else { return }
    self.liveMessageID = nil
    let text = LiveChatModel.text(message)
    let state = LiveMessageBubble.state(of: message, isStreaming: false)
    let spoken =
      ResumedReply.accessibilityValue(state: state?.accessibilityValue, of: message).map {
        String(localized: "\(senderName): \(text). \($0)")
      } ?? String(localized: "\(senderName): \(text)")
    announcer.announceOnce(spoken, key: "message." + message.id.rawValue)
  }

  /// The dismissal action that returns VoiceOver focus to the sheet's trigger.
  private func restore(_ trigger: ChatSheetTrigger) -> () -> Void {
    { Task { @MainActor in sheetTrigger = trigger } }
  }

  private var transcriptSearchBar: some View {
    let trimmed = transcriptSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    let matchCount =
      trimmed.isEmpty
      ? 0
      : model.messages.filter {
        LiveChatModel.text($0).localizedCaseInsensitiveContains(trimmed)
      }.count
    return HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12))
        .foregroundStyle(WarmShellColors.mutedText)
      TextField(
        "Find in conversation…", text: $transcriptSearchQuery,
        prompt: Text("Find in conversation…").foregroundStyle(WarmShellColors.mutedText)
      )
      .textFieldStyle(.plain)
      .font(.system(size: 12.5))
      .foregroundStyle(WarmShellColors.primaryText)
      .accessibilityIdentifier("chat.findField")
      if !trimmed.isEmpty {
        Text("\(matchCount) match\(matchCount == 1 ? "" : "es")")
          .font(.system(size: 11))
          .foregroundStyle(WarmShellColors.mutedText)
      }
      Button {
        withAnimation(.easeInOut(duration: 0.15)) {
          transcriptSearchQuery = ""
          isSearchVisible = false
        }
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 13))
          .foregroundStyle(WarmShellColors.mutedText)
      }
      .buttonStyle(.plain)
      .help("Close Find")
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: 320, minHeight: 32, maxHeight: 32)
    .background(WarmShellColors.card, in: Capsule())
    .overlay(Capsule().stroke(WarmShellColors.cardBorder, lineWidth: 1))
    .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
  }

  private func floatingBotHeader(senderName: String, isLiveBot: Bool) -> some View {
    let selected = model.providerSetup.selectedModel
    let modelLabel =
      isLiveBot
      ? (model.botModel?.ref.rawValue
        ?? (selected.isEmpty ? String(localized: "Select a model") : selected))
      : (selectedMockBot?.modelLabel ?? "Claude Opus 5.5")
    let liveStyle: (symbol: String, gradient: [Color])? =
      model.chat.map { chat in
        let custom = appearances.appearance(for: chat.botId, isAssistant: chat.kind == .assistant)
        if chat.kind == .session {
          return ("text.bubble", custom.gradient)
        }
        return custom
      }
    let avatarSymbol = selectedMockBot?.symbol ?? liveStyle?.symbol ?? "sparkles"
    let avatarGradient =
      selectedMockBot?.gradient
      ?? liveStyle?.gradient
      ?? [Color(red: 0.16, green: 0.68, blue: 0.56), Color(red: 0.10, green: 0.44, blue: 0.48)]
    let isConnected = model.connection == .connected
    return GlassEffectContainer(spacing: 8) {
      HStack(spacing: 8) {
        if !isSidebarPresented {
          Button {
            withAnimation(.easeInOut(duration: 0.15)) { isSidebarPresented = true }
          } label: {
            Image(systemName: "sidebar.left")
              .font(.system(size: 14, weight: .regular))
              .foregroundStyle(WarmShellColors.primaryText)
              .frame(width: 34, height: 34)
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .glassEffect(.regular.interactive(), in: Circle())
          .help("Show Sidebar")
        }
        Menu {
          if let bot = model.directory.bots.first(where: { $0.id == model.chat?.botId }) {
            Button("Edit Bot…", systemImage: "person.badge.gearshape") {
              onEditBot(bot)
            }
          }
          if isLiveBot {
            Button(
              isSearchVisible ? "Hide Find in Chat" : "Find in Chat…",
              systemImage: "magnifyingglass"
            ) {
              withAnimation(.easeInOut(duration: 0.15)) {
                isSearchVisible.toggle()
                if !isSearchVisible { transcriptSearchQuery = "" }
              }
            }
          }
          Button("Activity…", systemImage: "list.bullet.rectangle") {
            isActivityPresented = true
          }
          .accessibilityIdentifier("chat.activity")
          Button("Folders…", systemImage: "folder") {
            isFoldersPresented = true
          }
          .accessibilityIdentifier("chat.folderSettings")
          Button("Model Settings…", systemImage: "slider.horizontal.3") {
            isSetupPresented = true
          }
          .accessibilityIdentifier("chat.modelSettings")
        } label: {
          HStack(spacing: 10) {
            ShellBotAvatar(
              symbol: avatarSymbol,
              gradient: avatarGradient,
              size: 32)
            VStack(alignment: .leading, spacing: 1) {
              HStack(spacing: 6) {
                Text(verbatim: senderName)
                  .font(.system(size: 13.5, weight: .semibold))
                  .foregroundStyle(WarmShellColors.primaryText)
                if isLiveBot {
                  HStack(spacing: 4) {
                    Circle()
                      .fill(isConnected ? Color.green : WarmShellColors.badgeText)
                      .frame(width: 6, height: 6)
                    Text(isConnected ? "Live" : "Connecting")
                      .font(.system(size: 10.5, weight: .semibold))
                  }
                  .foregroundStyle(
                    isConnected ? Color(red: 0.18, green: 0.68, blue: 0.36) : WarmShellColors.badgeText)
                  .padding(.horizontal, 7)
                  .padding(.vertical, 2)
                  .background(
                    isConnected
                      ? Color.green.opacity(0.16) : WarmShellColors.badgeFill,
                    in: Capsule())
                } else {
                  HStack(spacing: 3) {
                    Image(systemName: "lock.open.fill")
                      .font(.system(size: 9, weight: .semibold))
                    Text("Bypass")
                      .font(.system(size: 10.5, weight: .semibold))
                  }
                  .foregroundStyle(WarmShellColors.badgeText)
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(WarmShellColors.badgeFill, in: Capsule())
                }
              }
              Text(verbatim: modelLabel)
                .font(.system(size: 11.5))
                .foregroundStyle(WarmShellColors.mutedText)
                .lineLimit(1)
            }
            Image(systemName: "chevron.down")
              .font(.system(size: 10.5, weight: .medium))
              .foregroundStyle(WarmShellColors.mutedText)
              .padding(.leading, 6)
          }
          .padding(.leading, 8)
          .padding(.trailing, 14)
          .padding(.vertical, 6)
          .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular.interactive(), in: Capsule())
      }
    }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      if let title = model.chat?.title {
        Label(title, systemImage: "bubble.left.and.bubble.right")
      } else {
        Label("Your Assistant", systemImage: "bubble.left.and.bubble.right")
      }
    } description: {
      Group {
        if supervisor.problem == .signingRequired {
          Text(
            "A matching Apple-signed app and helper are required. This view does not bypass peer authentication."
          )
        } else if model.connection != .connected {
          Text(
            "Connecting to the local text-chat runtime. Design examples are separate from this conversation."
          )
        } else if model.providerSetup.models.isEmpty {
          Text(
            "Sign in with ChatGPT or add a Keychain-backed API provider in Model Settings. A local server is optional. PiDurable stores conversation history on this Mac."
          )
        } else {
          Text(
            "Send your first message. Conversations stay durable on this Mac with policy-reviewed Apple, search, connector, and bot-handoff tools."
          )
        }
      }
      .foregroundStyle(DesignControlRoles.secondaryText)
    } actions: {
      if supervisor.hasAuthenticatedDaemon {
        Button("Model Settings") { isSetupPresented = true }
          .accessibilityIdentifier("chat.setup")
      } else {
        Button("Retry Connection") { supervisor.retryConnection() }
          .disabled(supervisor.isBusy)
      }
    }
    .frame(minHeight: DS.Layout.Conversation.emptyStateMinHeight)
  }

  private func reloadConversationCards() {
    guard selectedMockBot == nil, let chatID = model.chat?.id.rawValue else {
      handoffs = []
      pendingConnectCards = []
      return
    }
    let root = supervisor.activeDataDirectory
    handoffs = BotHandoffStore(dataDirectory: root).load(forConversation: chatID)
    pendingConnectCards = ConnectorCatalogStore(dataDirectory: root).loadConnectCards().filter {
      $0.status == .pending
        && ($0.requestedByConversationID == nil || $0.requestedByConversationID == chatID)
    }
  }

}

private struct LiveChatTranscript: View {
  let model: LiveChatModel
  let senderName: String
  let searchQuery: String
  let bookmarks: WorkspaceBookmarksStore
  var onOpenLinks: () -> Void
  var focus: FocusState<LiveWorkspaceFocus?>.Binding

  var body: some View {
    ForEach(filteredItems) { item in
      switch item {
      case .message(let message, let showsEndState):
        LiveMessageBubble(
          message: message, isStreaming: false, showsEndState: showsEndState,
          senderName: senderName,
          bookmarks: bookmarks,
          conversationID: model.chat?.id.rawValue,
          onOpenLinks: onOpenLinks,
          onRetry: message.role == .user ? nil : { retryPreviousUserMessage(before: message.id) },
          onEdit: message.role == .user
            ? {
              let text = LiveChatModel.text(message).trimmingCharacters(in: .whitespacesAndNewlines)
              guard !text.isEmpty else { return }
              model.draft = text
              focus.wrappedValue = .composer
            } : nil)
      case .approval(let group):
        LiveApprovalGroupView(group: group, model: model.reviews, focus: focus)
      case .turnState(let message):
        LiveTurnStateMark(message: message, senderName: senderName)
      }
    }
  }

  private func retryPreviousUserMessage(before messageID: MessageID) {
    guard !model.isWorking,
      let idx = model.messages.firstIndex(where: { $0.id == messageID }),
      let prevUser = model.messages[..<idx].last(where: { $0.role == .user })
    else { return }
    let prompt = LiveChatModel.text(prevUser).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else { return }
    model.retryPrompt(prompt)
  }

  private var filteredItems: [TranscriptItem] {
    let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    let all = TranscriptLayout.items(
      messages: model.messages,
      groups: model.reviews.timelineGroups.filter {
        $0.id.conversationId.rawValue == model.chat?.id.rawValue
      })
    guard !trimmed.isEmpty else { return all }
    return all.filter { item in
      switch item {
      case .message(let message, _):
        return LiveChatModel.text(message).localizedCaseInsensitiveContains(trimmed)
      case .approval, .turnState:
        return false
      }
    }
  }
}

private final class SpeechSynthesizerBridge: NSObject, AVSpeechSynthesizerDelegate,
  @unchecked Sendable
{
  let synthesizer = AVSpeechSynthesizer()
  var onFinish: (@MainActor () -> Void)?

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)
  {
    let callback = onFinish
    Task { @MainActor in callback?() }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance)
  {
    let callback = onFinish
    Task { @MainActor in callback?() }
  }
}

/// Shared speech reader so starting narration on one message cleanly stops any previous utterance.
@MainActor
@Observable
private final class SharedSpeechReader {
  static let shared = SharedSpeechReader()
  private(set) var speakingMessageID: MessageID?
  @ObservationIgnored private let bridge = SpeechSynthesizerBridge()

  private init() {
    bridge.onFinish = { [weak self] in
      self?.speakingMessageID = nil
    }
  }

  func toggle(messageID: MessageID, text: String) {
    if speakingMessageID == messageID {
      bridge.synthesizer.stopSpeaking(at: .immediate)
      speakingMessageID = nil
      return
    }
    if bridge.synthesizer.isSpeaking {
      bridge.synthesizer.stopSpeaking(at: .immediate)
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    speakingMessageID = messageID
    bridge.synthesizer.speak(AVSpeechUtterance(string: trimmed))
  }
}

private struct LiveMessageBubble: View {
  let message: ChatMessage
  let isStreaming: Bool
  /// Whether the reply's end state is inside the bubble; a turn with Cards shows it after them.
  var showsEndState = true
  let senderName: String
  let bookmarks: WorkspaceBookmarksStore
  let conversationID: String?
  var onOpenLinks: (() -> Void)? = nil
  var onRetry: (() -> Void)? = nil
  var onEdit: (() -> Void)? = nil
  @State private var copied = false

  /// The unfinished or interrupted state, if any; finished replies have none.
  static func state(of message: ChatMessage, isStreaming: Bool) -> DesignMessageState? {
    if isStreaming { return .responding }
    switch message.stopReason {
    case .aborted: return .stopped
    case .error: return .failed
    default: return nil
    }
  }

  var body: some View {
    let isUser = message.role == .user
    let text = LiveChatModel.text(message)
    let state = showsEndState ? Self.state(of: message, isStreaming: isStreaming) : nil
    let value =
      showsEndState
      ? ResumedReply.accessibilityValue(state: state?.accessibilityValue, of: message) : nil
    let isBookmarked = bookmarks.isMessageBookmarked(message.id.rawValue)
    let isReading = SharedSpeechReader.shared.speakingMessageID == message.id
    let messageLinks =
      isStreaming ? [] : ExtractedConversationLink.extract(from: [message], senderName: senderName)
    HStack {
      if isUser { Spacer(minLength: DS.Space.s9) }
      VStack(alignment: isUser ? .trailing : .leading, spacing: DS.Space.s1) {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
          // A reply stopped before it had text, such as one whose tool call waited for a Card,
          // shows only its state.
          if !text.isEmpty || state == nil {
            MarkdownMessageView(text: text, isUser: isUser)
          }
          if showsEndState { LiveEndStateCaptions(message: message, state: state) }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
          isUser ? WarmShellColors.userBubble : WarmShellColors.card,
          in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: isUser ? .clear : .black.opacity(0.025), radius: 4, y: 1)

        if !isStreaming, !messageLinks.isEmpty {
          HStack(spacing: 6) {
            ForEach(messageLinks.prefix(3)) { link in
              Button {
                NSWorkspace.shared.open(link.url)
              } label: {
                HStack(spacing: 5) {
                  Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.16, green: 0.42, blue: 0.72))
                  Text(link.host)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(WarmShellColors.primaryText)
                    .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(WarmShellColors.card, in: Capsule())
                .overlay(Capsule().stroke(WarmShellColors.cardBorder, lineWidth: 1))
              }
              .buttonStyle(.plain)
              .help(link.url.absoluteString)
            }
            if let onOpenLinks, messageLinks.count > 1 {
              Button(action: onOpenLinks) {
                HStack(spacing: 4) {
                  Text(messageLinks.count > 3 ? "+\(messageLinks.count - 3) more" : "All Links")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(WarmShellColors.mutedText)
                  Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WarmShellColors.mutedText)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(WarmShellColors.pill, in: Capsule())
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.top, 2)
        }

        if !isStreaming, message.createdAt > 0 {
          HStack(spacing: 12) {
            Text(
              Date(timeIntervalSince1970: TimeInterval(message.createdAt) / 1000.0),
              format: .dateTime.hour().minute()
            )
            .font(.system(size: 11.5))
            .foregroundStyle(WarmShellColors.mutedText)

            if !text.isEmpty {
              Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                Task {
                  try? await Task.sleep(for: .seconds(1.4))
                  copied = false
                }
              } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                  .font(.system(size: 11, weight: .medium))
                  .foregroundStyle(copied ? WarmShellColors.badgeText : WarmShellColors.mutedText)
              }
              .buttonStyle(.plain)
              .help(copied ? "Copied" : "Copy message")

              Button {
                bookmarks.toggleMessage(
                  messageID: message.id.rawValue,
                  text: text,
                  botName: isUser ? String(localized: "You") : senderName,
                  conversationID: conversationID)
              } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                  .font(.system(size: 11, weight: .medium))
                  .foregroundStyle(
                    isBookmarked ? WarmShellColors.badgeText : WarmShellColors.mutedText)
              }
              .buttonStyle(.plain)
              .help(isBookmarked ? "Remove bookmark" : "Bookmark message")

              if isUser, let onEdit {
                Button(action: onEdit) {
                  Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WarmShellColors.mutedText)
                }
                .buttonStyle(.plain)
                .help("Edit and resend in composer")
                .accessibilityIdentifier("chat.message.edit.\(message.id.rawValue)")
              }
            }

            if !isUser {
              if let onRetry {
                Button(action: onRetry) {
                  Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(WarmShellColors.mutedText)
                }
                .buttonStyle(.plain)
                .help("Regenerate reply")
              }
              Button {
                SharedSpeechReader.shared.toggle(messageID: message.id, text: text)
              } label: {
                HStack(spacing: 4) {
                  Image(systemName: isReading ? "stop.circle" : "book")
                    .font(.system(size: 11.5, weight: .medium))
                  Text(isReading ? "Stop" : "Read")
                    .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(WarmShellColors.badgeText)
              }
              .buttonStyle(.plain)
              .help(isReading ? "Stop reading aloud" : "Read reply aloud")
            }
          }
          .padding(.horizontal, 4)
          .padding(.top, 2)
        }
      }
      if !isUser { Spacer(minLength: DS.Space.s8) }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isStaticText)
    .accessibilityLabel(isUser ? "You: \(text)" : "\(senderName): \(text)")
    // The sender label stays on the combined element; the stream state and the restart note
    // are its value (A1).
    .accessibilityValue(Text(verbatim: value ?? ""))
    .accessibilityIdentifier("chat.message.\(message.id.rawValue)")
  }
}

/// A reply's stream state and restart note, each on its own line.
private struct LiveEndStateCaptions: View {
  let message: ChatMessage
  let state: DesignMessageState?

  var body: some View {
    if let state {
      Text(state.caption).font(DS.Typography.subheadline).foregroundStyle(
        DS.Colors.Text.secondary)
    }
    if ResumedReply.isMarked(message) {
      Text(ResumedReply.caption).font(DS.Typography.subheadline).foregroundStyle(
        DS.Colors.Text.secondary)
    }
  }
}

/// A reply's end state after its turn's Cards (D139), outside any bubble and aligned with its
/// text. VoiceOver reads the sender, then the state and restart note as the value, once.
struct LiveTurnStateMark: View {
  let message: ChatMessage
  let senderName: String

  static func accessibilityIdentifier(for messageID: MessageID) -> String {
    "chat.turnState.\(messageID.rawValue)"
  }

  var body: some View {
    let state = LiveMessageBubble.state(of: message, isStreaming: false)
    let value = ResumedReply.accessibilityValue(state: state?.accessibilityValue, of: message)
    VStack(alignment: .leading, spacing: DS.Space.s2) {
      LiveEndStateCaptions(message: message, state: state)
    }
    .padding(.horizontal, DS.Layout.Message.bubblePaddingH)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isStaticText)
    .accessibilityLabel(Text(verbatim: senderName))
    .accessibilityValue(Text(verbatim: value ?? ""))
    .accessibilityIdentifier(Self.accessibilityIdentifier(for: message.id))
  }
}

/// The chat control that opened a sheet; VoiceOver focus returns to it on dismissal.
enum ChatSheetTrigger: Hashable {
  case activity, folders, modelSettings
}

/// D144 visual mockup of the Proofer conversation matching `HXlzoVyXYAAaqV5.png`, shown when the
/// live daemon has no messages yet so layout, typography and spacing can be verified side-by-side.
private struct ProoferReferenceTranscript: View {
  let bot: ShellExampleBot
  var onOpenLinks: () -> Void = {}
  var onOpenActivity: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Centered date/time header
      HStack {
        Spacer()
        Text("Today 4:46 PM")
          .font(.system(size: 11.5))
          .foregroundStyle(WarmShellColors.mutedText)
        Spacer()
      }

      // 1. Inter-bot handoff pill centered at top
      HStack {
        Spacer()
        HStack(spacing: 10) {
          ShellGroupAvatar(members: ShellExampleBot.sweMembers, size: 28)
          VStack(alignment: .leading, spacing: 2) {
            Text("Messaged Builder")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(WarmShellColors.mutedText)
            Text(
              "Proofer here: my proof of the release notes draft. I only changed grammar, and only where I'm sure. 1…"
            )
            .font(.system(size: 12))
            .foregroundStyle(WarmShellColors.primaryText)
            .lineLimit(2)
          }
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(WarmShellColors.mutedText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 440)
        .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
          RoundedRectangle(cornerRadius: 16).stroke(WarmShellColors.cardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
        Spacer()
      }

      // 2. First Assistant Card with inner Swift diff block
      VStack(alignment: .leading, spacing: 6) {
        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Swift")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WarmShellColors.mutedText)
              Spacer()
              HStack(spacing: 10) {
                Image(systemName: "arrow.turn.down.left")
                Image(systemName: "doc.on.doc")
              }
              .font(.system(size: 11))
              .foregroundStyle(WarmShellColors.mutedText)
            }
            VStack(alignment: .leading, spacing: 1.5) {
              Text("draft.md:")
                .foregroundStyle(WarmShellColors.primaryText)
              diffLine(
                num: "3",
                before: "\"[wrote about how I initially set up](/p/41e35e3fe8d881dd…)\"",
                after: nil,
                note: "link to the published article")
              diffLine(num: "3", before: "\"discovering bigs\"", after: "\"discovering bugs\"", note: "(typo)")
              diffLine(
                num: "5",
                before: "\"Not only would have that costed me\"",
                after: "\"Not only would that have cost me\"",
                note: "(word order)")
              diffLine(
                num: "9",
                before: "\"\\$1000/month\"",
                after: "\"\\$1,000/month\"",
                note: "(inconsistent with \\$75,000)")
              diffLine(
                num: "13",
                before: "\"YouTube premium\"",
                after: "\"YouTube Premium\"",
                note: "(product name is capitalized)")
              diffLine(
                num: "17",
                before: "\"6.1 Sol\"",
                after: "\"Sol 6.1\"",
                note: "(inconsistent with \"Sol 6.1\" on line 11)")
              diffLine(
                num: "23",
                before: "\"(i.e. a design change)\"",
                after: "\"(e.g., a design change)\"",
                note: "(introduces examples)")
            }
            .font(.system(size: 11, design: .monospaced))
          }
          .padding(12)
          .background(WarmShellColors.codeBlockBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

          Text(
            "Builder's draft proof for Weekly 538 needed no action from me. It had already made my three grammar fixes this afternoon, along with a few of its own."
          )
          .font(.system(size: 13))
          .lineSpacing(2)
          .foregroundStyle(WarmShellColors.primaryText)
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.025), radius: 4, y: 1)

        // Inline file-change confirmation / undo rows
        VStack(alignment: .leading, spacing: 4) {
          confirmationRow(file: "draft_checked.md", oldSize: "2 KB", newSize: "10 KB")
          confirmationRow(file: "draft_original.md", oldSize: "2 KB", newSize: "10 KB")
          Text("4:46 PM")
            .font(.system(size: 11))
            .foregroundStyle(WarmShellColors.mutedText)
            .padding(.top, 2)
        }
        .padding(.leading, 4)
      }

      // 3. Warm Amber User Bubble + right-aligned link pill
      VStack(alignment: .trailing, spacing: 8) {
        HStack {
          Spacer(minLength: 80)
          Text(
            verbatim:
              "replace that broken link with https://memoshi.app/docs/building-native-apps-with-agents-and-simulators/\n\nand fix the rest"
          )
          .font(.system(size: 14))
          .lineSpacing(3)
          .foregroundStyle(WarmShellColors.onUserBubble)
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
          .background(WarmShellColors.userBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }

        HStack {
          Spacer()
          Button(action: onOpenLinks) {
            HStack(spacing: 8) {
              Image(systemName: "doc.text.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color(red: 0.85, green: 0.24, blue: 0.22), in: Circle())
              Text("Building Native Apps with Multiple Agents, Simulators…")
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(WarmShellColors.primaryText)
                .lineLimit(1)
              Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WarmShellColors.mutedText)
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 7)
            .background(WarmShellColors.composerBg, in: Capsule())
            .overlay(Capsule().stroke(WarmShellColors.cardBorder.opacity(0.8), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.025), radius: 3, y: 1)
          }
          .buttonStyle(.plain)
        }
      }

      // 4. Worked 20s · 1 step > disclosure + Second Assistant Card
      VStack(alignment: .leading, spacing: 8) {
        Button(action: onOpenActivity) {
          HStack(spacing: 6) {
            Image(systemName: "brain")
            Image(systemName: "curlybraces")
            Text("Worked 20s · 1 step")
            Image(systemName: "chevron.right")
              .font(.system(size: 10, weight: .semibold))
          }
          .font(.system(size: 12))
          .foregroundStyle(WarmShellColors.mutedText)
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)

        VStack(alignment: .leading, spacing: 8) {
          Text("I fixed the draft and re-read the page to confirm every change is there:")
            .font(.system(size: 13))
            .lineSpacing(2)
            .foregroundStyle(WarmShellColors.primaryText)

          VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
              Text("•").foregroundStyle(WarmShellColors.mutedText)
              (Text("The link: ").fontWeight(.semibold)
                + Text("\"wrote about how I initially set up\" now points to the published story."))
            }
            HStack(alignment: .top, spacing: 8) {
              Text("•").foregroundStyle(WarmShellColors.mutedText)
              (Text("The other fixes: ").fontWeight(.semibold)
                + Text(
                  "\"bugs,\" \"would that have cost me,\" \"$1,000/month,\" \"YouTube Premium,\" \"Sol 6.1\" and \"(e.g., …).\""
                ))
            }
          }
          .font(.system(size: 13))
          .lineSpacing(2)
          .foregroundStyle(WarmShellColors.primaryText)
          .padding(.leading, 8)

          Text(
            "Two links are still missing, because I don't have their addresses: \"here\" on line 9, for the calculations, and \"this video\" on line 19. Send me those two links and I'll add them."
          )
          .font(.system(size: 13))
          .lineSpacing(2)
          .foregroundStyle(WarmShellColors.primaryText)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.025), radius: 4, y: 1)

        // Links pill + timestamp + retry + Read (matching close-up reference)
        VStack(alignment: .leading, spacing: 8) {
          Button(action: onOpenLinks) {
            HStack(spacing: 7) {
              Image(systemName: "globe")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.16, green: 0.42, blue: 0.72))
              Text("9 Links")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(WarmShellColors.primaryText)
              Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WarmShellColors.mutedText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(WarmShellColors.card, in: Capsule())
            .overlay(Capsule().stroke(WarmShellColors.cardBorder, lineWidth: 1))
          }
          .buttonStyle(.plain)

          HStack(spacing: 14) {
            Text("5:01 PM")
            Image(systemName: "arrow.clockwise")
            HStack(spacing: 4) {
              Image(systemName: "book")
              Text("Read")
                .fontWeight(.medium)
            }
            .foregroundStyle(WarmShellColors.badgeText)
          }
          .font(.system(size: 11.5))
          .foregroundStyle(WarmShellColors.mutedText)
        }
        .padding(.leading, 4)
      }
    }
  }

  private func diffLine(num: String, before: String, after: String?, note: String) -> some View {
    HStack(spacing: 4) {
      Text("-")
        .foregroundStyle(WarmShellColors.primaryText)
      Text("Line")
        .foregroundStyle(Color(red: 0.18, green: 0.44, blue: 0.42))
      Text("\(num):")
        .foregroundStyle(Color(red: 0.14, green: 0.36, blue: 0.78))
      Text(before)
        .foregroundStyle(Color(red: 0.72, green: 0.20, blue: 0.14))
      Text("→")
        .foregroundStyle(WarmShellColors.primaryText)
      if let after {
        Text(after)
          .foregroundStyle(Color(red: 0.72, green: 0.20, blue: 0.14))
      }
      Text(note)
        .foregroundStyle(WarmShellColors.primaryText)
    }
    .lineLimit(1)
  }

  private func confirmationRow(file: String, oldSize: String, newSize: String) -> some View {
    let vividOrange = Color(red: 0.92, green: 0.47, blue: 0.10)
    let undoBrown = Color(red: 0.50, green: 0.31, blue: 0.11)
    return HStack(spacing: 4) {
      Image(systemName: "questionmark.circle")
        .font(.system(size: 11))
        .foregroundStyle(vividOrange)
      Text("Not Confirmed: \(file) · Size")
        .foregroundStyle(vividOrange)
      Text(oldSize)
        .strikethrough()
        .foregroundStyle(WarmShellColors.mutedText)
      Text("→")
        .foregroundStyle(vividOrange)
      Text(newSize)
        .fontWeight(.semibold)
        .foregroundStyle(vividOrange)
      Text("Undo")
        .foregroundStyle(undoBrown)
        .padding(.leading, 4)
    }
    .font(.system(size: 11.5))
  }
}

/// Live `Messaged <Bot>` / `Handoff from <Bot>` cards rendered inline in the transcript (`D109`).
private struct BotHandoffCardsSection: View {
  let handoffs: [BotHandoffRecord]
  let activeConversationID: String?
  var onOpenConversation: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(handoffs) { record in
        let isOutgoing = record.sourceConversationID == activeConversationID
        let peerName = isOutgoing ? record.targetBotName : record.sourceBotName
        let peerConversationID =
          isOutgoing ? record.targetConversationID : record.sourceConversationID
        HStack(alignment: .top, spacing: 10) {
          ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(WarmShellColors.badgeFill)
            Image(systemName: isOutgoing ? "arrowshape.turn.up.right.fill" : "arrow.down.left")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(WarmShellColors.badgeText)
          }
          .frame(width: 28, height: 28)

          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
              Text(isOutgoing ? "Messaged \(peerName)" : "Handoff from \(peerName)")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(WarmShellColors.primaryText)
              Text("Hop \(record.hopDepth)/\(BotHandoffStore.maxHopDepth)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(WarmShellColors.mutedText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(WarmShellColors.canvas, in: Capsule())
            }
            Text(record.summary)
              .font(.system(size: 12))
              .foregroundStyle(WarmShellColors.mutedText)
              .lineLimit(2)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          Button {
            onOpenConversation(peerConversationID)
          } label: {
            Text("Open Chat")
              .font(.system(size: 11.5, weight: .semibold))
              .foregroundStyle(WarmShellColors.badgeText)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(WarmShellColors.badgeFill, in: Capsule())
          }
          .buttonStyle(.plain)
        }
        .padding(11)
        .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(WarmShellColors.cardBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("chat.handoffCard.\(record.id)")
      }
    }
  }
}

/// Inline one-tap Connect Cards requested by a bot via `connector_request_connect` (`D112`, `CON-14`).
private struct ChatConnectCardsSection: View {
  let cards: [ConnectorConnectCard]
  var onOpenConnectors: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(cards) { card in
        let connector = ConnectorCatalogStore.connector(id: card.connectorID)
        HStack(alignment: .center, spacing: 10) {
          ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(WarmShellColors.badgeFill)
            Image(systemName: connector?.symbol ?? "puzzlepiece.extension")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(WarmShellColors.badgeText)
          }
          .frame(width: 30, height: 30)

          VStack(alignment: .leading, spacing: 2) {
            Text("Connect \(connector?.name ?? card.connectorID)")
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(WarmShellColors.primaryText)
            Text(card.reason)
              .font(.system(size: 12))
              .foregroundStyle(WarmShellColors.mutedText)
              .lineLimit(2)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          if let onOpenConnectors {
            Button(action: onOpenConnectors) {
              Text("Connect")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(WarmShellColors.badgeText, in: Capsule())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(11)
        .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(WarmShellColors.cardBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("chat.connectCard.\(card.connectorID)")
      }
    }
  }
}

