import Accessibility
import SwiftUI

/// An unfinished or interrupted reply. The caption is drawn under the text; the value is what
/// assistive technologies read after the sender label (02 §13.2).
public enum DesignMessageState: CaseIterable, Sendable {
  case responding, stopped, failed

  /// The visible caption below the message text.
  public var caption: LocalizedStringResource {
    switch self {
    case .responding: LocalizedStringResource("Responding…", bundle: #bundle)
    case .stopped: LocalizedStringResource("Stopped", bundle: #bundle)
    case .failed: LocalizedStringResource("Response failed", bundle: #bundle)
    }
  }

  /// The accessibility value, so a partial reply is never read as a finished answer.
  public var accessibilityValue: LocalizedStringResource {
    switch self {
    case .responding: LocalizedStringResource("Responding", bundle: #bundle)
    case .stopped: LocalizedStringResource("Stopped", bundle: #bundle)
    case .failed: LocalizedStringResource("Response failed", bundle: #bundle)
    }
  }
}

/// Risk tiers with their label, glyph and color role (03 §4.3). Color escalates only from T3.
public enum DesignRiskTier: Int, CaseIterable, Sendable {
  case t0, t1, t2, t3, t4, t5

  /// A protocol tier level; unknown levels have no invented meaning.
  public init?(level: Int) { self.init(rawValue: level) }

  /// The tier label without its number.
  public var name: LocalizedStringResource {
    switch self {
    case .t0: LocalizedStringResource("Read", bundle: #bundle)
    case .t1: LocalizedStringResource("Local write", bundle: #bundle)
    case .t2: LocalizedStringResource("Execute", bundle: #bundle)
    case .t3: LocalizedStringResource("Reach out", bundle: #bundle)
    case .t4: LocalizedStringResource("Act externally", bundle: #bundle)
    case .t5: LocalizedStringResource("Critical", bundle: #bundle)
    }
  }

  /// The `TierBadge` text, always number and label together.
  public var badge: LocalizedStringResource {
    LocalizedStringResource("T\(rawValue) · \(String(localized: name))", bundle: #bundle)
  }

  /// The tier glyph shown beside the badge, so the tier never depends on color.
  public var glyph: String {
    switch self {
    case .t0: "eye"
    case .t1: "pencil"
    case .t2: "terminal"
    case .t3: "network"
    case .t4: "paperplane.fill"
    case .t5: "exclamationmark.shield.fill"
    }
  }

  /// The badge foreground role.
  public var foreground: AdaptiveColor {
    switch self {
    case .t0, .t1, .t2: DS.Colors.Status.Neutral.fg
    case .t3: DS.Colors.Status.Caution.fg
    case .t4: DS.Colors.Status.Attention.fg
    case .t5: DS.Colors.Status.Danger.fg
    }
  }
}

/// A card's grouped accessibility summary: "<Kind> from <origin>, <tier>, <summary>" with the
/// state and remaining time as its value (02 §13.2). Hosts supply already-localized parts.
public struct DesignCardAccessibility: Sendable {
  /// The summary label.
  public let label: LocalizedStringResource
  /// The current state, plus the remaining whole minutes while time remains.
  public let value: LocalizedStringResource

  /// `remainingMilliseconds` is the card deadline minus now, or nil without a deadline. Minutes
  /// round up so a live card never reads "0 minutes"; passed deadlines make no expiry claim.
  public init(
    kind: String, origin: String, tier: DesignRiskTier?, title: String, state: String,
    remainingMilliseconds: Int64?
  ) {
    if let tier {
      label = LocalizedStringResource(
        "\(kind) from \(origin), \(String(localized: tier.badge)), \(title)", bundle: #bundle)
    } else {
      label = LocalizedStringResource("\(kind) from \(origin), \(title)", bundle: #bundle)
    }
    guard let remaining = remainingMilliseconds, remaining > 0 else {
      value = LocalizedStringResource("\(state)", bundle: #bundle)
      return
    }
    let minutes = (remaining + 59_999) / 60_000
    // One key; the String Catalog's plural variation reads "1 minute" or "n minutes".
    value = LocalizedStringResource("\(state), expires in \(minutes) minutes", bundle: #bundle)
  }
}

/// Coalesces announcements for cards outside the focused conversation: the first posts at
/// once, later ones within the window are counted and posted together when it ends (02 §13.2).
public struct DesignAnnouncementCoalescer: Sendable {
  /// What the caller does with one received item.
  public enum Outcome: Equatable, Sendable {
    /// Post now for this many items.
    case post(count: Int)
    /// A post is due at this instant; call `flush(at:)` then.
    case deferred(until: ContinuousClock.Instant)
  }

  private let window: Duration
  private var lastPost: ContinuousClock.Instant?
  private var pending: Set<String> = []

  /// At most one announcement per `window`.
  public init(window: Duration) { self.window = window }

  /// Records a newly arrived item. Repeated identifiers within one window count once. An item
  /// that arrives after the window ended posts together with any still waiting for `flush`.
  public mutating func receive(_ id: String, at now: ContinuousClock.Instant) -> Outcome {
    if let lastPost, now < lastPost + window {
      pending.insert(id)
      return .deferred(until: lastPost + window)
    }
    lastPost = now
    pending.insert(id)
    let count = pending.count
    pending = []
    return .post(count: count)
  }

  /// The count to post when the window has ended and items are waiting, otherwise nil.
  public mutating func flush(at now: ContinuousClock.Instant) -> Int? {
    guard !pending.isEmpty, let lastPost, now >= lastPost + window else { return nil }
    let count = pending.count
    pending = []
    self.lastPost = now
    return count
  }
}

/// Posts polite VoiceOver announcements for the events in 02 §13.2. Callers decide the scope:
/// focused events post at once, completions post once per key and cards elsewhere coalesce.
/// Without a running assistive technology the system post has no effect.
@MainActor
public final class DesignAnnouncer {
  private let post: @MainActor (String) -> Void
  private let now: @MainActor () -> ContinuousClock.Instant
  private var coalescer: DesignAnnouncementCoalescer
  private var flushTask: Task<Void, Never>?
  private var flushDeadline: ContinuousClock.Instant?
  private var announcedKeys: [String] = []
  private static let keyLimit = 256

  /// The system announcer used unless a host injects another.
  nonisolated public static let system = DesignAnnouncer(
    window: .seconds(10), post: DesignAnnouncer.postPolitely)

  /// `post` receives each final announcement text; the default posts a system announcement.
  nonisolated public convenience init(
    window: Duration = .seconds(10), post: @escaping @MainActor (String) -> Void
  ) {
    self.init(window: window, now: { .now }, post: post)
  }

  /// `now` is the instant read when an item arrives and when a scheduled flush runs; tests
  /// supply their own so that arrival order does not depend on scheduling.
  nonisolated init(
    window: Duration, now: @escaping @MainActor () -> ContinuousClock.Instant,
    post: @escaping @MainActor (String) -> Void
  ) {
    self.post = post
    self.now = now
    coalescer = DesignAnnouncementCoalescer(window: window)
  }

  /// Announces an event in the focused conversation or surface.
  public func announce(_ text: String) {
    guard !text.isEmpty else { return }
    post(text)
  }

  /// Announces a completion or finished message only the first time its key is seen.
  public func announceOnce(_ text: String, key: String) {
    guard !announcedKeys.contains(key) else { return }
    announcedKeys.append(key)
    if announcedKeys.count > Self.keyLimit { announcedKeys.removeFirst() }
    announce(text)
  }

  /// Counts a new item that needs the person outside the focused conversation.
  public func noteElsewhere(id: String) {
    switch coalescer.receive(id, at: now()) {
    case .post(let count):
      post(Self.itemsNeedYou(count))
    case .deferred(let deadline):
      // One flush per deadline. A post made after a window ended opens a new window, so an item
      // deferred into it needs its own flush even while the earlier one has yet to run.
      guard flushDeadline != deadline else { return }
      flushDeadline = deadline
      flushTask?.cancel()
      flushTask = Task { [weak self] in
        try? await Task.sleep(until: deadline, clock: .continuous)
        self?.flush(due: deadline)
      }
    }
  }

  private func flush(due deadline: ContinuousClock.Instant) {
    guard flushDeadline == deadline else { return }
    flushDeadline = nil
    flushTask = nil
    if let count = coalescer.flush(at: now()) { post(Self.itemsNeedYou(count)) }
  }

  /// One key; the String Catalog's plural variation reads "1 item needs you" or "n items need
  /// you".
  private static func itemsNeedYou(_ count: Int) -> String {
    String(localized: "\(count) items need you", bundle: #bundle)
  }

  private static func postPolitely(_ text: String) {
    var announcement = AttributedString(text)
    announcement.accessibilitySpeechAnnouncementPriority = .low
    AccessibilityNotification.Announcement(announcement).post()
  }
}

private struct DesignAnnouncerKey: EnvironmentKey {
  static let defaultValue = DesignAnnouncer.system
}

extension EnvironmentValues {
  /// The announcer for this surface; hosts and fixtures may inject a scoped one.
  public var designAnnouncer: DesignAnnouncer {
    get { self[DesignAnnouncerKey.self] }
    set { self[DesignAnnouncerKey.self] = newValue }
  }
}
