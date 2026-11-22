#if os(iOS)
  import AppCore
  import Foundation
  import UIKit
  import WebKit

  @MainActor
  final class MobileBrowserReviewDelegate: NSObject, WKNavigationDelegate, WKUIDelegate,
    WKScriptMessageHandler
  {
    weak var session: MobileBrowserReviewSession?

    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      session?.receive(message)
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
      guard let session else {
        decisionHandler(.cancel)
        return
      }
      Task {
        let denial = await session.navigationDenial(action)
        if let denial {
          session.record(.navigation, denial)
          session.problem = denial
        }
        decisionHandler(denial == nil ? .allow : .cancel)
      }
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
      decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
      // The action policy admits the offline fixture's opaque data frame; its response has no
      // origin to compare.
      guard let session, !session.closed, session.active, !session.networkFrozen,
        response.canShowMIMEType,
        response.response.url.flatMap(BrowserAuthorization.origin(of:)) == session.site.origin
          || (session.route == .offlineDocument && !response.isForMainFrame
            && response.response.url?.scheme == "data"),
        (response.response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true
      else {
        self.session?.record(.navigation, "responseOrDownloadDenied")
        decisionHandler(.cancel)
        return
      }
      decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
      guard let session else { return }
      session.loading = true
      session.invalidate(cancelWork: true)
      session.record(.navigation, "provisionalStartObserved")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
      guard let session else { return }
      session.commit += 1
      session.invalidate(cancelWork: true)
      session.formPermit = nil
      // Only a commit replaces the document. A provisional navigation that fails or is denied
      // leaves the registered document displayed, and it must stay snapshottable.
      session.registrations.removeAll()
      session.record(.navigation, "mainDocumentCommitObserved", count: session.commit)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
      session?.loading = false
      session?.allowingOfflineLoad = false
      session?.record(.navigation, "navigationFinishedObserved")
      session?.collectGateway()
    }

    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?,
      withError error: any Error
    ) {
      failed()
    }

    func webView(
      _ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error
    ) {
      failed()
    }

    private func failed() {
      session?.loading = false
      session?.allowingOfflineLoad = false
      session?.formPermit = nil
      session?.invalidate(cancelWork: true)
      session?.problem = "navigationFailed"
      session?.record(.navigation, "navigationFailedNoAutomaticRetry")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      session?.loading = false
      session?.invalidate(cancelWork: true)
      session?.problem = "contentProcessTerminated"
      session?.record(.lifecycle, "contentProcessTerminatedNoAutomaticReplay")
    }

    func webView(
      _ webView: WKWebView, shouldGoTo item: WKBackForwardListItem,
      willUseInstantBack: Bool, completionHandler: @escaping (Bool) -> Void
    ) {
      // No implicit suspended-document resurrection can revive refs, file or secret permits.
      session?.record(.navigation, "historyNavigationDenied")
      completionHandler(false)
    }

    func webView(
      _ webView: WKWebView, willSubmitForm formInfo: WKFormInfo,
      submissionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
      // Never access WKFormInfo's value dictionary.
      guard let session, let permit = session.formPermit, permit.navigationApproved,
        !session.closed, session.active, !session.networkFrozen,
        session.commit == permit.binding.commit, ContinuousClock.now < permit.expires,
        BrowserAuthorization.origin(of: formInfo.sourceFrame.securityOrigin)
          == permit.binding.origin,
        formInfo.httpMethod.uppercased() == permit.method,
        session.formDestinationMatches(
          permit.destination, request: formInfo.submissionURL, method: permit.method),
        BrowserAuthorization.denial(
          action: .init(
            method: permit.method, destination: formInfo.submissionURL,
            label: "", containsPaymentFields: false, isForm: true),
          sourceOrigin: permit.binding.origin,
          sites: [session.site], privateData: session.privateData) == nil
      else {
        session?.formPermit = nil
        session?.record(.navigation, "unapprovedFormDenied")
        webView.stopLoading()
        // SDK 27 has a continue-only callback; denied forms never invoke it. The navigation
        // policy already rejects unapproved submissions before this continuation is offered.
        return
      }
      session.formPermit = nil
      Task {
        do {
          let document = try await MobileBrowserReviewScript.call(
            MobileBrowserReviewDocument.self,
            command: "documentId", frame: formInfo.sourceFrame, webView: webView)
          guard !session.closed, session.active, !session.networkFrozen,
            session.commit == permit.binding.commit, ContinuousClock.now < permit.expires,
            document.docId == permit.binding.documentID
          else { throw BrowserAuthorization.Denial.staleDocument }
          session.record(.navigation, "exactApprovedFormContinued")
          submissionHandler()
        } catch {
          session.record(.navigation, MobileBrowserReviewScript.code(error))
          webView.stopLoading()
        }
      }
    }

    func webView(
      _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
      initiatedByFrame frame: WKFrameInfo,
      completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
      guard let session else {
        completionHandler(nil)
        return
      }
      session.openPanel(parameters, frame: frame, completion: completionHandler)
    }

    func webView(
      _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
      completionHandler:
        @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
      if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
        completionHandler(.performDefaultHandling, nil)
      } else {
        completionHandler(.rejectProtectionSpace, nil)
      }
    }

    func webView(
      _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? { nil }

    func webView(
      _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
      initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
      decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) { decisionHandler(.deny) }

    func webView(
      _ webView: WKWebView, requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
      initiatedByFrame frame: WKFrameInfo,
      decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) { decisionHandler(.deny) }

    func webView(
      _ webView: WKWebView, requestGeolocationPermissionFor origin: WKSecurityOrigin,
      initiatedByFrame frame: WKFrameInfo,
      decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) { decisionHandler(.deny) }

    func webView(
      _ webView: WKWebView,
      contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
      completionHandler: @escaping @MainActor @Sendable (UIContextMenuConfiguration?) -> Void
    ) { completionHandler(nil) }

    func webView(_ webView: WKWebView, insertInputSuggestion inputSuggestion: UIInputSuggestion) {
      session?.record(.input, "autofillSuggestionDenied")
    }

    func webView(
      _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
      initiatedByFrame frame: WKFrameInfo,
      completionHandler: @escaping @MainActor @Sendable () -> Void
    ) { completionHandler() }

    func webView(
      _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
      initiatedByFrame frame: WKFrameInfo,
      completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) { completionHandler(false) }

    func webView(
      _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
      defaultText: String?, initiatedByFrame frame: WKFrameInfo,
      completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) { completionHandler(nil) }
  }

  @MainActor
  extension MobileBrowserReviewSession {
    func navigationDenial(_ action: WKNavigationAction) async -> String? {
      guard !closed, active, !networkFrozen else { return "inactiveOrFrozenNavigationDenied" }
      guard action.targetFrame != nil, !action.shouldPerformDownload, let url = action.request.url
      else {
        return "popupOrDownloadDenied"
      }
      let method = (action.request.httpMethod ?? "GET").uppercased()
      if route == .offlineDocument {
        if allowingOfflineLoad, action.targetFrame?.isMainFrame == true, method == "GET",
          url.absoluteString == "about:blank" || BrowserAuthorization.origin(of: url) == site.origin
        {
          return nil
        }
        // The shared offline fixture includes an intentionally opaque, read-only data frame.
        if action.targetFrame?.isMainFrame == false, url.scheme == "data", method == "GET" {
          return nil
        }
        return "offlineDocumentExternalNavigationDenied"
      }
      guard BrowserAuthorization.origin(of: url) == site.origin else { return "siteNotGranted" }
      let isForm =
        action.navigationType == .formSubmitted || action.navigationType == .formResubmitted
      if isForm || method != "GET" {
        guard var permit = formPermit, !permit.navigationApproved, commit == permit.binding.commit,
          ContinuousClock.now < permit.expires, method == permit.method,
          BrowserAuthorization.origin(of: action.sourceFrame.securityOrigin)
            == permit.binding.origin,
          formDestinationMatches(permit.destination, request: url, method: method)
        else { return "unapprovedFormDenied" }
        let facts = BrowserAuthorization.Action(
          method: method, destination: url, label: "",
          containsPaymentFields: false, isForm: true)
        if let denial = BrowserAuthorization.denial(
          action: facts, sourceOrigin: permit.binding.origin,
          sites: [site], privateData: privateData)
        {
          return denial.rawValue
        }
        do {
          let document = try await MobileBrowserReviewScript.call(
            MobileBrowserReviewDocument.self,
            command: "documentId", frame: action.sourceFrame, webView: webView)
          guard !closed, active, !networkFrozen, commit == permit.binding.commit,
            document.docId == permit.binding.documentID,
            formPermit?.binding == permit.binding, formPermit?.navigationApproved == false
          else { return "staleDocument" }
          try permit.permit.consume(for: permit.binding)
        } catch { return MobileBrowserReviewScript.code(error) }
        permit.navigationApproved = true
        formPermit = permit
      }
      return nil
    }

    func formDestinationMatches(_ staged: URL, request: URL, method: String) -> Bool {
      method == "GET"
        ? BrowserAuthorization.origin(of: staged) == BrowserAuthorization.origin(of: request)
          && staged.path == request.path
        : staged == request
    }
  }
#endif
