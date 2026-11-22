import AppCore
import Foundation
import WebKit

// Value types for the native S3 browser review lab. Page-derived strings (names, values, titles and
// URLs) live only in snapshots shown in the review window; every recorded event, measurement and
// export below carries typed codes, counts, timings and hosts instead.

// MARK: - Profiles, placement and policy

/// Where a session's web view lives right now.
enum BrowserPlacement: String, Codable, Sendable {
  /// Attached to the Browser Review window's live view.
  case reviewWindow
  /// Retained by the lab with no window at all: the S3.5 gate case.
  case detached
  /// Experiment: a borderless window placed beyond every screen. Not the S3.5 gate.
  case offscreenWindow
  /// Experiment: S3 row 3's fallback, a one-point window kept visible. Not the S3.5 gate.
  case onePointWindow
}

/// How sessions are parked whenever the review window does not show them.
enum BrowserParkingMode: String, Codable, Sendable, CaseIterable, Identifiable {
  case detached, offscreenWindow, onePointWindow

  var id: Self { self }

  var placement: BrowserPlacement {
    switch self {
    case .detached: .detached
    case .offscreenWindow: .offscreenWindow
    case .onePointWindow: .onePointWindow
    }
  }
}

/// WebKit's inactive scheduling policy. It is fixed when a session opens, so each measurement
/// runs under exactly one recorded policy.
enum BrowserSchedulingPolicy: String, Codable, Sendable, CaseIterable, Identifiable {
  case suspend
  case throttle
  case unthrottled = "none"

  var id: Self { self }

  var webKitValue: WKPreferences.InactiveSchedulingPolicy {
    switch self {
    case .suspend: WKPreferences.InactiveSchedulingPolicy.suspend
    case .throttle: WKPreferences.InactiveSchedulingPolicy.throttle
    case .unthrottled: WKPreferences.InactiveSchedulingPolicy.none
    }
  }
}

/// Who may drive the live page. Lab actions are held while the person is in control.
enum BrowserControl: String, Codable, Sendable {
  case watching, user
}

/// How an action reaches the page: synthesized `NSEvent`s sent straight to the web view, or DOM
/// calls from the isolated world, whose events are untrusted (`isTrusted == false`).
enum BrowserInputPath: String, Codable, Sendable, CaseIterable, Identifiable {
  case native, script
  var id: Self { self }
}

enum BrowserSnapshotMode: String, Codable, Sendable, CaseIterable, Identifiable {
  case interactive, full
  var id: Self { self }
}

enum BrowserActionKind: String, Codable, Sendable {
  case click, type, select, scroll
}

enum BrowserScrollDirection: String, Codable, Sendable, CaseIterable, Identifiable {
  case up, down, left, right

  var id: Self { self }

  func offset(points: Int) -> (dx: Int, dy: Int) {
    switch self {
    case .up: (dx: 0, dy: -points)
    case .down: (dx: 0, dy: points)
    case .left: (dx: -points, dy: 0)
    case .right: (dx: points, dy: 0)
    }
  }
}

// MARK: - Snapshots

struct BrowserElementOption: Decodable, Hashable, Sendable {
  let label: String
  let disabled: Bool
  let selected: Bool
}

/// One visible element from a frame snapshot. `name`, `value` and `options` are untrusted page text
/// and are shown only in the review window.
struct BrowserElement: Decodable, Hashable, Identifiable, Sendable {
  let ref: String
  let role: String
  let name: String
  let value: String?
  let masked: Bool
  let states: [String]
  let editable: Bool
  let sensitive: Bool
  let submit: Bool
  let selectable: Bool
  let picker: Bool
  let options: [BrowserElementOption]?
  /// The snapshot's frame index: 0 is the main frame.
  var frame = 0

  var id: String { "\(frame):\(ref)" }
  var displayRef: String { frame == 0 ? ref : "f\(frame)·\(ref)" }

  private enum CodingKeys: String, CodingKey {
    case ref, role, name, value, masked, states, editable, sensitive, submit, selectable, picker,
      options
  }
}

/// A validated handle on an element of a specific snapshot.
struct BrowserElementRef: Hashable, Sendable {
  let snapshotID: Int
  let frame: Int
  let ref: String
}

