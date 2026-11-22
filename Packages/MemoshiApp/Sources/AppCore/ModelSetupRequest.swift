import Foundation
import MemoshiProtocol
import Observation

/// Removes an app-owned model credential with the removal its reference's kind requires: an
/// API key (`kc_`) from the model Keychain, a ChatGPT sign-in (`cg_`) through its sign-out.
/// Every credential that model setup introduces or replaces is removed through this one choice.
@MainActor
public struct ModelCredentialRemover {
  /// Removes one credential of one kind by its opaque reference.
  public typealias Removal = @MainActor (String) async throws -> Void

  private let apiKey: Removal
  private let chatGPT: Removal

  /// A kind that cannot be removed in this launch is given a removal that throws.
  public init(apiKey: @escaping Removal, chatGPT: @escaping Removal) {
    self.apiKey = apiKey
    self.chatGPT = chatGPT
  }

  /// Removes the credential `reference` names with its kind's removal. A reference that names
  /// no app-owned credential reaches neither removal and throws
  /// `ModelKeychainError.invalidSecretRef`.
  public func remove(_ reference: String) async throws {
    switch ModelCredentialReference(rawValue: reference)?.kind {
    case .apiKey: try await apiKey(reference)
    case .chatGPT: try await chatGPT(reference)
    case nil: throw ModelKeychainError.invalidSecretRef
    }
  }
}

/// The one saved model-provider configuration request and the rules for retrying or abandoning
/// it. The exact request is saved before it is sent, and an uncertain delivery is retried with
/// that request. A discard is offered only after a definite refusal, and it removes the
/// credential the request introduced only when no attempt can still be applied (D130). The
/// credential the request replaces is saved with it and removed once the request is confirmed.
/// Credential bytes never pass through this type: only opaque references and the caller's
/// remover do.
@MainActor
@Observable
public final class ModelSetupRequest {
  /// How the runtime answered one attempt.
  public enum Answer: Equatable, Sendable {
    /// The configuration was applied.
    case confirmed
    /// A definite refusal: this attempt applied nothing.
    case refused
    /// The runtime was busy. It says so before it looks at the request, so an earlier attempt
    /// of the same request may still be running: a new attempt is permitted, a discard is not.
    case busy
    /// No definite answer: the attempt may still be applied.
    case uncertain

    /// Classifies what an attempt threw.
    public init(failure error: any Error) {
      guard let error = error as? RPCError else {
        self = .uncertain
        return
      }
      switch error.kind {
      case .invalidParams, .methodNotFound, .forbidden: self = .refused
      case .busy: self = .busy
      default: self = .uncertain
      }
    }
  }

  /// What discarding a refused request does, or did, with the credential that request
  /// introduced.
  public enum RefusedDiscard: Equatable, Sendable {
    /// The credential saved only for the request is removed.
    case removedCredential
    /// The credential is kept: an earlier attempt had no definite answer and may still be
    /// applied, naming it.
    case keptCredential
    /// The request introduced no credential of its own.
    case noCredential
  }

  /// The saved request, or nil when none is saved or the saved record cannot be read.
  public private(set) var params: ModelsProvidersConfigureParams?
  /// Whether a saved record exists whose delivery is not confirmed, readable or not.
  public private(set) var isUnconfirmed = false
  /// Whether the latest attempt was refused or answered busy, so that a retry may allocate a
  /// new request for the same credential.
  public private(set) var wasRejected = false
  /// Whether the latest attempt got a definite refusal.
  private var wasRefused = false
  /// Whether an attempt for the saved credential ended without a definite answer.
  private var hadUncertainAttempt = false
  /// The credential the saved request replaces for its provider, saved with the request.
  @ObservationIgnored private var superseded: (providerID: String, secretRef: String)?
  /// Credentials that confirmed requests replaced and whose removal has not succeeded yet.
  private var unremoved: [String] = []
  @ObservationIgnored private let defaults: UserDefaults

