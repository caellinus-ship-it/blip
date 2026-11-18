import Foundation

/// How big one arcade pixel is on screen.
public enum SizeOption: String, Codable, CaseIterable {
  case small, medium, large

  public var pointsPerPixel: Int {
    switch self {
    case .small: return 2
    case .medium: return 3
    case .large: return 4
    }
  }
}

/// The voice the assistant answers in; `custom` holds the user's own description.
public enum Personality: Codable, Equatable {
  case playful, plain
  case custom(String)
}

public enum AnswerLength: String, Codable, CaseIterable {
  case short, detailed
}

/// Which Claude model answers; `alias` is the value passed to `--model`.
public enum BrainModel: String, Codable, CaseIterable {
  case fastest, smarter

  public var alias: String {
    switch self {
    case .fastest: return "haiku"
    case .smarter: return "sonnet"
    }
  }
}

/// A global shortcut as a Carbon virtual key code and Carbon modifier mask.
public struct HotKey: Codable, Equatable {
  public var keyCode: UInt32
  public var modifiers: UInt32

  public init(keyCode: UInt32, modifiers: UInt32) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  /// Command-Escape: `kVK_Escape` (53) with Carbon `cmdKey` (256).
  public static let commandEscape = HotKey(keyCode: 53, modifiers: 256)
}

/// The line the ship follows on its way in and out.
public enum FlightPath: String, Codable, CaseIterable { case straight, curve, swoop, spiral }

/// What surrounds the ship while it flies in and off.
public enum EntryEffect: String, Codable, CaseIterable { case none, comet, warp, sparkle, bubble }

/// How long the fly-in and fly-off take.
public enum FlightSpeed: String, Codable, CaseIterable {
  case relaxed, normal, zippy

  /// Ticks for the fly-in and the fly-off.
  public var ticks: (flyIn: Int, flyOut: Int) {
    switch self {
    case .relaxed: return (130, 64)
    case .normal: return (90, 48)
    case .zippy: return (60, 34)
    }
  }
}

/// What glows around the creature while it hovers.
public enum AuraStyle: String, Codable, CaseIterable { case rings, sparkles, halo, off }

/// When the assistant must stop and ask before it acts on the Mac.
public enum AskPolicy: String, Codable, CaseIterable { case anyChange, riskyOnly, never }

/// Everything the user can change. Decoding fills any missing key with its default,
/// so settings saved by an older version still load.
public struct BlipSettings: Codable, Equatable {
  public var name = "Blip"
  public var creature = Creature.blob
  public var ship = Ship.rocket
  public var size = SizeOption.medium
  public var trail = TrailStyle.lightning
  public var trailColor = TrailColor.cyan
  /// What surrounds the ship while it flies in and off.
  public var entryEffect = EntryEffect.comet
  public var flightPath = FlightPath.curve
  public var flightSpeed = FlightSpeed.normal
  public var aura = AuraStyle.rings
  /// The aura's color; `nil` means use the creature's own colors.
  public var auraColor: RGBA? = nil
  public var bubbleColor: RGBA = 0x3B82F6FF
  public var hover = HoverMotion.figure8
  public var personality = Personality.playful
  public var answers = AnswerLength.short
  public var model = BrainModel.fastest
  public var sounds = true
  /// The assistant may act on the Mac: files, commands, the web, connected mail and drive.
  public var actions = true
  public var askFirst = AskPolicy.anyChange
  public var hotKey = HotKey.commandEscape
  public var launchAtLogin = true
  /// The `claude` executable to run; `nil` means find it automatically.
  public var claudePath: String? = nil

  public init() {}

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = BlipSettings()
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
    creature = try c.decodeIfPresent(Creature.self, forKey: .creature) ?? d.creature
    ship = try c.decodeIfPresent(Ship.self, forKey: .ship) ?? d.ship
    size = try c.decodeIfPresent(SizeOption.self, forKey: .size) ?? d.size
    trail = try c.decodeIfPresent(TrailStyle.self, forKey: .trail) ?? d.trail
    trailColor = try c.decodeIfPresent(TrailColor.self, forKey: .trailColor) ?? d.trailColor
    if let effect = try c.decodeIfPresent(EntryEffect.self, forKey: .entryEffect) {
      entryEffect = effect
    } else {
      // Saved before entry effects existed: the old switch was "comet" on or off.
      let legacy = try decoder.container(keyedBy: LegacyKeys.self)
      entryEffect = (try legacy.decodeIfPresent(Bool.self, forKey: .comet) ?? true) ? .comet : .none
    }
    flightPath = try c.decodeIfPresent(FlightPath.self, forKey: .flightPath) ?? d.flightPath
    flightSpeed = try c.decodeIfPresent(FlightSpeed.self, forKey: .flightSpeed) ?? d.flightSpeed
    aura = try c.decodeIfPresent(AuraStyle.self, forKey: .aura) ?? d.aura
    auraColor = try c.decodeIfPresent(RGBA.self, forKey: .auraColor) ?? d.auraColor
    bubbleColor = try c.decodeIfPresent(RGBA.self, forKey: .bubbleColor) ?? d.bubbleColor
    hover = try c.decodeIfPresent(HoverMotion.self, forKey: .hover) ?? d.hover
    personality = try c.decodeIfPresent(Personality.self, forKey: .personality) ?? d.personality
    answers = try c.decodeIfPresent(AnswerLength.self, forKey: .answers) ?? d.answers
    model = try c.decodeIfPresent(BrainModel.self, forKey: .model) ?? d.model
    sounds = try c.decodeIfPresent(Bool.self, forKey: .sounds) ?? d.sounds
    actions = try c.decodeIfPresent(Bool.self, forKey: .actions) ?? d.actions
    askFirst = try c.decodeIfPresent(AskPolicy.self, forKey: .askFirst) ?? d.askFirst
    hotKey = try c.decodeIfPresent(HotKey.self, forKey: .hotKey) ?? d.hotKey
    launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    claudePath = try c.decodeIfPresent(String.self, forKey: .claudePath) ?? d.claudePath
  }
}

extension BlipSettings {
  private enum LegacyKeys: String, CodingKey { case comet }

  /// The older on/off form of `entryEffect`: on means any effect, and turning it on picks the comet.
  public var comet: Bool {
    get { entryEffect != .none }
    set { entryEffect = newValue ? (entryEffect == .none ? .comet : entryEffect) : .none }
  }

  /// The name to show and to speak as: `name` without surrounding whitespace, or "Blip" when that is empty.
  public var displayName: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Blip" : trimmed
  }
}
