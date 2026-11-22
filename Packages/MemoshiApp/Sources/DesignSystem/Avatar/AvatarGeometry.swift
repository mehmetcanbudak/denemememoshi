import CoreGraphics
import Foundation

/// Parametric silhouettes generated from `avatar.shapes`, in view-box units with y down.
enum AvatarOutline {
  case arch(rect: CGRect, bottomCornerRadius: CGFloat)
  case circle(center: CGPoint, radius: CGFloat)
  case dentedEllipse(
    center: CGPoint, semiAxes: CGSize, dentDepth: CGFloat, dentAngle: CGFloat,
    dentWidthRad: CGFloat, rotation: CGFloat)
  case lens(
    center: CGPoint, length: CGFloat, width: CGFloat, rotation: CGFloat,
    tipCornerRadius: CGFloat)
  case radialWave(
    center: CGPoint, baseRadius: CGFloat, amplitude: CGFloat, lobes: Int, phase: CGFloat)
  case roundedPolygon(
    center: CGPoint, sides: Int, circumradius: CGFloat, startAngle: CGFloat,
    cornerRadius: CGFloat)
  case roundedStar(
    center: CGPoint, points: Int, outerRadius: CGFloat, innerRatio: CGFloat,
    startAngle: CGFloat, cornerRadius: CGFloat)
  case shield(
    top: CGFloat, left: CGFloat, right: CGFloat, shoulderY: CGFloat, tip: CGPoint,
    sideControls: [CGPoint], cornerRadius: CGFloat)
  case stadium(center: CGPoint, size: CGSize)
  case superellipse(center: CGPoint, semiAxes: CGSize, exponent: CGFloat)
  case teardrop(circleCenter: CGPoint, radius: CGFloat, apex: CGPoint, apexCornerRadius: CGFloat)
  case union(circles: [AvatarCircle], roundedRect: CGRect, roundedRectCornerRadius: CGFloat)
}

/// One circle of a union silhouette.
struct AvatarCircle {
  let center: CGPoint
  let radius: CGFloat

  init(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
    center = CGPoint(x: x, y: y)
    self.radius = radius
  }
}

/// Where the shared eye mark sits: the eye-center line, the distance between eye centers and a
/// uniform eye scale, all in view-box units.
struct AvatarEyeLine {
  let lineY: CGFloat
  let spread: CGFloat
  let scale: CGFloat
}

/// An eye pose in view-box units: offsets move both eyes, scales apply to each eye.
struct AvatarEyeTransform: Equatable {
  let scaleX: CGFloat
  let scaleY: CGFloat
  let offsetX: CGFloat
  let offsetY: CGFloat
}

/// Caches parametric silhouettes per shape, point size and small-avatar backing scale.
@MainActor
enum AvatarPaths {
  private struct Key: Hashable {
    let shape: AvatarShape
    let points: CGFloat
    let pixelScale: CGFloat?
  }

  private static var bodies: [Key: CGPath] = [:]

  /// Silhouettes at <=20pt snap their path points to the backing-pixel grid (03 §10.8).
  static func body(_ shape: AvatarShape, points: CGFloat, displayScale: CGFloat) -> CGPath {
    let pixelScale = AvatarMetrics.pixelScale(points: points, displayScale: displayScale)
    let key = Key(shape: shape, points: points, pixelScale: pixelScale)
    if let cached = bodies[key] { return cached }
    let unit = points / DS.Avatar.viewBox
    var scale = CGAffineTransform(scaleX: unit, y: unit)
    let outline = shape.outline.path()
    let scaled = outline.copy(using: &scale) ?? outline
    let path = pixelScale.map { snapped(scaled, scale: $0) } ?? scaled
    bodies[key] = path
    return path
  }

  private static func snapped(_ source: CGPath, scale: CGFloat) -> CGPath {
    let path = CGMutablePath()
    source.applyWithBlock { pointer in
      let element = pointer.pointee
      func point(_ index: Int) -> CGPoint {
        let value = element.points[index]
        return CGPoint(
          x: (value.x * scale).rounded() / scale, y: (value.y * scale).rounded() / scale)
      }
      switch element.type {
      case .moveToPoint: path.move(to: point(0))
      case .addLineToPoint: path.addLine(to: point(0))
      case .addQuadCurveToPoint: path.addQuadCurve(to: point(1), control: point(0))
      case .addCurveToPoint:
        path.addCurve(to: point(2), control1: point(0), control2: point(1))
      case .closeSubpath: path.closeSubpath()
      @unknown default: preconditionFailure("Unsupported avatar path element")
      }
    }
    return path
  }
}

