import AppKit
import BlipCore
import SwiftUI

/// The stage: the character run by the same `Scene` as the overlay, at the chosen size, so one arcade
/// pixel is `settings.size.pointsPerPixel` points. With `entrance` it flies in when it appears and
/// again whenever the look changes; without, it starts already hovering. Bumping `launches` replays
/// the fly-in on demand. It animates only while its window is on screen.
struct CharacterPreview: NSViewRepresentable {
  /// The stage in points.
  let size: CGSize
  let settings: BlipSettings
  var entrance = true
  var launches = 0

  func makeNSView(context: Context) -> StageView {
    context.coordinator.launches = launches
    return StageView(size: size, settings: settings, entrance: entrance)
  }

  func updateNSView(_ view: StageView, context: Context) {
    view.show(settings)
    if launches != context.coordinator.launches {
      context.coordinator.launches = launches
      view.replay()
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: StageView, context: Context) -> CGSize? { size }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator {
    var launches = 0
  }

  final class StageView: NSView {
    private static let tickSeconds: CFTimeInterval = 1.0 / 60
    private static let maxTicksPerFrame = 4
    /// Seconds of quiet after a custom color changes before the fly-in replays with it, so dragging
    /// in a color well doesn't restart the scene on every color it passes through.
    private static let colorReplayDelay: TimeInterval = 0.3

    /// What the stage draws; any change replays the fly-in. The name and the assistant's settings
    /// are not part of it.
    private struct Look: Equatable {
      var creature: Creature, ship: Ship, trail: TrailStyle, trailColor: TrailColor
      var auraColor: RGBA?, comet: Bool, hover: HoverMotion, size: SizeOption

      init(_ s: BlipSettings) {
        (creature, ship, trail, trailColor, auraColor, comet, hover, size) =
          (s.creature, s.ship, s.trail, s.trailColor, s.auraColor, s.comet, s.hover, s.size)
      }

      /// True when going from `old` to this look only picked a new custom trail color or aura color,
      /// which is what a color well reports while it is being dragged.
      func onlyCustomColorChanged(from old: Look) -> Bool {
        var a = self, b = old
        if case .custom = trailColor { (a.trailColor, b.trailColor) = (.custom(0), .custom(0)) }
        if auraColor != nil, old.auraColor != nil { (a.auraColor, b.auraColor) = (0, 0) }
        return a == b
      }
    }

    private let stageSize: CGSize
    private let entrance: Bool
    private var settings: BlipSettings
    private var look: Look
    private var scene: BlipCore.Scene
    private var buffer: PixelBuffer
    private var replays: UInt64 = 0
    private var pendingReplay: DispatchWorkItem?
    private let pixelLayer = CALayer()
    /// Faint fixed stars behind the scene, drawn once per buffer size.
    private let starLayer = CALayer()
    private var starSize: (width: Int, height: Int) = (0, 0)
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var accumulator: CFTimeInterval = 0
    private var windowObservers: [NSObjectProtocol] = []

    init(size: CGSize, settings: BlipSettings, entrance: Bool) {
      stageSize = size
      self.entrance = entrance
      self.settings = settings
      look = Look(settings)
      buffer = Self.buffer(for: size, settings)
      scene = Self.scene(settings, buffer: buffer, seed: 1, hovering: !entrance)
      super.init(frame: NSRect(origin: .zero, size: size))
      wantsLayer = true
      for l in [starLayer, pixelLayer] {
        l.magnificationFilter = .nearest
        l.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(l)
      }
      setAccessibilityElement(true)
      setAccessibilityRole(.image)
      setAccessibilityLabel("Preview")
      placePixelLayer()
      render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
      for o in windowObservers { NotificationCenter.default.removeObserver(o) }
    }

    override var intrinsicContentSize: NSSize { stageSize }

    override func layout() {
      super.layout()
      placePixelLayer()
    }

    /// Shows `settings`, replaying the fly-in if they look different from what is shown.
    func show(_ new: BlipSettings) {
      settings = new
      let newLook = Look(new)
      guard newLook != look else { return }
      let old = look
      look = newLook
      pendingReplay?.cancel()
      if newLook.onlyCustomColorChanged(from: old) {
        let replay = DispatchWorkItem { [weak self] in self?.replay() }
        pendingReplay = replay
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.colorReplayDelay, execute: replay)
      } else {
        restart(hovering: !entrance)
      }
    }

    /// Restarts the scene from the fly-in with the current settings.
    func replay() {
      restart(hovering: false)
    }

    private func restart(hovering: Bool) {
      pendingReplay?.cancel()
      pendingReplay = nil
      replays &+= 1
      let b = Self.buffer(for: stageSize, settings)
      if b.width != buffer.width || b.height != buffer.height {
        buffer = b
        placePixelLayer()
      }
      scene = Self.scene(settings, buffer: buffer, seed: replays &+ 1, hovering: hovering)
      lastTimestamp = nil
      accumulator = 0
      render()
    }

    // MARK: Running only while visible

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      for o in windowObservers { NotificationCenter.default.removeObserver(o) }
      windowObservers = []
      guard let window else {
        stopLink()
        pendingReplay?.cancel()
        return
      }
      let center = NotificationCenter.default
      for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                   NSWindow.didDeminiaturizeNotification] {
        windowObservers.append(
          center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateRunning() }
          })
      }
      updateRunning()
    }

    /// Runs the display link while the window is on screen: not closed, minimised or fully covered.
    private func updateRunning() {
      guard let window, window.occlusionState.contains(.visible), !window.isMiniaturized else {
        stopLink()
        return
      }
      guard link == nil else { return }
      lastTimestamp = nil
      accumulator = 0
      let l = displayLink(target: self, selector: #selector(frame(_:)))
      l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
      l.add(to: .main, forMode: .common)
      link = l
    }

    /// The display link holds on to the view, so it must be invalidated, not just dropped.
    private func stopLink() {
      link?.invalidate()
      link = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
      if let last = lastTimestamp { accumulator += link.timestamp - last }
      lastTimestamp = link.timestamp
      var ticks = Int(accumulator / Self.tickSeconds + 0.05)
      if ticks > Self.maxTicksPerFrame {
        ticks = Self.maxTicksPerFrame
        accumulator = 0
      } else {
        accumulator -= Double(ticks) * Self.tickSeconds
      }
      guard ticks > 0 else { return }
      for _ in 0..<ticks { scene.tick() }
      render()
    }

    // MARK: Drawing

    private func render() {
      buffer.clear()
      scene.render(into: &buffer)
      pixelLayer.contents = buffer.makeImage()
    }

    /// The buffer drawn at whole points per pixel, centred on the stage and snapped to whole points,
    /// with the stars behind it at the same scale.
    private func placePixelLayer() {
      let ppp = CGFloat(settings.size.pointsPerPixel)
      let w = CGFloat(buffer.width) * ppp, h = CGFloat(buffer.height) * ppp
      let frame = CGRect(
        x: ((bounds.width - w) / 2).rounded(.down), y: ((bounds.height - h) / 2).rounded(.down), width: w, height: h)
      pixelLayer.frame = frame
      starLayer.frame = frame
      if starSize != (buffer.width, buffer.height) {
        starSize = (buffer.width, buffer.height)
        starLayer.contents = Self.stars(width: buffer.width, height: buffer.height).makeImage()
      }
    }

    /// About one dim star per 160 pixels, a few of them a little brighter; the same sky every time.
    private static func stars(width: Int, height: Int) -> PixelBuffer {
      var sky = PixelBuffer(width: width, height: height)
      var random = SeededRandom(seed: 7)
      for _ in 0..<(width * height / 160) {
        let x = Int(random.next() * Double(width)), y = Int(random.next() * Double(height))
        sky.fill(x: x, y: y, w: 1, h: 1, random.next() < 0.2 ? 0x4A4A6AFF : 0x2C2C42FF)
      }
      return sky
    }

    private static func buffer(for size: CGSize, _ settings: BlipSettings) -> PixelBuffer {
      let ppp = CGFloat(settings.size.pointsPerPixel)
      return PixelBuffer(width: Int(size.width / ppp), height: Int(size.height / ppp))
    }

    /// A new scene at the start of its fly-in, or with `hovering` already past it.
    private static func scene(_ settings: BlipSettings, buffer: PixelBuffer, seed: UInt64, hovering: Bool)
      -> BlipCore.Scene
    {
      var scene = BlipCore.Scene(settings: settings, bufferWidth: buffer.width, bufferHeight: buffer.height, seed: seed)
      if hovering { for _ in 0..<SummonController.settleTicks { scene.tick() } }
      return scene
    }
  }
}
