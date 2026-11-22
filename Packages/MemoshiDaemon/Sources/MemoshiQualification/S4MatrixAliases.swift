// S4-T1: runs the three default-ignorable (U+200B / U+200D) alias spellings of the S4 raw
// matrix on arbitrary mounted volumes. The matrix's `physical-alias-default-ignorable` vectors
// are "established" only when distinct pathname bytes address the same device/inode with
// matching host bytes; on APFS the default-ignorable spellings are expected not to establish,
// while HFS+ folds the U+200D spellings. Qualification code only; it creates a 0700 scratch
// directory of synthetic files, records errno-level facts and removes exactly that directory.
import Darwin
import Foundation

/// One alias spelling: the canonical fixture path and the distinct default-ignorable spelling.
package struct S4AliasSpelling: Codable, Equatable {
  package let id: String
  /// Matrix vector ids this spelling's establishment feeds (`secret-ignorable-*` are read and
  /// overwrite; `config-ignorable` is overwrite only).
  package let vectorIDs: [String]
  package let canonicalRelative: String
  package let accessedRelative: String
  /// The Unicode scalar that distinguishes the accessed spelling from the canonical one.
  package let distinguishingScalar: String

  package static let defaultIgnorable: [S4AliasSpelling] = [
    S4AliasSpelling(
      id: "secret-ignorable-joiner",
      vectorIDs: ["secret-ignorable-joiner-read", "secret-ignorable-joiner-overwrite"],
      canonicalRelative: ".env", accessedRelative: ".e\u{200d}nv",
      distinguishingScalar: "U+200D"),
    S4AliasSpelling(
      id: "secret-ignorable-trailing",
      vectorIDs: ["secret-ignorable-trailing-read", "secret-ignorable-trailing-overwrite"],
      canonicalRelative: ".env", accessedRelative: ".env\u{200b}",
      distinguishingScalar: "U+200B"),
    S4AliasSpelling(
      id: "config-ignorable", vectorIDs: ["config-ignorable-overwrite"],
      canonicalRelative: ".git/config", accessedRelative: ".g\u{200d}it/config",
      distinguishingScalar: "U+200D"),
  ]
}

package struct S4AliasOutcome: Codable, Equatable {
  package let spellingID: String
  package let vectorIDs: [String]
  package let canonicalCreated: Bool
  package let canonicalCreateErrno: Int32
  package let canonicalStatErrno: Int32
  package let accessedStatErrno: Int32
  /// Distinct pathname bytes address the same device/inode.
  package let sameDeviceAndInode: Bool
  package let sameBytes: Bool
  package let established: Bool
  package let detail: String
}

package struct S4AliasVolumeResult: Codable, Equatable {
  package let volumePath: String
  package let filesystem: String
  package let writable: Bool
  /// Why the volume was skipped, when `writable` is false.
  package let skippedReason: String?
  package let scratchPath: String?
  package let outcomes: [S4AliasOutcome]
  package let cleanedUp: Bool
}

