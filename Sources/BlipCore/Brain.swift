import Foundation

/// Finds the `claude` executable: the owner's own path first, then the usual install places.
public enum ClaudeLocator {
  public static func find(custom: String?, home: String, exists: (String) -> Bool) -> String? {
    var candidates: [String] = []
    if let custom, !custom.isEmpty { candidates.append(custom) }
    candidates += [
      "\(home)/.local/bin/claude",
      "/opt/homebrew/bin/claude",
      "/usr/local/bin/claude",
      "\(home)/.claude/local/claude",
    ]
    return candidates.first(where: exists)
  }
}

/// The command-line arguments for the hidden session.
public enum BrainCommand {
  public static func arguments(model: BrainModel, systemPrompt: String) -> [String] {
    [
      "-p", "--model", model.alias, "--safe-mode", "--strict-mcp-config", "--tools", "",
      "--no-session-persistence", "--system-prompt", systemPrompt, "--input-format", "stream-json",
      "--output-format", "stream-json", "--verbose", "--include-partial-messages",
    ]
  }
}

/// The system prompt, built from the owner's settings.
public enum PromptBuilder {
  public static func systemPrompt(_ settings: BlipSettings) -> String {
    "You are \(settings.displayName), a tiny pixel creature who flies a spaceship on the user's Mac and answers "
      + "questions about what is on their screen. Each message comes with a screenshot of their screen taken "
      + "the moment they asked, and a numbered list of their open windows. "
      + "\(personality(settings.personality)) \(length(settings.answers)) "
      + "Reply in plain text only: no markdown, no bullet symbols, no headings. If you cannot read something "
      + "because one window is too small or blurry in the screenshot, or the question is about one specific "
      + "window in the list, reply with exactly LOOK:<number> using "
      + "that window's number from the list, and nothing else; you will then get a close-up of that window. "
      + "Only do this when you truly need it, and never more than once per question. You can only look and "
      + "answer; you cannot click, type, or change anything."
  }

  private static func personality(_ p: Personality) -> String {
    switch p {
    case .playful: return "Be playful, warm and a little cheeky, but never at the cost of a clear answer."
    case .plain: return "Be plain, direct and helpful."
    case .custom(let text):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? personality(.playful) : "Personality: " + trimmed
    }
  }

  private static func length(_ a: AnswerLength) -> String {
    switch a {
    case .short: return "Keep answers to one to three short sentences."
    case .detailed: return "Give a complete answer with the steps or reasons that matter, in short paragraphs."
    }
  }
}

/// One on-screen window, as offered to the assistant in the numbered list.
public struct WindowInfo: Equatable {
  public let id: UInt32
  public let app: String
  public let title: String

  public init(id: UInt32, app: String, title: String) {
    self.id = id
    self.app = app
    self.title = title
  }
}

/// The numbered window list: at most 20 lines, `N. App — Title` or `N. App`.
public enum WindowList {
  public static let limit = 20

  public static func text(_ windows: [WindowInfo]) -> String {
    windows.prefix(limit).enumerated().map { i, w in
      let showTitle = !w.title.isEmpty && w.title != w.app
      return showTitle ? "\(i + 1). \(w.app) — \(w.title)" : "\(i + 1). \(w.app)"
    }.joined(separator: "\n")
  }
}

/// One stream-json input line carrying a question, its screenshots and the window list.
public enum UserMessage {
  public static func line(text: String, jpegs: [Data], windows: [WindowInfo]) -> String {
    var body = text
    if !windows.isEmpty { body += "\n\nOpen windows:\n" + WindowList.text(windows) }
    let content = jpegs.map { Block.image(base64: $0.base64EncodedString()) } + [Block.text(body)]
    let envelope = Envelope(message: Message(content: content))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    // Encoding plain strings and arrays cannot fail; JSON escapes every newline inside strings.
    let data = (try? encoder.encode(envelope)) ?? Data()
    return String(decoding: data, as: UTF8.self)
  }

  private struct Envelope: Encodable {
    let type = "user"
    let message: Message
  }

  private struct Message: Encodable {
    let role = "user"
    let content: [Block]
  }

