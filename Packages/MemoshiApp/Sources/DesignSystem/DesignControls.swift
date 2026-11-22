import SwiftUI

/// The checked roles native controls draw with (03 §4.2). Token values are unchanged; these
/// select which already-checked role a control uses.
public enum DesignControlRoles {
  /// Control tint for links and inline actions: `accent.text`, never `accent.default`.
  public static let tint = DS.Colors.Accent.text
  /// Placeholder and prompt text that still meets AA.
  public static let placeholder = DS.Colors.Text.placeholder
  /// Secondary and empty-state description text that meets AA.
  public static let secondaryText = DS.Colors.Text.secondary
  /// The opaque surface behind floating bars on iPhone and iPad (the conversation header with
  /// the toolbar and tab bar above it, and the composer): `surface.window`. Content scrolled
  /// under a bar stops at its edge instead of showing through its glass.
  public static let barBacking = DS.Colors.Surface.window

  /// A field or card boundary: its standard role, or `border.strong` under Increase Contrast.
  public static func boundary(standard: AdaptiveColor, increasedContrast: Bool) -> AdaptiveColor {
    increasedContrast ? DS.Colors.Border.strong : standard
  }
}

extension View {
  /// Strokes a field or card edge, switching to `border.strong` under Increase Contrast.
  public func designBoundary<S: InsettableShape>(
    _ shape: S, standard: AdaptiveColor = DS.Colors.Border.field
  ) -> some View {
    overlay { DesignBoundary(shape: shape, standard: standard) }
  }
}

private struct DesignBoundary<S: InsettableShape>: View {
  let shape: S
  let standard: AdaptiveColor
  @Environment(\.effectiveIncreasedContrast) private var increasedContrast

  var body: some View {
    shape.strokeBorder(
      DesignControlRoles.boundary(standard: standard, increasedContrast: increasedContrast))
  }
}

/// A primary action on `accent.fill` with `accent.onFill` content, which meets 4.5:1 in both
/// palettes and every appearance, unlike a system prominent style tinted with the raw accent.
public struct DesignProminentButtonStyle: ButtonStyle {
  /// The fill role.
  public static let fill = DS.Colors.Accent.fill
  /// The label role carried on the fill.
  public static let label = DS.Colors.Accent.onFill
  /// The translucent role drawn over the fill while the button is pressed. `accent.onFill`
  /// over it is a checked pair; an opaque surface role here would hide the fill under the label.
  public static let pressedOverlay = DS.Colors.Surface.hover

  private let minimumSize: CGFloat

  /// `minimumSize` is the hit region in both dimensions, inside the button's own shape.
  public init(minimumSize: CGFloat = DS.Layout.HitTarget.preferred) {
    self.minimumSize = minimumSize
  }

  /// Draws the label on the fill, dimmed with disabled semantics when the button is disabled.
  public func makeBody(configuration: Configuration) -> some View {
    DesignProminentButton(configuration: configuration, minimumSize: minimumSize)
  }
}

private struct DesignProminentButton: View {
  let configuration: ButtonStyleConfiguration
  let minimumSize: CGFloat
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .font(DS.Typography.body.weight(.semibold))
      .foregroundStyle(DesignProminentButtonStyle.label)
      .padding(.horizontal, DS.Space.s4)
      .frame(minWidth: minimumSize, minHeight: minimumSize)
      .background {
        Capsule().fill(DesignProminentButtonStyle.fill)
        if configuration.isPressed { Capsule().fill(DesignProminentButtonStyle.pressedOverlay) }
      }
      .opacity(isEnabled ? 1 : DS.Opacity.disabled)
      .contentShape(Capsule())
  }
}

extension ButtonStyle where Self == DesignProminentButtonStyle {
  /// The primary action style; see `DesignProminentButtonStyle`.
  public static var designProminent: DesignProminentButtonStyle { DesignProminentButtonStyle() }

  /// The primary action style with an explicit hit region, such as 44 pt on iPhone and iPad.
  public static func designProminent(minimumSize: CGFloat) -> DesignProminentButtonStyle {
    DesignProminentButtonStyle(minimumSize: minimumSize)
  }
}

extension View {
  /// A sheet's default action: Return triggers it, and it draws with `.designProminent`, whose
  /// `accent.fill` + `accent.onFill` pair meets 4.5:1 in both palettes and every appearance. A
  /// system default button would draw its label over the `accent.text` control tint instead.
  public func designDefaultAction() -> some View {
    keyboardShortcut(.defaultAction).buttonStyle(.designProminent)
  }
}
