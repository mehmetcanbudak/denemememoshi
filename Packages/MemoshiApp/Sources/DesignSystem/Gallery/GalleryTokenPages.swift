import SwiftUI

/// Every generated color role, with explicit light, dark and increased-contrast variants.
struct GalleryColorPage: View {
  let comparison: GalleryComparison

  var body: some View {
    GalleryPage(section: .colors, comparison: comparison) {
      EmptyView()
    } specimen: {
      GalleryColorFamilies()
    }
  }
}

/// A token family such as `surface`, in catalog order.
private struct GalleryColorFamily: Identifiable {
  let id: String
  let roles: [DesignColorRole]

  static let all: [GalleryColorFamily] = DS.Colors.catalog.reduce(into: []) { families, role in
    let family = String(role.name.prefix { $0 != "." })
    if families.last?.id == family {
      families[families.count - 1] = GalleryColorFamily(
        id: family, roles: families[families.count - 1].roles + [role])
    } else {
      families.append(GalleryColorFamily(id: family, roles: [role]))
    }
  }
}

private struct GalleryColorFamilies: View {
  @Environment(\.previewPalette) private var palette

  var body: some View {
    ForEach(GalleryColorFamily.all) { family in
      GalleryGroup(
        title: Text(verbatim: family.id),
        note: Text(
          "Large: this setting. Small: light, dark, increased light, increased dark.",
          bundle: #bundle)
      ) {
        ForEach(family.roles) { role in
          GalleryColorRow(
            role: role, followsSystem: palette == .current && role.color.followsSystemColor)
        }
      }
    }
  }
}

/// The four token appearances, applied explicitly to one small swatch each.
private enum GalleryAppearance: CaseIterable, Identifiable {
  case light, dark, increasedLight, increasedDark

