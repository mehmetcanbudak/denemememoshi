import Chord
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable

/// D51 / Pi_Swift E20: Run again, Skip and Mark as done on a held step's Resume card. The
/// answer commits in the Store first and clears the step's hold (`Store.respondToResume`); Pi
/// gets it afterwards, from that durable record, whenever the conversation's engine is open.
extension RuntimeAdapter {
  /// Called only by the authenticated app session, never by a model-callable tool.
  func respondToResume(_ params: CardsRespondParams, hash: String, card: Card) async throws
    -> CardsRespondResult
  {
    try await withThread(card.conversationId) { adapter, thread in
      guard !thread.failed else { throw ApprovalError.notFound }
      let receipt = try await adapter.store.respondToResume(
        params, paramsHash: hash, actor: Actor(kind: .user), fence: thread.ownership.fence,
        at: IDGenerator.nowMilliseconds())
      try await adapter.continueAfterResume(thread)
      return receipt
    }
  }

  /// Hands a retried answer to Pi (`respondToCard`): the first attempt's hand-off may have
  /// failed after the Store committed the answer, and Pi's waiting step holds the conversation
  /// until it has it. Pi settles each card's request once, so a repeat changes nothing.
  func continueAfterRetriedResume(_ conversation: ConversationID) async throws {
    try await withThread(conversation) { adapter, thread in
      guard !thread.failed else { return }
      try await adapter.continueAfterResume(thread)
    }
  }

  /// Once the last held step is answered, the conversation continues: a held thread opens its
  /// Harness as any unheld one does, and Pi's waiting step gets the answer; an open one gives it
  /// now, settles its turn from Pi's committed state and sends queued input.
  private func continueAfterResume(_ thread: RuntimeThread) async throws {
    guard try await store.chatRecovery(thread.conversationID).value == nil else { return }
    if let engine = thread.engine {
      try await applyResumeDecisions(thread, graph: engine.taskGraph.value)
      try await reconcile(thread)
      if thread.resumed { try await drainQueuedInputs(thread) }
    } else if schedulerResumed {
      try await resumeThread(thread)
    }
  }

  /// Gives Pi each recorded answer whose step now waits on its decision. The request ID names
  /// the card, so a repeat after a kill is Pi's same settlement, never a second one. Run again
  /// cannot run twice either way: Memoshi's dispatch gate admits one execution per answer.
  func applyResumeDecisions(_ thread: RuntimeThread, graph: PiDurable.TaskGraph) async throws {
    guard let engine = thread.engine else { return }
    let decided = try await store.pendingResumeDecisions(thread.conversationID)
    guard !decided.isEmpty else { return }
    for value in graph.tasks.values {
      let node = try value.decode(PiDurable.TaskGraphNode.self)
      guard let step = node.interrupted, let waitID = step.decisionWaitId,
        step.status == .outcomeUnknown, !thread.answeredWaits.contains(waitID),
        let decision = decided[String(step.taskId.rawValue)]
      else { continue }
      let choice: PiDurable.InterruptedToolDecision
      switch decision.action {
      case .runAgain: choice = .runAgain
      case .skip: choice = .skip
      case .markDone: choice = .markDone
      case .unknown: throw RuntimeError.projectionFailed
      }
      let actor: PiCore.JSONValue = [
        "kind": "user", "cardId": .string(PiCore.JSONString(decision.cardId.rawValue)),
      ]
      switch try await engine.harness.settle(
        waitId: waitID, value: choice.waitValue(actor: actor),
        requestId: PiCore.JSONString("memoshi.resume:\(decision.cardId.rawValue)"))
      {
      case .settled, .alreadySettled, .notFound: break
      case .expired: throw RuntimeError.projectionFailed
      }
      thread.answeredWaits.insert(waitID)
    }
  }
}

