// S4-T1 port of the disposable raw 105-case Seatbelt file probe from
// `evidence/2026-11-14-memoshi-s4/raw-matrix/RawFileProfileProbe.swift` (re-snapshotted
// 2026-11-16 into `evidence/2026-11-16-memoshi-s4-h3/raw-matrix/`). The probe logic is
// preserved; the `@main` entry became `S4Matrix.prepare`/`S4Matrix.worker` for the
// `memoshi-qualification s4-matrix` subcommand and the case list moved to the declarative
// `S4MatrixVectors` fixture. A run root must sit below the recorded scratch or below an owned
// root the caller names (`--owned-root`, for volume runs); the host passes the same list to
// every worker through `MEMOSHI_S4_OWNED_ROOTS`, and the worker trusts only that list.
// Qualification code only: no production imports or composition; never use real data.
import CryptoKit
import Darwin
import Foundation

private let batchScratch = "/private/tmp/memoshi-s4-20261114"
/// Newline-separated owned parents the host hands each worker: the recorded scratch plus any
/// `--owned-root` the run named.
private let ownedRootsEnvironment = "MEMOSHI_S4_OWNED_ROOTS"
private let sourceFileSHA256 = "71bd068d7eecc6388b14f4339c57b337649781747694cacb4a2c38ed9f79c95f"
/// The SHA-256 of the SandboxProfileSnapshot.swift enums; runs before 2026-11-18 run-2 used the
/// d0dc184 snapshot, hash dc9cc7bfbd6b1ff9fd26ceb5bd29e52e53285ec95fe5ad15358e21b747d8266e.
private let enumSHA256 = "b0f0e0907a53fe91880091aa187e455b660752732afb4ca347a8a2b42300bd68"
private let maximumCases = 128
private let maximumWorkers = maximumCases * 3
private let maximumFileBytes = 4096
// 2026-11-14: the d0dc184 profile (generated secret regex) exceeds 4096 bytes; canaries keep 4096.
private let maximumProfileBytes = 65536
private let maximumWorkerSyscalls = 64
private let workerDeadlineSeconds = 8.0

private func hex(_ bytes: some Sequence<UInt8>) -> String {
  bytes.map { String(format: "%02x", $0) }.joined()
}
private func sha256(_ data: Data) -> String { hex(SHA256.hash(data: data)) }
private func byteEqual(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.elementsEqual(rhs.utf8) }
private func below(_ path: String, _ root: String) -> Bool {
  !path.utf8.contains(0) && path.utf8.starts(with: (root + "/").utf8)
    && !path.split(separator: "/").contains("..")
}
private func uniquePaths(_ paths: [String]) -> [String] {
  var seen = Set<String>()
  return paths.filter { seen.insert(hex($0.utf8)).inserted }
}
private func physical(_ path: String) throws -> String {
  guard let pointer = path.withCString({ Darwin.realpath($0, nil) }) else {
    throw ProbeError(stage: "realpath", code: errno)
  }
  defer { free(pointer) }
  return String(cString: pointer)
}
package struct ProbeError: Error, CustomStringConvertible {
  let stage: String
  let code: Int32
  package var description: String { "\(stage): errno=\(code)" }
}
private func required(_ condition: Bool, _ stage: String, _ code: Int32 = EINVAL) throws {
  if !condition { throw ProbeError(stage: stage, code: code) }
}

package struct ObjectIdentity: Codable, Equatable {
  let device: String
  let inode: String
  init(_ info: stat) {
    device = String(UInt64(bitPattern: Int64(info.st_dev)))
    inode = String(UInt64(info.st_ino))
  }
}
package struct Entry: Codable, Equatable {
  let identity: ObjectIdentity
  let mode: UInt32
  let links: UInt64
  let size: Int64
  init(_ info: stat) {
    identity = ObjectIdentity(info)
    mode = UInt32(info.st_mode)
    links = UInt64(info.st_nlink)
    size = Int64(info.st_size)
  }
}
package struct FileState: Codable, Equatable {
  let path: String
  let pathUTF8Hex: String
  let entry: Entry?
  let entryErrno: Int32
  let resolvedEntry: Entry?
  let resolvedErrno: Int32
  let realpath: String?
  let symlinkTarget: String?
  let bytesBase64: String?
  let bytesSHA256: String?
  let readErrno: Int32
}

