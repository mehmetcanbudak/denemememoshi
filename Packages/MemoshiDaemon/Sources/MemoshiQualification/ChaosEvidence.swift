import Darwin
import Foundation

struct ChaosDirectory: Sendable {
  let url: URL
  private let device: dev_t
  private let inode: ino_t

  static func inspect(_ url: URL) throws -> ChaosDirectory? {
    var path = url.path
    while path.count > 1, path.last == "/" { path.removeLast() }
    var information = stat()
    if lstat(path, &information) != 0 {
      guard errno == ENOENT else {
        throw DriverError.invalid("Cannot inspect \(url.path) (errno \(errno))")
      }
      return nil
    }
    guard information.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
      throw DriverError.invalid("Not a directory or final-component alias: \(url.path)")
    }
    return ChaosDirectory(url: url, device: information.st_dev, inode: information.st_ino)
  }

  static func create(_ url: URL) throws -> ChaosDirectory {
    try QualificationPaths.create(url)
    guard let directory = try inspect(url) else {
      throw DriverError.invalid("Created directory disappeared: \(url.path)")
    }
    return directory
  }

  func requireCurrent() throws {
    guard let current = try Self.inspect(url), current.device == device, current.inode == inode
    else {
      throw DriverError.invalid("Directory ownership changed: \(url.path)")
    }
  }

  func remove() throws {
    try requireCurrent()
    try FileManager.default.removeItem(at: url)
  }

  func removeIfEmpty() {
    guard (try? requireCurrent()) != nil,
      let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path),
      contents.isEmpty
    else { return }
    _ = rmdir(url.path)
  }
}

enum ChaosLogRetention: Sendable {
  case clean([URL])
  case withheld
}

struct ChaosEvidence: Sendable {
  let work: ChaosDirectory
  let output: ChaosDirectory
  private let outputRuns: ChaosDirectory
  private let scratch: [ChaosDirectory]
  private let createdWork: Bool

  var logs: URL { work.url.appendingPathComponent("logs", isDirectory: true) }
  var ledger: URL { work.url.appendingPathComponent("ledger", isDirectory: true) }
  var runs: URL { work.url.appendingPathComponent("runs", isDirectory: true) }
  var journal: URL { ledger.appendingPathComponent(EffectLedgerProcess.journalFileName) }

