import AppCore
import DesignSystem
import SwiftUI

/// Inspectable original sample content with native Share, Copy and informational source links.
public struct PreviewResourceDetailView: View {
  private let resource: PreviewResource

  /// Opens a local example without fetching data, invoking a model or executing an Apple tool.
  public init(resource: PreviewResource) {
    self.resource = resource
  }

  /// Presents the full native card in its own scroll container without a recursive expand action.
  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DS.Space.s6) {
        DesignPreviewNotice()
        switch resource {
        case .forecast:
          PreviewWeatherCard(showDetails: nil)
        case .readingNote:
          PreviewResearchCard(showDetails: nil)
        }
        Label {
          Text(
            "Read-only sample · Shared and copied text is labelled as an example",
            bundle: #bundle)
        } icon: {
          Image(systemName: "info.circle")
        }
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(DS.Space.s6)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(DS.Colors.Surface.inspector)
    .accessibilityIdentifier("preview.resource.detail.\(resource.rawValue)")
  }
}
