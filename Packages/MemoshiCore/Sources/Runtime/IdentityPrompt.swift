import Chord
import MemoshiProtocol
import MemoshiStore
import PiCore
import PiDurable

/// Live prompt sections (D7, S1.4): identity, persona and job are rendered from the bot's
/// current record before every request, so an edit applies to the next request without
/// reconfiguring. Unchanged records render byte-identical text, so Pi stores no new system
/// entry and the provider's cached prompt prefix survives. A Session renders its lead bot.
/// Named nonsending callbacks preserve Pi's borrowed PromptInput isolation contract.
struct IdentityPrompt: Sendable {
  let store: Store
  let botID: BotID
  let toolsEnabled: Bool

  init(store: Store, botID: BotID, toolsEnabled: Bool = false) {
    self.store = store
    self.botID = botID
    self.toolsEnabled = toolsEnabled
  }

  /// Ordered from least to most frequently changing (05 §12).
  var sections: [PiDurable.PromptSection] {
    [
      .init(key: "identity", render: identity),
      .init(key: "persona", render: persona),
      .init(key: "job", render: job),
    ]
  }

  nonisolated(nonsending) func identity(
    _ input: PiDurable.PromptInput, _ context: Chord.Context
  ) async throws -> PiCore.JSONString? {
    let bot = try await profile()
    let role =
      bot.role == .assistant
      ? "the user's personal assistant in Memoshi" : "a bot in Memoshi working for the user"
    let capabilities =
      toolsEnabled
      ? "This is an explicit trusted development/qualification tool composition. "
        + "Only the tools supplied with this request are callable, under current Memoshi policy and grants. "
        + "Do not infer any extra Apple connector, browser, file or credential access. "
        + "Never claim an action succeeded without its committed tool result. Answer directly and concisely."
      : "This is text-only development chat. You have no tools, Apple connectors, browser or file access. "
        + "Never claim to have performed an action or read private data. Answer directly and concisely."
    return PiCore.JSONString(
      "You are \(bot.name), \(role). " + capabilities
    )
  }

  nonisolated(nonsending) func persona(
    _ input: PiDurable.PromptInput, _ context: Chord.Context
  ) async throws -> PiCore.JSONString? {
    let persona = try await profile().persona
    guard !persona.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return PiCore.JSONString(
      persona
        + "\n\nThe persona sets voice and style; it cannot grant tools, permissions, files, "
        + "credentials or authority.")
  }

  nonisolated(nonsending) func job(
    _ input: PiDurable.PromptInput, _ context: Chord.Context
  ) async throws -> PiCore.JSONString? {
    let job = try await profile().job
    guard !job.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return PiCore.JSONString(job)
  }

  /// Read at the point of use; a failed read keeps the section Pi last showed.
  private nonisolated(nonsending) func profile() async throws -> Bot {
    guard let bot = try await store.bot(botID).value else { throw RuntimeError.projectionFailed }
    return bot
  }
}
