import Chord
import Foundation
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable

extension PolicyHooks {
  /// The end of every stopped reply in the model's context.
  static let stoppedNote =
    "<harness>\n[stopped] The user stopped this reply before it finished. "
    + "Answer the user's latest message.\n</harness>"

  /// The end of a crash-cut-off partial reply that a failed turn kept in the chat.
  static let interruptedNote =
    "<harness>\n[interrupted] This reply was cut off before it finished. "
    + "Answer the user's latest message.\n</harness>"

  /// What follows a stopped turn that ends with tool results: its calls ended with the Stop,
  /// and the latest message is a new request, which may need the tool again.
  static let stoppedTurnNote =
    "<harness>\n[stopped] The user stopped this turn before it finished. "
    + "Answer the user's latest message, and call a tool again if that message needs one."
    + "\n</harness>"

  /// Pi leaves every aborted reply out of the model's context (`deriveContext`, then again
  /// `transformMessages`), in the same process and after a restart alike. After a Stop, the
  /// stopped request and the next one reached the model as two user messages in a row, and it
  /// could answer the older one. Every request puts each reply the chat shows as stopped back
  /// where it was, as a finished reply: its text, then `stoppedNote`. A stopped turn none of
  /// whose reply reaches the model, as one stopped before its first delta, gets an assistant
  /// message of `stoppedNote` alone after its input. Pi's entries are unchanged.
  ///
  /// A stopped turn is one that ended canceled, by the user's Stop. A close cancels nothing
  /// (D139): Pi generates the reply it cut off again after the next open, and that turn ends as
  /// its new reply does. A partial that a restart converted before retrying is no stopped reply;
  /// if that turn later ends failed keeping its partial, the partial reaches the next request
  /// with `interruptedNote` instead of `stoppedNote`.
  ///
  /// A stopped reply that was calling a tool is left out, as Pi does, and its turn gets the
  /// note alone. Its calls never ran and their arguments may be cut off: as a finished reply it
  /// would need a result for every call, and the model would read that calls it never finished
  /// asking for had failed.
  ///
  /// A stopped turn whose finished reply called tools ends with their results, which Pi keeps:
  /// a call the Stop ended reads "was aborted", or blocked when its Card was pending. After a
  /// Stop with a pending Card the model read that as the tool failing and answered the next
  /// request as if it had failed too. Such a turn gets `stoppedTurnNote` after its last result,
  /// unless a stopped reply after the results already ends with `stoppedNote`.
  nonisolated(nonsending) func stoppedReplies(
    _ messages: [PiAI.Message], api: PiDurable.HookApi, context: Chord.Context
  ) async throws -> [PiAI.Message]? {
    // Pass the request's cut-off so `contextView` sees the exact range `messages` came from.
    let cutoff: PiDurable.EntryId?
    if let task = try await api.getTask(api.taskId, context: context),
      let value = task.state.checkpoint?["cutoff"]
    {
      cutoff = try value.decode(PiDurable.EntryId.self)
    } else {
      cutoff = nil
    }
    // The entries behind `messages`, aborted ones included; read from Pi's cached context.
    let view = try await api.contextView(at: cutoff, context: context)
    /// The first message after entry `position` in this request, which a stopped reply or
    /// note goes before.
    func following(_ position: Int) -> PiAI.Message? {
      view.contributions[(position + 1)...].joined().first { $0.role != "system" }
    }
    let isRoot = api.conversationId == .root
    // Lazily resolved for subagent conversations: whether any task in this child was aborted.
    var childAborted: Bool?
    // Keyed by the index of the message each goes before.
    var replies: [Int: PiAI.Message] = [:]
    // The same, for a note after a stopped turn's input or its last tool result: that
    // message's time and the note's text.
    var notes: [Int: (timestamp: Double, text: String)] = [:]
    for (position, entry) in view.entries.enumerated() {
      guard let model = entry.model, model.count == 1 else { continue }
      switch model[0] {
      case .assistant(let reply) where reply.stopReason == .aborted && reply.toolCalls.isEmpty:
        guard let next = following(position), let index = messages.firstIndex(of: next) else {
          continue
        }
        if isRoot {
          guard
            let turn = try await store.chatTurn(
              containingPiEntry: entry.id.rawValue, chatID: fence.conversationID),
            turn.assistantEntryId == entry.id.rawValue
          else { continue }
          if turn.status == .canceled {
            replies[index] = .assistant(Self.finished(stopped: reply))
          } else if turn.status == .failed {
            replies[index] = .assistant(Self.finished(interrupted: reply))
          }
        } else if let creator = entry.byTaskId,
          let task = try await api.getTask(creator, context: context),
          task.abortRequested || task.state.outcome?.status == .aborted
        {
          replies[index] = .assistant(Self.finished(stopped: reply))
        }
      case .user(let input):
        // Only an input another user message follows: otherwise some of its reply is there.
        guard let next = following(position), next.role == "user",
          let index = messages.firstIndex(of: next)
        else { continue }
        if isRoot {
          guard let key = entry.data?["memoshiRequestId"]?.stringValue,
            let request = try? ULID(key),
            let turn = try await store.chatTurn(request),
            turn.chatId.rawValue == fence.conversationID.rawValue,
            turn.userEntryId == entry.id.rawValue, turn.status == .canceled
          else { continue }
          notes[index] = (input.timestamp, Self.stoppedNote)
        } else {
          if childAborted == nil {
            childAborted = try await Self.hasAbortedTask(in: api, context: context)
          }
          if childAborted == true {
            notes[index] = (input.timestamp, Self.stoppedNote)
          }
        }
      case .toolResult(let result):
        // Only the last result, which the next turn's input follows.
        guard let next = following(position), next.role == "user",
          let index = messages.firstIndex(of: next)
        else { continue }
        if isRoot {
          guard
            let turn = try await store.chatTurn(
              containingPiEntry: entry.id.rawValue, chatID: fence.conversationID),
            turn.status == .canceled
          else { continue }
          notes[index] = (result.timestamp, Self.stoppedTurnNote)
        } else {
          if childAborted == nil {
            childAborted = try await Self.hasAbortedTask(in: api, context: context)
          }
          if childAborted == true {
            notes[index] = (result.timestamp, Self.stoppedTurnNote)
          }
        }
      default:
        continue
      }
    }
    // A stopped reply that goes back there already ends with the note.
    let pending = notes.filter { replies[$0.key] == nil }
    if !pending.isEmpty, let ref = try await api.agent(context: context).model,
      let model = api.models.getModel(ref.provider, ref.modelId)
    {
      for (index, note) in pending {
        replies[index] = .assistant(
          PiAI.AssistantMessage(
            content: [.text(PiCore.JSONString(note.text))], api: model.api,
            provider: model.provider, model: model.id, stopReason: .stop,
            timestamp: note.timestamp))
      }
    }
    guard !replies.isEmpty else { return nil }
    var rewritten = messages
    // Last first, so each index still names the message it was found at.
    for (index, reply) in replies.sorted(by: { $0.key > $1.key }) {
      rewritten.insert(reply, at: index)
    }
    return rewritten
  }

