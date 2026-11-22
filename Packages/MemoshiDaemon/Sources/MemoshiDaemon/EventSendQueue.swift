import Foundation
import MemoshiProtocol

/// One subscribed connection's event frames that are not yet written, bounded as protocol.md
/// §11 says: 10,000 frames or 8 MiB. A frame that would exceed the bound first makes the queue
/// merge its UI-only frames: the pending `message.delta` frames of one message and channel that
/// continue each other are concatenated into the first of them. Then the oldest UI-only frames
/// are dropped. A merge never moves text across a durable event, durable events and
/// `system.resync_required` are never merged or dropped, and frames already being written are
/// left alone. When kept frames alone exceed the bound, `admit` reports the overflow that
/// closes the connection with 4429. The output windows §11 also names (`tool.output`,
/// `codemode.output`, `terminal.output`) have no frame type yet, so nothing replaces them.
struct EventSendQueue {
  /// How much the queue holds, counting the batch being written.
  struct Limits: Sendable {
    var frames: Int
    var bytes: Int

    /// protocol.md §11.
    static let standard = Limits(frames: 10_000, bytes: 8_388_608)
  }

  /// One encoded event notification and what backpressure may do with it.
  struct Frame: Sendable {
    enum Kind: Sendable {
      /// A durable event or `system.resync_required`: never merged or dropped.
      case kept
      /// UI-only data that may be dropped.
      case droppable
      /// A `message.delta`, kept whole so that a delta continuing it can be concatenated.
      case delta(EventEnvelope)
    }

    let seq: Int64?
    let data: Data
    let kind: Kind

    /// `data` is `event` encoded as an event notification.
    init(_ event: EventEnvelope, data: Data) {
      seq = event.seq
      self.data = data
      if event.seq != nil {
        kind = .kept
      } else {
        switch event.event {
        case .systemResyncRequired: kind = .kept
        case .messageDelta: kind = .delta(event)
        default: kind = .droppable
        }
      }
    }

    private init(merged event: EventEnvelope, data: Data) {
      seq = nil
      self.data = data
      kind = .delta(event)
    }

    /// The queue counts a frame's own bytes and its share of the batch syntax.
    var cost: Int { data.count + 3 }

    var isKept: Bool {
      if case .kept = kind { return true }
      return false
    }

    static func merged(_ event: EventEnvelope, encoder: JSONEncoder) -> Frame? {
      guard let data = try? encoder.encode(EventNotification(event: event)) else { return nil }
      return Frame(merged: event, data: data)
    }
  }

  /// One write: at most 256 events and 4 MiB (protocol.md §7.1, §11).
  struct Batch {
    let data: Data
    /// The last durable `seq` in the batch.
    let lastSeq: Int64?
  }

  /// The most frame bytes one concatenated delta may stand for. The concatenation is smaller
  /// than its parts, which each repeat the envelope, and JSON escapes text one character at a
  /// time, so its payload stays within the 64 KiB event payload limit (protocol.md §11).
  static let concatenatedDeltaBytes = 65_536

  let limits: Limits
  private var frames: [Frame] = []
  /// The first frame not yet written.
  private var start = 0
  /// Frames `start ..< start + writing` are the batch being written.
  private var writing = 0
  private var writingBytes = 0
  /// The bytes of the frames not yet written, the batch being written included.
  private(set) var bytes = 0

  init(limits: Limits = .standard) {
    self.limits = limits
  }

  /// The frames not yet written, the batch being written included.
  var count: Int { frames.count - start }

  /// Whether a frame waits that no batch has taken yet.
  var hasFramesToSend: Bool { start + writing < frames.count }

  private var isOverLimits: Bool { count > limits.frames || bytes > limits.bytes }

  /// Queues `frame`, first merging and then dropping UI-only frames if the limits require it.
  /// Returns false when kept frames alone exceed the limits.
  mutating func admit(_ frame: Frame, encoder: JSONEncoder) -> Bool {
    frames.append(frame)
    bytes += frame.cost
    guard isOverLimits else { return true }
    concatenateDeltas(encoder: encoder)
    guard isOverLimits else { return true }
    dropOldestUIFrames()
    return !isOverLimits
  }

  /// Empties the queue, as for a new subscription.
  mutating func removeAll() {
    frames.removeAll(keepingCapacity: true)
    start = 0
    writing = 0
    writingBytes = 0
    bytes = 0
  }

  /// Removes the waiting durable events a resync covers.
  mutating func removeDurable(through head: Int64) {
    let first = start + writing
    var remaining: [Frame] = []
    remaining.reserveCapacity(frames.count - first)
    for frame in frames[first...] {
      if let seq = frame.seq, seq <= head {
        bytes -= frame.cost
      } else {
        remaining.append(frame)
      }
    }
    frames.replaceSubrange(first..., with: remaining)
  }

  /// Takes the next batch to write; the queue keeps its frames until `finishBatch`.
  mutating func beginBatch() -> Batch? {
    guard writing == 0, start < frames.count else { return nil }
    let end = Self.batchEnd(in: frames, from: start)
    var cost = 0
    var sequence: Int64?
    for frame in frames[start..<end] {
      cost += frame.cost
      if let seq = frame.seq { sequence = seq }
    }
    writing = end - start
    writingBytes = cost
    return Batch(data: Self.batchData(frames[start..<end]), lastSeq: sequence)
  }

