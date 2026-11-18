import AppKit
import BlipCore

/// Owns the overlay: summons the ship on the shortcut, runs the scene on a
/// display link at a fixed 60 Hz tick, handles dragging, and closes the
/// overlay once the ship has flown off.
@MainActor
final class SummonController: NSObject {
  /// A new summon began on this screen: its first frame is out and the ship is starting its fly-in.
  /// Called from the overlay's first display-link callback, so nothing built here holds up that frame.
  var onSummoned: ((NSScreen) -> Void)?
  /// The ship has finished flying in; the point is the hover anchor in screen coordinates.
  var onArrived: ((NSScreen, CGPoint) -> Void)?
  /// The hover anchor moved (dragged, or moved to another screen); screen coordinates.
  var onAnchorMoved: ((NSScreen, CGPoint) -> Void)?
  /// The shortcut sent the ship off; it is starting its fly-off.
  var onFlyOff: (() -> Void)?
  /// The summon is over: the overlay closed after its fly-off, a new summon
  /// replaced it, or its display was unplugged. Called exactly once per summon.
  var onDismissed: (() -> Void)?
  var thinking = false { didSet { scene?.thinking = thinking } }
  /// The creature is looking at the screen; kept when the summon moves to another display.
  private var reading = false { didSet { scene?.reading = reading } }
  /// When the shortcut that started the current summon was pressed (`CACurrentMediaTime`).
  private(set) var pressedAt: CFTimeInterval = 0
  /// Half the width of the ship and its creature, in points.
  var shipHalfWidth: CGFloat {
    guard let w = window, let sc = scene else { return 0 }
    return CGFloat(sc.hitRect.w * w.pointsPerPixel) / 2
  }

  private static let tickSeconds: CFTimeInterval = 1.0 / 60
  private static let maxTicksPerFrame = 4
  /// Blank ticks after `.gone` before the overlay closes.
  private static let blankTicksBeforeClose = 60
  /// Ticks a scene rebuilt on another screen (or for the settings preview) is run ahead: past the 90-tick
  /// fly-in, then long enough for the fly-in trail to die out.
  static let settleTicks = 150

  private let settings: () -> BlipSettings
  /// The settings the current summon started with; moving to another screen keeps them.
  private var summonSettings = BlipSettings()
  private var screen: NSScreen?
  /// The display the overlay covers.
  private var displayID: CGDirectDisplayID?
  private var window: CanvasWindow?
  private var scene: BlipCore.Scene?
  private var link: CADisplayLink?
  private var lastTimestamp: CFTimeInterval?
  private var accumulator: CFTimeInterval = 0
  private var arrived = false
  /// `onSummoned` has been called for the current summon.
  private var announced = true
  private var blankTicks = 0
  private var timing = SummonTiming()