  /// `reply` as a finished reply that ends with `stoppedNote`. Its thinking and its signatures
  /// are dropped: they belong to output its provider never finished.
  static func finished(stopped reply: PiAI.AssistantMessage) -> PiAI.AssistantMessage {
    finished(reply, note: stoppedNote)
  }

  /// `reply` as a finished reply that ends with `interruptedNote` (a crash-cut-off partial kept
  /// by a failed turn).
  static func finished(interrupted reply: PiAI.AssistantMessage) -> PiAI.AssistantMessage {
    finished(reply, note: interruptedNote)
  }

  private static func finished(
    _ reply: PiAI.AssistantMessage, note: String
  ) -> PiAI.AssistantMessage {
    var finished = reply
    finished.content = reply.content.compactMap { block in
      guard case .text(var text) = block,
        !text.text.displayString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return nil }
      text.textSignature = nil
      return .text(text)
    }
    finished.content.append(
      .text(PiCore.JSONString(finished.content.isEmpty ? note : "\n\n" + note)))
    finished.stopReason = .stop
    finished.errorMessage = nil
    return finished
  }

  private nonisolated(nonsending) static func hasAbortedTask(
    in api: PiDurable.HookApi, context: Chord.Context
  ) async throws -> Bool {
    var cursor: PiDurable.Cursor?
    repeat {
      let page = try await api.scanTasks(
        .init(conversationId: api.conversationId), limit: 128, cursor: cursor, context: context)
      if page.items.contains(where: {
        $0.abortRequested || $0.state.outcome?.status == .aborted
      }) {
        return true
      }
      cursor = page.next
    } while cursor != nil
    return false
  }
}
