import AppCore
import DesignSystem
import DevicePairingFeature
import Foundation
import MemoshiDevice
import MemoshiDeviceApple
import MemoshiProtocol
import Observation
import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// Native control-plane lab. No initializer enrolls an identity or activates a cloud account.
/// Actual Pi conversation-store handover remains outside this explicitly labelled surface.
@MainActor
struct DevicePairingReviewView: View {
  @State private var model = DevicePairingReviewModel()
  @State private var confirmEnrollment = false

  var body: some View {
    Group {
      if let coordinator = model.coordinator {
        DevicePairingView(coordinator: coordinator)
          .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
              Text(
                "Control-plane qualification only. This lab does not transfer Chat or Session stores."
              )
              .font(DS.Typography.callout)
              .foregroundStyle(DS.Colors.Text.secondary)
              Button("Close Pairing Session") { model.close() }
            }
            .padding(DS.Space.s5)
          }
      } else {
        NavigationStack {
          Form {
            // Section headers use the checked secondary role; the system's grouped header gray
            // only nearly meets 4.5:1.
            Section {
              Text(
                "Use your provisioned device-only Keychain identity and the real encrypted device group. Showing or scanning a code enables local discovery; group changes use the configured iCloud authority. No model spending, credentials or tool grants are approved here."
              )
              Text(
                "This is a control-plane lab with an identity-bound in-memory conversation adapter, not a Pi-store handover or deployed-capacity qualification."
              )
              .font(DS.Typography.callout)
              .foregroundStyle(DS.Colors.Text.secondary)
            } header: {
              Text("Qualification boundary").foregroundStyle(DesignControlRoles.secondaryText)
            }
            Section {
              TextField("Device name", text: $model.deviceName)
                .disabled(model.isBusy)
              Button("Open Existing Identity") { model.start(.loadExisting) }
                .disabled(model.isBusy || !model.hasConfiguredAccessGroup)
              Button("Create Device Identity…") { confirmEnrollment = true }
                .disabled(
                  model.isBusy || !model.hasConfiguredAccessGroup
                    || model.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              Text(
                "Creation is explicit and never replaces an existing identity. Locked, missing or unprovisioned Keychain access fails closed; there is no file or default-Keychain fallback."
              )
              .font(DS.Typography.callout)
              .foregroundStyle(DS.Colors.Text.secondary)
            } header: {
              Text("Device identity").foregroundStyle(DesignControlRoles.secondaryText)
            }
            if !model.hasConfiguredAccessGroup {
              Section {
                Text(
                  "This build has no configured device identity access group. The signed app needs its team-prefixed com.mehmetcanbudak.memoshi.devices Keychain group and iCloud.com.mehmetcanbudak.memoshi CloudKit capability. Ad-hoc builds cannot qualify this path."
                )
              } header: {
                Text("Provisioning required").foregroundStyle(DesignControlRoles.secondaryText)
              }
            }
            if model.isBusy { ProgressView("Opening device identity…") }
            if let notice = model.removalNotice {
              Section {
                switch notice {
                case .deleted:
                  Text(
                    "This device was removed from your devices. Data it received from them was deleted."
                  )
                case .deleting:
                  Text(
                    "This device was removed from your devices. Some data it received from them is not deleted yet; Memoshi is trying again."
                  )
                case .notDeletedYet:
                  Text(
                    "This device was removed from your devices. Some data it received from them could not be deleted yet. It is deleted the next time you open this lab."
                  )
                }
              }
            }
            if let error = model.error {
              Section {
                Text(error).foregroundStyle(DS.Colors.Status.Danger.fg)
              } header: {
                Text("Could not open pairing").foregroundStyle(DesignControlRoles.secondaryText)
              }
            }
          }
          .navigationTitle("Device Pairing Review")
          .confirmationDialog(
            "Create a new device identity?", isPresented: $confirmEnrollment,
            titleVisibility: .visible
          ) {
            Button("Create Device Identity") { model.create() }
            Button("Cancel", role: .cancel) {}
          } message: {
            Text(
              "Creates device-only private keys in this app's provisioned Keychain group. It does not replace a previous identity or start a connection."
            )
          }
        }
      }
    }
    .onDisappear { model.close() }
  }
}

@MainActor @Observable
private final class DevicePairingReviewModel {
  var deviceName: String
  private(set) var coordinator: DevicePairingCoordinator?
  private(set) var isBusy = false
  private(set) var error: String?
  /// D133: this device's removal was verified; says whether what it received is deleted.
  private(set) var removalNotice: DeviceRemovalNotice?
  let hasConfiguredAccessGroup: Bool
  private let accessGroup: String?
  @ObservationIgnored private var session: MemoshiPairingLabSession?
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var removalWatch: Task<Void, Never>?
  /// Shared by every presentation of this lab. A session that an earlier sheet is still opening
  /// or closing holds the journals' exclusive locks; a new open waits for it instead of
  /// reporting that refusal as lost history.
  private static var closing: Task<Void, Never>?
  /// Retries an incomplete deletion after a verified removal (D133). It outlives the sheet; a
  /// new open cancels it first, because that open runs the same deletion again.
  private static var removalRetry: Task<Void, Never>?
  @ObservationIgnored private var generation = UUID()