  init(settings: @escaping () -> BlipSettings) {
    self.settings = settings
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification,
      object: nil)
  }

  /// `pressedAt` is when the shortcut was taken (`CACurrentMediaTime`), for the debug timing log.
  func shortcutPressed(at pressedAt: CFTimeInterval = CACurrentMediaTime()) {
    switch SummonState.onShortcut(phase: scene?.phase) {
    case .start, .restart:
      self.pressedAt = pressedAt
      timing.summoned(at: pressedAt)
      // A restart throws away a ship that is flying off; a start may find one
      // still lingering in `.gone`. Either way that summon is over.
      endSummon()
      thinking = false
      reading = false
      if let s = screenUnderPointer() ?? NSScreen.main {
        summonSettings = settings()
        start(on: s, hovering: nil)
        announced = false
      }
    case .dismiss:
      announced = true  // sent back before its first frame: it never gets a chat
      timing.flyOffStarted()
      reading = false
      scene?.dismiss()
      onFlyOff?()
    case .none:
      break
    }
  }

  // MARK: Lifecycle

  /// Opens the overlay on `screen` with the summon's settings. With `hovering`, the ship is already
  /// hovering with its anchor at the pointer (a screen point) minus the grab offset (arcade pixels),
  /// kept inside the screen; otherwise it flies in.
  private func start(on screen: NSScreen, hovering: (pointer: CGPoint, grab: (x: Int, y: Int))?) {
    let s = summonSettings
    let w = CanvasWindow(screen: screen, pointsPerPixel: s.size.pointsPerPixel)
    var sc = BlipCore.Scene(
      settings: s, bufferWidth: w.buffer.width, bufferHeight: w.buffer.height, seed: Self.clockSeed())
    sc.thinking = thinking
    sc.reading = reading
    if let hovering {
      for _ in 0..<Self.settleTicks { sc.tick() }
      let p = w.arcadePixel(atScreenPoint: hovering.pointer)
      sc.drag(dx: p.x - hovering.grab.x - sc.anchor.x, dy: p.y - hovering.grab.y - sc.anchor.y)
    }
    arrived = hovering != nil
    blankTicks = 0
    lastTimestamp = nil
    accumulator = 0
    w.onDrag = { [weak self] anchor in self?.dragged(to: anchor) }
    w.onDragEnded = { [weak self] pointer, grab in
      // After the event that ended the drag, since moving to another screen closes this window.
      DispatchQueue.main.async { MainActor.assumeIsolated { self?.dragEnded(pointer: pointer, grab: grab) } }
    }
    self.screen = screen
    displayID = screen.displayID
    window = w
    scene = sc
    render()
    w.orderFrontRegardless()

    let l = w.contentView!.displayLink(target: self, selector: #selector(frame(_:)))
    l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
    l.add(to: .main, forMode: .common)
    link = l
  }

  /// Ends the current summon, if any: closes the overlay and calls `onDismissed`
  /// exactly once for it.
  private func endSummon() {
    guard window != nil else { return }
    tearDown()
    onDismissed?()
  }

  /// Closes the overlay, if any, without telling anyone. Used directly only
  /// when the same summon continues on another screen.
  private func tearDown() {
    link?.invalidate()
    link = nil
    window?.onDrag = nil
    window?.onDragEnded = nil
    window?.orderOut(nil)
    window?.close()
    window = nil
    scene = nil
    screen = nil
    displayID = nil
  }

  /// A display was plugged in, unplugged or rearranged. A summon whose display is gone ends at once, the
  /// way a finished fly-off does; its chat closes with it.
  @objc private func screensChanged(_ notification: Notification) {
    guard window != nil, let displayID else { return }
    let displays = NSScreen.screens.compactMap(\.displayID)
    guard SummonState.endsOnDisplayChange(shipDisplay: displayID, displays: displays) else { return }
    thinking = false
    reading = false
    endSummon()
  }

  // MARK: Looking and moods

  /// The assistant is taking a picture of `screenRect` (AppKit screen coordinates; `nil` for the whole
  /// display the ship is on): the creature starts reading and a scan beam sweeps that area.
  func scan(_ screenRect: CGRect?) {
    guard let w = window, scene != nil else { return }
    reading = true
    guard let r = screenRect else { return scene!.scan(nil) }
    // Arcade pixels run down from the window's top-left; screen points run up from the bottom.
    let topLeft = w.arcadePixel(atScreenPoint: CGPoint(x: r.minX, y: r.maxY))
    let p = CGFloat(w.pointsPerPixel)
    scene!.scan((topLeft.x, topLeft.y, Int((r.width / p).rounded(.up)), Int((r.height / p).rounded(.up))))
  }

  /// The creature stops reading: the first words of the answer showed, or the question ended.
  func stopReading() { reading = false }

  /// Shows a reaction on the creature.
  func react(_ reaction: BlipCore.Scene.Reaction) { scene?.react(reaction) }

  // MARK: Frames

  @objc private func frame(_ link: CADisplayLink) {
    guard scene != nil, let w = window, let screen else { return }
    timing.frame(phase: scene!.phase)
    if !announced {
      announced = true
      onSummoned?(screen)
    }

    if let last = lastTimestamp { accumulator += link.timestamp - last }
    lastTimestamp = link.timestamp
    // A little slack so display-link jitter around 1/60 s does not drop a tick.
    var ticks = Int(accumulator / Self.tickSeconds + 0.05)
    if ticks > Self.maxTicksPerFrame {
      ticks = Self.maxTicksPerFrame
      accumulator = 0
    } else {
      accumulator -= Double(ticks) * Self.tickSeconds
    }
    scene!.look(at: w.arcadePixel(atScreenPoint: NSEvent.mouseLocation))
    guard ticks > 0 else {
      w.updateMouseAcceptance()
      return
    }

    for _ in 0..<ticks { scene!.tick() }
    render()
    let phase = scene!.phase

    if !arrived && phase == .hover {
      arrived = true
      logAnchor("arrived")
      onArrived?(screen, anchorPoint())
    }

    if phase == .gone {
      blankTicks = w.buffer.pixels.allSatisfy { $0 == 0 } ? blankTicks + ticks : 0
      if blankTicks >= Self.blankTicksBeforeClose {
        endSummon()
      }
    }
  }

  /// Draws the scene and refreshes the clickable area.
  private func render() {
    guard let w = window, let sc = scene else { return }
    w.buffer.clear()
    sc.render(into: &w.buffer)
    w.present(w.buffer)
    w.hitRect = sc.phase == .hover ? w.windowRect(arcade: sc.hitRect) : nil
    w.anchor = sc.anchor
  }

  // MARK: Dragging

  /// Moves the anchor toward where the pointer asks for it; the scene stops it at the screen's edges.
  private func dragged(to target: (x: Int, y: Int)) {
    guard scene?.phase == .hover, let screen else { return }
    let before = scene!.anchor
    scene!.drag(dx: target.x - before.x, dy: target.y - before.y)
    guard scene!.anchor != before else { return }
    render()
    onAnchorMoved?(screen, anchorPoint())
  }

  /// Let go on another display: the overlay is rebuilt there with the ship hovering under the pointer,
  /// held where it was grabbed, and the chat follows. Nothing moves once the ship has been sent off.
  private func dragEnded(pointer: CGPoint, grab: (x: Int, y: Int)) {
    guard let phase = scene?.phase, let displayID else { return }
    let other = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    guard let other,
          SummonState.movesOnDragEnd(phase: phase, shipDisplay: displayID, pointerDisplay: other.displayID)
    else { return logAnchor("drag ended") }
    tearDown()
    start(on: other, hovering: (pointer, grab))
    logAnchor("drag ended, moved to another display")
    onAnchorMoved?(other, anchorPoint())
  }

  // MARK: Helpers

  /// The hover anchor in screen coordinates.
  private func anchorPoint() -> CGPoint {
    guard let w = window, let sc = scene else { return .zero }
    return w.screenPoint(arcadeX: sc.anchor.x, y: sc.anchor.y)
  }

  /// Debug log: where the anchor is, in screen points (top-left origin, as `CGEvent`s use) and arcade pixels.
  private func logAnchor(_ what: String) {
    guard SummonTiming.on, let sc = scene, let displayID else { return }
    let p = anchorPoint(), top = NSScreen.screens.first?.frame.maxY ?? 0
    SummonTiming.log(String(format: "ship: %@ on display %u, anchor (%.1f, %.1f), arcade (%d, %d)",
                            what, displayID, p.x, top - p.y, sc.anchor.x, sc.anchor.y))
  }

  private func screenUnderPointer() -> NSScreen? {
    let m = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) }
  }

  private static func clockSeed() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1000)
  }
}