struct BrowserPageSnapshot: Sendable {
  struct Frame: Hashable, Sendable {
    let index: Int
    let docID: String
    let origin: String
    let elementCount: Int
    let total: Int
    let truncated: Bool
  }

  let id: Int
  let capturedAt: Date
  let durationMs: Double
  /// The session's main-frame commit count when captured; a later commit makes refs stale.
  let commit: Int
  let mode: BrowserSnapshotMode
  let pageURL: String
  let title: String
  let frames: [Frame]
  let elements: [BrowserElement]
  let skippedFrames: Int

  var truncated: Bool { skippedFrames > 0 || frames.contains(where: \.truncated) }

  func element(for ref: BrowserElementRef) -> BrowserElement? {
    guard ref.snapshotID == id else { return nil }
    return elements.first { $0.frame == ref.frame && $0.ref == ref.ref }
  }

  func reference(to element: BrowserElement) -> BrowserElementRef {
    BrowserElementRef(snapshotID: id, frame: element.frame, ref: element.ref)
  }
}

// MARK: - Actions

enum BrowserActionRequest: Sendable {
  case click(BrowserElementRef, BrowserInputPath)
  case type(BrowserElementRef, text: String, replace: Bool, BrowserInputPath)
  case select(BrowserElementRef, optionIndex: Int, optionLabel: String)
  case scroll(BrowserScrollDirection, points: Int)
  case scrollTo(BrowserElementRef)

  var kind: BrowserActionKind {
    switch self {
    case .click: .click
    case .type: .type
    case .select: .select
    case .scroll, .scrollTo: .scroll
    }
  }

  var path: BrowserInputPath {
    switch self {
    case .click(_, let path), .type(_, _, _, let path): path
    case .select, .scroll, .scrollTo: .script
    }
  }

  var reference: BrowserElementRef? {
    switch self {
    case .click(let ref, _), .type(let ref, _, _, _), .select(let ref, _, _), .scrollTo(let ref):
      ref
    case .scroll: nil
    }
  }

  /// Only the length of typed text is ever recorded.
  var textLength: Int? {
    switch self {
    case .type(_, let text, _, _): text.count
    case .click, .select, .scroll, .scrollTo: nil
    }
  }
}

/// Typed, stable action and script failures. Raw values are the export codes.
enum BrowserActionError: String, Error, Codable, Sendable {
  case busy
  case sessionClosed
  case cancelled
  case userInControl
  case noSnapshot
  case staleSnapshot
  case unknownRef
  case elementGone
  case notVisible
  case outsideViewport
  case obscured
  case disabled
  case notEditable
  case notSelectable
  case notScrollable
  case optionUnavailable
  case optionChanged
  case credentialField
  case submitControlBlocked
  case nativePickerBlocked
  case nativeInputNeedsWindow
  case nativeInputMainFrameOnly
  case unsupportedScale
  case eventSynthesisFailed
  case focusFailed
  case emptyText
  case textTooLong
  case unsupportedText
  case invalidAmount
  case frameUnavailable
  case automationUnavailable
  case contentProcessUnavailable
  case scriptException
  case scriptTimedOut
  case scriptFailed
  case invalidResult
  case imageSnapshotFailed
  case navigationNotStarted
  case navigationFailed
  case notLabPage
  case storeTimedOut
  case noSignInForm
  case signInOriginMismatch
  case signInFieldsChanged
  case canarySourceInvalid
  case siteNotGranted, interactRequired, draftRequired, purchaseRequired,
    exposureConfirmationRequired
  case uploadNotStaged
  case evidenceUnavailable

  init(_ error: any Error) {
    if let error = error as? BrowserActionError {
      self = error
    } else if error is CancellationError {
      self = .cancelled
    } else if let denial = error as? BrowserAuthorization.Denial {
      self = BrowserActionError(rawValue: denial.rawValue) ?? .staleSnapshot
    } else {
      self = .scriptFailed
    }
  }

