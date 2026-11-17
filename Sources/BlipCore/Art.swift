/// A pixel-art image as rows of palette keys. `.` is a transparent cell.
public struct Sprite: Sendable {
  public let rows: [String]

  public init(rows: [String]) {
    self.rows = rows
  }

  /// The length of the longest row.
  public var width: Int { rows.map(\.count).max() ?? 0 }
  public var height: Int { rows.count }
}

public enum Creature: String, Codable, CaseIterable {
  case blob, ghost, cat, alien
}

public enum Ship: String, Codable, CaseIterable {
  case rocket, saucer, pod, star
}

/// A creature's sprite and its three body colors. `wiggles` creatures shift
/// their bottom row on alternate ticks.
public struct CreatureArt: Sendable {
  public let sprite: Sprite
  public let body, shade, highlight: RGBA
  public let wiggles: Bool
}

/// All sprite art, copied from `docs/reference/mockup.html` (`CR`, `SH`, `CF`).
public enum Art {
  /// The dark outline color, key `k` in every sprite.
  public static let outline: RGBA = 0x15151FFF

  public static func creature(_ c: Creature) -> CreatureArt {
    switch c {
    case .blob:
      return CreatureArt(
        sprite: Sprite(rows: [
          "....kkkkkkkk....",
          "..kkXXXXXXXXkk..",
          ".kXXhhXXXXXXXXk.",
          ".kXhhXXXXXXXXXk.",
          "kXXXXXXXXXXXXXXk",
          "kXXXowXXXXowXXXk",
          "kXXXooXXXXooXXXk",
          "kXbbXXXmmXXXbbXk",
          "kXXXXXXXXXXXXXXk",
          "kXXXXXXXXXXXXXsk",
          ".kXXXXXXXXXXXsk.",
          ".kssXXXXXXXsssk.",
          "..kkkkkkkkkkkk..",
        ]),
        body: 0x6EE7B7FF, shade: 0x34B88AFF, highlight: 0xD1FAE5FF, wiggles: false)
    case .ghost:
      return CreatureArt(
        sprite: Sprite(rows: [
          "....kkkkkkkk....",
          "..kkXXXXXXXXkk..",
          ".kXXhhXXXXXXXXk.",
          ".kXhhXXXXXXXXXk.",
          "kXXXXXXXXXXXXXXk",
          "kXXXowXXXXowXXXk",
          "kXXXooXXXXooXXXk",
          "kXXXXXXmmXXXXXXk",
          "kXXXXXXmmXXXXXXk",
          "kXXXXXXXXXXXXXsk",
          "kXXXXXXXXXXXXssk",
          "kXXkkXXXkkXXXkXk",
          ".kk..kkk..kkk.k.",
        ]),
        body: 0xC4B5FDFF, shade: 0x8B7BD8FF, highlight: 0xF5F3FFFF, wiggles: true)
    case .cat:
      return CreatureArt(
        sprite: Sprite(rows: [
          ".kk..........kk.",
          "kXXk........kXXk",
          "kXbXkkkkkkkkXbXk",
          "kXXXXXXXXXXXXXXk",
          "kXXhXXXXXXXXXXXk",
          "kXXXowXXXXowXXXk",
          "kXXXooXXXXooXXXk",
          "kXXXXXXppXXXXXXk",
          "kwwXXXmXXmXXXwwk",
          "kXXXXXXXXXXXXXsk",
          ".kXXXXXXXXXXXsk.",
          ".kssXXXXXXXsssk.",
          "..kkkkkkkkkkkk..",
        ]),
        body: 0xFDBA74FF, shade: 0xD98B3FFF, highlight: 0xFFEDD5FF, wiggles: false)
    case .alien:
      return CreatureArt(
        sprite: Sprite(rows: [
          ".......aa.......",
          ".......kk.......",
          "...kkkkXXkkkk...",
          "..kXXXXXXXXXXk..",
          ".kXhhXXXXXXXXXk.",
          ".kXhXXkkkkXXXXk.",
          "kXXXXkwwookXXXXk",
          "kXXXXkwoookXXXXk",
          "kXXXXXkkkkXXXXXk",
          "kXbXXXXmmXXXXbXk",
          ".kXXXXXXXXXXXsk.",
          "..kXkkXkkXkkXk..",
          "..kk..kk..kk.k..",
        ]),
        body: 0x7DD3FCFF, shade: 0x3BA4D4FF, highlight: 0xE0F2FEFF, wiggles: true)
    }
  }

