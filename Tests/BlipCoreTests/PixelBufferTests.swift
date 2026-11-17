import Testing
@testable import BlipCore

@Suite struct PixelBufferTests {
  @Test func fillSetsPixels() {
    var b = PixelBuffer(width: 4, height: 3)
    b.fill(x: 1, y: 1, w: 2, h: 1, 0xFF0000FF)
    #expect(b.pixel(x: 1, y: 1) == 0xFF0000FF)
    #expect(b.pixel(x: 2, y: 1) == 0xFF0000FF)
    #expect(b.pixel(x: 3, y: 1) == 0)
    #expect(b.pixel(x: 1, y: 0) == 0)
  }
  @Test func fillClips() {
    var b = PixelBuffer(width: 4, height: 3)
    b.fill(x: -2, y: -2, w: 3, h: 3, 0x00FF00FF)   // only (0,0) lands
    b.fill(x: 3, y: 2, w: 10, h: 10, 0x0000FFFF)   // only (3,2) lands
    b.fill(x: 9, y: 9, w: 1, h: 1, 0xFFFFFFFF)     // nothing, no crash
    #expect(b.pixels.filter { $0 != 0 }.count == 2)
    #expect(b.pixel(x: -1, y: 0) == 0)
  }
  @Test func clearEmpties() {
    var b = PixelBuffer(width: 2, height: 2); b.fill(x: 0, y: 0, w: 2, h: 2, 1); b.clear()
    #expect(b.pixels.allSatisfy { $0 == 0 })
  }
}
