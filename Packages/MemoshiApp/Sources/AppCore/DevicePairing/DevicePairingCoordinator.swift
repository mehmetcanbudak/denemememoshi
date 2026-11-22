import Foundation
import Observation

/// The UI retains QR secrets in memory only. Do not log, persist, copy to preferences or export.
public struct DevicePairingCode: Hashable, Sendable, Identifiable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// Longest accepted issuance-to-expiry interval, in milliseconds (five minutes).
  public static let maximumLifetimeMilliseconds: Int64 = 300_000
  /// Opaque backend invitation identifier used for synchronous invalidation.
  public let id: String
  /// Full one-time QR credential; never log, persist or export this text.
  public let text: String
  /// Issuance time in Unix epoch milliseconds, supplied by the backend.
  public let issuedAt: Int64
  /// Expiry time in Unix epoch milliseconds; the expiry instant itself is expired.
  public let expiresAt: Int64

  /// Checks the presentation envelope and a positive, overflow-free lifetime of at most five
  /// minutes. This does not authenticate the QR credential or check whether it is already expired;
  /// the backend owns handshake validation and one-time use.
  public init(id: String, text: String, issuedAt: Int64, expiresAt: Int64) throws {
    let lifetime = expiresAt.subtractingReportingOverflow(issuedAt)
    guard !id.isEmpty, text.hasPrefix("memoshi-pair:1:"), text.utf8.count <= 16_384,
      !lifetime.overflow, lifetime.partialValue > 0,
      lifetime.partialValue <= Self.maximumLifetimeMilliseconds
    else { throw DevicePairingFailure.invalidCode }
    self.id = id
    self.text = text
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
  }

  /// Compares a Unix epoch millisecond timestamp against the invitation's expiry.
  public func isExpired(at now: Int64) -> Bool { now >= expiresAt }
  /// A fixed redacted label that omits both the invitation identifier and QR credential.
  public var description: String { "DevicePairingCode(<redacted>)" }
  /// Uses the same secret-free label as ordinary string interpolation.
  public var debugDescription: String { description }
}

/// A backend-supplied peer summary for display and explicit removal, not a tool or secret grant.
public struct DevicePairingPeer: Hashable, Sendable, Identifiable {
  /// Backend device identifier passed unchanged to the revocation action.
  public let id: String
  /// Human-readable device label from the backend's peer or membership record.
  public let name: String
  /// Backend platform label for presentation; no platform capability is inferred from it.
  public let platform: String

  /// Retains the backend's identity and display labels without performing discovery or enrollment.
  public init(id: String, name: String, platform: String) {
    self.id = id
    self.name = name
    self.platform = platform
  }
}

/// Content-free UI failures; credential validation, transport details and recovery stay backend-owned.
public enum DevicePairingFailure: Error, Hashable, Sendable {
  case unavailable, invalidCode, expired, pairingFailed, revocationFailed
  case cameraPermissionDenied, cameraUnavailable
  case recoveryRequired
  /// This device's group already has `limit` devices, so no pairing code was issued. Final for
  /// the attempt: nothing helps until a device is removed.
  case groupFull(limit: Int)
  /// The device whose code was scanned reported that its group already has `limit` devices.
  /// Final for the attempt: a device must be removed there before a new code can work.
  case peerGroupFull(limit: Int)
}

/// AppCore never imports IPC/CloudKit. The concrete adapter is app-owned. Only user actions invoke
/// showInvitation/pair/revoke; pairedDevices is a local snapshot, not an account/network lookup.
public protocol DevicePairingBackend: Sendable {
  /// Issues a one-time QR credential for an explicit user action; the backend owns its authenticity.
  func showInvitation() async throws -> DevicePairingCode
  /// MUST synchronously void the Noise one-time code before the QR screen disappears.
  func invalidateInvitation(id: String)
  /// Authenticates a scanned credential and returns the peer admitted by the backend's handshake.
  func pair(scannedText: String) async throws -> DevicePairingPeer
  /// Returns a local roster snapshot without starting discovery, network or account access.
  func pairedDevices() async throws -> [DevicePairingPeer]
  /// Removes the named device through the backend after the caller obtains native user confirmation.
  func revoke(deviceID: String) async throws
}

