import Foundation

/// The device-only Keychain calls a first enrollment makes. The device layer owns the real
/// Keychain; AppCore sees only these four calls, so the rules below run against a fake too.
public protocol DeviceEnrollmentKeychain: Sendable {
  /// The device identity as the device layer holds it; the rules only pass it on.
  associatedtype Identity: Sendable
  /// The existing identity. Throws when there is none or it cannot be read.
  func load() async throws -> Identity
  /// Adds a new identity, marked as not yet enrolled. Throws when one exists already.
  func create() async throws -> Identity
  /// Clears the mark of a completed first enrollment. Does nothing for an enrolled identity.
  func completeEnrollment() async throws
  /// Removes the identity only while it is still marked as not yet enrolled. Throws, removing
  /// nothing, for an enrolled or absent identity.
  func removeUnenrolled() async throws
}

/// The file calls a first enrollment makes on its own directory. Entry names are the
/// directory's top-level names; a path is relative to the directory.
public protocol DeviceEnrollmentFiles: Sendable {
  /// Creates the directory when it is absent; an existing one is left as it is.
  func createDirectoryIfAbsent() throws
  /// The top-level entry names. Throws when the directory cannot be listed: that is never an
  /// empty directory.
  func entryNames() throws -> [String]
  /// Whether a top-level entry of that name exists.
  func hasEntry(_ name: String) -> Bool
  /// The bytes of a top-level file, or nil when it is absent or unreadable.
  func contents(ofEntry name: String) -> Data?
  /// Writes a top-level file in one step, readable by the user only.
  func write(_ data: Data, toEntry name: String) throws
  /// Removes a top-level entry with everything in it. Throws when it is absent.
  func removeEntry(_ name: String) throws
  /// The size of the file at a relative path, or nil when there is none.
  func size(ofFile path: String) -> Int64?
}

/// What a completed assembly hands back; the rules close it when a later step fails.
public protocol DeviceEnrollmentSession: Sendable {
  /// Releases everything the assembly opened.
  func close() async
}

/// A first enrollment failed or was interrupted and left nothing usable behind: its identity,
/// which never completed enrollment, was removed, so the person can create the identity again.
public struct DevicePairingEnrollmentRemoved: Error, Sendable {
  /// The error carries no detail: the removal is the whole message.
  public init() {}
}

/// Which identity an open is for.
public enum DeviceEnrollmentRequest: Sendable {
  /// Open the identity that exists, with its durable state.
  case loadExisting
  /// The person's explicit first enrollment of a new identity.
  case createNew
}

/// The names the rules know in the enrollment directory.
public enum DeviceEnrollmentLayout {
  /// The record a first enrollment leaves before it adds its identity: the names the
  /// directory already held. It is the only proof of what an attempt created, also after a
  /// restart; without it nothing in the directory is deleted. It is removed before the
  /// identity is marked enrolled, so on disk it always means an attempt that has not finished.
  public static let attemptRecord = "enrollment-attempt.json"
  /// The group checkpoint: the first durable half of a completed enrollment.
  public static let groupCheckpoint = "membership/group.jsonl"
  /// The node's replica journal: the second half.
  public static let replicaJournal = "replicas/replicas.jsonl"
}

/// The rules of a device's first enrollment and of opening it again (D130, D131).
///
/// A first enrollment either completes or leaves nothing behind. Every open reconciles: an
/// identity with enrolled state is never removed and is marked enrolled once it opens; one
/// that an interrupted enrollment left without state is removed, with exactly the entries its
/// record proves it created, so that the person can try again.
public struct DeviceFirstEnrollment<Keychain: DeviceEnrollmentKeychain>: Sendable {
  private let keychain: Keychain
  private let files: any DeviceEnrollmentFiles
  private let failure: @Sendable (any Error) -> DevicePairingFailure

  /// `failure` maps an underlying error to what the person is told.
  public init(
    keychain: Keychain, files: any DeviceEnrollmentFiles,
    failure: @escaping @Sendable (any Error) -> DevicePairingFailure
  ) {
    self.keychain = keychain
    self.files = files
    self.failure = failure
  }

  /// `assemble` opens the durable state for an identity and returns the session; its second
  /// argument says whether this is the identity's first enrollment.
  public func open<Session: DeviceEnrollmentSession>(
    _ request: DeviceEnrollmentRequest,
    assemble: (Keychain.Identity, _ firstEnrollment: Bool) async throws -> Session
  ) async throws -> Session {
    switch request {
    case .loadExisting:
      let identity = try await keychain.load()
      if !hasEnrolledState {
        // Without its durable state, an identity still marked as never enrolled is a first
        // enrollment that was interrupted: it is removed so that it can be created again. An
        // enrolled identity is refused by that removal and reported as before.
        let removal = await removeUnenrolled(keeping: recordedEntries())
        if removal.identity { throw DevicePairingEnrollmentRemoved() }
        guard hasGroupCheckpoint else { throw DevicePairingFailure.recoveryRequired }
      }
      let session = try await assemble(identity, false)
      // Opening proved the durable state. A record or a mark that survived a crash at the end
      // of a first enrollment is cleared before the session is handed out, so no session ever
      // exists for an identity that could still be removed.
      do {
        try endAttempt()
        try await keychain.completeEnrollment()
      } catch {
        await session.close()
        throw failure(error)
      }
      return session
    case .createNew:
      // An identity that an interrupted first enrollment left without durable state is removed
      // first. One with enrolled state is never touched: the creation below then fails as a
      // duplicate.
      if !hasEnrolledState { _ = await removeUnenrolled(keeping: recordedEntries()) }
      let attempt: (existing: Set<String>, isNew: Bool)
      do { attempt = try beginAttempt() } catch { throw DevicePairingFailure.unavailable }
      let identity: Keychain.Identity
      do { identity = try await keychain.create() } catch {
        if attempt.isNew { try? endAttempt() }
        throw error
      }
      do {
        // The creation proves that no identity existed: what an interrupted attempt wrote
        // for one is readable by no one. It goes before the new identity writes its state,
        // so a kill between the removal of an attempt's identity and of its files costs
        // this attempt nothing. The record stays until this attempt ends.
        if !attempt.isNew, !removeEntries(writtenSince: attempt.existing) {
          throw DevicePairingFailure.unavailable
        }
        let session = try await assemble(identity, true)
        do {
          try endAttempt()
          try await keychain.completeEnrollment()
        } catch {
          await session.close()
          throw error
        }
        return session
      } catch {
        // A first enrollment either completes or leaves nothing behind: its half-made
        // identity could be neither opened nor created again.
        let removal = await removeUnenrolled(keeping: attempt.existing)
        if error is CancellationError { throw CancellationError() }
        if removal.clean && attempt.existing.isEmpty { throw DevicePairingEnrollmentRemoved() }
        throw failure(error)
      }
    }
  }

