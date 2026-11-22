import AppCore
import DesignSystem
import MemoshiProtocol
import SwiftUI

/// The Assistant's real Chat on this device. The engine runs in this app (D46); example bots and
/// resources never enter this transcript.
struct MobileLiveChatView: View {
  @Bindable var model: InProcessChatModel
  let state: MobileEngineHost.State
  @State private var isModelSettingsPresented = false
  @State private var liveMessageID: MessageID?
  @State private var knownCards: Set<CardID>?
  @AccessibilityFocusState private var isModelButtonFocused: Bool
  @Environment(\.designAnnouncer) private var announcer
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        // Not lazy: a lazy stack estimated the unbuilt rows (about nine screens for three rows),
        // so scrolling to the end after an approval card landed past every built row and the
        // transcript showed blank. Every loaded message is built and laid out, also each earlier
        // page that Load Earlier Messages adds.
        VStack(alignment: .leading, spacing: DS.Layout.Message.turnSpacing) {
          if model.nextBefore != nil {
            // The frame is inside the label, so the whole 44 pt row is the hit region (A21).
            Button {
              model.loadOlder()
            } label: {
              Text("Load Earlier Messages")
                .frame(maxWidth: .infinity, minHeight: DS.Layout.Composer.minHeight)
                .contentShape(Rectangle())
            }
            .disabled(model.isLoadingOlder)
            .accessibilityIdentifier("chat.loadEarlier")
          }
          if let recovery = model.recovery {
            // One block, so a scroll can bring its last line, the choices, into view.
            VStack(alignment: .leading, spacing: DS.Layout.Message.turnSpacing) {
              // Plural variations live in the String Catalog (one/other).
              Label(
                "This chat is paused until \(recovery.steps.count) uncertain tool steps are resolved.",
                systemImage: "exclamationmark.triangle"
              )
              .font(.callout)
              .accessibilityIdentifier("chat.recovery")
              ForEach(recovery.steps, id: \.self) { held in
                if let step = held.step, let card = step.cardId,
                  let choices = model.resumeChoices[card], !choices.isEmpty
                {
                  MobileResumeChoices(model: model, tool: step.tool, card: card, choices: choices)
                }
              }
            }
            .id(Self.recoveryAnchor)
          }
          if isEmpty { emptyState }
          MobileLiveTranscript(model: model)
          if let message = model.live?.message,
            !model.messages.contains(where: { $0.id == message.id })
          {
            MobileMessageBubble(message: message, isStreaming: model.task?.status != .waiting)
              .accessibilityIdentifier("chat.liveMessage")
          }
          if model.recovery == nil && model.task?.status == .waiting {
            Label("Waiting for your decision", systemImage: "hand.raised")
              .font(.callout)
              .foregroundStyle(DS.Colors.Text.secondary)
              .accessibilityIdentifier("chat.waitingForApproval")
          } else if model.isWorking && model.live == nil {
            HStack(spacing: DS.Space.s3) {
              ProgressView()
              Text("Working…").font(.callout).foregroundStyle(DS.Colors.Text.secondary)
            }
            .accessibilityIdentifier("chat.working")
          }
          if dynamicTypeSize.isAccessibilitySize {
            // At accessibility sizes the composer's status lines scroll with the transcript,
            // just above the composer, so the fixed composer keeps only the field and its
            // button and the transcript stays readable (A24).
            MobileComposerNotices(model: model)
            MobileModelLine(model: model)
          }
          Color.clear.frame(height: DS.Layout.Conversation.scrollAnchorHeight).id("chat.bottom")
        }
        .padding(.horizontal, DS.Space.s5)
        .padding(.vertical, DS.Space.s4)
      }
      .defaultScrollAnchor(.bottom)
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: model.messages.last?.id) { _, _ in
        // A pending Resume card is the one thing the user must act on; keep it in view.
        if hasResumeChoices {
          proxy.scrollTo(Self.recoveryAnchor, anchor: .bottom)
        } else {
          proxy.scrollTo("chat.bottom", anchor: .bottom)
        }
        announceFinishedMessage()
      }
      // The Resume choices sit above the transcript, which opens scrolled to its end. When they
      // appear, also after a relaunch, scroll the notice's end, its choices, into view. With
      // small text the whole notice then shows below the header bar; when the notice is taller
      // than the space (large text), its first lines scroll under the header bar instead of the
      // choices going under the composer. The keyboard is put away: a held chat only queues
      // messages, and the keyboard leaves little room for the choices.
      .onChange(of: resumeCardIDs, initial: true) { _, cards in
        guard !cards.isEmpty else { return }
        UIApplication.shared.sendAction(
          #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
          await Task.yield()
          withAnimation { proxy.scrollTo(Self.recoveryAnchor, anchor: .bottom) }
        }
      }
      // A new approval Card needs a decision before the turn can go on. With the keyboard up,
      // large text leaves the Card's buttons under the header bar, so put the keyboard away
      // and show the end of the transcript, where the Card is. In iPhone landscape the end
      // leaves the Card's buttons above the little space there is, so they are then centred.
      .onChange(of: pendingCardIDs) { old, new in
        guard !Set(new).subtracting(old).isEmpty else { return }
        UIApplication.shared.sendAction(
          #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
          await Task.yield()
          withAnimation { proxy.scrollTo("chat.bottom", anchor: .bottom) }
        }
        revealDecision(proxy)
      }
      // Rotating or resizing keeps the scroll offset, not what was in view: in iPhone landscape,
      // the pending Card's buttons ended up under the header bar or the composer. Bring what
      // the person must answer back into view then, and when the keyboard has gone.
      .onGeometryChange(for: CGSize.self, of: \.size) { _ in revealDecision(proxy) }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification))
      { _ in revealDecision(proxy) }
    }
    .safeAreaInset(edge: .bottom) {
      // Backed down to the bottom edge, as the example conversations' composer is: the
      // transcript stops at the composer instead of showing around it and under the tab bar.
      MobileLiveComposer(model: model)
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .background(DesignControlRoles.barBacking, ignoresSafeAreaEdges: [.bottom, .horizontal])
    }
    .background(DS.Colors.Surface.window)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Model", systemImage: "slider.horizontal.3") { isModelSettingsPresented = true }
          .accessibilityFocused($isModelButtonFocused)
          .accessibilityIdentifier("chat.modelSettings")
      }
    }
    .sheet(isPresented: $isModelSettingsPresented, onDismiss: restoreModelButtonFocus) {
      MobileModelSettingsView(model: model)
    }
    .onChange(of: model.live?.message?.id, initial: true) { _, id in
      if let id { liveMessageID = id }
    }
    .onChange(of: model.problem ?? model.reviews.problem ?? model.task?.error?.message) {
      _, problem in
      if let problem { announcer.announce(problem) }
    }
    .onChange(of: model.reviews.hasLoaded, initial: true) { _, loaded in
      // Cards already pending when review state loads are history, not new arrivals.
      if loaded && knownCards == nil { knownCards = Set(pendingCardIDs) }
    }
    .onChange(of: pendingCardIDs) { _, current in
      // This device shows one conversation: each new card is announced in place (02 §13.2).
      guard let known = knownCards else {
        if model.reviews.hasLoaded { knownCards = Set(current) }
        return
      }
      knownCards = known.union(current)
      for entry in model.reviews.entries
      where current.contains(entry.id) && !known.contains(entry.id) {
        announcer.announce(String(localized: "Assistant needs you: \(entry.card.title.rawValue)"))
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("chat.realConversation")
  }

  private var pendingCardIDs: [CardID] {
    model.reviews.entries.filter(\.isPending).map(\.id)
  }

  /// This Chat's newest pending approval Card.
  private var newestPendingCard: CardID? {
    model.reviews.entries.last { $0.isPending && $0.card.conversationId == model.chat?.id }?.id
  }

  /// Brings what the person must answer into view after the layout settles: the Resume
  /// choices, placed as when they appear, or else the newest pending approval Card's buttons,
  /// centred in the visible part of the transcript. In iPhone landscape at the largest standard
  /// text size Deny is taller than that part; centred, Allow once still fits it whole. A Card
  /// at the end of the transcript, where it usually is, cannot move further up.
  private func revealDecision(_ proxy: ScrollViewProxy) {
    let target: (id: String, anchor: UnitPoint)
    if hasResumeChoices {
      target = (Self.recoveryAnchor, .bottom)
    } else if let card = newestPendingCard {
      target = (MobileApprovalCardView.actionsAnchor(card), .center)
    } else {
      return
    }
    Task { @MainActor in
      await Task.yield()
      withAnimation { proxy.scrollTo(target.id, anchor: target.anchor) }
    }
  }

  private static let recoveryAnchor = "chat.recovery"

  /// Held steps whose Resume card the user can answer now, in the hold's order.
  private var resumeCardIDs: [String] {
    (model.recovery?.steps ?? []).compactMap { held in
      guard let card = held.step?.cardId, model.resumeChoices[card]?.isEmpty == false else {
        return nil
      }
      return card.rawValue
    }
  }

  private var hasResumeChoices: Bool { !resumeCardIDs.isEmpty }

  /// Returns VoiceOver focus to the Model button when its sheet closes (02 §13.1).
  private func restoreModelButtonFocus() {
    Task { @MainActor in isModelButtonFocused = true }
  }

  /// A streamed reply is announced once, when it settles into the transcript (02 §13.2).
  private func announceFinishedMessage() {
    guard let liveMessageID, let message = model.messages.last, message.id == liveMessageID,
      message.role != .user
    else { return }
    self.liveMessageID = nil
    let text = InProcessChatModel.text(message)
    let state = MobileMessageBubble.state(of: message, isStreaming: false)
    let spoken =
      ResumedReply.accessibilityValue(state: state?.accessibilityValue, of: message).map {
        String(localized: "Assistant: \(text). \($0)")
      } ?? String(localized: "Assistant: \(text)")
    announcer.announceOnce(spoken, key: "message." + message.id.rawValue)
  }

  private var isEmpty: Bool {
    model.messages.isEmpty && model.live == nil && model.recovery == nil
      && !model.reviews.entries.contains { $0.card.conversationId == model.chat?.id }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("Your Assistant", systemImage: "sparkles")
    } description: {
      Group {
        switch state {
        case .opening:
          Text("Opening the engine on this device.")
        case .failed(let problem):
          Text(verbatim: problem)
        case .ready where model.models.isEmpty:
          Text(
            "Choose a local OpenAI-compatible endpoint in Model. No cloud model or key is used, and nothing is substituted."
          )
        case .ready:
          Text(
            "Send your first message. The conversation is stored on this device. Production tools and Apple connectors are off."
          )
        }
      }
      .foregroundStyle(DesignControlRoles.secondaryText)
    } actions: {
      if state == .ready && model.models.isEmpty {
        Button("Model Settings") { isModelSettingsPresented = true }
          .accessibilityIdentifier("chat.setup")
      }
    }
    .frame(minHeight: DS.Layout.Conversation.emptyStateMinHeight)
  }
}