  /// Maps the isolated world's error codes; unknown codes stay a generic script failure.
  init(scriptCode: String) {
    switch scriptCode {
    case "stale_snapshot": self = .staleSnapshot
    case "unknown_ref": self = .unknownRef
    case "element_gone": self = .elementGone
    case "not_visible": self = .notVisible
    case "outside_viewport": self = .outsideViewport
    case "obscured": self = .obscured
    case "disabled": self = .disabled
    case "not_editable": self = .notEditable
    case "not_selectable": self = .notSelectable
    case "not_scrollable": self = .notScrollable
    case "option_unavailable": self = .optionUnavailable
    case "option_changed": self = .optionChanged
    case "credential_field": self = .credentialField
    case "submit_control": self = .submitControlBlocked
    case "automation_unavailable": self = .automationUnavailable
    case "no_signin_form": self = .noSignInForm
    case "origin_mismatch": self = .signInOriginMismatch
    case "fields_changed": self = .signInFieldsChanged
    default: self = .scriptFailed
    }
  }

  /// Maps `callAsyncJavaScript` errors by domain and code only; exception messages can contain
  /// page-derived text and are never kept.
  init(scriptError error: any Error) {
    let error = error as NSError
    guard error.domain == "WKErrorDomain" else {
      self = .scriptFailed
      return
    }
    switch error.code {
    case 2, 3: self = .contentProcessUnavailable  // content process ended; view invalidated
    case 4: self = .scriptException  // JavaScript exception occurred
    case 12: self = .frameUnavailable  // invalid frame target
    default: self = .scriptFailed
    }
  }

  var message: String {
    switch self {
    case .busy: String(localized: "Another review action is still running.")
    case .sessionClosed: String(localized: "This browser session is closed.")
    case .cancelled: String(localized: "The action was cancelled.")
    case .userInControl:
      String(localized: "You're in control. Hand back before running lab actions.")
    case .noSnapshot: String(localized: "Take a snapshot first; actions target snapshot refs.")
    case .staleSnapshot:
      String(localized: "The page changed since this snapshot. Take a new snapshot.")
    case .unknownRef: String(localized: "That ref is not in the current snapshot.")
    case .elementGone: String(localized: "The element is no longer in the page.")
    case .notVisible: String(localized: "The element is not visible.")
    case .outsideViewport: String(localized: "The element could not be scrolled into view.")
    case .obscured:
      String(localized: "Another element covers this one, so nothing was clicked.")
    case .disabled: String(localized: "The element is disabled.")
    case .notEditable: String(localized: "The element does not accept typed text.")
    case .notSelectable: String(localized: "The element is not a selection list.")
    case .notScrollable: String(localized: "The page has no scrollable document.")
    case .optionUnavailable: String(localized: "That option is unavailable or disabled.")
    case .optionChanged:
      String(localized: "The list's options changed since the snapshot. Take a new snapshot.")
    case .credentialField:
      String(
        localized:
          "Credential fields are filled only through a sign-in Card, never by lab actions.")
    case .submitControlBlocked:
      String(localized: "The submit was not authorized for this document and site.")
    case .nativePickerBlocked:
      String(
        localized:
          "Native clicks on lists and pickers are blocked; they open system menus. Use Select."
      )
    case .nativeInputNeedsWindow:
      String(
        localized:
          "Native events need a window. This view is detached, so use script input or another placement."
      )
    case .nativeInputMainFrameOnly:
      String(localized: "This frame could not be mapped for native input; use script input.")
    case .unsupportedScale:
      String(localized: "The page's viewport scale could not be mapped to view coordinates.")
    case .eventSynthesisFailed: String(localized: "AppKit could not create the input events.")
    case .focusFailed: String(localized: "The field did not take keyboard focus.")
    case .emptyText: String(localized: "Enter text to type.")
    case .textTooLong: String(localized: "Typed text is limited to 500 characters.")
    case .unsupportedText:
      String(localized: "Typed text must be a single line without control characters.")
    case .invalidAmount: String(localized: "Scroll between 1 and 5,000 points.")
    case .frameUnavailable: String(localized: "That frame is no longer available.")
    case .automationUnavailable:
      String(localized: "The automation world is not available in this document.")
    case .contentProcessUnavailable: String(localized: "The page's web content process is gone.")
    case .scriptException: String(localized: "The automation script failed in this page.")
    case .scriptTimedOut: String(localized: "The page did not answer in time.")
    case .scriptFailed: String(localized: "The automation call failed.")
    case .invalidResult: String(localized: "The page returned an unreadable result.")
    case .imageSnapshotFailed: String(localized: "WebKit could not take an image snapshot.")
    case .navigationNotStarted: String(localized: "WebKit did not start the navigation.")
    case .navigationFailed: String(localized: "The navigation failed.")
    case .notLabPage: String(localized: "This step needs the built-in lab page.")
    case .storeTimedOut: String(localized: "The profile's WebKit store did not answer in time.")
    case .noSignInForm:
      String(localized: "No login form with a user name and password field is in this snapshot.")
    case .signInOriginMismatch:
      String(localized: "The page's origin differs from the Card's, so nothing was filled.")
    case .signInFieldsChanged:
      String(localized: "The form no longer shows the Card's fields, so nothing was filled.")
    case .canarySourceInvalid:
      String(
        localized:
          "The review harness's canary file is missing, unreadable, shared with other users or not for this page."
      )
    case .siteNotGranted:
      String(localized: "This exact site has not been authorized in the review lab.")
    case .interactRequired:
      String(localized: "A POST or button needs this site's Interact permission.")
    case .draftRequired:
      String(
        localized: "This consequential action needs a browser draft; the review lab refuses it.")
    case .purchaseRequired:
      String(localized: "This money action needs a purchase Card; the review lab refuses it.")
    case .exposureConfirmationRequired:
      String(
        localized:
          "This page holds private data. Explicitly confirm the next form before continuing.")
    case .uploadNotStaged:
      String(localized: "Stage approved files for this exact input before opening its picker.")
    case .evidenceUnavailable:
      String(
        localized:
          "The durable review evidence could not be saved; no further action is authorized.")
    }
  }
}

