import Foundation
import MemoshiProtocol
import MemoshiStore

extension RPCSession {
  func cancelSubscription() {
    generation &+= 1
    subscribed = false
    replaying = false
    flushing = false
    readerTask?.cancel()
    replayTask?.cancel()
    flushTask?.cancel()
    readerTask = nil
    replayTask = nil
    flushTask = nil
    queue.removeAll()
    resumeResponseWaiters()
  }

  func subscribe(_ params: EventsSubscribeParams, id: JSONRPCID) async throws {
    if params.focus != nil, hasFocusCapability == false {
      try await sendError(id: id, details: .capabilityMissing, message: "Focus was not negotiated.")
      return
    }
    let observation: EventObservation
    // The bus accepts at most 10,000: one commit may publish more events than its default
    // buffer holds, and this session's own 10,000-frame / 8 MiB queue is the documented limit.
    do {
      observation = try await store.observeEvents(after: params.after, capacity: 10_000)
    } catch StoreError.invalidReplayCursor {
      try await invalidParams(id)
      return
    }
    let bounds = observation.bounds
    // D131: a copy restored from a backup keeps its log identity, so the identity alone cannot
    // tell that a cursor was taken from another history. The time of the event at the cursor
    // can: a different time refuses the cursor like an expired one, and nothing is replayed.
    // So does a stated time that cannot be checked because the event there is pruned. A
    // client that states no time is as before; position 0 never had an event.
    var replay = bounds.canReplay(after: params.after)
    if replay, let after = params.after, after > 0, let stated = params.afterTs,
      try await store.eventTimestamp(seq: after) != stated
    {
      replay = false
    }
    // What a client that resyncs to this head states when it resumes.
    let headTs = try await store.eventTimestamp(seq: bounds.head)
    cancelSubscription()
    subscribed = true
    replaying = true
    let current = generation
    focus = Set(params.focus?.elements ?? [])
    liveAfter = bounds.head
    lastSent = replay ? (params.after ?? bounds.head) : bounds.head
    readerTask = Task { [weak self] in
      do {
        for try await event in observation.events {
          guard let self, Task.isCancelled == false else { return }
          try await self.enqueue(event, generation: current)
        }
      } catch is CancellationError {
        return
      } catch EventBusError.overflow {
        await self?.close(code: 4429, reason: "event_buffer_overflow")
      } catch {
        await self?.close(code: 4500, reason: "event_stream_failed")
      }
    }
    try await send(
      EventsSubscribe.self, id: id,
      result: EventsSubscribeResult(
        mode: replay ? .replay : .resync, head: bounds.head, headTs: headTs,
        minRetainedSeq: bounds.minRetainedSeq))
    guard current == generation, closed == false else { return }
    if replay, let after = params.after {
      replayTask = Task { [weak self] in
        await self?.replay(after: after, through: bounds.head, generation: current)
      }
    } else {
      finishReplay(generation: current)
    }
  }

  func replay(after: Int64, through: Int64, generation current: UInt64) async {
    do {
      var cursor = after
      while cursor < through, current == generation, closed == false, Task.isCancelled == false {
        let page = try await store.replay(after: cursor, through: through)
        guard current == generation, closed == false else { return }
        try await sendEvents(page.events, generation: current)
        guard current == generation, closed == false else { return }
        cursor = page.nextAfter
      }
      finishReplay(generation: current)
    } catch StoreError.cursorExpired {
      do { try await requireResync(generation: current) } catch {
        await close(code: 4500, reason: "resync_failed")
      }
    } catch is CancellationError {
      return
    } catch {
      if current == generation { await close(code: 4500, reason: "replay_failed") }
    }
  }

  func finishReplay(generation current: UInt64) {
    guard current == generation, closed == false else { return }
    replaying = false
    replayTask = nil
    scheduleFlush(generation: current)
    resumeResponseWaiters()
  }

