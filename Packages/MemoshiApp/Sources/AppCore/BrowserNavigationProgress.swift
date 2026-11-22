/// How far one web view's top-level navigations got, as WebKit reports them: asked for, answered
/// and, when allowed, started. WebKit asks for a clicked link's or form's navigation after the
/// click returns and starts an allowed one after that; a redirect of that load may then move to
/// a separate profile (D136). So a click reports only once the navigation it allowed has started,
/// and a refused separate opening at its redirect reaches the click's step (D136 review F5).
public struct BrowserNavigationProgress: Equatable, Sendable {
  /// What a click that began at a mark still waits for.
  public enum Wait: Equatable, Sendable {
    /// WebKit has not asked for a navigation since the mark, or has not answered one it asked for.
    case decision
    /// A navigation allowed since the mark has not started yet.
    case start
    /// Nothing: no navigation was allowed, or the allowed one started.
    case none
  }

  /// Decisions WebKit asked for.
  public private(set) var asked = 0
  /// Decisions answered, allowed or not.
  public private(set) var answered = 0
  /// Decisions answered by allowing a load.
  public private(set) var allowed = 0
  /// Loads started.
  public private(set) var started = 0

  /// No navigation yet.
  public init() {}

  /// WebKit asked for a decision.
  public mutating func ask() { asked += 1 }

  /// A decision was answered; `allowed` when it lets a load start.
  public mutating func answer(allowed: Bool) {
    answered += 1
    if allowed { self.allowed += 1 }
  }

  /// A load started.
  public mutating func start() { started += 1 }

  /// What a click whose progress was `mark` when it began still waits for.
  public func wait(since mark: Self) -> Wait {
    if asked == mark.asked || answered < asked { return .decision }
    if allowed > mark.allowed, started == mark.started { return .start }
    return .none
  }
}
