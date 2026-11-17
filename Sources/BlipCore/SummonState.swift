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
}