/// One DOM input event observed by the isolated world while an action ran.
struct BrowserObservedEvent: Codable, Hashable, Sendable {
  let type: String
  let trusted: Bool
  let onTarget: Bool
}

/// The typed, privacy-safe outcome of one review action. Typed text is reported only as a length.
struct BrowserActionOutcome: Codable, Identifiable, Sendable {
  let id: UUID
  let profileName: String
  let kind: BrowserActionKind
  let path: BrowserInputPath
  let frame: Int?
  let placement: BrowserPlacement
  let inWindow: Bool
  let windowVisible: Bool
  let pageHost: String?
  let startedAt: Date
  let durationMs: Double
  let error: BrowserActionError?
  /// Read back from the page: value, selection or scroll position matched the request.
  let verified: Bool?
  let textLength: Int?
  let scrolledPoints: Double?
  let navigationStarted: Bool
  let observed: [BrowserObservedEvent]

  var succeeded: Bool { error == nil }

  /// Native keyboard and mouse events observed on the target, the S3.2 trusted-input evidence.
  var nativeInputEvents: [BrowserObservedEvent] {
    observed.filter {
      ["mousedown", "mouseup", "click", "keydown", "keyup", "pointerdown", "pointerup"].contains(
        $0.type)
    }
  }
}

// MARK: - Navigation

enum BrowserBlockReason: String, Codable, Sendable {
  case scheme
  case formSubmission
  case nonGETMethod
  case download
  case newWindow
  case siteGrant
  /// The session's route, rule lists or Lockdown were not all in place.
  case networkBoundary
  /// The complete boundary refused an address outside its route's granted origins.
  case outsideRoute
}

/// A navigation failure reduced to its kind, domain and code; system descriptions are not kept.
struct BrowserNavigationFailure: Codable, Hashable, Sendable {
  enum Kind: String, Codable, Sendable {
    case appTransportSecurity
    case hostNotFound
    case offline
    case cannotConnect
    case timedOut
    case secureConnection
    case certificate
    case cancelled
    case interruptedByPolicy
    case other
  }

  let kind: Kind
  let domain: String
  let code: Int

