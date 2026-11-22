import Foundation

/// An original-source path class (policy.md §3.5.2).
///
/// A class describes the user's original folder namespace. A private working copy or staging
/// location never lowers it (D96), and source data is never classified as the bot's home.
public enum SourcePathClass: String, Hashable, Codable, Sendable {
  /// Ordinary granted source data.
  case project
  /// Credential material; a raw read reveals a secret and a write is a credential action.
  case secret
  /// A file that can make the host run code outside the sandbox.
  case hostExec = "host_exec"
  /// Repository data inside `.git` other than its `host_exec` configuration and hooks.
  case gitInternal = "git_internal"
  /// An agent instruction or skill file.
  case instruction
  /// Continuous-integration configuration; a write carries `sensitive_path`.
  case ciConfig = "ci_config"
  /// An operating-system or personal configuration path; never grantable.
  case system
  /// Memoshi's own state, app bundle or Pi stores; never grantable.
  case memoshiState = "memoshi_state"
}

/// A refused source path or grant root. Neither case ever authorizes anything.
public enum SourcePathPolicyError: Error, Equatable, Sendable {
  /// The path or the trusted context is not strict canonical syntax.
  case invalidPath
  /// The root can never be a folder grant or bound a classified source namespace.
  case notGrantable
}

/// Trusted host configuration, never values from a tool, the model or the process environment.
public struct SourcePathPolicyContext: Sendable {
  /// The user's canonical home folder.
  public let userHome: String
  /// Canonical Memoshi state, app bundle and Pi store roots.
  public let protectedStateRoots: [String]
  /// Canonical absolute targets of trusted `core.hooksPath` settings.
  public let hostExecRoots: [String]

  /// Every value must be a strict canonical absolute path; otherwise every decision refuses.
  public init(userHome: String, protectedStateRoots: [String], hostExecRoots: [String] = []) {
    self.userHome = userHome
    self.protectedStateRoots = protectedStateRoots
    self.hostExecRoots = hostExecRoots
  }
}

/// Pure lexical policy for original source paths (policy.md §3.5).
///
/// Physical root identity, bookmarks, no-follow traversal and staging stay with trusted host
/// code: this type performs no I/O and never reads the process environment, so callers pass
/// realpath-canonical paths. Components compare after NFC normalization and full case folding,
/// and protected names also match when default-ignorable scalars are dropped, so an equivalent
/// spelling cannot dodge a class. Patterns match anywhere in the complete original path, root
/// ancestors included, so a nested grant such as `<repo>/.git` or `<repo>/.github` keeps the
/// structure above it. A matching directory protects everything beneath it.
public enum SourcePathPolicy {
  /// Classifies one target below an original source root, never a private staging location.
  ///
  /// The strongest applicable class wins: `memoshi_state`, `system`, `secret`, `host_exec`,
  /// `git_internal`, `instruction`, `ci_config`, then `project`. Inside `.git`, git's own data
  /// outranks name-based instruction and CI patterns, and every `config`, `config.worktree` or
  /// `hooks` entry below `.git`, submodule and worktree git directories included, is `host_exec`.
  /// - Throws: `invalidPath` for non-canonical syntax or context; `notGrantable` for a root that
  ///   is `/`, the home folder or one of its ancestors, whose contents no class could bound.
  public static func classify(
    sourceRoot: String, relativePath: String, context: SourcePathPolicyContext
  ) throws -> SourcePathClass {
    let scope = try SourceScope(context)
    let root = try SourceSyntax.absolute(sourceRoot)
    let target = try SourceSyntax.relative(relativePath)
    guard !scope.containsHome(root) else { throw SourcePathPolicyError.notGrantable }
    return scope.classify(root + target)
  }

