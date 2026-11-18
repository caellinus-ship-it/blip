import Testing
@testable import BlipCore

@Suite struct DictationMergeTests {
  @Test func emptyPrefixGetsNoLeadingSpace() {
    #expect(DictationMerge.text(prefix: "", dictated: "what is on my screen") == "what is on my screen")
  }
  @Test func prefixEndingInSpaceIsKeptAsIs() {
    #expect(DictationMerge.text(prefix: "hello ", dictated: "there") == "hello there")
  }
  @Test func prefixWithoutTrailingSpaceGetsOne() {
    #expect(DictationMerge.text(prefix: "hello", dictated: "there") == "hello there")
  }
  @Test func prefixEndingInOtherWhitespaceGetsNoExtraSpace() {
    #expect(DictationMerge.text(prefix: "hello\n", dictated: "there") == "hello\nthere")
    #expect(DictationMerge.text(prefix: "hello\t", dictated: "there") == "hello\tthere")
  }
  @Test func emptyDictationLeavesThePrefixUntouched() {
    #expect(DictationMerge.text(prefix: "hello", dictated: "") == "hello")
    #expect(DictationMerge.text(prefix: "hello ", dictated: "") == "hello ")
    #expect(DictationMerge.text(prefix: "", dictated: "") == "")
  }
  @Test func eachPartialReplacesTheDictatedPart() {
    let prefix = "hello "
    let partials = ["the", "there", "there you go"]
    #expect(partials.map { DictationMerge.text(prefix: prefix, dictated: $0) }
            == ["hello the", "hello there", "hello there you go"])
  }
}
