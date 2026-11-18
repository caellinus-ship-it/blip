import Foundation
import Testing
@testable import BlipCore

@Suite struct SettingsTests {
  @Test func defaults() {
    let s = BlipSettings()
    #expect(s.name == "Blip" && s.creature == .blob && s.ship == .rocket && s.trail == .lightning)
    #expect(s.trailColor == .cyan && s.hotKey == .commandEscape && s.sounds && s.launchAtLogin)
    #expect(SizeOption.small.pointsPerPixel == 2 && SizeOption.large.pointsPerPixel == 4)
    #expect(BrainModel.fastest.alias == "haiku" && BrainModel.smarter.alias == "sonnet")
  }
  @Test func roundTripsAndToleratesMissingKeys() throws {
    var s = BlipSettings(); s.name = "Zap"; s.personality = .custom("a sleepy wizard"); s.trailColor = .custom(0x112233FF)
    let back = try JSONDecoder().decode(BlipSettings.self, from: JSONEncoder().encode(s))
    #expect(back == s)
    let partial = try JSONDecoder().decode(BlipSettings.self, from: Data(#"{"name":"Old"}"#.utf8))
    #expect(partial.name == "Old" && partial.trail == .lightning)
  }
  @Test func cometDefaultsOnAndToleratesMissingKey() throws {
    #expect(BlipSettings().comet)
    let old = try JSONDecoder().decode(BlipSettings.self, from: Data(#"{"name":"Old"}"#.utf8))
    #expect(old.comet)
    var s = BlipSettings(); s.comet = false
    #expect(try JSONDecoder().decode(BlipSettings.self, from: JSONEncoder().encode(s)).comet == false)
  }
}
