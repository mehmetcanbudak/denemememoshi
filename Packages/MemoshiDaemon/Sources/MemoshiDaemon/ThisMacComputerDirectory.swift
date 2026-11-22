import Darwin
import Foundation
import MemoshiEgress
import MemoshiProtocol
import MemoshiRuntime

/// Resolves each bot's default This Mac (sandboxed) computer (CMP-03, D16, D77, D96).
///
/// Each bot receives its own private 0700 home directory under `<dataDirectory>/computers/<bot>/home`
/// and a deny-all default egress policy until grants expand it. Returning the same cached
/// ``RuntimeSandboxComputer`` instance lets ``RuntimeEnvironments`` reuse the conversation's
/// confined daemon across calls while the bot's computer configuration is unchanged.
public actor ThisMacComputerDirectory: RuntimeComputerDirectory {
  private let computersRoot: URL
  private var cached: [BotID: RuntimeSandboxComputer] = [:]

  public init(dataDirectory: URL) {
    computersRoot = dataDirectory.appendingPathComponent("computers", isDirectory: true)
  }

  public func computer(conversation _: ConversationID, bot: BotID) async throws -> RuntimeComputer {
    if let existing = cached[bot] {
      return .thisMacSandbox(existing)
    }
    let homeURL = computersRoot
      .appendingPathComponent(bot.rawValue, isDirectory: true)
      .appendingPathComponent("home", isDirectory: true)
    let canonicalHome = try Self.ensurePrivateCanonicalDirectory(homeURL)
    let policy = try EgressPolicy(hosts: [])
    let computer = RuntimeSandboxComputer(
      id: "this-mac-\(bot.rawValue)",
      home: canonicalHome,
      workingRoot: nil,
      network: policy)
    cached[bot] = computer
    return .thisMacSandbox(computer)
  }

  /// Creates the directory chain with 0700 permissions on the bot home and returns its realpath.
  static func ensurePrivateCanonicalDirectory(_ url: URL) throws -> String {
    let fm = FileManager.default
    try fm.createDirectory(
      at: url, withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: 0o700)])
    try fm.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: url.path)
    return try canonicalPath(url.path)
  }

  /// Resolves symlinks via `realpath` so Seatbelt compares canonical paths.
  static func canonicalPath(_ path: String) throws -> String {
    guard let resolved = Darwin.realpath(path, nil) else {
      throw RuntimeEnvironmentError.invalidComposition
    }
    defer { free(resolved) }
    return String(cString: resolved)
  }
}
