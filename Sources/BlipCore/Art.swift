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
  case blob, ghost, cat, alien, santa, snowman, reindeer
}

public enum Ship: String, Codable, CaseIterable {
  case rocket, saucer, pod, star, sleigh
}

/// Where a creature's eyes are in its sprite, so the scene can move and reshape them without
/// reading sprite characters.
public enum Eyes: Sendable, Equatable {
  /// Two 2x2 eyes (`ow` over `oo`); the cells are each eye's top-left.
  case pair(left: Cell, right: Cell)
  /// One eye inside a dark frame: the white interior's top-left cell and its size.
  case framed(Cell, width: Int, height: Int)
}

/// A cell in a sprite: column and row from its top-left.
public struct Cell: Sendable, Equatable {
  public let x, y: Int

  public init(_ x: Int, _ y: Int) {
    self.x = x
    self.y = y
  }
}

/// A creature's sprite, its three body colors and where its face is. `wiggles` creatures shift
/// their bottom row on alternate ticks. `auraInner` and `auraOuter` color the aura when the owner
/// hasn't picked one; `mouth` is the top-left of the 2x2 a yawn opens.
public struct CreatureArt: Sendable {
  public let sprite: Sprite
  public let body, shade, highlight: RGBA
  public let wiggles: Bool
  public let eyes: Eyes
  public let mouth: Cell
  public let auraInner, auraOuter: RGBA

  public init(
    sprite: Sprite, body: RGBA, shade: RGBA, highlight: RGBA, wiggles: Bool, eyes: Eyes = Art.twoEyes,
    mouth: Cell, aura: (inner: RGBA, outer: RGBA)? = nil
  ) {
    self.sprite = sprite
    (self.body, self.shade, self.highlight, self.wiggles) = (body, shade, highlight, wiggles)
    (self.eyes, self.mouth) = (eyes, mouth)
    (auraInner, auraOuter) = aura ?? (highlight, body)
  }
}

/// All sprite art, copied from `docs/reference/mockup.html` (`CR`, `SH`, `CF`).
public enum Art {
  /// The dark outline color, key `k` in every sprite.
  public static let outline: RGBA = 0x15151FFF
  public static let white: RGBA = 0xFFFFFFFF
  public static let yellow: RGBA = 0xFDE047FF
  /// The eyes most creatures have: 2x2 at columns 4 and 10 of row 5.
  public static let twoEyes = Eyes.pair(left: Cell(4, 5), right: Cell(10, 5))

  /// The colors a creature sprite is drawn in. With `blink`, the eyes (`o` and `w`) take the
  /// shade and body colors; every other key, `W` white included, stays as it is.
  public static func creaturePalette(_ art: CreatureArt, blink: Bool = false) -> [Character: RGBA] {
    [
      "k": outline, "X": art.body, "s": art.shade, "h": art.highlight,
      "o": blink ? art.shade : outline, "w": blink ? art.body : white,
      "b": 0xFB7185FF, "m": outline, "p": 0xF472B6FF, "a": yellow,
      "r": 0xDC2626FF, "d": 0x991B1BFF, "W": white, "G": 0xD5DCE8FF, "n": 0xFB923CFF,
      "t": 0xE7C08AFF, "l": 0xF3D9B8FF, "T": 0x3A3F52FF,
    ]
  }

