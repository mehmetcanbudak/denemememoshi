// The declarative 105-vector table of the S4 raw matrix, extracted from the original probe's
// `populate()` so tests can assert the fixture without running Seatbelt. Base tokens ("home",
// "other-home", "home-tmp", "other-tmp", "copy", "shared", "synthetic-private") resolve per
// principal inside `S4Matrix`. Order and fields mirror the recorded probe exactly.
package struct S4MatrixVector: Codable, Equatable {
  package let id: String
  package let category: String
  package let role: String
  package let expectation: String
  package let operation: String
  package let base: String
  package let relative: String
  package let secondBase: String?
  package let secondRelative: String
  package let aliasKind: String?
  package let aliasRelative: String?
  package let physicalAlias: Bool
  package let outsideSymlink: Bool
  package let sharedInode: Bool
  package let limitation: String

  package init(
    id: String, category: String, role: String, expectation: String, operation: String,
    base: String, relative: String = "owned.txt", secondBase: String? = nil,
    secondRelative: String = "destination.txt", aliasKind: String? = nil,
    aliasRelative: String? = nil, physicalAlias: Bool = false, outsideSymlink: Bool = false,
    sharedInode: Bool = false, limitation: String = S4MatrixVector.defaultLimitation
  ) {
    self.id = id
    self.category = category
    self.role = role
    self.expectation = expectation
    self.operation = operation
    self.base = base
    self.relative = relative
    self.secondBase = secondBase
    self.secondRelative = secondRelative
    self.aliasKind = aliasKind
    self.aliasRelative = aliasRelative
    self.physicalAlias = physicalAlias
    self.outsideSymlink = outsideSymlink
    self.sharedInode = sharedInode
    self.limitation = limitation
  }

  package static let defaultLimitation =
    "Raw current-profile behavior only; not SDK descriptor-guard or admission/export qualification."
  static let sharedLimitation =
    "Owned synthetic shared tree only; never accesses /tmp/claude or other existing shared paths."
  static let sameSharedLimitation =
    "Same exact owned path and inode for A/B; never accesses real shared scratch."
  static let syntheticPrivateLimitation =
    "Owned synthetic shape only; does not test TCC or access actual ssh/Keychain/source data."
  static let secretDirectoryLimitation =
    "Defense-in-depth expectation: a secret-class directory must not expose descendants. This raw fixture does not assert admission permits such a directory."
  static let physicalAliasLimitation =
    "Only counted when stat proves distinct pathname bytes address the same device/inode and host bytes match. Absent/non-alias spellings are not denials."
  static let preexistingAliasLimitation =
    "Deliberately unsafe preexisting owned alias; D96 admission must reject it. A raw-profile gap is not by itself an admitted-copy escape."
  static let preexistingConfigAliasLimitation =
    "Synthetic non-executed config and deliberately unsafe preexisting alias; no git/hooks/tool execution."
  static let outsideSymlinkLimitation =
    "Owned alias targets an owned ungranted private canary, never real private data."
}

