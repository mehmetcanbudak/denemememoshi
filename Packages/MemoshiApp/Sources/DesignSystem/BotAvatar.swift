import SwiftUI

/// A bot's identity mark. The design-preview shell uses original SF Symbol compositions; the
/// P0-13 prototype draws the parametric Memoshi face with its status badge, overlays and
/// Core Animation motion. Neither form bundles artwork from a reference app.
public struct BotAvatar: View {
  private enum Content {
    case symbol(String, CGFloat)
    case face(Face)
  }

  private struct Face {
    let shape: AvatarShape
    let color: AvatarColor
    let status: AvatarStatus
    let overlays: AvatarOverlays
    let size: AvatarSize
    let botID: String
  }

  private let content: Content

  /// Creates a decorative identity from an SF Symbol at a token-sized dimension.
  public init(symbol: String, size: CGFloat = DS.Layout.AvatarGrid.avatarSize) {
    content = .symbol(symbol, size)
  }

  /// Creates the parametric face for a bot's `{shape, color}` pair.
  ///
  /// Pass the bot's stable identifier: it offsets loop phases so a roster never moves in
  /// unison and rate-limits one-shots per bot. The face is decorative for VoiceOver; give the
  /// containing row `AvatarAccessibility.label(name:status:detail:overlays:)`.
  public init(
    shape: AvatarShape, color: AvatarColor, status: AvatarStatus = .idle,
    overlays: AvatarOverlays = AvatarOverlays(), size: AvatarSize = .lg, botID: String
  ) {
    let face = Face(
      shape: shape, color: color, status: status, overlays: overlays, size: size, botID: botID)
    content = .face(face)
  }

  /// Renders the selected identity form.
  public var body: some View {
    switch content {
    case .symbol(let symbol, let size):
      SymbolAvatar(symbol: symbol, size: size)
    case .face(let face):
      FaceAvatarView(
        shape: face.shape, color: face.color, status: face.status, overlays: face.overlays,
        size: face.size, botID: face.botID)
    }
  }
}

/// The original symbol-based preview identity using adaptive accent and border roles.
private struct SymbolAvatar: View {
  let symbol: String
  let size: CGFloat

  var body: some View {
    Image(systemName: symbol)
      .font(.body.weight(.semibold))
      .foregroundStyle(DS.Colors.Accent.text)
      .frame(width: size, height: size)
      .background(DS.Colors.Accent.selection, in: Circle())
      .overlay {
        Circle().strokeBorder(DS.Colors.Border.subtle)
      }
      .accessibilityHidden(true)
  }
}
