import SwiftUI

/// The gallery's pages, grouped as the sidebar shows them.
enum GallerySection: CaseIterable, Identifiable, Hashable {
  case colors, typography, spacing, glyphs, materials
  case statuses, grid, playground, shapes
  case components, motion

  /// Sidebar groups.
  enum Category: CaseIterable, Identifiable {
    case tokens, avatars, components

    var id: Self { self }

    var title: LocalizedStringResource {
      switch self {
      case .tokens: LocalizedStringResource("Tokens", bundle: #bundle)
      case .avatars: LocalizedStringResource("Bot avatars", bundle: #bundle)
      case .components: LocalizedStringResource("Components", bundle: #bundle)
      }
    }

    var sections: [GallerySection] {
      GallerySection.allCases.filter { $0.category == self }
    }
  }

  var id: Self { self }

  var category: Category {
    switch self {
    case .colors, .typography, .spacing, .glyphs, .materials: .tokens
    case .statuses, .grid, .playground, .shapes: .avatars
    case .components, .motion: .components
    }
  }

  var title: LocalizedStringResource {
    switch self {
    case .colors: LocalizedStringResource("Color roles", bundle: #bundle)
    case .typography: LocalizedStringResource("Type", bundle: #bundle)
    case .spacing: LocalizedStringResource("Spacing and radii", bundle: #bundle)
    case .glyphs: LocalizedStringResource("Glyphs", bundle: #bundle)
    case .materials: LocalizedStringResource("Materials", bundle: #bundle)
    case .statuses: LocalizedStringResource("Statuses and overlays", bundle: #bundle)
    case .grid: LocalizedStringResource("Avatar grid", bundle: #bundle)
    case .playground: LocalizedStringResource("Avatar playground", bundle: #bundle)
    case .shapes: LocalizedStringResource("Shapes, colors and sizes", bundle: #bundle)
    case .components: LocalizedStringResource("Identity components", bundle: #bundle)
    case .motion: LocalizedStringResource("Native primitives and motion", bundle: #bundle)
    }
  }

  var symbol: String {
    switch self {
    case .colors: "paintpalette"
    case .typography: "textformat"
    case .spacing: "ruler"
    case .glyphs: "square.grid.2x2"
    case .materials: "square.on.square"
    case .statuses: "person.crop.circle.badge.exclamationmark"
    case .grid: "square.grid.3x3"
    case .playground: "slider.horizontal.3"
    case .shapes: "circle.hexagongrid"
    case .components: "rectangle.stack"
    case .motion: "waveform.path"
    }
  }

  var summary: LocalizedStringResource {
    switch self {
    case .colors:
      LocalizedStringResource(
        "Generated roles with light, dark and increased-contrast values in the chosen palette.",
        bundle: #bundle)
    case .typography:
      LocalizedStringResource(
        "Chrome uses native styles; generated prose and code metrics scale with accessibility text.",
        bundle: #bundle)
    case .spacing:
      LocalizedStringResource(
        "The 4-point spacing scale and corner radii at their generated sizes.", bundle: #bundle)
    case .glyphs:
      LocalizedStringResource(
        "Generated native symbol mappings, with explicit custom and deferred-renderer references.",
        bundle: #bundle)
    case .materials:
      LocalizedStringResource(
        "Content stays opaque; chrome material falls back to a raised surface without transparency.",
        bundle: #bundle)
    case .statuses:
      LocalizedStringResource(
        "Eight statuses and three overlays, each a glyph plus text, never color or motion alone.",
        bundle: #bundle)
    case .grid:
      LocalizedStringResource(
        "Twelve original shapes in twelve colors, as an avatar grid shows them.", bundle: #bundle)
    case .playground:
      LocalizedStringResource(
        "Change one example bot's status and overlays to review entry motion and still forms.",
        bundle: #bundle)
    case .shapes:
      LocalizedStringResource(
        "Parametric silhouettes, the palette with its muted fills, and every avatar size.",
        bundle: #bundle)
    case .components:
      LocalizedStringResource(
        "Existing design-preview components under the same review settings.", bundle: #bundle)
    case .motion:
      LocalizedStringResource(
        "Native state, causality and progress primitives; later Aiden reveal and entrances stay deferred.",
        bundle: #bundle)
    }
  }
}

/// A two-setting comparison applied to every specimen on a page.
enum GalleryComparison: CaseIterable, Identifiable {
  case single, palettes, appearance, contrast, transparency, motion, direction, textSize

  var id: Self { self }

  var title: LocalizedStringResource {
    switch self {
    case .single: LocalizedStringResource("No comparison", bundle: #bundle)
    case .palettes: LocalizedStringResource("Current and Warm", bundle: #bundle)
    case .appearance: LocalizedStringResource("Light and dark", bundle: #bundle)
    case .contrast: LocalizedStringResource("Standard and increased contrast", bundle: #bundle)
    case .transparency:
      LocalizedStringResource("Material and Reduce Transparency", bundle: #bundle)
    case .motion: LocalizedStringResource("Motion and Reduce Motion", bundle: #bundle)
    case .direction: LocalizedStringResource("Left to right and right to left", bundle: #bundle)
    case .textSize: LocalizedStringResource("Default and accessibility text", bundle: #bundle)
    }
  }

  var variants: (GalleryVariant, GalleryVariant)? {
    switch self {
    case .single: nil
    case .palettes: (.palette(.current), .palette(.warm))
    case .appearance: (.scheme(.light), .scheme(.dark))
    case .contrast: (.contrast(increased: false), .contrast(increased: true))
    case .transparency: (.transparency(reduced: false), .transparency(reduced: true))
    case .motion: (.motion(reduced: false), .motion(reduced: true))
    case .direction: (.direction(.leftToRight), .direction(.rightToLeft))
    case .textSize: (.textSize(.large), .textSize(.accessibility3))
    }
  }
}

/// One column's setting. Motion's first column follows the app preference and never forces it on.
enum GalleryVariant: Hashable {
  case palette(PreviewPalette)
  case scheme(ColorScheme)
  case contrast(increased: Bool)
  case transparency(reduced: Bool)
  case motion(reduced: Bool)
  case direction(LayoutDirection)
  case textSize(DynamicTypeSize)

  var title: LocalizedStringResource {
    switch self {
    case .palette(let palette):
      palette == .current
        ? LocalizedStringResource("Current palette", bundle: #bundle)
        : LocalizedStringResource("Warm palette", bundle: #bundle)
    case .scheme(let scheme):
      scheme == .dark
        ? LocalizedStringResource("Dark", bundle: #bundle)
        : LocalizedStringResource("Light", bundle: #bundle)
    case .contrast(let increased):
      increased
        ? LocalizedStringResource("Increased contrast", bundle: #bundle)
        : LocalizedStringResource("Standard contrast", bundle: #bundle)
    case .transparency(let reduced):
      reduced
        ? LocalizedStringResource("Reduce Transparency", bundle: #bundle)
        : LocalizedStringResource("Material", bundle: #bundle)
    case .motion(let reduced):
      reduced
        ? LocalizedStringResource("Reduce Motion", bundle: #bundle)
        : LocalizedStringResource("Motion (app preference)", bundle: #bundle)
    case .direction(let direction):
      direction == .rightToLeft
        ? LocalizedStringResource("Right to left", bundle: #bundle)
        : LocalizedStringResource("Left to right", bundle: #bundle)
    case .textSize(let size):
      size.isAccessibilitySize
        ? LocalizedStringResource("Accessibility text", bundle: #bundle)
        : LocalizedStringResource("Default text", bundle: #bundle)
    }
  }
}

/// Applies one comparison column's setting to everything inside it, including its surface.
private struct GalleryVariantModifier: ViewModifier {
  let variant: GalleryVariant

  @ViewBuilder
  func body(content: Content) -> some View {
    switch variant {
    case .palette(let palette):
      content.environment(\.previewPalette, palette)
    case .scheme(let scheme):
      content.environment(\.colorScheme, scheme)
    case .contrast(let increased):
      content.transformEnvironment(\.designReviewOverrides) { $0.increasedContrast = increased }
    case .transparency(let reduced):
      content.transformEnvironment(\.designReviewOverrides) { $0.reduceTransparency = reduced }
    case .motion(let reduced):
      content.transformEnvironment(\.designReviewOverrides) {
        $0.reduceMotion = reduced ? true : nil
      }
    case .direction(let direction):
      content.environment(\.layoutDirection, direction)
    case .textSize(let size):
      content.environment(\.dynamicTypeSize, size)
    }
  }
}

extension View {
  func galleryVariant(_ variant: GalleryVariant) -> some View {
    modifier(GalleryVariantModifier(variant: variant))
  }

  /// Forces the Reduce Motion still form for one specimen, whatever the system setting.
  func galleryStillForm() -> some View {
    transformEnvironment(\.designReviewOverrides) { $0.reduceMotion = true }
  }
}

/// A page: header, live review state, page controls, then specimens in comparison columns.
struct GalleryPage<Controls: View, Specimen: View>: View {
  let section: GallerySection
  let comparison: GalleryComparison
  @ViewBuilder let controls: () -> Controls
  @ViewBuilder let specimen: () -> Specimen

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DS.Space.s8) {
        Text(section.summary)
          .font(DS.Typography.body)
          .foregroundStyle(DS.Colors.Text.secondary)
          .fixedSize(horizontal: false, vertical: true)
        GalleryReviewState()
        controls()
        GalleryComparisonColumns(comparison: comparison, content: specimen)
      }
      .padding(DS.Space.s8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(DS.Colors.Surface.window)
    .navigationTitle(Text(section.title))
  }
}

/// Renders specimens once, or twice side by side under the comparison's two settings.
struct GalleryComparisonColumns<Content: View>: View {
  let comparison: GalleryComparison
  @ViewBuilder let content: () -> Content
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
  #endif

  var body: some View {
    if let variants = comparison.variants {
      let layout =
        stacksColumns
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s8))
        : AnyLayout(HStackLayout(alignment: .top, spacing: DS.Space.s8))
      layout {
        GalleryColumn(variant: variants.0, content: content)
        GalleryColumn(variant: variants.1, content: content)
      }
    } else {
      VStack(alignment: .leading, spacing: DS.Space.s8) {
        content()
      }
    }
  }

  private var stacksColumns: Bool {
    #if os(iOS)
      sizeClass == .compact || dynamicTypeSize.isAccessibilitySize || comparison == .textSize
    #else
      dynamicTypeSize.isAccessibilitySize || comparison == .textSize
    #endif
  }
}

private struct GalleryColumn<Content: View>: View {
  let variant: GalleryVariant
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s8) {
      Text(variant.title)
        .font(DS.Typography.headline)
        .foregroundStyle(DS.Colors.Text.primary)
        .accessibilityAddTraits(.isHeader)
      content()
    }
    .padding(DS.Space.s6)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(DS.Colors.Surface.content, in: RoundedRectangle(cornerRadius: DS.Radius.card))
    .overlay {
      RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Colors.Border.subtle)
    }
    .galleryVariant(variant)
  }
}

/// A titled group of specimens inside a page or column.
struct GalleryGroup<Content: View>: View {
  let title: Text
  var note: Text?
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s5) {
      title
        .font(DS.Typography.title3)
        .foregroundStyle(DS.Colors.Text.primary)
        .accessibilityAddTraits(.isHeader)
      if let note {
        note
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      content()
    }
  }
}

/// The actual system review settings, read live so captures can record their state honestly.
private struct GalleryReviewState: View {
  @Environment(\.previewPalette) private var palette
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Text(
        """
        Provisional tokens \(DS.version) · Example bots only, not connected · \
        Native material/focus contrast and performance are not certified
        """,
        bundle: #bundle
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      .fixedSize(horizontal: false, vertical: true)
      Grid(alignment: .leading, horizontalSpacing: DS.Space.s6, verticalSpacing: DS.Space.s2) {
        GalleryStateRow(
          name: LocalizedStringResource("Palette", bundle: #bundle),
          value: palette == .current
            ? LocalizedStringResource("Current", bundle: #bundle)
            : LocalizedStringResource("Warm", bundle: #bundle))
        GalleryStateRow(
          name: LocalizedStringResource("Appearance", bundle: #bundle),
          value: scheme == .dark
            ? LocalizedStringResource("Dark", bundle: #bundle)
            : LocalizedStringResource("Light", bundle: #bundle))
        GalleryStateRow(
          name: LocalizedStringResource("Increase Contrast", bundle: #bundle),
          value: Self.onOff(contrast == .increased))
        GalleryStateRow(
          name: LocalizedStringResource("Reduce Transparency", bundle: #bundle),
          value: Self.onOff(reduceTransparency))
        GalleryStateRow(
          name: LocalizedStringResource("Reduce Motion", bundle: #bundle),
          value: Self.onOff(reduceMotion))
      }
      .font(DS.Typography.callout)
      Text(Self.settingsPath)
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(DS.Space.s6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DS.Colors.Surface.well, in: RoundedRectangle(cornerRadius: DS.Radius.card))
    .accessibilityElement(children: .combine)
  }

  private static var settingsPath: LocalizedStringResource {
    #if os(macOS)
      LocalizedStringResource(
        "System settings apply live; change them in System Settings › Accessibility › Display.",
        bundle: #bundle)
    #else
      LocalizedStringResource(
        "System settings apply live; change them in Settings › Accessibility.", bundle: #bundle)
    #endif
  }

  private static func onOff(_ isOn: Bool) -> LocalizedStringResource {
    isOn
      ? LocalizedStringResource("On", bundle: #bundle)
      : LocalizedStringResource("Off", bundle: #bundle)
  }
}

private struct GalleryStateRow: View {
  let name: LocalizedStringResource
  let value: LocalizedStringResource

  var body: some View {
    GridRow {
      Text(name)
        .foregroundStyle(DS.Colors.Text.secondary)
      Text(value)
        .foregroundStyle(DS.Colors.Text.primary)
    }
  }
}