  private static let requestKey = "text-chat.pending-provider"
  private static let uncertainKey = "text-chat.pending-provider-uncertain"
  private static let supersededKey = "text-chat.pending-provider-superseded"
  private static let unremovedKey = "text-chat.replaced-credentials"

  /// Restores the saved request, if any, with the credential it supersedes, and the replaced
  /// credentials still to be removed. A record that cannot be read stays as an unreadable one;
  /// a request saved without its uncertainty flag is treated as uncertain.
  public init(defaults: UserDefaults) {
    self.defaults = defaults
    unremoved = defaults.stringArray(forKey: Self.unremovedKey) ?? []
    guard let bytes = defaults.data(forKey: Self.requestKey) else { return }
    isUnconfirmed = true
    if let saved = try? ProtocolCoding.makeDecoder(strict: true).decode(
      ModelsProvidersConfigureParams.self, from: bytes)
    {
      params = saved
      hadUncertainAttempt = defaults.object(forKey: Self.uncertainKey) as? Bool ?? true
      if let record = defaults.dictionary(forKey: Self.supersededKey) as? [String: String],
        let providerID = record["providerId"], let secretRef = record["secretRef"]
      {
        superseded = (providerID, secretRef)
      }
    }
  }

  /// Whether the saved record cannot be read, so it can never be retried.
  public var isUnreadable: Bool { isUnconfirmed && params == nil }

  /// How many credentials confirmed requests replaced and no removal has removed yet. Each is
  /// still saved, though nothing names it.
  public var keptCredentialCount: Int { unremoved.count }

  /// Whether the runtime definitely refused the latest attempt of the saved request, so the
  /// person may abandon it instead of retrying.
  public var canDiscardRefused: Bool { params != nil && wasRefused }

  /// Whether an earlier attempt may still be applied, so that the discard keeps a credential
  /// the request introduced.
  public var discardKeepsCredential: Bool { hadUncertainAttempt }

  /// Saves the exact request before it is sent. `continuing` marks a new request for the same
  /// credential after a rejection: an earlier uncertain attempt, and the credential the
  /// request supersedes, still count for it. Without it the request is a new setup.
  public func save(_ params: ModelsProvidersConfigureParams, continuing: Bool = false) throws {
    let bytes = try ProtocolCoding.makeEncoder().encode(params)
    defaults.set(bytes, forKey: Self.requestKey)
    self.params = params
    isUnconfirmed = true
    wasRejected = false
    wasRefused = false
    if !continuing {
      hadUncertainAttempt = false
      recordSuperseded(nil)
    }
    defaults.set(hadUncertainAttempt, forKey: Self.uncertainKey)
  }

  /// Records the credential the saved request replaces for its provider, saved with the
  /// request. It is removed once that request is confirmed. Ignored when no request is saved,
  /// so a credential in use is never marked for a request that does not exist, and for a
  /// reference that names no app-owned credential, which no removal could remove.
  public func supersede(secretRef: String) {
    guard let params, ModelCredentialReference(rawValue: secretRef) != nil else { return }
    recordSuperseded((params.providerId, secretRef))
  }

  /// Sends the saved request once and applies the answer. Throws what `send` throws. On
  /// confirmation the request is cleared, then `remover` removes the credential it superseded,
  /// when that was recorded for the same provider and is not the confirmed one, and every
  /// credential an earlier confirmation replaced but could not remove. A failed removal is not
  /// an error: its credential is kept, counted in `keptCredentialCount`, for `removeKept` or
  /// the next confirmation. Does nothing when no readable request is saved.
  public func attempt(
    removing remover: ModelCredentialRemover,
    _ send: @MainActor (ModelsProvidersConfigureParams) async throws -> Void
  ) async throws {
    guard let params else { return }
    // Saved before the call: a process that ends mid-attempt leaves an uncertain one behind.
    defaults.set(true, forKey: Self.uncertainKey)
    do {
      try await send(params)
    } catch {
      let answer = Answer(failure: error)
      wasRefused = answer == .refused
      wasRejected = wasRefused || answer == .busy
      if wasRejected {
        // This attempt was answered: the saved flag is what the attempts so far established.
        defaults.set(hadUncertainAttempt, forKey: Self.uncertainKey)
      } else {
        hadUncertainAttempt = true
      }
      throw error
    }
    // Nothing names the superseded credential now. The confirmed one is named, so it stays.
    var replaced = unremoved
    if let superseded, superseded.providerID == params.providerId,
      !replaced.contains(superseded.secretRef)
    {
      replaced.append(superseded.secretRef)
    }
    replaced.removeAll { $0 == params.secretRef }
    recordUnremoved(replaced)
    clear()
    for reference in replaced {
      do {
        try await remover.remove(reference)
        recordUnremoved(unremoved.filter { $0 != reference })
      } catch {
        // Kept for `removeKept` or the next confirmation.
      }
    }
  }

