import Testing
@testable import BlipCore

@Suite struct ChiptuneTests {
  @Test func renderLengthAndRange() {
    let s = Chiptune.render([Note(frequency: 440, duration: 0.1), Note(frequency: 0, duration: 0.05)], sampleRate: 44100, volume: 0.5)
    #expect(s.count == 6615); #expect(s.allSatisfy { abs($0) <= 0.5 })
    #expect(s[0] == 0); #expect(s[4409].magnitude < 0.01); #expect(s[5000] == 0)
    #expect(s[2000].magnitude == 0.5)
  }
  @Test func sequencesHaveTheRightShape() {
    #expect(Chiptune.launch.count == 8 && Chiptune.launch.first!.frequency == 220)
    #expect(abs(Chiptune.launch.last!.frequency - 880) < 0.5)
    #expect(Chiptune.launch.map(\.frequency) == Chiptune.launch.map(\.frequency).sorted())
    #expect(Chiptune.reply.map(\.frequency) == [880, 1320])
    #expect(Chiptune.flyOff.map(\.frequency) == Chiptune.flyOff.map(\.frequency).sorted(by: >))
  }
  /// Each effect, rendered as Blip plays it, is audible and never louder than its volume.
  @Test func effectsAreNonSilentAndWithinTheVolume() {
    for notes in [Chiptune.launch, Chiptune.reply, Chiptune.flyOff] {
      let s = Chiptune.render(notes, sampleRate: 48000, volume: 0.15)
      let peak = s.map(\.magnitude).max() ?? 0
      #expect(peak == 0.15)
      #expect(s.first == 0 && s.last == 0)  // starts and ends silent, so no click at either end
    }
  }
}
