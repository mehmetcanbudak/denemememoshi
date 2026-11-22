#if os(macOS)
  import AppKit

  /// Hosts one avatar's layer tree and reports what the window system knows about visibility:
  /// occlusion (which also covers minimized windows and hidden apps), sleeping displays and
  /// Low Power Mode. Decorative: it never takes clicks or accessibility focus.
  final class AvatarHostView: NSView {
    private let animator = AvatarAnimator(flipped: true)
    private weak var observedWindow: NSWindow?
    private var screensAsleep = false

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      layer?.addSublayer(animator.container)
      NotificationCenter.default.addObserver(
        self, selector: #selector(systemStateDidChange(_:)),
        name: .NSProcessInfoPowerStateDidChange, object: nil)
      let workspace = NSWorkspace.shared.notificationCenter
      workspace.addObserver(
        self, selector: #selector(screensDidSleep(_:)),
        name: NSWorkspace.screensDidSleepNotification, object: nil)
      workspace.addObserver(
        self, selector: #selector(screensDidWake(_:)),
        name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    required init?(coder: NSCoder) {
      return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
      super.setFrameSize(newSize)
      animator.layout(in: bounds)
    }

    override func layout() {
      super.layout()
      animator.layout(in: bounds)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let observedWindow {
        NotificationCenter.default.removeObserver(
          self, name: NSWindow.didChangeOcclusionStateNotification, object: observedWindow)
      }
      observedWindow = window
      if let window {
        NotificationCenter.default.addObserver(
          self, selector: #selector(systemStateDidChange(_:)),
          name: NSWindow.didChangeOcclusionStateNotification, object: window)
      }
      reconcile()
    }

    func configure(_ configuration: AvatarLayerConfiguration) {
      animator.configure(configuration)
      reconcile()
    }

    func detach() {
      animator.detach()
    }

    private func reconcile() {
      let visible =
        window.map { $0.occlusionState.contains(.visible) && !screensAsleep } ?? false
      animator.environmentDidChange(
        window: window, visible: visible,
        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    // Power-state changes arrive on a global queue; hop to the main actor for layer work.
    @objc nonisolated private func systemStateDidChange(_ notification: Notification) {
      Task { @MainActor [weak self] in self?.reconcile() }
    }

    @objc nonisolated private func screensDidSleep(_ notification: Notification) {
      Task { @MainActor [weak self] in
        self?.screensAsleep = true
        self?.reconcile()
      }
    }

    @objc nonisolated private func screensDidWake(_ notification: Notification) {
      Task { @MainActor [weak self] in
        self?.screensAsleep = false
        self?.reconcile()
      }
    }
  }
#else
  import UIKit

  /// Hosts one avatar's layer tree and reports scene activation and Low Power Mode as
  /// visibility. Decorative: it never takes touches or accessibility focus.
  final class AvatarHostView: UIView {
    private let animator = AvatarAnimator(flipped: false)

    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      layer.addSublayer(animator.container)
      let center = NotificationCenter.default
      for name in [
        Notification.Name.NSProcessInfoPowerStateDidChange,
        UIScene.didEnterBackgroundNotification, UIScene.willEnterForegroundNotification,
        UIScene.didActivateNotification,
      ] {
        center.addObserver(
          self, selector: #selector(systemStateDidChange(_:)), name: name, object: nil)
      }
    }

    required init?(coder: NSCoder) {
      return nil
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      animator.layout(in: bounds)
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      reconcile()
    }

    func configure(_ configuration: AvatarLayerConfiguration) {
      animator.configure(configuration)
      reconcile()
    }

    func detach() {
      animator.detach()
    }

    private func reconcile() {
      let state = window?.windowScene?.activationState
      let visible = state == .foregroundActive || state == .foregroundInactive
      animator.environmentDidChange(
        window: window, visible: visible,
        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    // Power-state changes arrive on a global queue; hop to the main actor for layer work.
    @objc nonisolated private func systemStateDidChange(_ notification: Notification) {
      Task { @MainActor [weak self] in self?.reconcile() }
    }
  }
#endif
