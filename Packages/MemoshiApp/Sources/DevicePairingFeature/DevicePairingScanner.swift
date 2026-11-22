@preconcurrency import AVFoundation
import AppCore
import DesignSystem
import Foundation
import SwiftUI

/// All mutable capture state and delegate callbacks are confined to captureQueue. The session
/// reference is also attached to Apple's preview layer on the main actor; start/stop/configure
/// never block that actor. No frames, photos, recordings or scanned credentials are persisted.
private final class PairingCameraCapture: NSObject, @unchecked Sendable,
  AVCaptureMetadataOutputObjectsDelegate
{
  let session = AVCaptureSession()
  private let captureQueue = DispatchQueue(label: "memoshi.pairing-camera")
  private let scanned: @MainActor @Sendable (String) -> Void
  private let failed: @MainActor @Sendable (DevicePairingFailure) -> Void
  private var delivered = false
  private var stopped = false
  private var output: AVCaptureMetadataOutput?

  init(
    scanned: @escaping @MainActor @Sendable (String) -> Void,
    failed: @escaping @MainActor @Sendable (DevicePairingFailure) -> Void
  ) {
    self.scanned = scanned
    self.failed = failed
    super.init()
  }

  func start() {
    captureQueue.async { [self] in
      guard !stopped else { return }
      do {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
          let camera = AVCaptureDevice.default(for: .video)
        else {
          throw DevicePairingFailure.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)
        let output = AVCaptureMetadataOutput()
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
          session.commitConfiguration()
          throw DevicePairingFailure.cameraUnavailable
        }
        session.addInput(input)
        session.addOutput(output)
        guard output.availableMetadataObjectTypes.contains(.qr) else {
          session.commitConfiguration()
          throw DevicePairingFailure.cameraUnavailable
        }
        output.setMetadataObjectsDelegate(self, queue: captureQueue)
        output.metadataObjectTypes = [.qr]
        self.output = output
        session.commitConfiguration()
        session.startRunning()
      } catch {
        session.stopRunning()
        let callback = failed
        Task { @MainActor in callback(.cameraUnavailable) }
      }
    }
  }

  func stop() {
    captureQueue.async { [self] in
      stopped = true
      output?.setMetadataObjectsDelegate(nil, queue: nil)
      session.stopRunning()
    }
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard !stopped, !delivered,
      let text = metadataObjects.compactMap({
        ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue
      })
      .first(where: { $0.hasPrefix("memoshi-pair:1:") && $0.utf8.count <= 16_384 })
    else { return }
    delivered = true
    captureQueue.async { [self] in session.stopRunning() }
    let callback = scanned
    Task { @MainActor in callback(text) }
  }
}

/// Construct this view only after the user presses Scan Code. Permission is requested once for
/// that explicit action; denial never opens Settings, starts a camera or falls back to a network.
@MainActor
struct DevicePairingScanner: View {
  let coordinator: DevicePairingCoordinator
  @State private var capture: PairingCameraCapture?

  var body: some View {
    VStack(spacing: DS.Space.s6) {
      if let capture {
        PairingCameraPreview(capture: capture)
          .frame(
            minWidth: DS.Layout.DevicePairing.scannerMinWidth,
            minHeight: DS.Layout.DevicePairing.scannerMinHeight
          )
          .accessibilityLabel(Text("Camera scanning a Memoshi pairing code", bundle: #bundle))
      } else {
        ProgressView { Text("Preparing camera…", bundle: #bundle) }
      }
      Text("Point the camera at the one-time code on your other device.", bundle: #bundle)
        .font(.callout)
      Button {
        coordinator.closeScreen()
      } label: {
        Text("Cancel Scan", bundle: #bundle)
      }
    }
    .task {
      let authorized: Bool
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: authorized = true
      case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
      default: authorized = false
      }
      guard !Task.isCancelled else { return }
      guard authorized else {
        coordinator.cameraFailed(.cameraPermissionDenied)
        return
      }
      let service = PairingCameraCapture(
        scanned: { [weak coordinator] text in coordinator?.scanned(text) },
        failed: { [weak coordinator] issue in coordinator?.cameraFailed(issue) })
      capture = service
      service.start()
    }
    .onDisappear {
      capture?.stop()
      capture = nil
    }
  }
}

#if os(iOS)
  import UIKit

  private final class PairingPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer {
      guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
        preconditionFailure(
          "PairingPreviewView.layerClass must create an AVCaptureVideoPreviewLayer")
      }
      return previewLayer
    }
  }

  @MainActor
  private struct PairingCameraPreview: UIViewRepresentable {
    let capture: PairingCameraCapture

    func makeUIView(context: Context) -> PairingPreviewView {
      let view = PairingPreviewView()
      view.previewLayer.session = capture.session
      view.previewLayer.videoGravity = .resizeAspectFill
      return view
    }

    func updateUIView(_ uiView: PairingPreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PairingPreviewView, coordinator: ()) {
      uiView.previewLayer.session = nil
    }
  }
#elseif os(macOS)
  import AppKit

  private final class PairingPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      layer = previewLayer
    }

    required init?(coder: NSCoder) { return nil }

    override func layout() {
      super.layout()
      previewLayer.frame = bounds
    }
  }

  @MainActor
  private struct PairingCameraPreview: NSViewRepresentable {
    let capture: PairingCameraCapture

    func makeNSView(context: Context) -> PairingPreviewView {
      let view = PairingPreviewView(frame: .zero)
      view.previewLayer.session = capture.session
      view.previewLayer.videoGravity = .resizeAspectFill
      return view
    }

    func updateNSView(_ nsView: PairingPreviewView, context: Context) {}

    static func dismantleNSView(_ nsView: PairingPreviewView, coordinator: ()) {
      nsView.previewLayer.session = nil
    }
  }
#endif
