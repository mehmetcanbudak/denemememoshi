import Foundation
import WebKit

/// The scheme serves only sealed app assets. There is deliberately no bot-file/network endpoint.
@MainActor
final class PyodideSchemeHandler: NSObject, WKURLSchemeHandler {
  static let scheme = "memoshi-pyodide"
  static let hostURL: URL = {
    guard let url = URL(string: "memoshi-pyodide://runtime/host.html") else {
      preconditionFailure("The sealed Pyodide host URL must be valid")
    }
    return url
  }()
  private let payload: PyodidePayload

  init(payload: PyodidePayload) {
    self.payload = payload
  }

  func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
    do {
      let request = urlSchemeTask.request
      guard request.httpMethod == nil || request.httpMethod == "GET",
        let url = request.url, url.scheme == Self.scheme, url.host == "runtime",
        url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil
      else { throw PyodideFailure.unsafePath }
      let relative = String(url.path.dropFirst())
      _ = try PyodidePath.components(relative)
      guard payload.allowedPaths.contains(relative) else { throw PyodideFailure.fileUnavailable }
      var bytes = try Data(
        contentsOf: payload.resources.appendingPathComponent(relative), options: .mappedIfSafe)
      let policy = Self.contentSecurityPolicy(allowsWorker: relative == "host.html")
      if relative == "host.html" {
        let html = String(decoding: bytes, as: UTF8.self)
          .replacingOccurrences(of: "__MEMOSHI_CSP__", with: policy)
        bytes = Data(html.utf8)
      }
      guard
        let response = HTTPURLResponse(
          url: url, statusCode: 200, httpVersion: "HTTP/1.1",
          headerFields: [
            "Content-Type": Self.mimeType(relative), "Content-Length": String(bytes.count),
            "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store",
            "Content-Security-Policy": policy, "X-Content-Type-Options": "nosniff",
            "Referrer-Policy": "no-referrer",
          ])
      else { throw PyodideFailure.fileUnavailable }
      urlSchemeTask.didReceive(response)
      urlSchemeTask.didReceive(bytes)
      urlSchemeTask.didFinish()
    } catch {
      urlSchemeTask.didFailWithError(PyodideFailure.fileUnavailable)
    }
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
    // Responses above are synchronous immutable reads; no asynchronous task survives a stop.
  }

  static func contentSecurityPolicy(allowsWorker: Bool) -> String {
    let workers = allowsWorker ? "blob:" : "'none'"
    return "default-src 'none'; script-src memoshi-pyodide: 'unsafe-eval' 'wasm-unsafe-eval'; "
      + "connect-src memoshi-pyodide:; worker-src \(workers); frame-src 'none'; "
      + "object-src 'none'; base-uri 'none'; form-action 'none'"
  }

  private static func mimeType(_ path: String) -> String {
    if path.hasSuffix(".html") { return "text/html; charset=utf-8" }
    if path.hasSuffix(".mjs") { return "text/javascript; charset=utf-8" }
    if path.hasSuffix(".wasm") { return "application/wasm" }
    if path.hasSuffix(".json") { return "application/json" }
    if path.hasSuffix(".py") { return "text/plain; charset=utf-8" }
    if path.hasSuffix(".whl") || path.hasSuffix(".zip") { return "application/zip" }
    return "text/plain; charset=utf-8"
  }
}
