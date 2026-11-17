/// A packed color, 0xRRGGBBAA. `0` is fully transparent.
public typealias RGBA = UInt32

/// A fixed-size grid of arcade pixels, row-major with the origin at the top-left.
public struct PixelBuffer {
  public let width: Int
  public let height: Int
  public private(set) var pixels: [RGBA]

  public init(width: Int, height: Int) {
    self.width = max(0, width)
    self.height = max(0, height)
    pixels = Array(repeating: 0, count: self.width * self.height)
  }

  /// Sets every pixel to transparent.
  public mutating func clear() {
    for i in pixels.indices { pixels[i] = 0 }
  }

  /// Fills the rectangle at (x, y) of size w x h, clipped to the buffer.
  public mutating func fill(x: Int, y: Int, w: Int, h: Int, _ color: RGBA) {
    let x0 = max(x, 0), y0 = max(y, 0)
    let x1 = min(x + w, width), y1 = min(y + h, height)
    guard x0 < x1, y0 < y1 else { return }
    for row in y0..<y1 {
      let start = row * width
      for col in x0..<x1 { pixels[start + col] = color }
    }
  }

  /// The pixel at (x, y), or `0` when (x, y) is outside the buffer.
  public func pixel(x: Int, y: Int) -> RGBA {
    guard x >= 0, x < width, y >= 0, y < height else { return 0 }
    return pixels[y * width + x]
  }
}
