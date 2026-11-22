/// The protocol's major versions this build speaks (protocol.md §3.5).
///
/// Each side of a connection declares `{min, max}` in `system.hello`, and the
/// chosen version is the highest one both support.
public enum ProtocolVersion {
  /// The newest major version this build supports.
  public static let current = 1

  /// The oldest major version this build still accepts. N-1 support begins
  /// once version 2 exists.
  public static let minimum = 1
}
