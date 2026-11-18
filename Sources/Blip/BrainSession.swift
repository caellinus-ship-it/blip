import BlipCore
import Foundation

/// One hidden `claude` process: questions go in on stdin, parsed events come back on the main queue.
/// Use it from the main thread only.
final class BrainSession {
  var onEvent: ((BrainEvent) -> Void)?
  /// Called once when the process ends by itself (never after `stop`), after its last output was delivered.
  var onExit: (() -> Void)?

  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  /// Writes can block on a full pipe, so they run off the main thread, in order.
  private let writeQueue = DispatchQueue(label: "com.blip.assistant.brain-write")
  /// Launching and terminating the process run here, in order, off the main thread.
  private let launchQueue = DispatchQueue(label: "com.blip.assistant.brain-launch")
  private var lines = LineBuffer()
  private var stopped = false
  private var outputEnded = false
  private var exited = false

  /// Seconds `stop` waits for the process to honor SIGTERM before it sends SIGKILL.
  private static let killDelay: TimeInterval = 2

  /// Debug switch `BLIP_DEBUG=1`: each launch, the child's stderr and every parsed event go to Blip's stderr.
  private static let debug = ProcessInfo.processInfo.environment["BLIP_DEBUG"] == "1"

  /// Nil when no `claude` executable is found. The process starts shortly after, off the main thread.
  init?(settings: BlipSettings) {
    var environment = ProcessInfo.processInfo.environment
    // Debug switch `BLIP_NO_CLAUDE=1`: behave as if the tool were missing.
    if environment["BLIP_NO_CLAUDE"] == "1" { return nil }
    // Debug switch `BLIP_CLAUDE_PATH=<path>`: run this executable instead of `claude`, e.g. `/usr/bin/false`.
    let customPath = environment["BLIP_CLAUDE_PATH"] ?? settings.claudePath
    let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
    environment["HOME"] = home
    guard let claude = ClaudeLocator.find(custom: customPath, home: home,
                                          exists: FileManager.default.isExecutableFile(atPath:))
    else { return nil }

    let workDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Blip", isDirectory: true)
    try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

    process.executableURL = URL(fileURLWithPath: claude)
    process.arguments = BrainCommand.arguments(model: settings.model,
                                               systemPrompt: PromptBuilder.systemPrompt(settings))
    process.currentDirectoryURL = workDir
    process.environment = environment
    process.standardInput = input
    process.standardOutput = output
    process.standardError = Self.debug ? FileHandle.standardError : FileHandle.nullDevice

    // A write to a process that already died must fail as an error, not kill Blip with SIGPIPE.
    signal(SIGPIPE, SIG_IGN)

    // Neither handler holds the session, so a session nobody uses any more is freed with its pipes.
    // The reading end is held by its own handler until the output ends, then closed there, on the
    // handler's queue, so it is never closed under a read in progress.
    let reader = output.fileHandleForReading
    reader.readabilityHandler = { [weak self] _ in
      let chunk = reader.availableData
      if chunk.isEmpty {
        reader.readabilityHandler = nil
        try? reader.close()
      }
      DispatchQueue.main.async { chunk.isEmpty ? self?.outputDidEnd() : self?.consume(chunk) }
    }
    process.terminationHandler = { [weak self] _ in
      DispatchQueue.main.async { self?.processDidExit() }
    }

    // Starting a process takes milliseconds the 60 Hz animation can't spare, so it happens off the
    // main thread. A launch that fails is reported like an exit.
    let process = self.process
    launchQueue.async { [weak self] in
      do {
        try process.run()
        if Self.debug { FileHandle.standardError.write(Data("BrainSession launched \(claude) pid \(process.processIdentifier)\n".utf8)) }
      } catch {
        NSLog("Blip: could not start \(claude) (\(error))")
        reader.readabilityHandler = nil
        try? reader.close()
        DispatchQueue.main.async { self?.launchFailed() }
      }
    }
  }

  /// Everyone stops a session before letting go of it; this only makes sure no `claude` outlives it.
  deinit {
    stop()
  }

  var isRunning: Bool { process.isRunning }
  var processIdentifier: Int32 { process.processIdentifier }

