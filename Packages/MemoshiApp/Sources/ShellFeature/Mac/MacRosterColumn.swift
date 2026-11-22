#if os(macOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  struct MacRosterColumn: View {
    @Bindable var workspace: PreviewWorkspace
    @Binding var searchText: String
    let liveAssistant: Bool
    let pendingApprovalCount: Int

    var body: some View {
      VStack(spacing: DS.Space.s0) {
        MacRosterSearchField(text: $searchText)
          .padding(DS.Space.s5)
        MacBotSidebar(
          workspace: workspace, searchText: $searchText, liveAssistant: liveAssistant,
          pendingApprovalCount: pendingApprovalCount)
      }
      .background(DS.Colors.Surface.window)
    }
  }

  private struct MacRosterSearchField: View {
    @Binding var text: String

    var body: some View {
      HStack(spacing: DS.Space.s3) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        TextField(
          "", text: $text,
          prompt: Text("Search bots and resources", bundle: #bundle)
        )
        .textFieldStyle(.plain)
        .accessibilityLabel(Text("Search bots and sample resources", bundle: #bundle))
        .accessibilityIdentifier("mac-search-bots")
        if !text.isEmpty {
          Button {
            text = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .frame(
                minWidth: DS.Layout.HitTarget.preferred,
                minHeight: DS.Layout.HitTarget.preferred
              )
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("Clear Search", bundle: #bundle))
          .help(Text("Clear Search", bundle: #bundle))
        }
      }
      .padding(DS.Space.s4)
      .background(DS.Colors.Surface.well, in: RoundedRectangle(cornerRadius: DS.Radius.control))
      .overlay {
        RoundedRectangle(cornerRadius: DS.Radius.control)
          .strokeBorder(DS.Colors.Border.field)
      }
    }
  }
#endif
