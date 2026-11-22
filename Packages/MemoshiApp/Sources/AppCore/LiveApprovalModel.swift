import Foundation
import MemoshiProtocol
import Observation

/// The two decisions this development profile can send.
public enum ApprovalReviewAction: String, Codable, Hashable, Sendable {
  case allowOnce = "allow_once"
  case deny
}

/// A snapshot or event the engine produced contradicts the projection's own invariants.
public enum ProjectionError: Error, Equatable, Sendable {
  case protocolViolation(String)
}

/// The only approval response data written to preferences. No arguments, targets, notes or proof.
private struct PendingApprovalResponse: Codable, Hashable, Sendable {
  let requestId: ULID
  let cardId: CardID
  let action: ApprovalReviewAction

  var params: CardsRespondParams {
    CardsRespondParams(
      requestId: requestId, cardId: cardId, action: action.rawValue, surface: .ui)
  }
}

/// What the authoritative card and approval records say about one decision. Display copy and
/// actions belong to each platform's card view.
public enum ApprovalReviewState: Hashable, Sendable {
  case pending
  /// Both records are still pending after the deadline; the runner has not expired them yet.
  case deadlinePassed
  /// The card resolved with Allow once; execution is not confirmed by the decision.
  case allowedOnce
  /// The approval is allowed while its card is still pending.
  case allowed
  case denied
  /// Resolved with another, or no, recorded action.
  case resolved(String?)
  case expired
  case canceled
  /// An unrecognized card state; decisions stay disabled.
  case unsupported
}

/// One approval card and its matching approval record.
public struct ApprovalReviewEntry: Identifiable, Hashable, Sendable {
  /// The authoritative approval card.
  public let card: Card
  /// Its approval record, once loaded.
  public let approval: Approval?
  /// The sanitized arguments, pretty-printed for review.
  public let argumentsPreview: String?

  /// The card's identity.
  public var id: CardID { card.id }
  /// The decision deadline, Unix milliseconds.
  public var expiresAt: Int64? { approval?.expiresAt ?? card.expiresAt }
  /// Both records still await a decision.
  public var isPending: Bool {
    card.status == .pending && (approval == nil || approval?.status == .pending)
  }
  /// The card names exactly this approval, conversation, bot, task and deadline.
  public var hasValidBinding: Bool {
    guard let approval else { return false }
    return card.subject == ObjectRef(kind: "approval", id: approval.id.rawValue)
      && card.conversationId == approval.conversationId && card.botId == approval.botId
      && card.taskId == approval.taskId && card.expiresAt == approval.expiresAt
  }

  /// Whether the deadline has passed at `now`; a missing deadline counts as passed.
  public func isExpired(at now: Int64) -> Bool {
    expiresAt.map { $0 <= now } ?? true
  }

  /// The decision state at `now`, Unix milliseconds.
  public func state(at now: Int64) -> ApprovalReviewState {
    switch card.status {
    case .resolved:
      switch card.outcome?.action {
      case "allow_once": return .allowedOnce
      case "deny": return .denied
      case let action: return .resolved(action)
      }
    case .expired:
      return .expired
    case .canceled:
      return .canceled
    case .pending:
      switch approval?.status {
      case .expired: return .expired
      case .canceled: return .canceled
      case .denied: return .denied
      case .allowed: return .allowed
      default: return isExpired(at: now) ? .deadlinePassed : .pending
      }
    case .unknown:
      return .unsupported
    }
  }
}

/// Cards that share a conversation, turn and root tool call.
public struct ApprovalReviewGroup: Identifiable, Hashable, Sendable {
  /// The conversation, turn and root call a group shares.
  public struct ID: Hashable, Sendable {
    /// The owning conversation.
    public let conversationId: ConversationID
    /// The owning turn, when known.
    public let taskId: TaskID?
    /// The outermost related tool call.
    public let rootCallId: String
  }

  /// The group's identity.
  public let id: ID
  /// The group's cards in creation order.
  public var entries: [ApprovalReviewEntry]
}

