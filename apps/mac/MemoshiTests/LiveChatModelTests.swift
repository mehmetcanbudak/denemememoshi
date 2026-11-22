import AppCore
import AppKit
import Foundation
import MemoshiClient
import MemoshiProtocol
import MemoshiRuntime
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

  @Test("Composer thinking effort and speed mode persist and Fast caps high reasoning to low")
  func composerThinkingAndSpeedModePersistAndCap() {
    let store = TestDefaults()
    store.defaults.set("Extra High", forKey: "composer.thinkingLevel")
    store.defaults.set("Fast", forKey: "composer.speedMode")

    let model = LiveChatModel(defaults: store.defaults)
    #expect(model.composerThinkingEffort == .xhigh)
    #expect(model.composerSpeedMode == .fast)
    #expect(model.effectiveThinkingEffort == .low)

    model.composerSpeedMode = .standard
    #expect(model.effectiveThinkingEffort == .xhigh)
    #expect(store.defaults.string(forKey: "composer.speedMode") == "Standard")

    model.composerThinkingEffort = .off
    model.composerSpeedMode = .fast
    #expect(model.effectiveThinkingEffort == .off)
    #expect(store.defaults.string(forKey: "composer.thinkingLevel") == "off")
  }

  @Test("WorkspaceBookmarksStore toggles and persists links and messages")
  func workspaceBookmarksPersistAndToggle() throws {
    let store = TestDefaults()
    let bookmarks = WorkspaceBookmarksStore(defaults: store.defaults)
    let url = try #require(URL(string: "https://example.com/docs/swift"))

    bookmarks.toggleLink(
      url: url, title: "Swift Docs", subtitle: "Reference", botName: "Assistant",
      conversationID: "cht_01JC0000000000000000000001")
    #expect(bookmarks.isLinkBookmarked(url))
    #expect(bookmarks.items.count == 1)

    bookmarks.toggleMessage(
      messageID: "msg_1", text: "First line\nSecond line", botName: "Assistant",
      conversationID: "cht_01JC0000000000000000000001")
    #expect(bookmarks.isMessageBookmarked("msg_1"))
    #expect(bookmarks.items.count == 2)

    let reloaded = WorkspaceBookmarksStore(defaults: store.defaults)
    #expect(reloaded.isLinkBookmarked(url))
    #expect(reloaded.isMessageBookmarked("msg_1"))

    reloaded.toggleLink(
      url: url, botName: "Assistant", conversationID: nil)
    #expect(!reloaded.isLinkBookmarked(url))
    #expect(reloaded.items.count == 1)
  }

  @Test("ExtractedConversationLink extracts and deduplicates HTTP/HTTPS URLs newest first")
  func extractedConversationLinksDeduplicateAndOrderNewestFirst() throws {
    let chatID = try ConversationID("cht_01JC" + String(format: "%022d", 40))
    let msg1 = ChatMessage(
      id: try MessageID("msg_01JC" + String(format: "%022d", 41)),
      conversationId: chatID,
      taskId: nil,
      role: .user,
      content: [.text(TextPart(text: "Check https://apple.com/macos and https://swift.org"))],
      createdAt: 1_000)
    let msg2 = ChatMessage(
      id: try MessageID("msg_01JC" + String(format: "%022d", 42)),
      conversationId: chatID,
      taskId: nil,
      role: .bot,
      content: [.text(TextPart(text: "Updated link: https://SWIFT.ORG and https://github.com/apple"))],
      createdAt: 2_000)

    let links = ExtractedConversationLink.extract(from: [msg1, msg2], senderName: "Assistant")
    #expect(links.count == 3)
    #expect(links[0].host == "github.com")
    #expect(links[1].host.lowercased() == "swift.org")
    #expect(links[2].host == "apple.com")
  }

  @Test("MarkdownMessageParser handles prose, fenced code blocks, and unclosed streaming fences")
  func markdownMessageParserHandlesFencedAndStreamingBlocks() {
    let sample = """
      Here is an example:
      ```swift
      let x = 42
      ```
      And streaming:
      ```bash
      git status
      """
    let blocks = MarkdownMessageParser.parse(sample)
    #expect(blocks.count == 4)
    #expect(blocks[0] == .prose("Here is an example:"))
    #expect(blocks[1] == .code(language: "swift", content: "let x = 42"))
    #expect(blocks[2] == .prose("And streaming:"))
    #expect(blocks[3] == .code(language: "bash", content: "git status"))
  }

  @Test("NotesDocumentStore creates, updates, sanitizes filenames, and deletes Markdown files")
  func notesDocumentStoreCRUDAndSanitization() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("memoshi-notes-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    #expect(NotesDocumentStore.sanitizedFilename(from: "Project Plan: Q4 / Draft!") == "project-plan-q4-draft.md")
    #expect(NotesDocumentStore.sanitizedFilename(from: "   ///   ") == "untitled.md")

    let store = NotesDocumentStore(directoryURL: tempDir)
    #expect(store.notes.isEmpty)

    let first = try #require(store.createNote(title: "Release Checklist"))
    #expect(first.filename == "release-checklist.md")
    #expect(first.title == "Release Checklist")
    #expect(store.notes.count == 1)

    let duplicate = try #require(store.createNote(title: "Release Checklist"))
    #expect(duplicate.filename == "release-checklist-2.md")
    #expect(store.notes.count == 2)

    store.saveNote(first, content: "# Updated Heading\n\nBody text")
    let updated = try #require(store.notes.first(where: { $0.id == first.id }))
    #expect(updated.title == "Updated Heading")
    #expect(updated.content.contains("Body text"))

    store.deleteNote(duplicate)
    #expect(store.notes.count == 1)
  }

  @Test("CommandPaletteMatcher ranks exact and prefix hits ahead of substring and keyword matches")
  func commandPaletteMatcherRanksMatches() {
    let items = [
      CommandPaletteItem(
        id: "1", title: "My Apps", subtitle: "Hub", symbol: "square.grid.2x2",
        category: .workspaces, keywords: ["calendar"]),
      CommandPaletteItem(
        id: "2", title: "Calendar", subtitle: "My Apps", symbol: "calendar",
        category: .apps, keywords: ["events"]),
      CommandPaletteItem(
        id: "3", title: "Calendar Sync Check", subtitle: "Action", symbol: "arrow.clockwise",
        category: .actions, keywords: []),
      CommandPaletteItem(
        id: "4", title: "Weekly Calendar Review", subtitle: "Bot", symbol: "sparkles",
        category: .conversations, keywords: []),
    ]

    let results = CommandPaletteMatcher.filter(items, query: "calendar")
    #expect(results.map(\.id) == ["2", "3", "4", "1"])

    let all = CommandPaletteMatcher.filter(items, query: "   ")
    #expect(all.count == 4)
  }

  @Test("LiveCalendarStore.eventsByDay groups events across a 7-day window in chronological order")
  func liveCalendarEventsByDayGroupsAcrossWindow() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let base = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9)))
    let day0Morning = try #require(calendar.date(byAdding: .hour, value: 1, to: base))
    let day0Afternoon = try #require(calendar.date(byAdding: .hour, value: 5, to: base))
    let day2Event = try #require(calendar.date(byAdding: .day, value: 2, to: base))

    let items = [
      LiveCalendarStore.EventItem(
        id: "b", title: "Afternoon", calendarTitle: "Work",
        startDate: day0Afternoon, endDate: day0Afternoon.addingTimeInterval(3600),
        isAllDay: false, location: nil),
      LiveCalendarStore.EventItem(
        id: "a", title: "Morning", calendarTitle: "Work",
        startDate: day0Morning, endDate: day0Morning.addingTimeInterval(3600),
        isAllDay: false, location: nil),
      LiveCalendarStore.EventItem(
        id: "c", title: "Day 2 Sync", calendarTitle: "Work",
        startDate: day2Event, endDate: day2Event.addingTimeInterval(1800),
        isAllDay: false, location: nil),
    ]

    let grouped = LiveCalendarStore.eventsByDay(items, startingFrom: base, days: 7, calendar: calendar)
    #expect(grouped.count == 7)
    #expect(grouped[0].events.map(\.id) == ["a", "b"])
    #expect(grouped[1].events.isEmpty)
    #expect(grouped[2].events.map(\.id) == ["c"])
  }

  @Test("MarkdownMessageParser parses diffs, pipe tables, headings, and blockquotes")
  func markdownMessageParserParsesRichBlocks() {
    let sample = """
      ## Summary
      > Keep changes small
      > and reversible.

      | Metric | Value |
      | --- | ---: |
      | Latency | 12ms |
      | Memory | 48MB |

      ```diff
      --- a/App.swift
      +++ b/App.swift
      @@ -1,2 +1,3 @@
       let a = 1
      -let b = 2
      +let b = 3
      +let c = 4
      ```
      """
    let blocks = MarkdownMessageParser.parse(sample)
    #expect(blocks.count == 4)
    #expect(blocks[0] == .heading(level: 2, text: "Summary"))
    #expect(blocks[1] == .quote("Keep changes small\nand reversible."))
    #expect(
      blocks[2] == .table(
        headers: ["Metric", "Value"],
        rows: [["Latency", "12ms"], ["Memory", "48MB"]]
      )
    )
    if case let .diff(added, removed, _, lines) = blocks[3] {
      #expect(added == 2)
      #expect(removed == 1)
      #expect(lines.count == 7)
      #expect(lines[0].kind == .header)
      #expect(lines[1].kind == .header)
      #expect(lines[2].kind == .hunk)
      #expect(lines[3].kind == .context)
      #expect(lines[4].kind == .removed)
      #expect(lines[5].kind == .added)
      #expect(lines[6].kind == .added)
    } else {
      Issue.record("Expected fourth Markdown block to be .diff")
    }
  }

  @Test("LiveChatModel.canQueueWhileWorking requires connected working state without recovery hold")
  func liveChatModelCanQueueWhileWorkingDefaultsFalse() {
    let model = LiveChatModel(defaults: freshDefaults())
    #expect(model.canQueueWhileWorking == false)
    #expect(model.canSend == false)
    model.draft = "Follow-up prompt"
    #expect(model.canQueueWhileWorking == false)
    #expect(model.canSend == false)
  }

  @Test("ToolPolicy enforces D118 mail tiers, untrusted send safety, and destroy confirmation")
  func toolPolicyEnforcesD118MailClasses() {
    let attendedNormal = ToolPolicyContext(
      permissionMode: .normal, rootOrigin: .user, grantsPresent: true, budgetAvailable: true)
    let attendedBypass = ToolPolicyContext(
      permissionMode: .bypass, rootOrigin: .user, grantsPresent: true, budgetAvailable: true)
    let untrustedBypass = ToolPolicyContext(
      permissionMode: .bypass, rootOrigin: .connectorEvent, grantsPresent: true,
      budgetAvailable: true)
    let unattendedNormal = ToolPolicyContext(
      permissionMode: .normal, rootOrigin: .routine, grantsPresent: true, budgetAvailable: true)

    for op in [ToolPolicyOperation.mailRead, .mailStage, .mailOrganize] {
      #expect(op.tier == 3)
      #expect(ToolPolicy.evaluate(op, context: attendedNormal).kind == .ask)
      #expect(ToolPolicy.evaluate(op, context: attendedBypass).kind == .allow)
      #expect(ToolPolicy.evaluate(op, context: untrustedBypass).kind == .deny)
      #expect(ToolPolicy.evaluate(op, context: unattendedNormal).kind == .deny)
    }

    #expect(ToolPolicyOperation.mailSend.tier == 4)
    let normalSend = ToolPolicy.evaluate(.mailSend, context: attendedNormal)
    #expect(normalSend.kind == .draft)
    #expect(normalSend.autoSend == false)
    let untrustedSend = ToolPolicy.evaluate(.mailSend, context: untrustedBypass)
    #expect(untrustedSend.kind == .draft)
    #expect(untrustedSend.autoSend == false)

    #expect(ToolPolicyOperation.mailDestroy.tier == 5)
    let bypassDestroy = ToolPolicy.evaluate(.mailDestroy, context: attendedBypass)
    #expect(bypassDestroy.kind == .ask)
    #expect(bypassDestroy.typedConfirmationRequired == true)
    #expect(ToolPolicy.evaluate(.mailDestroy, context: unattendedNormal).kind == .deny)
  }

  @Test("PersonalHostTools satisfy PolicyHooks invariants and untrusted mail exposure (D116)")
  func personalHostToolsSatisfyPolicyInvariants() {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("memoshi-host-tools-\(UUID().uuidString)", isDirectory: true)
    let tools = PersonalHostTools.all(dataDirectory: tempDir)
    #expect(tools.count >= 8)

    var names = Set<String>()
    for tool in tools {
      #expect(!tool.name.isEmpty)
      #expect(tool.name.utf8.count <= 64)
      #expect(names.insert(tool.name).inserted)
      #expect(tool.operation.tier < 4)
      if case .object = tool.parameters {
        // valid object schema
      } else {
        Issue.record("Tool \(tool.name) must declare an object parameter schema")
      }
      if tool.name.hasPrefix("mail_") {
        #expect(tool.outputExposure.untrusted == true)
        #expect(tool.outputExposure.privateData == true)
      }
    }
    #expect(names.contains("notes_list"))
    #expect(names.contains("notes_read"))
    #expect(names.contains("notes_save"))
    #expect(names.contains("mail_list"))
    #expect(names.contains("mail_search"))
    #expect(names.contains("mail_read"))
    #expect(names.contains("mail_draft"))
    #expect(names.contains("mail_organize"))
  }

  @Test("NotesHostStore enforces canonical containment and supports Markdown CRUD")
  func notesHostStoreContainmentAndCRUD() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("memoshi-notes-host-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = NotesHostStore(directoryURL: tempDir)
    for bad in ["../escape.md", "sub/dir.md", ".secret.md", "", ".."] {
      #expect(throws: RuntimeToolError.invalidArguments) {
        _ = try store.validatedURL(for: bad)
      }
    }

    let saved = try store.save(filename: "roadmap", content: "# Phase 1\n\nShip host tools.")
    #expect(saved.filename == "roadmap.md")
    #expect(saved.byteCount > 0)

    let (readName, readContent) = try store.read(filename: "roadmap.md")
    #expect(readName == "roadmap.md")
    #expect(readContent.contains("Ship host tools."))

    let listed = try store.list(query: "Phase 1")
    #expect(listed.count == 1)
    #expect(listed[0].title == "Phase 1")
  }

  @Test("MailHostStore persists staged drafts and reversible organize audit entries")
  func mailHostStoreDraftsAndOrganizeAudit() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("memoshi-mail-host-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = MailHostStore(dataDirectory: tempDir)
    let draft = MailDraftRecord(
      to: ["alex@example.com"],
      subject: "Weekly Sync",
      body: "Sharing notes from today's build."
    )
    try store.saveDraft(draft)
    let loaded = store.loadDrafts()
    #expect(loaded.count == 1)
    #expect(loaded[0].subject == "Weekly Sync")

    let audit = MailOrganizeAuditEntry(
      accountID: "acc-1", messageID: "msg-42", action: .archive)
    #expect(audit.inverseAction == .unarchive)
    try store.appendOrganizeAudit(audit)
    let history = store.loadOrganizeAudit()
    #expect(history.count == 1)
    #expect(history[0].messageID == "msg-42")
    #expect(history[0].inverseAction == .unarchive)

    try store.deleteDraft(id: draft.id)
    #expect(store.loadDrafts().isEmpty)
  }

  @Test("ApplePersonalTools.parseDate handles ISO-8601 and date-only strings")
  func applePersonalToolsParsesDates() {
    #expect(ApplePersonalTools.parseDate("2026-11-22T14:30:00Z") != nil)
    #expect(ApplePersonalTools.parseDate("2026-11-22T14:30:00.250Z") != nil)
    #expect(ApplePersonalTools.parseDate("2026-11-22") != nil)
    #expect(ApplePersonalTools.parseDate("2026-11-22T09:15") != nil)
    #expect(ApplePersonalTools.parseDate("not-a-date") == nil)
  }

  @Test("ToolPolicy enforces D121 Tier 3 rules for search.web")
  func toolPolicySearchWebTier3() {
    let attendedNormal = ToolPolicyContext(
      permissionMode: .normal, rootOrigin: .user, grantsPresent: true, budgetAvailable: true)
    let attendedBypass = ToolPolicyContext(
      permissionMode: .bypass, rootOrigin: .user, grantsPresent: true, budgetAvailable: true)
    let untrustedBypass = ToolPolicyContext(
      permissionMode: .bypass, rootOrigin: .connectorEvent, grantsPresent: true,
      budgetAvailable: true)
    let unattendedNormal = ToolPolicyContext(
      permissionMode: .normal, rootOrigin: .routine, grantsPresent: true, budgetAvailable: true)

    #expect(ToolPolicyOperation.searchWeb.tier == 3)
    #expect(ToolPolicy.evaluate(.searchWeb, context: attendedNormal).kind == .ask)
    #expect(ToolPolicy.evaluate(.searchWeb, context: attendedBypass).kind == .allow)
    #expect(ToolPolicy.evaluate(.searchWeb, context: untrustedBypass).kind == .deny)
    #expect(ToolPolicy.evaluate(.searchWeb, context: unattendedNormal).kind == .deny)
  }

  @Test("SearchAndConnectorTools satisfy PolicyHooks invariants and untrusted web exposure (D112)")
  func searchAndConnectorToolsSatisfyPolicyInvariants() {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("memoshi-search-tools-\(UUID().uuidString)", isDirectory: true)
    let tools = SearchAndConnectorTools.all(dataDirectory: tempDir)
    #expect(tools.count == 4)

    var names = Set<String>()
    for tool in tools {
      #expect(!tool.name.isEmpty)
      #expect(tool.name.utf8.count <= 64)
      #expect(names.insert(tool.name).inserted)
      #expect(tool.operation.tier < 4)
      if case .object = tool.parameters {
        // valid object schema
      } else {
        Issue.record("Tool \(tool.name) must declare an object parameter schema")
      }
      if tool.name == "web_search" || tool.name == "x_search" {
        #expect(tool.operation == .searchWeb)
        #expect(tool.outputExposure.untrusted == true)
        #expect(tool.outputExposure.privateData == false)
      }
    }
    #expect(names.contains("web_search"))
    #expect(names.contains("x_search"))
    #expect(names.contains("connectors_catalog"))
    #expect(names.contains("connector_request_connect"))
  }

  @Test("SearchAndConnectorTools formats numbered Markdown citation links")
  func searchCitationsMarkdownFormatting() {
    let md = SearchAndConnectorTools.formatCitationsMarkdown(
      header: "Exa search results for \"Swift 6\":",
      citations: [
        SearchCitation(
          title: "Swift 6 Release",
          url: "https://www.swift.org/blog/announcing-swift-6/",
          snippet: "Complete concurrency checking by default."
        )
      ]
    )
    #expect(md.contains("Exa search results"))
    #expect(md.contains("[Swift 6 Release](https://www.swift.org/blog/announcing-swift-6/)"))
    #expect(md.contains("Complete concurrency checking by default."))
  }

  @Test("ConnectorCatalogStore defaults to Exa, deduplicates Connect Cards, and tracks status (D112, D120)")
  func connectorCatalogStorePersistenceAndCards() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("memoshi-connector-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = ConnectorCatalogStore(dataDirectory: tempDir)
    #expect(store.loadSearchSettings().defaultWebProvider == .exa)
    #expect(ConnectorCatalogStore.connector(id: "GitHub")?.id == "mcp.github")
    #expect(ConnectorCatalogStore.connector(id: "search.exa")?.name == "Exa")

    try store.saveSearchSettings(SearchSettings(defaultWebProvider: .brave))
    #expect(store.loadSearchSettings().defaultWebProvider == .brave)

    let first = try store.enqueueConnectCard(
      connectorID: "mcp.github", reason: "Read open PRs", conversationID: "cht_01")
    let duplicate = try store.enqueueConnectCard(
      connectorID: "mcp.github", reason: "Second request", conversationID: "cht_01")
    #expect(first.id == duplicate.id)
    #expect(store.loadConnectCards().count == 1)

    try store.updateConnectCard(id: first.id, status: .connected)
    #expect(store.loadConnectCards().first?.status == .connected)
  }

  @Test("BotHandoffStore enforces 8-hop ceiling and filters by source or target conversation (D109, GR-06)")
  func botHandoffStoreAppendAndFilter() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("memoshi-handoff-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    #expect(BotHandoffStore.maxHopDepth == 8)
    let store = BotHandoffStore(dataDirectory: tempDir)
    let record = BotHandoffRecord(
      sourceBotID: "bot_a",
      sourceBotName: "Assistant",
      sourceConversationID: "cht_source",
      targetBotID: "bot_b",
      targetBotName: "Builder",
      targetConversationID: "cht_target",
      summary: "Review the latest Swift build failure.",
      hopDepth: 1
    )
    try store.append(record)

    #expect(store.loadAll().count == 1)
    #expect(store.load(forConversation: "cht_source").first?.id == record.id)
    #expect(store.load(forConversation: "cht_target").first?.id == record.id)
    #expect(store.load(forConversation: "cht_unrelated").isEmpty)
  }

  @Test("ModelProviderDefinition.claudeCode enforces D108 keyless subscription rules")
  func claudeCodeProviderDefinitionRules() {
    let claude = ModelProviderDefinition.named("claude-code")
    #expect(claude?.id == "claude-code")
    #expect(claude?.name == "Claude Code")
    #expect(claude?.requiresCredential == false)
    #expect(claude?.acceptsAPIKey == false)
    #expect(claude?.acceptsChatGPT == false)
    // D108: Subscription usage reports as price unknown (never billed per token, never free).
    #expect(claude?.usage(secretRef: nil) == .subscription)
    #expect(ModelProviderDefinition.all.contains { $0.id == "claude-code" })
  }

  @Test("ClaudeCodeLocator validates only the canonical URI or clean local file paths")
  func claudeCodeLocatorEndpointValidation() {
    #expect(ClaudeCodeLocator.isValidEndpoint(ClaudeCodeLocator.defaultEndpoint))
    #expect(ClaudeCodeLocator.isValidEndpoint("file:///opt/homebrew/bin/claude"))
    #expect(
      ClaudeCodeLocator.explicitBinaryPath(from: "file:///opt/homebrew/bin/claude")
        == "/opt/homebrew/bin/claude")
    #expect(ClaudeCodeLocator.explicitBinaryPath(from: ClaudeCodeLocator.defaultEndpoint) == nil)

    for invalid in [
      "https://api.anthropic.com",
      "http://127.0.0.1:8080/claude",
      "file:///opt/homebrew/../bin/claude",
      "file:///opt/homebrew/bin/claude?arg=1",
      "file:///opt/homebrew/bin/claude#frag",
      "/opt/homebrew/bin/claude",
      "",
    ] {
      #expect(ClaudeCodeLocator.isValidEndpoint(invalid) == false)
    }
  }

  @Test("ClaudeCodeTransport extracts prompts and parses Claude Code stream-json events (D108)")
  func claudeCodeTransportPromptAndStreamParsing() throws {
    let payload: [String: Any] = [
      "model": "claude-opus-4-6",
      "stream": true,
      "messages": [
        ["role": "system", "content": "You are concise."],
        ["role": "user", "content": "Summarize Swift 6 actors."],
      ],
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    let extracted = try ClaudeCodeTransport.extractPrompt(from: data)
    #expect(extracted.model == "claude-opus-4-6")
    #expect(extracted.systemPrompt == "You are concise.")
    #expect(extracted.prompt == "Summarize Swift 6 actors.")
    #expect(extracted.stream == true)

    let deltaLine =
      #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Actors isolate state."}}}"#
    let deltaEvent = ClaudeCodeTransport.parseStreamJSONLine(deltaLine)
    #expect(deltaEvent?.textDelta == "Actors isolate state.")

    let resultLine =
      #"{"type":"result","subtype":"success","is_error":false,"result":"Actors isolate state.","usage":{"input_tokens":120,"output_tokens":45}}"#
    let resultEvent = ClaudeCodeTransport.parseStreamJSONLine(resultLine)
    #expect(resultEvent?.isResult == true)
    #expect(resultEvent?.isError == false)
    #expect(resultEvent?.inputTokens == 120)
    #expect(resultEvent?.outputTokens == 45)

    let errorLine =
      #"{"type":"result","subtype":"error","is_error":true,"result":"Not authenticated"}"#
    let errorEvent = ClaudeCodeTransport.parseStreamJSONLine(errorLine)
    #expect(errorEvent?.isError == true)
    #expect(errorEvent?.errorMessage == "Not authenticated")
  }
}




