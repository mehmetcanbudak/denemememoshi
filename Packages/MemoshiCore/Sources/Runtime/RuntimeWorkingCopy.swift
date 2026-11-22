import CryptoKit
import Foundation
import MemoshiProtocol
import MemoshiStore

/// Presentation-safe copy failures. Native diagnostics, bookmark bytes and source contents
/// never become an error description sent to the app or model.
public enum RuntimeWorkingCopyError: Error, Equatable, Sendable {
  case unavailable
  case invalidProposal
  case noChanges
  case outcomeUnknown
  case cleanupRequired
  /// Source or staged metadata cannot be represented without losing information.
  case unsupportedMetadata
  /// A trusted profile was invalid or attempted to widen the development ceilings.
  case invalidLimits
  /// Admission, traversal, frozen bytes or canonical arguments exceeded the trusted profile.
  case resourceLimitExceeded
  /// Local ownership or an effect receipt could not be committed; never report success.
  case journalUnavailable
}

/// One immutable, content-bound proposal issued by a live private copy. The tool uses the
/// existing mandatory policy hooks; these arguments are an intent, never an approval.
public struct WorkingCopyExport: Sendable {
  /// The engine-issued digest binding the session, source baseline and exact proposed bytes.
  public let contentHash: String
  /// The exact immutable intent to submit; editing even canonically equivalent bytes refuses it.
  public let arguments: MemoshiProtocol.JSONValue
  /// The real Chat-scoped export definition for trusted runtime composition, not an approval.
  public let tool: RuntimeToolDefinition
}

