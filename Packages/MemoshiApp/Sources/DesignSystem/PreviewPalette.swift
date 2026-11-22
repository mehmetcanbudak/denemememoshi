import Combine
import SwiftUI

/// The two review palettes; Current retains the original neutral/system-accent roles.
public enum PreviewPalette: String, CaseIterable, Identifiable, Sendable {
  case current, warm

  /// Stable identity for native palette controls.
  public var id: Self { self }
  /// The concise name shown in the comparison selector.
  public var title: LocalizedStringResource {
    self == .current
      ? LocalizedStringResource("Current", bundle: #bundle)
      : LocalizedStringResource("Warm", bundle: #bundle)
  }

  static let preferenceKey = "design-preview.palette"
}

extension EnvironmentValues {
  /// A small value-only appearance selection, never model or conversation state.
  @Entry public var previewPalette: PreviewPalette = .warm
}

/// A native live selector shared by both platform shells.
public struct PalettePicker: View {
  @AppStorage(PreviewPalette.preferenceKey) private var palette = PreviewPalette.warm

  /// Creates a selector for the device-local palette preference.
  public init() {}

  /// Changes only appearance; selection, pane state and drafts stay intact.
  public var body: some View {
    Picker(selection: $palette) {
      ForEach(PreviewPalette.allCases) { palette in
        Text(palette.title).tag(palette)
      }
    } label: {
      Text("Palette", bundle: #bundle)
    }
    .accessibilityIdentifier("preview.palette")
    .accessibilityHint(
      Text(
        "Compare the original neutral palette with the newer warm ivory and amber palette.",
        bundle: #bundle))
  }
}

extension View {
  /// Applies the persisted palette and matching native-control tint to an entire app surface.
  public func previewAppearance() -> some View {
    modifier(PreviewAppearanceModifier())
  }
}

private struct PreviewAppearanceModifier: ViewModifier {
  @AppStorage(PreviewPalette.preferenceKey) private var palette = PreviewPalette.warm
  @AppStorage(ChromeAppearance.preferenceKey) private var chrome = ChromeAppearance.frosted
  @AppStorage(MotionPreference.preferenceKey) private var motion = MotionPreference.system
  @AppStorage(MotionPreference.avatarPreferenceKey) private var animateAvatars = true
  @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
  #if os(macOS)
    @State private var visible = true
  #else
    @Environment(\.scenePhase) private var scenePhase
  #endif
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    content
      .environment(\.previewPalette, palette)
      .environment(\.chromeAppearance, chrome)
      .environment(\.motionPreference, motion)
      .environment(\.animateBotAvatars, animateAvatars)
      .environment(\.motionLowPower, lowPower)
      #if os(macOS)
        .environment(\.motionIsVisible, visible)
        .background { MotionVisibilityReader(isVisible: $visible) }
      #else
        .environment(\.motionIsVisible, scenePhase != .background)
      #endif
      .onReceive(
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
          .receive(on: RunLoop.main)
      ) { _ in
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
      }
      .tint(controlTint)
  }

  /// Links and inline actions use `accent.text` (03 §4.2); primary actions use
  /// `.designProminent`. Current derives it from the system accent, as its other accent roles do.
  private var controlTint: Color {
    var environment = EnvironmentValues()
    environment.previewPalette = palette
    environment.colorScheme = scheme
    environment.designReviewOverrides.increasedContrast = contrast == .increased
    return DesignControlRoles.tint.resolve(in: environment)
  }
}
