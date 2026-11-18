import Foundation

/// One whole frame of Blip: the ship's motion, its trail, the comet fire, the
/// aura and the sprites, on the fixed 60 Hz tick. Layout follows `frame()` in
/// `docs/reference/mockup.html`, in arcade pixels relative to the ship's
/// top-centre `(x, y)`. The creature's eyes follow the pointer, it shows moods
/// while it hovers, and a scan beam can sweep what it is looking at.
public struct Scene {
  /// A short burst of feeling, shown over whatever else the creature is doing.
  public enum Reaction { case happy, startled }

  /// What the creature's face is doing, highest priority first. Reactions carry their age in ticks.
  enum Mood: Equatable { case startled(Int), happy(Int), reading, yawning, asleep, calm }

  /// Ticks one aura step lasts; the step also drives blinking and wiggling.
  static let stepTicks = 20
  static let thinkingStepTicks = 6
  /// Ticks the creature spends on each bob height.
  static let bobTicks = 30
  /// The most ticks the trail and the comet keep running after the ship is
  /// gone, so the fly-off is not cut short; the linger ends sooner once
  /// neither has anything left to draw.
  static let lingerTicks = 60
  /// Ticks of launch shake at the start of the fly-in, alternating 1 px right and left.
  static let shakeTicks = 10
  /// On arrival the ship carries on up past its hover point, `overshoot`
  /// pixels over `overshootTicks`, then settles back down over `settleTicks`.
  static let overshoot = 2
  static let overshootTicks = 8
  static let settleTicks = 12
  /// Half the width of the body the comet fire wraps.
  static let cometHalfWidth = 12

  /// How long each reaction lasts, in ticks.
  static let happyTicks = 70
  static let startledTicks = 50
  /// Idle hover ticks before the yawn, how long the yawn lasts, and idle ticks before falling asleep.
  static let yawnAt = 1500
  static let yawnTicks = 50
  static let sleepAt = 2700
  /// Ticks one sleepy "z" takes to drift away before the next one starts.
  static let zTicks = 60
  /// Ticks each glance lasts while reading.
  static let glanceTicks = 10
  /// A pointer this close to the eyes, in arcade pixels, leaves them looking straight ahead.
  static let gazeDeadZone = 10
  /// How far the pointer must move, in arcade pixels, to count as activity.
  static let stirDistance = 3
  /// The scan beam's whole run, and its sweep from the area's top to its bottom; the corner
  /// brackets blink out over the ticks after the sweep.
  static let scanTicks = 48
  static let sweepStart = 2
  static let sweepTicks = 38
  static let scanSparkleLife = 10
  /// The happy sparkles, relative to the ship's top-centre, and the tick each one pops.
  static let happySparkles: [(dx: Int, dy: Int, at: Int)] = [(-9, -15, 6), (-3, -19, 14), (4, -17, 22), (10, -14, 30)]
  static let sparkleLife = 24

  static let domeColor: RGBA = 0xBAE6FDFF
  static let white = Art.white
  static let yellow = Art.yellow

  /// While true, the aura steps faster. Starting to think counts as activity.
  public var thinking = false {
    didSet { if thinking && !oldValue { stir() } }
  }
  /// While true, the creature is looking at the screen: its eyes narrow and glance left and right.
  /// Starting to read counts as activity.
  public var reading = false {
    didSet { if reading && !oldValue { stir() } }
  }

  public var phase: Phase { motion.phase }
  /// The ship is gone and its trail and comet have nothing left to draw, or the linger ran out.
  public var isFinished: Bool { motion.phase == .gone && !lingering }
  /// The hover centre.
  public var anchor: (x: Int, y: Int) { (motion.anchorX, motion.anchorY) }
  /// The rectangle covering the creature and the ship, where they are drawn.
  public var hitRect: (x: Int, y: Int, w: Int, h: Int) {
    (shipX - 12, shipY - 12, 24, 12 + shipSprite.height)
  }

