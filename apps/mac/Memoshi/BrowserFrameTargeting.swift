import AppCore
import Foundation
import WebKit

/// Maps an isolated-world target through real WKJSHandle frame identities. A frame URL or
/// page-provided identifier is never used as authority for native input. Unsupported transforms
/// fail closed rather than sending a click to a guessed location.
///
/// WebKit materializes a handle to a frame's WindowProxy only inside that frame: passed to its
/// parent it arrives as `undefined`. The parent therefore works with a handle to the owner
/// element, and every refresh proves, through a WindowProxy handle taken in the same turn as the
/// geometry, that the element still hosts the document `find` identified.
@MainActor
enum BrowserFrameTargeting {
  @MainActor private struct FrameReply: Sendable { let value: WKFrameInfo? }

  private struct Child: Sendable {
    let window: WKJSHandle
    let element: WKJSHandle
  }

  private struct Geometry: Sendable {
    let values: [Double]
    let window: WKJSHandle
  }

  private struct Link {
    let parent: WKFrameInfo?
    /// The frame's owner element, usable in `parent`'s automation world.
    let element: WKJSHandle
    let docID: String
  }

  static func target(_ target: BrowserTargetPayload, documentID: String, in webView: WKWebView)
    async throws -> (point: CGPoint, viewport: CGSize)
  {
    guard let chain = try await find(documentID: documentID, parent: nil, in: webView, depth: 0)
    else {
      throw BrowserActionError.frameUnavailable
    }
    var x = target.x
    var y = target.y
    for link in chain.reversed() {
      let current = try await refresh(link, in: webView)
      x = current[0] + x * current[2]
      y = current[1] + y * current[3]
      let gate = BrowserResumeGate<Bool>()
      let pointX = x
      let pointY = y
      let verified = try await gate.value(
        timeout: .seconds(3), timeoutError: BrowserActionError.frameUnavailable
      ) {
        webView.callAsyncJavaScript(
          "const node = document.elementFromPoint(x, y); return !!node && node === element;",
          arguments: ["x": pointX, "y": pointY, "element": link.element], in: link.parent,
          in: BrowserAutomationScript.world
        ) { result in
          if case .success(let value) = result, let value = value as? Bool {
            gate.resume(.success(value))
          } else {
            gate.resume(.failure(BrowserActionError.frameUnavailable))
          }
        }
      }
      guard verified else { throw BrowserActionError.obscured }
    }
    let gate = BrowserResumeGate<[Double]>()
    let viewport = try await gate.value(
      timeout: .seconds(3), timeoutError: BrowserActionError.frameUnavailable
    ) {
      webView.callAsyncJavaScript(
        "return [innerWidth, innerHeight];", arguments: [:], in: nil,
        in: BrowserAutomationScript.world
      ) { result in
        if case .success(let value) = result, let values = value as? [Double], values.count == 2 {
          gate.resume(.success(values))
        } else {
          gate.resume(.failure(BrowserActionError.frameUnavailable))
        }
      }
    }
    guard x.isFinite, y.isFinite, x >= 0, y >= 0, x < viewport[0], y < viewport[1] else {
      throw BrowserActionError.outsideViewport
    }
    return (CGPoint(x: x, y: y), CGSize(width: viewport[0], height: viewport[1]))
  }

  private static func find(
    documentID: String, parent: WKFrameInfo?, in webView: WKWebView,
    depth: Int
  ) async throws -> [Link]? {
    guard depth < 8 else { return nil }
    for child in try await children(parent: parent, in: webView) {
      guard let shown = try await identify(child.window, in: webView) else { continue }
      let link = Link(parent: parent, element: child.element, docID: shown.docID)
      if shown.docID == documentID { return [link] }
      if let descendants = try await find(
        documentID: documentID, parent: shown.frame, in: webView, depth: depth + 1)
      {
        return [link] + descendants
      }
    }
    return nil
  }

