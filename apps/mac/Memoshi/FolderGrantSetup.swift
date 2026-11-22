import Foundation
import MemoshiClient
import MemoshiProtocol
import Observation

/// Whether the connected runtime negotiated local folder management.
enum FolderGrantSupport: Equatable, Sendable {
  /// No authenticated hello has been inspected yet.
  case unknown
  /// The runtime negotiated `bots.grants.folder.v1`.
  case supported
  /// The runtime offers no folder management. Nothing is listed, so no empty list is implied.
  case unsupported
}

/// One explicit review before any request. Choosing a folder or opening a row grants nothing.
struct FolderGrantReview: Equatable, Sendable {
  enum Subject: Equatable, Sendable {
    /// A folder chosen in the system panel, with the device and inode observed when it was
    /// chosen. A new-folder request carries them, so the runtime grants only that directory.
    case newFolder(FolderGrantSelectionIdentity)
    /// An active grant at the exact revision and access that were reviewed.
    case existing(GrantID, revision: Int64, access: FolderGrantPermission)
  }

  let subject: Subject
  /// The folder's physical path as its file system spells it; the runtime receives exactly this.
  let path: String
  /// An entire Desktop, Documents, Downloads, Pictures, Movies, Music or Public folder.
  let isBroad: Bool
}

/// A folder-panel result that cannot be reviewed. Nothing is granted or substituted for it.
private enum FolderSelectionError: Error {
  case notLocal
  case notFolder
  case linked(actual: String)
  case unreadable

  var message: String {
    switch self {
    case .notLocal:
      String(localized: "Choose a folder on this Mac's file system. Nothing was granted.")
    case .notFolder:
      String(
        localized:
          "Choose a folder, not a file, package, alias or symbolic link. Nothing was granted.")
    case .linked(let actual):
      String(
        localized:
          "This location is reached through a link or a different spelling. Choose the folder at its actual location, \(actual). Nothing was granted."
      )
    case .unreadable:
      String(
        localized:
          "The selected folder's identity could not be read. Choose it again; nothing was granted."
      )
    }
  }
}

/// App-owned folder-grant review for the Assistant only. The list is an authoritative runtime
/// snapshot fed by LiveChatModel's bootstrap and sole event consumer; a mutation receipt is
/// never applied as current state. Preferences hold only exact request parameters, including a
/// chosen folder's device and inode numbers, never bookmark bytes or folder contents.
@MainActor
@Observable
final class FolderGrantSetup {
  private static let capability = "bots.grants.folder.v1"

  private(set) var botID: BotID?
  private(set) var botName: String?
  private(set) var grants: [FolderGrantSummary] = []
  private(set) var support = FolderGrantSupport.unknown
  private(set) var connection = ClientConnectionState.disconnected
  private(set) var hasLoaded = false
  private(set) var isFresh = false
  private(set) var isLoading = false
  private(set) var isUpdating = false
  private(set) var revoking: Set<GrantID> = []
  private(set) var now = Int64(Date().timeIntervalSince1970 * 1_000)
  private(set) var problem: String?
  private(set) var outcome: String?
  private(set) var grantOutcomes: [GrantID: String] = [:]
  private(set) var review: FolderGrantReview?
  private(set) var confirmationRequiredByRuntime = false
  private(set) var pendingUpdate: BotsGrantsUpdateParams?
  private(set) var pendingRevocations: [GrantID: BotsGrantsRevokeParams] = [:]
  private(set) var hasUnreadableRecord = false
  /// The access chosen in the open review. Read only is the default for a new folder.
  var access = FolderGrantPermission.read
  /// Typed confirmation of the reviewed path. It confirms the chosen folder; it never chooses one.
  var confirmation = ""

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var client: MemoshiClient?
  @ObservationIgnored private var grantsAsOf: Int64 = 0
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var loadsInFlight = 0
  @ObservationIgnored private var needsSnapshot = true
  @ObservationIgnored private var unreadableKeys: [String] = []
  @ObservationIgnored private var updateTask: Task<Void, Never>?
  @ObservationIgnored private var revokeTasks: [GrantID: Task<Void, Never>] = [:]
  @ObservationIgnored private var refreshTask: Task<Void, Never>?

