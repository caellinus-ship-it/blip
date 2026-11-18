import Foundation

/// The comet look on the fly-in and fly-off: a glowing cap over the leading
/// side of the ship and creature, flame sheaths down both sides of the body,
/// a long tapering tail streaming behind, and embers left in its wake.
///
/// `strength` rises fast while flying and eases to 0 once the ship stops, and
/// every length is scaled by it, so the fire never cuts off. All randomness
/// is drawn in `tick`; `draw` only renders the stored state.
public struct CometShroud {
  /// A spark left behind the tail. It stays where it was spawned, so it falls
  /// behind the moving ship.
  private struct Ember {
    /// Where across the tail it spawned, from -0.5 (left edge) to 0.5 (right edge).
    let spread: Double
    /// Sideways drift in pixels per tick.
    let drift: Double
    /// True when it spawned below the body (the ship was moving up).
    let below: Bool
    /// How far behind the trailing edge of the body it is now, in rows.
    var behind = 0
    var age = 0
  }

  static let emberLife = 26
  /// Rows with their own wobble; longer sheaths and the tail reuse them.
  static let wobbleRows = 32

  public private(set) var strength: Double = 1

  private var random: SeededRandom
  private var tickCount = 0
  /// The tail streams below the body (the ship is moving up); mirrored otherwise.
  private var streamDown = true
  private var embers: [Ember] = []
  /// Each row's ragged edge, -1, 0 or +1, for the sheaths and the tail: left side then right side.
  private var wobble: [Int] = []

  public init(seed: UInt64) {
    random = SeededRandom(seed: seed)
    rollWobble()
  }

  /// Advances one tick. `velocityY` is the ship's change in y this tick
  /// (negative when moving up); the fire streams the opposite way. The
  /// direction only follows the ship while it is flying, so hover drift never
  /// flips a tail that is easing away.
  public mutating func tick(flying: Bool, velocityY: Int) {
    tickCount += 1
    strength += flying ? (1 - strength) * 0.25 : -strength * 0.07
    if strength < 0.02 { strength = 0 }
    if flying && velocityY != 0 { streamDown = velocityY < 0 }

    embers.removeAll { $0.age >= Self.emberLife }
    for i in embers.indices {
      embers[i].age += 1
      embers[i].behind += embers[i].below ? -velocityY : velocityY
    }
    if strength > 0.3 && tickCount % 2 == 0 {
      embers.append(Ember(spread: random.next() - 0.5, drift: (random.next() * 2 - 1) * 0.3, below: streamDown))
    }
    if tickCount % 3 == 0 { rollWobble() }
  }

