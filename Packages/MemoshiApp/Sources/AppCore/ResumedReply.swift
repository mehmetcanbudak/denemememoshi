import Foundation
import MemoshiProtocol

/// The note on a reply the runtime continued by itself after a restart cut it off
/// (`task.resumed` by `system`, events.md §5.5), for the Mac and iPhone transcripts.
public enum ResumedReply {
  /// The visible note: below the reply's text, or after the turn's Cards when it has any (D139).
  public static let caption = LocalizedStringResource(
    "Interrupted · continued after a restart", bundle: #bundle)
  /// What VoiceOver reads for the note.
  public static let spokenNote = LocalizedStringResource(
    "Interrupted, then continued after a restart", bundle: #bundle)

  /// Whether the transcript marks this message: a bot reply whose turn was continued.
  public static func isMarked(_ message: ChatMessage) -> Bool {
    message.role == .bot && message.resumedAfterInterruption == true
  }

  /// The reply's accessibility value: its state, if any, then the note when it is marked.
  public static func accessibilityValue(
    state: LocalizedStringResource?, of message: ChatMessage
  ) -> String? {
    let state = state.map { String(localized: $0) }
    guard isMarked(message) else { return state }
    let note = String(localized: spokenNote)
    guard let state else { return note }
    return String(localized: "\(state), \(note)", bundle: #bundle)
  }
}