/// Pure presentation ordering: late async code creation can never reopen a dismissed screen.
/// A rejected late code must still be invalidated by the backend; it is not simply dropped.
public struct DevicePairingLifecycle: Sendable {
  /// In-memory presentation ticket, not a device-group epoch or durable fencing authority.
  public private(set) var generation: UInt64 = 0
  /// Whether presentation callbacks for the current generation may still be accepted.
  public private(set) var isOpen = false
  /// Displayed invitation identifier to invalidate on close, or nil before a code is accepted.
  public private(set) var displayedCodeID: String?

  /// Starts closed, without an invitation awaiting invalidation.
  public init() {}

  /// Opens a presentation and advances its ticket; callers must close and invalidate any prior code.
  public mutating func begin() -> UInt64 {
    generation &+= 1
    isOpen = true
    return generation
  }

  /// Records a code only for the current open ticket and before its expiry, using Unix epoch
  /// milliseconds. A false result leaves backend invalidation of that rejected code to the caller.
  public mutating func display(_ code: DevicePairingCode, generation ticket: UInt64, at now: Int64)
    -> Bool
  {
    guard isOpen, generation == ticket, !code.isExpired(at: now) else { return false }
    displayedCodeID = code.id
    return true
  }

  /// Closes presentation, advances the ticket and returns the displayed ID for backend invalidation.
  @discardableResult
  public mutating func close() -> String? {
    let code = displayedCodeID
    displayedCodeID = nil
    isOpen = false
    generation &+= 1
    return code
  }

  /// Whether an asynchronous presentation result still belongs to the current open screen.
  public func accepts(generation ticket: UInt64) -> Bool { isOpen && generation == ticket }
}

/// Current pairing-screen state; membership changes and their persistence are backend responsibilities.
public enum DevicePairingPhase: Hashable, Sendable {
  case idle, creatingCode, scanning, joining
  case showingCode(DevicePairingCode)
  case paired(DevicePairingPeer)
  case revoking(String)
  case failed(DevicePairingFailure)
}

/// Main-actor presentation owner for user-driven pairing and removal. Invitations and roster
/// snapshots stay in memory; the injected backend owns authentication, membership and persistence.
@MainActor @Observable
public final class DevicePairingCoordinator {
  /// Screen state updated by current presentation operations and scanner callbacks.
  public private(set) var phase: DevicePairingPhase = .idle
  /// Last successful local-roster snapshot. A failed refresh leaves these entries unchanged; a
  /// removal the backend confirmed drops its entry at once.
  public private(set) var peers: [DevicePairingPeer] = []
  private let backend: any DevicePairingBackend
  private let now: @Sendable () -> Int64
  @ObservationIgnored private var lifecycle = DevicePairingLifecycle()
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var expiry: Task<Void, Never>?
  @ObservationIgnored private var rosterRequest = 0
  @ObservationIgnored private var appliedRosterRequest = 0

  /// Offline/inert. Creating a coordinator never requests camera/network/cloud permission.
  /// The injected clock returns Unix epoch milliseconds for invitation expiry.
  public init(
    backend: any DevicePairingBackend,
    now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.backend = backend
    self.now = now
  }

  /// Replaces the current screen with an explicitly requested invitation. Late, cancelled or
  /// expired codes are invalidated rather than displayed, and displayed codes receive an expiry task.
  public func showCode() {
    closeScreen()
    let ticket = lifecycle.begin()
    phase = .creatingCode
    operation = Task {
      do {
        let code = try await backend.showInvitation()
        guard lifecycle.display(code, generation: ticket, at: now()), !Task.isCancelled else {
          backend.invalidateInvitation(id: code.id)
          if lifecycle.accepts(generation: ticket) { phase = .failed(.expired) }
          return
        }
        phase = .showingCode(code)
        expiry = Task {
          do { try await Task.sleep(for: .milliseconds(max(0, code.expiresAt - now()))) } catch {
            return
          }
          guard lifecycle.accepts(generation: ticket) else { return }
          // Atomic book invalidation precedes hiding the QR; no actor/network hop is involved.
          if let id = lifecycle.close() { backend.invalidateInvitation(id: id) }
          phase = .failed(.expired)
        }
      } catch {
        if lifecycle.accepts(generation: ticket), !Task.isCancelled {
          phase = .failed((error as? DevicePairingFailure) ?? .pairingFailed)
        }
      }
    }
  }

