import Testing
@testable import BlipCore

@Suite struct HotKeyRulesTests {
  @Test func rules() {
    #expect(HotKeyRules.problem(for: .commandEscape) == nil)
    #expect(HotKeyRules.problem(for: HotKey(keyCode: 11, modifiers: 4096 + 2048)) == nil)        // ctrl+opt+B
    #expect(HotKeyRules.problem(for: HotKey(keyCode: 11, modifiers: 2048)) == .needsCommandOrControl)
    #expect(HotKeyRules.problem(for: HotKey(keyCode: 11, modifiers: 512)) == .needsCommandOrControl)
    for code: UInt32 in [0, 6, 7, 8, 9, 12, 13, 48, 49] {
      #expect(HotKeyRules.problem(for: HotKey(keyCode: code, modifiers: 256)) == .reserved)
    }
    #expect(HotKeyRules.problem(for: HotKey(keyCode: 6, modifiers: 256 + 512)) == .reserved)
    #expect(HotKeyRules.problem(for: HotKey(keyCode: 8, modifiers: 256 + 2048)) == nil)          // cmd+opt+C
  }
}
