#if os(iOS)
  import AppCore
  import Foundation
  import WebKit

  /// Content-free failures: raw WebKit/JavaScript/Keychain diagnostics never enter the UI journal.
  enum MobileBrowserReviewFailure: String, Error, Sendable {
    case unavailable, busy, closed, inactive, invalidResult, scriptFailed, scriptTimedOut
    case staleDocument, frameUnavailable, originMismatch, fixtureUnavailable, noSnapshot
    case nativeHandoffRequired, noTrustedEventObserved, credentialField, uploadNotStaged
    case snapshotsDisabledAfterSecretRelease, keychainNotConfigured, unsupportedOperation
    case profileRegistryUnavailable
  }

  enum MobileBrowserReviewLevel: String, CaseIterable, Identifiable {
    case readOnly, signIn, interact
    var id: Self { self }
    var title: LocalizedStringResource {
      switch self {
      case .readOnly: "Read Only"
      case .signIn: "Sign In"
      case .interact: "Interact"
      }
    }
  }

  struct MobileBrowserReviewElement: Decodable, Identifiable, Hashable, Sendable {
    let ref: String
    let role: String
    let name: String
    // Values are deliberately not decoded: this review has no browser_read/eval escape hatch.
    let masked: Bool
    let editable: Bool
    let sensitive: Bool
    let submit: Bool
    let selectable: Bool
    let picker: Bool
    let states: [String]
    var frameID = ""
    var id: String { frameID + ":" + ref }
    private enum CodingKeys: String, CodingKey {
      case ref, role, name, masked, editable, sensitive, submit, selectable, picker, states
    }
  }

  struct MobileBrowserReviewSnapshot: Sendable {
    struct Ancestor: Sendable {
      let parent: WKFrameInfo?
      let parentDocumentID: String
      let child: WKJSHandle
    }
    struct Frame: Sendable {
      let documentID: String
      let origin: String
      let info: WKFrameInfo?
      let ancestors: [Ancestor]
    }
    let id: Int
    let commit: Int
    let frames: [Frame]
    let elements: [MobileBrowserReviewElement]
    let skippedFrames: Int
    let truncated: Bool
  }

  struct MobileBrowserReviewSnapshotPayload: Decodable, Sendable {
    let docId: String
    let elements: [MobileBrowserReviewElement]
    let total: Int
    let truncated: Bool
  }
  struct MobileBrowserReviewDocument: Decodable, Sendable { let docId: String }
  struct MobileBrowserReviewAction: Decodable, Sendable {
    let docId: String
    let origin: String
    let destination: String?
    let method: String?
    let label: String
    let payment: Bool
    let link: Bool
    let file: Bool
  }
  struct MobileBrowserReviewTarget: Decodable, Sendable {
    let sensitive: Bool
    let editable: Bool
    let submit: Bool
    let picker: Bool
    let file: Bool
  }
  struct MobileBrowserReviewPicker: Decodable, Sendable {
    let matches: Bool
    let docId: String
    let origin: String
  }
  struct MobileBrowserReviewForm: Decodable, Sendable {
    let origin: String
    let usernameRef: String
    let passwordRef: String
  }
  struct MobileBrowserReviewFill: Decodable, Sendable {
    let usernameMatches: Bool
    let passwordMatches: Bool
    let masked: Int
  }
  struct MobileBrowserReviewOK: Decodable, Sendable { let ok: Bool }
  struct MobileBrowserReviewMark: Decodable, Sendable { let mark: Int }
  struct MobileBrowserReviewEvents: Decodable, Sendable {
    struct Event: Decodable, Sendable {
      let type: String
      let trusted: Bool
      let onTarget: Bool
    }
    let events: [Event]
  }

  /// The journal contains no page text, URLs, input, account references, cookies or errors.
  struct MobileBrowserReviewObservation: Identifiable, Sendable {
    enum Kind: String, Sendable {
      case route, navigation, snapshot, input, upload, secret, lifecycle, isolation, recipe
    }
    let id = UUID()
    let at = Date()
    let kind: Kind
    let code: String
    let count: Int
  }

  @MainActor
  enum MobileBrowserReviewScript {
    private struct Failure: Decodable { let error: String? }

    static func children(frame: WKFrameInfo?, webView: WKWebView) async throws -> [WKJSHandle] {
      let gate = BrowserResumeGate<[WKJSHandle]>()
      return try await gate.value(
        timeout: .seconds(8), timeoutError: MobileBrowserReviewFailure.scriptTimedOut
      ) {
        webView.callAsyncJavaScript(
          """
          return Array.from(document.querySelectorAll('iframe,frame')).slice(0,16)
            .filter(node => node.contentWindow).map(node => window.webkit.createJSHandle(node.contentWindow));
          """, arguments: [:], in: frame, in: BrowserAutomationScript.world
        ) { result in
          if case .success(let value) = result, let handles = value as? [WKJSHandle] {
            gate.resume(.success(handles))
          } else {
            gate.resume(.failure(MobileBrowserReviewFailure.frameUnavailable))
          }
        }
      }
    }

    static func verifyFrame(
      _ ancestor: MobileBrowserReviewSnapshot.Ancestor, scroll: Bool,
      webView: WKWebView
    ) async throws {
      let gate = BrowserResumeGate<Bool>()
      let present = try await gate.value(
        timeout: .seconds(8), timeoutError: MobileBrowserReviewFailure.scriptTimedOut
      ) {
        webView.callAsyncJavaScript(
          "return globalThis.__memoshiMobileGuard.frame({child,expectedDocument,scroll}).ok === true;",
          arguments: [
            "child": ancestor.child, "expectedDocument": ancestor.parentDocumentID,
            "scroll": scroll,
          ],
          in: ancestor.parent, in: BrowserAutomationScript.world
        ) { result in
          if case .success(let value) = result, let present = value as? Bool {
            gate.resume(.success(present))
          } else {
            gate.resume(.failure(MobileBrowserReviewFailure.frameUnavailable))
          }
        }
      }
      guard present else { throw MobileBrowserReviewFailure.frameUnavailable }
    }

    static func call<Payload: Decodable & Sendable>(
      _ type: Payload.Type, command: String,
      input: [String: Any] = [:], frame: WKFrameInfo? = nil, webView: WKWebView,
      guardCall: Bool = false
    ) async throws -> Payload {
      let gate = BrowserResumeGate<String>()
      let json = try await gate.value(
        timeout: .seconds(8), timeoutError: MobileBrowserReviewFailure.scriptTimedOut
      ) {
        webView.callAsyncJavaScript(
          guardCall
            ? "return JSON.stringify(globalThis.__memoshiMobileGuard[command](input));"
            : BrowserAutomationScript.dispatchBody,
          arguments: ["command": command, "input": input], in: frame,
          in: BrowserAutomationScript.world
        ) { result in
          if case .success(let value) = result, let json = value as? String,
            json.utf8.count <= 1_000_000
          {
            gate.resume(.success(json))
          } else {
            gate.resume(.failure(MobileBrowserReviewFailure.scriptFailed))
          }
        }
      }
      let bytes = Data(json.utf8)
      if let failure = try? JSONDecoder().decode(Failure.self, from: bytes), failure.error != nil {
        // Never forward arbitrary script error strings, even from our own isolated library.
        throw MobileBrowserReviewFailure.staleDocument
      }
      guard let payload = try? JSONDecoder().decode(type, from: bytes) else {
        throw MobileBrowserReviewFailure.invalidResult
      }
      return payload
    }

    static func code(_ error: any Error) -> String {
      if let error = error as? MobileBrowserReviewFailure { return error.rawValue }
      if let error = error as? BrowserAuthorization.Denial { return error.rawValue }
      if let error = error as? BrowserUploadError { return error.rawValue }
      if let error = error as? BrowserKeychainError { return error.rawValue }
      return error is CancellationError ? "cancelled" : "unavailable"
    }
  }
#endif
