import AppCore
import AppKit
import Foundation
import MemoshiClient
import MemoshiProtocol
import SwiftUI
import Testing

/// The Mac Chat's saved Send across a relaunch (D130): what the restored record offers before
/// the app is connected, and what each discard removes. The record's shape is AppCore's
/// `SavedSend`, tested there.
@Suite("Mac Chat model: the saved Send after a relaunch", .timeLimit(.minutes(1)))
@MainActor
struct LiveChatModelTests {
  private static let requestKey = "text-chat.pending-send"

  private static func request() throws -> ChatsSendParams {
    ChatsSendParams(
      requestId: try ULID("01JC" + String(format: "%022d", 1)),
      chatId: try ConversationID("cht_01JC" + String(format: "%022d", 2)),
      content: [.text(TextPart(text: "Hello"))], whenBusy: .reject,
      model: ModelRef(ref: try ModelName("local/test-model")), surface: .ui)
  }

  @Test("A refused saved Send keeps its reason after a relaunch; Discard removes only the request")
  func refusedSendIsRestoredAndDiscarded() throws {
    let store = TestDefaults()
    let saved = SavedSend(defaults: store.defaults)
    try saved.save(Self.request())
    saved.recordRefusal("The request identity conflicts.")
    store.defaults.set("Kept draft", forKey: "text-chat.draft")

    let model = LiveChatModel(defaults: store.defaults)
    #expect(model.hasUnconfirmedSend)
    #expect(model.refusedSendReason == "The request identity conflicts.")
    #expect(model.canDiscardRefusedSend)
    // Not connected yet: nothing can be sent or retried.
    #expect(!model.canSend)
    #expect(!model.canRetrySend)

    model.discardRefusedSend()
    #expect(!model.hasUnconfirmedSend)
    #expect(model.refusedSendReason == nil)
    #expect(saved.load() == nil)
    #expect(model.draft == "Kept draft")
  }

  @Test("An unrefused saved Send is kept for Retry and offers no Discard")
  func unrefusedSendOffersNoDiscard() throws {
    let store = TestDefaults()
    try SavedSend(defaults: store.defaults).save(Self.request())
    let model = LiveChatModel(defaults: store.defaults)
    #expect(model.hasUnconfirmedSend)
    #expect(model.refusedSendReason == nil)
    #expect(!model.canDiscardRefusedSend)
    model.discardRefusedSend()
    #expect(model.hasUnconfirmedSend)
    #expect(SavedSend(defaults: store.defaults).load() != nil)
  }

  @Test(
    "An unreadable saved Send blocks with its own explanation and needs a loaded snapshot to go")
  func unreadableSendNeedsALoadedSnapshot() {
    let store = TestDefaults()
    store.defaults.set(Data("not a request".utf8), forKey: Self.requestKey)
    let model = LiveChatModel(defaults: store.defaults)
    #expect(model.hasUnreadableSend)
    #expect(model.hasUnconfirmedSend)
    #expect(model.unreadableSendExplanation != nil)
    #expect(model.problem == nil)
    #expect(!model.canRetrySend)
    // Disconnected, no conversation snapshot: the discard is not offered and does nothing.
    #expect(!model.canDiscardUnreadableSend)
    model.discardUnreadableSend()
    #expect(model.hasUnreadableSend)
    #expect(store.defaults.data(forKey: Self.requestKey) != nil)
  }

  @Test(
    "Reconnects count every new hello and trigger model discovery only when the daemon restarts")
  func reconnectTracksDaemonRestarts() throws {
    let store = TestDefaults()
    let model = LiveChatModel(defaults: store.defaults)
    let logID = try LogID("log_01JC" + String(format: "%022d", 10))
    let firstDaemon = DaemonInfo(version: "0.1.0", build: "1", pid: 1001, startedAt: 100)
    let restartedDaemon = DaemonInfo(version: "0.1.0", build: "1", pid: 2002, startedAt: 200)
    let limits = ConnectionLimits(
      maxInboundBytes: 1_048_576, maxOutboundFrameBytes: 4_194_304,
      maxBatchEvents: 256, maxInFlightRequests: 64, maxFocus: 8)
    let hash = "sha256:" + String(repeating: "a", count: 64)

    func hello(connectionID: String, daemon: DaemonInfo) -> SystemHelloResult {
      SystemHelloResult(
        connectionId: connectionID, daemon: daemon, protocolVersion: ProtocolVersion.current,
        capabilities: [], logId: logID, head: 0, minRetainedSeq: 0, serverTime: 1,
        schemaHash: hash, limits: limits)
    }

    // Initial connection: count = 1, no rediscovery flag yet.
    model.observeStatus(
      state: .connected, hello: hello(connectionID: "conn-1", daemon: firstDaemon))
    #expect(model.connection == .connected)
    #expect(model.connectionCount == 1)
    #expect(!model.isModelDiscoveryPending)

    // Same daemon reconnects (new connectionId, same DaemonInfo): count = 2, still no rediscovery.
    model.observeStatus(state: .disconnected, hello: nil)
    #expect(model.connection == .disconnected)
    model.observeStatus(
      state: .connected, hello: hello(connectionID: "conn-2", daemon: firstDaemon))
    #expect(model.connectionCount == 2)
    #expect(!model.isModelDiscoveryPending)

    // Helper restarted (new pid/startedAt): count = 3, needsModelDiscovery becomes true.
    model.observeStatus(
      state: .connected, hello: hello(connectionID: "conn-3", daemon: restartedDaemon))
    #expect(model.connectionCount == 3)
    #expect(model.isModelDiscoveryPending)
  }

