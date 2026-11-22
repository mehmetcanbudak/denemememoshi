import Foundation
import NIOSSL

/// One explicitly provisioned secret-host interception identity. The private key remains in the
/// host process; it is never written to a bot home, proxy environment, decision or CA bundle.
public struct EgressTLSIdentity: Sendable {
  /// The normalized, nonlocal DNS name used to select this client's interception context.
  public let host: String
  let context: NIOSSLContext

  /// Builds an HTTP/1.1 server context with TLS 1.2 as its minimum version. The host must
  /// provision a certificate/key appropriate for `host`; this does not issue a certificate.
  /// Invalid hosts, empty certificate chains, invalid PEM, or inputs over 1 MiB each throw
  /// `EgressConfigurationError.invalidTLS` without publishing trust material.
  public init(host: String, certificateChainPEM: [UInt8], privateKeyPEM: [UInt8]) throws {
    guard let host = EgressHost.normalize(host), !EgressHost.isIPLiteral(host),
      !EgressHost.isLocalName(host), certificateChainPEM.count <= 1 << 20,
      privateKeyPEM.count <= 1 << 20
    else { throw EgressConfigurationError.invalidTLS }
    do {
      let certificates = try NIOSSLCertificate.fromPEMBytes(certificateChainPEM)
      guard !certificates.isEmpty else { throw EgressConfigurationError.invalidTLS }
      let key = try NIOSSLPrivateKey(bytes: privateKeyPEM, format: .pem)
      var configuration = TLSConfiguration.makeServerConfiguration(
        certificateChain: certificates.map { .certificate($0) }, privateKey: .privateKey(key))
      configuration.minimumTLSVersion = .tlsv12
      configuration.applicationProtocols = ["http/1.1"]
      context = try NIOSSLContext(configuration: configuration)
      self.host = host
    } catch { throw EgressConfigurationError.invalidTLS }
  }
}

/// Opt-in TLS termination only for a client's secret-bound hosts. The supplied public CA bundle
/// is published beside that client's host-owned Unix socket and passed to that sandbox alone.
/// Provisioning/renewal of these identities is a host prerequisite, not automatic CA issuance
/// or a global/system trust-store installation. Other CONNECT destinations remain opaque.
public struct EgressTLSInterception: Sendable {
  let identities: [String: NIOSSLContext]
  let certificateAuthoritiesPEM: [UInt8]

  /// Requires unique host identities and a nonempty CA input of at most 2 MiB. Only parsed
  /// public certificates are retained for publication; surrounding PEM material is discarded.
  /// Invalid inputs throw `EgressConfigurationError.invalidTLS`. Certificate trust and
  /// identity renewal remain the provisioning host's responsibility.
  public init(certificateAuthoritiesPEM: [UInt8], identities: [EgressTLSIdentity]) throws {
    guard !identities.isEmpty, Set(identities.map(\.host)).count == identities.count,
      !certificateAuthoritiesPEM.isEmpty, certificateAuthoritiesPEM.count <= 2 << 20
    else { throw EgressConfigurationError.invalidTLS }
    let publicAuthorities: [UInt8]
    do {
      publicAuthorities = try Self.publicCertificates(certificateAuthoritiesPEM)
    } catch { throw EgressConfigurationError.invalidTLS }
    self.identities = Dictionary(uniqueKeysWithValues: identities.map { ($0.host, $0.context) })
    self.certificateAuthoritiesPEM = publicAuthorities
  }

  /// Parse and re-serialize certificates only. PEM parsers may skip arbitrary surrounding
  /// material, including private keys; copying the caller's original bytes would expose it.
  static func publicCertificates(_ bytes: [UInt8]) throws -> [UInt8] {
    let certificates = try NIOSSLCertificate.fromPEMBytes(bytes)
    guard !certificates.isEmpty else { throw EgressConfigurationError.invalidTLS }
    var result: [UInt8] = []
    for certificate in certificates {
      result += Array("-----BEGIN CERTIFICATE-----\n".utf8)
      result += try Data(certificate.toDERBytes()).base64EncodedData(
        options: [.lineLength64Characters, .endLineWithLineFeed])
      result += Array("\n-----END CERTIFICATE-----\n".utf8)
    }
    return result
  }
}
