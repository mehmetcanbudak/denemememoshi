import Darwin
import Foundation
import MemoshiProtocol
import MemoshiStore

/// Safe failures; bookmark bytes, source contents and raw OS errors are never rendered.
public enum SourceFolderAuthorityError: Error, Equatable, Sendable {
  case invalidRoot
  case confirmationRequired
  case unavailable
  case changedRoot
  case unsupportedPlatform
  /// No trusted host source context was composed, so folder management stays unavailable.
  case notConfigured
}

/// A captured source capability, not permission to expose its live path to a model environment.
/// Grant revisions are immutable here: access changes require a fresh binding and proposal.
public struct SourceFolderBinding: Sendable {
  /// The existing folder Grant's identity.
  public var grantID: GrantID { record.id }
  /// The source path used for review and original-namespace policy, never a sandbox allowance.
  public var sourceRoot: String { record.path }
  /// The exact local grant generation admitted by this binding.
  public var reference: FolderGrantReference { record.reference }

  fileprivate let record: FolderGrantRecord
  let store: Store
  fileprivate let context: SourcePathPolicyContext

  /// Declares one actual file target from this host-captured source, not a model-supplied class.
  public func target(_ relativePath: String) throws -> RuntimeSourceTarget {
    let classification = try SourcePathPolicy.classify(
      sourceRoot: record.path, relativePath: relativePath, context: context)
    return RuntimeSourceTarget(
      binding: self, relativePath: relativePath, classification: classification)
  }

  /// Current local ownership for an explicitly admitted private copy. The Chat is looked up,
  /// not accepted as a caller-supplied bot identity, and access changes invalidate this binding.
  func workingCopyAuthority(chatID: ConversationID, access: FolderGrantAccess) async throws
    -> FolderSourceIdentity
  {
    let chats = try await store.chats().value
    guard
      chats.contains(where: { $0.id == chatID && $0.botId == record.botID })
    else {
      throw FolderGrantError.notFound
    }
    let current = try await store.folderGrantAuthority(
      [reference], botID: record.botID, access: access, at: IDGenerator.nowMilliseconds())
    guard let source = current.first, source.path.utf8.elementsEqual(record.path.utf8),
      source.sourceIdentity == record.sourceIdentity, source.bookmarkData == record.bookmarkData
    else { throw FolderGrantError.staleReference }
    try SourceFolderAuthority.verify(source, context: context)
    return source.sourceIdentity
  }

  /// Private copies must live in protected application state, never another grantable folder.
  func validateWorkingCopyContainer(_ path: String) throws {
    guard
      context.protectedStateRoots.contains(where: {
        path.utf8.elementsEqual($0.utf8) || path.utf8.starts(with: ($0 + "/").utf8)
      })
    else { throw SourcePathPolicyError.notGrantable }
  }

  /// Inspect each entry before the native importer reads/traverses it. Protected entries
  /// refuse the complete admission; nothing is silently omitted or exposed as raw secrets.
  func validateWorkingCopyEntry(_ path: String) throws {
    switch try target(path).classification {
    case .project, .instruction, .ciConfig: return
    case .secret, .hostExec, .gitInternal, .system, .memoshiState:
      throw SourcePathPolicyError.notGrantable
    }
  }
}

/// Source metadata for a trusted tool's actual read/write. Construct through a validated binding.
public struct RuntimeSourceTarget: Sendable {
  /// The original source-relative file path, not a staging location.
  public let relativePath: String
  /// The original source class; callers cannot substitute a bot-home classification.
  public let classification: SourcePathClass
  fileprivate let binding: SourceFolderBinding

  fileprivate init(
    binding: SourceFolderBinding, relativePath: String, classification: SourcePathClass
  ) {
    self.binding = binding
    self.relativePath = relativePath
    self.classification = classification
  }

  var originalPath: String { binding.sourceRoot + "/" + relativePath }
}

/// Trusted host admission of folder authority. This does not start PiEnv, copy file data or
/// export a proposal; those effects still require their own qualified descriptor implementation.
public struct SourceFolderAuthority: Sendable {
  private let store: Store
  private let context: SourcePathPolicyContext

  /// Host configuration must include every application/Pi state root and external hook root.
  public init(store: Store, context: SourcePathPolicyContext) {
    self.store = store
    self.context = context
  }

  /// `bots.grants.list` for the authenticated app: one bot's grants, after lapsed deadlines end
  /// durably. `available` is a fresh no-follow root and bookmark check; it reads no source
  /// content and never reports a raw filesystem reason.
  public func list(
    _ params: BotsGrantsListParams, at now: Int64 = IDGenerator.nowMilliseconds()
  ) async throws -> BotsGrantsListResult {
    let snapshot = try await store.folderGrants(botID: params.botId, at: now)
    return BotsGrantsListResult(
      items: snapshot.value.map { $0.summary(available: isAvailable($0)) }, asOf: snapshot.asOf)
  }

