import Foundation
import NIOCore

/// One host a bot may reach through the gateway, with the ports it may use. A pattern is an exact
/// DNS name or `*.` followed by a name, which matches that name's subdomains but not the name
/// itself. IP literals, local names and private ranges are never patterns (policy.md §3.7).
public struct EgressHostRule: Sendable, Hashable, Codable {
  /// The normalized pattern: lowercase ASCII, no trailing dot.
  public let pattern: String
  /// The destination ports this rule admits.
  public let ports: Set<Int>
  /// A trusted network_domain grant's write permission, never inferred from the request.
  public let write: Bool

  /// Refuses an empty port set, a port outside 1–65535 and any pattern that is not a plain
  /// public DNS name.
  public init(_ pattern: String, ports: Set<Int> = [80, 443], write: Bool = false) throws {
    let wildcard = pattern.hasPrefix("*.")
    let name = wildcard ? String(pattern.dropFirst(2)) : pattern
    guard let normalized = EgressHost.normalize(name), !EgressHost.isIPLiteral(normalized),
      !EgressHost.isLocalName(normalized), normalized.contains(".") || !wildcard,
      !ports.isEmpty, ports.allSatisfy({ (1...65_535).contains($0) })
    else { throw EgressConfigurationError.invalidRule }
    self.pattern = wildcard ? "*." + normalized : normalized
    self.ports = ports
    self.write = write
  }

  /// Checks an already-normalized host and exact port against this trusted grant.
  public func matches(host: String, port: Int) -> Bool {
    guard ports.contains(port) else { return false }
    if pattern.hasPrefix("*.") { return host.hasSuffix(pattern.dropFirst(1)) }
    return host == pattern
  }

  func matches(host: String) -> Bool {
    pattern.hasPrefix("*.") ? host.hasSuffix(pattern.dropFirst(1)) : host == pattern
  }
}

/// A credential the sandbox only ever sees as a placeholder. The gateway replaces the placeholder
/// with the real value in request headers, and only toward the binding's exact hosts; a
/// placeholder sent anywhere else blocks the request (policy.md §13). The value is read at use.
public struct EgressSecretBinding: Sendable {
  /// The environment variable that carries the placeholder inside the sandbox; also the name the
  /// decision log records, never the value.
  public let name: String
  /// The opaque broker record this immutable binding resolves; never the credential value.
  public let secretRef: String
  /// Exact normalized hosts the real value may reach.
  public let hosts: Set<String>
  /// Reads the real value at each use, for example from the Keychain broker.
  public let value: @Sendable () async throws -> String

  /// `name` is an uppercase environment-variable name that no sandbox host owns (see
  /// ``isReservedName(_:)``); every host must be a plain public name.
  /// - Throws: `reservedSecretName` for a host-owned name, `invalidSecret` for any other
  ///   invalid field.
  public init(
    name: String, secretRef: String, hosts: Set<String>,
    value: @escaping @Sendable () async throws -> String
  ) throws {
    let validName =
      name.utf8.first.map { $0 == UInt8(ascii: "_") || (65...90).contains($0) } == true
      && name.utf8.allSatisfy {
        $0 == UInt8(ascii: "_") || (65...90).contains($0) || (48...57).contains($0)
      }
    let normalized = try hosts.map { host -> String in
      guard let value = EgressHost.normalize(host), !EgressHost.isIPLiteral(value),
        !EgressHost.isLocalName(value)
      else { throw EgressConfigurationError.invalidSecret }
      return value
    }
    guard validName, !secretRef.isEmpty, secretRef.utf8.count <= 256,
      !secretRef.utf8.contains(where: { $0 == 0 || $0 == 10 || $0 == 13 }),
      !normalized.isEmpty
    else { throw EgressConfigurationError.invalidSecret }
    guard !Self.isReservedName(name) else { throw EgressConfigurationError.reservedSecretName }
    self.name = name
    self.secretRef = secretRef
    self.hosts = Set(normalized)
    self.value = value
  }

