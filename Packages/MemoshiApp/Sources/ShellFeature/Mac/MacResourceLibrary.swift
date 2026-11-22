#if os(macOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  struct MacResourceLibrary: View {
    let workspace: PreviewWorkspace

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
          MacLibraryHeading()
          ForEach(PreviewResource.allCases) { resource in
            MacLibraryResource(resource: resource, workspace: workspace)
          }
        }
        .frame(maxWidth: DS.Layout.Conversation.contentMaxWidth)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s8)
      }
      .background(DS.Colors.Surface.window)
      .accessibilityIdentifier("preview.library")
    }
  }

  private struct MacLibraryHeading: View {
    var body: some View {
      VStack(alignment: .leading, spacing: DS.Space.s4) {
        Text("Library", bundle: #bundle)
          .font(.largeTitle.weight(.semibold))
        Text(
          "Two original sample resources, available entirely in this local preview.",
          bundle: #bundle
        )
        .font(.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
      }
    }
  }

  private struct MacLibraryResource: View {
    let resource: PreviewResource
    let workspace: PreviewWorkspace

    var body: some View {
      VStack(alignment: .leading, spacing: DS.Space.s6) {
        Label {
          VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(resource.title)
              .font(.headline)
            Text(resource.subtitle)
              .font(.callout)
              .foregroundStyle(DS.Colors.Text.secondary)
          }
        } icon: {
          Image(systemName: resource.systemImage)
            .foregroundStyle(DS.Colors.Accent.text)
        }

        Text(resource.shareText)
          .font(.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
          .lineLimit(4)
          .textSelection(.enabled)

        MacLibraryResourceActions(resource: resource, workspace: workspace)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(DS.Space.s6)
      .background(DS.Colors.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.card))
      .overlay {
        RoundedRectangle(cornerRadius: DS.Radius.card)
          .strokeBorder(DS.Colors.Border.hairline)
      }
      .accessibilityIdentifier("preview.library.\(resource.rawValue)")
    }
  }

  private struct MacLibraryResourceActions: View {
    let resource: PreviewResource
    let workspace: PreviewWorkspace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
      let layout =
        dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s4))
        : AnyLayout(HStackLayout(spacing: DS.Space.s4))

      layout {
        Button {
          workspace.showResource(resource)
        } label: {
          Label {
            Text("Open Details", bundle: #bundle)
          } icon: {
            Image(systemName: PreviewRightPane.resource.systemImage)
          }
          .frame(minHeight: DS.Layout.HitTarget.preferred)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("preview.library.open.\(resource.rawValue)")

        Button {
          workspace.select(resource.bot)
        } label: {
          Label {
            Text("Open \(resource.bot.name)", bundle: #bundle)
          } icon: {
            Image(systemName: "bubble.left.and.bubble.right")
          }
          .frame(minHeight: DS.Layout.HitTarget.preferred)
        }
        .buttonStyle(.borderless)
        .help(Text("Open the sample resource’s bot conversation", bundle: #bundle))
      }
    }
  }
#endif
