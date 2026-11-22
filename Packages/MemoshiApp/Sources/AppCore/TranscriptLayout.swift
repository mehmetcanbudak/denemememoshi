import MemoshiProtocol

/// One row of a Chat transcript on the Mac and iPhone.
public enum TranscriptItem: Identifiable, Hashable, Sendable {
  /// A row's identity, stable while a reply's end state moves between its bubble and its mark.
  public enum ID: Hashable, Sendable {
    case message(MessageID)
    case approval(ApprovalReviewGroup.ID)
    case turnState(MessageID)
  }

  /// A message's bubble; `showsEndState` says whether its end state is inside the bubble.
  case message(ChatMessage, showsEndState: Bool)
  /// A group of approval Cards.
  case approval(ApprovalReviewGroup)
  /// A reply's end state on its own, after its turn's Cards.
  case turnState(ChatMessage)

  /// The row's identity.
  public var id: ID {
    switch self {
    case .message(let message, _): .message(message.id)
    case .approval(let group): .approval(group.id)
    case .turnState(let message): .turnState(message.id)
    }
  }
}

/// The order of messages and approval Cards in a Chat transcript.
public enum TranscriptLayout {
  /// Whether a message ends its turn in a state the transcript marks: a bot reply that was
  /// stopped, failed, or continued after a restart (``ResumedReply``).
  public static func hasEndState(_ message: ChatMessage) -> Bool {
    guard message.role == .bot else { return false }
    return message.stopReason == .aborted || message.stopReason == .error
      || ResumedReply.isMarked(message)
  }

  /// Messages and `groups`, the Chat's own Card groups, in transcript order: each Card group
  /// beside its Pi anchor message, or at its own creation time when that anchor is not loaded.
  /// A marked reply whose turn has Cards shows its end state once, after them (D139), and
  /// without a bubble when it has no text, as a reply that only called a tool.
  public static func items(
    messages: [ChatMessage], groups: [ApprovalReviewGroup]
  ) -> [TranscriptItem] {
    let anchors = Set(groups.map { $0.entries[0].card.messageId })
    var messageTimes: [MessageID: Int64] = [:]
    var items: [TranscriptItem] = groups.map(TranscriptItem.approval)
    items.reserveCapacity(groups.count + messages.count + anchors.count)
    for message in messages {
      messageTimes[message.id] = message.createdAt
      guard hasEndState(message), anchors.contains(message.id) else {
        items.append(.message(message, showsEndState: true))
        continue
      }
      if hasText(message) { items.append(.message(message, showsEndState: false)) }
      items.append(.turnState(message))
    }
    // Keep related calls beside their actual transcript anchor. A Pi anchor absent from
    // the loaded text history uses its real card creation time, not a synthetic message.
    func order(_ item: TranscriptItem) -> (Int64, String, Int, Int64, String) {
      switch item {
      case .message(let message, _):
        return (message.createdAt, message.id.rawValue, 0, message.createdAt, message.id.rawValue)
      case .approval(let group):
        let card = group.entries[0].card
        return (
          messageTimes[card.messageId] ?? card.createdAt, card.messageId.rawValue, 1,
          card.createdAt, card.id.rawValue
        )
      case .turnState(let message):
        return (message.createdAt, message.id.rawValue, 2, message.createdAt, message.id.rawValue)
      }
    }
    items.sort { order($0) < order($1) }
    return items
  }

  private static func hasText(_ message: ChatMessage) -> Bool {
    message.content.contains { part in
      if case .text(let text) = part { !text.text.isEmpty } else { false }
    }
  }
}