// Host-side reads are independent of worker output and use POSIX bytes, not URL normalization.
// Followed paths must first resolve inside the owned run root. No fixture FD is inherited.
private func readFD(_ fd: Int32) throws -> Data {
  var result = Data()
  var storage = [UInt8](repeating: 0, count: maximumFileBytes + 1)
  for _ in 0..<16 {
    let capacity = storage.count
    let amount = storage.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, capacity) }
    if amount < 0 {
      if errno == EINTR { continue }
      throw ProbeError(stage: "read", code: errno)
    }
    if amount == 0 { return result }
    result.append(contentsOf: storage.prefix(amount))
    try required(result.count <= maximumFileBytes, "bounded-read", EFBIG)
  }
  throw ProbeError(stage: "read-call-bound", code: E2BIG)
}
private func writeFD(_ fd: Int32, _ bytes: Data, limit: Int = maximumFileBytes) throws {
  try required(bytes.count <= limit, "bounded-write", EFBIG)
  var offset = 0
  for _ in 0..<16 {
    if offset == bytes.count { return }
    let amount = writeBuffer(fd, bytes, offset: offset)
    if amount < 0 {
      if errno == EINTR { continue }
      throw ProbeError(stage: "write", code: errno)
    }
    try required(amount > 0, "zero-write", EIO)
    offset += amount
  }
  throw ProbeError(stage: "write-call-bound", code: E2BIG)
}
/// One bounded write call at `offset`; `EFAULT` when the buffer has no base address.
private func writeBuffer(_ fd: Int32, _ bytes: Data, offset: Int) -> Int {
  bytes.withUnsafeBytes { buffer -> Int in
    guard let base = buffer.baseAddress else {
      errno = EFAULT
      return -1
    }
    return Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
  }
}
private func snapshot(_ path: String, root: String) throws -> FileState {
  try required(below(path, root), "snapshot-owned-path")
  var raw = stat()
  let rawStatus = path.withCString { Darwin.fstatat(AT_FDCWD, $0, &raw, AT_SYMLINK_NOFOLLOW) }
  let rawErrno: Int32 = rawStatus == 0 ? 0 : errno
  var followed = stat()
  let followedStatus = path.withCString { Darwin.fstatat(AT_FDCWD, $0, &followed, 0) }
  let followedErrno: Int32 = followedStatus == 0 ? 0 : errno
  var resolved: String?
  var target: String?
  var bytes: Data?
  var readError: Int32 = 0
  if rawStatus == 0 && raw.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) {
    var storage = [CChar](repeating: 0, count: 4097)
    let amount = path.withCString { pathname in
      storage.withUnsafeMutableBufferPointer { Darwin.readlink(pathname, $0.baseAddress, 4096) }
    }
    if amount >= 0 {
      target = String(decoding: storage.prefix(amount).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
  }
  if followedStatus == 0 {
    resolved = try physical(path)
    try required(resolved.map { below($0, root) } == true, "followed-path-owned")
    if followed.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) {
      let fd = path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC) }
      if fd >= 0 {
        defer { Darwin.close(fd) }
        do {
          var opened = stat()
          try required(Darwin.fstat(fd, &opened) == 0, "host-fstat", errno)
          try required(ObjectIdentity(opened) == ObjectIdentity(followed), "host-read-identity")
          bytes = try readFD(fd)
        } catch let error as ProbeError { readError = error.code }
      } else {
        readError = errno
      }
    }
  }
  return FileState(
    path: path, pathUTF8Hex: hex(path.utf8), entry: rawStatus == 0 ? Entry(raw) : nil,
    entryErrno: rawErrno, resolvedEntry: followedStatus == 0 ? Entry(followed) : nil,
    resolvedErrno: followedErrno, realpath: resolved, symlinkTarget: target,
    bytesBase64: bytes?.base64EncodedString(), bytesSHA256: bytes.map(sha256), readErrno: readError)
}
private func makeDirectories(_ path: String, root: String) throws {
  try required(byteEqual(path, root) || below(path, root), "mkdir-owned-path")
  let suffix = path.utf8.dropFirst(root.utf8.count + 1)
  let relative = String(decoding: suffix, as: UTF8.self)
  var current = root
  for component in relative.split(separator: "/", omittingEmptySubsequences: true) {
    current += "/" + String(component)
    let status = current.withCString { Darwin.mkdir($0, 0o700) }
    if status != 0 && errno != EEXIST { throw ProbeError(stage: "mkdir", code: errno) }
    var info = stat()
    try required(
      current.withCString { Darwin.fstatat(AT_FDCWD, $0, &info, AT_SYMLINK_NOFOLLOW) } == 0,
      "mkdir-lstat", errno)
    try required(
      info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) && info.st_uid == geteuid(),
      "owned-directory-type")
  }
}
private func parentDirectory(_ path: String) -> String {
  guard let slash = path.lastIndex(of: "/") else { return path }
  return String(path[..<slash])
}
private func createFile(_ path: String, bytes: Data, root: String, limit: Int = maximumFileBytes)
  throws
{
  try makeDirectories(parentDirectory(path), root: root)
  let fd = path.withCString {
    Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
  }
  try required(fd >= 0, "create-owned-file", errno)
  defer { Darwin.close(fd) }
  try writeFD(fd, bytes, limit: limit)
}
private func writeExisting(_ path: String, bytes: Data, root: String) throws {
  try required(below(path, root), "restore-owned-path")
  let fd = path.withCString { Darwin.open($0, O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOFOLLOW) }
  try required(fd >= 0, "restore-open", errno)
  defer { Darwin.close(fd) }
  try writeFD(fd, bytes)
}
private func removeFileIfPresent(_ path: String, root: String) throws {
  try required(below(path, root), "unlink-owned-path")
  if path.withCString({ Darwin.unlink($0) }) != 0 && errno != ENOENT {
    throw ProbeError(stage: "restore-unlink", code: errno)
  }
}

package enum Principal: String, Codable { case a, b }
package enum Operation: String, Codable { case read, overwrite, create, link, rename }
package enum Expectation: String, Codable { case deny, allow }
package struct AliasRequest: Codable {
  let kind: String
  let canonicalPath: String
  let accessedPath: String
  let conditionalPhysicalAlias: Bool
}
package struct CaseSpec: Codable {
  let id: String
  let category: String
  let principal: Principal
  let expectation: Expectation
  let operation: Operation
  let first: String
  let second: String?
  let canonicalFile: String
  let originalBase64: String
  let watchedPaths: [String]
  let alias: AliasRequest?
  let limitation: String
}
package struct Job: Codable {
  let schema: String
  let root: String
  let caseID: String
  let operation: Operation
  let first: String
  let second: String?
  let payloadBase64: String
}
package struct WorkerResult: Codable {
  let schema: String
  let caseID: String
  let operation: Operation
  let succeeded: Bool
  let stage: String
  let errnoCode: Int32
  let objectIdentity: ObjectIdentity?
  let bytesBase64: String
  let primarySyscallCount: Int
}
private func executeWorker(_ job: Job) -> WorkerResult {
  var stage = "validate"
  var descriptor: Int32 = -1
  var identity: ObjectIdentity?
  var observed = Data()
  var calls = 0
  func tick() throws {
    calls += 1
    try required(calls <= maximumWorkerSyscalls, "worker-syscall-bound", E2BIG)
  }
  defer { if descriptor >= 0 { Darwin.close(descriptor) } }
  do {
    try required(
      job.schema == "memoshi.s4.raw-file-job.v1" && below(job.first, job.root), "job-owned-path")
    if let second = job.second { try required(below(second, job.root), "job-second-owned-path") }
    try required(ownedParents().contains { below(job.root, $0) }, "job-owned-root")
    let payload = Data(base64Encoded: job.payloadBase64) ?? Data()
    try required(!payload.isEmpty && payload.count <= maximumFileBytes, "job-payload")
    switch job.operation {
    case .read, .overwrite, .create:
      stage = "open"
      let flags: Int32
      switch job.operation {
      case .read: flags = O_RDONLY | O_CLOEXEC
      case .overwrite: flags = O_WRONLY | O_TRUNC | O_CLOEXEC
      default: flags = O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC
      }
      // Intentionally follows established owned symbolic aliases: this tests Seatbelt, not an
      // O_NOFOLLOW refusal. Both the host and worker restrict every supplied path to this run.
      try tick()
      descriptor = job.first.withCString { Darwin.open($0, flags, 0o600) }
      try required(descriptor >= 0, stage, errno)
      stage = "fstat"
      var info = stat()
      try tick()
      try required(Darwin.fstat(descriptor, &info) == 0, stage, errno)
      try required(info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), "regular-file-required")
      identity = ObjectIdentity(info)
      if job.operation == .read {
        stage = "read"
        var storage = [UInt8](repeating: 0, count: maximumFileBytes + 1)
        var ended = false
        for _ in 0..<16 {
          try tick()
          let capacity = storage.count
          let amount = storage.withUnsafeMutableBytes {
            Darwin.read(descriptor, $0.baseAddress, capacity)
          }
          if amount < 0 {
            if errno == EINTR { continue }
            throw ProbeError(stage: stage, code: errno)
          }
          if amount == 0 {
            ended = true
            break
          }
          observed.append(contentsOf: storage.prefix(amount))
          try required(observed.count <= maximumFileBytes, "bounded-read", EFBIG)
        }
        try required(ended, "read-call-bound", E2BIG)
      } else {
        stage = "write"
        var offset = 0
        for _ in 0..<16 {
          if offset == payload.count { break }
          try tick()
          let amount = writeBuffer(descriptor, payload, offset: offset)
          if amount < 0 {
            if errno == EINTR { continue }
            throw ProbeError(stage: stage, code: errno)
          }
          try required(amount > 0, "zero-write", EIO)
          offset += amount
        }
        try required(offset == payload.count, "write-call-bound", E2BIG)
      }
    case .link:
      stage = "link"
      guard let second = job.second else { throw ProbeError(stage: "link-target", code: EINVAL) }
      try tick()
      let status = job.first.withCString { first in second.withCString { Darwin.link(first, $0) } }
      try required(status == 0, stage, errno)
    case .rename:
      stage = "rename"
      guard let second = job.second else { throw ProbeError(stage: "rename-target", code: EINVAL) }
      try tick()
      let status = job.first.withCString { first in second.withCString { Darwin.rename(first, $0) }
      }
      try required(status == 0, stage, errno)
    }
    return WorkerResult(
      schema: "memoshi.s4.raw-file-worker.v1", caseID: job.caseID,
      operation: job.operation, succeeded: true, stage: "complete", errnoCode: 0,
      objectIdentity: identity, bytesBase64: observed.base64EncodedString(),
      primarySyscallCount: calls)
  } catch {
    let failure = error as? ProbeError ?? ProbeError(stage: stage, code: EIO)
    return WorkerResult(
      schema: "memoshi.s4.raw-file-worker.v1", caseID: job.caseID,
      operation: job.operation, succeeded: false, stage: failure.stage, errnoCode: failure.code,
      objectIdentity: identity, bytesBase64: observed.base64EncodedString(),
      primarySyscallCount: calls)
  }
}