package enum S4MatrixVectors {
  /// The complete fixture: 105 vectors, 80 deny / 25 allow expectations, in recorded order.
  package static let all: [S4MatrixVector] = {
    var vectors: [S4MatrixVector] = []
    func append(_ vector: S4MatrixVector) { vectors.append(vector) }
    for (role, other) in [("a", "b"), ("b", "a")] {
      for operation in ["read", "overwrite", "create", "link", "rename"] {
        append(
          S4MatrixVector(
            id: "own-home-\(role)-\(operation)", category: "owned-positive", role: role,
            expectation: "allow", operation: operation, base: "home"))
      }
      for operation in ["read", "overwrite"] {
        append(
          S4MatrixVector(
            id: "own-copy-\(role)-\(operation)", category: "private-copy-positive", role: role,
            expectation: "allow", operation: operation, base: "copy"))
        append(
          S4MatrixVector(
            id: "other-home-\(role)-\(operation)", category: "cross-bot-isolation", role: role,
            expectation: "deny", operation: operation, base: "other-home"))
      }
      append(
        S4MatrixVector(
          id: "own-tmp-\(role)", category: "per-bot-tmpdir-positive", role: role,
          expectation: "allow", operation: "create", base: "home-tmp"))
      append(
        S4MatrixVector(
          id: "other-tmp-\(role)", category: "per-bot-tmpdir-isolation", role: role,
          expectation: "deny", operation: "create", base: "other-tmp"))
      for operation in ["read", "overwrite", "create"] {
        append(
          S4MatrixVector(
            id: "shared-\(role)-\(operation)", category: "ungranted-shared-path", role: role,
            expectation: "deny", operation: operation, base: "shared",
            limitation: S4MatrixVector.sharedLimitation))
      }
      append(
        S4MatrixVector(
          id: "cross-bot-link-\(role)", category: "new-cross-bot-link", role: role,
          expectation: "deny", operation: "link", base: "other-home", secondBase: "home"))
      append(
        S4MatrixVector(
          id: "link-to-shared-\(role)", category: "new-outside-link", role: role,
          expectation: "deny", operation: "link", base: "home", secondBase: "shared"))
    }
    for (role, operation) in [("a", "read"), ("a", "overwrite"), ("b", "read"), ("b", "overwrite")]
    {
      append(
        S4MatrixVector(
          id: "same-shared-\(role)-\(operation)", category: "identical-shared-inode", role: role,
          expectation: "deny", operation: operation, base: "shared",
          relative: "common-owned.txt", sharedInode: true,
          limitation: S4MatrixVector.sameSharedLimitation))
    }
    for (index, relative) in [
      ".ssh/id_owned", "Library/Keychains/owned.keychain-db", "live-source/source.txt",
    ].enumerated() {
      for operation in ["read", "overwrite"] {
        append(
          S4MatrixVector(
            id: "outside-private-\(index)-\(operation)", category: "synthetic-private-outside-home",
            role: "a", expectation: "deny", operation: operation, base: "synthetic-private",
            relative: relative, limitation: S4MatrixVector.syntheticPrivateLimitation))
      }
    }
    let secretNames = [
      ".env", ".ENV", ".eNv.production", "certificate.PeM", "client.kEy", "client.P12",
      "client.PfX", "client.jKs", "client.KeyStore",
    ]
    for (index, name) in secretNames.enumerated() {
      for operation in ["read", "overwrite"] {
        append(
          S4MatrixVector(
            id: "secret-\(index)-\(operation)", category: "configured-secret-basename", role: "a",
            expectation: "deny", operation: operation, base: "copy", relative: "nested/" + name))
      }
    }
    for (index, relative) in ["nested/.env/secret.txt", "nested/store.KeyStore/entry.txt"]
      .enumerated()
    {
      for operation in ["read", "overwrite"] {
        append(
          S4MatrixVector(
            id: "secret-directory-\(index)-\(operation)", category: "secret-directory-descendant",
            role: "a", expectation: "deny", operation: operation, base: "copy", relative: relative,
            limitation: S4MatrixVector.secretDirectoryLimitation))
      }
    }
    for (index, name) in [".env.example", ".ENV.sample", ".eNv.template", ".env.dist"].enumerated()
    {
      for operation in ["read", "overwrite"] {
        append(
          S4MatrixVector(
            id: "template-\(index)-\(operation)", category: "explicit-template-positive", role: "a",
            expectation: "allow", operation: operation, base: "copy", relative: "nested/" + name))
      }
    }
    append(
      S4MatrixVector(
        id: "host-config-read", category: "host-exec-config-readable-positive", role: "a",
        expectation: "allow", operation: "read", base: "copy", relative: ".git/config"))
    append(
      S4MatrixVector(
        id: "host-config-write", category: "host-exec-config-write", role: "a",
        expectation: "deny", operation: "overwrite", base: "copy", relative: ".git/config"))
    let physicalAliases: [(String, String, String, String)] = [
      ("secret-case-env", ".env.production", ".ENV.PRODUCTION", "case"),
      ("secret-case-extension", "client.pem", "CLIENT.PEM", "case"),
      ("config-case-leaf", ".git/config", ".git/CONFIG", "case"),
      ("config-case-directory", ".git/config", ".GIT/config", "case"),
      ("config-case-mixed", ".git/config", ".GiT/CoNfIg", "case"),
      ("secret-normalized-directory", "caf\u{00e9}/.env", "cafe\u{0301}/.env", "nfc-nfd"),
      ("secret-normalized-suffix", ".env.caf\u{00e9}", ".env.cafe\u{0301}", "nfc-nfd"),
      (
        "config-normalized-directory", "r\u{00e9}po/.git/config", "re\u{0301}po/.git/config",
        "nfc-nfd"
      ),
      ("secret-ignorable-joiner", ".env", ".e\u{200d}nv", "default-ignorable"),
      ("secret-ignorable-trailing", ".env", ".env\u{200b}", "default-ignorable"),
      ("config-ignorable", ".git/config", ".g\u{200d}it/config", "default-ignorable"),
    ]
    for (id, canonical, alias, kind) in physicalAliases {
      let operations = id.hasPrefix("secret-") ? ["read", "overwrite"] : ["overwrite"]
      for operation in operations {
        append(
          S4MatrixVector(
            id: id + "-" + operation, category: "physical-alias-" + kind, role: "a",
            expectation: "deny", operation: operation, base: "copy", relative: canonical,
            aliasKind: kind, aliasRelative: alias, physicalAlias: true,
            limitation: S4MatrixVector.physicalAliasLimitation))
      }
    }
    for kind in ["symbolic-link", "hard-link"] {
      for operation in ["read", "overwrite"] {
        append(
          S4MatrixVector(
            id: kind + "-secret-" + operation, category: "preexisting-secret-inode-alias",
            role: "a",
            expectation: "deny", operation: operation, base: "copy", relative: "nested/.env",
            aliasKind: kind, aliasRelative: "ordinary-alias.txt",
            limitation: S4MatrixVector.preexistingAliasLimitation))
      }
      append(
        S4MatrixVector(
          id: kind + "-config-write", category: "preexisting-host-exec-inode-alias", role: "a",
          expectation: "deny", operation: "overwrite", base: "copy", relative: ".git/config",
          aliasKind: kind, aliasRelative: "ordinary-config-alias.txt",
          limitation: S4MatrixVector.preexistingConfigAliasLimitation))
    }
    for operation in ["read", "overwrite"] {
      append(
        S4MatrixVector(
          id: "symbolic-link-outside-" + operation, category: "outside-symlink-target", role: "a",
          expectation: "deny", operation: operation, base: "synthetic-private",
          aliasKind: "symbolic-link", outsideSymlink: true,
          limitation: S4MatrixVector.outsideSymlinkLimitation))
    }
    append(
      S4MatrixVector(
        id: "secret-new-hardlink", category: "new-secret-hardlink", role: "a", expectation: "deny",
        operation: "link", base: "copy", relative: ".env"))
    append(
      S4MatrixVector(
        id: "secret-rename-out", category: "secret-file-rename", role: "a", expectation: "deny",
        operation: "rename", base: "copy", relative: ".env"))
    append(
      S4MatrixVector(
        id: "config-rename-out", category: "host-exec-file-rename", role: "a", expectation: "deny",
        operation: "rename", base: "copy", relative: ".git/config"))
    append(
      S4MatrixVector(
        id: "secret-rename-in", category: "secret-name-create-by-rename", role: "a",
        expectation: "deny", operation: "rename", base: "copy", secondRelative: ".env"))
    append(
      S4MatrixVector(
        id: "config-rename-in", category: "host-exec-name-create-by-rename", role: "a",
        expectation: "deny", operation: "rename", base: "copy", secondRelative: ".git/config"))
    append(
      S4MatrixVector(
        id: "rename-to-shared", category: "outside-file-rename", role: "a", expectation: "deny",
        operation: "rename", base: "home", secondBase: "shared"))
    return vectors
  }()

  /// The default-ignorable (U+200B / U+200D) physical-alias vectors: five cases no APFS spelling
  /// establishes, reported as `not_applicable_alias_not_established` (HFS+ folds the U+200D ones).
  package static let defaultIgnorableAliasIDs: Set<String> = Set(
    all.filter { $0.category == "physical-alias-default-ignorable" }.map(\.id))

  /// The deliberately preexisting hard-link vectors: the recorded accepted-limit effects.
  package static let preexistingHardLinkIDs: Set<String> = Set(
    all.filter { $0.aliasKind == "hard-link" }.map(\.id))
}
