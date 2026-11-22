import Foundation
import MemoshiProtocol
import MemoshiTransport

extension MemoshiClient {
  /// Attach one consumer for the lifetime of the client. The stream survives disconnects so
  /// the same stores can apply reconnect replay. Canceling its iterator disconnects the client.
  /// A slow consumer never loses a durable event. UI-only frames give way first: the oldest
  /// undelivered ones are dropped, from the client's buffer of 10,000 events and 8 MiB and from
  /// this stream's 256 elements (protocol.md §7.4, §11). A durable event that still does not fit
  /// ends the connection, as the daemon's 4429 does. The client reconnects and replays from the
  /// applied cursor, waiting longer after each overflow until the consumer catches up.
  public func events() throws -> AsyncThrowingStream<ClientEvent, any Error> {
    guard eventConsumerID == nil else { throw ClientError.eventConsumerAlreadyAttached }
    let id = UUID()
    // A full buffer evicts its oldest element; `emit` decides whether that loss is allowed.
    let (stream, continuation) = AsyncThrowingStream<ClientEvent, any Error>.makeStream(
      bufferingPolicy: .bufferingNewest(256))
    eventConsumerID = id
    eventContinuation = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.eventConsumerEnded(id) }
    }
    if let request = statusValue.resync { try emit(.resyncRequired(request)) }
    try drainEvents()
    return stream
  }

  /// Acknowledge exactly the current receipt after the real consumer has applied it. Receipts
  /// are serialized, so neither a later event nor a stale connection can jump the cursor.
  public func acknowledgeApplied(_ delivery: EventDelivery) throws {
    guard outstandingDelivery == delivery, let seq = delivery.envelope.seq,
      let cursor = statusValue.lastAppliedSeq, cursor < Int64.max, seq == cursor + 1
    else { throw ClientError.staleAcknowledgment }
    statusValue.lastAppliedSeq = seq
    lastAppliedTs = delivery.envelope.ts
    outstandingDelivery = nil
    outstandingBytes = 0
    try drainEvents()
    finishReplayIfApplied()
    publishStatus()
  }

  /// Acknowledge the exact subscribe barrier, only after list/history bootstrap has actually
  /// covered it. Keep each store's own asOf and filter later deliveries against that watermark.
  /// Receiving hello, inspecting status or merely receiving events is not a bootstrap.
  public func completeResync(_ request: ResyncRequest, appliedThrough: Int64) throws {
    guard statusValue.resync == request, connection != nil, subscribed else {
      throw ClientError.staleAcknowledgment
    }
    guard appliedThrough == request.head else {
      throw ClientError.invalidResyncWatermark(expected: request.head, actual: appliedThrough)
    }
    statusValue.lastAppliedSeq = request.head
    lastAppliedTs = request.headTs
    cursorLogId = statusValue.hello?.logId
    statusValue.resync = nil
    replayHead = request.head
    try drainEvents()
    finishReplayIfApplied()
    publishStatus()
  }

  /// Replaces this connection's bounded live-content focus set.
  public func setFocus(_ conversations: [ConversationID]) async throws {
    let requested = try FocusList(conversations)
    guard let hello = statusValue.hello, connection != nil else { throw ClientError.notConnected }
    guard !subscriptionPending, !subscriptionControlInFlight,
      subscriptionTask == nil, connectionTask == nil
    else {
      throw ClientError.subscriptionBusy
    }
    guard hello.capabilities.contains(where: { $0.rawValue == "events.focus.v1" }) else {
      throw RPCError(
        message: "events.focus.v1 was not negotiated",
        data: RPCErrorData(details: .capabilityMissing))
    }
    guard conversations.count <= hello.limits.maxFocus else {
      throw ClientError.protocolViolation("Focus exceeds negotiated limit")
    }
    let expected = generation
    subscriptionControlInFlight = true
    defer { finishSubscriptionControl(generation: expected) }
    _ = try await request(
      EventsFocus.self, EventsFocusParams(conversationIds: requested), generation: expected)
    guard expected == generation else { throw ClientError.disconnected }
    focus = requested
  }

  /// Stops event delivery while retaining the last consumer-applied cursor.
  public func unsubscribe() async throws {
    try Task.checkCancellation()
    guard connection != nil, statusValue.hello != nil else { throw ClientError.notConnected }
    guard !subscriptionPending, !subscriptionControlInFlight,
      subscriptionTask == nil, connectionTask == nil
    else {
      throw ClientError.subscriptionBusy
    }
    let expected = generation
    subscriptionControlInFlight = true
    defer { finishSubscriptionControl(generation: expected) }
    do {
      _ = try await request(EventsUnsubscribe.self, EmptyParams(), generation: expected)
    } catch {
      await subscriptionControlFailed(error, generation: expected)
      throw error
    }
    guard expected == generation else { throw ClientError.disconnected }
    subscribed = false
    clearEventDelivery()
    statusValue.resync = nil
    statusValue.state = .syncing
    publishStatus()
  }

  /// Resume a deliberately unsubscribed stream, using only the last consumer-applied cursor.
  public func subscribe() async throws {
    try Task.checkCancellation()
    guard connection != nil, statusValue.hello != nil else { throw ClientError.notConnected }
    guard !subscribed else { return }
    guard !subscriptionPending, !subscriptionControlInFlight,
      subscriptionTask == nil, connectionTask == nil
    else {
      throw ClientError.subscriptionBusy
    }
    let expected = generation
    subscriptionControlInFlight = true
    defer { finishSubscriptionControl(generation: expected) }
    do {
      try await subscribe(
        generation: expected,
        reason: statusValue.lastAppliedSeq == nil ? .coldStart : .cursorExpired)
    } catch {
      await subscriptionControlFailed(error, generation: expected)
      throw error
    }
  }

  /// A local admission refusal sent nothing, so the live connection and its calls stay. An
  /// outbound overflow sent nothing either; the carrier has already begun closing with 4429, and
  /// the receive loop reports that loss. Any other failure leaves the daemon's subscription
  /// unknown and the connection is replaced. A caller's cancellation is not a request to stay
  /// disconnected: it reconnects like a loss.
  func subscriptionControlFailed(_ error: any Error, generation expected: UInt64) async {
    if case .inFlightLimit = error as? ClientError { return }
    if error as? IPCError == .outboundOverflow { return }
    let loss: any Error =
      error is CancellationError
      ? ClientError.connectionClosed(code: 1006, reason: "Subscription control canceled") : error
    await connectionLost(loss, generation: expected)
  }

  func finishSubscriptionControl(generation expected: UInt64) {
    guard generation == expected else { return }
    subscriptionControlInFlight = false
    startResubscribeIfNeeded()
  }

  func subscribe(
    generation expected: UInt64, reason: ResyncRequest.Reason, discardingCursor: Bool = false
  ) async throws {
    // D131: a cursor taken from another event log is never sent. This is decided for every
    // subscribe, not only at connect, so a resubscribe before that resync is completed
    // withholds it too. A restored copy keeps its identity; `afterTs` covers that case.
    let foreign = cursorLogId.map { $0 != statusValue.hello?.logId } ?? false
    let after =
      reason == .serverRequested || discardingCursor || foreign ? nil : statusValue.lastAppliedSeq
    subscriptionPending = true
    statusValue.state = .syncing
    publishStatus()
    do {
      let params =
        after.map { EventsSubscribeParams(after: $0, afterTs: lastAppliedTs, focus: focus) }
        ?? EventsSubscribeParams(after: nil, focus: focus)
      let result = try await request(EventsSubscribe.self, params, generation: expected)
      guard expected == generation, connection != nil else { throw ClientError.disconnected }
      guard result.head >= 0, result.minRetainedSeq >= 0,
        result.minRetainedSeq <= result.head
          || result.head < Int64.max && result.minRetainedSeq == result.head + 1
      else { throw ClientError.protocolViolation("Invalid subscription watermarks") }
      switch result.mode {
      case .resync:
        eventQueue.removeAll()
        transientQueue.removeAll()
        outstandingDelivery = nil
        outstandingBytes = 0
        receivedThrough = result.head
        replayHead = nil
        // The trigger belongs to the one server-requested resync it caused, never a later one.
        let trigger = reason == .serverRequested ? pendingResyncTrigger : nil
        pendingResyncTrigger = nil
        let request = ResyncRequest(
          head: result.head, minRetainedSeq: result.minRetainedSeq, reason: reason,
          trigger: trigger, headTs: result.headTs)
        statusValue.resync = request
        if eventContinuation != nil { try emit(.resyncRequired(request)) }
      case .replay:
        guard let after, result.head >= after else {
          throw ClientError.protocolViolation("Replay requires a valid applied cursor")
        }
        if receivedThrough == nil { receivedThrough = after }
        replayHead = result.head
      case .unknown:
        throw ClientError.protocolViolation("Unknown subscription mode")
      }
      subscribed = true
      subscriptionPending = false
      // UI-only frames first: each still waits for its own `after` watermark, so none overtakes
      // the durable event it follows.
      while let entry = stagedTransients.popFirst() { try acceptEvent(entry) }
      while let entry = stagedEvents.popFirst() { try acceptEvent(entry) }
      try drainEvents()
      finishReplayIfApplied()
      publishStatus()
      startResubscribeIfNeeded()
    } catch {
      if expected == generation {
        subscriptionPending = false
        stagedEvents.removeAll()
        stagedTransients.removeAll()
      }
      throw error
    }
  }

  func acceptEvent(_ entry: EventBuffer.Entry) throws {
    let envelope = entry.envelope
    if let seq = envelope.seq {
      guard seq > 0, let through = receivedThrough else {
        throw ClientError.protocolViolation("Durable event without a subscription baseline")
      }
      if seq <= through { return }
      guard through < Int64.max, seq == through + 1 else {
        needsResubscribe = true
        statusValue.state = .syncing
        publishStatus()
        startResubscribeIfNeeded()
        return
      }
      try requireEventRoom(for: entry.bytes)
      eventQueue.append(entry)
      receivedThrough = seq
    } else {
      guard let after = envelope.after, after >= 0 else {
        throw ClientError.protocolViolation("UI-only event without a valid after watermark")
      }
      if envelope.type == "system.resync_required" {
        // The resync request retains this original, leniently decoded control envelope.
        pendingResyncTrigger = envelope
        needsResubscribe = true
        needsFullResync = true
        startResubscribeIfNeeded()
      } else if makeEventRoom(for: entry.bytes) {
        transientQueue.append(entry)
      }
      // Otherwise the buffer holds only durable events, and this UI-only frame is dropped.
    }
    try drainEvents()
  }

  func drainEvents() throws {
    guard eventContinuation != nil, statusValue.resync == nil, !subscriptionPending,
      let cursor = statusValue.lastAppliedSeq
    else { return }
    // UI-only ordering cannot block the durable event needed to reach its `after` watermark.
    // None is emitted behind an undelivered durable event, so a full buffer evicts only frames.
    while outstandingDelivery == nil, let entry = transientQueue.first,
      let after = entry.envelope.after, after <= cursor
    {
      _ = transientQueue.popFirst()
      try emit(.transient(entry.envelope))
    }
    guard outstandingDelivery == nil, let entry = eventQueue.popFirst() else { return }
    let delivery = EventDelivery(envelope: entry.envelope)
    outstandingDelivery = delivery
    outstandingBytes = entry.bytes
    try emit(.event(delivery))
  }

  func finishReplayIfApplied() {
    guard statusValue.resync == nil, !subscriptionPending, subscribed,
      !needsResubscribe, let target = replayHead,
      let cursor = statusValue.lastAppliedSeq, cursor >= target
    else { return }
    replayHead = nil
    statusValue.state = .connected
    // Caught up: the next buffer overflow starts from the first reconnect delay again.
    overflowReconnectDelay = 100
  }

  func startResubscribeIfNeeded() {
    guard needsResubscribe, subscriptionTask == nil, !subscriptionPending,
      !subscriptionControlInFlight, connection != nil, statusValue.hello != nil
    else { return }
    let expected = generation
    subscriptionTask = Task { [weak self] in
      await self?.performResubscriptions(generation: expected)
    }
  }

  private func performResubscriptions(generation expected: UInt64) async {
    var full = false
    do {
      while needsResubscribe, expected == generation {
        full = needsFullResync
        needsResubscribe = false
        needsFullResync = false
        try await subscribe(
          generation: expected, reason: full ? .serverRequested : .cursorExpired)
      }
      if expected == generation { subscriptionTask = nil }
    } catch {
      if expected == generation { subscriptionTask = nil }
      if expected == generation, case .inFlightLimit = error as? ClientError {
        // Nothing was sent. Keep the request; `finishCall` retries it when a call slot frees.
        needsResubscribe = true
        needsFullResync = needsFullResync || full
        return
      }
      await connectionLost(error, generation: expected)
    }
  }

  /// Frames that arrive while a subscribe is pending wait for its result. UI-only frames wait
  /// apart from the others so that backpressure can still drop them. The resync request is a
  /// control frame and is never dropped.
  func stage(_ entry: EventBuffer.Entry) throws {
    if entry.envelope.seq == nil, entry.envelope.type != "system.resync_required" {
      if makeEventRoom(for: entry.bytes) { stagedTransients.append(entry) }
    } else {
      try requireEventRoom(for: entry.bytes)
      stagedEvents.append(entry)
    }
  }

  /// protocol.md §7.4 and §11: UI-only frames may be dropped under backpressure, durable events
  /// never are. Drops the oldest undelivered UI-only frames until `bytes` more fit, and reports
  /// whether they do. Accepted frames arrived before any staged one, so they go first.
  func makeEventRoom(for bytes: Int) -> Bool {
    while !eventBufferHasRoom(for: bytes) {
      guard transientQueue.popFirst() != nil || stagedTransients.popFirst() != nil else {
        return false
      }
    }
    return true
  }

  /// A durable event or a resync request that still finds no room ends the connection. Nothing
  /// applied is lost: the cursor moves only on acknowledgment, and the reconnect replays from it.
  func requireEventRoom(for bytes: Int) throws {
    guard makeEventRoom(for: bytes) else { throw ClientError.eventBufferOverflow }
  }

  private func eventBufferHasRoom(for bytes: Int) -> Bool {
    let count =
      eventQueue.count + stagedEvents.count + stagedTransients.count + transientQueue.count
      + (outstandingDelivery == nil ? 0 : 1)
    let bufferedBytes =
      eventQueue.bytes + stagedEvents.bytes + stagedTransients.bytes + transientQueue.bytes
      + outstandingBytes
    return count < maximumBufferedEvents && bytes <= maximumBufferedBytes - bufferedBytes
  }

  func emit(_ event: ClientEvent) throws {
    guard let eventContinuation else { return }
    switch eventContinuation.yield(event) {
    case .enqueued: break
    // The evicted oldest element was a UI-only frame, which backpressure may drop.
    case .dropped(.transient): break
    // Any other eviction lost a receipt or a resync barrier the consumer never saw. Drains never
    // yield behind either, so this does not happen; if it did, the stream ends.
    case .dropped:
      eventContinuation.finish(throwing: ClientError.eventBufferOverflow)
      throw ClientError.eventBufferOverflow
    case .terminated: throw ClientError.disconnected
    @unknown default: throw ClientError.eventBufferOverflow
    }
  }

  func clearEventDelivery() {
    eventQueue.removeAll()
    stagedEvents.removeAll()
    stagedTransients.removeAll()
    transientQueue.removeAll()
    outstandingDelivery = nil
    outstandingBytes = 0
    receivedThrough = statusValue.lastAppliedSeq
    replayHead = nil
    needsResubscribe = false
    needsFullResync = false
    pendingResyncTrigger = nil
  }

  func eventConsumerEnded(_ id: UUID) async {
    guard eventConsumerID == id else { return }
    eventConsumerID = nil
    eventContinuation = nil
    await disconnect()
  }
}
