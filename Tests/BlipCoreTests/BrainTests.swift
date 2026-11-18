import Foundation
import Testing
@testable import BlipCore

@Suite struct BrainTests {
  @Test func locatorPrefersCustomThenKnownPlaces() {
    let have: Set<String> = ["/Users/x/.local/bin/claude", "/opt/homebrew/bin/claude", "/custom/claude"]
    #expect(ClaudeLocator.find(custom: "/custom/claude", home: "/Users/x", exists: have.contains) == "/custom/claude")
    #expect(ClaudeLocator.find(custom: "/missing", home: "/Users/x", exists: have.contains) == "/Users/x/.local/bin/claude")
    #expect(ClaudeLocator.find(custom: "", home: "/Users/y", exists: have.contains) == "/opt/homebrew/bin/claude")
    #expect(ClaudeLocator.find(custom: nil, home: "/Users/y", exists: { _ in false }) == nil)
  }
  @Test func argumentsAreExact() {
    #expect(BrainCommand.arguments(model: .fastest, systemPrompt: "SP") == ["-p", "--model", "haiku", "--safe-mode",
      "--strict-mcp-config", "--tools", "", "--no-session-persistence", "--system-prompt", "SP", "--input-format",
      "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"])
    #expect(BrainCommand.arguments(model: .smarter, systemPrompt: "SP")[2] == "sonnet")
  }
  @Test func promptReflectsSettings() {
    var s = BlipSettings(); s.name = "Zap"; s.answers = .detailed; s.personality = .custom("a sleepy wizard")
    let p = PromptBuilder.systemPrompt(s)
    #expect(p.hasPrefix("You are Zap, a tiny pixel creature")); #expect(p.contains("Personality: a sleepy wizard"))
    #expect(p.contains("Give a complete answer")); #expect(p.contains("reply with exactly LOOK:<number>"))
    #expect(PromptBuilder.systemPrompt(BlipSettings()).contains("Be playful, warm and a little cheeky"))
    #expect(PromptBuilder.systemPrompt(BlipSettings()).contains("one to three short sentences"))
  }
  @Test func promptFallsBackForEmptyNameAndPersonality() {
    var s = BlipSettings(); s.name = " "; s.personality = .custom("  ")
    let p = PromptBuilder.systemPrompt(s)
    #expect(p.hasPrefix("You are Blip, a tiny pixel creature"))
    #expect(p.contains("Be playful, warm and a little cheeky")); #expect(!p.contains("Personality:"))
  }
  @Test func windowListFormatsAndTruncates() {
    let w = [WindowInfo(id: 1, app: "Safari", title: "Apple"), WindowInfo(id: 2, app: "Notes", title: ""),
             WindowInfo(id: 3, app: "Finder", title: "Finder")]
    #expect(WindowList.text(w) == "1. Safari — Apple\n2. Notes\n3. Finder")
    #expect(WindowList.text([]) == "")
    let many = (1...30).map { WindowInfo(id: UInt32($0), app: "A\($0)", title: "") }
    #expect(WindowList.text(many).split(separator: "\n").count == 20)
  }
  @Test func userMessageIsOneJSONLine() throws {
    let line = UserMessage.line(text: "what is \"this\"?\nline two", jpegs: [Data([1, 2, 3])],
                                windows: [WindowInfo(id: 1, app: "Safari", title: "Apple")])
    #expect(!line.contains("\n"))
    let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    let content = (obj["message"] as! [String: Any])["content"] as! [[String: Any]]
    #expect(obj["type"] as? String == "user"); #expect(content.count == 2)
    #expect((content[0]["source"] as! [String: Any])["data"] as? String == "AQID")
    #expect((content[0]["source"] as! [String: Any])["media_type"] as? String == "image/jpeg")
    #expect(content[1]["text"] as? String == "what is \"this\"?\nline two\n\nOpen windows:\n1. Safari — Apple")
    let bare = UserMessage.line(text: "hi", jpegs: [], windows: [])
    #expect(bare.contains(#""text":"hi""#))
  }
  @Test func lineBufferSplits() {
    var b = LineBuffer()
    #expect(b.append(Data("{\"a\":1}\n{\"b\"".utf8)) == ["{\"a\":1}"])
    #expect(b.append(Data(":2}".utf8)) == [])
    #expect(b.append(Data("\n\n{\"c\":3}\n".utf8)) == ["{\"b\":2}", "{\"c\":3}"])
  }
  @Test func parserReadsRealEventShapes() {
    #expect(StreamParser.parse(line: #"{"type":"system","subtype":"init","model":"claude-haiku-5-5","tools":[]}"#) == .ready(model: "claude-haiku-5-5"))
    #expect(StreamParser.parse(line: #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}}"#) == .textDelta("Hello"))
    #expect(StreamParser.parse(line: #"{"type":"stream_event","event":{"type":"message_stop"}}"#) == .messageDone)
    #expect(StreamParser.parse(line: #"{"type":"result","is_error":true,"result":"Failed to authenticate: OAuth session expired"}"#) == .result(text: "Failed to authenticate: OAuth session expired", isError: true))
    #expect(StreamParser.parse(line: #"{"type":"result","result":"Hi"}"#) == .result(text: "Hi", isError: false))
    #expect(StreamParser.parse(line: #"{"type":"rate_limit_event","rate_limit_info":{}}"#) == .other)
    #expect(StreamParser.parse(line: #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}"#) == .other)
  }
  @Test func parserIgnoresGarbage() {
    for l in ["", "not json", "{", "[1,2]", #"{"type":5}"#, #"{"type":"stream_event"}"#,
              #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta"}}}"#] {
      #expect(StreamParser.parse(line: l) == .other)
    }
  }
  @Test func gatePassesOrdinaryTextStraightThrough() {
    var g = ReplyGate(windowCount: 3, allowLook: true)
    #expect(g.feed("It") == "It"); #expect(g.feed("'s a bug.") == "'s a bug."); #expect(g.finish() == .text(""))
  }
  @Test func gateHoldsAndRecognisesTheMarker() {
    var g = ReplyGate(windowCount: 3, allowLook: true)
    #expect(g.feed("LO") == ""); #expect(g.feed("OK:") == ""); #expect(g.feed("2") == ""); #expect(g.finish() == .look(2))
    var h = ReplyGate(windowCount: 3, allowLook: true); _ = h.feed(" LOOK:3\n"); #expect(h.finish() == .look(3))
  }
  @Test func gateReleasesLookalikes() {
    var a = ReplyGate(windowCount: 3, allowLook: true)
    #expect(a.feed("Loo") == "Loo"); #expect(a.feed("king at it") == "king at it")
    var b = ReplyGate(windowCount: 3, allowLook: true)
    #expect(b.feed("LOOK") == ""); #expect(b.feed(": here it is") == "LOOK: here it is"); #expect(b.finish() == .text(""))
    var c = ReplyGate(windowCount: 3, allowLook: true); _ = c.feed("LOOK:99"); #expect(c.finish() == .unusableMarker)
    var d = ReplyGate(windowCount: 3, allowLook: false); _ = d.feed("LOOK:2"); #expect(d.finish() == .unusableMarker)
    var f = ReplyGate(windowCount: 3, allowLook: true); _ = f.feed("LOO"); #expect(f.finish() == .text("LOO"))
    var e = ReplyGate(windowCount: 3, allowLook: true); _ = e.feed("LOOK:2 please"); #expect(e.finish() == .text(""))
  }
  @Test func promptOffersACloseUpForAQuestionAboutOneWindow() {
    let p = PromptBuilder.systemPrompt(BlipSettings())
    #expect(p.contains("or the question is about one specific window in the list"))
    #expect(p.contains("If you cannot read something because one window is too small or blurry in the screenshot, "
      + "or the question is about one specific window in the list, reply with exactly LOOK:<number>"))
  }
  @Test func actionRulesFailClosedOnPaths() {
    let home = "/Users/x"
    func kind(_ tool: String, _ path: String?, exists: Bool = false) -> ActionKind {
      ActionRules.kind(tool: tool, input: path.map { ["file_path": $0] } ?? [:], home: home, exists: { _ in exists })
    }
    #expect(kind("Read", "/Users/x/Desktop/notes.txt") == .read)
    #expect(kind("Read", "/Users/x/Desktop/../.ssh/id_rsa") == .risky)
    #expect(kind("Read", "/Users/x/Desktopish/a.txt") == .risky)
    #expect(kind("Read", "Desktop/notes.txt") == .risky)
    #expect(kind("Read", "/Users/x/.ssh/id_rsa") == .risky)
    #expect(kind("Grep", nil) == .risky)
    #expect(kind("Write", "/Users/x/Desktop/new.txt") == .gentle)
    #expect(kind("Write", "/Users/x/Desktop/new.txt", exists: true) == .risky)
    #expect(kind("Write", "/Users/x/Desktop/../Library/LaunchAgents/a.plist") == .risky)
    #expect(kind("Write", "/Users/x/.zshrc") == .risky)
    #expect(kind("Write", "/Users/x/Documents/.hidden") == .risky)
    #expect(kind("Bash", nil) == .risky)
    #expect(ActionRules.needsAsk(.read, policy: .anyChange) == false)
    #expect(ActionRules.needsAsk(.gentle, policy: .anyChange)); #expect(!ActionRules.needsAsk(.gentle, policy: .riskyOnly))
    #expect(ActionRules.needsAsk(.risky, policy: .riskyOnly)); #expect(!ActionRules.needsAsk(.risky, policy: .never))
  }
  @Test func approvalSummaryIsNeverCutShort() {
    let long = "echo ok; " + String(repeating: "x", count: 600) + "; rm -rf ~/Documents"
    let summary = ActionRules.summary(tool: "Bash", input: ["command": long], home: "/Users/x", exists: { _ in false })
    #expect(summary.hasSuffix("rm -rf ~/Documents"))
    let mail = ActionRules.summary(
      tool: "mcp__claude_ai_Gmail__send_message",
      input: ["to": ["a@example.com"], "bcc": ["hidden@example.com"], "subject": "Hi"], home: "/Users/x", exists: { _ in false })
    #expect(mail.contains("a@example.com") && mail.contains("bcc hidden@example.com"))
    let sneaky = ActionRules.summary(tool: "Bash", input: ["command": "ls\u{1B}[2K\u{202E}"], home: "/Users/x", exists: { _ in false })
    #expect(!sneaky.unicodeScalars.contains("\u{1B}") && !sneaky.unicodeScalars.contains("\u{202E}"))
  }
}