  init(_ error: any Error) {
    let error = error as NSError
    domain = error.domain
    code = error.code
    if error.domain == NSURLErrorDomain {
      switch URLError.Code(rawValue: error.code) {
      case .cancelled: kind = .cancelled
      case .appTransportSecurityRequiresSecureConnection: kind = .appTransportSecurity
      case .cannotFindHost, .dnsLookupFailed: kind = .hostNotFound
      case .notConnectedToInternet, .networkConnectionLost: kind = .offline
      case .cannotConnectToHost: kind = .cannotConnect
      case .timedOut: kind = .timedOut
      case .secureConnectionFailed: kind = .secureConnection
      case .serverCertificateUntrusted, .serverCertificateHasBadDate,
        .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
        .clientCertificateRejected, .clientCertificateRequired:
        kind = .certificate
      default: kind = .other
      }
    } else if error.domain == "WebKitErrorDomain" && error.code == 102 {
      kind = .interruptedByPolicy  // WebKitErrorFrameLoadInterruptedByPolicyChange
    } else {
      kind = .other
    }
  }

  var message: String {
    switch kind {
    case .appTransportSecurity:
      String(localized: "Blocked by App Transport Security: this page needs HTTPS.")
    case .hostNotFound: String(localized: "The server could not be found.")
    case .offline: String(localized: "The Mac is offline or the connection was lost.")
    case .cannotConnect: String(localized: "The server refused or dropped the connection.")
    case .timedOut: String(localized: "The page timed out.")
    case .secureConnection: String(localized: "A secure connection could not be made.")
    case .certificate: String(localized: "The server's certificate was not trusted.")
    case .cancelled: String(localized: "The load was cancelled.")
    case .interruptedByPolicy: String(localized: "The load was stopped by the lab's policy.")
    case .other: String(localized: "The page failed to load (\(domain) \(code)).")
    }
  }
}

/// What the live page is doing, for the review window's status line.
enum BrowserNavigationState: Equatable, Sendable {
  case idle
  case loading
  case finished(ms: Double?)
  case failed(BrowserNavigationFailure)
  case blocked(BrowserBlockReason)
  case terminated
}

struct BrowserNavigationRecord: Codable, Sendable {
  enum Result: String, Codable, Sendable { case finished, failed, blocked }

  let date: Date
  let profileName: String
  let host: String?
  let result: Result
  let durationMs: Double?
  let httpStatus: Int?
  let failure: BrowserNavigationFailure?
  let blockReason: BrowserBlockReason?
}

// MARK: - Lab events and measurements

/// One review-log entry. Details are typed values, never page text or typed input.
struct BrowserLabEvent: Identifiable, Sendable {
  enum Kind: Sendable {
    case profileCreated
    case profileRemoved
    case profileRemovalFailed(BrowserActionError?)
    case sessionOpened(BrowserSchedulingPolicy)
    case sessionClosed
    case navigationFinished(host: String?, ms: Double?)
    case navigationFailed(host: String?, BrowserNavigationFailure)
    case blocked(BrowserBlockReason, detail: String?)
    case openedInPlace(host: String?)
    /// D136: another site opened in a separate, empty profile instead of this one.
    case openedInSeparateProfile(host: String?)
    case dialogDismissed
    case permissionDenied
    case filePickerCancelled
    case authenticationDeclined
    case contentProcessTerminated
    case snapshotTaken(elements: Int, frames: Int, ms: Double)
    case snapshotFailed(BrowserActionError)
    case action(BrowserActionKind, BrowserInputPath, BrowserActionError?)
    case moved(from: BrowserPlacement, to: BrowserPlacement)
    case moveChecked(BrowserHostMoveResult)
    case takeoverStarted
    case takeoverEnded(navigations: Int)
    case probeSet
    case probeFailed
    case isolationChecked(met: Int, of: Int)
    case backgroundRunStarted(BrowserPlacement)
    case backgroundRunEnded(BrowserBackgroundRunState)
    case signInOffered(host: String?)
    case signInEnded(BrowserSignInOutcome.Result, refusal: String?)
    case exportWritten
    case exportFailed
  }

  let id: UUID
  let date: Date
  let profileName: String?
  let kind: Kind
}

