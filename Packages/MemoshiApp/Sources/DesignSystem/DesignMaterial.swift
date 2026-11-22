import SwiftUI

/// D85's appearance selection is independent of the Current/Warm palette comparison.
public enum ChromeAppearance: String, CaseIterable, Identifiable, Sendable {
  case frosted, solid

  /// Stable picker identity.
  public var id: Self { self }
  /// Native preference label.
  public var title: LocalizedStringResource {
    self == .frosted
      ? LocalizedStringResource("Frosted", bundle: #bundle)
      : LocalizedStringResource("Solid", bundle: #bundle)
  }
  static let preferenceKey = "appearance.chrome"
}

extension EnvironmentValues {
  /// Custom chrome only; system toolbars, sidebars, menus and sheets keep their native style.
  @Entry public var chromeAppearance: ChromeAppearance = .frosted
}

/// A generated opaque shadow. Glass supplies its own elevation and never applies this ladder.
public struct DesignShadow: Sendable {
  let color: Color
  let radius: CGFloat
  let x: CGFloat
  let y: CGFloat

  init(rgba: UInt32, opacity: Double, radius: CGFloat, x: CGFloat, y: CGFloat) {
    color = Color(
      .sRGB, red: Double((rgba >> 24) & 0xFF) / 255,
      green: Double((rgba >> 16) & 0xFF) / 255, blue: Double((rgba >> 8) & 0xFF) / 255,
      opacity: Double(rgba & 0xFF) / 255 * opacity)
    self.radius = radius
    self.x = x
    self.y = y
  }
}

/// Generated appearance-aware elevation; the canonical ladder has at most two shadows.
public struct DesignElevation: Sendable {
  let light: [DesignShadow]
  let dark: [DesignShadow]
  let hairline: Bool
}

/// A closed custom functional-surface recipe, generated from the material inventory and the
/// existing radius/elevation tokens. Content cards cannot opt in through a material flag.
public struct DesignMaterial: Sendable {
  /// Canonical recipe name.
  public let name: String
  let radius: CGFloat
  let elevation: DesignElevation

  /// Solid and Reduce Transparency are the same opaque path, not two material conventions.
  public func usesGlass(appearance: ChromeAppearance, reduceTransparency: Bool) -> Bool {
    appearance == .frosted && !reduceTransparency
  }
}

extension View {
  /// Applies a closed custom-chrome recipe. Nearby glass surfaces must share a
  /// `GlassEffectContainer`; system-owned chrome does not use this modifier.
  public func designChrome(_ material: DesignMaterial) -> some View {
    modifier(DesignChromeModifier(material: material))
  }

  /// Applies opaque elevation only. Never layer this shadow on a glass surface.
  public func designElevation(_ elevation: DesignElevation) -> some View {
    modifier(DesignElevationModifier(elevation: elevation))
  }
}

private struct DesignChromeModifier: ViewModifier {
  let material: DesignMaterial
  @Environment(\.chromeAppearance) private var appearance
  @Environment(\.effectiveReduceTransparency) private var reduceTransparency
  @Environment(\.effectiveIncreasedContrast) private var increasedContrast

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: material.radius, style: .continuous)
    let glass = material.usesGlass(appearance: appearance, reduceTransparency: reduceTransparency)
    content.background {
      if !glass {
        shape.fill(DS.Colors.Surface.raised).designElevation(material.elevation)
      }
    }
    .glassEffect(glass ? .regular : .identity, in: shape)
    .overlay {
      if increasedContrast || (!glass && material.elevation.hairline) {
        shape.strokeBorder(
          increasedContrast ? DS.Colors.Border.strong : DS.Colors.Border.hairline)
      }
    }
  }
}

private struct DesignElevationModifier: ViewModifier {
  let elevation: DesignElevation
  @Environment(\.colorScheme) private var scheme

  func body(content: Content) -> some View {
    let shadows = scheme == .dark ? elevation.dark : elevation.light
    content
      .modifier(DesignShadowModifier(shadow: shadows.first))
      .modifier(DesignShadowModifier(shadow: shadows.dropFirst().first))
  }
}

private struct DesignShadowModifier: ViewModifier {
  let shadow: DesignShadow?

  func body(content: Content) -> some View {
    if let shadow {
      content.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    } else {
      content
    }
  }
}
