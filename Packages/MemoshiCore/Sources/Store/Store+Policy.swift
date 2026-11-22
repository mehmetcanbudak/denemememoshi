import Foundation
import MemoshiProtocol

extension Store {
  /// Seeds the real Assistant's initial Ask first state once, without changing existing modes.
  public func ensureBotPolicy(_ botID: BotID, at now: Int64) throws -> BotPolicyState {
    try requireOpen()
    var events: [EventEnvelope] = []
    let state = try writer.transaction(write: true) {
      if let existing = try readBotPolicy(botID, database: writer) { return existing }
      try writer.execute(
        "INSERT INTO bot_policy (bot_id, permission_mode, active) VALUES (?, 'ask_first', 1)",
        [.text(botID.rawValue)])
      events.append(
        try append(
          policySettingsEvent(
            botID, mode: .askFirst, active: true, actor: Actor(kind: .system), at: now)))
      guard let state = try readBotPolicy(botID, database: writer) else {
        throw ApprovalError.bindingConflict
      }
      return state
    }
    eventBus.publish(events)
    return state
  }

  /// Reads mode and hard-stop state together at the point of use.
  public func botPolicy(_ botID: BotID) throws -> BotPolicyState {
    try requireOpen()
    return try reader.transaction(write: false) {
      guard let state = try readBotPolicy(botID, database: reader) else {
        throw ApprovalError.bindingConflict
      }
      return state
    }
  }

  /// Trusted application composition may update records only for an explicit user decision.
  /// Existing pending approvals retain their original decisions; this does not auto-apply a mode.
  public func setBotPolicy(
    _ botID: BotID, permissionMode: PermissionMode, active: Bool,
    actor: Actor, confirmedBypass: Bool = false, at now: Int64
  ) throws -> BotPolicyState {
    try requireOpen()
    guard actor.kind == .user else { throw ApprovalError.forbidden }
    guard permissionMode.isKnown else { throw ApprovalError.invalidRequest }
    var events: [EventEnvelope] = []
    let state = try writer.transaction(write: true) {
      guard let previous = try readBotPolicy(botID, database: writer) else {
        throw ApprovalError.notFound
      }
      if permissionMode == .bypass && previous.permissionMode != .bypass && !confirmedBypass {
        throw ApprovalError.forbidden
      }
      if previous.permissionMode != permissionMode || previous.active != active {
        try writer.execute(
          "UPDATE bot_policy SET permission_mode = ?, active = ? WHERE bot_id = ?",
          [.text(permissionMode.rawValue), .integer(active ? 1 : 0), .text(botID.rawValue)])
        events.append(
          try append(
            policySettingsEvent(botID, mode: permissionMode, active: active, actor: actor, at: now))
        )
      }
      guard let state = try readBotPolicy(botID, database: writer) else {
        throw ApprovalError.bindingConflict
      }
      return state
    }
    eventBus.publish(events)
    return state
  }

  /// Class-A envelope mirrors survive ordinary event-feed pruning. This is not an HMAC chain.
  public func auditEvents(after: Int64 = 0, limit: PageLimit) throws -> StoreSnapshot<
    [EventEnvelope]
  > {
    try requireOpen()
    guard after >= 0, limit.isWithinLimits else { throw ApprovalError.invalidRequest }
    return try reader.transaction(write: false) {
      let events = try reader.query(
        "SELECT envelope FROM audit_events WHERE seq > ? ORDER BY seq LIMIT ?",
        [.integer(after), .integer(Int64(limit.rawValue))]
      ) { try decoder.decode(EventEnvelope.self, from: $0.requiredData(0)) }
      return StoreSnapshot(value: events, asOf: try position(conversationID: nil))
    }
  }

  private func readBotPolicy(_ botID: BotID, database: SQLiteConnection) throws -> BotPolicyState? {
    try database.query(
      "SELECT b.permission_mode, b.active, p.kill_switch FROM bot_policy b CROSS JOIN policy_control p WHERE b.bot_id = ? AND p.singleton = 1",
      [.text(botID.rawValue)]
    ) {
      let mode = PermissionMode(rawValue: try $0.requiredText(0))
      guard mode.isKnown else { throw ApprovalError.bindingConflict }
      return BotPolicyState(
        permissionMode: mode, active: $0.integer(1) == 1, killSwitch: $0.integer(2) == 1)
    }.first
  }

  private func policySettingsEvent(
    _ botID: BotID, mode: PermissionMode, active: Bool, actor: Actor, at now: Int64
  ) -> EventDraft {
    let prefix = "policy.bots." + botID.rawValue
    return EventDraft(
      ts: now, actor: actor, subject: ObjectRef(kind: "system", id: "policy"),
      event: .systemSettingsChanged(
        .init(
          keys: [prefix + ".permission_mode", prefix + ".active"],
          values: [
            prefix + ".permission_mode": .string(mode.rawValue), prefix + ".active": .bool(active),
          ])))
  }
}
