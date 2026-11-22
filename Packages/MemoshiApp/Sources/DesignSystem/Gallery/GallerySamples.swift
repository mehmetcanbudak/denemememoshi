import SwiftUI

/// An original illustrative bot for the gallery. These are design examples, not connected bots,
/// real activity or model output; names and details are Memoshi's own sample copy.
struct GallerySampleBot: Identifiable {
  let id: String
  let name: String
  let shape: AvatarShape
  let color: AvatarColor
  let status: AvatarStatus
  let detail: String?
  var overlays = AvatarOverlays()

  /// The VoiceOver form for rows and tiles that show this bot.
  var accessibilityLabel: Text {
    AvatarAccessibility.label(name: name, status: status, detail: detail, overlays: overlays)
  }

  /// The same bot in another status; its example subtitle no longer applies.
  func with(status newStatus: AvatarStatus) -> GallerySampleBot {
    GallerySampleBot(
      id: id, name: name, shape: shape, color: color, status: newStatus,
      detail: newStatus == status ? detail : nil, overlays: overlays)
  }

  /// Details for one example bot in every status, after 02-experience §4.4's subtitles.
  static let scoutDetails: [AvatarStatus: String] = [
    .idle: "Watches competitor pricing",
    .working: "reading pricing page",
    .needsYou: "approve npm test +2",
    .hasNews: "3 prices changed",
    .asleep: "until 9:00",
    .watching: "2 pages",
    .paused: "budget reached",
    .error: "model key rejected",
  ]

  static func scout(
    _ status: AvatarStatus, overlays: AvatarOverlays = AvatarOverlays()
  ) -> GallerySampleBot {
    GallerySampleBot(
      id: "gallery.scout.\(status.rawValue)", name: "Scout", shape: .squircle, color: .teal,
      status: status, detail: scoutDetails[status], overlays: overlays)
  }

  /// Twelve examples: every shape and every color once, covering all statuses and overlays.
  static let roster: [GallerySampleBot] = [
    GallerySampleBot(
      id: "gallery.memoshi", name: "Memoshi", shape: .circle, color: .cobalt, status: .idle,
      detail: "Your personal assistant"),
    GallerySampleBot(
      id: "gallery.scout", name: "Scout", shape: .squircle, color: .teal, status: .working,
      detail: "reading pricing page"),
    GallerySampleBot(
      id: "gallery.weather", name: "Weather", shape: .cloud, color: .sky, status: .asleep,
      detail: "until 7:00"),
    GallerySampleBot(
      id: "gallery.ledger", name: "Ledger", shape: .shield, color: .amber, status: .needsYou,
      detail: "approve a transfer"),
    GallerySampleBot(
      id: "gallery.atlas", name: "Atlas", shape: .leaf, color: .mint, status: .watching,
      detail: "3 flights"),
    GallerySampleBot(
      id: "gallery.juniper", name: "Juniper", shape: .flower, color: .lime, status: .hasNews,
      detail: "Seedlings are ready to plant", overlays: AvatarOverlays(unreadCount: 2)),
    GallerySampleBot(
      id: "gallery.relay", name: "Relay", shape: .hexagon, color: .slate, status: .paused,
      detail: "a week without you"),
    GallerySampleBot(
      id: "gallery.pixel", name: "Pixel", shape: .star, color: .orchid, status: .error,
      detail: "export failed"),
    GallerySampleBot(
      id: "gallery.harbor", name: "Harbor", shape: .capsule, color: .iris, status: .working,
      detail: "backing up photos", overlays: AvatarOverlays(offline: true)),
    GallerySampleBot(
      id: "gallery.tempo", name: "Tempo", shape: .drop, color: .coral, status: .paused,
      detail: nil, overlays: AvatarOverlays(takenOver: true)),
    GallerySampleBot(
      id: "gallery.quill", name: "Quill", shape: .arch, color: .violet, status: .idle,
      detail: "Drafts letters", overlays: AvatarOverlays(unreadCount: 12)),
    GallerySampleBot(
      id: "gallery.orbit", name: "Orbit", shape: .bean, color: .tangerine, status: .working,
      detail: "2 tasks"),
  ]
}