/// The worker's owned canonical parents: exactly the list the host passed in the environment,
/// or the recorded scratch when none was passed. The worker trusts only this check.
private func ownedParents() -> [String] {
  guard let raw = getenv(ownedRootsEnvironment) else { return [batchScratch] }
  let listed = String(cString: raw).split(separator: "\n", omittingEmptySubsequences: true)
    .map(String.init).filter { !$0.isEmpty && !$0.utf8.contains(0) }
  return listed.isEmpty ? [batchScratch] : listed
}

package struct ProcessReceipt: Codable {
  let argv: [String]
  let environment: [String: String]
  let confined: Bool
  let timedOut: Bool
  let exitCode: Int32
  let terminationReason: String
  let launchFailure: String?
  let stdoutBase64: String
  let stderrBase64: String
  let result: WorkerResult?
}
package struct S4EffectReceipt: Codable {
  let process: ProcessReceipt
  let payloadBase64: String
  let before: [FileState]
  let after: [FileState]
  let operationVerified: Bool
  let effectObserved: Bool
  let unchanged: Bool
}
package struct AliasProof: Codable {
  let request: AliasRequest
  let canonical: FileState
  let accessed: FileState
  let differentPathBytes: Bool
  let sameDeviceAndInode: Bool
  let sameBytes: Bool
  let established: Bool
}
package struct Failure: Codable {
  let kind: String
  let caseID: String
  let detail: String

  package init(kind: String, caseID: String, detail: String) {
    self.kind = kind
    self.caseID = caseID
    self.detail = detail
  }
}
package struct RunSummary: Codable {
  let schema: String
  let receipt: String
  let exitCode: Int32
  let reproducibleBypassCount: Int
  let caseCount: Int
}
package struct CaseReceipt: Codable {
  let spec: CaseSpec
  let outcome: String
  let preconditionValid: Bool
  let controlValid: Bool
  let aliasProof: AliasProof?
  let sandboxedAttempts: [S4EffectReceipt]
  let unconfinedControl: S4EffectReceipt?
  let restored: [FileState]
  let failures: [Failure]
}
package struct ProfileReceipt: Codable {
  let principal: Principal
  let home: String
  let workingRoot: String
  let tmpdir: String
  let profilePath: String
  let profileSHA256: String
  let profileText: String
}
package struct Report: Codable {
  package let schema: String
  package let scope: String
  package let root: String
  package let processUID: UInt32
  package let sourceFileSHA256: String
  package let exactEnumSHA256: String
  package let enumHashConvention: String
  package let profiles: [ProfileReceipt]
  package let limits: [String]
  package let maximumCaseCount: Int
  package let maximumWorkerCount: Int
  package let actualWorkerCount: Int
  package let maximumPrimaryWorkerSyscalls: Int
  package let workerDeadlineSeconds: Double
  package let cases: [CaseReceipt]
  package let failures: [Failure]
  package let reproducibleBypassCount: Int
  package let nonReproducedBypassCount: Int
  package let validDeniedCaseCount: Int
  package let validAllowedCaseCount: Int
  package let notApplicableAliasCount: Int
  package let exitCode: Int32
}

private final class Probe {
  let root: String
  let executable: String
  /// The owned parents this run accepts, handed unchanged to every worker.
  let ownedParents: [String]
  let homes: [Principal: String]
  let copies: [Principal: String]
  let profiles: [Principal: String]
  let profileReceipts: [ProfileReceipt]
  var specs: [CaseSpec] = []
  var workerCount = 0
  var commonSharedBytes: Data?

