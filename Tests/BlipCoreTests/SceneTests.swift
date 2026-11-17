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
}
