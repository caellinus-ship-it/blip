import AVFoundation
import BlipCore

/// Plays Blip's sound effects, unless Sounds is off. Its audio engine (not the one dictation uses)
/// starts on first use and stops once the effect has played, so a silent Blip holds no audio device.
/// Use it from the main thread only.
@MainActor final class SoundPlayer {
  static let volume: Float = 0.15
  /// Seconds: an effect asked for again sooner than this after the last time it was asked for plays
  /// nothing, so a mashed shortcut plays each effect once however long the mash goes on.
  static let repeatWindow: TimeInterval = 0.5

  /// Debug switch `BLIP_DEBUG=1`: each effect played, and each failure to play, go to Blip's stderr.
  private static let debug = ProcessInfo.processInfo.environment["BLIP_DEBUG"] == "1"

  private let settings: () -> BlipSettings
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  /// Bumped for every effect started, so the end of one that was cut off stops nothing.
  private var generation = 0
  /// When each effect was last asked for (system uptime), by name, whether it played or not.
  private var lastRequests: [String: TimeInterval] = [:]

  init(settings: @escaping () -> BlipSettings) {
    self.settings = settings
  }

  /// Plays `notes`, cutting off any effect still playing. Does nothing when Sounds is off, or when the
  /// same effect was asked for less than `repeatWindow` ago.
  /// A missing or changing output device is logged under `BLIP_DEBUG=1` and otherwise ignored.
  func play(_ notes: [Note]) {
    guard settings().sounds else { return }
    let name = Self.name(of: notes)
    let now = ProcessInfo.processInfo.systemUptime
    let previous = lastRequests.updateValue(now, forKey: name)
    if let previous, now - previous < Self.repeatWindow { return }
    guard let player = runningPlayer() else { return }

    let format = player.outputFormat(forBus: 0)
    let samples = Chiptune.render(notes, sampleRate: format.sampleRate, volume: Self.volume)
    guard !samples.isEmpty,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
    else { return }
    buffer.frameLength = buffer.frameCapacity
    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }

    generation += 1
    let number = generation
    player.stop()  // the effect still playing, if any, ends here
    player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack,
                          completionHandler: Self.onMain { [weak self] in self?.played(number) })
    player.play()
    let length = notes.reduce(0) { $0 + $1.duration }
    let peak = samples.map(\.magnitude).max() ?? 0
    Self.log(String(format: "sound %@ peak %.3f %.2f s at %.0f Hz", name, peak, length, format.sampleRate))
  }

  /// The player, on an engine that is running: the current one, or a new one started now.
  private func runningPlayer() -> AVAudioPlayerNode? {
    if let engine, let player, engine.isRunning { return player }
    // Not running: never started, stopped after its last effect, or stopped by a device change.
    stopEngine()
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    guard rate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
      Self.log("sound: no output device")
      return nil
    }
    engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.prepare()
    do {
      try engine.start()
    } catch {
      Self.log("sound: the audio engine did not start: \(error.localizedDescription)")
      return nil
    }
    self.engine = engine
    self.player = player
    return player
  }

  /// An effect finished playing; if it was the last one started, the engine stops.
  private func played(_ number: Int) {
    guard number == generation else { return }
    stopEngine()
    Self.log("sound: engine stopped")
  }

  private func stopEngine() {
    player?.stop()
    engine?.stop()
    player = nil
    engine = nil
  }

  private static func name(of notes: [Note]) -> String {
    switch notes {
    case Chiptune.launch: "launch"
    case Chiptune.reply: "reply"
    case Chiptune.flyOff: "flyOff"
    default: "effect"
    }
  }

  /// A completion handler, called on the audio engine's thread, that runs `body` on the main thread.
  private nonisolated static func onMain(
    _ body: @escaping @MainActor @Sendable () -> Void
  ) -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
    { _ in DispatchQueue.main.async { MainActor.assumeIsolated(body) } }
  }

  private static func log(_ line: String) {
    if debug { FileHandle.standardError.write(Data("\(line)\n".utf8)) }
  }
}