  /// Opens scanner presentation after invalidating any displayed code; the scanner view, not this
  /// action, requests camera permission.
  public func beginScanning() {
    closeScreen()
    _ = lifecycle.begin()
    phase = .scanning
  }

  /// Scanner callback accepted only while scanning. Checks the bounded QR envelope, then lets the
  /// backend authenticate and join; stale results cannot reopen a dismissed presentation.
  public func scanned(_ text: String) {
    guard phase == .scanning else { return }
    guard text.hasPrefix("memoshi-pair:1:"), text.utf8.count <= 16_384 else {
      phase = .failed(.invalidCode)
      return
    }
    let ticket = lifecycle.generation
    phase = .joining
    operation = Task {
      do {
        let peer = try await backend.pair(scannedText: text)
        guard lifecycle.accepts(generation: ticket), !Task.isCancelled else { return }
        phase = .paired(peer)
        // The roster is separate from the result: its failure must not replace `paired`.
        membershipChanged()
        _ = await loadPeers()
      } catch {
        if lifecycle.accepts(generation: ticket), !Task.isCancelled {
          phase = .failed((error as? DevicePairingFailure) ?? .pairingFailed)
        }
      }
    }
  }

  /// Scanner failure callback that closes pending presentation work before showing the supplied error.
  public func cameraFailed(_ failure: DevicePairingFailure) {
    closeScreen()
    phase = .failed(failure)
  }

  /// Refreshes the backend's local roster without discovery or account lookup. On failure, preserves
  /// the last snapshot and presents `unavailable` only when nothing else is on screen: a pairing
  /// code, scan, result or removal in progress is never replaced by a roster failure.
  public func refreshPeers() async {
    let loaded = await loadPeers()
    if !loaded, phase == .idle { phase = .failed(.unavailable) }
  }

  /// Applies a roster snapshot unless a newer one, or a membership change after its request,
  /// already superseded it. Returns false only when the latest request failed unsuperseded.
  private func loadPeers() async -> Bool {
    rosterRequest += 1
    let request = rosterRequest
    do {
      let snapshot = try await backend.pairedDevices()
      guard request > appliedRosterRequest else { return true }
      appliedRosterRequest = request
      peers = snapshot
      return true
    } catch {
      return request != rosterRequest || request <= appliedRosterRequest
    }
  }

  /// Snapshots requested before a confirmed pairing or removal no longer describe the group.
  private func membershipChanged() {
    appliedRosterRequest = rosterRequest
  }

  /// The view supplies a native confirmation; this action grants no model/tool/secret access.
  public func revoke(_ peer: DevicePairingPeer) {
    closeScreen()
    let ticket = lifecycle.begin()
    phase = .revoking(peer.id)
    operation = Task {
      do {
        try await backend.revoke(deviceID: peer.id)
        guard lifecycle.accepts(generation: ticket), !Task.isCancelled else { return }
        phase = .idle
        membershipChanged()
        peers.removeAll { $0.id == peer.id }
        _ = await loadPeers()
      } catch {
        if lifecycle.accepts(generation: ticket), !Task.isCancelled {
          phase = .failed(.revocationFailed)
        }
      }
    }
  }

  /// Call both from sheet onDismiss and the QR/scanner view's onDisappear.
  /// Invalidates the displayed invitation synchronously and cancels presentation tasks; cancellation
  /// does not promise to undo a backend join or revocation that has already completed.
  public func closeScreen() {
    if let id = lifecycle.close() { backend.invalidateInvitation(id: id) }
    expiry?.cancel()
    expiry = nil
    operation?.cancel()
    operation = nil
    phase = .idle
  }
}
