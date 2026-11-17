import AppKit
import BlipCore

/// Owns the overlay: summons the ship on the shortcut, runs the scene on a
/// display link at a fixed 60 Hz tick, handles dragging, and closes the
/// overlay once the ship has flown off.
@MainActor
final class SummonController: NSObject {
  /// The ship has finished flying in; the point is the hover anchor in screen coordinates.
  var onArrived: ((NSScreen, CGPoint) -> Void)?
  /// The hover anchor moved (dragged, or moved to another screen); screen coordinates.
  var onAnchorMoved: ((NSScreen, CGPoint) -> Void)?
  /// The summon is over: the overlay closed after its fly-off, or a new summon
  /// replaced it. Called exactly once per summon.
  var onDismissed: (() -> Void)?
  var thinking = false { didSet { scene?.thinking = thinking } }

  private static let tickSeconds: CFTimeInterval = 1.0 / 60
  private static let maxTicksPerFrame = 4
  /// Blank ticks after `.gone` before the overlay closes.
  private static let blankTicksBeforeClose = 60
  /// Ticks a scene rebuilt on another screen is run ahead: past the 90-tick
  /// fly-in, then long enough for the fly-in trail to die out.
  private static let settleTicks = 150

  private let settings: () -> BlipSettings
  private var screen: NSScreen?
  private var window: CanvasWindow?
  private var scene: BlipCore.Scene?
  private var link: CADisplayLink?
  private var lastTimestamp: CFTimeInterval?
  private var accumulator: CFTimeInterval = 0
  private var arrived = false
  private var blankTicks = 0

  init(settings: @escaping () -> BlipSettings) {
    self.settings = settings
  }

  func shortcutPressed() {
    switch SummonState.onShortcut(phase: scene?.phase) {
    case .start, .restart:
      // A restart throws away a ship that is flying off; a start may find one
      // still lingering in `.gone`. Either way that summon is over.
      endSummon()
      if let s = screenUnderPointer() ?? NSScreen.main { start(on: s, hoveringAt: nil) }
    case .dismiss:
      scene?.dismiss()
    case .none:
      break
    }
  }

  // MARK: Lifecycle

  /// Opens the overlay on `screen`. With `hoveringAt`, the ship is already
  /// hovering with its anchor under that screen point; otherwise it flies in.
  private func start(on screen: NSScreen, hoveringAt point: CGPoint?) {
    let s = settings()
    let w = CanvasWindow(screen: screen, pointsPerPixel: s.size.pointsPerPixel)
    var sc = BlipCore.Scene(
      settings: s, bufferWidth: w.buffer.width, bufferHeight: w.buffer.height, seed: Self.clockSeed())
    sc.thinking = thinking
    if let point {
      for _ in 0..<Self.settleTicks { sc.tick() }
      let target = w.arcadePixel(atScreenPoint: point)
      sc.drag(dx: target.x - sc.anchor.x, dy: target.y - sc.anchor.y)
    }
    arrived = point != nil
    blankTicks = 0
    lastTimestamp = nil
    accumulator = 0
    w.onDrag = { [weak self] dx, dy in self?.dragged(dx: dx, dy: dy) }
    self.screen = screen
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
    window?.orderOut(nil)
    window?.close()
    window = nil
    scene = nil
    screen = nil
  }

  // MARK: Frames

  @objc private func frame(_ link: CADisplayLink) {
    guard scene != nil, let w = window, let screen else { return }

    if w.isDragging, let other = screenUnderPointer(), other.frame != screen.frame {
      moveToScreen(other)
      return
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
    guard ticks > 0 else {
      w.updateMouseAcceptance()
      return
    }

    for _ in 0..<ticks { scene!.tick() }
    render()
    let phase = scene!.phase

    if !arrived && phase == .hover {
      arrived = true
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
  }

  // MARK: Dragging

  private func dragged(dx: Int, dy: Int) {
    guard scene?.phase == .hover, let screen else { return }
    scene!.drag(dx: dx, dy: dy)
    render()
    onAnchorMoved?(screen, anchorPoint())
  }

  /// Rebuilds the overlay on `other`, hovering under the pointer.
  private func moveToScreen(_ other: NSScreen) {
    let pointer = NSEvent.mouseLocation
    tearDown()
    start(on: other, hoveringAt: pointer)
    onAnchorMoved?(other, anchorPoint())
  }

  // MARK: Helpers

  /// The hover anchor in screen coordinates.
  private func anchorPoint() -> CGPoint {
    guard let w = window, let sc = scene else { return .zero }
    return w.screenPoint(arcadeX: sc.anchor.x, y: sc.anchor.y)
  }

  private func screenUnderPointer() -> NSScreen? {
    let m = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) }
  }

  private static func clockSeed() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1000)
  }
}
