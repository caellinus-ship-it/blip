import AppKit
import BlipCore
import SwiftUI

/// What the chat panel shows and what it reports back.
@MainActor final class ChatModel: ObservableObject {
  @Published var log = ChatLog()
  @Published var input = ""
  @Published var listening = false
  /// Enter was pressed in the text box; carries the box's text.
  var onSend: ((String) -> Void)?
  var onMic: (() -> Void)?
  /// What the assistant is waiting for permission to do, in plain words; `nil` when nothing.
  @Published var pendingAsk: String?
  /// The owner pressed Allow (true) or Don't (false) on the pending question.
  var onAnswer: ((Bool) -> Void)?
}

/// The texting-style chat beside the ship: bubbles above, the text box with its mic below.
/// Colors and sizes follow `chat()` in `docs/reference/mockup.html`.
struct ChatView: View {
  static let width: CGFloat = 340
  static let maxHeight: CGFloat = 420
  static let inputHeight: CGFloat = 36
  static let spacing: CGFloat = 8

  @ObservedObject var model: ChatModel
  let name: String
  let bubbleColor: Color
  /// The height the view needs, which changes as bubbles arrive; the panel sizes itself to it.
  let onHeightChange: (CGFloat) -> Void
  /// Where the view draws something (bubbles and the text box), in points from its top-left corner.
  /// Clicks anywhere else should reach the app underneath.
  let onSolidRectsChange: ([CGRect]) -> Void

  @FocusState private var inputFocused: Bool
  @State private var contentHeight: CGFloat = 0
  @State private var bubbleRects: [CGRect] = []

  private var showsBubbles: Bool { !model.log.messages.isEmpty || model.log.awaitingFirstText }
  private var bubblesHeight: CGFloat {
    min(contentHeight, Self.maxHeight - Self.inputHeight - Self.spacing)
  }
  private var totalHeight: CGFloat {
    showsBubbles ? bubblesHeight + Self.spacing + Self.inputHeight : Self.inputHeight
  }
  private var solidRects: [CGRect] {
    let visible = CGRect(x: 0, y: 0, width: Self.width, height: showsBubbles ? bubblesHeight : 0)
    let shown = bubbleRects.map { $0.intersection(visible) }.filter { !$0.isNull && !$0.isEmpty }
    return shown + [CGRect(x: 0, y: totalHeight - Self.inputHeight, width: Self.width, height: Self.inputHeight)]
  }

  var body: some View {
    VStack(spacing: Self.spacing) {
      if showsBubbles { bubbles }
      inputRow
    }
    .frame(width: Self.width)
    .coordinateSpace(name: Self.space)
    .onPreferenceChange(BubbleRectsKey.self) { bubbleRects = $0 }
    .onAppear {
      inputFocused = true
      onHeightChange(totalHeight)
      onSolidRectsChange(solidRects)
    }
    .onChange(of: totalHeight) { onHeightChange(totalHeight) }
    .onChange(of: solidRects) { onSolidRectsChange(solidRects) }
  }

  // MARK: Bubbles

  private var bubbles: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 8) {
          ForEach(model.log.messages) { bubble($0) }
          if let ask = model.pendingAsk {
            confirmBubble(ask)
          } else if model.log.betweenBubbles {
            TypingBubble().frame(maxWidth: .infinity, alignment: .leading)
          }
          Color.clear.frame(height: 0).id(Self.bottomID)
        }
        .background(GeometryReader { g in
          Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
        })
      }
      .frame(height: bubblesHeight)
      .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
      .onChange(of: model.log.messages) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
      .onChange(of: contentHeight) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
      .onChange(of: model.pendingAsk) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
    }
  }

  private static let bottomID = "bottom"
  static let space = "chat"

  /// The assistant wants to act: what it will do, with Allow and Don't.
  private func confirmBubble(_ ask: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Can I do this?").fontWeight(.semibold)
      Text(ask)
      HStack(spacing: 8) {
        Button("Allow") { model.onAnswer?(true) }
          .buttonStyle(.plain)
          .padding(.horizontal, 14)
          .padding(.vertical, 5)
          .background(RoundedRectangle(cornerRadius: 8).fill(bubbleColor))
          .foregroundStyle(Color.white)
        Button("Don't") { model.onAnswer?(false) }
          .buttonStyle(.plain)
          .padding(.horizontal, 14)
          .padding(.vertical, 5)
          .background(RoundedRectangle(cornerRadius: 8).fill(Palette.fieldBorder))
          .foregroundStyle(Palette.assistantText)
      }
    }
    .modifier(BubbleStyle(fill: Palette.assistant, textColor: Palette.assistantText, side: .leading,
                          border: bubbleColor))
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private func bubble(_ message: ChatMessage) -> some View {
    switch message.role {
    case .note:
      Text(message.text)
        .font(.system(size: 11))
        .foregroundStyle(Palette.assistantText.opacity(0.75))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.field))
        .reportsBubbleRect()
        .frame(maxWidth: 280, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    case .user:
      Text(message.text)
        .modifier(BubbleStyle(fill: bubbleColor, textColor: .white, side: .trailing))
        .frame(maxWidth: .infinity, alignment: .trailing)
    case .assistant:
      Text(message.text)
        .modifier(BubbleStyle(fill: Palette.assistant, textColor: Palette.assistantText, side: .leading))
        .frame(maxWidth: .infinity, alignment: .leading)
    case .problem:
      VStack(alignment: .leading, spacing: 8) {
        Text(message.text)
        if let url = SettingsPane.url(forProblemText: message.text) {
          Button("Open Settings") { NSWorkspace.shared.open(url) }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.problemBorder))
            .foregroundStyle(Color.white)
        }
      }
      .modifier(BubbleStyle(fill: Palette.assistant, textColor: Palette.assistantText, side: .leading,
                            border: Palette.problemBorder))
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: Input

  private var inputRow: some View {
    HStack(spacing: 8) {
      TextField("", text: $model.input, prompt: Text("Ask \(name)").foregroundStyle(Palette.placeholder))
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(Palette.assistantText)
        .focused($inputFocused)
        .onSubmit { model.onSend?(model.input) }
      Button { model.onMic?() } label: {
        MicIcon(listening: model.listening, color: bubbleColor)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(model.listening ? "Stop listening" : "Talk")
    }
    .padding(.leading, 14)
    .padding(.trailing, 8)
    .frame(height: Self.inputHeight)
    .background(
      RoundedRectangle(cornerRadius: 12).fill(Palette.field)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.fieldBorder, lineWidth: 1))
    )
  }
}