  private let creature: CreatureArt
  private let shipSprite: Sprite
  private let hasDome: Bool
  private let ramp: ColorRamp
  private let auraColor: RGBA?
  private var motion: ShipMotion
  private var trail: TrailSystem
  /// The effect around the ship in flight; `nil` when the entry effect is off.
  private var shroud: EntryFX?
  private let auraStyle: AuraStyle
  private let followPointer: Bool
  private let moodsOn: Bool
  private let scanOn: Bool
  private let bufferWidth: Int
  private let bufferHeight: Int
  /// The scene's own randomness, for the scan beam; the trail and the comet have theirs.
  private var random: SeededRandom
  /// The pointer in arcade pixels, when known and followed.
  private var pointer: (x: Int, y: Int)?
  /// Where the pointer was when it last counted as activity.
  private var stirPointer: (x: Int, y: Int)?
  /// Where the eyes look, each of x and y -1, 0 or 1; worked out in `tick`.
  private var gaze = (x: 0, y: 0)
  /// Ticks of hovering without activity.
  private var idleTicks = 0
  /// Ticks since each reaction started; `nil` when it is not showing.
  private var happyAge: Int?
  private var startledAge: Int?
  private var beam: ScanBeam?
  private var ticks = 0
  private var step = 0
  private var ticksIntoStep = 0
  private var goneTicks = 0
  private var lingering = true
  /// Ticks since the fly-in reached the hover point; `nil` before then.
  private var landedTicks: Int?
  /// Where the ship is drawn: its motion plus the launch shake and the arrival overshoot.
  private var shipX: Int
  private var shipY: Int
  /// Where the comet fire is drawn. It stays at the ship's last place on screen
  /// once the ship is gone, so the tail can finish leaving.
  private var shroudX: Int
  private var shroudY: Int

  public init(settings: BlipSettings, bufferWidth: Int, bufferHeight: Int, seed: UInt64) {
    creature = Art.creature(settings.creature)
    shipSprite = Art.ship(settings.ship)
    hasDome = settings.ship == .pod
    ramp = ColorRamp(settings.trailColor)
    auraColor = settings.auraColor
    auraStyle = settings.aura
    followPointer = settings.followPointer
    moodsOn = settings.moods
    scanOn = settings.scanBeam
    random = SeededRandom(seed: seed ^ 0x6C_6F6F_6B)  // "look"
    motion = ShipMotion(
      bufferWidth: bufferWidth, bufferHeight: bufferHeight, hover: settings.hover, path: settings.flightPath,
      speed: settings.flightSpeed)
    trail = TrailSystem(style: settings.trail, seed: seed)
    shroud = EntryFX(style: settings.entryEffect, seed: seed ^ 0x636F_6D65_74)  // "comet", so it differs from the trail's
    self.bufferWidth = bufferWidth
    self.bufferHeight = bufferHeight
    (shipX, shipY) = (motion.x, motion.y)
    (shroudX, shroudY) = (shipX, shipY)
  }

  public mutating func tick() {
    guard lingering else { return }
    if motion.phase == .gone { goneTicks += 1 }
    ticks += 1
    ticksIntoStep += 1
    // Asleep, the aura steps at half speed.
    let stepLength = thinking ? Self.thinkingStepTicks : (mood == .asleep ? 2 * Self.stepTicks : Self.stepTicks)
    if ticksIntoStep >= stepLength {
      step += 1
      ticksIntoStep = 0
    }
    let lastY = motion.y
    motion.tick()
    let gone = motion.phase == .gone
    if let t = landedTicks {
      if t < Self.overshootTicks + Self.settleTicks { landedTicks = t + 1 }
    } else if (motion.phase == .flyIn && motion.y == motion.anchorY) || motion.phase == .hover {
      landedTicks = 0
    }
    shipX = motion.x + shakeOffset()
    shipY = motion.y + arrivalOffset()
    if !gone { (shroudX, shroudY) = (shipX, shipY) }

    // The fire's direction and embers follow the ship's flight alone, not the
    // shake or the overshoot, and stand still with it once it is gone.
    shroud?.tick(
      flying: motion.flying, velocityY: gone ? 0 : motion.y - lastY, velocity: gone ? (0, 0) : motion.velocity)
    trail.tick(
      shipX: shipX, shipY: shipY, exhaustY: shipY + shipSprite.height, flying: motion.flying, emitting: !gone)
    if gone { lingering = goneTicks < Self.lingerTicks && (!trail.isEmpty || shroudOnScreen) }
    tickMoods()
    tickBeam()
  }