  public static func ship(_ s: Ship) -> Sprite {
    switch s {
    case .rocket:
      return Sprite(rows: [
        "..kkkkkkkkkkkkkkkkkkkk..",
        ".kHLLHHHHHHHHHHHHHHHDDk.",
        ".kHLHHHHHHHHHHHHHHHHDDk.",
        ".kRRRRRRRRRRRRRRRRRRRRk.",
        "kkHLHHHHHHHHHHHHHHHHDDkk",
        "kRkHHHHHoHHHHoHHHHHDDkRk",
        "kRRkHHHHHHHHHHHHHHDDkRRk",
        "kRRRkkkkkkkkkkkkkkkkRRRk",
        "kkkk...kTTk..kTTk...kkkk",
      ])
    case .saucer:
      return Sprite(rows: [
        "....kkkkkkkkkkkkkkkk....",
        "..kkHLLHHHHHHHHHHHHDkk..",
        "kkHLLHHHHHHHHHHHHHHHHDkk",
        "kRRyRRyRRyRRyRRyRRyRRyRk",
        "kkHHHHHHHHHHHHHHHHHHDDkk",
        "..kkDDDDDDDDDDDDDDDDkk..",
        "....kkTTkk....kkTTkk....",
      ])
    case .pod:
      return Sprite(rows: [
        ".kkkkkkkkkkkkkkkkkkkkkk.",
        "kHLLHHHHHHHHHHHHHHHHHDDk",
        "kRRRRRRRRRRRRRRRRRRRRRRk",
        ".kHHHHHHHHHHHHHHHHHHDDk.",
        "..kkDDDDDDDDDDDDDDDDkk..",
        "......kkTTTTTTTTkk......",
      ])
    case .star:
      return Sprite(rows: [
        "k......kkkkkkkkkk......k",
        "kk...kkHLLHHHHHHDkk...kk",
        "kRk.kHHLHHHHHHHHHDDk.kRk",
        "kRRkHHHHHHHHHHHHHHDDkRRk",
        "kRRRkRRRRRRRRRRRRRRkRRRk",
        "kRRkkkHHHHHHHHHHHHkkkRRk",
        "kkk...kkDDDDDDDDkk...kkk",
        "........kTTk.kTTk.......",
      ])
    }
  }

  /// The three 5x5 confetti shapes; each is drawn in a single color.
  public static let confetti: [Sprite] = [
    Sprite(rows: [".X.X.", "XXXXX", "XXXXX", ".XXX.", "..X.."]),
    Sprite(rows: ["..X..", "XXXXX", ".XXX.", ".X.X.", "X...X"]),
    Sprite(rows: ["..X..", ".XXX.", "XXXXX", ".XXX.", "..X.."]),
  ]
}

public enum TrailColor: Codable, Equatable {
  case fire, pink, cyan, lime, violet
  case custom(RGBA)
}

/// The four colors a trail steps through as it ages: white, light, main, dark.
public struct ColorRamp: Equatable {
  public let white, light, main, dark: RGBA

  public init(_ color: TrailColor) {
    white = 0xFFFFFFFF
    switch color {
    case .fire: (light, main, dark) = (0xFDE047FF, 0xFB923CFF, 0xB91C1CFF)
    case .pink: (light, main, dark) = (0xFBCFE8FF, 0xF472B6FF, 0x9D174DFF)
    case .cyan: (light, main, dark) = (0xCFFAFEFF, 0x22D3EEFF, 0x155E75FF)
    case .lime: (light, main, dark) = (0xECFCCBFF, 0xA3E635FF, 0x3F6212FF)
    case .violet: (light, main, dark) = (0xEDE9FEFF, 0xA78BFAFF, 0x4C1D95FF)
    case .custom(let c):
      main = c
      light = ColorRamp.mapRGB(c) { ($0 + 256) / 2 }
      dark = ColorRamp.mapRGB(c) { $0 / 2 }
    }
  }

  /// The ramp color for age fraction `f`: quarters of 0...1 map to white,
  /// light, main, dark; anything past 0.75 is dark.
  public func step(_ f: Double) -> RGBA {
    if f < 0.25 { return white }
    if f < 0.5 { return light }
    if f < 0.75 { return main }
    return dark
  }

  /// Applies `transform` to each RGB channel of `c`; alpha becomes `FF`.
  private static func mapRGB(_ c: RGBA, _ transform: (UInt32) -> UInt32) -> RGBA {
    let r = transform((c >> 24) & 0xFF)
    let g = transform((c >> 16) & 0xFF)
    let b = transform((c >> 8) & 0xFF)
    return (r << 24) | (g << 16) | (b << 8) | 0xFF
  }
}

extension PixelBuffer {
  /// Draws `s` with its top-left cell at (x, y), clipped to the buffer.
  /// `.` cells are skipped. With `mono`, every other cell uses that color;
  /// otherwise a key missing from `palette` is skipped. With `dither`, cells
  /// where `(col + row) % 2 == 1` are skipped.
  public mutating func draw(
    _ s: Sprite, x: Int, y: Int, palette: [Character: RGBA], mono: RGBA? = nil, dither: Bool = false
  ) {
    for (row, line) in s.rows.enumerated() {
      for (col, key) in line.enumerated() {
        if key == "." || (dither && (col + row) % 2 == 1) { continue }
        guard let color = mono ?? palette[key] else { continue }
        fill(x: x + col, y: y + row, w: 1, h: 1, color)
      }
    }
  }
}
