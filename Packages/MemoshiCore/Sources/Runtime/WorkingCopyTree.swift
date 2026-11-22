import Darwin

/// One scanned tree keyed by `/`-separated paths relative to its root, where `""` is the root.
struct WorkingCopyTree: Equatable, Sendable {
  var directories: [String: WorkingCopyDirectoryRecord] = [:]
  var files: [String: WorkingCopyFileRecord] = [:]

  /// Every scanned directory and file identity, the root included.
  var identities: Set<WorkingCopyObjectID> {
    var result = Set(directories.values.map(\.identity))
    result.formUnion(files.values.map(\.state.identity))
    return result
  }
}

/// The namespace a scan reads. A source scan passes each nonempty source-relative path to the
/// trusted original-namespace entry policy before that entry is examined, opened, hashed or
/// copied. The private stage is classified only through its original targets at export.
enum WorkingCopyNamespace {
  case source((String) throws -> Void)
  case stage
}

/// A fresh private directory receiving admitted bytes.
struct WorkingCopyCopyTarget {
  let handle: WorkingCopyHandle
  let path: String
  let device: UInt64
}

extension WorkingCopyFS {
  /// Scans a tree without following links: real same-device directories and single-link regular
  /// files owned by this user, each unchanged while it is hashed. Any other entry, including a
  /// symlink, special file or mount crossing, refuses the whole scan; nothing is skipped.
  static func scan(
    _ root: WorkingCopyHandle, path: String, namespace: WorkingCopyNamespace,
    limits: WorkingCopyLimits, buffer: inout [UInt8]
  ) throws -> WorkingCopyTree {
    var created: Set<WorkingCopyObjectID> = []
    return try scan(
      root, path: path, namespace: namespace, copyTo: nil, created: &created,
      limits: limits, buffer: &buffer)
  }

  /// Scans a tree and, with `copyTo`, copies each entry into a fresh private object. Each
  /// created object's identity is recorded before a later step can fail, so a refused admission
  /// can remove exactly those objects and nothing else.
  static func scan(
    _ root: WorkingCopyHandle, path: String, namespace: WorkingCopyNamespace,
    copyTo: WorkingCopyCopyTarget?, created: inout Set<WorkingCopyObjectID>,
    limits: WorkingCopyLimits, buffer: inout [UInt8]
  ) throws -> WorkingCopyTree {
    try verifyPath(root.value, path)
    let rootMetadata = try metadata(root.value)
    try requireOwnedDirectory(rootMetadata, path: path)
    var tree = WorkingCopyTree()
    var budget = WorkingCopyBudget(limits)
    try scanDirectory(
      root, path: path, relative: "", device: WorkingCopyObjectID(rootMetadata).device,
      namespace: namespace, copyTo: copyTo, created: &created, depth: 0, budget: &budget,
      buffer: &buffer, tree: &tree)
    return tree
  }

  /// Opens a directory below `root` one validated no-follow component at a time.
  static func openRelativeDirectory(
    root: WorkingCopyHandle, rootPath: String, components: ArraySlice<String>, device: UInt64
  ) throws -> WorkingCopyHandle {
    var directory = root
    var path = rootPath
    for name in components {
      path = childPath(path, name)
      directory = try openDirectory(
        directory.value, name: name, expectedPath: path, device: device)
    }
    try verifyPath(directory.value, path)
    return directory
  }

