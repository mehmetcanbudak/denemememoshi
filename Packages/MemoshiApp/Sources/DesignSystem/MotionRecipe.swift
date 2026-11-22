import SwiftUI

/// The live user preference. Off is an explicit choice; System follows the OS setting.
public enum MotionPreference: String, CaseIterable, Identifiable, Sendable {
  case system, on, off

  /// Stable native picker identity.
  public var id: Self { self }

  /// Localized preference label.
  public var title: LocalizedStringResource {
    switch self {
    case .system: LocalizedStringResource("System", bundle: #bundle)
    case .on: LocalizedStringResource("On", bundle: #bundle)
    case .off: LocalizedStringResource("Off", bundle: #bundle)
    }
  }

  static let preferenceKey = "accessibility.reduce-motion"
  static let avatarPreferenceKey = "accessibility.animate-bot-avatars"
}

/// One value policy for all Memoshi-owned motion, not a second animation clock.
public struct MotionPolicy: Equatable, Sendable {
  /// Whether only still states or the recipe's short opacity crossfade are allowed.
  public var reduceMotion: Bool
  /// Ambient loops stop in Low Power Mode; one-shots remain available.
  public var lowPower: Bool
  /// False for off-screen, occluded, minimized, hidden or sleeping surfaces.
  public var isVisible: Bool
  /// The live Pause/Stop preference for avatar motion.
  public var animateAvatars: Bool

  /// Creates a resolved policy. Hosts supply actual visibility and power state.
  public init(
    reduceMotion: Bool, lowPower: Bool = false, isVisible: Bool = true,
    animateAvatars: Bool = true
  ) {
    self.reduceMotion = reduceMotion
    self.lowPower = lowPower
    self.isVisible = isVisible
    self.animateAvatars = animateAvatars
  }

  /// Render-server ambient work is permitted only while visible and unconstrained.
  public var allowsAmbientMotion: Bool { isVisible && !reduceMotion && !lowPower }

  /// Avatar one-shots obey Pause/Stop as well as visibility and Reduce Motion.
  public var allowsAvatarMotion: Bool { isVisible && !reduceMotion && animateAvatars }
}

extension EnvironmentValues {
  /// The in-app tri-state preference, applied live at the appearance boundary.
  @Entry public var motionPreference: MotionPreference = .system
  /// Stops original avatar loops and one-shots without hiding their status cues.
  @Entry public var animateBotAvatars: Bool = true
  /// The nearest motion owner supplies visibility; avatar hosts also check their real window.
  @Entry public var motionIsVisible: Bool = true
  /// The appearance boundary refreshes this on system power-state notifications.
  @Entry public var motionLowPower: Bool = false

  /// The only policy consumed by native recipe bindings.
  public var motionPolicy: MotionPolicy {
    MotionPolicy(
      reduceMotion: effectiveReduceMotion, lowPower: motionLowPower,
      isVisible: motionIsVisible, animateAvatars: animateBotAvatars)
  }
}

/// A recipe's off-state. Horizontal offsets are logical, not hard-coded screen directions.
public struct MotionTransform: Equatable, Sendable {
  /// Opacity of the absent state.
  public let opacity: Double
  /// Logical horizontal offset in points.
  public let offsetX: CGFloat
  /// Vertical offset in points.
  public let offsetY: CGFloat
  /// Uniform scale of the absent state.
  public let scale: CGFloat

  init(opacity: Double = 1, offsetX: CGFloat = 0, offsetY: CGFloat = 0, scale: CGFloat = 1) {
    self.opacity = opacity
    self.offsetX = offsetX
    self.offsetY = offsetY
    self.scale = scale
  }

  /// Reduce Motion never retains displacement or scale; instant forms retain no fade either.
  public func resolved(reduceMotion: Bool, fades: Bool, rightToLeft: Bool) -> MotionTransform {
    if reduceMotion {
      return MotionTransform(opacity: fades ? 0 : 1)
    }
    return MotionTransform(
      opacity: opacity, offsetX: rightToLeft ? -offsetX : offsetX,
      offsetY: offsetY, scale: scale)
  }
}

/// Generated recipe metadata and native bindings. Declaration is not product adoption: the
/// later reveal/shimmer/ticker/roster/Metal passes remain outside Phase 0.
public struct MotionRecipe: Identifiable, Sendable {
  /// Canonical `motion.recipes` key.
  public let id: String
  /// Named source from the JSON, or Memoshi's native state recipe.
  public let source: String
  /// Normal duration in seconds.
  public let duration: TimeInterval
  /// One shared generated timing curve.
  public let curve: MotionCurve
  /// The absent state, for transitions that actually have one.
  public let absent: MotionTransform
  /// Reduce Motion opacity duration; zero is an instant final state.
  public let reducedDuration: TimeInterval
  /// Main-thread budget class from the canonical recipe.
  public let budget: String

  /// Hidden motion is instant. Low Power Mode removes loops, not bounded one-shots.
  public func duration(for policy: MotionPolicy) -> TimeInterval {
    guard policy.isVisible else { return 0 }
    return policy.reduceMotion ? reducedDuration : duration
  }

  /// No implicit/default animation is substituted for a still form.
  public func animation(for policy: MotionPolicy) -> Animation? {
    let duration = duration(for: policy)
    return duration > 0 ? curve.animation(duration: duration) : nil
  }

  /// A token-driven transition; RTL mirrors only the logical horizontal offset.
  public func transition(for policy: MotionPolicy, rightToLeft: Bool = false) -> AnyTransition {
    guard duration(for: policy) > 0 else { return .identity }
    let state = absent.resolved(
      reduceMotion: policy.reduceMotion, fades: reducedDuration > 0, rightToLeft: rightToLeft)
    return .modifier(
      active: MotionTransformModifier(state: state),
      identity: MotionTransformModifier(state: MotionTransform()))
  }
}

private struct MotionTransformModifier: ViewModifier {
  let state: MotionTransform

  func body(content: Content) -> some View {
    content.opacity(state.opacity).scaleEffect(state.scale)
      .offset(x: state.offsetX, y: state.offsetY)
  }
}

/// Conditional native content with an explicit Reduce Motion form. The removed subtree loses
/// hit testing, enabled controls and accessibility immediately, rather than leaving a clickable
/// fading snapshot. SwiftUI owns removal and releases keyboard focus with the subtree.
public struct MotionPresence<Content: View>: View {
  private let isPresented: Bool
  private let recipe: MotionRecipe
  private let content: () -> Content
  @Environment(\.motionPolicy) private var policy
  @Environment(\.layoutDirection) private var direction

  /// Creates a causal enter/exit site; never use it for scrolling cells or first paint.
  public init(
    isPresented: Bool, recipe: MotionRecipe, @ViewBuilder content: @escaping () -> Content
  ) {
    self.isPresented = isPresented
    self.recipe = recipe
    self.content = content
  }

  /// Native removal owns retention; there is no timer or duplicate view identity.
  public var body: some View {
    Group {
      if isPresented {
        content()
          .transition(recipe.transition(for: policy, rightToLeft: direction == .rightToLeft))
      }
    }
    .allowsHitTesting(isPresented)
    .disabled(!isPresented)
    .accessibilityHidden(!isPresented)
    .animation(recipe.animation(for: policy), value: isPresented)
  }
}