  /// `bots.grants.update` with the authenticated user's authority, applied at most once per
  /// request key. A stored receipt answers before any current check, so a retry never runs
  /// again, never allocates a second grant and never undoes a later change. A new root needs
  /// fresh no-follow physical and bookmark proof before it persists, and widening needs that
  /// proof again. Granting or widening a whole personal folder needs its exact typed path,
  /// checked here. Restricting needs neither, so unavailable authority can always be narrowed.
  public func update(
    _ params: BotsGrantsUpdateParams, actor: Actor,
    at now: Int64 = IDGenerator.nowMilliseconds()
  ) async throws -> BotsGrantsUpdateResult {
    #if os(macOS)
      guard actor.kind == .user else { throw FolderGrantError.forbidden }
      let hash = try RuntimeAdapter.paramsHash(params)
      if var receipt = try await store.requestReceipt(
        params.requestId, method: BotsGrantsUpdate.name, paramsHash: hash,
        as: BotsGrantsUpdateResult.self)
      {
        receipt.replayed = true
        return receipt
      }
      let change = params.grant
      guard let access = FolderGrantAccess(change.access), change.path.utf8.count <= 4_096 else {
        throw FolderGrantError.invalidRequest
      }
      if let typed = change.confirmationText, typed != change.path {
        throw SourceFolderAuthorityError.confirmationRequired
      }
      if change.id == nil {
        guard change.expectedRevision == nil, change.expiresAt.map({ $0 > now }) ?? true,
          let selected = change.selectionIdentity.flatMap(Self.sourceIdentity)
        else { throw FolderGrantError.invalidRequest }
        let broad = try SourcePathPolicy.validateGrantRoot(change.path, context: context)
        guard !broad || change.confirmationText != nil else {
          throw SourceFolderAuthorityError.confirmationRequired
        }
        let proof = try Self.capture(change.path, context: context)
        // The directory the user reviewed must be the one captured here, before anything commits.
        guard proof.identity == selected else { throw SourceFolderAuthorityError.changedRoot }
        return try await store.createFolderGrant(
          params, paramsHash: hash, sourceIdentity: proof.identity, bookmarkData: proof.bookmark,
          actor: actor, at: now)
      }
      guard let id = change.id, let expected = change.expectedRevision, expected > 0,
        change.selectionIdentity == nil
      else { throw FolderGrantError.invalidRequest }
      guard let current = try await store.folderGrant(id, at: now).value,
        current.botID == params.botId, current.deviceID == store.deviceID
      else { throw FolderGrantError.notFound }
      guard current.path.utf8.elementsEqual(change.path.utf8),
        change.expiresAt == nil || change.expiresAt == current.expiresAt
      else { throw FolderGrantError.invalidRequest }
      guard current.status == .active else { throw FolderGrantError.unavailable }
      guard current.revision == expected else { throw FolderGrantError.staleReference }
      let available: Bool
      if access == .write, current.access == .read {
        let broad = try SourcePathPolicy.validateGrantRoot(current.path, context: context)
        guard !broad || change.confirmationText != nil else {
          throw SourceFolderAuthorityError.confirmationRequired
        }
        try Self.reprove(current, context: context)
        available = true
      } else {
        available = isAvailable(current)
      }
      return try await store.changeFolderGrantAccess(
        params, paramsHash: hash, available: available, actor: actor, at: now)
    #else
      throw SourceFolderAuthorityError.unsupportedPlatform
    #endif
  }

  /// `bots.grants.revoke` with the authenticated user's authority, applied at most once per
  /// request key. It reads no filesystem state, so unavailable authority can always end.
  public func revoke(
    _ params: BotsGrantsRevokeParams, actor: Actor,
    at now: Int64 = IDGenerator.nowMilliseconds()
  ) async throws {
    let hash = try RuntimeAdapter.paramsHash(params)
    try await store.revokeFolderGrant(params, paramsHash: hash, actor: actor, at: now)
  }

  /// Rebinds a persisted, currently readable source after normal store/runtime reopen.
  public func bind(
    _ grantID: GrantID, botID: BotID, at now: Int64 = IDGenerator.nowMilliseconds()
  ) async throws -> SourceFolderBinding {
    #if os(macOS)
      guard let record = try await store.folderGrant(grantID, at: now).value else {
        throw FolderGrantError.notFound
      }
      let records = try await store.folderGrantAuthority(
        [record.reference], botID: botID, access: .read, at: now)
      guard let current = records.first else { throw FolderGrantError.unavailable }
      try Self.verify(current, context: context)
      return SourceFolderBinding(record: current, store: store, context: context)
    #else
      throw SourceFolderAuthorityError.unsupportedPlatform
    #endif
  }

