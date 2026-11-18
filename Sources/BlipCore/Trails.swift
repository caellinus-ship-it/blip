import Foundation

/// The six exhaust trails, ported from `trail()` in `docs/reference/mockup.html`.
public enum TrailStyle: String, Codable, CaseIterable {
  case comet, flame, rings, echoes, lightning, confetti
}

/// A SplitMix64 generator: the same seed always gives the same sequence.
public struct SeededRandom {
  private var state: UInt64

  public init(seed: UInt64) {
    state = seed
  }

  /// The next value in `0..<1`.
  public mutating func next() -> Double {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Double(z >> 11) * 0x1.0p-53
  }
}

/// One trail's state on the fixed 60 Hz tick, in arcade pixels.
///
/// `power` eases between 1 (flying) and 0 (hovering), and every length and
/// rate is computed from it, so nothing changes abruptly when the ship stops.
/// All randomness is drawn in `tick`; `draw` only renders the stored state.
public struct TrailSystem {
  /// A moving trail element: a comet point, ring, echo or confetti piece.
  private struct Particle {
    var x: Double
    var y: Double
    var age = 0
    let life: Double
    var vx = 0.0
    var vy = 0.0
    var shape = 0
    var tint = 0

    var fraction: Double { Double(age) / life }
  }

  /// One row of a flame: its sideways offset and width.
  private struct FlameRow {
    let offset: Int
    let width: Int
  }

  /// One row of a bolt: its sideways offset and which side a fork would go.
  private struct BoltRow {
    let offset: Int
    let forkRight: Bool
  }

  public let style: TrailStyle
  public private(set) var power: Double = 1

  private var random: SeededRandom
  private var tickCount = 0
  private var ticksSinceSpawn = 0
  private var shipX = 0
  private var shipY = 0
  private var exhaustY = 0
  private var particles: [Particle] = []
  private var flame: [FlameRow] = []
  private var sparks: [(dx: Int, dy: Int)] = []
  private var bolts: [[BoltRow]] = [[], [], []]

  public init(style: TrailStyle, seed: UInt64) {
    self.style = style
    random = SeededRandom(seed: seed)
  }

  /// The row counts of the three lightning bolts (left, middle, right);
  /// all zero for the other styles.
  public var boltLengths: [Int] { bolts.map(\.count) }

  /// True when nothing is left to draw: no particles, and no flame or bolts.
  public var isEmpty: Bool {
    particles.isEmpty && flame.isEmpty && sparks.isEmpty && bolts.allSatisfy(\.isEmpty)
  }

  /// Advances the trail one tick. `(shipX, shipY)` is the top-centre of the
  /// ship; `exhaustY` is the row just below it. With `emitting` false (the
  /// ship has gone) nothing new appears: particles already out keep moving and
  /// ageing, and the flame and bolts, which hang off the ship, go out.
  public mutating func tick(shipX: Int, shipY: Int, exhaustY: Int, flying: Bool, emitting: Bool = true) {
    tickCount += 1
    power += ((flying ? 1 : 0) - power) * 0.035
    self.shipX = shipX
    self.shipY = shipY
    self.exhaustY = exhaustY
    particles.removeAll { Double($0.age) >= $0.life }

    guard emitting else {
      flame = []
      sparks = []
      bolts = [[], [], []]
      ageParticles()
      return
    }
    switch style {
    case .comet: tickComet()
    case .flame: tickFlame()
    case .rings: tickRings()
    case .echoes: tickEchoes()
    case .lightning: tickLightning()
    case .confetti: tickConfetti()
    }
  }

  /// Draws the trail. `silhouette` is the creature and ship sprites with their
  /// offsets from the ship's top-centre; only `echoes` uses it.
  public func draw(into b: inout PixelBuffer, ramp: ColorRamp, silhouette: [(Sprite, dx: Int, dy: Int)]) {
    switch style {
    case .comet: drawComet(into: &b, ramp: ramp)
    case .flame: drawFlame(into: &b, ramp: ramp)
    case .rings: drawRings(into: &b, ramp: ramp)
    case .echoes: drawEchoes(into: &b, ramp: ramp, silhouette: silhouette)
    case .lightning: drawLightning(into: &b, ramp: ramp)
    case .confetti: drawConfetti(into: &b, ramp: ramp)
    }
  }