  /// The frame a WindowProxy handle represents and that frame's isolated-world document
  /// identity; nil when the handle names no frame or the frame answers no identity.
  private static func identify(_ window: WKJSHandle, in webView: WKWebView) async throws
    -> (frame: WKFrameInfo, docID: String)?
  {
    let gate = BrowserResumeGate<FrameReply>()
    let reply = try await gate.value(
      timeout: .seconds(3), timeoutError: BrowserActionError.frameUnavailable
    ) {
      window.getWindowProxyFrame { frame in gate.resume(.success(FrameReply(value: frame))) }
    }
    guard let frame = reply.value else { return nil }
    let json = try? await BrowserScriptCall.run(
      command: "documentId", input: [:], frame: frame,
      in: webView, timeout: .seconds(3))
    guard let json,
      let identity = try? BrowserScriptCall.decode(BrowserDocumentPayload.self, from: json)
    else { return nil }
    return (frame, identity.docId)
  }

  private static func refresh(_ link: Link, in webView: WKWebView) async throws -> [Double] {
    let gate = BrowserResumeGate<Geometry>()
    let geometry = try await gate.value(
      timeout: .seconds(3), timeoutError: BrowserActionError.unsupportedScale
    ) {
      webView.callAsyncJavaScript(
        #"""
        if (!element || !element.isConnected || !element.contentWindow) { return null; }
        for (let node = element; node; node = node.parentElement) {
          const style = getComputedStyle(node);
          const matrix = new DOMMatrixReadOnly(style.transform === 'none' ? undefined : style.transform);
          if (style.display === 'none' || style.visibility !== 'visible' || Number(style.opacity) === 0 ||
              !matrix.is2D || matrix.b !== 0 || matrix.c !== 0 || matrix.a <= 0 || matrix.d <= 0) { return null; }
        }
        element.scrollIntoView({block:'center', inline:'center', behavior:'instant'});
        const rect = element.getBoundingClientRect();
        if (element.offsetWidth <= 0 || element.offsetHeight <= 0) { return null; }
        const sx = rect.width / element.offsetWidth;
        const sy = rect.height / element.offsetHeight;
        return [rect.left + element.clientLeft * sx, rect.top + element.clientTop * sy, sx, sy,
          window.webkit.createJSHandle(element.contentWindow)];
        """#, arguments: ["element": link.element], in: link.parent,
        in: BrowserAutomationScript.world
      ) { result in
        guard case .success(let value) = result, let items = value as? [Any], items.count == 5,
          let values = Array(items.prefix(4)) as? [Double], let window = items[4] as? WKJSHandle,
          values.allSatisfy(\.isFinite), values[2] > 0, values[3] > 0
        else {
          gate.resume(.failure(BrowserActionError.unsupportedScale))
          return
        }
        gate.resume(.success(Geometry(values: values, window: window)))
      }
    }
    // The measured element must still host the identified document.
    guard let shown = try await identify(geometry.window, in: webView), shown.docID == link.docID
    else {
      throw BrowserActionError.frameUnavailable
    }
    return geometry.values
  }

  private static func children(parent: WKFrameInfo?, in webView: WKWebView) async throws
    -> [Child]
  {
    let gate = BrowserResumeGate<[Child]>()
    return try await gate.value(
      timeout: .seconds(3), timeoutError: BrowserActionError.frameUnavailable
    ) {
      webView.callAsyncJavaScript(
        #"""
        const handles = [];
        for (const element of document.querySelectorAll('iframe,frame')) {
          if (!element.contentWindow) { continue; }
          handles.push([window.webkit.createJSHandle(element.contentWindow),
            window.webkit.createJSHandle(element)]);
          if (handles.length === 24) { break; }
        }
        return handles;
        """#, arguments: [:], in: parent, in: BrowserAutomationScript.world
      ) { result in
        guard case .success(let value) = result, let pairs = value as? [[WKJSHandle]],
          pairs.allSatisfy({ $0.count == 2 })
        else {
          gate.resume(.failure(BrowserActionError.frameUnavailable))
          return
        }
        gate.resume(.success(pairs.map { Child(window: $0[0], element: $0[1]) }))
      }
    }
  }
}
