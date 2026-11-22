import AppCore
import ConversationFeature
import DesignSystem
import ShellFeature
import SwiftUI

/// Memoshi on iPhone and iPad. The Memoshi tab is the Assistant's real Chat, whose engine runs in
/// this app; the other bots and resources remain separately labelled local examples.
@main
struct MemoshiMobileApp: App {
  var body: some Scene {
    WindowGroup {
      if DevelopmentComposition.isolatedBrowserReview {
        MobileBrowserReviewView().previewAppearance()
      } else {
        MobileApplicationWorkspace()
      }
    }
  }
}

/// Normal app ownership is constructed only outside the explicit isolated review root.
private struct MobileApplicationWorkspace: View {
  @State private var host = MobileEngineHost()
  @State private var workspace = PreviewWorkspace()
  @State private var drafts = ComposerDrafts()
  #if DEBUG
    @State private var developmentReview: MobileDevelopmentReview?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  #endif
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    // The development menu takes its own row below the tabs. As a bottom safe-area inset it was
    // drawn over the Assistant's composer: the tab content does not take an outer inset.
    VStack(spacing: DS.Space.s0) {
      MobileWorkspaceView(
        workspace: workspace, liveAssistant: true,
        pendingApprovalCount: host.chat.reviews.pendingCount
      ) { bot in
        if bot == .assistant {
          MobileLiveChatView(model: host.chat, state: host.state)
        } else {
          PreviewConversationView(
            bot: bot, drafts: drafts,
            showActivity: { workspace.showActivity(for: bot) },
            showResource: { workspace.showResource($0) }
          )
        }
      } activity: { bot in
        PreviewActivityView(bot: bot)
      } resourceDetail: { resource in
        PreviewResourceDetailView(resource: resource)
      }
      #if DEBUG
        HStack {
          Spacer()
          if dynamicTypeSize.isAccessibilitySize {
            // At accessibility sizes the row keeps to the glyph; the name stays its label.
            developmentMenu.labelStyle(.iconOnly)
          } else {
            developmentMenu
          }
        }
        .background(DS.Colors.Surface.window)
      #endif
    }
    #if DEBUG
      .sheet(item: $developmentReview) { review in
        switch review {
        case .python:
          NavigationStack { PyodideReviewView() }
        case .browser:
          MobileBrowserReviewView()
        case .pairing:
          DevicePairingReviewView()
        }
      }
    #endif
    .task { await host.open() }
    // Close the in-process engine inside a background task before suspension and reopen on active.
    .onChange(of: scenePhase) { _, phase in
      Task { await host.scenePhaseChanged(phase) }
    }
    // Outermost, so the Development Review sheets also get the palette and the checked tint;
    // applied above `.sheet`, they drew system-blue controls.
    .previewAppearance()
  }
  #if DEBUG
    private var developmentMenu: some View {
      Menu("Development Review", systemImage: "wrench.and.screwdriver") {
        Button("Python Review", systemImage: "chart.xyaxis.line") {
          developmentReview = .python
        }
        Button("Browser Review", systemImage: "globe") {
          developmentReview = .browser
        }
        Button("Device Pairing Review", systemImage: "qrcode") {
          developmentReview = .pairing
        }
      }
      .accessibilityIdentifier("mobile.developmentReview")
      .padding(DS.Space.s3)
    }
  #endif
}

#if DEBUG
  private enum MobileDevelopmentReview: String, Identifiable {
    case python
    case browser
    case pairing
    var id: String { rawValue }
  }
#endif
