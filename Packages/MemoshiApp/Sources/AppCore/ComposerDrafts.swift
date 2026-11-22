import Foundation
import Observation

/// UI-local text only: this does not submit a message or write an authoritative transcript.
@MainActor
@Observable
public final class ComposerDrafts {
  private var values: [String: String]
  private let defaults: UserDefaults
  private let namespace: String

  /// Restores draft text from the given UI-preference namespace without submitting it.
  public init(
    defaults: UserDefaults = .standard,
    namespace: String = "design-preview.drafts"
  ) {
    self.defaults = defaults
    self.namespace = namespace
    values = defaults.dictionary(forKey: namespace) as? [String: String] ?? [:]
  }

  /// Returns this bot's unsent text, or an empty string when no draft was saved.
  public func text(for bot: PreviewBot) -> String {
    values[bot.rawValue] ?? ""
  }

  /// Saves exact text for one bot; an empty string clears only that bot's draft.
  public func setText(_ text: String, for bot: PreviewBot) {
    guard text != values[bot.rawValue] else { return }
    if text.isEmpty {
      values.removeValue(forKey: bot.rawValue)
    } else {
      values[bot.rawValue] = text
    }
    defaults.set(values, forKey: namespace)
  }
}
