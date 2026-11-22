import Foundation
import MemoshiDevice
import MemoshiProtocol
import MemoshiStore

/// The device layer's fenced store backed by the real `MemoshiStore`: authority-decided epochs
/// land in the `leases` table through `Store.recordAuthorityLease`, and every change is an
/// ordinary fenced `Store.commit` of one task record and its `task.created` event, so a stale
/// epoch is refused by exactly the check every other store write uses.
package struct S2StoreAdapter: ConversationStore {
  private let store: Store
  private let botID: BotID
  private let encoder = ProtocolCoding.makeEncoder()

  package init(store: Store) throws {
    self.store = store
    botID = try BotID("bot_" + DeviceULID.make())
  }

  package func adoptLease(_ lease: LeaseRecord, at now: Int64) async throws {
    do {
      try await store.recordAuthorityLease(
        lease.conversationID, epoch: lease.epoch, runnerDeviceID: lease.runner,
        expiresAt: lease.runner == nil ? nil : (lease.expiresAt ?? now), at: now)
    } catch StoreError.leaseFenced(_, let epoch) {
      throw FenceError.fenced(currentEpoch: epoch)
    } catch StoreError.invalidCommit {
      throw FenceError.conflictingRunner
    }
  }

  package func commit(_ change: PendingChange, at now: Int64) async throws -> CommittedChange {
    let task = MemoshiTask(
      id: try TaskID("tsk_" + DeviceULID.make(at: now)), conversationId: change.conversationID,
      botId: botID, kind: .turn, origin: Origin(kind: .user, rootKind: .user), regime: .attended,
      title: try Title(String(change.label.prefix(TitleBounds.maxLength))), status: .queued,
      requestId: change.requestID?.rawValue ?? DeviceULID.make(at: now), budgetIds: [],
      usage: Usage(
        inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
        costMicroUsd: 0, costKnown: true), resumeMode: .auto, createdAt: now)
    let event = EventDraft(
      ts: now, actor: Actor(kind: .user), subject: ObjectRef(kind: "task", id: task.id.rawValue),
      scope: EventScope(botId: botID, conversationId: change.conversationID, taskId: task.id),
      origin: task.origin,
      event: .taskCreated(
        TaskCreatedPayload(
          taskId: task.id, kind: task.kind, title: task.title, origin: task.origin,
          regime: task.regime, parentTaskId: nil)))
    let envelopes: [EventEnvelope]
    do {
      envelopes = try await store.commit(
        StoreCommit(
          records: [.task(task)], events: [event],
          fences: [ConversationFence(conversationID: change.conversationID, epoch: change.epoch)]),
        at: now)
    } catch StoreError.leaseFenced(_, let epoch) {
      throw FenceError.fenced(currentEpoch: epoch)
    }
    return CommittedChange(
      records: [
        ReplicatedRecord(
          kind: "task", id: task.id.rawValue, op: .upsert,
          value: try JSONValue.parse(encoder.encode(task)))
      ], events: envelopes)
  }

  package func releaseLease(_ conversationID: ConversationID, epoch: Int64, at now: Int64)
    async throws
  {
    do {
      try await store.releaseConversation(
        ConversationFence(conversationID: conversationID, epoch: epoch), at: now)
    } catch StoreError.leaseFenced(_, let current) {
      throw FenceError.fenced(currentEpoch: current)
    }
  }
}