  /// Validates a folder-grant root against the normative never-grantable roots.
  ///
  /// - Returns: Whether the root is a whole Desktop, Documents, Downloads, Pictures, Movies,
  ///   Music or Public folder, which needs typed confirmation.
  /// - Throws: `invalidPath` for non-canonical syntax or context; `notGrantable` for `/`, the
  ///   home folder or one of its ancestors, anything under `~/Library`, or another `system` or
  ///   `memoshi_state` path. Physical identity and no-follow checks remain the host's.
  public static func validateGrantRoot(
    _ path: String, context: SourcePathPolicyContext
  ) throws -> Bool {
    let scope = try SourceScope(context)
    let root = try SourceSyntax.absolute(path)
    guard !scope.containsHome(root) else { throw SourcePathPolicyError.notGrantable }
    switch scope.classify(root) {
    case .system, .memoshiState: throw SourcePathPolicyError.notGrantable
    default: return scope.needsConfirmation(root)
    }
  }
}

extension SourcePathPolicy {
  /// Host admission's `secret` rule (§3.5.2) over a path below some root, for the confined
  /// daemon's guard, which decides each access to a name a confined process may have created
  /// itself rather than admitting one: components split on scalars, compared exactly as
  /// ``classify(sourceRoot:relativePath:context:)`` compares them, with only an exact template
  /// spelling exempt. No syntax is refused; every nonempty component is judged by its spelling.
  static func namesSecret(relativePath: String) -> Bool {
    let path = SourceSyntax.spellings(relativePath)
    return path.indices.contains { SourceScope.isSecret(path, at: $0) }
  }

  /// The spelling admission compares a component by: NFC with full case folding, then
  /// default-ignorable scalars dropped.
  static func comparedSpelling(_ component: String) -> String {
    SourceComponent(spelling: component).loose
  }
}

/// One validated component: `exact` is NFC with full case folding, and `loose` also drops
/// default-ignorable scalars, which some case-insensitive volumes ignore when comparing names.
private struct SourceComponent {
  let exact: String
  let loose: String

  init(_ raw: String) throws {
    let forbidden = raw.unicodeScalars.contains {
      $0 == "\\" || $0 == ":" || $0.properties.generalCategory == .control
    }
    guard !forbidden else { throw SourcePathPolicyError.invalidPath }
    self.init(spelling: raw)
    // `~` is never expanded; dot entries and named forks are refused, never resolved.
    guard !loose.isEmpty, loose != ".", loose != "..", loose != "..namedfork",
      loose.unicodeScalars.first != "~"
    else { throw SourcePathPolicyError.invalidPath }
  }

  /// Only the folded spellings, without the syntax checks.
  init(spelling raw: String) {
    exact = Self.fold(raw)
    var kept = String.UnicodeScalarView()
    kept.append(
      contentsOf: exact.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint })
    loose = String(kept).precomposedStringWithCanonicalMapping
  }

  /// Locale-free full case folding: lowering first maps capital sharp s, then the round trip
  /// folds sharp and long s, ligatures and final sigma onto one spelling.
  static func fold(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping.lowercased().uppercased().lowercased()
      .precomposedStringWithCanonicalMapping
  }
}

/// Strict slash-separated syntax, split on scalars so a combining mark cannot hide a separator.
private enum SourceSyntax {
  static func absolute(_ text: String) throws -> [SourceComponent] {
    let scalars = text.unicodeScalars
    guard scalars.first == "/" else { throw SourcePathPolicyError.invalidPath }
    let rest = scalars.dropFirst()
    return try rest.isEmpty ? [] : components(rest)
  }

  static func relative(_ text: String) throws -> [SourceComponent] {
    let scalars = text.unicodeScalars
    guard let first = scalars.first, first != "/" else { throw SourcePathPolicyError.invalidPath }
    return try components(scalars[...])
  }

  /// Every nonempty component's spellings, split on scalars; nothing is refused.
  static func spellings(_ text: String) -> [SourceComponent] {
    text.unicodeScalars.split(separator: "/").map {
      SourceComponent(spelling: String(Substring($0)))
    }
  }

  private static func components(
    _ scalars: Substring.UnicodeScalarView
  ) throws -> [SourceComponent] {
    try scalars.split(separator: "/", omittingEmptySubsequences: false).map {
      try SourceComponent(String(Substring($0)))
    }
  }
}

