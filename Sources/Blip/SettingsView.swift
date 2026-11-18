import AppKit
import BlipCore
import SwiftUI

/// The settings window: the stage on the left, flying the current combination, with the name plate
/// and Launch under it; every option on the right, in panels. Every change is saved and applied at once.
struct SettingsView: View {
  static let size = CGSize(width: 760, height: 600)
  /// Tall enough that Launch lines up with the bottom of the options column.
  static let stageSize = CGSize(width: 320, height: 452)
  private static let margin: CGFloat = 20

  @ObservedObject var store: SettingsStore
  var shortcut = ShortcutHooks()

  /// The last custom personality typed, kept while another personality is picked.
  @State private var customPersonality = ""
  /// What "Find automatically" found: `nil` before it is pressed, `""` when nothing was found.
  @State private var foundClaude: String?
  /// Bumped by Launch to replay the fly-in.
  @State private var launches = 0
  /// Start at login as macOS has it, read when the window opens and after each change.
  @State private var loginOn = LoginItem.isOn
  @State private var loginNeedsApproval = LoginItem.needsApproval

  private var settings: Binding<BlipSettings> { $store.settings }
  private var accent: Color { SettingsTheme.accent(store.settings.trailColor) }

  var body: some View {
    HStack(alignment: .top, spacing: Self.margin) {
      stageColumn
        .frame(width: Self.stageSize.width)
        .padding(.vertical, Self.margin)
      ScrollView {
        optionsColumn
          .padding(.vertical, Self.margin)
          .padding(.trailing, Self.margin)
      }
    }
    .padding(.leading, Self.margin)
    .frame(width: Self.size.width, height: Self.size.height)
    .background(SettingsTheme.background)
    .foregroundStyle(SettingsTheme.text)
    .tint(accent)
    .preferredColorScheme(.dark)
    .onAppear {
      if case .custom(let text) = store.settings.personality { customPersonality = text }
      refreshLogin()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      refreshLogin()  // the owner may have changed it in System Settings
    }
  }

  // MARK: Left: the stage

