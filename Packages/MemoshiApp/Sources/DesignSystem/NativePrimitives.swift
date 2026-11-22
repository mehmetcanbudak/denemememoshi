import SwiftUI

/// State vocabulary for a bounded native work row. Every state keeps both text and a glyph.
public enum DesignWorkState: String, CaseIterable, Identifiable, Sendable {
  case queued, running, succeeded, failed

  /// Stable native picker identity.
  public var id: Self { self }
  /// State label, independent of color and motion.
  public var label: LocalizedStringResource {
    switch self {
    case .queued: LocalizedStringResource("Queued", bundle: #bundle)
    case .running: LocalizedStringResource("Running", bundle: #bundle)
    case .succeeded: LocalizedStringResource("Completed", bundle: #bundle)
    case .failed: LocalizedStringResource("Failed", bundle: #bundle)
    }
  }

  var glyph: String {
    switch self {
    case .queued: "hourglass"
    case .running: "arrow.trianglehead.2.clockwise"
    case .succeeded: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    }
  }

  var foreground: AdaptiveColor {
    switch self {
    case .queued: DS.Colors.Status.Neutral.fg
    case .running: DS.Colors.Status.Running.fg
    case .succeeded: DS.Colors.Status.Success.fg
    case .failed: DS.Colors.Status.Danger.fg
    }
  }
}

/// An opaque content chip. It is a label, not a fake button or a looping activity effect.
public struct DesignStatusChip: View {
  private let title: String
  private let state: DesignWorkState
  @Environment(\.motionPolicy) private var policy
  @Environment(\.effectiveIncreasedContrast) private var increasedContrast

  /// The host supplies actual state and truthful work text.
  public init(_ title: String, state: DesignWorkState) {
    self.title = title
    self.state = state
  }

  /// Native state changes crossfade; Reduce Motion changes the state without interpolation.
  public var body: some View {
    Label {
      Text("\(title) · \(Text(state.label))", bundle: #bundle)
    } icon: {
      Image(systemName: state.glyph)
    }
    .font(DS.Typography.callout)
    .foregroundStyle(state.foreground)
    .padding(.horizontal, DS.Layout.Chip.paddingH)
    .frame(minHeight: DS.Layout.Chip.height)
    .background(DS.Colors.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.md))
    .overlay {
      if increasedContrast {
        RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Colors.Border.strong)
      }
    }
    .contentTransition(.opacity)
    .animation(DS.Motion.Recipes.chipState.animation(for: policy), value: state)
    .accessibilityElement(children: .combine)
  }
}

/// The reusable opaque content layer. Native buttons/fields remain owned by its caller;
/// neither a token nor an API flag can turn model-authored content into functional glass.
public struct DesignCard<Content: View>: View {
  private let title: LocalizedStringResource
  private let content: () -> Content
  @Environment(\.effectiveIncreasedContrast) private var increasedContrast

  /// Creates a native content card using the shared provisional card metrics.
  public init(_ title: LocalizedStringResource, @ViewBuilder content: @escaping () -> Content) {
    self.title = title
    self.content = content
  }

  /// Opaque content with an explicit heading and a stronger increased-contrast edge.
  public var body: some View {
    VStack(alignment: .leading, spacing: DS.Layout.Card.headerGap) {
      Text(title).font(DS.Typography.headline).accessibilityAddTraits(.isHeader)
      content()
    }
    .font(DS.Typography.body)
    .foregroundStyle(DS.Colors.Text.primary)
    .padding(DS.Layout.Card.padding)
    .frame(maxWidth: DS.Layout.Card.maxWidth, alignment: .leading)
    .background(DS.Colors.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.card))
    .overlay {
      RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(
        increasedContrast ? DS.Colors.Border.strong : DS.Colors.Border.subtle)
    }
    .designElevation(DS.Elevation.e1)
    .accessibilityElement(children: .contain)
  }
}

/// A system progress indicator, not the later Aiden shimmer/activity-mark design pass.
public struct DesignProgressLabel: View {
  private let title: LocalizedStringResource
  @Environment(\.motionPolicy) private var policy
  @State private var onScreen = true

  /// Creates progress text; remove it when no work is running.
  public init(_ title: LocalizedStringResource) { self.title = title }

  /// Every constrained form retains a static glyph and the same readable progress label.
  public var body: some View {
    HStack(spacing: DS.Space.s4) {
      if policy.allowsAmbientMotion && onScreen {
        ProgressView().controlSize(.small).accessibilityHidden(true)
      } else {
        Image(systemName: "hourglass").accessibilityHidden(true)
      }
      Text(title).font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
    }
    .onScrollVisibilityChange { onScreen = $0 }
    .accessibilityElement(children: .combine)
  }
}

/// Plain selectable native text throughout streaming and settlement. There is no paced reveal,
/// transient custom TextRenderer or second persisted transcript in this Phase 0 primitive.
public struct DesignMessage: View {
  private let sender: String
  private let text: String
  private let isStreaming: Bool
  @ScaledMetric(relativeTo: .body) private var fontSize = DS.Typography.Prose.Sizes.M.size
  @ScaledMetric(relativeTo: .body) private var lineHeight = DS.Typography.Prose.Sizes.M.lineHeight

  /// Hosts provide the current text and actual running state.
  public init(sender: String, text: String, isStreaming: Bool) {
    self.sender = sender
    self.text = text
    self.isStreaming = isStreaming
  }

  /// Sender semantics stay on the combined static-text element, not selectable Text, avoiding
  /// the documented AppKit accessibility-label recursion in the existing native preview.
  public var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Text(verbatim: sender).font(DS.Typography.headline)
      Text(verbatim: text)
        .font(.system(size: fontSize))
        .lineSpacing(max(0, lineHeight - fontSize))
        .textSelection(.enabled)
    }
    .foregroundStyle(DS.Colors.Text.primary)
    .frame(maxWidth: DS.Layout.Conversation.contentMaxWidth, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isStaticText)
    .accessibilityLabel(
      isStreaming
        ? Text("\(sender) is replying", bundle: #bundle)
        : Text("\(sender): \(text)", bundle: #bundle))
  }
}
