/// Small still pictures of each option for the settings pickers, drawn with the same art and trail
/// code as the scene.
public enum Thumbnail {
  /// The ship trim color in ship pictures, so they don't change with the trail color.
  static let trim: RGBA = 0xF87171FF
  /// Ticks a trail runs before it is drawn.
  static let trailTicks = 40
  /// Where the trail leaves the ship in a trail picture.
  static let exhaust = (x: 18, y: 6)
  /// Pixels a tick the ship climbs for the echoes picture. Echoes are left behind by the ship's
  /// movement, so a still ship would stack them all in one place.
  static let echoClimb = 3

  /// 18 by 15, the creature at (1, 1) in its own colors, eyes open.
  public static func creature(_ c: Creature) -> PixelBuffer {
    let art = Art.creature(c)
    var b = PixelBuffer(width: 18, height: 15)
    b.draw(art.sprite, x: 1, y: 1, palette: Art.creaturePalette(art))
    return b
  }

  /// 26 by 11, the ship at (1, 1) with red trim.
  public static func ship(_ s: Ship) -> PixelBuffer {
    var b = PixelBuffer(width: 26, height: 11)
    b.draw(Art.ship(s), x: 1, y: 1, palette: Art.shipPalette(trim: trim))
    return b
  }

  /// 36 by 44: the trail at full strength after `trailTicks` ticks, leaving the ship at `exhaust`.
  /// The ship itself is not drawn; echoes are the rocket's silhouette.
  public static func trail(_ style: TrailStyle, ramp: ColorRamp) -> PixelBuffer {
    let rocket = Art.ship(.rocket)
    var trail = TrailSystem(style: style, seed: 1)
    for t in 1...trailTicks {
      let climb = style == .echoes ? (trailTicks - t) * echoClimb : 0
      let exhaustY = exhaust.y + climb
      trail.tick(shipX: exhaust.x, shipY: exhaustY - rocket.height, exhaustY: exhaustY, flying: true)
    }
    var b = PixelBuffer(width: 36, height: 44)
    trail.draw(into: &b, ramp: ramp, silhouette: [(rocket, dx: -12, dy: 0)])
    return b
  }
}
