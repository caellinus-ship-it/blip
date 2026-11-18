import Foundation

/// One whole frame of Blip: the ship's motion, its trail, the comet fire, the
/// aura and the sprites, on the fixed 60 Hz tick. Layout follows `frame()` in
/// `docs/reference/mockup.html`, in arcade pixels relative to the ship's
/// top-centre `(x, y)`.
public struct Scene {
  /// Ticks one aura step lasts; the step also drives blinking and wiggling.
  static let stepTicks = 20
  static let thinkingStepTicks = 6
  /// Ticks the creature spends on each bob height.
  static let bobTicks = 30
  /// Ticks the trail keeps running after the ship is gone, so the fly-off is not cut short.
  static let lingerTicks = 60
  /// Half the width of the body the comet fire wraps.
  static let cometHalfWidth = 12

  static let domeColor: RGBA = 0xBAE6FDFF
  static let white: RGBA = 0xFFFFFFFF
  static let yellow: RGBA = 0xFDE047FF

  /// While true, the aura steps faster.
  public var thinking = false

  public var phase: Phase { motion.phase }
  /// The hover centre.
  public var anchor: (x: Int, y: Int) { (motion.anchorX, motion.anchorY) }
  /// The rectangle covering the creature and the ship.
  public var hitRect: (x: Int, y: Int, w: Int, h: Int) {
    (motion.x - 12, motion.y - 12, 24, 12 + shipSprite.height)
  }

  private let creature: CreatureArt
  private let shipSprite: Sprite
  private let hasDome: Bool
  private let ramp: ColorRamp
  private let auraColor: RGBA?
  private var motion: ShipMotion
  private var trail: TrailSystem
  /// The fire around the ship in flight; `nil` when the comet setting is off.
  private var shroud: CometShroud?
  private var ticks = 0
  private var step = 0
  private var ticksIntoStep = 0
  private var goneTicks = 0

  public init(settings: BlipSettings, bufferWidth: Int, bufferHeight: Int, seed: UInt64) {
    creature = Art.creature(settings.creature)
    shipSprite = Art.ship(settings.ship)
    hasDome = settings.ship == .pod
    ramp = ColorRamp(settings.trailColor)
    auraColor = settings.auraColor
    motion = ShipMotion(bufferWidth: bufferWidth, bufferHeight: bufferHeight, hover: settings.hover)
    trail = TrailSystem(style: settings.trail, seed: seed)
    shroud = settings.comet ? CometShroud(seed: seed ^ 0x636F_6D65_74) : nil  // "comet", so it differs from the trail's
  }

  public mutating func tick() {
    if motion.phase == .gone {
      guard goneTicks < Self.lingerTicks else { return }
      goneTicks += 1
    }
    ticks += 1
    ticksIntoStep += 1
    if ticksIntoStep >= (thinking ? Self.thinkingStepTicks : Self.stepTicks) {
      step += 1
      ticksIntoStep = 0
    }
    let lastY = motion.y
    motion.tick()
    shroud?.tick(flying: motion.flying, velocityY: motion.y - lastY)
    trail.tick(
      shipX: motion.x, shipY: motion.y, exhaustY: motion.y + shipSprite.height, flying: motion.flying)
  }

  /// Starts the fly-off.
  public mutating func dismiss() { motion.dismiss() }

  /// Moves the hover centre. Ignored outside `hover`.
  public mutating func drag(dx: Int, dy: Int) { motion.drag(dx: dx, dy: dy) }

  /// Draws the frame over `b`'s current contents; callers clear `b` first.
  public func render(into b: inout PixelBuffer) {
    let x = motion.x, y = motion.y
    let creatureSprite = creatureFrame()
    let silhouette = [(creatureSprite, dx: -8, dy: -11), (shipSprite, dx: -12, dy: 0)]

    if motion.phase == .gone {
      if goneTicks < Self.lingerTicks { trail.draw(into: &b, ramp: ramp, silhouette: silhouette) }
      return
    }

    trail.draw(into: &b, ramp: ramp, silhouette: silhouette)
    if let shroud {
      shroud.draw(
        into: &b, ramp: ramp, centerX: x, top: y - 12, bottom: y + shipSprite.height - 1,
        halfWidth: Self.cometHalfWidth)
    }
    // While the fire is strong it takes the aura's place.
    if (shroud?.strength ?? 0) <= 0.5 { drawAura(into: &b, x: x, y: y) }

    let blink = step % 10 == 0
    let bob = (ticks / Self.bobTicks) % 2
    b.draw(
      creatureSprite, x: x - 8, y: y - 11 - bob,
      palette: [
        "k": Art.outline, "X": creature.body, "s": creature.shade, "h": creature.highlight,
        "o": blink ? creature.shade : Art.outline, "w": blink ? creature.body : Self.white,
        "b": 0xFB7185FF, "m": Art.outline, "p": 0xF472B6FF, "a": 0xFDE047FF,
      ])

    if hasDome { drawDome(into: &b, x: x, y: y) }

    b.draw(
      shipSprite, x: x - 12, y: y,
      palette: [
        "k": Art.outline, "H": 0xE8EAF0FF, "L": 0xFFFFFFFF, "D": 0x9AA1B2FF, "R": ramp.main,
        "T": 0x3A3F52FF, "o": 0x5B6378FF, "y": step % 2 == 1 ? Self.yellow : Self.white,
      ])
  }

  /// The creature sprite for this step: on odd steps a wiggling creature's
  /// bottom row shifts right by one.
  private func creatureFrame() -> Sprite {
    guard creature.wiggles && step % 2 == 1, let last = creature.sprite.rows.last else {
      return creature.sprite
    }
    return Sprite(rows: Array(creature.sprite.rows.dropLast()) + ["." + String(last.dropLast())])
  }

  /// Two dotted ellipses around the creature, alternate points lit, swapping each step.
  private func drawAura(into b: inout PixelBuffer, x: Int, y: Int) {
    let cy = y - 4
    let inner = auraColor ?? creature.highlight, outer = auraColor ?? creature.body
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
