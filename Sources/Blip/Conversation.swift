import AppKit
import BlipCore

/// One summon's chat: the panel, the hidden session it talks to, and the ask-and-answer loop.
/// Made when the ship is summoned and closed when it flies off; closing forgets everything.
@MainActor final class Conversation {
  /// Seconds a question may go without any reply text before it fails as `.timeout`.
  static let replyTimeout: TimeInterval = 30
  /// Seconds an assistant that may act can go quiet (a slow command, a mail search) before that.
  static let actingTimeout: TimeInterval = 120
  static let screenReply = "Here is my screen. Now answer my question."
  static let closeUpRequest = "Here is a close-up of window %d. Now answer my question."
  /// Seconds a stopped answer's last lines may take to arrive before the session is replaced.
  static let stopTimeout: TimeInterval = 10
  static let unclearWindowReply = "I couldn't get a clear look at that window. Try making it bigger and asking again."

  /// Whether the ship should show it is thinking.
  var onThinkingChanged: ((Bool) -> Void)?
  /// The first words of an answer appeared: once per question, never for the hidden close-up exchange.
  var onReplyStarted: (() -> Void)?
  /// A picture is being taken: `nil` for the whole screen, or the window's frame for a close-up, in
  /// AppKit screen coordinates (converted from ScreenCaptureKit's top-left-origin global coordinates).
  var onLooking: ((CGRect?) -> Void)?
  /// The question ended, once per question: true for a finished answer, false for a problem or a
  /// window that couldn't be seen clearly.
  var onOutcome: ((Bool) -> Void)?
  /// The owner stopped the answer; `onOutcome` is not called for that question.
  var onStopped: (() -> Void)?

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
  /// Those windows' frames by ID, as ScreenCaptureKit gave them.
  private var windowFrames: [UInt32: CGRect] = [:]
  /// The last question `onOutcome` was called for.
  private var outcomeFor = 0
  /// Replies the session still owes a `result` line for.
  private var pendingResults = 0
  /// How many of those belong to answers the owner stopped. Until they have arrived, everything the
  /// session says is the tail of a stopped answer and is dropped.
  private var staleResults = 0
  private var staleTimeout: DispatchWorkItem?
  /// Bumped for every question and on close, so late captures and timers from an older one do nothing.
  private var questionNumber = 0
  private var timeout: DispatchWorkItem?
  private var closed = false
  private let settings: BlipSettings
  private let home = NSHomeDirectory()
  /// The message that is ending stopped to use a tool, so its end is not the answer's end.
  private var toolPending = false
  /// Reply text after a tool was used starts a new paragraph.
  private var breakBeforeNextText = false
  /// The tool request waiting on the owner's Allow or Don't.
  private var pendingAsk: (id: String, input: String, summary: String)?
  private let dictation = Dictation()
  /// What the text box held when the mic was pressed; spoken words go after it.
  private var dictationPrefix = ""

  init(pool: BrainPool, settings: BlipSettings, screen: NSScreen) {
    self.pool = pool
    self.screen = screen
    self.settings = settings
    panel = ChatPanel(model: model, name: settings.displayName, bubbleColor: settings.bubbleColor)
    session = pool.take()
    adopt(session)
    model.onSend = { [weak self] text in self?.send(text) }
    model.onMic = { [weak self] in self?.micPressed() }
    model.onAnswer = { [weak self] allow in self?.answered(allow) }
    model.onStop = { [weak self] in self?.stop() }
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
    staleTimeout?.cancel()
    dictation.stop()
    model.onSend = nil
    model.onMic = nil
    model.onAnswer = nil
    model.onStop = nil
    pendingAsk = nil
    model.pendingAsk = nil
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
    toolPending = false
    breakBeforeNextText = false

    // A session that died while idle was dropped; start one now, at most once per question.
    if session == nil {
      session = pool.take()
      adopt(session)
    }
    guard let session else { return fail(.toolMissing) }
    let question = model.log.messages.last?.text ?? text
    onThinkingChanged?(true)
    startTimeout(for: number)

    // The screen goes along only when the question sounds like it is about the screen; otherwise
    // the assistant answers straight away, or asks for the screen with `LOOK:0`.
    if ScreenNeed.likely(question) {
      sendWithScreen(question, to: session)
    } else {
      windows = []
      gate = ReplyGate(windowCount: 0, allowLook: false, allowScreen: true)
      pendingResults += 1
      session.send(text: question, jpegs: [], windows: [])
    }
  }