  private static let pendingUpdateKey = "folder-grants.pending-update"
  private static let pendingRevocationsKey = "folder-grants.pending-revocations"

  init(defaults: UserDefaults) {
    self.defaults = defaults
    let decoder = ProtocolCoding.makeDecoder(strict: true)
    if let bytes = defaults.data(forKey: Self.pendingUpdateKey) {
      do {
        pendingUpdate = try decoder.decode(BotsGrantsUpdateParams.self, from: bytes)
      } catch { unreadableKeys.append(Self.pendingUpdateKey) }
    }
    if let bytes = defaults.data(forKey: Self.pendingRevocationsKey) {
      do {
        var restored: [GrantID: BotsGrantsRevokeParams] = [:]
        for intent in try decoder.decode([BotsGrantsRevokeParams].self, from: bytes) {
          guard restored.updateValue(intent, forKey: intent.grantId) == nil else {
            throw ClientError.protocolViolation("Duplicate saved folder revocation")
          }
        }
        pendingRevocations = restored
      } catch { unreadableKeys.append(Self.pendingRevocationsKey) }
    }
    if !unreadableKeys.isEmpty {
      hasUnreadableRecord = true
      problem = String(
        localized:
          "A saved folder request could not be read. New folder changes are blocked so an uncertain request is not duplicated or widened."
      )
    }
  }

  /// A current snapshot of the Assistant's grants from a supported, connected runtime, with no
  /// read in flight. Folder changes are offered only in this state.
  var isReady: Bool {
    connection == .connected && support == .supported && botID != nil && hasLoaded && isFresh
      && !isLoading
  }

  var isSynchronized: Bool { connection == .connected && isFresh }
  var canRefresh: Bool { connection == .connected && !isLoading }

  var canChoose: Bool { isReady && canKeepSelection }

  /// A panel result may return while a list read is in flight; it still only opens a review,
  /// whose action requires a current snapshot.
  private var canKeepSelection: Bool {
    connection == .connected && support == .supported && botID != nil && !hasUnreadableRecord
      && pendingUpdate == nil && !isUpdating
  }

  /// Broad folders need typed confirmation to be granted or widened; so does any request that
  /// the runtime refused for lacking it.
  var requiresConfirmation: Bool {
    guard let review else { return false }
    if confirmationRequiredByRuntime { return true }
    guard review.isBroad else { return false }
    switch review.subject {
    case .newFolder: return true
    case .existing(_, _, let current): return current == .read && access == .write
    }
  }

  var canSubmitReview: Bool {
    guard let review, isReady, !hasUnreadableRecord, pendingUpdate == nil, !isUpdating,
      access == .read || access == .write,
      !requiresConfirmation || confirmation == review.path
    else { return false }
    switch review.subject {
    case .newFolder:
      return true
    case .existing(let id, let revision, let current):
      guard access != current, let grant = grants.first(where: { $0.id == id }),
        grant.status == .active, grant.revision == revision, grant.access == current,
        pendingRevocations[id] == nil, !revoking.contains(id)
      else { return false }
      // Restricting never needs the folder; widening needs a present, unexpired source.
      return access == .read || (grant.available && !isPastDeadline(grant))
    }
  }

  func canChangeAccess(_ grant: FolderGrantSummary) -> Bool {
    guard isReady, !hasUnreadableRecord, pendingUpdate == nil, !isUpdating,
      grant.status == .active, pendingRevocations[grant.id] == nil, !revoking.contains(grant.id)
    else { return false }
    switch grant.access {
    case .write: return true
    case .read: return grant.available && !isPastDeadline(grant)
    default: return false
    }
  }

  /// Revocation only removes authority, so a list read in flight does not block it.
  func canRevoke(_ grant: FolderGrantSummary) -> Bool {
    connection == .connected && support == .supported && hasLoaded && !hasUnreadableRecord
      && grant.status == .active && pendingRevocations[grant.id] == nil
      && !revoking.contains(grant.id)
  }

  /// Retrying sends only the exact saved request, never a replacement.
  var canRetryPendingUpdate: Bool {
    connection == .connected && support == .supported && pendingUpdate != nil && !isUpdating
  }

