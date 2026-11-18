/// What the summon shortcut should do.
public enum SummonAction: Equatable { case start, dismiss, restart, none }

/// Decides what a press of the summon shortcut does, given the current scene's phase.
public enum SummonState {
  /// `phase` is `nil` when no scene exists. A scene that is flying off is thrown
  /// away and replaced by a fresh fly-in (`restart`).
  public static func onShortcut(phase: Phase?) -> SummonAction {
    switch phase {
    case nil, .gone?: return .start
    case .flyIn?, .hover?: return .dismiss
    case .flyOut?: return .restart
    }
  }

  /// Whether letting go of a drag moves the ship to the display under the pointer. Displays are
  /// `CGDirectDisplayID`s; `pointerDisplay` is `nil` when the pointer is on none. Only a ship still
  /// hovering moves: one sent off by the shortcut mid-drag stays gone.
  public static func movesOnDragEnd(phase: Phase, shipDisplay: UInt32, pointerDisplay: UInt32?) -> Bool {
    guard phase == .hover, let pointerDisplay else { return false }
    return pointerDisplay != shipDisplay
  }

  /// Whether a change to the connected displays ends the summon: its display is no longer connected.
  public static func endsOnDisplayChange(shipDisplay: UInt32, displays: [UInt32]) -> Bool {
    !displays.contains(shipDisplay)
  }
}
