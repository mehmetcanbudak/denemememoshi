import MemoshiProtocol
import MemoshiRuntime
import MemoshiStore

extension RPCSession {
  /// Folder management needs the composed backend and this connection's negotiated capability.
  func requireFolderGrants() throws -> RuntimeAdapter {
    guard capabilities.contains(where: { $0.rawValue == "bots.grants.folder.v1" }),
      let runtime
    else {
      throw RPCError(
        message: "Folder grants are not enabled for this daemon.",
        data: RPCErrorData(details: .methodNotFound))
    }
    guard negotiated.contains(where: { $0.rawValue == "bots.grants.folder.v1" }) else {
      throw RPCError(
        message: "This connection did not negotiate bots.grants.folder.v1.",
        data: RPCErrorData(details: .capabilityMissing))
    }
    return runtime
  }

  /// Fixed, safe messages: paths, bookmarks, source identities and OS errors never reach the app.
  static func folderGrantRefusal(_ error: FolderGrantError) -> RPCError {
    switch error {
    case .notFound:
      refused(.notFound, "The bot or folder grant was not found.")
    case .invalidRequest:
      invalidFolderGrant(
        path: "/params/grant",
        message:
          "Send a new folder with its selected identity and no ID or revision, or an existing grant's ID, exact path and current revision without a different expiry or selection."
      )
    case .forbidden:
      refused(.forbidden, "Only the authenticated app user may change folder grants.")
    case .unavailable:
      refused(
        .conflict,
        "This folder grant has ended. Refresh, then choose the folder again to grant it.")
    case .staleReference:
      refused(.conflict, "This folder grant changed. Refresh before changing it.")
    case .alreadyGranted:
      refused(.conflict, "This folder is already granted to this bot. Change its access instead.")
    case .limitReached:
      refused(
        .conflict, "This bot already has the most active folder grants allowed. Revoke one first.")
    }
  }

  /// Root and confirmation refusals; none names the folder or the operating-system reason.
  static func sourceFolderRefusal(_ error: SourceFolderAuthorityError) -> RPCError {
    switch error {
    case .invalidRoot:
      invalidFolderGrant(
        path: "/params/grant/path",
        message:
          "Choose the folder with the folder picker. It must be a folder you own, at its physical location without symbolic links."
      )
    case .confirmationRequired:
      refused(.typedConfirmationMismatch, "Type the folder's exact path to confirm this grant.")
    case .unavailable:
      refused(
        .conflict, "The folder is unavailable. Reconnect it, or choose it again for a new grant.")
    case .changedRoot:
      refused(
        .conflict, "The folder changed since it was chosen. Choose it again to create a new grant.")
    case .unsupportedPlatform:
      refused(.methodNotFound, "Folder grants are not available here.")
    case .notConfigured:
      refused(.methodNotFound, "Folder grants are not enabled for this daemon.")
    }
  }

  /// Policy refusals of a requested root.
  static func sourcePathRefusal(_ error: SourcePathPolicyError) -> RPCError {
    switch error {
    case .invalidPath:
      invalidFolderGrant(
        path: "/params/grant/path",
        message: "The folder path must be the absolute physical path the folder picker returned.")
    case .notGrantable:
      refused(
        .forbidden,
        "This folder can't be granted. Choose a specific folder, not the home folder, a system or Library folder, or Memoshi's own data."
      )
    }
  }

  private static func invalidFolderGrant(path: String, message: String) -> RPCError {
    refused(
      .invalidParams(InvalidParamsDetails(issues: [ParamIssue(path: path, message: message)])),
      message)
  }

  private static func refused(_ details: RPCErrorDetails, _ message: String) -> RPCError {
    RPCError(message: message, data: RPCErrorData(details: details))
  }
}