  func canRetryRevocation(_ id: GrantID) -> Bool {
    connection == .connected && support == .supported && pendingRevocations[id] != nil
      && !revoking.contains(id)
  }

  var canDiscardUnreadableRecord: Bool { hasUnreadableRecord && isReady }

  /// Saved revocations whose grant is absent from the loaded list stay visible and retryable.
  var unmatchedRevocations: [GrantID] {
    pendingRevocations.keys.filter { id in !grants.contains { $0.id == id } }
      .sorted { $0.rawValue < $1.rawValue }
  }

  func isPastDeadline(_ grant: FolderGrantSummary) -> Bool {
    grant.status == .active && grant.expiresAt.map { $0 <= now } == true
  }

  func attach(_ client: MemoshiClient) { self.client = client }

  func stop() {
    updateTask?.cancel()
    refreshTask?.cancel()
    for work in revokeTasks.values { work.cancel() }
    updateTask = nil
    refreshTask = nil
    revokeTasks.removeAll()
    isFresh = false
    needsSnapshot = true
  }

  func connectionChanged(_ state: ClientConnectionState) {
    if state != connection && state != .connected {
      isFresh = false
      needsSnapshot = true
    }
    connection = state
  }

  /// A reconnect replaces the folder snapshot before folder changes are offered again.
  var needsReconnectSnapshot: Bool { needsSnapshot }

  /// Bootstrap replaces the Assistant identity and its whole folder snapshot before the barrier
  /// is acknowledged. Other bots and design previews are never listed here.
  func bootstrap(
    _ client: MemoshiClient, assistant: ChatSummary?, minimumSeq: Int64
  ) async throws {
    if botID != assistant?.botId {
      cancelReview()
      outcome = nil
      grantOutcomes.removeAll()
    }
    botID = assistant?.botId
    botName = assistant?.title
    try await reload(client, minimumSeq: minimumSeq, replacing: true)
  }

  /// The runtime lists one bot's grants in one read, durably expiring lapsed grants first. Only
  /// a snapshot at or after the application barrier is accepted.
  func reload(
    _ client: MemoshiClient, minimumSeq: Int64 = 0, replacing: Bool = false
  ) async throws {
    if replacing {
      generation += 1
      grants = []
      grantsAsOf = 0
      hasLoaded = false
      isFresh = false
    }
    let generation = self.generation
    loadsInFlight += 1
    isLoading = true
    defer {
      loadsInFlight -= 1
      isLoading = loadsInFlight != 0
    }
    do {
      guard let hello = await client.status().hello else { throw ClientError.notConnected }
      guard generation == self.generation else { return }
      guard hello.capabilities.contains(where: { $0.rawValue == Self.capability }) else {
        markUnsupported()
        return
      }
      support = .supported
      guard let botID else {
        // Without an Assistant Chat there is no bot whose folders could be listed or granted.
        grants = []
        hasLoaded = false
        isFresh = false
        needsSnapshot = false
        return
      }
      let result = try await client.call(BotsGrantsList.self, .init(botId: botID))
      guard result.asOf.seq >= minimumSeq else {
        throw ClientError.protocolViolation("Folder grant snapshot predates application barrier")
      }
      guard result.items.allSatisfy({ $0.botId == botID }),
        Set(result.items.map(\.id)).count == result.items.count
      else { throw ClientError.protocolViolation("Folder grant snapshot is inconsistent") }
      // A replacing bootstrap or a different Assistant supersedes this read.
      guard generation == self.generation, botID == self.botID else { return }
      if result.asOf.seq >= grantsAsOf { applySnapshot(result) }
      hasLoaded = true
      isFresh = true
      needsSnapshot = false
      if !hasUnreadableRecord { problem = nil }
    } catch {
      guard generation == self.generation else { throw error }
      // A runtime without the folder backend refuses the method; that is not an empty list.
      if let refusal = error as? RPCError,
        refusal.kind == .methodNotFound || refusal.kind == .capabilityMissing
      {
        markUnsupported()
        return
      }
      isFresh = false
      needsSnapshot = true
      if !hasUnreadableRecord { problem = Self.snapshotMessage(error) }
      throw error
    }
  }

