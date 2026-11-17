import AppKit
import BlipCore

// `Blip --brain-check "<question>" [--image <path.jpg>] [--kill-after <seconds>]`:
// asks the hidden session one question with no UI, prints each event, then exits.
// `--kill-after` kills the `claude` child (not Blip) that many seconds after the question is sent.
if CommandLine.arguments.contains("--brain-check") {
  MainActor.assumeIsolated { BrainCheck.run(CommandLine.arguments) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

@MainActor enum BrainCheck {
  static func run(_ arguments: [String]) -> Never {
    func value(after flag: String) -> String? {
      guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
      return arguments[i + 1]
    }
    guard let question = value(after: "--brain-check") else {
      fail("usage: Blip --brain-check \"<question>\" [--image <path.jpg>] [--kill-after <seconds>]")
    }
    var jpegs: [Data] = []
    if let path = value(after: "--image") {
      guard let jpeg = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
      jpegs.append(jpeg)
    }
    let killAfter = value(after: "--kill-after").flatMap(Double.init)

    setvbuf(stdout, nil, _IOLBF, 0)
    let start = DispatchTime.now()
    func say(_ text: String) {
      let ms = (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
      print("\(String(ms).leftPadded(to: 6)) ms  \(text)")
    }

    let pool = BrainPool(settings: { BlipSettings() })
    guard let session = pool.take() else { fail("no claude executable found") }

    // Exit only once the child is gone; `stop` escalates to SIGKILL within two seconds.
    func exitWhenChildGone(_ code: Int32) {
      if !session.isRunning { exit(code) }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exitWhenChildGone(code) }
    }
    func finish(_ code: Int32) {
      session.stop()
      exitWhenChildGone(code)
    }

    session.onEvent = { event in
      say(String(describing: event))
      switch event {
      case .messageDone, .result: finish(0)
      default: break
      }
    }
    session.onExit = {
      say("EXIT")
      finish(1)
    }
    session.send(text: question, jpegs: jpegs, windows: [])

    if let killAfter {
      DispatchQueue.main.asyncAfter(deadline: .now() + killAfter) {
        if session.isRunning { kill(session.processIdentifier, SIGKILL) }
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
      say("TIMEOUT")
      finish(1)
    }

    RunLoop.main.run()
    exit(0)
  }

  private static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
  }
}

private extension String {
  func leftPadded(to width: Int) -> String {
    String(repeating: " ", count: max(0, width - count)) + self
  }
}