  /// Whether a confined computer's host owns the environment variable `name`, setting it or
  /// leaving it unset on purpose: the process base (`HOME`, `TMPDIR`, `PATH`, `LANG`,
  /// `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM`), the gateway's proxy, bypass and trust
  /// variables, and every `MEMOSHI_` variable. A mask never takes such a name, so no
  /// placeholder can replace or add a value the host relies on.
  public static func isReservedName(_ name: String) -> Bool {
    name.utf8.starts(with: "MEMOSHI_".utf8) || reservedNames.contains(name)
  }

  private static let reservedNames = EgressClient.proxyVariableNames.union([
    "HOME", "TMPDIR", "PATH", "LANG", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM",
  ])
}

/// One bot's network list and masked credentials, applied by its own gateway client.
public struct EgressPolicy: Sendable {
  /// Hosts the bot may reach. Everything else is refused.
  public let hosts: [EgressHostRule]
  /// Credentials injected only toward their bound hosts.
  public let secrets: [EgressSecretBinding]
  /// Explicit host-supplied identities for secret-bound HTTPS hosts only. Without these, HTTPS
  /// can use verified absolute-form forwarding, but ordinary CONNECT remains non-injecting.
  public let tlsInterception: EgressTLSInterception?

  /// Every secret's hosts must also be allowed hosts, and secret names must be unique.
  public init(
    hosts: [EgressHostRule], secrets: [EgressSecretBinding] = [],
    tlsInterception: EgressTLSInterception? = nil
  ) throws {
    guard Set(secrets.map(\.name)).count == secrets.count,
      secrets.allSatisfy({ secret in
        secret.hosts.allSatisfy { host in hosts.contains { $0.matches(host: host) } }
      })
    else { throw EgressConfigurationError.invalidSecret }
    let secretHosts = Set(secrets.flatMap(\.hosts))
    guard tlsInterception?.identities.keys.allSatisfy({ secretHosts.contains($0) }) ?? true else {
      throw EgressConfigurationError.invalidTLS
    }
    self.hosts = hosts
    self.secrets = secrets
    self.tlsInterception = tlsInterception
  }
}

/// Whose traffic a gateway client carries. Every decision is attributed to these values.
public struct EgressClientIdentity: Sendable, Hashable, Codable {
  /// The bot's ID.
  public let bot: String
  /// The conversation's ID.
  public let conversation: String
  /// The computer's identity.
  public let computer: String

  /// Creates an identity from trusted host values.
  public init(bot: String, conversation: String, computer: String) {
    self.bot = bot
    self.conversation = conversation
    self.computer = computer
  }
}

/// Configuration failures; never carries a value or placeholder.
public enum EgressConfigurationError: Error, Equatable, Sendable {
  case invalidRule
  case invalidSecret
  /// A mask named like an environment variable the sandbox host sets or keeps unset itself.
  case reservedSecretName
  case closed
  case unbound
  case logUnavailable
  case invalidTLS
}

/// DNS-name checks done before any resolution.
enum EgressHost {
  /// Lowercase ASCII labels of letters, digits, `-` and `_`, without a trailing dot, or nil.
  static func normalize(_ raw: String) -> String? {
    var host = raw.lowercased()
    if host.hasSuffix(".") { host.removeLast() }
    guard !host.isEmpty, host.utf8.count <= 253 else { return nil }
    for label in host.split(separator: ".", omittingEmptySubsequences: false) {
      guard !label.isEmpty, label.utf8.count <= 63, label.first != "-", label.last != "-",
        label.utf8.allSatisfy({
          (97...122).contains($0) || (48...57).contains($0) || $0 == UInt8(ascii: "-")
            || $0 == UInt8(ascii: "_")
        })
      else { return nil }
    }
    return host
  }

  /// A dotted or legacy numeric address spelling, such as `127.1` or `0x7f.1`. A DNS name never
  /// has an all-numeric last label, so such hosts are refused as IP literals.
  static func isIPLiteral(_ host: String) -> Bool {
    guard let last = host.split(separator: ".").last else { return false }
    if last.allSatisfy(\.isNumber) { return true }
    return last.hasPrefix("0x") && last.dropFirst(2).allSatisfy(\.isHexDigit)
  }