  init(parent: String, executable: String, ownedParents: [String]) throws {
    let canonicalParent = try physical(parent)
    try required(
      byteEqual(canonicalParent, parent) && ownedParents.contains { below(parent, $0) },
      "canonical-owned-parent")
    var parentInfo = stat()
    try required(
      parent.withCString { Darwin.fstatat(AT_FDCWD, $0, &parentInfo, AT_SYMLINK_NOFOLLOW) } == 0,
      "owned-parent-lstat", errno)
    try required(
      parentInfo.st_uid == geteuid() && parentInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
      "owned-parent-type")
    var template = Array((parent + "/run.XXXXXX").utf8CString)
    guard let created = template.withUnsafeMutableBufferPointer({ Darwin.mkdtemp($0.baseAddress) })
    else {
      throw ProbeError(stage: "mkdtemp", code: errno)
    }
    let runRoot = String(cString: created)
    let probeExecutable = try physical(executable)
    let homePaths: [Principal: String] = [.a: runRoot + "/home-a", .b: runRoot + "/home-b"]
    let copyPaths: [Principal: String] = [.a: runRoot + "/copy-a", .b: runRoot + "/copy-b"]
    for role in [Principal.a, .b] {
      guard let home = homePaths[role], let copy = copyPaths[role] else {
        throw ProbeError(stage: "fixture-paths", code: EINVAL)
      }
      try makeDirectories(home, root: runRoot)
      try makeDirectories(home + "/tmp", root: runRoot)
      try makeDirectories(home + "/config", root: runRoot)
      try makeDirectories(home + "/cache", root: runRoot)
      try makeDirectories(copy, root: runRoot)
    }
    try makeDirectories(runRoot + "/shared", root: runRoot)
    try makeDirectories(runRoot + "/synthetic-private", root: runRoot)
    var madeProfiles: [Principal: String] = [:]
    var receipts: [ProfileReceipt] = []
    for role in [Principal.a, .b] {
      guard let home = homePaths[role], let copy = copyPaths[role] else {
        throw ProbeError(stage: "fixture-paths", code: EINVAL)
      }
      let text = SandboxProfile.make(executable: probeExecutable, home: home, workingRoot: copy)
      let profilePath = runRoot + "/profile-" + role.rawValue + ".sb"
      try createFile(profilePath, bytes: Data(text.utf8), root: runRoot, limit: maximumProfileBytes)
      madeProfiles[role] = text
      receipts.append(
        ProfileReceipt(
          principal: role, home: home, workingRoot: copy,
          tmpdir: home + "/tmp", profilePath: profilePath,
          profileSHA256: sha256(Data(text.utf8)), profileText: text))
    }
    root = runRoot
    self.executable = probeExecutable
    self.ownedParents = ownedParents
    homes = homePaths
    copies = copyPaths
    profiles = madeProfiles
    profileReceipts = receipts
  }
  func environment(_ role: Principal) -> [String: String] {
    let home = home(role)
    return [
      "HOME": home, "TMPDIR": home + "/tmp/", "PATH": "/usr/bin:/bin",
      "XDG_CONFIG_HOME": home + "/config", "XDG_CACHE_HOME": home + "/cache",
      "LANG": "C", "LC_ALL": "C", "TZ": "UTC",
    ]
  }
  /// Non-optional fixture accessors; the dictionaries are built for exactly the two principals.
  func home(_ role: Principal) -> String {
    guard let value = homes[role] else { fatalError("s4-matrix: missing fixture home") }
    return value
  }
  func copy(_ role: Principal) -> String {
    guard let value = copies[role] else { fatalError("s4-matrix: missing fixture copy") }
    return value
  }
  func profile(_ role: Principal) -> String {
    guard let value = profiles[role] else { fatalError("s4-matrix: missing fixture profile") }
    return value
  }
  func appendCase(
    id: String, category: String, role: Principal = .a, base: String,
    relative: String = "owned.txt", operation: Operation, expectation: Expectation,
    secondBase: String? = nil, secondRelative: String = "destination.txt",
    aliasKind: String? = nil, aliasRelative: String? = nil, physicalAlias: Bool = false,
    limitation: String =
      "Raw current-profile behavior only; not SDK descriptor-guard or admission/export qualification."
  ) throws {
    try required(specs.count < maximumCases, "case-count-bound", E2BIG)
    let folder = base + "/case-" + id
    let canonical = folder + "/" + relative
    let bytes = Data(("synthetic-canary:" + id + ":" + UUID().uuidString + "\n").utf8)
    if operation == .create {
      try makeDirectories(parentDirectory(canonical), root: root)
    } else {
      try createFile(canonical, bytes: bytes, root: root)
    }
    var accessed = canonical
    var alias: AliasRequest?
    if let kind = aliasKind, let relativeAlias = aliasRelative {
      accessed = folder + "/" + relativeAlias
      if kind == "symbolic-link" {
        try makeDirectories(parentDirectory(accessed), root: root)
        let status = canonical.withCString { target in
          accessed.withCString { Darwin.symlink(target, $0) }
        }
        try required(status == 0, "create-owned-symlink", errno)
      } else if kind == "hard-link" {
        try makeDirectories(parentDirectory(accessed), root: root)
        let status = canonical.withCString { source in
          accessed.withCString { Darwin.link(source, $0) }
        }
        try required(status == 0, "create-owned-hardlink", errno)
      }
      alias = AliasRequest(
        kind: kind, canonicalPath: canonical, accessedPath: accessed,
        conditionalPhysicalAlias: physicalAlias)
    }
    var second: String?
    if operation == .link || operation == .rename {
      let target = (secondBase ?? base) + "/case-" + id + "/" + secondRelative
      try makeDirectories(parentDirectory(target), root: root)
      second = target
    }
    specs.append(
      CaseSpec(
        id: id, category: category, principal: role, expectation: expectation,
        operation: operation, first: accessed, second: second, canonicalFile: canonical,
        originalBase64: bytes.base64EncodedString(),
        watchedPaths: uniquePaths([canonical, accessed] + (second.map { [$0] } ?? [])),
        alias: alias, limitation: limitation))
  }

  /// Resolves one fixture-base token from `S4MatrixVectors` for the given principal.
  private func resolveBase(_ token: String, role: Principal) throws -> String {
    let other: Principal = role == .a ? .b : .a
    switch token {
    case "home": return home(role)
    case "other-home": return home(other)
    case "home-tmp": return home(role) + "/tmp"
    case "other-tmp": return home(other) + "/tmp"
    case "copy": return copy(role)
    case "shared": return root + "/shared"
    case "synthetic-private": return root + "/synthetic-private"
    default: throw ProbeError(stage: "vector-base-token", code: EINVAL)
    }
  }