  /// Whether a grant is active and its root still proves the identity it captured. A failed
  /// check is only `false`, never an error or a raw OS reason.
  private func isAvailable(_ record: FolderGrantRecord) -> Bool {
    guard record.status == .active else { return false }
    do {
      try Self.verify(record, context: context)
      return true
    } catch {
      return false
    }
  }

  /// The reviewed identity as canonical decimal text, exactly `String(UInt64)`; anything else,
  /// such as a sign, leading zero or whitespace, is not an identity.
  private static func sourceIdentity(
    _ selection: FolderGrantSelectionIdentity
  ) -> FolderSourceIdentity? {
    guard let device = UInt64(selection.device), String(device) == selection.device,
      let inode = UInt64(selection.inode), String(inode) == selection.inode
    else { return nil }
    return FolderSourceIdentity(device: device, inode: inode)
  }

  /// Fresh physical proof for one new root before anything persists: a no-follow descriptor, a
  /// bookmark captured while it is held, and that bookmark resolved back to the same physical
  /// path and identity.
  private static func capture(
    _ path: String, context: SourcePathPolicyContext
  ) throws -> (identity: FolderSourceIdentity, bookmark: Data) {
    #if os(macOS)
      let root = try SourceDirectoryHandle(path)
      let bookmark: Data
      do {
        bookmark = try URL(fileURLWithPath: path, isDirectory: true).bookmarkData(
          options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      } catch { throw SourceFolderAuthorityError.unavailable }
      try root.verify()
      try verify(path: path, identity: root.identity, bookmark: bookmark, context: context)
      return (root.identity, bookmark)
    #else
      throw SourceFolderAuthorityError.unsupportedPlatform
    #endif
  }

  /// Fresh proof that an existing grant's root is still the one it captured. A root the policy
  /// no longer admits keeps that refusal; any other failure is reported as unavailable.
  private static func reprove(
    _ record: FolderGrantRecord, context: SourcePathPolicyContext
  ) throws {
    do {
      try verify(record, context: context)
    } catch SourcePathPolicyError.notGrantable {
      throw SourcePathPolicyError.notGrantable
    } catch SourceFolderAuthorityError.changedRoot {
      throw SourceFolderAuthorityError.changedRoot
    } catch {
      throw SourceFolderAuthorityError.unavailable
    }
  }

  fileprivate static func verify(
    _ record: FolderGrantRecord, context: SourcePathPolicyContext
  ) throws {
    try verify(
      path: record.path, identity: record.sourceIdentity, bookmark: record.bookmarkData,
      context: context)
  }

  /// The complete check of one captured root: policy, no-follow identity, and a bookmark that
  /// resolves without UI or mounting to the same physical path and identity.
  private static func verify(
    path: String, identity: FolderSourceIdentity, bookmark: Data,
    context: SourcePathPolicyContext
  ) throws {
    #if os(macOS)
      _ = try SourcePathPolicy.validateGrantRoot(path, context: context)
      let root = try SourceDirectoryHandle(path)
      guard root.identity == identity else { throw SourceFolderAuthorityError.changedRoot }
      var stale = false
      let resolved: URL
      do {
        resolved = try URL(
          resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
          relativeTo: nil, bookmarkDataIsStale: &stale)
      } catch { throw SourceFolderAuthorityError.unavailable }
      guard !stale, resolved.isFileURL,
        try SourceDirectoryHandle.physicalPath(resolved.path) == path
      else {
        throw SourceFolderAuthorityError.changedRoot
      }
      let bookmarked = try SourceDirectoryHandle(path)
      guard bookmarked.identity == identity else { throw SourceFolderAuthorityError.changedRoot }
      try root.verify()
    #else
      throw SourceFolderAuthorityError.unsupportedPlatform
    #endif
  }
}

/// Derived only from current Store records and host-captured source identities.
struct RuntimeSourceAuthorization: Sendable {
  let references: [FolderGrantReference]
  let classes: Set<SourcePathClass>
  let targets: [String]
  let contentHash: String

