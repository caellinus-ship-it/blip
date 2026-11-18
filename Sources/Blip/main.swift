import AppKit
import BlipCore

// `Blip --brain-check "<question>" [--image <path.jpg>] [--capture] [--kill-after <seconds>]`:
// asks the hidden session one question with no UI, prints each event, then exits.
// `--capture` sends a fresh capture of the main display and its window list with the question.
// `--kill-after` kills the `claude` child (not Blip) that many seconds after the question is sent.
if CommandLine.arguments.contains("--brain-check") {
  MainActor.assumeIsolated { BrainCheck.run(CommandLine.arguments) }
}

// `Blip --capture-check`: prints the Screen Recording permission, captures the main display in memory
// and prints the JPEG's size and the window list, with no UI, then exits. Nothing is written to disk.
if CommandLine.arguments.contains("--capture-check") {
  MainActor.assumeIsolated { CaptureCheck.run() }
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
      fail("usage: Blip --brain-check \"<question>\" [--image <path.jpg>] [--capture] [--kill-after <seconds>]")
    }
    var jpegs: [Data] = []
    if let path = value(after: "--image") {
      guard let jpeg = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
      jpegs.append(jpeg)
    }
    let killAfter = value(after: "--kill-after").flatMap(Double.init)
    let capture = arguments.contains("--capture")
    if capture && !ScreenCapturer.hasPermission {
      ScreenCapturer.requestPermission()
      fail("--capture needs Screen Recording permission for Blip (System Settings > Privacy & Security)")
    }

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
    func ask(jpegs: [Data], windows: [WindowInfo]) {
      session.send(text: question, jpegs: jpegs, windows: windows)
      if let killAfter {
        DispatchQueue.main.asyncAfter(deadline: .now() + killAfter) {
          if session.isRunning { kill(session.processIdentifier, SIGKILL) }
        }
      }
    }

    if capture {
      Task { @MainActor in
        do {
          let shot = try await ScreenCapturer.captureDisplay(NSScreen.main ?? NSScreen.screens[0])
          say("captured \(shot.jpeg.count) bytes, \(shot.windows.count) windows")
          ask(jpegs: jpegs + [shot.jpeg], windows: shot.windows)
        } catch {
          say("CAPTURE FAILED \(error)")
          finish(1)
        }
      }
    } else {
      ask(jpegs: jpegs, windows: [])
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

@MainActor enum CaptureCheck {
  static func run() -> Never {
    setvbuf(stdout, nil, _IOLBF, 0)
    let permission = ScreenCapturer.hasPermission
    print("permission: \(permission)")
    guard permission else {
      ScreenCapturer.requestPermission()
      print("requested Screen Recording; allow Blip in System Settings > Privacy & Security, then run again")
      exit(1)
    }
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
      print("no display")
      exit(1)
    }
    Task { @MainActor in
      do {
        let start = DispatchTime.now()
        let capture = try await ScreenCapturer.captureDisplay(screen)
        let ms = (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        print("display: \(describe(capture.jpeg)) in \(ms) ms")
        print("windows: \(capture.windows.count)")
        for window in capture.windows {
          print("  \(window.id)  \(window.app)\(window.title.isEmpty ? "" : " — " + window.title)")
        }
        if let front = capture.windows.first {
          let jpeg = try await ScreenCapturer.captureWindow(id: front.id)
          print("front window \(front.id): \(describe(jpeg))")
        }
        exit(0)
      } catch {
        print("capture failed: \(error)")
        exit(1)
      }
    }
    RunLoop.main.run()
    exit(0)
  }

  /// Byte count and pixel size, read back from the JPEG in memory.
  private static func describe(_ jpeg: Data) -> String {
    let source = CGImageSourceCreateWithData(jpeg as CFData, nil)
    let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) } as? [CFString: Any]
    let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
    return "\(jpeg.count) bytes JPEG, \(width)x\(height) px"
  }
}

private extension String {
  func leftPadded(to width: Int) -> String {
    String(repeating: " ", count: max(0, width - count)) + self
  }
}