  /// Called before the shared consumer acknowledges a durable event. A grant event for the
  /// Assistant, or a pending reconnect snapshot, reloads the whole list first.
  func apply(_ envelope: EventEnvelope, client: MemoshiClient) async throws {
    let seq = envelope.seq ?? 0
    let changed =
      envelope.type.hasPrefix("grant.") && seq > grantsAsOf
      && (envelope.scope.botId == nil || envelope.scope.botId == botID)
    if needsSnapshot || changed {
      try await reload(client, minimumSeq: seq)
    }
  }

  func refresh() {
    guard let client, refreshTask == nil, canRefresh else { return }
    refreshTask = Task { [weak self, client] in
      guard let self else { return }
      defer { self.refreshTask = nil }
      // A failed read is reported in `problem`; nothing is retried or mutated.
      do { try await self.reload(client) } catch {}
    }
  }

  /// Opening the sheet updates deadline display and re-reads a stale list, never a mutation.
  func sheetAppeared() {
    now = Self.milliseconds()
    if !isFresh && support != .unsupported { refresh() }
  }

  /// Records only a review. The system panel's choice grants nothing by itself.
  func choose(_ url: URL) {
    guard canKeepSelection else {
      outcome = String(
        localized:
          "Folder changes are unavailable right now, so this folder was not reviewed or granted. Choose it again when folder state is synchronized."
      )
      return
    }
    outcome = nil
    do {
      let selection = try Self.inspect(url)
      guard !grants.contains(where: { $0.status == .active && $0.path == selection.path }) else {
        cancelReview()
        outcome = Self.duplicateMessage
        return
      }
      review = FolderGrantReview(
        subject: .newFolder(selection.identity), path: selection.path,
        isBroad: Self.isBroadRoot(selection.path))
      access = .read
      confirmation = ""
      confirmationRequiredByRuntime = false
    } catch {
      cancelReview()
      outcome = ((error as? FolderSelectionError) ?? .unreadable).message
    }
  }

  func choiceFailed() {
    outcome = String(localized: "The folder panel did not return a folder. Nothing was granted.")
  }

  /// Opens an explicit access-change review at the grant's current revision.
  func reviewChange(of grant: FolderGrantSummary) {
    guard canChangeAccess(grant) else { return }
    review = FolderGrantReview(
      subject: .existing(grant.id, revision: grant.revision, access: grant.access),
      path: grant.path, isBroad: Self.isBroadRoot(grant.path))
    access = grant.access == .write ? .read : .write
    confirmation = ""
    confirmationRequiredByRuntime = false
    outcome = nil
  }

  func cancelReview() {
    review = nil
    confirmation = ""
    confirmationRequiredByRuntime = false
  }

  /// Saves the exact request before sending it, so an uncertain answer can only be retried.
  func submitReview() {
    guard canSubmitReview, let review, let botID else { return }
    let confirmationText = requiresConfirmation ? confirmation : nil
    let change: FolderGrantChange
    switch review.subject {
    case .newFolder(let identity):
      // The panel's folder must still be the same directory at this exact path. The runtime
      // checks the same identity again when it captures the folder, before anything commits.
      guard Self.identity(at: review.path) == identity else {
        cancelReview()
        outcome = String(
          localized:
            "The folder at this path changed after you chose it. Nothing was sent; choose it again."
        )
        return
      }
      change = FolderGrantChange(
        path: review.path, access: access, confirmationText: confirmationText,
        selectionIdentity: identity)
    case .existing(let id, let revision, _):
      change = FolderGrantChange(
        id: id, path: review.path, access: access, expectedRevision: revision,
        confirmationText: confirmationText)
    }
    do {
      let params = BotsGrantsUpdateParams(
        requestId: try MemoshiClient.requestID(), botId: botID, grant: change)
      try rememberUpdate(params)
      performUpdate(params)
    } catch {
      outcome = String(localized: "The request could not be saved on this Mac, so it was not sent.")
    }
  }

  func retryPendingUpdate() {
    guard canRetryPendingUpdate, let pendingUpdate else { return }
    performUpdate(pendingUpdate)
  }

