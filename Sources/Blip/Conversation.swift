import AppKit
import BlipCore

/// One summon's chat: the panel, the hidden session it talks to, and the ask-and-answer loop.
/// Made when the ship is summoned and closed when it flies off; closing forgets everything.
@MainActor final class Conversation {
  /// Seconds a question may go without any reply text before it fails as `.timeout`.
  static let replyTimeout: TimeInterval = 30
  static let closeUpRequest = "Here is a close-up of window %d. Now answer my question."
  static let unclearWindowReply = "I couldn't get a clear look at that window. Try making it bigger and asking again."

  /// Whether the ship should show it is thinking.
  var onThinkingChanged: ((Bool) -> Void)?
  /// The first words of an answer appeared: once per question, never for the hidden close-up exchange.
  var onReplyStarted: (() -> Void)?

  private let model = ChatModel()
  private let panel: ChatPanel
  private let pool: BrainPool
  private var session: BrainSession?
  /// The display the ship is on; questions capture it.
  private var screen: NSScreen
  /// Holds back each reply while it could still be the window-look marker.
  private var gate: ReplyGate?
  /// The window list sent with the current question, so a `LOOK:<n>` can find window `n`.
  private var windows: [WindowInfo] = []
  /// Replies the session still owes a `result` line for.
  private var pendingResults = 0
  /// Bumped for every question and on close, so late captures and timers from an older one do nothing.
  private var questionNumber = 0
  private var timeout: DispatchWorkItem?
  private var closed = false
  private let dictation = Dictation()
  /// What the text box held when the mic was pressed; spoken words go after it.
  private var dictationPrefix = ""

  init(pool: BrainPool, settings: BlipSettings, screen: NSScreen) {
    self.pool = pool
    self.screen = screen
    panel = ChatPanel(model: model, name: settings.displayName, bubbleColor: settings.bubbleColor)
    session = pool.take()
    adopt(session)
    model.onSend = { [weak self] text in self?.send(text) }
    model.onMic = { [weak self] in self?.micPressed() }
    dictation.onText = { [weak self] spoken in
      guard let self else { return }
      self.model.input = DictationMerge.text(prefix: self.dictationPrefix, dictated: spoken)
    }
    dictation.onStopped = { [weak self] in self?.model.listening = false }
    dictation.onDenied = { [weak self] in self?.model.log.note(.noMicPermission) }

    // Placed where the ship will hover, invisible, and holding the keyboard, so anything typed
    // during the fly-in lands in the box.
    panel.place(anchor: CGPoint(x: screen.frame.midX, y: screen.frame.midY), shipHalfWidth: 0, screen: screen)
    panel.showForTyping()
  }

  // MARK: The ship

  func shipArrived(on screen: NSScreen, anchor: CGPoint, shipHalfWidth: CGFloat) {
    guard !closed else { return }
    shipMoved(on: screen, anchor: anchor, shipHalfWidth: shipHalfWidth)
    panel.fadeIn()
  }

  func shipMoved(on screen: NSScreen, anchor: CGPoint, shipHalfWidth: CGFloat) {
    guard !closed else { return }
    self.screen = screen
    panel.place(anchor: anchor, shipHalfWidth: shipHalfWidth, screen: screen)
  }

  /// Fades the panel out and ends the session, which forgets the conversation. Never waits on `claude`.
  func close() {
    guard !closed else { return }
    closed = true
    questionNumber += 1
    timeout?.cancel()
    dictation.stop()
    model.onSend = nil
    model.onMic = nil
    panel.fadeOutAndClose()
    if let session { pool.release(session) }
    session = nil
  }

  // MARK: Asking

  private func micPressed() {
    guard !closed else { return }
    if !dictation.isListening { dictationPrefix = model.input }
    dictation.toggle()
    model.listening = dictation.isListening
  }