  static func prepare(work requestedWork: URL, output requestedOutput: URL) throws -> ChaosEvidence
  {
    let manager = FileManager.default
    // Resolves the deepest existing ancestor with `realpath`, so overlap and protected-root
    // checks compare real locations. `resolvingSymlinksInPath` is not used: it strips
    // `/private`, turning `/private/tmp` back into the `/tmp` symlink.
    func resolve(_ path: URL) throws -> (ancestor: URL, resolved: URL) {
      var ancestor = path
      var suffix: [String] = []
      while true {
        var information = stat()
        if lstat(ancestor.path, &information) == 0 { break }
        guard errno == ENOENT else {
          throw DriverError.invalid("Cannot inspect evidence ancestor (errno \(errno))")
        }
        suffix.append(ancestor.lastPathComponent)
        ancestor.deleteLastPathComponent()
      }
      guard let real = realpath(ancestor.path, nil) else {
        throw DriverError.invalid("Cannot resolve evidence ancestor (errno \(errno))")
      }
      defer { free(real) }
      let resolvedAncestor = URL(fileURLWithPath: String(cString: real), isDirectory: true)
      let resolved = suffix.reversed().reduce(resolvedAncestor) {
        $0.appendingPathComponent($1, isDirectory: true)
      }
      return (resolvedAncestor, resolved)
    }
    func canonical(_ requested: URL) throws -> URL {
      guard requested.isFileURL, requested.path.hasPrefix("/") else {
        throw DriverError.invalid("Expected an absolute file path")
      }
      let standardized = requested.standardizedFileURL
      _ = try ChaosDirectory.inspect(standardized)
      let parent = try resolve(standardized.deletingLastPathComponent())
      guard try ChaosDirectory.inspect(parent.ancestor) != nil else {
        throw DriverError.invalid("Evidence ancestor is not a directory")
      }
      return parent.resolved.appendingPathComponent(
        standardized.lastPathComponent, isDirectory: true)
    }
    func key(_ url: URL) -> String {
      url.path.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
    func contains(_ parent: String, _ child: String) -> Bool {
      child == parent || child.hasPrefix(parent == "/" ? "/" : parent + "/")
    }
    let workURL = try canonical(requestedWork)
    let outputURL = try canonical(requestedOutput)
    let existingWork = try ChaosDirectory.inspect(workURL)
    guard try ChaosDirectory.inspect(outputURL) == nil else {
      throw DriverError.invalid("Output already exists: \(outputURL.path)")
    }
    let workKey = key(workURL)
    let outputKey = key(outputURL)
    guard !contains(outputKey, workKey),
      !contains(workKey, outputKey)
        || outputURL.path == workURL.appendingPathComponent("report").path
    else { throw DriverError.invalid("Work and output roots overlap unsafely") }
    let home = manager.homeDirectoryForCurrentUser
    let protected = try [
      home.appendingPathComponent("Library/Application Support/Memoshi"),
      home.appendingPathComponent("Library/Application Support/Memoshi Development"),
      home.appendingPathComponent("Documents/Memoshi-Plan"),
      URL(fileURLWithPath: "/private/tmp/memoshi-native-review"),
    ].map { try key(resolve($0.standardizedFileURL).resolved) }
    for candidate in [workKey, outputKey] {
      for root in protected where contains(root, candidate) || contains(candidate, root) {
        throw DriverError.invalid("Evidence root overlaps protected \(root)")
      }
    }
    if let existingWork {
      try existingWork.requireCurrent()
      guard try manager.contentsOfDirectory(atPath: workURL.path).isEmpty else {
        throw DriverError.invalid("Work directory is not empty: \(workURL.path)")
      }
    }
    var created: [ChaosDirectory] = []
    func createTree(_ url: URL) throws -> ChaosDirectory {
      if let directory = try ChaosDirectory.inspect(url) { return directory }
      _ = try createTree(url.deletingLastPathComponent())
      let directory = try ChaosDirectory.create(url)
      created.append(directory)
      return directory
    }
    do {
      let work: ChaosDirectory
      if let existingWork {
        work = existingWork
      } else {
        _ = try createTree(workURL.deletingLastPathComponent())
        work = try ChaosDirectory.create(workURL)
        created.append(work)
      }
      _ = try createTree(outputURL.deletingLastPathComponent())
      let output = try ChaosDirectory.create(outputURL)
      created.append(output)
      var scratch: [ChaosDirectory] = []
      for name in ["ledger", "logs", "tmp", "ledger-home", "runs"] {
        try work.requireCurrent()
        let directory = try ChaosDirectory.create(workURL.appendingPathComponent(name))
        scratch.append(directory)
        created.append(directory)
      }
      let outputRuns = try ChaosDirectory.create(outputURL.appendingPathComponent("runs"))
      created.append(outputRuns)
      try work.requireCurrent()
      try output.requireCurrent()
      return ChaosEvidence(
        work: work, output: output, outputRuns: outputRuns, scratch: scratch,
        createdWork: existingWork == nil)
    } catch {
      for directory in created.reversed() { directory.removeIfEmpty() }
      throw error
    }
  }

  func write(_ value: some Encodable, named name: String) throws {
    try write(JSONLines.prettyEncoder.encode(value), named: name)
  }

  func write(_ bytes: Data, named name: String) throws {
    try withFile(named: name) { try $0.write(contentsOf: bytes) }
  }

  func writeResults(_ results: [RunResult]) throws {
    try withFile(named: "results.jsonl") { handle in
      for result in results {
        var line = try JSONLines.encoder.encode(result)
        line.append(UInt8(ascii: "\n"))
        try handle.write(contentsOf: line)
      }
    }
  }

  private func withFile(named name: String, write: (FileHandle) throws -> Void) throws {
    try output.requireCurrent()
    let destination = output.url.appendingPathComponent(name)
    let descriptor = open(
      destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      throw DriverError.invalid("Cannot exclusively create \(name) (errno \(errno))")
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do {
      try write(handle)
      try handle.close()
    } catch {
      try? handle.close()
      throw error
    }
  }

  func logFiles(in directory: URL) throws -> [URL] {
    guard let directory = try ChaosDirectory.inspect(directory) else {
      throw DriverError.invalid("Missing log directory")
    }
    try directory.requireCurrent()
    return try FileManager.default.contentsOfDirectory(
      at: directory.url, includingPropertiesForKeys: nil
    )
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  func retainRunLogs(_ retention: ChaosLogRetention, run: String) -> [String] {
    guard case .clean(let files) = retention else { return [] }
    let destination: ChaosDirectory
    do {
      try output.requireCurrent()
      try outputRuns.requireCurrent()
      destination = try ChaosDirectory.create(outputRuns.url.appendingPathComponent(run))
    } catch { return ["run log retention: \(error)"] }
    var failures: [String] = []
    for file in files {
      do {
        try output.requireCurrent()
        try outputRuns.requireCurrent()
        try destination.requireCurrent()
        try copy(file, to: destination.url.appendingPathComponent(file.lastPathComponent))
      } catch { failures.append("log retention \(file.lastPathComponent): \(error)") }
    }
    return failures
  }

  func retainLedger(canaries: [Canary]) -> [String] {
    var failures: [String] = []
    do { try work.requireCurrent() } catch { return ["ledger retention: \(error)"] }
    do {
      let scan = try scan([journal], canaries: canaries)
      guard scan.hits.isEmpty else { throw DriverError.invalid("Ledger journal has canary hits") }
      try copy(journal, to: output.url.appendingPathComponent("ledger-effects.jsonl"))
    } catch { failures.append("ledger journal retention: \(error)") }
    do {
      for file in try logFiles(in: logs) {
        do {
          let scan = try scan([file], canaries: canaries)
          guard scan.hits.isEmpty else { throw DriverError.invalid("Ledger log has canary hits") }
          try copy(file, to: output.url.appendingPathComponent(file.lastPathComponent))
        } catch { failures.append("ledger log retention \(file.lastPathComponent): \(error)") }
      }
    } catch { failures.append("ledger log enumeration: \(error)") }
    return failures
  }

  private func copy(_ source: URL, to destination: URL) throws {
    try work.requireCurrent()
    try output.requireCurrent()
    var information = stat()
    guard lstat(source.path, &information) == 0,
      information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    else {
      throw DriverError.invalid(
        "Required log or journal is not a regular file: \(source.lastPathComponent)")
    }
    try FileManager.default.copyItem(at: source, to: destination)
  }

  func scan(_ roots: [URL], canaries: [Canary], excluding: Set<String> = []) throws
    -> CanaryScanReport
  {
    try output.requireCurrent()
    let scanner = try CanaryScanner(canaries: canaries)
    let excluded = Set(excluding.map { CanaryScanner.canonical(URL(fileURLWithPath: $0)) })
    var report = CanaryScanReport()
    func visit(_ file: URL, relative: String) throws {
      var information = stat()
      guard lstat(file.path, &information) == 0 else {
        throw DriverError.invalid("Cannot inspect scan input \(relative) (errno \(errno))")
      }
      var name = CanaryScanReport()
      scanner.scanBytes(Data(relative.utf8), path: relative, into: &name)
      for hit in name.hits {
        report.hits.append(
          CanaryHit(
            canary: hit.canary, fingerprint: hit.fingerprint, encoding: hit.encoding,
            path: hit.path, offset: -1))
      }
      switch information.st_mode & mode_t(S_IFMT) {
      case mode_t(S_IFDIR):
        let children = try FileManager.default.contentsOfDirectory(
          at: file, includingPropertiesForKeys: nil)
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
          try visit(child, relative: relative + "/" + child.lastPathComponent)
        }
      case mode_t(S_IFREG):
        if excluded.contains(CanaryScanner.canonical(file)) {
          report.excluded.append(relative)
        } else {
          let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
          report.filesScanned += 1
          report.bytesScanned += bytes.count
          scanner.scanBytes(bytes, path: relative, into: &report)
        }
      default:
        report.skipped.append(relative)
      }
    }
    for (index, root) in roots.enumerated() { try visit(root, relative: "\(index):") }
    return report
  }

  func removeRun(_ directory: ChaosDirectory) throws {
    try work.requireCurrent()
    try directory.remove()
  }

  func cleanUp(keepRuns: Bool) -> (complete: Bool, failures: [String]) {
    var failures: [String] = []
    do { try work.requireCurrent() } catch { return (false, ["work cleanup: \(error)"]) }
    for directory in scratch where !keepRuns || directory.url.lastPathComponent != "runs" {
      do {
        try work.requireCurrent()
        if directory.url.lastPathComponent == "runs" {
          try directory.requireCurrent()
          guard try FileManager.default.contentsOfDirectory(atPath: directory.url.path).isEmpty
          else {
            throw DriverError.invalid("Unremoved run directories remain")
          }
        }
        try directory.remove()
      } catch { failures.append("work cleanup \(directory.url.lastPathComponent): \(error)") }
    }
    do {
      try work.requireCurrent()
      var kept: Set<String> = keepRuns ? ["runs"] : []
      if output.url.deletingLastPathComponent() == work.url { kept.insert("report") }
      let remaining = try FileManager.default.contentsOfDirectory(atPath: work.url.path)
      guard remaining.allSatisfy({ kept.contains($0) }) else {
        throw DriverError.invalid("Unexpected work directory contents remain")
      }
      if createdWork, kept.isEmpty { try work.remove() }
    } catch { failures.append("work cleanup: \(error)") }
    return (failures.isEmpty, failures)
  }
}
