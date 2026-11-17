import BlipCore
import Carbon.HIToolbox
import Foundation

/// One system-wide shortcut, registered with Carbon. `handler` runs on the main thread.
final class HotKeyCenter {
  /// 'Blip', tagging our hot key so other hot-key events are left alone.
  private static let signature: OSType = 0x426C_6970
  private static let hotKeyID: UInt32 = 1

  private let handler: () -> Void
  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?

  init(hotKey: HotKey, handler: @escaping () -> Void) {
    self.handler = handler
    var pressed = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        let read = GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard read == noErr, id.signature == HotKeyCenter.signature, id.id == HotKeyCenter.hotKeyID
        else { return OSStatus(eventNotHandledErr) }
        Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().handler()
        return noErr
      }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    if status != noErr { NSLog("Blip: InstallEventHandler failed (\(status))") }
    register(hotKey)
  }

  deinit {
    unregister()
    if let handlerRef { RemoveEventHandler(handlerRef) }
  }

  /// Replaces the shortcut.
  func update(_ hotKey: HotKey) {
    unregister()
    register(hotKey)
  }

  private func register(_ hotKey: HotKey) {
    let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
    let status = RegisterEventHotKey(
      hotKey.keyCode, hotKey.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    if status != noErr {
      NSLog("Blip: RegisterEventHotKey(\(hotKey.keyCode), \(hotKey.modifiers)) failed (\(status))")
      hotKeyRef = nil
    }
  }

  private func unregister() {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    hotKeyRef = nil
  }
}
