import SwiftUI

/// Keeps bundled examples distinct from model output and live Apple resources.
public struct DesignPreviewNotice: View {
  /// Creates the common disclosure shown with every example conversation.
  public init() {}

  /// Explains the preview's disconnected state without implying a service health check.
  public var body: some View {
    Label {
      Text("Design preview · Examples only · No services connected", bundle: #bundle)
    } icon: {
      Image(systemName: "paintpalette")
    }
    .font(DS.Typography.subheadline)
    .foregroundStyle(DS.Colors.Text.tertiary)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, DS.Space.s3)
    .accessibilityElement(children: .combine)
  }
}