extension NSScreen {
  /// The display this screen shows, as Core Graphics and ScreenCaptureKit know it.
  var displayID: CGDirectDisplayID? {
    deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
  }
}

/// Debug switch `BLIP_DEBUG=1`: how soon after the shortcut the overlay's first frame comes, and the
/// longest gap between frames over each fly-in and fly-off, go to Blip's stderr.
struct SummonTiming {
  static let on = ProcessInfo.processInfo.environment["BLIP_DEBUG"] == "1"

  private var pressedAt: CFTimeInterval?
  private var lastFrame: CFTimeInterval?
  private var longestGap: CFTimeInterval = 0
  /// When the longest gap ended, from the start of the flight.
  private var longestGapAt: CFTimeInterval = 0
  /// Gaps of more than one and a half frames.
  private var longGaps = 0
  private var flightStart: CFTimeInterval = 0
  /// The flight being watched: `.flyIn` or `.flyOut`.
  private var flight: Phase?

  mutating func summoned(at time: CFTimeInterval) {
    guard Self.on else { return }
    pressedAt = time
    lastFrame = nil
    startFlight(.flyIn, at: time)
  }

  mutating func flyOffStarted() {
    guard Self.on else { return }
    startFlight(.flyOut, at: CACurrentMediaTime())
  }

  private mutating func startFlight(_ phase: Phase, at time: CFTimeInterval) {
    flight = phase
    flightStart = time
    longestGap = 0
    longestGapAt = 0
    longGaps = 0
  }

  /// A display-link callback, before the scene ticks.
  mutating func frame(phase: Phase) {
    guard Self.on else { return }
    let now = CACurrentMediaTime()
    if let pressedAt {
      Self.log(String(format: "summon: first frame callback %.1f ms after the shortcut", (now - pressedAt) * 1000))
      self.pressedAt = nil
    }
    if let lastFrame {
      let gap = now - lastFrame
      if gap > 1.5 / 60 { longGaps += 1 }
      if gap > longestGap { (longestGap, longestGapAt) = (gap, now - flightStart) }
    }
    lastFrame = now
    if flight == .flyIn && phase != .flyIn || flight == .flyOut && phase == .gone {
      Self.log(String(format: "%@: longest gap between frames %.1f ms, ending %.0f ms in; %d gaps over 25 ms",
                      flight == .flyIn ? "fly-in" : "fly-off", longestGap * 1000, longestGapAt * 1000, longGaps))
      flight = nil
    }
  }

  static func log(_ line: String) {
    if on { FileHandle.standardError.write(Data("\(line)\n".utf8)) }
  }
}