enum BrowserHostMoveResult: String, Codable, Sendable {
  /// The same document answered after the move: no reload.
  case sameDocument
  /// A different document answered without a main-frame commit: the page was replaced.
  case documentChanged
  /// The main frame navigated during the check, so it proves nothing.
  case navigationDuringCheck
  /// No automation identity was known for the page before the move.
  case noBaseline
  /// The page did not answer (for example, a suspended detached view).
  case checkFailed
}

struct BrowserHostMoveCheck: Codable, Identifiable, Sendable {
  let id: UUID
  let date: Date
  let profileName: String
  let from: BrowserPlacement
  let to: BrowserPlacement
  let result: BrowserHostMoveResult
}

struct BrowserSnapshotTiming: Codable, Sendable {
  enum Source: String, Codable, Sendable { case manual, background, taskSuite }

  let date: Date
  let profileName: String
  let pageHost: String?
  let placement: BrowserPlacement
  let source: Source
  let durationMs: Double
  let elements: Int
  let frames: Int
  let skippedFrames: Int
  let truncated: Bool
}

struct BrowserIsolationObservation: Codable, Hashable, Sendable {
  let profileID: UUID
  let profileName: String
  /// This profile holds a registered probe and should still contain it.
  let expectsOwnProbe: Bool
  let foundOwnProbe: Bool
  /// A probe registered by another review profile is visible here: an isolation leak.
  let foundForeignProbe: Bool
  /// A probe cookie with an unregistered value, for example from a removed profile record.
  let foundUnregisteredProbe: Bool
  /// The registered probe predates this launch, so finding it shows relaunch persistence.
  let probeSetBeforeThisLaunch: Bool?
  let dataRecordCount: Int
  /// The store could not be read, so this row proves nothing either way.
  let readFailed: Bool

  var meetsExpectation: Bool {
    !readFailed && (!expectsOwnProbe || foundOwnProbe) && !foundForeignProbe
  }
}

struct BrowserIsolationCheck: Codable, Identifiable, Sendable {
  let id: UUID
  let date: Date
  let observations: [BrowserIsolationObservation]

  var metCount: Int { observations.filter(\.meetsExpectation).count }
  var hasComparison: Bool {
    observations.count >= 2 && observations.contains(where: \.expectsOwnProbe)
  }
}

struct BrowserBackgroundConfiguration: Codable, Hashable, Sendable {
  var minutes = 11
  /// One sample per interval, on a fixed cadence counted from the run's start.
  var sampleSeconds = 1
  /// Reload the built-in lab page about once a minute to measure navigation while parked.
  var includesNavigation = false
  /// While the run lasts and no review window shows the page, host it in the visible one-point
  /// window (S3 row 3's fallback), so WebKit does not treat it as hidden and align its timers to
  /// one second. Off measures the parking choice itself, such as the detached gate case.
  var keepsPageVisible = true
}

enum BrowserBackgroundRunState: String, Codable, Sendable {
  case running, completed, cancelled, sessionClosed
}

/// One sample of a parked or shown page: timer rate, DOM and image snapshots and host state.
struct BrowserBackgroundSample: Codable, Hashable, Sendable {
  let elapsedSeconds: Double
  let placement: BrowserPlacement
  let inWindow: Bool
  let windowVisible: Bool
  let reviewWindowShown: Bool
  let otherVisibleWindows: Int
  let appActive: Bool
  let documentVisibility: String?
  /// Timer ticks since the probe last started, for windowed rates computed after the run.
  let timerTicks: Int?
  let timerHz: Double?
  let domSnapshotMs: Double?
  let domSnapshotElements: Int?
  let imageSnapshotMs: Double?
  let navigationMs: Double?
  let documentChanged: Bool
  /// Failed stages as `stage:code`, for example `image:imageSnapshotFailed`.
  let failures: [String]
}

struct BrowserBackgroundRunRecord: Codable, Identifiable, Sendable {
  let id: UUID
  let profileID: UUID
  let profileName: String
  let scheduling: BrowserSchedulingPolicy
  let configuration: BrowserBackgroundConfiguration
  let startedAt: Date
  var endedAt: Date?
  var state: BrowserBackgroundRunState
  var samples: [BrowserBackgroundSample]

