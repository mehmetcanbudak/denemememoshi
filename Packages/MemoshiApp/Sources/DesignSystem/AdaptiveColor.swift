import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// Resolves a generated role using the active appearance and accessibility contrast.
public struct AdaptiveColor: ShapeStyle, Sendable {
  private let light: Color
  private let dark: Color
  private let increasedLight: Color
  private let increasedDark: Color
  private let systemColor: Color?
  private let nativeAccent: NativeAccentPalette.Role?
  private let warm: Variants?
  private let canonical: CanonicalVariants

  init(
    light: UInt32,
    dark: UInt32,
    increasedContrastLight: UInt32,
    increasedContrastDark: UInt32,
    system: String? = nil,
    nativeAccent: NativeAccentPalette.Role? = nil,
    warm: Variants? = nil
  ) {
    self.light = Self.color(light)
    self.dark = Self.color(dark)
    increasedLight = Self.color(increasedContrastLight)
    increasedDark = Self.color(increasedContrastDark)
    systemColor = Self.nativeColor(system)
    self.nativeAccent = nativeAccent
    self.warm = warm
    canonical = CanonicalVariants(
      light: light, dark: dark, increasedLight: increasedContrastLight,
      increasedDark: increasedContrastDark)
  }

  /// Resolves the selected palette, system appearance and accessibility contrast.
  public func resolve(in environment: EnvironmentValues) -> Color {
    if let adjustment = nativeAccentAdjustment(in: environment) {
      return Self.color(adjustment.rgba)
    }
    return resolved(
      palette: environment.previewPalette,
      scheme: environment.colorScheme,
      increasedContrast: environment.effectiveIncreasedContrast
    )
  }

  /// Whether Current resolves a native color, including contrast-derived native accents.
  /// Native system colors apply their own increased-contrast variants.
  var followsSystemColor: Bool { systemColor != nil || nativeAccent != nil }

  func nativeAccentAdjustment(in environment: EnvironmentValues) -> NativeAccentColor.Adjustment? {
    guard environment.previewPalette == .current, let nativeAccent else { return nil }
    return NativeAccentPalette.resolve(in: environment)[nativeAccent]
  }

  func resolved(palette: PreviewPalette, scheme: ColorScheme, increasedContrast: Bool) -> Color {
    if palette == .warm, let warm {
      return warm.resolve(scheme: scheme, increasedContrast: increasedContrast)
    }
    if let systemColor { return systemColor }
    if increasedContrast { return scheme == .dark ? increasedDark : increasedLight }
    return scheme == .dark ? dark : light
  }

  /// The canonical fallback bytes for deterministic contrast/theme checks. A role backed by a
  /// system color still resolves natively at runtime; fallback bytes do not certify that color.
  public func canonicalRGBA(
    palette: PreviewPalette, appearance: DesignTokenAppearance
  ) -> UInt32 {
    if palette == .warm, let warm { return warm.canonical.value(in: appearance) }
    return canonical.value(in: appearance)
  }

  struct CanonicalVariants: Sendable {
    let light: UInt32
    let dark: UInt32
    let increasedLight: UInt32
    let increasedDark: UInt32

    func value(in appearance: DesignTokenAppearance) -> UInt32 {
      switch appearance {
      case .light: light
      case .dark: dark
      case .increasedContrastLight: increasedLight
      case .increasedContrastDark: increasedDark
      }
    }
  }

  struct Variants: Sendable {
    private let light: Color
    private let dark: Color
    private let increasedLight: Color
    private let increasedDark: Color
    let canonical: CanonicalVariants

    init(
      light: UInt32, dark: UInt32,
      increasedContrastLight: UInt32, increasedContrastDark: UInt32
    ) {
      self.light = AdaptiveColor.color(light)
      self.dark = AdaptiveColor.color(dark)
      increasedLight = AdaptiveColor.color(increasedContrastLight)
      increasedDark = AdaptiveColor.color(increasedContrastDark)
      canonical = CanonicalVariants(
        light: light, dark: dark, increasedLight: increasedContrastLight,
        increasedDark: increasedContrastDark)
    }

    func resolve(scheme: ColorScheme, increasedContrast: Bool) -> Color {
      if increasedContrast { return scheme == .dark ? increasedDark : increasedLight }
      return scheme == .dark ? dark : light
    }
  }

  private static func color(_ rgba: UInt32) -> Color {
    Color(
      .sRGB,
      red: Double((rgba >> 24) & 0xFF) / 255,
      green: Double((rgba >> 16) & 0xFF) / 255,
      blue: Double((rgba >> 8) & 0xFF) / 255,
      opacity: Double(rgba & 0xFF) / 255
    )
  }

  private static func nativeColor(_ name: String?) -> Color? {
    #if os(macOS)
      switch name {
      case "windowBackgroundColor": Color(nsColor: .windowBackgroundColor)
      case "textBackgroundColor": Color(nsColor: .textBackgroundColor)
      case "labelColor": Color(nsColor: .labelColor)
      case "controlAccentColor": Color.accentColor
      case "separatorColor": Color(nsColor: .separatorColor)
      case "keyboardFocusIndicatorColor": Color(nsColor: .keyboardFocusIndicatorColor)
      default: nil
      }
    #else
      switch name {
      case "windowBackgroundColor": Color(uiColor: .systemGroupedBackground)
      case "textBackgroundColor": Color(uiColor: .systemBackground)
      case "labelColor": Color(uiColor: .label)
      case "controlAccentColor": Color.accentColor
      case "separatorColor": Color(uiColor: .separator)
      case "keyboardFocusIndicatorColor": Color.accentColor
      default: nil
      }
    #endif
  }
}
