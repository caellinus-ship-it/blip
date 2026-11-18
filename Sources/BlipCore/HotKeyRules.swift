/// Why a combination can't be the global shortcut.
public enum HotKeyProblem: Equatable {
  /// Without Command or Control it would take over ordinary typing.
  case needsCommandOrControl
  /// Everyday editing and system shortcuts (copy, paste, undo, quit, close, app switching, Spotlight).
  case reserved
}

/// Which combinations may be the global shortcut, by Carbon key code and modifier mask.
public enum HotKeyRules {
  private static let command: UInt32 = 256, shift: UInt32 = 512, option: UInt32 = 2048, control: UInt32 = 4096

  /// With Command alone: A, Z, X, C, V, Q, W, Tab and Space.
  private static let reservedWithCommand: Set<UInt32> = [0, 6, 7, 8, 9, 12, 13, 48, 49]
  /// Z, with Command and Shift (redo).
  private static let redo: UInt32 = 6

  /// `nil` when the combination is allowed.
  public static func problem(for hotKey: HotKey) -> HotKeyProblem? {
    let m = hotKey.modifiers & (command | shift | option | control)
    if m & (command | control) == 0 { return .needsCommandOrControl }
    if m == command && reservedWithCommand.contains(hotKey.keyCode) { return .reserved }
    if m == command | shift && hotKey.keyCode == redo { return .reserved }
    return nil
  }
}
