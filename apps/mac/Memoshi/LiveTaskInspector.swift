import Foundation
import MemoshiClient
import MemoshiProtocol
import Observation

/// A read-only attachment to one Pi child, plus an original-ID, explicitly requested Stop.
/// The existing event consumer asks for snapshots; no timer or second subscription runs here.
@MainActor
@Observable
final class LiveTaskInspector {
  private(set) var selectedTaskID: TaskID?
  private(set) var conversationID: ConversationID?
  private(set) var snapshot: TasksHistoryResult?
  private(set) var items: [TaskHistoryMessage] = []
  private(set) var nextBefore: String?
  private(set) var isLoading = false
  private(set) var isLoadingEarlier = false
  private(set) var isStopping = false
  private(set) var problem: String?
  var hasPendingStop: Bool { stopIntent != nil || corruptStop }
  var canRetryStop: Bool { stopIntent != nil && !isStopping && api != nil }
  /// A saved Stop that cannot be decoded, so it can never be retried.
  var hasUnreadableStop: Bool { corruptStop }
  /// Offered only while attached to the authenticated runtime, so current tasks can be checked.
  var canDiscardUnreadableStop: Bool { corruptStop && !isStopping && api != nil }
  var canStop: Bool {
    guard let task = snapshot?.task else { return false }
    return !hasPendingStop && !isStopping && [.queued, .running, .waiting].contains(task.status)
  }

  @ObservationIgnored private let defaults: UserDefaults
  private var api: (any MemoshiAPI)?
  @ObservationIgnored private var visible = false
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var needsRefresh = false
  @ObservationIgnored private var readTask: Task<Void, Never>?
  @ObservationIgnored private var stopTask: Task<Void, Never>?
  @ObservationIgnored private var stopIntent: TasksAbortParams?
  private var corruptStop = false
  private static let stopKey = "text-chat.task-stop-intent"

  init(defaults: UserDefaults) {
    self.defaults = defaults
    if let bytes = defaults.data(forKey: Self.stopKey) {
      do {
        stopIntent = try ProtocolCoding.makeDecoder(strict: true).decode(
          TasksAbortParams.self, from: bytes)
      } catch {
        corruptStop = true
        problem = String(
          localized:
            "The saved task Stop could not be read. New task Stops are blocked to avoid targeting different work."
        )
      }
    }
  }

  func attach(_ api: any MemoshiAPI) {
    self.api = api
    refresh()
  }

  func detach() {
    hide()
    stopTask?.cancel()
    api = nil
  }

  func show() {
    visible = true
    refresh()
  }

  func hide() {
    visible = false
    cancelRead()
  }

  func select(_ task: MemoshiTask?) {
    let task = task?.kind == .subagent ? task : nil
    guard selectedTaskID != task?.id else { return }
    cancelRead()
    selectedTaskID = task?.id
    conversationID = task?.conversationId
    snapshot = nil
    items = []
    nextBefore = nil
    if !hasPendingStop { problem = nil }
    refresh()
  }

  /// A resync replaces the attached child's history even when its position is below the old
  /// one, so the old snapshot is dropped and read again.
  func prepareForResync() {
    cancelRead()
    snapshot = nil
    items = []
    nextBefore = nil
    refresh()
  }

  func observe(_ envelope: EventEnvelope) {
    guard envelope.scope.taskId == selectedTaskID, selectedTaskID != nil else { return }
    refresh()
  }

  func refresh() {
    guard visible, selectedTaskID != nil, api != nil else { return }
    needsRefresh = true
    guard readTask == nil else { return }
    let token = generation
    readTask = Task { [weak self] in await self?.readLatest(generation: token) }
  }

