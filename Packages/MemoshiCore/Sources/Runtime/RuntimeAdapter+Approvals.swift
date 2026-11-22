import MemoshiProtocol
import MemoshiStore

extension RuntimeAdapter {
  /// Called only by the authenticated app session, never by a model-callable tool. The card's
  /// conversation opens if it is not open, so its fence and recovery state are current.
  public func respondToCard(_ params: CardsRespondParams) async throws -> CardsRespondResult {
    try requireReady()
    let hash = try Self.paramsHash(params)
    // A retry of an answered request returns its receipt before any current check: its card's
    // conversation may since have closed, lost its lease or moved to Trash. A Resume answer is
    // handed to Pi again while its conversation is open, since the first hand-off may have
    // failed after the commit; one that is not open gives Pi the answer when it opens.
    if var receipt = try await store.requestReceipt(
      params.requestId, method: CardsRespond.name, paramsHash: hash, as: CardsRespondResult.self)
    {
      receipt.replayed = true
      if receipt.card.kind == .resume, threads[receipt.card.conversationId] != nil {
        try await continueAfterRetriedResume(receipt.card.conversationId)
      }
      return receipt
    }
    guard let card = try await store.card(params.cardId).value else { throw ApprovalError.notFound }
    if card.kind == .resume { return try await respondToResume(params, hash: hash, card: card) }
    return try await withThread(card.conversationId) { adapter, thread in
      guard !thread.failed else { throw ApprovalError.notFound }
      var sanitized = params
      if let payload = params.payload {
        sanitized.payload = try await adapter.credentials.scrubPolicyMetadata(payload)
      }
      return try await adapter.store.respondToApproval(
        sanitized, paramsHash: hash, actor: Actor(kind: .user), fence: thread.ownership.fence,
        at: IDGenerator.nowMilliseconds())
    }
  }
}
