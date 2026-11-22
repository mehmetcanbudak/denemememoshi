import Foundation
import MemoshiRuntime

/// Trusted host composition for development builds. The normal composition supplies no tools;
/// production tools stay off until their gates pass.
enum DevelopmentComposition {
  /// An explicit Debug-only review root. It constructs no engine, broker or runtime owner.
  /// `-MemoshiDevelopmentBrowserReview YES` is an argument-domain choice, not tool authority.
  static var isolatedBrowserReview: Bool {
    #if DEBUG
      DevelopmentLaunchArgument.isSet("MemoshiDevelopmentBrowserReview")
    #else
      false
    #endif
  }

  /// Debug builds launched with `-MemoshiDevelopmentApprovalTool YES` get
  /// `DevelopmentApprovalProbe`, a test tool whose every call needs the user's approval (P0-09's
  /// approval Card). Debug builds launched with `-MemoshiDevelopmentPythonTool YES` get
  /// `python_run` (S6.5, `DevelopmentPythonTool`). Release builds compile neither tool, and all
  /// other launches get none.
  static func tools(directory: URL) -> [RuntimeToolDefinition] {
    #if DEBUG
      let support = directory.deletingLastPathComponent()
      var tools: [RuntimeToolDefinition] = []
      if DevelopmentLaunchArgument.isSet(DevelopmentApprovalProbe.launchArgument) {
        tools.append(
          DevelopmentApprovalProbe.definition(
            notes: support.appendingPathComponent("development-notes.txt")))
      }
      if DevelopmentLaunchArgument.isSet("MemoshiDevelopmentPythonTool") {
        tools.append(DevelopmentPythonTool.definition(support: support))
      }
      return tools
    #else
      return []
    #endif
  }
}
