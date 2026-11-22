import MemoshiProtocol
import MemoshiStore

extension RuntimeAdapter {
  /// `bots.list` for the authenticated app session.
  public func listBots(_ params: BotsListParams) async throws -> BotsListResult {
    try requireReady()
    // No bot can be archived yet, so `includeArchived` lists the same bots.
    let snapshot = try await store.bots()
    return BotsListResult(items: snapshot.value, asOf: snapshot.asOf)
  }

  /// `bots.get` for the authenticated app session.
  public func bot(_ params: BotsGetParams) async throws -> BotsGetResult {
    try requireReady()
    let snapshot = try await store.bot(params.botId)
    guard let bot = snapshot.value else { throw ConversationRecordError.botNotFound }
    return BotsGetResult(bot: bot, asOf: snapshot.asOf)
  }

  /// `bots.create` with the authenticated app user's authority; the bot's Chat opens on first
  /// use, and the bot starts in Ask first like every new bot (D52).
  public func createBot(_ params: BotsCreateParams) async throws -> BotsCreateResult {
    try requireReady()
    let result = try await store.createBot(
      params, paramsHash: Self.paramsHash(params), at: IDGenerator.nowMilliseconds())
    _ = try await store.ensureBotPolicy(result.bot.id, at: IDGenerator.nowMilliseconds())
    return result
  }

  /// `bots.update` with the authenticated app user's authority. Every open conversation of the
  /// bot renders the new identity, persona and job, and uses the new model and effort, from its
  /// next request; nothing is reconfigured or reopened here.
  public func updateBot(_ params: BotsUpdateParams) async throws -> BotsUpdateResult {
    try requireReady()
    if let model = params.patch.model {
      guard Self.isSelectableModel(model) else { throw RuntimeError.invalidParams }
    }
    return try await store.updateBot(
      params, paramsHash: Self.paramsHash(params), at: IDGenerator.nowMilliseconds())
  }

  /// `sessions.create` with the authenticated app user's authority; it opens on first use.
  public func createSession(_ params: SessionsCreateParams) async throws -> SessionsCreateResult {
    try requireReady()
    return try await store.createSession(
      params, paramsHash: Self.paramsHash(params), at: IDGenerator.nowMilliseconds())
  }

  /// `default`, or a model of a provider in the provider table with a known thinking level.
  /// Whether that provider is configured and lists the model is checked when a send uses it.
  static func isSelectableModel(_ model: MemoshiProtocol.ModelRef) -> Bool {
    guard model.effort?.isKnown ?? true else { return false }
    let ref = model.ref.rawValue
    guard ref != "default" else { return true }
    let pieces = ref.split(separator: "/", maxSplits: 1)
    return pieces.count == 2 && ModelProviderDefinition.named(String(pieces[0])) != nil
  }
}