extension AvatarOutline {
  /// The silhouette in view-box units.
  func path() -> CGPath {
    switch self {
    case .arch(let rect, let corner):
      return Self.arch(rect, corner: corner)
    case .circle(let center, let radius):
      return CGPath(
        ellipseIn: CGRect(
          x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
        transform: nil)
    case .dentedEllipse(let center, let axes, let depth, let angle, let width, let rotation):
      return Self.dentedEllipse(
        center: center, axes: axes, depth: depth, dentAngle: angle, dentWidth: width,
        rotation: rotation)
    case .lens(let center, let length, let width, let rotation, let tipRadius):
      return Self.lens(
        center: center, length: length, width: width, rotation: rotation, tipRadius: tipRadius)
    case .radialWave(let center, let base, let amplitude, let lobes, let phase):
      return Self.radialWave(
        center: center, base: base, amplitude: amplitude, lobes: lobes, phase: phase)
    case .roundedPolygon(let center, let sides, let radius, let start, let corner):
      let vertices = (0..<sides).map { index in
        Self.point(
          center, radius: radius,
          angle: Self.radians(start) + 2 * .pi * CGFloat(index) / CGFloat(sides))
      }
      return Self.rounded(vertices, radius: corner)
    case .roundedStar(let center, let points, let outer, let ratio, let start, let corner):
      let vertices = (0..<(points * 2)).map { index in
        Self.point(
          center, radius: index.isMultiple(of: 2) ? outer : outer * ratio,
          angle: Self.radians(start) + .pi * CGFloat(index) / CGFloat(points))
      }
      return Self.rounded(vertices, radius: corner)
    case .shield(let top, let left, let right, let shoulder, let tip, let controls, let corner):
      return Self.shield(
        top: top, left: left, right: right, shoulder: shoulder, tip: tip, controls: controls,
        corner: corner)
    case .stadium(let center, let size):
      let rect = CGRect(
        x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width,
        height: size.height)
      let corner = min(size.width, size.height) / 2
      return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    case .superellipse(let center, let axes, let exponent):
      return Self.superellipse(center: center, axes: axes, exponent: exponent)
    case .teardrop(let center, let radius, let apex, let apexRadius):
      return Self.teardrop(center: center, radius: radius, apex: apex, apexRadius: apexRadius)
    case .union(let circles, let rect, let corner):
      var combined = CGPath(
        roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
      for circle in circles {
        let bounds = CGRect(
          x: circle.center.x - circle.radius, y: circle.center.y - circle.radius,
          width: circle.radius * 2, height: circle.radius * 2)
        combined = combined.union(CGPath(ellipseIn: bounds, transform: nil))
      }
      return combined
    }
  }

  private static func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

  private static func point(_ center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
    CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
  }

  /// A closed polygon whose corners are rounded with tangent arcs.
  private static func rounded(_ vertices: [CGPoint], radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    guard let last = vertices.last, let first = vertices.first else { return path }
    path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
    for (index, corner) in vertices.enumerated() {
      let next = vertices[(index + 1) % vertices.count]
      path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
    }
    path.closeSubpath()
    return path
  }

  /// A closed outline through sampled points; dense enough to read as smooth at 96 pt.
  private static func sampled(_ count: Int, _ point: (CGFloat) -> CGPoint) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: (0..<count).map { point(2 * .pi * CGFloat($0) / CGFloat(count)) })
    path.closeSubpath()
    return path
  }

