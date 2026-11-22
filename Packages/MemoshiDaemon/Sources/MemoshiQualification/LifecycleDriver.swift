import Darwin
import Foundation
import MemoshiProtocol
import MemoshiRuntime
import MemoshiStore

/// S1.2 development proof against default production idle timing and real Pi SQLite/Harnesses.
/// No model, credential, signing bypass, clock acceleration or private runtime API is used.
package enum LifecycleDriver {
  package static func run(work: URL, output: URL) async -> Int32 {
    var ownedWork = false
    var ownedOutput = false
    var store: Store?
    var runtime: RuntimeAdapter?
    var report: LifecycleReport?
    var failures: [String] = []
    do {
      let paths = try QualificationPaths(work: work, output: output)
      try QualificationPaths.create(paths.work)
      ownedWork = true
      try QualificationPaths.create(paths.output)
      ownedOutput = true
      let openedStore = try Store(directory: paths.work)
      store = openedStore
      let openedRuntime = RuntimeAdapter(store: openedStore, publishLive: { _ in })
      runtime = openedRuntime
      try await openedRuntime.start()
      try await openedRuntime.resume()
      report = try await withDeadline(.seconds(720), "real default idle lifecycle") {
        try await observe(runtime: openedRuntime, store: openedStore, directory: paths.work)
      }
    } catch {
      failures.append("Lifecycle scenario refused or failed: \(error)")
    }
    do { try await runtime?.close() } catch { failures.append("Runtime close failed") }
    do { try await store?.close() } catch { failures.append("Store close failed") }
    if ownedWork {
      do { try FileManager.default.removeItem(at: work) } catch {
        failures.append("Owned lifecycle root cleanup failed")
      }
    }
    if ownedOutput {
      do {
        let result = LifecycleRun(
          evidenceClass:
            "development Mac / actual Pi stores / unchanged default 600-second idle limit",
          referenceQualification: false, passed: failures.isEmpty, processID: getpid(),
          sdkCandidate: PiDevelopmentSnapshot.revision, schemaVersion: Store.schemaVersion,
          os: ProcessInfo.processInfo.operatingSystemVersionString,
          report: report, failures: failures)
        try JSONLines.prettyEncoder.encode(result).write(
          to: output.appendingPathComponent("lifecycle.json"), options: .withoutOverwriting)
      } catch { failures.append("Lifecycle report write failed") }
    }
    for failure in failures { LineWriter.standardError.text(failure) }
    return failures.isEmpty ? 0 : 1
  }

  private static func observe(runtime: RuntimeAdapter, store: Store, directory: URL) async throws
    -> LifecycleReport
  {
    let assistant = try await runtime.listBots(.init()).items.first
    guard let assistant else { throw DriverError.invalid("No Assistant") }
    let disposable = try await runtime.createSession(
      .init(
        requestId: IDGenerator.shared.next(), leadBotId: assistant.id, title: "Lifecycle disposable"
      ))
    let idle = try await runtime.createSession(
      .init(
        requestId: IDGenerator.shared.next(), leadBotId: assistant.id,
        title: "Default idle observation"))
    let disposableID = try ConversationID(disposable.session.id.rawValue)
    let idleID = try ConversationID(idle.session.id.rawValue)
    let assistantID = try ConversationID(assistant.chatId.rawValue)
    _ = try await runtime.history(.init(chatId: assistantID))
    _ = try await runtime.history(.init(chatId: disposableID))
    _ = try await runtime.history(.init(chatId: idleID))
    guard await runtime.status().openThreads == 3 else {
      throw DriverError.invalid("Three independent real Harnesses did not open")
    }
    let disposableFile = directory.appendingPathComponent("pi/\(disposableID.rawValue).sqlite")
    let idleFile = directory.appendingPathComponent("pi/\(idleID.rawValue).sqlite")
    guard FileManager.default.fileExists(atPath: disposableFile.path),
      FileManager.default.fileExists(atPath: idleFile.path)
    else { throw DriverError.invalid("Real Pi SQLite files were not created") }
    let firstEpoch = try await store.lease(disposableID)?.epoch
    let deletion = SessionsDeleteParams(
      requestId: try IDGenerator.shared.next(), sessionId: disposable.session.id)
    let deleted = try await runtime.deleteSession(deletion)
    guard await runtime.status().openThreads == 2,
      try await store.lease(disposableID)?.runnerDeviceID == nil,
      FileManager.default.fileExists(atPath: disposableFile.path),
      try await runtime.listTrash().items.map(\.id) == [disposable.session.id]
    else { throw DriverError.invalid("Deletion did not close and retain only the selected store") }
    _ = try await runtime.restoreSession(
      .init(requestId: IDGenerator.shared.next(), id: disposable.session.id))
    _ = try await runtime.history(.init(chatId: disposableID))
    guard try await store.lease(disposableID)?.epoch == firstEpoch.map({ $0 + 1 }) else {
      throw DriverError.invalid("Restore reused a released lease epoch")
    }
    let replay = try await runtime.deleteSession(deletion)
    guard replay.replayed == true, replay.writtenSeq == deleted.writtenSeq,
      try await runtime.listTrash().items.isEmpty
    else { throw DriverError.invalid("An old deletion receipt changed restored state") }
    _ = try await runtime.deleteSession(
      .init(requestId: IDGenerator.shared.next(), sessionId: disposable.session.id))
    let purge = TrashEmptyParams(
      requestId: try IDGenerator.shared.next(), ids: [disposable.session.id])
    let purged = try await runtime.emptyTrash(purge)
    let purgedReplay = try await runtime.emptyTrash(purge)
    guard purgedReplay.replayed == true, purgedReplay.writtenSeq == purged.writtenSeq,
      !FileManager.default.fileExists(atPath: disposableFile.path),
      FileManager.default.fileExists(atPath: idleFile.path),
      await runtime.status().openThreads == 2
    else { throw DriverError.invalid("Purge did not remove only its closed Pi store exactly once") }
    do {
      _ = try await runtime.history(.init(chatId: disposableID))
      throw DriverError.invalid("A purged Session reopened")
    } catch StoreError.chatNotFound {}

    // This is deliberately the unchanged 10-minute timer. Status inspection never touches
    // the idle Session. A different Chat remains in use, proving the sweeper is per-thread.
    _ = try await runtime.history(.init(chatId: idleID))
    let idleEpoch = try await store.lease(idleID)?.epoch
    let start = ContinuousClock.now
    var lastKeepAlive = start
    var observedNanoseconds: Int64?
    var observations = 0
    while start.duration(to: .now) < .seconds(690) {
      try Task.checkCancellation()
      let now = ContinuousClock.now
      if lastKeepAlive.duration(to: now) >= .seconds(30) {
        _ = try await runtime.history(.init(chatId: assistantID))
        lastKeepAlive = now
      }
      let status = await runtime.status()
      observations += 1
      guard !status.lifecycleMaintenanceFailed else {
        throw DriverError.invalid("Lifecycle maintenance reported a failure")
      }
      if status.openThreads == 1 {
        let elapsed = S1Clock.nanoseconds(since: start)
        guard elapsed >= 600_000_000_000,
          try await store.lease(idleID)?.runnerDeviceID == nil
        else { throw DriverError.invalid("The idle store closed early or kept its lease") }
        observedNanoseconds = elapsed
        break
      }
      guard status.openThreads == 2 else {
        throw DriverError.invalid("Unrelated store count changed during idle observation")
      }
      try await Task.sleep(for: .seconds(1))
    }
    guard let observedNanoseconds else {
      throw DriverError.timeout("The default idle sweeper did not release the store")
    }
    _ = try await runtime.history(.init(chatId: idleID))
    guard await runtime.status().openThreads == 2,
      try await store.lease(idleID)?.epoch == idleEpoch.map({ $0 + 1 }),
      FileManager.default.fileExists(atPath: idleFile.path)
    else { throw DriverError.invalid("Idle close did not preserve and reopen the original store") }
    let events = try await store.replay(after: 0).events
    return LifecycleReport(
      deletionCount: events.filter { $0.type == "session.deleted" }.count,
      restoreCount: events.filter { $0.type == "session.restored" }.count,
      purgeCount: events.filter { $0.type == "session.purged" }.count,
      idleObservedNanoseconds: observedNanoseconds, statusObservations: observations,
      unrelatedChatStayedOpen: true, originalPIDPreserved: getpid(),
      openStoresAfterIdleReopen: await runtime.status().openThreads,
      originalMutationReceiptsPreserved: true, purgedFileAbsent: true)
  }
}

private struct LifecycleReport: Encodable, Sendable {
  let deletionCount: Int
  let restoreCount: Int
  let purgeCount: Int
  let idleObservedNanoseconds: Int64
  let statusObservations: Int
  let unrelatedChatStayedOpen: Bool
  let originalPIDPreserved: Int32
  let openStoresAfterIdleReopen: Int
  let originalMutationReceiptsPreserved: Bool
  let purgedFileAbsent: Bool
}

private struct LifecycleRun: Encodable {
  let evidenceClass: String
  let referenceQualification: Bool
  let passed: Bool
  let processID: Int32
  let sdkCandidate: String
  let schemaVersion: Int
  let os: String
  let report: LifecycleReport?
  let failures: [String]
}
