import Foundation
import MemoshiProtocol

/// Local ownership metadata, not a new domain object, filesystem capability or replay token.
/// File contents and bookmark bytes never belong in this journal.
public struct WorkingCopyOwnership: Codable, Equatable, Sendable {
  /// The store-local copy reservation, never a bearer capability.
  public let id: UUID
  /// The persisted Chat (or Session) that owns the copy.
  public let chatID: ConversationID
  /// The bot derived from that Chat, not supplied by a model.
  public let botID: BotID
  /// The local device that holds the source grant.
  public let deviceID: DeviceID
  /// The exact source-grant revision captured at admission.
  public let grant: FolderGrantReference
  /// The granted source root's physical identity.
  public let sourceIdentity: FolderSourceIdentity
  /// The trusted protected-state container, kept out of events.
  public let containerRoot: String
  /// The container identity captured before private-root creation.
  public let containerIdentity: FolderSourceIdentity
  /// The verified private inode, absent until admission finishes.
  public internal(set) var workingIdentity: FolderSourceIdentity?

  /// Chosen and journaled before the host creates any private directory.
  public var workingName: String { ".memoshi-working-" + id.uuidString }
  /// A review location, never sufficient authority to attach or delete a recovered copy.
  public var workingRoot: String { containerRoot + "/" + workingName }
}

/// A reopened copy is interrupted, never automatically attached, exported or removed.
public enum WorkingCopyPhase: String, Codable, Sendable {
  case admitting
  case active
  case interrupted
  case cleanupRequired = "cleanup_required"
  case closed
}

/// The one name of the tool that exports a private working copy; the runtime registers it and
/// the store recognizes its calls in the journal and on a Resume card.
public enum WorkingCopyExportTool {
  /// The tool's name.
  public static let name = "export_working_copy"
}

/// An uncommitted outcome becomes unknown on Store reopen, even when the bytes look right.
public enum WorkingCopyExportState: String, Codable, Sendable {
  case pending
  case applied
  case notApplied = "not_applied"
  case unknown
}

/// Content-free description of one frozen source effect. Hashes bind bytes but authorize nothing.
public struct WorkingCopyExportChange: Codable, Equatable, Sendable {
  /// The exact source-relative target.
  public let path: String
  /// One content-only operation: `create`, `replace` or `delete`.
  public let operation: String
  /// SHA-256 of the admitted bytes, absent for a create.
  public let baseHash: String?
  /// SHA-256 of the frozen replacement bytes, absent for a delete.
  public let newHash: String?

  /// Describes frozen data without storing its contents.
  public init(path: String, operation: String, baseHash: String?, newHash: String?) {
    self.path = path
    self.operation = operation
    self.baseHash = baseHash
    self.newHash = newHash
  }
}

/// Immutable dispatch identity and the host's recorded effect outcome, not a policy receipt.
public struct WorkingCopyExportReceipt: Equatable, Sendable {
  /// The engine-issued digest binding the copy, baseline and frozen proposal.
  public let contentHash: String
  /// SHA-256 of the exact canonical tool arguments.
  public let argumentsHash: String
  /// The actual opaque Pi task key, linked to its persisted policy-call identity.
  public let runtimeTaskKey: String
  /// The immutable tool-call identifier from that invocation.
  public let callID: String
  /// The persisted application task that owned dispatch.
  public let taskID: TaskID
  /// The frozen source-relative effects, with hashes instead of file contents.
  public let changes: [WorkingCopyExportChange]
  /// The committed host outcome, not a claim that current source bytes remain unchanged.
  public let state: WorkingCopyExportState
  /// Paths the native engine reported installed before its outcome.
  public let completedPaths: [String]
  /// Known source-relative temporary residue requiring inspection.
  public let remainingTemporaryPaths: [String]
}

/// Read-only local recovery information. Reading it never opens a source or staging path.
public struct WorkingCopyRecovery: Equatable, Sendable {
  /// Captured local ownership; it grants no recovery-time filesystem access.
  public let ownership: WorkingCopyOwnership
  /// The copy lifecycle, independent of Pi task status.
  public let phase: WorkingCopyPhase
  /// Retained intents and receipts, including uncertainty that private cleanup cannot erase.
  public let exports: [WorkingCopyExportReceipt]
}

/// Only a newly committed intent permits dispatch; an exact applied proposal has no new effect.
public enum WorkingCopyExportAdmission: Sendable {
  case execute
  case alreadyApplied
}

/// Safe failures. No raw paths, native errors, file contents or bookmarks are rendered.
public enum WorkingCopyJournalError: Error, Equatable, Sendable {
  case invalidRequest
  case unavailable
  case recoveryRequired
  case bindingConflict
}

struct WorkingCopyExportProgress: Codable, Equatable {
  let completedPaths: [String]
  let remainingTemporaryPaths: [String]
}
