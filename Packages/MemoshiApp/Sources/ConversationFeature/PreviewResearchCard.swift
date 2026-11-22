import AppCore
import DesignSystem
import SwiftUI

struct PreviewResearchCard: View {
  let showDetails: (() -> Void)?
  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s6) {
      PreviewResourceHeader(resource: .readingNote, showDetails: showDetails)
      Text(
        "Conversations give work a home. Native cards make resources tangible. Activity makes the process inspectable without getting in the way.",
        bundle: #bundle
      )
      .font(.body)
      .textSelection(.enabled)
      DisclosureGroup {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
          Label {
            Text("Keep a continuous conversation for each bot", bundle: #bundle)
          } icon: {
            Image(systemName: "bubble.left.and.bubble.right")
          }
          Label {
            Text("Represent real objects with native controls", bundle: #bundle)
          } icon: {
            Image(systemName: "rectangle.on.rectangle")
          }
          Label {
            Text("Show state honestly, including when work is blocked", bundle: #bundle)
          } icon: {
            Image(systemName: "checkmark.shield")
          }
        }
        .font(.callout)
        .padding(.top, DS.Space.s4)
      } label: {
        Text("Design principles", bundle: #bundle)
      }
      PreviewResourceFooter(resource: .readingNote)
    }
    .modifier(PreviewResourceSurface())
  }
}