  /// Names that resolve on the local machine or network. Other names still meet the address
  /// check after resolution, such as `/etc/hosts` entries.
  static func isLocalName(_ host: String) -> Bool {
    host == "localhost"
      || [".localhost", ".local", ".home.arpa", ".internal"].contains { host.hasSuffix($0) }
  }
}

/// Address classes the gateway refuses after resolution (policy.md §3.7): loopback, RFC 1918,
/// link-local (including 169.254.169.254), ULA, CGNAT, multicast, broadcast and other
/// special-purpose ranges that are not globally reachable. IPv4-mapped, NAT64 and 6to4 IPv6
/// addresses are checked by their embedded IPv4 address.
enum EgressAddress {
  static func deniedClass(_ address: SocketAddress) -> String? {
    switch address {
    case .v4(let ipv4):
      let value = UInt32(bigEndian: ipv4.address.sin_addr.s_addr)
      return deniedClass(
        ipv4: (
          UInt8(value >> 24), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff),
          UInt8(value & 0xff)
        ))
    case .v6(let ipv6):
      return withUnsafeBytes(of: ipv6.address.sin6_addr) { deniedClass(ipv6: Array($0)) }
    default:
      return "unsupported_family"
    }
  }

  static func deniedClass(ipv4 a: (UInt8, UInt8, UInt8, UInt8)) -> String? {
    switch (a.0, a.1, a.2) {
    case (0, _, _): return "this_network"
    case (10, _, _): return "private"
    case (100, 64...127, _): return "cgnat"
    case (127, _, _): return "loopback"
    case (169, 254, _): return "link_local"
    case (172, 16...31, _): return "private"
    case (192, 0, 0): return "special"
    case (192, 0, 2), (198, 51, 100), (203, 0, 113): return "documentation"
    case (192, 88, 99): return "special"
    case (192, 168, _): return "private"
    case (198, 18...19, _): return "benchmarking"
    case (224...239, _, _): return "multicast"
    case (255, 255, 255) where a.3 == 255: return "broadcast"
    case (240...255, _, _): return "reserved"
    default: return nil
    }
  }

  static func deniedClass(ipv6 b: [UInt8]) -> String? {
    guard b.count == 16 else { return "unsupported_family" }
    let prefix96Zero = b[0..<10].allSatisfy { $0 == 0 }
    if prefix96Zero && b[10] == 0xff && b[11] == 0xff {
      return deniedClass(ipv4: (b[12], b[13], b[14], b[15]))
    }
    if b[0..<12].allSatisfy({ $0 == 0 }) {
      if b[12..<15].allSatisfy({ $0 == 0 }) && b[15] <= 1 {
        return b[15] == 1 ? "loopback" : "unspecified"
      }
      return "special"
    }
    if b[0] == 0x00 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b {
      if b[4..<12].allSatisfy({ $0 == 0 }) {
        return deniedClass(ipv4: (b[12], b[13], b[14], b[15]))
      }
      if b[4] == 0 && b[5] == 1 { return "private" }
    }
    if b[0] == 0x01 && b[1] == 0x00 && b[2..<8].allSatisfy({ $0 == 0 }) { return "special" }
    if b[0] == 0x20 && b[1] == 0x01 {
      if b[2] == 0x0d && b[3] == 0xb8 { return "documentation" }
      if b[2] < 0x02 { return "special" }
    }
    if b[0] == 0x20 && b[1] == 0x02 { return deniedClass(ipv4: (b[2], b[3], b[4], b[5])) }
    if b[0] & 0xfe == 0xfc { return "private" }
    if b[0] == 0xfe && b[1] & 0xc0 == 0x80 { return "link_local" }
    if b[0] == 0xfe && b[1] & 0xc0 == 0xc0 { return "site_local" }
    if b[0] == 0xff { return "multicast" }
    return nil
  }
}
