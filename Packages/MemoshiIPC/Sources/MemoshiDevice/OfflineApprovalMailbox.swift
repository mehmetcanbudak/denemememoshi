import CryptoKit
import Foundation
import MemoshiProtocol

/// A replica's encrypted pending approval answers. This is delivery state only: the confirmed
/// runner must re-read the real card, expiry, grants and owner proof before applying any answer.
/// It neither decides policy nor acknowledges a successful tool/approval operation itself.
public actor OfflineApprovalMailbox {
  /// An answer retains its original method parameters and its original card's deadline.
  public struct Answer: Codable, Hashable, Sendable {
    /// Conversation whose confirmed runner must revalidate and apply the answer.
    public var conversationID: ConversationID
    /// Original response identity and decision, retained unchanged for idempotent delivery.
    public var params: CardsRespondParams
    /// Original card deadline in Unix milliseconds, not a renewed offline delivery lease.
    public var expiresAt: Int64
  }

  /// A durable, user-visible explanation; consumers acknowledge only after displaying it.
  public struct ExpiryNotice: Codable, Hashable, Sendable {
    /// Original response request identity used to acknowledge this notice.
    public var requestID: ULID
    /// Card whose queued answer was withheld after its deadline.
    public var cardID: CardID
    /// Original card deadline in Unix milliseconds, not the time expiry was discovered.
    public var expiredAt: Int64
  }

  private enum Record: Codable {
    case queued(Answer)
    case expired(ExpiryNotice)
    case delivered(ULID)
    case noticeDisplayed(ULID)
    /// Written alone by ``OfflineApprovalMailbox/erase()``; nothing is ever written after it.
    case erased
  }

  private var journal: DeviceStateJournal
  private let url: URL
  private let key: SymmetricKey
  private static let purpose = "memoshi.offline-approvals.v1"
  private var answers: [ULID: Answer] = [:]
  private var notices: [ULID: ExpiryNotice] = [:]
  private var known: [ULID: Answer] = [:]
  private var failed = false
  private var closed = false
  private var erased = false

  /// The device identity encrypts this local mailbox; a missing/wrong key refuses reopen.
  public init(identity: DeviceIdentity, directory: URL) throws {
    url = directory.appendingPathComponent("approval-answers.jsonl")
    key = try identity.stateEncryptionKey()
    journal = try DeviceStateJournal(url: url, key: key, purpose: Self.purpose)
    for bytes in journal.takeRecovered() {
      switch try JSONDecoder().decode(Record.self, from: bytes) {
      case .queued(let answer):
        known[answer.params.requestId] = answer
        answers[answer.params.requestId] = answer
      case .expired(let notice):
        answers[notice.requestID] = nil
        notices[notice.requestID] = notice
      case .delivered(let requestID): answers[requestID] = nil
      case .noticeDisplayed(let requestID): notices[requestID] = nil
      case .erased:
        answers.removeAll()
        notices.removeAll()
        known.removeAll()
        erased = true
      }
    }
  }

  /// Queues only ordinary allow-once/deny decisions, never credentials or secure-form payloads.
  /// T4/T5 owner verification and all other card actions require the real runner's live path.
  public func enqueue(
    conversationID: ConversationID, params: CardsRespondParams, expiresAt: Int64, at now: Int64
  ) throws {
    guard !failed, !erased else { throw DeviceLayerError.closed }
    guard params.action == "allow_once" || params.action == "deny", params.payload == nil,
      params.deviceAuth == nil, params.surface == nil || params.surface == .ui
    else { throw DeviceLayerError.invalid("offline approval action") }
    let answer = Answer(conversationID: conversationID, params: params, expiresAt: expiresAt)
    if let existing = known[params.requestId] {
      guard existing == answer else {
        throw DeviceLayerError.invalid("offline approval request conflict")
      }
      return
    }
    guard expiresAt > now else { throw DeviceLayerError.invalid("approval already expired") }
    try persist(.queued(answer))
    known[params.requestId] = answer
    answers[params.requestId] = answer
  }

  /// Selects only answers whose original deadline is still in the future. Expired answers are
  /// removed and their notice is synchronized before returning; they cannot be sent on retry.
  public func pending(at now: Int64) throws -> [Answer] {
    guard !failed else { throw DeviceLayerError.closed }
    for answer in answers.values.sorted(by: {
      $0.params.requestId.rawValue < $1.params.requestId.rawValue
    })
    where answer.expiresAt <= now {
      let notice = ExpiryNotice(
        requestID: answer.params.requestId, cardID: answer.params.cardId,
        expiredAt: answer.expiresAt)
      try persist(.expired(notice))
      answers[answer.params.requestId] = nil
      notices[notice.requestID] = notice
    }
    return answers.values.sorted { $0.params.requestId.rawValue < $1.params.requestId.rawValue }
  }

  /// Call only after the confirmed runner returns the original request's definitive result.
  /// An uncertain/offline send is deliberately retained for idempotent delivery after reconnect.
  public func acknowledgeResult(_ requestID: ULID) throws {
    guard answers[requestID] != nil else { return }
    try persist(.delivered(requestID))
    answers[requestID] = nil
  }

  /// Returns undisplayed expiry notices in request-ID order without consuming them.
  public func expiryNotices() -> [ExpiryNotice] {
    notices.values.sorted { $0.requestID.rawValue < $1.requestID.rawValue }
  }

  /// Call after displaying the notice. Persists its removal before forgetting it; unknown
  /// request IDs are harmless, and a journal failure leaves the mailbox failed closed.
  public func acknowledgeNotice(_ requestID: ULID) throws {
    guard notices[requestID] != nil else { return }
    try persist(.noticeDisplayed(requestID))
    notices[requestID] = nil
  }

  /// D133: after this device's verified removal from its group, deletes every held answer and
  /// expiry notice. The journal is replaced by one `erased` record (written beside it,
  /// synchronized, renamed over it, directory synchronized), so no byte of an earlier record is
  /// in the file when this returns. Every later write is refused, also after a reopen. Repeating
  /// it rewrites the same record. A failure leaves the mailbox failed closed, and calling it
  /// again tries again. Not after ``close()``.
  public func erase() throws {
    guard !closed else { throw DeviceLayerError.closed }
    // A failed write leaves a journal refusing every later one, so the erasure goes through
    // the journal opened again, replacing the file without reading it.
    journal.close()
    do {
      journal = try DeviceStateJournal(
        url: url, key: key, purpose: Self.purpose, discardingHistory: true)
      try journal.replace(Record.erased)
    } catch {
      failed = true
      throw error
    }
    answers.removeAll()
    notices.removeAll()
    known.removeAll()
    erased = true
    // The erased journal is sound: reads answer empty, and every write is refused as erased.
    failed = false
  }

  /// Closes the local journal and refuses future writes; does not delete queued disk state.
  public func close() {
    failed = true
    closed = true
    journal.close()
  }

  private func persist(_ record: Record) throws {
    guard !failed, !erased else { throw DeviceLayerError.closed }
    do { try journal.append(record) } catch {
      failed = true
      throw error
    }
  }
}
