import Testing
@testable import BlipCore

@Suite struct ArtTests {
  @Test func creatureSpritesAre16x13() {
    for c in Creature.allCases {
      let s = Art.creature(c).sprite
      #expect(s.height == 13); #expect(s.rows.allSatisfy { $0.count == 16 })
    }
  }
  @Test func shipSpritesAre24Wide() {
    for s in Ship.allCases { #expect(Art.ship(s).rows.allSatisfy { $0.count == 24 }) }
  }
  @Test func onlyGhostAndAlienWiggle() {
    #expect(Creature.allCases.filter { Art.creature($0).wiggles } == [.ghost, .alien])
  }
  @Test func eyesAndMouthMatchTheSprites() {
    for c in Creature.allCases {
      let art = Art.creature(c), rows = art.sprite.rows.map { Array($0) }
      switch art.eyes {
      case .pair(let l, let r):
        for e in [l, r] {
          #expect(String([rows[e.y][e.x], rows[e.y][e.x + 1]]) == "ow", "\(c)")
          #expect(String([rows[e.y + 1][e.x], rows[e.y + 1][e.x + 1]]) == "oo", "\(c)")
        }
      case .framed(let cell, let w, let h):
        for y in cell.y..<(cell.y + h) { for x in cell.x..<(cell.x + w) { #expect("ow".contains(rows[y][x]), "\(c)") } }
      }
      #expect(art.mouth.x + 1 < 16 && art.mouth.y < 11, "\(c) mouth starts above the ship")
    }
  }
  @Test func everySpriteKeyHasAColor() {
    let creatureKeys = Set(Art.creaturePalette(Art.creature(.blob)).keys), shipKeys = Set(Art.shipPalette(trim: 1).keys)
    for c in Creature.allCases { for k in Art.creature(c).sprite.rows.joined() where k != "." { #expect(creatureKeys.contains(k), "\(c) \(k)") } }
    for s in Ship.allCases { for k in Art.ship(s).rows.joined() where k != "." { #expect(shipKeys.contains(k), "\(s) \(k)") } }
    #expect(Art.creaturePalette(Art.creature(.cat), blink: true)["W"] == Art.white)  // whiskers stay through a blink
  }
  @Test func rampSteps() {
    let r = ColorRamp(.cyan)
    #expect(r.white == 0xFFFFFFFF); #expect(r.main == 0x22D3EEFF)
    #expect(r.step(0) == r.white); #expect(r.step(0.3) == r.light)
    #expect(r.step(0.6) == r.main); #expect(r.step(0.99) == r.dark); #expect(r.step(1.5) == r.dark)
  }
  @Test func customRampDerivesLightAndDark() {
    let r = ColorRamp(.custom(0x808080FF))
    #expect(r.main == 0x808080FF); #expect(r.light == 0xC0C0C0FF); #expect(r.dark == 0x404040FF)
  }
  @Test func drawSkipsDotsAndDithers() {
    var b = PixelBuffer(width: 4, height: 2)
    b.draw(Sprite(rows: ["X.XX", "XXXX"]), x: 0, y: 0, palette: ["X": 5])
    #expect(b.pixels == [5, 0, 5, 5, 5, 5, 5, 5])
    b.clear(); b.draw(Sprite(rows: ["XXXX", "XXXX"]), x: 0, y: 0, palette: [:], mono: 7, dither: true)
    #expect(b.pixels == [7, 0, 7, 0, 0, 7, 0, 7])
  }
}
