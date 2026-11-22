import SwiftUI

/// A bot's derived status as avatars and status labels present it ([object model §5.1]).
///
/// Raw values are the protocol's wire names. Every status except `idle` pairs its text label
/// with a glyph badge, so no state relies on color or motion alone (D30); idle shows no badge
/// and its row shows the job line instead.
public enum AvatarStatus: String, CaseIterable, Identifiable, Sendable {
  /// Nothing above applies.
  case idle
  /// A task is running.
  case working
  /// A pending card needs the user.
  case needsYou = "needs_you"
  /// Unseen news or unread output.
  case hasNews = "has_news"
  /// A wake or routine fire is scheduled.
  case asleep
  /// An active watch, with nothing above applying.
  case watching
  /// Paused by the user, by absence or by budget, or while the user is in control.
  case paused
  /// Something failed and needs attention.
  case error

  /// Stable identity for native lists and pickers.
  public var id: Self { self }

  /// The short status name read with the glyph and by VoiceOver.
  public var label: LocalizedStringResource {
    switch self {
    case .idle: LocalizedStringResource("Idle", bundle: #bundle)
    case .working: LocalizedStringResource("Working", bundle: #bundle)
    case .needsYou: LocalizedStringResource("Needs you", bundle: #bundle)
    case .hasNews: LocalizedStringResource("Has news", bundle: #bundle)
    case .asleep: LocalizedStringResource("Asleep", bundle: #bundle)
    case .watching: LocalizedStringResource("Watching", bundle: #bundle)
    case .paused: LocalizedStringResource("Paused", bundle: #bundle)
    case .error: LocalizedStringResource("Needs attention", bundle: #bundle)
    }
  }

  /// The visible status line for a detail given without the status name, following
  /// 02-experience §4.4: "Working: reading pricing page", "Watching 2 pages", "Asleep until
  /// 9:00", or the detail alone for news and an idle bot's job line.
  public func subtitle(detail: String?) -> Text {
    guard let detail, !detail.isEmpty else { return Text(label) }
    switch self {
    case .idle, .hasNews: return Text(verbatim: detail)
    case .watching, .asleep: return Text("\(Text(label)) \(detail)", bundle: #bundle)
    case .working, .needsYou, .paused, .error:
      return Text("\(Text(label)): \(detail)", bundle: #bundle)
    }
  }

  /// The badge glyph and color roles; `nil` for idle, which shows no badge.
  public var badge: AvatarBadgeStyle? {
    switch self {
    case .idle: nil
    case .working: DS.Avatar.StatusBadges.working
    case .needsYou: DS.Avatar.StatusBadges.needsYou
    case .hasNews: DS.Avatar.StatusBadges.hasNews
    case .asleep: DS.Avatar.StatusBadges.asleep
    case .watching: DS.Avatar.StatusBadges.watching
    case .paused: DS.Avatar.StatusBadges.paused
    case .error: DS.Avatar.StatusBadges.error
    }
  }

  /// The model eye pose: held whenever loops are absent (Reduce Motion, Low Power Mode, budget
  /// overflow, overlays, hidden), while running loops animate from it.
  var stillPose: AvatarEyePose {
    switch self {
    case .idle: DS.Avatar.States.Idle.stillPose
    case .working: DS.Avatar.States.Working.stillPose
    case .needsYou: DS.Avatar.States.NeedsYou.stillPose
    case .hasNews: DS.Avatar.States.HasNews.stillPose
    case .asleep: DS.Avatar.States.Asleep.stillPose
    case .watching: DS.Avatar.States.Watching.stillPose
    case .paused: DS.Avatar.States.Paused.stillPose
    case .error: DS.Avatar.States.Error.stillPose
    }
  }

  /// Whether the status has an ambient loop; one-shots are separate.
  var hasLoop: Bool {
    switch self {
    case .working, .needsYou, .watching, .asleep: true
    case .idle, .hasNews, .paused, .error: false
    }
  }

  /// Rank in the shared per-window motion budget; lower ranks keep loops or one-shots first.
  var animationRank: Int {
    DS.Avatar.Concurrency.priority.firstIndex(of: self) ?? DS.Avatar.Concurrency.priority.count
  }
}

/// Orthogonal avatar overlays: in control, computer offline and unread count.
public struct AvatarOverlays: Equatable, Sendable {
  /// The user controls the bot's browser or computer; its status is `paused`.
  public var takenOver: Bool
  /// The bot's computer is in `error`, `stopped` or `unreachable` while work waits.
  public var offline: Bool
  /// Unread messages and news; zero hides the count badge.
  public var unreadCount: Int

  /// Creates overlays; the defaults show none.
  public init(takenOver: Bool = false, offline: Bool = false, unreadCount: Int = 0) {
    self.takenOver = takenOver
    self.offline = offline
    self.unreadCount = unreadCount
  }

  /// The bottom-trailing badge: in control, then offline, then the status badge.
  func badge(for status: AvatarStatus) -> AvatarBadgeStyle? {
    if takenOver { return DS.Avatar.StatusBadges.takenOver }
    if offline { return DS.Avatar.StatusBadges.offline }
    return status.badge
  }
}

/// The VoiceOver form "<Name>, <status>[: <detail>][, <overlay>]" (03-design-system §10.6).
public enum AvatarAccessibility {
  /// Builds the spoken label. `detail` is the status detail without the status name, as for
  /// `AvatarStatus.subtitle(detail:)`.
  public static func label(
    name: String, status: AvatarStatus, detail: String? = nil,
    overlays: AvatarOverlays = AvatarOverlays()
  ) -> Text {
    var label = Text("\(name), \(Text(status.label))", bundle: #bundle)
    if let detail, !detail.isEmpty {
      label = Text("\(name), \(Text(status.label)): \(detail)", bundle: #bundle)
    }
    if overlays.takenOver {
      label = Text("\(label), you are in control", bundle: #bundle)
    }
    if overlays.offline {
      label = Text("\(label), computer offline", bundle: #bundle)
    }
    if overlays.unreadCount > 0 {
      label = Text("\(label), \(overlays.unreadCount) unread", bundle: #bundle)
    }
    return label
  }
}
