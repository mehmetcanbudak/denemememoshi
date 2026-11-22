import SwiftUI

#if os(macOS)
  import AppKit

  /// Adds no frame clock. Visibility changes arrive from the actual native window/display.
  struct MotionVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> MotionVisibilityHost {
      let view = MotionVisibilityHost(frame: .zero)
      view.changed = { next in
        Task { @MainActor in
          if isVisible != next { isVisible = next }
        }
      }
      return view
    }

    func updateNSView(_ view: MotionVisibilityHost, context: Context) {}
  }

  final class MotionVisibilityHost: NSView {
    var changed: ((Bool) -> Void)?
    private weak var observedWindow: NSWindow?
    private var screensAsleep = false

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      setAccessibilityElement(false)
      let workspace = NSWorkspace.shared.notificationCenter
      workspace.addObserver(
        self, selector: #selector(sleeping(_:)), name: NSWorkspace.screensDidSleepNotification,
        object: nil)
      workspace.addObserver(
        self, selector: #selector(waking(_:)), name: NSWorkspace.screensDidWakeNotification,
        object: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let observedWindow {
        NotificationCenter.default.removeObserver(
          self, name: NSWindow.didChangeOcclusionStateNotification, object: observedWindow)
      }
      observedWindow = window
      if let window {
        NotificationCenter.default.addObserver(
          self, selector: #selector(visibilityChanged(_:)),
          name: NSWindow.didChangeOcclusionStateNotification, object: window)
      }
      reconcile()
    }

    private func reconcile() {
      changed?(window?.occlusionState.contains(.visible) == true && !screensAsleep)
    }

    @objc nonisolated private func visibilityChanged(_ notification: Notification) {
      Task { @MainActor [weak self] in self?.reconcile() }
    }

    @objc nonisolated private func sleeping(_ notification: Notification) {
      Task { @MainActor [weak self] in
        self?.screensAsleep = true
        self?.reconcile()
      }
    }

    @objc nonisolated private func waking(_ notification: Notification) {
      Task { @MainActor [weak self] in
        self?.screensAsleep = false
        self?.reconcile()
      }
    }
  }
#endif
