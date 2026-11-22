import Darwin
import Dispatch
import Foundation
import MemoshiDaemon
import MemoshiProtocol
import MemoshiRuntime
import MemoshiStore

/// launchd owns the normal service; --foreground gives an app-owned child a stdin lifetime pipe.
enum Request {
  case version
  case help
  case sandboxEnvDaemon
  case serve(directory: URL, foreground: Bool, textChat: Bool, approvalTool: Bool)
  case usage

  init(arguments: [String]) {
    if arguments == ["--version"] {
      self = .version
      return
    }
    if arguments == ["--help"] {
      self = .help
      return
    }
    if arguments == ["--sandbox-env-daemon"] {
      self = .sandboxEnvDaemon
      return
    }
    var directory = DaemonConfiguration.defaultDataDirectory
    var foreground = false
    var textChat = true
    var sawDevelopmentChat = false
    var approvalTool = false
    var hasDirectory = false
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--foreground" where foreground == false:
        foreground = true
        index += 1
      case "--development-chat" where sawDevelopmentChat == false:
        sawDevelopmentChat = true
        textChat = true
        index += 1
      case "--data-directory" where hasDirectory == false && index + 1 < arguments.count:
        directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        hasDirectory = true
        index += 2
      #if DEBUG
        // Only the Mac app's own development helper gets it, when the app was launched with
        // `-MemoshiDevelopmentApprovalTool YES`; Release builds compile no such option.
        case DevelopmentApprovalProbe.helperFlag where approvalTool == false:
          approvalTool = true
          index += 1
      #endif
      default:
        self = .usage
        return
      }
    }
    // Tools exist only in the development chat composition (DaemonServer refuses them otherwise).
    guard textChat || !approvalTool else {
      self = .usage
      return
    }
    self = .serve(
      directory: directory, foreground: foreground, textChat: textChat, approvalTool: approvalTool)
  }
}

#if DEBUG
  let developmentOptionsHelp =
    "  \(DevelopmentApprovalProbe.helperFlag)\n" + String(repeating: " ", count: 26)
    + "Debug builds, with --development-chat: offer the approval test tool "
    + "\(DevelopmentApprovalProbe.name).\n"
#else
  let developmentOptionsHelp = ""
#endif

let helpText = """
  Usage: memoshid [--foreground] [--data-directory <path>] [--development-chat]
         memoshid --version | --help

  Runs Memoshi's authenticated local storage and JSON-RPC service. Text-only Pi
  development chat, the app Keychain broker and local folder-grant management are
  opt-in and require a separate data directory. Tools and Apple connectors are off.
  Apple-signed hardened peers are required.

  Options:
    --foreground            Stop gracefully when the owning app closes stdin.
    --data-directory <path> Use this private data directory instead of Application Support/Memoshi.
    --development-chat      Enable text-only chat, the app Keychain broker and local folder grants outside the production data directory.
    --version               Print the build and supported protocol versions.
    --help                  Print this help.
  \(developmentOptionsHelp)
  """

func versionText(bundle: Bundle) -> String {
  let info = bundle.infoDictionary ?? [:]
  let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
  let build = info["CFBundleVersion"] as? String ?? "unknown"
  return """
    memoshid \(version) (build \(build))
    protocol versions \(ProtocolVersion.minimum) through \(ProtocolVersion.current)

    """
}

func report(_ text: String) {
  FileHandle.standardError.write(Data(("memoshid: " + text + "\n").utf8))
}

/// The development tools of this launch: none, except `DevelopmentApprovalProbe` in a Debug build
/// started with its flag. Its notes file sits beside the data directory, as on the iPhone.
func developmentTools(directory: URL, approvalTool: Bool) -> [RuntimeToolDefinition] {
  #if DEBUG
    guard approvalTool else { return [] }
    let notes = directory.deletingLastPathComponent()
      .appendingPathComponent("development-notes.txt")
    return [DevelopmentApprovalProbe.definition(notes: notes)]
  #else
    return []
  #endif
}