  private enum Block: Encodable {
    case image(base64: String)
    case text(String)

    private enum Keys: String, CodingKey { case type, source, text }
    private enum SourceKeys: String, CodingKey { case type, media_type, data }

    func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: Keys.self)
      switch self {
      case .image(let base64):
        try c.encode("image", forKey: .type)
        var s = c.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
        try s.encode("base64", forKey: .type)
        try s.encode("image/jpeg", forKey: .media_type)
        try s.encode(base64, forKey: .data)
      case .text(let text):
        try c.encode("text", forKey: .type)
        try c.encode(text, forKey: .text)
      }
    }
  }
}

/// Splits a byte stream into lines; keeps the unfinished tail for the next chunk.
public struct LineBuffer {
  private var pending = Data()

  public init() {}

  public mutating func append(_ chunk: Data) -> [String] {
    pending.append(chunk)
    var lines: [String] = []
    // Split on bytes, not characters, so a UTF-8 sequence cut across chunks stays whole.
    while let newline = pending.firstIndex(of: 0x0A) {
      let line = pending[pending.startIndex..<newline]
      pending = Data(pending[pending.index(after: newline)...])
      if !line.isEmpty { lines.append(String(decoding: line, as: UTF8.self)) }
    }
    return lines
  }
}

/// What one line of the session's output means to the app.
public enum BrainEvent: Equatable {
  case ready(model: String)
  case textDelta(String)
  case messageDone
  case result(text: String, isError: Bool)
  case other
}

/// Reads one stream-json output line. Anything unrecognised or malformed is `.other`.
public enum StreamParser {
  public static func parse(line: String) -> BrainEvent {
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = obj["type"] as? String
    else { return .other }

    switch type {
    case "system":
      if obj["subtype"] as? String == "init", let model = obj["model"] as? String { return .ready(model: model) }
    case "stream_event":
      guard let event = obj["event"] as? [String: Any], let eventType = event["type"] as? String else { break }
      if eventType == "message_stop" { return .messageDone }
      if eventType == "content_block_delta", let delta = event["delta"] as? [String: Any],
         delta["type"] as? String == "text_delta", let text = delta["text"] as? String {
        return .textDelta(text)
      }
    case "result":
      // A result always ends the turn, so it is reported even when its text is missing.
      return .result(text: obj["result"] as? String ?? "", isError: obj["is_error"] as? Bool ?? false)
    default:
      break
    }
    return .other
  }
}

/// Holds back a reply while it could still be the `LOOK:<number>` marker, then decides what it was.
public struct ReplyGate {
  public enum Outcome: Equatable {
    case text(String)
    case look(Int)
    case unusableMarker
  }

  private let windowCount: Int
  private let allowLook: Bool
  private var held = ""
  private var holding = true

  public init(windowCount: Int, allowLook: Bool) {
    self.windowCount = windowCount
    self.allowLook = allowLook
  }

  /// Returns the text that is safe to show now (possibly empty).
  public mutating func feed(_ delta: String) -> String {
    guard holding else { return delta }
    held += delta
    if Self.couldBeMarker(held) { return "" }
    holding = false
    defer { held = "" }
    return held
  }

  /// Ends the reply: the marker if the whole reply was one, otherwise the text still held.
  public mutating func finish() -> Outcome {
    defer { held = "" }
    guard holding else { return .text(held) }
    let whole = held.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let match = whole.wholeMatch(of: #/LOOK:(\d+)/#) else { return .text(held) }
    let n = Int(match.1) ?? 0  // too many digits is still the marker, just not a usable one
    return allowLook && n >= 1 && n <= windowCount ? .look(n) : .unusableMarker
  }

  /// Whether the text so far, ignoring leading whitespace, could still grow into the marker.
  /// Whitespace alone is held too, since a marker may arrive after it in a later delta.
  private static func couldBeMarker(_ text: String) -> Bool {
    let start = String(text.drop(while: \.isWhitespace))
    return start.wholeMatch(of: #/(?:L|LO|LOO|LOOK|LOOK:\d*\s*)?/#) != nil
  }
}