  // MARK: - Tick

  /// True once every `interval` ticks, counted from the last spawn, so a
  /// changing interval never causes a burst or a gap.
  private mutating func spawnDue(every interval: Int) -> Bool {
    ticksSinceSpawn += 1
    guard ticksSinceSpawn >= interval else { return false }
    ticksSinceSpawn = 0
    return true
  }

  private mutating func tickComet() {
    particles.append(Particle(x: Double(shipX), y: Double(exhaustY), life: 28 + 18 * power))
    ageParticles()
  }

  private mutating func tickFlame() {
    guard tickCount % 3 == 0 || flame.isEmpty else { return }
    let length = Int((6 + 12 * power).rounded()) + Int(random.next() * 4)
    flame = (0..<length).map { j in
      let f = Double(j) / Double(length)
      let width = max(1, Int(((1 - f) * 7).rounded())) + (random.next() > 0.6 ? 1 : 0)
      let offset = Int(((random.next() - 0.5) * f * 4).rounded())
      return FlameRow(offset: offset, width: width)
    }
    sparks = (0..<5).map { _ in
      (dx: Int(((random.next() - 0.5) * 18).rounded()), dy: Int((random.next() * Double(length)).rounded()))
    }
  }

  private mutating func tickRings() {
    if spawnDue(every: Int((26 - 18 * power).rounded())) {
      particles.append(Particle(x: Double(shipX), y: Double(exhaustY), life: 44))
    }
    ageParticles()
  }

  private mutating func tickEchoes() {
    if tickCount % 4 == 0 {
      particles.append(Particle(x: Double(shipX), y: Double(shipY), life: 24))
    }
    ageParticles()
  }

  private mutating func tickLightning() {
    let middle = 15 + 21 * power
    for b in 0..<3 where (tickCount + b) % 3 == 0 || bolts[b].isEmpty {
      let dir = Double(b - 1)
      let length = Int((b == 1 ? middle : middle * 0.72).rounded())
      var offset = (b - 1) * 4
      bolts[b] = (0..<length).map { _ in
        offset += Int(((random.next() - 0.5) * 2.6 + dir * 0.45).rounded())
        return BoltRow(offset: offset, forkRight: random.next() > 0.5)
      }
    }
  }

  private mutating func tickConfetti() {
    if spawnDue(every: Int((9 - 7 * power).rounded())) {
      let x = Double(shipX) + (random.next() - 0.5) * 12
      let vx = (random.next() - 0.5) * 0.8
      let vy = 1.0 / 3 + (1.0 / 6 + random.next() * 4 / 6) * (0.5 + 0.5 * power)
      let shape = Int(random.next() * 3), tint = Int(random.next() * 3)
      particles.append(
        Particle(x: x, y: Double(exhaustY), life: 36 + 24 * power, vx: vx, vy: vy, shape: shape, tint: tint))
    }
    ageParticles()
  }

  /// Moves every particle on by one tick, the way its style moves it.
  private mutating func ageParticles() {
    for i in particles.indices {
      particles[i].age += 1
      switch style {
      case .comet: particles[i].y += 0.5 + 0.5 * power
      case .rings: particles[i].y += 0.4 + 0.33 * power
      case .echoes: particles[i].y += 0.53 * (1 - power)
      case .confetti:
        let p = particles[i]
        particles[i].x += p.vx + sin(Double(p.age + p.shape * 9) / 6) * 0.27
        particles[i].y += p.vy
      case .flame, .lightning: break
      }
    }
  }

  // MARK: - Draw

