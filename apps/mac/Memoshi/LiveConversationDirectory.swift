import AppCore
import Foundation
import MemoshiClient
import MemoshiProtocol
import Observation

/// Authoritative bot/conversation snapshots and one durable UI mutation intent. An uncertain
/// create or edit is retried with its original request ID, never replaced by a second create.
@MainActor
@Observable
final class LiveConversationDirectory {
  private(set) var conversations: [ChatSummary] = []
  private(set) var bots: [Bot] = []
  private(set) var isChanging = false
  private(set) var problem: String?
  private(set) var requestedSelection: ConversationID?
  private(set) var generation = 0
  private(set) var trash: [TrashedSession] = []
  private(set) var trashProblem: String?
  private(set) var isLoadingTrash = false
  /// The visible Trash list's position; nil while Trash has not been opened.
  private var trashAsOf: SnapshotWatermark?
  var hasPendingChange: Bool { intent != nil || corruptIntent }
  /// A saved change that cannot be decoded, so it can never be retried.
  var hasUnreadableChange: Bool { corruptIntent }
  /// Offered only after a directory snapshot is loaded, so the current list can be checked.
  var canDiscardUnreadableChange: Bool { corruptIntent && generation > 0 && !isChanging }

  private enum Intent: Codable {
    case createBot(BotsCreateParams)
    case updateBot(BotsUpdateParams)
    case createSession(SessionsCreateParams)
    case deleteSession(SessionsDeleteParams)
    case restoreSession(TrashRestoreParams)
    case purgeSessions(TrashEmptyParams)
  }

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var api: (any MemoshiAPI)?
  @ObservationIgnored private var intent: Intent?
  private var corruptIntent = false
  @ObservationIgnored private var action: Task<Void, Never>?
  private static let intentKey = "text-chat.conversation-change"

  init(defaults: UserDefaults) {
    self.defaults = defaults
    if let bytes = defaults.data(forKey: Self.intentKey) {
      do {
        intent = try ProtocolCoding.makeDecoder(strict: true).decode(Intent.self, from: bytes)
      } catch {
        corruptIntent = true
        problem = String(
          localized:
            "The saved bot change could not be read. Further changes are blocked to avoid duplicating an uncertain request."
        )
      }
    }
  }

  func attach(_ api: any MemoshiAPI) { self.api = api }

  func reload(minimumSeq: Int64 = 0) async throws {
    guard let api else { throw ClientError.notConnected }
    let listedBots = try await api.call(BotsList.self, BotsListParams())
    let listedChats = try await api.call(ChatsList.self, EmptyParams())
    guard listedBots.asOf.seq >= minimumSeq, listedChats.asOf.seq >= minimumSeq else {
      throw ClientError.protocolViolation("Conversation directory predates its event barrier")
    }
    bots = listedBots.items
    conversations = listedChats.items
    generation += 1
  }

  func createBot(name: String) {
    saveAndPerform { .createBot(.init(requestId: try MemoshiClient.requestID(), name: name)) }
  }

  func updateBot(_ bot: Bot, name: String, job: String, persona: String, model: ModelRef) {
    saveAndPerform {
      .updateBot(
        .init(
          requestId: try MemoshiClient.requestID(), botId: bot.id,
          patch: BotPatch(name: name, job: job, persona: persona, model: model),
          expectedRevision: bot.revision))
    }
  }

  func createSession(bot: BotID, title: String) {
    saveAndPerform {
      .createSession(.init(requestId: try MemoshiClient.requestID(), leadBotId: bot, title: title))
    }
  }

  func deleteSession(_ session: SessionID) {
    saveAndPerform {
      .deleteSession(.init(requestId: try MemoshiClient.requestID(), sessionId: session))
    }
  }

  func restoreSession(_ session: SessionID) {
    saveAndPerform {
      .restoreSession(.init(requestId: try MemoshiClient.requestID(), id: session))
    }
  }

  func purgeSessions(_ sessions: [SessionID]) {
    guard !sessions.isEmpty else { return }
    saveAndPerform {
      .purgeSessions(.init(requestId: try MemoshiClient.requestID(), ids: sessions))
    }
  }

