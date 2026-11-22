#if os(iOS)
  import AppCore
  import Foundation
  import Network

  /// App-owned HTTP fixture bound only to this device's loopback. Direct, NOT proxy-covered;
  /// never a real-site, credential-fill, upload-to-network or background qualification.
  @MainActor
  final class MobileBrowserReviewFixture {
    var origin: String {
      get throws {
        guard let port = listener.port else { throw MobileBrowserReviewFailure.fixtureUnavailable }
        return "http://127.0.0.1:\(port.rawValue)"
      }
    }
    private let listener: NWListener
    private var connections: [UUID: NWConnection] = [:]

    private init(listener: NWListener) {
      self.listener = listener
      listener.newConnectionHandler = { [weak self] connection in
        Task { @MainActor in self?.accept(connection) }
      }
    }

    static func start() async throws -> MobileBrowserReviewFixture {
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
      let listener = try NWListener(using: parameters)
      // Network requires the incoming handler before start; the ready callback is too late.
      let fixture = MobileBrowserReviewFixture(listener: listener)
      let gate = BrowserResumeGate<MobileBrowserReviewFixture>()
      defer { listener.stateUpdateHandler = nil }
      do {
        return try await gate.value(
          timeout: .seconds(8), timeoutError: MobileBrowserReviewFailure.scriptTimedOut
        ) {
          listener.stateUpdateHandler = { state in
            Task { @MainActor in
              switch state {
              case .ready:
                guard listener.port != nil else {
                  gate.resume(.failure(MobileBrowserReviewFailure.fixtureUnavailable))
                  return
                }
                gate.resume(.success(fixture))
              case .failed, .cancelled:
                gate.resume(.failure(MobileBrowserReviewFailure.fixtureUnavailable))
              default: break
              }
            }
          }
          listener.start(queue: .main)
        }
      } catch {
        fixture.close()
        throw error
      }
    }

    private func accept(_ connection: NWConnection) {
      let id = UUID()
      connections[id] = connection
      connection.stateUpdateHandler = { [weak self] state in
        switch state {
        case .failed, .cancelled:
          Task { @MainActor in self?.connections.removeValue(forKey: id) }
        default: break
        }
      }
      connection.start(queue: .main)
      receive(connection, id: id, accumulated: Data())
      Task { [weak self, weak connection] in
        do { try await Task.sleep(for: .seconds(10)) } catch { return }
        connection?.cancel()
        self?.connections.removeValue(forKey: id)
      }
    }

    private func receive(_ connection: NWConnection, id: UUID, accumulated: Data) {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
        [weak self] bytes, _, complete, error in
        Task { @MainActor in
          guard let self, self.connections[id] != nil else {
            connection.cancel()
            return
          }
          var buffer = accumulated
          if let bytes { buffer.append(bytes) }
          guard buffer.count <= 32_768, error == nil else {
            connection.cancel()
            return
          }
          if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
            self.respond(connection, request: buffer)
          } else if complete {
            connection.cancel()
          } else {
            self.receive(connection, id: id, accumulated: buffer)
          }
        }
      }
    }

    private func respond(_ connection: NWConnection, request: Data) {
      // Bodies, queries, cookies, filenames and credentials are never reflected or logged.
      let firstLine = String(decoding: request.prefix(2048), as: UTF8.self).components(
        separatedBy: "\r\n")[0]
      let parts = firstLine.split(separator: " ")
      let path = parts.count == 3 && parts[0] == "GET" ? String(parts[1]) : ""
      let body: String
      let status: String
      switch path {
      case "/", "/next":
        body = Self.page(second: path == "/next")
        status = "200 OK"
      case "/frame":
        body = """
          <!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
          <title>Owned child frame</title><body style="font:16px system-ui">
          <label>Frame text <input aria-label="Frame text" autocomplete="off"></label>
          <button type="button" onclick="this.nextElementSibling.textContent=String(++window.frameCount)">Frame count</button>
          <output>0</output><script>window.frameCount=0</script></body></html>
          """
        status = "200 OK"
      default:
        body = "<!doctype html><html lang=\"en\"><body>Fixture request refused.</body></html>"
        status = "405 Method Not Allowed"
      }
      let payload = Data(body.utf8)
      let headers =
        "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(payload.count)\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-src 'self'; form-action 'none'; connect-src 'none'\r\n\r\n"
      connection.send(
        content: Data(headers.utf8) + payload,
        completion: .contentProcessed { _ in connection.cancel() })
    }

    func close() {
      listener.cancel()
      for connection in connections.values { connection.cancel() }
      connections.removeAll()
    }

    private static func page(second: Bool) -> String {
      """
      <!doctype html><html lang="en"><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1"><title>Owned mobile browser fixture</title>
      <style>:root{color-scheme:light dark;font:17px system-ui}body{padding:16px;margin:0}section{margin-block:20px}
      label{display:block;margin-block:12px}input,button,select{font:inherit;max-width:100%}button,a{min-height:44px}
      iframe{width:100%;height:180px}input[type=file]{display:block;width:100%}</style></head><body>
      <h1>\(second ? "Second fixture document" : "Owned mobile fixture")</h1>
      <p>Direct loopback only. No gateway coverage, external requests, sign-in or five-site result.</p>
      <section><label>Fixture text <input aria-label="Fixture text" autocomplete="off"></label>
      <button type="button" id="count">Count clicks</button> <output id="clicks">0</output>
      <label>Fixture choice <select aria-label="Fixture choice"><option>First option</option><option>Second option</option></select></label>
      <p>Last page-observed input: <output id="event">none</output></p></section>
      <section><h2>Staged upload</h2><label>Selected upload <input aria-label="Selected upload" id="upload" type="file" multiple></label>
      <output id="upload-result">No files selected</output><p>Only staged app-owned copies enter this picker. No upload endpoint exists.</p></section>
      <section><h2>Consequential actions stay denied</h2><button type="button">Send message</button>
      <button type="button">Buy item</button></section>
      <section><a href="\(second ? "/" : "/next")">Next fixture document</a></section>
      \(second ? "<button type=\"button\" id=\"history-back\">Try history back</button>" : "")
      <section><h2>Same-origin child frame</h2><iframe title="Owned child frame" src="/frame"></iframe></section>
      <script>
      let count=0;document.getElementById('count').addEventListener('click',()=>{document.getElementById('clicks').textContent=String(++count)});
      document.getElementById('history-back')?.addEventListener('click',()=>history.back());
      for(const type of ['click','input','change'])document.addEventListener(type,event=>{document.getElementById('event').textContent=event.type+(event.isTrusted?' trusted':' untrusted')},true);
      document.getElementById('upload').addEventListener('change',event=>{const files=Array.from(event.target.files||[]);document.getElementById('upload-result').textContent=files.length+' files, '+files.reduce((n,file)=>n+file.size,0)+' bytes';});
      </script></body></html>
      """
    }
  }
#endif
