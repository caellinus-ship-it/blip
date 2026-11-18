import AppKit
import BlipCore
import Combine
import SwiftUI

/// Owns the settings window. The window is built when it is shown and thrown away when it closes,
/// which also stops the stage.
@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
  private let store: SettingsStore
  private let shortcut: ShortcutHooks
  private var window: NSWindow?
  private var titleWatch: AnyCancellable?

  init(store: SettingsStore, shortcut: ShortcutHooks) {
    self.store = store
    self.shortcut = shortcut
  }

  func show() {
    let window = self.window ?? makeWindow()
    self.window = window
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()  // in front even when macOS declines the activation
  }

  private func makeWindow() -> NSWindow {
    let window = SettingsWindow(
      contentRect: NSRect(origin: .zero, size: SettingsView.size),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = NSColor(SettingsTheme.background)
    window.titlebarAppearsTransparent = true
    window.contentView = NSHostingView(rootView: SettingsView(store: store, shortcut: shortcut))
    window.delegate = self
    window.center()
    titleWatch = store.$settings.map(\.displayName).removeDuplicates().sink { [weak window] name in
      window?.title = "\(name) Settings"
    }
    return window
  }

  func windowWillClose(_ notification: Notification) {
    titleWatch = nil
    if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.close() }  // opened by a color well here
    window?.delegate = nil
    window?.contentView = nil  // takes the stage out of the window, which stops its display link
    window = nil
  }
}

/// What the shortcut recorder needs from the app.
struct ShortcutHooks {
  /// Recording started (`true`) or ended (`false`); the global shortcut is off while recording.
  var recordingChanged: (Bool) -> Void = { _ in }
  /// Makes this the global shortcut; false when macOS refuses it because it is already taken.
  var register: (HotKey) -> Bool = { _ in true }
}

/// A normal window that also handles the editing shortcuts and Command-W, as Blip has no menu bar
/// of its own to provide them.
private final class SettingsWindow: NSWindow {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
    // The views go first, so the shortcut recorder can record any of these.
    if super.performKeyEquivalent(with: event) { return true }
    if event.type == .keyDown, modifiers == .command, key == "w" {
      performClose(nil)
      return true
    }
    if event.type == .keyDown, modifiers == .command || modifiers == [.command, .shift],
       let action = ChatPanel.editAction(key: key, shift: modifiers.contains(.shift)),
       NSApp.sendAction(action, to: nil, from: self) {
      return true
    }
    return false
  }
}
