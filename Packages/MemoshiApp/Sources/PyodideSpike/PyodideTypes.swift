import Foundation

/// Development-only S6 execution. It does not register a model tool or authorize a script.
public struct PyodideRequest: Sendable {
  /// Correlates script replies and names the write-once result directory; repeated exports can conflict.
  public let id: UUID
  /// Python source whose execution the caller must authorize independently of this value.
  public let code: String
  /// Relative admitted-bot-folder paths copied into the cell's in-memory working directory.
  public let inputPaths: [String]
  /// Declared cell-relative files to export; undeclared interpreter files never cross the bridge.
  public let outputPaths: [String]
  /// Native wall-time limit in seconds, accepted from 0.05 through 900 and armed after input copying.
  public let timeoutSeconds: Double

  /// Paths are relative to this host's bot folder / the cell's private in-memory work directory.
  /// Output paths must be declared before dispatch; only those files can leave the interpreter.
  /// Construction only stores values; the host validates paths, sizes and timeout before dispatch.
  public init(
    id: UUID = UUID(), code: String, inputPaths: [String] = [], outputPaths: [String] = [],
    timeoutSeconds: Double = 30
  ) {
    self.id = id
    self.code = code
    self.inputPaths = inputPaths
    self.outputPaths = outputPaths
    self.timeoutSeconds = timeoutSeconds
  }
}

/// A bounded scientific table sample returned as data, not HTML, executable output or a model reply.
public struct PyodideTable: Sendable, Codable, Equatable {
  /// Stringified source column labels, ordered to match the values in each sampled JSON row.
  public let columns: [String]
  /// A bounded JSON representation; nulls remain null and non-finite numbers become null.
  public let jsonRows: String
  /// Source frame's row count before sampling; `jsonRows` contains at most 100 of those rows.
  public let totalRows: Int
}

/// A bounded PNG result from the cell's scientific-output bridge, with no UI execution authority.
public struct PyodideFigure: Sendable, Codable, Equatable {
  /// PNG-encoded bytes whose signature and size the host checks before returning a result.
  public let png: Data
}

/// Metadata for a declared cell output exported as a write-once file inside the admitted bot folder.
public struct PyodideArtifact: Sendable, Codable, Equatable {
  /// Bot-folder-relative location under `pyodide-results/<request-id>/<declared-path>`.
  public let path: String
  /// Number of exported file bytes, not the interpreter's encoded transfer size.
  public let bytes: Int
  /// Lowercase hexadecimal SHA-256 computed natively from the exported bytes.
  public let sha256: String
}

/// Bounds-checked scientific output from one cell, independent of model execution or tool authorization.
public struct PyodideResult: Sendable, Codable, Equatable {
  /// Identifier of the request whose matching script reply produced these values.
  public let requestID: UUID
  /// Captured standard-output text; untrusted result content, not app instructions.
  public let stdout: String
  /// Captured standard-error text, subject to the shared stdout/stderr byte limit.
  public let stderr: String
  /// At most eight data-only table samples with host-checked row and column bounds.
  public let tables: [PyodideTable]
  /// At most eight PNG figures accepted by the host's signature and byte limits.
  public let figures: [PyodideFigure]
  /// Metadata for all declared outputs after successful native export, not ambient filesystem access.
  public let artifacts: [PyodideArtifact]
  /// Worker-reported seconds from cell setup through result collection, excluding native input
  /// copying and artifact export; this is one sample, not a latency percentile.
  public let elapsedSeconds: Double
}

/// One bounded HTTP hop from a live Python cell. This value carries no native gateway credential.
public struct PyodideHTTPRequest: Sendable {
  /// Original absolute HTTP(S) URL; native admission rejects credentials and other schemes.
  public let url: String
  /// HTTP token selected by the script, subject to native method and body checks.
  public let method: String
  /// Caller headers, excluding native transport, framing and gateway credentials.
  public let headers: [String: String]
  /// Entity bytes, bounded to 1 MiB before transport dispatch.
  public let body: Data

  /// Stores one request; construction alone performs neither validation nor network work.
  public init(
    url: String, method: String = "GET", headers: [String: String] = [:], body: Data = Data()
  ) {
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
  }
}

