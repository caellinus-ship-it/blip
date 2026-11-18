import Foundation
import Testing
@testable import BlipCore

@Suite struct ChatTests {
  @Test func imageSizingFits() {
    #expect(ImageSizing.fit(width: 5120, height: 2880, maxLongEdge: 1568) == (1568, 882))
    #expect(ImageSizing.fit(width: 1000, height: 3000, maxLongEdge: 1568) == (523, 1568))
    #expect(ImageSizing.fit(width: 800, height: 600, maxLongEdge: 1568) == (800, 600))
    #expect(ImageSizing.fit(width: 10000, height: 1, maxLongEdge: 100) == (100, 1))
  }

  // `submit` is mutating, and `#expect` cannot call a mutating method inside its expression,
  // so each result is taken first.
  @Test func chatLogRejectsEmptyAndDoubleSends() {
    var log = ChatLog()
    let empty = log.submit("   \n"); #expect(!empty); #expect(log.messages.isEmpty)
    let first = log.submit(" hi "); #expect(first); #expect(log.messages.last?.text == "hi"); #expect(log.waiting)
    let again = log.submit("again"); #expect(!again); #expect(log.messages.count == 1)
  }
  @Test func chatLogStreamsAndFinishes() {
    var log = ChatLog(); _ = log.submit("hi")
    log.append(delta: ""); #expect(log.messages.count == 1)
    log.append(delta: "Hel"); log.append(delta: "lo")
    #expect(log.messages.last?.role == .assistant && log.messages.last?.text == "Hello")
    log.finish(); #expect(!log.waiting); let next = log.submit("next"); #expect(next)
    log.fail(.timeout); #expect(log.messages.last?.role == .problem); #expect(!log.waiting)
    #expect(log.messages.last?.text == "That took too long. Try asking again.")
  }
  @Test func typingDotsShowUntilTheFirstWords() {
    var log = ChatLog()
    #expect(!log.awaitingFirstText)
    _ = log.submit("hi"); #expect(log.awaitingFirstText)
    log.append(delta: "Hi"); #expect(!log.awaitingFirstText)
    log.finish(); _ = log.submit("again"); #expect(log.awaitingFirstText)
    log.fail(.timeout); #expect(!log.awaitingFirstText)
  }
  @Test func problemsClassify() {
    #expect(BlipProblem.classify(resultText: "Failed to authenticate: OAuth session expired") == .notLoggedIn)
    #expect(BlipProblem.classify(resultText: "Usage limit reached") == .usageLimit)
    #expect(BlipProblem.classify(resultText: "boom") == .other("boom"))
    #expect(BlipProblem.other("boom").bubbleText == "Something went wrong: boom")
  }
  @Test func chatLayoutFlipsAndClamps() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800), panel = CGSize(width: 340, height: 420)
    #expect(ChatLayout.frame(anchor: CGPoint(x: 500, y: 400), shipHalfWidth: 36, panel: panel, screen: screen)
            == CGRect(x: 552, y: 190, width: 340, height: 420))
    #expect(ChatLayout.frame(anchor: CGPoint(x: 900, y: 400), shipHalfWidth: 36, panel: panel, screen: screen).maxX == 848)
    #expect(ChatLayout.frame(anchor: CGPoint(x: 500, y: 790), shipHalfWidth: 36, panel: panel, screen: screen).maxY == 788)
    #expect(ChatLayout.frame(anchor: CGPoint(x: 500, y: 5), shipHalfWidth: 36, panel: panel, screen: screen).minY == 12)
  }
}