package enum S4MatrixAliases {
  /// The establishment rule, shared with the matrix's `AliasProof`: distinct pathname bytes,
  /// same device/inode, and the host read the same bytes from both spellings.
  package static func established(
    differentPathBytes: Bool, sameDeviceAndInode: Bool, sameBytes: Bool
  ) -> Bool {
    differentPathBytes && sameDeviceAndInode && sameBytes
  }

  /// Probes one mounted volume: creates the canonical fixtures and stats each accessed
  /// spelling. Never follows or trusts preexisting content; everything lives in a fresh 0700
  /// directory that is removed afterwards.
  package static func probe(volume: URL) -> S4AliasVolumeResult {
    let volumePath = volume.path
    var filesystem = "unknown"
    var statfsResult = statfs()
    let mount = volumePath.withCString { statfs($0, &statfsResult) }
    if mount == 0 {
      filesystem = withUnsafeBytes(of: statfsResult.f_fstypename) { buffer -> String in
        guard let base = buffer.baseAddress else { return "unknown" }
        return String(cString: base.assumingMemoryBound(to: CChar.self))
      }
    }
    func fail(_ reason: String) -> S4AliasVolumeResult {
      S4AliasVolumeResult(
        volumePath: volumePath, filesystem: filesystem, writable: false, skippedReason: reason,
        scratchPath: nil, outcomes: [], cleanedUp: false)
    }
    var template = Array((volumePath + "/memoshi-s4-alias-XXXXXX").utf8CString)
    guard let created = template.withUnsafeMutableBufferPointer({ Darwin.mkdtemp($0.baseAddress) })
    else {
      return fail("mkdir failed: errno=\(errno) (read-only or refusing volume)")
    }
    let scratch = String(cString: created)
    var outcomes: [S4AliasOutcome] = []
    let canary = Data("synthetic-s4-alias-canary:".utf8)
    for spelling in S4AliasSpelling.defaultIgnorable {
      // One fresh subdirectory per spelling: spellings share canonical names by design and must
      // not see each other's fixtures.
      let spellingRoot = scratch + "/" + spelling.id
      guard createParents(spellingRoot + "/x", root: scratch) else {
        outcomes.append(
          S4AliasOutcome(
            spellingID: spelling.id, vectorIDs: spelling.vectorIDs, canonicalCreated: false,
            canonicalCreateErrno: errno, canonicalStatErrno: 0, accessedStatErrno: 0,
            sameDeviceAndInode: false, sameBytes: false, established: false,
            detail: "per-spelling scratch create failed: errno=\(errno)"))
        continue
      }
      let canonical = spellingRoot + "/" + spelling.canonicalRelative
      let accessed = spellingRoot + "/" + spelling.accessedRelative
      var canonicalCreateErrno: Int32 = 0
      var canonicalCreated = false
      if createParents(canonical, root: scratch) {
        let exclusive = canonical.withCString {
          Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        }
        let fd: Int32
        if exclusive >= 0 {
          fd = exclusive
        } else {
          canonicalCreateErrno = errno
          // Some filesystems refuse O_EXCL or report a stale collision; fall back to truncation
          // so the canonical fixture exists with the exact bytes this probe wrote.
          fd = canonical.withCString {
            Darwin.open($0, O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOFOLLOW)
          }
        }
        if fd >= 0 {
          canonicalCreated = true
          if canonicalCreateErrno != 0 { canonicalCreateErrno = 0 }
          _ = canary.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, canary.count) }
          Darwin.close(fd)
        }
      } else {
        canonicalCreateErrno = errno
      }
      var canonicalStat = stat()
      let canonicalStatus = canonical.withCString {
        Darwin.fstatat(AT_FDCWD, $0, &canonicalStat, 0)
      }
      let canonicalErrno: Int32 = canonicalStatus == 0 ? 0 : errno
      var accessedStat = stat()
      let accessedStatus = accessed.withCString { Darwin.fstatat(AT_FDCWD, $0, &accessedStat, 0) }
      let accessedErrno: Int32 = accessedStatus == 0 ? 0 : errno
      let sameIdentity =
        canonicalStatus == 0 && accessedStatus == 0
        && UInt64(bitPattern: Int64(canonicalStat.st_dev))
          == UInt64(bitPattern: Int64(accessedStat.st_dev))
        && canonicalStat.st_ino == accessedStat.st_ino
      let sameBytes: Bool
      if canonicalStatus == 0 && accessedStatus == 0, let canonicalBytes = readAll(canonical) {
        // Both reads must succeed and return exactly the canary this probe wrote.
        sameBytes = canonicalBytes == canary && readAll(accessed) == canonicalBytes
      } else {
        sameBytes = false
      }
      let distinct = !canonical.utf8.elementsEqual(accessed.utf8)
      var detail: String
      if canonicalCreated == false {
        detail = "canonical fixture create failed: errno=\(canonicalCreateErrno)"
      } else if accessedStatus != 0 {
        detail = "accessed spelling did not resolve: errno=\(accessedErrno)"
      } else if sameIdentity {
        detail = "the filesystem folded the spellings to one inode (alias established)"
      } else {
        detail = "distinct inode at the accessed spelling (alias not established)"
      }
      outcomes.append(
        S4AliasOutcome(
          spellingID: spelling.id, vectorIDs: spelling.vectorIDs,
          canonicalCreated: canonicalCreated, canonicalCreateErrno: canonicalCreateErrno,
          canonicalStatErrno: canonicalErrno, accessedStatErrno: accessedErrno,
          sameDeviceAndInode: sameIdentity, sameBytes: sameBytes,
          established: established(
            differentPathBytes: distinct, sameDeviceAndInode: sameIdentity, sameBytes: sameBytes),
          detail: detail))
    }
    let cleaned = removeTree(scratch, within: scratch)
    return S4AliasVolumeResult(
      volumePath: volumePath, filesystem: filesystem, writable: true, skippedReason: nil,
      scratchPath: scratch, outcomes: outcomes, cleanedUp: cleaned)
  }

  /// Creates every parent directory of `path` below `root` (never the final component itself),
  /// failing on any non-directory.
  private static func createParents(_ path: String, root: String) -> Bool {
    guard path.utf8.starts(with: (root + "/").utf8) else { return false }
    var current = root
    let components = path.utf8.dropFirst(root.utf8.count + 1)
      .split(separator: 0x2F as UInt8, omittingEmptySubsequences: true)
    guard components.count > 1 else { return true }
    for component in components.dropLast() {
      current += "/" + String(decoding: component, as: UTF8.self)
      if Darwin.mkdir(current, 0o700) != 0 && errno != EEXIST { return false }
    }
    return true
  }

  private static func readAll(_ path: String) -> Data? {
    let fd = path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC) }
    guard fd >= 0 else { return nil }
    defer { Darwin.close(fd) }
    var data = Data()
    var storage = [UInt8](repeating: 0, count: 4096)
    while true {
      let capacity = storage.count
      let amount = storage.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, capacity) }
      if amount <= 0 { break }
      data.append(contentsOf: storage.prefix(amount))
      if data.count > 1 << 20 { return nil }
    }
    return data
  }

  /// Depth-first removal of the probe's own `mkdtemp` scratch; it never leaves `root` and never
  /// follows a link. Returns final success.
  private static func removeTree(_ path: String, within root: String) -> Bool {
    guard path.utf8.elementsEqual(root.utf8) || path.utf8.starts(with: (root + "/").utf8) else {
      return false
    }
    var removed = true
    guard
      let names: [String] = path.withCString({ directoryPath -> [String]? in
        guard let directory = opendir(directoryPath) else { return nil }
        defer { closedir(directory) }
        var names: [String] = []
        while let entry = readdir(directory) {
          let name = withUnsafeBytes(of: entry.pointee.d_name) { buffer -> String in
            guard let base = buffer.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
          }
          if name != "." && name != ".." && !name.isEmpty { names.append(name) }
        }
        return names
      })
    else { return Darwin.rmdir(path) == 0 || errno == ENOENT }
    for name in names {
      let child = path + "/" + name
      var info = stat()
      let directory: Bool = child.withCString {
        Darwin.fstatat(AT_FDCWD, $0, &info, AT_SYMLINK_NOFOLLOW) == 0
          && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
      }
      if directory {
        if !removeTree(child, within: root) { removed = false }
      } else if Darwin.unlink(child) != 0 && errno != ENOENT {
        removed = false
      }
    }
    return removed && (Darwin.rmdir(path) == 0 || errno == ENOENT)
  }
}
