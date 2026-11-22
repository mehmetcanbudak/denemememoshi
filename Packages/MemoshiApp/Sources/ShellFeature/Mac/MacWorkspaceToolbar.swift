#if os(macOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  struct MacWorkspaceToolbar: ToolbarContent {
    @Bindable var workspace: PreviewWorkspace

    var body: some ToolbarContent {
      ToolbarItem(placement: .navigation) {
        Toggle(isOn: $workspace.isSidebarPresented) {
          Label {
            Text("Sidebar", bundle: #bundle)
          } icon: {
            Image(systemName: "sidebar.left")
          }
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .help(Text("Show or hide the sidebar (⌃⌘S)", bundle: #bundle))
        .accessibilityIdentifier("sidebar-toggle")
      }

      ToolbarItem(placement: .primaryAction) {
        PalettePicker()
          .pickerStyle(.menu)
          .fixedSize()
          .help(
            Text(
              "Compare Current and Warm palettes without changing your workspace", bundle: #bundle))
      }

      ToolbarItem(placement: .primaryAction) {
        Toggle(isOn: $workspace.isInspectorPresented) {
          Label {
            Text("Context", bundle: #bundle)
          } icon: {
            Image(systemName: "sidebar.trailing")
          }
        }
        .toggleStyle(.button)
        .help(
          Text("Show or hide Activity, sample details or a bot conversation (⌃⌘I)", bundle: #bundle)
        )
        .accessibilityIdentifier("context-toggle")
      }
    }
  }
#endif