/// The trusted context resolved into folded names, plus the normative §3.5.2 patterns.
private struct SourceScope {
  let home: [String]
  let stateRoots: [[String]]
  let hookRoots: [[String]]
  let systemRoots: [[String]]
  let personalFolders: [[String]]

  init(_ context: SourcePathPolicyContext) throws {
    let home = try Self.names(absolute: context.userHome)
    guard !home.isEmpty else { throw SourcePathPolicyError.invalidPath }
    self.home = home
    stateRoots = try context.protectedStateRoots.map { try Self.names(absolute: $0) }
    hookRoots = try context.hostExecRoots.map { try Self.names(absolute: $0) }
    systemRoots =
      try Self.absoluteSystem.map { try Self.names(absolute: $0) }
      + Self.homeSystem.map { try home + Self.names(relative: $0) }
    personalFolders = try Self.personal.map { try home + Self.names(relative: $0) }
  }

  /// `/`, the home folder and its ancestors hold personal data that no class bounds.
  func containsHome(_ root: [SourceComponent]) -> Bool {
    home.starts(with: root.map(\.loose))
  }

  func needsConfirmation(_ root: [SourceComponent]) -> Bool {
    personalFolders.contains(root.map(\.loose))
  }

  func classify(_ path: [SourceComponent]) -> SourcePathClass {
    let names = path.map(\.loose)
    func under(_ roots: [[String]]) -> Bool { roots.contains { names.starts(with: $0) } }
    if under(stateRoots) { return .memoshiState }
    if under(systemRoots) { return .system }
    if path.indices.contains(where: { Self.isSecret(path, at: $0) }) { return .secret }
    if under(hookRoots) || Self.isHostExec(names) { return .hostExec }
    if names.contains(".git") { return .gitInternal }
    if Self.isInstruction(names) { return .instruction }
    if Self.isContinuousIntegration(names) { return .ciConfig }
    return .project
  }

  /// policy.md §3.5.2 `system` roots; `/etc` names the same directory as `/private/etc`.
  static let absoluteSystem = [
    "/System", "/usr", "/bin", "/sbin", "/Library", "/private/etc", "/etc", "/dev",
  ]
  /// Home-relative `system` paths; `Library` covers every `~/Library` location.
  static let homeSystem = [
    "Library", ".ssh", ".gnupg", ".aws", ".config/gcloud", ".config/gh", ".azure", ".kube",
    ".docker", ".zshrc", ".bashrc", ".profile", ".gitconfig",
  ]
  /// Whole personal folders whose grant needs typed confirmation.
  static let personal = [
    "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public",
  ]
  static let secretNames = folded(SourceSecretSpellings.names)
  static let secretTemplates = folded(SourceSecretSpellings.templates)
  static let secretPrefixes = SourceSecretSpellings.prefixes
  static let secretSuffixes = SourceSecretSpellings.suffixes
  static let hostExecNames = folded([".gitmodules", ".envrc", ".husky", ".devcontainer"])
  static let editorFiles = folded(["tasks.json", "settings.json", "launch.json"])
  /// Git configuration and hook entries in any git directory below `.git`.
  static let gitExecNames = folded(["config", "config.worktree", "hooks"])
  static let instructionNames = folded([
    "AGENTS.md", "CLAUDE.md", "GEMINI.md", ".cursorrules", ".windsurfrules", ".clinerules",
    "SKILL.md", ".memoshi", "bot.md",
  ])
  static let ciNames = folded([
    ".gitlab-ci.yml", "Jenkinsfile", "azure-pipelines.yml", "bitbucket-pipelines.yml",
    ".travis.yml", ".circleci", ".buildkite",
  ])

