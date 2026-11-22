import SwiftUI
import Synchronization

/// Current-only native colors. Warm retains its separately reviewed canonical variants.
/// The four cache slots are invalidated by the resolved accent and native surface colors.
enum NativeAccentPalette {
  enum Role: Sendable { case text, fill }

  struct Pair: Sendable {
    let text: NativeAccentColor.Adjustment
    let fill: NativeAccentColor.Adjustment

    subscript(_ role: Role) -> NativeAccentColor.Adjustment {
      switch role {
      case .text: text
      case .fill: fill
      }
    }
  }

  private struct Inputs: Equatable, Sendable {
    let accent: Color.Resolved
    let content: Color.Resolved
    let window: Color.Resolved
  }

  private struct Entry: Sendable {
    let inputs: Inputs
    let pair: Pair
  }

  private struct Cache: Sendable {
    var light: Entry?
    var dark: Entry?
    var increasedLight: Entry?
    var increasedDark: Entry?
  }

  private static let cache = Mutex(Cache())
  // The catalogue is the single authority for intended text/background pairings.
  private static let textPairs = DS.Contrast.pairs.filter { $0.id.hasPrefix("accent.text / ") }

  static func resolve(in environment: EnvironmentValues) -> Pair {
    let inputs = Inputs(
      accent: Color.accentColor.resolve(in: environment),
      content: DS.Colors.Surface.content.resolve(in: environment).resolve(in: environment),
      window: DS.Colors.Surface.window.resolve(in: environment).resolve(in: environment))
    let dark = environment.colorScheme == .dark
    let increased = environment.effectiveIncreasedContrast
    return cache.withLock { cache in
      switch (dark, increased) {
      case (false, false):
        return resolve(&cache.light, inputs: inputs, environment: environment)
      case (true, false):
        return resolve(&cache.dark, inputs: inputs, environment: environment)
      case (false, true):
        return resolve(&cache.increasedLight, inputs: inputs, environment: environment)
      case (true, true):
        return resolve(&cache.increasedDark, inputs: inputs, environment: environment)
      }
    }
  }

  private static func resolve(
    _ entry: inout Entry?, inputs: Inputs, environment: EnvironmentValues
  ) -> Pair {
    if let entry, entry.inputs == inputs { return entry.pair }
    let increased = environment.effectiveIncreasedContrast
    let dark = environment.colorScheme == .dark
    let seed = rgb(inputs.accent)
    var backgrounds = SIMD8<Double>()
    var count = 0
    var textMinimum = 0.0
    for pair in textPairs {
      let resolved = pair.background.resolve(in: environment).resolve(in: environment)
      backgrounds[count] = rgb(resolved).luminance
      count += 1
      textMinimum = max(textMinimum, increased ? pair.increasedMinimum : pair.standardMinimum)
    }
    let onFill = DS.Colors.Accent.onFill.resolve(in: environment).resolve(in: environment)
    let text = NativeAccentColor.adjust(
      seed: seed, backgrounds: backgrounds, count: count,
      minimum: textMinimum + DS.Contrast.derivationMargin, lighten: dark)
    let fill = NativeAccentColor.adjust(
      seed: seed, backgrounds: SIMD8(repeating: rgb(onFill).luminance), count: 1,
      minimum: DS.Contrast.accentFillMinimum + DS.Contrast.derivationMargin, lighten: dark)
    let pair = Pair(text: text, fill: fill)
    entry = Entry(inputs: inputs, pair: pair)
    return pair
  }

  private static func rgb(_ color: Color.Resolved) -> NativeAccentColor.RGB {
    NativeAccentColor.RGB(
      red: Double(color.linearRed), green: Double(color.linearGreen), blue: Double(color.linearBlue)
    )
  }
}
