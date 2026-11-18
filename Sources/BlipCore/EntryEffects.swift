import Foundation

/// Whatever surrounds the ship while it flies in and off: the comet fire, or one of the other
/// entry effects. Like the comet, each one is scaled by a `strength` that rises fast in flight and
/// eases to 0 once the ship stops, so nothing cuts off. All randomness is drawn in `tick`.
public struct EntryFX {
  /// A warp line rushing past the ship, placed relative to the body's centre.
  private struct Streak { var dx: Int; var y: Double; var length: Int; var speed: Double; var wide: Bool }
  /// A star thrown off the ship, placed relative to the body's centre.
  private struct Spark { var x: Double; var y: Double; var vx: Double; var vy: Double; var age = 0; let life: Int; let big: Bool }
  /// A ring shed behind the bubble shield.
  private struct Ripple { var behind: Double; var age = 0 }

  static let streakCount = 18
  static let rippleLife = 28

  public let style: EntryEffect
  /// The effect stands in for the aura while it is strong.
  public var hidesAura: Bool { style == .comet || style == .bubble }
  public var strength: Double { comet?.strength ?? level }

  private var comet: CometShroud?
  private var level = 1.0
  private var random: SeededRandom
  private var tickCount = 0
  /// The effect streams below the body (the ship is moving up).
  private var streamDown = true
  private var streaks: [Streak] = []
  private var sparks: [Spark] = []
  private var ripples: [Ripple] = []

  /// `nil` for `.none`.
  public init?(style: EntryEffect, seed: UInt64) {
    guard style != .none else { return nil }
    self.style = style
    random = SeededRandom(seed: seed)
    if style == .comet { comet = CometShroud(seed: seed) }
    if style == .warp { streaks = (0..<Self.streakCount).map { _ in newStreak(anywhere: true) } }
  }

  /// Advances one tick. `velocityY` is the ship's whole-pixel change in y; `velocity` is its exact
  /// movement, used to lean the effect along a curved path.
  public mutating func tick(flying: Bool, velocityY: Int, velocity: (dx: Double, dy: Double)) {
    if comet != nil {
      let lean = abs(velocity.dy) > 0.3 ? max(-0.8, min(0.8, -velocity.dx / abs(velocity.dy))) : nil
      comet?.tick(flying: flying, velocityY: velocityY, lean: flying ? lean : nil)
      return
    }
    tickCount += 1
    level += flying ? (1 - level) * 0.25 : -level * 0.07
    if level < 0.02 { level = 0 }
    if flying && velocityY != 0 { streamDown = velocityY < 0 }
    let fall = streamDown ? 1.0 : -1.0

    switch style {
    case .warp:
      for i in streaks.indices {
        streaks[i].y += streaks[i].speed * fall
        if abs(streaks[i].y) > 95 { streaks[i] = newStreak(anywhere: false) }
      }
    case .sparkle:
      sparks.removeAll { $0.age >= $0.life }
      for i in sparks.indices {
        sparks[i].age += 1
        sparks[i].x += sparks[i].vx - velocity.dx * 0.6
        sparks[i].y += sparks[i].vy - velocity.dy * 0.6
      }
      let births = level > 0.2 ? (tickCount % 2 == 0 ? 2 : 1) : 0
      for _ in 0..<births {
        let a = random.next() * 2 * Double.pi, speed = 0.5 + random.next() * 1.6
        sparks.append(
          Spark(
            x: cos(a) * 11, y: sin(a) * 11, vx: cos(a) * speed, vy: sin(a) * speed,
            life: 20 + Int(random.next() * 20), big: random.next() < 0.45))
      }
    case .bubble:
      ripples.removeAll { $0.age >= Self.rippleLife }
      for i in ripples.indices {
        ripples[i].age += 1
        ripples[i].behind += abs(velocity.dy) * 0.8 + 0.5
      }
      if level > 0.3 && tickCount % 6 == 0 { ripples.append(Ripple(behind: 0)) }
    case .comet, .none:
      break
    }
  }

  private mutating func newStreak(anywhere: Bool) -> Streak {
    let dx = Int(random.next() * 93) - 46
    let start = anywhere ? random.next() * 180 - 90 : -90 - random.next() * 20
    return Streak(
      dx: dx, y: streamDown ? start : -start, length: 8 + Int(random.next() * 26),
      speed: 4 + random.next() * 6, wide: random.next() < 0.25)
  }