extension PolicyHooks {
  /// A call Pi had already ended (Stop, or a tool that returned an unknown effect) keeps Pi's
  /// committed result. The user's later answer on its Resume card is added to that result in
  /// every request, in D51's words; Pi's entry is unchanged. Only results whose committed entry
  /// was written by the answered Pi tool task get the note, and none whose entry records that
  /// Pi applied this same card's answer itself (its own note is there): a Run again that Pi got
  /// ran again and says so, and one that found no wait ran nothing.
  nonisolated(nonsending) func resumeNotes(
    _ messages: [PiAI.Message], api: PiDurable.HookApi, context: Chord.Context
  ) async throws -> [PiAI.Message]? {
    let noted = try await store.notedResumeDecisions(fence.conversationID)
    guard !noted.isEmpty else { return nil }
    var candidates: [PiCore.JSONString: Int] = [:]
    for (index, message) in messages.enumerated() {
      guard case .toolResult(let result) = message else { continue }
      candidates[result.toolCallId] = index
    }
    guard !candidates.isEmpty else { return nil }
    var confirmed: [PiCore.JSONString: ResumeAction] = [:]
    try await Self.committedToolResults(of: Set(candidates.keys), api: api, context: context) {
      entry, id in
      guard let creator = entry.byTaskId, let answer = noted[String(creator.rawValue)] else {
        return
      }
      // Pi applied this very answer and wrote its own note. A Run again's rerun carries an
      // earlier card's answer, which does not cover this one.
      if let value = entry.data?["interruption"],
        let decision = try value.decode(PiDurable.ToolInterruption.self).decision,
        decision.requestId?.displayString == "memoshi.resume:\(answer.cardId.rawValue)"
      {
        return
      }
      confirmed[id] = answer.action
    }
    guard !confirmed.isEmpty else { return nil }
    var rewritten = messages
    for (id, action) in confirmed {
      guard let index = candidates[id], case .toolResult(var result) = messages[index] else {
        continue
      }
      let note = Self.resumeNote(tool: result.toolName.displayString, action: action)
      result.isError = note.isError
      result.content.append(
        .text(PiCore.JSONString("<harness>\n" + note.text + "\n</harness>")))
      rewritten[index] = .toolResult(result)
    }
    return rewritten
  }

  /// What the model reads after a call Pi had ended when the user answered its Resume card with
  /// `action`, and whether the result then counts as an error. None of the answers ran it again:
  /// Pi had no wait to give it to.
  static func resumeNote(tool: String, action: ResumeAction) -> (text: String, isError: Bool) {
    switch action {
    case .markDone:
      (
        "[info] Tool \(tool): the user confirmed that it happened (Mark as done), "
          + "so it did not run again.", false
      )
    case .runAgain:
      (
        "[error] Tool \(tool) may have partially run; the user chose Run again, "
          + "but the call had already ended, so it did not run again.", true
      )
    default:
      (
        "[error] Tool \(tool) may have partially run; the user skipped it, "
          + "so it did not run again.", true
      )
    }
  }

  /// Visits the newest committed result entry of each call in `calls`, reading the
  /// conversation's entries newest first and no further back than the oldest of them.
  nonisolated(nonsending) static func committedToolResults(
    of calls: Set<PiCore.JSONString>, api: PiDurable.HookApi, context: Chord.Context,
    visit: (PiDurable.EntryRecord, PiCore.JSONString) throws -> Void
  ) async throws {
    try await scanToolResults(
      calls,
      toolCallId: { entry in
        entry.kind == "pi.tool-result" ? entry.model?.first?.toolResultMessage?.toolCallId : nil
      },
      page: { cursor in
        let page = try await api.scanEntries(
          .init(conversationId: api.conversationId), limit: 128, cursor: cursor, context: context)
        return (page.items, page.next)
      }, visit: visit)
  }

  /// The scan behind `committedToolResults`: pages, newest entries first, until every key in
  /// `pending` has been seen once. A request's tool results are among its conversation's newest
  /// entries, so a scan for them never reads the older history.
  nonisolated(nonsending) static func scanToolResults<Entry, Cursor, Key: Hashable>(
    _ pending: Set<Key>, toolCallId: (Entry) -> Key?,
    page: nonisolated(nonsending) (Cursor?) async throws -> (items: [Entry], next: Cursor?),
    visit: (Entry, Key) throws -> Void
  ) async throws {
    var remaining = pending
    var cursor: Cursor?
    while !remaining.isEmpty {
      let (items, next) = try await page(cursor)
      for entry in items {
        guard let key = toolCallId(entry), remaining.remove(key) != nil else { continue }
        try visit(entry, key)
      }
      guard let next else { return }
      cursor = next
    }
  }
}
