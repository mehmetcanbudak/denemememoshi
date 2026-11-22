import Foundation

/// Original local resources for visual review, not records fetched from Apple services.
public enum PreviewResource: String, CaseIterable, Identifiable, Sendable {
  case forecast, readingNote

  /// Stable identity inside the design preview.
  public var id: Self { self }
  /// The resource's human-readable title.
  public var title: String {
    switch self {
    case .forecast: String(localized: "Cupertino forecast", bundle: #bundle)
    case .readingNote: String(localized: "An assistant, not another dashboard", bundle: #bundle)
    }
  }
  /// A description that keeps example resources distinguishable from live data.
  public var subtitle: String {
    switch self {
    case .forecast: String(localized: "Illustrative weather · not a live report", bundle: #bundle)
    case .readingNote: String(localized: "Original design note · local example", bundle: #bundle)
    }
  }
  /// The resource category's system symbol.
  public var systemImage: String {
    switch self {
    case .forecast: "cloud.sun"
    case .readingNote: "doc.text"
    }
  }
  /// The example bot associated with this resource.
  public var bot: PreviewBot {
    switch self {
    case .forecast: .weather
    case .readingNote: .researcher
    }
  }
  /// An official informational website, not evidence that a connector fetched this example.
  public var sourceURL: URL? {
    switch self {
    case .forecast: Self.weatherURL
    case .readingNote: Self.designURL
    }
  }
  /// Exact original sample content exported by Copy and Share actions.
  public var shareText: String {
    switch self {
    case .forecast:
      String(
        localized:
          """
          Memoshi — illustrative Cupertino forecast
          Example data only. No weather service was contacted.
          19°C, partly cloudy. Feels like 18°C. High 23°C, low 14°C.
          Today: 14–23°C · Tomorrow: 15–22°C · Monday: 13–20°C
          Tuesday: 14–24°C · Wednesday: 15–25°C
          Hours: 8 AM 16°C · 11 AM 19°C · 2 PM 23°C · 5 PM 21°C
          """,
        bundle: #bundle)
    case .readingNote:
      String(
        localized:
          """
          An assistant, not another dashboard
          Original Memoshi example note. No research or model call was performed.

          Conversations give work a home. Native cards make resources tangible.
          Activity makes the process inspectable without getting in the way.

          • Keep a continuous conversation for each bot.
          • Represent real objects with native controls.
          • Show state honestly, including when work is blocked.
          """,
        bundle: #bundle)
    }
  }

  private static let weatherURL = URL(string: "https://weather.apple.com/")
  private static let designURL = URL(
    string: "https://developer.apple.com/design/human-interface-guidelines/")
}
