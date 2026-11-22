import AppKit
import CoreFoundation
import Foundation

// Run with `swift scripts/design-tokens.swift [--check]` from any working directory.
// The JSON is authoritative; generated Swift is committed so app builds need no script phase.
struct TokenGenerationError: Error, CustomStringConvertible {
  let description: String
}

enum Token {
  static let appearances = ["light", "dark", "increasedContrastLight", "increasedContrastDark"]
  static let lineLength = 100
}

/// `needs_you` becomes `needsYou`; keys without underscores are unchanged.
func camelCase(_ key: String) -> String {
  let parts = key.split(separator: "_").map(String.init)
  guard let first = parts.first else { return key }
  return first + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
}

func typeName(_ key: String) -> String {
  let name = camelCase(key)
  return name.prefix(1).uppercased() + name.dropFirst()
}

func identifier(_ key: String, type: Bool = false) -> String {
  "`\(type ? typeName(key) : camelCase(key))`"
}

/// A Swift literal: integers of five or more digits are grouped for swift-format, and fractions
/// use the shortest round-tripping decimal.
func literal(_ value: Double) -> String {
  guard value.rounded() == value, abs(value) < 1e9 else { return String(value) }
  let digits = String(Int(abs(value)))
  var grouped = ""
  for (index, digit) in digits.enumerated() {
    if index > 0, digits.count >= 5, (digits.count - index) % 3 == 0 { grouped.append("_") }
    grouped.append(digit)
  }
  return (value < 0 ? "-" : "") + grouped
}

func number(_ value: Any?, path: String) throws -> Double {
  guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else {
    throw TokenGenerationError(description: "Expected a number at \(path)")
  }
  return value.doubleValue
}

func numbers(_ value: Any?, count: Int, path: String) throws -> [Double] {
  guard let values = value as? [Any], values.count == count else {
    throw TokenGenerationError(description: "Expected \(count) numbers at \(path)")
  }
  return try values.map { try number($0, path: path) }
}

func string(_ value: Any?, path: String) throws -> String {
  guard let text = value as? String else {
    throw TokenGenerationError(description: "Expected a string at \(path)")
  }
  return text
}

/// Formats `prefix name(arguments)` on one line when it fits, otherwise one argument per line.
func call(_ prefix: String, _ name: String, _ arguments: [String], indent: String) -> [String] {
  let single = "\(indent)\(prefix)\(name)(\(arguments.joined(separator: ", ")))"
  if single.count <= Token.lineLength { return [single] }
  var lines = ["\(indent)\(prefix)\(name)("]
  for (index, argument) in arguments.enumerated() {
    lines.append("\(indent)  \(argument)\(index < arguments.count - 1 ? "," : "")")
  }
  lines.append("\(indent))")
  return lines
}

func rgba(_ value: Any?, path: String) throws -> String {
  guard let text = value as? String, text.first == "#",
    text.count == 7 || text.count == 9,
    let number = UInt32(text.dropFirst(), radix: 16)
  else {
    throw TokenGenerationError(description: "Invalid color at \(path)")
  }
  let expanded = text.count == 7 ? (number << 8) | 0xFF : number
  let hex = String(format: "%08X", expanded)
  return "0x\(hex.prefix(4))_\(hex.suffix(4))"
}

/// Opaque `#RRGGBB` channels.
func channels(_ value: Any?, path: String) throws -> [Int] {
  guard let text = value as? String, text.first == "#", text.count == 7,
    let number = UInt32(text.dropFirst(), radix: 16)
  else {
    throw TokenGenerationError(description: "Expected an opaque #RRGGBB color at \(path)")
  }
  return [Int((number >> 16) & 0xFF), Int((number >> 8) & 0xFF), Int(number & 0xFF)]
}

/// The muted-avatar rule: `mix(fill, neutral, fraction)` per sRGB channel.
func mixed(_ fill: Any?, toward neutral: Any?, fraction: Double, path: String) throws -> String {
  let from = try channels(fill, path: path)
  let target = try channels(neutral, path: "avatar.colorRules.mutedNeutral")
  let result = zip(from, target).map { source, goal in
    Int((Double(source) * (1 - fraction) + Double(goal) * fraction).rounded())
  }
  return "#" + result.map { String(format: "%02X", $0) }.joined()
}

func adaptiveColor(
  _ key: String, role: [String: Any], warm: [String: Any], indent: String, path: String
) throws -> [String] {
  var arguments: [[String]] = []
  for variant in Token.appearances {
    let value = try rgba(role[variant], path: path + "." + variant)
    arguments.append(["\(variant): \(value)"])
  }
  if let system = role["system"] as? String {
    arguments.append(["system: \"\(system)\""])
  }
  if let nativeAccent = role["nativeAccent"] as? String {
    guard ["text", "fill"].contains(nativeAccent), path == "color.accent.\(nativeAccent)" else {
      throw TokenGenerationError(description: "Unexpected native accent derivation at \(path)")
    }
    arguments.append(["nativeAccent: .\(nativeAccent)"])
  }
  if !warm.isEmpty {
    let variants = try Token.appearances.map {
      let value = try rgba(warm[$0], path: "palettes.warm.\(path).\($0)")
      return "  \($0): \(value),"
    }
    arguments.append(["warm: .init("] + variants + [")"])
  }
  var lines = [
    "\(indent)/// Canonical `\(path)` adaptive color role.",
    "\(indent)public static let \(identifier(key)) = AdaptiveColor(",
  ]
  for (index, argument) in arguments.enumerated() {
    for (lineIndex, line) in argument.enumerated() {
      let comma = lineIndex == argument.count - 1 && index < arguments.count - 1 ? "," : ""
      lines.append("\(indent)  \(line)\(comma)")
    }
  }
  lines.append("\(indent))")
  return lines
}

func colors(
  _ object: [String: Any], warm: [String: Any], indent: String, path: String
) throws -> [String] {
  var lines: [String] = []
  for key in object.keys.sorted() where !key.hasPrefix("$") {
    guard let child = object[key] as? [String: Any] else { continue }
    let childPath = "\(path).\(key)"
    let warmRole = warm[key] as? [String: Any] ?? [:]
    if child["light"] != nil {
      lines += try adaptiveColor(key, role: child, warm: warmRole, indent: indent, path: childPath)
    } else {
      let members = try colors(child, warm: warmRole, indent: indent + "  ", path: childPath)
      if !members.isEmpty {
        lines +=
          [
            "\(indent)/// Canonical `\(childPath)` color roles.",
            "\(indent)public enum \(identifier(key, type: true)) {",
          ] + members
        lines.append("\(indent)}")
      }
    }
  }
  return lines
}

/// SF Symbol entries remain strings for native Label/Image APIs. Custom, composed and
/// later-stage marks stay explicit references, never invalid system symbol names.
func icons(_ document: [String: Any]) throws -> [String] {
  guard let icon = document["icon"] as? [String: Any],
    let sizes = icon["sizes"] as? [String: Any]
  else { throw TokenGenerationError(description: "Missing icon inventory or sizes") }
  func member(_ key: String) -> String {
    let parts = key.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    let joined = parts.enumerated().map { index, part in
      index == 0 ? part.prefix(1).lowercased() + part.dropFirst() : typeName(part)
    }.joined()
    return identifier(joined)
  }
  var lines = [
    "  /// Canonical glyph mappings; reference marks are not SF Symbol names.",
    "  public enum Icons {",
    "    /// Canonical point sizes from `icon.sizes`.",
    "    public enum Sizes {",
  ]
  lines += metrics(sizes, indent: "      ", path: "icon.sizes")
  lines.append("    }")
  var catalogue: [String] = []
  for group in [
    "custom", "objects", "modes", "cards", "tools", "review", "composer", "statusGlyph",
  ] {
    guard let entries = icon[group] as? [String: Any] else {
      throw TokenGenerationError(description: "Missing icon.\(group)")
    }
    lines += [
      "    /// Canonical `icon.\(group)` mappings.",
      "    public enum \(identifier(group, type: true)) {",
    ]
    var members = Set<String>()
    for key in entries.keys.sorted() where !key.hasPrefix("$") {
      let name = member(key)
      guard members.insert(name).inserted else {
        throw TokenGenerationError(
          description: "Colliding Swift glyph name at icon.\(group).\(key)")
      }
      let value = try string(entries[key], path: "icon.\(group).\(key)")
      let reference = group == "custom" || value.hasPrefix("custom:") || value.contains(" ")
      let expression: String
      if reference {
        expression = "DesignGlyph.Source.reference(\(String(reflecting: value)))"
      } else {
        guard NSImage(systemSymbolName: value, accessibilityDescription: nil) != nil else {
          throw TokenGenerationError(
            description: "Unavailable SF Symbol \(value) at icon.\(group).\(key)")
        }
        expression = String(reflecting: value)
      }
      lines += [
        "      /// Canonical `icon.\(group).\(key)` \(reference ? "reference" : "SF Symbol").",
        "      public static let \(name) = \(expression)",
      ]
      let path = "\(identifier(group, type: true)).\(name)"
      let source = reference ? path : ".system(\(path))"
      catalogue.append("      .init(\(String(reflecting: "\(group).\(key)")), \(source)),")
    }
    lines.append("    }")
  }
  lines +=
    [
      "    /// Every declared glyph; references require their named renderer, not Image(systemName:).",
      "    public static let catalog: [DesignGlyph] = [",
    ] + catalogue + ["    ]", "  }"]
  return lines
}

