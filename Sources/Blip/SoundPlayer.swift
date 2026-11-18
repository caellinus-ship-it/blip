import AVFoundation
import BlipCore

/// Plays Blip's sound effects, unless Sounds is off. Its audio engine (not the one dictation uses)
/// starts on first use and stops once the effect has played, so a silent Blip holds no audio device.
/// Starting an engine takes tens of milliseconds, so all audio work runs on a queue of its own, never
/// holding up the main thread and the 60 Hz animation. `play` is called from the main thread.
final class SoundPlayer: @unchecked Sendable {
  static let volume: Float = 0.15

  /// Debug switch `BLIP_DEBUG=1`: each effect played, and each failure to play, go to Blip's stderr.
  private static let debug = ProcessInfo.processInfo.environment["BLIP_DEBUG"] == "1"

  private let settings: () -> BlipSettings
  /// The audio queue. Everything below it is used only there.
  private let queue = DispatchQueue(label: "com.blip.assistant.sound")
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  /// Watches the engine for an output device change, which stops it.
  private var configurationObserver: NSObjectProtocol?
  /// Bumped for every effect started, so the end of one that was cut off stops nothing.
  private var generation = 0

  init(settings: @escaping () -> BlipSettings) {
    self.settings = settings
  }

  /// Plays `notes`, cutting off any effect still playing, so effects never overlap. Does nothing when
  /// Sounds is off.
  /// A missing or changing output device is logged under `BLIP_DEBUG=1` and otherwise ignored.
  @MainActor func play(_ notes: [Note]) {
    guard settings().sounds else { return }
    let asked = ProcessInfo.processInfo.systemUptime
    queue.async { self.start(notes, asked: asked) }
  }

  /// On the audio queue: plays `notes` from the start, `asked` (system uptime) being when it was asked for.
  private func start(_ notes: [Note], asked: TimeInterval) {
    guard let player = runningPlayer() else { return }

    let format = player.outputFormat(forBus: 0)
    let samples = Chiptune.render(notes, sampleRate: format.sampleRate, volume: Self.volume)
    guard !samples.isEmpty,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
    else { return }
    buffer.frameLength = buffer.frameCapacity
    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }

    // Checked again just before playing: the output device may have changed while the samples were
    // made, and a player can't play on a stopped engine. The effect is dropped then.
    guard let engine, engine.isRunning, self.player === player else {
      stopEngine()
      return Self.log("sound: the output changed; effect dropped")
    }
    generation += 1
    let number = generation
    player.stop()  // the effect still playing, if any, ends here
    player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack,
                          completionHandler: { [weak self] _ in self?.queue.async { self?.played(number) } })
    player.play()
    let name = Self.name(of: notes)
    let length = notes.reduce(0) { $0 + $1.duration }
    let peak = samples.map(\.magnitude).max() ?? 0
    let delay = (ProcessInfo.processInfo.systemUptime - asked) * 1000
    Self.log(String(format: "sound %@ peak %.3f %.2f s at %.0f Hz, playing %.0f ms after it was asked for",
                    name, peak, length, format.sampleRate, delay))
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
    // A device change stops the engine; it is dropped, and the next effect starts a new one.
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
    ) { [weak self, weak engine] _ in
      self?.queue.async {
        guard let self, let engine, self.engine === engine else { return }
        self.stopEngine()
        Self.log("sound: the output changed; engine dropped")
      }
    }
    return player
  }

  /// An effect finished playing; if it was the last one started, the engine stops.
  private func played(_ number: Int) {
    guard number == generation else { return }
    stopEngine()
    Self.log("sound: engine stopped")
  }

  private func stopEngine() {
    if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    configurationObserver = nil
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

  private static func log(_ line: String) {
    if debug { FileHandle.standardError.write(Data("\(line)\n".utf8)) }
  }
}
