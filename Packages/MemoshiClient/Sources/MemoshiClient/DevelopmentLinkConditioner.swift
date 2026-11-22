import Foundation
import MemoshiTransport
import Synchronization

/// A development-only carrier decorator for the Mac debug menu. With no delay selected, the
/// authenticated carrier is returned unchanged, keeping its own queues and backpressure. With
/// a delay, every frame is held for that one-way time, first in first out in each direction,
/// in lines bounded by frames and bytes. Turning the delay on or off ends the live carrier as a
/// transport loss, so each connection is either delayed throughout or untouched; the client
/// then reconnects and replays from its applied cursor. Frames are never altered, duplicated or
/// reordered, nothing is resent, and peer checks stay in the wrapped carrier.
public final class DevelopmentLinkConditioner: ClientTransport {
  private struct Carrier: Sendable {
    let connection: any ClientConnection
    let isDelayed: Bool
  }

  private let base: any ClientTransport
  private let settings = LinkSettings()
  private let live = Mutex<Carrier?>(nil)

  /// Wraps the production carrier unless a test supplies another authenticated carrier.
  public init(wrapping base: any ClientTransport = UnixWebSocketTransport()) {
    self.base = base
  }

  /// The one-way delay given to frames entering the link.
  public var latency: Duration { settings.latency }

  /// Between nonzero values the change applies to later frames at once, and held frames keep
  /// their place in line. Turning the delay on or off drops the live carrier once.
  public func setLatency(_ latency: Duration) async {
    let value = max(.zero, latency)
    settings.latency = value
    guard let carrier = live.withLock({ $0 }), carrier.isDelayed != (value > .zero) else {
      return
    }
    _ = await Self.drop(carrier)
  }

  /// Ends the current carrier as an abrupt transport loss; frames still held in either
  /// direction are discarded, as on a cut link. Returns false when no carrier was open.
  @discardableResult
  public func dropConnection() async -> Bool {
    guard let carrier = live.withLock({ $0 }) else { return false }
    return await Self.drop(carrier)
  }

  /// Connects through the wrapped carrier, delaying it only while a delay is selected.
  public func connect(at paths: IPCPaths, policy: PeerPolicy) async throws -> any ClientConnection {
    let opened = try await base.connect(at: paths, policy: policy)
    guard settings.latency > .zero else {
      live.withLock { $0 = Carrier(connection: opened, isDelayed: false) }
      return opened
    }
    let delayed = ConditionedConnection(base: opened, settings: settings)
    await delayed.start()
    live.withLock { $0 = Carrier(connection: delayed, isDelayed: true) }
    return delayed
  }

  private static func drop(_ carrier: Carrier) async -> Bool {
    if let delayed = carrier.connection as? ConditionedConnection { return await delayed.drop() }
    await carrier.connection.close(
      code: ConditionedConnection.dropCode, reason: ConditionedConnection.dropReason)
    return true
  }
}

/// The delay shared by every connection the conditioner opens.
final class LinkSettings: Sendable {
  private let value = Mutex(Duration.zero)

  var latency: Duration {
    get { value.withLock { $0 } }
    set { value.withLock { $0 = newValue } }
  }
}

