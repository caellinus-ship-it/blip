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
  @Test func releasingADragOnAnotherDisplayMovesAHoveringShipThere() {
    #expect(SummonState.movesOnDragEnd(phase: .hover, shipDisplay: 1, pointerDisplay: 2))
    #expect(!SummonState.movesOnDragEnd(phase: .hover, shipDisplay: 1, pointerDisplay: 1))
    #expect(!SummonState.movesOnDragEnd(phase: .hover, shipDisplay: 1, pointerDisplay: nil))
    // A shortcut pressed mid-drag sent it off; letting go must not bring it back.
    #expect(!SummonState.movesOnDragEnd(phase: .flyOut, shipDisplay: 1, pointerDisplay: 2))
    #expect(!SummonState.movesOnDragEnd(phase: .gone, shipDisplay: 1, pointerDisplay: 2))
  }
  @Test func aSummonEndsWhenItsDisplayGoesAway() {
    #expect(SummonState.endsOnDisplayChange(shipDisplay: 2, displays: [1]))
    #expect(SummonState.endsOnDisplayChange(shipDisplay: 2, displays: []))
    #expect(!SummonState.endsOnDisplayChange(shipDisplay: 2, displays: [1, 2]))
    #expect(!SummonState.endsOnDisplayChange(shipDisplay: 1, displays: [1]))
  }
}