  /// The stop button or Escape: ends the answer on its way and keeps what has arrived. The session
  /// is told to stop too, and stays, so it still remembers the conversation. With no answer on its
  /// way, it stops the microphone instead.
  private func stop() {
    guard !closed else { return }
    guard model.log.waiting else { return dictation.stop() }
    if let ask = pendingAsk { session?.answer(id: ask.id, allow: false, input: ask.input) }
    gate = nil
    model.log.stop()
    stoppedWaiting()
    outcomeFor = questionNumber  // a stop is neither a finished answer nor a problem
    if pendingResults > 0, let session {
      staleResults = pendingResults
      session.interrupt()
      startStaleTimeout(for: session)
    }
    onStopped?()
  }

  /// A session that never ends a stopped answer would mix it into the next one; replace it.
  private func startStaleTimeout(for session: BrainSession) {
    staleTimeout?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self, !self.closed, self.session === session, self.staleResults > 0 else { return }
      if self.model.log.waiting { self.fail(.timeout) }
      self.dropSession()
    }
    staleTimeout = item
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.stopTimeout, execute: item)
  }

  /// Captures the display the ship is on and sends `text` with it and the window list.
  private func sendWithScreen(_ text: String, to session: BrainSession) {
    guard ScreenCapturer.hasPermission else {
      ScreenCapturer.requestPermission()
      return fail(.noScreenPermission)
    }
    onLooking?(nil)
    let number = questionNumber
    let displayID = screen.displayID
    Task { @MainActor [weak self] in
      do {
        guard let displayID else { throw CaptureError.displayNotFound }
        let shot = try await ScreenCapturer.captureDisplay(displayID)
        guard let self, self.isCurrent(number, session) else { return }
        self.windows = shot.windows
        self.windowFrames = shot.windowFrames
        self.gate = ReplyGate(windowCount: min(shot.windows.count, WindowList.limit), allowLook: true)
        self.pendingResults += 1
        session.send(text: text, jpegs: [shot.jpeg], windows: shot.windows)
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
    onLooking?(windowFrames[windowID].map(ScreenCapturer.appKitRect))
    Task { @MainActor [weak self] in
      let jpeg = try? await ScreenCapturer.captureWindow(id: windowID)
      guard let self, self.isCurrent(number, session) else { return }
      guard let jpeg else { return self.finish(appending: Self.unclearWindowReply, ok: false) }
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
      guard let self, !self.closed, number == self.questionNumber, self.pendingAsk == nil,
            self.settings.actions ? self.model.log.waiting : self.model.log.awaitingFirstText
      else { return }
      self.fail(.timeout)
      // The late reply would land on the next question; the next one gets a fresh session.
      self.dropSession()
    }
    timeout = item
    let seconds = settings.actions ? Self.actingTimeout : Self.replyTimeout
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
  }

  // MARK: Replies

  private func adopt(_ session: BrainSession?) {
    pendingResults = 0
    staleResults = 0
    staleTimeout?.cancel()
    staleTimeout = nil
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
    if staleResults > 0 {
      // The tail of an answer the owner stopped. A question asked since then is answered after it.
      switch event {
      case .result:
        pendingResults = max(0, pendingResults - 1)
        staleResults -= 1
        if staleResults == 0 {
          staleTimeout?.cancel()
          staleTimeout = nil
        }
      case .ask(let id, _, let input):
        session?.answer(id: id, allow: false, input: input)
      default:
        break
      }
      return
    }
    switch event {
    case .textDelta(let delta):
      guard gate != nil else { return }
      let shown = gate!.feed(delta)
      show(shown)
    case .toolPause:
      toolPending = true
    case .messageDone:
      if toolPending {
        toolPending = false
        pausedForTool()
      } else {
        replyEnded()
      }
    case .ask(let id, let tool, let input):
      asked(id: id, tool: tool, input: input)
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
    case .look(0):
      // A question sent without the screen turned out to need it.
      if let session { sendWithScreen(Self.screenReply, to: session) }
    case .look(let n): sendCloseUp(of: n)
    case .unusableMarker: finish(appending: Self.unclearWindowReply, ok: false)
    }
  }

  /// A message ended so the assistant could use a tool: show what was held back and keep waiting.
  private func pausedForTool() {
    guard var g = gate else { return }
    if case .text(let rest) = g.finish() { show(rest) }
    // The window close-up marker only makes sense as a whole first reply.
    gate = ReplyGate(windowCount: 0, allowLook: false)
    breakBeforeNextText = true
    if model.log.waiting && pendingAsk == nil { startTimeout(for: questionNumber) }
  }

  /// The session wants to use a tool: let it, or put the question to the owner.
  private func asked(id: String, tool: String, input: String) {
    guard let session else { return }
    guard model.log.waiting else { return session.answer(id: id, allow: false, input: input) }
    let fields = (input.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
    let exists = FileManager.default.fileExists(atPath:)
    let kind = ActionRules.kind(tool: tool, input: fields, home: home, exists: exists)
    let summary = ActionRules.summary(tool: tool, input: fields, home: home, exists: exists)
    if ActionRules.needsAsk(kind, policy: settings.askFirst) {
      pendingAsk = (id, input, summary)
      model.pendingAsk = summary
      timeout?.cancel()
      onThinkingChanged?(false)
    } else {
      session.answer(id: id, allow: true, input: input)
      if kind != .read { model.log.remark("Did: " + summary) }
      startTimeout(for: questionNumber)
    }
  }

  /// The owner pressed Allow or Don't.
  private func answered(_ allow: Bool) {
    guard !closed, let ask = pendingAsk else { return }
    pendingAsk = nil
    model.pendingAsk = nil
    session?.answer(id: ask.id, allow: allow, input: ask.input)
    model.log.remark((allow ? "Allowed: " : "Skipped: ") + ask.summary)
    guard model.log.waiting else { return }
    onThinkingChanged?(true)
    startTimeout(for: questionNumber)
  }

  /// Adds reply text to the panel, telling `onReplyStarted` when it is the answer's first.
  private func show(_ text: String) {
    guard !text.isEmpty else { return }
    var text = text
    if breakBeforeNextText {
      breakBeforeNextText = false
      if !model.log.betweenBubbles { text = "\n\n" + text }
    }
    let first = model.log.awaitingFirstText
    model.log.append(delta: text)
    if first && !model.log.awaitingFirstText { onReplyStarted?() }
  }

  private func finish(appending text: String, ok: Bool = true) {
    show(text)
    model.log.finish()
    stoppedWaiting()
    tellOutcome(ok)
  }

  private func fail(_ problem: BlipProblem) {
    gate = nil
    model.log.fail(problem)
    stoppedWaiting()
    tellOutcome(false)
  }

  /// Calls `onOutcome` for the current question, if it hasn't been called for it yet.
  private func tellOutcome(_ ok: Bool) {
    guard !closed, outcomeFor != questionNumber else { return }
    outcomeFor = questionNumber
    onOutcome?(ok)
  }

  private func stoppedWaiting() {
    pendingAsk = nil
    model.pendingAsk = nil
    toolPending = false
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