/// Actual HTTP status, end-to-end headers and entity bytes, including non-success responses.
public struct PyodideHTTPResponse: Sendable {
  /// Actual HTTP status, including an upstream non-success or the owned gateway's refusal.
  public let status: Int
  /// Bounded end-to-end headers; native admission removes cookie and hop-by-hop fields.
  public let headers: [String: String]
  /// Identity-encoded entity bytes, empty for HEAD/bodyless statuses and bounded to 16 MiB.
  public let body: Data

  /// Stores a response for native validation before any worker receives its bytes.
  public init(status: Int, headers: [String: String], body: Data) {
    self.status = status
    self.headers = headers
    self.body = body
  }
}

/// Caller-owned, attributed native networking. Each send performs exactly one hop, never retries or
/// follows redirects, and must cancel and drain owned network work before returning from cancellation.
/// The host admits at most eight sends, with 1 MiB request and 16 MiB response bodies. No transport
/// means offline execution; this protocol supplies neither policy grants nor a production tool route.
public protocol PyodideNetworkTransport: Sendable {
  /// Performs one hop for this native-selected live cell, retaining ownership through cancel/drain.
  func send(_ request: PyodideHTTPRequest, cellID: UUID) async throws -> PyodideHTTPResponse
}

/// Content-free bridge, filesystem and lifecycle failures; none automatically retries a cell or
/// selects a different Python engine.
public enum PyodideFailure: String, Error, Sendable, Codable, LocalizedError {
  case bundleMissing
  case bundleIntegrity
  case invalidRequest
  case unsafePath
  case fileUnavailable
  case fileChanged
  case outputConflict
  case outputLimit
  case busy
  case notReady
  case startupFailed
  /// The realm missed its start limit: no cell was dispatched, so nothing ran.
  case startTimedOut
  case scriptFailed
  case cancelled
  case timedOut
  case webContentTerminated
  case hostClosed
  case lockdownRequiresMac
  case packageUnavailable
  case backgroundInterrupted
  case networkFailed
  case idleExpired
  case lifetimeExpired

  /// User-facing failure summary that omits source, file contents, exception bodies and credentials.
  public var errorDescription: String? {
    switch self {
    case .bundleMissing:
      "The pinned offline Python payload is missing. Package it before running S6."
    case .bundleIntegrity: "The bundled Python payload did not match its pinned manifest."
    case .invalidRequest: "The Python request exceeds the spike's declared limits."
    case .unsafePath: "A Python file path or linked filesystem object was refused."
    case .fileUnavailable: "A declared Python input or output file is unavailable."
    case .fileChanged: "A Python input changed while it was being copied. Nothing ran."
    case .outputConflict: "A Python output would replace an existing file. Nothing was replaced."
    case .outputLimit: "Python output exceeded the spike's bounded result size."
    case .busy: "This bot already has a Python call in flight."
    case .notReady: "This bot's Python interpreter is not ready."
    case .startupFailed: "The offline Python interpreter could not start."
    case .startTimedOut:
      "Python could not start within its start limit, so the cell did not run and nothing ran. "
        + "Its interpreter was discarded; the call may be retried."
    case .scriptFailed: "The Python cell failed. No output files were exported."
    case .cancelled: "Python was stopped; its web view and in-memory interpreter were discarded."
    case .timedOut: "Python reached its wall-time limit; its interpreter was discarded."
    case .webContentTerminated:
      "WebKit terminated Python's content process. The cell was not retried."
    case .hostClosed: "The Python host was closed."
    case .lockdownRequiresMac:
      "Lockdown Mode is enabled. Python needs an available, authorized Mac."
    case .packageUnavailable:
      "That package is not in the pinned offline stack. No package was downloaded."
    case .backgroundInterrupted:
      "Python was stopped because the app could not keep this run active."
    case .networkFailed: "The Python network request failed."
    case .idleExpired:
      "Python was idle past its limit, so its interpreter was discarded. Start it again to continue."
    case .lifetimeExpired:
      "Python reached its session lifetime, so its interpreter was discarded. Start it again to continue."
    }
  }

  /// This is advice for the gate, never an automatic execution or an unavailable fake fallback.
  public var fallback: PyodideFallback {
    switch self {
    case .lockdownRequiresMac, .backgroundInterrupted: .authorizedMacRequired
    case .bundleMissing, .bundleIntegrity, .startupFailed, .startTimedOut, .webContentTerminated:
      .measureLazyBundleThenAuthorizedMac
    default: .none
    }
  }
}

