import Foundation

/// One note of a sound effect: a pitch held for a time. A frequency of 0 is a rest.
public struct Note: Equatable, Sendable {
  public let frequency: Double
  /// Seconds.
  public let duration: Double

  public init(frequency: Double, duration: Double) {
    self.frequency = frequency
    self.duration = duration
  }
}

/// Blip's three sound effects and the square-wave synth that renders them.
public enum Chiptune {
  /// A summon: a rising sweep, eight notes from 220 Hz to 880 Hz in equal ratio steps.
  public static let launch = sweep(from: 220, to: 880, notes: 8, duration: 0.04)
  /// The first words of an answer: two quick high notes.
  public static let reply = [Note(frequency: 880, duration: 0.05), Note(frequency: 1320, duration: 0.05)]
  /// The ship leaving: eight notes falling from 880 Hz to 220 Hz.
  public static let flyOff = sweep(from: 880, to: 220, notes: 8, duration: 0.03)

  /// Seconds each note takes to rise from silence, and to fall back to it, so notes never click.
  static let ramp = 0.005

  /// Renders `notes` as mono samples: a 50% square wave at `volume`, each note with a linear
  /// attack and release of `ramp` seconds. Every note starts and ends at exactly 0.
  public static func render(_ notes: [Note], sampleRate: Double, volume: Float) -> [Float] {
    var samples: [Float] = []
    let rampSamples = ramp * sampleRate
    for note in notes {
      let count = Int((note.duration * sampleRate).rounded())
      guard note.frequency > 0 else {
        samples.append(contentsOf: repeatElement(0, count: count))
        continue
      }
      for i in 0..<count {
        let envelope = min(1, Double(i) / rampSamples, Double(count - 1 - i) / rampSamples)
        let phase = (Double(i) * note.frequency / sampleRate).truncatingRemainder(dividingBy: 1)
        let level: Float = phase < 0.5 ? 1 : -1
        samples.append(volume * Float(envelope) * level)
      }
    }
    return samples
  }

  /// `notes` notes of `duration` seconds each, from `start` to `end` Hz in equal ratio steps.
  private static func sweep(from start: Double, to end: Double, notes: Int, duration: Double) -> [Note] {
    (0..<notes).map { k in
      Note(frequency: start * pow(end / start, Double(k) / Double(notes - 1)), duration: duration)
    }
  }
}
