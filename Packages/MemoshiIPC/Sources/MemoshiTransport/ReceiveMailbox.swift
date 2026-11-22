import Foundation
import NIOCore

/// A demand-aware queue behind AsyncThrowingStream's public unfolding seam.
/// This avoids a second hidden stream buffer and bounds bytes as well as frames.
internal final class ReceiveMailbox: @unchecked Sendable {
  enum Offer { case enqueued, overflow, terminated }

  private let lock = NSLock()
  private var queue = CircularBuffer<Data>(initialCapacity: 16)
  private var bytes = 0
  private var terminal: (any Error)?
  private var waiter: CheckedContinuation<Data?, any Error>?
  private var onDemand: (@Sendable () -> Void)?
  private var onCancel: (@Sendable () -> Void)?

  func configure(onDemand: @escaping @Sendable () -> Void, onCancel: @escaping @Sendable () -> Void)
  {
    lock.withLock {
      self.onDemand = onDemand
      self.onCancel = onCancel
    }
  }

  private var hasCapacity: Bool {
    bytes < TransportLimits.receiveHighBytes && queue.count < TransportLimits.receiveHighFrames
  }

  var canRead: Bool { lock.withLock { terminal == nil && hasCapacity } }

  func offer(_ data: Data) -> Offer {
    var consumer: CheckedContinuation<Data?, any Error>?
    let result: Offer = lock.withLock {
      guard terminal == nil else { return .terminated }
      if let waiting = waiter {
        waiter = nil
        consumer = waiting
        return .enqueued
      }
      guard data.count <= TransportLimits.queuedBytes - bytes,
        queue.count < TransportLimits.queuedFrames
      else { return .overflow }
      queue.append(data)
      bytes += data.count
      return .enqueued
    }
    consumer?.resume(returning: data)
    return result
  }

  /// Buffered messages are always delivered before the terminal error. An
  /// overflow therefore cannot silently replace or drop an earlier durable frame.
  func finish(_ error: any Error) {
    let consumer: CheckedContinuation<Data?, any Error>? = lock.withLock {
      guard terminal == nil else { return nil }
      terminal = error
      let consumer = waiter
      waiter = nil
      return consumer
    }
    consumer?.resume(throwing: error)
  }

  func next() async throws -> Data? {
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        var demand: (@Sendable () -> Void)?
        let ready: Result<Data?, any Error>? = lock.withLock {
          let hadCapacity = hasCapacity
          if !queue.isEmpty {
            let data = queue.removeFirst()
            bytes -= data.count
            if !hadCapacity && hasCapacity && terminal == nil { demand = onDemand }
            return .success(data)
          }
          if let terminal { return .failure(terminal) }
          guard waiter == nil else {
            return .failure(
              IPCError.closed(code: 1002, reason: "Only one receive consumer is supported"))
          }
          waiter = continuation
          demand = onDemand
          return nil
        }
        if let ready { continuation.resume(with: ready) }
        demand?()
      }
    } onCancel: {
      self.finish(CancellationError())
      let cancel = self.lock.withLock { self.onCancel }
      cancel?()
    }
  }
}
