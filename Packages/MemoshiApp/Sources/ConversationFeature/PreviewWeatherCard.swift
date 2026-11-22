import AppCore
import DesignSystem
import SwiftUI

struct PreviewWeatherCard: View {
  let showDetails: (() -> Void)?
  @State private var period = ForecastPeriod.days

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s6) {
      PreviewResourceHeader(resource: .forecast, showDetails: showDetails)
      ForecastHeading()
      Picker(selection: $period) {
        Text("Hours", bundle: #bundle).tag(ForecastPeriod.hours)
        Text("Days", bundle: #bundle).tag(ForecastPeriod.days)
      } label: {
        Text("Forecast period", bundle: #bundle)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("preview.forecastPeriod")
      if period == .days {
        VStack(spacing: DS.Space.s5) {
          ForEach(ForecastDay.examples) { day in
            ForecastDayRow(day: day)
          }
        }
        .accessibilityIdentifier("preview.forecast.days")
      } else {
        VStack(spacing: DS.Space.s5) {
          ForEach(ForecastHour.examples) { hour in
            ForecastHourRow(hour: hour)
          }
        }
        .accessibilityIdentifier("preview.forecast.hours")
      }
      PreviewResourceFooter(resource: .forecast)
    }
    .modifier(PreviewResourceSurface())
  }
}

private enum ForecastPeriod {
  case hours
  case days
}

private struct ForecastHeading: View {
  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      HStack(alignment: .center, spacing: DS.Space.s6) {
        Text("19°", bundle: #bundle)
          .font(.largeTitle.weight(.medium))
          .monospacedDigit()
          .accessibilityLabel(Text("19 degrees Celsius", bundle: #bundle))
        Spacer(minLength: DS.Space.s4)
        VStack(alignment: .trailing, spacing: DS.Space.s2) {
          Image(systemName: "cloud.sun")
            .font(.title2)
            .accessibilityHidden(true)
          Text("Partly cloudy", bundle: #bundle)
            .font(.subheadline.weight(.medium))
          Text("Feels like 18° · H:23° L:14°", bundle: #bundle)
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
        }
      }
    }
  }
}

private struct ForecastDay: Identifiable, Sendable {
  let id: String
  let name: LocalizedStringResource
  let symbol: String
  let condition: LocalizedStringResource
  let low: Int
  let high: Int

  static let examples = [
    Self(
      id: "today", name: LocalizedStringResource("Today", bundle: #bundle), symbol: "cloud.sun",
      condition: LocalizedStringResource("Partly cloudy", bundle: #bundle), low: 14, high: 23
    ),
    Self(
      id: "tomorrow", name: LocalizedStringResource("Tomorrow", bundle: #bundle), symbol: "cloud",
      condition: LocalizedStringResource("Cloudy", bundle: #bundle), low: 15, high: 22),
    Self(
      id: "monday", name: LocalizedStringResource("Monday", bundle: #bundle),
      symbol: "cloud.drizzle",
      condition: LocalizedStringResource("Light rain", bundle: #bundle), low: 13,
      high: 20),
    Self(
      id: "tuesday", name: LocalizedStringResource("Tuesday", bundle: #bundle), symbol: "sun.max",
      condition: LocalizedStringResource("Sunny", bundle: #bundle), low: 14, high: 24),
    Self(
      id: "wednesday", name: LocalizedStringResource("Wednesday", bundle: #bundle),
      symbol: "cloud.sun",
      condition: LocalizedStringResource("Partly cloudy", bundle: #bundle), low: 15,
      high: 25),
  ]
}

private struct ForecastDayRow: View {
  let day: ForecastDay
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      HStack(spacing: DS.Space.s4) {
        Text(day.name)
          .fontWeight(.medium)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: day.symbol)
          .frame(width: DS.Layout.Composer.controlSize)
          .accessibilityHidden(true)
        Text("\(day.low)°", bundle: #bundle)
          .foregroundStyle(DS.Colors.Text.secondary)
          .monospacedDigit()
        if !dynamicTypeSize.isAccessibilitySize {
          ForecastRange(low: day.low, high: day.high)
        }
        Text("\(day.high)°", bundle: #bundle)
          .monospacedDigit()
      }
      if dynamicTypeSize.isAccessibilitySize {
        Text(day.condition)
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
      }
    }
    .font(.callout)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(
        "\(String(localized: day.name)), \(String(localized: day.condition)), low \(day.low), high \(day.high) degrees Celsius",
        bundle: #bundle))
  }
}

private struct ForecastRange: View {
  let low: Int
  let high: Int

  // Celsius data-domain bounds for these sample forecasts, not layout dimensions.
  private static let scaleMinimumCelsius: CGFloat = 10
  private static let scaleSpanCelsius: CGFloat = 16

  var body: some View {
    GeometryReader { geometry in
      Capsule()
        .fill(DS.Colors.Surface.card)
        .overlay(alignment: .leading) {
          Capsule()
            .fill(DS.Colors.Accent.text)
            .frame(width: geometry.size.width * CGFloat(high - low) / Self.scaleSpanCelsius)
            .offset(
              x: geometry.size.width * (CGFloat(low) - Self.scaleMinimumCelsius)
                / Self.scaleSpanCelsius)
        }
    }
    .frame(minWidth: DS.Space.s8, maxWidth: DS.Space.s12, maxHeight: DS.Space.s3)
    .accessibilityHidden(true)
  }
}

private struct ForecastHour: Identifiable, Sendable {
  let id: String
  let name: LocalizedStringResource
  let symbol: String
  let condition: LocalizedStringResource
  let temperature: Int

  static let examples = [
    Self(
      id: "eight", name: LocalizedStringResource("8 AM", bundle: #bundle), symbol: "cloud",
      condition: LocalizedStringResource("Cloudy", bundle: #bundle), temperature: 16),
    Self(
      id: "eleven", name: LocalizedStringResource("11 AM", bundle: #bundle), symbol: "cloud.sun",
      condition: LocalizedStringResource("Partly cloudy", bundle: #bundle), temperature: 19),
    Self(
      id: "two", name: LocalizedStringResource("2 PM", bundle: #bundle), symbol: "sun.max",
      condition: LocalizedStringResource("Sunny", bundle: #bundle), temperature: 23),
    Self(
      id: "five", name: LocalizedStringResource("5 PM", bundle: #bundle), symbol: "cloud.sun",
      condition: LocalizedStringResource("Partly cloudy", bundle: #bundle), temperature: 21),
  ]
}

private struct ForecastHourRow: View {
  let hour: ForecastHour

  var body: some View {
    HStack(spacing: DS.Space.s5) {
      Text(hour.name)
        .fontWeight(.medium)
      Image(systemName: hour.symbol)
        .frame(width: DS.Layout.Composer.controlSize)
        .accessibilityHidden(true)
      Text(hour.condition)
        .foregroundStyle(DS.Colors.Text.secondary)
      Spacer(minLength: DS.Space.s4)
      Text("\(hour.temperature)°", bundle: #bundle)
        .monospacedDigit()
    }
    .font(.callout)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(
        "\(String(localized: hour.name)), \(String(localized: hour.condition)), \(hour.temperature) degrees Celsius",
        bundle: #bundle))
  }
}
