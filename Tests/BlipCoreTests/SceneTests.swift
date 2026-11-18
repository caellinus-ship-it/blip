import Testing
@testable import BlipCore

@Suite struct SceneTests {
  func frame(_ s: Scene) -> PixelBuffer { var b = PixelBuffer(width: 240, height: 200); s.render(into: &b); return b }
  @Test func everyCombinationRendersInsideTheBuffer() {
    for c in Creature.allCases { for sh in Ship.allCases { for t in TrailStyle.allCases {
      var set = BlipSettings(); set.creature = c; set.ship = sh; set.trail = t
      var s = Scene(settings: set, bufferWidth: 240, bufferHeight: 200, seed: 1)
      for _ in 0..<200 { s.tick() }
      #expect(s.phase == .hover); #expect(frame(s).pixels.contains { $0 != 0 })
    } } }
  }
  @Test func shipSitsAtTheAnchorAndHitRectCoversIt() {
    var set = BlipSettings(); set.hover = .still
    var s = Scene(settings: set, bufferWidth: 240, bufferHeight: 200, seed: 1)
    for _ in 0..<120 { s.tick() }
    #expect(s.anchor.x == 120 && s.anchor.y == 100)
    let r = s.hitRect; #expect(r.x == 108 && r.y == 88 && r.w == 24 && r.h == 21)
    #expect(frame(s).pixel(x: 120, y: 101) != 0)
  }
  @Test func nothingIsDrawnOnceGone() {
    var s = Scene(settings: BlipSettings(), bufferWidth: 240, bufferHeight: 200, seed: 1)
    for _ in 0..<100 { s.tick() }; s.dismiss(); for _ in 0..<400 { s.tick() }
    #expect(s.phase == .gone); #expect(frame(s).pixels.allSatisfy { $0 == 0 })
  }
  @Test func thinkingSpinsTheAuraFaster() {
    var set = BlipSettings(); set.hover = .still; set.trail = .flame
    var a = Scene(settings: set, bufferWidth: 240, bufferHeight: 200, seed: 1), b = a
    for _ in 0..<120 { a.tick(); b.tick() }
    #expect(frame(a).pixels == frame(b).pixels)
    b.thinking = true; for _ in 0..<6 { a.tick(); b.tick() }
    #expect(frame(a).pixels != frame(b).pixels)
  }
  @Test func cometShowsInFlightAndIsGoneInHover() {
    var set = BlipSettings(); set.hover = .still; set.trail = .rings
    var s = Scene(settings: set, bufferWidth: 240, bufferHeight: 200, seed: 1)
    for _ in 0..<45 { s.tick() }
    var flying = PixelBuffer(width: 240, height: 200); s.render(into: &flying)
    for _ in 0..<255 { s.tick() }
    var hovering = PixelBuffer(width: 240, height: 200); s.render(into: &hovering)
    #expect(flying.pixels.filter { $0 != 0 }.count > hovering.pixels.filter { $0 != 0 }.count + 150)
  }
  @Test func cometOffMatchesNoShroud() {
    var on = BlipSettings(); on.hover = .still; on.trail = .rings
    var off = on; off.comet = false
    var a = Scene(settings: on, bufferWidth: 240, bufferHeight: 200, seed: 1)
    var b = Scene(settings: off, bufferWidth: 240, bufferHeight: 200, seed: 1)
    for _ in 0..<45 { a.tick(); b.tick() }
    var fa = PixelBuffer(width: 240, height: 200), fb = PixelBuffer(width: 240, height: 200)
    a.render(into: &fa); b.render(into: &fb)
    #expect(fa.pixels.filter { $0 != 0 }.count > fb.pixels.filter { $0 != 0 }.count + 150)
    for _ in 0..<255 { a.tick(); b.tick() }
    fa.clear(); fb.clear(); a.render(into: &fa); b.render(into: &fb)
    #expect(fa.pixels == fb.pixels)
  }
  @Test func arrivalOvershootsThenSettles() {
    var set = BlipSettings(); set.hover = .still
    var s = Scene(settings: set, bufferWidth: 240, bufferHeight: 200, seed: 1)
    var minY = Int.max
    for _ in 0..<110 { s.tick(); minY = min(minY, s.hitRect.y + 12) }
    #expect(minY == 98); #expect(s.hitRect.y + 12 == 100)
  }
  @Test func launchShakesForTenTicks() {
    var set = BlipSettings(); set.hover = .still; set.flightPath = .straight
    var s = Scene(settings: set, bufferWidth: 240, bufferHeight: 200, seed: 1)
    var xs: [Int] = []
    for _ in 0..<20 { s.tick(); xs.append(s.hitRect.x + 12) }
    #expect(xs == [121, 119, 121, 119, 121, 119, 121, 119, 121, 119] + Array(repeating: 120, count: 10))
  }
  @Test func cometTailFinishesLeavingAfterTheShipIsGone() {
    var on = BlipSettings(); on.hover = .still; on.trail = .rings
    var off = on; off.comet = false
    var a = Scene(settings: on, bufferWidth: 240, bufferHeight: 200, seed: 1)
    var b = Scene(settings: off, bufferWidth: 240, bufferHeight: 200, seed: 1)
    for _ in 0..<120 { a.tick(); b.tick() }
    a.dismiss(); b.dismiss()
    while a.phase != .gone { a.tick(); b.tick() }
    #expect(frame(a).pixels.filter { $0 != 0 }.count > frame(b).pixels.filter { $0 != 0 }.count + 20)
    for _ in 0..<60 { a.tick(); b.tick() }
    #expect(frame(a).pixels.allSatisfy { $0 == 0 }); #expect(frame(b).pixels.allSatisfy { $0 == 0 })
  }
  @Test func lingerEndsWhenNothingIsLeftToDraw() {
    for trail in TrailStyle.allCases { for comet in [false, true] {
      var set = BlipSettings(); set.hover = .still; set.trail = trail; set.comet = comet
      var s = Scene(settings: set, bufferWidth: 240, bufferHeight: 200, seed: 1)
      for _ in 0..<120 { s.tick() }; s.dismiss()
      while s.phase != .gone { s.tick() }
      // Flame and lightning hang off the ship and go with it; everything else is still in view.
      if comet || ![.flame, .lightning].contains(trail) { #expect(!s.isFinished, "\(trail) comet \(comet)") }
      var n = 0
      while !s.isFinished && n < 100 { s.tick(); n += 1 }
      #expect(n <= 60, "\(trail) comet \(comet)"); #expect(frame(s).pixels.allSatisfy { $0 == 0 })
    } }
    var set = BlipSettings(); set.hover = .still; set.trail = .echoes; set.comet = false
    var s = Scene(settings: set, bufferWidth: 240, bufferHeight: 200, seed: 1)
    for _ in 0..<120 { s.tick() }; s.dismiss()
    while s.phase != .gone { s.tick() }
    var n = 0
    while !s.isFinished { s.tick(); n += 1 }
    #expect(n < 40)   // echoes last 24 ticks; the linger does not run its full 60
  }
  @Test func auraAndShipStayWithinTheReachTheDragClampUses() {
    let r = ShipMotion.drawnReach
    for c in Creature.allCases { for sh in Ship.allCases {
      var set = BlipSettings(); set.creature = c; set.ship = sh; set.hover = .still; set.comet = false; set.trail = .rings
      var s = Scene(settings: set, bufferWidth: 240, bufferHeight: 200, seed: 1)
      for _ in 0..<150 { s.tick() }
      let (ax, ay) = s.anchor
      #expect(s.hitRect.x >= ax - r.left && s.hitRect.x + s.hitRect.w - 1 <= ax + r.right)
      #expect(s.hitRect.y >= ay - r.up && s.hitRect.y + s.hitRect.h - 1 <= ay + r.down)
      for _ in 0..<40 {
        s.tick()
        let b = frame(s)
        // Rows above the exhaust hold only the aura, the creature, the dome and the ship.
        for y in 0..<(ay + 9) { for x in 0..<240 where b.pixel(x: x, y: y) != 0 {
          #expect(x >= ax - r.left && x <= ax + r.right && y >= ay - r.up, "\(c) \(sh) (\(x), \(y))")
        } }
      }
    } }
  }
  @Test func draggingIntoACornerKeepsTheShipInside() {
    var s = Scene(settings: BlipSettings(), bufferWidth: 240, bufferHeight: 200, seed: 1)
    for _ in 0..<150 { s.tick() }
    s.drag(dx: -999, dy: -999)
    for _ in 0..<200 { s.tick(); #expect(s.hitRect.x >= 0 && s.hitRect.y >= 0) }
    s.drag(dx: 999, dy: 999)
    for _ in 0..<200 {
      s.tick(); #expect(s.hitRect.x + s.hitRect.w <= 240 && s.hitRect.y + s.hitRect.h <= 200)
    }
  }
}
