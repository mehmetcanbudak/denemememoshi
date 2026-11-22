import CryptoKit
import Foundation

/// The ledger's reply to one attempt.
package struct EffectReceipt: Codable, Equatable, Sendable {
  /// What the ledger did.
  package var disposition: EffectDisposition
  /// The attempt's own sequence.
  package var seq: Int
  /// The sequence that originally recorded this key.
  package var effectSeq: Int
}

/// Per-run bearer authority. Only SHA-256 digests are held; tokens never reach the journal.
package actor EffectLedgerAuthority {
  private var digests: [String: Data] = [:]

  package init() {}

  /// Registers the digest of the token a run's tool will present.
  package func register(run: String, tokenSHA256 hex: String) throws {
    guard let digest = Data(hexadecimal: hex), digest.count == 32, !run.isEmpty else {
      throw EffectLedgerRequestError.invalid
    }
    digests[run] = digest
  }

  /// Checks an `Authorization: Bearer` value for the run without retaining it.
  package func authorize(run: String, authorization: String?) throws {
    guard let expected = digests[run] else { throw EffectLedgerRequestError.unknownRun }
    guard let authorization, authorization.hasPrefix("Bearer "),
      Data(SHA256.hash(data: Data(authorization.dropFirst(7).utf8))) == expected
    else { throw EffectLedgerRequestError.unauthorized }
  }
}

/// Request refusals, mapped to HTTP statuses without echoing request content.
package enum EffectLedgerRequestError: Error, Equatable {
  /// Malformed or out-of-bounds input (400).
  case invalid
  /// Missing or wrong bearer token (401).
  case unauthorized
  /// The run was never registered (403).
  case unknownRun
}