  /// Samples taken while the view was in no window and no review window showed it: the S3.5 case.
  var detachedSamples: [BrowserBackgroundSample] {
    samples.filter { $0.placement == .detached && !$0.inWindow }
  }

  /// Allowed interval between samples of one continuous stretch: two sampling periods.
  var maximumGapSeconds: Double { Double(2 * max(1, configuration.sampleSeconds)) }

  /// This run's samples scored in one closed-window case against phase-0's 1 Hz bound.
  func summary(of closedCase: BrowserClosedWindowCase) -> BrowserContinuity.Summary {
    BrowserContinuity.summarize(
      samples.map { sample in
        BrowserContinuity.Sample(
          elapsedSeconds: sample.elapsedSeconds, isInCase: closedCase.contains(sample),
          timerHz: sample.timerHz,
          snapshotsSucceeded: sample.imageSnapshotMs != nil && sample.domSnapshotMs != nil)
      }, thresholdHz: BrowserClosedWindowCase.thresholdHz, maximumGapSeconds: maximumGapSeconds)
  }
}

/// Where a page lived while every app window was closed and no review window showed it. Each
/// case is scored separately; only `detached` is the S3.5 gate case.
enum BrowserClosedWindowCase: String, Codable, Sendable, CaseIterable {
  /// No window at all: the S3.5 gate case.
  case detached
  /// The visible one-point host window: S3 row 3's fallback.
  case visibleHost
  /// A window beyond every screen, which WebKit treats as occluded.
  case offscreenWindow

  /// Phase-0's closed-window bound for timers.
  static let thresholdHz = 1.0

  func contains(_ sample: BrowserBackgroundSample) -> Bool {
    guard !sample.reviewWindowShown, sample.otherVisibleWindows == 0 else { return false }
    switch self {
    case .detached: return sample.placement == .detached && !sample.inWindow
    case .visibleHost: return sample.placement == .onePointWindow && sample.inWindow
    case .offscreenWindow: return sample.placement == .offscreenWindow && sample.inWindow
    }
  }
}

// MARK: - Sign-in Card (development review)

/// Where the development Card's canary login came from. It is never a real credential.
enum BrowserCanarySource: String, Codable, Sendable {
  /// The review harness's canary file, named by `MEMOSHI_BROWSER_REVIEW_SIGNIN_CANARY`.
  case harnessFile
  /// A canary generated in memory for one fill and then dropped.
  case ephemeral
}

/// A development sign-in Card for the lab page's login form, standing in for `browser_sign_in`.
/// It holds field refs and its binding, never a credential.
struct BrowserSignInCard: Identifiable, Sendable {
  enum State: Sendable { case offered, filling }

  let id: UUID
  let binding: BrowserSignIn.CardBinding
  let host: String
  let snapshotID: Int
  let usernameRef: String
  let passwordRef: String
  let source: BrowserCanarySource
  let offeredAt: Date
  var state: State
}

/// The typed outcome of one sign-in Card. It holds no credential value: only nonsecret
/// fingerprints, booleans and counts.
struct BrowserSignInOutcome: Codable, Identifiable, Sendable {
  enum Result: String, Codable, Sendable { case filled, refused, declined }

  let id: UUID
  let profileName: String
  let pageHost: String?
  let offeredAt: Date
  let endedAt: Date
  let result: Result
  /// For refusals: a `BrowserSignIn.Refusal` or `BrowserActionError` code. Nothing was filled.
  let refusal: String?
  let source: BrowserCanarySource?
  let usernameFingerprint: String?
  let passwordFingerprint: String?
  /// Both fields held exactly the canary values when read back in the isolated world.
  let domMatched: Bool?
  /// The page's own script received both values: the SHA-256 digests it computed match.
  let pageReceiptMatched: Bool?
  /// Input and change events the page's script counted on its sign-in form.
  let pageInputEvents: Int?
  /// Credential fields masked in a snapshot taken after the fill.
  let maskedFieldsAfterFill: Int?
  /// Whether that snapshot's names, values, title or URL contained either canary value.
  let snapshotContainsCanary: Bool?
  let durationMs: Double?
}

// MARK: - Isolated-world payloads

struct BrowserScriptErrorPayload: Decodable {
  let error: String?
}

