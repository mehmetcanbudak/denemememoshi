// macOS smoke/diagnostic entry for CodeModeWorkload.swift. Mac numbers are never reference-device gate evidence.
// Compile both files with Swift 6 against Pi_Swift's modules (the pattern of Pi_Swift's
// Scripts/benchmarks/ai-release.sh), then run:
// Set TMPDIR to an existing, absolute directory owned by this run before invoking the driver.
//   codemode-workload --fixture <fixture-root> --workload W1 --backend WasmKit --launches 10 --output results.jsonl
// Driver mode starts one child process per launch (`--launch <k>`), so every cold sample is a fresh process. Each child
// keeps its SQLite store in a private directory under TMPDIR and removes it on every normal return path. The
// driver waits for every child to exit on its own: it sends no signal and enforces no deadline, so the per-launch
// deadline stays with the device driver.
// Exit status: 0 when every launch verified; otherwise the first failing child's status (1 launch error, 2 verification
// failure, 128 + signal for a child that ended on a signal); 64 for a usage error.
// provenance.json records what was compiled or executed with each revision.
#if os(macOS)
  import Foundation

  @main
  enum CodeModeWorkloadCLI {
    static let usage =
      "usage: codemode-workload --fixture <dir> --workload W1|W2|W3a|W3b|W3c --backend <label> --output <file.jsonl> [--launches N | --launch K]"

    static func main() async {
      let arguments = Array(CommandLine.arguments.dropFirst())
      func value(_ flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
          fail(usage, status: 64)
        }
        return arguments[index + 1]
      }
      guard let fixture = value("--fixture"), let name = value("--workload"),
        let workload = WorkloadID(rawValue: name),
        let backend = value("--backend"), let output = value("--output")
      else { fail(usage, status: 64) }

      if let text = value("--launch") {
        guard let launch = Int(text), launch >= 1 else { fail(usage, status: 64) }
        exit(
          await runLaunch(
            fixture: fixture, workload: workload, backend: backend, output: output, launch: launch))
      }
      let launches: Int?
      if let text = value("--launches") { launches = Int(text) } else { launches = 10 }
      guard let launches, launches >= 1, let executable = Bundle.main.executableURL else {
        fail(usage, status: 64)
      }
      exit(
        drive(
          executable: executable, fixture: fixture, workload: workload, backend: backend,
          output: output, launches: launches))
    }

    /// One launch in this process. The store directory is removed on every path: verified, failed verification or thrown.
    static func runLaunch(
      fixture: String, workload: WorkloadID, backend: String, output: String, launch: Int
    ) async -> Int32 {
      let files = FileManager.default
      guard let temporaryRoot = ProcessInfo.processInfo.environment["TMPDIR"],
        temporaryRoot.hasPrefix("/")
      else {
        report("launch \(launch): set TMPDIR to an explicit, existing scratch directory")
        return 64
      }
      let scratch = URL(fileURLWithPath: temporaryRoot, isDirectory: true)
        .appendingPathComponent("memoshi-codemode-\(UUID().uuidString)", isDirectory: true)
      do {
        try files.createDirectory(
          at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      } catch {
        report("launch \(launch): cannot create \(scratch.path): \(error)")
        return 1
      }
      var status: Int32
      do {
        let result = try await CodeModeWorkloadRunner.runLaunch(
          WorkloadLaunchOptions(
            workload: workload, fixture: URL(fileURLWithPath: fixture, isDirectory: true),
            storeDirectory: scratch,
            backendLabel: backend, launchIndex: launch))
        try append(result, to: output)
        for failure in result.failures { report("launch \(launch): \(failure)") }
        status = result.failures.isEmpty ? 0 : 2
      } catch {
        report("launch \(launch) failed: \(error)")
        status = 1
      }
      if files.fileExists(atPath: scratch.path) {
        do { try files.removeItem(at: scratch) } catch {
          report("launch \(launch): cannot remove \(scratch.path): \(error)")
          if status == 0 { status = 1 }
        }
      }
      return status
    }

    static func append(_ result: LaunchResult, to output: String) throws {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      var line = try encoder.encode(result)
      line.append(10)
      if !FileManager.default.fileExists(atPath: output),
        !FileManager.default.createFile(atPath: output, contents: nil)
      {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: output])
      }
      let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: output))
      defer { try? handle.close() }
      _ = try handle.seekToEnd()
      try handle.write(contentsOf: line)
    }

    /// Driver mode: one child per launch, one after another. Every child ends by its own exit; none is signalled.
    static func drive(
      executable: URL, fixture: String, workload: WorkloadID, backend: String, output: String,
      launches: Int
    ) -> Int32 {
      var firstFailure: Int32 = 0
      for launch in 1...launches {
        let child = Process()
        child.executableURL = executable
        child.arguments = [
          "--fixture", fixture, "--workload", workload.rawValue, "--backend", backend, "--output",
          output, "--launch", String(launch),
        ]
        do { try child.run() } catch {
          report("launch \(launch) could not start: \(error)")
          return firstFailure == 0 ? 1 : firstFailure
        }
        child.waitUntilExit()
        let status =
          child.terminationReason == .exit ? child.terminationStatus : 128 + child.terminationStatus
        if status != 0 {
          report("launch \(launch) exited with status \(status)")
          if firstFailure == 0 { firstFailure = status }
        }
      }
      return firstFailure
    }

    static func report(_ message: String) {
      FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    static func fail(_ message: String, status: Int32) -> Never {
      report(message)
      exit(status)
    }
  }
#endif
