import Foundation

/// The four canonical token appearances. Native material composites still require capture.
public enum DesignTokenAppearance: String, CaseIterable, Sendable {
  case light, dark, increasedContrastLight, increasedContrastDark

  /// Whether the appearance uses the dark palette.
  public var isDark: Bool { self == .dark || self == .increasedContrastDark }
  /// Whether the increased-contrast role is selected.
  public var increasedContrast: Bool {
    self == .increasedContrastLight || self == .increasedContrastDark
  }
}

/// An sRGB token color used for composited WCAG calculations, not a sampled native material.
public struct DesignContrastColor: Equatable, Sendable {
  /// Red channel in 0...1.
  public let red: Double
  /// Green channel in 0...1.
  public let green: Double
  /// Blue channel in 0...1.
  public let blue: Double
  /// Alpha channel in 0...1.
  public let alpha: Double

  /// Decodes canonical RRGGBBAA bytes without quantizing composited channels.
  public init(rgba: UInt32) {
    red = Double((rgba >> 24) & 0xFF) / 255
    green = Double((rgba >> 16) & 0xFF) / 255
    blue = Double((rgba >> 8) & 0xFF) / 255
    alpha = Double(rgba & 0xFF) / 255
  }

  private init(red: Double, green: Double, blue: Double, alpha: Double) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  /// Source-over compositing in sRGB, matching the token convention.
  public func composited(over background: DesignContrastColor) -> DesignContrastColor {
    let opacity = alpha + background.alpha * (1 - alpha)
    guard opacity > 0 else { return self }
    func channel(_ foreground: Double, _ behind: Double) -> Double {
      (foreground * alpha + behind * background.alpha * (1 - alpha)) / opacity
    }
    return DesignContrastColor(
      red: channel(red, background.red), green: channel(green, background.green),
      blue: channel(blue, background.blue), alpha: opacity)
  }

  /// WCAG 2.2 relative luminance. Alpha must be composited before comparing colors.
  public var luminance: Double {
    func linear(_ channel: Double) -> Double {
      channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// A transparent background is unknown, never an invented white-background pass.
  public func contrast(over background: DesignContrastColor) -> Double? {
    guard background.alpha == 1 else { return nil }
    let foreground = composited(over: background).luminance
    let behind = background.luminance
    return (max(foreground, behind) + 0.05) / (min(foreground, behind) + 0.05)
  }
}

/// A generated, intended role pair. Disabled text and decorative separators are not falsely
/// certified; foreground text, badge labels and strong boundaries are explicitly covered.
public struct DesignContrastPair: Identifiable, Sendable {
  /// Source role pair, including the backdrop for a translucent fill.
  public let id: String
  let foreground: AdaptiveColor
  let background: AdaptiveColor
  let backdrop: AdaptiveColor?
  let standardMinimum: Double
  let increasedMinimum: Double

  init(
    id: String, foreground: AdaptiveColor, background: AdaptiveColor,
    backdrop: AdaptiveColor? = nil, standardMinimum: Double, increasedMinimum: Double
  ) {
    self.id = id
    self.foreground = foreground
    self.background = background
    self.backdrop = backdrop
    self.standardMinimum = standardMinimum
    self.increasedMinimum = increasedMinimum
  }

  /// Required ratio from 03 §4/§11; an explicit threshold, not a rounded display value.
  public func minimum(in appearance: DesignTokenAppearance) -> Double {
    appearance.increasedContrast ? increasedMinimum : standardMinimum
  }

  /// Canonical fallback sRGB contrast. System accents, actual NSColors, glass, focus rings and
  /// composited display output require separate native review; this never claims those pass.
  public func ratio(palette: PreviewPalette, appearance: DesignTokenAppearance) -> Double? {
    func color(_ role: AdaptiveColor) -> DesignContrastColor {
      DesignContrastColor(rgba: role.canonicalRGBA(palette: palette, appearance: appearance))
    }
    var behind = color(background)
    if let backdrop { behind = behind.composited(over: color(backdrop)) }
    return color(foreground).contrast(over: behind)
  }
}
