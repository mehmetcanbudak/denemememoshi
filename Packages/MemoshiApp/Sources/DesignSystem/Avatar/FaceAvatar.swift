import SwiftUI

/// The parametric face with its status and unread badges. Decorative for VoiceOver: rows and
/// tiles carry the spoken label from `AvatarAccessibility`.
struct FaceAvatarView: View {
  let shape: AvatarShape
  let color: AvatarColor
  let status: AvatarStatus
  let overlays: AvatarOverlays
  let size: AvatarSize
  let botID: String
  @State private var isOnScreen = true

  var body: some View {
    let points = size.points
    let diameter = AvatarMetrics.badgeDiameter(points: points)
    let badge = size.showsBadges ? overlays.badge(for: status) : nil
    let showsUnread =
      size.showsBadges && overlays.unreadCount > 0 && points >= DS.Avatar.Overlays.Unread.hideBelow
    AvatarLayerRepresentable(
      model: AvatarLayerModel(
        shape: shape, color: color, status: status, overlays: overlays, size: size,
        botID: botID, statusHole: badge != nil, unreadHole: showsUnread, isOnScreen: isOnScreen)
    )
    .frame(width: points, height: points)
    .overlay(alignment: .bottomTrailing) {
      if let badge {
        AvatarBadge(style: badge, diameter: diameter)
      }
    }
    .overlay(alignment: .topTrailing) {
      if showsUnread {
        AvatarUnreadBadge(count: overlays.unreadCount, diameter: diameter)
      }
    }
    .onScrollVisibilityChange { isOnScreen = $0 }
    .accessibilityHidden(true)
  }
}

/// A status or overlay glyph on its role fill; the layer tree cuts the ring around it.
struct AvatarBadge: View {
  let style: AvatarBadgeStyle
  let diameter: CGFloat

  var body: some View {
    Circle()
      .fill(style.fill)
      .frame(width: diameter, height: diameter)
      .overlay {
        if let glyph = style.glyph {
          Image(systemName: glyph)
            .font(.system(size: diameter * DS.Avatar.Badge.glyphFraction, weight: .semibold))
            .foregroundStyle(style.ink)
        }
      }
  }
}

/// The unread count on the accent fill. A single digit keeps the badge circular; row labels and
/// VoiceOver carry the exact count.
struct AvatarUnreadBadge: View {
  private static let largestShown = 9

  let count: Int
  let diameter: CGFloat

  var body: some View {
    let style = DS.Avatar.StatusBadges.unread
    let font = Font.system(size: diameter * DS.Avatar.Badge.glyphFraction, weight: .semibold)
    Text(verbatim: count > Self.largestShown ? "\(Self.largestShown)+" : String(count))
      .font(font.monospacedDigit())
      .foregroundStyle(style.ink)
      .frame(width: diameter, height: diameter)
      .background(style.fill, in: Circle())
  }
}

/// Plain inputs for the layer tree; colors resolve against the representable's environment.
struct AvatarLayerModel: Equatable {
  let shape: AvatarShape
  let color: AvatarColor
  let status: AvatarStatus
  let overlays: AvatarOverlays
  let size: AvatarSize
  let botID: String
  let statusHole: Bool
  let unreadHole: Bool
  let isOnScreen: Bool

  func configuration(in environment: EnvironmentValues) -> AvatarLayerConfiguration {
    func resolved(_ role: AdaptiveColor) -> CGColor {
      role.resolve(in: environment).resolve(in: environment).cgColor
    }
    let increased = environment.effectiveIncreasedContrast
    let scale = max(environment.displayScale, 1)
    let edge = increased ? DS.Colors.Text.secondary : DS.Colors.Border.hairline
    let hairline = DS.Avatar.Face.Edge.hairlinePixels / scale
    let edgeWidth = increased ? DS.Avatar.Face.Edge.increasedContrastWidth : hairline
    return AvatarLayerConfiguration(
      shape: shape, points: size.points, loopFrameRateMax: size.loopFrameRateMax,
      status: status, takenOver: overlays.takenOver, offline: overlays.offline,
      fill: resolved(color.fill), mutedFill: resolved(color.muted), edge: resolved(edge),
      edgeWidth: edgeWidth, eyeInk: resolved(DS.Avatar.eyeInk),
      glow: resolved(DS.Avatar.StatusBadges.needsYouGlow),
      sparkle: resolved(DS.Avatar.StatusBadges.hasNews.fill), statusHole: statusHole,
      unreadHole: unreadHole, rightToLeft: environment.layoutDirection == .rightToLeft,
      reduceMotion: !environment.motionPolicy.allowsAvatarMotion, isOnScreen: isOnScreen,
      displayScale: scale, botID: botID)
  }
}

#if os(macOS)
  struct AvatarLayerRepresentable: NSViewRepresentable {
    let model: AvatarLayerModel

    func makeNSView(context: Context) -> AvatarHostView {
      AvatarHostView(frame: .zero)
    }

    func updateNSView(_ view: AvatarHostView, context: Context) {
      view.configure(model.configuration(in: context.environment))
    }

    static func dismantleNSView(_ view: AvatarHostView, coordinator: ()) {
      view.detach()
    }
  }
#else
  struct AvatarLayerRepresentable: UIViewRepresentable {
    let model: AvatarLayerModel

    func makeUIView(context: Context) -> AvatarHostView {
      AvatarHostView(frame: .zero)
    }

    func updateUIView(_ view: AvatarHostView, context: Context) {
      view.configure(model.configuration(in: context.environment))
    }

    static func dismantleUIView(_ view: AvatarHostView, coordinator: ()) {
      view.detach()
    }
  }
#endif