/// Messages and approval Cards in transcript order (``TranscriptLayout``): each Card beside its
/// Pi anchor message, or at its own creation time when that anchor is not loaded, and a reply's
/// end state after its turn's Cards.
private struct MobileLiveTranscript: View {
  let model: InProcessChatModel

  var body: some View {
    ForEach(items) { item in
      switch item {
      case .message(let message, let showsEndState):
        MobileMessageBubble(message: message, isStreaming: false, showsEndState: showsEndState)
          .accessibilityIdentifier("chat.message.\(message.id.rawValue)")
      case .approval(let group):
        ForEach(group.entries) { entry in
          MobileApprovalCardView(entry: entry, model: model.reviews)
        }
      case .turnState(let message):
        MobileTurnStateMark(message: message)
      }
    }
  }

  private var items: [TranscriptItem] {
    TranscriptLayout.items(
      messages: model.messages,
      groups: model.reviews.timelineGroups.filter { $0.id.conversationId == model.chat?.id })
  }
}

private struct MobileMessageBubble: View {
  let message: ChatMessage
  let isStreaming: Bool
  /// Whether the reply's end state is inside the bubble; a turn with Cards shows it after them.
  var showsEndState = true

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
    let text = InProcessChatModel.text(message)
    let state = showsEndState ? Self.state(of: message, isStreaming: isStreaming) : nil
    let value =
      showsEndState
      ? ResumedReply.accessibilityValue(state: state?.accessibilityValue, of: message) : nil
    HStack {
      if isUser { Spacer(minLength: DS.Space.s9) }
      VStack(alignment: .leading, spacing: DS.Space.s2) {
        // A reply stopped before it had text, such as one whose tool call waited for a Card,
        // shows only its state.
        if !text.isEmpty || state == nil {
          Text(verbatim: text)
            .font(.body)
            .foregroundStyle(isUser ? DS.Colors.Text.onUserBubble : DS.Colors.Text.primary)
            .textSelection(.enabled)
        }
        if showsEndState { MobileEndStateCaptions(message: message, state: state) }
      }
      .padding(.vertical, DS.Layout.Message.bubblePaddingV)
      .padding(.horizontal, DS.Layout.Message.bubblePaddingH)
      .background(
        isUser ? DS.Colors.Surface.userBubble : DS.Colors.Surface.raised,
        in: RoundedRectangle(cornerRadius: DS.Radius.bubble))
      if !isUser { Spacer(minLength: DS.Space.s8) }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isStaticText)
    .accessibilityLabel(isUser ? "You: \(text)" : "Assistant: \(text)")
    // The sender label stays on the combined element; the stream state and the restart note
    // are its value (A1).
    .accessibilityValue(Text(verbatim: value ?? ""))
  }
}

