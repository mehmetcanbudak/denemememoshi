import Chord
import MemoshiProtocol
import MemoshiStore
import PiCore
import PiDurable

/// Child scope is proved from Pi's immutable ownership + host-authored first entry + the
/// original root assistant call. A current active turn, child-supplied ID or call-ID prefix is
/// never sufficient authority for a child. Every SDK access remains on its invocation line.
enum RuntimeTaskScope {
  nonisolated(nonsending) static func taskID(
    _ api: PiDurable.HookApi, store: Store, chat: ChatSummary, fence: ConversationFence,
    context: Chord.Context, toolName: String? = nil
  ) async throws -> MemoshiProtocol.TaskID {
    if api.conversationId != .root {
      let binding = try await child(
        api.conversationId, store: store, chat: chat, fence: fence,
        getConversation: { try await api.getConversation($0, context: context) },
        getTask: { try await api.getTask($0, context: context) },
        getEntry: { try await api.getEntry($0, context: context) },
        originalTask: {
          try await originalTaskID(
            before: $0, store: store, chat: chat.id,
            scan: { query, cursor in
              try await api.scanEntries(query, limit: 128, cursor: cursor, context: context)
            })
        },
        firstEntry: {
          try await api.scanEntries(
            .init(conversationId: $0, order: .ascending),
            limit: 1, context: context
          ).items.first
        })
      guard toolName.map({ binding.toolNames.contains($0) }) ?? true else {
        throw RuntimeToolError.notAuthorized
      }
      return binding.taskId
    }
    guard var record = try await api.getTask(api.taskId, context: context) else {
      throw RuntimeToolError.notAuthorized
    }
    var seen: Set<PiDurable.TaskId> = []
    while record.kind == "pi.tool" {
      guard record.conversationId == .root, seen.insert(record.id).inserted,
        let input = try record.input?.decode(PiDurable.ToolTaskInput.self)
      else { throw RuntimeToolError.notAuthorized }
      if let (assistant, _) = input.modelCall,
        let entry = try await api.getEntry(assistant, context: context),
        entry.conversationId == .root
      {
        return try await originalTaskID(
          before: entry.id, store: store, chat: chat.id,
          scan: { query, cursor in
            try await api.scanEntries(query, limit: 128, cursor: cursor, context: context)
          })
      }
      guard let parent = input.nestedParent,
        let next = try await api.getTask(parent, context: context)
      else { throw RuntimeToolError.notAuthorized }
      record = next
    }
    throw RuntimeToolError.notAuthorized
  }

  static func child(
    _ id: PiDurable.ConversationId, storage: PiDurable.SqliteStorage, store: Store,
    chat: ChatSummary, fence: ConversationFence
  ) async throws -> RuntimeSubagentBinding {
    try await child(
      id, store: store, chat: chat, fence: fence,
      getConversation: { try await storage.conversation($0) },
      getTask: { try await storage.task($0) },
      getEntry: { try await storage.entry($0)?.entry },
      originalTask: {
        try await originalTaskID(before: $0, storage: storage, store: store, chat: chat.id)
      },
      firstEntry: {
        try await storage.scanEntries(
          .init(conversationId: $0, order: .ascending),
          limit: 1
        ).items.first
      })
  }

