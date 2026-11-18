import Testing
@testable import BlipCore

@Suite struct CometTests {
  func lit(_ c: CometShroud, rows: Range<Int>, cols: Range<Int> = 0..<200) -> Int {
    var b = PixelBuffer(width: 200, height: 240)
    c.draw(into: &b, ramp: ColorRamp(.fire), centerX: 100, top: 60, bottom: 80, halfWidth: 12)
    var n = 0
    for y in rows { for x in cols where b.pixel(x: x, y: y) != 0 { n += 1 } }
    return n
  }
  @Test func wrapsTheBodyAndStreamsBehindWhileFlying() {
    var c = CometShroud(seed: 1)
    for _ in 0..<20 { c.tick(flying: true, velocityY: -3) }
    #expect(c.strength > 0.99)
    #expect(lit(c, rows: 50..<60) > 0)                       // cap ahead of the body
    #expect(lit(c, rows: 62..<80, cols: 84..<90) > 0)        // left sheath
    #expect(lit(c, rows: 62..<80, cols: 111..<117) > 0)      // right sheath
    #expect(lit(c, rows: 81..<127) > 60)                     // tail behind
    #expect(lit(c, rows: 0..<48) == 0)                       // nothing far ahead
  }
  @Test func bodyInteriorIsLeftClear() {
    var c = CometShroud(seed: 1)
    for _ in 0..<20 { c.tick(flying: true, velocityY: -3) }
    #expect(lit(c, rows: 64..<79, cols: 92..<109) == 0)
  }
  @Test func streamsTheOtherWayWhenMovingDown() {
    var c = CometShroud(seed: 1)
    for _ in 0..<20 { c.tick(flying: true, velocityY: 3) }
    #expect(lit(c, rows: 14..<59) > 60)                      // tail above the body
    #expect(lit(c, rows: 100..<240) == 0)
  }
  @Test func easesAwayOnArrivalWithoutACutoff() {
    var c = CometShroud(seed: 1)
    for _ in 0..<20 { c.tick(flying: true, velocityY: -3) }
    var last = c.strength, lastTail = lit(c, rows: 81..<240)
    for _ in 0..<90 {
      c.tick(flying: false, velocityY: 0)
      #expect(c.strength <= last); #expect(last - c.strength <= 0.071)
      last = c.strength
    }
    #expect(c.strength == 0); #expect(lit(c, rows: 0..<240) == 0); #expect(lastTail > 0)
  }
  @Test func flaresUpQuicklyOnDismiss() {
    var c = CometShroud(seed: 1)
    for _ in 0..<120 { c.tick(flying: false, velocityY: 0) }
    #expect(c.strength == 0)
    for _ in 0..<8 { c.tick(flying: true, velocityY: -2) }
    #expect(c.strength > 0.85)
  }
  @Test func sameSeedSamePixels() {
    func frame() -> [RGBA] {
      var c = CometShroud(seed: 5)
      for _ in 0..<40 { c.tick(flying: true, velocityY: -3) }
      var b = PixelBuffer(width: 200, height: 240)
      c.draw(into: &b, ramp: ColorRamp(.cyan), centerX: 100, top: 60, bottom: 80, halfWidth: 12); return b.pixels
    }
    #expect(frame() == frame())
  }
}
