import CMemoshiSecurity
import Darwin
import Foundation
import NIOCore
import Security

/// Transport failures never contain bearer tokens or kernel audit-token bytes.
public enum IPCError: Error, Equatable, Sendable {
  case closed(code: Int, reason: String)
  case systemCall(operation: String, code: Int32)
  case unsafePath(String)
  case invalidPolicy
  case authenticationFailed(status: Int32)
  case signingRequired
  case invalidToken
  case messageTooLarge
  case outboundOverflow
  case receiveOverflow
  case upgradeFailed
  case timedOut
}

/// An identity obtained from dynamically validated running code, not bundle metadata.
public struct PeerIdentity: Hashable, Sendable {
  /// The peer's kernel-reported effective user ID.
  public let uid: UInt32
  /// The Apple-issued signing team from validated code.
  public let teamID: String
  /// The identifier sealed into that running executable's signature.
  public let signingIdentifier: String

}

/// Both the Apple-issued signing team and a sealed signing identifier must match.
public struct PeerPolicy: Sendable {
  /// The trusted expected team, never a value supplied by the connecting peer.
  public let teamID: String
  /// The exact sealed executable identifiers this side accepts.
  public let identifiers: Set<String>

  /// Creates a nonempty, escaped Apple-team and identifier requirement.
  public init(teamID: String, identifiers: Set<String>) throws {
    guard Self.isRequirementString(teamID), !identifiers.isEmpty,
      identifiers.allSatisfy(Self.isRequirementString)
    else { throw IPCError.invalidPolicy }
    self.teamID = teamID
    self.identifiers = identifiers
  }

  private static func isRequirementString(_ value: String) -> Bool {
    !value.isEmpty && value.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7f }
  }

  private static func quoted(_ value: String) -> String {
    "\""
      + value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }

  internal var requirement: String {
    let allowed = identifiers.sorted().map { "identifier \(Self.quoted($0))" }.joined(
      separator: " or ")
    return
      "anchor apple generic and certificate leaf[subject.OU] = \(Self.quoted(teamID)) and (\(allowed))"
  }
}

/// Resolves and validates running-code identity through public Security APIs.
public enum PeerAuthentication {
  /// Ad-hoc, unsigned, relaxed-runtime and debug-entitled executables cannot claim an identity.
  public static func currentIdentity() throws -> PeerIdentity {
    var information: CFDictionary?
    guard MMSCopySelfSigningInformation(&information) == errSecSuccess, let information else {
      throw IPCError.signingRequired
    }
    do {
      return try identity(in: information, uid: UInt32(geteuid()))
    } catch {
      throw IPCError.signingRequired
    }
  }

  /// The descriptor-bound half of the check: the peer's user and the running code its audit
  /// token selects, read from this descriptor. The code is located, not yet validated.
  internal static func guest(socketFD: CInt) throws -> PeerGuest {
    var code: SecCode?
    var uid: UInt32 = .max
    var systemError: CInt = 0
    let status = MMSCopyPeerGuest(socketFD, &uid, &systemError, &code)
    guard status == errSecSuccess, let code else {
      if systemError != 0 {
        throw IPCError.systemCall(operation: "peer credentials", code: systemError)
      }
      throw IPCError.authenticationFailed(status: status)
    }
    return PeerGuest(uid: uid, code: code)
  }

  internal static func guest(channel: any Channel) throws -> PeerGuest {
    // The pinned NIO public API is scoped to this channel's actual FD. Callers keep autoRead
    // false, install no byte-consuming handler and issue no writes until the whole check,
    // this half and `validate`, has passed.
    guard
      let guest = try channel.pipeline.syncOperations.withUnsafeTransportIfAvailable(
        of: NIOBSDSocket.Handle.self, { try guest(socketFD: $0) })
    else { throw IPCError.authenticationFailed(status: errSecUnimplemented) }
    return guest
  }

