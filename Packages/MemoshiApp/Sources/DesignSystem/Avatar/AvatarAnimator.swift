import Foundation
import QuartzCore

/// Resolved inputs for one avatar's layer tree. Equal configurations skip all layer work.
struct AvatarLayerConfiguration: Equatable {
  var shape: AvatarShape
  var points: CGFloat
  var loopFrameRateMax: Float
  var status: AvatarStatus
  var takenOver: Bool
  var offline: Bool
  var fill: CGColor
  var mutedFill: CGColor
  var edge: CGColor
  var edgeWidth: CGFloat
  var eyeInk: CGColor
  var glow: CGColor
  var sparkle: CGColor
  var statusHole: Bool
  var unreadHole: Bool
  var rightToLeft: Bool
  var reduceMotion: Bool
  var isOnScreen: Bool
  var displayScale: CGFloat
  var botID: String
}

/// Shared avatar measurements derived from the badge tokens.
enum AvatarMetrics {
  /// Small silhouettes use backing-pixel geometry; larger silhouettes preserve their curves.
  static func pixelScale(points: CGFloat, displayScale: CGFloat) -> CGFloat? {
    points <= 20 ? max(displayScale, 1) : nil
  }

  /// Status and unread badge diameter for an avatar size.
  static func badgeDiameter(points: CGFloat) -> CGFloat {
    max(points * DS.Avatar.Badge.diameterFraction, DS.Avatar.Badge.minDiameter)
  }

  /// A stable 0..<1 loop phase per bot, so a roster never moves in unison.
  static func phase(for botID: String) -> CGFloat {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in botID.utf8 {
      hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
    }
    return CGFloat(hash % 1_000) / 1_000
  }
}

/// Grants avatar motion per window, highest status priority first (03 §10.8). Loops and
/// one-shots share the cap; overflow keeps the still pose and badge.
@MainActor
final class AvatarMotionBudget {
  private struct Entry {
    weak var animator: AvatarAnimator?
    let rank: Int
    let order: Int
  }

  private struct Registration {
    weak var window: AnyObject?
    let budget: AvatarMotionBudget
  }

  private static var registry: [ObjectIdentifier: Registration] = [:]

  private var entries: [ObjectIdentifier: Entry] = [:]
  private var granted: Set<ObjectIdentifier> = []
  private var nextOrder = 0

  /// The window's budget; registrations of closed windows are dropped when another opens.
  static func budget(for window: AnyObject) -> AvatarMotionBudget {
    let key = ObjectIdentifier(window)
    if let registration = registry[key], registration.window === window {
      return registration.budget
    }
    registry = registry.filter { $0.value.window != nil }
    let budget = AvatarMotionBudget()
    registry[key] = Registration(window: window, budget: budget)
    return budget
  }

  /// Records whether `animator` requests motion at `rank` (`nil` releases it) and returns
  /// its grant. Other animators whose grant changes are told directly.
  func request(_ animator: AvatarAnimator, rank: Int?) -> Bool {
    let id = ObjectIdentifier(animator)
    if let rank {
      if entries[id]?.rank != rank {
        entries[id] = Entry(animator: animator, rank: rank, order: nextOrder)
        nextOrder += 1
      }
    } else if entries[id] == nil {
      return false
    } else {
      entries[id] = nil
    }
    entries = entries.filter { $0.value.animator != nil }
    let ordered = entries.sorted {
      ($0.value.rank, $0.value.order) < ($1.value.rank, $1.value.order)
    }
    let next = Set(ordered.prefix(DS.Avatar.Concurrency.maxAnimatingPerWindow).map(\.key))
    let changed = next.symmetricDifference(granted)
    granted = next
    for other in changed where other != id {
      entries[other]?.animator?.motionGrantDidChange(next.contains(other))
    }
    return next.contains(id)
  }
}

/// One avatar's Core Animation layer tree. The still pose is drawn once per state change;
/// loops and one-shots are render-server keyframes, so running motion costs no main-thread
/// work per frame (budget B0). Motion carries status only and stops for Reduce Motion, Low
/// Power Mode (loops), hidden windows, off-screen scrolling and the per-window budget.
@MainActor
final class AvatarAnimator {
  /// The root layer the host view installs; flipped on macOS so geometry is y-down everywhere.
  let container = CALayer()

