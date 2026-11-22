// Non-shipping helper for the signed replay qualification (`scripts/run-replay-qualification.sh`).
// It must be signed as `com.mehmetcanbudak.memoshi.memoshid`; `DaemonServer` refuses otherwise.
//   memoshi-replay-daemon serve --data DIR --schema FILE   one daemon life; commands on stdin
//   memoshi-replay-daemon verify --data DIR                folds a stopped store from seq 0
import Foundation
import MemoshiDaemon
import MemoshiProtocol
import MemoshiReplayKit
import MemoshiStore
import MemoshiTransport

setvbuf(stdout, nil, _IOLBF, 0)
let arguments = CommandLine.arguments
func value(_ flag: String) -> String? {
  arguments.firstIndex(of: flag).flatMap {
    arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
  }
}
guard arguments.count > 1, let data = value("--data") else {
  FileHandle.standardError.write(Data("usage: serve|verify --data DIR [--schema FILE]\n".utf8))
  exit(64)
}
let directory = URL(fileURLWithPath: data, isDirectory: true)

do {
  switch arguments[1] {
  case "serve":
    guard let schema = value("--schema") else { exit(64) }
    let identity = try PeerAuthentication.currentIdentity()
    let configuration = try DaemonConfiguration(
      dataDirectory: directory, version: "replay", build: "1",
      canonicalSchema: Data(contentsOf: URL(fileURLWithPath: schema)))
    let server = try DaemonServer(configuration: configuration)
    try await server.start()
    print("READY pid=\(getpid()) id=\(identity.signingIdentifier) team=\(identity.teamID)")
    // One command per line: `retention DAYS` commits one durable settings event and answers it.
    for try await line in FileHandle.standardInput.bytes.lines {
      let words = line.split(separator: " ")
      guard words.count == 2, words[0] == "retention", let days = Int(words[1]) else {
        print("ERROR \(line)")
        continue
      }
      let events = try await server.setEventRetentionDays(days)
      print("COMMIT " + (try events.first.map(ReplayWire.encode) ?? "none"))
    }
    // EOF is the owner ending this life: a graceful stop commits `system.stopping`.
    try await server.stop(reason: .user)
    let store = try Store(directory: directory)
    let head = try await store.replayBounds().head
    let page = try await store.replay(after: head - 1)
    try await store.close()
    print("STOP " + (try page.events.last.map(ReplayWire.encode) ?? "none"))
  case "verify":
    let store = try Store(directory: directory)
    var chain = ReplayChain()
    var after: Int64 = 0
    var duplicates = 0
    var gaps = 0
    let bounds = try await store.replayBounds()
    while after < bounds.head {
      let page = try await store.replay(after: after, through: bounds.head)
      for event in page.events {
        switch try chain.append(event) {
        case .next: break
        case .duplicate: duplicates += 1
        case .gap: gaps += 1
        }
      }
      after = page.nextAfter
    }
    print(
      "FOLD head=\(bounds.head) min=\(bounds.minRetainedSeq) count=\(chain.count) chain=\(chain.hex)"
        + " duplicates=\(duplicates) gaps=\(gaps) schema=\(Store.schemaVersion)"
        + " retention=\(try await store.eventRetentionDays()) device=\(store.deviceID.rawValue)")
    try await store.close()
  default:
    exit(64)
  }
} catch {
  FileHandle.standardError.write(Data("error: \(error)\n".utf8))
  exit(1)
}