  private static func scanDirectory(
    _ directory: WorkingCopyHandle, path: String, relative: String, device: UInt64,
    namespace: WorkingCopyNamespace, copyTo: WorkingCopyCopyTarget?,
    created: inout Set<WorkingCopyObjectID>, depth: Int, budget: inout WorkingCopyBudget,
    buffer: inout [UInt8], tree: inout WorkingCopyTree
  ) throws {
    try verifyPath(directory.value, path)
    let before = try metadata(directory.value)
    try requireOwnedDirectory(before, path: path)
    try requireDirectory(before, path: path, device: device)
    try requireContentOnlyMetadata(directory.value, metadata: before)
    let initialNames = try entryNames(directory.value, maximumEntries: budget.remainingEntries)
    try budget.consumeEntries(initialNames.count)
    tree.directories[relative] = WorkingCopyDirectoryRecord(before)
    for name in initialNames {
      try Task.checkCancellation()
      try budget.requireDepth(depth + 1)
      let fullPath = childPath(path, name)
      let relativePath = relative.isEmpty ? name : relative + "/" + name
      // The original-namespace policy sees each source entry before any per-entry access.
      if case .source(let validateEntry) = namespace { try validateEntry(relativePath) }
      guard let entry = try metadataAt(directory.value, name) else {
        throw WorkingCopyFailure.refused("entry disappeared during scan: \(fullPath)")
      }
      switch entry.st_mode & mode_t(S_IFMT) {
      case mode_t(S_IFDIR):
        try requireOwnedDirectory(entry, path: fullPath)
        let child = try openDirectory(
          directory.value, name: name, expectedPath: fullPath, device: device)
        var copiedChild: WorkingCopyCopyTarget?
        if let copyTo {
          copiedChild = try makePrivateDirectory(in: copyTo, name: name, created: &created)
        }
        try scanDirectory(
          child, path: fullPath, relative: relativePath, device: device, namespace: namespace,
          copyTo: copiedChild, created: &created, depth: depth + 1, budget: &budget,
          buffer: &buffer, tree: &tree)
        if let copiedChild {
          // The admitted mode applies only once the private subtree is complete.
          guard Darwin.fchmod(copiedChild.handle.value, entry.st_mode & 0o777) == 0 else {
            throw failure("fchmod private directory \(copiedChild.path)")
          }
        }
      case mode_t(S_IFREG):
        try requireRegular(entry, path: fullPath, device: device)
        var copiedFile: WorkingCopyHandle?
        if let copyTo {
          copiedFile = try makePrivateFile(
            in: copyTo, name: name, source: entry, created: &created)
        }
        let read = try readFile(
          parent: directory.value, name: name, expectedPath: fullPath, device: device,
          buffer: &buffer, copyTo: copiedFile?.value, maximumBytes: budget.fileAllowance)
        tree.files[relativePath] = read.file
        try budget.consumeBytes(read.file.state.size)
        if let copiedFile {
          guard Darwin.fchmod(copiedFile.value, entry.st_mode & 0o777) == 0 else {
            throw failure("fchmod private copy of \(fullPath)")
          }
        }
      default:
        throw WorkingCopyFailure.refused("symlink or special entry in tree: \(fullPath)")
      }
    }
    let after = try metadata(directory.value)
    try requireContentOnlyMetadata(directory.value, metadata: after)
    guard WorkingCopyFileState(before) == WorkingCopyFileState(after),
      try entryNames(directory.value, maximumEntries: initialNames.count) == initialNames
    else {
      throw WorkingCopyFailure.refused("directory changed while scanning: \(path)")
    }
    try verifyPath(directory.value, path)
  }

  /// Creates one private child directory, recording its identity as soon as it is observed.
  /// It must then open as that same empty directory.
  private static func makePrivateDirectory(
    in parent: WorkingCopyCopyTarget, name: String, created: inout Set<WorkingCopyObjectID>
  ) throws -> WorkingCopyCopyTarget {
    let path = childPath(parent.path, name)
    guard Darwin.mkdirat(parent.handle.value, name, 0o700) == 0 else {
      throw failure("mkdirat private directory \(path)")
    }
    guard let made = try metadataAt(parent.handle.value, name),
      made.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), made.st_uid == geteuid(),
      WorkingCopyObjectID(made).device == parent.device
    else {
      throw WorkingCopyFailure.refused("fresh private directory cannot be identified: \(path)")
    }
    let identity = WorkingCopyObjectID(made)
    created.insert(identity)
    let handle = try openDirectory(
      parent.handle.value, name: name, expectedPath: path, device: parent.device)
    let opened = try metadata(handle.value)
    guard WorkingCopyObjectID(opened) == identity,
      try entryNames(handle.value, maximumEntries: 0).isEmpty
    else {
      throw WorkingCopyFailure.refused("fresh private directory was replaced: \(path)")
    }
    try requireContentOnlyMetadata(handle.value, metadata: opened)
    return WorkingCopyCopyTarget(handle: handle, path: path, device: parent.device)
  }

  /// Exclusively creates one private file, recording the created inode before any check.
  private static func makePrivateFile(
    in parent: WorkingCopyCopyTarget, name: String, source: stat,
    created: inout Set<WorkingCopyObjectID>
  ) throws -> WorkingCopyHandle {
    let path = childPath(parent.path, name)
    let raw = Darwin.openat(
      parent.handle.value, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
      mode_t(0o600))
    guard raw >= 0 else { throw failure("create independent private file \(path)") }
    let output = WorkingCopyHandle(raw)
    let made = try metadata(output.value)
    created.insert(WorkingCopyObjectID(made))
    try verifyPath(output.value, path)
    try requireRegular(made, path: path, device: parent.device)
    try requireContentOnlyMetadata(output.value, metadata: made)
    guard WorkingCopyObjectID(made) != WorkingCopyObjectID(source) else {
      throw WorkingCopyFailure.refused("private file is not independent from source: \(path)")
    }
    return output
  }
}