  nonisolated(nonsending) private static func child(
    _ id: PiDurable.ConversationId, store: Store, chat: ChatSummary, fence: ConversationFence,
    getConversation: (PiDurable.ConversationId) async throws -> PiDurable.ConversationRecord?,
    getTask: (PiDurable.TaskId) async throws -> PiDurable.TaskRecord?,
    getEntry: (PiDurable.EntryId) async throws -> PiDurable.EntryRecord?,
    originalTask: (PiDurable.EntryId) async throws -> MemoshiProtocol.TaskID,
    firstEntry: (PiDurable.ConversationId) async throws -> PiDurable.EntryRecord?
  ) async throws -> RuntimeSubagentBinding {
    guard id != .root, let conversation = try await getConversation(id),
      conversation.parent == nil, let owner = conversation.owner, owner.conversationId == .root,
      let entry = try await firstEntry(id), entry.kind == RuntimeSubagents.identityKind,
      entry.conversationId == id, entry.model == nil, let data = entry.data,
      let record = try await getTask(owner.taskId)
    else { throw RuntimeToolError.notAuthorized }
    let binding = try data.decode(RuntimeSubagentBinding.self)
    let permitted = Set(binding.toolNames)
    guard binding.conversationId == chat.id, fence.conversationID == chat.id,
      binding.piOwnerTaskId == owner.taskId.rawValue, binding.piConversationId == id.rawValue,
      binding.requestId == "subagent:\(owner.taskId.rawValue)",
      permitted.count == binding.toolNames.count,
      permitted.isDisjoint(with: RuntimeSubagents.names),
      record.conversationId == .root, record.owner == nil || !binding.background,
      let source = try await getTask(PiDurable.TaskId(binding.sourceToolTaskId)),
      source.kind == "pi.tool", source.conversationId == .root,
      entry.byTaskId == source.id,
      let input = try source.input?.decode(PiDurable.ToolTaskInput.self),
      let (assistant, callId) = input.modelCall, let message = try await getEntry(assistant),
      message.conversationId == .root,
      let call = message.model?.first?.assistantMessage?.toolCalls.first(where: {
        $0.id == callId
      }),
      call.name.displayString
        == (binding.background ? RuntimeSubagents.backgroundName : RuntimeSubagents.foregroundName),
      try await originalTask(assistant) == binding.originalTaskId
    else { throw RuntimeToolError.notAuthorized }
    if binding.background {
      guard record.kind == RuntimeSubagents.anchorName, record.background,
        let input = try record.input?.decode(RuntimeSubagents.BackgroundInput.self),
        input.taskId == binding.taskId, input.originalTaskId == binding.originalTaskId,
        input.sourceToolTaskId == binding.sourceToolTaskId
      else { throw RuntimeToolError.notAuthorized }
    } else {
      guard record.id == source.id, record.kind == "pi.tool", !record.background else {
        throw RuntimeToolError.notAuthorized
      }
    }
    _ = try await store.ensureRuntimeSubagent(
      binding, fence: fence, at: IDGenerator.nowMilliseconds())
    return binding
  }

  static func originalTaskID(
    before entry: PiDurable.EntryId, storage: PiDurable.SqliteStorage, store: Store,
    chat: MemoshiProtocol.ConversationID
  ) async throws -> MemoshiProtocol.TaskID {
    try await originalTaskID(
      before: entry, store: store, chat: chat,
      scan: { query, cursor in try await storage.scanEntries(query, limit: 128, cursor: cursor) })
  }

  nonisolated(nonsending) private static func originalTaskID(
    before entry: PiDurable.EntryId, store: Store, chat: MemoshiProtocol.ConversationID,
    scan: (PiDurable.EntryQuery, PiDurable.Cursor?) async throws ->
      PiDurable.Page<PiDurable.EntryRecord>
  ) async throws -> MemoshiProtocol.TaskID {
    var cursor: PiDurable.Cursor?
    repeat {
      let page = try await scan(
        .init(conversationId: .root, maxEntryId: entry, order: .descending), cursor)
      for candidate in page.items where candidate.kind == "memoshi.user" {
        guard candidate.conversationId == .root,
          let key = candidate.data?["memoshiRequestId"]?.stringValue,
          let turn = try await store.chatTurn(ULID(key)), turn.chatId == chat
        else { throw RuntimeToolError.notAuthorized }
        return turn.taskId
      }
      cursor = page.next
    } while cursor != nil
    throw RuntimeToolError.notAuthorized
  }
}

extension PiDurable.ToolTaskInput {
  /// A model call's assistant entry and call ID; nil for a nested call.
  var modelCall: (assistant: PiDurable.EntryId, callId: PiCore.JSONString)? {
    if case .model(let assistant, let callId) = self { (assistant, callId) } else { nil }
  }

  /// True for a call made by another tool, not by the model.
  var isNestedCall: Bool { modelCall == nil }

  /// A nested call's parent task; nil for a model call.
  var nestedParent: PiDurable.TaskId? {
    if case .nested(let parent, _, _, _, _) = self { parent } else { nil }
  }

  /// A nested call's parent call ID; nil for a model call.
  var nestedParentCallId: PiCore.JSONString? {
    if case .nested(_, let parentCallId, _, _, _) = self { parentCallId } else { nil }
  }

  /// A nested call's key within its parent; nil for a model call.
  var nestedKey: PiCore.JSONString? {
    if case .nested(_, _, let key, _, _) = self { key } else { nil }
  }

  /// A nested call itself; nil for a model call.
  var nestedCall: PiDurable.NestedToolCall? {
    if case .nested(_, _, _, let call, _) = self { call } else { nil }
  }
}