  private func drawComet(into b: inout PixelBuffer, ramp: ColorRamp) {
    let widths = [9, 7, 5, 3, 1]
    for p in particles {
      let f = p.fraction
      if f > 0.65 && p.age % 2 == 1 { continue }
      let x = Int(p.x), y = Int(p.y.rounded())
      let w = widths[min(4, Int(f * 5))]
      b.fill(x: x - w / 2, y: y, w: w, h: 1, ramp.step(f))
      if f < 0.3 { b.fill(x: x - 1, y: y, w: 3, h: 1, ramp.white) }
    }
  }

  private func drawFlame(into b: inout PixelBuffer, ramp: ColorRamp) {
    let length = flame.count
    for (j, row) in flame.enumerated() {
      let f = Double(j) / Double(length)
      let left = shipX + row.offset - (row.width + 1) / 2
      b.fill(x: left, y: exhaustY + j, w: row.width, h: 1, ramp.step(f))
      if f < 0.45 && row.width > 3 {
        b.fill(x: left + 2, y: exhaustY + j, w: row.width - 4, h: 1, ramp.white)
      }
    }
    for s in sparks {
      b.fill(x: shipX + s.dx, y: exhaustY + s.dy, w: 1, h: 1, ramp.main)
    }
  }

  private func drawRings(into b: inout PixelBuffer, ramp: ColorRamp) {
    for p in particles {
      let f = p.fraction
      let rx = 2.7 + 0.3 * Double(p.age)
      let count = Int((2 * Double.pi * rx).rounded(.up))
      let color = ramp.step(f)
      for k in 0..<count {
        if f > 0.5 && k % 2 == 1 { continue }
        let angle = Double(k) / Double(count) * 2 * Double.pi
        let x = Int((p.x + cos(angle) * rx).rounded())
        let y = Int((p.y + sin(angle) * rx * 0.4).rounded())
        b.fill(x: x, y: y, w: 1, h: 1, color)
      }
    }
  }

  private func drawEchoes(into b: inout PixelBuffer, ramp: ColorRamp, silhouette: [(Sprite, dx: Int, dy: Int)]) {
    for p in particles {
      let f = p.fraction
      let color = ramp.step(0.25 + 0.75 * f)
      let x = Int(p.x), y = Int(p.y.rounded())
      for (sprite, dx, dy) in silhouette {
        b.draw(sprite, x: x + dx, y: y + dy, palette: [:], mono: color, dither: f > 0.3)
      }
    }
  }

  private func drawLightning(into b: inout PixelBuffer, ramp: ColorRamp) {
    for (bolt, rows) in bolts.enumerated() {
      let isMiddle = bolt == 1
      let length = Double(rows.count)
      for (j, row) in rows.enumerated() {
        let f = Double(j) / length
        if f > 0.82 && j % 2 == 1 { continue }
        let w = isMiddle ? (f > 0.6 ? 2 : 3) : (f > 0.5 ? 1 : 2)
        let color = ramp.step(0.25 + 0.75 * f)
        let x = shipX + row.offset, y = exhaustY + j
        b.fill(x: x - (w > 2 ? 1 : 0), y: y, w: w, h: 1, color)
        if j % 6 == 3 && f < 0.8 {
          b.fill(x: x + (row.forkRight ? w : -2), y: y + 1, w: 2, h: 1, color)
        }
        if f < (isMiddle ? 0.55 : 0.3) { b.fill(x: x, y: y, w: 1, h: 1, ramp.white) }
      }
    }
    if tickCount % 4 < 2 && !bolts[1].isEmpty { b.fill(x: shipX - 5, y: exhaustY, w: 10, h: 1, ramp.white) }
  }

  private func drawConfetti(into b: inout PixelBuffer, ramp: ColorRamp) {
    let tints = [ramp.white, ramp.light, ramp.main]
    for p in particles {
      if p.fraction > 0.7 && tickCount % 2 == 1 { continue }
      b.draw(
        Art.confetti[p.shape], x: Int(p.x.rounded()), y: Int(p.y.rounded()), palette: [:], mono: tints[p.tint])
    }
  }
}