/// A rounded chat bubble around a text.
private struct BubbleStyle: ViewModifier {
  let fill: Color
  let textColor: Color
  /// The side of the chat the bubble sits on.
  let side: Alignment
  var border: Color? = nil

  func body(content: Content) -> some View {
    content
      .font(.system(size: 13))
      .foregroundStyle(textColor)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 12).fill(fill)
          .overlay {
            if let border { RoundedRectangle(cornerRadius: 12).strokeBorder(border, lineWidth: 1.5) }
          }
      )
      .reportsBubbleRect()
      .frame(maxWidth: 280, alignment: side)
  }
}

/// Three square dots taking turns to light up, while the answer is on its way.
private struct TypingBubble: View {
  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.25)) { context in
      let lit = Int(context.date.timeIntervalSinceReferenceDate * 4) % 3
      HStack(spacing: 8) {
        ForEach(0..<3, id: \.self) { i in
          Rectangle().fill(i == lit ? Color.white : Palette.dotDim).frame(width: 4, height: 4)
        }
      }
      .frame(width: 60, height: 30)
      .background(RoundedRectangle(cornerRadius: 12).fill(Palette.assistant))
      .reportsBubbleRect()
    }
    .accessibilityLabel("Thinking")
  }
}

/// The mic: an outline while idle; filled in the bubble color and pulsing in size steps while listening.
private struct MicIcon: View {
  let listening: Bool
  let color: Color

  private static let step: TimeInterval = 0.15
  private static let scales: [CGFloat] = [1.0, 1.1, 1.2, 1.1]

  var body: some View {
    if listening {
      TimelineView(.periodic(from: .now, by: Self.step)) { context in
        let i = Int(context.date.timeIntervalSinceReferenceDate / Self.step) % Self.scales.count
        symbol("mic.fill", color).scaleEffect(Self.scales[i])
      }
    } else {
      symbol("mic", Palette.mic)
    }
  }

  private func symbol(_ name: String, _ color: Color) -> some View {
    Image(systemName: name)
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(color)
  }
}

/// Every bubble's frame in the chat's coordinate space.
private struct BubbleRectsKey: PreferenceKey {
  static let defaultValue: [CGRect] = []
  static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

private extension View {
  func reportsBubbleRect() -> some View {
    background(GeometryReader { g in
      Color.clear.preference(key: BubbleRectsKey.self, value: [g.frame(in: .named(ChatView.space))])
    })
  }
}

private struct ContentHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The chat's fixed colors.
enum Palette {
  static let assistant = Color(rgba: 0x2E2E3EFF)
  static let assistantText = Color(rgba: 0xF4F4F8FF)
  static let problemBorder = Color(rgba: 0xFB7185FF)
  static let field = Color(rgba: 0x1F1F2CFF)
  static let fieldBorder = Color(rgba: 0x4A4A60FF)
  static let placeholder = Color(rgba: 0x8A8AA0FF)
  static let mic = Color(rgba: 0xC8C8D8FF)
  static let dotDim = Color(rgba: 0x7C7C92FF)
}

/// The System Settings page that fixes a missing permission.
enum SettingsPane {
  static func url(forProblemText text: String) -> URL? {
    switch text {
    case BlipProblem.noScreenPermission.bubbleText:
      return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    case BlipProblem.noMicPermission.bubbleText:
      return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    default:
      return nil
    }
  }
}

extension Color {
  /// From `0xRRGGBBAA`, in sRGB.
  init(rgba: RGBA) {
    self.init(.sRGB,
              red: Double((rgba >> 24) & 0xFF) / 255, green: Double((rgba >> 16) & 0xFF) / 255,
              blue: Double((rgba >> 8) & 0xFF) / 255, opacity: Double(rgba & 0xFF) / 255)
  }
}
