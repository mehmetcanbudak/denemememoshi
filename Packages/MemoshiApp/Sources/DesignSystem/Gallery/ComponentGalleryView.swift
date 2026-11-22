import SwiftUI

/// The Phase 0 component and avatar gallery: generated tokens, materials, the complete bot
/// status vocabulary and the parametric avatar prototype, reviewable side by side in both
/// palettes, light and dark, standard and increased contrast, with and without transparency,
/// and with and without motion. Every bot shown is an original example, not a connected bot.
public struct ComponentGalleryView: View {
  @State private var selection: GallerySection? = .statuses
  @State private var comparison = GalleryComparison.single

  /// Creates the gallery; it applies the persisted palette itself.
  public init() {}

  /// A native sidebar of pages, the selected page, and the comparison and palette controls.
  public var body: some View {
    NavigationSplitView {
      GallerySidebar(selection: $selection)
    } detail: {
      GalleryDetail(section: selection ?? .statuses, comparison: comparison)
    }
    .toolbar {
      ToolbarItem {
        Picker(selection: $comparison) {
          ForEach(GalleryComparison.allCases) { option in
            Text(option.title).tag(option)
          }
        } label: {
          Text("Compare", bundle: #bundle)
        }
        .pickerStyle(.menu)
        .help(
          Text(
            "Show every specimen twice, side by side, under two review settings",
            bundle: #bundle)
        )
        .accessibilityIdentifier("gallery.comparison")
      }
      ToolbarItem {
        PalettePicker()
          .pickerStyle(.menu)
          .help(Text("Switch this app's Current or Warm palette", bundle: #bundle))
      }
      ToolbarItem { GalleryPreferencesMenu() }
    }
    .modifier(GalleryWindowMinimum())
    .previewAppearance()
  }
}

private struct GallerySidebar: View {
  @Binding var selection: GallerySection?

  var body: some View {
    List(selection: $selection) {
      ForEach(GallerySection.Category.allCases) { category in
        Section {
          ForEach(category.sections) { section in
            NavigationLink(value: section) {
              Label {
                Text(section.title)
              } icon: {
                Image(systemName: section.symbol)
              }
            }
          }
        } header: {
          Text(category.title)
        }
      }
    }
    .navigationSplitViewColumnWidth(
      min: DS.Layout.Sidebar.min, ideal: DS.Layout.Sidebar.default, max: DS.Layout.Sidebar.max
    )
    .navigationTitle(Text("Component Gallery", bundle: #bundle))
    .accessibilityIdentifier("gallery.sidebar")
  }
}

private struct GalleryDetail: View {
  let section: GallerySection
  let comparison: GalleryComparison

  var body: some View {
    switch section {
    case .colors: GalleryColorPage(comparison: comparison)
    case .typography: GalleryTypePage(comparison: comparison)
    case .spacing: GallerySpacingPage(comparison: comparison)
    case .glyphs: GalleryGlyphPage(comparison: comparison)
    case .materials: GalleryMaterialPage(comparison: comparison)
    case .statuses: GalleryStatusPage(comparison: comparison)
    case .grid: GalleryGridPage(comparison: comparison)
    case .playground: GalleryPlaygroundPage(comparison: comparison)
    case .shapes: GalleryShapesPage(comparison: comparison)
    case .components: GalleryComponentsPage(comparison: comparison)
    case .motion: GalleryPrimitivePage(comparison: comparison)
    }
  }
}

/// Keeps two comparison columns beside the sidebar on the Mac; iPhone and iPad adapt instead.
private struct GalleryWindowMinimum: ViewModifier {
  func body(content: Content) -> some View {
    #if os(macOS)
      content.frame(minWidth: DS.Layout.Gallery.minWidth, minHeight: DS.Layout.Gallery.minHeight)
    #else
      content
    #endif
  }
}