/// Token paths and Swift member paths of every adaptive role, in the order `colors` emits them.
func colorRoles(_ object: [String: Any], path: String, member: String) -> [(String, String)] {
  var roles: [(String, String)] = []
  for key in object.keys.sorted() where !key.hasPrefix("$") {
    guard let child = object[key] as? [String: Any] else { continue }
    if child["light"] != nil {
      roles.append(("\(path).\(key)", "\(member).\(identifier(key))"))
    } else {
      roles += colorRoles(child, path: "\(path).\(key)", member: "\(member).\(typeName(key))")
    }
  }
  return roles
}

func metrics(
  _ object: [String: Any], indent: String, path: String, numbered: Bool = false
) -> [String] {
  var lines: [String] = []
  for key in object.keys.sorted() where !key.hasPrefix("$") {
    if let child = object[key] as? [String: Any] {
      let members = metrics(child, indent: indent + "  ", path: "\(path).\(key)")
      if !members.isEmpty {
        lines +=
          [
            "\(indent)/// Canonical `\(path).\(key)` values.",
            "\(indent)public enum \(identifier(key, type: true)) {",
          ] + members
        lines.append("\(indent)}")
      }
    } else if let value = object[key] as? NSNumber,
      CFGetTypeID(value) != CFBooleanGetTypeID()
    {
      let name = numbered ? "s\(key)" : key
      lines.append("\(indent)/// Canonical `\(path).\(key)` value.")
      lines.append("\(indent)public static let \(identifier(name)): CGFloat = \(value.stringValue)")
    }
  }
  return lines
}

/// Names that string-valued avatar tokens may reference, and their generated expressions.
struct References {
  let curves: Set<String>
  let springs: Set<String>
  let poses: Set<String>

  func expression(for key: String, value: String, path: String) throws -> (String, String)? {
    switch key {
    case "curve":
      guard curves.contains(value) else { break }
      return ("curve", "DS.Motion.Curves.\(identifier(value))")
    case "spring":
      guard springs.contains(value) else { break }
      return ("spring", "DS.Motion.Springs.\(identifier(value))")
    case "pose", "stillPose", "apexEyePose":
      guard poses.contains(value) else { break }
      return ("eye pose", "AvatarEyePose.\(camelCase(value))")
    case "glyph":
      return ("SF Symbol", "\"\(value)\"")
    default:
      return nil
    }
    throw TokenGenerationError(description: "Unknown \(key) reference \(value) at \(path)")
  }
}

/// Numbers, keyframes, number lists and typed references as nested enums. Descriptive strings
/// (names, labels, notes and sources) remain documentation in the JSON.
func values(
  _ object: [String: Any], indent: String, path: String, references: References
) throws -> [String] {
  var lines: [String] = []
  for key in object.keys.sorted() where !key.hasPrefix("$") {
    let childPath = "\(path).\(key)"
    let value = object[key]
    if let child = value as? [String: Any] {
      let members = try values(
        child, indent: indent + "  ", path: childPath, references: references)
      if !members.isEmpty {
        lines +=
          [
            "\(indent)/// Canonical `\(childPath)` values.",
            "\(indent)public enum \(identifier(key, type: true)) {",
          ] + members
        lines.append("\(indent)}")
      }
    } else if let scalar = value as? NSNumber, CFGetTypeID(scalar) != CFBooleanGetTypeID() {
      let literalValue = literal(scalar.doubleValue)
      lines.append("\(indent)/// Canonical `\(childPath)` value.")
      lines.append("\(indent)public static let \(identifier(key)): CGFloat = \(literalValue)")
    } else if let text = value as? String {
      let reference = try references.expression(for: key, value: text, path: childPath)
      if let reference {
        lines.append("\(indent)/// Canonical `\(childPath)` \(reference.0).")
        lines.append("\(indent)public static let \(identifier(key)) = \(reference.1)")
      }
    } else if let array = value as? [Any], !array.isEmpty {
      lines += try arrayValue(array, key: key, indent: indent, path: childPath)
    }
  }
  return lines
}

func arrayValue(_ array: [Any], key: String, indent: String, path: String) throws -> [String] {
  let name = identifier(key)
  if array.allSatisfy({ $0 is NSNumber }) {
    let items = try array.map { literal(try number($0, path: path)) }
    return [
      "\(indent)/// Canonical `\(path)` values.",
      "\(indent)public static let \(name): [CGFloat] = [\(items.joined(separator: ", "))]",
    ]
  }
  if array.allSatisfy({ ($0 as? [Any])?.count == 2 }) {
    var lines = [
      "\(indent)/// Canonical `\(path)` keyframes: time in 0...1 of the period, then value.",
      "\(indent)public static let \(name): [AvatarKeyframe] = [",
    ]
    for item in array {
      let pair = try numbers(item, count: 2, path: path)
      lines.append("\(indent)  .init(\(literal(pair[0])), \(literal(pair[1]))),")
    }
    lines.append("\(indent)]")
    return lines
  }
  if array.allSatisfy({ ($0 as? [String: Any])?["t"] != nil }) {
    var lines = [
      "\(indent)/// Canonical `\(path)` scale keyframes.",
      "\(indent)public static let \(name): [AvatarScaleKeyframe] = [",
    ]
    for item in array {
      guard let frame = item as? [String: Any] else { continue }
      let time = literal(try number(frame["t"], path: path))
      let scaleX = literal(try number(frame["scaleX"], path: path))
      let scaleY = literal(try number(frame["scaleY"], path: path))
      lines.append("\(indent)  .init(\(time), scaleX: \(scaleX), scaleY: \(scaleY)),")
    }
    lines.append("\(indent)]")
    return lines
  }
  return []
}

func statusCases(_ value: Any?, known: Set<String>, path: String) throws -> [String] {
  guard let names = value as? [String], Set(names).isSubset(of: known) else {
    throw TokenGenerationError(description: "Unknown or missing statuses at \(path)")
  }
  guard Set(names).count == names.count else {
    throw TokenGenerationError(description: "Duplicate statuses at \(path)")
  }
  return names.map { ".\(camelCase($0))" }
}