  func revoke(_ grant: FolderGrantSummary) {
    guard let current = grants.first(where: { $0.id == grant.id }), current.status == .active
    else { return }
    guard canRevoke(current) else {
      grantOutcomes[current.id] = String(
        localized:
          "Revocation is unavailable right now, so nothing was sent. Revoke again when folder state is synchronized."
      )
      return
    }
    do {
      let params = BotsGrantsRevokeParams(
        requestId: try MemoshiClient.requestID(), grantId: current.id)
      var next = pendingRevocations
      next[current.id] = params
      try saveRevocations(next)
      performRevoke(params)
    } catch {
      grantOutcomes[current.id] = String(
        localized: "The revocation could not be saved on this Mac, so it was not sent.")
    }
  }

  func retryRevocation(_ id: GrantID) {
    guard canRetryRevocation(id), let params = pendingRevocations[id] else { return }
    performRevoke(params)
  }

  /// Removes only records that can never be read or retried, after a current list is loaded.
  func discardUnreadableRecords() {
    guard canDiscardUnreadableRecord else { return }
    for key in unreadableKeys { defaults.removeObject(forKey: key) }
    unreadableKeys.removeAll()
    hasUnreadableRecord = false
    problem = nil
    outcome = String(
      localized:
        "The unreadable saved request was discarded without sending anything. The list shows current grants; check it before granting the same folder again."
    )
  }

  private func performUpdate(_ params: BotsGrantsUpdateParams) {
    guard let client, updateTask == nil else { return }
    isUpdating = true
    outcome = nil
    updateTask = Task { [weak self, client] in
      guard let self else { return }
      defer {
        self.isUpdating = false
        self.updateTask = nil
      }
      do {
        let result = try await client.call(BotsGrantsUpdate.self, params)
        guard result.grant.botId == params.botId, result.grant.path == params.grant.path,
          params.grant.id.map({ $0 == result.grant.id }) ?? true
        else {
          throw ClientError.protocolViolation("Folder grant receipt mismatch")
        }
        self.clearPendingUpdate()
        if self.review?.path == params.grant.path { self.cancelReview() }
        self.outcome = Self.receiptMessage(result, params: params)
        // A receipt, even a replayed one, is not current authority; only the snapshot is.
        do { try await self.reload(client, minimumSeq: result.writtenSeq) } catch {
          self.outcome = String(
            localized:
              "The runtime answered this request, but the current folder list could not be loaded. Refresh before relying on it."
          )
        }
      } catch let error as RPCError {
        if Self.isDefinite(error) {
          self.clearPendingUpdate()
          if error.kind == .typedConfirmationMismatch, self.review?.path == params.grant.path {
            self.confirmationRequiredByRuntime = true
          }
          // A refused new folder (not the chosen directory, already granted, or over the limit)
          // must be chosen again rather than resubmitted from the same review.
          if error.kind == .conflict, params.grant.id == nil,
            self.review?.path == params.grant.path
          {
            self.cancelReview()
          }
          self.outcome = Self.refusalMessage(error, isNewGrant: params.grant.id == nil)
        } else {
          self.outcome = Self.uncertainUpdateMessage
        }
        do { try await self.reload(client) } catch {}
      } catch {
        self.outcome = Self.uncertainUpdateMessage
      }
    }
  }

  private func performRevoke(_ params: BotsGrantsRevokeParams) {
    let id = params.grantId
    guard let client, revokeTasks[id] == nil else { return }
    revoking.insert(id)
    grantOutcomes.removeValue(forKey: id)
    revokeTasks[id] = Task { [weak self, client] in
      guard let self else { return }
      defer {
        self.revoking.remove(id)
        self.revokeTasks.removeValue(forKey: id)
      }
      do {
        _ = try await client.call(BotsGrantsRevoke.self, params)
        self.clearRevocation(id)
        self.grantOutcomes[id] = String(
          localized:
            "Revocation recorded. A revoked grant cannot be restored; choose the folder again to make a new grant."
        )
        do { try await self.reload(client) } catch {
          self.grantOutcomes[id] = String(
            localized:
              "The runtime answered this revocation, but the current folder list could not be loaded. Refresh before relying on it."
          )
        }
      } catch let error as RPCError {
        if Self.isDefinite(error) {
          self.clearRevocation(id)
          self.grantOutcomes[id] = Self.refusalMessage(error)
        } else {
          self.grantOutcomes[id] = Self.uncertainRevocationMessage
        }
        do { try await self.reload(client) } catch {}
      } catch {
        self.grantOutcomes[id] = Self.uncertainRevocationMessage
      }
    }
  }