/// One authenticated carrier seen through a selected delay. Inbound frames are stamped when the
/// wrapped carrier yields them and released, one per consumer read, in arrival order; outbound
/// frames are stamped when submitted and written in submission order. Inbound capacity lasts
/// until consumer delivery. Outbound capacity includes queued frames and the unsettled base write.
actor ConditionedConnection: ClientConnection {
  /// Matches the client's own buffered-event bounds, so the decorator adds no unbounded queue.
  struct Limits: Sendable {
    var frames = 10_000
    var bytes = 8 * 1024 * 1024
  }

  private struct Held {
    let data: Data
    let due: ContinuousClock.Instant
  }

  private struct Outbound {
    let id: UInt64
    let data: Data
    let due: ContinuousClock.Instant
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct ActiveOutbound {
    let id: UInt64
    let bytes: Int
    var continuation: CheckedContinuation<Void, any Error>?
  }

  static let dropCode = 4000
  static let dropReason = "Development connection drop"

  nonisolated let peer: PeerIdentity
  private let base: any ClientConnection
  private let settings: LinkSettings
  private let limits: Limits
  private var held: [Held] = []
  private var heldBytes = 0
  private var inboundEnd: Result<Void, any Error>?
  private var deliveryWaiter: CheckedContinuation<Void, Never>?
  private var reader: Task<Void, Never>?
  private var outbound: [Outbound?] = []
  private var outboundHead = 0
  private var outboundVacancies = 0
  private var reservedFrames = 0
  private var reservedBytes = 0
  private var activeOutbound: ActiveOutbound?
  private var writer: Task<Void, Never>?
  private var nextOutboundID: UInt64 = 0
  private var terminal: (any Error)?
  private var shutdown: Task<Void, Never>?
  private var inboundCloser: Task<Void, Never>?

  init(base: any ClientConnection, settings: LinkSettings, limits: Limits = Limits()) {
    peer = base.peer
    self.base = base
    self.settings = settings
    self.limits = limits
  }

  /// One consumer, as for every carrier. Each read takes exactly one held frame when it is due.
  nonisolated var messages: AsyncThrowingStream<Data, any Error> {
    AsyncThrowingStream(unfolding: { try await self.nextDelivery() })
  }

  /// Begins reading the wrapped carrier.
  func start() {
    guard reader == nil else { return }
    let base = base
    reader = Task { [weak self] in
      do {
        for try await frame in base.messages {
          guard let self, await self.hold(frame) else { return }
        }
        await self?.endInbound(.success(()))
      } catch {
        await self?.endInbound(.failure(error))
      }
    }
  }

  func revalidatePeer(policy: PeerPolicy) async throws -> PeerIdentity {
    try await base.revalidatePeer(policy: policy)
  }

  func send(_ data: Data) async throws {
    try Task.checkCancellation()
    if let terminal { throw terminal }
    guard reservedFrames < limits.frames, data.count <= limits.bytes - reservedBytes else {
      throw IPCError.outboundOverflow
    }
    nextOutboundID &+= 1
    let id = nextOutboundID
    let due = ContinuousClock.now + settings.latency
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        guard !Task.isCancelled else {
          continuation.resume(throwing: CancellationError())
          return
        }
        reservedFrames += 1
        reservedBytes += data.count
        outbound.append(Outbound(id: id, data: data, due: due, continuation: continuation))
        #if DEBUG
          noteAdmission(inbound: 0, outbound: 1)
        #endif
        startWriter()
      }
    } onCancel: {
      Task { await self.cancelOutbound(id) }
    }
  }

  func close(code: Int, reason: String) async {
    await beginShutdown(code: code, reason: reason).value
    reader = nil
    inboundCloser = nil
  }

  func waitUntilClosed() async {
    if let shutdown {
      await shutdown.value
    } else {
      await base.waitUntilClosed()
      if let shutdown { await shutdown.value }
    }
  }

  /// Terminal for this carrier only: unsent and undelivered frames are lost, and the consumer
  /// sees a transport failure at its next read. Returns false if the carrier had already ended.
  func drop() async -> Bool {
    let started = terminal == nil
    await beginShutdown(code: Self.dropCode, reason: Self.dropReason).value
    reader = nil
    inboundCloser = nil
    return started
  }

  private func beginShutdown(code: Int, reason: String) -> Task<Void, Never> {
    if let shutdown { return shutdown }
    let error = IPCError.closed(code: code, reason: reason)
    terminal = error
    failOutbound(error)
    held.removeAll()
    heldBytes = 0
    wakeDelivery()
    reader?.cancel()
    writer?.cancel()
    let base = base
    let reader = reader
    let writer = writer
    let inboundCloser = inboundCloser
    let completion = Task {
      await base.close(code: code, reason: reason)
      await inboundCloser?.value
      await reader?.value
      await writer?.value
    }
    shutdown = completion
    return completion
  }

  private func nextDelivery() async throws -> Data? {
    while true {
      if let terminal { throw terminal }
      try Task.checkCancellation()
      if let next = held.first {
        if next.due > .now {
          try await Task.sleep(until: next.due, clock: .continuous)
          continue
        }
        held.removeFirst()
        heldBytes -= next.data.count
        return next.data
      }
      switch inboundEnd {
      case .success?: return nil
      case .failure(let error)?: throw error
      case nil: await waitForInbound()
      }
    }
  }

  private func waitForInbound() async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        if Task.isCancelled {
          continuation.resume()
        } else {
          deliveryWaiter = continuation
        }
      }
    } onCancel: {
      Task { await self.wakeDelivery() }
    }
  }

  private func wakeDelivery() {
    deliveryWaiter?.resume()
    deliveryWaiter = nil
  }

  private func hold(_ frame: Data) -> Bool {
    guard terminal == nil, inboundEnd == nil else { return false }
    guard held.count < limits.frames, frame.count <= limits.bytes - heldBytes else {
      // Like the wrapped carrier's own receive bound: fail the link rather than drop a frame.
      endInbound(.failure(IPCError.receiveOverflow))
      inboundCloser = Task { [base] in
        await base.close(code: 4429, reason: "Receive queue overflow")
      }
      return false
    }
    held.append(Held(data: frame, due: .now + settings.latency))
    heldBytes += frame.count
    #if DEBUG
      noteAdmission(inbound: 1, outbound: 0)
    #endif
    wakeDelivery()
    return true
  }

  private func endInbound(_ end: Result<Void, any Error>) {
    guard inboundEnd == nil else { return }
    inboundEnd = end
    wakeDelivery()
  }

  private func startWriter() {
    guard writer == nil, terminal == nil, reservedFrames > 0 else { return }
    writer = Task { await self.drainOutbound() }
  }

  private func outboundDeadline() -> ContinuousClock.Instant? {
    compactOutbound()
    return outboundHead < outbound.count ? outbound[outboundHead]?.due : nil
  }

  private func compactOutbound() {
    while outboundHead < outbound.count, outbound[outboundHead] == nil {
      outboundHead += 1
    }
    if outboundHead == outbound.count {
      outbound.removeAll(keepingCapacity: true)
      outboundHead = 0
      outboundVacancies = 0
    } else if outboundVacancies >= 1024, outboundVacancies >= outbound.count / 2 {
      outbound.removeAll { $0 == nil }
      outboundHead = 0
      outboundVacancies = 0
    }
  }

  private func takeOutbound() -> Outbound? {
    guard outboundHead < outbound.count, let frame = outbound[outboundHead] else { return nil }
    outbound[outboundHead] = nil
    outboundHead += 1
    outboundVacancies += 1
    compactOutbound()
    return frame
  }

  private func drainOutbound() async {
    while terminal == nil, !Task.isCancelled, let due = outboundDeadline() {
      if due > .now {
        #if DEBUG
          noteOutboundDelay()
        #endif
        do { try await Task.sleep(until: due, clock: .continuous) } catch { break }
        continue
      }
      guard let frame = takeOutbound() else { continue }
      activeOutbound = ActiveOutbound(
        id: frame.id, bytes: frame.data.count, continuation: frame.continuation)
      let result: Result<Void, any Error>
      do {
        try await base.send(frame.data)
        result = .success(())
      } catch {
        result = .failure(error)
      }
      finishActiveOutbound(result)
    }
    writer = nil
    startWriter()
  }

  private func releaseOutbound(bytes: Int) {
    reservedFrames -= 1
    reservedBytes -= bytes
  }

  private func finishActiveOutbound(_ result: Result<Void, any Error>) {
    guard let active = activeOutbound else { return }
    activeOutbound = nil
    releaseOutbound(bytes: active.bytes)
    active.continuation?.resume(with: result)
  }

  private func cancelOutbound(_ id: UInt64) {
    if activeOutbound?.id == id {
      let continuation = activeOutbound?.continuation
      activeOutbound?.continuation = nil
      continuation?.resume(throwing: CancellationError())
      // Canceling the caller cannot release bytes still owned by the carrier's write.
      writer?.cancel()
      return
    }
    guard let index = outbound.firstIndex(where: { $0?.id == id }),
      let frame = outbound[index]
    else { return }
    outbound[index] = nil
    outboundVacancies += 1
    releaseOutbound(bytes: frame.data.count)
    if activeOutbound == nil, index == outboundHead { writer?.cancel() }
    compactOutbound()
    frame.continuation.resume(throwing: CancellationError())
  }

  private func failOutbound(_ error: any Error) {
    let continuation = activeOutbound?.continuation
    activeOutbound?.continuation = nil
    continuation?.resume(throwing: error)
    for index in outboundHead..<outbound.count {
      guard let frame = outbound[index] else { continue }
      outbound[index] = nil
      releaseOutbound(bytes: frame.data.count)
      frame.continuation.resume(throwing: error)
    }
    outbound.removeAll()
    outboundHead = 0
    outboundVacancies = 0
  }

  #if DEBUG
    private var admittedInbound = 0
    private var admittedOutbound = 0
    private var admissionWaiters:
      [(inbound: Int, outbound: Int, CheckedContinuation<Void, Never>)] =
        []
    private var outboundDelays = 0
    private var delayWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func waitUntilDelayingOutbound(_ total: Int) async {
      if outboundDelays >= total { return }
      await withCheckedContinuation { delayWaiters.append((total, $0)) }
    }

    private func noteOutboundDelay() {
      outboundDelays += 1
      let ready = delayWaiters.filter { $0.0 <= outboundDelays }
      delayWaiters.removeAll { $0.0 <= outboundDelays }
      for (_, continuation) in ready { continuation.resume() }
    }

    /// Test observation only, compiled out of release builds: suspends until at least these
    /// totals have entered the inbound and outbound lines.
    func waitUntilAdmitted(inbound inboundTotal: Int = 0, outbound outboundTotal: Int = 0) async {
      if admittedInbound >= inboundTotal, admittedOutbound >= outboundTotal { return }
      await withCheckedContinuation {
        admissionWaiters.append((inbound: inboundTotal, outbound: outboundTotal, $0))
      }
    }

    private func noteAdmission(inbound: Int, outbound: Int) {
      admittedInbound += inbound
      admittedOutbound += outbound
      var waiting: [(inbound: Int, outbound: Int, CheckedContinuation<Void, Never>)] = []
      for waiter in admissionWaiters {
        if admittedInbound >= waiter.inbound, admittedOutbound >= waiter.outbound {
          waiter.2.resume()
        } else {
          waiting.append(waiter)
        }
      }
      admissionWaiters = waiting
    }
  #endif
}
