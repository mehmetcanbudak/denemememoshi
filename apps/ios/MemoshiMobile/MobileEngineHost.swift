import AppCore
import Foundation
import MemoshiProtocol
import MemoshiRuntime
import MemoshiStore
import Observation
import SwiftUI
import UIKit
import os

/// Wraps `UIApplication`'s finite background-task assertion so closing the in-process engine on
/// background entry finishes before iOS suspends the process, and unit tests can observe it.
@MainActor
struct BackgroundExecutionTask {
  let begin:
    @MainActor (_ name: String, _ expiration: @escaping @MainActor () -> Void) ->
      UIBackgroundTaskIdentifier
  let end: @MainActor (UIBackgroundTaskIdentifier) -> Void

  static let system = BackgroundExecutionTask(
    begin: { name, expiration in
      UIApplication.shared.beginBackgroundTask(withName: name) {
        MainActor.assumeIsolated { expiration() }
      }
    },
    end: { id in
      guard id != .invalid else { return }
      UIApplication.shared.endBackgroundTask(id)
    })
}

/// Owns this app's in-process engine (D46, 04-architecture §2.7): the Store and Pi stores live
/// in the app's private container, excluded from backups, and the UI reaches the engine only
/// through the typed API (D78). There is no daemon, socket or helper.
@MainActor
@Observable
final class MobileEngineHost {
  enum State: Equatable {
    case opening
    case ready
    case failed(String)
  }

  private(set) var state = State.opening
  let chat: InProcessChatModel
  @ObservationIgnored private let turns = ContinuedTurnProcessing()
  @ObservationIgnored private let directoryProvider: @MainActor () throws -> URL
  @ObservationIgnored private let backgroundTask: BackgroundExecutionTask
  @ObservationIgnored private var engine: InProcessEngine?
  /// Serializes open, resume and background-close transitions so scene-phase changes never race.
  @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
  /// The engine is open, but its unfinished turns have not been resumed yet.
  @ObservationIgnored private var resumePending = false
  /// Whether the scene is currently in `.background`.
  @ObservationIgnored private var isBackgrounded = false
  @ObservationIgnored private let log = Logger(
    subsystem: "com.mehmetcanbudak.memoshi", category: "engine")

  /// Whether the in-process engine is currently open (exposed for unit tests).
  var isEngineOpen: Bool { engine != nil }

  /// The system allows an expired background task only a short, undocumented time to complete.
  /// The engine is in this process and a Stop is one committed call, so this is ample.
  private static let stopSettleLimit = Duration.seconds(2)

