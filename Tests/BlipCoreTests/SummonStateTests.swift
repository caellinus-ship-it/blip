import Testing
@testable import BlipCore

@Suite struct SummonStateTests {
  @Test func summonStateMachine() {
    #expect(SummonState.onShortcut(phase: nil) == .start)
    #expect(SummonState.onShortcut(phase: .gone) == .start)
    #expect(SummonState.onShortcut(phase: .flyIn) == .dismiss)
    #expect(SummonState.onShortcut(phase: .hover) == .dismiss)
    #expect(SummonState.onShortcut(phase: .flyOut) == .restart)
  }
}
