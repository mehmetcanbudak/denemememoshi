// The shipping SandboxProfile (MemoshiCore SandboxComputer.swift) and SourceSecretSpellings
// (SourcePathPolicy.swift), re-snapshotted 2026-11-18 from the working tree on 754cca2 after the
// review fixes (ASCII case-insensitive host-exec names), re-indented to top level. UTF-8 SHA-256
// of the two enums as written below, LF, no final LF: b0f0e0907a53fe91880091aa187e455b660752732afb4ca347a8a2b42300bd68.
// Provenance of earlier runs: every raw-matrix run up to and including
// evidence/2026-11-18-memoshi-review-fixes/s4-matrix/run-1 used the d0dc184 snapshot (enum hash
// dc9cc7bfbd6b1ff9fd26ceb5bd29e52e53285ec95fe5ad15358e21b747d8266e), kept in git history in this
// file at 754cca2. SandboxProfileDriftTests renders the shipping profile and fails on any
// difference from this copy, so a rule change needs a new snapshot and a matrix rerun.
import Foundation

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

enum SandboxProfile {
  /// Appended to every deny rule: the kernel's report of that denial then ends with the
  /// instance's `INV` parameter, its invocation tag (S4.7).
  static let tagMessage = #"(with message (param "INV"))"#

  /// The protected-secret predicate, generated from ``SourceSecretSpellings`` so the profile
  /// and host admission cannot drift. A secret-spelled component protects itself and every
  /// descendant; only an exact lowercase template leaf is exempt, never a template directory
  /// or a template below a secret directory. Matching is ASCII case-insensitive: Seatbelt
  /// cannot fold Unicode or drop default-ignorable scalars, which admission refuses instead
  /// and the daemon's guard adds (``SandboxGuardedFiles/protectsSecret(in:)``).
  static let protectedSecret: String = {
    let patterns = secretPatterns
    return "(require-any " + regex(patterns.directory) + " (require-all "
      + regex(patterns.leaf) + " (require-not " + regex(patterns.template) + ")))"
  }()

  /// The regular expressions of ``protectedSecret``: a secret-spelled directory, a
  /// secret-spelled leaf, and the exempt template leaves.
  fileprivate static let secretPatterns: (directory: String, leaf: String, template: String) = {
    typealias Spellings = SourceSecretSpellings
    let any = "[^/]*"
    var alternatives = Spellings.names.map { pattern($0) }
    alternatives.append(pattern(Spellings.templatedPrefix) + any)
    alternatives += Spellings.prefixes.map { pattern($0) + any }
    alternatives += Spellings.suffixes.map { any + pattern($0) }
    alternatives += Spellings.affixes.map { pattern($0.prefix) + any + pattern($0.suffix) }
    alternatives += Spellings.children.map { pattern($0.parent) + "/" + pattern($0.name) }
    alternatives += Spellings.childPrefixes.map {
      pattern($0.parent) + "/" + pattern($0.prefix) + any
    }
    let component = "(" + alternatives.joined(separator: "|") + ")"
    let templates =
      "("
      + Spellings.templates.map { pattern($0, caseInsensitive: false) }
      .joined(separator: "|") + ")"
    return ("/" + component + "/", "/" + component + "$", "/" + templates + "$")
  }()

  /// D103 `host_exec` write targets inside the roots: each of these directories and
  /// everything below it.
  static let hostExecDirectories = [".git/hooks", ".vscode", ".idea"]
  /// D103 `host_exec` write targets inside the roots: exactly these entries.
  static let hostExecLeaves = [".git/config", ".gitconfig", ".bashrc", ".zshrc", ".mcp.json"]

  /// Every protected host-exec entry as lowercase names, and whether it protects everything
  /// below it. `.git` itself stays writable so a bot can create and move repositories.
  // Open until a host git exists: a directory built elsewhere can be renamed onto `.git`.
  static let hostExecEntries: [(names: [String], below: Bool)] =
    hostExecLeaves.map { ($0.split(separator: "/").map(String.init), false) }
    + hostExecDirectories.map { ($0.split(separator: "/").map(String.init), true) }

  /// ``hostExecEntries`` as the profile's write exception, ASCII case-insensitive as the
  /// secret rules are.
  static let hostExecPath: String = {
    let alternatives = hostExecEntries.map { entry in
      entry.names.map { pattern($0) }.joined(separator: "/") + (entry.below ? "(/.*)?" : "")
    }
    return regex("/(" + alternatives.joined(separator: "|") + ")$")
  }()

