import Foundation
import Observation

/// Routes local design examples without owning canonical conversations or runtime state.
@MainActor @Observable
public final class PreviewWorkspace {
  /// The conversation selected in the main workspace.
  public var selectedBot: PreviewBot = .assistant
  /// The independently selected conversation in the secondary pane.
  public var secondaryBot: PreviewBot = .researcher
  /// Whether the Mac source list is visible.
  public var isSidebarPresented = true
  /// Whether the contextual pane or mobile detail presentation is visible.
  public var isInspectorPresented: Bool
  /// The main workspace's current local destination.
  public var section: PreviewWorkspaceSection = .conversation
  /// The type of content shown beside the main conversation.
  public var rightPane: PreviewRightPane = .activity
  /// The sample resource most recently opened for inspection.
  public private(set) var selectedResource: PreviewResource = .forecast
  /// The bot whose example work was explicitly opened, independent of either chat selection.
  public private(set) var activityBot: PreviewBot = .assistant

  /// Creates a device-local preview; Mac may initially expose its contextual pane.
  public init(isInspectorPresented: Bool = false) {
    self.isInspectorPresented = isInspectorPresented
  }

  /// Selects the main chat without replacing the secondary chat or its context.
  public func select(_ bot: PreviewBot) {
    selectedBot = bot
    section = .conversation
  }

  /// Inspects the requesting bot's example work without changing either chat selection.
  public func showActivity(for bot: PreviewBot) {
    activityBot = bot
    rightPane = .activity
    isInspectorPresented = true
  }

  /// Opens a sample resource without navigating either conversation away.
  public func showResource(_ resource: PreviewResource) {
    selectedResource = resource
    rightPane = .resource
    isInspectorPresented = true
  }

  /// Opens another chat beside the main one without replacing the main selection.
  public func openBeside(_ bot: PreviewBot) {
    secondaryBot = bot
    rightPane = .conversation
    isInspectorPresented = true
  }
}

/// Local destinations represented by the richer design-preview source list.
public enum PreviewWorkspaceSection: String, CaseIterable, Identifiable, Sendable {
  case conversation, waitingForYou, library, pages, activity

  /// Stable identity for source-list selection.
  public var id: Self { self }
  /// The visible destination name.
  public var title: String {
    switch self {
    case .conversation: String(localized: "Chat", bundle: #bundle)
    case .waitingForYou: String(localized: "Waiting for You", bundle: #bundle)
    case .library: String(localized: "Library", bundle: #bundle)
    case .pages: String(localized: "Pages", bundle: #bundle)
    case .activity: String(localized: "Activity", bundle: #bundle)
    }
  }
  /// The system symbol associated with the destination.
  public var systemImage: String {
    switch self {
    case .conversation: "bubble.left.and.bubble.right"
    case .waitingForYou: "hand.raised"
    case .library: "books.vertical"
    case .pages: "doc.richtext"
    case .activity: "clock"
    }
  }
}

/// Contextual content beside a Mac chat or in a mobile presentation.
public enum PreviewRightPane: String, CaseIterable, Identifiable, Sendable {
  case activity, resource, conversation

  /// Stable identity for context selection.
  public var id: Self { self }
  /// A short label for the pane chooser.
  public var title: String {
    switch self {
    case .activity: String(localized: "Activity", bundle: #bundle)
    case .resource: String(localized: "Details", bundle: #bundle)
    case .conversation: String(localized: "Chat", bundle: #bundle)
    }
  }
  /// A system symbol that supplements, rather than replaces, the pane label.
  public var systemImage: String {
    switch self {
    case .activity: "list.bullet.rectangle"
    case .resource: "doc.text.magnifyingglass"
    case .conversation: "bubble.left.and.bubble.right"
    }
  }
}
