import AppKit
import BlipCore
import Carbon.HIToolbox
import SwiftUI

/// Records the global shortcut: click it, then press a combination with Command, Option or Control
/// (Shift may join them). Escape alone cancels, as does clicking elsewhere.
struct HotKeyRecorder: NSViewRepresentable {
  @Binding var hotKey: HotKey
  /// Recording started (`true`) or ended (`false`). The global shortcut should be off while
  /// recording, so pressing the current one records it instead of summoning.
  var onRecordingChanged: (Bool) -> Void = { _ in }

  func makeNSView(context: Context) -> RecorderButton {
    let button = RecorderButton()
    button.onRecord = { hotKey = $0 }
    button.onRecordingChanged = onRecordingChanged
    button.hotKey = hotKey
    return button
  }

  func updateNSView(_ button: RecorderButton, context: Context) {
    button.onRecord = { hotKey = $0 }
    button.onRecordingChanged = onRecordingChanged
    button.hotKey = hotKey
  }

  /// A push button that shows the shortcut and becomes the recorder when clicked.
  final class RecorderButton: NSButton {
    var onRecord: ((HotKey) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var hotKey = HotKey.commandEscape { didSet { updateTitle() } }

    private var recording = false {
      didSet {
        guard recording != oldValue else { return }
        recording ? watchForLeaving() : stopWatching()
        updateTitle()
        onRecordingChanged?(recording)
      }
    }
    /// While recording: observers that cancel it when the owner moves on.
    private var leaveObservers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
      super.init(frame: .zero)
      bezelStyle = .push
      setButtonType(.momentaryPushIn)
      target = self
      action = #selector(clicked)
      setAccessibilityLabel("Shortcut")
      updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
      for (center, observer) in leaveObservers { center.removeObserver(observer) }
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
      recording = false
      return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil { recording = false }
    }

    @objc private func clicked() {
      if recording {
        recording = false
      } else if window?.makeFirstResponder(self) == true {
        recording = true
      }
    }

    // Combinations with Command arrive here, before `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      guard recording, window?.firstResponder === self, event.type == .keyDown else {
        return super.performKeyEquivalent(with: event)
      }
      record(event)
      return true
    }

    override func keyDown(with event: NSEvent) {
      guard recording else { return super.keyDown(with: event) }
      record(event)
    }

    private func record(_ event: NSEvent) {
      let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
      if flags.isEmpty && Int(event.keyCode) == kVK_Escape {
        recording = false
        return
      }
      guard !flags.intersection([.command, .option, .control]).isEmpty else {
        NSSound.beep()
        return
      }
      let recorded = HotKey(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(flags))
      recording = false
      hotKey = recorded
      onRecord?(recorded)
    }

    /// The shortcut is off while recording, so recording must end when the owner turns to anything
    /// else: the window stops being key, Blip stops being active, or another app comes forward (which
    /// covers a Settings window that was never key because macOS declined to activate Blip).
    private func watchForLeaving() {
      stopWatching()
      let cancel: @Sendable (Notification) -> Void = { [weak self] _ in
        MainActor.assumeIsolated { self?.recording = false }
      }
      let local = NotificationCenter.default
      leaveObservers.append(
        (local, local.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main,
                                  using: cancel)))
      leaveObservers.append(
        (local, local.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                  queue: .main, using: cancel)))
      let workspace = NSWorkspace.shared.notificationCenter
      leaveObservers.append(
        (workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                          queue: .main) { [weak self] note in
          let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
          guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
          MainActor.assumeIsolated { self?.recording = false }
        }))
    }

    private func stopWatching() {
      for (center, observer) in leaveObservers { center.removeObserver(observer) }
      leaveObservers = []
    }

    private func updateTitle() {
      title = recording ? "Press a shortcut…" : HotKeyRecorder.describe(hotKey)
      setAccessibilityValue(title)
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
      var m = 0
      if flags.contains(.command) { m |= cmdKey }
      if flags.contains(.shift) { m |= shiftKey }
      if flags.contains(.option) { m |= optionKey }
      if flags.contains(.control) { m |= controlKey }
      return UInt32(m)
    }
  }

  // MARK: Describing a shortcut

  /// The shortcut as the menus write it, for example "⌃⌥B" or "⌘⎋".
  static func describe(_ hotKey: HotKey) -> String {
    let m = Int(hotKey.modifiers)
    var text = ""
    if m & controlKey != 0 { text += "⌃" }
    if m & optionKey != 0 { text += "⌥" }
    if m & shiftKey != 0 { text += "⇧" }
    if m & cmdKey != 0 { text += "⌘" }
    return text + keyName(Int(hotKey.keyCode))
  }

  private static let namedKeys: [Int: String] = [
    kVK_Escape: "⎋", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
    kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
    kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
    kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
  ]

  /// The key's name: a symbol for special keys, otherwise what it types on the current layout.
  private static func keyName(_ keyCode: Int) -> String {
    if let name = namedKeys[keyCode] { return name }
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return "Key \(keyCode)" }
    let layout = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
    var deadKeys: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var length = 0
    let status = layout.withUnsafeBytes { raw -> OSStatus in
      guard let base = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
      return UCKeyTranslate(
        base, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
    }
    guard status == noErr, length > 0 else { return "Key \(keyCode)" }
    return String(utf16CodeUnits: chars, count: length).uppercased()
  }
}