  private let masked = CALayer()
  private let holes = CAShapeLayer()
  private let motion = CALayer()
  private let glow = CAShapeLayer()
  private let body = CAShapeLayer()
  private let eyes = CALayer()
  private let leftEye = CAShapeLayer()
  private let rightEye = CAShapeLayer()
  private let sparkle = CAShapeLayer()

  private static var lastCheer: [String: CFTimeInterval] = [:]

  private var configuration: AvatarLayerConfiguration?
  private var bounds = CGRect.zero
  private var isVisible = false
  private var lowPower = false
  private var budget: AvatarMotionBudget?
  private var loopsRunning = false
  private var oneShotActive = false
  private var oneShotDuration: TimeInterval = 0
  private var oneShotGeneration: UInt64 = 0
  private var oneShotCompletion: Task<Void, Never>?

  init(flipped: Bool) {
    container.isGeometryFlipped = flipped
    container.addSublayer(masked)
    container.addSublayer(sparkle)
    masked.mask = holes
    masked.addSublayer(motion)
    motion.addSublayer(glow)
    motion.addSublayer(body)
    motion.addSublayer(eyes)
    eyes.addSublayer(leftEye)
    eyes.addSublayer(rightEye)
    holes.fillRule = .evenOdd
    glow.fillColor = nil
    glow.lineJoin = .round
    sparkle.opacity = 0
    motion.anchorPoint = CGPoint(x: 0.5, y: 1)
  }

  /// Applies a new SwiftUI configuration; a status change may play its one-shot.
  func configure(_ next: AvatarLayerConfiguration) {
    guard next != configuration else { return }
    let previous = configuration
    configuration = next
    apply(previous: previous)
  }

  /// Applies window visibility, Low Power Mode and the window's motion budget.
  func environmentDidChange(window: AnyObject?, visible: Bool, lowPower: Bool) {
    let nextBudget = window.map { AvatarMotionBudget.budget(for: $0) }
    guard visible != isVisible || lowPower != self.lowPower || nextBudget !== budget else {
      return
    }
    if nextBudget !== budget {
      _ = budget?.request(self, rank: nil)
      budget = nextBudget
    }
    isVisible = visible
    self.lowPower = lowPower
    apply(previous: configuration)
  }

  /// Releases the budget slot when the host leaves its window or is dismantled.
  func detach() {
    stopOneShot()
    _ = budget?.request(self, rank: nil)
    budget = nil
    setLoops(false)
  }

  func layout(in bounds: CGRect) {
    guard bounds != self.bounds else { return }
    self.bounds = bounds
    withoutImplicitAnimation {
      container.frame = bounds
      if let configuration { layoutGeometry(configuration) }
    }
  }

  /// A preempted one-shot never replays; its bounded reservation expires at its original end.
  func motionGrantDidChange(_ granted: Bool) {
    setLoops(granted && wantsLoops)
    if !granted { removeAnimations(prefix: "once.") }
  }

  // MARK: - State

  private func apply(previous: AvatarLayerConfiguration?) {
    guard let configuration else { return }
    let statusChanged = previous.map { $0.status != configuration.status } ?? false
    withoutImplicitAnimation {
      if Self.changesGeometry(from: previous, to: configuration) {
        container.frame = bounds
        layoutGeometry(configuration)
      }
      applyStill(configuration)
    }
    if statusChanged || !allowsMotion { stopOneShot() }
    if Self.restartsLoops(from: previous, to: configuration) {
      setLoops(false)
    }
    let hasTransition: Bool
    switch configuration.status {
    case .error, .needsYou, .hasNews, .paused: hasTransition = true
    case .idle, .working, .asleep, .watching: hasTransition = previous?.status == .asleep
    }
    let startsOneShot = statusChanged && allowsMotion && hasTransition
    if startsOneShot { oneShotActive = true }
    let granted = updateMotionBudget()
    if startsOneShot {
      if granted, let previous {
        playTransition(from: previous.status, to: configuration)
        finishOneShotAfterDuration()
      } else {
        stopOneShot()
        _ = updateMotionBudget()
      }
    }
  }

  private var allowsMotion: Bool {
    guard let configuration else { return false }
    return isVisible && configuration.isOnScreen && !configuration.reduceMotion
      && configuration.loopFrameRateMax > 0 && !configuration.takenOver && !configuration.offline
  }

  private var wantsLoops: Bool {
    allowsMotion && !lowPower && (configuration?.status.hasLoop ?? false)
  }