  /// Removes through `remover` each kept credential, the ones confirmed requests replaced and
  /// no removal has removed yet, without a new confirmation. One that `inUse` (the references
  /// the current providers name) or the saved request names is in use again: it is no longer
  /// kept, and never removed. A failed removal keeps its credential, as in `attempt`.
  public func removeKept(removing remover: ModelCredentialRemover, inUse: Set<String>) async {
    let named = inUse.union(params?.secretRef.map { [$0] } ?? [])
    recordUnremoved(unremoved.filter { !named.contains($0) })
    for reference in unremoved {
      do {
        try await remover.remove(reference)
        recordUnremoved(unremoved.filter { $0 != reference })
      } catch {
        // Still kept.
      }
    }
  }

  /// Removes a record that can never be read or retried, with the superseded record saved with
  /// it. No credential is removed: whether the record was applied cannot be known.
  public func discardUnreadable() {
    guard isUnreadable else { return }
    clear()
  }

  /// What `discardRefused` does with the credential the request introduced, or nil when that
  /// discard is not offered. A reference equal to `configuredSecretRef`, the provider's current
  /// one, is not introduced by the request. An introduced one is removed unless an earlier
  /// attempt may still be applied, naming it.
  public func discardPreview(configuredSecretRef: String?) -> RefusedDiscard? {
    guard canDiscardRefused, let params else { return nil }
    guard let secretRef = params.secretRef, secretRef != configuredSecretRef else {
      return .noCredential
    }
    return hadUncertainAttempt ? .keptCredential : .removedCredential
  }

  /// Abandons the request the runtime definitely refused; returns nil, changing nothing, when
  /// that discard is not offered. The outcome is `discardPreview(configuredSecretRef:)`; a
  /// credential it removes is removed through `remover` first. A failed removal throws and
  /// keeps the request, so the discard can be repeated. The credential the request superseded
  /// stays in use, and its record is dropped.
  public func discardRefused(
    configuredSecretRef: String?, removing remover: ModelCredentialRemover
  ) async throws -> RefusedDiscard? {
    guard let outcome = discardPreview(configuredSecretRef: configuredSecretRef) else {
      return nil
    }
    if outcome == .removedCredential, let introduced = params?.secretRef {
      try await remover.remove(introduced)
    }
    clear()
    return outcome
  }

  /// Drops the saved request and the superseded record saved with it.
  private func clear() {
    params = nil
    isUnconfirmed = false
    wasRejected = false
    wasRefused = false
    hadUncertainAttempt = false
    defaults.removeObject(forKey: Self.requestKey)
    defaults.removeObject(forKey: Self.uncertainKey)
    recordSuperseded(nil)
  }

  private func recordSuperseded(_ record: (providerID: String, secretRef: String)?) {
    superseded = record
    if let record {
      defaults.set(
        ["providerId": record.providerID, "secretRef": record.secretRef],
        forKey: Self.supersededKey)
    } else {
      defaults.removeObject(forKey: Self.supersededKey)
    }
  }

  private func recordUnremoved(_ references: [String]) {
    unremoved = references
    if references.isEmpty {
      defaults.removeObject(forKey: Self.unremovedKey)
    } else {
      defaults.set(references, forKey: Self.unremovedKey)
    }
  }
}
