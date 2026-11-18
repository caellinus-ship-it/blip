import AppKit
import BlipCore
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// A screenshot of one display, as JPEG, and the windows open on it.
struct Capture {
  let jpeg: Data
  /// On-screen app windows on that display, front to back, never Blip's own.
  let windows: [WindowInfo]
}

enum CaptureError: Error {
  case displayNotFound
  case windowNotFound
  case encodingFailed
}

/// Takes screenshots in memory only; nothing is ever written to disk.
enum ScreenCapturer {
  static let maxLongEdge = 1568
  static let jpegQuality = 0.85
  /// Windows smaller than this, in points, are left out of the list.
  static let minWindowSize = CGSize(width: 120, height: 80)

  static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

  /// Asks macOS for Screen Recording; the first call lists Blip in System Settings.
  static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

  /// The whole display, with Blip's own windows left out. Callers read the ID from the `NSScreen` on the
  /// main actor (`NSScreen.displayID`); this runs off it.
  static func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> Capture {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content.displays.first(where: { $0.displayID == displayID })
    else { throw CaptureError.displayNotFound }

    let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter(isBlip),
                                 exceptingWindows: [])
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                           configuration: configuration(for: filter))
    return Capture(jpeg: try jpeg(image), windows: windows(in: content, on: CGDisplayBounds(displayID)))
  }

  /// One window by itself, at its native pixel size capped at the long edge, as JPEG.
  static func captureWindow(id: UInt32) async throws -> Data {
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
    guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.windowNotFound }
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                           configuration: configuration(for: filter))
    return try jpeg(image)
  }

  /// Output at the content's native pixel size, scaled down to `maxLongEdge`.
  private static func configuration(for filter: SCContentFilter) -> SCStreamConfiguration {
    let scale = CGFloat(filter.pointPixelScale)
    let native = (width: Int((filter.contentRect.width * scale).rounded()),
                  height: Int((filter.contentRect.height * scale).rounded()))
    let size = ImageSizing.fit(width: native.width, height: native.height, maxLongEdge: maxLongEdge)
    let configuration = SCStreamConfiguration()
    configuration.width = size.width
    configuration.height = size.height
    return configuration
  }

  /// Encodes into memory; no file is involved.
  private static func jpeg(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw CaptureError.encodingFailed }
    let options = [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else { throw CaptureError.encodingFailed }
    return data as Data
  }

  /// This process, or another running copy of Blip (such as the menu-bar app while a check mode runs).
  private static func isBlip(_ app: SCRunningApplication) -> Bool {
    if app.processID == ProcessInfo.processInfo.processIdentifier { return true }
    guard let ownBundleID = Bundle.main.bundleIdentifier else { return false }
    return app.bundleIdentifier == ownBundleID
  }

  /// On-screen, layer-0 windows of other apps that are big enough and overlap the display, front to back.
  private static func windows(in content: SCShareableContent, on displayBounds: CGRect) -> [WindowInfo] {
    let candidates = content.windows.filter { window in
      guard let app = window.owningApplication, !isBlip(app) else { return false }
      return window.isOnScreen && window.windowLayer == 0
        && window.frame.width >= minWindowSize.width && window.frame.height >= minWindowSize.height
        && window.frame.intersects(displayBounds)
    }
    let order = frontToBackOrder()
    return candidates
      .enumerated()
      .sorted { (order[$0.element.windowID] ?? Int.max, $0.offset) < (order[$1.element.windowID] ?? Int.max, $1.offset) }
      .map { _, window in
        WindowInfo(id: window.windowID,
                   app: printable(window.owningApplication?.applicationName ?? ""),
                   title: printable(window.title ?? ""))
      }
  }

  /// Each on-screen window's place in the window server's front-to-back list.
  private static func frontToBackOrder() -> [CGWindowID: Int] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] ?? []
    var order: [CGWindowID: Int] = [:]
    for (index, info) in list.enumerated() {
      if let id = info[kCGWindowNumber] as? CGWindowID, order[id] == nil { order[id] = index }
    }
    return order
  }

  private static let unprintable = CharacterSet.controlCharacters.union(.newlines)

  /// App names and titles come from other apps: newlines and other control characters become spaces.
  private static func printable(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.map { unprintable.contains($0) ? " " : $0 }))
  }
}
