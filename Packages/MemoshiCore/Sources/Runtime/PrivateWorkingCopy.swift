import CryptoKit
import Darwin
import Foundation
import MemoshiStore

/// One exact file change frozen from a private copy, named by its original source-relative path.
struct WorkingCopyChange: Sendable {
  /// The original source-relative file path, never a private staging location.
  let path: String
  /// `create`, `replace` or `delete`.
  let kind: String
  /// The admitted source bytes' SHA-256, or `nil` for a create.
  let baseHash: String?
  /// The frozen private bytes' SHA-256, or `nil` for a delete.
  let newHash: String?
  /// The exact frozen bytes, or `nil` for a delete.
  let newContents: Data?

  fileprivate init(
    path: String, kind: String, baseHash: String?, newHash: String?, newContents: Data?
  ) {
    self.path = path
    self.kind = kind
    self.baseHash = baseHash
    self.newHash = newHash
    self.newContents = newContents
  }
}

/// An immutable content-bound proposal that only a live private copy issues. Its digest binds
/// the copy session, the admitted source baseline, the frozen stage and every exact byte.
struct WorkingCopyProposal: Sendable {
  let contentHash: String
  let changes: [WorkingCopyChange]

  fileprivate init(contentHash: String, changes: [WorkingCopyChange]) {
    self.contentHash = contentHash
    self.changes = changes
  }
}

/// A completed export, or an exact proposal whose export had already completed.
enum WorkingCopyApplyResult: String, Sendable {
  case applied
  case alreadyApplied
}

/// Engine failures. Descriptions carry raw paths and `errno` text for diagnosis inside the
/// engine only; callers expose safe runtime errors instead.
enum WorkingCopyFailure: Error, CustomStringConvertible, Sendable {
  /// A check refused before any effect it guards.
  case refused(String)
  /// A system call failed.
  case system(operation: String, code: Int32)
  /// Metadata outside the content-only profile must be preserved by refusing the operation.
  case unsupportedMetadata
  /// The trusted resource profile cannot admit, scan, capture or export this work.
  case resourceLimitExceeded
  /// A source effect happened, or a prepared temporary could not be proven removed. Paths are
  /// source-relative. The copy then refuses every later proposal and export.
  case partialApplication(
    contentHash: String, completedPaths: [String], remainingTemporaryPaths: [String],
    cause: String)
  /// Private cleanup refused an unproven object or failed, so the private root may remain.
  case cleanupFailed(String)

  var description: String {
    switch self {
    case .refused(let reason):
      return "Working-copy refusal: \(reason)"
    case .system(let operation, let code):
      return "Working-copy \(operation): \(String(cString: strerror(code))) (errno \(code))"
    case .unsupportedMetadata:
      return "Working-copy metadata is not supported by the content-only profile."
    case .resourceLimitExceeded:
      return "Working-copy resource ceiling exceeded."
    case .partialApplication(let hash, let paths, let temporaryPaths, let cause):
      return "Working-copy partial application \(hash); completed paths: \(paths); "
        + "remaining temporary paths: \(temporaryPaths); \(cause). No multi-file transaction "
        + "or external-writer CAS is claimed; inspect the source before a new working copy."
    case .cleanupFailed(let reason):
      return "Working-copy private cleanup did not complete: \(reason)"
    }
  }
}