  @Test(
    "Live text deltas preserve resumedAfterInterruption per task and never bleed into a new task")
  func liveDeltasPreserveResumedFlagPerTask() throws {
    let store = TestDefaults()
    let model = LiveChatModel(defaults: store.defaults)
    let chatID = try ConversationID("cht_01JC" + String(format: "%022d", 20))
    let resumedTask = try TaskID("tsk_01JC" + String(format: "%022d", 21))
    let nextTask = try TaskID("tsk_01JC" + String(format: "%022d", 22))
    let msgA = try MessageID("msg_01JC" + String(format: "%022d", 23))
    let msgB = try MessageID("msg_01JC" + String(format: "%022d", 24))

    // Seed a resumed live turn (as `chats.history` delivers after a helper restart).
    model.seedLiveStateForTesting(
      ChatLiveState(taskId: resumedTask, message: nil, resumedAfterInterruption: true))

    // First delta for the resumed task creates the partial carrying `resumedAfterInterruption == true`.
    let first = try model.applyLiveTextDelta(
      MessageDeltaPayload(messageId: msgA, channel: .text, offsetUtf16: 0, text: "Hello "),
      chatID: chatID, taskID: resumedTask, ts: 100)
    #expect(first == .applied)
    #expect(model.live?.resumedAfterInterruption == true)
    #expect(model.live?.message?.resumedAfterInterruption == true)
    #expect(model.live?.message.map(LiveChatModel.text) == "Hello ")

    // Continuing delta keeps the mark and appends text cleanly; duplicate offset is ignored.
    let second = try model.applyLiveTextDelta(
      MessageDeltaPayload(messageId: msgA, channel: .text, offsetUtf16: 6, text: "world"),
      chatID: chatID, taskID: resumedTask, ts: 101)
    #expect(second == .applied)
    #expect(model.live?.resumedAfterInterruption == true)
    #expect(model.live?.message.map(LiveChatModel.text) == "Hello world")

    let replay = try model.applyLiveTextDelta(
      MessageDeltaPayload(messageId: msgA, channel: .text, offsetUtf16: 0, text: "Hello "),
      chatID: chatID, taskID: resumedTask, ts: 102)
    #expect(replay == .ignored)

    // Gap in UTF-16 offset triggers history reload rather than splicing.
    let gap = try model.applyLiveTextDelta(
      MessageDeltaPayload(messageId: msgA, channel: .text, offsetUtf16: 50, text: "!"),
      chatID: chatID, taskID: resumedTask, ts: 103)
    #expect(gap == .needsReload)

    // A new task's delta must not inherit the old task's `resumedAfterInterruption` flag.
    let fresh = try model.applyLiveTextDelta(
      MessageDeltaPayload(messageId: msgB, channel: .text, offsetUtf16: 0, text: "Fresh"),
      chatID: chatID, taskID: nextTask, ts: 104)
    #expect(fresh == .applied)
    #expect(model.live?.taskId == nextTask)
    #expect(model.live?.resumedAfterInterruption == nil)
    #expect(model.live?.message?.resumedAfterInterruption == nil)
  }

  @Test(
    "LiveTurnStateMark exposes chat.turnState.<id> with stopped and continued accessibility values")
  func turnStateMarkExposesAccessibilityIdentifierAndValue() throws {
    let chatID = try ConversationID("cht_01JC" + String(format: "%022d", 30))
    let msgID = try MessageID("msg_01JC" + String(format: "%022d", 31))
    let taskID = try TaskID("tsk_01JC" + String(format: "%022d", 32))
    let stoppedMessage = ChatMessage(
      id: msgID, conversationId: chatID, taskId: taskID, role: .bot, content: [], createdAt: 100,
      stopReason: .aborted, resumedAfterInterruption: true)

    #expect(
      LiveTurnStateMark.accessibilityIdentifier(for: msgID) == "chat.turnState.\(msgID.rawValue)")
    let value = try #require(
      ResumedReply.accessibilityValue(state: "Stopped", of: stoppedMessage))
    #expect(value.contains("Stopped"))
    #expect(value.contains("Interrupted"))

    let view = NSHostingView(
      rootView: LiveTurnStateMark(message: stoppedMessage, senderName: "Memoshi"))
    #expect(view.fittingSize.width > 0)
    #expect(view.fittingSize.height > 0)
  }
}
