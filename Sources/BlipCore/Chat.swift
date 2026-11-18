import CoreGraphics
import Foundation

/// Picks the pixel size a screenshot is sent at.
public enum ImageSizing {
  /// Scales down so the long edge is at most `maxLongEdge`, keeping the aspect ratio
  /// (short edge rounded to nearest). Never scales up and never returns a zero edge.
  public static func fit(width: Int, height: Int, maxLongEdge: Int) -> (width: Int, height: Int) {
    let width = max(1, width), height = max(1, height), maxLongEdge = max(1, maxLongEdge)
    let longEdge = max(width, height)
    guard longEdge > maxLongEdge else { return (width, height) }
    let scale = Double(maxLongEdge) / Double(longEdge)
    func scaled(_ edge: Int) -> Int {
      edge == longEdge ? maxLongEdge : max(1, Int((Double(edge) * scale).rounded()))
    }
    return (scaled(width), scaled(height))
  }
}

/// One bubble in the chat.
public struct ChatMessage: Identifiable, Equatable {
  /// `note` is a small line about something the assistant did or was not allowed to do.
  public enum Role { case user, assistant, problem, note }

  public let id: UUID
  public var role: Role
  public var text: String

  public init(role: Role, text: String) {
    id = UUID()
    self.role = role
    self.text = text
  }
}

/// Something that stopped a question from being answered, told to the owner as a friendly bubble.
public enum BlipProblem: Equatable {
  case notLoggedIn, toolMissing, noScreenPermission, noMicPermission, timeout, usageLimit
  case other(String)

  public var bubbleText: String {
    switch self {
    case .notLoggedIn: return "I can't reach my brain. Open Terminal and run: claude auth login"
    case .toolMissing: return "I can't find the claude tool. Set the path to claude in Settings."
    case .noScreenPermission:
      return "I can't see your screen yet. Turn on Screen Recording for Blip in System Settings."
    case .noMicPermission:
      return "I can't hear you yet. Turn on Microphone and Speech Recognition for Blip in System Settings."
    case .timeout: return "That took too long. Try asking again."
    case .usageLimit: return "My brain hit its usage limit. Try again later."
    case .other(let text): return "Something went wrong: " + text
    }
  }

  /// Reads the text of an error result from the hidden session.
  public static func classify(resultText: String) -> BlipProblem {
    let lower = resultText.lowercased()
    if ["authenticate", "oauth", "log in", "login"].contains(where: lower.contains) { return .notLoggedIn }
    if lower.contains("limit") { return .usageLimit }
    return .other(resultText)
  }
}

/// The conversation shown in the chat panel: one question at a time, the reply streamed in.
public struct ChatLog {
  public private(set) var messages: [ChatMessage] = []
  /// A question is out and its answer has not finished.
  public private(set) var waiting = false
  /// Where the current reply's text goes, once its first words have arrived.
  private var replyIndex: Int?
  /// Some of the current answer has been shown, in a bubble a note has since closed.
  private var hadReply = false

  public init() {}

  /// Waiting, with no words of the reply shown yet: the time for the typing dots.
  public var awaitingFirstText: Bool { waiting && replyIndex == nil && !hadReply }
  /// Waiting with nothing streaming into a bubble right now.
  public var betweenBubbles: Bool { waiting && replyIndex == nil }

  /// Adds the owner's question, trimmed. Does nothing and returns false when it is empty or
  /// a reply is still on its way.
  public mutating func submit(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !waiting else { return false }
    messages.append(ChatMessage(role: .user, text: trimmed))
    waiting = true
    replyIndex = nil
    hadReply = false
    return true
  }

  /// Adds streamed reply text; the reply's bubble appears with its first non-empty words.
  public mutating func append(delta: String) {
    guard waiting, !delta.isEmpty else { return }
    if let i = replyIndex {
      messages[i].text += delta
    } else {
      messages.append(ChatMessage(role: .assistant, text: delta))
      replyIndex = messages.count - 1
    }
  }

  /// The reply is complete.
  public mutating func finish() {
    waiting = false
    replyIndex = nil
    hadReply = false
  }

  /// Ends any wait with a problem bubble.
  public mutating func fail(_ problem: BlipProblem) {
    note(problem)
    finish()
  }

  /// Adds a small line about an action. Text that follows it starts a new reply bubble.
  public mutating func remark(_ text: String) {
    messages.append(ChatMessage(role: .note, text: text))
    if waiting {
      if replyIndex != nil { hadReply = true }
      replyIndex = nil
    }
  }

  /// Adds a problem bubble that has nothing to do with the question, if any, still being answered;
  /// its reply keeps streaming into its own bubble.
  public mutating func note(_ problem: BlipProblem) {
    messages.append(ChatMessage(role: .problem, text: problem.bubbleText))
  }
}

/// Where the chat panel goes beside the ship.
public enum ChatLayout {
  public static let gap: CGFloat = 16
  public static let margin: CGFloat = 12

  /// To the right of the ship, or to its left when the right side would leave the screen;
  /// vertically centred on the anchor; kept `margin` points inside the screen.
  public static func frame(anchor: CGPoint, shipHalfWidth: CGFloat, panel: CGSize, screen: CGRect) -> CGRect {
    var x = anchor.x + shipHalfWidth + gap
    if x + panel.width > screen.maxX - margin { x = anchor.x - shipHalfWidth - gap - panel.width }
    var y = anchor.y - panel.height / 2
    x = clamp(x, screen.minX + margin, screen.maxX - margin - panel.width)
    y = clamp(y, screen.minY + margin, screen.maxY - margin - panel.height)
    return CGRect(x: x, y: y, width: panel.width, height: panel.height)
  }

  /// Like `min(max(v, lo), hi)`, but `lo` wins when the range is empty (a panel bigger than the screen).
  private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    max(lo, min(v, hi))
  }
}