  var id: Self { self }
  var scheme: ColorScheme { self == .light || self == .increasedLight ? .light : .dark }
  var increasedContrast: Bool { self == .increasedLight || self == .increasedDark }
}

private struct GalleryColorRow: View {
  let role: DesignColorRole
  let followsSystem: Bool
  @Environment(\.self) private var environment

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: DS.Space.s5) {
        name.frame(width: DS.Layout.Gallery.labelWidth, alignment: .leading)
        swatches
        nativeNote
      }
      VStack(alignment: .leading, spacing: DS.Space.s3) {
        name
        swatches
        nativeNote
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var name: some View {
    Text(verbatim: role.name)
      .font(DS.Typography.callout.monospaced())
      .foregroundStyle(DS.Colors.Text.primary)
  }

  private var swatches: some View {
    HStack(spacing: DS.Space.s3) {
      GallerySwatch(role: role, size: DS.Layout.Gallery.swatchSize)
      ForEach(GalleryAppearance.allCases) { appearance in
        GallerySwatch(role: role, size: DS.Layout.Gallery.variantSwatchSize)
          .environment(\.colorScheme, appearance.scheme)
          .transformEnvironment(\.designReviewOverrides) {
            $0.increasedContrast = appearance.increasedContrast
          }
      }
    }
  }

  @ViewBuilder
  private var nativeNote: some View {
    if let adjustment = role.color.nativeAccentAdjustment(in: environment) {
      (adjustment.metMinimum
        ? Text("Derived native accent; opaque contrast floor met", bundle: #bundle)
        : Text("Native accent contrast unresolved", bundle: #bundle))
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
    } else if followsSystem {
      Text("Native system color", bundle: #bundle)
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
    }
  }
}

private struct GallerySwatch: View {
  let role: DesignColorRole
  let size: CGFloat

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: DS.Radius.sm)
    ZStack {
      shape.fill(DS.Colors.Surface.content)
      if role.name.hasPrefix("text.") {
        Text(verbatim: "Aa")
          .font(DS.Typography.headline)
          .foregroundStyle(role.color)
      } else {
        shape.fill(role.color)
      }
    }
    .frame(width: size, height: size)
    .overlay { shape.strokeBorder(DS.Colors.Border.subtle) }
    .accessibilityHidden(true)
  }
}

/// Chrome text styles, fixed prose sizes and monospace sizes.
struct GalleryTypePage: View {
  let comparison: GalleryComparison

  var body: some View {
    GalleryPage(section: .typography, comparison: comparison) {
      EmptyView()
    } specimen: {
      GalleryTypeSpecimens()
    }
  }
}

private struct GalleryFixedType: Identifiable {
  let id: String
  let size: CGFloat
  let lineHeight: CGFloat

  static let prose = [
    GalleryFixedType(
      id: "prose.S", size: DS.Typography.Prose.Sizes.S.size,
      lineHeight: DS.Typography.Prose.Sizes.S.lineHeight),
    GalleryFixedType(
      id: "prose.M", size: DS.Typography.Prose.Sizes.M.size,
      lineHeight: DS.Typography.Prose.Sizes.M.lineHeight),
    GalleryFixedType(
      id: "prose.L", size: DS.Typography.Prose.Sizes.L.size,
      lineHeight: DS.Typography.Prose.Sizes.L.lineHeight),
    GalleryFixedType(
      id: "prose.XL", size: DS.Typography.Prose.Sizes.XL.size,
      lineHeight: DS.Typography.Prose.Sizes.XL.lineHeight),
  ]

  static let mono = [
    GalleryFixedType(
      id: "mono.code", size: DS.Typography.Mono.Code.size,
      lineHeight: DS.Typography.Mono.Code.lineHeight),
    GalleryFixedType(
      id: "mono.terminal", size: DS.Typography.Mono.Terminal.size,
      lineHeight: DS.Typography.Mono.Terminal.lineHeight),
    GalleryFixedType(
      id: "mono.diff", size: DS.Typography.Mono.Diff.size,
      lineHeight: DS.Typography.Mono.Diff.lineHeight),
  ]

  var metrics: String { Self.describe(id, size, lineHeight) }

  static func describe(_ name: String, _ size: CGFloat, _ lineHeight: CGFloat) -> String {
    "\(name) · \(Double(size).formatted()) / \(Double(lineHeight).formatted()) pt"
  }
}

private struct GalleryTypeSpecimens: View {
  var body: some View {
    GalleryGroup(
      title: Text("Chrome text styles", bundle: #bundle),
      note: Text(
        "Native styles follow Dynamic Type; the numbers are nominal macOS sizes.", bundle: #bundle)
    ) {
      ForEach(DS.Typography.catalog) { role in
        VStack(alignment: .leading, spacing: DS.Space.s1) {
          Text("Memoshi keeps each bot's work in view", bundle: #bundle)
            .font(role.font)
            .foregroundStyle(DS.Colors.Text.primary)
          Text(verbatim: GalleryFixedType.describe(role.name, role.size, role.lineHeight))
            .font(DS.Typography.callout.monospaced())
            .foregroundStyle(DS.Colors.Text.secondary)
        }
        .accessibilityElement(children: .combine)
      }
    }
    GalleryGroup(
      title: Text("Message prose", bundle: #bundle),
      note: Text(
        "Generated nominal sizes, scaled for accessibility text; M is the default.",
        bundle: #bundle)
    ) {
      ForEach(GalleryFixedType.prose) { type in
        VStack(alignment: .leading, spacing: DS.Space.s1) {
          GalleryScaledTypeSample(
            type: type, text: "Your forecast for the weekend is ready to read.", design: .default)
          Text(verbatim: type.metrics)
            .font(DS.Typography.callout.monospaced())
            .foregroundStyle(DS.Colors.Text.secondary)
        }
        .accessibilityElement(children: .combine)
      }
    }
    GalleryGroup(
      title: Text("Monospace", bundle: #bundle),
      note: Text("Code, terminal and diffs; always left to right.", bundle: #bundle)
    ) {
      ForEach(GalleryFixedType.mono) { type in
        VStack(alignment: .leading, spacing: DS.Space.s1) {
          GalleryScaledTypeSample(
            type: type, text: "swift test --filter NativeDesignContractTests", design: .monospaced
          )
          .environment(\.layoutDirection, .leftToRight)
          Text(verbatim: type.metrics)
            .font(DS.Typography.callout.monospaced())
            .foregroundStyle(DS.Colors.Text.secondary)
        }
        .accessibilityElement(children: .combine)
      }
    }
  }
}

/// Nominal token metrics retain their relative scale as the native text size grows.
private struct GalleryScaledTypeSample: View {
  let text: String
  let design: Font.Design
  @ScaledMetric private var size: CGFloat
  @ScaledMetric private var lineHeight: CGFloat

  init(type: GalleryFixedType, text: String, design: Font.Design) {
    self.text = text
    self.design = design
    _size = ScaledMetric(wrappedValue: type.size, relativeTo: .body)
    _lineHeight = ScaledMetric(wrappedValue: type.lineHeight, relativeTo: .body)
  }

  var body: some View {
    Text(verbatim: text)
      .font(.system(size: size, design: design))
      .lineSpacing(max(0, lineHeight - size))
      .foregroundStyle(DS.Colors.Text.primary)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// The spacing scale and corner radii at their generated sizes.
struct GallerySpacingPage: View {
  let comparison: GalleryComparison

  var body: some View {
    GalleryPage(section: .spacing, comparison: comparison) {
      EmptyView()
    } specimen: {
      GallerySpacingSpecimens()
    }
  }
}

private struct GallerySpacingSpecimens: View {
  var body: some View {
    GalleryGroup(
      title: Text("Spacing", bundle: #bundle),
      note: Text("A 4-point grid; every gap in Memoshi uses one.", bundle: #bundle)
    ) {
      ForEach(DS.Space.catalog) { metric in
        GalleryMetricRow(metric: metric) {
          Rectangle()
            .fill(DS.Colors.Accent.fill)
            .frame(width: metric.value, height: DS.Layout.Gallery.variantSwatchSize)
        }
      }
    }
    GalleryGroup(
      title: Text("Corner radii", bundle: #bundle),
      note: Text("Continuous corners; pill caps at a capsule.", bundle: #bundle)
    ) {
      ForEach(DS.Radius.catalog) { metric in
        GalleryMetricRow(metric: metric) {
          RoundedRectangle(cornerRadius: min(metric.value, DS.Layout.Gallery.swatchSize / 2))
            .fill(DS.Colors.Surface.card)
            .overlay {
              RoundedRectangle(cornerRadius: min(metric.value, DS.Layout.Gallery.swatchSize / 2))
                .strokeBorder(DS.Colors.Border.strong)
            }
            .frame(width: DS.Layout.Gallery.swatchSize * 2, height: DS.Layout.Gallery.swatchSize)
        }
      }
    }
  }
}

private struct GalleryMetricRow<Sample: View>: View {
  let metric: DesignMetric
  @ViewBuilder let sample: () -> Sample

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: DS.Space.s5) {
        name.frame(width: DS.Layout.Gallery.labelWidth, alignment: .leading)
        specimen
      }
      VStack(alignment: .leading, spacing: DS.Space.s3) {
        name
        specimen
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var name: some View {
    Text(verbatim: metric.name)
      .font(DS.Typography.callout.monospaced())
      .foregroundStyle(DS.Colors.Text.primary)
  }

  private var specimen: some View {
    HStack(spacing: DS.Space.s5) {
      sample().accessibilityHidden(true)
      Text(verbatim: "\(Double(metric.value).formatted()) pt")
        .font(DS.Typography.callout.monospacedDigit())
        .foregroundStyle(DS.Colors.Text.secondary)
    }
  }
}

/// Opaque content surfaces and chrome over busy content, with their fallbacks.
struct GalleryMaterialPage: View {
  let comparison: GalleryComparison
  @State private var composerDraft = "Try editing this local gallery sample."
  @State private var lastComposerSample: String?

  var body: some View {
    GalleryPage(section: .materials, comparison: comparison) {
      EmptyView()
    } specimen: {
      GalleryMaterialSpecimens(
        composerDraft: $composerDraft, lastComposerSample: $lastComposerSample)
    }
  }
}

private struct GalleryMaterialSpecimens: View {
  @Binding var composerDraft: String
  @Binding var lastComposerSample: String?
  private static let surfaces = DS.Colors.catalog.filter { $0.name.hasPrefix("surface.") }

  var body: some View {
    GalleryGroup(
      title: Text("Content surfaces", bundle: #bundle),
      note: Text(
        "Opaque fills for transcripts, cards and resources; never glass.", bundle: #bundle)
    ) {
      ForEach(Self.surfaces) { role in
        GallerySurfaceSample(role: role)
      }
    }
    GalleryGroup(
      title: Text("Chrome over content", bundle: #bundle),
      note: Text(
        """
        Every custom recipe over busy example content. Frosted uses glass; Solid or Reduce \
        Transparency uses surface.raised and the recipe's elevation. These are labelled \
        gallery specimens, not connected product flows.
        """,
        bundle: #bundle
      )
    ) {
      GlassEffectContainer(spacing: DS.Space.s5) {
        VStack(alignment: .leading, spacing: DS.Space.s7) {
          GalleryChromeSpecimen(
            material: DS.Materials.identity,
            note: LocalizedStringResource(
              "The existing floating identity, with sample-only connection details.",
              bundle: #bundle)
          ) {
            FloatingBotIdentity(
              name: "Scout", symbol: "magnifyingglass",
              detail: "Gallery identity specimen · not connected", badge: "Sample")
          }
          GalleryChromeSpecimen(
            material: DS.Materials.composer,
            note: LocalizedStringResource(
              """
              Edit the text, then choose Send sample to record it below in this gallery only. \
              No model or runtime message is sent.
              """,
              bundle: #bundle)
          ) {
            GalleryComposerSample(draft: $composerDraft, lastSample: $lastComposerSample)
          }
          GalleryChromeSpecimen(
            material: DS.Materials.toast,
            note: LocalizedStringResource(
              "A static toast specimen; it does not appear or dismiss automatically.",
              bundle: #bundle)
          ) {
            Label {
              Text("Local example ready", bundle: #bundle)
            } icon: {
              Image(systemName: "checkmark.circle")
            }
            .font(DS.Typography.body)
            .foregroundStyle(DS.Colors.Text.primary)
            .padding(.horizontal, DS.Space.s6)
            .padding(.vertical, DS.Space.s5)
            .designChrome(DS.Materials.toast)
          }
          GalleryChromeSpecimen(
            material: DS.Materials.commandPalette,
            note: LocalizedStringResource(
              "A static command-palette specimen; there is no search or command execution.",
              bundle: #bundle)
          ) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
              Label {
                Text("Sample command palette", bundle: #bundle)
              } icon: {
                Image(systemName: "command")
              }
              .font(DS.Typography.headline)
              Divider()
              Label {
                Text("Example: Find in sample content", bundle: #bundle)
              } icon: {
                Image(systemName: "magnifyingglass")
              }
              .font(DS.Typography.body)
            }
            .foregroundStyle(DS.Colors.Text.primary)
            .padding(DS.Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .designChrome(DS.Materials.commandPalette)
            .accessibilityElement(children: .combine)
          }
          GalleryChromeSpecimen(
            material: DS.Materials.scrollToLatest,
            note: LocalizedStringResource(
              "A static scroll-control specimen; it does not move the gallery.", bundle: #bundle)
          ) {
            Label {
              Text("Scroll to latest sample", bundle: #bundle)
            } icon: {
              Image(systemName: "arrow.down")
            }
            .font(DS.Typography.body)
            .foregroundStyle(DS.Colors.Text.primary)
            .padding(.horizontal, DS.Space.s6)
            .padding(.vertical, DS.Space.s5)
            .designChrome(DS.Materials.scrollToLatest)
          }
        }
      }
    }
    GalleryGroup(
      title: Text("Opaque elevation ladder", bundle: #bundle),
      note: Text(
        "All generated levels on surface.raised. Glass supplies its own elevation; these shadows are for opaque surfaces only.",
        bundle: #bundle
      )
    ) {
      GalleryElevationSample(
        title: LocalizedStringResource("e0 · Flat content", bundle: #bundle), name: "e0",
        elevation: DS.Elevation.e0)
      GalleryElevationSample(
        title: LocalizedStringResource("e1 · Resting controls and cards", bundle: #bundle),
        name: "e1", elevation: DS.Elevation.e1)
      GalleryElevationSample(
        title: LocalizedStringResource("e2 · Hovered opaque controls", bundle: #bundle),
        name: "e2", elevation: DS.Elevation.e2)
      GalleryElevationSample(
        title: LocalizedStringResource("e3 · Opaque popover fallback", bundle: #bundle),
        name: "e3", elevation: DS.Elevation.e3)
      GalleryElevationSample(
        title: LocalizedStringResource("e4 · Toast and scroll-control fallback", bundle: #bundle),
        name: "e4", elevation: DS.Elevation.e4)
      GalleryElevationSample(
        title: LocalizedStringResource(
          "e5 · Dialog and command-palette fallback", bundle: #bundle),
        name: "e5", elevation: DS.Elevation.e5)
      GalleryElevationSample(
        title: LocalizedStringResource("e6 · Modal fallback", bundle: #bundle), name: "e6",
        elevation: DS.Elevation.e6)
    }
  }
}

private struct GallerySurfaceSample: View {
  let role: DesignColorRole

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: DS.Space.s5) {
        name.frame(width: DS.Layout.Gallery.labelWidth, alignment: .leading)
        swatch
      }
      VStack(alignment: .leading, spacing: DS.Space.s3) {
        name
        swatch
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var name: some View {
    Text(verbatim: role.name)
      .font(DS.Typography.callout.monospaced())
      .foregroundStyle(DS.Colors.Text.primary)
  }

  private var swatch: some View {
    RoundedRectangle(cornerRadius: DS.Radius.card)
      .fill(role.color)
      .overlay {
        RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Colors.Border.subtle)
      }
      .frame(minWidth: DS.Layout.Gallery.swatchSize, maxWidth: .infinity)
      .frame(height: DS.Layout.Gallery.swatchSize)
      .accessibilityHidden(true)
  }
}

/// A labelled review backdrop, not another material layer. Its height grows with the specimen.
private struct GalleryChromeSpecimen<Content: View>: View {
  let material: DesignMaterial
  let note: LocalizedStringResource
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Text(verbatim: material.name)
        .font(DS.Typography.headline.monospaced())
        .foregroundStyle(DS.Colors.Text.primary)
        .accessibilityAddTraits(.isHeader)
      Text(note)
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
        .fixedSize(horizontal: false, vertical: true)
      content()
        .padding(DS.Space.s6)
        .frame(
          maxWidth: .infinity, minHeight: DS.Layout.Gallery.backdropHeight,
          alignment: .topLeading
        )
        .background {
          GalleryBackdrop().clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
        }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("gallery.material.\(material.name)")
  }
}

private struct GalleryElevationSample: View {
  let title: LocalizedStringResource
  let name: String
  let elevation: DesignElevation
  @Environment(\.effectiveIncreasedContrast) private var increasedContrast

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Text(title).font(DS.Typography.headline)
      Text("Opaque surface.raised", bundle: #bundle).font(DS.Typography.callout)
    }
    .foregroundStyle(DS.Colors.Text.primary)
    .padding(DS.Space.s6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DS.Colors.Surface.raised, in: shape)
    .overlay {
      if increasedContrast || elevation.hairline {
        shape.strokeBorder(
          increasedContrast ? DS.Colors.Border.strong : DS.Colors.Border.hairline)
      }
    }
    .designElevation(elevation)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("gallery.elevation.\(name)")
    .padding(DS.Space.s8)
  }
}

/// Busy example content: palette stripes under sample text, so material is easy to judge.
private struct GalleryBackdrop: View {
  var body: some View {
    ZStack(alignment: .bottomLeading) {
      HStack(spacing: DS.Space.s0) {
        ForEach(AvatarColor.allCases, id: \.self) { color in
          Rectangle().fill(color.fill)
        }
      }
      Text("Examples only · Your forecast for the weekend is ready to read", bundle: #bundle)
        .font(DS.Typography.title2)
        .foregroundStyle(DS.Colors.Text.primary)
        .padding(DS.Space.s6)
    }
    .accessibilityHidden(true)
  }
}

/// Editable and actionable only within this specimen; no transport or runtime is composed here.
private struct GalleryComposerSample: View {
  @Environment(\.chromeAppearance) private var appearance
  @Environment(\.effectiveReduceTransparency) private var reduceTransparency
  @Binding var draft: String
  @Binding var lastSample: String?
  @FocusState private var fieldFocused: Bool

  private var usesGlass: Bool {
    DS.Materials.composer.usesGlass(
      appearance: appearance, reduceTransparency: reduceTransparency)
  }

  private var canSendSample: Bool { draft.contains { !$0.isWhitespace } }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s5) {
      VStack(alignment: .leading, spacing: DS.Space.s4) {
        TextField(
          text: $draft, prompt: Text("Local sample message", bundle: #bundle), axis: .vertical
        ) {
          Text("Local sample message", bundle: #bundle)
        }
        .textFieldStyle(.plain)
        .font(DS.Typography.body)
        .foregroundStyle(DS.Colors.Text.primary)
        .lineLimit(1...6)
        .frame(minHeight: DS.Layout.Composer.controlSize, alignment: .topLeading)
        .focused($fieldFocused)
        .submitLabel(.send)
        .onSubmit(sendSample)
        .accessibilityHint(
          Text(
            "Sample only. Send sample records this text below, without contacting a model or runtime.",
            bundle: #bundle)
        )
        .accessibilityIdentifier("gallery.material.composer.field")
        ViewThatFits(in: .horizontal) {
          HStack(spacing: DS.Space.s4) {
            appearanceLabel
            sendButton
          }
          VStack(alignment: .leading, spacing: DS.Space.s4) {
            appearanceLabel
            sendButton
          }
        }
      }
      .padding(DS.Layout.Composer.padding)
      .designChrome(DS.Materials.composer)
      if let lastSample {
        DesignCard(LocalizedStringResource("Last local sample · not sent", bundle: #bundle)) {
          Text(verbatim: lastSample)
            .textSelection(.enabled)
        }
        .accessibilityIdentifier("gallery.material.composer.lastSample")
      }
    }
  }

  private var appearanceLabel: some View {
    (usesGlass
      ? Text("Frosted · local sample only", bundle: #bundle)
      : Text("Opaque fallback · local sample only", bundle: #bundle))
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.primary)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private var sendButton: some View {
    if usesGlass {
      sendAction.buttonStyle(.glassProminent)
    } else {
      sendAction.buttonStyle(.borderedProminent)
    }
  }

  private var sendAction: some View {
    Button(action: sendSample) {
      Label {
        Text("Send sample", bundle: #bundle)
      } icon: {
        Image(systemName: "arrow.up")
      }
      .font(DS.Typography.body)
      .frame(minHeight: DS.Layout.Composer.minHeight)
    }
    .disabled(!canSendSample)
    .accessibilityHint(
      Text("Records the text in this gallery only. No message is sent.", bundle: #bundle)
    )
    .accessibilityIdentifier("gallery.material.composer.send")
  }

  private func sendSample() {
    guard canSendSample else { return }
    lastSample = draft
    draft = ""
    fieldFocused = true
  }
}
