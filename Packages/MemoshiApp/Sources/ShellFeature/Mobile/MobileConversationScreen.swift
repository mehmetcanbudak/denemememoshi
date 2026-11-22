#if os(iOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  struct MobileConversationScreen<Conversation: View>: View {
    let bot: PreviewBot
    /// The real in-process Chat rather than a local example.
    let isLive: Bool
    let selectableBots: [PreviewBot]
    let selectBot: @MainActor (PreviewBot) -> Void
    let showActivity: () -> Void
    @ViewBuilder let conversation: (PreviewBot) -> Conversation
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // The header is a bar in the safe area at every text size. As the toolbar's principal
    // item, its three lines were taller than the navigation bar and hung over the top of the
    // conversation, which got no inset for it; a tap there reached the header instead. Like
    // system bars, it stops growing at the largest standard size and offers the Large Content
    // Viewer instead: at accessibility sizes it otherwise filled the space above the composer.
    // In iPhone landscape it is one line: there, the three lines covered the approval Card's
    // Allow once button at the largest standard size. The bar is backed by the opaque window
    // surface up to the top edge, so transcript text and Cards scrolled up stop at the header
    // instead of showing through the identity pill, the bar buttons and the iPad tab bar.
    var body: some View {
      let compact = verticalSizeClass == .compact
      conversation(bot)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .top) {
          MobileConversationHeader(
            bot: bot,
            isLive: isLive,
            selectableBots: selectableBots,
            selectBot: selectBot,
            compact: compact
          )
          .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, DS.Space.s5)
          .padding(.vertical, compact ? DS.Space.s2 : DS.Space.s3)
          .background(DesignControlRoles.barBacking, ignoresSafeAreaEdges: [.top, .horizontal])
        }
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            if isLive {
              MobilePreviewMenu(isLive: true)
            } else {
              MobilePreviewMenu(bot: bot, showActivity: showActivity)
            }
          }
        }
    }
  }
#endif
