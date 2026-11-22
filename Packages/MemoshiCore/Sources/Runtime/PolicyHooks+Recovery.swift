import Chord
import Foundation
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable

extension PolicyHooks {
  /// Pinned Pi reports ordinary hook errors and continues. A recovery guard therefore waits
  /// for committed evidence or actual invocation cancellation; it must never throw open.
  nonisolated(nonsending) func waitForRecovery(signal: AbortSignal, context: Chord.Context)
    async throws
  {
    try await PiAI.withAbortSignal(signal) {
      try await observeRecovery(signal: signal, context: context)
    }
  }

  /// Pi validates structured output after afterTool. Read those actual immutable entries
  /// before another generation, rather than treating the host callback as final success.
  nonisolated(nonsending) func observeCommittedResults(
    _ entries: [PiDurable.EntryId], api: PiDurable.HookApi,
    context: Chord.Context, fence: ConversationFence
  ) async throws {
    do {
      for id in entries {
        try context.throwIfAborted()
        try api.signal.throwIfAborted()
        guard let entry = try await api.getEntry(id, context: context),
          let creator = entry.byTaskId
        else { throw RuntimeError.projectionFailed }
        try await store.observeCommittedToolResult(
          ToolOutcomeMetadata.model(entry), runtimeTaskKey: String(creator.rawValue),
          fence: fence, at: IDGenerator.nowMilliseconds())
      }
    } catch {
      try await waitForObservationAbort(signal: api.signal, context: context)
    }
  }

  /// Nested result documents are committed before executeTool returns. Observe that result
  /// on the invocation path: a stalled UI/event consumer cannot permit another effect.
  nonisolated(nonsending) func observeCommittedNestedResult(
    _ result: PiDurable.NestedToolExecutionResult, api: PiDurable.ToolExecutionApi,
    context: Chord.Context, fence: ConversationFence
  ) async throws {
    do {
      guard let task = try await api.getTask(result.taskId, context: context),
        task.status == .terminal,
        let input = try task.input?.decode(PiDurable.ToolTaskInput.self),
        case .nested(_, let parentCallId, _, let call, _) = input
      else { throw RuntimeError.projectionFailed }
      try await store.observeCommittedToolResult(
        ToolOutcomeMetadata.nested(result, call: call, parent: parentCallId),
        runtimeTaskKey: String(result.taskId.rawValue), fence: fence,
        at: IDGenerator.nowMilliseconds())
    } catch {
      try await waitForObservationAbort(signal: api.signal, context: context)
    }
  }

  nonisolated(nonsending) private func waitForObservationAbort(
    signal: AbortSignal, context: Chord.Context
  ) async throws {
    try context.throwIfAborted()
    try signal.throwIfAborted()
    // This pin swallows ordinary hook errors. Only real invocation cancellation may
    // end an observation that could not prove which final result Pi committed.
    try await PiAI.withAbortSignal(signal) {
      try await waitForRecoveryAbort(signal)
    }
  }

  nonisolated(nonsending) private func observeRecovery(
    signal: AbortSignal, context: Chord.Context
  ) async throws {
    while true {
      try signal.throwIfAborted()
      try context.throwIfAborted()
      do {
        let changes = try store.subscribeEvents(capacity: 256)
        if try await store.chatRecovery(chat.id).value == nil { return }
        for try await _ in changes {
          try signal.throwIfAborted()
          try context.throwIfAborted()
          if try await store.chatRecovery(chat.id).value == nil { return }
        }
      } catch {
        try signal.throwIfAborted()
        try context.throwIfAborted()
        // A missing/overflowed/closed observation cannot release the hold. Recheck durable
        // state on overflow; if the Store itself cannot be read, park until invocation close.
        if (try? await store.chatRecovery(chat.id)) == nil {
          try await waitForRecoveryAbort(signal)
        }
      }
      try signal.throwIfAborted()
      try context.throwIfAborted()
    }
  }
}

private func waitForRecoveryAbort(_ signal: AbortSignal) async throws {
  try await withCheckedThrowingContinuation {
    (continuation: CheckedContinuation<Void, any Error>) in
    signal.addListener { continuation.resume(throwing: $0) }
  }
}
