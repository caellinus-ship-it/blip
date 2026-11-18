import Testing
@testable import BlipCore

@Suite struct ThumbnailsTests {
  @Test func sizesAndContent() {
    for c in Creature.allCases {
      let b = Thumbnail.creature(c)
      #expect(b.width == 18 && b.height == 15); #expect(b.pixels.contains { $0 != 0 })
      #expect(b.pixel(x: 0, y: 0) == 0)
    }
    for s in Ship.allCases { let b = Thumbnail.ship(s); #expect(b.width == 26 && b.height == 11); #expect(b.pixels.contains { $0 != 0 }) }
    for t in TrailStyle.allCases {
      let b = Thumbnail.trail(t, ramp: ColorRamp(.cyan))
      #expect(b.width == 36 && b.height == 44); #expect(b.pixels.contains { $0 != 0 })
      #expect(b.pixels == Thumbnail.trail(t, ramp: ColorRamp(.cyan)).pixels)
    }
    #expect(Set(TrailStyle.allCases.map { Thumbnail.trail($0, ramp: ColorRamp(.fire)).pixels }).count == 6)
  }
}
