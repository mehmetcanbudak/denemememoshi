import MemoshiProtocol
import MemoshiStore

extension RuntimeAdapter {
  /// `bots.grants.list` for the authenticated app session, never a model-callable tool.
  public func listFolderGrants(
    _ params: BotsGrantsListParams
  ) async throws -> BotsGrantsListResult {
    try await requireSourceFolders().list(params)
  }

  /// `bots.grants.update` with the authenticated app user's authority. No caller names the
  /// actor, and no run or tool reaches this method.
  public func updateFolderGrant(
    _ params: BotsGrantsUpdateParams
  ) async throws -> BotsGrantsUpdateResult {
    try await requireSourceFolders().update(params, actor: Actor(kind: .user))
  }

  /// `bots.grants.revoke` with the authenticated app user's authority.
  public func revokeFolderGrant(_ params: BotsGrantsRevokeParams) async throws -> EmptyParams {
    try await requireSourceFolders().revoke(params, actor: Actor(kind: .user))
    return EmptyParams()
  }

  /// Folder management exists only with composed trusted host roots, and only while ready.
  private func requireSourceFolders() throws -> SourceFolderAuthority {
    guard let sourceFolders else { throw SourceFolderAuthorityError.notConfigured }
    try requireReady()
    return sourceFolders
  }
}
