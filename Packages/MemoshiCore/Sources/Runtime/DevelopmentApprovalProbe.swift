#if DEBUG
  import Foundation
  import MemoshiProtocol

  /// Debug-only launch choices of the development compositions: the iPhone and iPad app's
  /// in-process engine, and the Mac app, which hands its choices to the memoshid it owns. Release
  /// builds compile none of this file; `scripts/check-bundle.sh --release-composition` scans
  /// Release code for its names.
  public enum DevelopmentLaunchArgument {
    /// Whether this launch's arguments set `key` to true (`-key YES`). Only the argument domain is
    /// read, so a value saved in the app's persistent defaults enables nothing. `-key NO` and a
    /// missing argument read as false, as `UserDefaults.bool(forKey:)` reads them.
    public static func isSet(_ key: String) -> Bool {
      isSet(key, in: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain))
    }

    /// `isSet(_:)` over an explicit argument domain.
    public static func isSet(_ key: String, in arguments: [String: Any]) -> Bool {
      switch arguments[key] {
      case let value as Bool: value
      case let value as String: (value as NSString).boolValue
      default: false
      }
    }
  }

  /// A development test tool whose every call needs the user's approval (P0-09's approval Card).
  /// It appends one line to a development file on this device. It is unclassified, so policy asks
  /// before every call, whatever the permission mode; nothing leaves the device.
  public enum DevelopmentApprovalProbe {
    /// The app launch argument that composes it: `-MemoshiDevelopmentApprovalTool YES`.
    public static let launchArgument = "MemoshiDevelopmentApprovalTool"
    /// The flag with which the Mac app hands the tool to its own development memoshid.
    public static let helperFlag = "--development-approval-tool"
    /// The model-visible tool name.
    public static let name = "development_note"

    /// The tool, appending `<effect key>\t<note>` lines to `notes`.
    public static func definition(notes: URL) -> RuntimeToolDefinition {
      RuntimeToolDefinition(
        name: name,
        description:
          "Development only: save one short note on this device. Each call asks the user first.",
        parameters: [
          "type": "object",
          "properties": ["note": ["type": "string", "minLength": 1, "maxLength": 200]],
          "required": ["note"], "additionalProperties": false,
        ],
        operation: .unknown,
        authorize: { _ in true },
        execute: { arguments, invocation in
          guard case .object(let values) = arguments, case .string(let note)? = values["note"],
            !note.isEmpty, note.count <= 200
          else { throw RuntimeToolError.invalidArguments }
          let line = invocation.effectKey + "\t" + note.replacingOccurrences(of: "\n", with: " ")
          try append(line + "\n", to: notes)
          return RuntimeToolResult(text: "Saved the note on this device.")
        })
    }

    private static func append(_ text: String, to url: URL) throws {
      if !FileManager.default.fileExists(atPath: url.path) {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
          throw RuntimeToolError.unavailable
        }
      }
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: Data(text.utf8))
      try handle.synchronize()
    }
  }
#endif