  /// The other half: `SecCodeCheckValidity` against the policy, which can take long, so it
  /// never runs on an event loop (see `PeerCheck`).
  internal static func validate(_ guest: PeerGuest, policy: PeerPolicy) throws -> PeerIdentity {
    var information: CFDictionary?
    let status = MMSCopyGuestSigningInformation(
      guest.code, policy.requirement as CFString, &information)
    guard status == errSecSuccess, let information else {
      throw IPCError.authenticationFailed(status: status)
    }
    let result = try identity(in: information, uid: guest.uid)
    guard result.uid == geteuid(), result.teamID == policy.teamID,
      policy.identifiers.contains(result.signingIdentifier)
    else { throw IPCError.authenticationFailed(status: errSecAuthFailed) }
    return result
  }

  /// Runs `body` on the queue where peer validation runs, never an event loop or a thread of
  /// the cooperative pool.
  internal static func validating<Value: Sendable>(
    _ body: @escaping @Sendable () throws -> Value
  ) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
      validationQueue.async { continuation.resume(with: Result { try body() }) }
    }
  }

  /// Validations of different peers run side by side, so a slow one delays only its own.
  internal static let validationQueue = DispatchQueue(
    label: "com.mehmetcanbudak.memoshi.peer-validation", qos: .userInitiated,
    attributes: .concurrent)

  /// What the C helper requires of signing information once the signature itself validated.
  internal static func isHardened(_ information: CFDictionary) -> Bool {
    MMSSigningInformationIsHardened(information) != 0
  }

  private static func identity(in raw: CFDictionary, uid: UInt32) throws -> PeerIdentity {
    let information = raw as NSDictionary
    guard let team = information[kSecCodeInfoTeamIdentifier] as? String, !team.isEmpty,
      let identifier = information[kSecCodeInfoIdentifier] as? String, !identifier.isEmpty
    else { throw IPCError.authenticationFailed(status: errSecAuthFailed) }

    return PeerIdentity(uid: uid, teamID: team, signingIdentifier: identifier)
  }
}

/// The running code on one connection, located on its own descriptor and not yet validated.
/// `SecCode` is an immutable Security object whose code-signing functions may be called from
/// any thread; the guest moves from the event loop to one validation and is then dropped.
internal struct PeerGuest: @unchecked Sendable {
  let uid: UInt32
  let code: SecCode
}

/// protocol.md §3.2's peer check in its two halves. `locate` runs on the channel's event loop
/// on the actual descriptor, before any handler is installed or any byte is read or written.
/// `validate`, the code-signature check, can take seconds for a large sealed bundle under disk
/// load; it runs on `PeerAuthentication.validationQueue`, so it never stalls the other
/// connections that share the event loop. The channel stays without handlers and with
/// autoRead off until both halves have passed.
internal struct PeerCheck<Guest: Sendable>: Sendable {
  let locate: @Sendable (any Channel) throws -> Guest
  let validate: @Sendable (Guest) throws -> PeerIdentity

  /// On `channel`'s event loop. The returned future completes on that loop.
  func run(on channel: any Channel) -> EventLoopFuture<PeerIdentity> {
    channel.eventLoop.assertInEventLoop()
    let guest: Guest
    do {
      guest = try locate(channel)
    } catch {
      return channel.eventLoop.makeFailedFuture(error)
    }
    let promise = channel.eventLoop.makePromise(of: PeerIdentity.self)
    let validate = validate
    PeerAuthentication.validationQueue.async {
      promise.completeWith(Result { try validate(guest) })
    }
    return promise.futureResult
  }
}

extension PeerCheck where Guest == PeerGuest {
  /// The real check: a running peer whose code satisfies `policy`.
  static func codeSignature(_ policy: PeerPolicy) -> PeerCheck {
    PeerCheck(
      locate: { try PeerAuthentication.guest(channel: $0) },
      validate: { try PeerAuthentication.validate($0, policy: policy) })
  }
}