  /// The colors a ship sprite is drawn in: `trim` for the `R` band, `lights` for the saucer's `y` lights.
  public static func shipPalette(trim: RGBA, lights: RGBA = yellow) -> [Character: RGBA] {
    [
      "k": outline, "H": 0xE8EAF0FF, "L": white, "D": 0x9AA1B2FF, "R": trim,
      "T": 0x3A3F52FF, "o": 0x5B6378FF, "y": lights,
      "r": 0xDC2626FF, "d": 0x991B1BFF, "g": 0xFBBF24FF,
    ]
  }

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
        body: 0x6EE7B7FF, shade: 0x34B88AFF, highlight: 0xD1FAE5FF, wiggles: false, mouth: Cell(7, 7))
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
        body: 0xC4B5FDFF, shade: 0x8B7BD8FF, highlight: 0xF5F3FFFF, wiggles: true, mouth: Cell(7, 7))
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
          "kWWXXXmXXmXXXWWk",
          "kXXXXXXXXXXXXXsk",
          ".kXXXXXXXXXXXsk.",
          ".kssXXXXXXXsssk.",
          "..kkkkkkkkkkkk..",
        ]),
        body: 0xFDBA74FF, shade: 0xD98B3FFF, highlight: 0xFFEDD5FF, wiggles: false, mouth: Cell(7, 8))
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
        body: 0x7DD3FCFF, shade: 0x3BA4D4FF, highlight: 0xE0F2FEFF, wiggles: true,
        eyes: .framed(Cell(6, 6), width: 4, height: 2), mouth: Cell(7, 9))
    case .santa:
      return CreatureArt(
        sprite: Sprite(rows: [
          "......kkkk..kk..",
          "....kkrrrrkkWWk.",
          "...krrrrrrrrkWWk",
          "..krrrrrrrrrrkk.",
          ".kkWWWWWWWWWWkk.",
          "kWWWWWWWWWWWWWWk",
          "kkXXowXXXXowXXkk",
          ".kXXooXppXooXXk.",
          ".kbXWWWXXWWWXbk.",
          "kWWWWWWmmWWWWWWk",
          "kWWWWWWWWWWWWGGk",
          ".kGGWWWWWWWGGGk.",
          "..kkkkkkkkkkkk..",
        ]),
        body: 0xFFD9B8FF, shade: 0xE0A982FF, highlight: 0xFFEBD9FF, wiggles: false,
        eyes: .pair(left: Cell(4, 6), right: Cell(10, 6)), mouth: Cell(7, 9), aura: (Art.white, 0xEF4444FF))
    case .snowman:
      return CreatureArt(
        sprite: Sprite(rows: [
          "....kkkkkkkk....",
          "....kTTTTTTk....",
          "....krrrrrrk....",
          "..kTTTTTTTTTTk..",
          ".kXXhhXXXXXXXXk.",
          "kXXXowXXXXowXXXk",
          "kXXXooXXXXooXXXk",
          "kXbXXXXnnnXXXbXk",
          "kXXXXmXXXXmXXXXk",
          ".kXXXXmmmmXXXXk.",
          ".krrdrrdrrdrrdk.",
          "kXXXXXXXXXXXXXsk",
          ".kkkkkkkkkkkkkk.",
        ]),
        body: 0xF1F5F9FF, shade: 0xCBD5E1FF, highlight: 0xFFFFFFFF, wiggles: false,
        mouth: Cell(7, 8), aura: (Art.white, 0x7DD3FCFF))
    case .reindeer:
      return CreatureArt(
        sprite: Sprite(rows: [
          ".kk.k......k.kk.",
          "kttktk....ktkttk",
          ".kttk......kttk.",
          "..ktkkkkkkkktk..",
          "kssXXhXXXXXXXssk",
          ".kXXowXXXXowXXk.",
          ".kXXooXXXXooXXk.",
          ".kXXXXllllXXXXk.",
          ".kXbXlrWrrlXbXk.",
          "..kXXlrrrrlXXk..",
          "..kXXXllllXXXk..",
          "..kXXXXXXXXXXk..",
          "...kkkkkkkkkk...",
        ]),
        body: 0xC68B59FF, shade: 0x8F5A2EFF, highlight: 0xE2B48AFF, wiggles: false,
        mouth: Cell(7, 10), aura: (0xFDE047FF, 0xEF4444FF))
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
    case .sleigh:
      return Sprite(rows: [
        ".kk..................kk.",
        "kggkkkkkkkkkkkkkkkkkkggk",
        "kgkrLLrrrrrrrrrrrrrrdkgk",
        ".kkrLrrrrrrrrrrrrrrrdkk.",
        "..kRRRRRRRRRRRRRRRRRRk..",
        "kk.kkkkkkkkkkkkkkkkkk.kk",
        "kgk..kgk........kgk..kgk",
        ".kggggggggggggggggggggk.",
        "..kkkkkkkkkkkkkkkkkkkk..",
      ])
    }
  }

  /// The three 5x5 confetti shapes; each is drawn in a single color.
  public static let confetti: [Sprite] = [
    Sprite(rows: [".X.X.", "XXXXX", "XXXXX", ".XXX.", "..X.."]),
    Sprite(rows: ["..X..", "XXXXX", ".XXX.", ".X.X.", "X...X"]),
    Sprite(rows: ["..X..", ".XXX.", "XXXXX", ".XXX.", "..X.."]),
  ]

  /// The snow trail's three flakes, largest first; each is drawn in a single color.
  public static let snowflakes: [Sprite] = [
    Sprite(rows: ["..X..", "X.X.X", ".XXX.", "X.X.X", "..X.."]),
    Sprite(rows: [".X.", "XXX", ".X."]),
    Sprite(rows: ["XX", "XX"]),
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