  @discardableResult
  private func updateMotionBudget() -> Bool {
    guard let configuration else { return false }
    let rank = wantsLoops || oneShotActive ? configuration.status.animationRank : nil
    let granted = budget?.request(self, rank: rank) ?? false
    setLoops(wantsLoops && granted)
    if !granted { removeAnimations(prefix: "once.") }
    return granted
  }

  private func stopOneShot() {
    guard oneShotActive || oneShotCompletion != nil else { return }
    oneShotGeneration &+= 1
    oneShotCompletion?.cancel()
    oneShotCompletion = nil
    oneShotActive = false
    oneShotDuration = 0
    removeAnimations(prefix: "once.")
  }

  private func finishOneShotAfterDuration() {
    guard oneShotDuration > 0 else {
      stopOneShot()
      _ = updateMotionBudget()
      return
    }
    let duration = oneShotDuration
    let generation = oneShotGeneration
    oneShotCompletion = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(duration)) } catch { return }
      guard let self, self.oneShotGeneration == generation else { return }
      self.oneShotCompletion = nil
      self.oneShotActive = false
      self.oneShotDuration = 0
      self.removeAnimations(prefix: "once.")
      _ = self.updateMotionBudget()
    }
  }

  /// Loop values depend on status, size, direction and the bot's phase.
  private static func restartsLoops(
    from previous: AvatarLayerConfiguration?, to next: AvatarLayerConfiguration
  ) -> Bool {
    guard let previous else { return false }
    return previous.status != next.status || previous.points != next.points
      || previous.rightToLeft != next.rightToLeft || previous.botID != next.botID
  }

  /// Paths, eye placement, badge holes and the sparkle depend only on these inputs.
  private static func changesGeometry(
    from previous: AvatarLayerConfiguration?, to next: AvatarLayerConfiguration
  ) -> Bool {
    guard let previous else { return true }
    return previous.shape != next.shape || previous.points != next.points
      || previous.statusHole != next.statusHole || previous.unreadHole != next.unreadHole
      || previous.rightToLeft != next.rightToLeft || previous.displayScale != next.displayScale
  }

  private func applyStill(_ configuration: AvatarLayerConfiguration) {
    let pose = configuration.status.stillPose.transform
    let unit = configuration.points / DS.Avatar.viewBox
    let direction: CGFloat = configuration.rightToLeft ? -1 : 1
    let muted = configuration.status == .paused || configuration.offline
    body.fillColor = muted ? configuration.mutedFill : configuration.fill
    body.strokeColor = configuration.edge
    body.lineWidth = configuration.edgeWidth
    leftEye.fillColor = configuration.eyeInk
    rightEye.fillColor = configuration.eyeInk
    eyes.transform = CATransform3DMakeTranslation(
      pose.offsetX * unit * direction, pose.offsetY * unit, 0)
    let eyeScale = CATransform3DMakeScale(pose.scaleX, pose.scaleY, 1)
    leftEye.transform = eyeScale
    rightEye.transform = eyeScale
    glow.isHidden = configuration.status != .needsYou
    glow.strokeColor = configuration.glow
    glow.opacity = Float(DS.Avatar.States.NeedsYou.Loop.glowOpacity.first ?? 1)
    motion.opacity = configuration.offline ? Float(DS.Avatar.Overlays.Offline.opacity) : 1
    sparkle.fillColor = configuration.sparkle
    for layer in [container, masked, holes, motion, glow, body, eyes, leftEye, rightEye, sparkle] {
      layer.contentsScale = configuration.displayScale
    }
  }

  private func layoutGeometry(_ configuration: AvatarLayerConfiguration) {
    let size = configuration.points
    let unit = size / DS.Avatar.viewBox
    let pixelScale = AvatarMetrics.pixelScale(
      points: size, displayScale: configuration.displayScale)
    func snapped(_ value: CGFloat) -> CGFloat {
      pixelScale.map { (value * $0).rounded() / $0 } ?? value
    }
    let origin = CGPoint(
      x: snapped((bounds.width - size) / 2), y: snapped((bounds.height - size) / 2))
    let content = CGRect(origin: .zero, size: CGSize(width: size, height: size))
    masked.frame = container.bounds
    holes.frame = container.bounds
    motion.bounds = content
    motion.position = CGPoint(x: origin.x + size / 2, y: origin.y + size)
    let outline = AvatarPaths.body(
      configuration.shape, points: size, displayScale: configuration.displayScale)
    body.frame = content
    body.path = outline
    glow.frame = content
    glow.path = outline
    let glowLoop = DS.Avatar.States.NeedsYou.Loop.self
    let ringWidth = max(size * glowLoop.ringWidthFraction, glowLoop.ringMin)
    // The ring strokes the outline beneath the body, so only its outer half shows.
    glow.lineWidth = ringWidth * 2
    eyes.frame = content
    let line = configuration.shape.eyes
    let rawWidth = max(
      DS.Avatar.Face.Eye.width * line.scale * unit, DS.Avatar.Face.MinEyeSize.width)
    let rawHeight = max(
      DS.Avatar.Face.Eye.height * line.scale * unit, DS.Avatar.Face.MinEyeSize.height)
    let width = pixelScale.map { ceil(rawWidth * $0) / $0 } ?? rawWidth
    let height = pixelScale.map { ceil(rawHeight * $0) / $0 } ?? rawHeight
    let corner = min(DS.Avatar.Face.Eye.cornerRadius * line.scale * unit, width / 2, height / 2)
    let eyePath = CGPath(
      roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerWidth: corner,
      cornerHeight: corner, transform: nil)
    for (eye, side) in [(leftEye, CGFloat(-1)), (rightEye, CGFloat(1))] {
      eye.bounds = CGRect(x: 0, y: 0, width: width, height: height)
      let centerX = (DS.Avatar.viewBox / 2 + side * line.spread / 2) * unit
      eye.position = CGPoint(
        x: snapped(centerX - width / 2) + width / 2,
        y: snapped(line.lineY * unit - height / 2) + height / 2)
      eye.path = eyePath
    }
    let diameter = AvatarMetrics.badgeDiameter(points: size)
    let ring = DS.Avatar.Badge.cutoutRing
    let trailingX = configuration.rightToLeft ? origin.x : origin.x + size - diameter
    let mask = CGMutablePath()
    mask.addRect(container.bounds.insetBy(dx: -size, dy: -size))
    if configuration.statusHole {
      let badge = CGRect(
        x: trailingX, y: origin.y + size - diameter, width: diameter, height: diameter)
      mask.addEllipse(in: badge.insetBy(dx: -ring, dy: -ring))
    }
    if configuration.unreadHole {
      let badge = CGRect(x: trailingX, y: origin.y, width: diameter, height: diameter)
      mask.addEllipse(in: badge.insetBy(dx: -ring, dy: -ring))
    }
    holes.path = mask
    let sparkleSize = diameter * DS.Avatar.Badge.glyphFraction
    let shift = configuration.unreadHole ? (configuration.rightToLeft ? diameter : -diameter) : 0
    sparkle.bounds = CGRect(x: 0, y: 0, width: sparkleSize, height: sparkleSize)
    sparkle.position = CGPoint(x: trailingX + diameter / 2 + shift, y: origin.y + diameter / 2)
    sparkle.path = Self.sparklePath(size: sparkleSize)
  }

  /// The original four-point sparkle mark used by the has-news cheer.
  private static func sparklePath(size: CGFloat) -> CGPath {
    let radius = size / 2
    let waist = radius * (1 - DS.Avatar.Badge.glyphFraction) / 2
    let points = (0..<8).map { index in
      let angle = CGFloat(index) * .pi / 4 - .pi / 2
      let length = index.isMultiple(of: 2) ? radius : waist
      return CGPoint(x: radius + length * cos(angle), y: radius + length * sin(angle))
    }
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
  }

  // MARK: - Loops

  private func setLoops(_ running: Bool) {
    guard running != loopsRunning else { return }
    loopsRunning = running
    removeAnimations(prefix: "loop.")
    if running, let configuration { addLoops(configuration) }
  }

  private func addLoops(_ configuration: AvatarLayerConfiguration) {
    let unit = configuration.points / DS.Avatar.viewBox
    let direction: CGFloat = configuration.rightToLeft ? -1 : 1
    let phase = AvatarMetrics.phase(for: configuration.botID)
    let sizeRate = configuration.loopFrameRateMax
    switch configuration.status {
    case .working:
      let loop = DS.Avatar.States.Working.Loop.self
      let glance = DS.Avatar.States.Working.Eyes.self
      let period = Self.seconds(loop.periodMs)
      let squash = loop.bodySquash
      run(
        Self.keyframes(
          "transform.translation.y", loop.bodyOffsetY, scale: unit, rest: 0, curve: loop.curve),
        on: motion, key: "loop.body.y", period: period, phase: phase, rate: sizeRate)
      run(
        Self.keyframes(
          "transform.scale.x", squash.map { AvatarKeyframe($0.time, $0.scaleX) }, scale: 1,
          rest: 1, curve: loop.curve),
        on: motion, key: "loop.body.scaleX", period: period, phase: phase, rate: sizeRate)
      run(
        Self.keyframes(
          "transform.scale.y", squash.map { AvatarKeyframe($0.time, $0.scaleY) }, scale: 1,
          rest: 1, curve: loop.curve),
        on: motion, key: "loop.body.scaleY", period: period, phase: phase, rate: sizeRate)
      let glancePeriod = Self.seconds(glance.periodMs)
      run(
        Self.keyframes(
          "transform.translation.x", glance.offsetX, scale: unit * direction, rest: 0,
          curve: glance.curve),
        on: eyes, key: "loop.eyes.x", period: glancePeriod, phase: phase, rate: sizeRate)
      for eye in [leftEye, rightEye] {
        run(
          Self.keyframes(
            "transform.scale.y", glance.blinkScaleY, scale: 1, rest: 1, curve: glance.curve),
          on: eye, key: "loop.blink", period: glancePeriod, phase: phase, rate: sizeRate)
      }
    case .needsYou:
      let loop = DS.Avatar.States.NeedsYou.Loop.self
      let breath = CABasicAnimation(keyPath: "opacity")
      breath.fromValue = loop.glowOpacity.first ?? 1
      breath.toValue = loop.glowOpacity.last ?? 1
      breath.autoreverses = true
      breath.timingFunction = loop.curve.timingFunction
      run(
        breath, on: glow, key: "loop.glow", period: Self.seconds(loop.periodMs) / 2,
        phase: phase, rate: min(sizeRate, Float(loop.fpsMax)))
    case .watching:
      let loop = DS.Avatar.States.Watching.Loop.self
      let period = Self.seconds(loop.periodMs)
      let rate = min(sizeRate, Float(loop.fpsMax))
      run(
        Self.keyframes(
          "transform.translation.x", loop.eyesOffsetX, scale: unit * direction, rest: 0,
          curve: loop.curve),
        on: eyes, key: "loop.eyes.x", period: period, phase: phase, rate: rate)
      run(
        Self.keyframes(
          "transform.rotation.z", loop.bodyRotation, scale: .pi / 180 * direction, rest: 0,
          curve: loop.curve),
        on: motion, key: "loop.body.rotation", period: period, phase: phase, rate: rate)
    case .asleep:
      let loop = DS.Avatar.States.Asleep.Loop.self
      let breath = CABasicAnimation(keyPath: "transform.scale")
      breath.fromValue = loop.bodyScale.first ?? 1
      breath.toValue = loop.bodyScale.last ?? 1
      breath.autoreverses = true
      breath.timingFunction = loop.curve.timingFunction
      run(
        breath, on: motion, key: "loop.body.scale", period: Self.seconds(loop.periodMs) / 2,
        phase: phase, rate: min(sizeRate, Float(loop.fpsMax)))
    case .idle, .hasNews, .paused, .error:
      break
    }
  }

  private func run(
    _ animation: CAAnimation, on layer: CALayer, key: String, period: CFTimeInterval,
    phase: CGFloat, rate: Float
  ) {
    animation.duration = period
    animation.repeatCount = .infinity
    animation.timeOffset = period * Double(phase)
    animation.preferredFrameRateRange = CAFrameRateRange(
      minimum: rate, maximum: rate, preferred: rate)
    layer.add(animation, forKey: key)
  }

  // MARK: - One-shots

  private func playTransition(
    from previous: AvatarStatus, to configuration: AvatarLayerConfiguration
  ) {
    let animates =
      isVisible && configuration.isOnScreen && !configuration.reduceMotion
      && configuration.loopFrameRateMax > 0
    guard animates else { return }
    let unit = configuration.points / DS.Avatar.viewBox
    let direction: CGFloat = configuration.rightToLeft ? -1 : 1
    if previous == .asleep {
      wake(to: configuration, unit: unit)
    }
    switch configuration.status {
    case .error:
      let shake = DS.Avatar.States.Error.OneShot.self
      once(
        Self.keyframes(
          "transform.translation.x", shake.bodyOffsetX, scale: unit * direction, rest: 0,
          curve: shake.curve),
        on: motion, key: "once.body.x", duration: Self.seconds(shake.durationMs))
    case .needsYou:
      let hop = DS.Avatar.States.NeedsYou.OneShot.self
      let loop = DS.Avatar.States.NeedsYou.Loop.self
      let duration = Self.seconds(hop.durationMs)
      once(
        Self.springTrack(
          "transform.translation.y", hop.bodyOffsetY, scale: unit, rest: 0,
          duration: duration, spring: hop.spring),
        on: motion, key: "once.body.y", duration: duration)
      if loopsRunning, loop.hopRepeatMax > 1 {
        let every = Self.seconds(loop.hopRepeatEveryMs)
        let compressed = hop.bodyOffsetY.map {
          AvatarKeyframe($0.time * CGFloat(duration / every), $0.value)
        }
        let repeats = Self.springTrack(
          "transform.translation.y", compressed, scale: unit, rest: 0,
          duration: every, spring: hop.spring)
        repeats.repeatCount = Float(loop.hopRepeatMax - 1)
        repeats.beginTime = motion.convertTime(CACurrentMediaTime(), from: nil) + every
        motion.add(repeats, forKey: "loop.hops")
      }
    case .hasNews:
      cheer(configuration, unit: unit)
    case .paused:
      let fade = CABasicAnimation(keyPath: "fillColor")
      fade.fromValue = configuration.fill
      fade.toValue = configuration.mutedFill
      fade.timingFunction = DS.Motion.Curves.standard.timingFunction
      once(
        fade, on: body, key: "once.fill",
        duration: Self.seconds(DS.Avatar.States.Paused.enterCrossfadeMs))
    case .idle, .working, .asleep, .watching:
      break
    }
  }

  private func wake(to configuration: AvatarLayerConfiguration, unit: CGFloat) {
    let wake = DS.Avatar.States.Asleep.WakeTransition.self
    let duration = Self.seconds(wake.durationMs)
    let closed = AvatarEyePose.closed.transform.scaleY
    let open = configuration.status.stillPose.transform.scaleY
    let eyeFrames = [
      AvatarKeyframe(0, closed), AvatarKeyframe(0.5, wake.eyesOvershootScaleY),
      AvatarKeyframe(1, open),
    ]
    for eye in [leftEye, rightEye] {
      once(
        Self.springTrack(
          "transform.scale.y", eyeFrames, scale: 1, rest: open,
          duration: duration, spring: DS.Motion.Springs.avatarHop),
        on: eye, key: "once.wake.eye", duration: duration)
    }
    let hop = [AvatarKeyframe(0, 0), AvatarKeyframe(0.5, wake.bodyOffsetY), AvatarKeyframe(1, 0)]
    once(
      Self.springTrack(
        "transform.translation.y", hop, scale: unit, rest: 0,
        duration: duration, spring: DS.Motion.Springs.avatarHop),
      on: motion, key: "once.wake.body", duration: duration)
  }

  private func cheer(_ configuration: AvatarLayerConfiguration, unit: CGFloat) {
    let cheer = DS.Avatar.States.HasNews.OneShot.self
    let now = CACurrentMediaTime()
    let limit = Self.seconds(cheer.rateLimitMs)
    if let last = Self.lastCheer[configuration.botID], now - last < limit { return }
    Self.lastCheer[configuration.botID] = now
    let duration = Self.seconds(cheer.durationMs)
    let frames = cheer.bodyOffsetY
    guard let apexIndex = frames.indices.min(by: { frames[$0].value < frames[$1].value }) else {
      return
    }
    let apex = frames[apexIndex].time
    let landing = apexIndex + 1 < frames.count ? frames[apexIndex + 1].time : 1
    let curve = DS.Motion.Curves.bounce
    once(
      Self.keyframes("transform.translation.y", frames, scale: unit, rest: 0, curve: curve),
      on: motion, key: "once.body.y", duration: duration)
    let stretch = DS.Avatar.States.HasNews.OneShot.BodyStretchAtApex.self
    for (keyPath, value) in [
      ("transform.scale.x", stretch.scaleX), ("transform.scale.y", stretch.scaleY),
    ] {
      let pulse = [
        AvatarKeyframe(0, 1), AvatarKeyframe(apex, value), AvatarKeyframe(landing, 1),
      ]
      once(
        Self.keyframes(keyPath, pulse, scale: 1, rest: 1, curve: curve),
        on: motion, key: "once.\(keyPath)", duration: duration)
    }
    let wide = cheer.apexEyePose.transform.scaleX
    let eyePulse = [AvatarKeyframe(0, 1), AvatarKeyframe(apex, wide), AvatarKeyframe(landing, 1)]
    for eye in [leftEye, rightEye] {
      once(
        Self.keyframes("transform.scale", eyePulse, scale: 1, rest: 1, curve: curve),
        on: eye, key: "once.eye.wide", duration: duration)
    }
    let fade = Self.seconds(cheer.sparkleFadeMs)
    let drawn = CGFloat(duration / fade)
    once(
      Self.keyframes(
        "transform.scale", [AvatarKeyframe(0, 0), AvatarKeyframe(apex * drawn, 1)], scale: 1,
        rest: 1, curve: curve),
      on: sparkle, key: "once.sparkle.scale", duration: fade)
    once(
      Self.keyframes(
        "opacity",
        [AvatarKeyframe(0, 1), AvatarKeyframe(landing * drawn, 1), AvatarKeyframe(1, 0)],
        scale: 1, rest: 0, curve: curve),
      on: sparkle, key: "once.sparkle.opacity", duration: fade)
  }

  private func once(_ animation: CAAnimation, on layer: CALayer, key: String, duration: Double) {
    animation.duration = duration
    oneShotDuration = max(oneShotDuration, duration)
    layer.add(animation, forKey: key)
  }

  // MARK: - Helpers

  private func removeAnimations(prefix: String) {
    for layer in [motion, glow, body, eyes, leftEye, rightEye, sparkle] {
      for key in layer.animationKeys() ?? [] where key.hasPrefix(prefix) {
        layer.removeAnimation(forKey: key)
      }
    }
  }

  private func withoutImplicitAnimation(_ changes: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    changes()
    CATransaction.commit()
  }

  private static func seconds(_ milliseconds: CGFloat) -> CFTimeInterval {
    CFTimeInterval(milliseconds) / 1_000
  }
  /// Each token segment settles through the shared spring coefficients; CA runs the track.
  private static func springTrack(
    _ keyPath: String, _ frames: [AvatarKeyframe], scale: CGFloat, rest: CGFloat,
    duration: CFTimeInterval, spring: MotionSpring
  ) -> CAAnimationGroup {
    var track = frames.sorted { $0.time < $1.time }
    if let first = track.first, first.time > 0 { track.insert(AvatarKeyframe(0, rest), at: 0) }
    if let last = track.last, last.time < 1 { track.append(AvatarKeyframe(1, rest)) }
    let physical = spring.spring
    let settling = physical.settlingDuration
    var segments: [CAAnimation] = []
    segments.reserveCapacity(max(track.count - 1, 0))
    for (start, end) in zip(track, track.dropFirst()) {
      let interval = duration * Double(end.time - start.time)
      let segment = CASpringAnimation(keyPath: keyPath)
      segment.mass = physical.mass
      segment.stiffness = physical.stiffness
      segment.damping = physical.damping
      segment.fromValue = start.value * scale
      segment.toValue = end.value * scale
      segment.beginTime = duration * Double(start.time)
      segment.duration = settling
      segment.speed = Float(settling / interval)
      segment.fillMode = .forwards
      segments.append(segment)
    }
    let group = CAAnimationGroup()
    group.animations = segments
    group.duration = duration
    return group
  }

  /// A keyframe track in token units, scaled to points, degrees or radians as needed. Tracks
  /// that start after zero or end before one rest at `rest` there, so loops are seamless.
  private static func keyframes(
    _ keyPath: String, _ frames: [AvatarKeyframe], scale: CGFloat, rest: CGFloat,
    curve: MotionCurve
  ) -> CAKeyframeAnimation {
    var track = frames.sorted { $0.time < $1.time }
    if let first = track.first, first.time > 0 { track.insert(AvatarKeyframe(0, rest), at: 0) }
    if let last = track.last, last.time < 1 { track.append(AvatarKeyframe(1, rest)) }
    let animation = CAKeyframeAnimation(keyPath: keyPath)
    animation.values = track.map { NSNumber(value: Double($0.value * scale)) }
    animation.keyTimes = track.map { NSNumber(value: Double($0.time)) }
    animation.timingFunctions = Array(
      repeating: curve.timingFunction, count: max(track.count - 1, 1))
    animation.calculationMode = .linear
    return animation
  }
}