  private var stageColumn: some View {
    VStack(spacing: 12) {
      CharacterPreview(size: Self.stageSize, settings: store.settings, launches: launches)
        .frame(width: Self.stageSize.width, height: Self.stageSize.height)
        .background(SettingsTheme.well)
        .overlay(RoundedRectangle(cornerRadius: SettingsTheme.cornerRadius).strokeBorder(SettingsTheme.line))
        .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.cornerRadius))
      namePlate
      Button { launches += 1 } label: {
        Label("Launch", systemImage: "arrow.up")
          .frame(maxWidth: .infinity, minHeight: 24)
      }
      .buttonStyle(ArcadeButtonStyle(fill: accent, textColor: SettingsTheme.background))
      .accessibilityLabel("Launch")
    }
  }

  private var namePlate: some View {
    TextField("Name", text: settings.name, prompt: Text("Blip").foregroundStyle(SettingsTheme.secondaryText))
      .textFieldStyle(.plain)
      .font(.system(size: 22, weight: .semibold))
      .multilineTextAlignment(.center)
      .foregroundStyle(SettingsTheme.text)
      .padding(.horizontal, 36)
      .frame(height: 48)
      .background(SettingsTheme.panel)
      .overlay(alignment: .trailing) {
        Image(systemName: "pencil")
          .foregroundStyle(SettingsTheme.secondaryText)
          .padding(.trailing, 14)
          .accessibilityHidden(true)
      }
      .overlay(alignment: .bottom) { Rectangle().fill(accent).frame(height: 2) }
      .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.cornerRadius))
      .accessibilityLabel("Name")
  }

  // MARK: Right: the options

  private var optionsColumn: some View {
    VStack(spacing: 12) {
      SettingsPanel(title: "Creature") {
        TilePicker(
          label: "Creature",
          options: [(.blob, "Blob"), (.ghost, "Ghost"), (.cat, "Cat"), (.alien, "Alien")],
          images: ThumbnailImages.creatures, scale: 4, columns: 4, selection: settings.creature, accent: accent)
      }
      SettingsPanel(title: "Ship") {
        TilePicker(
          label: "Ship",
          options: [(.rocket, "Rocket"), (.saucer, "Saucer"), (.pod, "Bubble pod"), (.star, "Star ship")],
          images: ThumbnailImages.ships, scale: 3, columns: 4, selection: settings.ship, accent: accent)
      }
      SettingsPanel(title: "Trail") {
        TilePicker(
          label: "Trail",
          options: [
            (.comet, "Comet"), (.flame, "Flame"), (.rings, "Smoke rings"),
            (.echoes, "Echoes"), (.lightning, "Lightning"), (.confetti, "Confetti"),
          ],
          images: ThumbnailImages.trails(ColorRamp(store.settings.trailColor)), scale: 2, columns: 3,
          selection: settings.trail, accent: accent)
      }
      colors
      SettingsPanel(title: "Flight") {
        SettingRow(label: "Comet entrance") {
          Toggle("Comet entrance", isOn: settings.comet)
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel("Comet entrance")
        }
        SettingRow(label: "Size") {
          segmented("Size", settings.size, [(.small, "Small"), (.medium, "Medium"), (.large, "Large")])
        }
        SettingRow(label: "Motion") {
          segmented("Motion", settings.hover, [(.figure8, "Figure 8"), (.bob, "Simple bob"), (.still, "Still")])
        }
      }
      assistant
      app
    }
  }

  private var colors: some View {
    SettingsPanel(title: "Colors") {
      SettingRow(label: "Trail") {
        TrailSwatches(trailColor: settings.trailColor)
        ColorPicker("Custom trail color", selection: customTrailColor, supportsOpacity: false)
          .labelsHidden()
      }
      SettingRow(label: "Aura") {
        Toggle("Match creature", isOn: auraMatchesCreature)
          .toggleStyle(.switch)
          .foregroundStyle(SettingsTheme.secondaryText)
          .accessibilityLabel("Aura matches creature")
        ColorPicker("Aura color", selection: auraColor, supportsOpacity: false)
          .labelsHidden()
          .disabled(store.settings.auraColor == nil)
          .opacity(store.settings.auraColor == nil ? 0.4 : 1)
      }
      SettingRow(label: "Chat bubbles") {
        ColorPicker("Bubble color", selection: bubbleColor, supportsOpacity: false)
          .labelsHidden()
      }
    }
  }

  private var assistant: some View {
    SettingsPanel(title: "Assistant") {
      SettingRow(label: "Personality") {
        segmented("Personality", personalityKind, [(.playful, "Playful"), (.plain, "Plain"), (.custom, "My own")])
      }
      if case .custom = store.settings.personality {
        TextField("Description", text: customPersonalityText, prompt: Text("a sleepy wizard who loves puns"),
                  axis: .vertical)
          .lineLimit(2...4)
          .textFieldStyle(ArcadeFieldStyle())
          .accessibilityLabel("Personality description")
      }
      SettingRow(label: "Answers") {
        segmented("Answers", settings.answers, [(.short, "Short"), (.detailed, "Detailed")])
      }
      SettingRow(label: "Brain") {
        segmented("Brain", settings.model, [(.fastest, "Fastest"), (.smarter, "Smarter")])
      }
    }
  }

  private var app: some View {
    SettingsPanel(title: "App") {
      SettingRow(label: "Sounds") {
        Toggle("Sounds", isOn: settings.sounds)
          .toggleStyle(.switch)
          .labelsHidden()
          .accessibilityLabel("Sounds")
      }
      SettingRow(label: "Shortcut") {
        HotKeyRecorder(hotKey: settings.hotKey, hooks: shortcut)
          .frame(width: 150)
      }
      SettingRow(label: "Start at login") {
        Toggle("Start at login", isOn: startAtLogin)
          .toggleStyle(.switch)
          .labelsHidden()
          .accessibilityLabel("Start at login")
      }
      if loginNeedsApproval {
        Text("Allow Blip in System Settings, under Login Items.")
          .font(.caption)
          .foregroundStyle(SettingsTheme.secondaryText)
      }
      advanced
    }
  }

  private var advanced: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Path to claude")
        .foregroundStyle(SettingsTheme.text)
        .padding(.top, 4)
      TextField("claude", text: claudePath, prompt: Text("Found automatically"))
        .textFieldStyle(ArcadeFieldStyle())
        .accessibilityLabel("Path to claude")
      HStack(spacing: 8) {
        Button("Find automatically") { foundClaude = Self.locateClaude() ?? "" }
          .buttonStyle(ArcadeButtonStyle(fill: SettingsTheme.panel, textColor: SettingsTheme.text, border: SettingsTheme.line))
          .fixedSize()
        if let foundClaude {
          Text(foundClaude.isEmpty ? "Not found" : foundClaude)
            .font(.caption)
            .foregroundStyle(SettingsTheme.secondaryText)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
          if !foundClaude.isEmpty && store.settings.claudePath != nil {
            Spacer(minLength: 0)
            Button("Use") { store.settings.claudePath = nil }
              .buttonStyle(ArcadeButtonStyle(fill: SettingsTheme.panel, textColor: accent, border: accent))
              .fixedSize()
              .accessibilityLabel("Use found claude")
          }
        }
      }
    }
  }

  // MARK: Controls

  private func segmented<T: Hashable>(_ label: String, _ selection: Binding<T>, _ options: [(T, String)]) -> some View {
    Picker(label, selection: selection) {
      ForEach(options, id: \.0) { option in Text(option.1).tag(option.0) }
    }
    .pickerStyle(.segmented)
    .labelsHidden()  // the picker's own title is still its accessibility label
    .fixedSize()
  }

  // MARK: Colors

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

  // MARK: Start at login

  private var startAtLogin: Binding<Bool> {
    LoginItem.switchBinding(store: store, shown: $loginOn, refreshed: refreshLogin)
  }

  private func refreshLogin() {
    loginOn = LoginItem.isOn
    loginNeedsApproval = LoginItem.needsApproval
  }

  // MARK: Advanced

  private var claudePath: Binding<String> {
    Binding(
      get: { store.settings.claudePath ?? "" },
      set: { path in
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        store.settings.claudePath = trimmed.isEmpty ? nil : trimmed
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
