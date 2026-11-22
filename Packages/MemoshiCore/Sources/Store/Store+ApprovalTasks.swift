import MemoshiProtocol

extension Store {
  /// Whether any decision of this task is still pending, read in the caller's transaction.
  func hasPendingApproval(_ taskID: TaskID) throws -> Bool {
    try writer.integer(
      "SELECT EXISTS (SELECT 1 FROM approvals WHERE json_extract(record, '$.taskId') = ? AND status = 'pending')",
      [.text(taskID.rawValue)]) == 1
  }

  /// Internal to the caller's fenced writer transaction; no independently published state.
  func updateApprovalWait(taskID: TaskID, at now: Int64) throws -> [EventEnvelope] {
    guard
      let bytes = try writer.query(
        "SELECT record FROM tasks WHERE id = ?", [.text(taskID.rawValue)],
        row: { try $0.requiredData(0) }
      ).first
    else { throw ApprovalError.bindingConflict }
    var task = try decoder.decode(MemoshiTask.self, from: bytes)
    guard [.queued, .running, .waiting].contains(task.status) else { return [] }
    let pending = try hasPendingApproval(taskID)
    if !pending && task.waitingOn != .approval { return [] }
    // A more specific hold (an uncertain step or child tasks) keeps the task as it is: a
    // decision ending under it changes neither the status nor what the task waits on.
    guard task.waitingOn == nil || task.waitingOn == .approval else { return [] }
    let desired: TaskStatus = pending ? .waiting : .running
    if task.status == desired && task.waitingOn == (pending ? .approval : nil) { return [] }
    let scope = EventScope(botId: task.botId, conversationId: task.conversationId, taskId: task.id)
    let subject = ObjectRef(kind: "task", id: task.id.rawValue)
    var events: [EventEnvelope] = []
    if task.status == .queued {
      task.startedAt = now
      events.append(
        try append(
          EventDraft(
            ts: now, actor: Actor(kind: .system), subject: subject, scope: scope,
            origin: task.origin,
            event: .taskStarted(.init(taskId: task.id)))))
    }
    let previous: ActiveTaskStatus = task.status == .waiting ? .waiting : .running
    task.status = desired
    task.waitingOn = pending ? .approval : nil
    try writeRecord(.task(task))
    if var turn = try writer.query(
      "SELECT record FROM chat_turns WHERE json_extract(record, '$.taskId') = ? AND status IN ('queued', 'running', 'waiting')",
      [.text(taskID.rawValue)],
      row: { try decoder.decode(StoredChatTurn.self, from: $0.requiredData(0)) }
    ).first {
      turn.status = desired
      try writeTurn(turn)
    }
    events.append(
      try append(
        EventDraft(
          ts: now, actor: Actor(kind: .system), subject: subject, scope: scope, origin: task.origin,
          event: .taskStatusChanged(
            .init(
              taskId: task.id, status: pending ? .waiting : .running,
              waitingOn: task.waitingOn, previous: previous)))))
    return events
  }
}