func typography(_ document: [String: Any]) throws -> [String] {
  guard let typography = document["typography"] as? [String: Any],
    let chrome = typography["chrome"] as? [String: Any]
  else {
    throw TokenGenerationError(description: "Missing typography.chrome roles")
  }
  let styles: Set = [
    "largeTitle", "title", "title2", "title3", "headline", "body", "callout", "subheadline",
  ]
  let weights: Set = ["regular", "medium", "semibold", "bold"]
  var lines = [
    "  /// Canonical `typography` values. Chrome roles use native text styles, so Dynamic Type",
    "  /// applies; their nominal macOS sizes are documented in `Chrome`.",
    "  public enum `Typography` {",
  ]
  var catalog: [(Double, String)] = []
  for key in chrome.keys.sorted() where !key.hasPrefix("$") {
    let path = "typography.chrome.\(key)"
    guard let role = chrome[key] as? [String: Any] else { continue }
    let style = try string(role["textStyle"], path: path + ".textStyle")
    let weight = try string(role["weight"], path: path + ".weight")
    guard styles.contains(style), weights.contains(weight) else {
      throw TokenGenerationError(description: "Unsupported text style or weight at \(path)")
    }
    let font = "Font.system(.\(style), weight: .\(weight))"
    lines.append("    /// Canonical `\(path)` font: native `\(style)` style, \(weight) weight.")
    lines.append("    public static let \(identifier(key)) = \(font)")
    let size = try number(role["size"], path: path + ".size")
    let member = "Chrome.\(typeName(key))"
    let nominal = "\(member).size, \(member).lineHeight"
    catalog.append((size, ".init(\"\(key)\", \(identifier(key)), \(nominal)),"))
  }
  lines += metrics(typography, indent: "    ", path: "typography")
  lines += [
    "    /// Every chrome text role from largest to smallest, for galleries.",
    "    public static let catalog: [DesignTextRole] = [",
  ]
  let ordered = catalog.sorted { $0.0 > $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
  lines += ordered.map { "      \($0.1)" }
  lines += ["    ]", "  }"]
  return lines
}

func motion(_ document: [String: Any]) throws -> [String] {
  guard let motion = document["motion"] as? [String: Any],
    let curves = motion["curves"] as? [String: Any],
    let durations = motion["durations"] as? [String: Any],
    let springs = motion["springs"] as? [String: Any],
    let frameRate = motion["frameRate"] as? [String: Any]
  else {
    throw TokenGenerationError(description: "Missing motion curves, durations, springs or rates")
  }
  var lines = [
    "  /// Canonical `motion` values; recipe declarations remain provisional, not adoption.",
    "  public enum `Motion` {",
    "    /// Canonical `motion.curves` cubic Bézier control points.",
    "    public enum `Curves` {",
  ]
  for key in curves.keys.sorted() where !key.hasPrefix("$") {
    let points = try numbers(curves[key], count: 4, path: "motion.curves.\(key)").map(literal)
    lines.append("      /// Canonical `motion.curves.\(key)` timing curve.")
    lines += call(
      "public static let \(identifier(key)) = ", "MotionCurve", points, indent: "      ")
  }
  lines += [
    "    }",
    "    /// Canonical `motion.durations`, converted from milliseconds to seconds.",
    "    public enum `Durations` {",
  ]
  for key in durations.keys.sorted() where !key.hasPrefix("$") {
    let milliseconds = try number(durations[key], path: "motion.durations.\(key)")
    let seconds = literal(milliseconds / 1000)
    lines.append("      /// Canonical `motion.durations.\(key)` (\(literal(milliseconds)) ms).")
    lines.append("      public static let \(identifier(key)): TimeInterval = \(seconds)")
  }
  lines.append("    }")
  lines += metrics(["frameRate": frameRate], indent: "    ", path: "motion")
  lines += ["    /// Canonical `motion.springs`.", "    public enum `Springs` {"]
  for key in springs.keys.sorted() where !key.hasPrefix("$") {
    let path = "motion.springs.\(key)"
    guard let spring = springs[key] as? [String: Any] else { continue }
    let duration = literal(try number(spring["durationMs"], path: path) / 1000)
    let bounce = literal(try number(spring["bounce"], path: path))
    lines.append("      /// Canonical `\(path)` spring.")
    lines += call(
      "public static let \(identifier(key)) = ", "MotionSpring",
      ["duration: \(duration)", "bounce: \(bounce)"], indent: "      ")
  }
  lines.append("    }")
  lines += try motionRecipes(motion, curves: Set(curves.keys))
  lines.append("  }")
  return lines
}

/// Simple native recipe bindings plus nested enter/exit pairs. Specialized reveal schedulers,
/// shimmer, activity marks and later-pass effects are deliberately not implemented here.
func motionRecipes(_ motion: [String: Any], curves: Set<String>) throws -> [String] {
  guard let recipes = motion["recipes"] as? [String: Any] else {
    throw TokenGenerationError(description: "Missing motion.recipes")
  }
  var entries: [(String, [String: Any])] = []
  for key in recipes.keys.sorted() where !key.hasPrefix("$") {
    guard let recipe = recipes[key] as? [String: Any] else { continue }
    if recipe["durationMs"] != nil, recipe["curve"] != nil {
      entries.append((key, recipe))
    }
    for phase in ["enter", "exit"] {
      if var child = recipe[phase] as? [String: Any] {
        child["source"] = recipe["source"]
        entries.append((key + "." + phase, child))
      }
    }
  }
  var lines = [
    "    /// Native bindings for simple recipes; later-pass declarations are reference only.",
    "    public enum `Recipes` {",
  ]
  var names: [String: String] = [:]
  for (key, recipe) in entries {
    let path = "motion.recipes.\(key)"
    let curve = try string(recipe["curve"], path: path + ".curve")
    guard curves.contains(curve) else {
      throw TokenGenerationError(description: "Unknown curve at \(path)")
    }
    let transform = (recipe["from"] ?? recipe["to"]) as? [String: Any] ?? [:]
    // Custom clipping or a layout-token displacement needs its scheduled specialized renderer.
    guard Set(transform.keys).isSubset(of: ["opacity", "offsetX", "offsetY", "scale"]),
      transform.values.allSatisfy({ $0 is NSNumber })
    else {
      continue
    }
    let name = identifier(key.replacingOccurrences(of: ".", with: "_"))
    let duration = literal(try number(recipe["durationMs"], path: path + ".durationMs") / 1000)
    let reduced = try string(recipe["reduceMotion"], path: path + ".reduceMotion")
    let reducedMs: Double
    if reduced.hasPrefix("fade:"), let value = Double(reduced.dropFirst("fade:".count)),
      value >= 0, value <= 150
    {
      reducedMs = value
    } else if reduced.hasPrefix("instant") {
      reducedMs = 0
    } else {
      continue
    }
    names[key] = name
    let source = recipe["source"] as? String ?? "Memoshi native state recipe"
    let budget = try string(recipe["budget"], path: path + ".budget")
    let state = try ["opacity", "offsetX", "offsetY", "scale"].map { field in
      let fallback: Double = field == "scale" ? 1 : 0
      let value = try transform[field].map { try number($0, path: path + "." + field) } ?? fallback
      return "\(field): \(literal(value))"
    }
    lines += [
      "      /// Provisional `\(path)`; preserve its source and scheduled design-pass boundary.",
      "      public static let \(name) = MotionRecipe(",
      "        id: \(String(reflecting: key)),",
      "        source: \(String(reflecting: source)),",
      "        duration: \(duration), curve: DS.Motion.Curves.\(identifier(curve)),",
    ]
    let renderedState = call("absent: ", "MotionTransform", state, indent: "        ")
    lines += renderedState.dropLast()
    if let last = renderedState.last { lines.append(last + ",") }
    lines += [
      "        reducedDuration: \(literal(reducedMs / 1000)), budget: \(String(reflecting: budget))",
      "      )",
    ]
  }
  lines += [
    "      /// Every supported simple binding, not a list of shipped product effects.",
    "      public static let catalog: [MotionRecipe] = [",
  ]
  lines += names.keys.sorted().compactMap { names[$0].map { "        \($0)," } }
  lines += [
    "      ]",
    "      /// Phase 0 state/feedback specimens, without the later Aiden reveal or entrances.",
    "      public static let phase0: [MotionRecipe] = [",
  ]
  for key in [
    "composer.focus", "hover.fill", "chip.state", "card.resolve", "disclosure.toggle",
    "message.send", "panel.toggle",
  ] {
    guard let name = names[key] else {
      throw TokenGenerationError(description: "Missing native Phase 0 recipe \(key)")
    }
    lines.append("        \(name),")
  }
  lines += ["      ]", "    }"]
  return lines
}

func elevation(_ document: [String: Any]) throws -> [String] {
  guard let elevation = document["elevation"] as? [String: Any] else {
    throw TokenGenerationError(description: "Missing elevation")
  }
  var lines = [
    "  /// Canonical opaque elevation; never layered onto glass.", "  public enum Elevation {",
  ]
  for key in elevation.keys.sorted() where key.hasPrefix("e") {
    guard let level = elevation[key] as? [String: Any] else { continue }
    lines += [
      "    /// Canonical `elevation.\(key)`.", "    public static let \(key) = DesignElevation(",
    ]
    for appearance in ["light", "dark"] {
      guard let shadows = level[appearance] as? [[String: Any]], shadows.count <= 2 else {
        throw TokenGenerationError(description: "Expected at most two shadows at elevation.\(key)")
      }
      lines.append("      \(appearance): [")
      for shadow in shadows {
        let path = "elevation.\(key).\(appearance)"
        let color = try rgba(shadow["color"], path: path + ".color")
        let scalars = try ["opacity", "radius", "x", "y"].map {
          "\($0): \(literal(try number(shadow[$0], path: path + "." + $0)))"
        }
        let rendered = call("", ".init", ["rgba: \(color)"] + scalars, indent: "        ")
        lines += rendered.dropLast()
        if let last = rendered.last { lines.append(last + ",") }
      }
      lines.append("      ],")
    }
    lines += ["      hairline: \(level["hairline"] as? Bool == true)", "    )"]
  }
  lines += ["  }"]
  guard let colors = document["color"] as? [String: Any],
    let glass = colors["glass"] as? [String: Any],
    let chrome = glass["chrome"] as? [String: Any],
    chrome["material"] as? String == "Glass.regular",
    chrome["reduceTransparency"] as? String == "surface.raised"
  else {
    throw TokenGenerationError(description: "Unsupported custom chrome material contract")
  }
  lines += [
    "  /// Closed custom functional surfaces from 03 §3 and D94; content stays opaque.",
    "  public enum Materials {",
  ]
  for (name, radius, elevation) in [
    ("composer", "composer", "e1"), ("toast", "pill", "e4"),
    ("commandPalette", "popover", "e5"), ("scrollToLatest", "pill", "e4"),
    ("identity", "pill", "e1"),
  ] {
    lines.append("    /// Provisional native `\(name)` chrome and its opaque fallback.")
    lines += call(
      "public static let \(name) = ", "DesignMaterial",
      ["name: \"\(name)\"", "radius: DS.Radius.\(radius)", "elevation: DS.Elevation.\(elevation)"],
      indent: "    ")
  }
  lines += ["  }"]
  return lines
}

func performance(_ document: [String: Any]) throws -> [String] {
  guard let performance = document["performance"] as? [String: Any],
    let frame = performance["frame"] as? [String: Any],
    let scenarios = performance["scenarios"] as? [String: Any]
  else {
    throw TokenGenerationError(description: "Missing performance frame/scenario budgets")
  }
  var lines = [
    "  /// Canonical numeric budgets, not measured results.", "  public enum Performance {",
  ]
  lines += metrics(["frame": frame], indent: "    ", path: "performance")
  lines += [
    "    /// Scenario thresholds from the design-system contract.", "    public enum Scenarios {",
  ]
  for key in scenarios.keys.sorted() {
    guard let scenario = scenarios[key] as? [String: Any] else { continue }
    let name = String(key.dropFirst("P-".count)).lowercased()
    lines += [
      "      /// Canonical `performance.scenarios.\(key)`.",
      "      public enum \(typeName(name)) {",
    ]
    lines += metrics(scenario, indent: "        ", path: "performance.scenarios.\(key)")
    lines.append("      }")
  }
  lines += ["    }", "  }"]
  return lines
}

/// Badge fill, glyph ink and on-surface foreground members for a `color.avatarState` role.
func badgeRoles(_ role: String, color: [String: Any], path: String) throws -> [String] {
  let parts = role.split(separator: ".").map(String.init)
  if parts == ["accent", "fill"] {
    return ["DS.Colors.Accent.fill", "DS.Colors.Accent.onFill", "DS.Colors.Accent.text"]
  }
  if parts.count == 2, parts[0] == "status",
    let family = (color["status"] as? [String: Any])?[parts[1]] as? [String: Any],
    family["fill"] != nil, family["onFill"] != nil, family["fg"] != nil
  {
    let member = "DS.Colors.Status.\(typeName(parts[1]))"
    return ["\(member).fill", "\(member).onFill", "\(member).fg"]
  }
  throw TokenGenerationError(description: "Unsupported badge role \(role) at \(path)")
}

/// A `color.*` role path such as `status.attention.fill` as its generated member.
func colorMember(_ role: String, color: [String: Any], path: String) throws -> String {
  let parts = role.split(separator: ".").map(String.init)
  var node: Any? = color
  for part in parts { node = (node as? [String: Any])?[part] }
  guard let leaf = parts.last, (node as? [String: Any])?["light"] != nil else {
    throw TokenGenerationError(description: "Unknown color role \(role) at \(path)")
  }
  return (["DS.Colors"] + parts.dropLast().map(typeName) + [leaf]).joined(separator: ".")
}

func avatarBadges(
  _ badgeStates: [String: Any], states: [String: Any], overlays: [String: Any],
  color: [String: Any]
) throws -> [String] {
  var lines = [
    "    /// Canonical `color.avatarState` badge glyphs and roles; idle shows no badge.",
    "    public enum `StatusBadges` {",
  ]
  for key in badgeStates.keys.sorted() where !key.hasPrefix("$") {
    let path = "color.avatarState.\(key)"
    guard let entry = badgeStates[key] as? [String: Any], let role = entry["role"] as? String
    else { continue }
    let overlay = key.hasPrefix("overlay.")
    let name = overlay ? String(key.dropFirst("overlay.".count)) : key
    guard let declared = (overlay ? overlays[name] : states[name]) as? [String: Any] else {
      throw TokenGenerationError(description: "\(path) has no avatar state or overlay")
    }
    let glyph = entry["glyph"] as? String
    guard glyph == declared["glyph"] as? String else {
      throw TokenGenerationError(description: "\(path).glyph differs from the avatar tokens")
    }
    let roles = try badgeRoles(role, color: color, path: path)
    let symbol = glyph.map { "\"\($0)\"" } ?? "nil"
    let arguments = [
      "glyph: \(symbol)", "fill: \(roles[0])", "ink: \(roles[1])", "foreground: \(roles[2])",
    ]
    lines.append("      /// Canonical `\(path)` badge.")
    lines += call(
      "public static let \(identifier(name)) = ", "AvatarBadgeStyle", arguments, indent: "      ")
    if let glow = entry["glow"] as? String {
      let member = try colorMember(glow, color: color, path: path)
      lines.append("      /// Canonical `\(path).glow` ring role.")
      lines.append("      public static let \(identifier(name + "Glow")) = \(member)")
    }
  }
  lines.append("    }")
  return lines
}

func avatar(_ document: [String: Any], references: References) throws -> [String] {
  guard let avatar = document["avatar"] as? [String: Any],
    let color = document["color"] as? [String: Any],
    let badgeStates = color["avatarState"] as? [String: Any],
    let states = avatar["states"] as? [String: Any],
    let badge = avatar["badge"] as? [String: Any],
    var face = avatar["face"] as? [String: Any],
    let ink = (face["eye"] as? [String: Any])?["ink"] as? [String: Any],
    let palette = avatar["colors"] as? [String: Any],
    let neutral = (avatar["colorRules"] as? [String: Any])?["mutedNeutral"] as? [String: Any],
    let overlays = avatar["overlays"] as? [String: Any],
    let generation = avatar["generation"] as? [String: Any],
    let concurrency = generation["concurrency"] as? [String: Any],
    let opacity = document["opacity"] as? [String: Any]
  else {
    throw TokenGenerationError(description: "Missing avatar, avatarState or opacity tokens")
  }
  let known = Set(states.keys)
  let precedence = try statusCases(
    avatar["statusPrecedence"], known: known, path: "avatar.statusPrecedence")
  guard precedence.count == known.count else {
    throw TokenGenerationError(description: "avatar.statusPrecedence must list every state")
  }
  let priority = try statusCases(
    concurrency["priority"], known: known, path: "avatar.generation.concurrency.priority")
  let maximum = try number(
    concurrency["maxAnimatingPerWindow"], path: "avatar.generation.concurrency")
  let viewBox = literal(try number(avatar["viewBox"], path: "avatar.viewBox"))
  var lines = [
    "  /// Canonical `avatar` values: original geometry, palette, face, badges and status motion.",
    "  public enum `Avatar` {",
    "    /// Canonical `avatar.viewBox` value.",
    "    public static let `viewBox`: CGFloat = \(viewBox)",
  ]
  lines += try adaptiveColor(
    "eyeInk", role: ink, warm: [:], indent: "    ", path: "avatar.face.eye.ink")
  lines += try values(["badge": badge], indent: "    ", path: "avatar", references: references)
  lines += [
    "    /// Canonical `avatar.generation.concurrency` values.",
    "    public enum `Concurrency` {",
    "      /// Canonical `avatar.generation.concurrency.maxAnimatingPerWindow` value.",
    "      public static let `maxAnimatingPerWindow` = \(literal(maximum))",
    "      /// Canonical `avatar.generation.concurrency.priority`, highest first.",
    "      public static let `priority`: [AvatarStatus] = [",
  ]
  lines += priority.map { "        \($0)," }
  lines += ["      ]", "    }"]
  face["poses"] = nil
  lines += try values(["face": face], indent: "    ", path: "avatar", references: references)
  lines += try values(
    ["overlays": overlays], indent: "    ", path: "avatar", references: references)
  let fraction = try number(opacity["mutedAvatar"], path: "opacity.mutedAvatar")
  var augmented: [String: Any] = [:]
  for (key, value) in palette where !key.hasPrefix("$") {
    guard var entry = value as? [String: Any], let fill = entry["fill"] as? [String: Any] else {
      throw TokenGenerationError(description: "Missing avatar.colors.\(key).fill")
    }
    var muted: [String: Any] = [:]
    for variant in Token.appearances {
      muted[variant] = try mixed(
        fill[variant], toward: neutral[variant], fraction: fraction,
        path: "avatar.colors.\(key).fill.\(variant)")
    }
    entry["muted"] = muted
    augmented[key] = entry
  }
  lines += [
    "    /// Canonical `avatar.colors` roles; `muted` is generated from `avatar.colorRules`.",
    "    public enum `Palette` {",
  ]
  lines += try colors(augmented, warm: [:], indent: "      ", path: "avatar.colors")
  lines += [
    "    }",
    "    /// Canonical `avatar.statusPrecedence`, highest first.",
    "    public static let `statusPrecedence`: [AvatarStatus] = [",
  ]
  lines += precedence.map { "      \($0)," }
  lines.append("    ]")
  lines += try avatarBadges(badgeStates, states: states, overlays: overlays, color: color)
  lines += try values(["states": states], indent: "    ", path: "avatar", references: references)
  lines.append("  }")
  return lines
}

func outlineArguments(_ shape: [String: Any], path: String) throws -> (String, [String]) {
  let kind = try string(shape["kind"], path: path + ".kind")
  func point(_ key: String) throws -> String {
    let value = try numbers(shape[key], count: 2, path: "\(path).\(key)").map(literal)
    return "\(key): CGPoint(x: \(value[0]), y: \(value[1]))"
  }
  func size(_ key: String) throws -> String {
    let value = try numbers(shape[key], count: 2, path: "\(path).\(key)").map(literal)
    return "\(key): CGSize(width: \(value[0]), height: \(value[1]))"
  }
  func scalar(_ key: String) throws -> String {
    "\(key): \(literal(try number(shape[key], path: "\(path).\(key)")))"
  }
  func edges(_ value: Any?, label: String) throws -> String {
    let bounds = try numbers(value, count: 4, path: "\(path).\(label)")
    let origin = "x: \(literal(bounds[0])), y: \(literal(bounds[1]))"
    let width = literal(bounds[2] - bounds[0])
    let extent = "width: \(width), height: \(literal(bounds[3] - bounds[1]))"
    return "\(label): CGRect(\(origin), \(extent))"
  }
  func pointList(_ key: String, count: Int) throws -> [[String]] {
    try (shape[key] as? [Any] ?? []).map {
      try numbers($0, count: count, path: "\(path).\(key)").map(literal)
    }
  }
  var used: Set = ["kind", "eyes"]
  let arguments: [String]
  switch kind {
  case "circle":
    arguments = [try point("center"), try scalar("radius")]
  case "superellipse":
    arguments = [try point("center"), try size("semiAxes"), try scalar("exponent")]
  case "stadium":
    let dimensions = try numbers(shape["size"], count: 2, path: path + ".size")
    let axis = try string(shape["axis"], path: path + ".axis")
    guard (axis == "vertical") == (dimensions[1] >= dimensions[0]) else {
      throw TokenGenerationError(description: "Stadium axis does not match its size at \(path)")
    }
    used.insert("axis")
    arguments = [try point("center"), try size("size")]
  case "teardrop":
    arguments = [
      try point("circleCenter"), try scalar("radius"), try point("apex"),
      try scalar("apexCornerRadius"),
    ]
  case "shield":
    let controls = try pointList("sideControls", count: 2)
    guard controls.count == 2 else {
      throw TokenGenerationError(description: "Expected two side controls at \(path)")
    }
    let points = controls.map { "CGPoint(x: \($0[0]), y: \($0[1]))" }.joined(separator: ", ")
    arguments = [
      try scalar("top"), try scalar("left"), try scalar("right"), try scalar("shoulderY"),
      try point("tip"), "sideControls: [\(points)]", try scalar("cornerRadius"),
    ]
  case "lens":
    arguments = [
      try point("center"), try scalar("length"), try scalar("width"), try scalar("rotation"),
      try scalar("tipCornerRadius"),
    ]
  case "roundedPolygon":
    arguments = [
      try point("center"), try scalar("sides"), try scalar("circumradius"),
      try scalar("startAngle"), try scalar("cornerRadius"),
    ]
  case "radialWave":
    arguments = [
      try point("center"), try scalar("baseRadius"), try scalar("amplitude"),
      try scalar("lobes"), try scalar("phase"),
    ]
  case "union":
    let circles = try pointList("circles", count: 3).map {
      "AvatarCircle(\($0.joined(separator: ", ")))"
    }
    guard let rounded = shape["roundedRect"] as? [String: Any], !circles.isEmpty else {
      throw TokenGenerationError(description: "Expected circles and a roundedRect at \(path)")
    }
    let corner = literal(try number(rounded["cornerRadius"], path: path + ".roundedRect"))
    arguments = [
      "circles: [\(circles.joined(separator: ", "))]",
      try edges(rounded["rect"], label: "roundedRect"), "roundedRectCornerRadius: \(corner)",
    ]
  case "roundedStar":
    arguments = [
      try point("center"), try scalar("points"), try scalar("outerRadius"),
      try scalar("innerRatio"), try scalar("startAngle"), try scalar("cornerRadius"),
    ]
  case "arch":
    arguments = [try edges(shape["rect"], label: "rect"), try scalar("bottomCornerRadius")]
  case "dentedEllipse":
    arguments = [
      try point("center"), try size("semiAxes"), try scalar("dentDepth"),
      try scalar("dentAngle"), try scalar("dentWidthRad"), try scalar("rotation"),
    ]
  default:
    throw TokenGenerationError(description: "Unsupported avatar shape kind \(kind) at \(path)")
  }
  for argument in arguments {
    if let label = argument.split(separator: ":").first { used.insert(String(label)) }
  }
  used.remove("roundedRectCornerRadius")
  guard Set(shape.keys) == used else {
    throw TokenGenerationError(description: "Unhandled or missing fields at \(path)")
  }
  return (kind, arguments)
}

/// A generated `switch self` property. One-element bodies are unindented expressions; longer
/// bodies are already indented for the case.
func switchProperty(doc: String, declaration: String, cases: [(String, [String])]) -> [String] {
  var lines = ["", "  /// \(doc)", "  \(declaration) {", "    switch self {"]
  for (name, body) in cases {
    if body.count == 1 {
      let line = "    case .\(name): \(body[0])"
      lines += line.count <= Token.lineLength ? [line] : ["    case .\(name):", "      \(body[0])"]
    } else {
      lines.append("    case .\(name):")
      lines += body
    }
  }
  lines += ["    }", "  }"]
  return lines
}

func shapeType(_ shapes: [String: Any]) throws -> [String] {
  var lines = [
    "",
    "/// Generated from `avatar.shapes`: original Memoshi silhouettes in a 100-unit view box.",
    "public enum AvatarShape: String, CaseIterable, Sendable {",
  ]
  var outlines: [(String, [String])] = []
  var eyes: [(String, [String])] = []
  for key in shapes.keys.sorted() where !key.hasPrefix("$") {
    let path = "avatar.shapes.\(key)"
    guard let shape = shapes[key] as? [String: Any], let eye = shape["eyes"] as? [String: Any]
    else {
      throw TokenGenerationError(description: "Missing \(path) or its eyes")
    }
    let name = camelCase(key)
    lines += ["  /// Canonical `\(path)` silhouette.", "  case \(name)"]
    let (kind, arguments) = try outlineArguments(shape, path: path)
    let indent = "      "
    let rendered = call("", "AvatarOutline.\(kind)", arguments, indent: indent)
    let body = rendered.count == 1 ? [String(rendered[0].dropFirst(indent.count))] : rendered
    outlines.append((name, body))
    let placement = try ["lineY", "spread", "scale"].map {
      "\($0): \(literal(try number(eye[$0], path: "\(path).eyes.\($0)")))"
    }
    eyes.append((name, ["AvatarEyeLine(\(placement.joined(separator: ", ")))"]))
  }
  lines += switchProperty(
    doc: "The parametric outline in view-box units, y down.",
    declaration: "var outline: AvatarOutline", cases: outlines)
  lines += switchProperty(
    doc: "Where the shared eye mark sits on this silhouette.",
    declaration: "var eyes: AvatarEyeLine", cases: eyes)
  lines.append("}")
  return lines
}

func colorType(_ palette: [String: Any]) -> [String] {
  var lines = [
    "",
    "/// Generated from `avatar.colors`: twelve original fills. Fills are never used for text.",
    "public enum AvatarColor: String, CaseIterable, Sendable {",
  ]
  let names = palette.keys.sorted().filter { !$0.hasPrefix("$") }
  for key in names {
    lines += ["  /// Canonical `avatar.colors.\(key)` fill.", "  case \(camelCase(key))"]
  }
  for (role, doc) in [
    ("fill", "The body fill."),
    ("muted", "The paused or offline body fill, generated by the muted rule."),
    ("text", "The bot-name text variant; never the fill."),
  ] {
    lines += switchProperty(
      doc: doc, declaration: "public var \(role): AdaptiveColor",
      cases: names.map { (camelCase($0), ["DS.Avatar.Palette.\(typeName($0)).\(role)"]) })
  }
  lines.append("}")
  return lines
}

func sizeType(_ sizes: [String: Any]) throws -> [String] {
  var lines = [
    "",
    "/// Generated from `avatar.sizes`, smallest first.",
    "public enum AvatarSize: String, CaseIterable, Sendable {",
  ]
  var ordered: [(points: Double, key: String, badge: Bool, loop: Double)] = []
  for key in sizes.keys where !key.hasPrefix("$") {
    let path = "avatar.sizes.\(key)"
    guard let size = sizes[key] as? [String: Any], let badge = size["badge"] as? Bool else {
      throw TokenGenerationError(description: "Missing \(path) or its badge flag")
    }
    let points = try number(size["pt"], path: path + ".pt")
    let loop = try number(size["loopFpsMax"], path: path + ".loopFpsMax")
    ordered.append((points, key, badge, loop))
  }
  ordered.sort { $0.points < $1.points }
  for size in ordered {
    lines += [
      "  /// Canonical `avatar.sizes.\(size.key)` (\(literal(size.points)) pt).",
      "  case \(size.key)",
    ]
  }
  lines += switchProperty(
    doc: "The canonical point dimension.", declaration: "public var points: CGFloat",
    cases: ordered.map { ($0.key, [literal($0.points)]) })
  lines += switchProperty(
    doc: "Whether status and unread badges render at this size.",
    declaration: "public var showsBadges: Bool",
    cases: ordered.map { ($0.key, [$0.badge ? "true" : "false"]) })
  lines += switchProperty(
    doc: "The loop frame-rate cap; zero means this size never loops.",
    declaration: "var loopFrameRateMax: Float",
    cases: ordered.map { ($0.key, [literal($0.loop)]) })
  lines.append("}")
  return lines
}

func poseType(_ poses: [String: Any]) throws -> [String] {
  var lines = [
    "",
    "/// Generated from `avatar.face.poses`: poses of the eye mark every bot shares.",
    "public enum AvatarEyePose: String, CaseIterable, Sendable {",
  ]
  var transforms: [(String, [String])] = []
  for key in poses.keys.sorted() where !key.hasPrefix("$") {
    let path = "avatar.face.poses.\(key)"
    guard let pose = poses[key] as? [String: Any],
      Set(pose.keys).isSubset(of: ["scale", "scaleY", "offsetX", "offsetY"])
    else {
      throw TokenGenerationError(description: "Missing or unhandled pose field at \(path)")
    }
    let uniform = try pose["scale"].map { try number($0, path: path + ".scale") } ?? 1
    let scaleY = try pose["scaleY"].map { try number($0, path: path + ".scaleY") } ?? uniform
    let offsetX = try pose["offsetX"].map { try number($0, path: path + ".offsetX") } ?? 0
    let offsetY = try pose["offsetY"].map { try number($0, path: path + ".offsetY") } ?? 0
    lines += ["  /// Canonical `\(path)` eye pose.", "  case \(camelCase(key))"]
    let arguments = [
      "scaleX: \(literal(uniform))", "scaleY: \(literal(scaleY))",
      "offsetX: \(literal(offsetX))", "offsetY: \(literal(offsetY))",
    ]
    transforms.append(
      (camelCase(key), ["AvatarEyeTransform(\(arguments.joined(separator: ", ")))"]))
  }
  lines += switchProperty(
    doc: "Eye scale and offset in view-box units.",
    declaration: "var transform: AvatarEyeTransform", cases: transforms)
  lines.append("}")
  return lines
}

/// Intended contrast pairs are generated and checked from one catalogue, not separate lists
/// in tests and the script. Neutral content surfaces exclude the dedicated user-bubble pair.
struct ContrastPairDefinition {
  let foreground: String
  let background: String
  let backdrop: String?
  let standard: Double
  let increased: Double

  var name: String {
    foreground + " / " + background + (backdrop.map { " @ " + $0 } ?? "")
  }
}

func contrastPairs(_ document: [String: Any]) throws -> [ContrastPairDefinition] {
  guard let color = document["color"] as? [String: Any],
    let status = color["status"] as? [String: Any],
    let avatarColors = (document["avatar"] as? [String: Any])?["colors"] as? [String: Any]
  else {
    throw TokenGenerationError(description: "Missing contrast role families")
  }
  let surfaces = [
    "surface.content", "surface.window", "surface.inspector", "surface.card",
    "surface.cardHover", "surface.well", "surface.resource", "surface.raised",
  ]
  let foregrounds =
    [
      "text.primary", "text.secondary", "text.tertiary", "text.placeholder", "accent.text",
    ] + status.keys.sorted().filter { !$0.hasPrefix("$") }.map { "status.\($0).fg" }
  var pairs = surfaces.flatMap { surface in
    foregrounds.map {
      ContrastPairDefinition(
        foreground: $0, background: surface, backdrop: nil, standard: 4.5, increased: 7)
    }
  }
  pairs += surfaces.map {
    ContrastPairDefinition(
      foreground: "border.strong", background: $0, backdrop: nil, standard: 3, increased: 3)
  }
  pairs.append(
    ContrastPairDefinition(
      foreground: "text.onUserBubble", background: "surface.userBubble", backdrop: nil,
      standard: 4.5, increased: 7))
  pairs.append(
    ContrastPairDefinition(
      foreground: "accent.onFill", background: "accent.fill", backdrop: nil,
      standard: 4.5, increased: 4.5))
  // A pressed prominent control draws `surface.hover` over its fill, under the same label.
  pairs.append(
    ContrastPairDefinition(
      foreground: "accent.onFill", background: "surface.hover", backdrop: "accent.fill",
      standard: 4.5, increased: 4.5))
  for key in status.keys.sorted() where !key.hasPrefix("$") {
    pairs += surfaces.map {
      ContrastPairDefinition(
        foreground: "status.\(key).onFill", background: "status.\(key).fill", backdrop: $0,
        standard: 4.5, increased: 4.5)
    }
  }
  // Bot-name text in the bot's own color, at the ratios `avatar.colorRules.textVariant`
  // declares, on every opaque surface a name can sit on (D127).
  for key in avatarColors.keys.sorted() where !key.hasPrefix("$") {
    pairs += surfaces.map {
      ContrastPairDefinition(
        foreground: "avatar.colors.\(key).text", background: $0, backdrop: nil,
        standard: 4.6, increased: 7)
    }
  }
  return pairs
}

func contrastCatalogue(_ document: [String: Any]) throws -> [String] {
  guard let color = document["color"] as? [String: Any] else {
    throw TokenGenerationError(description: "Missing color catalogue")
  }
  let pairs = try contrastPairs(document)
  let accentPairs = pairs.filter { $0.foreground == "accent.text" }
  guard !accentPairs.isEmpty, accentPairs.count <= 8,
    let fill = pairs.first(where: { $0.foreground == "accent.onFill" }),
    let meta = document["$meta"] as? [String: Any],
    let correction = meta["contrastCorrection"] as? [String: Any]
  else {
    throw TokenGenerationError(description: "Missing or oversized native accent contrast set")
  }
  let margin = try number(correction["ratioMargin"], path: "$meta.contrastCorrection.ratioMargin")
  for pair in accentPairs {
    let role =
      pair.background.split(separator: ".").reduce(color as Any?) {
        ($0 as? [String: Any])?[String($1)]
      } as? [String: Any]
    if let system = role?["system"] as? String,
      !["textBackgroundColor", "windowBackgroundColor"].contains(system)
    {
      throw TokenGenerationError(
        description: "Add the native input to the accent cache key: \(pair.background)")
    }
  }
  func member(_ role: String, path: String) throws -> String {
    let parts = role.split(separator: ".").map(String.init)
    if parts.count == 4, parts[0] == "avatar", parts[1] == "colors" {
      return "DS.Avatar.Palette.\(typeName(parts[2])).\(parts[3])"
    }
    return try colorMember(role, color: color, path: path)
  }
  var lines = [
    "  /// Intended role pairs from 03 §4/§11; canonical sRGB is not rendered-material proof.",
    "  public enum Contrast {",
    "    /// Quantized derivation safety margin; canonical passing fallbacks remain unchanged.",
    "    public static let derivationMargin: Double = \(literal(margin))",
    "    /// The declared contrast floor for content carried on an accent fill.",
    "    public static let accentFillMinimum: Double = \(literal(max(fill.standard, fill.increased)))",
    "    /// Every enabled-text, badge-label and strong-boundary pair checked by token lint.",
    "    public static let pairs: [DesignContrastPair] = [",
  ]
  for pair in pairs {
    var arguments = ["id: \(String(reflecting: pair.name))"]
    arguments += try [
      ("foreground", pair.foreground), ("background", pair.background),
    ].map { name, role in
      "\(name): \(try member(role, path: pair.name))"
    }
    if let backdrop = pair.backdrop {
      arguments.append("backdrop: \(try member(backdrop, path: pair.name))")
    }
    arguments += [
      "standardMinimum: \(literal(pair.standard))",
      "increasedMinimum: \(literal(pair.increased))",
    ]
    let rendered = call("", ".init", arguments, indent: "      ")
    lines += rendered.dropLast()
    if let last = rendered.last { lines.append(last + ",") }
  }
  lines += ["    ]", "  }"]
  return lines
}

/// Fallback-token contrast only. Native system color resolution and glass remain separate
/// measured review requirements. Alpha is composited before WCAG relative luminance.
func checkContrast(_ document: [String: Any]) throws {
  guard let color = document["color"] as? [String: Any],
    let warm = (document["palettes"] as? [String: Any])?["warm"] as? [String: Any]
  else {
    throw TokenGenerationError(description: "Missing contrast palettes")
  }
  func role(_ path: String, palette: String, appearance: String) throws -> [Double] {
    func lookup(_ root: [String: Any]) -> Any? {
      path.split(separator: ".").reduce(root as Any?) {
        ($0 as? [String: Any])?[String($1)]
      }
    }
    let node =
      path.hasPrefix("avatar.")
      ? lookup(document) : (palette == "warm" ? lookup(warm) : nil) ?? lookup(color)
    let value = try rgba((node as? [String: Any])?[appearance], path: path + "." + appearance)
    guard let packed = UInt32(value.dropFirst(2).replacingOccurrences(of: "_", with: ""), radix: 16)
    else {
      throw TokenGenerationError(description: "Invalid packed color \(path)")
    }
    return [24, 16, 8, 0].map { Double((packed >> $0) & 0xFF) / 255 }
  }
  func over(_ foreground: [Double], _ background: [Double]) -> [Double] {
    let alpha = foreground[3] + background[3] * (1 - foreground[3])
    guard alpha > 0 else { return foreground }
    return (0..<3).map {
      (foreground[$0] * foreground[3] + background[$0] * background[3] * (1 - foreground[3]))
        / alpha
    } + [alpha]
  }
  func luminance(_ channels: [Double]) -> Double {
    let linear = channels.prefix(3).map {
      $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
    }
    return zip(linear, [0.2126, 0.7152, 0.0722]).reduce(0) { $0 + $1.0 * $1.1 }
  }
  var failures: [String] = []
  let pairs = try contrastPairs(document)
  for palette in ["current", "warm"] {
    for appearance in Token.appearances {
      for pair in pairs {
        var background = try role(pair.background, palette: palette, appearance: appearance)
        if let backdrop = pair.backdrop {
          background = try over(
            background, role(backdrop, palette: palette, appearance: appearance))
        }
        guard background[3] == 1 else {
          failures.append("\(palette)/\(appearance): unresolved background for \(pair.name)")
          continue
        }
        let foreground = try over(
          role(pair.foreground, palette: palette, appearance: appearance), background)
        let first = luminance(foreground)
        let second = luminance(background)
        let ratio = (max(first, second) + 0.05) / (min(first, second) + 0.05)
        let minimum = appearance.hasPrefix("increased") ? pair.increased : pair.standard
        if ratio < minimum {
          failures.append(
            "\(palette)/\(appearance): \(pair.name) = \(String(format: "%.4f", ratio)):1 < \(minimum):1"
          )
        }
      }
    }
  }
  guard failures.isEmpty else {
    throw TokenGenerationError(
      description: "Canonical contrast failures:\n" + failures.joined(separator: "\n"))
  }
  print("Canonical contrast: \(pairs.count) intended role pairs × two palettes × four appearances.")
}

/// Masks comments and string literals while preserving UTF-16 offsets and newlines. Thus
/// example text, URLs, numeric labels and commented code cannot produce visual-literal hits.
func maskedSwift(_ text: String) -> String {
  let units = Array(text.utf16)
  var result = units
  var index = 0
  var blockDepth = 0
  var lineComment = false
  var quotes = 0
  while index < units.count {
    let current = units[index]
    let next = index + 1 < units.count ? units[index + 1] : 0
    func mask(_ count: Int) {
      for offset in 0..<count where index + offset < result.count {
        if result[index + offset] != 10 { result[index + offset] = 32 }
      }
    }
    if lineComment {
      if current == 10 { lineComment = false } else { mask(1) }
    } else if blockDepth > 0 {
      mask(1)
      if current == 47 && next == 42 {
        mask(2)
        blockDepth += 1
        index += 1
      } else if current == 42 && next == 47 {
        mask(2)
        blockDepth -= 1
        index += 1
      }
    } else if quotes > 0 {
      mask(1)
      if current == 92 {
        mask(2)
        index += 1
      } else if current == 34 {
        let count = units[index...].prefix { $0 == 34 }.count
        if count >= quotes {
          mask(quotes)
          index += quotes - 1
          quotes = 0
        }
      }
    } else if current == 47 && next == 47 {
      mask(2)
      lineComment = true
      index += 1
    } else if current == 47 && next == 42 {
      mask(2)
      blockDepth = 1
      index += 1
    } else if current == 34 {
      quotes = units[index...].prefix { $0 == 34 }.count >= 3 ? 3 : 1
      mask(quotes)
      index += quotes - 1
    }
    index += 1
  }
  return String(decoding: result, as: UTF16.self)
}

func checkVisualLiterals(root: URL) throws {
  let rules = try [
    (#"\bColor\s*\(\s*(?:red:|hue:|\.sRGB|[)]|nsColor:\s*\.|uiColor:\s*\.)"#, "literal color"),
    (
      #"\bColor\.(?:white|black|gray|red|green|blue|orange|yellow|purple|pink|cyan|mint|teal|indigo|brown)\b"#,
      "literal color"
    ),
    (
      #"\.(?:foregroundStyle|foregroundColor|background|fill|tint|stroke|strokeBorder)\s*\(\s*\.(?:white|black|gray|red|green|blue|orange|yellow|purple|pink|cyan|mint|teal|indigo|brown)\b"#,
      "literal color"
    ),
    (
      #"\b(?:spacing|cornerRadius|radius|minWidth|idealWidth|maxWidth|minHeight|idealHeight|maxHeight|width|height)\s*:\s*-?\d"#,
      "literal rendering metric"
    ),
    (
      #"\.(?:frame|padding|offset|scaleEffect|opacity)\s*\([^)]*(?<![A-Za-z0-9_.])\d+(?:\.\d+)?"#,
      "literal rendering expression"
    ),
    (#"\.padding\s*\(\s*(?:(?:\.[A-Za-z]+\s*,\s*)?)-?\d"#, "literal spacing"),
    (#"\.font\s*\(\s*\.system\s*\(\s*size\s*:\s*\d"#, "literal font size"),
    (
      #"\.font\s*\(\s*(?:Font\s*)?\.(?:footnote|caption2?)\b"#,
      "native text style below the functional 11 pt minimum"
    ),
    (
      #"\.font\s*\(\s*(?:Font\s*)?\.system\s*\(\s*\.(?:footnote|caption2?)\b"#,
      "native text style below the functional 11 pt minimum"
    ),
    (#"\.(?:opacity|scaleEffect)\s*\(\s*-?\d"#, "literal visual state"),
    (#"\.offset\s*\(\s*(?:x|y)\s*:\s*-?\d"#, "literal motion displacement"),
    (
      #"\.(?:timingCurve|spring|easeIn|easeOut|easeInOut|linear)\s*\(\s*(?:duration\s*:\s*)?-?\d"#,
      "literal animation duration or curve"
    ),
    (#"\bduration\s*:\s*\d"#, "literal animation duration"),
  ].map { (try NSRegularExpression(pattern: $0.0), $0.1) }
  var failures: [String] = []
  // Only rendering declarations: runtime/model/network/data bounds are not design metrics.
  // Functional view roots only; DesignSystem's explicit typography catalogue is excluded.
  // Feature targets are found by name, so a new one is linted without a change here, and a
  // root that is missing or holds no Swift source fails instead of reading as clean.
  let sources = "Packages/MemoshiApp/Sources"
  let targets =
    (try? FileManager.default.contentsOfDirectory(
      atPath: root.appendingPathComponent(sources).path)) ?? []
  let features = targets.filter { $0.hasSuffix("Feature") }.sorted().map { sources + "/" + $0 }
  guard !features.isEmpty else {
    throw TokenGenerationError(description: "No feature targets to lint under \(sources)")
  }
  for relative in features + ["apps/mac/Memoshi", "apps/ios", "apps/shared"] {
    let directory = root.appendingPathComponent(relative)
    guard
      let files = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else {
      throw TokenGenerationError(description: "Lint root cannot be read: \(relative)")
    }
    var sourceCount = 0
    for case let file as URL in files where file.pathExtension == "swift" {
      sourceCount += 1
      let source = try String(contentsOf: file, encoding: .utf8)
      let text = maskedSwift(source)
      // Any SwiftUI file can declare rendering: a style, a shape or a `some View` helper
      // conforms to none of the view protocols.
      guard
        text.range(
          of:
            #"\bimport\s+SwiftUI\b|:\s*(?:View|ViewModifier|NSViewRepresentable|UIViewRepresentable)\b"#,
          options: .regularExpression) != nil
      else {
        continue
      }
      let range = NSRange(text.startIndex..., in: text)
      for (rule, description) in rules {
        for match in rule.matches(in: text, range: range) {
          let line = text.utf16.prefix(match.range.location).filter { $0 == 10 }.count + 1
          let path = file.path.replacingOccurrences(of: root.path + "/", with: "")
          failures.append("\(path):\(line): \(description); use the generated semantic token")
        }
      }
    }
    guard sourceCount > 0 else {
      throw TokenGenerationError(
        description: "Lint root is missing or has no Swift source: \(relative)")
    }
  }
  guard failures.isEmpty else {
    throw TokenGenerationError(description: failures.sorted().joined(separator: "\n"))
  }
  print("Feature rendering uses token colors, spacings, sizes, typography, durations and curves.")
}

func generate(_ document: [String: Any]) throws -> String {
  guard let meta = document["$meta"] as? [String: Any],
    let version = meta["version"] as? String
  else {
    throw TokenGenerationError(description: "Missing $meta.version")
  }
  var lines = [
    "// Generated by scripts/design-tokens.swift from docs/specs/design-tokens.json.",
    "// Do not edit; regenerate after changing the source tokens.",
    "import SwiftUI", "",
    "/// Generated native UI values; edit the canonical JSON rather than this enum.",
    "public enum DS {",
    "  /// Canonical `$meta.version` of the provisional token source.",
    "  public static let version = \"\(version)\"",
    "  /// Adaptive semantic roles from the canonical color families.",
    "  public enum Colors {",
  ]
  guard let color = document["color"] as? [String: Any] else {
    throw TokenGenerationError(description: "Missing color roles")
  }
  guard let palettes = document["palettes"] as? [String: Any],
    let warm = palettes["warm"] as? [String: Any]
  else {
    throw TokenGenerationError(description: "Missing palettes.warm roles")
  }
  // These role families are consumed by the native surfaces and the gallery. Syntax, terminal,
  // diff, glass and tier palettes have different shapes and belong to later feature renderers.
  // Warm overrides the neutral and accent families; both palettes share the status hues.
  var roles: [(String, String)] = []
  for (key, overridden) in [
    ("accent", true), ("border", true), ("pairing", false), ("status", false),
    ("surface", true), ("text", true),
  ] {
    guard let family = color[key] as? [String: Any] else {
      throw TokenGenerationError(description: "Missing color.\(key) roles")
    }
    let warmFamily = warm[key] as? [String: Any]
    if overridden && warmFamily == nil {
      throw TokenGenerationError(description: "Missing palettes.warm.\(key) roles")
    }
    lines.append("    /// Canonical `color.\(key)` adaptive roles.")
    lines.append("    public enum \(identifier(key, type: true)) {")
    lines += try colors(family, warm: warmFamily ?? [:], indent: "      ", path: "color.\(key)")
    lines.append("    }")
    roles += colorRoles(family, path: key, member: typeName(key))
  }
  lines += [
    "    /// Every generated color role in canonical order, for galleries and theme dumps.",
    "    public static let catalog: [DesignColorRole] = [",
  ]
  lines += roles.map { "      .init(\"\($0.0)\", \($0.1))," }
  lines += ["    ]", "  }"]
  for key in ["space", "radius", "layout", "opacity"] {
    guard let group = document[key] as? [String: Any] else {
      throw TokenGenerationError(description: "Missing \(key) metrics")
    }
    lines.append("  /// Canonical `\(key)` values.")
    lines.append("  public enum \(identifier(key, type: true)) {")
    lines += metrics(group, indent: "    ", path: key, numbered: key == "space")
    if key == "space" || key == "radius" {
      var entries: [(Double, String)] = []
      for name in group.keys where !name.hasPrefix("$") {
        guard let value = group[name] as? NSNumber else { continue }
        let member = identifier(key == "space" ? "s\(name)" : name)
        entries.append((value.doubleValue, ".init(\"\(key).\(name)\", \(member)),"))
      }
      lines += [
        "    /// Every `\(key)` value in ascending order, for galleries.",
        "    public static let catalog: [DesignMetric] = [",
      ]
      let ordered = entries.sorted { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
      lines += ordered.map { "      \($0.1)" }
      lines.append("    ]")
    }
    lines.append("  }")
  }
  guard let motionTokens = document["motion"] as? [String: Any],
    let curves = motionTokens["curves"] as? [String: Any],
    let springs = motionTokens["springs"] as? [String: Any],
    let avatarTokens = document["avatar"] as? [String: Any],
    let shapes = avatarTokens["shapes"] as? [String: Any],
    let palette = avatarTokens["colors"] as? [String: Any],
    let sizes = avatarTokens["sizes"] as? [String: Any],
    let poses = (avatarTokens["face"] as? [String: Any])?["poses"] as? [String: Any]
  else {
    throw TokenGenerationError(description: "Missing motion or avatar definitions")
  }
  let references = References(
    curves: Set(curves.keys.filter { !$0.hasPrefix("$") }),
    springs: Set(springs.keys.filter { !$0.hasPrefix("$") }),
    poses: Set(poses.keys.filter { !$0.hasPrefix("$") }))
  lines += try icons(document)
  lines += try typography(document)
  lines += try motion(document)
  lines += try elevation(document)
  lines += try performance(document)
  lines += try contrastCatalogue(document)
  lines += try avatar(document, references: references)
  lines.append("}")
  lines += try shapeType(shapes)
  lines += colorType(palette)
  lines += try sizeType(sizes)
  lines += try poseType(poses)
  lines.append("")
  return lines.joined(separator: "\n")
}

/// Generation and drift checking use the same formatter as canonical source lint.
func formattedSwift(_ source: String, root: URL) throws -> String {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("memoshi-design-tokens-" + UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(
    at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("GeneratedTokens.swift")
  try source.write(to: file, atomically: true, encoding: .utf8)
  let formatter = Process()
  formatter.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
  formatter.arguments = [
    "swift-format", "format", "--in-place", "--configuration",
    root.appendingPathComponent(".swift-format").path, file.path,
  ]
  try formatter.run()
  formatter.waitUntilExit()
  guard formatter.terminationReason == .exit, formatter.terminationStatus == 0 else {
    throw TokenGenerationError(description: "Canonical generated Swift formatting failed")
  }
  return try String(contentsOf: file, encoding: .utf8)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
do {
  let input = root.appendingPathComponent("docs/specs/design-tokens.json")
  let output = root.appendingPathComponent(
    "Packages/MemoshiApp/Sources/DesignSystem/GeneratedTokens.swift")
  let data = try Data(contentsOf: input)
  guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    throw TokenGenerationError(description: "Token source is not an object")
  }
  let options = Set(CommandLine.arguments.dropFirst())
  if options.contains("--contrast-check") {
    try checkContrast(document)
  } else if options.contains("--lint") {
    try checkVisualLiterals(root: root)
  } else {
    let generated = try formattedSwift(generate(document), root: root)
    if options.contains("--check") {
      guard try String(contentsOf: output, encoding: .utf8) == generated else {
        throw TokenGenerationError(
          description: "Design tokens drifted; run swift scripts/design-tokens.swift")
      }
      print("Design token Swift matches its JSON source.")
      try checkContrast(document)
      try checkVisualLiterals(root: root)
    } else {
      try generated.write(to: output, atomically: true, encoding: .utf8)
      print("Generated \(output.lastPathComponent) from design-tokens.json.")
    }
  }
} catch {
  FileHandle.standardError.write(Data("error: \(error)\n".utf8))
  exit(1)
}
