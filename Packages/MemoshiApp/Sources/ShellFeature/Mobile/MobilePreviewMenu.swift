#if os(iOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  struct MobilePreviewMenu: View {
    var bot: PreviewBot? = nil
    var showActivity: (() -> Void)? = nil
    /// The real in-process Chat: no example Activity and no "not connected" disclosure.
    var isLive = false

    var body: some View {
      Menu {
        if let bot, let showActivity {
          Section {
            Button(action: showActivity) {
              Label {
                Text("Sample Activity for \(bot.name)", bundle: #bundle)
              } icon: {
                Image(systemName: "list.bullet.rectangle")
              }
            }
            .accessibilityHint(Text("Opens local example steps. No tools run.", bundle: #bundle))
            .accessibilityIdentifier("workspace.activity")
          }
        }
        Section {
          PalettePicker()
        } header: {
          Text("Appearance", bundle: #bundle)
        }
        Section {
          if isLive {
            Text("Development chat · Engine on this device", bundle: #bundle)
          } else {
            Text("Design Preview · Not connected", bundle: #bundle)
          }
        }
      } label: {
        Label {
          Text("Palette", bundle: #bundle)
        } icon: {
          Image(systemName: "paintpalette")
        }
        .labelStyle(.titleOnly)
        .frame(
          minWidth: DS.Layout.Composer.minHeight,
          minHeight: DS.Layout.Composer.minHeight
        )
      }
      .accessibilityLabel(Text("Palette and preview options", bundle: #bundle))
      .accessibilityHint(
        bot == nil
          ? Text("Choose Current or Warm colors for the local preview.", bundle: #bundle)
          : Text("Choose Current or Warm colors and inspect sample Activity.", bundle: #bundle)
      )
      .accessibilityIdentifier("workspace.palette")
    }
  }
#endif