  /// Draws the fire around a body whose first and last rows are `top` and
  /// `bottom`, centred on `centerX`, `halfWidth` pixels to each side.
  public func draw(into b: inout PixelBuffer, ramp: ColorRamp, centerX: Int, top: Int, bottom: Int, halfWidth: Int) {
    guard strength > 0 else { return }
    let s = strength
    // The geometry is laid out for a tail below the body, then mirrored.
    let down = streamDown
    func row(_ x: Int, _ y: Int, _ w: Int, _ color: RGBA) {
      b.fill(x: x, y: down ? y : top + bottom - y, w: w, h: 1, color)
    }

    let cx = centerX, cy = top + 4
    let baseWidth = Double(2 * halfWidth + 6)

    // Embers, where they were left; drawn first, so they show once they fall out of the tail.
    for e in embers {
      let f = Double(e.age) / Double(Self.emberLife)
      if f > 2.0 / 3 && tickCount % 2 == 1 { continue }
      let x = cx + Self.round(e.spread * baseWidth + e.drift * Double(e.age))
      let y = e.below ? bottom + 1 + e.behind : top - 1 - e.behind
      b.fill(x: x, y: y, w: 1, h: 1, f < 0.5 ? ramp.light : ramp.dark)
    }

    // The fire around the body pulls back from the front as it weakens, so it
    // dies away toward the tail instead of shrinking as a box.
    let rx = halfWidth + 3, ry = Self.round(7 * s) + 2
    let reach = min(1, max(0, (s - 0.15) / 0.6))
    let firstRow = bottom + 1 - Self.round(Double(bottom + 1 - (cy - ry)) * reach)
    func head(_ x: Int, _ y: Int, _ w: Int, _ color: RGBA) {
      if y >= firstRow { row(x, y, w, color) }
    }

    // Cap: a half ellipse over the leading side, two rings thick, its outer
    // ring flickering, filled with glow behind the creature.
    let flicker = (tickCount / 2) % 2
    Self.halfEllipse(rx: rx, ry: ry) { i, dx, dy in
      if (i + flicker) % 2 == 0 { head(cx + dx, cy + dy, 1, ramp.main) }
    }
    Self.halfEllipse(rx: rx - 1, ry: ry - 1) { _, dx, dy in head(cx + dx, cy + dy, 1, ramp.light) }
    for dy in stride(from: ry - 2, through: 1, by: -1) {
      let half = Self.round(Double(rx - 2) * (1 - pow(Double(dy) / Double(ry - 1), 2)).squareRoot())
      head(cx - half, cy - dy, 2 * half + 1, ramp.light)
    }
    head(cx - 1, cy - ry + 1, 3, ramp.white)

    // Sheaths: from the cap's ends down both sides of the body, glow between
    // them and the creature.
    let clear = halfWidth - 3  // the glow stops this far from the centre, short of the creature
    let sheathRows = max(1, bottom - cy)
    for i in 0..<sheathRows {
      let y = cy + 1 + i
      let color = ramp.step(0.25 + 0.5 * Double(i) / Double(sheathRows))
      let left = 2 + wobble[i % Self.wobbleRows], right = 2 + wobble[Self.wobbleRows + i % Self.wobbleRows]
      head(cx - rx + 2 - left, y, left, color)
      head(cx + rx - 1, y, right, color)
    }
    for y in cy...bottom {
      head(cx - rx + 2, y, rx - 1 - clear, ramp.light)
      head(cx + clear, y, rx - 1 - clear, ramp.light)
    }

    // Tail: nested flames tapering away below the body, ragged at the edges,
    // swaying, its far end dithered.
    let length = Self.round(56 * s)
    let tailWidth = baseWidth * min(1, 0.3 + s)  // a weak tail narrows as well as shortens
    for j in 0..<length {
      let f = Double(j) / Double(length)
      if f >= 0.75 && (j + tickCount) % 2 == 1 { continue }
      let width = max(1, Self.round(tailWidth * pow(1 - f, 1.6)))
      let sway = Self.round(sin(Double(j + tickCount) / 5) * 2 * f)
      let k = j % Self.wobbleRows
      let ragL = width > 2 ? wobble[k] : 0, ragR = width > 2 ? wobble[Self.wobbleRows + k] : 0
      let left = cx + sway - width / 2, y = bottom + 1 + j
      row(left - ragL, y, width + ragL + ragR, ramp.step(0.4 + 0.6 * f))
      if width > 6 { row(left + 3, y, width - 6, ramp.step(0.25 + 0.6 * f)) }
      if f < 0.3 && width > 12 { row(left + 6, y, width - 12, ramp.white) }
    }
  }

  private mutating func rollWobble() {
    wobble = (0..<2 * Self.wobbleRows).map { _ in Int(random.next() * 3) - 1 }
  }

  /// Calls `body` once per pixel of the upper half of an ellipse, in order
  /// from its left end over the top to its right end, with the pixel's index
  /// along the arc and its offset from the centre.
  private static func halfEllipse(rx: Int, ry: Int, _ body: (Int, Int, Int) -> Void) {
    let samples = 4 * (rx + ry)
    var last: (Int, Int)?
    var index = 0
    for k in 0...samples {
      let a = Double.pi + Double.pi * Double(k) / Double(samples)
      let p = (round(cos(a) * Double(rx)), round(sin(a) * Double(ry)))
      if let last, last == p { continue }
      body(index, p.0, p.1)
      index += 1
      last = p
    }
  }

  private static func round(_ v: Double) -> Int { Int(v.rounded()) }
}