/// HTTP routes over one ledger store. Loopback only; see ``LoopbackHTTPServer``.
package struct EffectLedgerRoutes: Sendable {
  let store: EffectLedgerStore
  let authority: EffectLedgerAuthority

  package init(store: EffectLedgerStore, authority: EffectLedgerAuthority) {
    self.store = store
    self.authority = authority
  }

  /// `POST /v1/effects`, `GET /v1/effects?run=`, `GET /v1/summary`, `GET /v1/health`.
  package func handle(_ request: LoopbackHTTPRequest, _ responder: LoopbackHTTPResponder) async {
    switch (request.method, request.path) {
    case ("POST", "/v1/effects"):
      do {
        let attempt = try JSONDecoder().decode(EffectAttempt.self, from: request.body)
        guard Self.bounded(attempt.key), Self.bounded(attempt.run), Self.bounded(attempt.step),
          Self.bounded(attempt.payloadHash)
        else { throw EffectLedgerRequestError.invalid }
        try await authority.authorize(
          run: attempt.run, authorization: request.header("Authorization"))
        let record = try await store.submit(attempt)
        let status: Int
        switch record.disposition {
        case .recorded: status = 201
        case .replayed: status = 200
        case .conflict: status = 409
        }
        await responder.json(
          status,
          encoding: EffectReceipt(
            disposition: record.disposition, seq: record.seq, effectSeq: record.effectSeq))
      } catch EffectLedgerRequestError.unauthorized {
        await responder.json(401, Data(#"{"error":"unauthorized"}"#.utf8))
      } catch EffectLedgerRequestError.unknownRun {
        await responder.json(403, Data(#"{"error":"unknown_run"}"#.utf8))
      } catch is EffectLedgerError {
        await responder.json(500, Data(#"{"error":"journal"}"#.utf8))
      } catch {
        await responder.json(400, Data(#"{"error":"invalid"}"#.utf8))
      }
    case ("GET", "/v1/effects"):
      guard let run = request.query["run"], Self.bounded(run) else {
        await responder.json(400, Data(#"{"error":"invalid"}"#.utf8))
        return
      }
      await responder.json(200, encoding: await store.attempts(run: run))
    case ("GET", "/v1/summary"):
      await responder.json(200, encoding: await store.summary())
    case ("GET", "/v1/health"):
      await responder.json(200, Data(#"{"ok":true}"#.utf8))
    default:
      await responder.json(404, Data(#"{"error":"not_found"}"#.utf8))
    }
  }

  private static func bounded(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 512 }
}

/// A control line on the ledger process's stdin. EOF stops the ledger normally.
package struct EffectLedgerControl: Codable, Sendable {
  /// Only `register` exists.
  package var op: String
  /// The run being registered.
  package var run: String
  /// Hex SHA-256 of the run's bearer token.
  package var tokenSHA256: String

  package init(run: String, tokenSHA256: String) {
    op = "register"
    self.run = run
    self.tokenSHA256 = tokenSHA256
  }
}

/// The ledger as its own process: binds an OS-chosen loopback port, writes `ledger.port`,
/// journals into `effects.jsonl`, accepts run registrations on stdin and stops on stdin EOF.
package enum EffectLedgerProcess {
  /// The port file name inside the ledger directory.
  package static let portFileName = "ledger.port"
  /// The journal file name inside the ledger directory.
  package static let journalFileName = "effects.jsonl"

  /// Runs until stdin closes and returns the process exit status.
  package static func run(directory: URL) async -> Int32 {
    let output = LineWriter.standardOutput
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      let store = try EffectLedgerStore(directory: directory)
      let authority = EffectLedgerAuthority()
      let routes = EffectLedgerRoutes(store: store, authority: authority)
      let server = try await LoopbackHTTPServer.start { request, responder in
        await routes.handle(request, responder)
      }
      try Data("\(server.port)\n".utf8).write(
        to: directory.appendingPathComponent(portFileName), options: .atomic)
      output.emit(["event": "listening", "port": String(server.port)])
      for await line in LineStream.lines(from: STDIN_FILENO, closeAtEnd: false) {
        guard
          let control = try? JSONDecoder().decode(
            EffectLedgerControl.self, from: Data(line.utf8)),
          control.op == "register"
        else {
          output.emit(["event": "rejected"])
          continue
        }
        do {
          try await authority.register(run: control.run, tokenSHA256: control.tokenSHA256)
          output.emit(["event": "registered", "run": control.run])
        } catch {
          output.emit(["event": "rejected", "run": control.run])
        }
      }
      await server.close()
      let summary = await store.summary()
      output.emit([
        "event": "stopped", "attempts": String(summary.total.attempts),
        "effects": String(summary.total.effects), "duplicates": String(summary.total.duplicates),
      ])
      return 0
    } catch {
      output.emit(["event": "failed", "error": String(describing: error)])
      return 1
    }
  }
}

/// A loopback client for the tool and the driver.
package struct EffectLedgerClient: Sendable {
  /// `http://127.0.0.1:<port>`.
  package let baseURL: URL
  private let session: URLSession

  package init(port: Int) {
    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = port
    baseURL = components.url ?? URL(fileURLWithPath: "/")
    session = URLSession(configuration: .ephemeral)
  }

  /// Reads the OS-chosen port the ledger wrote.
  package static func port(in directory: URL) throws -> Int {
    let text = try String(
      contentsOf: directory.appendingPathComponent(EffectLedgerProcess.portFileName),
      encoding: .utf8)
    guard let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else {
      throw EffectLedgerRequestError.invalid
    }
    return port
  }

  /// Posts one attempt. Any refusal other than a replay of the same body throws.
  package func post(_ attempt: EffectAttempt, bearer: String) async throws -> EffectReceipt {
    var request = URLRequest(url: baseURL.appendingPathComponent("v1/effects"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(attempt)
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    switch status {
    case 200, 201, 409: return try JSONDecoder().decode(EffectReceipt.self, from: data)
    case 401: throw EffectLedgerRequestError.unauthorized
    case 403: throw EffectLedgerRequestError.unknownRun
    default: throw EffectLedgerRequestError.invalid
    }
  }

  /// Every attempt the ledger holds for one run.
  package func attempts(run: String) async throws -> [EffectLedgerRecord] {
    var components = URLComponents(
      url: baseURL.appendingPathComponent("v1/effects"), resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "run", value: run)]
    guard let url = components?.url else { throw EffectLedgerRequestError.invalid }
    let (data, _) = try await session.data(from: url)
    return try JSONDecoder().decode([EffectLedgerRecord].self, from: data)
  }

  /// Totals across the whole ledger.
  package func summary() async throws -> EffectLedgerSummary {
    let (data, _) = try await session.data(from: baseURL.appendingPathComponent("v1/summary"))
    return try JSONDecoder().decode(EffectLedgerSummary.self, from: data)
  }
}

extension Data {
  /// Parses lowercase or uppercase hexadecimal; nil for odd lengths or other characters.
  init?(hexadecimal text: String) {
    let digits = Array(text.utf8)
    guard digits.count.isMultiple(of: 2) else { return nil }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(digits.count / 2)
    func value(_ digit: UInt8) -> UInt8? {
      switch digit {
      case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
      case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
      case UInt8(ascii: "A")...UInt8(ascii: "F"): digit - UInt8(ascii: "A") + 10
      default: nil
      }
    }
    var index = 0
    while index < digits.count {
      guard let high = value(digits[index]), let low = value(digits[index + 1]) else { return nil }
      bytes.append(high << 4 | low)
      index += 2
    }
    self.init(bytes)
  }

  /// Lowercase hexadecimal.
  var hexadecimal: String { map { String(format: "%02x", $0) }.joined() }
}
