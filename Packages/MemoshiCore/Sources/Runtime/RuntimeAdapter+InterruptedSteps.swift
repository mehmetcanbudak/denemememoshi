import Chord
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable

extension RuntimeAdapter {
  static let undispatchedActor: PiCore.JSONValue = [
    "kind": "memoshi", "reason": "not_dispatched",
  ]

  /// Pi records a call's intent, then executes it; Memoshi records its dispatch inside that
  /// execution, before any effect, with a commit that survives power loss
  /// (`Store.beginUnsafeToolDispatch`). A replay-unsafe step Pi reports interrupted without that
  /// record, and without a result Memoshi projected, was cut off in between, so Memoshi never
  /// dispatched it. It fails as interrupted and does not run again, as it did before Pi_Swift
  /// E20: Memoshi answers Pi's decision wait with Skip in its own name. Every other step that
  /// waits on a decision gets a Resume card, held like any uncertain dispatch:
  /// - one Memoshi recorded as ended: Pi's commits survive a process kill only, so an OS crash
  ///   or a power loss can take back Pi's result after Memoshi projected it. It ran.
  /// - a replay-safe one, which Pi asks about only once its tool is no longer registered as
  ///   replay-safe: its execution needs no record of Memoshi's, so none proves it never ran.
  /// - one Memoshi cannot account for otherwise (a rerun, or a tool no longer offered).
  /// A step with Memoshi's record or Resume card is governed by that.
  func settleUndispatchedSteps(_ thread: RuntimeThread, graph: PiDurable.TaskGraph) async throws {
    guard let engine = thread.engine else { return }
    for value in graph.tasks.values {
      let node = try value.decode(PiDurable.TaskGraphNode.self)
      guard let step = node.interrupted, let waitID = step.decisionWaitId,
        step.status == .outcomeUnknown, !thread.accountedSteps.contains(waitID)
      else { continue }
      let key = String(step.taskId.rawValue)
      switch try await store.unsafeToolDispatchEvidence(
        thread.conversationID, runtimeTaskKey: key)
      {
      case .recorded:
        break
      case .absent
      where !step.replaySafe && step.attempt == 1
        && step.tool?.nativeString.map({ engine.dispatchRecordedTools.contains($0) }) == true:
        switch try await engine.harness.settle(
          waitId: waitID,
          value: PiDurable.InterruptedToolDecision.skip.waitValue(actor: Self.undispatchedActor),
          requestId: PiCore.JSONString("memoshi.undispatched:\(key)"))
        {
        case .settled, .alreadySettled, .notFound: break
        case .expired: throw RuntimeError.projectionFailed
        }
      case .absent, .completed:
        guard let task = try await thread.storage.task(step.taskId), task.kind == "pi.tool",
          let input = try task.input?.decode(PiDurable.ToolTaskInput.self)
        else { throw RuntimeError.projectionFailed }
        try await store.holdUnaccountedToolDispatch(
          try await policyToolCall(task, input: input, thread: thread).identity,
          fence: thread.ownership.fence, at: IDGenerator.nowMilliseconds())
      }
      thread.accountedSteps.insert(waitID)
    }
  }
}

extension PolicyHooks {
  /// Pi's model text for a skipped interrupted step (Pi_Swift ToolTask `interruptionNote`).
  static let skippedNote = "the user skipped it, so it did not run again"

  /// Pi tells the model that the user skipped a step and that it may have partially run. For a
  /// step Memoshi settled as `not_dispatched` both are false: it never ran and nobody chose.
  /// Every request replaces that note with D51's account; Pi's committed entry is unchanged. Only
  /// results whose committed decision names Memoshi's actor and request are replaced.
  nonisolated(nonsending) static func truthfulInterruptions(
    _ messages: [PiAI.Message], api: PiDurable.HookApi, context: Chord.Context
  ) async throws -> [PiAI.Message]? {
    var candidates: [PiCore.JSONString: Int] = [:]
    for (index, message) in messages.enumerated() {
      guard case .toolResult(let result) = message, result.isError,
        result.content.contains(where: {
          $0.textContent?.text.displayString.contains(skippedNote) == true
        })
      else { continue }
      candidates[result.toolCallId] = index
    }
    guard !candidates.isEmpty else { return nil }
    var confirmed: Set<PiCore.JSONString> = []
    try await committedToolResults(of: Set(candidates.keys), api: api, context: context) {
      entry, id in
      guard let value = entry.data?["interruption"],
        let decision = try value.decode(PiDurable.ToolInterruption.self).decision,
        decision.action == .skip, decision.actor == RuntimeAdapter.undispatchedActor,
        decision.requestId?.displayString.hasPrefix("memoshi.undispatched:") == true
      else { return }
      confirmed.insert(id)
    }
    guard !confirmed.isEmpty else { return nil }
    var rewritten = messages
    for id in confirmed {
      guard let index = candidates[id], case .toolResult(var result) = messages[index] else {
        continue
      }
      let note = PiCore.JSONString(
        "<harness>\n[error] Tool \(result.toolName.displayString) was interrupted before it ran: "
          + "it did not run, nothing was applied, and it was not run again.\n</harness>")
      result.content = result.content.map { block in
        block.textContent?.text.displayString.contains(skippedNote) == true ? .text(note) : block
      }
      rewritten[index] = .toolResult(result)
    }
    return rewritten
  }
}
