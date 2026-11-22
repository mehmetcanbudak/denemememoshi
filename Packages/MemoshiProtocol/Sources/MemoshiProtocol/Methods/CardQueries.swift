/// `cards.list`: current card records; events are not the source of snapshot state.
public enum CardsList: RPCMethod {
  /// Snapshot filters and exclusive cursor.
  public typealias Params = CardsListParams
  /// A bounded page of current records.
  public typealias Result = CardsListResult
  /// `cards.list`.
  public static let name = "cards.list"
  /// Read-only.
  public static let isMutating = false
}

/// `cards.get`: the authoritative current record for one card.
public enum CardsGet: RPCMethod {
  /// The current card's ID.
  public typealias Params = CardsGetParams
  /// The authoritative card snapshot.
  public typealias Result = CardsGetResult
  /// `cards.get`.
  public static let name = "cards.get"
  /// Read-only.
  public static let isMutating = false
}

/// Filters and exclusive keyset cursor for a bounded card snapshot.
public struct CardsListParams: Codable, Hashable, Sendable {
  /// Restricts the page to one conversation.
  public var conversationId: ConversationID?
  /// Restricts the page to one known lifecycle state.
  public var status: CardStatus?
  /// The previous page's last CardID, exclusive.
  public var cursor: String?
  /// Maximum records to return.
  public var limit: PageLimit

  /// Creates a bounded snapshot query without inferring a selected conversation.
  public init(
    conversationId: ConversationID? = nil, status: CardStatus? = nil,
    cursor: String? = nil, limit: PageLimit
  ) {
    self.conversationId = conversationId
    self.status = status
    self.cursor = cursor
    self.limit = limit
  }
}

/// A card page and the watermark from its actual read transaction.
public struct CardsListResult: Codable, Hashable, Sendable {
  /// Current cards in ascending CardID order.
  public var items: [Card]
  /// Exclusive cursor for the next page, when present.
  public var nextCursor: String?
  /// Position of this page's actual read transaction.
  public var asOf: AsOf

  /// Creates a page with its own watermark.
  public init(items: [Card], nextCursor: String? = nil, asOf: AsOf) {
    self.items = items
    self.nextCursor = nextCursor
    self.asOf = asOf
  }
}

/// Identifies a card independently of any currently selected conversation.
public struct CardsGetParams: Codable, Hashable, Sendable {
  /// The requested card.
  public var cardId: CardID
  /// Identifies one authoritative card record.
  public init(cardId: CardID) { self.cardId = cardId }
}

/// The current card and the same read transaction's position.
public struct CardsGetResult: Codable, Hashable, Sendable {
  /// The current card.
  public var card: Card
  /// Position of the same read transaction.
  public var asOf: AsOf
  /// Creates an authoritative single-card snapshot.
  public init(card: Card, asOf: AsOf) {
    self.card = card
    self.asOf = asOf
  }
}