/// A descriptor-owned private copy of one granted source folder.
///
/// Admission opens the source root without following links and requires its granted identity
/// before any entry is read. Every source scan passes each nonempty source-relative path to the
/// trusted entry policy before that entry is examined or copied, and admitted bytes land in fresh
/// private inodes. A proposal freezes exact staged bytes against the admitted baseline; export
/// rechecks that baseline and installs each file through an exclusive temporary and rename.
/// There is no multi-file transaction or external-writer compare-and-swap, so a failure after
/// any effect poisons the copy with an explicit partial outcome. No operation suspends, so
/// close, proposal and export never interleave.
actor PrivateWorkingCopy {
  /// The private root a sandboxed environment may use; never the live source.
  nonisolated let workingRoot: String
  private let sourcePath: String
  private let containerPath: String
  private let workingName: String
  private let sourceIdentity: WorkingCopyObjectID
  private let containerIdentity: WorkingCopyObjectID
  nonisolated let workingIdentity: WorkingCopyObjectID
  private let sessionID: String
  private let validateEntry: @Sendable (String) throws -> Void
  /// Test-only scheduling barriers; production composition passes none.
  private let exportWillAffect: @Sendable (String) throws -> Void
  private let exportDidDisplace: @Sendable (String) throws -> Void
  private let exportWillRemove: @Sendable (String) throws -> Void
  private let exportWillCloseRemoval: @Sendable (String) throws -> Void
  private let exportWillUnlinkClosed: @Sendable (String) throws -> Void
  private let exportDidCloseProbe: @Sendable (String) throws -> Void
  private let cleanupWillRemove: @Sendable (String) throws -> Void
  private let limits: WorkingCopyLimits
  private var sourceHandle: WorkingCopyHandle?
  private var containerHandle: WorkingCopyHandle?
  private var workingHandle: WorkingCopyHandle?
  private var baseline: WorkingCopyTree
  private var expectedWorkingFiles: [String: StagedMode]
  private var expectedWorkingDirectories: [String: WorkingCopyDirectoryRecord]
  /// Source and exported identities that private cleanup must never remove.
  private var protectedSourceObjects: Set<WorkingCopyObjectID>
  private var generation: UInt64 = 0
  private var issued: IssuedProposal?
  private var appliedBindings: [String: String] = [:]
  private var exportFailure: WorkingCopyFailure?
  private var closeFailure: WorkingCopyFailure?
  private var closed = false
  /// One reusable buffer for every streamed hash, copy and capture.
  private var ioBuffer: [UInt8]

  private struct StagedMode: Equatable, Sendable {
    let mode: mode_t
    let group: gid_t
  }

  private struct IssuedProposal: Sendable {
    let proposal: WorkingCopyProposal
    let binding: String
    let generation: UInt64
    let stagedTree: WorkingCopyTree
  }

  private struct OpenRoots {
    let source: WorkingCopyHandle
    let working: WorkingCopyHandle
    let container: WorkingCopyHandle
  }

  /// One change's original location, opened and conflict-checked before any source effect.
  private struct PlannedChange {
    let change: WorkingCopyChange
    let parent: WorkingCopyHandle
    let parentRelative: String
    let parentPath: String
    let name: String
  }

  /// One exclusive export temporary in a source directory, owned from its creation.
  private struct Temporary {
    let handle: WorkingCopyHandle
    let parent: WorkingCopyHandle
    let parentPath: String
    let name: String
    /// The temporary's source-relative path, the only form reported to callers.
    let relativePath: String
    var installed = false
  }

  /// Source effects and temporaries so far, for honest partial-outcome reporting.
  private struct ExportProgress {
    var temporaries: [Temporary] = []
    var temporaryIndex: [String: Int] = [:]
    var completed: [String] = []
    var installed: [String: WorkingCopyObjectID] = [:]
    /// Source-relative Memoshi names still holding an outside or displaced object.
    var retained: [String] = []
  }

  /// Admits the source into a fresh private root beneath `containerRoot`.
  ///
  /// `expectedSourceIdentity` must match the opened source root before anything below it is
  /// read. `validateEntry` receives every nonempty source-relative entry path, never the root,
  /// before that entry is examined, traversed, read or copied, on this and every later source
  /// scan; a throw refuses the whole operation. Other entry types are refused after it passes.
  /// A refused admission removes only objects it created itself.
  ///
  /// `exportWillAffect`, `exportDidDisplace`, `exportWillRemove`, `exportWillCloseRemoval`,
  /// `exportWillUnlinkClosed`, `exportDidCloseProbe` and `cleanupWillRemove` are internal test
  /// barriers. The first receives a change's source-relative path after that change's final
  /// conflict check, immediately before its first source effect; the second receives a replaced
  /// or deleted path once its original has been moved to a Memoshi name, before that object is
  /// verified; the third receives that path after the moved original was verified, before
  /// export removes it from its Memoshi name; the fourth receives the source-relative path of
  /// that original inside its removal directory, once it was moved there and before the
  /// directory's deny entry is set; the fifth receives the same path after its last check,
  /// immediately before `unlinkat`; the sixth receives the source-relative path of export's
  /// access-control probe directory once its deny entry is set, before the probe tries to add
  /// an entry to it; the seventh receives a private entry's name after cleanup's final check of
  /// it, immediately before its removal. Production passes none.
  init(
    sourceRoot: String, containerRoot: String, ownership: WorkingCopyOwnership,
    limits: WorkingCopyLimits, validateEntry: @escaping @Sendable (String) throws -> Void,
    exportWillAffect: @escaping @Sendable (String) throws -> Void = { _ in },
    exportDidDisplace: @escaping @Sendable (String) throws -> Void = { _ in },
    exportWillRemove: @escaping @Sendable (String) throws -> Void = { _ in },
    exportWillCloseRemoval: @escaping @Sendable (String) throws -> Void = { _ in },
    exportWillUnlinkClosed: @escaping @Sendable (String) throws -> Void = { _ in },
    exportDidCloseProbe: @escaping @Sendable (String) throws -> Void = { _ in },
    cleanupWillRemove: @escaping @Sendable (String) throws -> Void = { _ in }
  ) throws {
    let source = try WorkingCopyFS.openAbsoluteDirectory(sourceRoot)
    let sourceID = WorkingCopyObjectID(source.metadata)
    guard sourceID.device == ownership.sourceIdentity.device,
      sourceID.inode == ownership.sourceIdentity.inode
    else { throw WorkingCopyFailure.refused("source root is not the granted folder") }
    try WorkingCopyFS.requireOwnedDirectory(source.metadata, path: source.path)
    let container = try WorkingCopyFS.openAbsoluteDirectory(containerRoot)
    try WorkingCopyFS.requireOwnedDirectory(
      container.metadata, path: container.path, privateContainer: true)
    let containerID = WorkingCopyObjectID(container.metadata)
    guard containerID.device == ownership.containerIdentity.device,
      containerID.inode == ownership.containerIdentity.inode
    else { throw WorkingCopyFailure.refused("private container changed after reservation") }
    guard !container.ancestors.contains(sourceID), !source.ancestors.contains(containerID),
      !WorkingCopyFS.isWithin(container.path, source.path),
      !WorkingCopyFS.isWithin(source.path, container.path)
    else { throw WorkingCopyFailure.refused("working-copy container and source overlap") }
    let name = ownership.workingName
    let privatePath = WorkingCopyFS.childPath(container.path, name)
    let privateRoot = try PrivateWorkingCopy.makePrivateRoot(
      in: container, name: name, path: privatePath)
    var created: Set<WorkingCopyObjectID> = [privateRoot.identity]
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    let imported: WorkingCopyTree
    let staged: WorkingCopyTree
    do {
      let target = WorkingCopyCopyTarget(
        handle: privateRoot.handle, path: privatePath, device: privateRoot.identity.device)
      imported = try WorkingCopyFS.scan(
        source.handle, path: source.path, namespace: .source(validateEntry), copyTo: target,
        created: &created, limits: limits, buffer: &buffer)
      let rescanned = try WorkingCopyFS.scan(
        source.handle, path: source.path, namespace: .source(validateEntry),
        limits: limits, buffer: &buffer)
      guard rescanned == imported else {
        throw WorkingCopyFailure.refused("source changed during admission copy")
      }
      staged = try WorkingCopyFS.scan(
        privateRoot.handle, path: privatePath, namespace: .stage, limits: limits, buffer: &buffer)
      try PrivateWorkingCopy.verifyAdmittedCopy(
        imported: imported, staged: staged, created: created)
      // After every byte is copied, both paths still name the roots that were opened.
      try PrivateWorkingCopy.verifyRootPath(source.handle, path: source.path, identity: sourceID)
      try PrivateWorkingCopy.verifyRootPath(
        container.handle, path: container.path, identity: containerID, privateContainer: true)
    } catch {
      // No environment has this root yet: only objects created above may be removed.
      do {
        try PrivateWorkingCopy.removePrivateRoot(
          container: container.handle, containerPath: container.path, name: name,
          root: privateRoot.handle, rootPath: privatePath, protected: [sourceID],
          createdOnly: created, willRemove: cleanupWillRemove)
      } catch let cleanupError {
        throw WorkingCopyFailure.cleanupFailed(
          "admission failed: \(error); private cleanup refused: \(cleanupError)")
      }
      throw error
    }
    workingRoot = privatePath
    sourcePath = source.path
    containerPath = container.path
    workingName = name
    sourceIdentity = sourceID
    containerIdentity = containerID
    workingIdentity = privateRoot.identity
    sessionID = ownership.id.uuidString
    self.validateEntry = validateEntry
    self.exportWillAffect = exportWillAffect
    self.exportDidDisplace = exportDidDisplace
    self.exportWillRemove = exportWillRemove
    self.exportWillCloseRemoval = exportWillCloseRemoval
    self.exportWillUnlinkClosed = exportWillUnlinkClosed
    self.exportDidCloseProbe = exportDidCloseProbe
    self.cleanupWillRemove = cleanupWillRemove
    self.limits = limits
    sourceHandle = source.handle
    containerHandle = container.handle
    workingHandle = privateRoot.handle
    baseline = imported
    expectedWorkingFiles = staged.files.mapValues {
      StagedMode(mode: $0.state.permissions, group: $0.state.group)
    }
    expectedWorkingDirectories = staged.directories
    protectedSourceObjects = imported.identities.union([sourceID])
    ioBuffer = buffer
  }

  deinit {
    // Explicit close reports cleanup failures. This best-effort fallback refuses the same
    // unsafe cases, and descriptor deinitializers still close every handle.
    guard !closed, let containerHandle, let workingHandle else { return }
    try? Self.removeOwnedRoot(
      source: sourceHandle, container: containerHandle, containerPath: containerPath,
      containerIdentity: containerIdentity, working: workingHandle, workingRoot: workingRoot,
      workingName: workingName, protected: protectedSourceObjects,
      willRemove: cleanupWillRemove)
  }

  /// Freezes the exact staged differences from the admitted baseline. Issuing a proposal
  /// changes no source file, and a newer proposal makes every older one stale.
  func proposal() throws -> WorkingCopyProposal {
    guard generation < UInt64(limits.maximumExports) else {
      throw WorkingCopyFailure.resourceLimitExceeded
    }
    let roots = try verifyRoots()
    let staged = try scanStage(roots.working)
    try verifySupportedStage(staged)
    guard try scanSource(roots.source) == baseline else {
      throw WorkingCopyFailure.refused("live source no longer matches the admitted baseline")
    }
    let paths = Set(baseline.files.keys).union(staged.files.keys).sorted {
      $0.utf8.lexicographicallyPrecedes($1.utf8)
    }
    var changes: [WorkingCopyChange] = []
    var parents: [String: WorkingCopyHandle] = [:]
    var captureBudget = WorkingCopyBudget(limits, maximumBytes: limits.maximumProposalBytes)
    for path in paths {
      let old = baseline.files[path]
      guard old?.hash != staged.files[path]?.hash else { continue }
      guard changes.count < limits.maximumChanges else {
        throw WorkingCopyFailure.resourceLimitExceeded
      }
      guard let new = staged.files[path] else {
        changes.append(
          WorkingCopyChange(
            path: path, kind: "delete", baseHash: old?.hash, newHash: nil, newContents: nil))
        continue
      }
      let parts = try WorkingCopyFS.relativeComponents(path)
      guard let name = parts.last else {
        throw WorkingCopyFailure.refused("expected a nonempty relative path")
      }
      let parentRelative = parts.dropLast().joined(separator: "/")
      let parent: WorkingCopyHandle
      if let cached = parents[parentRelative] {
        parent = cached
      } else {
        parent = try WorkingCopyFS.openRelativeDirectory(
          root: roots.working, rootPath: workingRoot, components: parts.dropLast(),
          device: workingIdentity.device)
        parents[parentRelative] = parent
      }
      let read = try WorkingCopyFS.readFile(
        parent: parent.value, name: name, expectedPath: WorkingCopyFS.childPath(workingRoot, path),
        device: workingIdentity.device, buffer: &ioBuffer, capture: true,
        maximumBytes: captureBudget.fileAllowance)
      guard read.file == new, let contents = read.contents else {
        throw WorkingCopyFailure.refused("staged file changed while freezing proposal: \(path)")
      }
      try captureBudget.consumeBytes(read.file.state.size)
      changes.append(
        WorkingCopyChange(
          path: path, kind: old == nil ? "create" : "replace", baseHash: old?.hash,
          newHash: new.hash, newContents: contents))
    }
    // Refuses a change to an earlier file made while later immutable data was captured.
    guard try scanStage(roots.working) == staged else {
      throw WorkingCopyFailure.refused("staged tree changed during proposal capture")
    }
    let context = binding(for: staged)
    let result = WorkingCopyProposal(
      contentHash: Self.proposalHash(binding: context, changes: changes), changes: changes)
    issued = IssuedProposal(
      proposal: result, binding: context, generation: generation, stagedTree: staged)
    return result
  }

  /// Authenticates the exact issued proposal and rechecks its frozen stage and source baseline.
  /// An exact proposal that was already applied has no further effect and passes.
  func validate(_ proposal: WorkingCopyProposal) throws {
    guard let record = try authenticate(proposal) else { return }
    try validateCurrent(record)
  }

  /// Exports the exact issued proposal. Every known conflict refuses the whole batch before any
  /// source effect, as does a source volume that does not report exclusive rename and access
  /// control list support, or whose mount does not enforce the deny entry that closes a
  /// removal directory (``requireEnforcedClosure(in:device:)``). Each create is then installed
  /// by an exclusive temporary and exclusive rename. Each replace is an atomic swap whose
  /// swapped-out object must be the admitted original or, where the volume reports no swap
  /// support, an exclusive move of the admitted original aside followed by an exclusive rename
  /// of the replacement onto the freed name. Each delete is an exclusive move that must hold
  /// the admitted original before it is removed. A displaced original or unused temporary is
  /// removed only inside a directory closed to new entries, so an object renamed onto a Memoshi
  /// name is never unlinked. An outside edit found by those checks is restored, a name
  /// recreated outside in between is never overwritten, and the export refuses. A failure
  /// after any effect, or a Memoshi name that cannot be proven removed, is a partial
  /// application.
  func apply(
    _ proposal: WorkingCopyProposal, expectedContentHash: String
  ) throws -> WorkingCopyApplyResult {
    guard expectedContentHash == proposal.contentHash else {
      throw WorkingCopyFailure.refused("approval digest does not match the immutable proposal")
    }
    guard let record = try authenticate(proposal) else { return .alreadyApplied }
    try validateCurrent(record)
    let roots = try verifyRoots()
    // Every known parent and target conflict refuses before any source-side temporary exists.
    // No directory or mode change is exported.
    let plan = try preflight(record.proposal, source: roots.source)
    // Every planned parent is on the source root's device, so its volume decides for all.
    let renames = try Self.renameSupport(roots.source)
    guard renames.exclusive, renames.accessControlLists else {
      throw WorkingCopyFailure.refused(
        "the source volume does not report exclusive rename and access control list support, "
          + "so no change can be installed or removed without risking an outside object; "
          + "nothing was changed")
    }
    try requireEnforcedClosure(in: roots.source, device: sourceIdentity.device)
    var progress = ExportProgress()
    do {
      try prepareTemporaries(plan, progress: &progress)
      try install(plan, swap: renames.swap, progress: &progress)
      try finishExport(record, plan: plan, progress: progress, source: roots.source)
      return .applied
    } catch {
      throw unwind(error, proposal: record.proposal, progress: progress)
    }
  }

  /// Removes the whole private root and closes every descriptor. A refused or failed cleanup is
  /// reported, here and on every later call, never treated as success.
  func close() throws {
    guard !closed else {
      if let closeFailure { throw closeFailure }
      return
    }
    closed = true
    issued = nil
    appliedBindings.removeAll(keepingCapacity: false)
    var failures: [String] = []
    if let containerHandle, let workingHandle {
      do {
        try Self.removeOwnedRoot(
          source: sourceHandle, container: containerHandle, containerPath: containerPath,
          containerIdentity: containerIdentity, working: workingHandle, workingRoot: workingRoot,
          workingName: workingName, protected: protectedSourceObjects,
          willRemove: cleanupWillRemove)
      } catch {
        failures.append(String(describing: error))
      }
    }
    for handle in [workingHandle, sourceHandle, containerHandle] {
      do {
        try handle?.close()
      } catch {
        failures.append(String(describing: error))
      }
    }
    workingHandle = nil
    sourceHandle = nil
    containerHandle = nil
    guard failures.isEmpty else {
      let failure = WorkingCopyFailure.cleanupFailed("close: " + failures.joined(separator: "; "))
      closeFailure = failure
      throw failure
    }
  }

  // MARK: - Admission

  /// Creates the fresh private root. On failure it removes only that identified directory, and
  /// only while it is still empty.
  private static func makePrivateRoot(
    in container: WorkingCopyRoot, name: String, path: String
  ) throws -> (handle: WorkingCopyHandle, identity: WorkingCopyObjectID) {
    let parent = container.handle.value
    guard Darwin.mkdirat(parent, name, 0o700) == 0 else {
      throw WorkingCopyFS.failure("mkdirat fresh private root")
    }
    guard let made = try? WorkingCopyFS.metadataAt(parent, name),
      made.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), made.st_uid == geteuid()
    else {
      throw WorkingCopyFailure.cleanupFailed(
        "fresh private root cannot be identified, so nothing was removed: \(path)")
    }
    let identity = WorkingCopyObjectID(made)
    do {
      let handle = try WorkingCopyFS.openDirectory(
        parent, name: name, expectedPath: path, device: identity.device)
      guard WorkingCopyObjectID(try WorkingCopyFS.metadata(handle.value)) == identity,
        try WorkingCopyFS.entryNames(handle.value, maximumEntries: 0).isEmpty
      else { throw WorkingCopyFailure.refused("fresh private root changed during open") }
      guard Darwin.fchmod(handle.value, 0o700) == 0 else {
        throw WorkingCopyFS.failure("fchmod fresh private root")
      }
      return (handle, identity)
    } catch {
      guard let current = try? WorkingCopyFS.metadataAt(parent, name),
        WorkingCopyObjectID(current) == identity
      else {
        throw WorkingCopyFailure.cleanupFailed(
          "private root setup failed: \(error); its name changed, so cleanup was refused")
      }
      // Directory removal also refuses unless the identified root is still empty.
      guard Darwin.unlinkat(parent, name, AT_REMOVEDIR) == 0 else {
        let code = errno
        throw WorkingCopyFailure.cleanupFailed(
          "private root setup failed: \(error); empty-root removal failed: errno \(code)")
      }
      throw error
    }
  }

  /// The private tree must be exactly the admitted tree, made only of objects this admission
  /// created, with independent identities and matching bytes and modes.
  private static func verifyAdmittedCopy(
    imported: WorkingCopyTree, staged: WorkingCopyTree, created: Set<WorkingCopyObjectID>
  ) throws {
    guard Set(staged.directories.keys) == Set(imported.directories.keys),
      Set(staged.files.keys) == Set(imported.files.keys),
      staged.identities.isSubset(of: created)
    else { throw WorkingCopyFailure.refused("private copy differs from the admitted tree") }
    for (path, file) in imported.files {
      guard let copy = staged.files[path], copy.hash == file.hash,
        copy.state.permissions == file.state.permissions,
        copy.state.identity != file.state.identity
      else { throw WorkingCopyFailure.refused("private file copy mismatch: \(path)") }
    }
    for (path, directory) in imported.directories where !path.isEmpty {
      guard let copy = staged.directories[path], copy.permissions == directory.permissions,
        copy.identity != directory.identity
      else { throw WorkingCopyFailure.refused("private directory copy mismatch: \(path)") }
    }
  }

  /// Proves a held root descriptor is still at its path, and that the path reopened from `/`
  /// without following links still names the same owned directory.
  private static func verifyRootPath(
    _ handle: WorkingCopyHandle, path: String, identity: WorkingCopyObjectID,
    privateContainer: Bool = false
  ) throws {
    try WorkingCopyFS.verifyPath(handle.value, path)
    let reopened = try WorkingCopyFS.openAbsoluteDirectory(path)
    guard WorkingCopyObjectID(reopened.metadata) == identity,
      WorkingCopyObjectID(try WorkingCopyFS.metadata(handle.value)) == identity
    else { throw WorkingCopyFailure.refused("root path identity changed: \(path)") }
    try WorkingCopyFS.requireOwnedDirectory(
      reopened.metadata, path: path, privateContainer: privateContainer)
  }

  // MARK: - Current state

  private func requireOpen() throws -> OpenRoots {
    guard !closed, let sourceHandle, let workingHandle, let containerHandle else {
      throw WorkingCopyFailure.refused("working copy is closed")
    }
    if let exportFailure { throw exportFailure }
    return OpenRoots(source: sourceHandle, working: workingHandle, container: containerHandle)
  }

  private func verifyRoots() throws -> OpenRoots {
    let roots = try requireOpen()
    try Self.verifyRootPath(roots.source, path: sourcePath, identity: sourceIdentity)
    try Self.verifyRootPath(roots.working, path: workingRoot, identity: workingIdentity)
    try Self.verifyRootPath(
      roots.container, path: containerPath, identity: containerIdentity, privateContainer: true)
    guard !WorkingCopyFS.isWithin(workingRoot, sourcePath),
      !WorkingCopyFS.isWithin(sourcePath, workingRoot)
    else { throw WorkingCopyFailure.refused("source and private copy overlap") }
    return roots
  }

  /// Every source scan consults the original-namespace entry policy before each entry.
  private func scanSource(_ handle: WorkingCopyHandle) throws -> WorkingCopyTree {
    try WorkingCopyFS.scan(
      handle, path: sourcePath, namespace: .source(validateEntry), limits: limits, buffer: &ioBuffer
    )
  }

  private func scanStage(_ handle: WorkingCopyHandle) throws -> WorkingCopyTree {
    try WorkingCopyFS.scan(
      handle, path: workingRoot, namespace: .stage, limits: limits, buffer: &ioBuffer)
  }

  /// The proposal ABI is content-only: an unrepresentable directory or mode edit refuses instead
  /// of silently exporting a subset of the private tree.
  private func verifySupportedStage(_ staged: WorkingCopyTree) throws {
    guard Set(staged.directories.keys) == Set(expectedWorkingDirectories.keys) else {
      throw WorkingCopyFailure.refused(
        "directory creation or removal, including an empty directory, cannot be exported")
    }
    for (path, directory) in staged.directories {
      guard let expected = expectedWorkingDirectories[path],
        directory.permissions == expected.permissions, directory.owner == expected.owner,
        directory.group == expected.group
      else {
        throw WorkingCopyFailure.refused("directory mode, owner or group change: \(path)")
      }
    }
    for (path, file) in staged.files {
      if let expected = expectedWorkingFiles[path] {
        guard file.state.permissions == expected.mode, file.state.group == expected.group else {
          throw WorkingCopyFailure.refused("file mode or group change cannot be exported: \(path)")
        }
        continue
      }
      let parent = try WorkingCopyFS.relativeComponents(path).dropLast().joined(separator: "/")
      let standardMode = file.state.permissions == 0o600 || file.state.permissions == 0o644
      guard standardMode, file.state.group == staged.directories[parent]?.group else {
        throw WorkingCopyFailure.refused(
          "new executable, nonstandard-mode or regrouped file cannot be exported: \(path)")
      }
    }
  }

  /// Binds a proposal to this session, both root identities, the generation, the admitted
  /// source baseline and the frozen stage.
  private func binding(for staged: WorkingCopyTree) -> String {
    var hasher = SHA256()
    Self.add("Memoshi.PrivateWorkingCopy.binding.v1", to: &hasher)
    Self.add(sessionID, to: &hasher)
    Self.add(sourcePath, to: &hasher)
    Self.add(sourceIdentity.device, to: &hasher)
    Self.add(sourceIdentity.inode, to: &hasher)
    Self.add(workingRoot, to: &hasher)
    Self.add(workingIdentity.device, to: &hasher)
    Self.add(workingIdentity.inode, to: &hasher)
    Self.add(generation, to: &hasher)
    for (path, directory) in baseline.directories.sorted(by: { $0.key < $1.key }) {
      Self.add("source-directory", to: &hasher)
      Self.add(path, to: &hasher)
      Self.add(directory.identity.device, to: &hasher)
      Self.add(directory.identity.inode, to: &hasher)
      Self.add(UInt64(directory.permissions), to: &hasher)
    }
    for (path, file) in baseline.files.sorted(by: { $0.key < $1.key }) {
      Self.add("source-file", to: &hasher)
      Self.add(path, to: &hasher)
      Self.add(file.state.identity.device, to: &hasher)
      Self.add(file.state.identity.inode, to: &hasher)
      Self.add(file.hash, to: &hasher)
      Self.add(UInt64(file.state.permissions), to: &hasher)
    }
    for (path, directory) in staged.directories.sorted(by: { $0.key < $1.key }) {
      Self.add("staged-directory", to: &hasher)
      Self.add(path, to: &hasher)
      Self.add(UInt64(directory.permissions), to: &hasher)
    }
    for (path, file) in staged.files.sorted(by: { $0.key < $1.key }) {
      Self.add("staged-file", to: &hasher)
      Self.add(path, to: &hasher)
      Self.add(file.hash, to: &hasher)
      Self.add(UInt64(file.state.permissions), to: &hasher)
    }
    return WorkingCopyFS.hex(hasher.finalize())
  }

  /// The issued record for an exact current proposal, or `nil` for an exact proposal this copy
  /// already applied. Anything else is unknown, stale or modified.
  private func authenticate(_ proposal: WorkingCopyProposal) throws -> IssuedProposal? {
    _ = try requireOpen()
    if let binding = appliedBindings[proposal.contentHash] {
      guard Self.proposalHash(binding: binding, changes: proposal.changes) == proposal.contentHash
      else {
        throw WorkingCopyFailure.refused("modified already-applied proposal body or preview")
      }
      return nil
    }
    guard let issued, issued.generation == generation,
      proposal.contentHash == issued.proposal.contentHash,
      Self.proposalHash(binding: issued.binding, changes: proposal.changes) == proposal.contentHash
    else {
      throw WorkingCopyFailure.refused("unknown, stale or modified proposal digest or body")
    }
    return issued
  }

  private func validateCurrent(_ record: IssuedProposal) throws {
    let roots = try verifyRoots()
    let staged = try scanStage(roots.working)
    try verifySupportedStage(staged)
    guard staged == record.stagedTree else {
      throw WorkingCopyFailure.refused("staged contents or identity changed after the proposal")
    }
    guard try scanSource(roots.source) == baseline else {
      throw WorkingCopyFailure.refused(
        "source conflict after the proposal; the whole known batch refused before effects")
    }
  }

  // MARK: - Export

  private func preflight(
    _ proposal: WorkingCopyProposal, source: WorkingCopyHandle
  ) throws -> [PlannedChange] {
    var parents: [String: WorkingCopyHandle] = [:]
    var seen: Set<String> = []
    var plan: [PlannedChange] = []
    plan.reserveCapacity(proposal.changes.count)
    for change in proposal.changes {
      guard seen.insert(change.path).inserted else {
        throw WorkingCopyFailure.refused("duplicate change path: \(change.path)")
      }
      let parts = try WorkingCopyFS.relativeComponents(change.path)
      guard let name = parts.last else {
        throw WorkingCopyFailure.refused("expected a nonempty relative path")
      }
      let parentRelative = parts.dropLast().joined(separator: "/")
      let parent: WorkingCopyHandle
      if let cached = parents[parentRelative] {
        parent = cached
      } else {
        parent = try WorkingCopyFS.openRelativeDirectory(
          root: source, rootPath: sourcePath, components: parts.dropLast(),
          device: sourceIdentity.device)
        parents[parentRelative] = parent
      }
      let parentPath =
        parentRelative.isEmpty ? sourcePath : WorkingCopyFS.childPath(sourcePath, parentRelative)
      let planned = PlannedChange(
        change: change, parent: parent, parentRelative: parentRelative, parentPath: parentPath,
        name: name)
      try checkParent(planned)
      try checkTarget(planned)
      plan.append(planned)
    }
    return plan
  }

  private func checkParent(_ planned: PlannedChange) throws {
    try WorkingCopyFS.verifyPath(planned.parent.value, planned.parentPath)
    let current = try WorkingCopyFS.metadata(planned.parent.value)
    try WorkingCopyFS.requireOwnedDirectory(current, path: planned.parentPath)
    try WorkingCopyFS.requireContentOnlyMetadata(planned.parent.value, metadata: current)
    let admitted = baseline.directories[planned.parentRelative]
    guard WorkingCopyDirectoryRecord(current) == admitted else {
      throw WorkingCopyFailure.refused("source parent directory changed: \(planned.parentPath)")
    }
  }

  /// A replaced or deleted target must still hold its exact admitted bytes and metadata; a
  /// created target must still be absent.
  private func checkTarget(_ planned: PlannedChange) throws {
    let path = planned.change.path
    guard let expected = baseline.files[path] else {
      guard try WorkingCopyFS.metadataAt(planned.parent.value, planned.name) == nil else {
        throw WorkingCopyFailure.refused("source create target already exists: \(path)")
      }
      return
    }
    let current = try WorkingCopyFS.readFile(
      parent: planned.parent.value, name: planned.name,
      expectedPath: WorkingCopyFS.childPath(sourcePath, path), device: sourceIdentity.device,
      buffer: &ioBuffer, maximumBytes: limits.maximumFileBytes)
    guard current.file == expected,
      let named = try WorkingCopyFS.metadataAt(planned.parent.value, planned.name),
      WorkingCopyFileState(named) == current.file.state
    else {
      throw WorkingCopyFailure.refused("source target conflict immediately before export: \(path)")
    }
  }

  /// A replacement keeps the admitted file's permission bits; a created file is private 0600.
  private func exportMode(for path: String) -> mode_t {
    baseline.files[path]?.state.permissions ?? 0o600
  }

  /// A replacement keeps its admitted group; a created file inherits its parent directory's.
  private func exportGroup(for planned: PlannedChange) -> gid_t? {
    baseline.files[planned.change.path]?.state.group
      ?? baseline.directories[planned.parentRelative]?.group
  }

  private func prepareTemporaries(_ plan: [PlannedChange], progress: inout ExportProgress) throws {
    for planned in plan where planned.change.kind != "delete" {
      guard let contents = planned.change.newContents else {
        throw WorkingCopyFailure.refused("issued content change has no immutable data")
      }
      try checkParent(planned)
      let name = ".memoshi-export-" + UUID().uuidString.lowercased()
      let path = WorkingCopyFS.childPath(planned.parentPath, name)
      let relativePath =
        planned.parentRelative.isEmpty ? name : planned.parentRelative + "/" + name
      let raw = Darwin.openat(
        planned.parent.value, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
        mode_t(0o600))
      guard raw >= 0 else { throw WorkingCopyFS.failure("openat exclusive export temporary") }
      // Owned before any later step can throw, so unwinding always accounts for it.
      progress.temporaryIndex[planned.change.path] = progress.temporaries.count
      progress.temporaries.append(
        Temporary(
          handle: WorkingCopyHandle(raw), parent: planned.parent, parentPath: planned.parentPath,
          name: name, relativePath: relativePath))
      try WorkingCopyFS.verifyPath(raw, path)
      let created = try WorkingCopyFS.metadata(raw)
      try WorkingCopyFS.requireRegular(created, path: path, device: sourceIdentity.device)
      try WorkingCopyFS.requireContentOnlyMetadata(raw, metadata: created)
      try contents.withUnsafeBytes { try WorkingCopyFS.writeAll(raw, $0) }
      if let original = baseline.files[planned.change.path] {
        guard Darwin.fchown(raw, original.state.owner, original.state.group) == 0 else {
          throw WorkingCopyFS.failure("preserve replacement owner and group on temporary")
        }
      }
      guard Darwin.fchmod(raw, exportMode(for: planned.change.path)) == 0 else {
        throw WorkingCopyFS.failure("fchmod export temporary")
      }
      guard Darwin.fsync(raw) == 0 else { throw WorkingCopyFS.failure("fsync export temporary") }
      let prepared = try WorkingCopyFS.metadata(raw)
      try WorkingCopyFS.requireRegular(prepared, path: path, device: sourceIdentity.device)
      try WorkingCopyFS.requireContentOnlyMetadata(raw, metadata: prepared)
      guard Int64(prepared.st_size) == Int64(contents.count),
        let named = try WorkingCopyFS.metadataAt(planned.parent.value, name),
        WorkingCopyObjectID(named) == WorkingCopyObjectID(prepared)
      else { throw WorkingCopyFailure.refused("export temporary changed during preparation") }
    }
  }

  /// Installs each planned change. `swap` is the source volume's reported `RENAME_SWAP` support;
  /// exclusive rename support was already required.
  private func install(
    _ plan: [PlannedChange], swap: Bool, progress: inout ExportProgress
  ) throws {
    for planned in plan {
      _ = try verifyRoots()
      try checkParent(planned)
      try checkTarget(planned)
      let path = planned.change.path
      if planned.change.kind == "delete" {
        try exportWillAffect(path)
        try deleteAdmitted(planned, progress: &progress)
        continue
      }
      guard let index = progress.temporaryIndex[path] else {
        throw WorkingCopyFailure.refused("prepared export temporary is missing: \(path)")
      }
      let temporary = progress.temporaries[index]
      let temporaryPath = WorkingCopyFS.childPath(temporary.parentPath, temporary.name)
      try WorkingCopyFS.verifyPath(temporary.handle.value, temporaryPath)
      let prepared = try WorkingCopyFS.metadata(temporary.handle.value)
      try WorkingCopyFS.requireRegular(
        prepared, path: temporaryPath, device: sourceIdentity.device)
      let frozen = try WorkingCopyFS.readFile(
        parent: planned.parent.value, name: temporary.name, expectedPath: temporaryPath,
        device: sourceIdentity.device, buffer: &ioBuffer, maximumBytes: limits.maximumFileBytes)
      guard frozen.file.state == WorkingCopyFileState(prepared),
        frozen.file.hash == planned.change.newHash,
        frozen.file.state.permissions == exportMode(for: path),
        frozen.file.state.group == exportGroup(for: planned)
      else {
        throw WorkingCopyFailure.refused("prepared export temporary changed: \(path)")
      }
      // Recheck the target after reading the prepared bytes, as close as possible to rename.
      try checkParent(planned)
      try checkTarget(planned)
      try exportWillAffect(path)
      if planned.change.kind == "create" {
        // RENAME_EXCL keeps a racing create from being overwritten.
        try Self.rename(
          planned.parent.value, temporary.name, planned.name, flags: RENAME_EXCL,
          operation: "exclusive per-file export rename")
      } else if swap {
        try swapAdmitted(planned, temporary: index, progress: &progress)
      } else {
        try replaceExclusively(planned, temporary: index, progress: &progress)
      }
      progress.temporaries[index].installed = true
      if !progress.completed.contains(path) { progress.completed.append(path) }
      let identity = WorkingCopyObjectID(prepared)
      progress.installed[path] = identity
      protectedSourceObjects.insert(identity)
      guard let current = try WorkingCopyFS.metadataAt(planned.parent.value, planned.name),
        WorkingCopyObjectID(current) == identity, current.st_nlink == 1
      else { throw WorkingCopyFailure.refused("source target changed immediately after rename") }
    }
  }

  /// Deletes an admitted original only after moving it to an exclusive Memoshi name and proving
  /// the moved object is still that original. An outside replacement or edit made after the
  /// final conflict check is renamed back to its name and the export refuses.
  private func deleteAdmitted(_ planned: PlannedChange, progress: inout ExportProgress) throws {
    let path = planned.change.path
    guard let expected = baseline.files[path] else {
      throw WorkingCopyFailure.refused("delete target was never admitted: \(path)")
    }
    let quarantine = ".memoshi-export-delete-" + UUID().uuidString.lowercased()
    let held = try displaceAdmitted(
      planned, to: quarantine, expected: expected, progress: &progress)
    try removeDisplaced(planned, name: quarantine, held: held, progress: &progress)
  }

  /// Installs a prepared replacement on a volume without swap support. The original is moved to
  /// an exclusive Memoshi name and proven to be the admitted original, then the replacement is
  /// renamed exclusively onto the freed name and the original is removed. A changed original is
  /// renamed back and refuses. A name recreated outside between the two renames is never
  /// overwritten: the install fails, the original goes back if its name is free again, or else
  /// stays at its reported Memoshi name, and the export refuses. The user's name is absent from
  /// the first rename until the install.
  private func replaceExclusively(
    _ planned: PlannedChange, temporary index: Int, progress: inout ExportProgress
  ) throws {
    let path = planned.change.path
    let temporary = progress.temporaries[index]
    guard let expected = baseline.files[path] else {
      throw WorkingCopyFailure.refused("replace target was never admitted: \(path)")
    }
    let prepared = WorkingCopyObjectID(try WorkingCopyFS.metadata(temporary.handle.value))
    let aside = ".memoshi-export-replace-" + UUID().uuidString.lowercased()
    let held = try displaceAdmitted(planned, to: aside, expected: expected, progress: &progress)
    guard
      Darwin.renameatx_np(
        planned.parent.value, temporary.name, planned.parent.value, planned.name,
        UInt32(RENAME_EXCL)) == 0
    else {
      let failure = WorkingCopyFS.failure("exclusive per-file export rename")
      try restoreDisplaced(
        planned, from: aside,
        cause: "the replacement could not be installed exclusively: \(failure)",
        progress: &progress)
    }
    progress.temporaries[index].installed = true
    progress.completed.append(path)
    progress.installed[path] = prepared
    protectedSourceObjects.insert(prepared)
    try removeDisplaced(planned, name: aside, held: held, progress: &progress)
  }

  /// Moves the object at a replaced or deleted name to an exclusive Memoshi name, then proves it
  /// is the admitted original. Otherwise it is renamed back and the export refuses.
  private func displaceAdmitted(
    _ planned: PlannedChange, to name: String, expected: WorkingCopyFileRecord,
    progress: inout ExportProgress
  ) throws -> WorkingCopyHandle {
    try Self.rename(
      planned.parent.value, planned.name, name, flags: RENAME_EXCL,
      operation: "exclusive move of the source original")
    do {
      try exportDidDisplace(planned.change.path)
      return try verifyDisplaced(planned, name: name, expected: expected)
    } catch {
      try restoreDisplaced(
        planned, from: name, cause: "source target changed after its final check: \(error)",
        progress: &progress)
    }
  }

  /// Renames a displaced object back to its name only while that name is free, then refuses.
  /// A reoccupied name keeps both objects: the displaced one stays at its reported Memoshi name.
  private func restoreDisplaced(
    _ planned: PlannedChange, from name: String, cause: String, progress: inout ExportProgress
  ) throws -> Never {
    guard
      Darwin.renameatx_np(
        planned.parent.value, name, planned.parent.value, planned.name, UInt32(RENAME_EXCL)) == 0
    else {
      let failure = WorkingCopyFS.failure("exclusive restore of the source original")
      progress.retained.append(relative(planned, name))
      throw WorkingCopyFailure.refused(
        "\(cause); the moved object could not be restored (\(failure)) and was kept at "
          + relative(planned, name))
    }
    throw WorkingCopyFailure.refused("\(cause); restored: \(planned.change.path)")
  }

  /// Installs a prepared replacement by atomically swapping it with the original name, then
  /// proves the swapped-out object is the admitted original before removing it. Otherwise the
  /// swap is reversed, the outside object is back at its name and the export refuses. The
  /// approved bytes are visible at the name only for that verification interval.
  private func swapAdmitted(
    _ planned: PlannedChange, temporary index: Int, progress: inout ExportProgress
  ) throws {
    let path = planned.change.path
    let temporary = progress.temporaries[index]
    guard let expected = baseline.files[path] else {
      throw WorkingCopyFailure.refused("replace target was never admitted: \(path)")
    }
    let prepared = WorkingCopyObjectID(try WorkingCopyFS.metadata(temporary.handle.value))
    try Self.rename(
      planned.parent.value, temporary.name, planned.name, flags: RENAME_SWAP,
      operation: "atomic per-file export swap")
    let held: WorkingCopyHandle
    do {
      try exportDidDisplace(path)
      held = try verifyDisplaced(planned, name: temporary.name, expected: expected)
    } catch {
      let displaced = try? WorkingCopyFS.metadataAt(planned.parent.value, temporary.name)
      let restored =
        Darwin.renameatx_np(
          planned.parent.value, temporary.name, planned.parent.value, planned.name,
          UInt32(RENAME_SWAP)) == 0
      let atName = try? WorkingCopyFS.metadataAt(planned.parent.value, planned.name)
      let atTemporary = try? WorkingCopyFS.metadataAt(planned.parent.value, temporary.name)
      guard restored, let displaced, let atName, let atTemporary,
        WorkingCopyObjectID(atName) == WorkingCopyObjectID(displaced),
        WorkingCopyObjectID(atTemporary) == prepared
      else {
        // The approved bytes may now be at the name and the outside object at the temporary.
        progress.temporaries[index].installed = true
        progress.completed.append(path)
        progress.installed[path] = prepared
        protectedSourceObjects.insert(prepared)
        progress.retained.append(temporary.relativePath)
        throw WorkingCopyFailure.refused(
          "source replace target changed after its final check and the swap could not be "
            + "verified as reversed: \(path): \(error)")
      }
      throw WorkingCopyFailure.refused(
        "source replace target changed after its final check; swap reversed: \(path): \(error)")
    }
    progress.temporaries[index].installed = true
    progress.completed.append(path)
    progress.installed[path] = prepared
    protectedSourceObjects.insert(prepared)
    try removeDisplaced(planned, name: temporary.name, held: held, progress: &progress)
  }

  /// Opens the object now at a Memoshi-owned name and proves it is exactly the admitted
  /// original: identity, bytes and metadata, except the change time a rename updates.
  private func verifyDisplaced(
    _ planned: PlannedChange, name: String, expected: WorkingCopyFileRecord
  ) throws -> WorkingCopyHandle {
    let raw = Darwin.openat(
      planned.parent.value, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard raw >= 0 else { throw WorkingCopyFS.failure("openat displaced source object") }
    let held = WorkingCopyHandle(raw)
    let read = try WorkingCopyFS.readFile(
      parent: planned.parent.value, name: name,
      expectedPath: WorkingCopyFS.childPath(planned.parentPath, name),
      device: sourceIdentity.device, buffer: &ioBuffer, maximumBytes: limits.maximumFileBytes)
    let current = read.file.state
    let admitted = expected.state
    guard read.file.hash == expected.hash, current.identity == admitted.identity,
      WorkingCopyObjectID(try WorkingCopyFS.metadata(held.value)) == admitted.identity,
      current.mode == admitted.mode, current.owner == admitted.owner,
      current.group == admitted.group, current.flags == admitted.flags,
      current.links == admitted.links, current.size == admitted.size,
      current.modifiedSeconds == admitted.modifiedSeconds,
      current.modifiedNanoseconds == admitted.modifiedNanoseconds
    else {
      throw WorkingCopyFailure.refused(
        "displaced source object is not the admitted original: \(planned.change.path)")
    }
    return held
  }

  /// Removes the verified original from its Memoshi name through ``removeHeld``, so an object
  /// renamed onto that name is never unlinked: it stays at its reported Memoshi path instead.
  private func removeDisplaced(
    _ planned: PlannedChange, name: String, held: WorkingCopyHandle,
    progress: inout ExportProgress
  ) throws {
    let path = planned.change.path
    try exportWillRemove(path)
    // The original has already left the user's name, so this change has had an effect.
    if !progress.completed.contains(path) { progress.completed.append(path) }
    do {
      try Self.removeHeld(
        held, named: name, in: planned.parent, parentPath: planned.parentPath,
        device: sourceIdentity.device,
        willClose: { try exportWillCloseRemoval(relative(planned, $0)) },
        willUnlink: { try exportWillUnlinkClosed(relative(planned, $0)) })
    } catch let refusal as RemovalRefusal {
      progress.retained += refusal.retained.map { relative(planned, $0) }
      throw WorkingCopyFailure.refused(
        "the moved original was not removed: \(path): \(refusal.cause)")
    }
  }

  /// Names a removal left in place, relative to its directory, and why.
  private struct RemovalRefusal: Error {
    let retained: [String]
    let cause: any Error
  }

  /// The well-known membership UUID of the `everyone` group,
  /// `ABCDEFAB-CDEF-ABCD-EFAB-CDEF0000000C`.
  private static let everyone: uuid_t = (
    0xAB, 0xCD, 0xEF, 0xAB, 0xCD, 0xEF, 0xAB, 0xCD, 0xEF, 0xAB, 0xCD, 0xEF, 0x00, 0x00, 0x00, 0x0C
  )

  /// Proves, before any source effect, that this mount enforces the deny entry that closes a
  /// removal directory. The volume capability names the format, not the mount: a volume can
  /// store ACLs and still not apply them (for example with ownership ignored), and there an
  /// object renamed into a "closed" directory would be unlinked. A fresh probe directory in
  /// the source root is closed to new entries; creating a directory in it must then fail with
  /// `EACCES` or `EPERM`. The probe and anything made in it are empty directories, removed by
  /// name, so no outside data can be lost; a probe that cannot be removed is reported.
  private func requireEnforcedClosure(in source: WorkingCopyHandle, device: UInt64) throws {
    let name = ".memoshi-export-probe-" + UUID().uuidString.lowercased()
    guard Darwin.mkdirat(source.value, name, 0o700) == 0 else {
      throw WorkingCopyFailure.refused(
        "the access control probe could not be created in the source; nothing was changed")
    }
    var enforced = false
    var failure: (any Error)?
    do {
      let probe = try WorkingCopyFS.openDirectory(
        source.value, name: name, expectedPath: WorkingCopyFS.childPath(sourcePath, name),
        device: device)
      defer { try? probe.close() }
      try Self.closeToNewEntries(probe)
      try exportDidCloseProbe(name)
      if Darwin.mkdirat(probe.value, "added", 0o700) == 0 {
        _ = Darwin.unlinkat(probe.value, "added", AT_REMOVEDIR)
      } else {
        enforced = errno == EACCES || errno == EPERM
      }
    } catch {
      failure = error
    }
    guard Darwin.unlinkat(source.value, name, AT_REMOVEDIR) == 0 else {
      throw WorkingCopyFailure.refused(
        "the access control probe \(name) could not be removed from the source; "
          + "no change was exported")
    }
    if let failure {
      throw WorkingCopyFailure.refused(
        "the access control probe could not be closed: \(failure); nothing was changed")
    }
    guard enforced else {
      throw WorkingCopyFailure.refused(
        "the source volume does not enforce access control lists, so a removal directory "
          + "cannot be closed to outside objects; nothing was changed")
    }
  }

  /// Sets one deny entry for everyone: no file or directory can be added to `directory`, by any
  /// rename, link or create, while its entries can still be removed.
  private static func closeToNewEntries(_ directory: WorkingCopyHandle) throws {
    var acl = acl_init(1)
    defer { if let acl { acl_free(UnsafeMutableRawPointer(acl)) } }
    var entry: acl_entry_t?
    var permissions: acl_permset_t?
    var group = everyone
    guard acl != nil, acl_create_entry(&acl, &entry) == 0, let entry,
      acl_set_tag_type(entry, ACL_EXTENDED_DENY) == 0,
      withUnsafeBytes(of: &group, { acl_set_qualifier(entry, $0.baseAddress) }) == 0,
      acl_get_permset(entry, &permissions) == 0, let permissions,
      acl_add_perm(permissions, ACL_ADD_FILE) == 0,
      acl_add_perm(permissions, ACL_ADD_SUBDIRECTORY) == 0,
      acl_set_permset(entry, permissions) == 0, let acl,
      acl_set_fd_np(directory.value, acl, ACL_TYPE_EXTENDED) == 0
    else { throw WorkingCopyFS.failure("close export removal directory to new entries") }
  }

  /// Removes `name` from `parent` only as `held`'s single-link object, so an object renamed onto
  /// the name is never unlinked. Darwin has no unlink conditioned on a descriptor, and a rename
  /// onto a name between any check and `unlinkat` would make that unlink remove the outside
  /// object, while the held object shows no link either way. So the object is moved exclusively
  /// into a fresh Memoshi directory, which a deny ACL for everyone then closes to every rename,
  /// link and create, this user's own included; only there is the entry checked and unlinked,
  /// and the empty directory removed. An object found instead is moved back to `name` while
  /// that is free, or stays in the reported directory. Before the deny entry is set, an outside
  /// process can still add to the directory: an object renamed onto the entry then fails the
  /// check made after the entry is set, and one added beside it can no longer be renamed onto
  /// the entry, so it stays and the directory, no longer empty, is reported. The deny entry does
  /// not bind root, nor a process of the same owner that edits or removes the directory's ACL
  /// first; either can still put an object there before the unlink. Every directory this
  /// removes by name is empty, so no outside data can be lost there. `willClose` and
  /// `willUnlink` are test barriers that receive the entry's path relative to `parent`: the
  /// first once the object was moved there, before the deny entry is set; the second after its
  /// last check, immediately before `unlinkat`.
  private static func removeHeld(
    _ held: WorkingCopyHandle, named name: String, in parent: WorkingCopyHandle,
    parentPath: String, device: UInt64, willClose: (String) throws -> Void = { _ in },
    willUnlink: (String) throws -> Void = { _ in }
  ) throws {
    func isHeld(_ current: stat?) throws -> Bool {
      let object = try WorkingCopyFS.metadata(held.value)
      guard let current else { return false }
      return WorkingCopyObjectID(current) == WorkingCopyObjectID(object) && object.st_nlink == 1
    }
    func existing(_ names: [String]) -> [String] {
      names.filter { (try? WorkingCopyFS.metadataAt(parent.value, $0)) != nil }
    }
    guard try isHeld(WorkingCopyFS.metadataAt(parent.value, name)) else {
      throw RemovalRefusal(
        retained: existing([name]),
        cause: WorkingCopyFailure.refused("the name no longer holds the verified object"))
    }
    let closed = ".memoshi-export-remove-" + UUID().uuidString.lowercased()
    guard Darwin.mkdirat(parent.value, closed, 0o700) == 0 else {
      throw RemovalRefusal(
        retained: [name], cause: WorkingCopyFS.failure("mkdirat export removal directory"))
    }
    let directory: WorkingCopyHandle
    do {
      directory = try WorkingCopyFS.openDirectory(
        parent.value, name: closed, expectedPath: WorkingCopyFS.childPath(parentPath, closed),
        device: device)
    } catch {
      _ = Darwin.unlinkat(parent.value, closed, AT_REMOVEDIR)
      throw RemovalRefusal(retained: existing([name, closed]), cause: error)
    }
    let entry = "removed"
    guard
      Darwin.renameatx_np(parent.value, name, directory.value, entry, UInt32(RENAME_EXCL)) == 0
    else {
      let failure = WorkingCopyFS.failure("exclusive move into the export removal directory")
      _ = Darwin.unlinkat(parent.value, closed, AT_REMOVEDIR)
      throw RemovalRefusal(retained: existing([name, closed]), cause: failure)
    }
    // An unexpected object goes back to its name while that is free; nothing is unlinked.
    func moveBack(_ cause: any Error) -> RemovalRefusal {
      if Darwin.renameatx_np(directory.value, entry, parent.value, name, UInt32(RENAME_EXCL)) == 0 {
        _ = Darwin.unlinkat(parent.value, closed, AT_REMOVEDIR)
      }
      return RemovalRefusal(retained: existing([name, closed]), cause: cause)
    }
    do {
      try willClose(closed + "/" + entry)
      try closeToNewEntries(directory)
    } catch {
      throw moveBack(error)
    }
    guard try isHeld(WorkingCopyFS.metadataAt(directory.value, entry)) else {
      throw moveBack(
        WorkingCopyFailure.refused("an outside object replaced the verified one before removal"))
    }
    do {
      try willUnlink(closed + "/" + entry)
    } catch {
      throw moveBack(error)
    }
    guard Darwin.unlinkat(directory.value, entry, 0) == 0 else {
      throw RemovalRefusal(
        retained: existing([closed]), cause: WorkingCopyFS.failure("unlinkat verified object"))
    }
    guard try WorkingCopyFS.metadata(held.value).st_nlink == 0 else {
      throw RemovalRefusal(
        retained: existing([closed]),
        cause: WorkingCopyFailure.refused("another link to the removed object remains"))
    }
    let opened = try WorkingCopyFS.metadata(directory.value)
    guard let current = try? WorkingCopyFS.metadataAt(parent.value, closed),
      WorkingCopyObjectID(current) == WorkingCopyObjectID(opened),
      Darwin.unlinkat(parent.value, closed, AT_REMOVEDIR) == 0
    else {
      throw RemovalRefusal(
        retained: existing([closed]),
        cause: WorkingCopyFailure.refused("the empty export removal directory was not removed"))
    }
  }

  private func relative(_ planned: PlannedChange, _ name: String) -> String {
    planned.parentRelative.isEmpty ? name : planned.parentRelative + "/" + name
  }

  /// The source volume's own report of atomic rename support. Selection uses this report, never
  /// a path or file-system name, and never the call's result alone: an observed FAT32 volume
  /// reports neither flag yet completes both as an ordinary, overwriting rename.
  private struct RenameSupport {
    /// `RENAME_EXCL`: a move that fails, instead of replacing, when the destination exists.
    let exclusive: Bool
    /// `RENAME_SWAP`: an atomic exchange of two existing names.
    let swap: Bool
    /// Access control lists, which close a removal directory to new entries.
    let accessControlLists: Bool
  }

  /// Reads the volume capabilities through an open directory descriptor. A flag counts only
  /// when the volume reports it as both valid and supported.
  private static func renameSupport(_ directory: WorkingCopyHandle) throws -> RenameSupport {
    var request = attrlist()
    request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
    request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_CAPABILITIES)
    // The reply is a u_int32_t length, then vol_capabilities_attr_t: four capability words
    // followed by four valid words.
    var reply = [UInt32](repeating: 0, count: 9)
    let status = reply.withUnsafeMutableBytes {
      Darwin.fgetattrlist(directory.value, &request, $0.baseAddress, $0.count, 0)
    }
    guard status == 0 else { throw WorkingCopyFS.failure("read source volume capabilities") }
    let interfaces = Int(VOL_CAPABILITIES_INTERFACES)
    let reported = reply[1 + interfaces] & reply[5 + interfaces]
    return RenameSupport(
      exclusive: reported & UInt32(VOL_CAP_INT_RENAME_EXCL) != 0,
      swap: reported & UInt32(VOL_CAP_INT_RENAME_SWAP) != 0,
      accessControlLists: reported & UInt32(VOL_CAP_INT_EXTENDED_SECURITY) != 0)
  }

  /// One same-directory `renameatx_np`. A volume that cannot provide the requested atomic
  /// semantics refuses before any effect; nothing falls back to a plain rename.
  private static func rename(
    _ parent: Int32, _ from: String, _ to: String, flags: Int32, operation: String
  ) throws {
    guard Darwin.renameatx_np(parent, from, parent, to, UInt32(flags)) == 0 else {
      let code = errno
      if code == ENOTSUP || code == EINVAL {
        throw WorkingCopyFailure.refused(
          "the source volume does not support \(operation); nothing was changed")
      }
      throw WorkingCopyFailure.system(operation: operation, code: code)
    }
  }

  /// Proves the whole source now holds exactly the baseline plus this batch, then advances the
  /// baseline so a later proposal starts from the exported state.
  private func finishExport(
    _ record: IssuedProposal, plan: [PlannedChange], progress: ExportProgress,
    source: WorkingCopyHandle
  ) throws {
    let finalTree = try scanSource(source)
    var expectedPaths = Set(baseline.files.keys)
    var plannedByPath: [String: PlannedChange] = [:]
    for planned in plan {
      plannedByPath[planned.change.path] = planned
      if planned.change.kind == "delete" {
        expectedPaths.remove(planned.change.path)
      } else {
        expectedPaths.insert(planned.change.path)
      }
    }
    guard finalTree.directories == baseline.directories,
      Set(finalTree.files.keys) == expectedPaths
    else { throw WorkingCopyFailure.refused("source tree changed during export") }
    for (path, file) in finalTree.files {
      guard let planned = plannedByPath[path] else {
        guard file == baseline.files[path] else {
          throw WorkingCopyFailure.refused("unchanged source file changed during export: \(path)")
        }
        continue
      }
      guard file.hash == planned.change.newHash, file.state.identity == progress.installed[path],
        file.state.permissions == exportMode(for: path),
        file.state.group == exportGroup(for: planned)
      else {
        throw WorkingCopyFailure.refused("exported bytes, identity or mode changed: \(path)")
      }
    }
    baseline = finalTree
    protectedSourceObjects.formUnion(finalTree.identities)
    for planned in plan {
      if planned.change.kind == "delete" {
        expectedWorkingFiles.removeValue(forKey: planned.change.path)
      } else if let state = record.stagedTree.files[planned.change.path]?.state {
        expectedWorkingFiles[planned.change.path] = StagedMode(
          mode: state.permissions, group: state.group)
      }
    }
    appliedBindings[record.proposal.contentHash] = record.binding
    generation += 1
    issued = nil
  }

  /// Removes unused temporaries. Any completed effect or unremoved temporary becomes an explicit
  /// partial outcome that poisons this copy; otherwise the original refusal stands.
  private func unwind(
    _ failure: any Error, proposal: WorkingCopyProposal, progress: ExportProgress
  ) -> any Error {
    var remaining: [String] = progress.retained
    var cleanupErrors: [String] = []
    for temporary in progress.temporaries where !temporary.installed {
      do {
        try Self.removeTemporary(temporary)
      } catch let refusal as RemovalRefusal {
        let parent = String(temporary.relativePath.dropLast(temporary.name.count))
        remaining += refusal.retained.map { parent + $0 }
        cleanupErrors.append(String(describing: refusal.cause))
      } catch {
        remaining.append(temporary.relativePath)
        cleanupErrors.append(String(describing: error))
      }
    }
    guard !progress.completed.isEmpty || !remaining.isEmpty else { return failure }
    var cause = String(describing: failure)
    if !cleanupErrors.isEmpty {
      cause += "; temporary cleanup: " + cleanupErrors.joined(separator: "; ")
    }
    let partial = WorkingCopyFailure.partialApplication(
      contentHash: proposal.contentHash, completedPaths: progress.completed,
      remainingTemporaryPaths: remaining, cause: cause)
    exportFailure = partial
    issued = nil
    return partial
  }

  /// Removes an uninstalled temporary only while its name still denotes the owned single-link
  /// file, through ``removeHeld``. A moved or extra-linked temporary may still hold prepared
  /// bytes, and an object renamed onto its name is an outside object, so either stays a reported
  /// unknown effect instead.
  private static func removeTemporary(_ temporary: Temporary) throws {
    guard !temporary.installed else { return }
    try WorkingCopyFS.verifyPath(temporary.parent.value, temporary.parentPath)
    let opened = try WorkingCopyFS.metadata(temporary.handle.value)
    guard let named = try WorkingCopyFS.metadataAt(temporary.parent.value, temporary.name) else {
      // An absent name proves nothing remains only when no link holds the bytes elsewhere.
      guard opened.st_nlink == 0 else {
        throw WorkingCopyFailure.refused("export temporary moved; prepared bytes may remain")
      }
      return
    }
    guard WorkingCopyObjectID(named) == WorkingCopyObjectID(opened),
      named.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), opened.st_nlink == 1
    else {
      throw WorkingCopyFailure.refused("export temporary was replaced or linked; not removed")
    }
    try removeHeld(
      temporary.handle, named: temporary.name, in: temporary.parent,
      parentPath: temporary.parentPath, device: WorkingCopyObjectID(opened).device)
  }

  // MARK: - Private cleanup

  /// Removes the whole private root after proving its container path, its name and every removed
  /// object. A source object, a foreign device or a source moved inside refuses instead.
  private static func removeOwnedRoot(
    source: WorkingCopyHandle?, container: WorkingCopyHandle, containerPath: String,
    containerIdentity: WorkingCopyObjectID, working: WorkingCopyHandle, workingRoot: String,
    workingName: String, protected: Set<WorkingCopyObjectID>,
    willRemove: @escaping @Sendable (String) throws -> Void
  ) throws {
    let reopened = try WorkingCopyFS.openAbsoluteDirectory(containerPath)
    guard WorkingCopyObjectID(reopened.metadata) == containerIdentity else {
      throw WorkingCopyFailure.refused("container path changed; private cleanup refused")
    }
    if let source {
      let liveSource = try WorkingCopyFS.descriptorPath(source.value)
      guard !WorkingCopyFS.isWithin(liveSource, workingRoot) else {
        throw WorkingCopyFailure.refused("source moved into the private root; cleanup refused")
      }
    }
    try removePrivateRoot(
      container: container, containerPath: containerPath, name: workingName, root: working,
      rootPath: workingRoot, protected: protected, createdOnly: nil, willRemove: willRemove)
  }

  /// Removes one private root and everything beneath it without following any name. With
  /// `createdOnly`, every removed object must be one this admission created; any other object
  /// refuses cleanup and stays in place.
  private static func removePrivateRoot(
    container: WorkingCopyHandle, containerPath: String, name: String, root: WorkingCopyHandle,
    rootPath: String, protected: Set<WorkingCopyObjectID>,
    createdOnly: Set<WorkingCopyObjectID>?, willRemove: @escaping @Sendable (String) throws -> Void
  ) throws {
    try WorkingCopyFS.verifyPath(container.value, containerPath)
    try WorkingCopyFS.verifyPath(root.value, rootPath)
    let identity = WorkingCopyObjectID(try WorkingCopyFS.metadata(root.value))
    guard !protected.contains(identity), createdOnly?.contains(identity) ?? true,
      let named = try WorkingCopyFS.metadataAt(container.value, name),
      WorkingCopyObjectID(named) == identity
    else { throw WorkingCopyFailure.refused("private root name or identity changed") }
    // Byte-exact from here, so cleanup also removes private names the scanner refuses.
    let rootBytes = try WorkingCopyFS.rawDescriptorPath(root.value)
    let quarantineName = ".memoshi-cleanup-" + UUID().uuidString.lowercased()
    guard Darwin.mkdirat(container.value, quarantineName, 0o700) == 0 else {
      throw WorkingCopyFS.failure("mkdirat private cleanup quarantine")
    }
    do {
      let quarantine = CleanupQuarantine(
        handle: try WorkingCopyFS.openDirectory(
          container.value, name: quarantineName,
          expectedPath: WorkingCopyFS.childPath(containerPath, quarantineName),
          device: identity.device),
        willRemove: willRemove)
      var remaining = WorkingCopyLimits.standard.maximumEntries
      try removeChildren(
        root.value, path: rootBytes, device: identity.device, protected: protected,
        createdOnly: createdOnly, depth: 0, remaining: &remaining, quarantine: quarantine)
      guard let current = try WorkingCopyFS.metadataAt(container.value, name),
        WorkingCopyObjectID(current) == identity
      else { throw WorkingCopyFailure.refused("private root changed before removal") }
      try WorkingCopyFS.verifyPath(container.value, containerPath)
      try WorkingCopyFS.verifyPath(root.value, rootPath)
      guard Darwin.unlinkat(container.value, name, AT_REMOVEDIR) == 0 else {
        throw WorkingCopyFS.failure("unlinkat private root")
      }
    } catch {
      // Removes only an empty quarantine; one holding an unrestorable object stays reported.
      _ = Darwin.unlinkat(container.value, quarantineName, AT_REMOVEDIR)
      throw error
    }
    guard Darwin.unlinkat(container.value, quarantineName, AT_REMOVEDIR) == 0 else {
      throw WorkingCopyFS.failure("unlinkat empty private cleanup quarantine")
    }
  }

  /// A fresh Memoshi-only directory in the 0700 container, outside every sandbox profile root.
  /// Cleanup moves each checked entry there and proves its identity before removing it.
  private struct CleanupQuarantine {
    let handle: WorkingCopyHandle
    let willRemove: @Sendable (String) throws -> Void
  }

  /// Moves one checked private entry into the quarantine, proves the moved object is the
  /// checked one, then removes it. An object swapped onto the name after the check is renamed
  /// back, or kept in the quarantine if its name was reoccupied, and cleanup refuses.
  private static func removeEntry(
    _ directory: Int32, name: [CChar], identity: WorkingCopyObjectID, path: [UInt8],
    quarantine: CleanupQuarantine, flags: Int32
  ) throws {
    try requireUnchanged(directory, name: name, identity: identity, path: path)
    try quarantine.willRemove(entryName(name))
    let parked = ".memoshi-removing-" + UUID().uuidString.lowercased()
    guard
      Darwin.renameatx_np(directory, name, quarantine.handle.value, parked, UInt32(RENAME_EXCL))
        == 0
    else { throw WorkingCopyFS.failure("move private cleanup entry into quarantine") }
    guard let moved = try WorkingCopyFS.metadataAt(quarantine.handle.value, parked),
      WorkingCopyObjectID(moved) == identity
    else {
      guard
        Darwin.renameatx_np(quarantine.handle.value, parked, directory, name, UInt32(RENAME_EXCL))
          == 0
      else {
        throw WorkingCopyFailure.refused(
          "private cleanup entry was replaced after its check and its name was reoccupied; "
            + "the replacement stays in the cleanup quarantine")
      }
      throw WorkingCopyFailure.refused(
        "private cleanup entry was replaced after its check; it was restored, not removed")
    }
    guard Darwin.unlinkat(quarantine.handle.value, parked, flags) == 0 else {
      throw WorkingCopyFS.failure("unlinkat quarantined private cleanup entry")
    }
  }

  private static func removeChildren(
    _ directory: Int32, path: [UInt8], device: UInt64, protected: Set<WorkingCopyObjectID>,
    createdOnly: Set<WorkingCopyObjectID>?, depth: Int, remaining: inout Int,
    quarantine: CleanupQuarantine
  ) throws {
    guard try WorkingCopyFS.rawDescriptorPath(directory) == path else {
      throw WorkingCopyFailure.refused("private cleanup directory moved")
    }
    let current = try WorkingCopyFS.metadata(directory)
    let identity = WorkingCopyObjectID(current)
    guard identity.device == device, !protected.contains(identity),
      createdOnly?.contains(identity) ?? true, current.st_uid == geteuid()
    else {
      throw WorkingCopyFailure.refused("source, foreign or unrecorded directory in cleanup")
    }
    // Restore only an owned private directory's owner access, never a source mode.
    if current.st_mode & 0o700 != 0o700 {
      guard Darwin.fchmod(directory, (current.st_mode & 0o777) | 0o700) == 0 else {
        throw WorkingCopyFS.failure("restore private cleanup access")
      }
    }
    let names = try rawEntryNames(directory, maximumEntries: remaining)
    remaining -= names.count
    for name in names {
      var before = stat()
      guard Darwin.fstatat(directory, name, &before, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw WorkingCopyFS.failure("fstatat private cleanup entry")
      }
      let entry = WorkingCopyObjectID(before)
      guard entry.device == device, !protected.contains(entry),
        createdOnly?.contains(entry) ?? true
      else {
        throw WorkingCopyFailure.refused("source, foreign or unrecorded entry in cleanup")
      }
      if before.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
        guard depth < WorkingCopyLimits.standard.maximumDepth else {
          throw WorkingCopyFailure.resourceLimitExceeded
        }
        let raw = Darwin.openat(directory, name, O_EVTONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard raw >= 0 else { throw WorkingCopyFS.failure("openat private cleanup directory") }
        let child = WorkingCopyHandle(raw)
        guard WorkingCopyObjectID(try WorkingCopyFS.metadata(child.value)) == entry else {
          throw WorkingCopyFailure.refused("private cleanup child changed during open")
        }
        try WorkingCopyFS.requireCloexec(child.value)
        try removeChildren(
          child.value, path: path + [47] + name.dropLast().map { UInt8(bitPattern: $0) },
          device: device, protected: protected, createdOnly: createdOnly,
          depth: depth + 1, remaining: &remaining, quarantine: quarantine)
        try removeEntry(
          directory, name: name, identity: entry, path: path, quarantine: quarantine,
          flags: AT_REMOVEDIR)
        withExtendedLifetime(child) {}
      } else {
        try removeEntry(
          directory, name: name, identity: entry, path: path, quarantine: quarantine, flags: 0)
      }
    }
  }

  /// A raw NUL-terminated entry name, decoded only for the test barrier.
  private static func entryName(_ name: [CChar]) -> String {
    String(decoding: name.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  /// The name still denotes the identified entry, in a directory that has not moved.
  private static func requireUnchanged(
    _ directory: Int32, name: [CChar], identity: WorkingCopyObjectID, path: [UInt8]
  ) throws {
    var current = stat()
    guard Darwin.fstatat(directory, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
      WorkingCopyObjectID(current) == identity,
      try WorkingCopyFS.rawDescriptorPath(directory) == path
    else { throw WorkingCopyFailure.refused("private cleanup entry changed before removal") }
  }

  /// Every raw entry name except dot entries, NUL-terminated and unvalidated: cleanup must also
  /// remove private names the scanner refuses, and it never follows them. Names are collected
  /// before any removal, so enumeration never races this copy's own unlinks.
  private static func rawEntryNames(
    _ directory: Int32, maximumEntries: Int
  ) throws -> [[CChar]] {
    let raw = Darwin.openat(directory, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard raw >= 0 else { throw WorkingCopyFS.failure("open private cleanup enumeration") }
    guard let stream = fdopendir(raw) else {
      let code = errno
      Darwin.close(raw)
      throw WorkingCopyFailure.system(operation: "fdopendir private cleanup", code: code)
    }
    defer { closedir(stream) }
    try WorkingCopyFS.requireCloexec(raw)
    var names: [[CChar]] = []
    while true {
      errno = 0
      guard let entry = readdir(stream) else {
        if errno != 0 { throw WorkingCopyFS.failure("readdir private cleanup") }
        break
      }
      let length = Int(entry.pointee.d_namlen)
      let name = withUnsafeBytes(of: &entry.pointee.d_name) { bytes in
        bytes.prefix(length).map { CChar(bitPattern: $0) } + [0]
      }
      if name == [46, 0] || name == [46, 46, 0] { continue }
      guard names.count < maximumEntries else { throw WorkingCopyFailure.resourceLimitExceeded }
      names.append(name)
    }
    return names
  }

  // MARK: - Digests

  private static func proposalHash(binding: String, changes: [WorkingCopyChange]) -> String {
    var hasher = SHA256()
    add("Memoshi.PrivateWorkingCopy.proposal.v1", to: &hasher)
    add(binding, to: &hasher)
    add(UInt64(changes.count), to: &hasher)
    for change in changes {
      add(change.path, to: &hasher)
      add(change.kind, to: &hasher)
      addOptional(change.baseHash, to: &hasher)
      addOptional(change.newHash, to: &hasher)
      if let contents = change.newContents {
        add(1, to: &hasher)
        add(UInt64(contents.count), to: &hasher)
        contents.withUnsafeBytes { hasher.update(bufferPointer: $0) }
      } else {
        add(0, to: &hasher)
      }
    }
    return WorkingCopyFS.hex(hasher.finalize())
  }

  /// Length-prefixed UTF-8, so adjacent fields can never be reframed.
  private static func add(_ string: String, to hasher: inout SHA256) {
    add(UInt64(string.utf8.count), to: &hasher)
    var bytes = string
    bytes.withUTF8 { hasher.update(bufferPointer: UnsafeRawBufferPointer($0)) }
  }

  private static func add(_ number: UInt64, to hasher: inout SHA256) {
    withUnsafeBytes(of: number.bigEndian) { hasher.update(bufferPointer: $0) }
  }

  private static func addOptional(_ value: String?, to hasher: inout SHA256) {
    if let value {
      add(1, to: &hasher)
      add(value, to: &hasher)
    } else {
      add(0, to: &hasher)
    }
  }
}