  private var hasGroupCheckpoint: Bool {
    (files.size(ofFile: DeviceEnrollmentLayout.groupCheckpoint) ?? 0) > 0
  }

  /// Both durable halves of a completed enrollment. An identity that has them is never removed.
  private var hasEnrolledState: Bool {
    hasGroupCheckpoint && files.size(ofFile: DeviceEnrollmentLayout.replicaJournal) != nil
  }

  /// The names an unfinished attempt recorded, or nil without a readable record.
  private func recordedEntries() -> Set<String>? {
    guard let data = files.contents(ofEntry: DeviceEnrollmentLayout.attemptRecord),
      let names = try? JSONDecoder().decode([String].self, from: data)
    else { return nil }
    return Set(names)
  }

  /// Returns the recorded names and whether this call made the record; an interrupted attempt
  /// keeps its original one. A listing that fails is not an empty directory: it throws, before
  /// anything is added.
  private func beginAttempt() throws -> (existing: Set<String>, isNew: Bool) {
    if let existing = recordedEntries() { return (existing, false) }
    try files.createDirectoryIfAbsent()
    let existing = Set(try files.entryNames()).subtracting([DeviceEnrollmentLayout.attemptRecord])
    try files.write(
      try JSONEncoder().encode(existing.sorted()), toEntry: DeviceEnrollmentLayout.attemptRecord)
    return (existing, true)
  }

  private func endAttempt() throws {
    if files.hasEntry(DeviceEnrollmentLayout.attemptRecord) {
      try files.removeEntry(DeviceEnrollmentLayout.attemptRecord)
    }
  }

  /// Removes an identity still marked as never enrolled, then what its attempt wrote. The
  /// Keychain refuses any other identity, and then nothing is deleted. The state is encrypted
  /// to the identity, so it goes only once the identity is gone, and only the entries that
  /// `existing`, the attempt's own record of what the directory held before, proves it
  /// created: without that record, or when the directory cannot be listed, no file is deleted.
  /// `clean` means nothing of the attempt remains.
  private func removeUnenrolled(
    keeping existing: Set<String>?
  ) async -> (identity: Bool, clean: Bool) {
    do { try await keychain.removeUnenrolled() } catch { return (false, false) }
    guard let existing, removeEntries(writtenSince: existing) else { return (true, false) }
    // The record stays while anything of the attempt remains, for the next try.
    try? endAttempt()
    return (true, true)
  }

  /// Deletes every top-level entry but the record that `existing`, an attempt's record of what
  /// the directory held before it, does not name: what that attempt wrote. False when the
  /// directory cannot be listed, then nothing is deleted, or when an entry cannot be deleted.
  private func removeEntries(writtenSince existing: Set<String>) -> Bool {
    guard let present = try? files.entryNames() else { return false }
    var clean = true
    for name in present
    where name != DeviceEnrollmentLayout.attemptRecord && !existing.contains(name) {
      do { try files.removeEntry(name) } catch { clean = false }
    }
    return clean
  }
}

/// The enrollment directory on disk.
public struct DeviceEnrollmentDirectory: DeviceEnrollmentFiles {
  private let directory: URL

  /// The enrollment directory; it need not exist yet.
  public init(_ directory: URL) { self.directory = directory }

  /// Creates the directory, private to the user, when it is absent.
  public func createDirectoryIfAbsent() throws {
    guard !FileManager.default.fileExists(atPath: directory.path) else { return }
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
  }

  /// The top-level names; throws when the directory is absent or cannot be listed.
  public func entryNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path)
  }

  /// Whether a top-level entry of that name exists.
  public func hasEntry(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
  }

  /// The bytes of a top-level file, or nil when it is absent or unreadable.
  public func contents(ofEntry name: String) -> Data? {
    try? Data(contentsOf: directory.appendingPathComponent(name))
  }

  /// Writes a top-level file in one step, then makes it readable by the user only.
  public func write(_ data: Data, toEntry name: String) throws {
    let url = directory.appendingPathComponent(name)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  /// Removes a top-level entry with everything in it; throws when it is absent.
  public func removeEntry(_ name: String) throws {
    try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
  }

  /// The size of the file at a relative path, or nil when there is none.
  public func size(ofFile path: String) -> Int64? {
    let file = directory.appendingPathComponent(path).path
    return (try? FileManager.default.attributesOfItem(atPath: file)[.size] as? NSNumber)?
      .int64Value
  }
}