  /// The batch from `beginBatch` was written.
  mutating func finishBatch() {
    start += writing
    bytes -= writingBytes
    writing = 0
    writingBytes = 0
    if start == frames.count {
      frames.removeAll(keepingCapacity: true)
      start = 0
    } else if start >= 256, start >= frames.count / 2 {
      frames.removeFirst(start)
      start = 0
    }
  }

  /// The end of the batch that starts at `start`: at most 256 events and 4 MiB.
  static func batchEnd(in frames: [Frame], from start: Int) -> Int {
    var end = start
    var size = 2
    while end < frames.count, end - start < 256 {
      let added = frames[end].data.count + (end == start ? 0 : 1)
      if end > start, size + added > 4_194_304 { break }
      size += added
      end += 1
    }
    return end
  }

  /// One frame as it is; several as one JSON-RPC batch array.
  static func batchData(_ frames: ArraySlice<Frame>) -> Data {
    if frames.count == 1, let first = frames.first { return first.data }
    var data = Data()
    data.reserveCapacity(frames.reduce(2) { $0 + $1.data.count + 1 })
    data.append(91)
    for (index, frame) in frames.enumerated() {
      if index > 0 { data.append(44) }
      data.append(frame.data)
    }
    data.append(93)
    return data
  }

  /// Concatenates each delta that continues an earlier waiting delta of its message and
  /// channel into that one, unless a kept frame lies between them.
  private mutating func concatenateDeltas(encoder: JSONEncoder) {
    let first = start + writing
    var merged: [Frame] = []
    merged.reserveCapacity(frames.count - first)
    // Each stream's latest frame since the last kept one, and the runs that grew from them.
    var open: [DeltaStream: Int] = [:]
    var runs: [Int: DeltaRun] = [:]
    for frame in frames[first...] {
      switch frame.kind {
      case .kept:
        open.removeAll(keepingCapacity: true)
      case .droppable:
        break
      case .delta(let envelope):
        guard case .messageDelta(let delta) = envelope.event else { break }
        let stream = DeltaStream(message: delta.messageId, channel: delta.channel)
        if let index = open[stream], case .delta(let base) = merged[index].kind,
          var run = runs[index] ?? DeltaRun(base, bytes: merged[index].data.count),
          run.extend(with: envelope, delta, bytes: frame.data.count)
        {
          runs[index] = run
          continue
        }
        open[stream] = merged.count
      }
      merged.append(frame)
    }
    guard !runs.isEmpty else { return }
    for (index, run) in runs {
      // Encoding cannot fail where its parts encoded; if it did, nothing is merged.
      guard let frame = Frame.merged(run.envelope, encoder: encoder) else { return }
      merged[index] = frame
    }
    frames.replaceSubrange(first..., with: merged)
    bytes = frames[start...].reduce(0) { $0 + $1.cost }
  }

  /// Drops the oldest UI-only frames that no batch has taken until the queue is within its
  /// limits or none is left.
  private mutating func dropOldestUIFrames() {
    let first = start + writing
    var excessFrames = count - limits.frames
    var excessBytes = bytes - limits.bytes
    var remaining: [Frame] = []
    remaining.reserveCapacity(frames.count - first)
    for frame in frames[first...] {
      if excessFrames > 0 || excessBytes > 0, !frame.isKept {
        excessFrames -= 1
        excessBytes -= frame.cost
        bytes -= frame.cost
      } else {
        remaining.append(frame)
      }
    }
    frames.replaceSubrange(first..., with: remaining)
  }
}

/// One message channel's text.
private struct DeltaStream: Hashable {
  let message: MessageID
  let channel: DeltaChannel
}

/// Deltas of one stream that continue each other, concatenated into the first one.
private struct DeltaRun {
  private var base: EventEnvelope
  private var payload: MessageDeltaPayload
  /// The UTF-16 offset at which the run's text ends.
  private var end: Int64
  /// The frame bytes of its parts.
  private var bytes: Int

  init?(_ base: EventEnvelope, bytes: Int) {
    guard case .messageDelta(let payload) = base.event else { return nil }
    self.base = base
    self.payload = payload
    end = payload.offsetUtf16 + Int64(payload.text.utf16.count)
    self.bytes = bytes
  }

  /// The concatenation: the first delta's envelope and offset with all the text. It carries
  /// the latest `after` of its parts, so a client still holds it behind every durable event
  /// one of them followed, and the latest time.
  var envelope: EventEnvelope {
    var envelope = base
    envelope.event = .messageDelta(payload)
    return envelope
  }

  /// Appends `delta` if it continues this run, in the same envelope, within the size bound.
  mutating func extend(with next: EventEnvelope, _ delta: MessageDeltaPayload, bytes count: Int)
    -> Bool
  {
    guard delta.offsetUtf16 == end, bytes + count <= EventSendQueue.concatenatedDeltaBytes,
      next.v == base.v, next.deviceId == base.deviceId, next.actor == base.actor,
      next.subject == base.subject, next.scope == base.scope, next.origin == base.origin
    else { return false }
    payload.text += delta.text
    end += Int64(delta.text.utf16.count)
    bytes += count
    base.ts = max(base.ts, next.ts)
    if let after = next.after { base.after = max(base.after ?? after, after) }
    return true
  }
}
