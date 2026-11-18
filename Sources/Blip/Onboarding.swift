import AppKit
import BlipCore
import SwiftUI

/// The welcome shown on the first launch: the character hovering, three lines in its own voice
/// (what it does and the shortcut, Screen Recording, the microphone), the Start at login switch
/// and a button to close it.
enum Onboarding {
  /// Set once the welcome has been closed, so it is shown only on the first launch.
  static let didOnboardKey = "didOnboard"

  static var isDone: Bool { UserDefaults.standard.bool(forKey: didOnboardKey) }
}

struct OnboardingView: View {
  static let width: CGFloat = 560
  static let background = Color(rgba: 0x12121CFF)
  static let panel = Color(rgba: 0x1C1C2BFF)
  static let text = Color(rgba: 0xE8E8F2FF)
  static let secondaryText = Color(rgba: 0x9A9AB2FF)

  @ObservedObject var store: SettingsStore
  var onDone: () -> Void

  @State private var screenAllowed = ScreenCapturer.hasPermission
  /// The macOS prompt shows only once; after that, Turn on opens the page in System Settings.
  @State private var askedForScreen = false

  private var name: String { store.settings.name }
  private var accent: Color { Color(rgba: ColorRamp(store.settings.trailColor).main) }

  var body: some View {
    HStack(alignment: .top, spacing: 22) {
      CharacterPreview(settings: store.settings)
        .frame(width: CharacterPreview.size.width, height: CharacterPreview.size.height)
        .background(Self.panel)
        .overlay(Rectangle().strokeBorder(accent.opacity(0.6), lineWidth: 2))

      VStack(alignment: .leading, spacing: 16) {
        line("sparkles") {
          Text("Hi, I'm \(name). Press \(HotKeyRecorder.describe(store.settings.hotKey)) and I'll fly in to help with whatever's on your screen. Press it again and I'm off.")
        }
        line("rectangle.dashed") {
          VStack(alignment: .leading, spacing: 8) {
            Text("To see your screen I need Screen Recording. I only look when you ask me something.")
            screenButton
          }
        }
        line("mic") {
          Text("The first time you press the mic, I'll ask to use it so you can talk to me.")
        }
        Spacer(minLength: 0)
        HStack {
          Toggle("Start at login", isOn: $store.settings.launchAtLogin)
            .toggleStyle(.switch)
            .accessibilityLabel("Start at login")
            .tint(accent)
            .foregroundStyle(Self.text)
          Spacer()
          Button("Got it", action: onDone)
            .buttonStyle(ArcadeButtonStyle(fill: accent, textColor: Self.background))
            .keyboardShortcut(.defaultAction)
        }
      }
      .frame(maxWidth: .infinity, minHeight: CharacterPreview.size.height, alignment: .topLeading)
    }
    .padding(24)
    .frame(width: Self.width)
    .fixedSize(horizontal: false, vertical: true)
    .background(Self.background)
    .preferredColorScheme(.dark)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      screenAllowed = ScreenCapturer.hasPermission
    }
  }

  @ViewBuilder private var screenButton: some View {
    if screenAllowed {
      Label("Screen Recording is on", systemImage: "checkmark")
        .font(.callout)
        .foregroundStyle(accent)
    } else {
      Button("Turn on") {
        if askedForScreen, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
          NSWorkspace.shared.open(url)
        } else {
          ScreenCapturer.requestPermission()
          askedForScreen = true
        }
        screenAllowed = ScreenCapturer.hasPermission
      }
      .buttonStyle(ArcadeButtonStyle(fill: Self.panel, textColor: accent, border: accent))
    }
  }

  private func line<Content: View>(_ symbol: String, @ViewBuilder _ content: () -> Content) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: symbol)
        .foregroundStyle(accent)
        .frame(width: 18)
        .accessibilityHidden(true)
      content()
        .foregroundStyle(Self.text)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// A square-cornered button in the arcade style.
private struct ArcadeButtonStyle: ButtonStyle {
  let fill: Color
  let textColor: Color
  var border: Color?

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(textColor)
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .background(fill.brightness(configuration.isPressed ? -0.15 : 0))
      .overlay(Rectangle().strokeBorder(border ?? .clear, lineWidth: 2))
      .contentShape(Rectangle())
  }
}

/// Owns the welcome window. It is built when shown and thrown away when closed, which also stops
/// the preview; closing it by any means counts as done.
@MainActor final class OnboardingWindowController: NSObject, NSWindowDelegate {
  private let store: SettingsStore
  private var window: NSWindow?

  init(store: SettingsStore) {
    self.store = store
  }

  /// Shows the welcome if it has not been closed before.
  func showIfFirstLaunch() {
    guard !Onboarding.isDone else { return }
    show()
  }

  func show() {
    let window = self.window ?? makeWindow()
    self.window = window
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()  // in front even when macOS declines the activation
  }

  private func makeWindow() -> NSWindow {
    let host = NSHostingView(rootView: OnboardingView(store: store) { [weak self] in self?.window?.performClose(nil) })
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: host.fittingSize),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Welcome"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = NSColor(OnboardingView.background)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.delegate = self
    window.center()
    return window
  }

  func windowWillClose(_ notification: Notification) {
    UserDefaults.standard.set(true, forKey: Onboarding.didOnboardKey)
    window?.delegate = nil
    window?.contentView = nil  // takes the preview out of the window, which stops its display link
    window = nil
  }
}
