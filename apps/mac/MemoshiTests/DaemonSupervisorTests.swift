import Darwin
import Foundation
import MemoshiClient
import MemoshiProtocol
import Testing

/// The supervisor's status line and its wait for an unregistered agent's daemon to exit. The
/// supervisor itself needs the signed app bundle and launchd, so these test what it decides.
@MainActor
@Suite("Daemon supervisor")
struct DaemonSupervisorTests {
  @Test(
    "While a wait runs, a missing socket is not shown as a stopped daemon (protocol.md §3.1)",
    arguments: [DaemonWait.connecting, .helperStarting, .agentStopping])
  func waitingIsNotStopped(_ wait: DaemonWait) {
    let note = DaemonStatusNote(problem: nil, wait: wait, client: .daemonStopped)
    #expect(note == .waiting(wait))
    #expect(note?.message.key != DaemonStatusNote.daemonStopped.message.key)
  }

  @Test("Without a wait, the client's own state is the status line")
  func clientStateWithoutAWait() {
    #expect(DaemonStatusNote(problem: nil, wait: nil, client: .daemonStopped) == .daemonStopped)
    #expect(
      DaemonStatusNote(problem: nil, wait: nil, client: .versionMismatch) == .versionMismatch)
    #expect(
      DaemonStatusNote(problem: nil, wait: nil, client: .signingRequired) == .signingRequired)
    #expect(DaemonStatusNote(problem: nil, wait: nil, client: .connected) == nil)
    #expect(DaemonStatusNote(problem: nil, wait: nil, client: nil) == nil)
  }

  @Test("A problem the operation reported comes before any wait")
  func problemComesFirst() {
    let note = DaemonStatusNote(
      problem: .agentStillRunning, wait: .agentStopping, client: .daemonStopped)
    #expect(note == .problem(.agentStillRunning))
  }

  @Test("Each wait has its own text")
  func waitTextsDiffer() {
    let keys = [DaemonWait.connecting, .helperStarting, .agentStopping].map {
      DaemonStatusNote.waiting($0).message.key
    }
    #expect(Set(keys).count == 3)
  }

  @Test("The wait for an agent's exit outlasts the LaunchAgent's own exit timeout")
  func agentStopCeilingCoversExitTimeOut() throws {
    let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(
        "Memoshi/Resources/LaunchAgents/com.mehmetcanbudak.memoshi.memoshid.plist")
    let object = try PropertyListSerialization.propertyList(
      from: Data(contentsOf: plist), format: nil)
    let exitTimeOut = try #require((object as? [String: Any])?["ExitTimeOut"] as? Int)
    // launchd kills a job that outlives ExitTimeOut, so the agent is gone before the bound.
    #expect(DaemonSupervisor.agentStopCeiling > .seconds(exitTimeOut))
  }

  @Test("The exit wait ends as soon as the process is gone, and never sleeps for a gone one")
  func exitWaitEndsAtTheExit() async throws {
    var checks = 0
    var slept: [Duration] = []
    let exited = try await DaemonProcessExit.wait(
      within: .seconds(35),
      isRunning: {
        checks += 1
        return checks <= 3
      }, sleep: { slept.append($0) })
    #expect(exited)
    #expect(slept == Array(repeating: .milliseconds(100), count: 3))

    slept.removeAll()
    let gone = try await DaemonProcessExit.wait(
      within: .seconds(35), isRunning: { false }, sleep: { slept.append($0) })
    #expect(gone)
    #expect(slept.isEmpty)
  }

  @Test("The exit wait gives up at its bound")
  func exitWaitGivesUpAtTheBound() async throws {
    var slept = Duration.zero
    let exited = try await DaemonProcessExit.wait(
      within: .seconds(1), isRunning: { true }, sleep: { slept += $0 })
    #expect(exited == false)
    #expect(slept == .seconds(1))
  }

  @Test("A daemon runs while its PID names this user's process that started before it said")
  func runningDaemonIdentity() throws {
    let now = Int64(Date().timeIntervalSince1970 * 1_000)
    let pid = Int(getpid())
    #expect(DaemonProcessExit.isRunning(info(pid: pid, startedAt: now)))
    // A process that started after the daemon said it did holds a reused PID.
    #expect(DaemonProcessExit.isRunning(info(pid: pid, startedAt: 0)) == false)
    // launchd is another user's process.
    #expect(DaemonProcessExit.isRunning(info(pid: 1, startedAt: now)) == false)
    #expect(DaemonProcessExit.isRunning(info(pid: 0, startedAt: now)) == false)
  }

  @Test("A daemon whose process has exited no longer runs")
  func exitedDaemonIsNotRunning() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try process.run()
    process.waitUntilExit()
    let now = Int64(Date().timeIntervalSince1970 * 1_000)
    #expect(
      DaemonProcessExit.isRunning(info(pid: Int(process.processIdentifier), startedAt: now))
        == false)
  }

  @Test("Default supervisor uses production SMAppService mode rather than isolated development chat")
  func defaultSupervisorUsesProductionMode() {
    let supervisor = DaemonSupervisor()
    #expect(supervisor.isDevelopmentChat == false)
    let appSupervisor = MemoshiApp.makeDefaultDaemonSupervisor()
    #expect(appSupervisor.isDevelopmentChat == false)
  }

  private func info(pid: Int, startedAt: Int64) -> DaemonInfo {
    DaemonInfo(version: "0.1.0", build: "1", pid: pid, startedAt: startedAt)
  }
}