func runDaemon(
  directory: URL, foreground: Bool, textChat: Bool, tools: [RuntimeToolDefinition]
) async -> Int32 {
  do {
    let bundle = Bundle.main
    guard
      let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      let schema = bundle.url(forResource: "protocol.schema", withExtension: "json")
    else {
      report("invalid_bundle: build metadata or protocol schema is missing")
      return EX_CONFIG
    }
    let configuration = try DaemonConfiguration(
      dataDirectory: directory, version: version, build: build,
      canonicalSchema: Data(contentsOf: schema), enableTextChat: textChat)
    let sandboxCommand: [String]? =
      textChat ? bundle.executablePath.map { [$0, "--sandbox-env-daemon"] } : nil
    let server = try DaemonServer(
      configuration: configuration, tools: tools, sandboxDaemonCommand: sandboxCommand)
    var sources: [any DispatchSourceProtocol] = []
    for number in [SIGTERM, SIGINT] {
      signal(number, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
      source.setEventHandler {
        Task {
          do { try await server.stop(reason: .signal) } catch { report("shutdown_failed") }
        }
      }
      source.activate()
      sources.append(source)
    }
    if foreground {
      // Only the app keeps the write end. No parent PID polling or daemon-process kill is used.
      let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .global())
      source.setEventHandler {
        var byte: UInt8 = 0
        let count = Darwin.read(STDIN_FILENO, &byte, 1)
        if count == 0 || (count < 0 && errno != EINTR && errno != EAGAIN) {
          source.setEventHandler(handler: nil)
          source.cancel()
          Task {
            do { try await server.stop(reason: .user) } catch { report("shutdown_failed") }
          }
        }
      }
      source.activate()
      sources.append(source)
    }
    defer {
      for source in sources {
        source.setEventHandler(handler: nil)
        source.cancel()
      }
    }
    do {
      try await server.start()
      if !textChat {
        report("ready: authenticated local service; engine unavailable")
      } else if tools.isEmpty {
        report(
          "ready: authenticated text chat with app Keychain broker; tools and Apple connectors disabled"
        )
      } else {
        report(
          "ready: authenticated text chat with app Keychain broker; \(tools.count) development "
            + "tool(s); Apple connectors disabled")
      }
      try await server.waitUntilStopped()
      return EX_OK
    } catch DaemonError.notRunning {
      // A normal owner EOF or signal may arrive while the socket is still being bound.
      try await server.waitUntilStopped()
      return EX_OK
    }
  } catch StoreError.alreadyRunning {
    report("already_running")
    return EX_TEMPFAIL
  } catch StoreError.alreadyOpen {
    report("store_already_open")
    return EX_TEMPFAIL
  } catch StoreError.schemaTooNew(let found, let supported) {
    report("schema_too_new: found \(found), supported \(supported); restore the compatible backup")
    return EX_CONFIG
  } catch {
    // Startup/storage errors contain no RPC frames, token bytes or provider credentials.
    report("service_failed: \(error)")
    return EX_SOFTWARE
  }
}

switch Request(arguments: Array(CommandLine.arguments.dropFirst())) {
case .version:
  print(versionText(bundle: .main), terminator: "")
case .help:
  print(helpText, terminator: "")
case .usage:
  FileHandle.standardError.write(Data(helpText.utf8))
  exit(EX_USAGE)
case .sandboxEnvDaemon:
  Task {
    exit(await RuntimeSandboxDaemon.serve())
  }
  dispatchMain()
case .serve(let directory, let foreground, let textChat, let approvalTool):
  let tools = developmentTools(directory: directory, approvalTool: approvalTool)
  Task {
    let code = await runDaemon(
      directory: directory, foreground: foreground, textChat: textChat, tools: tools)
    exit(code)
  }
  dispatchMain()
}