  init() {
    #if os(iOS)
      deviceName =
        UIDevice.current.userInterfaceIdiom == .pad ? "Development iPad" : "Development iPhone"
    #else
      deviceName = "Development Mac"
    #endif
    let value =
      Bundle.main.object(forInfoDictionaryKey: "MemoshiDeviceIdentityAccessGroup") as? String
    let suffix = ".com.mehmetcanbudak.memoshi.devices"
    accessGroup = value.flatMap {
      $0.hasSuffix(suffix) && $0.count > suffix.count && !$0.contains("$(") ? $0 : nil
    }
    hasConfiguredAccessGroup = accessGroup != nil
  }

  func create() {
    #if os(iOS)
      let platform: DevicePlatform = UIDevice.current.userInterfaceIdiom == .pad ? .ipad : .iphone
    #else
      let platform: DevicePlatform = .mac
    #endif
    start(
      .createNew(
        name: deviceName.trimmingCharacters(in: .whitespacesAndNewlines), platform: platform))
  }

  func start(_ enrollment: MemoshiPairingIdentityEnrollment) {
    guard !isBusy, session == nil, let accessGroup else { return }
    isBusy = true
    error = nil
    removalNotice = nil
    let token = UUID()
    generation = token
    let closing = Self.closing
    let retry = Self.removalRetry
    retry?.cancel()
    Self.removalRetry = nil
    operation = Task { [weak self] in
      guard let self else { return }
      do {
        await retry?.value
        await closing?.value
        try Task.checkCancellation()
        let opened = try await Self.openLab(enrollment, accessGroup: accessGroup)
        guard !Task.isCancelled, generation == token else {
          await opened.close()
          return
        }
        session = opened
        coordinator = DevicePairingCoordinator(backend: opened.backend)
        isBusy = false
        operation = nil
        removalWatch = Task { [weak self] in
          guard let outcome = await opened.removalVerified(), let self, generation == token
          else { return }
          // Told as soon as the removal is verified, also while a deletion is retried.
          close()
          followRemoval(outcome, accessGroup: accessGroup)
        }
      } catch {
        guard generation == token else { return }
        isBusy = false
        operation = nil
        if error as? DevicePairingFailure == .recoveryRequired {
          self.error = String(
            localized:
              "Existing device or group history is unavailable or changed. Pairing is held; no replacement identity or empty history was created. Recover the original state before trying again."
          )
        } else if let removed = error as? DevicePairingRemovedFromGroup {
          followRemoval(removed.deletion, accessGroup: accessGroup)
        } else if error is DevicePairingEnrollmentRemoved {
          self.error = String(
            localized:
              "A first enrollment of this device identity did not complete, so that identity was removed again. No enrolled identity and no earlier state was touched. Verify the signed device Keychain/CloudKit capabilities and unlock the device, then create the identity again."
          )
        } else if !(error is CancellationError) {
          self.error = String(
            localized:
              "The provisioned device identity or encrypted group could not be opened. Verify the signed device Keychain/CloudKit capabilities and unlock the device. No alternate identity or authority was selected."
          )
        }
      }
    }
  }

  private static func openLab(
    _ enrollment: MemoshiPairingIdentityEnrollment, accessGroup: String
  ) async throws -> MemoshiPairingLabSession {
    let directory = try MemoshiPairingLabSession.privateLabDirectory()
    let cloudDirectory = directory.appendingPathComponent("cloud", isDirectory: true)
    return try await MemoshiPairingLabSession.open(
      enrollment: enrollment, validatedAccessGroup: accessGroup, directory: directory,
      store: { MemoryConversationStore(deviceID: $0.deviceID) },
      authority: { group, identity, createdNewIdentity in
        let cloud = CloudKitDeviceHost(
          identity: identity, group: group, directory: cloudDirectory,
          maximumLeaseMilliseconds: 120_000, allowFirstEnrollment: createdNewIdentity)
        // Consent is this explicit Start action; account activation waits for a group operation.
        await cloud.authorizeCloudOperations()
        return MemoshiPairingAuthority(cloud: cloud)
      })
  }

  /// Shows the removal at once and, while the deletion is incomplete, retries it with a
  /// bounded backoff. Each retry opens the existing identity again after every earlier close,
  /// which for a removed device starts no session and only runs the deletion with fresh
  /// journals (the node's replica journal, the CloudKit spool and state checkpoint).
  private func followRemoval(_ first: DeviceRemovalOutcome, accessGroup: String) {
    let previous = Self.removalRetry
    previous?.cancel()
    Self.removalRetry = Task { [weak self] in
      await previous?.value
      await DeviceRemovalRetry().follow(
        first: first,
        attempt: { await Self.retryDeletion(accessGroup: accessGroup) },
        report: { [weak self] notice in await self?.show(notice) })
    }
  }

  private func show(_ notice: DeviceRemovalNotice) { removalNotice = notice }

  private static func retryDeletion(accessGroup: String) async -> DeviceRemovalOutcome {
    await closing?.value
    do {
      let session = try await openLab(.loadExisting, accessGroup: accessGroup)
      await session.close()
      return .member
    } catch let removed as DevicePairingRemovedFromGroup {
      return removed.deletion
    } catch {
      return .incomplete
    }
  }

  func close() {
    generation = UUID()
    let pending = operation
    pending?.cancel()
    operation = nil
    removalWatch?.cancel()
    removalWatch = nil
    coordinator?.closeScreen()
    coordinator = nil
    let current = session
    session = nil
    isBusy = false
    guard pending != nil || current != nil else { return }
    let previous = Self.closing
    Self.closing = Task {
      await previous?.value
      // A cancelled open still closes the session it produced; that is part of this close.
      await pending?.value
      await current?.close()
    }
  }
}