  func populate() throws {
    for vector in S4MatrixVectors.all {
      guard let role = Principal(rawValue: vector.role),
        let operation = Operation(rawValue: vector.operation),
        let expectation = Expectation(rawValue: vector.expectation)
      else { throw ProbeError(stage: "vector-enum", code: EINVAL) }
      if vector.sharedInode {
        // Both principals additionally operate on these very same existing shared bytes/inode.
        let bytes =
          commonSharedBytes ?? Data(("synthetic-common-shared:" + UUID().uuidString + "\n").utf8)
        if commonSharedBytes == nil {
          commonSharedBytes = bytes
          try createFile(root + "/shared/common-owned.txt", bytes: bytes, root: root)
        }
        let common = root + "/shared/common-owned.txt"
        specs.append(
          CaseSpec(
            id: vector.id, category: vector.category, principal: role,
            expectation: expectation, operation: operation, first: common, second: nil,
            canonicalFile: common, originalBase64: bytes.base64EncodedString(),
            watchedPaths: [common],
            alias: nil, limitation: vector.limitation))
        continue
      }
      let base = try resolveBase(vector.base, role: role)
      let secondBase = try vector.secondBase.map { try resolveBase($0, role: role) }
      try appendCase(
        id: vector.id, category: vector.category, role: role, base: base,
        relative: vector.relative, operation: operation, expectation: expectation,
        secondBase: secondBase, secondRelative: vector.secondRelative,
        aliasKind: vector.aliasKind, aliasRelative: vector.aliasRelative,
        physicalAlias: vector.physicalAlias, limitation: vector.limitation)
      if vector.outsideSymlink {
        // The alias replaces the accessed path with a link inside home-a to the owned ungranted
        // private canary, exactly as the original probe's special case did.
        let original = specs.removeLast()
        let alias = home(.a) + "/case-" + vector.id + "/alias.txt"
        try makeDirectories(parentDirectory(alias), root: root)
        let status = original.canonicalFile.withCString { target in
          alias.withCString { Darwin.symlink(target, $0) }
        }
        try required(status == 0, "owned-outside-symlink", errno)
        specs.append(
          CaseSpec(
            id: original.id, category: original.category, principal: .a,
            expectation: expectation, operation: operation, first: alias, second: nil,
            canonicalFile: original.canonicalFile, originalBase64: original.originalBase64,
            watchedPaths: [original.canonicalFile, alias],
            alias: AliasRequest(
              kind: "symbolic-link", canonicalPath: original.canonicalFile,
              accessedPath: alias, conditionalPhysicalAlias: false), limitation: vector.limitation))
      }
    }
    try required(specs.count <= maximumCases, "final-case-bound", E2BIG)
  }
  func snapshots(_ spec: CaseSpec) throws -> [FileState] {
    try spec.watchedPaths.map { try snapshot($0, root: root) }
  }
  func reset(_ spec: CaseSpec) throws {
    switch spec.operation {
    case .read: break
    case .overwrite:
      guard let original = Data(base64Encoded: spec.originalBase64) else {
        throw ProbeError(stage: "reset-original-bytes", code: EINVAL)
      }
      try writeExisting(spec.canonicalFile, bytes: original, root: root)
    case .create: try removeFileIfPresent(spec.first, root: root)
    case .link:
      guard let second = spec.second else {
        throw ProbeError(stage: "reset-link-target", code: EINVAL)
      }
      try removeFileIfPresent(second, root: root)
    case .rename:
      guard let second = spec.second else {
        throw ProbeError(stage: "reset-rename-target", code: EINVAL)
      }
      let source = try snapshot(spec.first, root: root)
      let target = try snapshot(second, root: root)
      if source.entry == nil && target.entry != nil {
        let status = second.withCString { from in
          spec.first.withCString { Darwin.rename(from, $0) }
        }
        try required(status == 0, "restore-rename", errno)
      } else {
        try required(source.entry != nil && target.entry == nil, "restore-rename-state")
      }
    }
  }
  func runProcess(_ spec: CaseSpec, confined: Bool, payload: Data) throws -> ProcessReceipt {
    workerCount += 1
    try required(workerCount <= maximumWorkers, "worker-count-bound", E2BIG)
    let job = Job(
      schema: "memoshi.s4.raw-file-job.v1", root: root, caseID: spec.id,
      operation: spec.operation, first: spec.first, second: spec.second,
      payloadBase64: payload.base64EncodedString())
    let encodedJob = try JSONEncoder().encode(job).base64EncodedString()
    let args =
      confined
      ? [
        "/usr/bin/sandbox-exec", "-p", profile(spec.principal), executable, "--s4-worker",
        encodedJob,
      ]
      : [executable, "--s4-worker", encodedJob]
    var processEnvironment = environment(spec.principal)
    processEnvironment[ownedRootsEnvironment] = ownedParents.joined(separator: "\n")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: args[0])
    process.arguments = Array(args.dropFirst())
    process.environment = processEnvironment
    process.currentDirectoryURL = URL(fileURLWithPath: home(spec.principal))
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    process.standardInput = FileHandle.nullDevice
    do { try process.run() } catch {
      return ProcessReceipt(
        argv: args, environment: processEnvironment, confined: confined,
        timedOut: false, exitCode: -1, terminationReason: "launch_failed",
        launchFailure: String(describing: error),
        stdoutBase64: "", stderrBase64: "", result: nil)
    }
    let deadline = Date().addingTimeInterval(workerDeadlineSeconds)
    while process.isRunning && Date() < deadline { usleep(10_000) }
    let timedOut = process.isRunning
    if timedOut { Darwin.kill(process.processIdentifier, SIGKILL) }
    process.waitUntilExit()
    let output = out.fileHandleForReading.readDataToEndOfFile()
    let errors = err.fileHandleForReading.readDataToEndOfFile()
    let result = try? JSONDecoder().decode(WorkerResult.self, from: output)
    let matching =
      result?.schema == "memoshi.s4.raw-file-worker.v1" && result?.caseID == spec.id
      && result?.operation == spec.operation
    return ProcessReceipt(
      argv: args, environment: processEnvironment, confined: confined,
      timedOut: timedOut, exitCode: process.terminationStatus,
      terminationReason: process.terminationReason == .exit ? "exit" : "signal", launchFailure: nil,
      stdoutBase64: output.base64EncodedString(), stderrBase64: errors.base64EncodedString(),
      result: matching ? result : nil)
  }
  func attempt(_ spec: CaseSpec, confined: Bool, number: Int) throws -> S4EffectReceipt {
    let before = try snapshots(spec)
    let payload = Data(
      ("synthetic-mutation:" + spec.id + ":attempt-" + String(number) + ":" + UUID().uuidString
        + "\n").utf8)
    let process = try runProcess(spec, confined: confined, payload: payload)
    let after = try snapshots(spec)
    func state(_ states: [FileState], _ path: String) -> FileState? {
      states.first { byteEqual($0.path, path) }
    }
    let fromBefore = state(before, spec.first)
    let fromAfter = state(after, spec.first)
    let toBefore = spec.second.flatMap { state(before, $0) }
    let toAfter = spec.second.flatMap { state(after, $0) }
    let canonicalBefore = state(before, spec.canonicalFile)
    let canonicalAfter = state(after, spec.canonicalFile)
    guard let original = Data(base64Encoded: spec.originalBase64) else {
      throw ProbeError(stage: "attempt-original-bytes", code: EINVAL)
    }
    let observed = process.result.flatMap { Data(base64Encoded: $0.bytesBase64) } ?? Data()
    let unchanged = before == after
    let workerComplete =
      process.result?.succeeded == true && process.exitCode == 0 && !process.timedOut
    let verified: Bool
    let disclosed =
      !observed.isEmpty && original.starts(with: observed)
      && process.result?.objectIdentity == fromBefore?.resolvedEntry?.identity
    let originalLinkCount = fromBefore?.resolvedEntry?.links
    switch spec.operation {
    case .read:
      verified = workerComplete && observed == original && disclosed && unchanged
    case .overwrite:
      verified =
        workerComplete && canonicalAfter?.bytesBase64 == payload.base64EncodedString()
        && canonicalBefore?.resolvedEntry?.identity == canonicalAfter?.resolvedEntry?.identity
        && canonicalBefore?.bytesBase64 == spec.originalBase64
    case .create:
      verified =
        workerComplete && fromBefore?.entry == nil && fromBefore?.entryErrno == ENOENT
        && fromAfter?.bytesBase64 == payload.base64EncodedString() && fromAfter?.entry != nil
    case .link:
      verified =
        workerComplete && toBefore?.entry == nil && toBefore?.entryErrno == ENOENT
        && fromAfter?.resolvedEntry?.identity == fromBefore?.resolvedEntry?.identity
        && toAfter?.resolvedEntry?.identity == fromBefore?.resolvedEntry?.identity
        && toAfter?.bytesBase64 == spec.originalBase64
        && fromAfter?.resolvedEntry?.links == originalLinkCount.map { $0 + 1 }
    case .rename:
      verified =
        workerComplete && toBefore?.entry == nil && toBefore?.entryErrno == ENOENT
        && fromAfter?.entry == nil && fromAfter?.entryErrno == ENOENT
        && toAfter?.resolvedEntry?.identity == fromBefore?.resolvedEntry?.identity
        && toAfter?.bytesBase64 == spec.originalBase64
    }
    return S4EffectReceipt(
      process: process, payloadBase64: payload.base64EncodedString(), before: before, after: after,
      operationVerified: verified,
      effectObserved: spec.operation == .read ? disclosed || !unchanged : !unchanged,
      unchanged: unchanged)
  }
  func runCase(_ spec: CaseSpec) throws -> CaseReceipt {
    let initial = try snapshots(spec)
    var proof: AliasProof?
    if let request = spec.alias {
      let canonical = try snapshot(request.canonicalPath, root: root)
      let accessed = try snapshot(request.accessedPath, root: root)
      let distinct = !byteEqual(request.canonicalPath, request.accessedPath)
      let sameIdentity =
        canonical.resolvedEntry != nil && accessed.resolvedEntry != nil
        && canonical.resolvedEntry?.identity == accessed.resolvedEntry?.identity
      let sameBytes =
        canonical.bytesBase64 != nil && canonical.bytesBase64 == accessed.bytesBase64
        && canonical.readErrno == 0 && accessed.readErrno == 0
      proof = AliasProof(
        request: request, canonical: canonical, accessed: accessed, differentPathBytes: distinct,
        sameDeviceAndInode: sameIdentity, sameBytes: sameBytes,
        established: distinct && sameIdentity && sameBytes)
      if proof?.established != true {
        let conditional = request.conditionalPhysicalAlias
        let failures =
          conditional
          ? []
          : [
            Failure(
              kind: "fixture_alias_failure", caseID: spec.id,
              detail: "Requested link did not establish matching host-readable inode and bytes.")
          ]
        return CaseReceipt(
          spec: spec,
          outcome: conditional ? "not_applicable_alias_not_established" : "fixture_failure",
          preconditionValid: false, controlValid: false, aliasProof: proof, sandboxedAttempts: [],
          unconfinedControl: nil, restored: initial, failures: failures)
      }
    }
    let firstState = initial.first { byteEqual($0.path, spec.first) }
    let sourceReady =
      spec.operation == .create
      ? firstState?.entry == nil && firstState?.entryErrno == ENOENT
      : firstState?.bytesBase64 == spec.originalBase64 && firstState?.resolvedEntry != nil
        && firstState?.readErrno == 0
    let destinationReady =
      spec.second.map { target in
        initial.first { byteEqual($0.path, target) }?.entryErrno == ENOENT
      } ?? true
    if !sourceReady || !destinationReady {
      return CaseReceipt(
        spec: spec, outcome: "fixture_failure", preconditionValid: false, controlValid: false,
        aliasProof: proof, sandboxedAttempts: [], unconfinedControl: nil, restored: initial,
        failures: [
          Failure(
            kind: "fixture_precondition", caseID: spec.id,
            detail: "Missing owned source bytes/inode or nonempty destination; no denial counted.")
        ])
    }
    var attempts: [S4EffectReceipt] = []
    var failures: [Failure] = []
    var control: S4EffectReceipt?
    var restored = initial
    do {
      for number in 1...2 {
        try reset(spec)
        try required(try snapshots(spec) == initial, "repeat-reset-identity-and-bytes")
        attempts.append(try attempt(spec, confined: true, number: number))
      }
      try reset(spec)
      try required(try snapshots(spec) == initial, "control-reset-identity-and-bytes")
      control = try attempt(spec, confined: false, number: 3)
      try reset(spec)
      restored = try snapshots(spec)
    } catch {
      failures.append(
        Failure(kind: "harness_failure", caseID: spec.id, detail: String(describing: error)))
      return CaseReceipt(
        spec: spec, outcome: "harness_failure", preconditionValid: true, controlValid: false,
        aliasProof: proof, sandboxedAttempts: attempts, unconfinedControl: control,
        restored: (try? snapshots(spec)) ?? restored, failures: failures)
    }
    let controlValid = control?.operationVerified == true && restored == initial
    if !controlValid {
      failures.append(
        Failure(
          kind: "invalid_unconfined_control", caseID: spec.id,
          detail:
            "The exact-path unconfined operation or independent inode/byte restoration failed; confinement is inconclusive."
        ))
    }
    let bypasses = attempts.filter(\.effectObserved).count
    let outcome: String
    if spec.expectation == .deny {
      if bypasses > 0 {
        outcome =
          controlValid
          ? (bypasses == 2 ? "reproducible_guard_bypass" : "guard_bypass_not_reproduced")
          : "inconclusive_effect_with_invalid_control"
        failures.append(
          Failure(
            kind: controlValid ? "guard_bypass" : "unqualified_effect", caseID: spec.id,
            detail:
              "Independent effect/disclosure observed in \(bypasses)/2 confined attempts; inspect category and fixture limitations."
          ))
      } else {
        let denied = attempts.allSatisfy { attempt in
          let result = attempt.process.result
          return !attempt.process.timedOut && result?.succeeded == false && attempt.unchanged
            && (result?.errnoCode == EPERM || result?.errnoCode == EACCES)
        }
        outcome = controlValid && denied ? "denied" : "inconclusive"
        if !denied {
          failures.append(
            Failure(
              kind: "denial_not_established", caseID: spec.id,
              detail:
                "Requires two decoded permission failures, unchanged host state and a valid same-path unconfined positive; exit status alone is insufficient."
            ))
        }
      }
    } else {
      let allowed = attempts.allSatisfy(\.operationVerified)
      outcome = controlValid && allowed ? "allowed" : "allowed_control_failed"
      if !allowed {
        failures.append(
          Failure(
            kind: "confined_positive_failed", caseID: spec.id,
            detail: "A legitimate owned/template operation failed independent byte/inode checks."))
      }
    }
    return CaseReceipt(
      spec: spec, outcome: outcome, preconditionValid: true, controlValid: controlValid,
      aliasProof: proof, sandboxedAttempts: attempts, unconfinedControl: control,
      restored: restored, failures: failures)
  }
  func run() throws -> Report {
    try populate()
    var receipts: [CaseReceipt] = []
    for spec in specs {
      do { receipts.append(try runCase(spec)) } catch {
        receipts.append(
          CaseReceipt(
            spec: spec, outcome: "harness_failure", preconditionValid: false,
            controlValid: false, aliasProof: nil, sandboxedAttempts: [], unconfinedControl: nil,
            restored: (try? snapshots(spec)) ?? [],
            failures: [
              Failure(
                kind: "harness_failure", caseID: spec.id,
                detail: String(describing: error))
            ]))
      }
    }
    let failures = receipts.flatMap(\.failures)
    let reproduced = receipts.filter { $0.outcome == "reproducible_guard_bypass" }.count
    let single = receipts.filter { $0.outcome == "guard_bypass_not_reproduced" }.count
    let exit = S4Matrix.recordedExit(
      failures: failures, reproducedBypasses: reproduced, singleBypasses: single)
    return Report(
      schema: "memoshi.s4.raw-file-profile.v1",
      scope:
        "Bounded synthetic raw Seatbelt file profile only; not S4 acceptance or D96/SDK admission/export conformance.",
      root: root, processUID: geteuid(), sourceFileSHA256: sourceFileSHA256,
      exactEnumSHA256: enumSHA256,
      enumHashConvention:
        "UTF-8 SourceSecretSpellings and SandboxProfile enums exactly as in SandboxProfileSnapshot.swift (the shipping profile re-snapshotted 2026-11-18, re-indented to top level), joined by one blank line, internal LF, no final LF. Deny rules carry the shipping (with message (param \"INV\")) tag; the matrix passes no INV value.",
      profiles: profileReceipts,
      limits: [
        "No actual user private paths, credentials, security tools, networks, sockets or services are accessed.",
        "No supplied toolchain read roots, gateway socket or certificate exception; profile enum is unmodified.",
        "Preexisting unsafe hardlink/symlink fixtures test raw defense in depth; D96 admission must reject them and is not tested here.",
        "Secret-directory descendants are requested protection probes; a gap is retained even though the captured leaf regex may not protect the subtree.",
        "Missing Unicode/case aliases are not counted as denials. Actual stat device/inode plus host bytes are required.",
        "Kernel-denial attribution, TCC, races, SDK guard, generic clients, reference hardware and production enablement remain open.",
        "Fresh run directories and receipts are retained; no automatic recursive cleanup or retries.",
      ], maximumCaseCount: maximumCases, maximumWorkerCount: maximumWorkers,
      actualWorkerCount: workerCount,
      maximumPrimaryWorkerSyscalls: maximumWorkerSyscalls,
      workerDeadlineSeconds: workerDeadlineSeconds,
      cases: receipts, failures: failures, reproducibleBypassCount: reproduced,
      nonReproducedBypassCount: single,
      validDeniedCaseCount: receipts.filter { $0.outcome == "denied" }.count,
      validAllowedCaseCount: receipts.filter { $0.outcome == "allowed" }.count,
      notApplicableAliasCount: receipts.filter {
        $0.outcome == "not_applicable_alias_not_established"
      }.count, exitCode: exit)
  }
}