  func loadTrash() async {
    guard !isLoadingTrash else { return }
    isLoadingTrash = true
    defer { isLoadingTrash = false }
    do {
      try await reloadTrash()
      trashProblem = nil
    } catch {
      trashProblem = Self.message(error)
    }
  }

  func reloadTrashIfVisible(minimumSeq: Int64) async throws {
    if trashAsOf != nil { try await reloadTrash(minimumSeq: minimumSeq) }
  }

  /// A resync replaces a visible Trash list even when its position is below the old one.
  func prepareForResync() {
    trashAsOf?.reset()
  }

  private func reloadTrash(minimumSeq: Int64 = 0) async throws {
    guard let api else { throw ClientError.notConnected }
    let listed = try await api.call(TrashList.self, EmptyParams())
    guard listed.asOf.seq >= minimumSeq else {
      throw ClientError.protocolViolation("Trash snapshot predates its event barrier")
    }
    var position = trashAsOf ?? SnapshotWatermark()
    guard position.advance(to: listed.asOf.seq) else { return }
    trash = listed.items
    trashAsOf = position
  }

  func retryChange() {
    guard !isChanging, !corruptIntent, let intent else { return }
    perform(intent)
  }

  /// Removes only a record that can never be read or retried. Nothing is sent.
  func discardUnreadableChange() {
    guard canDiscardUnreadableChange else { return }
    defaults.removeObject(forKey: Self.intentKey)
    corruptIntent = false
    problem = String(
      localized:
        "The unreadable saved change was discarded without sending anything. Check the current bots and Sessions before making the same change again."
    )
  }

  private func saveAndPerform(_ make: () throws -> Intent) {
    guard !isChanging, !hasPendingChange else {
      problem = String(
        localized: "Retry the saved change before starting another bot or Session change.")
      return
    }
    do {
      let intent = try make()
      defaults.set(try ProtocolCoding.makeEncoder().encode(intent), forKey: Self.intentKey)
      self.intent = intent
      perform(intent)
    } catch { problem = Self.message(error) }
  }

  private func perform(_ intent: Intent) {
    guard let api else {
      problem = String(localized: "Reconnect before retrying the saved change.")
      return
    }
    isChanging = true
    problem = nil
    requestedSelection = nil
    action = Task { [weak self] in
      guard let self else { return }
      defer {
        self.isChanging = false
        self.action = nil
      }
      do {
        let selection: ConversationID?
        switch intent {
        case .createBot(let params):
          let result = try await api.call(BotsCreate.self, params)
          selection = try ConversationID(result.chatId.rawValue)
        case .updateBot(let params):
          _ = try await api.call(BotsUpdate.self, params)
          selection = nil
        case .createSession(let params):
          let result = try await api.call(SessionsCreate.self, params)
          selection = try ConversationID(result.session.id.rawValue)
        case .deleteSession(let params):
          _ = try await api.call(SessionsDelete.self, params)
          selection = nil
        case .restoreSession(let params):
          let result = try await api.call(TrashRestore.self, params)
          selection = try ConversationID(result.session.id.rawValue)
        case .purgeSessions(let params):
          _ = try await api.call(TrashEmpty.self, params)
          selection = nil
        }
        self.clearIntent()
        try await self.reload()
        if self.trashAsOf != nil { try await self.reloadTrash() }
        self.requestedSelection = selection
      } catch let error as RPCError {
        self.problem = error.message
        // These refusals are definite: nothing was applied, so no saved change remains.
        if [.invalidParams, .busy, .conflict, .notFound, .forbidden, .methodNotFound].contains(
          error.kind)
        {
          self.clearIntent()
        }
      } catch {
        self.problem = Self.message(error)
      }
    }
  }

  private func clearIntent() {
    intent = nil
    defaults.removeObject(forKey: Self.intentKey)
  }

  private static func message(_ error: any Error) -> String {
    if let error = error as? RPCError { return error.message }
    return String(
      localized:
        "The connection changed. Reload the directory or retry the saved change; no second request was created."
    )
  }
}
