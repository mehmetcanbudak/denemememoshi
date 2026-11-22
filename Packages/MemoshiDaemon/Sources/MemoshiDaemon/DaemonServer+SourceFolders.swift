import Darwin
import Foundation
import MemoshiRuntime

extension DaemonServer {
  /// Trusted source-policy roots from the operating system's account record and this helper's
  /// own placement, never from RPC, model or environment input: the physical account home, and
  /// the data directory (store, Pi conversations, token and backups) plus the enclosing app
  /// bundle as protected Memoshi state. `nil` keeps folder management unavailable.
  static func sourcePolicyContext(dataDirectory: URL) -> SourcePathPolicyContext? {
    #if os(macOS)
      guard let home = accountHome(), let state = physicalPath(dataDirectory.path),
        let helper = physicalPath(Bundle.main.bundleURL.path)
      else { return nil }
      let context = SourcePathPolicyContext(
        userHome: home, protectedStateRoots: [state, outermostBundle(helper)])
      // Usable only if the whole context is canonical and its own state can never be granted.
      do {
        _ = try SourcePathPolicy.validateGrantRoot(state, context: context)
        return nil
      } catch SourcePathPolicyError.notGrantable {
        return context
      } catch {
        return nil
      }
    #else
      return nil
    #endif
  }

  /// The effective user's home directory from the account database, not `HOME`.
  private static func accountHome() -> String? {
    var account = passwd()
    var found: UnsafeMutablePointer<passwd>?
    return withUnsafeTemporaryAllocation(of: CChar.self, capacity: 16_384) { buffer in
      guard let base = buffer.baseAddress,
        getpwuid_r(geteuid(), &account, base, buffer.count, &found) == 0, found != nil,
        let directory = account.pw_dir
      else { return nil }
      return physicalPath(String(cString: directory))
    }
  }

  /// The outermost `.app` containing this helper, so the whole Memoshi.app stays protected.
  private static func outermostBundle(_ path: String) -> String {
    var components: [Substring] = []
    var outermost: String?
    for component in path.split(separator: "/") {
      components.append(component)
      if outermost == nil, component.lowercased().hasSuffix(".app") {
        outermost = "/" + components.joined(separator: "/")
      }
    }
    return outermost ?? path
  }

  private static func physicalPath(_ path: String) -> String? {
    path.withCString { input in
      withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(MAXPATHLEN)) { buffer in
        guard let address = buffer.baseAddress, realpath(input, address) != nil else { return nil }
        return String(cString: address)
      }
    }
  }
}
