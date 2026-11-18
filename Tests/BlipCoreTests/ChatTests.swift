import Testing
@testable import BlipCore

@Suite struct ChatTests {
  @Test func imageSizingFits() {
    #expect(ImageSizing.fit(width: 5120, height: 2880, maxLongEdge: 1568) == (1568, 882))
    #expect(ImageSizing.fit(width: 1000, height: 3000, maxLongEdge: 1568) == (523, 1568))
    #expect(ImageSizing.fit(width: 800, height: 600, maxLongEdge: 1568) == (800, 600))
    #expect(ImageSizing.fit(width: 10000, height: 1, maxLongEdge: 100) == (100, 1))
  }
}