  static func resolve(
    _ targets: [RuntimeSourceTarget], operation: ToolPolicyOperation,
    store: Store, botID: BotID, at now: Int64
  ) async throws -> RuntimeSourceAuthorization {
    guard !targets.isEmpty, targets.count <= 1024 else {
      throw RuntimeToolError.invalidArguments
    }
    var bindings: [GrantID: SourceFolderBinding] = [:]
    for target in targets {
      let binding = target.binding
      guard binding.store === store else { throw FolderGrantError.unavailable }
      if let previous = bindings[binding.grantID] {
        guard previous.reference == binding.reference,
          previous.record.path == binding.record.path,
          previous.record.sourceIdentity == binding.record.sourceIdentity
        else { throw FolderGrantError.staleReference }
      } else {
        bindings[binding.grantID] = binding
      }
    }
    let references = bindings.values.map(\.reference).sorted {
      $0.grantID.rawValue < $1.grantID.rawValue
    }
    let records = try await store.folderGrantAuthority(
      references, botID: botID, access: operation == .fileRead ? .read : .write, at: now)
    for record in records {
      guard let binding = bindings[record.id], record.path == binding.record.path,
        record.sourceIdentity == binding.record.sourceIdentity,
        record.bookmarkData == binding.record.bookmarkData
      else { throw FolderGrantError.staleReference }
      try SourceFolderAuthority.verify(record, context: binding.context)
    }
    let sorted = targets.sorted {
      if $0.binding.grantID != $1.binding.grantID {
        return $0.binding.grantID.rawValue < $1.binding.grantID.rawValue
      }
      return $0.relativePath < $1.relativePath
    }
    let identity: [JSONValue] = sorted.map {
      [
        "grantId": .string($0.binding.grantID.rawValue),
        "revision": .integer($0.binding.reference.revision),
        "sourceRoot": .string($0.binding.sourceRoot),
        "relativePath": .string($0.relativePath),
        "class": .string($0.classification.rawValue),
      ]
    }
    return RuntimeSourceAuthorization(
      references: references, classes: Set(targets.map(\.classification)),
      targets: sorted.map(\.originalPath),
      contentHash: try RuntimeAdapter.paramsHash(JSONValue.array(identity)))
  }
}

/// One owned descriptor across the Store actor hop. Only immutable metadata/path are shared;
/// operations are synchronous, and no descriptor is returned to callers or child processes.
private final class SourceDirectoryHandle: Sendable {
  let path: String
  let identity: FolderSourceIdentity
  private let descriptor: Int32

  init(_ path: String) throws {
    guard path.utf8.first == 47, path != "/", path.utf8.last != 47 else {
      throw SourceFolderAuthorityError.invalidRoot
    }
    let parts = path.utf8.dropFirst().split(separator: 47, omittingEmptySubsequences: false)
    var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard current >= 0 else { throw SourceFolderAuthorityError.unavailable }
    do {
      var expected = ""
      for part in parts {
        let name = String(decoding: part, as: UTF8.self)
        guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix("~"),
          name.lowercased() != "..namedfork", !name.contains(":"), !name.contains("\\"),
          !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw SourceFolderAuthorityError.invalidRoot }
        expected += "/" + name
        let next = name.withCString {
          Darwin.openat(current, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard next >= 0 else { throw SourceFolderAuthorityError.invalidRoot }
        Darwin.close(current)
        current = next
        try Self.checkPath(current, expected: expected)
      }
      var metadata = stat()
      guard Darwin.fstat(current, &metadata) == 0,
        metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
        metadata.st_uid == geteuid(), metadata.st_mode & mode_t(0o7000) == 0
      else { throw SourceFolderAuthorityError.invalidRoot }
      self.path = path
      self.identity = FolderSourceIdentity(
        device: UInt64(bitPattern: Int64(metadata.st_dev)), inode: UInt64(metadata.st_ino))
      self.descriptor = current
    } catch {
      Darwin.close(current)
      throw error
    }
  }

  deinit { Darwin.close(descriptor) }

  func verify() throws {
    try Self.checkPath(descriptor, expected: path)
    let current = try SourceDirectoryHandle(path)
    guard current.identity == identity else { throw SourceFolderAuthorityError.changedRoot }
  }

  private static func checkPath(_ descriptor: Int32, expected: String) throws {
    let flags = Darwin.fcntl(descriptor, F_GETFD)
    guard flags >= 0, flags & FD_CLOEXEC != 0 else {
      throw SourceFolderAuthorityError.invalidRoot
    }
    let same = withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(MAXPATHLEN)) { buffer in
      guard let address = buffer.baseAddress,
        Darwin.fcntl(descriptor, F_GETPATH, address) == 0
      else { return false }
      return String(cString: address) == expected
    }
    guard same else { throw SourceFolderAuthorityError.changedRoot }
  }

  static func physicalPath(_ path: String) throws -> String {
    try path.withCString { input in
      try withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(MAXPATHLEN)) { buffer in
        guard let address = buffer.baseAddress, Darwin.realpath(input, address) != nil else {
          throw SourceFolderAuthorityError.changedRoot
        }
        return String(cString: address)
      }
    }
  }
}
