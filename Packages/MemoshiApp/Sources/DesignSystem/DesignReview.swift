import SwiftUI

/// Side-by-side review overrides used only inside the component gallery. `nil` follows the
/// system setting, so product surfaces never see an override.
struct DesignReviewOverrides: Equatable, Sendable {
  var increasedContrast: Bool?
  var reduceTransparency: Bool?
  var reduceMotion: Bool?
}

extension EnvironmentValues {
  @Entry var designReviewOverrides: DesignReviewOverrides = DesignReviewOverrides()

  /// Increase Contrast as Memoshi components apply it. Product surfaces follow the system; the
  /// component gallery can compare both forms side by side.
  public var effectiveIncreasedContrast: Bool {
    designReviewOverrides.increasedContrast ?? (colorSchemeContrast == .increased)
  }

  /// Reduce Transparency as Memoshi chrome applies it, with the gallery's review override.
  public var effectiveReduceTransparency: Bool {
    designReviewOverrides.reduceTransparency ?? accessibilityReduceTransparency
  }

  /// Reduce Motion as Memoshi motion applies it, with the gallery's review override. Ambient
  /// avatar loops additionally stop for Low Power Mode and while not visible.
  public var effectiveReduceMotion: Bool {
    if let override = designReviewOverrides.reduceMotion { return override }
    switch motionPreference {
    case .system: return accessibilityReduceMotion
    case .on: return true
    case .off: return false
    }
  }
}
