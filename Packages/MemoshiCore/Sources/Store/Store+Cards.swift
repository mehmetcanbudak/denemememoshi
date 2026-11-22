import MemoshiProtocol

extension Store {
  /// A bounded authoritative card page, independent of retained event history.
  public func cardsPage(
    conversationID: ConversationID? = nil, status: CardStatus? = nil,
    after: CardID? = nil, limit: PageLimit
  ) throws -> CardsListResult {
    try requireOpen()
    guard status?.isKnown != false, limit.isWithinLimits else { throw ApprovalError.invalidRequest }
    return try reader.transaction(write: false) {
      var clauses: [String] = []
      var values: [SQLiteConnection.Value] = []
      if let conversationID {
        clauses.append("conversation_id = ?")
        values.append(.text(conversationID.rawValue))
      }
      if let status {
        clauses.append("status = ?")
        values.append(.text(status.rawValue))
      }
      if let after {
        clauses.append("id > ?")
        values.append(.text(after.rawValue))
      }
      let predicate = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
      values.append(.integer(Int64(limit.rawValue + 1)))
      var items = try reader.query(
        "SELECT record FROM cards\(predicate) ORDER BY id LIMIT ?", values
      ) {
        try decoder.decode(Card.self, from: $0.requiredData(0))
      }
      let hasMore = items.count > limit.rawValue
      if hasMore { items.removeLast() }
      return CardsListResult(
        items: items, nextCursor: hasMore ? items.last?.id.rawValue : nil,
        asOf: try position(conversationID: conversationID))
    }
  }
}
