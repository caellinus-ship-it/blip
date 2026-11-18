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
    #expect(lit(c, rows: 64..<79, cols: 92..<108) == 0)
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
  @Test func fireHugsTheSpritesEvenly() {
    // The sprites span x-8...x+7 and x-12...x+11: centred half a pixel left of x (here 99.5).
    var c = CometShroud(seed: 1)
    for _ in 0..<20 { c.tick(flying: true, velocityY: -3) }
    var b = PixelBuffer(width: 200, height: 240)
    c.draw(into: &b, ramp: ColorRamp(.fire), centerX: 100, top: 60, bottom: 80, halfWidth: 12)
    for y in 50..<65 {
      let cols = (0..<200).filter { b.pixel(x: $0, y: y) != 0 }
      if let l = cols.first, let r = cols.last { #expect(l + r == 199, "row \(y): \(l)...\(r)") }
    }
    #expect(lit(c, rows: 64..<79, cols: 91..<92) == 15)      // glow touches the creature's left side
    #expect(lit(c, rows: 64..<79, cols: 108..<109) == 15)    // and its right side
  }
  @Test func embersSpawnWithinTheCurrentTailWidth() {
    var widest = 0, seen = 0
    for seed in UInt64(1)...100 {
      var c = CometShroud(seed: seed)
      for _ in 0..<60 { c.tick(flying: false, velocityY: 0) }       // faded out, no embers left
      c.tick(flying: true, velocityY: -60); c.tick(flying: true, velocityY: -60)  // first ember, at strength 0.44
      c.tick(flying: true, velocityY: -60)                           // carried 60 rows behind, past the tail
      var b = PixelBuffer(width: 200, height: 240)
      c.draw(into: &b, ramp: ColorRamp(.fire), centerX: 100, top: 60, bottom: 80, halfWidth: 12)
      for y in 140..<240 { for x in 0..<200 where b.pixel(x: x, y: y) != 0 { seen += 1; widest = max(widest, abs(x - 100)) } }
    }
    #expect(seen > 50)
    // The tail is 30 * (0.3 + 0.44) = 22 wide then, so its embers stay within 11 of the centre.
    #expect(widest <= 11)
  }
}