  private func send(_ text: String) {
    guard !closed, model.log.submit(text) else { return }
    dictation.stop()
    model.input = ""
    questionNumber += 1
    let number = questionNumber

    // A session that died while idle was dropped; start one now, at most once per question.
    if session == nil {
      session = pool.take()
      adopt(session)
    }
    guard let session else { return fail(.toolMissing) }
    guard ScreenCapturer.hasPermission else {
      ScreenCapturer.requestPermission()
      return fail(.noScreenPermission)
    }
    onThinkingChanged?(true)
    startTimeout(for: number)

    let question = model.log.messages.last?.text ?? text
    let screen = self.screen
    Task { @MainActor [weak self] in
      do {
        let shot = try await ScreenCapturer.captureDisplay(screen)
        guard let self, self.isCurrent(number, session) else { return }
        self.windows = shot.windows
        self.gate = ReplyGate(windowCount: min(shot.windows.count, WindowList.limit), allowLook: true)
        self.pendingResults += 1
        session.send(text: question, jpegs: [shot.jpeg], windows: shot.windows)
      } catch {
        guard let self, self.isCurrent(number, session) else { return }
        self.fail(.other("I couldn't take a picture of your screen."))
      }
    }
  }

  /// Sends a close-up of window `n` from the last list, for a reply that asked for one.
  private func sendCloseUp(of n: Int) {
    guard let session else { return }
    let number = questionNumber
    let windowID = windows[n - 1].id
    Task { @MainActor [weak self] in
      let jpeg = try? await ScreenCapturer.captureWindow(id: windowID)
      guard let self, self.isCurrent(number, session) else { return }
      guard let jpeg else { return self.finish(appending: Self.unclearWindowReply) }
      self.gate = ReplyGate(windowCount: 0, allowLook: false)
      self.pendingResults += 1
      session.send(text: String(format: Self.closeUpRequest, n), jpegs: [jpeg], windows: [])
    }
  }

  private func isCurrent(_ number: Int, _ session: BrainSession) -> Bool {
    !closed && number == questionNumber && self.session === session && model.log.waiting
  }

  private func startTimeout(for number: Int) {
    timeout?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self, !self.closed, number == self.questionNumber, self.model.log.awaitingFirstText else { return }
      self.fail(.timeout)
      // The late reply would land on the next question; the next one gets a fresh session.
      self.dropSession()
    }
    timeout = item
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.replyTimeout, execute: item)
  }

  // MARK: Replies

  private func adopt(_ session: BrainSession?) {
    pendingResults = 0
    gate = nil
    session?.onEvent = { [weak self] event in
      MainActor.assumeIsolated { self?.handle(event) }
    }
    session?.onExit = { [weak self] in
      MainActor.assumeIsolated { self?.sessionExited() }
    }
  }

  private func handle(_ event: BrainEvent) {
    guard !closed else { return }
    switch event {
    case .textDelta(let delta):
      guard gate != nil else { return }
      let shown = gate!.feed(delta)
      show(shown)
    case .messageDone:
      replyEnded()
    case .result(let text, let isError):
      pendingResults = max(0, pendingResults - 1)
      if isError && model.log.waiting {
        fail(BlipProblem.classify(resultText: text))
      } else if pendingResults == 0 && model.log.waiting && gate != nil {
        replyEnded()  // a reply that ended without its own end-of-message event
      }
    case .ready, .other:
      break
    }
  }

  /// The streamed message is complete: show what the gate held back, or fetch the close-up it asked for.
  private func replyEnded() {
    guard var g = gate else { return }
    gate = nil
    switch g.finish() {
    case .text(let rest): finish(appending: rest)
    case .look(let n): sendCloseUp(of: n)
    case .unusableMarker: finish(appending: Self.unclearWindowReply)
    }
  }

  /// Adds reply text to the panel, telling `onReplyStarted` when it is the answer's first.
  private func show(_ text: String) {
    guard !text.isEmpty else { return }
    let first = model.log.awaitingFirstText
    model.log.append(delta: text)
    if first && !model.log.awaitingFirstText { onReplyStarted?() }
  }

  private func finish(appending text: String) {
    show(text)
    model.log.finish()
    stoppedWaiting()
  }

  private func fail(_ problem: BlipProblem) {
    gate = nil
    model.log.fail(problem)
    stoppedWaiting()
  }

  private func stoppedWaiting() {
    timeout?.cancel()
    timeout = nil
    onThinkingChanged?(false)
  }

  /// A `claude` that dies is not replaced here: the next question takes a new one. Replacing it at once
  /// would spin, launching `claude` after `claude`, if it dies at launch.
  private func sessionExited() {
    guard !closed else { return }
    if model.log.waiting { fail(.other("the assistant stopped unexpectedly")) }
    dropSession()
  }

  private func dropSession() {
    if let session { pool.release(session) }
    session = nil
    adopt(nil)
  }
}
