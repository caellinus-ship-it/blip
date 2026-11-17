import Foundation

/// How the ship drifts while it hovers in place.
public enum HoverMotion: String, Codable, CaseIterable { case figure8, bob, still }

/// The ship's life cycle: fly in from below, hover, fly off the top, gone.
public enum Phase: Equatable { case flyIn, hover, flyOut, gone }

/// The ship's position on a fixed 60 Hz tick, in whole arcade pixels.
/// `(x, y)` is the top-centre of the ship sprite; `(anchorX, anchorY)` is the hover centre.
public struct ShipMotion {
  static let flyInTicks = 90
  static let flyOutTicks = 48
  static let flyInDepth = 30  // starts this far below the bottom edge
  static let flyOutY = -45

  public private(set) var phase: Phase = .flyIn
  public private(set) var x: Int
  public private(set) var y: Int
  public private(set) var anchorX: Int
  public private(set) var anchorY: Int

  private let hover: HoverMotion
  /// Ticks spent in the current phase.
  private var phaseTicks = 0
  /// Where the current fly-in or fly-off began.
  private var fromY: Int

  public var flying: Bool { phase == .flyIn || phase == .flyOut }

  public init(bufferWidth: Int, bufferHeight: Int, hover: HoverMotion) {
    self.hover = hover
    anchorX = bufferWidth / 2
    anchorY = bufferHeight / 2
    x = anchorX
    fromY = bufferHeight + Self.flyInDepth
    y = fromY
  }

  public mutating func tick() {
    switch phase {
    case .flyIn:
      phaseTicks += 1
      if phaseTicks >= Self.flyInTicks {
        phase = .hover; phaseTicks = 0; placeAtHoverOffset()
      } else {
        let p = Double(phaseTicks) / Double(Self.flyInTicks)
        y = Self.lerp(fromY, anchorY, 1 - pow(1 - p, 3))
      }
    case .hover:
      phaseTicks += 1
      placeAtHoverOffset()
    case .flyOut:
      phaseTicks += 1
      if phaseTicks >= Self.flyOutTicks {
        phase = .gone; y = Self.flyOutY
      } else {
        let p = Double(phaseTicks) / Double(Self.flyOutTicks)
        y = Self.lerp(fromY, Self.flyOutY, pow(p, 3))
      }
    case .gone:
      break
    }
  }

  /// Starts the fly-off from wherever the ship is now. Ignored once it is already leaving.
  public mutating func dismiss() {
    guard phase == .flyIn || phase == .hover else { return }
    phase = .flyOut; phaseTicks = 0; fromY = y
  }

  /// Moves the hover centre, and the ship with it. Ignored outside `hover`.
  public mutating func drag(dx: Int, dy: Int) {
    guard phase == .hover else { return }
    anchorX += dx; anchorY += dy
    placeAtHoverOffset()
  }

  private mutating func placeAtHoverOffset() {
    let h = 1.3 * Double(phaseTicks) / 60
    switch hover {
    case .figure8:
      x = anchorX + Int((6 * sin(h)).rounded())
      y = anchorY + Int((3 * sin(2 * h)).rounded())
    case .bob:
      x = anchorX
      y = anchorY + Int((3 * sin(h)).rounded())
    case .still:
      x = anchorX; y = anchorY
    }
  }

  private static func lerp(_ a: Int, _ b: Int, _ t: Double) -> Int {
    Int((Double(a) + Double(b - a) * t).rounded())
  }
}