  private func applySnapshot(_ result: BotsGrantsListResult) {
    grants = result.items.sorted { lhs, rhs in
      let lhsEnded = lhs.status != .active
      let rhsEnded = rhs.status != .active
      if lhsEnded != rhsEnded { return !lhsEnded }
      if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
      return lhs.id.rawValue < rhs.id.rawValue
    }
    grantsAsOf = result.asOf.seq
    now = Self.milliseconds()
    // A terminal grant can never regain authority, so its saved revocation has nothing left to do.
    let ended = Set(grants.filter { $0.status == .revoked || $0.status == .expired }.map(\.id))
    let settled = pendingRevocations.keys.filter { ended.contains($0) && !revoking.contains($0) }
    if !settled.isEmpty {
      var next = pendingRevocations
      for id in settled { next.removeValue(forKey: id) }
      try? saveRevocations(next)
    }
    // An unresolved saved request keeps its review as sent. Otherwise never submit a review
    // against a grant that changed, and never grant an actively granted folder a second time.
    guard pendingUpdate == nil, let review else { return }
    switch review.subject {
    case .existing(let id, let revision, let current):
      let unchanged = grants.contains {
        $0.id == id && $0.status == .active && $0.revision == revision && $0.access == current
      }
      if !unchanged {
        cancelReview()
        outcome = String(
          localized:
            "This grant changed while you were reviewing it. Nothing was sent; review its current access again."
        )
      }
    case .newFolder:
      if grants.contains(where: { $0.status == .active && $0.path == review.path }) {
        cancelReview()
        outcome = Self.duplicateMessage
      }
    }
  }

  private func markUnsupported() {
    support = .unsupported
    grants = []
    grantsAsOf = 0
    hasLoaded = false
    isFresh = false
    needsSnapshot = false
    cancelReview()
  }

  private func rememberUpdate(_ params: BotsGrantsUpdateParams) throws {
    guard !unreadableKeys.contains(Self.pendingUpdateKey) else {
      throw ClientError.protocolViolation("Unreadable saved folder request")
    }
    defaults.set(try ProtocolCoding.makeEncoder().encode(params), forKey: Self.pendingUpdateKey)
    pendingUpdate = params
  }

  private func clearPendingUpdate() {
    guard pendingUpdate != nil else { return }
    defaults.removeObject(forKey: Self.pendingUpdateKey)
    pendingUpdate = nil
  }

  private func saveRevocations(_ next: [GrantID: BotsGrantsRevokeParams]) throws {
    guard !unreadableKeys.contains(Self.pendingRevocationsKey) else {
      throw ClientError.protocolViolation("Unreadable saved folder revocations")
    }
    if next.isEmpty {
      defaults.removeObject(forKey: Self.pendingRevocationsKey)
    } else {
      let saved = next.values.sorted { $0.grantId.rawValue < $1.grantId.rawValue }
      defaults.set(
        try ProtocolCoding.makeEncoder().encode(saved), forKey: Self.pendingRevocationsKey)
    }
    pendingRevocations = next
  }

  private func clearRevocation(_ id: GrantID) {
    guard pendingRevocations[id] != nil else { return }
    var next = pendingRevocations
    next.removeValue(forKey: id)
    try? saveRevocations(next)
  }

  /// The panel's URL must already be the folder's own physical spelling: a link, alias, package
  /// or differently spelled path is refused rather than resolved into another location.
  private static func inspect(
    _ url: URL
  ) throws -> (path: String, identity: FolderGrantSelectionIdentity) {
    guard url.isFileURL else { throw FolderSelectionError.notLocal }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let values: URLResourceValues
    do {
      values = try url.resourceValues(forKeys: [
        .isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .isPackageKey, .canonicalPathKey,
      ])
    } catch { throw FolderSelectionError.unreadable }
    guard values.isDirectory == true, values.isSymbolicLink != true,
      values.isAliasFile != true, values.isPackage != true
    else { throw FolderSelectionError.notFolder }
    guard let actual = values.canonicalPath, actual.hasPrefix("/") else {
      throw FolderSelectionError.unreadable
    }
    guard actual == url.path else { throw FolderSelectionError.linked(actual: actual) }
    guard let identity = identity(at: actual) else { throw FolderSelectionError.unreadable }
    return (actual, identity)
  }

