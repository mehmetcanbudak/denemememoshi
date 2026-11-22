import Chord
import Foundation
import PiCore
import PiEnv
import Synchronization

#if os(macOS)
  /// The confined daemon's descriptor-guarded file service (S4-T3; Pi_Swift slice-2 H3, request
  /// 2026-11-02 consumer handoff). Every file request the daemon serves resolves one component at
  /// a time from a mapped root descriptor, never through a symbolic link and never outside the
  /// roots; content operations refuse special files and multiply-linked regular files; writes go
  /// to a new file in the verified parent and `renameat` into place (D81). The policy hook applies
  /// D103's classifications per operation: a path is secret when the generated Seatbelt profile's
  /// own expressions or host admission's rule names it, so the guard refuses at least what
  /// either refuses. H3 decides only the requested path; the entries a listing, a directory
  /// handle or a watch presents below it get the same secret decision from
  /// ``SandboxListingGuard``.
  enum SandboxGuardedFiles {
    /// The host conveys the working copy root to the daemon in its launch environment, the way
    /// `HOME` already is. A bot controls its own commands' environment, never the daemon's.
    static let workingRootVariable = "MEMOSHI_SANDBOX_WORKING_ROOT"
    /// Trusted read-only toolchain roots as a JSON array of strings, so a root may hold any
    /// character; already canonical (validated by ``RuntimeSandboxHost``).
    static let toolchainRootsVariable = "MEMOSHI_SANDBOX_TOOLCHAIN_ROOTS"

    /// The mapped roots of one daemon life: the private home (with `tmp/` inside it) and the
    /// working copy read-write, toolchain roots read-only.
    static func rootSet(environment: [String: String]) throws -> [GuardedRoot] {
      var roots: [GuardedRoot] = []
      if let home = environment["HOME"], !home.isEmpty {
        roots.append(try GuardedRoot.open(home, access: .readWrite))
      }
      if let workingRoot = environment[workingRootVariable], !workingRoot.isEmpty {
        roots.append(try GuardedRoot.open(workingRoot, access: .readWrite))
      }
      for root in try toolchainRoots(environment) {
        roots.append(try GuardedRoot.open(root, access: .readOnly))
      }
      return roots
    }

    /// The guarded file service the daemon serves its session with.
    static func service(environment: [String: String]) throws -> EnvDaemonFileService {
      let roots = try rootSet(environment: environment)
      return SandboxListingGuard(
        GuardedDaemonFileService(roots: GuardedRootSet(roots), policy: policy), roots: roots)
    }

    /// The toolchain roots the host encoded; a value it did not encode fails the daemon.
    static func toolchainRoots(_ environment: [String: String]) throws -> [String] {
      guard let encoded = environment[toolchainRootsVariable], !encoded.isEmpty else { return [] }
      do {
        return try JSONDecoder().decode([String].self, from: Data(encoded.utf8))
      } catch {
        throw RuntimeEnvironmentError.invalidComposition
      }
    }

    /// The variables that carry the roots above; merged into every daemon launch environment.
    static func rootVariables(workingRoot: String?, toolchainRoots: [String]) -> [String: String] {
      var variables: [String: String] = [:]
      if let workingRoot { variables[workingRootVariable] = workingRoot }
      let encoder = JSONEncoder()
      encoder.outputFormatting = .withoutEscapingSlashes
      // An array of strings always encodes; without it the daemon maps no toolchain root.
      if !toolchainRoots.isEmpty, let encoded = try? encoder.encode(toolchainRoots) {
        variables[toolchainRootsVariable] = String(decoding: encoded, as: UTF8.self)
      }
      return variables
    }

    /// The host's per-access decision (D103): secret-spelled paths are denied for every
    /// operation, host-exec paths for every write-class operation, both root-relative.
    static let policy: @Sendable (GuardedFileAccess) -> GuardedFileDecision = { access in
      if protectsSecret(in: access.relativePath) {
        return .deny("a protected secret spelling (D103)")
      }
      if writesHostExec(access.operation), isHostExecPath(access.relativePath) {
        return .deny("a host-exec path (D103)")
      }
      return .allow
    }

    /// Write-class operations, the ones the profile's `file-write*` deny covers for host-exec
    /// paths.
    static func writesHostExec(_ operation: GuardedFileAccess.Operation) -> Bool {
      switch operation {
      case .write, .createDirectory, .remove, .renameSource, .renameDestination: return true
      case .metadata, .read, .list, .watch: return false
      }
    }

    /// Whether a root-relative path is a protected secret: the profile's expressions match its
    /// bytes, or host admission's rule (scalar components, full case folding, default-ignorable
    /// scalars dropped) names it. A secret-spelled component protects itself and every
    /// descendant; a template leaf (`.env.example` and the other
    /// ``SourceSecretSpellings/templates``) is exempt only as the last component and only in
    /// its exact lowercase spelling, the one both rules exempt.
    static func protectsSecret(in relativePath: String) -> Bool {
      guard !relativePath.isEmpty else { return false }
      return SandboxSecretExpressions.shared.protects("/" + relativePath)
        || SourcePathPolicy.namesSecret(relativePath: relativePath)
    }

    /// The profile's host-exec write rule over ``SandboxProfile/hostExecEntries``: the `.git`
    /// configuration and hooks, the editor directories (which protect everything below them)
    /// and the shell and MCP entry files. Components split on scalars and compare as admission's
    /// do (``SourcePathPolicy/comparedSpelling(_:)``), so this refuses at least what the
    /// profile's case-insensitive expression does.
    static func isHostExecPath(_ relativePath: String) -> Bool {
      let names = relativePath.unicodeScalars.split(separator: "/").map {
        SourcePathPolicy.comparedSpelling(String(Substring($0)))
      }
      return SandboxProfile.hostExecEntries.contains { entry in
        names.indices.contains { start in
          let end = start + entry.names.count
          return end <= names.count && Array(names[start..<end]) == entry.names
            && (entry.below || end == names.count)
        }
      }
    }
  }

  /// The guard's decision for what H3 presents below a request it admitted. H3 decides each
  /// requested path, then lists a directory tree (`listFiles`), pages a directory handle
  /// (`readdir`) and reports a watch's changes without a decision for their entries. This
  /// service gives each such entry ``SandboxGuardedFiles/protectsSecret(in:)`` by its
  /// root-relative path and leaves a protected one out, as a refused `lstat` of it would be. A
  /// secret-spelled directory protects every entry below it, so a tree listing and a recursive
  /// watch leave its contents out too. Ignore files below a listed directory are still read
  /// without a decision; they only choose which of the entries below them are listed. Every
  /// other request passes through unchanged.
  final class SandboxListingGuard: EnvDaemonFileService {
    private let files: any EnvDaemonFileService
    private let roots: [GuardedRoot]
    /// The root-relative path of each open directory handle, for the entries it pages.
    private let directories = Mutex<[Int: String]>([:])

    init(_ files: any EnvDaemonFileService, roots: [GuardedRoot]) {
      self.files = files
      self.roots = roots
    }

    func dispatch(_ request: JSONObject, payload: Data, context: Context) throws -> (
      JSONObject, Data
    ) {
      var (reply, data) = try files.dispatch(request, payload: payload, context: context)
      let listed = request["path"]?.stringValue.flatMap { Self.relativePath($0, in: roots) }
      switch request["op"]?.stringValue {
      case "listFiles":
        guard let listed else { break }
        // Each entry is a kind byte, its path relative to the listed directory, and a NUL.
        var kept = Data()
        var count = 0
        var start = data.startIndex
        while start < data.endIndex, let end = data[(start + 1)...].firstIndex(of: 0) {
          let entry = String(decoding: data[(start + 1)..<end], as: UTF8.self)
          if !SandboxGuardedFiles.protectsSecret(in: Self.join(listed, entry)) {
            kept.append(data[start...end])
            count += 1
          }
          start = end + 1
        }
        data = kept
        reply["count"] = .number(Double(count))
      case "opendir":
        guard let listed, let handle = reply["handle"]?.intValue else { break }
        directories.withLock { $0[handle] = listed }
      case "readdir":
        guard let handle = request["handle"]?.intValue,
          let listed = directories.withLock({ $0[handle] }),
          let entries = reply["entries"]?.arrayValue
        else { break }
        reply["entries"] = .array(
          entries.filter { entry in
            !SandboxGuardedFiles.protectsSecret(in: Self.join(listed, Self.name(of: entry)))
          })
      case "close":
        guard let handle = request["handle"]?.intValue else { break }
        _ = directories.withLock { $0.removeValue(forKey: handle) }
      default:
        break
      }
      return (reply, data)
    }

    func watch(
      _ targets: [WatchTarget], options: LocalWatchOptions,
      onChange: @escaping @Sendable (WatchChange) -> Void
    ) async throws -> any FileWatcher {
      let roots = roots
      return try await files.watch(targets, options: options) { change in
        guard case .paths(let paths) = change else { return onChange(change) }
        let shown = paths.filter { path in
          guard let relative = Self.relativePath(path, in: roots) else { return true }
          return !SandboxGuardedFiles.protectsSecret(in: relative)
        }
        if !shown.isEmpty { onChange(.paths(shown)) }
      }
    }

    func closeAll() {
      directories.withLock { $0.removeAll() }
      files.closeAll()
    }

    /// The root-relative path H3 resolves `path` to: made absolute against the daemon's working
    /// directory, `.` and `..` resolved lexically, below the root whose own or canonical path
    /// is the longest prefix, compared by bytes. Nil outside every root, which H3 refuses.
    static func relativePath(_ path: String, in roots: [GuardedRoot]) -> String? {
      let absolute =
        path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
      let components = lexical(absolute)
      var best: Int?
      for root in roots {
        for prefix in [lexical(root.path), lexical(root.canonicalPath)]
        where prefix.count > (best ?? -1) && components.starts(with: prefix) {
          best = prefix.count
        }
      }
      guard let best else { return nil }
      return components[best...].map { String(decoding: $0, as: UTF8.self) }
        .joined(separator: "/")
    }

    private static func lexical(_ path: String) -> [ArraySlice<UInt8>] {
      var components: [ArraySlice<UInt8>] = []
      for component in Array(path.utf8).split(separator: 0x2F) {
        if component.elementsEqual([0x2E]) { continue }
        if component.elementsEqual([0x2E, 0x2E]) {
          _ = components.popLast()
          continue
        }
        components.append(component)
      }
      return components
    }

    private static func join(_ directory: String, _ entry: String) -> String {
      directory.isEmpty ? entry : directory + "/" + entry
    }

    /// An entry's raw name when it is not UTF-8, decoded as H3 decodes it, else its name.
    private static func name(of entry: JSONValue) -> String {
      if let raw = entry["raw"]?.arrayValue {
        return String(
          decoding: raw.compactMap { $0.intValue.flatMap(UInt8.init(exactly:)) }, as: UTF8.self)
      }
      return entry["name"]?.stringValue ?? ""
    }
  }

  /// A Pi-type-free view of the guarded file operations, for the runtime tests: in process, the
  /// same mapped roots and policy the daemon serves, resolved through the same descriptor guard;
  /// or a live environment, such as the confined daemon's wire path. An outcome mirrors the
  /// wire code a daemon client sees; `failed` covers every other code.
  struct SandboxGuardedFileProbe: Sendable {
    enum Outcome: Equatable, Sendable { case ok, denied, invalid, failed }

    private let environment: any ExecutionEnv

    init(cwd: String, home: String, workingRoot: String? = nil, toolchainRoots: [String] = [])
      throws
    {
      var variables = ["HOME": home]
      variables.merge(
        SandboxGuardedFiles.rootVariables(workingRoot: workingRoot, toolchainRoots: toolchainRoots)
      ) {
        _, new in new
      }
      environment = MappedExecutionEnv(
        cwd: cwd, roots: GuardedRootSet(try SandboxGuardedFiles.rootSet(environment: variables)),
        policy: SandboxGuardedFiles.policy)
    }

    init(live environment: any ExecutionEnv) { self.environment = environment }

    func writeFile(_ path: String, _ content: String) async -> Outcome {
      outcome(await environment.writeFile(path, .text(content), context: .background))
    }

    func readFile(_ path: String) async -> Outcome {
      outcome(await environment.readTextFile(path, context: .background))
    }

    func remove(_ path: String) async -> Outcome {
      outcome(await environment.remove(path, options: nil, context: .background))
    }

    func fileInfo(_ path: String) async -> Outcome {
      outcome(await environment.fileInfo(path, context: .background))
    }

    private func outcome<T>(_ result: Result<T, FileError>) -> Outcome {
      guard case .failure(let error) = result else { return .ok }
      switch error.code {
      case .permissionDenied: return .denied
      case .invalid: return .invalid
      default: return .failed
      }
    }
  }

  /// A Pi-type-free view of the listings the daemon's file service presents, for the runtime
  /// tests: in process, the service ``RuntimeSandboxDaemon/serve()`` serves, through its wire
  /// requests; or a live environment, such as the confined daemon's. `listFiles` returns paths
  /// relative to the listed directory, `listDirectory` names, and `watch` the paths a watcher
  /// reports.
  struct SandboxDaemonFileProbe: Sendable {
    private enum Backing: Sendable {
      case service(any EnvDaemonFileService)
      case live(any ExecutionEnv)
    }

    private let backing: Backing

    init(environment: [String: String]) throws {
      backing = .service(try SandboxGuardedFiles.service(environment: environment))
    }

    init(live environment: any ExecutionEnv) { backing = .live(environment) }

    func listFiles(_ path: String) async throws -> [String] {
      switch backing {
      case .service(let service):
        let (reply, payload) = try service.dispatch(
          ["op": "listFiles", "path": .string(path)], payload: Data(), context: .background)
        var entries: [String] = []
        var start = payload.startIndex
        while start < payload.endIndex, let end = payload[(start + 1)...].firstIndex(of: 0) {
          entries.append(String(decoding: payload[(start + 1)..<end], as: UTF8.self))
          start = end + 1
        }
        guard reply["count"]?.intValue == entries.count else {
          throw RuntimeEnvironmentError.commandFailed
        }
        return entries
      case .live(let environment):
        guard
          case .success(let listing) = await environment.listFiles(
            path, options: nil, context: .background)
        else { throw RuntimeEnvironmentError.commandFailed }
        return listing.entries.map(\.path)
      }
    }

    func listDirectory(_ path: String) async throws -> [String] {
      switch backing {
      case .service(let service):
        let (opened, _) = try service.dispatch(
          ["op": "opendir", "path": .string(path)], payload: Data(), context: .background)
        guard let handle = opened["handle"] else { throw RuntimeEnvironmentError.commandFailed }
        defer {
          _ = try? service.dispatch(
            ["op": "close", "handle": handle], payload: Data(), context: .background)
        }
        var names: [String] = []
        while true {
          // Two entries a page, so a filtered page can come back short or empty.
          let (reply, _) = try service.dispatch(
            ["op": "readdir", "handle": handle, "max": 2], payload: Data(),
            context: .background)
          names += reply["entries"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
          if reply["done"]?.boolValue == true { break }
        }
        return names.sorted()
      case .live(let environment):
        guard case .success(let entries) = await environment.listDir(path, context: .background)
        else { throw RuntimeEnvironmentError.commandFailed }
        return entries.map(\.name).sorted()
      }
    }

    /// Every path a recursive watch of `path` reports while `body` runs and until a reported
    /// path ends with `marker`, or ten seconds pass.
    func watch(
      _ path: String, until marker: String, during body: () async throws -> Void
    ) async throws -> [String] {
      let seen = Mutex<[String]>([])
      let onChange: @Sendable (WatchChange) -> Void = { change in
        if case .paths(let paths) = change { seen.withLock { $0 += paths } }
      }
      let target = WatchTarget(path: path, recursive: true)
      let watcher: any FileWatcher
      switch backing {
      case .service(let service):
        watcher = try await service.watch(
          [target], options: LocalWatchOptions(), onChange: onChange)
      case .live(let environment):
        guard
          case .success(let opened) = await environment.watch(
            [target], onChange: onChange, context: .background)
        else { throw RuntimeEnvironmentError.commandFailed }
        watcher = opened
      }
      do {
        try await body()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !seen.withLock({ $0.contains { $0.hasSuffix(marker) } }),
          ContinuousClock.now < deadline
        {
          try await Task.sleep(for: .milliseconds(20))
        }
      } catch {
        await watcher.close(context: .background)
        throw error
      }
      await watcher.close(context: .background)
      return seen.withLock { $0 }
    }
  }
#endif
