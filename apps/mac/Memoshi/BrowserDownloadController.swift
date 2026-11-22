import AppCore
import AppKit
import Darwin
import Foundation
import WebKit

/// Explicit, one-use downloads. A suggested page filename is never a filesystem path.
@MainActor
final class BrowserDownloadController: NSObject, WKDownloadDelegate {
  private struct Permit {
    let id: UUID
    let origin: String
    let commit: Int
    let expires: ContinuousClock.Instant
  }
  private struct Transfer {
    let id: UUID
    let download: WKDownload
    var destination: URL?
    var observer: Task<Void, Never>?
  }

  private weak var review: BrowserSessionReview?
  private let profileID: UUID
  private let directory: URL
  private let cap: Int64 = 1_073_741_824
  private var permit: Permit?
  private var transfers: [ObjectIdentifier: Transfer] = [:]

  init(review: BrowserSessionReview, profileID: UUID, directory: URL) {
    self.review = review
    self.profileID = profileID
    self.directory = directory
  }

  func authorize(origin: String, commit: Int) throws -> UUID {
    if let previous = permit {
      record(
        id: previous.id, state: .cancelled, bytes: nil, quarantined: false,
        code: "authorizationReplaced")
    }
    let id = UUID()
    record(id: id, state: .authorized, bytes: nil, quarantined: false, code: nil)
    guard review?.evidence.storageProblem == false else {
      throw BrowserActionError.evidenceUnavailable
    }
    permit = Permit(
      id: id, origin: origin, commit: commit, expires: ContinuousClock.now + .seconds(30))
    return id
  }

  func mayStart(url: URL?, commit: Int) -> Bool {
    guard let permit, let url, let origin = BrowserAuthorization.origin(of: url) else {
      return false
    }
    return permit.commit == commit && ContinuousClock.now < permit.expires
      && permit.origin == origin
  }

  func start(_ download: WKDownload) {
    guard let permit, let session = review?.session,
      mayStart(url: download.originalRequest?.url, commit: session.commitCount)
    else {
      download.cancel(nil)
      record(id: UUID(), state: .refused, bytes: nil, quarantined: false, code: "unstagedDownload")
      return
    }
    self.permit = nil
    let key = ObjectIdentifier(download)
    transfers[key] = Transfer(id: permit.id, download: download)
    download.delegate = self
    transfers[key]?.observer = Task { [weak self, weak download] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(50))
        guard let self, let download, transfers[key] != nil else { return }
        if download.progress.completedUnitCount > cap || download.progress.totalUnitCount > cap {
          cancel(key, code: "downloadTooLarge")
          return
        }
      }
    }
  }

  func download(
    _ download: WKDownload, decideDestinationUsing response: URLResponse,
    suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
  ) {
    let key = ObjectIdentifier(download)
    guard var transfer = transfers[key], response.expectedContentLength <= cap,
      review?.allowsDownloadRedirect(response.url) == true
    else {
      completionHandler(nil)
      cancel(key, code: "downloadRefused")
      return
    }
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      // Keep the page's extension only when it is a small plain ASCII extension. The basename
      // is app-generated, and downloaded executables are never opened or run automatically.
      let ext = URL(fileURLWithPath: suggestedFilename).pathExtension
      let suffix =
        !ext.isEmpty && ext.utf8.count <= 12
          && ext.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
          }) ? "." + ext : ""
      let url = directory.appendingPathComponent(transfer.id.uuidString + suffix)
      transfer.destination = url
      transfers[key] = transfer
      completionHandler(url)
    } catch {
      completionHandler(nil)
      cancel(key, code: "downloadStorageUnavailable")
    }
  }

  func download(
    _ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    decisionHandler: @escaping @MainActor @Sendable (WKDownload.RedirectPolicy) -> Void
  ) {
    decisionHandler(review?.allowsDownloadRedirect(request.url) == true ? .allow : .cancel)
  }

  func download(
    _ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    completionHandler(
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
        ? .performDefaultHandling : .rejectProtectionSpace, nil)
  }

  func downloadDidFinish(_ download: WKDownload) {
    let key = ObjectIdentifier(download)
    guard let transfer = transfers.removeValue(forKey: key) else { return }
    transfer.observer?.cancel()
    guard let url = transfer.destination else {
      record(
        id: transfer.id, state: .failed, bytes: nil, quarantined: false, code: "missingDestination")
      return
    }
    let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    var status = stat()
    var quarantined = false
    if fd >= 0 {
      defer { _ = Darwin.close(fd) }
      if fstat(fd, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
        status.st_nlink == 1, status.st_uid == getuid(), status.st_size <= cap,
        fchmod(fd, 0o600) == 0
      {
        let attribute =
          "0083;\(String(Int(Date().timeIntervalSince1970), radix: 16));Memoshi;\(transfer.id.uuidString)"
        quarantined = attribute.withCString { value in
          fsetxattr(fd, "com.apple.quarantine", value, strlen(value), 0, 0) == 0
        }
      }
    }
    guard quarantined else {
      try? FileManager.default.removeItem(at: url)
      record(
        id: transfer.id, state: .failed, bytes: nil, quarantined: false,
        code: "downloadValidationFailed")
      return
    }
    record(id: transfer.id, state: .completed, bytes: status.st_size, quarantined: true, code: nil)
    review?.collectGatewayEvidence()
  }

  func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
    let key = ObjectIdentifier(download)
    guard let transfer = transfers.removeValue(forKey: key) else { return }
    transfer.observer?.cancel()
    if let destination = transfer.destination {
      try? FileManager.default.removeItem(at: destination)
    }
    record(id: transfer.id, state: .failed, bytes: nil, quarantined: false, code: "downloadFailed")
    // Resume data is intentionally discarded. No automatic action retry is allowed.
  }

  func close(code: String = "sessionClosed") {
    if let permit {
      record(
        id: permit.id, state: .cancelled, bytes: nil, quarantined: false, code: code)
    }
    permit = nil
    for key in Array(transfers.keys) { cancel(key, code: code) }
  }

  private func cancel(_ key: ObjectIdentifier, code: String) {
    guard let transfer = transfers.removeValue(forKey: key) else { return }
    transfer.observer?.cancel()
    transfer.download.cancel { _ in
      if let destination = transfer.destination {
        try? FileManager.default.removeItem(at: destination)
      }
    }
    record(id: transfer.id, state: .cancelled, bytes: nil, quarantined: false, code: code)
  }

  private func record(
    id: UUID, state: BrowserReviewEvidence.Download.State, bytes: Int64?,
    quarantined: Bool, code: String?
  ) {
    review?.evidence.record(
      BrowserReviewEvidence.Download(
        id: id, profileID: profileID, at: Date(),
        state: state, bytes: bytes, quarantined: quarantined, code: code))
  }
}
