import Foundation

/// Picks the pixel size a screenshot is sent at.
public enum ImageSizing {
  /// Scales down so the long edge is at most `maxLongEdge`, keeping the aspect ratio
  /// (short edge rounded to nearest). Never scales up and never returns a zero edge.
  public static func fit(width: Int, height: Int, maxLongEdge: Int) -> (width: Int, height: Int) {
    let width = max(1, width), height = max(1, height), maxLongEdge = max(1, maxLongEdge)
    let longEdge = max(width, height)
    guard longEdge > maxLongEdge else { return (width, height) }
    let scale = Double(maxLongEdge) / Double(longEdge)
    func scaled(_ edge: Int) -> Int {
      edge == longEdge ? maxLongEdge : max(1, Int((Double(edge) * scale).rounded()))
    }
    return (scaled(width), scaled(height))
  }
}
