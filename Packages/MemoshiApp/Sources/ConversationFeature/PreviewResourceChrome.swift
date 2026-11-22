import AppCore
import DesignSystem
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct PreviewResourceHeader: View {
  let resource: PreviewResource
  let showDetails: (() -> Void)?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s4))
      : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Space.s4))
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      layout {
        Label {
          resource == .forecast
            ? Text("WEATHER", bundle: #bundle) : Text("READING NOTE", bundle: #bundle)
        } icon: {
          Image(systemName: resource.systemImage)
        }
        .font(DS.Typography.subheadline.weight(.bold))
        .foregroundStyle(DS.Colors.Accent.text)
        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: DS.Space.s3) }
        PreviewResourceActions(resource: resource, showDetails: showDetails)
      }
      Text(verbatim: resource.title)
        .font(.system(.title3, design: .serif, weight: .semibold))
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct PreviewResourceActions: View {
  let resource: PreviewResource
  let showDetails: (() -> Void)?
  @State private var copied = false
  @Environment(\.designAnnouncer) private var announcer

  var body: some View {
    HStack(spacing: DS.Space.s2) {
      ShareLink(item: resource.shareText, subject: Text(resource.title)) {
        ResourceActionGlyph(symbol: "square.and.arrow.up")
      }
      .accessibilityLabel(Text("Share example \(resource.title)", bundle: #bundle))
      .help(Text("Share original sample content", bundle: #bundle))
      Button {
        #if os(macOS)
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(resource.shareText, forType: .string)
        #else
          UIPasteboard.general.string = resource.shareText
        #endif
        copied = true
        announcer.announce(String(localized: "Sample copied", bundle: #bundle))
      } label: {
        ResourceActionGlyph(symbol: copied ? "checkmark" : "doc.on.doc")
      }
      // The name stays the action; the outcome is announced and the checkmark is brief.
      .accessibilityLabel(Text("Copy example \(resource.title)", bundle: #bundle))
      .help(Text("Copy original sample content", bundle: #bundle))
      .task(id: copied) {
        guard copied else { return }
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        copied = false
      }
      .accessibilityIdentifier("preview.resource.copy.\(resource.rawValue)")
      if let showDetails {
        Button(action: showDetails) {
          ResourceActionGlyph(symbol: "arrow.up.left.and.arrow.down.right")
        }
        .accessibilityLabel(Text("Inspect example \(resource.title)", bundle: #bundle))
        .help(Text("Open resource details", bundle: #bundle))
        .accessibilityIdentifier("preview.resource.open.\(resource.rawValue)")
      }
    }
    .buttonStyle(.borderless)
    .foregroundStyle(DS.Colors.Accent.text)
    .id(resource)
  }
}

private struct ResourceActionGlyph: View {
  let symbol: String

  var body: some View {
    Image(systemName: symbol)
      .font(.callout)
      #if os(macOS)
        .frame(minWidth: DS.Layout.Composer.controlSize, minHeight: DS.Layout.Composer.controlSize)
      #else
        .frame(minWidth: DS.Layout.Composer.minHeight, minHeight: DS.Layout.Composer.minHeight)
      #endif
      .background(DS.Colors.Surface.well, in: Circle())
  }
}

struct PreviewResourceFooter: View {
  let resource: PreviewResource

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Divider()
      Label(resource.subtitle, systemImage: "paintpalette")
        .font(DS.Typography.subheadline)
        .foregroundStyle(DS.Colors.Text.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if let url = resource.sourceURL {
        Link(destination: url) {
          Label {
            resource == .forecast
              ? Text("Apple Weather website", bundle: #bundle)
              : Text("Apple design guidelines", bundle: #bundle)
          } icon: {
            Image(systemName: "arrow.up.right.square")
          }
          #if os(iOS)
            // The whole 44 pt row is the hit region, not only the one line of text.
            .frame(minHeight: DS.Layout.Composer.minHeight)
            .contentShape(Rectangle())
          #endif
        }
        .font(DS.Typography.callout.weight(.medium))
        .accessibilityHint(
          Text(
            "Opens an official website. This example did not fetch information from it.",
            bundle: #bundle))
      }
    }
  }
}

struct PreviewResourceSurface: ViewModifier {
  @Environment(\.self) private var environment

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: DS.Radius.card)
    content
      .foregroundStyle(DS.Colors.Text.primary)
      .padding(DS.Layout.Card.padding)
      .frame(maxWidth: DS.Layout.Card.maxWidth, alignment: .leading)
      // Shadow belongs on the opaque card shape only (matching DesignMaterial), never on the
      // outer container where SwiftUI propagates it to every child text glyph and overlay stroke.
      .background {
        shape
          .fill(DS.Colors.Surface.resource)
          .shadow(
            color: DS.Colors.Border.subtle.resolve(in: environment),
            radius: DS.Space.s2, x: DS.Space.s0, y: DS.Space.s1
          )
      }
      .overlay {
        shape.strokeBorder(DS.Colors.Border.field)
      }
  }
}
