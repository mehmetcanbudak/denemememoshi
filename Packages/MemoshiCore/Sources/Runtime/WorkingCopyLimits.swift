/// Conservative development ceilings, not product workload or reference-device qualification.
/// Trusted host composition may tighten each ceiling; model arguments cannot change them.
/// Invalid or widened profiles are refused at admission, before any private root is created.
public struct WorkingCopyLimits: Sendable {
  /// Largest regular file, checked before reading or reserving capture storage.
  public let maximumFileBytes: Int64
  /// Aggregate regular-file bytes in each complete source/private traversal.
  public let maximumTreeBytes: Int64
  /// Files and directories below the root; the root itself is not an entry.
  public let maximumEntries: Int
  /// Source-relative path components, counting both directory and file names.
  public let maximumDepth: Int
  /// Maximum files in one export, also bounding held parents and exclusive temporaries.
  public let maximumChanges: Int
  /// Successful exports per live copy, bounding replay receipts and protected inode history.
  public let maximumExports: Int
  /// Total raw replacement/creation data retained in one immutable proposal.
  public let maximumProposalBytes: Int64
  /// Canonical UTF-8 JSON, including escaping, paths and hashes, not just raw file data.
  public let maximumArgumentBytes: Int

  /// Development ceiling; callers can select only equally strict or smaller values.
  public static let standard = WorkingCopyLimits()

  /// Creates a host-selected profile. Admission validates every value; none means unlimited.
  public init(
    maximumFileBytes: Int64 = 8 * 1024 * 1024,
    maximumTreeBytes: Int64 = 64 * 1024 * 1024,
    maximumEntries: Int = 4096, maximumDepth: Int = 32, maximumChanges: Int = 64,
    maximumExports: Int = 64, maximumProposalBytes: Int64 = 32 * 1024,
    maximumArgumentBytes: Int = 48 * 1024
  ) {
    self.maximumFileBytes = maximumFileBytes
    self.maximumTreeBytes = maximumTreeBytes
    self.maximumEntries = maximumEntries
    self.maximumDepth = maximumDepth
    self.maximumChanges = maximumChanges
    self.maximumExports = maximumExports
    self.maximumProposalBytes = maximumProposalBytes
    self.maximumArgumentBytes = maximumArgumentBytes
  }

  func validate() throws {
    let ceiling = Self.standard
    guard maximumFileBytes > 0, maximumFileBytes <= ceiling.maximumFileBytes,
      maximumTreeBytes > 0, maximumTreeBytes <= ceiling.maximumTreeBytes,
      maximumEntries > 0, maximumEntries <= ceiling.maximumEntries,
      maximumDepth > 0, maximumDepth <= ceiling.maximumDepth,
      maximumChanges > 0, maximumChanges <= ceiling.maximumChanges,
      maximumExports > 0, maximumExports <= ceiling.maximumExports,
      maximumProposalBytes > 0, maximumProposalBytes <= ceiling.maximumProposalBytes,
      maximumArgumentBytes > 0, maximumArgumentBytes <= ceiling.maximumArgumentBytes
    else { throw RuntimeWorkingCopyError.invalidLimits }
  }
}

/// A fresh allowance for one complete traversal or immutable capture. Counters are charged
/// before retention, traversal or transfer, with subtraction so attacker-sized inputs cannot
/// overflow. Cleanup uses the standard shape ceiling, independent of a tighter caller profile.
struct WorkingCopyBudget {
  let limits: WorkingCopyLimits
  private(set) var remainingEntries: Int
  private(set) var remainingBytes: Int64

  init(_ limits: WorkingCopyLimits, maximumBytes: Int64? = nil) {
    self.limits = limits
    remainingEntries = limits.maximumEntries
    remainingBytes = maximumBytes ?? limits.maximumTreeBytes
  }

  mutating func consumeEntries(_ count: Int) throws {
    guard count >= 0, count <= remainingEntries else {
      throw WorkingCopyFailure.resourceLimitExceeded
    }
    remainingEntries -= count
  }

  mutating func consumeBytes(_ count: Int64) throws {
    guard count >= 0, count <= remainingBytes else {
      throw WorkingCopyFailure.resourceLimitExceeded
    }
    remainingBytes -= count
  }

  func requireDepth(_ depth: Int) throws {
    guard depth <= limits.maximumDepth else { throw WorkingCopyFailure.resourceLimitExceeded }
  }

  var fileAllowance: Int64 { min(limits.maximumFileBytes, remainingBytes) }
}
