import AppKit
import DesignSystem
import SwiftUI
import WebKit

/// Shows a session's existing web view in the review window. The view is moved, never recreated
/// or reloaded, so live view and takeover keep the same page, process and document.
struct BrowserLiveView: NSViewRepresentable {
  let lab: BrowserReviewLab
  let session: BrowserSession
  /// While watching, a shield blocks the person's pointer, scroll and keys.
  let shieldsInput: Bool

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> BrowserLiveContainerView {
    let container = BrowserLiveContainerView(frame: .zero)
    let coordinator = context.coordinator
    container.onWindowWillClose = { [weak coordinator, weak container] in
      guard let coordinator, let container else { return }
      coordinator.release(from: container)
    }
    container.onWindowAvailable = { [weak coordinator, weak container] in
      guard let coordinator, let container else { return }
      coordinator.showIfNeeded(in: container)
    }
    container.shieldsInput = shieldsInput
    coordinator.show(session, lab: lab, in: container)
    return container
  }

  func updateNSView(_ container: BrowserLiveContainerView, context: Context) {
    container.shieldsInput = shieldsInput
    if context.coordinator.session !== session {
      context.coordinator.show(session, lab: lab, in: container)
    } else {
      context.coordinator.showIfNeeded(in: container)
    }
  }

  static func dismantleNSView(_ container: BrowserLiveContainerView, coordinator: Coordinator) {
    coordinator.release(from: container)
  }

  /// Connects one live container to the lab; the lab owns where the web view lives.
  @MainActor
  final class Coordinator {
    private(set) weak var session: BrowserSession?
    private weak var lab: BrowserReviewLab?

    func show(
      _ session: BrowserSession, lab: BrowserReviewLab, in container: BrowserLiveContainerView
    ) {
      if let previous = self.session, previous !== session {
        lab.releaseLiveView(of: previous, from: container)
      }
      self.session = session
      self.lab = lab
      lab.attach(session, to: container)
    }

    /// Re-attaches once the container is in an open window: after it reaches one, or when its
    /// closed window is on screen again.
    func showIfNeeded(in container: BrowserLiveContainerView) {
      guard let session, let lab, !session.isClosed, container.window != nil,
        !container.isWindowClosed, session.lane.webView.superview !== container
      else { return }
      lab.attach(session, to: container)
    }

    func release(from container: BrowserLiveContainerView) {
      guard let session, let lab else { return }
      lab.releaseLiveView(of: session, from: container)
    }
  }
}

/// Hosts a session's web view under the watching-mode input shield.
final class BrowserLiveContainerView: NSView {
  var onWindowWillClose: (() -> Void)?
  var onWindowAvailable: (() -> Void)?
  /// From this view's window closing until that window is on screen again or this view moves to
  /// another window. A SwiftUI `Window` keeps its closed window and content for reopening.
  private(set) var isWindowClosed = false
  private let shield = BrowserInputShieldView()
  private var windowObservers: [any NSObjectProtocol] = []

  var shieldsInput = true {
    didSet {
      shield.isActive = shieldsInput
      if !shieldsInput, window?.firstResponder === shield { window?.makeFirstResponder(nil) }
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    clipsToBounds = true
    shield.frame = bounds
    addSubview(shield)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  /// Moves the web view here without reloading it; AppKit removes it from its old superview.
  /// Until this view has a size, the page keeps its previous viewport rather than collapsing.
  func host(_ webView: WKWebView) {
    guard webView.superview !== self else { return }
    webView.autoresizingMask = []
    if !bounds.isEmpty { webView.frame = bounds }
    addSubview(webView, positioned: .below, relativeTo: shield)
  }

  /// Gives keyboard focus to the shield, so a watching person's keys don't reach the page.
  func focusShield() {
    guard shieldsInput, let window else { return }
    window.makeFirstResponder(shield)
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    fitSubviews()
  }

  override func layout() {
    super.layout()
    fitSubviews()
  }

  private func fitSubviews() {
    guard !bounds.isEmpty else { return }
    for subview in subviews where subview.frame != bounds { subview.frame = bounds }
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    super.viewWillMove(toWindow: newWindow)
    for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
    windowObservers = []
    isWindowClosed = false
    guard let newWindow else { return }
    let center = NotificationCenter.default
    windowObservers = [
      center.addObserver(
        forName: NSWindow.willCloseNotification, object: newWindow, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.isWindowClosed = true
          self.onWindowWillClose?()
        }
      },
      // Reopening the kept window orders it in without moving this view.
      center.addObserver(
        forName: NSWindow.didChangeOcclusionStateNotification, object: newWindow, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.windowDidChangeOcclusionState()
        }
      },
    ]
  }