/// The one shared approval/card projection (protocol.md, current implementation scope): it loads
/// every snapshot page and applies approval/card changes before its consumer acknowledges them.
/// The Mac feeds it from its socket client and the iPhone and iPad host from the in-process
/// engine; both call the engine through ``MemoshiAPI``.
@MainActor
@Observable
public final class LiveApprovalModel {
  /// Every approval card, in creation order.
  public private(set) var entries: [ApprovalReviewEntry] = []
  /// All groups, for transcript placement.
  public private(set) var timelineGroups: [ApprovalReviewGroup] = []
  /// Groups with cards still awaiting a decision.
  public private(set) var pendingGroups: [ApprovalReviewGroup] = []
  /// Groups with decided, expired or canceled cards.
  public private(set) var recentGroups: [ApprovalReviewGroup] = []
  /// Saved decisions or issues whose card is not in the loaded state.
  public private(set) var unmatchedResponseIDs: [CardID] = []
  /// Pending, unexpired cards that need the user.
  public private(set) var pendingCount = 0
  /// The clock reading of the latest deadline update, Unix milliseconds.
  public private(set) var now = Int64(Date().timeIntervalSince1970 * 1_000)
  /// Whether the engine connection can currently accept decisions.
  public private(set) var isConnected = false
  /// Whether a complete snapshot has ever loaded.
  public private(set) var hasLoaded = false
  /// Whether the loaded snapshot is current; decisions need it.
  public private(set) var isFresh = false
  /// Whether a snapshot load is in flight.
  public private(set) var isLoading = false
  /// A synchronization problem to show the user.
  public private(set) var problem: String?
  /// Per-card refusal or delivery problems.
  public private(set) var issues: [CardID: String] = [:]
  /// Per-card receipts to show the user.
  public private(set) var notices: [CardID: String] = [:]
  /// Cards whose decision is being sent.
  public private(set) var sending: Set<CardID> = []
  /// Why no card can be answered while the projection is not connected or not current, for
  /// every pending card to show beside its disabled decisions; nil once it is synchronized.
  public var synchronizationNotice: String? {
    if !isConnected {
      return String(
        localized:
          "Not connected to the runner. Decisions are disabled until review state has reloaded.",
        bundle: #bundle)
    }
    guard !(hasLoaded && isFresh) else { return nil }
    return isLoading
      ? String(
        localized: "Review state is reloading. Decisions are disabled until it has loaded.",
        bundle: #bundle)
      : String(localized: "Review is not synchronized. Decisions are disabled.", bundle: #bundle)
  }

  private var pending: [CardID: PendingApprovalResponse] = [:]
  private var blocked: Set<CardID> = []
  private var pendingCorrupt = false

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let makeRequestID: @Sendable () throws -> ULID
  @ObservationIgnored private var client: (any MemoshiAPI)?
  @ObservationIgnored private var approvals: [ApprovalID: Approval] = [:]
  @ObservationIgnored private var cards: [CardID: Card] = [:]
  @ObservationIgnored private var approvalVersions: [ApprovalID: Int64] = [:]
  @ObservationIgnored private var cardVersions: [CardID: Int64] = [:]
  @ObservationIgnored private var approvalsAsOf: Int64 = 0
  @ObservationIgnored private var cardsAsOf: Int64 = 0
  @ObservationIgnored private var snapshotGeneration = 0
  @ObservationIgnored private var loadsInFlight = 0
  @ObservationIgnored private var loadsStarted = 0
  @ObservationIgnored private var newestCompletedLoad = 0
  @ObservationIgnored private var actionTasks: [CardID: Task<Void, Never>] = [:]
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  @ObservationIgnored private var refreshesStarted = 0
  @ObservationIgnored private var expiryTask: Task<Void, Never>?

  /// Restores saved, unconfirmed decisions. `makeRequestID` is the caller's canonical ULID
  /// generator for new decisions; a retry always reuses the saved key.
  public init(
    defaults: UserDefaults = .standard, makeRequestID: @escaping @Sendable () throws -> ULID
  ) {
    self.defaults = defaults
    self.makeRequestID = makeRequestID
    if let bytes = defaults.data(forKey: "approval-review.pending-responses") {
      do {
        let saved = try ProtocolCoding.makeDecoder(strict: true).decode(
          [PendingApprovalResponse].self, from: bytes)
        for intent in saved {
          guard pending[intent.cardId] == nil else {
            throw ProjectionError.protocolViolation("Duplicate saved approval response")
          }
          pending[intent.cardId] = intent
        }
      } catch {
        pendingCorrupt = true
        problem = String(
          localized:
            "The saved approval delivery record could not be read. Decisions are blocked to avoid sending a different answer to an uncertain request.",
          bundle: #bundle
        )
      }
    }
    rebuildUnmatchedResponses()
  }

  /// Sets the engine that receives decisions and the reload a reconnect starts; other snapshots
  /// arrive through `reload`.
  public func attach(_ client: any MemoshiAPI) {
    self.client = client
  }

  /// Only an actually connected engine may receive decisions; leaving it marks state stale.
  /// Returning to it with a loaded but stale projection reloads every snapshot page once, as
  /// Reload Review does, so a replaced connection (a restarted helper) needs no action from the
  /// person. The first snapshot stays the host's bootstrap. Reports that the engine is still
  /// connected start nothing, so a failed reload is not repeated.
  public func connectionChanged(isConnected: Bool) {
    let reconnected = isConnected && !self.isConnected
    if !isConnected { isFresh = false }
    self.isConnected = isConnected
    if reconnected && hasLoaded && !isFresh { refresh() }
  }

  /// Cancels in-flight decisions, refreshes and deadline updates, and marks state stale.
  public func stop() {
    for work in actionTasks.values { work.cancel() }
    refreshTask?.cancel()
    expiryTask?.cancel()
    actionTasks.removeAll()
    refreshTask = nil
    expiryTask = nil
    isFresh = false
  }

  /// Every page has its own read transaction. Retain the minimum watermark, not the last
  /// page's head: an intervening update to an earlier page still needs its event applied.
  public func reload(
    _ client: some MemoshiAPI, minimumSeq: Int64 = 0, replacing: Bool = false
  ) async throws {
    try await load(client, minimumSeq: minimumSeq, replacing: replacing, failureMarksStale: true)
  }

  /// `failureMarksStale` is false for the refresh that follows this model's own request: its
  /// failure makes the loaded state no older, and the consumer still applies every change.
  private func load(
    _ client: some MemoshiAPI, minimumSeq: Int64, replacing: Bool, failureMarksStale: Bool
  ) async throws {
    if replacing {
      snapshotGeneration += 1
      hasLoaded = false
      isFresh = false
      approvals.removeAll()
      cards.removeAll()
      approvalVersions.removeAll()
      cardVersions.removeAll()
      approvalsAsOf = 0
      cardsAsOf = 0
      rebuildProjection()
    }
    let generation = snapshotGeneration
    loadsStarted += 1
    let number = loadsStarted
    loadsInFlight += 1
    isLoading = true
    defer {
      loadsInFlight -= 1
      isLoading = loadsInFlight != 0
    }
    do {
      var freshApprovals: [ApprovalID: Approval] = [:]
      var freshApprovalVersions: [ApprovalID: Int64] = [:]
      var approvalFloor = Int64.max
      var cursor: String?
      var seenCursors: Set<String> = []
      repeat {
        let page = try await client.call(
          ApprovalsList.self, .init(cursor: cursor, limit: PageLimit(200)))
        guard page.asOf.seq >= minimumSeq else {
          throw ProjectionError.protocolViolation(
            "Approval snapshot predates application barrier")
        }
        approvalFloor = min(approvalFloor, page.asOf.seq)
        for approval in page.items {
          freshApprovals[approval.id] = approval
          freshApprovalVersions[approval.id] = page.asOf.seq
        }
        cursor = page.nextCursor
        if let cursor, !seenCursors.insert(cursor).inserted {
          throw ProjectionError.protocolViolation("Approval page cursor did not advance")
        }
      } while cursor != nil

      // Reading cards after approvals ensures each approval already read can have its
      // atomically-created card projected. Newer cards wait for their approval-domain event.
      var freshCards: [CardID: Card] = [:]
      var freshCardVersions: [CardID: Int64] = [:]
      var cardFloor = Int64.max
      cursor = nil
      seenCursors.removeAll(keepingCapacity: true)
      repeat {
        let page = try await client.call(
          CardsList.self, .init(cursor: cursor, limit: PageLimit(200)))
        guard page.asOf.seq >= minimumSeq else {
          throw ProjectionError.protocolViolation("Card snapshot predates application barrier")
        }
        cardFloor = min(cardFloor, page.asOf.seq)
        for card in page.items {
          freshCards[card.id] = card
          freshCardVersions[card.id] = page.asOf.seq
        }
        cursor = page.nextCursor
        if let cursor, !seenCursors.insert(cursor).inserted {
          throw ProjectionError.protocolViolation("Card page cursor did not advance")
        }
      } while cursor != nil
      let presentedApprovalIDs = Set(
        freshCards.values.compactMap { card -> String? in
          guard card.kind == .approval, card.subject?.kind == "approval" else { return nil }
          return card.subject?.id
        })
      guard
        freshApprovals.values.allSatisfy({
          $0.status != .pending || presentedApprovalIDs.contains($0.id.rawValue)
        })
      else {
        throw ProjectionError.protocolViolation("Pending approval has no durable card projection")
      }
      try Task.checkCancellation()
      guard generation == snapshotGeneration else { throw CancellationError() }
      // Response receipts may land while a page read is suspended. Never overwrite a newer
      // per-record receipt with an older page or promote one receipt to a domain watermark.
      for (id, approval) in freshApprovals {
        let version = freshApprovalVersions[id] ?? approvalFloor
        if version >= (approvalVersions[id] ?? 0) {
          approvals[id] = approval
          approvalVersions[id] = version
        }
      }
      for id in approvals.keys where freshApprovals[id] == nil {
        if (approvalVersions[id] ?? 0) <= approvalFloor {
          approvals.removeValue(forKey: id)
          approvalVersions.removeValue(forKey: id)
        }
      }
      for (id, card) in freshCards {
        let version = freshCardVersions[id] ?? cardFloor
        if version >= (cardVersions[id] ?? 0) {
          cards[id] = card
          cardVersions[id] = version
        }
      }
      for id in cards.keys where freshCards[id] == nil {
        if (cardVersions[id] ?? 0) <= cardFloor {
          cards.removeValue(forKey: id)
          cardVersions.removeValue(forKey: id)
        }
      }
      approvalsAsOf = max(approvalsAsOf, approvalFloor)
      cardsAsOf = max(cardsAsOf, cardFloor)
      newestCompletedLoad = max(newestCompletedLoad, number)
      hasLoaded = true
      isFresh = true
      if !pendingCorrupt { problem = nil }
      rebuildProjection()
    } catch {
      // A read that fails after a later-started one loaded leaves that newer state current.
      if generation == snapshotGeneration, failureMarksStale, number > newestCompletedLoad {
        isFresh = false
        if !pendingCorrupt { problem = Self.snapshotMessage(error) }
      }
      throw error
    }
  }

  /// Called before the consumer acknowledges a durable fact, independent of the selected
  /// chat/route. One domain's newer snapshot must not hide another domain's update.
  public func apply(_ envelope: EventEnvelope, client: some MemoshiAPI) async throws {
    let seq = envelope.seq ?? 0
    let approvalChanged = envelope.type.hasPrefix("approval.") && seq > approvalsAsOf
    let cardChanged = envelope.type.hasPrefix("card.") && seq > cardsAsOf
    if approvalChanged || cardChanged {
      try await reload(client, minimumSeq: seq)
    }
  }

  /// Reloads every snapshot page once, if none is already loading.
  public func refresh() {
    guard let client, refreshTask == nil else { return }
    refreshesStarted += 1
    let number = refreshesStarted
    refreshTask = Task { [weak self, client] in
      guard let self else { return }
      // A refresh `stop` canceled ends after the one a reconnect then started; keep that handle.
      defer { if self.refreshesStarted == number { self.refreshTask = nil } }
      do { try await self.reload(client) } catch {}
    }
  }

  /// Whether a fresh, connected projection may send a first decision for this pending card.
  public func canRespond(to entry: ApprovalReviewEntry) -> Bool {
    guard isConnected, isFresh, hasLoaded, !pendingCorrupt,
      entry.hasValidBinding, entry.isPending, !entry.isExpired(at: Self.milliseconds()),
      (0...3).contains(entry.approval?.tier.rawValue ?? 4), entry.argumentsPreview != nil,
      cards[entry.id]?.status == .pending, let approvalID = entry.approval?.id,
      approvals[approvalID]?.status == .pending
    else { return false }
    return pending[entry.id] == nil && !sending.contains(entry.id) && !blocked.contains(entry.id)
  }

  /// Whether a saved decision for this card awaits its receipt.
  public func hasUnconfirmedResponse(for id: CardID) -> Bool { pending[id] != nil }

  /// The saved, unconfirmed decision for this card.
  public func pendingAction(for id: CardID) -> ApprovalReviewAction? { pending[id]?.action }

  /// Whether the saved decision may be resent with its original request ID.
  public func canRetry(_ entry: ApprovalReviewEntry) -> Bool {
    isConnected && isFresh && hasLoaded && !pendingCorrupt
      && pending[entry.id] != nil && !sending.contains(entry.id)
      && (!entry.isPending || !entry.isExpired(at: Self.milliseconds()))
  }

  /// Whether a saved decision whose card is not loaded may be resent to recover its receipt.
  public func canRetrySavedResponse(for id: CardID) -> Bool {
    isConnected && isFresh && hasLoaded && !pendingCorrupt
      && cards[id] == nil && pending[id] != nil && !sending.contains(id)
  }

  /// Resends the saved decision for a card that is not loaded, unchanged.
  public func retrySavedResponse(for id: CardID) {
    guard canRetrySavedResponse(for: id), let intent = pending[id] else { return }
    perform(intent)
  }

  /// Saves the decision with a new request ID, then sends it once.
  public func respond(to entry: ApprovalReviewEntry, action: ApprovalReviewAction) {
    guard canRespond(to: entry) else { return }
    do {
      let intent = PendingApprovalResponse(
        requestId: try makeRequestID(), cardId: entry.id, action: action)
      var next = pending
      next[entry.id] = intent
      try persist(next)
      perform(intent)
    } catch {
      issues[entry.id] = String(
        localized: "The decision could not be recorded locally. No answer was sent.",
        bundle: #bundle)
    }
  }

  /// Resends the saved decision with its original request ID.
  public func retry(_ entry: ApprovalReviewEntry) {
    guard canRetry(entry), let intent = pending[entry.id] else { return }
    perform(intent)
  }

  private func persist(_ next: [CardID: PendingApprovalResponse]) throws {
    if next.isEmpty {
      defaults.removeObject(forKey: "approval-review.pending-responses")
    } else {
      let saved = next.values.sorted { $0.cardId.rawValue < $1.cardId.rawValue }
      let bytes = try ProtocolCoding.makeEncoder().encode(saved)
      defaults.set(bytes, forKey: "approval-review.pending-responses")
    }
    pending = next
    rebuildUnmatchedResponses()
  }

  private func clearPending(_ id: CardID) throws {
    var next = pending
    next.removeValue(forKey: id)
    try persist(next)
  }

  private func perform(_ intent: PendingApprovalResponse) {
    guard let client, actionTasks[intent.cardId] == nil else { return }
    let id = intent.cardId
    sending.insert(id)
    issues.removeValue(forKey: id)
    notices.removeValue(forKey: id)
    actionTasks[id] = Task { [weak self, client] in
      guard let self else { return }
      defer {
        self.sending.remove(id)
        self.actionTasks.removeValue(forKey: id)
      }
      do {
        let result = try await client.call(CardsRespond.self, intent.params)
        guard result.card.id == id,
          result.queued == true
            || result.card.status == .resolved
              && result.card.outcome?.action == intent.action.rawValue
        else {
          throw ProjectionError.protocolViolation(
            "Approval receipt does not match the saved answer")
        }
        self.apply(result)
        if result.queued == true {
          self.notices[id] = String(
            localized:
              "The runner has not received this answer. It is queued only until the card expires; permission and execution are not confirmed.",
            bundle: #bundle
          )
        } else {
          self.notices[id] =
            result.replayed == true
            ? String(
              localized:
                "The original decision receipt was recovered. No second answer was created.",
              bundle: #bundle)
            : String(
              localized: "The runner recorded this decision. It does not confirm tool execution.",
              bundle: #bundle)
          do { try self.clearPending(id) } catch {
            self.issues[id] = String(
              localized:
                "The decision receipt was received, but the saved delivery record could not be cleared. Any retry keeps its original identity.",
              bundle: #bundle
            )
          }
        }
        // A failed read after a successful receipt must not be reported as uncertain delivery,
        // and must not disable the other cards: nothing here is older than before.
        do {
          try await self.load(
            client, minimumSeq: result.writtenSeq, replacing: false, failureMarksStale: false)
        } catch {
          self.issues[id] = String(
            localized:
              "The decision receipt was received, but current review state could not be refreshed.",
            bundle: #bundle)
        }
      } catch let error as RPCError {
        self.issues[id] = Self.responseMessage(error)
        if !error.data.retryable
          && ![
            .timeout, .internalError, .storageFailed, .leaseFenced, .deviceUnreachable,
            .hostUnavailable, .shuttingDown,
          ].contains(error.kind)
        {
          do { try self.clearPending(id) } catch {
            self.issues[id] = String(
              localized:
                "The runner refused this answer, but its local delivery record could not be cleared. Retry keeps the original request identity.",
              bundle: #bundle
            )
          }
        }
        if [
          .deviceAuthRequired, .capabilityMissing, .methodNotFound, .forbidden, .unauthorized,
          .idempotencyConflict, .invalidParams, .invalidRequest, .invalidState, .conflict,
          .notFound, .updateRequired,
        ].contains(error.kind) {
          self.blocked.insert(id)
        }
        do {
          try await self.load(client, minimumSeq: 0, replacing: false, failureMarksStale: false)
        } catch {}
      } catch {
        self.issues[id] = String(
          localized:
            "Delivery is unconfirmed. Reconnect and retry the same decision to recover its receipt; a different answer will not be sent.",
          bundle: #bundle
        )
      }
    }
  }

  private func apply(_ result: CardsRespondResult) {
    let id = result.card.id
    if result.writtenSeq >= (cardVersions[id] ?? 0) {
      cards[id] = result.card
      cardVersions[id] = result.writtenSeq
    }
    if let effect = result.effects, var approval = approvals[effect.approvalId],
      result.writtenSeq >= (approvalVersions[effect.approvalId] ?? 0)
    {
      approval.status = effect.status
      approval.scope = effect.scope
      approval.grantId = effect.grantId
      approvals[approval.id] = approval
      approvalVersions[approval.id] = result.writtenSeq
    }
    rebuildProjection()
  }

  private func rebuildProjection() {
    entries = cards.values.filter { $0.kind == .approval }.map { card in
      let approval = card.subject.flatMap { subject -> Approval? in
        guard subject.kind == "approval", let id = try? ApprovalID(subject.id) else { return nil }
        return approvals[id]
      }
      return ApprovalReviewEntry(
        card: card, approval: approval,
        argumentsPreview: approval.flatMap { Self.preview($0.argsPreview) })
    }.sorted {
      $0.card.createdAt == $1.card.createdAt
        ? $0.id.rawValue < $1.id.rawValue : $0.card.createdAt < $1.card.createdAt
    }
    timelineGroups = groups(entries)
    pendingGroups = timelineGroups.compactMap { group in
      let pending = group.entries.filter(\.isPending)
      return pending.isEmpty ? nil : ApprovalReviewGroup(id: group.id, entries: pending)
    }
    recentGroups = timelineGroups.compactMap { group in
      let recent = group.entries.filter { !$0.isPending }
      return recent.isEmpty ? nil : ApprovalReviewGroup(id: group.id, entries: recent)
    }
    rebuildUnmatchedResponses()
    updateDeadline()
  }

  private func rebuildUnmatchedResponses() {
    let ids = Set(pending.keys).union(issues.keys)
    unmatchedResponseIDs = ids.filter { cards[$0] == nil }
      .sorted { $0.rawValue < $1.rawValue }
  }

  private func groups(_ entries: [ApprovalReviewEntry]) -> [ApprovalReviewGroup] {
    let callEntries = Dictionary(grouping: self.entries) { entry in
      ApprovalReviewGroup.ID(
        conversationId: entry.card.conversationId, taskId: entry.card.taskId,
        rootCallId: entry.approval?.toolCallId ?? entry.id.rawValue)
    }
    var grouped: [ApprovalReviewGroup] = []
    var indices: [ApprovalReviewGroup.ID: Int] = [:]
    for entry in entries {
      var root = entry.approval?.toolCallId ?? entry.id.rawValue
      var parent = entry.approval?.parentToolCallId
      var seen: Set<String> = [root]
      while let next = parent, seen.insert(next).inserted {
        root = next
        let key = ApprovalReviewGroup.ID(
          conversationId: entry.card.conversationId, taskId: entry.card.taskId, rootCallId: next)
        parent = callEntries[key]?.first?.approval?.parentToolCallId
      }
      let key = ApprovalReviewGroup.ID(
        conversationId: entry.card.conversationId, taskId: entry.card.taskId, rootCallId: root)
      if let index = indices[key] {
        grouped[index].entries.append(entry)
      } else {
        indices[key] = grouped.count
        grouped.append(ApprovalReviewGroup(id: key, entries: [entry]))
      }
    }
    return grouped
  }

  private func updateDeadline() {
    now = Self.milliseconds()
    pendingCount = entries.reduce(into: 0) { count, entry in
      if entry.isPending && entry.card.needsYou && !entry.isExpired(at: now) { count += 1 }
    }
    scheduleExpiry()
  }

  private func scheduleExpiry() {
    expiryTask?.cancel()
    guard
      let deadline = entries.compactMap({ entry in
        entry.isPending && !entry.isExpired(at: now) ? entry.expiresAt : nil
      }).min()
    else {
      expiryTask = nil
      return
    }
    expiryTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(max(1, deadline - Self.milliseconds())))
        try Task.checkCancellation()
        self?.updateDeadline()
      } catch {}
    }
  }

  private static func preview(_ value: JSONValue) -> String? {
    let encoder = ProtocolCoding.makeEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func milliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  private static func snapshotMessage(_ error: any Error) -> String {
    String(
      localized:
        "Approval state could not be synchronized. No decision is enabled until authoritative approvals and cards have loaded.",
      bundle: #bundle
    )
  }

  private static func responseMessage(_ error: RPCError) -> String {
    switch error.kind {
    case .cardResolved:
      return String(
        localized:
          "This card was already decided. The first valid answer wins; current state is being reloaded.",
        bundle: #bundle
      )
    case .cardExpired:
      return String(
        localized: "This approval expired. The answer was not accepted.", bundle: #bundle)
    case .canceled:
      return String(
        localized: "The call was canceled. This answer did not authorize it.", bundle: #bundle)
    case .deviceAuthRequired:
      return String(
        localized:
          "This tier requires device-owner authentication, which this development profile does not provide.",
        bundle: #bundle
      )
    case .capabilityMissing, .methodNotFound:
      return String(
        localized:
          "The connected runtime does not support this decision. No permission was granted.",
        bundle: #bundle)
    case .forbidden, .unauthorized:
      return String(
        localized:
          "The authenticated app is not authorized to answer this card. No permission was granted.",
        bundle: #bundle)
    case .idempotencyConflict:
      return String(
        localized:
          "The saved request identity conflicts with another request. A new identity will not be substituted.",
        bundle: #bundle
      )
    case .notFound:
      return String(
        localized: "This card is no longer available. No answer was accepted.", bundle: #bundle)
    case .leaseFenced, .deviceUnreachable, .hostUnavailable, .shuttingDown:
      return String(
        localized:
          "The owning runner is unavailable. The decision is not confirmed; any retry keeps the original identity.",
        bundle: #bundle
      )
    case .timeout, .internalError, .storageFailed:
      return String(
        localized:
          "The runner could not confirm delivery. Retry only the same saved decision to recover its receipt.",
        bundle: #bundle
      )
    default:
      return String(
        localized:
          "The runner refused this decision. No substitute action or broader permission was requested.",
        bundle: #bundle
      )
    }
  }
}
