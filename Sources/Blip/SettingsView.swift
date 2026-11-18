import AppKit
import BlipCore
import Combine
import SwiftUI

/// The settings window: a live preview of the character on the left, every option on the right.
/// Every change is saved and applied at once.
struct SettingsView: View {
  static let size = CGSize(width: 560, height: 520)

  @ObservedObject var store: SettingsStore
  /// The shortcut recorder started (`true`) or stopped (`false`) listening.
  var onRecordingShortcut: (Bool) -> Void = { _ in }

  /// The last custom personality typed, kept while another personality is picked.
  @State private var customPersonality = ""
  /// What "Find automatically" found: `nil` before it is pressed, `""` when nothing was found.
  @State private var foundClaude: String?

  private var settings: Binding<BlipSettings> { $store.settings }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      VStack(spacing: 10) {
        CharacterPreview(settings: store.settings)
          .frame(width: CharacterPreview.size.width, height: CharacterPreview.size.height)
          .background(RoundedRectangle(cornerRadius: 10).fill(Color(rgba: 0x262A3AFF)))
          .clipShape(RoundedRectangle(cornerRadius: 10))
        Text(store.settings.name)
          .font(.headline)
      }
      .padding(20)
      .frame(width: CharacterPreview.size.width + 40)

      Form {
        character
        look
        Section("Motion") {
          Picker("Motion", selection: settings.hover) {
            Text("Figure 8").tag(HoverMotion.figure8)
            Text("Simple bob").tag(HoverMotion.bob)
            Text("Still").tag(HoverMotion.still)
          }
          .accessibilityLabel("Motion")
        }
        personality
        Section("Answers") {
          Picker("Answers", selection: settings.answers) {
            Text("Short").tag(AnswerLength.short)
            Text("Detailed").tag(AnswerLength.detailed)
          }
          .accessibilityLabel("Answers")
        }
        Section("Brain") {
          Picker("Brain", selection: settings.model) {
            Text("Fastest").tag(BrainModel.fastest)
            Text("Smarter").tag(BrainModel.smarter)
          }
          .accessibilityLabel("Brain")
        }
        Section("Sounds") {
          Toggle("Sounds", isOn: settings.sounds)
            .accessibilityLabel("Sounds")
        }
        Section("Shortcut") {
          LabeledContent("Shortcut") {
            HotKeyRecorder(hotKey: settings.hotKey, onRecordingChanged: onRecordingShortcut)
              .frame(width: 140)
          }
        }
        Section("Start at login") {
          Toggle("Start at login", isOn: settings.launchAtLogin)
            .accessibilityLabel("Start at login")
        }
        advanced
      }
      .formStyle(.grouped)
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .onAppear {
      if case .custom(let text) = store.settings.personality { customPersonality = text }
    }
  }

  // MARK: Groups

  private var character: some View {
    Section("Character") {
      TextField("Name", text: settings.name)
        .accessibilityLabel("Name")
      Picker("Creature", selection: settings.creature) {
        Text("Blob").tag(Creature.blob)
        Text("Ghost").tag(Creature.ghost)
        Text("Cat").tag(Creature.cat)
        Text("Alien").tag(Creature.alien)
      }
      .accessibilityLabel("Creature")
      Picker("Ship", selection: settings.ship) {
        Text("Rocket").tag(Ship.rocket)
        Text("Saucer").tag(Ship.saucer)
        Text("Bubble pod").tag(Ship.pod)
        Text("Star ship").tag(Ship.star)
      }
      .accessibilityLabel("Ship")
      Picker("Size", selection: settings.size) {
        Text("Small").tag(SizeOption.small)
        Text("Medium").tag(SizeOption.medium)
        Text("Large").tag(SizeOption.large)
      }
      .accessibilityLabel("Size")
    }
  }

  private var look: some View {
    Section("Look") {
      Picker("Trail", selection: settings.trail) {
        Text("Comet").tag(TrailStyle.comet)
        Text("Flame").tag(TrailStyle.flame)
        Text("Smoke rings").tag(TrailStyle.rings)
        Text("Echoes").tag(TrailStyle.echoes)
        Text("Lightning").tag(TrailStyle.lightning)
        Text("Confetti").tag(TrailStyle.confetti)
      }
      .accessibilityLabel("Trail")
      HStack(spacing: 6) {
        Text("Trail color")
        Spacer()
        HStack(spacing: 6) {
          ForEach(Self.trailPresets, id: \.name) { preset in
            swatch(preset.color, name: preset.name)
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trail color presets")
        ColorPicker("Custom trail color", selection: customTrailColor, supportsOpacity: false)
          .labelsHidden()
      }
      Toggle("Aura matches creature", isOn: auraMatchesCreature)
        .accessibilityLabel("Aura matches creature")
      ColorPicker("Aura color", selection: auraColor, supportsOpacity: false)
        .accessibilityLabel("Aura color")
        .disabled(store.settings.auraColor == nil)
      ColorPicker("Bubble color", selection: bubbleColor, supportsOpacity: false)
        .accessibilityLabel("Bubble color")
    }
  }

  private var personality: some View {
    Section("Personality") {
      Picker("Personality", selection: personalityKind) {
        Text("Playful").tag(PersonalityKind.playful)
        Text("Plain").tag(PersonalityKind.plain)
        Text("My own").tag(PersonalityKind.custom)
      }
      .accessibilityLabel("Personality")
      if case .custom = store.settings.personality {
        TextField("Description", text: customPersonalityText, prompt: Text("a sleepy wizard who loves puns"),
                  axis: .vertical)
          .lineLimit(2...4)
          .accessibilityLabel("Personality description")
      }
    }
  }

  private var advanced: some View {
    Section("Advanced") {
      TextField("claude", text: claudePath, prompt: Text("Found automatically"))
        .accessibilityLabel("Path to claude")
      HStack {
        Button("Find automatically") {
          store.settings.claudePath = nil
          foundClaude = Self.locateClaude() ?? ""
        }
        if let foundClaude {
          Text(foundClaude.isEmpty ? "Not found" : foundClaude)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
      }
    }
  }

  // MARK: Trail color

  private static let trailPresets: [(name: String, color: TrailColor)] = [
    ("Fire", .fire), ("Pink", .pink), ("Cyan", .cyan), ("Lime", .lime), ("Violet", .violet),
  ]

  private func swatch(_ color: TrailColor, name: String) -> some View {
    let selected = store.settings.trailColor == color
    return Button { store.settings.trailColor = color } label: {
      Label("\(name) trail", systemImage: selected ? "smallcircle.filled.circle.fill" : "circle.fill")
        .labelStyle(.iconOnly)
        .font(.system(size: 18))
        .foregroundStyle(Color(rgba: ColorRamp(color).main))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  /// The color well: shows the custom color, or the preset's main color until one is picked.
  private var customTrailColor: Binding<Color> {
    Binding(
      get: { Color(rgba: ColorRamp(store.settings.trailColor).main) },
      set: { color in
        // Opening the well reports the color it shows; that alone must not turn a preset into a custom color.
        let rgba = color.rgba
        guard rgba != ColorRamp(store.settings.trailColor).main else { return }
        store.settings.trailColor = .custom(rgba)
      })
  }

  // MARK: Other colors

  private var auraMatchesCreature: Binding<Bool> {
    Binding(
      get: { store.settings.auraColor == nil },
      set: { matches in
        store.settings.auraColor = matches ? nil : Art.creature(store.settings.creature).body
      })
  }

  private var auraColor: Binding<Color> {
    Binding(
      get: { Color(rgba: store.settings.auraColor ?? Art.creature(store.settings.creature).body) },
      set: { store.settings.auraColor = $0.rgba })
  }

  private var bubbleColor: Binding<Color> {
    Binding(get: { Color(rgba: store.settings.bubbleColor) }, set: { store.settings.bubbleColor = $0.rgba })
  }

  // MARK: Personality

  private enum PersonalityKind: Hashable { case playful, plain, custom }

  private var personalityKind: Binding<PersonalityKind> {
    Binding(
      get: {
        switch store.settings.personality {
        case .playful: return .playful
        case .plain: return .plain
        case .custom: return .custom
        }
      },
      set: { kind in
        switch kind {
        case .playful: store.settings.personality = .playful
        case .plain: store.settings.personality = .plain
        case .custom: store.settings.personality = .custom(customPersonality)
        }
      })
  }

  private var customPersonalityText: Binding<String> {
    Binding(
      get: {
        if case .custom(let text) = store.settings.personality { return text }
        return customPersonality
      },
      set: { text in
        customPersonality = text
        store.settings.personality = .custom(text)
      })
  }

  // MARK: Advanced

  private var claudePath: Binding<String> {
    Binding(
      get: { store.settings.claudePath ?? "" },
      set: { path in
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        store.settings.claudePath = trimmed.isEmpty ? nil : trimmed
        foundClaude = nil
      })
  }

  /// Where `claude` is found without a custom path, as `BrainSession` looks for it.
  private static func locateClaude() -> String? {
    let home = ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
    return ClaudeLocator.find(custom: nil, home: home, exists: FileManager.default.isExecutableFile(atPath:))
  }
}

extension Color {
  /// As `0xRRGGBBAA` in sRGB, fully opaque.
  var rgba: RGBA {
    guard let c = NSColor(self).usingColorSpace(.sRGB) else { return 0x000000FF }
    func byte(_ v: CGFloat) -> RGBA { RGBA((min(max(v, 0), 1) * 255).rounded()) }
    return byte(c.redComponent) << 24 | byte(c.greenComponent) << 16 | byte(c.blueComponent) << 8 | 0xFF
  }
}

// MARK: - Preview

/// The current character hovering, run by the same `Scene` as the overlay, one arcade pixel per
/// `pointsPerPixel` points. It animates only while it is in a window.
struct CharacterPreview: NSViewRepresentable {
  static let bufferWidth = 96
  static let bufferHeight = 110
  static let pointsPerPixel = 2
  static let size = CGSize(width: bufferWidth * pointsPerPixel, height: bufferHeight * pointsPerPixel)

  let settings: BlipSettings

  func makeNSView(context: Context) -> PreviewView { PreviewView(settings: settings) }

  func updateNSView(_ view: PreviewView, context: Context) { view.show(settings) }

  final class PreviewView: NSView {
    private static let tickSeconds: CFTimeInterval = 1.0 / 60
    private static let maxTicksPerFrame = 4

    /// The settings the preview draws; a change to any of them restarts the scene.
    private struct Look: Equatable {
      let creature: Creature, ship: Ship, trail: TrailStyle, trailColor: TrailColor
      let auraColor: RGBA?, hover: HoverMotion

      init(_ s: BlipSettings) {
        (creature, ship, trail, trailColor, auraColor, hover) =
          (s.creature, s.ship, s.trail, s.trailColor, s.auraColor, s.hover)
      }
    }

    private var look: Look
    private var scene: BlipCore.Scene
    private var buffer = PixelBuffer(width: CharacterPreview.bufferWidth, height: CharacterPreview.bufferHeight)
    private let pixelLayer = CALayer()
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var accumulator: CFTimeInterval = 0

    init(settings: BlipSettings) {
      look = Look(settings)
      scene = Self.hoveringScene(settings)
      super.init(frame: NSRect(origin: .zero, size: CharacterPreview.size))
      wantsLayer = true
      pixelLayer.frame = bounds
      pixelLayer.magnificationFilter = .nearest
      pixelLayer.actions = ["contents": NSNull()]  // no cross-fade between frames
      layer?.addSublayer(pixelLayer)
      setAccessibilityElement(true)
      setAccessibilityRole(.image)
      setAccessibilityLabel("Preview")
      render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
      super.layout()
      pixelLayer.frame = bounds
    }

    /// Restarts the scene if `settings` look different from what is shown.
    func show(_ settings: BlipSettings) {
      let new = Look(settings)
      guard new != look else { return }
      look = new
      scene = Self.hoveringScene(settings)
      render()
    }

    /// The display link holds on to the view, so it runs only while the view is in a window.
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil {
        link?.invalidate()
        link = nil
      } else if link == nil {
        lastTimestamp = nil
        accumulator = 0
        let l = displayLink(target: self, selector: #selector(frame(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
      }
    }

    @objc private func frame(_ link: CADisplayLink) {
      if let last = lastTimestamp { accumulator += link.timestamp - last }
      lastTimestamp = link.timestamp
      var ticks = Int(accumulator / Self.tickSeconds + 0.05)
      if ticks > Self.maxTicksPerFrame {
        ticks = Self.maxTicksPerFrame
        accumulator = 0
      } else {
        accumulator -= Double(ticks) * Self.tickSeconds
      }
      guard ticks > 0 else { return }
      for _ in 0..<ticks { scene.tick() }
      render()
    }

    private func render() {
      buffer.clear()
      scene.render(into: &buffer)
      pixelLayer.contents = buffer.makeImage()
    }

    /// A scene already past its fly-in, hovering in the middle of the buffer.
    private static func hoveringScene(_ settings: BlipSettings) -> BlipCore.Scene {
      var scene = BlipCore.Scene(
        settings: settings, bufferWidth: CharacterPreview.bufferWidth,
        bufferHeight: CharacterPreview.bufferHeight, seed: 1)
      for _ in 0..<SummonController.settleTicks { scene.tick() }
      return scene
    }
  }
}

// MARK: - Window

/// Owns the settings window. The window is built when it is shown and thrown away when it closes,
/// which also stops the preview.
@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
  private let store: SettingsStore
  private let onRecordingShortcut: (Bool) -> Void
  private var window: NSWindow?
  private var titleWatch: AnyCancellable?

  init(store: SettingsStore, onRecordingShortcut: @escaping (Bool) -> Void) {
    self.store = store
    self.onRecordingShortcut = onRecordingShortcut
  }

  func show() {
    let window = self.window ?? makeWindow()
    self.window = window
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()  // in front even when macOS declines the activation
  }

  private func makeWindow() -> NSWindow {
    let window = SettingsWindow(
      contentRect: NSRect(origin: .zero, size: SettingsView.size),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(
      rootView: SettingsView(store: store, onRecordingShortcut: onRecordingShortcut))
    window.delegate = self
    window.center()
    titleWatch = store.$settings.map(\.name).removeDuplicates().sink { [weak window] name in
      window?.title = "\(name) Settings"
    }
    return window
  }

  func windowWillClose(_ notification: Notification) {
    titleWatch = nil
    if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.close() }  // opened by a color well here
    window?.delegate = nil
    window?.contentView = nil  // takes the preview out of the window, which stops its display link
    window = nil
  }
}

/// A normal window that also handles the editing shortcuts and Command-W, as Blip has no menu bar
/// of its own to provide them.
private final class SettingsWindow: NSWindow {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
    // The views go first, so the shortcut recorder can record any of these.
    if super.performKeyEquivalent(with: event) { return true }
    if event.type == .keyDown, modifiers == .command, key == "w" {
      performClose(nil)
      return true
    }
    if event.type == .keyDown, modifiers == .command || modifiers == [.command, .shift],
       let action = ChatPanel.editAction(key: key, shift: modifiers.contains(.shift)),
       NSApp.sendAction(action, to: nil, from: self) {
      return true
    }
    return false
  }
}