  static func isSecret(_ path: [SourceComponent], at index: Int) -> Bool {
    let name = path[index].loose
    if secretNames.contains(name) || secretPrefixes.contains(where: { has(name, prefix: $0) })
      || secretSuffixes.contains(where: { has(name, suffix: $0) })
    {
      return true
    }
    // Only an exact template spelling is exempt; an ignorable scalar makes another `.env.*` file.
    if has(name, prefix: SourceSecretSpellings.templatedPrefix) {
      return !secretTemplates.contains(path[index].exact)
    }
    for affix in SourceSecretSpellings.affixes
    where has(name, prefix: affix.prefix) && has(name, suffix: affix.suffix)
      && name.unicodeScalars.count
        >= affix.prefix.unicodeScalars.count + affix.suffix.unicodeScalars.count
    {
      return true
    }
    let parent = index > 0 ? path[index - 1].loose : nil
    return SourceSecretSpellings.children.contains { parent == $0.parent && name == $0.name }
      || SourceSecretSpellings.childPrefixes.contains {
        parent == $0.parent && has(name, prefix: $0.prefix)
      }
  }

  static func isHostExec(_ names: [String]) -> Bool {
    names.indices.contains { index in
      let name = names[index]
      if hostExecNames.contains(name) { return true }
      if name == ".vscode", let next = component(after: index, in: names) {
        return editorFiles.contains(next)
      }
      return name == ".git" && names[(index + 1)...].contains { gitExecNames.contains($0) }
    }
  }

  static func isInstruction(_ names: [String]) -> Bool {
    names.indices.contains { index in
      let next = component(after: index, in: names)
      return instructionNames.contains(names[index])
        || (names[index] == ".cursor" && next == "rules")
        || (names[index] == ".github" && next == "copilot-instructions.md")
    }
  }

  static func isContinuousIntegration(_ names: [String]) -> Bool {
    names.indices.contains { index in
      ciNames.contains(names[index])
        || (names[index] == ".github" && component(after: index, in: names) == "workflows")
    }
  }

  static func component(after index: Int, in names: [String]) -> String? {
    names.indices.contains(index + 1) ? names[index + 1] : nil
  }

  /// Scalar-wise, so a combining mark after a protected prefix cannot hide it.
  static func has(_ name: String, prefix: String) -> Bool {
    name.unicodeScalars.starts(with: prefix.unicodeScalars)
  }

  static func has(_ name: String, suffix: String) -> Bool {
    name.unicodeScalars.reversed().starts(with: suffix.unicodeScalars.reversed())
  }

  private static func folded(_ values: [String]) -> Set<String> {
    Set(values.map(SourceComponent.fold))
  }

  private static func names(absolute text: String) throws -> [String] {
    try SourceSyntax.absolute(text).map(\.loose)
  }

  private static func names(relative text: String) throws -> [String] {
    try SourceSyntax.relative(text).map(\.loose)
  }
}

/// policy.md §3.5.2 `secret` spellings: the one source for host admission and for the generated
/// Seatbelt profile, so the two cannot drift. Every spelling is lowercase ASCII; both consumers
/// match case-insensitively.
enum SourceSecretSpellings {
  static let names = [
    ".env", ".npmrc", ".pypirc", ".netrc", ".git-credentials", "credentials.json",
    ".vault-token", ".htpasswd",
  ]
  /// A name with this prefix is secret unless it is exactly one of ``templates``.
  static let templatedPrefix = ".env."
  static let templates = [".env.example", ".env.sample", ".env.template", ".env.dist"]
  static let prefixes = ["id_rsa", "id_ed25519", "id_ecdsa", "id_dsa"]
  static let suffixes = [
    ".pem", ".key", ".p12", ".pfx", ".jks", ".keystore", ".tfstate", ".keychain-db",
  ]
  /// A name that starts with `prefix` and ends with a non-overlapping `suffix`.
  static let affixes: [(prefix: String, suffix: String)] = [("service-account", ".json")]
  /// A name directly below `parent` equal to `name`.
  static let children: [(parent: String, name: String)] = [(".gem", "credentials")]
  /// A name directly below `parent` that starts with `prefix`.
  static let childPrefixes: [(parent: String, prefix: String)] = [(".cargo", "credentials")]
}