  /// Ages the reactions, runs the idle clock and points the eyes at the pointer.
  private mutating func tickMoods() {
    if let a = happyAge { happyAge = a + 1 < Self.happyTicks ? a + 1 : nil }
    if let a = startledAge { startledAge = a + 1 < Self.startledTicks ? a + 1 : nil }
    if motion.phase == .hover { idleTicks = thinking || reading ? 0 : idleTicks + 1 }
    gaze = (0, 0)
    guard let p = pointer else { return }
    let eye = eyeCentre()
    let dx = p.x - eye.x, dy = p.y - eye.y
    guard dx * dx + dy * dy > Self.gazeDeadZone * Self.gazeDeadZone else { return }
    // Eight ways: an axis counts when the angle is within 67.5 degrees of it (tan 22.5 is about 5/12).
    gaze.x = abs(dx) * 12 >= abs(dy) * 5 ? dx.signum() : 0
    gaze.y = abs(dy) * 12 >= abs(dx) * 5 ? dy.signum() : 0
  }

  /// Ages the scan beam, moves its line on and leaves sparkles behind it.
  private mutating func tickBeam() {
    guard var s = beam else { return }
    s.age += 1
    guard s.age < Self.scanTicks else {
      beam = nil
      return
    }
    s.sparkles = s.sparkles.compactMap { $0.age + 1 < Self.scanSparkleLife ? ($0.x, $0.y, $0.age + 1) : nil }
    let t = s.age - Self.sweepStart
    if t >= 0 && t < Self.sweepTicks {
      let last = s.lineY ?? s.y
      s.lineY = s.y + Self.round(Double(t) / Double(Self.sweepTicks - 1) * Double(s.h - 1))
      for _ in 0..<max(1, s.w / 50) {
        let x = s.x + Int(random.next() * Double(s.w))
        let y = last - 4 + Int(random.next() * Double(max(1, s.lineY! - last + 3)))
        if y >= s.y && y < s.y + s.h { s.sparkles.append((x, y, 0)) }
      }
      s.runs = (0..<max(1, s.w / 16)).map { _ in (s.x + Int(random.next() * Double(s.w)), 2 + Int(random.next() * 5)) }
    } else {
      s.lineY = nil
      s.runs = []
    }
    beam = s
  }

  /// The middle of the creature's eyes, in buffer pixels, where it is drawn this tick.
  private func eyeCentre() -> (x: Int, y: Int) {
    let top = shipY - 11 - bob - hop
    switch creature.eyes {
    case .pair(let l, let r): return (shipX - 8 + (l.x + r.x + 2) / 2, top + l.y + 1)
    case .framed(let c, let w, let h): return (shipX - 8 + c.x + w / 2, top + c.y + h / 2)
    }
  }

  /// What the face shows now. Moods show only while hovering, and not at all with moods off.
  var mood: Mood {
    guard moodsOn, motion.phase == .hover else { return .calm }
    if let a = startledAge { return .startled(a) }
    if let a = happyAge { return .happy(a) }
    if reading { return .reading }
    if idleTicks >= Self.sleepAt { return .asleep }
    if idleTicks >= Self.yawnAt && idleTicks < Self.yawnAt + Self.yawnTicks { return .yawning }
    return .calm
  }

  /// The creature's bob: up one pixel on alternate `bobTicks`.
  private var bob: Int { (ticks / Self.bobTicks) % 2 }

  /// How high a reaction lifts the creature: two small hops when happy, one quick one when startled.
  private var hop: Int {
    switch mood {
    case .happy(let t) where t < 44 && t % 22 < 18:
      return Self.round(2 * sin(Double.pi * Double(t % 22) / 18))
    case .startled(let t) where t < 14:
      return Self.round(3 * sin(Double.pi * Double(t) / 14))
    default:
      return 0
    }
  }

  // MARK: - Looking, moods and scanning

  /// Tells the scene where the pointer is, in arcade pixels (it may be outside the buffer; `nil` when
  /// unknown). The eyes turn toward it, and a move of `stirDistance` pixels or more counts as
  /// activity. With `followPointer` off it only counts the activity.
  public mutating func look(at p: (x: Int, y: Int)?) {
    if let p {
      if let s = stirPointer {
        if max(abs(p.x - s.x), abs(p.y - s.y)) >= Self.stirDistance {
          stirPointer = p
          stir()
        }
      } else {
        stirPointer = p
      }
    }
    pointer = followPointer ? p : nil
  }

  /// Shows a reaction; it counts as activity. Does nothing with moods off.
  public mutating func react(_ r: Reaction) {
    guard moodsOn else { return }
    stir()
    switch r {
    case .happy: happyAge = 0
    case .startled: startledAge = 0
    }
  }

