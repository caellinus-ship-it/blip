import AppKit
import BlipCore
import SwiftUI

/// The floating chat beside the ship. A non-activating panel that can still become key, so
/// the owner can type into it without Blip coming to the front or the app underneath losing
/// its place. It sizes itself to the chat and keeps itself beside the ship.
final class ChatPanel: NSPanel {
  static let fadeSeconds: TimeInterval = 0.25

  private var placement: (anchor: CGPoint, shipHalfWidth: CGFloat, screen: CGRect)?
  /// Where the chat draws something, in points from the panel's top-left corner; clicks elsewhere pass through.
  private var solidRects: [CGRect] = []
  /// Polls the pointer while the panel is shown, to switch click-through on and off.
  private var pointerTimer: Timer?

  init(model: ChatModel, name: String, bubbleColor: RGBA) {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: ChatView.width, height: ChatView.inputHeight),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    // Panels default to hiding when their app deactivates, and Blip is never the active app.
    hidesOnDeactivate = false
    animationBehavior = .none
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)  // just above the ship's canvas
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    let view = ChatView(
      model: model, name: name, bubbleColor: Color(rgba: bubbleColor),
      onHeightChange: { [weak self] height in self?.setContentHeight(height) },
      onSolidRectsChange: { [weak self] rects in self?.solidRects = rects })
    let host = NSHostingView(rootView: view)
    host.sizingOptions = []  // the panel follows `onHeightChange`, not the hosting view's own sizing
    contentView = host
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func becomeKey() {
    super.becomeKey()
    SummonTiming.log("chat: has the keyboard")
  }

  override func resignKey() {
    super.resignKey()
    SummonTiming.log("chat: gave up the keyboard")
  }

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

  /// Blip has no Edit menu, and is never the active app, so the usual editing shortcuts would find
  /// nothing to run them; they are sent to the text box here instead.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if event.type == .keyDown, modifiers == .command || modifiers == [.command, .shift],
       let action = Self.editAction(key: event.charactersIgnoringModifiers?.lowercased() ?? "",
                                    shift: modifiers.contains(.shift)),
       NSApp.sendAction(action, to: nil, from: self) {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  /// The editing action for a Command shortcut, also used by the settings window.
  static func editAction(key: String, shift: Bool) -> Selector? {
    switch (key, shift) {
    case ("x", false): return #selector(NSText.cut(_:))
    case ("c", false): return #selector(NSText.copy(_:))
    case ("v", false): return #selector(NSText.paste(_:))
    case ("a", false): return #selector(NSText.selectAll(_:))
    case ("z", false): return Selector(("undo:"))
    case ("z", true): return Selector(("redo:"))
    default: return nil
    }
  }

  /// Puts the panel beside the ship, whose hover anchor is at `anchor` on `screen` (screen coordinates).
  func place(anchor: CGPoint, shipHalfWidth: CGFloat, screen: NSScreen) {
    placement = (anchor, shipHalfWidth, screen.visibleFrame)
    layOut()
  }

  /// Shows the panel, still transparent and not clickable, and takes the keyboard.
  func showForTyping() {
    alphaValue = 0
    ignoresMouseEvents = true
    makeKeyAndOrderFront(nil)
  }

  func fadeIn() {
    startPointerTracking()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fadeSeconds
      animator().alphaValue = 1
    }
  }

  /// Fades out, then closes, which hands the keyboard back.
  func fadeOutAndClose() {
    pointerTimer?.invalidate()
    pointerTimer = nil
    ignoresMouseEvents = true
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fadeSeconds
      animator().alphaValue = 0
    } completionHandler: {
      // Holds the panel until it has faded, even though its conversation is already gone.
      self.orderOut(nil)
      self.close()
    }
  }

  // MARK: Click-through

  private func startPointerTracking() {
    pointerTimer?.invalidate()
    let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.updateMouseAcceptance() }
    }
    RunLoop.main.add(timer, forMode: .common)
    pointerTimer = timer
    updateMouseAcceptance()
  }

  /// Takes the mouse only over a bubble or the text box, like the ship's canvas does over the ship.
  private func updateMouseAcceptance() {
    // Leave it as it is mid-click, so a drag that wanders off a bubble is not cut short.
    guard NSEvent.pressedMouseButtons == 0 else { return }
    let m = NSEvent.mouseLocation
    let point = CGPoint(x: m.x - frame.minX, y: frame.maxY - m.y)
    let accept = solidRects.contains { $0.contains(point) }
    if ignoresMouseEvents == accept { ignoresMouseEvents = !accept }
  }

  private func setContentHeight(_ height: CGFloat) {
    guard height > 0, height != frame.height else { return }
    setContentSize(NSSize(width: ChatView.width, height: height))
    layOut()
  }

  private func layOut() {
    guard let p = placement else { return }
    let rect = ChatLayout.frame(anchor: p.anchor, shipHalfWidth: p.shipHalfWidth, panel: frame.size, screen: p.screen)
    setFrame(rect, display: true)
  }
}
