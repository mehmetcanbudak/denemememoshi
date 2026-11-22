import QuartzCore
import SwiftUI

/// One generated color role and its canonical token path, for galleries and theme dumps.
public struct DesignColorRole: Identifiable, Sendable {
  /// The token path, such as `surface.card`.
  public let name: String
  /// The palette- and appearance-aware role.
  public let color: AdaptiveColor

  /// Stable identity: the token path.
  public var id: String { name }

  init(_ name: String, _ color: AdaptiveColor) {
    self.name = name
    self.color = color
  }
}

/// One canonical glyph mapping, without pretending custom/composed marks are SF Symbols.
public struct DesignGlyph: Identifiable, Sendable {
  /// The token path below `icon`, such as `composer.send`.
  public let name: String
  /// A native symbol or an explicit renderer/artwork reference.
  public let source: Source
  /// Stable identity: the canonical token path.
  public var id: String { name }

  /// Keeps reference-only inventory entries out of system-symbol APIs.
  public enum Source: Sendable {
    /// A verified native SF Symbol name.
    case system(String)
    /// The canonical custom/composed or deferred-renderer description, not a fallback glyph.
    case reference(String)
  }

  init(_ name: String, _ source: Source) {
    self.name = name
    self.source = source
  }
}

/// One generated length and its canonical token path.
public struct DesignMetric: Identifiable, Sendable {
  /// The token path, such as `space.4`.
  public let name: String
  /// The value in points.
  public let value: CGFloat

  /// Stable identity: the token path.
  public var id: String { name }

  init(_ name: String, _ value: CGFloat) {
    self.name = name
    self.value = value
  }
}

/// One generated chrome text role: a native text style plus its nominal macOS metrics.
public struct DesignTextRole: Identifiable, Sendable {
  /// The token name, such as `headline`.
  public let name: String
  /// The native, Dynamic Type–aware font for the role.
  public let font: Font
  /// The nominal macOS point size; the system may scale it.
  public let size: CGFloat
  /// The nominal macOS line height.
  public let lineHeight: CGFloat

  /// Stable identity: the token name.
  public var id: String { name }

  init(_ name: String, _ font: Font, _ size: CGFloat, _ lineHeight: CGFloat) {
    self.name = name
    self.font = font
    self.size = size
    self.lineHeight = lineHeight
  }
}

/// A cubic Bézier timing curve shared by SwiftUI and Core Animation.
public struct MotionCurve: Sendable {
  /// First control point, x.
  public let x1: Double
  /// First control point, y.
  public let y1: Double
  /// Second control point, x.
  public let x2: Double
  /// Second control point, y.
  public let y2: Double

  init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
    self.x1 = x1
    self.y1 = y1
    self.x2 = x2
    self.y2 = y2
  }

  /// The SwiftUI animation for this curve over a token duration.
  public func animation(duration: TimeInterval) -> Animation {
    .timingCurve(x1, y1, x2, y2, duration: duration)
  }

  /// The render-server timing function for this curve.
  var timingFunction: CAMediaTimingFunction {
    CAMediaTimingFunction(controlPoints: Float(x1), Float(y1), Float(x2), Float(y2))
  }
}

/// A spring expressed as SwiftUI's perceptual duration and bounce.
public struct MotionSpring: Sendable {
  /// Perceptual duration in seconds.
  public let duration: TimeInterval
  /// Bounce; zero is critically damped.
  public let bounce: Double

  /// The SwiftUI animation for this spring.
  public var animation: Animation { .spring(duration: duration, bounce: bounce) }

  /// Both renderers derive their physical coefficients from this same perceptual spring.
  var spring: Spring { Spring(duration: duration, bounce: bounce) }
}

/// One keyframe: a time in 0...1 of its period and a value in token units.
public struct AvatarKeyframe: Sendable {
  /// Time as a fraction of the period.
  public let time: CGFloat
  /// Value in view-box units, degrees or a unitless scale, as the token documents.
  public let value: CGFloat

  init(_ time: CGFloat, _ value: CGFloat) {
    self.time = time
    self.value = value
  }
}

/// One non-uniform scale keyframe.
public struct AvatarScaleKeyframe: Sendable {
  /// Time as a fraction of the period.
  public let time: CGFloat
  /// Horizontal scale.
  public let scaleX: CGFloat
  /// Vertical scale.
  public let scaleY: CGFloat

  init(_ time: CGFloat, scaleX: CGFloat, scaleY: CGFloat) {
    self.time = time
    self.scaleX = scaleX
    self.scaleY = scaleY
  }
}

/// A status or overlay badge: its glyph and the color roles that carry it.
public struct AvatarBadgeStyle: Sendable {
  /// The SF Symbol, or `nil` for the unread count badge.
  public let glyph: String?
  /// The badge fill.
  public let fill: AdaptiveColor
  /// The glyph or count color on the fill.
  public let ink: AdaptiveColor
  /// The glyph color beside text on ordinary surfaces.
  public let foreground: AdaptiveColor
}