/// Native-owned bounds on one interpreter realm. A message from the realm cannot attest that cell
/// code stopped, so these limits bound how long code a cell leaves behind can keep running: past
/// the idle period between calls, and past the realm's lifetime at its next call boundary.
public struct PyodideSessionLimits: Sendable, Equatable {
  /// Seconds a ready realm may wait for its next call before it is discarded; nil disables this.
  public let idleSeconds: Double?
  /// Seconds after startup until the realm is discarded at its next call boundary; a running cell
  /// still finishes and returns its result first. Nil disables this.
  public let lifetimeSeconds: Double?

  /// Development defaults: ten idle minutes and one hour per realm. A composition that must keep
  /// an open notebook warm supplies its own limits.
  public static let standard = PyodideSessionLimits(validIdleSeconds: 600, lifetimeSeconds: 3_600)

  /// Each value is nil or a finite number of seconds within 1...86_400.
  public init(idleSeconds: Double?, lifetimeSeconds: Double?) throws {
    for value in [idleSeconds, lifetimeSeconds] {
      if let value, !value.isFinite || !(1...86_400).contains(value) {
        throw PyodideFailure.invalidRequest
      }
    }
    self.init(validIdleSeconds: idleSeconds, lifetimeSeconds: lifetimeSeconds)
  }

  private init(validIdleSeconds: Double?, lifetimeSeconds: Double?) {
    idleSeconds = validIdleSeconds
    self.lifetimeSeconds = lifetimeSeconds
  }
}

/// Advice for a later gate decision, never an executor, authorization or automatic fallback route.
public enum PyodideFallback: String, Sendable, Codable {
  case none
  case measureLazyBundleThenAuthorizedMac
  case authorizedMacRequired
}

/// Timings and configuration for one successful interpreter start, not an aggregate or a device
/// qualification result. Native callback timings and worker-reported import time are kept separate.
public struct PyodideStartup: Sendable, Codable, Equatable {
  /// Native seconds from web-view creation to receipt of the core-ready script callback.
  public let coreSeconds: Double
  /// Worker-reported seconds spent loading the scientific packages and importing the four libraries.
  public let scientificStackSeconds: Double
  /// Native seconds from web-view creation to the validated ready callback, excluding payload hashing.
  public let webViewToReadySeconds: Double
  /// Sum of runtime-file byte counts in the verified manifest, not app download or installed-size delta.
  public let bundledBytes: Int
  /// Pyodide release identifier from the pinned, verified manifest.
  public let pyodideVersion: String
  /// Package versions reported by the worker and checked for exact agreement with that manifest.
  public let packageVersions: [String: String]
  /// Whether a native transport was supplied; this alone proves no grant or network confinement.
  public let networkConfigured: Bool
  /// Recorded Lockdown Mode state; this host refuses enabled mode, so successful starts report false.
  public let lockdownEnabled: Bool
}

enum PyodideLimits {
  static let codeBytes = 256 * 1_024
  static let fileBytes = 16 * 1_024 * 1_024
  static let totalFileBytes = 32 * 1_024 * 1_024
  static let textBytes = 256 * 1_024
  static let files = 32
  static let resultBytes = 48 * 1_024 * 1_024

  static func validate(_ request: PyodideRequest) throws {
    guard !request.code.isEmpty, request.code.utf8.count <= codeBytes,
      request.timeoutSeconds.isFinite, (0.05...900).contains(request.timeoutSeconds),
      request.inputPaths.count <= files, request.outputPaths.count <= files,
      Set(request.inputPaths).count == request.inputPaths.count,
      Set(request.outputPaths).count == request.outputPaths.count
    else { throw PyodideFailure.invalidRequest }
    for path in request.inputPaths + request.outputPaths { _ = try PyodidePath.components(path) }
  }
}

enum PyodidePath {
  static func components(_ path: String) throws -> [String] {
    guard !path.isEmpty, path.utf8.count <= 1_024, !path.hasPrefix("/"),
      !path.contains("\\"), !path.contains(":"),
      !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { throw PyodideFailure.unsafePath }
    let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard parts.count <= 32,
      parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix("~") })
    else { throw PyodideFailure.unsafePath }
    return parts
  }
}