  /// Ends a close once the same window is on screen again. Closing only makes it invisible, so
  /// this never re-attaches into a closing window.
  private func windowDidChangeOcclusionState() {
    guard isWindowClosed, let window, window.isVisible, window.occlusionState.contains(.visible)
    else { return }
    isWindowClosed = false
    onWindowAvailable?()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil { onWindowAvailable?() }
  }
}

/// Blocks a person's pointer, scroll and key input while the lab drives the page. Synthesized lab
/// events go straight to the web view and never pass through it.
final class BrowserInputShieldView: NSView {
  var isActive = true

  override var acceptsFirstResponder: Bool { isActive }

  override func hitTest(_ point: NSPoint) -> NSView? {
    isActive ? super.hitTest(point) : nil
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {}
  override func rightMouseDown(with event: NSEvent) {}
  override func otherMouseDown(with event: NSEvent) {}
  override func scrollWheel(with event: NSEvent) {}
  override func magnify(with event: NSEvent) {}

  override func keyDown(with event: NSEvent) {
    // Tab still moves keyboard focus between the window's controls.
    if event.keyCode == 48 { super.keyDown(with: event) }
  }
}

/// The two experimental parking windows. Each is created only when its experiment is chosen and
/// is ordered out once it holds no page. Neither replaces the detached (no-window) S3.5 case.
@MainActor
final class BrowserHostWindows {
  private var windows: [BrowserParkingMode: NSWindow] = [:]

  func park(_ webView: WKWebView, mode: BrowserParkingMode) {
    guard mode != .detached else {
      webView.removeFromSuperview()
      return
    }
    let window = window(for: mode)
    let current = webView.frame.size
    let size = current.width >= 1 && current.height >= 1 ? current : BrowserSession.initialViewport
    webView.autoresizingMask = []
    webView.frame = CGRect(origin: .zero, size: size)
    window.contentView?.addSubview(webView)
    position(window, mode: mode, contentSize: size)
  }

  func contains(_ window: NSWindow?) -> Bool {
    guard let window else { return false }
    return windows.values.contains { $0 === window }
  }

  /// Orders out experiment windows that no longer hold a page.
  func orderOutEmptyWindows() {
    for window in windows.values where window.contentView?.subviews.isEmpty ?? true {
      window.orderOut(nil)
    }
  }

  /// Removes any remaining page views and releases both windows, for app quit.
  func closeAll() {
    for window in windows.values {
      for subview in window.contentView?.subviews ?? [] { subview.removeFromSuperview() }
      window.orderOut(nil)
    }
    windows.removeAll()
  }

  private func window(for mode: BrowserParkingMode) -> NSWindow {
    if let window = windows[mode] { return window }
    let window = NSWindow(
      contentRect: CGRect(
        x: 0, y: 0,
        width: DS.Layout.BrowserReview.onePointWindowSide,
        height: DS.Layout.BrowserReview.onePointWindowSide), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.isExcludedFromWindowsMenu = true
    window.canHide = false
    window.ignoresMouseEvents = true
    window.hasShadow = false
    window.animationBehavior = .none
    // The one-point window must stay unoccluded to keep its page visible to WebKit, so it also
    // joins full-screen spaces.
    window.collectionBehavior =
      mode == .onePointWindow
      ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
      : [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.title =
      mode == .onePointWindow
      ? String(localized: "Browser Review Host (One Point)")
      : String(localized: "Browser Review Host (Off-Screen)")
    let content = NSView(frame: .zero)
    content.autoresizesSubviews = false
    window.contentView = content
    windows[mode] = window
    return window
  }

  private func position(_ window: NSWindow, mode: BrowserParkingMode, contentSize: CGSize) {
    switch mode {
    case .offscreenWindow:
      // Beyond the union of every screen, so no display ever shows it.
      let screens = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
      let reference = screens.isNull ? CGRect.zero : screens
      let origin = CGPoint(
        x: reference.minX - contentSize.width - 4_000,
        y: reference.minY - contentSize.height - 4_000)
      window.level = .normal
      window.setFrame(CGRect(origin: origin, size: contentSize), display: false)
      window.orderBack(nil)
    case .onePointWindow:
      // S3 row 3's fallback: one visible point at the top-left of the main display.
      let visible = NSScreen.screens.first?.visibleFrame ?? .zero
      window.level = .floating
      let point = CGRect(
        x: visible.minX, y: visible.maxY - DS.Layout.BrowserReview.onePointWindowSide,
        width: DS.Layout.BrowserReview.onePointWindowSide,
        height: DS.Layout.BrowserReview.onePointWindowSide)
      window.setFrame(point, display: false)
      window.orderFrontRegardless()
    case .detached:
      window.orderOut(nil)
    }
  }
}