struct BrowserFramePayload: Decodable {
  let docId: String
  let url: String
  let title: String
  let elements: [BrowserElement]
  let total: Int
  let truncated: Bool
}

struct BrowserTargetPayload: Decodable {
  let x: Double
  let y: Double
  let viewportWidth: Double
  let viewportHeight: Double
  let editable: Bool
  let sensitive: Bool
  let submit: Bool
  let picker: Bool
  let file: Bool
}

struct BrowserOKPayload: Decodable {
  let ok: Bool
}

struct BrowserMarkPayload: Decodable {
  let mark: Int
}

struct BrowserObservedPayload: Decodable {
  let events: [BrowserObservedEvent]
}

struct BrowserFocusPayload: Decodable {
  let focused: Bool
}

struct BrowserVerifyPayload: Decodable {
  let matches: Bool
}

struct BrowserScrollPayload: Decodable {
  let moved: Double
}

struct BrowserDocumentPayload: Decodable {
  let docId: String
}

struct BrowserTimerPayload: Decodable {
  let docId: String
  let ticks: Int
  let running: Bool
  let visibility: String
}

/// The lab page's login form, as refs into the snapshot the Card was offered from.
struct BrowserSignInFormPayload: Decodable {
  let usernameRef: String
  let passwordRef: String
  let origin: String
}

/// Read back in the isolated world after a fill: booleans and a count, never the values.
struct BrowserFillPayload: Decodable {
  let usernameMatches: Bool
  let passwordMatches: Bool
  /// How many of the two filled fields the snapshot function now masks.
  let masked: Int
}

/// What the lab page's own script recorded about its sign-in form: SHA-256 digests and counts.
struct BrowserSignInReceiptPayload: Decodable {
  let digests: Bool
  let usernameDigest: String
  let passwordDigest: String
  let inputEvents: Int
}

// MARK: - Shared helpers

enum BrowserClock {
  static func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
  }

  static func milliseconds(since start: ContinuousClock.Instant) -> Double {
    milliseconds(ContinuousClock.now - start)
  }

  static func percentile(_ values: [Double], _ fraction: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let rank = fraction * Double(sorted.count - 1)
    let lower = Int(rank.rounded(.down))
    let upper = Int(rank.rounded(.up))
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (rank - Double(lower))
  }
}

enum BrowserAddress {
  enum Problem: Error, Equatable {
    case empty, tooLong, invalid, credentials, missingHost
    case unsupportedScheme(String)
    /// The session's network boundary (route, rule lists, Lockdown) is not in place.
    case networkBoundary
    /// The address is not one of the origins the session's route admits.
    case outsideRoute

    var message: String {
      switch self {
      case .empty: String(localized: "Enter a web address.")
      case .tooLong: String(localized: "Web addresses are limited to 2,048 characters.")
      case .invalid: String(localized: "That is not a valid web address.")
      case .credentials:
        String(localized: "Addresses with a user name or password are not used in the review lab.")
      case .missingHost: String(localized: "The address has no host.")
      case .unsupportedScheme(let scheme):
        String(localized: "Only http and https addresses open here, not \(scheme).")
      case .networkBoundary:
        String(
          localized:
            "This page can't load until the session's network boundary is in place. Choose a route first."
        )
      case .outsideRoute:
        String(localized: "This address is not one of the sites granted to this session.")
      }
    }
  }

  /// Accepts http and https only, adds https to a bare host, and rejects embedded credentials.
  static func resolve(_ input: String) -> Result<URL, Problem> {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .failure(.empty) }
    guard trimmed.utf8.count <= 2_048 else { return .failure(.tooLong) }
    let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
    guard let components = URLComponents(string: candidate),
      let scheme = components.scheme?.lowercased()
    else { return .failure(.invalid) }
    guard scheme == "https" || scheme == "http" else {
      return .failure(.unsupportedScheme(String(scheme.prefix(32))))
    }
    guard components.user == nil, components.password == nil else {
      return .failure(.credentials)
    }
    guard let host = components.host, !host.isEmpty else { return .failure(.missingHost) }
    guard let url = components.url else { return .failure(.invalid) }
    return .success(url)
  }
}
