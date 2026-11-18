import AppKit
import BlipCore

/// A transparent, click-through window covering one screen that shows a
/// `PixelBuffer`, one arcade pixel per `pointsPerPixel` x `pointsPerPixel` points.
///
/// Arcade pixels have a top-left origin; the window has AppKit's bottom-left
/// origin. The buffer's top-left pixel sits at the window's top-left corner;
/// the buffer is rounded up, so its last column and row may hang off the
/// right and bottom edges.
final class CanvasWindow: NSPanel {
  let pointsPerPixel: Int
  /// Scratch buffer sized to cover the screen.
  var buffer: PixelBuffer
  /// Called while the ship is dragged with the hover anchor the pointer asks for: the pointer's arcade
  /// pixel minus where on the ship it was grabbed. It can lie outside the buffer; the scene stops the
  /// ship at the edge.
  var onDrag: ((_ anchor: (x: Int, y: Int)) -> Void)?
  /// Called when a drag ends, with the pointer in screen coordinates and the grab offset in arcade pixels.
  var onDragEnded: ((_ pointer: CGPoint, _ grab: (x: Int, y: Int)) -> Void)?
  /// The ship's hover anchor in arcade pixels; the controller keeps it current.
  var anchor = (x: 0, y: 0)
  /// Where the window takes mouse events, in window points; elsewhere clicks pass through.
  var hitRect: CGRect? { didSet { updateMouseAcceptance() } }
  private(set) var isDragging = false

  private let pixelLayer = CALayer()
  /// The pointer's arcade pixel minus the anchor, when the drag began.
  private var grab = (x: 0, y: 0)
  /// The anchor last asked for.
  private var requested = (x: 0, y: 0)

  init(screen: NSScreen, pointsPerPixel: Int) {
    let ppp = max(1, pointsPerPixel)
    self.pointsPerPixel = ppp
    let size = screen.frame.size
    buffer = PixelBuffer(
      width: Int((size.width / CGFloat(ppp)).rounded(.up)),
      height: Int((size.height / CGFloat(ppp)).rounded(.up)))
    // A non-activating panel: clicking or dragging the ship never activates Blip
    // or takes key status from the app in front.
    super.init(
      contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    setFrame(screen.frame, display: false)
    isReleasedWhenClosed = false
    // Panels default to hiding when their app deactivates; the controller would
    // not notice and would keep "hovering" an invisible ship.
    hidesOnDeactivate = false
    animationBehavior = .none
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    // Same color space as the frames, so Core Animation does not color-match every frame on the CPU.
    colorSpace = .sRGB
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    ignoresMouseEvents = true

    let view = CanvasView(frame: NSRect(origin: .zero, size: size))
    view.wantsLayer = true
    view.layer?.magnificationFilter = .nearest
    let drawnHeight = CGFloat(buffer.height * ppp)
    pixelLayer.frame = CGRect(
      x: 0, y: size.height - drawnHeight, width: CGFloat(buffer.width * ppp), height: drawnHeight)
    pixelLayer.magnificationFilter = .nearest
    pixelLayer.actions = ["contents": NSNull()]  // no cross-fade between frames
    view.layer?.addSublayer(pixelLayer)
    contentView = view
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

  /// Shows `b`.
  func present(_ b: PixelBuffer) {
    guard let image = b.makeImage() else { return }
    pixelLayer.contents = image
  }

  // MARK: Coordinates

  /// An arcade-pixel rectangle as a window rectangle in points.
  func windowRect(arcade r: (x: Int, y: Int, w: Int, h: Int)) -> CGRect {
    let p = CGFloat(pointsPerPixel)
    return CGRect(
      x: CGFloat(r.x) * p, y: frame.height - CGFloat(r.y + r.h) * p,
      width: CGFloat(r.w) * p, height: CGFloat(r.h) * p)
  }

  /// The centre of arcade pixel `(x, y)` in screen coordinates.
  func screenPoint(arcadeX x: Int, y: Int) -> CGPoint {
    let p = CGFloat(pointsPerPixel)
    return CGPoint(x: frame.minX + (CGFloat(x) + 0.5) * p, y: frame.maxY - (CGFloat(y) + 0.5) * p)
  }

  /// The arcade pixel under a screen point.
  func arcadePixel(atScreenPoint s: CGPoint) -> (x: Int, y: Int) {
    let p = CGFloat(pointsPerPixel)
    return (Int(((s.x - frame.minX) / p).rounded(.down)), Int(((frame.maxY - s.y) / p).rounded(.down)))
  }

  // MARK: Mouse

  /// Accepts mouse events only while the pointer is over `hitRect` (or a drag is under way).
  func updateMouseAcceptance() {
    let accept: Bool
    if isDragging {
      accept = true
    } else if let hitRect {
      let m = NSEvent.mouseLocation
      accept = hitRect.contains(CGPoint(x: m.x - frame.minX, y: m.y - frame.minY))
    } else {
      accept = false
    }
    if ignoresMouseEvents == accept { ignoresMouseEvents = !accept }
  }

  override func mouseDown(with event: NSEvent) {
    guard let hitRect, hitRect.contains(event.locationInWindow) else { return }
    isDragging = true
    let p = arcadePixel(atScreenPoint: NSEvent.mouseLocation)
    grab = (p.x - anchor.x, p.y - anchor.y)
    requested = anchor
  }

  override func mouseDragged(with event: NSEvent) {
    guard isDragging else { return }
    let p = arcadePixel(atScreenPoint: NSEvent.mouseLocation)
    let target = (x: p.x - grab.x, y: p.y - grab.y)
    guard target != requested else { return }
    requested = target
    onDrag?(target)
  }

  override func mouseUp(with event: NSEvent) {
    let wasDragging = isDragging
    isDragging = false
    updateMouseAcceptance()
    if wasDragging { onDragEnded?(NSEvent.mouseLocation, grab) }
  }
}

/// The window's content view: takes the first click so a drag starts without
/// first activating Blip.
private final class CanvasView: NSView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension PixelBuffer {
  private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  private static let bitmapInfo = CGBitmapInfo(
    rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)

  /// The buffer as an sRGB image, one image pixel per arcade pixel (premultiplied RGBA, 8 bits per
  /// channel). Show it in a layer with `.nearest` magnification so the pixels stay crisp.
  func makeImage() -> CGImage? {
    let data = pixels.withUnsafeBytes { Data($0) } as CFData
    guard let provider = CGDataProvider(data: data) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: Self.colorSpace, bitmapInfo: Self.bitmapInfo,
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }
}
