import SwiftUI

/// A bot status line: the badge glyph beside its text, so status never relies on color or
/// motion alone (D30). In control and offline overlays take the glyph, as on the avatar.
public struct BotStatusLabel: View {
  private let status: AvatarStatus
  private let detail: String?
  private let overlays: AvatarOverlays

  /// Creates a status line. `detail` omits the status name, such as "reading pricing page";
  /// the line then reads "Working: reading pricing page". Without one, the status name shows.
  public init(
    _ status: AvatarStatus, detail: String? = nil, overlays: AvatarOverlays = AvatarOverlays()
  ) {
    self.status = status
    self.detail = detail
    self.overlays = overlays
  }

  /// Glyph, then text, in the secondary text role.
  public var body: some View {
    let badge = overlays.badge(for: status)
    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
      Image(systemName: badge?.glyph ?? "circle")
        .foregroundStyle(badge?.foreground ?? DS.Colors.Text.secondary)
        .accessibilityHidden(true)
      status.subtitle(detail: detail)
    }
    .font(DS.Typography.callout)
    .foregroundStyle(DS.Colors.Text.secondary)
  }
}
