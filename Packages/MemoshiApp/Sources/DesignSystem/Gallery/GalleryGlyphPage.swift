import SwiftUI

/// Native symbols are rendered; artwork and deferred marks stay honestly labelled references.
struct GalleryGlyphPage: View {
  let comparison: GalleryComparison

  var body: some View {
    GalleryPage(section: .glyphs, comparison: comparison) {
      EmptyView()
    } specimen: {
      GalleryGroup(
        title: Text("Canonical glyph inventory", bundle: #bundle),
        note: Text(
          "Native symbols follow adjacent text weight. Custom, composed and later-stage marks are references, not substituted artwork.",
          bundle: #bundle
        )
      ) {
        ForEach(DS.Icons.catalog) { glyph in
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
              name(glyph)
                .frame(width: DS.Layout.Gallery.labelWidth, alignment: .leading)
              mark(glyph.source)
            }
            VStack(alignment: .leading, spacing: DS.Space.s2) {
              name(glyph)
              mark(glyph.source)
            }
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  private func name(_ glyph: DesignGlyph) -> some View {
    Text(verbatim: glyph.name)
      .font(DS.Typography.callout.monospaced())
      .foregroundStyle(DS.Colors.Text.primary)
  }

  @ViewBuilder
  private func mark(_ source: DesignGlyph.Source) -> some View {
    switch source {
    case .system(let name):
      HStack(spacing: DS.Space.s3) {
        Image(systemName: name)
          .font(DS.Typography.body)
          .frame(width: DS.Icons.Sizes.row)
          .accessibilityHidden(true)
        Text(verbatim: name)
          .font(DS.Typography.callout.monospaced())
      }
      .foregroundStyle(DS.Colors.Text.primary)
    case .reference(let description):
      VStack(alignment: .leading, spacing: DS.Space.s1) {
        Text("Renderer / artwork reference", bundle: #bundle)
          .font(DS.Typography.callout)
        Text(verbatim: description)
          .font(DS.Typography.callout.monospaced())
      }
      .foregroundStyle(DS.Colors.Text.secondary)
    }
  }
}