  init(
    directoryProvider: @escaping @MainActor () throws -> URL = MobileEngineHost.dataDirectory,
    backgroundTask: BackgroundExecutionTask = .system
  ) {
    self.directoryProvider = directoryProvider
    self.backgroundTask = backgroundTask
    chat = InProcessChatModel(makeRequestID: { try IDGenerator.shared.next() })
    let turns = turns
    let chat = chat
    turns.onExpiration = { [weak chat] request in
      guard let chat else { return }
      chat.stopBackgroundTurn(request)
      // A Send in flight dispatches the Stop when it is admitted, before it clears `isSending`;
      // `isStopping` then lasts until the engine has answered the Stop.
      let deadline = ContinuousClock.now + Self.stopSettleLimit
      while chat.isSending || chat.isStopping, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(20))
      }
    }
    turns.onAllTasksEnded = { [weak self] in
      guard let self, self.isBackgrounded else { return }
      Task { @MainActor in await self.closeForBackground() }
    }
    chat.onTurnActivity = { turns.handle($0) }
  }

  /// Opens the engine once, attaches the Chat's single event consumer, then resumes any
  /// unfinished turn, as memoshid resumes once it listens.
  func open() async {
    await enqueueLifecycle { [self] in
      await self.openUnlocked()
    }
  }

  /// Retries a resume that failed after the engine opened; otherwise does nothing.
  func resumeIfNeeded() async {
    await enqueueLifecycle { [self] in
      guard let engine = self.engine, self.resumePending else { return }
      await self.resume(engine)
    }
  }

  /// Closes the in-process engine on `.background` inside a finite background task (unless a
  /// `BGContinuedProcessingTask` holds background execution time), because a store left open
  /// while iOS suspends the process loses its lease and risks `0xdead10cc`. Reopens on `.active`.
  func scenePhaseChanged(_ phase: ScenePhase) async {
    switch phase {
    case .background:
      isBackgrounded = true
      guard !turns.hasActiveTask else { return }
      await closeForBackground()
    case .active:
      isBackgrounded = false
      await enqueueLifecycle { [self] in
        if let engine = self.engine {
          if self.resumePending { await self.resume(engine) }
        } else {
          await self.openUnlocked()
        }
      }
    case .inactive:
      break
    @unknown default:
      break
    }
  }

  /// Closes the engine cleanly (D139 keeps unfinished turns and Cards for the next open) under
  /// `beginBackgroundTask` so SQLite releases its locks before iOS suspends the process.
  private func closeForBackground() async {
    await enqueueLifecycle { [self] in
      await self.closeForBackgroundUnlocked()
    }
  }

  private func enqueueLifecycle(_ operation: @escaping @MainActor () async -> Void) async {
    let previous = lifecycleTask
    let next = Task<Void, Never> { @MainActor in
      await previous?.value
      await operation()
    }
    lifecycleTask = next
    await next.value
  }

  private func openUnlocked() async {
    guard engine == nil else { return }
    let engine: InProcessEngine
    do {
      let directory = try directoryProvider()
      let tools = DevelopmentComposition.tools(directory: directory)
      engine = try await InProcessEngine.open(directory: directory, tools: tools)
      self.engine = engine
      chat.attach(
        InProcessEngineConnection(
          api: engine,
          subscribe: {
            let feed = try await engine.events()
            return EngineEventFeed(head: feed.head, events: feed.events)
          }))
      state = .ready
      log.notice("engine open: tools=\(tools.count, privacy: .public)")
    } catch StoreError.alreadyOpen {
      state = .failed(
        String(localized: "This conversation store is already open. A second open is refused."))
      log.error("engine open refused: store already open")
      return
    } catch {
      state = .failed(
        String(localized: "The on-device engine could not open. No other model or store is used."))
      log.error("engine open failed: \(String(describing: type(of: error)), privacy: .public)")
      return
    }
    await resume(engine)
    // If the app entered background while `open` was running and no continued task holds time,
    // close cleanly before suspension.
    if isBackgrounded, !turns.hasActiveTask {
      await closeForBackgroundUnlocked()
    }
  }

  private func closeForBackgroundUnlocked() async {
    guard isBackgrounded, !turns.hasActiveTask, let engine = self.engine else { return }
    var taskID = UIBackgroundTaskIdentifier.invalid
    let endTask: @MainActor () -> Void = { [backgroundTask] in
      guard taskID != .invalid else { return }
      let id = taskID
      taskID = .invalid
      backgroundTask.end(id)
    }
    taskID = backgroundTask.begin("MemoshiEngineClose") {
      endTask()
    }
    defer { endTask() }
    chat.detach()
    self.engine = nil
    resumePending = false
    do {
      try await engine.close()
      log.notice("engine closed for background")
    } catch {
      let kind = String(describing: type(of: error))
      log.error("engine background close failed: \(kind, privacy: .public)")
    }
  }

  /// A failed resume is not a failed open: the engine is attached and usable, so `state` stays
  /// ready. Unfinished turns stay paused until a later resume succeeds.
  private func resume(_ engine: InProcessEngine) async {
    do {
      try await engine.resume()
      resumePending = false
      log.notice("engine resumed")
    } catch {
      resumePending = true
      log.error("engine resume failed: \(String(describing: type(of: error)), privacy: .public)")
    }
  }

  /// `Application Support/Memoshi` in this app's container: the Mac layout without `run/`,
  /// excluded from iCloud and device backups (09-platform §12.2).
  static func dataDirectory() throws -> URL {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var directory = support.appendingPathComponent("Memoshi", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
    return directory
  }
}
