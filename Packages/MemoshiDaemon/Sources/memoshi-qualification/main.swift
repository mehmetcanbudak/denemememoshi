// Non-shipping P0-15, S1, S2 and S4-T1 qualification CLI; see Sources/MemoshiQualification/README.md.
import Foundation
import MemoshiQualification

let usage = """
  usage: memoshi-qualification chaos --runs N --seed S --work-dir DIR [--output-dir DIR]
           [--points p1,p2,...] [--kills-per-run K] [--startup discover-then-resume|daemon]
           [--terminal-timeout SECONDS] [--keep-run-dirs]
           [--upstream http://127.0.0.1:PORT/v1 --upstream-model MODEL]
         memoshi-qualification ledger --directory DIR
         memoshi-qualification ledger-summary --journal FILE
         memoshi-qualification scan [--exclude FILE]... PATH...   (canaries on stdin: label=value)
         memoshi-qualification host   (driver-owned child; configuration on stdin)
         memoshi-qualification s1 --work-dir DIR --output-dir DIR [--open-samples N]
           [--timeout-seconds N]   (development Mac / synthetic loopback provider only)
         memoshi-qualification s1-host   (driver-owned runtime child; NOT memoshid)
         memoshi-qualification lifecycle --work-dir DIR --output-dir DIR
           (real default ten-minute idle and live Session Trash/purge; no provider)
         memoshi-qualification s2 --work-dir DIR --output-dir DIR [--quick] [--real-expiry]
           [--load] [--bonjour]
         memoshi-qualification s2-device --directory DIR --name NAME --platform mac|iphone|ipad
         memoshi-qualification s2-relay --directory DIR [--no-authority-journal] [--no-grant-log]
         memoshi-qualification s2-load --relay-port PORT --users N --active N --idle N
           --active-renew-ms MS --active-ttl-ms MS --idle-renew-ms MS --idle-ttl-ms MS
           --moves N --duration-ms MS --output FILE
         memoshi-qualification s4-matrix [--parent DIR] [--owned-root DIR]... [--output-dir DIR]
           [--aliases-volume PATH]...   (S4-T1 raw 105-vector Seatbelt matrix. Without --parent
           a fresh owned parent is made below \(S4Matrix.defaultScratch); --parent must be a
           canonical directory strictly below it or below an --owned-root. --output-dir must
           not exist yet; --aliases-volume requires it. Exit 2 = the three accepted hard-link
           effects only; exit 3 = any other failure, including a skipped or uncleaned alias
           volume)

  kill points: \(KillPoint.allCases.map(\.rawValue).joined(separator: ", "))
  """

func fail(_ message: String, status: Int32 = 64) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(status)
}

/// Parses `--flag value` pairs and bare flags after the subcommand. Only the subcommand's own
/// options are accepted and a value never starts with `--`, so a misspelt switch is a usage
/// error instead of an option that swallows the one after it.
struct Flags {
  var values: [String: String] = [:]
  var repeated: [String: [String]] = [:]
  var switches: Set<String> = []
  var positional: [String] = []

  init(
    _ arguments: ArraySlice<String>, options: Set<String>, switches known: Set<String> = [],
    repeatable: Set<String> = []
  ) {
    var index = arguments.startIndex
    while index < arguments.endIndex {
      let argument = arguments[index]
      if known.contains(argument) {
        switches.insert(argument)
        index += 1
      } else if argument.hasPrefix("--") {
        guard options.contains(argument) || repeatable.contains(argument),
          index + 1 < arguments.endIndex, !arguments[index + 1].hasPrefix("--")
        else { fail(usage) }
        if repeatable.contains(argument) {
          repeated[argument, default: []].append(arguments[index + 1])
        } else {
          guard values[argument] == nil else { fail(usage) }
          values[argument] = arguments[index + 1]
        }
        index += 2
      } else {
        positional.append(argument)
        index += 1
      }
    }
  }
}

