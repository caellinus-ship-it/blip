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
  /// How far to the side the curved paths reach, in arcade pixels.
  static let curveReach = 44.0
  static let swoopReach = 26.0
  static let spiralReach = 18.0
  static let flyInDepth = 30  // starts this far below the bottom edge
  static let flyOutY = -45
  /// How far the ship's drawing reaches from its top-centre `(x, y)`, in arcade pixels: the aura's outer
  /// ring (`Scene.drawAura`), which also covers the creature, the dome and the ship. Drags keep all of it
  /// inside the buffer.
  public static let drawnReach = (left: 19, right: 19, up: 21, down: 13)

  public private(set) var phase: Phase = .flyIn
  public private(set) var x: Int
  public private(set) var y: Int
  public private(set) var anchorX: Int
  public private(set) var anchorY: Int

  /// The ship's exact movement this tick, before rounding, in arcade pixels (y negative when rising).
  public private(set) var velocity: (dx: Double, dy: Double) = (0, 0)

  private let hover: HoverMotion
  private let path: FlightPath
  private let flyInTicks: Int
  private let flyOutTicks: Int
  /// The exact position the rounded `x`, `y` come from.
  private var exact: (x: Double, y: Double) = (0, 0)
  /// Where the current fly-off began, sideways.
  private var fromX = 0
  private let bufferWidth: Int
  private let bufferHeight: Int
  /// Ticks spent in the current phase.
  private var phaseTicks = 0
  /// Where the current fly-in or fly-off began.
  private var fromY: Int

  public var flying: Bool { phase == .flyIn || phase == .flyOut }

  public init(
    bufferWidth: Int, bufferHeight: Int, hover: HoverMotion, path: FlightPath = .straight,
    speed: FlightSpeed = .normal
  ) {
    self.hover = hover
    self.path = path
    (flyInTicks, flyOutTicks) = speed == .normal ? (Self.flyInTicks, Self.flyOutTicks) : speed.ticks
    self.bufferWidth = bufferWidth
    self.bufferHeight = bufferHeight
    anchorX = bufferWidth / 2
    anchorY = bufferHeight / 2
    x = anchorX
    fromY = bufferHeight + Self.flyInDepth
    y = fromY
    x = anchorX + Int(sideways(arriving: 0).rounded())
    exact = (Double(x), Double(y))
  }

  public mutating func tick() {
    let before = exact
    switch phase {
    case .flyIn:
      phaseTicks += 1
      if phaseTicks >= flyInTicks {
        phase = .hover; phaseTicks = 0; placeAtHoverOffset()
        exact = (Double(x), Double(y))
      } else {
        let e = 1 - pow(1 - Double(phaseTicks) / Double(flyInTicks), 3)
        place(Double(anchorX) + sideways(arriving: e), Double(fromY) + Double(anchorY - fromY) * e)
      }
    case .hover:
      phaseTicks += 1
      placeAtHoverOffset()
      exact = (Double(x), Double(y))
    case .flyOut:
      phaseTicks += 1
      if phaseTicks >= flyOutTicks {
        phase = .gone; y = Self.flyOutY
        exact.y = Double(y)
      } else {
        let e = pow(Double(phaseTicks) / Double(flyOutTicks), 3)
        place(Double(fromX) + sideways(leaving: e), Double(fromY) + Double(Self.flyOutY - fromY) * e)
      }
    case .gone:
      break
    }
    velocity = (exact.x - before.x, exact.y - before.y)
  }

  private mutating func place(_ px: Double, _ py: Double) {
    exact = (px, py)
    x = Int(px.rounded()); y = Int(py.rounded())
  }

  /// How far to the side of the hover point the ship is when it is `e` of the way in (0 at the
  /// bottom, 1 on arrival). Every path ends at 0, so the ship always lands on its hover point.
  private func sideways(arriving e: Double) -> Double {
    switch path {
    case .straight: return 0
    case .curve: return -Self.curveReach * pow(1 - e, 1.5)
    case .swoop: return Self.swoopReach * sin(2 * Double.pi * e) * (1 - e)
    case .spiral: return Self.spiralReach * sin(5 * Double.pi * e) * (1 - e)
    }
  }

  /// How far to the side of where it left from the ship is when it is `e` of the way out.
  private func sideways(leaving e: Double) -> Double {
    switch path {
    case .straight: return 0
    case .curve: return Self.curveReach * pow(e, 1.5)
    case .swoop: return Self.swoopReach * sin(2 * Double.pi * e) * e
    case .spiral: return Self.spiralReach * sin(5 * Double.pi * e) * e
    }
  }

  /// Starts the fly-off from wherever the ship is now. Ignored once it is already leaving.
  public mutating func dismiss() {
    guard phase == .flyIn || phase == .hover else { return }
    phase = .flyOut; phaseTicks = 0; fromY = y; fromX = x
    exact = (Double(x), Double(y))
  }

  /// Moves the hover centre, and the ship with it, but never so far that the ship or its aura would
  /// leave the buffer at any point of its hover swing. Ignored outside `hover`.
  public mutating func drag(dx: Int, dy: Int) {
    guard phase == .hover else { return }
    let r = Self.drawnReach, swing = hoverSwing
    anchorX = Self.clamp(anchorX + dx, r.left + swing.x, bufferWidth - 1 - r.right - swing.x)
    anchorY = Self.clamp(anchorY + dy, r.up + swing.y, bufferHeight - 1 - r.down - swing.y)
    placeAtHoverOffset()
  }

  /// The most the hover moves the ship from its anchor, each way.
  private var hoverSwing: (x: Int, y: Int) {
    switch hover {
    case .figure8: return (6, 3)
    case .bob: return (0, 3)
    case .still: return (0, 0)
    }
  }

  /// `v` within `lo...hi`; `lo` when the range is empty (a buffer too small for the ship).
  private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(v, hi)) }

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