/// A reply's stream state and restart note, each on its own line.
private struct MobileEndStateCaptions: View {
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
struct MobileTurnStateMark: View {
  let message: ChatMessage

  var body: some View {
    let state = MobileMessageBubble.state(of: message, isStreaming: false)
    let value = ResumedReply.accessibilityValue(state: state?.accessibilityValue, of: message)
    VStack(alignment: .leading, spacing: DS.Space.s2) {
      MobileEndStateCaptions(message: message, state: state)
    }
    .padding(.horizontal, DS.Layout.Message.bubblePaddingH)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isStaticText)
    .accessibilityLabel(Text("Assistant"))
    .accessibilityValue(Text(verbatim: value ?? ""))
    .accessibilityIdentifier("chat.turnState.\(message.id.rawValue)")
  }
}

/// The current problem, and either an unreadable saved Send with its own explanation and its
/// discard, or an unconfirmed Send with its Retry, plus its discard once the engine refused it.
/// Accessibility sizes stack the notice above its action and wrap every line in full instead
/// of truncating (A24).
private struct MobileComposerNotices: View {
  let model: InProcessChatModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var isDiscardingRecord = false
  @State private var isDiscardingRefused = false

  var body: some View {
    if let problem = model.problem ?? model.reviews.problem ?? model.task?.error?.message {
      Text(verbatim: problem)
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("chat.error")
    }
    if let explanation = model.unreadableSendExplanation {
      // Its own row: the explanation stays beside any later problem until the person discards
      // the record.
      Text(verbatim: explanation)
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("chat.unreadableSendExplanation")
      Button("Discard Unreadable Record…", role: .destructive) { isDiscardingRecord = true }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!model.canDiscardUnreadableSend)
        .accessibilityIdentifier("chat.discardUnreadableSend")
        .frame(
          maxWidth: .infinity,
          alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
        )
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
    } else if model.hasUnconfirmedSend {
      let layout =
        dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s3))
        : AnyLayout(HStackLayout(spacing: DS.Space.s3))
      layout {
        Group {
          if let reason = model.refusedSendReason {
            Text(verbatim: reason).accessibilityIdentifier("chat.refusedSendReason")
          } else {
            Text("Delivery unconfirmed · original request kept")
          }
        }
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
        .fixedSize(horizontal: false, vertical: true)
        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
        Button("Retry") { model.retrySend() }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .disabled(!model.canRetrySend)
          .accessibilityIdentifier("chat.retrySend")
      }
      if model.refusedSendReason != nil {
        // The engine will refuse this request again as it stands; only the person discards it.
        Button("Discard Refused Message…", role: .destructive) { isDiscardingRefused = true }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .disabled(!model.canDiscardRefusedSend)
          .accessibilityIdentifier("chat.discardRefusedSend")
          .frame(
            maxWidth: .infinity,
            alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
          )
          .confirmationDialog(
            "Discard Refused Message?", isPresented: $isDiscardingRefused,
            titleVisibility: .visible
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
  }
}

