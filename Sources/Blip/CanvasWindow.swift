import AppKit
import BlipCore

/// A transparent, click-through window covering one screen that shows a
/// `PixelBuffer`, one arcade pixel per `pointsPerPixel` x `pointsPerPixel` points.
///
/// Arcade pixels have a top-left origin; the window has AppKit's bottom-left
/// origin. The buffer's top-left pixel sits at the window's top-left corner;
/// the buffer is rounded up, so its last column and row may hang off the
/// right and bottom edges.
final class CanvasWindow: NSWindow {
  private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  private static let bitmapInfo = CGBitmapInfo(
    rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)

  let pointsPerPixel: Int
  /// Scratch buffer sized to cover the screen.
  var buffer: PixelBuffer
  /// Called with whole-pixel deltas while the ship is dragged; `dy` grows downward.
  var onDrag: ((_ dx: Int, _ dy: Int) -> Void)?
  /// Where the window takes mouse events, in window points; elsewhere clicks pass through.
  var hitRect: CGRect? { didSet { updateMouseAcceptance() } }
  private(set) var isDragging = false

  private let pixelLayer = CALayer()
  private var dragStart = NSPoint.zero
  private var reported = (x: 0, y: 0)

  init(screen: NSScreen, pointsPerPixel: Int) {
    let ppp = max(1, pointsPerPixel)
    self.pointsPerPixel = ppp
    let size = screen.frame.size
    buffer = PixelBuffer(
      width: Int((size.width / CGFloat(ppp)).rounded(.up)),
      height: Int((size.height / CGFloat(ppp)).rounded(.up)))
    super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    setFrame(screen.frame, display: false)
    isReleasedWhenClosed = false
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

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

  /// Shows `b` (premultiplied RGBA, 8 bits per channel).
  func present(_ b: PixelBuffer) {
    let data = b.pixels.withUnsafeBytes { Data($0) } as CFData
    guard let provider = CGDataProvider(data: data),
      let image = CGImage(
        width: b.width, height: b.height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: b.width * 4, space: Self.colorSpace, bitmapInfo: Self.bitmapInfo,
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return }
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
    dragStart = NSEvent.mouseLocation
    reported = (0, 0)
  }

  override func mouseDragged(with event: NSEvent) {
    guard isDragging else { return }
    let m = NSEvent.mouseLocation, p = CGFloat(pointsPerPixel)
    // Screen y grows upward, arcade y downward.
    let total = (x: Int((m.x - dragStart.x) / p), y: Int((dragStart.y - m.y) / p))
    let dx = total.x - reported.x, dy = total.y - reported.y
    guard dx != 0 || dy != 0 else { return }
    reported = total
    onDrag?(dx, dy)
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
    updateMouseAcceptance()
  }
}

/// The window's content view: takes the first click so a drag starts without
/// first activating Blip.
private final class CanvasView: NSView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