  func loadEarlier() {
    guard visible, let id = selectedTaskID, let before = nextBefore,
      let api, readTask == nil
    else { return }
    let token = generation
    isLoadingEarlier = true
    readTask = Task { [weak self] in
      guard let self else { return }
      defer { self.finishRead(generation: token) }
      do {
        let page = try await api.call(
          TasksHistory.self, .init(taskId: id, before: before, limit: PageLimit(200)))
        guard token == self.generation, !Task.isCancelled else { return }
        let present = Set(self.items.map(\.entryId))
        self.items = page.items.filter { !present.contains($0.entryId) } + self.items
        self.nextBefore = page.nextBefore
        self.record(page)
      } catch is CancellationError {
      } catch { if token == self.generation { self.problem = Self.message(error) } }
    }
  }

  func stopSelected() {
    guard canStop, let id = selectedTaskID else { return }
    do {
      let intent = TasksAbortParams(requestId: try MemoshiClient.requestID(), taskId: id)
      defaults.set(try ProtocolCoding.makeEncoder().encode(intent), forKey: Self.stopKey)
      stopIntent = intent
      performStop(intent)
    } catch { problem = Self.message(error) }
  }

  func retryStop() {
    guard canRetryStop, let intent = stopIntent else { return }
    performStop(intent)
  }

  /// Removes only a record that can never be read or retried. Nothing is sent.
  func discardUnreadableStop() {
    guard canDiscardUnreadableStop else { return }
    defaults.removeObject(forKey: Self.stopKey)
    corruptStop = false
    problem = String(
      localized:
        "The unreadable saved task Stop was discarded without sending anything. Check the task list before stopping the same work again."
    )
  }

  private func performStop(_ intent: TasksAbortParams) {
    guard let api else { return }
    isStopping = true
    problem = nil
    stopTask = Task { [weak self] in
      guard let self else { return }
      defer {
        self.isStopping = false
        self.stopTask = nil
      }
      do {
        _ = try await api.call(TasksAbort.self, intent)
        self.clearStop()
        self.refresh()
      } catch let error as RPCError {
        self.problem = error.message
        if [.invalidParams, .conflict, .notFound, .forbidden, .methodNotFound].contains(error.kind)
        {
          self.clearStop()
        }
      } catch { self.problem = Self.message(error) }
    }
  }

  private func clearStop() {
    stopIntent = nil
    defaults.removeObject(forKey: Self.stopKey)
  }

  private func readLatest(generation token: Int) async {
    defer { finishRead(generation: token) }
    while needsRefresh, visible, token == generation, let id = selectedTaskID, let api {
      needsRefresh = false
      isLoading = true
      do {
        let page = try await api.call(
          TasksHistory.self, .init(taskId: id, limit: PageLimit(200)))
        guard token == generation, !Task.isCancelled else { return }
        if let snapshot, page.asOf.seq < snapshot.asOf.seq { continue }
        let incoming = Set(page.items.map(\.entryId))
        if let overlap = items.firstIndex(where: { incoming.contains($0.entryId) }) {
          items = Array(items[..<overlap]) + page.items
        } else {
          // A non-overlapping latest page is a fresh window, not evidence of gapless history.
          items = page.items
          nextBefore = page.nextBefore
        }
        record(page)
        if !hasPendingStop { problem = nil }
      } catch is CancellationError {
        return
      } catch {
        guard token == generation, !Task.isCancelled else { return }
        problem = Self.message(error)
        needsRefresh = false
        return
      }
    }
  }

  private func record(_ page: TasksHistoryResult) {
    guard page.task.id == selectedTaskID,
      page.asOf.seq >= snapshot?.asOf.seq ?? .min
    else { return }
    snapshot = page
  }

  private func finishRead(generation token: Int) {
    guard token == generation else { return }
    readTask = nil
    isLoading = false
    isLoadingEarlier = false
    if needsRefresh { refresh() }
  }

  private func cancelRead() {
    generation += 1
    readTask?.cancel()
    readTask = nil
    needsRefresh = false
    isLoading = false
    isLoadingEarlier = false
  }

  private static func message(_ error: any Error) -> String {
    if let error = error as? RPCError { return error.message }
    return String(
      localized:
        "The task connection changed. Refresh the snapshot or retry the saved Stop; no different work was targeted."
    )
  }
}