  /// Something happened: restarts the idle clock, waking the creature if it was asleep.
  public mutating func stir() { idleTicks = 0 }

  /// Sweeps a scan beam over `area` (buffer pixels; `nil` is the whole buffer), clipped to the buffer.
  /// It draws only while hovering and leaves nothing behind. Does nothing with the scan beam off.
  public mutating func scan(_ area: (x: Int, y: Int, w: Int, h: Int)?) {
    guard scanOn else { return }
    let a = area ?? (0, 0, bufferWidth, bufferHeight)
    let x0 = max(a.x, 0), y0 = max(a.y, 0)
    let x1 = min(a.x + a.w, bufferWidth), y1 = min(a.y + a.h, bufferHeight)
    guard x0 < x1, y0 < y1 else { return }
    beam = ScanBeam(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
  }

  /// 1 px right then left on alternate ticks over the start of the fly-in.
  private func shakeOffset() -> Int {
    guard motion.phase == .flyIn, ticks <= Self.shakeTicks else { return 0 }
    return ticks % 2 == 1 ? 1 : -1
  }

  /// Up past the hover point and back: eases out to `-overshoot`, then eases
  /// back to 0. Runs to its end whatever the phase, so it never jumps.
  private func arrivalOffset() -> Int {
    guard let t = landedTicks else { return 0 }
    let rise = Self.overshootTicks, settle = Self.settleTicks
    let f: Double
    if t <= rise {
      f = sin(Double.pi / 2 * Double(t) / Double(rise))
    } else if t < rise + settle {
      f = (1 + cos(Double.pi * Double(t - rise) / Double(settle))) / 2
    } else {
      return 0
    }
    return -Self.round(Double(Self.overshoot) * f)
  }

  /// The comet fire has something to draw inside the buffer.
  private var shroudOnScreen: Bool {
    guard let rows = shroud?.rows(top: shroudY - 12, bottom: shroudY + shipSprite.height - 1) else { return false }
    return rows.upperBound >= 0 && rows.lowerBound < bufferHeight
  }

  /// Starts the fly-off; a scan stops at once.
  public mutating func dismiss() {
    motion.dismiss()
    beam = nil
  }

  /// Moves the hover centre. Ignored outside `hover`. Counts as activity.
  public mutating func drag(dx: Int, dy: Int) {
    stir()
    motion.drag(dx: dx, dy: dy)
  }

  /// Draws the frame over `b`'s current contents; callers clear `b` first.
  public func render(into b: inout PixelBuffer) {
    guard lingering else { return }
    let x = shipX, y = shipY
    let creatureSprite = creatureFrame()
    let silhouette = [(creatureSprite, dx: -8, dy: -11), (shipSprite, dx: -12, dy: 0)]

    trail.draw(into: &b, ramp: ramp, silhouette: silhouette)
    if let shroud {
      shroud.draw(
        into: &b, ramp: ramp, centerX: shroudX, top: shroudY - 12, bottom: shroudY + shipSprite.height - 1,
        halfWidth: Self.cometHalfWidth)
    }
    if motion.phase == .gone { return }
    let mood = mood
    if motion.phase == .hover, let beam { drawBeam(beam, into: &b) }

    // While the fire is strong it takes the aura's place.
    if !(shroud?.hidesAura ?? false) || (shroud?.strength ?? 0) <= 0.5 { drawAura(into: &b, x: x, y: y) }

    let blink = mood == .calm && step % 10 == 0
    let cx = x - 8, cy = y - 11 - bob - hop
    b.draw(creatureSprite, x: cx, y: cy, palette: Art.creaturePalette(creature, blink: blink))
    drawFace(into: &b, x: cx, y: cy, mood: mood, blink: blink)

    if hasDome { drawDome(into: &b, x: x, y: y) }

    b.draw(shipSprite, x: x - 12, y: y, palette: Art.shipPalette(trim: ramp.main, lights: step % 2 == 1 ? Self.yellow : Self.white))

    switch mood {
    case .happy(let t): drawHappySparkles(into: &b, x: x, y: y, age: t)
    case .startled(let t): drawExclamation(into: &b, x: x, y: y, age: t)
    case .asleep: drawZ(into: &b, x: x, y: y)
    default: break
    }
  }

  // MARK: - Faces

  /// The shapes the eyes take.
  private enum EyeShape {
    /// Open, shifted by the gaze.
    case open(dx: Int, dy: Int)
    /// Narrowed to a line, glancing sideways.
    case narrow(dx: Int)
    case shut, arches, wide
  }

  /// Redraws the eyes, and the mouth for a yawn, over the creature drawn at `(x, y)`. Calm and looking
  /// straight ahead, the sprite's own eyes stand.
  private func drawFace(into b: inout PixelBuffer, x: Int, y: Int, mood: Mood, blink: Bool) {
    let shape: EyeShape
    switch mood {
    case .startled: shape = .wide
    case .happy: shape = .arches
    case .reading: shape = .narrow(dx: [-1, 0, 1, 0][(ticks / Self.glanceTicks) % 4])
    case .yawning, .asleep: shape = .shut
    case .calm:
      guard gaze != (0, 0) else { return }
      shape = .open(dx: gaze.x, dy: gaze.y)
    }
    let dark = blink ? creature.shade : Art.outline, light = blink ? creature.body : Self.white
    switch creature.eyes {
    case .pair(let l, let r):
      for (eye, outward) in [(l, -1), (r, 0)] {
        drawPairEye(into: &b, x: x + eye.x, y: y + eye.y, outward: outward, shape: shape, dark: dark, light: light)
      }
    case .framed(let c, let w, let h):
      drawFramedEye(into: &b, x: x + c.x, y: y + c.y, w: w, h: h, shape: shape, dark: dark, light: light)
    }
    if mood == .yawning { b.fill(x: x + creature.mouth.x, y: y + creature.mouth.y, w: 2, h: 2, Art.outline) }
  }

  /// One 2x2 eye with its top-left at `(x, y)`. The 3-wide shapes grow by one column `outward`
  /// (-1 for the left eye, 0 for the right) so the pair stays symmetric.
  private func drawPairEye(
    into b: inout PixelBuffer, x: Int, y: Int, outward: Int, shape: EyeShape, dark: RGBA, light: RGBA
  ) {
    b.fill(x: x, y: y, w: 2, h: 2, creature.body)
    switch shape {
    case .open(let dx, let dy):
      b.fill(x: x + dx, y: y + dy, w: 2, h: 2, dark)
      dot(&b, x + dx + 1, y + dy, light)
    case .narrow(let dx):
      b.fill(x: x + dx, y: y + 1, w: 2, h: 1, Art.outline)
    case .shut:
      b.fill(x: x, y: y, w: 2, h: 1, creature.shade)
      b.fill(x: x, y: y + 1, w: 2, h: 1, Art.outline)
    case .arches:
      dot(&b, x + outward + 1, y, Art.outline)
      dot(&b, x + outward, y + 1, Art.outline)
      dot(&b, x + outward + 2, y + 1, Art.outline)
    case .wide:
      // A dark ring with a white middle, one row taller than the eye: it reads on the white snowman too.
      b.fill(x: x + outward, y: y - 1, w: 3, h: 3, Art.outline)
      dot(&b, x + outward + 1, y, Self.white)
    }
  }

  /// The alien's one eye: the white interior at `(x, y)`, `w` by `h`, inside a dark frame.
  private func drawFramedEye(
    into b: inout PixelBuffer, x: Int, y: Int, w: Int, h: Int, shape: EyeShape, dark: RGBA, light: RGBA
  ) {
    let mid = x + (w - 2) / 2
    switch shape {
    case .open(let dx, let dy):
      b.fill(x: x, y: y, w: w, h: h, light)
      // Looking up or down, the pupil is half height on the top or bottom row.
      b.fill(x: mid + dx, y: dy > 0 ? y + h - 1 : y, w: 2, h: dy == 0 ? h : 1, dark)
    case .narrow(let dx):
      // The frame's top row becomes the lid, pressed down onto the eye's top row.
      b.fill(x: x, y: y - 1, w: w, h: 1, creature.body)
      b.fill(x: x - 1, y: y, w: w + 2, h: 1, Art.outline)
      b.fill(x: x, y: y + h - 1, w: w, h: 1, Self.white)
      b.fill(x: mid + dx, y: y + h - 1, w: 2, h: 1, Art.outline)
    case .shut, .arches:
      // No frame: a curve, down at the ends when shut and up in the middle when happy.
      b.fill(x: x - 1, y: y - 1, w: w + 2, h: h + 2, creature.body)
      let ends = shapeIsShut(shape) ? y : y + 1, middle = shapeIsShut(shape) ? y + 1 : y
      b.fill(x: x, y: middle, w: w, h: 1, Art.outline)
      dot(&b, x - 1, ends, Art.outline)
      dot(&b, x + w, ends, Art.outline)
    case .wide:
      // The frame opens a row higher, and a small pupil stares out of the middle.
      b.fill(x: x, y: y - 2, w: w, h: 1, Art.outline)
      b.fill(x: x, y: y - 1, w: w, h: h + 1, Self.white)
      b.fill(x: mid, y: y, w: 2, h: 1, Art.outline)
    }
  }

  private func shapeIsShut(_ shape: EyeShape) -> Bool {
    if case .shut = shape { return true }
    return false
  }

  /// Three or four little stars popping one after another above the head, in the aura colors.
  private func drawHappySparkles(into b: inout PixelBuffer, x: Int, y: Int, age: Int) {
    let (inner, outer) = auraColors
    for (i, s) in Self.happySparkles.enumerated() {
      let a = age - s.at
      guard a >= 0, a < Self.sparkleLife, a < Self.sparkleLife - 4 || a % 2 == 0 else { continue }
      let px = x + s.dx, py = y + s.dy, color = i % 2 == 0 ? inner : outer
      if a >= 3 && a < 15 {
        b.fill(x: px - 1, y: py, w: 3, h: 1, color)
        b.fill(x: px, y: py - 1, w: 1, h: 3, color)
        dot(&b, px, py, Self.white)
      } else {
        dot(&b, px, py, a < 3 ? Self.white : color)
      }
    }
  }

  /// A yellow "!" with a dark outline, up and to the right of the head.
  private func drawExclamation(into b: inout PixelBuffer, x: Int, y: Int, age: Int) {
    guard age >= 2, age < Self.startledTicks - 10 || (age / 2) % 2 == 0 else { return }
    let mark = Sprite(rows: [".kk.", "kyyk", "kyyk", "kyyk", ".kk.", "kyyk", ".kk."])
    b.draw(mark, x: x + 8, y: y - 21, palette: ["k": Art.outline, "y": Self.yellow])
  }

  /// One "z" at a time drifting up and to the right from the head, growing as it goes.
  private func drawZ(into b: inout PixelBuffer, x: Int, y: Int) {
    let a = (idleTicks - Self.sleepAt) % Self.zTicks
    guard a < Self.zTicks - 8 || a % 2 == 0 else { return }
    let z = a < Self.zTicks / 2
      ? Sprite(rows: ["XXXX", "..X.", ".X..", "XXXX"])
      : Sprite(rows: ["XXXXX", "...X.", "..X..", ".X...", "XXXXX"])
    let zx = x + 6 + a / 10, zy = y - 14 - a / 8
    b.draw(z, x: zx + 1, y: zy + 1, palette: [:], mono: Art.outline)
    b.draw(z, x: zx, y: zy, palette: [:], mono: Self.white)
  }

  // MARK: - Scan beam

  /// A scan in progress over a fixed area of the buffer.
  private struct ScanBeam {
    let x, y, w, h: Int
    var age = 0
    /// The leading row of the line; `nil` before and after the sweep.
    var lineY: Int?
    /// White runs on the leading row, redrawn each tick.
    var runs: [(x: Int, w: Int)] = []
    var sparkles: [(x: Int, y: Int, age: Int)] = []
  }

  /// Viewfinder brackets at the area's corners and the line sweeping down it, in the trail ramp.
  private func drawBeam(_ s: ScanBeam, into b: inout PixelBuffer) {
    let sweepEnd = Self.sweepStart + Self.sweepTicks
    if s.age < sweepEnd || ((s.age - sweepEnd) / 2) % 2 == 1 {
      let inset = 2, thick = 2
      let longest = max(thick, min(10, (s.w - 2 * inset) / 2, (s.h - 2 * inset) / 2))
      let arm = min(longest, 4 + 2 * s.age)
      let left = s.x + inset, right = s.x + s.w - inset - thick
      let top = s.y + inset, bottom = s.y + s.h - inset - thick
      for (cx, cy, sx, sy) in [(left, top, 1, 1), (right, top, -1, 1), (left, bottom, 1, -1), (right, bottom, -1, -1)] {
        b.fill(x: sx > 0 ? cx : cx + thick - arm, y: cy, w: arm, h: thick, ramp.light)
        b.fill(x: cx, y: sy > 0 ? cy : cy + thick - arm, w: thick, h: arm, ramp.light)
      }
    }
    for p in s.sparkles { dot(&b, p.x, p.y, ramp.step(Double(p.age) / Double(Self.scanSparkleLife))) }
    guard let line = s.lineY else { return }
    // A stepped tail above the line: two dithered rows in main, then three sparser rows in dark.
    for back in 1...5 where line - back >= s.y {
      let row = line - back
      for col in s.x..<(s.x + s.w) {
        let lit = back <= 2 ? (col + row) % 2 == 0 : (col + 2 * row) % 4 == 0
        if lit { dot(&b, col, row, back <= 2 ? ramp.main : ramp.dark) }
      }
    }
    b.fill(x: s.x, y: line, w: s.w, h: 1, ramp.light)
    for r in s.runs { b.fill(x: r.x, y: line, w: min(r.w, s.x + s.w - r.x), h: 1, ramp.white) }
  }

  /// The creature sprite for this step: on odd steps a wiggling creature's
  /// bottom row shifts right by one.
  private func creatureFrame() -> Sprite {
    guard creature.wiggles && step % 2 == 1, let last = creature.sprite.rows.last else {
      return creature.sprite
    }
    return Sprite(rows: Array(creature.sprite.rows.dropLast()) + ["." + String(last.dropLast())])
  }

  /// The aura's two colors: the owner's pick, or the creature's own.
  private var auraColors: (inner: RGBA, outer: RGBA) {
    (auraColor ?? creature.auraInner, auraColor ?? creature.auraOuter)
  }

  /// Two dotted ellipses around the creature, alternate points lit, swapping each step.
  private func drawAura(into b: inout PixelBuffer, x: Int, y: Int) {
    let cy = y - 4
    let (inner, outer) = auraColors
    switch auraStyle {
    case .off:
      return
    case .halo:
      // Two solid rings, the outer one breathing in and out with the step.
      for i in 0..<48 {
        let a = Double(i) / 48 * 2 * Double.pi
        dot(&b, x + Self.round(cos(a) * 15), cy + Self.round(sin(a) * 13), inner)
        let grow = step % 2 == 0 ? 0.0 : 1.0
        if i % 2 == 0 { dot(&b, x + Self.round(cos(a) * (18 + grow)), cy + Self.round(sin(a) * (16 + grow)), outer) }
      }
      return
    case .sparkles:
      // Little stars that hop to new places around the creature every step.
      for i in 0..<9 {
        let h = Double((i * 7919 + step * 104729) % 1000) / 1000
        let a = (Double(i) + h) / 9 * 2 * Double.pi
        let r = 14 + Double((i * 31 + step * 17) % 6)
        let px = x + Self.round(cos(a) * r), py = cy + Self.round(sin(a) * r * 0.9)
        let color = i % 3 == 0 ? Self.white : (i % 2 == 0 ? inner : outer)
        dot(&b, px, py, color)
        if (i + step) % 3 == 0 {
          b.fill(x: px - 1, y: py, w: 3, h: 1, color)
          b.fill(x: px, y: py - 1, w: 1, h: 3, color)
        }
      }
      return
    case .rings:
      break
    }
    for i in 0..<20 where (i + step) % 2 == 0 {
      let a = Double(i) / 20 * 2 * Double.pi
      dot(&b, x + Self.round(cos(a) * 15), cy + Self.round(sin(a) * 13), inner)
    }
    for i in 0..<12 where (i + step) % 2 == 1 {
      let a = Double(i) / 12 * 2 * Double.pi + 0.3  // offset from the inner ring, as in the mockup
      dot(&b, x + Self.round(cos(a) * 19), cy + Self.round(sin(a) * 17), outer)
    }
  }

  /// The pod's glass dome: a half ellipse above the ship with a white glint.
  private func drawDome(into b: inout PixelBuffer, x: Int, y: Int) {
    for i in 0...26 {
      let a = Double.pi + Double(i) / 26 * Double.pi
      dot(&b, x + Self.round(cos(a) * 11), y + Self.round(sin(a) * 15), Self.domeColor)
      if (5...8).contains(i) {
        dot(&b, x + Self.round(cos(a) * 9), y + Self.round(sin(a) * 13), Self.white)
      }
    }
  }

  private func dot(_ b: inout PixelBuffer, _ x: Int, _ y: Int, _ color: RGBA) {
    b.fill(x: x, y: y, w: 1, h: 1, color)
  }

  private static func round(_ v: Double) -> Int { Int(v.rounded()) }
}