  func send(text: String, jpegs: [Data], windows: [WindowInfo]) {
    guard !stopped else { return }
    let handle = input.fileHandleForWriting
    // Encoding the images is done on the write queue too, so a send never holds up the main thread.
    // A failed write means the process died; that is reported through `onExit`.
    writeQueue.async {
      let line = Data((UserMessage.line(text: text, jpegs: jpegs, windows: windows) + "\n").utf8)
      try? handle.write(contentsOf: line)
    }
  }

  /// Closes stdin and terminates the process, escalating to SIGKILL if it lingers. No events follow.
  func stop() {
    guard !stopped else { return }
    stopped = true
    onEvent = nil
    onExit = nil
    process.terminationHandler = nil
    let handle = input.fileHandleForWriting
    let process = self.process
    // After the launch, if it is still under way. Terminating unblocks a write stuck on a full pipe,
    // so the close behind it can run. The output's end closes the reading end.
    launchQueue.async { if process.isRunning { process.terminate() } }
    writeQueue.async { try? handle.close() }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.killDelay) {
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
  }

  private func consume(_ chunk: Data) {
    for line in lines.append(chunk) where !stopped {
      let event = StreamParser.parse(line: line)
      if Self.debug { FileHandle.standardError.write(Data("BrainEvent \(event)\n".utf8)) }
      onEvent?(event)
    }
  }

  private func outputDidEnd() {
    outputEnded = true
    reportExitIfFinished()
  }

  private func processDidExit() {
    exited = true
    // The output normally ends with the process; don't wait forever if a stray child keeps it open.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.outputEnded = true
      self?.reportExitIfFinished()
    }
    reportExitIfFinished()
  }

  private func launchFailed() {
    exited = true
    outputEnded = true
    reportExitIfFinished()
  }

  private func reportExitIfFinished() {
    guard exited, outputEnded, !stopped else { return }
    stopped = true
    process.terminationHandler = nil
    let handle = input.fileHandleForWriting
    writeQueue.async { try? handle.close() }
    let callback = onExit
    onEvent = nil
    onExit = nil
    callback?()
  }
}

/// Keeps one idle session started ahead of time, so a question never waits for `claude` to launch.
@MainActor final class BrainPool {
  private let settings: () -> BlipSettings
  private var standby: BrainSession?
  /// Sessions handed out by `take` and not yet released, so `shutdown` can stop them.
  private var taken: [BrainSession] = []
  private var isShutDown = false

  init(settings: @escaping () -> BlipSettings) {
    self.settings = settings
    standby = startStandby()
  }

  /// Hands over the standby, or a session started on the spot if there is none.
  func take() -> BrainSession? {
    guard !isShutDown else { return nil }
    let session = standby ?? startStandby()
    standby = nil
    if let session { taken.append(session) }
    return session
  }

  /// Stops a session that is done with and gets a fresh standby ready on the next main-queue turn, so
  /// a dismiss that lets one go has started the fly-off first.
  func release(_ session: BrainSession) {
    session.stop()
    taken.removeAll { $0 === session }
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.standby == nil, !self.isShutDown else { return }
        self.standby = self.startStandby()
      }
    }
  }

  /// Stops every session, idle or in use, and starts no more. For quitting, so no `claude` outlives Blip.
  func shutdown() {
    isShutDown = true
    standby?.stop()
    standby = nil
    taken.forEach { $0.stop() }
    taken = []
  }

  /// Replaces the idle standby so the next question uses the new settings.
  func settingsChanged() {
    guard !isShutDown else { return }
    standby?.stop()
    standby = startStandby()
  }

  private func startStandby() -> BrainSession? {
    guard let session = BrainSession(settings: settings()) else { return nil }
    // A standby that dies while idle is dropped, not restarted, so a broken `claude` can't spin;
    // the next `take` starts one on the spot. Whoever takes the session replaces this handler.
    session.onExit = { [weak self, weak session] in
      MainActor.assumeIsolated {
        guard let self, let session, self.standby === session else { return }
        self.standby = nil
      }
    }
    return session
  }
}