  /// Metadata only: the directory entry itself, without following a final symbolic link. The
  /// numbers use the runtime's own conversion of `st_dev` and `st_ino` to canonical decimal.
  private static func identity(at path: String) -> FolderGrantSelectionIdentity? {
    var status = stat()
    guard lstat(path, &status) == 0, status.st_mode & S_IFMT == S_IFDIR else { return nil }
    return FolderGrantSelectionIdentity(
      device: String(UInt64(bitPattern: Int64(status.st_dev))),
      inode: String(UInt64(status.st_ino)))
  }

  /// Advisory only, to ask before sending. The runtime classifies broad roots from its trusted
  /// home and refuses a missing confirmation with `typed_confirmation_mismatch`.
  private static func isBroadRoot(_ path: String) -> Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public"].contains {
      path.compare("\(home)/\($0)", options: .caseInsensitive) == .orderedSame
    }
  }

  private static func milliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  /// A definite refusal means this request was not applied, so its saved record may be cleared.
  private static func isDefinite(_ error: RPCError) -> Bool {
    !error.data.retryable
      && ![
        .timeout, .internalError, .storageFailed, .shuttingDown, .hostUnavailable, .leaseFenced,
        .deviceUnreachable,
      ].contains(error.kind)
  }

  private static func receiptMessage(
    _ result: BotsGrantsUpdateResult, params: BotsGrantsUpdateParams
  ) -> String {
    if result.replayed == true {
      return String(
        localized:
          "The original request's receipt was recovered. No second grant or wider access was created; the list shows current state, including any later change."
      )
    }
    if params.grant.id == nil {
      return String(
        localized:
          "Folder access was granted to the Assistant. Tools stay disabled, so nothing in the folder is read or changed now."
      )
    }
    return String(localized: "Folder access was changed. Tools stay disabled.")
  }

  /// A new grant's `conflict` (already granted, or the per-bot limit) carries the runtime's own
  /// explanation; an access change's `conflict` means its reviewed revision is no longer current.
  private static func refusalMessage(_ error: RPCError, isNewGrant: Bool = false) -> String {
    switch error.kind {
    case .typedConfirmationMismatch:
      String(
        localized:
          "This folder needs typed confirmation of its exact path. Nothing was changed; type the path and review again."
      )
    case .conflict where !isNewGrant:
      String(
        localized:
          "The grant changed or ended before this request applied. Nothing was changed; review its current state."
      )
    case .notFound:
      String(localized: "The Assistant or this grant is no longer available. Nothing was changed.")
    case .idempotencyConflict:
      String(
        localized:
          "The saved request identity was already used for a different request. Nothing else was sent, and no replacement identity was substituted."
      )
    case .methodNotFound, .capabilityMissing:
      String(
        localized: "The connected runtime does not support folder management. Nothing was changed.")
    case .conflict where isNewGrant, .forbidden, .invalidParams:
      String(localized: "\(error.message) Nothing was changed.")
    default:
      String(localized: "The runtime refused this request: \(error.message) Nothing was changed.")
    }
  }

  private static var duplicateMessage: String {
    String(
      localized:
        "This folder already has an active grant for the Assistant. Change its access or revoke it in the list; nothing new was granted."
    )
  }

  private static var uncertainUpdateMessage: String {
    String(
      localized:
        "Delivery is unconfirmed. The exact request is saved on this Mac; Retry Original Request recovers its answer without creating another grant or asking for wider access."
    )
  }

  private static var uncertainRevocationMessage: String {
    String(
      localized:
        "Revocation delivery is unconfirmed. The exact revocation is saved on this Mac; retrying sends only that original request."
    )
  }

  private static func snapshotMessage(_ error: any Error) -> String {
    if let error = error as? RPCError {
      return String(
        localized:
          "Folder grants could not be loaded: \(error.message) Folder changes stay disabled until the current list loads."
      )
    }
    return String(
      localized:
        "Folder grants are not synchronized. Folder changes stay disabled until the current list loads; Refresh tries again."
    )
  }
}