  private static func arch(_ rect: CGRect, corner: CGFloat) -> CGPath {
    let radius = rect.width / 2
    let shoulder = rect.minY + radius
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: shoulder))
    path.addArc(
      center: CGPoint(x: rect.midX, y: shoulder), radius: radius, startAngle: .pi,
      endAngle: 2 * .pi, clockwise: false)
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
      tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: corner)
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
      tangent2End: CGPoint(x: rect.minX, y: shoulder), radius: corner)
    path.closeSubpath()
    return path
  }

  private static func superellipse(center: CGPoint, axes: CGSize, exponent: CGFloat) -> CGPath {
    let power = 2 / exponent
    return sampled(144) { angle in
      let x = cos(angle)
      let y = sin(angle)
      return CGPoint(
        x: center.x + axes.width * (x < 0 ? -1 : 1) * pow(abs(x), power),
        y: center.y + axes.height * (y < 0 ? -1 : 1) * pow(abs(y), power))
    }
  }

  private static func radialWave(
    center: CGPoint, base: CGFloat, amplitude: CGFloat, lobes: Int, phase: CGFloat
  ) -> CGPath {
    sampled(lobes * 24) { angle in
      let radius = base + amplitude * cos(CGFloat(lobes) * (angle - radians(phase)))
      return point(center, radius: radius, angle: angle)
    }
  }

  /// An ellipse with a raised-cosine dent of half-width `dentWidth` radians, then rotated.
  private static func dentedEllipse(
    center: CGPoint, axes: CGSize, depth: CGFloat, dentAngle: CGFloat, dentWidth: CGFloat,
    rotation: CGFloat
  ) -> CGPath {
    let dent = radians(dentAngle)
    let local = sampled(144) { angle in
      let x = axes.width * cos(angle)
      let y = axes.height * sin(angle)
      let distance = atan2(sin(angle - dent), cos(angle - dent))
      let weight = abs(distance) < dentWidth ? (1 + cos(.pi * distance / dentWidth)) / 2 : 0
      let length = max(hypot(x, y), .ulpOfOne)
      let inset = depth * weight / length
      return CGPoint(x: x - x * inset, y: y - y * inset)
    }
    var transform = CGAffineTransform(translationX: center.x, y: center.y)
      .rotated(by: radians(rotation))
    return local.copy(using: &transform) ?? local
  }

  /// Two circular arcs meeting at tips rounded by tangent circles, then rotated.
  private static func lens(
    center: CGPoint, length: CGFloat, width: CGFloat, rotation: CGFloat, tipRadius: CGFloat
  ) -> CGPath {
    let halfLength = length / 2
    let halfWidth = width / 2
    let radius = (halfLength * halfLength + halfWidth * halfWidth) / (2 * halfWidth)
    let offset = radius - halfWidth
    let tip = sqrt(max((radius - tipRadius) * (radius - tipRadius) - offset * offset, 0))
    let angle = atan2(offset, tip)
    let path = CGMutablePath()
    path.addArc(
      center: CGPoint(x: 0, y: offset), radius: radius, startAngle: angle - .pi,
      endAngle: -angle, clockwise: false)
    path.addArc(
      center: CGPoint(x: tip, y: 0), radius: tipRadius, startAngle: -angle, endAngle: angle,
      clockwise: false)
    path.addArc(
      center: CGPoint(x: 0, y: -offset), radius: radius, startAngle: angle,
      endAngle: .pi - angle, clockwise: false)
    path.addArc(
      center: CGPoint(x: -tip, y: 0), radius: tipRadius, startAngle: .pi - angle,
      endAngle: .pi + angle, clockwise: false)
    path.closeSubpath()
    var transform = CGAffineTransform(translationX: center.x, y: center.y)
      .rotated(by: radians(rotation))
    return path.copy(using: &transform) ?? path
  }

  /// A circle joined to an apex by tangent lines, with a rounded apex.
  private static func teardrop(
    center: CGPoint, radius: CGFloat, apex: CGPoint, apexRadius: CGFloat
  ) -> CGPath {
    let toApex = atan2(apex.y - center.y, apex.x - center.x)
    let distance = hypot(apex.x - center.x, apex.y - center.y)
    let spread = acos(min(radius / distance, 1))
    let leading = point(center, radius: radius, angle: toApex - spread)
    let trailing = point(center, radius: radius, angle: toApex + spread)
    let path = CGMutablePath()
    path.move(to: leading)
    path.addArc(tangent1End: apex, tangent2End: trailing, radius: apexRadius)
    path.addLine(to: trailing)
    path.addArc(
      center: center, radius: radius, startAngle: toApex + spread,
      endAngle: toApex - spread + 2 * .pi, clockwise: false)
    path.closeSubpath()
    return path
  }

  /// A flat top with rounded corners, straight shoulders and quadratic sides to the tip.
  private static func shield(
    top: CGFloat, left: CGFloat, right: CGFloat, shoulder: CGFloat, tip: CGPoint,
    controls: [CGPoint], corner: CGFloat
  ) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: (left + right) / 2, y: top))
    path.addArc(
      tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: shoulder),
      radius: corner)
    path.addLine(to: CGPoint(x: right, y: shoulder))
    if controls.count == 2 {
      path.addQuadCurve(to: tip, control: controls[0])
      path.addQuadCurve(to: CGPoint(x: left, y: shoulder), control: controls[1])
    } else {
      path.addLine(to: tip)
      path.addLine(to: CGPoint(x: left, y: shoulder))
    }
    path.addArc(
      tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: (left + right) / 2, y: top),
      radius: corner)
    path.closeSubpath()
    return path
  }
}
