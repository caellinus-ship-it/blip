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
  private var lines = LineBuffer()
  private var stopped = false
  private var outputEnded = false
  private var exited = false

  /// Seconds `stop` waits for the process to honor SIGTERM before it sends SIGKILL.
  private static let killDelay: TimeInterval = 2

  init?(settings: BlipSettings) {
    var environment = ProcessInfo.processInfo.environment
    let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
    environment["HOME"] = home
    guard let claude = ClaudeLocator.find(custom: settings.claudePath, home: home,
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
    process.standardError = environment["BLIP_DEBUG"] == "1" ? FileHandle.standardError : FileHandle.nullDevice

    // A write to a process that already died must fail as an error, not kill Blip with SIGPIPE.
    signal(SIGPIPE, SIG_IGN)

    output.fileHandleForReading.readabilityHandler = { [self] handle in
      let chunk = handle.availableData
      if chunk.isEmpty { handle.readabilityHandler = nil }
      DispatchQueue.main.async { chunk.isEmpty ? self.outputDidEnd() : self.consume(chunk) }
    }
    process.terminationHandler = { [self] _ in
      DispatchQueue.main.async { self.processDidExit() }
    }

    do {
      try process.run()
    } catch {
      output.fileHandleForReading.readabilityHandler = nil
      return nil
    }
  }

  var isRunning: Bool { process.isRunning }
  var processIdentifier: Int32 { process.processIdentifier }

  func send(text: String, jpegs: [Data], windows: [WindowInfo]) {
    guard !stopped else { return }
    let line = Data((UserMessage.line(text: text, jpegs: jpegs, windows: windows) + "\n").utf8)
    let handle = input.fileHandleForWriting
    // A failed write means the process died; that is reported through `onExit`.
    writeQueue.async { try? handle.write(contentsOf: line) }
  }

  /// Closes stdin and terminates the process, escalating to SIGKILL if it lingers. No events follow.
  func stop() {
    guard !stopped else { return }
    stopped = true
    onEvent = nil
    onExit = nil
    let handle = input.fileHandleForWriting
    // Terminating first unblocks a write stuck on a full pipe, so the close behind it can run.
    if process.isRunning { process.terminate() }
    writeQueue.async { try? handle.close() }
    let process = self.process
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.killDelay) {
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
  }

  private func consume(_ chunk: Data) {
    for line in lines.append(chunk) where !stopped {
      onEvent?(StreamParser.parse(line: line))
    }
  }

  private func outputDidEnd() {
    outputEnded = true
    reportExitIfFinished()
  }

  private func processDidExit() {
    exited = true
    // The output normally ends with the process; don't wait forever if a stray child keeps it open.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
      outputEnded = true
      reportExitIfFinished()
    }
    reportExitIfFinished()
  }

  private func reportExitIfFinished() {
    guard exited, outputEnded, !stopped else { return }
    stopped = true
    output.fileHandleForReading.readabilityHandler = nil
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

  init(settings: @escaping () -> BlipSettings) {
    self.settings = settings
    standby = startStandby()
  }

  /// Hands over the standby, or a session started on the spot if there is none.
  func take() -> BrainSession? {
    if let session = standby {
      standby = nil
      return session
    }
    return startStandby()
  }

  /// Stops a session that is done with and gets a fresh standby ready.
  func release(_ session: BrainSession) {
    session.stop()
    if standby == nil { standby = startStandby() }
  }

  /// Replaces the idle standby so the next question uses the new settings.
  func settingsChanged() {
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
