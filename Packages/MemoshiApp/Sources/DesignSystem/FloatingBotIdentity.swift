import SwiftUI

/// Original bot identity presented in a compact floating native-material capsule.
public struct FloatingBotIdentity: View {
  /// The badge is a solid accent capsule: `accent.onFill` on `accent.fill`, the checked pair
  /// prominent buttons use (D127).
  static let badgeFill = DS.Colors.Accent.fill
  /// The badge label's role, carried on `badgeFill`.
  static let badgeLabel = DS.Colors.Accent.onFill

  private let name: String
  private let symbol: String
  private let detail: String
  private let badge: String
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// Creates noninteractive identity chrome; the shell supplies its actual picker/menu action.
  /// Without `detail` or `badge`, the design-preview status and badge from DesignSystem's own
  /// String Catalog are shown.
  public init(name: String, symbol: String, detail: String? = nil, badge: String? = nil) {
    self.name = name
    self.symbol = symbol
    self.detail = detail ?? String(localized: "Design Preview · Not connected", bundle: #bundle)
    self.badge = badge ?? String(localized: "Preview", bundle: #bundle)
  }

  /// Uses native text sizing, a concise preview status and a solid reduced-transparency fallback.
  public var body: some View {
    HStack(spacing: DS.Space.s4) {
      #if os(macOS)
        BotAvatar(symbol: symbol, size: DS.Layout.Composer.controlSize)
      #else
        BotAvatar(symbol: symbol, size: DS.Layout.Composer.minHeight)
      #endif
      VStack(alignment: .leading, spacing: DS.Space.s1) {
        if dynamicTypeSize.isAccessibilitySize {
          nameText
        } else {
          // The name never breaks mid-word to make room for the badge ("Memo-shi" beside
          // "Development" on iPhone): when both do not fit on one line, the badge goes under it.
          ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.s3) {
              nameText.fixedSize()
              FloatingBotBadge(badge)
            }
            VStack(alignment: .leading, spacing: DS.Space.s1) {
              nameText
              FloatingBotBadge(badge)
            }
          }
        }
        Text(verbatim: detail)
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .foregroundStyle(DS.Colors.Text.primary)
    .padding(.horizontal, DS.Space.s5)
    .padding(.vertical, DS.Space.s3)
    .designChrome(DS.Materials.identity)
    .accessibilityElement(children: .combine)
  }

  private var nameText: some View {
    Text(verbatim: name)
      .font(DS.Typography.headline)
  }
}

/// The identity's badge ("Preview", "Development") on its own, for a shell that lays a shorter
/// identity out itself.
public struct FloatingBotBadge: View {
  private let text: String

  /// Creates the badge with its visible text.
  public init(_ text: String) {
    self.text = text
  }

  /// A solid accent capsule that keeps its size.
  public var body: some View {
    Text(verbatim: text)
      .font(DS.Typography.subheadline.weight(.semibold))
      .foregroundStyle(FloatingBotIdentity.badgeLabel)
      .fixedSize()
      .padding(.horizontal, DS.Space.s3)
      .padding(.vertical, DS.Space.s1)
      .background(FloatingBotIdentity.badgeFill, in: Capsule())
  }
}