/// The model the next Send names.
private struct MobileModelLine: View {
  let model: InProcessChatModel

  var body: some View {
    Text(label)
      .font(DS.Typography.subheadline)
      .foregroundStyle(DS.Colors.Text.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("chat.modelLabel")
  }

  private var label: String {
    guard model.isConnected else { return String(localized: "Engine not ready") }
    guard let choice = model.models.first(where: { $0.ref.ref.rawValue == model.selectedModel })
    else { return String(localized: "No model selected") }
    return String(localized: "\(choice.name) · local endpoint")
  }
}

private struct MobileLiveComposer: View {
  @Bindable var model: InProcessChatModel
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      // At accessibility sizes the notices and the model line are in the transcript instead.
      if !dynamicTypeSize.isAccessibilitySize { MobileComposerNotices(model: model) }
      HStack(alignment: .bottom, spacing: DS.Space.s3) {
        TextField(
          "Message Assistant", text: $model.draft,
          // The full placeholder cannot fit beside the button at accessibility sizes; the
          // field's accessibility label still names the Assistant.
          prompt: (dynamicTypeSize.isAccessibilitySize
            ? Text("Message") : Text("Message Assistant"))
            .foregroundStyle(DesignControlRoles.placeholder),
          axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.body)
        // At accessibility sizes the draft grows to three lines, keeping the transcript visible;
        // longer drafts scroll inside the field (A24).
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 1...3 : 1...6)
        .frame(minHeight: DS.Layout.Composer.minHeight, alignment: .leading)
        .disabled(model.isSending || model.hasUnconfirmedSend)
        .accessibilityLabel("Message Assistant")
        .accessibilityHint("Saved as a local draft until you send it to the selected model.")
        .accessibilityIdentifier("chat.composer")
        // accent.fill + onFill, with the 44 pt hit region inside the button's own shape.
        if model.isWorking {
          Button(model.isStopping ? "Stopping…" : "Stop", systemImage: "stop.fill") {
            model.stop()
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.designProminent(minimumSize: DS.Layout.Composer.minHeight))
          .disabled(!model.canStop)
          .accessibilityIdentifier("chat.stop")
        } else {
          Button("Send", systemImage: "arrow.up") { model.send() }
            .labelStyle(.iconOnly)
            .buttonStyle(.designProminent(minimumSize: DS.Layout.Composer.minHeight))
            .disabled(!model.canSend)
            .accessibilityIdentifier("chat.send")
        }
      }
      if !dynamicTypeSize.isAccessibilitySize { MobileModelLine(model: model) }
    }
    .padding(DS.Layout.Composer.padding)
    .background(
      reduceTransparency
        ? AnyShapeStyle(DS.Colors.Surface.raised) : AnyShapeStyle(.regularMaterial),
      in: RoundedRectangle(cornerRadius: DS.Radius.composer)
    )
    .designBoundary(RoundedRectangle(cornerRadius: DS.Radius.composer))
  }
}

/// A held step's Resume card (D51): Run again, Skip or Mark as done, as the card offers now.
private struct MobileResumeChoices: View {
  let model: InProcessChatModel
  let tool: String
  let card: CardID
  let choices: [ResumeAction]

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Label(tool, systemImage: "pause.circle")
        .font(.callout.monospaced())
        .accessibilityLabel("\(tool), outcome unresolved")
      // Side by side when they fit; otherwise one per line, so no title wraps (one view tree,
      // unlike ViewThatFits, so Dynamic Type keeps applying to each button).
      DesignFittingStack(spacing: DS.Space.s3) { buttons }
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private var buttons: some View {
    ForEach(choices, id: \.self) { choice in
      Button(Self.title(choice)) { model.answerResume(card, choice) }
        .buttonStyle(.bordered)
        .disabled(!model.isConnected || model.answeringResume.contains(card))
        .accessibilityIdentifier("chat.resume.\(choice.rawValue).\(card.rawValue)")
    }
    if model.answeringResume.contains(card) { ProgressView() }
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
