import Testing
@testable import BlipCore

@Suite struct ShipMotionTests {
  func run(_ m: inout ShipMotion, _ n: Int) { for _ in 0..<n { m.tick() } }
  @Test func fliesInFromBelowToCentre() {
    var m = ShipMotion(bufferWidth: 400, bufferHeight: 300, hover: .still)
    #expect(m.phase == .flyIn); #expect(m.y == 330); #expect(m.flying)
    run(&m, 90)
    #expect(m.phase == .hover); #expect(m.x == 200); #expect(m.y == 150); #expect(!m.flying)
  }
  @Test func flyInEasesOut() {
    var m = ShipMotion(bufferWidth: 400, bufferHeight: 300, hover: .still)
    let y0 = m.y; run(&m, 10); let early = y0 - m.y; run(&m, 70); let y80 = m.y; run(&m, 10)
    #expect(early > y80 - m.y)
  }
  @Test func figure8StaysWithinSixByThree() {
    var m = ShipMotion(bufferWidth: 400, bufferHeight: 300, hover: .figure8); run(&m, 90)
    var xs = Set<Int>(), ys = Set<Int>()
    for _ in 0..<600 { m.tick(); xs.insert(m.x - 200); ys.insert(m.y - 150) }
    #expect(xs.min()! == -6 && xs.max()! == 6); #expect(ys.min()! == -3 && ys.max()! == 3)
  }
  @Test func dismissFliesOffTheTop() {
    var m = ShipMotion(bufferWidth: 400, bufferHeight: 300, hover: .still); run(&m, 100)
    m.dismiss(); #expect(m.phase == .flyOut); run(&m, 48)
    #expect(m.phase == .gone); #expect(m.y <= -45)
  }
  @Test func dismissDuringFlyIn() {
    var m = ShipMotion(bufferWidth: 400, bufferHeight: 300, hover: .still); run(&m, 30)
    let yAt = m.y; m.dismiss(); m.dismiss(); m.tick()
    #expect(m.phase == .flyOut); #expect(m.y <= yAt); run(&m, 60); #expect(m.phase == .gone)
    m.dismiss(); m.tick(); #expect(m.phase == .gone)
  }
  @Test func dragMovesAnchorOnlyWhileHovering() {
    var m = ShipMotion(bufferWidth: 400, bufferHeight: 300, hover: .still)
    m.drag(dx: 10, dy: 5); #expect(m.anchorX == 200)
    run(&m, 90); m.drag(dx: 10, dy: -5)
    #expect(m.anchorX == 210 && m.anchorY == 145 && m.x == 210 && m.y == 145)
  }
}