/// The in-repo S4-T1 entry point for the `memoshi-qualification s4-matrix` subcommand.
package enum S4Matrix {
  /// Exit for a finished matrix. The three preexisting hard-link effects are D137's accepted
  /// limit and exit 2 on their own. Any other failure exits 3, including one that lands in the
  /// same run as those hard links, so a new escape is not reported as the accepted limit.
  package static func recordedExit(
    failures: [Failure], reproducedBypasses: Int, singleBypasses: Int
  ) -> Int32 {
    let acceptedLimit = failures.allSatisfy { failure in
      failure.kind == "guard_bypass"
        && S4MatrixVectors.preexistingHardLinkIDs.contains(failure.caseID)
    }
    if !failures.isEmpty && !acceptedLimit { return 3 }
    if !failures.isEmpty || reproducedBypasses > 0 || singleBypasses > 0 { return 2 }
    return 0
  }

  /// The recorded owned scratch parent the standard APFS run uses.
  package static let defaultScratch = batchScratch

  /// A fresh owned run parent below the recorded scratch, for a run without `--parent`. The
  /// scratch is created 0700 when absent and must be a canonical directory this user owns with
  /// no group or other access; the parent is a new `mkdtemp` child, never an existing one.
  package static func makeDefaultParent() throws -> String {
    if Darwin.mkdir(batchScratch, 0o700) != 0 && errno != EEXIST {
      throw ProbeError(stage: "scratch-mkdir", code: errno)
    }
    var info = stat()
    try required(lstat(batchScratch, &info) == 0, "scratch-lstat", errno)
    try required(
      info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) && info.st_uid == geteuid()
        && info.st_mode & 0o077 == 0, "scratch-owned-private")
    try required(byteEqual(try physical(batchScratch), batchScratch), "scratch-canonical")
    var template = Array((batchScratch + "/run-parent.XXXXXX").utf8CString)
    guard let created = template.withUnsafeMutableBufferPointer({ Darwin.mkdtemp($0.baseAddress) })
    else { throw ProbeError(stage: "parent-mkdtemp", code: errno) }
    return String(cString: created)
  }

  /// Prepares the 105-vector matrix below `parent`: checks ownership, creates the run root,
  /// fixtures and profiles, and runs no case. `parent` must be canonical and strictly below the
  /// recorded scratch or one of `extraOwnedParents`, each an absolute canonical directory this
  /// user owns. `executable` is this binary, re-run as every worker.
  package static func prepare(
    parent: String, executable: URL, extraOwnedParents: [String] = []
  ) throws -> S4PreparedMatrix {
    for root in extraOwnedParents {
      var info = stat()
      try required(
        root.hasPrefix("/") && byteEqual(try physical(root), root), "owned-root-canonical")
      try required(lstat(root, &info) == 0, "owned-root-lstat", errno)
      try required(
        info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) && info.st_uid == geteuid(),
        "owned-root-type")
    }
    return S4PreparedMatrix(
      try Probe(
        parent: parent, executable: executable.path,
        ownedParents: [batchScratch] + extraOwnedParents))
  }

  /// The snapshot profile the matrix runs (re-taken from the shipping profile on 2026-11-18),
  /// rendered for the given inputs, so a test can compare it with the profile Memoshi ships.
  package static func snapshotProfile(
    executable: String, home: String, workingRoot: String?, gatewaySocket: String?,
    certificateBundle: String?, readOnlyToolchainRoots: [String]
  ) -> String {
    SandboxProfile.make(
      executable: executable, home: home, workingRoot: workingRoot, gatewaySocket: gatewaySocket,
      certificateBundle: certificateBundle, readOnlyToolchainRoots: readOnlyToolchainRoots)
  }

  /// Creates a run's evidence directory, mode 0700, refusing one that already exists.
  package static func createOutputDirectory(_ path: String) throws {
    try required(Darwin.mkdir(path, 0o700) == 0, "output-directory-create", errno)
  }

  /// Writes `data` to a new file, mode 0600, refusing an existing file or link.
  package static func writeExclusive(_ data: Data, to path: String) throws {
    let descriptor = path.withCString {
      Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
    }
    try required(descriptor >= 0, "exclusive-open", errno)
    defer { Darwin.close(descriptor) }
    try required(data.count <= 32 * 1024 * 1024, "exclusive-byte-bound", EFBIG)
    var offset = 0
    for _ in 0..<1024 {
      if offset == data.count { break }
      let amount = writeBuffer(descriptor, data, offset: offset)
      if amount < 0 {
        if errno == EINTR { continue }
        throw ProbeError(stage: "exclusive-write", code: errno)
      }
      try required(amount > 0, "exclusive-zero-write", EIO)
      offset += amount
    }
    try required(offset == data.count, "exclusive-write-call-bound", E2BIG)
  }

  /// Worker mode: `memoshi-qualification --s4-worker <base64 job>`, run directly or under
  /// `sandbox-exec`. Writes one JSON `WorkerResult` line and exits 0/1.
  package static func worker(_ base64Job: String) -> Int32 {
    do {
      alarm(6)
      guard let data = Data(base64Encoded: base64Job) else {
        throw ProbeError(stage: "worker-argument", code: EINVAL)
      }
      let job = try JSONDecoder().decode(Job.self, from: data)
      let result = executeWorker(job)
      let output = try JSONEncoder().encode(result)
      try writeFD(STDOUT_FILENO, output)
      Darwin.exit(result.succeeded ? 0 : 1)
    } catch {
      let failure = Failure(
        kind: "fatal_worker_failure", caseID: "worker", detail: String(describing: error))
      if let output = try? JSONEncoder().encode(failure) {
        FileHandle.standardError.write(output)
        FileHandle.standardError.write(Data("\n".utf8))
      }
      Darwin.exit(3)
    }
  }

  /// Encodes the one-line summary the probe originally printed to stdout. `exitCode` is the
  /// process exit, which an incomplete alias probe raises above the matrix's own.
  package static func summary(report: Report, receiptPath: String, exitCode: Int32? = nil)
    throws -> Data
  {
    let summary = RunSummary(
      schema: "memoshi.s4.raw-file-profile-summary.v1", receipt: receiptPath,
      exitCode: exitCode ?? report.exitCode,
      reproducibleBypassCount: report.reproducibleBypassCount, caseCount: report.cases.count)
    return try JSONEncoder().encode(summary)
  }

  /// Writes the full report JSON into the owned run root, as the original probe did.
  package static func writeReceipt(report: Report, root: String) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let receipt = root + "/receipt.json"
    try writeExclusive(try encoder.encode(report), to: receipt)
    return receipt
  }

  /// A one-line human-readable digest of the summary counts.
  package static func humanSummary(_ report: Report) -> String {
    "S4 raw matrix: \(report.cases.count) cases; denied \(report.validDeniedCaseCount) / allowed \(report.validAllowedCaseCount) / reproducible effects \(report.reproducibleBypassCount) / not-reproduced \(report.nonReproducedBypassCount) / default-ignorable (U+200B/U+200D) aliases not established \(report.notApplicableAliasCount); exit \(report.exitCode)"
  }
}

/// A matrix whose owned run root, fixtures and profiles exist and whose cases have not run.
package final class S4PreparedMatrix {
  private let probe: Probe

  fileprivate init(_ probe: Probe) { self.probe = probe }

  /// The fresh run root below the parent.
  package var root: String { probe.root }

  /// Runs every case once and returns the report.
  package func run() throws -> Report { try probe.run() }
}
