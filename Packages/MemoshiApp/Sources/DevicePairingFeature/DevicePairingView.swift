import AppCore
import CoreImage.CIFilterBuiltins
import DesignSystem
import SwiftUI

/// A native sheet entrypoint; the host owns the coordinator and calls closeScreen on dismissal.
/// This view has no CloudKit/account configuration and cannot grant credentials or tool access.
@MainActor
public struct DevicePairingView: View {
  private let coordinator: DevicePairingCoordinator
  @State private var removal: DevicePairingPeer?
  @Environment(\.designAnnouncer) private var announcer

  /// Retains the host-owned coordinator without starting pairing or requesting camera access.
  public init(coordinator: DevicePairingCoordinator) { self.coordinator = coordinator }

  /// Presents user-driven pairing, scanner and confirmed-removal controls, refreshes the local roster
  /// on appearance and closes presentation work on disappearance.
  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
          DevicePairingIntroduction()
          DevicePairingPhaseContent(coordinator: coordinator)
          DevicePairingActions(coordinator: coordinator)
          DevicePairingPeers(peers: coordinator.peers) { removal = $0 }
        }
        .padding(DS.Space.s8)
        .frame(maxWidth: DS.Layout.DevicePairing.contentMaxWidth)
        .frame(maxWidth: .infinity)
      }
      .navigationTitle(Text("Devices", bundle: #bundle))
      .confirmationDialog(
        Text("Remove this device?", bundle: #bundle),
        isPresented: Binding(
          get: { removal != nil }, set: { if !$0 { removal = nil } }),
        titleVisibility: .visible
      ) {
        if let peer = removal {
          Button(role: .destructive) {
            coordinator.revoke(peer)
            removal = nil
          } label: {
            Text("Remove \(peer.name)", bundle: #bundle)
          }
        }
        Button(role: .cancel) {
          removal = nil
        } label: {
          Text("Cancel", bundle: #bundle)
        }
      } message: {
        Text(
          "This changes the encrypted device group. The removed device cannot read new messages. Existing credentials and tool grants are not added or changed by pairing.",
          bundle: #bundle)
      }
    }
    .task { await coordinator.refreshPeers() }
    .onChange(of: coordinator.phase) { _, phase in
      // Pairing results are announced once when they land (02 §13.2, A3).
      switch phase {
      case .paired(let peer):
        announcer.announce(String(localized: "Paired with \(peer.name)", bundle: #bundle))
      case .failed:
        announcer.announce(String(localized: "Device pairing unavailable", bundle: #bundle))
      default:
        break
      }
    }
    .onDisappear { coordinator.closeScreen() }
  }
}

private struct DevicePairingIntroduction: View {
  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Label {
        Text("Pair your own devices", bundle: #bundle)
      } icon: {
        Image(systemName: "lock.shield")
      }
      .font(.title2.weight(.semibold))
      .accessibilityAddTraits(.isHeader)
      Text(
        "Show a one-time code here, or scan one on a device you already trust. Pairing authenticates membership of your encrypted device group; it does not approve model spending, credentials or tools.",
        bundle: #bundle
      )
      .foregroundStyle(DS.Colors.Text.secondary)
    }
  }
}

@MainActor
private struct DevicePairingPhaseContent: View {
  let coordinator: DevicePairingCoordinator

  var body: some View {
    switch coordinator.phase {
    case .idle:
      Text("Nothing connects until you choose an action below.", bundle: #bundle)
        .foregroundStyle(DS.Colors.Text.secondary)
    case .creatingCode:
      ProgressView { Text("Preparing one-time pairing code…", bundle: #bundle) }
    case .showingCode(let code):
      DevicePairingQRCode(code: code)
    case .scanning:
      DevicePairingScanner(coordinator: coordinator)
    case .joining:
      ProgressView {
        Text("Authenticating your device and joining the encrypted group…", bundle: #bundle)
      }
    case .paired(let peer):
      Label {
        Text("Paired with \(peer.name)", bundle: #bundle)
      } icon: {
        Image(systemName: "checkmark.shield")
      }
    case .revoking:
      ProgressView { Text("Removing device and advancing encryption epoch…", bundle: #bundle) }
    case .failed(let failure):
      DevicePairingFailureView(failure: failure)
    }
  }
}

@MainActor
private struct DevicePairingActions: View {
  let coordinator: DevicePairingCoordinator

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s5) {
      Button {
        coordinator.showCode()
      } label: {
        Label {
          Text("Show Pairing Code", bundle: #bundle)
        } icon: {
          Image(systemName: "qrcode")
        }
      }
      Button {
        coordinator.beginScanning()
      } label: {
        Label {
          Text("Scan Pairing Code", bundle: #bundle)
        } icon: {
          Image(systemName: "camera")
        }
      }
      Text(
        "Showing a code enables local-network discovery. Scanning asks for camera access. Codes expire after five minutes and become invalid as soon as their screen closes. iCloud and relay connections require their own explicit host setup.",
        bundle: #bundle
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
    }
    .buttonStyle(.bordered)
  }
}

@MainActor
private struct DevicePairingQRCode: View {
  let code: DevicePairingCode
  @State private var image: CGImage?
  @State private var failed = false

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s5) {
      if let image {
        Image(decorative: image, scale: 1)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
          .padding(DS.Space.s7)
          .background(DS.Colors.Pairing.qrPaper)
          .frame(
            maxWidth: DS.Layout.DevicePairing.qrCodeMaxDimension,
            maxHeight: DS.Layout.DevicePairing.qrCodeMaxDimension
          )
          .accessibilityLabel(Text("One-time Memoshi pairing QR code", bundle: #bundle))
      } else if failed {
        Text(
          "The pairing code could not be rendered. Close this screen and try again.",
          bundle: #bundle)
      } else {
        ProgressView { Text("Rendering code…", bundle: #bundle) }
      }
      Text(
        "Expires at \(Date(timeIntervalSince1970: Double(code.expiresAt) / 1_000), format: .dateTime.hour().minute().second())",
        bundle: #bundle
      )
      .font(.callout)
      Text(
        "Keep this code private. It contains a one-time joining key, not a reusable password.",
        bundle: #bundle
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
    }
    .privacySensitive()
    .task(id: code.id) {
      let filter = CIFilter.qrCodeGenerator()
      filter.message = Data(code.text.utf8)
      filter.correctionLevel = "M"
      guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
      else {
        failed = true
        return
      }
      image = CIContext().createCGImage(output, from: output.extent)
      failed = image == nil
    }
  }
}

private struct DevicePairingFailureView: View {
  let failure: DevicePairingFailure

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Label {
        Text("Device pairing unavailable", bundle: #bundle)
      } icon: {
        Image(systemName: "exclamationmark.shield")
      }
      switch failure {
      case .expired:
        Text("That one-time code expired. Show a new code to try again.", bundle: #bundle)
      case .invalidCode:
        Text("This is not a valid current Memoshi pairing code.", bundle: #bundle)
      case .cameraPermissionDenied:
        Text(
          "Camera access was not allowed. You can show a code here and scan it from your other device, or change camera access in system settings.",
          bundle: #bundle)
      case .cameraUnavailable:
        Text(
          "A camera with QR scanning is not available. Show a code here instead.", bundle: #bundle)
      case .revocationFailed:
        Text(
          "Removal was not confirmed. No new permission was granted. Reconnect to the configured authority and check the device list before trying again.",
          bundle: #bundle)
      case .recoveryRequired:
        Text(
          "Existing device or group history is unavailable or changed. Pairing is held; no replacement identity or empty history was created. Recover the original state before trying again.",
          bundle: #bundle)
      case .unavailable:
        Text(
          "The signed device host is not configured or is unavailable. No connection, cloud account or permission has been enabled automatically.",
          bundle: #bundle)
      case .pairingFailed:
        Text(
          "Pairing was not confirmed. The code may be used, closed, expired, or the configured group authority may be unreachable. Show a new code to try again.",
          bundle: #bundle)
      case .groupFull(let limit):
        Text(
          "This device group already has \(limit) devices. Remove a device before you add another.",
          bundle: #bundle)
      case .peerGroupFull(let limit):
        Text(
          "The other device's group is full (\(limit) devices). Remove a device there, then show a new code.",
          bundle: #bundle)
      }
    }
    .foregroundStyle(DS.Colors.Text.secondary)
  }
}

private struct DevicePairingPeers: View {
  let peers: [DevicePairingPeer]
  let remove: (DevicePairingPeer) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s5) {
      Text("Paired devices", bundle: #bundle).font(.headline).accessibilityAddTraits(.isHeader)
      if peers.isEmpty {
        Text(
          "No other devices in this device's current local membership snapshot.", bundle: #bundle
        )
        .foregroundStyle(DS.Colors.Text.secondary)
      }
      ForEach(peers) { peer in
        HStack {
          VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(peer.name)
            Text(peer.platform).font(DS.Typography.callout).foregroundStyle(
              DS.Colors.Text.secondary)
          }
          Spacer()
          Button(role: .destructive) {
            remove(peer)
          } label: {
            Text("Remove", bundle: #bundle)
          }
          .accessibilityLabel(Text("Remove \(peer.name)", bundle: #bundle))
        }
      }
    }
  }
}
