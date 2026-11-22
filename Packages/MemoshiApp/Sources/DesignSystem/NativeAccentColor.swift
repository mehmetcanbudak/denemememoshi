import Foundation

/// Quantized sRGB contrast derivation. OKLab matrices: Björn Ottosson, public domain,
/// https://bottosson.github.io/posts/oklab/ (2021-01-25 coefficients).
/// Lightness changes first; chroma decreases only when the candidate leaves sRGB.
enum NativeAccentColor {
  struct RGB: Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
      self.red = red
      self.green = green
      self.blue = blue
    }

    init(sRGB: UInt32) {
      red = Self.linear(Double((sRGB >> 16) & 255) / 255)
      green = Self.linear(Double((sRGB >> 8) & 255) / 255)
      blue = Self.linear(Double(sRGB & 255) / 255)
    }

    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    var rgba: UInt32 {
      (Self.byte(red) << 24) | (Self.byte(green) << 16) | (Self.byte(blue) << 8) | 255
    }

    var inGamut: Bool {
      red >= -1e-8 && red <= 1 + 1e-8 && green >= -1e-8 && green <= 1 + 1e-8
        && blue >= -1e-8 && blue <= 1 + 1e-8
    }

    private static func linear(_ channel: Double) -> Double {
      channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func byte(_ linear: Double) -> UInt32 {
      let bounded = min(1, max(0, linear))
      let encoded = bounded <= 0.0031308 ? 12.92 * bounded : 1.055 * pow(bounded, 1 / 2.4) - 0.055
      return UInt32((encoded * 255).rounded())
    }
  }

  struct Adjustment: Sendable {
    let rgba: UInt32
    let minimumRatio: Double
    /// False for mathematically impossible surface/threshold combinations. Never a pass.
    let metMinimum: Bool
  }

  /// Eight lanes cover the declared opaque text surfaces; fills use only the first lane.
  /// Fixed storage avoids allocating a surface array during native color resolution.
  static func adjust(
    seed: RGB, backgrounds: borrowing SIMD8<Double>, count: Int,
    minimum: Double, lighten: Bool
  ) -> Adjustment {
    let initial = seed.rgba
    let initialRatio = ratio(initial, backgrounds: backgrounds, count: count)
    if initialRatio >= minimum {
      return Adjustment(rgba: initial, minimumRatio: initialRatio, metMinimum: true)
    }
    let blackRatio = ratio(0x0000_00FF, backgrounds: backgrounds, count: count)
    let whiteRatio = ratio(0xFFFF_FFFF, backgrounds: backgrounds, count: count)
    let endpoint: UInt32 = lighten ? 0xFFFF_FFFF : 0x0000_00FF
    let endpointRatio = lighten ? whiteRatio : blackRatio
    guard endpointRatio >= minimum else {
      // Some backgrounds admit neither polarity at the requested ratio.
      let whiteWins = whiteRatio > blackRatio
      let bestRatio = whiteWins ? whiteRatio : blackRatio
      return Adjustment(
        rgba: whiteWins ? 0xFFFF_FFFF : 0x0000_00FF,
        minimumRatio: bestRatio, metMinimum: bestRatio >= minimum)
    }
    let lab = Lab(seed)
    var failingLightness = lab.lightness
    var passingLightness = lighten ? 1.0 : 0.0
    var best = endpoint
    var bestRatio = endpointRatio
    for _ in 0..<24 {
      let lightness = (failingLightness + passingLightness) / 2
      let candidate = lab.gamutMapped(lightness: lightness).rgba
      let candidateRatio = ratio(candidate, backgrounds: backgrounds, count: count)
      if candidateRatio >= minimum {
        passingLightness = lightness
        best = candidate
        bestRatio = candidateRatio
      } else {
        failingLightness = lightness
      }
    }
    return Adjustment(rgba: best, minimumRatio: bestRatio, metMinimum: true)
  }

  private static func ratio(
    _ rgba: UInt32, backgrounds: borrowing SIMD8<Double>, count: Int
  ) -> Double {
    let foreground = RGB(sRGB: rgba >> 8).luminance
    var minimum = 21.0
    for index in 0..<count {
      let background = backgrounds[index]
      minimum = min(
        minimum, (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05))
    }
    return minimum
  }

  private struct Lab {
    let lightness: Double
    let a: Double
    let b: Double

    init(_ color: RGB) {
      let l = cbrt(
        0.4122214708 * color.red + 0.5363325363 * color.green + 0.0514459929 * color.blue)
      let m = cbrt(
        0.2119034982 * color.red + 0.6806995451 * color.green + 0.1073969566 * color.blue)
      let s = cbrt(
        0.0883024619 * color.red + 0.2817188376 * color.green + 0.6299787005 * color.blue)
      lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
      a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
      b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    func gamutMapped(lightness: Double) -> RGB {
      let full = rgb(lightness: lightness, chroma: 1)
      if full.inGamut { return full }
      var passing = 0.0
      var failing = 1.0
      var result = rgb(lightness: lightness, chroma: 0)
      for _ in 0..<16 {
        let chroma = (passing + failing) / 2
        let candidate = rgb(lightness: lightness, chroma: chroma)
        if candidate.inGamut {
          passing = chroma
          result = candidate
        } else {
          failing = chroma
        }
      }
      return result
    }

    private func rgb(lightness: Double, chroma: Double) -> RGB {
      let l = lightness + 0.3963377774 * a * chroma + 0.2158037573 * b * chroma
      let m = lightness - 0.1055613458 * a * chroma - 0.0638541728 * b * chroma
      let s = lightness - 0.0894841775 * a * chroma - 1.2914855480 * b * chroma
      let l3 = l * l * l
      let m3 = m * m * m
      let s3 = s * s * s
      return RGB(
        red: 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
        green: -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
        blue: -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
    }
  }
}
