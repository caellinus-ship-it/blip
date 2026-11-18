@preconcurrency import AVFoundation
@preconcurrency import Speech

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

  /// Starting and stopping the audio engine takes tens of milliseconds, so it happens here, never on the
  /// main thread and its 60 Hz animation; in order, so a stop always comes after the start before it.
  nonisolated private static let audioQueue = DispatchQueue(label: "com.blip.assistant.dictation")

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
    if let engine { Self.release(engine) }
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

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    Self.audioQueue.async { [weak self] in
      let started = Self.startEngine(feeding: request)
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          // A listen stopped, or a conversation closed, while the engine started: let go of the mic.
          guard let self, self.isListening, self.generation == number else {
            if case .success(let engine) = started { Self.release(engine) }
            return
          }
          switch started {
          case .success(let engine): self.listen(engine: engine, recognizer: recognizer, request: request, number)
          case .failure(let failure): self.refuse(failure.reason)
          }
        }
      }
    }
  }

  /// The engine is running and feeding `request`: recognition starts.
  private func listen(engine: AVAudioEngine, recognizer: SFSpeechRecognizer,
                      request: SFSpeechAudioBufferRecognitionRequest, _ number: Int) {
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

  private struct EngineFailure: Error { let reason: String }

  /// On the audio queue: an engine started on the default input, its audio going to `request`.
  nonisolated private static func startEngine(
    feeding request: SFSpeechAudioBufferRecognitionRequest
  ) -> Result<AVAudioEngine, EngineFailure> {
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      return .failure(EngineFailure(reason: "no usable input device"))
    }
    input.installTap(onBus: 0, bufferSize: 1024, format: format, block: feeding(request))
    engine.prepare()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      return .failure(EngineFailure(reason: "the audio engine did not start: \(error.localizedDescription)"))
    }
    return .success(engine)
  }

  /// Stops `engine` on the audio queue, which releases the microphone.
  nonisolated private static func release(_ engine: AVAudioEngine) {
    audioQueue.async {
      engine.stop()
      engine.inputNode.removeTap(onBus: 0)
    }
  }

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
