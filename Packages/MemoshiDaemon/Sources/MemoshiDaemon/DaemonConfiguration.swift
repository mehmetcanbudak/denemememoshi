import CryptoKit
import Foundation

/// Invalid packaging, identity and service-lifecycle failures.
public enum DaemonError: Error, Equatable, Sendable {
  case invalidConfiguration
  case wrongSigningIdentity
  case alreadyStarted
  case notRunning
}

/// Packaging supplies the real build identity and the canonical protocol schema.
public struct DaemonConfiguration: Sendable {
  /// The sealed signing identifier permitted to connect as the Mac application.
  public static let appIdentifier = "com.mehmetcanbudak.memoshi.mac"
  /// The sealed signing identifier required of this daemon process.
  public static let helperIdentifier = "com.mehmetcanbudak.memoshi.memoshid"
  /// This user's Application Support root for Memoshi's stores and runtime files.
  public static var defaultDataDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/Memoshi", isDirectory: true)
  }

  /// The private local root used by this service instance.
  public let dataDirectory: URL
  /// The helper's actual packaged version.
  public let version: String
  /// The helper's actual packaged build identifier.
  public let build: String
  /// SHA-256 of the canonical protocol schema bytes supplied by packaging.
  public let schemaHash: String
  /// Whether the Pi_Swift chat engine, Keychain host broker and local folder grants are enabled.
  public let enableTextChat: Bool

  /// Captures build metadata and hashes the real bundled canonical schema.
  public init(
    dataDirectory: URL, version: String, build: String, canonicalSchema: Data,
    enableTextChat: Bool = false
  ) throws {
    guard dataDirectory.isFileURL, version.isEmpty == false, build.isEmpty == false,
      canonicalSchema.isEmpty == false
    else { throw DaemonError.invalidConfiguration }
    // The build copies the generated canonical schema; no placeholder identity is advertised.
    let digest = SHA256.hash(data: canonicalSchema)
    let digits: StaticString = "0123456789abcdef"
    let hexadecimal = digits.withUTF8Buffer { alphabet in
      String(unsafeUninitializedCapacity: 64) { output in
        for (index, byte) in digest.enumerated() {
          output[index * 2] = alphabet[Int(byte >> 4)]
          output[index * 2 + 1] = alphabet[Int(byte & 15)]
        }
        return 64
      }
    }
    self.dataDirectory = dataDirectory
    self.version = version
    self.build = build
    self.schemaHash = "sha256:" + hexadecimal
    self.enableTextChat = enableTextChat
  }
}