/// Trusted host file-data admission and policy-controlled export for one granted local Chat.
/// This does not start PiEnv or register a product tool. A caller must explicitly close its
/// copy. Reopening reports retained ownership and unknown outcomes, never attaches or exports.
/// The content-only profile refuses ACLs, file flags, extended attributes and resource forks
/// rather than stripping them. OS-managed provenance stays owned by macOS. This remains a
/// bounded plain-file path, not a general-purpose metadata-preserving editor.
public actor RuntimeWorkingCopy {
  /// Store-local ownership, not a new protocol object or authority token.
  public nonisolated let id: UUID
  /// The independent private directory, never an allowance for a model to access live sources.
  public nonisolated let workingRoot: String
  /// The persisted local conversation that owns the copy and may discover its export definition.
  public nonisolated let chatID: ConversationID
  /// The original source grant; its captured revision must remain current for every operation.
  public nonisolated let grantID: GrantID

  private let binding: SourceFolderBinding
  private let engine: PrivateWorkingCopy
  private nonisolated let limits: WorkingCopyLimits
  private var issued: IssuedExport?
  private var closed = false
  private var outcomeUncertain = false
  /// Proposals whose committed receipt says this copy's export applied nothing. The journal
  /// keeps one row per live copy and proposal, so this is that row's state, bounded with it.
  private var refused: Set<String> = []

  private struct IssuedExport: Sendable {
    let proposal: WorkingCopyProposal
    let argumentsHash: String
    let arguments: MemoshiProtocol.JSONValue
  }

  private init(
    engine: PrivateWorkingCopy, binding: SourceFolderBinding, ownership: WorkingCopyOwnership,
    limits: WorkingCopyLimits
  ) {
    self.engine = engine
    self.binding = binding
    self.id = ownership.id
    self.chatID = ownership.chatID
    self.limits = limits
    self.grantID = binding.grantID
    self.workingRoot = engine.workingRoot
  }

  /// A read grant permits admission, not later export. The importer compares its opened
  /// source identity before copying and inspects every original-namespace entry before read.
  public static func admit(
    binding: SourceFolderBinding, chatID: ConversationID, containerRoot: String,
    limits: WorkingCopyLimits = .standard
  ) async throws -> RuntimeWorkingCopy {
    #if os(macOS)
      try limits.validate()
      var engine: PrivateWorkingCopy?
      var ownership: WorkingCopyOwnership?
      do {
        try binding.validateWorkingCopyContainer(containerRoot)
        let container = try WorkingCopyFS.openAbsoluteDirectory(containerRoot)
        try WorkingCopyFS.requireOwnedDirectory(
          container.metadata, path: container.path, privateContainer: true)
        let containerID = WorkingCopyObjectID(container.metadata)
        let sourceID = try await binding.workingCopyAuthority(chatID: chatID, access: .read)
        let reserved = try await binding.store.reserveWorkingCopy(
          chatID: chatID, grant: binding.reference, containerRoot: containerRoot,
          containerIdentity: FolderSourceIdentity(
            device: containerID.device, inode: containerID.inode),
          at: IDGenerator.nowMilliseconds())
        ownership = reserved
        guard reserved.sourceIdentity == sourceID else {
          throw RuntimeWorkingCopyError.unavailable
        }
        let admitted = try withExtendedLifetime(container) {
          try PrivateWorkingCopy(
            sourceRoot: binding.sourceRoot, containerRoot: containerRoot, ownership: reserved,
            limits: limits, validateEntry: { try binding.validateWorkingCopyEntry($0) })
        }
        engine = admitted
        _ = try await binding.workingCopyAuthority(chatID: chatID, access: .read)
        let privateID = admitted.workingIdentity
        try await binding.store.activateWorkingCopy(
          reserved.id,
          workingIdentity: FolderSourceIdentity(device: privateID.device, inode: privateID.inode),
          at: IDGenerator.nowMilliseconds())
        return RuntimeWorkingCopy(
          engine: admitted, binding: binding, ownership: reserved, limits: limits)
      } catch {
        var cleanupFailed = false
        if case WorkingCopyFailure.cleanupFailed = error { cleanupFailed = true }
        if let engine {
          do { try await engine.close() } catch { cleanupFailed = true }
        }
        if let ownership {
          do {
            try await binding.store.finishWorkingCopyCleanup(
              ownership.id, removed: !cleanupFailed, at: IDGenerator.nowMilliseconds())
          } catch {
            if !cleanupFailed { throw RuntimeWorkingCopyError.journalUnavailable }
          }
        }
        if cleanupFailed { throw RuntimeWorkingCopyError.cleanupRequired }
        switch error {
        case WorkingCopyFailure.unsupportedMetadata:
          throw RuntimeWorkingCopyError.unsupportedMetadata
        case WorkingCopyFailure.resourceLimitExceeded:
          throw RuntimeWorkingCopyError.resourceLimitExceeded
        default: throw RuntimeWorkingCopyError.unavailable
        }
      }
    #else
      throw SourceFolderAuthorityError.unsupportedPlatform
    #endif
  }

  /// Static host composition can register this definition before private edits exist.
  /// No export is authorized until an exact current proposal has been frozen explicitly.
  public nonisolated var exportTool: RuntimeToolDefinition {
    RuntimeToolDefinition(
      name: WorkingCopyExportTool.name,
      description: "Export the exact immutable, reviewed changes from this Chat's private copy.",
      parameters: Self.argumentSchema(maximumChanges: limits.maximumChanges),
      resultSchema: Self.resultSchema, chatID: chatID,
      operation: .fileWrite, replaySafe: false,
      authorize: { arguments in
        do {
          _ = try await self.resolve(arguments)
          return true
        } catch { return false }
      },
      sourceTargets: { arguments in try await self.targets(arguments) },
      execute: { arguments, invocation in
        let runtimeTaskKey = invocation.runtimeTaskKey
        let callID = invocation.callID
        let fence = invocation.fence
        return try await invocation.runCancellable {
          try await self.execute(
            arguments, runtimeTaskKey: runtimeTaskKey, callID: callID, fence: fence)
        }
      })
  }

  /// Freezes exact bytes and original paths. Creating a proposal changes no source file and
  /// grants no authority; a newer proposal invalidates an older in-flight intent.
  public func exportProposal() async throws -> WorkingCopyExport {
    guard !outcomeUncertain else { throw RuntimeWorkingCopyError.outcomeUnknown }
    guard !closed else { throw RuntimeWorkingCopyError.unavailable }
    do {
      _ = try await binding.workingCopyAuthority(chatID: chatID, access: .read)
      let proposal = try await engine.proposal()
      guard !proposal.changes.isEmpty else { throw RuntimeWorkingCopyError.noChanges }
      _ = try await binding.workingCopyAuthority(chatID: chatID, access: .read)
      guard !closed else { throw RuntimeWorkingCopyError.unavailable }
      let arguments = Self.arguments(proposal)
      var canonical = arguments.canonicalText
      guard canonical.utf8.count <= limits.maximumArgumentBytes else {
        throw RuntimeWorkingCopyError.resourceLimitExceeded
      }
      var hasher = SHA256()
      canonical.withUTF8 { hasher.update(bufferPointer: UnsafeRawBufferPointer($0)) }
      issued = IssuedExport(
        proposal: proposal, argumentsHash: WorkingCopyFS.hex(hasher.finalize()),
        arguments: arguments)
      return WorkingCopyExport(
        contentHash: proposal.contentHash, arguments: arguments, tool: exportTool)
    } catch let failure as RuntimeWorkingCopyError {
      throw failure
    } catch WorkingCopyFailure.partialApplication {
      throw RuntimeWorkingCopyError.outcomeUnknown
    } catch WorkingCopyFailure.unsupportedMetadata {
      throw RuntimeWorkingCopyError.unsupportedMetadata
    } catch WorkingCopyFailure.resourceLimitExceeded {
      throw RuntimeWorkingCopyError.resourceLimitExceeded
    } catch {
      throw RuntimeWorkingCopyError.invalidProposal
    }
  }

  /// Removes only the independent, descriptor-owned private data. Failed cleanup is reported,
  /// never treated as success or expanded into removal of a caller-supplied path.
  public func close() async throws {
    closed = true
    issued = nil
    do { try await engine.close() } catch {
      try? await binding.store.finishWorkingCopyCleanup(
        id, removed: false, at: IDGenerator.nowMilliseconds())
      throw RuntimeWorkingCopyError.cleanupRequired
    }
    do {
      try await binding.store.finishWorkingCopyCleanup(
        id, removed: true, at: IDGenerator.nowMilliseconds())
    } catch { throw RuntimeWorkingCopyError.journalUnavailable }
  }

  private func resolve(_ arguments: MemoshiProtocol.JSONValue) async throws -> IssuedExport {
    guard !outcomeUncertain else { throw RuntimeWorkingCopyError.outcomeUnknown }
    guard !closed, let current = issued, Self.sameArguments(arguments, current.arguments) else {
      throw RuntimeWorkingCopyError.invalidProposal
    }
    _ = try await binding.workingCopyAuthority(chatID: chatID, access: .write)
    try await engine.validate(current.proposal)
    _ = try await binding.workingCopyAuthority(chatID: chatID, access: .write)
    guard !closed, issued?.argumentsHash == current.argumentsHash else {
      throw RuntimeWorkingCopyError.invalidProposal
    }
    return current
  }

  private func targets(_ arguments: MemoshiProtocol.JSONValue) throws -> [RuntimeSourceTarget] {
    guard !closed, let current = issued,
      Self.sameArguments(arguments, current.arguments)
    else {
      throw RuntimeWorkingCopyError.invalidProposal
    }
    return try current.proposal.changes.map { try binding.target($0.path) }
  }

  private func execute(
    _ arguments: MemoshiProtocol.JSONValue, runtimeTaskKey: String, callID: String,
    fence: ConversationFence
  ) async throws -> RuntimeToolResult {
    // Every exit before `engine.apply` provably changed no source file: it reports a known
    // no-effect refusal, never the unknown outcome that holds the whole Chat.
    let current: IssuedExport
    do {
      current = try await resolve(arguments)
    } catch RuntimeWorkingCopyError.outcomeUnknown {
      throw RuntimeWorkingCopyError.outcomeUnknown
    } catch {
      throw RuntimeToolExecutionError.notApplied
    }
    let openWriters = await openWriters(current.proposal)
    let admission: WorkingCopyExportAdmission
    do {
      admission = try await binding.store.beginWorkingCopyExport(
        id, contentHash: current.proposal.contentHash, argumentsHash: current.argumentsHash,
        changes: current.proposal.changes.map {
          WorkingCopyExportChange(
            path: $0.path, operation: $0.kind, baseHash: $0.baseHash, newHash: $0.newHash)
        }, runtimeTaskKey: runtimeTaskKey, callID: callID, fence: fence,
        at: IDGenerator.nowMilliseconds())
    } catch WorkingCopyJournalError.recoveryRequired {
      // The journal never dispatches a proposal twice. An earlier export of this copy that is
      // pending or unknown stays unknown; one this copy recorded as not applied is refused
      // again, with nothing attempted.
      guard refused.contains(current.proposal.contentHash) else {
        throw RuntimeWorkingCopyError.outcomeUnknown
      }
      return Self.result(
        current.proposal, outcome: "not_applied",
        text:
          "This exact proposal was already refused without changing any source file. A changed proposal is required.",
        isError: true, effectOutcome: .notApplied)
    } catch {
      // No intent was journaled, so no source effect was attempted.
      throw RuntimeToolExecutionError.notApplied
    }
    if admission == .alreadyApplied {
      return Self.result(
        current.proposal, outcome: "already_applied",
        text: "This exact proposal was already applied. This call changed no source file.")
    }
    do {
      // The journal actor hop is not permission: refresh authority and frozen data afterward.
      _ = try await resolve(arguments)
      _ = try await engine.apply(
        current.proposal, expectedContentHash: current.proposal.contentHash)
    } catch WorkingCopyFailure.partialApplication(_, let completed, let remaining, _) {
      outcomeUncertain = true
      issued = nil
      _ = await recordOutcome(
        current, runtimeTaskKey: runtimeTaskKey, state: .unknown, completed: completed,
        remaining: remaining)
      return Self.result(
        current.proposal, outcome: "unknown",
        text:
          "Export outcome unknown: source files or export temporaries may remain changed. Do not retry automatically; inspect the source before making a fresh copy and proposal.",
        completed: completed, remaining: remaining, openWriters: openWriters, isError: true)
    } catch {
      guard await recordOutcome(current, runtimeTaskKey: runtimeTaskKey, state: .notApplied) else {
        throw RuntimeWorkingCopyError.outcomeUnknown
      }
      refused.insert(current.proposal.contentHash)
      return Self.result(
        current.proposal, outcome: "not_applied",
        text: "The export was not applied. The source or reviewed proposal changed.",
        isError: true, effectOutcome: .notApplied)
    }
    let completed = current.proposal.changes.map(\.path)
    guard
      await recordOutcome(
        current, runtimeTaskKey: runtimeTaskKey, state: .applied, completed: completed)
    else {
      return Self.result(
        current.proposal, outcome: "unknown",
        text:
          "Source changes may have completed, but the durable export receipt could not be committed. Do not retry automatically.",
        completed: completed, openWriters: openWriters, isError: true)
    }
    return Self.result(
      current.proposal, outcome: "applied",
      text: "The exact approved changes were exported to their original source files.",
      completed: completed, openWriters: openWriters)
  }

  /// D137, best effort: the replaced or deleted originals that another program still has open
  /// for writing when the check ends: the whole check, scans and waiting for writers to close,
  /// takes at most ``WorkingCopyOpenWriters/limit`` (2 s). Their later writes go to the file
  /// Memoshi replaced or removed and can be lost; the export still applies.
  private func openWriters(_ proposal: WorkingCopyProposal) async -> [String] {
    #if os(macOS)
      let originals = proposal.changes.filter { $0.kind != "create" }.map(\.path)
      let open = await WorkingCopyOpenWriters.remaining(
        originals.map { binding.sourceRoot + "/" + $0 })
      return originals.filter { open.contains(binding.sourceRoot + "/" + $0) }
    #else
      return []
    #endif
  }

  private func recordOutcome(
    _ current: IssuedExport, runtimeTaskKey: String, state: WorkingCopyExportState,
    completed: [String] = [], remaining: [String] = []
  ) async -> Bool {
    do {
      try await binding.store.finishWorkingCopyExport(
        id, contentHash: current.proposal.contentHash, runtimeTaskKey: runtimeTaskKey,
        state: state, completedPaths: completed, remainingTemporaryPaths: remaining,
        at: IDGenerator.nowMilliseconds())
      return true
    } catch {
      outcomeUncertain = true
      issued = nil
      return false
    }
  }

  /// Compare only the trusted frozen shape: array/object counts and bounded UTF-8 walks
  /// reject attacker-sized or deeply nested replacements before serialization or hashing.
  /// Swift String equality is deliberately not used for content: NFC and NFD differ here.
  private static func sameArguments(
    _ received: MemoshiProtocol.JSONValue, _ frozen: MemoshiProtocol.JSONValue
  ) -> Bool {
    switch (received, frozen) {
    case (.null, .null): return true
    case (.string(let actual), .string(let expected)):
      return actual.utf8.elementsEqual(expected.utf8)
    case (.array(let actual), .array(let expected)):
      guard actual.count == expected.count else { return false }
      return zip(actual, expected).allSatisfy { sameArguments($0.0, $0.1) }
    case (.object(let actual), .object(let expected)):
      guard actual.count == expected.count else { return false }
      return expected.allSatisfy { key, value in
        guard let received = actual[key] else { return false }
        return sameArguments(received, value)
      }
    default: return false
    }
  }

  private static func arguments(_ proposal: WorkingCopyProposal) -> MemoshiProtocol.JSONValue {
    [
      "proposalDigest": .string(proposal.contentHash),
      "changes": .array(
        proposal.changes.map { change in
          var value: [String: MemoshiProtocol.JSONValue] = [
            "path": .string(change.path), "kind": .string(change.kind),
            "baseHash": change.baseHash.map(MemoshiProtocol.JSONValue.string) ?? .null,
            "newHash": change.newHash.map(MemoshiProtocol.JSONValue.string) ?? .null,
          ]
          if let contents = change.newContents {
            if let text = String(validating: contents, as: UTF8.self) {
              value["newText"] = .string(text)
            } else {
              value["newBase64"] = .string(contents.base64EncodedString())
            }
          }
          return .object(value)
        }),
    ]
  }

  /// `openWriters` are source-relative originals still open for writing elsewhere; the export
  /// card, once there is one, shows them from `data` (D137).
  private static func result(
    _ proposal: WorkingCopyProposal, outcome: String, text: String,
    completed: [String] = [], remaining: [String] = [], openWriters: [String] = [],
    isError: Bool = false, effectOutcome: RuntimeToolEffectOutcome? = nil
  ) -> RuntimeToolResult {
    let warning =
      openWriters.isEmpty
      ? ""
      : " These files were still open for writing in another program, so changes it makes to them later may be lost: "
        + openWriters.joined(separator: ", ") + "."
    return RuntimeToolResult(
      text: text + warning,
      data: [
        "proposalDigest": .string(proposal.contentHash), "outcome": .string(outcome),
        "completedPaths": .array(completed.map(MemoshiProtocol.JSONValue.string)),
        "remainingTemporaryPaths": .array(remaining.map(MemoshiProtocol.JSONValue.string)),
        "openWriters": .array(openWriters.map(MemoshiProtocol.JSONValue.string)),
      ], isError: isError, effectOutcome: effectOutcome)
  }

  private static func argumentSchema(maximumChanges: Int) -> MemoshiProtocol.JSONValue {
    [
      "type": "object", "required": ["proposalDigest", "changes"], "additionalProperties": false,
      "properties": [
        "proposalDigest": ["type": "string"],
        "changes": [
          "type": "array", "minItems": 1, "maxItems": .integer(Int64(maximumChanges)),
          "items": [
            "type": "object", "required": ["path", "kind", "baseHash", "newHash"],
            "additionalProperties": false,
            "properties": [
              "path": ["type": "string"],
              "kind": ["type": "string", "enum": ["create", "replace", "delete"]],
              "baseHash": ["type": ["string", "null"]],
              "newHash": ["type": ["string", "null"]],
              "newText": ["type": "string"], "newBase64": ["type": "string"],
            ],
          ],
        ],
      ],
    ]
  }

  private static let resultSchema: MemoshiProtocol.JSONValue = [
    "type": "object", "additionalProperties": false,
    "required": [
      "proposalDigest", "outcome", "completedPaths", "remainingTemporaryPaths", "openWriters",
    ],
    "properties": [
      "proposalDigest": ["type": "string"],
      "outcome": [
        "type": "string", "enum": ["applied", "already_applied", "not_applied", "unknown"],
      ],
      "completedPaths": ["type": "array", "items": ["type": "string"]],
      "remainingTemporaryPaths": ["type": "array", "items": ["type": "string"]],
      "openWriters": ["type": "array", "items": ["type": "string"]],
    ],
  ]
}
