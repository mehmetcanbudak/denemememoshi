import Foundation
import MemoshiDevice

/// Carrier choices in attempt/fallback priority order: direct, relay, then iCloud.
/// Route availability does not establish membership or execution authority.
public enum AppleDeviceRoute: String, Codable, Hashable, Sendable, CaseIterable {
  case direct, relay, icloud
}

/// First connected wins; later direct availability always upgrades. A relay appearing after an
/// iCloud winner does not interrupt that stream. Disconnect falls back to the best live route.
public struct DeviceRouteSelection: Sendable {
  /// Current live carrier, or `nil` when none is selected.
  public private(set) var selected: AppleDeviceRoute?
  /// Routes currently reported connected, including nonselected catch-up carriers.
  public private(set) var connected: Set<AppleDeviceRoute> = []

  /// Starts with no connected or selected carrier.
  public init() {}

  /// Records availability, selecting the first carrier or upgrading an existing selection to
  /// direct. Returns whether selection changed; a late relay never displaces iCloud.
  @discardableResult
  public mutating func didConnect(_ route: AppleDeviceRoute) -> Bool {
    connected.insert(route)
    let previous = selected
    if selected == nil || route == .direct { selected = route }
    return selected != previous
  }

  /// Removes availability and, only if the selected route vanished, falls back in declared
  /// direct/relay/iCloud order. Returns whether selection changed.
  @discardableResult
  public mutating func didDisconnect(_ route: AppleDeviceRoute) -> Bool {
    connected.remove(route)
    let previous = selected
    if selected == route {
      selected = AppleDeviceRoute.allCases.first(where: { connected.contains($0) })
    }
    return selected != previous
  }
}

/// One live carrier of opaque MLS bytes. These closures do not decrypt or grant credentials.
public struct DeviceRouteEndpoint: Sendable {
  let id = UUID()
  let connectionID: Data?
  let frames: AsyncThrowingStream<Data, any Error>
  let send: @Sendable (Data) async throws -> Void
  let close: @Sendable () async -> Void

  /// Wraps an already-established carrier and transfers its close/send lifecycle to the owner.
  /// `connectionID`, when supplied, is the authenticated tie-break value for duplicate direct
  /// carriers; frames remain opaque and transport failures propagate through the closures/stream.
  public init(
    frames: AsyncThrowingStream<Data, any Error>,
    connectionID: Data? = nil,
    send: @escaping @Sendable (Data) async throws -> Void,
    close: @escaping @Sendable () async -> Void
  ) {
    self.frames = frames
    self.connectionID = connectionID
    self.send = send
    self.close = close
  }

  /// Activation is not implicit. The receiving transport MUST share this mailbox's durable
  /// spool: its stream coalesces wake samples while the complete encrypted inbox stays on disk.
  public static func cloudMailbox(_ mailbox: CloudKitMailbox) async throws -> DeviceRouteEndpoint {
    let subscription = try await mailbox.subscribe()
    return DeviceRouteEndpoint(
      frames: subscription.frames,
      send: { bytes in
        try await mailbox.enqueueCiphertext(bytes)
        try await mailbox.flush()
      },
      close: { await mailbox.unsubscribe(subscription) })
  }
}

/// One deferred carrier attempt; constructing it performs no connection work.
public struct DeviceRouteCandidate: Sendable {
  /// Carrier class used for attempt ordering, selection, and route events.
  public let route: AppleDeviceRoute
  let connect: @Sendable () async throws -> DeviceRouteEndpoint

  /// Stores a connection closure that must return an authenticated endpoint or throw.
  /// The racer invokes it at the route's staggered start and owns any accepted endpoint.
  public init(
    route: AppleDeviceRoute, connect: @escaping @Sendable () async throws -> DeviceRouteEndpoint
  ) {
    self.route = route
    self.connect = connect
  }
}

/// Local carrier lifecycle observations, not delivery acknowledgements or authority decisions.
public enum DeviceRouteEvent: Sendable {
  case connected(AppleDeviceRoute)
  case selected(AppleDeviceRoute?)
  case disconnected(AppleDeviceRoute)
  case connectionFailed(AppleDeviceRoute)
  case rejectedFrame(AppleDeviceRoute)
}