  static func make(
    executable: String, home: String, workingRoot: String?, gatewaySocket: String? = nil,
    certificateBundle: String? = nil, readOnlyToolchainRoots: [String] = []
  ) -> String {
    let hostExec = Self.hostExecPath
    let protectedSecret = Self.protectedSecret
    var roots = [home]
    if let workingRoot { roots.append(workingRoot) }
    var rules = [
      "(version 1)",
      deny("default"),
      #"(allow process-exec (require-not (require-any (literal "/usr/bin/security") (literal "/usr/bin/osascript") (literal "/usr/bin/open") (literal "/usr/bin/pbcopy") (literal "/usr/bin/pbpaste") (literal "/usr/bin/sudo") (literal "/usr/bin/su"))))"#,
      "(allow process-fork)",
      "(allow signal (target same-sandbox))",
      "(allow process-info* (target same-sandbox))",
      "(allow sysctl-read)",
      #"(allow file-read* (require-any (subpath "/System/Library") (subpath "/System/Cryptexes/OS/usr/lib") (subpath "/usr/lib") (subpath "/usr/bin") (subpath "/usr/share") (subpath "/bin") (subpath "/sbin") (literal "/dev/null") (literal "/dev/random") (literal "/dev/urandom") (literal "#
        + quoted(executable) + ")))",
      #"(allow file-read* (literal "/private/var/select/sh"))"#,
      #"(allow file-read* (literal "/Library/Preferences/com.apple.dt.Xcode.plist"))"#,
      #"(allow file-read* (subpath "/private/etc/ssl"))"#,
      #"(allow file-write-data (literal "/dev/null"))"#,
      #"(allow file-read* (literal "/"))"#,
      "(allow file-read-metadata (vnode-type DIRECTORY))",
    ]
    for root in readOnlyToolchainRoots {
      rules.append(
        "(allow file-read* (require-all (subpath " + quoted(root) + ") (require-not "
          + protectedSecret + ")))")
    }
    for root in roots {
      rules.append(
        "(allow file-read* (require-all (subpath " + quoted(root) + ") (require-not "
          + protectedSecret + ")))")
      rules.append(
        "(allow file-write* (require-all (subpath " + quoted(root) + ") (require-not "
          + protectedSecret + ") (require-not " + hostExec + ")))")
    }
    for root in readOnlyToolchainRoots {
      rules.append(deny("file-write* (subpath " + quoted(root) + ")"))
      protectAncestors(of: root, rules: &rules)
    }
    rules.append(deny("file-write* (literal " + quoted(executable) + ")"))
    protectAncestors(of: executable, rules: &rules)
    if let gatewaySocket {
      rules.append("(allow network-outbound (literal " + quoted(gatewaySocket) + "))")
      rules.append("(allow file-read-metadata (literal " + quoted(gatewaySocket) + "))")
    }
    if let certificateBundle {
      rules.append("(allow file-read* (literal " + quoted(certificateBundle) + "))")
    }
    return rules.joined(separator: "\n")
  }

  // Path-based protection must also prevent moving the protected inode to a writable name.
  // Split scalars: a combining filename can make "/" part of a larger Character.
  private static func protectAncestors(of path: String, rules: inout [String]) {
    var ancestor = path.unicodeScalars[...]
    while let slash = ancestor.lastIndex(of: "/"), slash != ancestor.startIndex {
      ancestor = ancestor[..<slash]
      rules.append(deny("file-write-unlink (literal " + quoted(String(ancestor)) + ")"))
    }
  }

  private static func deny(_ rule: String) -> String { "(deny " + rule + " " + tagMessage + ")" }

  private static func quoted(_ text: String) -> String {
    "\""
      + text.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }

  /// An ERE fragment matching `text` literally, ASCII letters case-insensitively by default.
  private static func pattern(_ text: String, caseInsensitive: Bool = true) -> String {
    text.unicodeScalars.map { scalar -> String in
      let character = String(scalar)
      switch scalar {
      case "a"..."z", "A"..."Z":
        return caseInsensitive
          ? "[" + character.lowercased() + character.uppercased() + "]" : character
      case "0"..."9", "_", "-":
        return character
      case "^", "]", "\\":
        return "\\" + character
      default:
        return scalar.isASCII ? "[" + character + "]" : character
      }
    }
    .joined()
  }

  private static func regex(_ pattern: String) -> String { "(regex #\"" + pattern + "\")" }
}
