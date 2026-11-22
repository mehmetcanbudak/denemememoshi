import Foundation

/// Stable identities for the local design examples, not persisted product Bot records.
public enum PreviewBot: String, CaseIterable, Identifiable, Sendable {
  case assistant
  case researcher
  case weather

  /// Stable selection identity within the design preview.
  public var id: Self { self }

  /// The example bot's display name, not a configured production identity.
  public var name: String {
    switch self {
    case .assistant: String(localized: "Memoshi", bundle: #bundle)
    case .researcher: String(localized: "Scout", bundle: #bundle)
    case .weather: String(localized: "Weather", bundle: #bundle)
    }
  }

  /// A short description for the roster and its search results.
  public var subtitle: String {
    switch self {
    case .assistant: String(localized: "Your personal assistant", bundle: #bundle)
    case .researcher: String(localized: "Research and reading", bundle: #bundle)
    case .weather: String(localized: "A forecast at a glance", bundle: #bundle)
    }
  }

  /// A system symbol used instead of third-party avatar artwork.
  public var systemImage: String {
    switch self {
    case .assistant: "sparkle"
    case .researcher: "magnifyingglass"
    case .weather: "cloud.sun"
    }
  }
}