/// Happy-Eyeballs-style carrier racing. No route is started in init. The direct attempt is never
/// cancelled merely because relay/iCloud won first, so it can perform the required live upgrade.
/// Recovery supplies the durable pending ciphertexts; retries/upgrades NEVER reseal MLS frames.
public actor DeviceLinkRacer {
  /// Unbounded lifecycle event stream, finished when the racer stops.
  public nonisolated let events: AsyncStream<DeviceRouteEvent>
  private let continuation: AsyncStream<DeviceRouteEvent>.Continuation
  private let receive: @Sendable (Data) async throws -> Void
  private let pending: @Sendable () async throws -> [Data]
  private var selection = DeviceRouteSelection()
  private var endpoints: [AppleDeviceRoute: DeviceRouteEndpoint] = [:]
  private var connections: [AppleDeviceRoute: Task<Void, Never>] = [:]
  private var readers: [AppleDeviceRoute: Task<Void, Never>] = [:]
  private var generation = UUID()
  private var closed = false

  /// Retains callbacks without starting routes. `pending` supplies original durable ciphertexts
  /// for replay; `receive` must authenticate/apply incoming bytes and throw on rejection.
  public init(
    pending: @escaping @Sendable () async throws -> [Data],
    receive: @escaping @Sendable (Data) async throws -> Void
  ) {
    self.pending = pending
    self.receive = receive
    (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
  }

  /// Whether `start` accepts these candidates now; throws its lifecycle error otherwise.
  func requireStartable(_ candidates: [DeviceRouteCandidate]) throws {
    guard !closed, connections.isEmpty,
      Set(candidates.map(\.route)).count == candidates.count
    else {
      throw AppleDeviceError.invalidState("route race lifecycle")
    }
  }

  /// The stagger is a declared qualification input, not a measured O10 production default.
  /// One-shot: each candidate is attempted once and a lost relay or iCloud route is never
  /// dialled again, so a second start with candidates throws. Build a new racer to reconnect.
  public func start(_ candidates: [DeviceRouteCandidate], stagger: Duration) throws {
    try requireStartable(candidates)
    let epoch = generation
    let ordered = candidates.sorted { Self.rank($0.route) < Self.rank($1.route) }
    for (index, candidate) in ordered.enumerated() {
      connections[candidate.route] = Task { [weak self] in
        do {
          if index > 0 { try await Task.sleep(for: stagger * index) }
          let endpoint = try await candidate.connect()
          guard let self else {
            await endpoint.close()
            return
          }
          await self.connected(endpoint, route: candidate.route, generation: epoch)
        } catch {
          guard let self else { return }
          await self.failedConnection(candidate.route, generation: epoch)
        }
      }
    }
  }

  /// Only hand over an endpoint after its peer authentication completes.
  public func attach(_ endpoint: DeviceRouteEndpoint, route: AppleDeviceRoute) async {
    await connected(endpoint, route: route, generation: generation)
  }

  /// Direct carries live traffic; every connected enabled store-and-forward route also receives
  /// the identical frame so either relay or iCloud alone can later supply catch-up.
  func publish(_ ciphertext: Data) async throws {
    guard !closed else { throw AppleDeviceError.closed }
    guard let selected = selection.selected else { throw AppleDeviceError.authorityUnavailable }
    let routes = [selected] + AppleDeviceRoute.allCases.filter { $0 != selected && $0 != .direct }
    var delivered = false
    for route in routes {
      guard let endpoint = endpoints[route] else { continue }
      do {
        try await endpoint.send(ciphertext)
        delivered = true
      } catch { await disconnected(route, endpointID: endpoint.id) }
    }
    guard delivered else { throw AppleDeviceError.authorityUnavailable }
  }

  private func connected(
    _ endpoint: DeviceRouteEndpoint, route: AppleDeviceRoute, generation epoch: UUID
  ) async {
    guard !closed, epoch == generation else {
      await endpoint.close()
      return
    }
    if let existing = endpoints[route] {
      if route == .direct, let old = existing.connectionID, let new = endpoint.connectionID,
        old == new || old.lexicographicallyPrecedes(new)
      {
        await endpoint.close()
        return
      }
      readers.removeValue(forKey: route)?.cancel()
      endpoints[route] = endpoint
      await existing.close()
      guard !closed, epoch == generation, endpoints[route]?.id == endpoint.id else {
        await endpoint.close()
        return
      }
    } else {
      endpoints[route] = endpoint
    }
    let changed = selection.didConnect(route)
    continuation.yield(.connected(route))
    if changed { continuation.yield(.selected(selection.selected)) }
    readers[route] = Task { [weak self] in
      do {
        for try await frame in endpoint.frames {
          guard let self else { return }
          try await self.receive(frame)
        }
      } catch {
        if !Task.isCancelled { await self?.rejected(route) }
      }
      await self?.disconnected(route, endpointID: endpoint.id)
    }
    do {
      // Replay all unacknowledged original frames on every newly established route. The receiver
      // buffers stream gaps and deduplicates by authenticated message ID before host application.
      for frame in try await pending() { try await endpoint.send(frame) }
    } catch { await disconnected(route, endpointID: endpoint.id) }
  }

  private func disconnected(_ route: AppleDeviceRoute, endpointID: UUID) async {
    guard let endpoint = endpoints[route], endpoint.id == endpointID else { return }
    endpoints[route] = nil
    readers.removeValue(forKey: route)?.cancel()
    let changed = selection.didDisconnect(route)
    continuation.yield(.disconnected(route))
    if changed { continuation.yield(.selected(selection.selected)) }
    await endpoint.close()
    if changed {
      if let route = selection.selected, let endpoint = endpoints[route] {
        do { for frame in try await pending() { try await endpoint.send(frame) } } catch {
          await disconnected(route, endpointID: endpoint.id)
        }
      }
    }
  }

  private func failedConnection(_ route: AppleDeviceRoute, generation epoch: UUID) {
    if !closed, epoch == generation { continuation.yield(.connectionFailed(route)) }
  }

  private func rejected(_ route: AppleDeviceRoute) { continuation.yield(.rejectedFrame(route)) }

  private static func rank(_ route: AppleDeviceRoute) -> Int {
    switch route {
    case .direct: 0
    case .relay: 1
    case .icloud: 2
    }
  }

  /// Permanently stops attempts/readers, closes live endpoints, and finishes events.
  /// Durable pending ciphertexts remain owned by the supplied replay store.
  public func stop() async {
    closed = true
    generation = UUID()
    for task in connections.values { task.cancel() }
    connections.removeAll()
    for task in readers.values { task.cancel() }
    readers.removeAll()
    let active = endpoints.values
    endpoints.removeAll()
    for endpoint in active { await endpoint.close() }
    continuation.finish()
  }
}
