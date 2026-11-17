import Testing
@testable import BlipCore

@Suite struct TrailsTests {
  func lit(_ t: TrailSystem) -> Int {
    var b = PixelBuffer(width: 200, height: 200)
    t.draw(into: &b, ramp: ColorRamp(.cyan), silhouette: [(Art.ship(.rocket), dx: -12, dy: 0)])
    return b.pixels.filter { $0 != 0 }.count
  }
  @Test func randomIsDeterministic() {
    var a = SeededRandom(seed: 7), b = SeededRandom(seed: 7)
    let xs = (0..<5).map { _ in a.next() }, ys = (0..<5).map { _ in b.next() }
    #expect(xs == ys); #expect(xs.allSatisfy { $0 >= 0 && $0 < 1 }); #expect(Set(xs).count == 5)
  }
  @Test func everyStyleDrawsWhileFlyingAndWhileHovering() {
    for style in TrailStyle.allCases {
      var t = TrailSystem(style: style, seed: 1)
      for i in 0..<60 { t.tick(shipX: 100, shipY: 120 - i, exhaustY: 129 - i, flying: true) }
      #expect(lit(t) > 0, "\(style) flying")
      for _ in 0..<300 { t.tick(shipX: 100, shipY: 60, exhaustY: 69, flying: false) }
      #expect(lit(t) > 0, "\(style) hovering")
    }
  }
  @Test func powerEasesWithoutJumps() {
    var t = TrailSystem(style: .flame, seed: 1); var last = t.power
    #expect(last == 1)
    for _ in 0..<240 {
      t.tick(shipX: 0, shipY: 0, exhaustY: 0, flying: false)
      #expect(t.power <= last); #expect(last - t.power <= 0.036); last = t.power
    }
    #expect(last < 0.01)
  }
  @Test func lightningHasThreeBoltsThatShrinkGradually() {
    var t = TrailSystem(style: .lightning, seed: 3)
    for _ in 0..<30 { t.tick(shipX: 100, shipY: 50, exhaustY: 59, flying: true) }
    #expect(t.boltLengths.count == 3); #expect(t.boltLengths[1] == 36)
    #expect(t.boltLengths[0] == 26 && t.boltLengths[2] == 26)
    var prev = t.boltLengths[1]
    for _ in 0..<300 {
      t.tick(shipX: 100, shipY: 50, exhaustY: 59, flying: false)
      #expect(prev - t.boltLengths[1] <= 3); prev = t.boltLengths[1]
    }
    #expect(prev == 15)
  }
  @Test func sameSeedSamePixels() {
    func frame() -> [RGBA] {
      var t = TrailSystem(style: .confetti, seed: 9)
      for _ in 0..<80 { t.tick(shipX: 100, shipY: 50, exhaustY: 59, flying: true) }
      var b = PixelBuffer(width: 200, height: 200); t.draw(into: &b, ramp: ColorRamp(.fire), silhouette: []); return b.pixels
    }
    #expect(frame() == frame())
  }
}