func absoluteURL(_ path: String) -> URL {
  URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { fail(usage) }
if arguments.count == 3 && arguments[1] == "--s4-worker" {
  exit(S4Matrix.worker(arguments[2]))
}
switch arguments[1] {
case "chaos":
  let flags = Flags(
    arguments.dropFirst(2),
    options: [
      "--runs", "--seed", "--work-dir", "--output-dir", "--points", "--kills-per-run",
      "--startup", "--terminal-timeout", "--upstream", "--upstream-model",
    ], switches: ["--keep-run-dirs"])
  guard flags.positional.isEmpty,
    let runs = flags.values["--runs"].flatMap({ Int($0) }), runs > 0,
    let seed = flags.values["--seed"].flatMap({ UInt64($0) }),
    let work = flags.values["--work-dir"]
  else { fail(usage) }
  let points: [KillPoint]
  if let raw = flags.values["--points"] {
    let parsed = raw.split(separator: ",").map { KillPoint(rawValue: String($0)) }
    guard parsed.allSatisfy({ $0 != nil }) else { fail(usage) }
    // An explicit selection keeps every point, gated ones included; the driver refuses each
    // gated run with its recorded reason.
    points = parsed.compactMap { $0 }
  } else {
    // The default draws the recorded S1.13 gate points; every other point needs --points.
    for point in KillPoint.allCases {
      guard let reason = point.defaultExclusionReason else { continue }
      LineWriter.standardError.text(
        "memoshi-qualification: the default selection excludes \(point.rawValue) (\(reason))")
    }
    points = KillPoint.defaultSelection
  }
  guard let kills = Int(flags.values["--kills-per-run"] ?? "1"), kills > 0,
    let startup = StartupOrder(rawValue: flags.values["--startup"] ?? "discover-then-resume"),
    let terminal = Int(flags.values["--terminal-timeout"] ?? "90"), terminal > 0,
    let executable = Bundle.main.executableURL
  else { fail(usage) }
  // Real-model mode: both flags together select one model of a loopback OpenAI-compatible
  // server behind the canary-checking proxy. The driver never starts, stops or pulls it.
  let model: ChaosModelSelection
  switch (flags.values["--upstream"], flags.values["--upstream-model"]) {
  case (nil, nil):
    model = .scripted
  case (let upstream?, let name?):
    guard let url = URL(string: upstream), url.scheme == "http", !name.isEmpty else { fail(usage) }
    model = .upstream(url, model: name)
  default:
    fail(usage)
  }
  let workURL = absoluteURL(work)
  let options = ChaosOptions(
    runs: runs, seed: seed, workDirectory: workURL,
    outputDirectory: flags.values["--output-dir"].map(absoluteURL)
      ?? workURL.appendingPathComponent("report", isDirectory: true),
    points: points.compactMap { $0 }, killsPerRun: kills, startup: startup,
    keepRunDirectories: flags.switches.contains("--keep-run-dirs"),
    terminalTimeout: .seconds(terminal), model: model, executable: executable,
    arguments: Array(arguments.dropFirst()))
  exit(await ChaosDriver.run(options))
case "ledger":
  let flags = Flags(arguments.dropFirst(2), options: ["--directory"])
  guard flags.positional.isEmpty, let directory = flags.values["--directory"] else { fail(usage) }
  exit(await EffectLedgerProcess.run(directory: absoluteURL(directory)))
case "ledger-summary":
  let flags = Flags(arguments.dropFirst(2), options: ["--journal"])
  guard flags.positional.isEmpty, let journal = flags.values["--journal"] else { fail(usage) }
  do {
    let summary = EffectLedgerState.summarize(
      try EffectLedgerJournal.read(URL(fileURLWithPath: journal)))
    FileHandle.standardOutput.write(try JSONLines.prettyEncoder.encode(summary) + Data("\n".utf8))
    exit(summary.total.duplicates == 0 && summary.total.conflicts == 0 ? 0 : 2)
  } catch {
    fail("ledger-summary: \(error)", status: 1)
  }
case "scan":
  let flags = Flags(arguments.dropFirst(2), options: [], repeatable: ["--exclude"])
  guard !flags.positional.isEmpty else { fail(usage) }
  var canaries: [Canary] = []
  while let line = readLine(strippingNewline: true) {
    guard let separator = line.firstIndex(of: "="), line[..<separator].isEmpty == false else {
      continue
    }
    let value = String(line[line.index(after: separator)...])
    // An empty needle matches nothing: an unset variable must not read as a clean scan.
    guard !value.isEmpty else { fail("scan: a canary on stdin has no value") }
    canaries.append(Canary(label: String(line[..<separator]), value: value))
  }
  guard !canaries.isEmpty else { fail("scan: no canaries on stdin") }
  do {
    let report = try CanaryScanner(canaries: canaries).scan(
      flags.positional.map { URL(fileURLWithPath: $0) },
      excluding: Set(flags.repeated["--exclude"] ?? []))
    FileHandle.standardOutput.write(try JSONLines.prettyEncoder.encode(report) + Data("\n".utf8))
    if !report.hits.isEmpty { exit(2) }
    // Zero hits is a clean scan only when something was read.
    guard report.filesScanned > 0 else { fail("scan: no file was read", status: 1) }
    exit(0)
  } catch {
    fail("scan: \(error)", status: 1)
  }
case "host":
  guard arguments.count == 2 else { fail(usage) }
  exit(await QualificationHost.run())
case "s1":
  let flags = Flags(
    arguments.dropFirst(2),
    options: ["--work-dir", "--output-dir", "--open-samples", "--timeout-seconds"])
  guard flags.positional.isEmpty,
    let work = flags.values["--work-dir"], let output = flags.values["--output-dir"],
    let samples = Int(flags.values["--open-samples"] ?? "3"), (1...30).contains(samples),
    let timeout = Int(flags.values["--timeout-seconds"] ?? "300"), (1...3600).contains(timeout),
    let executable = Bundle.main.executableURL
  else { fail(usage) }
  exit(
    await S1Driver.run(
      S1Options(
        workDirectory: absoluteURL(work), outputDirectory: absoluteURL(output),
        executable: executable, openSamples: samples, timeout: .seconds(timeout),
        arguments: Array(arguments.dropFirst()))))
case "lifecycle":
  let flags = Flags(arguments.dropFirst(2), options: ["--work-dir", "--output-dir"])
  guard flags.positional.isEmpty,
    let work = flags.values["--work-dir"], let output = flags.values["--output-dir"]
  else { fail(usage) }
  exit(await LifecycleDriver.run(work: absoluteURL(work), output: absoluteURL(output)))
case "s1-host":
  guard arguments.count == 2 else { fail(usage) }
  exit(await S1Host.run())
case "s2":
  let flags = Flags(
    arguments.dropFirst(2), options: ["--work-dir", "--output-dir"],
    switches: ["--quick", "--real-expiry", "--load", "--bonjour"])
  guard flags.positional.isEmpty, let work = flags.values["--work-dir"],
    let output = flags.values["--output-dir"], let executable = Bundle.main.executableURL
  else { fail(usage) }
  exit(
    await S2Driver.run(
      S2Options(
        workDirectory: absoluteURL(work), outputDirectory: absoluteURL(output),
        executable: executable, quick: flags.switches.contains("--quick"),
        realExpiry: flags.switches.contains("--real-expiry"),
        load: flags.switches.contains("--load"), bonjour: flags.switches.contains("--bonjour"))))
case "s2-device":
  let flags = Flags(arguments.dropFirst(2), options: ["--directory", "--name", "--platform"])
  guard flags.positional.isEmpty, let directory = flags.values["--directory"],
    let name = flags.values["--name"], let platform = flags.values["--platform"]
  else { fail(usage) }
  exit(await S2DeviceProcess.run(directory: absoluteURL(directory), name: name, platform: platform))
case "s2-relay":
  let flags = Flags(
    arguments.dropFirst(2), options: ["--directory"],
    switches: ["--no-authority-journal", "--no-grant-log"])
  guard flags.positional.isEmpty, let directory = flags.values["--directory"] else { fail(usage) }
  exit(
    await S2RelayProcess.run(
      directory: absoluteURL(directory),
      journalAuthority: !flags.switches.contains("--no-authority-journal"),
      keepGrants: !flags.switches.contains("--no-grant-log")))
case "s2-load":
  let flags = Flags(
    arguments.dropFirst(2),
    options: [
      "--relay-port", "--users", "--active", "--idle", "--active-renew-ms", "--active-ttl-ms",
      "--idle-renew-ms", "--idle-ttl-ms", "--moves", "--duration-ms", "--output",
    ])
  func number(_ name: String) -> Int64 {
    guard let value = flags.values[name].flatMap({ Int64($0) }), value >= 0 else { fail(usage) }
    return value
  }
  guard flags.positional.isEmpty, let output = flags.values["--output"] else { fail(usage) }
  exit(
    await S2LoadProcess.run(
      options: S2LoadOptions(
        relayPort: Int(number("--relay-port")), users: Int(number("--users")),
        activePerUser: Int(number("--active")), idlePerUser: Int(number("--idle")),
        activeRenewMs: number("--active-renew-ms"), activeTtlMs: number("--active-ttl-ms"),
        idleRenewMs: number("--idle-renew-ms"), idleTtlMs: number("--idle-ttl-ms"),
        movesPerUserPerCycle: Int(number("--moves")), durationMs: number("--duration-ms"),
        claimConcurrency: 32),
      output: URL(fileURLWithPath: output)))
case "s4-matrix":
  let flags = Flags(
    arguments.dropFirst(2), options: ["--parent", "--output-dir"],
    repeatable: ["--aliases-volume", "--owned-root"])
  guard flags.positional.isEmpty, let executable = Bundle.main.executableURL else { fail(usage) }
  let aliasVolumes = flags.repeated["--aliases-volume"] ?? []
  let ownedRoots = flags.repeated["--owned-root"] ?? []
  if !aliasVolumes.isEmpty, flags.values["--output-dir"] == nil {
    fail("s4-matrix: --aliases-volume requires --output-dir")
  }
  // The matrix compares canonical path bytes, so a relative spelling can never be owned.
  guard ownedRoots.allSatisfy({ $0.hasPrefix("/") }),
    flags.values["--parent"].map({ $0.hasPrefix("/") }) ?? true
  else { fail("s4-matrix: --parent and --owned-root take absolute canonical paths\n" + usage) }
  let outputDirectory = flags.values["--output-dir"].map { absoluteURL($0).path }
  // Like every other subcommand, evidence goes only into a directory this run creates.
  if let outputDirectory {
    var existing = stat()
    guard lstat(outputDirectory, &existing) == -1, errno == ENOENT else {
      fail("s4-matrix: --output-dir must not exist yet: \(outputDirectory)")
    }
  }
  do {
    let parent = try flags.values["--parent"] ?? S4Matrix.makeDefaultParent()
    let report = try S4Matrix.prepare(
      parent: parent, executable: executable, extraOwnedParents: ownedRoots
    ).run()
    let receipt = try S4Matrix.writeReceipt(report: report, root: report.root)
    var status = report.exitCode
    if let outputDirectory {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      try S4Matrix.createOutputDirectory(outputDirectory)
      try S4Matrix.writeExclusive(encoder.encode(report), to: outputDirectory + "/report.json")
      if !aliasVolumes.isEmpty {
        let aliasResults = aliasVolumes.map {
          S4MatrixAliases.probe(volume: URL(fileURLWithPath: $0, isDirectory: true))
        }
        try S4Matrix.writeExclusive(
          encoder.encode(aliasResults), to: outputDirectory + "/aliases.json")
        // A requested volume that was skipped or kept its scratch is a failed run, not a pass.
        for result in aliasResults where !result.writable || !result.cleanedUp {
          FileHandle.standardError.write(
            Data(
              ("s4-matrix: alias probe on \(result.volumePath) "
                + (result.writable ? "left its scratch behind" : "was skipped")
                + "\n").utf8))
          status = 3
        }
      }
      try S4Matrix.writeExclusive(
        S4Matrix.summary(report: report, receiptPath: receipt, exitCode: status),
        to: outputDirectory + "/summary.json")
    }
    FileHandle.standardOutput.write(
      try S4Matrix.summary(report: report, receiptPath: receipt, exitCode: status))
    FileHandle.standardOutput.write(Data("\n".utf8))
    FileHandle.standardError.write(Data((S4Matrix.humanSummary(report) + "\n").utf8))
    exit(status)
  } catch {
    fail("s4-matrix: \(error)", status: 1)
  }
default:
  fail(usage)
}