  func requireResync(generation current: UInt64) async throws {
    let bounds = try await store.replayBounds()
    guard current == generation, closed == false else { return }
    liveAfter = bounds.head
    lastSent = bounds.head
    queue.removeDurable(through: bounds.head)
    let event = EventEnvelope(
      seq: nil, after: bounds.head, ts: IDGenerator.nowMilliseconds(), deviceId: store.deviceID,
      actor: Actor(kind: .system), subject: ObjectRef(kind: "system", id: "memoshid"),
      scope: EventScope(),
      event: .systemResyncRequired(SystemResyncRequiredPayload(reason: .cursorExpired)))
    try await connection.send(encoder.encode(EventNotification(event: event)))
    finishReplay(generation: current)
  }

  func enqueueLive(_ event: EventEnvelope) async throws {
    try await enqueue(event, generation: generation)
  }

  func enqueue(_ event: EventEnvelope, generation current: UInt64) async throws {
    guard current == generation, closed == false, subscribed else { return }
    if let seq = event.seq {
      guard seq > liveAfter else { return }
    } else if let conversation = event.scope.conversationId, focus.contains(conversation) == false {
      return
    }
    let data = try encoder.encode(EventNotification(event: event))
    guard data.count <= 4_194_304 else {
      await close(code: 4429, reason: "event_frame_too_large")
      return
    }
    // §11: UI-only frames are merged, then dropped; durable events never are.
    guard queue.admit(EventSendQueue.Frame(event, data: data), encoder: encoder) else {
      await close(code: 4429, reason: "event_queue_overflow")
      return
    }
    if replaying == false {
      scheduleFlush(generation: current)
      resumeResponseWaiters()
    }
  }

  /// protocol.md §4: on a subscribed connection the events a request wrote are sent before its
  /// response. The store's head once the handler has returned or thrown covers every event it
  /// committed.
  func sendWrittenEvents() async throws {
    guard subscribed, closed == false else { return }
    let head = try await store.replayBounds().head
    while subscribed, closed == false, lastSent < head {
      if replaying == false, flushing == false, queue.hasFramesToSend {
        // A waiting response does not also wait out the coalescing delay.
        flushTask?.cancel()
        flushTask = nil
        await flush(generation: generation)
      } else {
        await withCheckedContinuation { responseWaiters.append($0) }
      }
    }
  }

  /// Every change to `lastSent`, `replaying` or the subscription re-evaluates held responses.
  func resumeResponseWaiters() {
    let waiting = responseWaiters
    responseWaiters.removeAll()
    for waiter in waiting { waiter.resume() }
  }

  func scheduleFlush(generation current: UInt64) {
    guard queue.hasFramesToSend, flushTask == nil, flushing == false, replaying == false
    else { return }
    flushTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
      await self?.flush(generation: current)
    }
  }

  func flush(generation current: UInt64) async {
    guard current == generation, closed == false, replaying == false, flushing == false else {
      return
    }
    flushTask = nil
    flushing = true
    do {
      while current == generation, closed == false, let batch = queue.beginBatch() {
        try await connection.send(batch.data)
        guard current == generation, closed == false else { return }
        if let sequence = batch.lastSeq {
          guard sequence >= lastSent else {
            await close(code: 4500, reason: "event_order_failed")
            return
          }
          lastSent = sequence
          resumeResponseWaiters()
        }
        queue.finishBatch()
      }
      if current == generation { flushing = false }
    } catch {
      if current == generation { await close(code: 4500, reason: "event_send_failed") }
    }
  }

  func sendEvents(_ events: [EventEnvelope], generation current: UInt64) async throws {
    var frames: [EventSendQueue.Frame] = []
    frames.reserveCapacity(events.count)
    for event in events {
      frames.append(
        EventSendQueue.Frame(event, data: try encoder.encode(EventNotification(event: event))))
    }
    var index = 0
    while index < frames.count, current == generation, closed == false {
      let end = EventSendQueue.batchEnd(in: frames, from: index)
      try await connection.send(EventSendQueue.batchData(frames[index..<end]))
      guard current == generation, closed == false else { return }
      if let sequence = frames[end - 1].seq {
        lastSent = sequence
        resumeResponseWaiters()
      }
      index = end
    }
  }
}