  /// The rows the effect may reach around a body whose first and last rows are `top` and `bottom`;
  /// `nil` when it draws nothing.
  public func rows(top: Int, bottom: Int) -> ClosedRange<Int>? {
    if let comet { return comet.rows(top: top, bottom: bottom) }
    guard level > 0 || !sparks.isEmpty || !ripples.isEmpty else { return nil }
    return (top - 100)...(bottom + 110)
  }

  public func draw(into b: inout PixelBuffer, ramp: ColorRamp, centerX: Int, top: Int, bottom: Int, halfWidth: Int) {
    if let comet {
      comet.draw(into: &b, ramp: ramp, centerX: centerX, top: top, bottom: bottom, halfWidth: halfWidth)
      return
    }
    let s = level, cx = centerX, cy = (top + bottom) / 2
    let down = streamDown
    func flip(_ y: Int) -> Int { down ? y : top + bottom - y }

    switch style {
    case .warp:
      guard s > 0 else { return }
      for streak in streaks.prefix(Self.round(Double(Self.streakCount) * s)) {
        let length = max(2, Self.round(Double(streak.length) * s))
        let head = cy + Self.round(streak.y)
        for k in 0..<length {
          let f = Double(k) / Double(length)
          // The bright end leads the way the line is rushing.
          let y = down ? head - k : head + k
          b.fill(x: cx + streak.dx, y: y, w: streak.wide ? 2 : 1, h: 1, ramp.step(0.1 + 0.9 * f))
        }
      }
      // Bow waves: chevrons riding ahead of the ship.
      for c in 0..<3 where s > 0.25 * Double(c) {
        let apex = top - 5 - c * 6 - (tickCount / 2) % 4
        let arm = Self.round(Double(9 + 4 * c) * s)
        for i in 0...arm where (i + tickCount / 2 + c) % 3 != 0 {
          let color = ramp.step(0.2 + 0.3 * Double(c))
          b.fill(x: cx - 1 - i, y: flip(apex + i), w: 1, h: 1, color)
          b.fill(x: cx + i, y: flip(apex + i), w: 1, h: 1, color)
        }
      }
    case .sparkle:
      for spark in sparks {
        let f = Double(spark.age) / Double(spark.life)
        if f > 0.7 && (spark.age + tickCount) % 2 == 1 { continue }
        let color = f < 0.25 ? ramp.white : ramp.step(0.3 + 0.7 * f)
        let x = cx + Self.round(spark.x), y = cy + Self.round(spark.y)
        b.fill(x: x, y: y, w: 1, h: 1, color)
        if spark.big && f < 0.55 {
          b.fill(x: x - 1, y: y, w: 3, h: 1, color)
          b.fill(x: x, y: y - 1, w: 1, h: 3, color)
        }
      }
    case .bubble:
      for ripple in ripples {
        let f = Double(ripple.age) / Double(Self.rippleLife)
        let rx = 8 + Double(ripple.age) * 0.7, ry = 3 + Double(ripple.age) * 0.15
        let base = bottom + 2 + Self.round(ripple.behind)
        let count = Self.round(rx * 3)
        for i in 0...count where f < 0.5 || (i + tickCount) % 2 == 0 {
          let a = Double.pi * Double(i) / Double(count)
          b.fill(
            x: cx + Self.round(cos(a) * rx), y: flip(base + Self.round(sin(a) * ry)), w: 1, h: 1,
            ramp.step(0.3 + 0.7 * f))
        }
      }
      guard s > 0 else { return }
      let grow = 0.55 + 0.45 * s
      let rx = Double(halfWidth + 6) * grow, ry = (Double(bottom - top) / 2 + 7) * grow
      for i in 0..<44 {
        let a = Double(i) / 44 * 2 * Double.pi
        if (i + tickCount / 3) % 6 != 0 {
          b.fill(x: cx + Self.round(cos(a) * rx), y: cy + Self.round(sin(a) * ry), w: 1, h: 1, ramp.light)
        }
        if (i + 3 - tickCount / 3 % 6 + 60) % 6 != 0 && s > 0.4 {
          b.fill(x: cx + Self.round(cos(a) * (rx - 2)), y: cy + Self.round(sin(a) * (ry - 2)), w: 1, h: 1, ramp.main)
        }
        // A glint on the upper left of the shield.
        if (27...31).contains(i) {
          b.fill(x: cx + Self.round(cos(a) * (rx - 4)), y: cy + Self.round(sin(a) * (ry - 4)), w: 1, h: 1, ramp.white)
        }
      }
    case .comet, .none:
      break
    }
  }

  private static func round(_ v: Double) -> Int { Int(v.rounded()) }
}
