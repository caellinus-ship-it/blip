import AVFoundation
import Speech

/// Turns the owner's speech into text while the mic is on, on this Mac only (never Apple's servers).
/// Each result is the whole transcript so far; nothing is ever sent from here.
@MainActor final class Dictation {
  /// Listening stops this long after the last recognized words.
  static let silenceTimeout: TimeInterval = 2
  /// Before the first words, a little longer, so a pause to think after pressing the mic is not cut off.
  static let firstWordsTimeout: TimeInterval = 5

  /// The transcript so far; each call replaces the last.
  var onText: ((String) -> Void)?
  /// Listening ended, for any reason.
  var onStopped: (() -> Void)?
  /// Listening could not start: Microphone or Speech Recognition was refused, on-device recognition
  /// is not available, or there is no usable input device. All of these are told as the same refusal.
  var onDenied: (() -> Void)?

  /// From the press that turns the mic on (including while permission is being asked) until it stops.
  private(set) var isListening = false

  private var recognizer: SFSpeechRecognizer?
  private var engine: AVAudioEngine?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var silenceTimer: DispatchWorkItem?
  /// Bumped on every start and stop, so late permission answers and results of an older listen do nothing.
  private var generation = 0

  func toggle() {
    if isListening { stop() } else { start() }
  }

  /// Stops listening and releases the microphone. Does nothing when not listening.
  func stop() {
    guard isListening else { return }
    isListening = false
    generation += 1
    silenceTimer?.cancel()
    silenceTimer = nil
    if let engine {
      engine.stop()
      engine.inputNode.removeTap(onBus: 0)
    }
    engine = nil
    request?.endAudio()
    request = nil
    task?.cancel()
    task = nil
    recognizer = nil
    onStopped?()
  }

  private func start() {
    isListening = true
    generation += 1
    let number = generation
    Task { @MainActor [weak self] in
      let allowed = await Self.requestPermissions()
      guard let self, self.isListening, self.generation == number else { return }
      guard allowed else { return self.refuse("Microphone or Speech Recognition permission refused") }
      self.begin(number)
    }
  }

  private func begin(_ number: Int) {
    // No silent fallback to server recognition: without on-device support, treat it as a refusal.
    guard let recognizer = SFSpeechRecognizer(), recognizer.supportsOnDeviceRecognition, recognizer.isAvailable
    else { return refuse("no on-device speech recognition for \(Locale.current.identifier)") }

    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else { return refuse("no usable input device") }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.feeding(request))
    engine.prepare()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      return refuse("the audio engine did not start: \(error.localizedDescription)")
    }

    self.recognizer = recognizer
    self.engine = engine
    self.request = request
    task = recognizer.recognitionTask(with: request, resultHandler: Self.delivering { [weak self] text, ended in
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.heard(text, ended: ended, in: number) }
      }
    })
    restartSilenceTimer(Self.firstWordsTimeout, in: number)
  }

  private func heard(_ text: String?, ended: Bool, in number: Int) {
    guard isListening, generation == number else { return }
    if let text, !text.isEmpty {
      onText?(text)
      restartSilenceTimer(Self.silenceTimeout, in: number)
    }
    if ended { stop() }
  }

  private func restartSilenceTimer(_ seconds: TimeInterval, in number: Int) {
    silenceTimer?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self, self.generation == number else { return }
      self.stop()
    }
    silenceTimer = item
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
  }

  /// Stops (the mic button goes back to idle) and tells the owner it can't listen.
  private func refuse(_ reason: String) {
    NSLog("Blip: can't listen: \(reason)")
    stop()
    onDenied?()
  }

  // MARK: Off the main actor

  /// Asks for the Microphone, then Speech Recognition, each only the first time; true when both are allowed.
  nonisolated private static func requestPermissions() async -> Bool {
    guard await AVCaptureDevice.requestAccess(for: .audio) else { return false }
    let status = await withCheckedContinuation { (done: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
      SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
    }
    return status == .authorized
  }

  /// The input tap; runs on the audio thread.
  nonisolated private static func feeding(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
    { buffer, _ in request.append(buffer) }
  }

  /// Turns each recognition callback into (transcript, ended).
  nonisolated private static func delivering(
    _ deliver: @escaping @Sendable (String?, Bool) -> Void
  ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
    { result, error in
      if let error { NSLog("Blip: speech recognition ended: \(error.localizedDescription)") }
      deliver(result?.bestTranscription.formattedString, error != nil || result?.isFinal == true)
    }
  }
}

/// `Blip --mic-check`: prints Blip's own Microphone and Speech Recognition permission and whether
/// speech can be recognized on this Mac for the current locale, with no UI and without asking; then exits.
enum MicCheck {
  static func run() -> Never {
    setvbuf(stdout, nil, _IOLBF, 0)
    print("microphone: \(describe(AVCaptureDevice.authorizationStatus(for: .audio)))")
    print("speech: \(describe(SFSpeechRecognizer.authorizationStatus()))")
    print("input device: \(AVCaptureDevice.default(for: .audio)?.localizedName ?? "none")")
    let recognizer = SFSpeechRecognizer()
    print("locale: \(Locale.current.identifier); recognizer: \(recognizer?.locale.identifier ?? "none")")
    print("on-device: \(recognizer?.supportsOnDeviceRecognition ?? false)")
    print("available: \(recognizer?.isAvailable ?? false)")
    exit(0)
  }

  private static func describe(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown(\(status.rawValue))"
    }
  }

  private static func describe(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown(\(status.rawValue))"
    }
  }
}
