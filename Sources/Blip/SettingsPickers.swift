import AppKit
import BlipCore
import SwiftUI

/// The settings window's arcade look: the mockup's deep blue-black, square-ish panels, and the trail
/// color as the accent.
enum SettingsTheme {
  static let background = Color(rgba: 0x12121CFF)
  static let panel = Color(rgba: 0x1A1A28FF)
  /// The strip a panel's title sits in, as in the mockup.
  static let panelHeader = Color(rgba: 0x222234FF)
  /// Behind the stage and inside tiles and fields: darker than the panels.
  static let well = Color(rgba: 0x0E0E17FF)
  static let line = Color(rgba: 0x2E2E44FF)
  static let text = Color(rgba: 0xE8E8F2FF)
  static let secondaryText = Color(rgba: 0x9A9AB2FF)
  static let cornerRadius: CGFloat = 4

  /// The trail ramp's main color, or its light color when the main one is too dark to see on the panels.
  static func accent(_ trailColor: TrailColor) -> Color {
    let ramp = ColorRamp(trailColor)
    return Color(rgba: luminance(ramp.main) < 0.12 ? ramp.light : ramp.main)
  }

  private static func luminance(_ c: RGBA) -> Double {
    let r = Double((c >> 24) & 0xFF), g = Double((c >> 16) & 0xFF), b = Double((c >> 8) & 0xFF)
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
  }
}

// MARK: - Panels and rows

/// A titled panel in the right-hand column.
struct SettingsPanel<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(SettingsTheme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsTheme.panelHeader)
        .accessibilityAddTraits(.isHeader)
      VStack(alignment: .leading, spacing: 10) { content }
        .padding(12)
    }
    .background(SettingsTheme.panel)
    .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.cornerRadius))
  }
}

/// A label on the left and its control on the right.
struct SettingRow<Control: View>: View {
  let label: String
  @ViewBuilder var control: Control

  var body: some View {
    HStack(spacing: 12) {
      Text(label).foregroundStyle(SettingsTheme.text).lineLimit(1).fixedSize()
      Spacer(minLength: 0)
      control
    }
    .frame(minHeight: 24)
  }
}

/// A dark, square-ish text field.
struct ArcadeFieldStyle: TextFieldStyle {
  func _body(configuration: TextField<Self._Label>) -> some View {
    configuration
      .textFieldStyle(.plain)
      .foregroundStyle(SettingsTheme.text)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(SettingsTheme.well)
      .overlay(RoundedRectangle(cornerRadius: SettingsTheme.cornerRadius).strokeBorder(SettingsTheme.line))
  }
}

// MARK: - Picture tiles

/// The pictures on the tiles, made once per option; trail pictures again for each new trail color.
@MainActor enum ThumbnailImages {
  static let creatures: [Creature: CGImage] = images(Creature.allCases, Thumbnail.creature)
  static let ships: [Ship: CGImage] = images(Ship.allCases, Thumbnail.ship)
  private static var trailCache: (ramp: ColorRamp, images: [TrailStyle: CGImage])?

  static func trails(_ ramp: ColorRamp) -> [TrailStyle: CGImage] {
    if let cache = trailCache, cache.ramp == ramp { return cache.images }
    let made = images(TrailStyle.allCases) { Thumbnail.trail($0, ramp: ramp) }
    trailCache = (ramp, made)
    return made
  }

  private static func images<T: Hashable>(_ options: [T], _ draw: (T) -> PixelBuffer) -> [T: CGImage] {
    var result: [T: CGImage] = [:]
    for option in options { result[option] = draw(option).makeImage() }
    return result
  }
}

/// A row or grid of tiles, one per option, each showing the option's picture and name.
struct TilePicker<Option: Hashable>: View {
  let label: String
  let options: [(option: Option, name: String)]
  let images: [Option: CGImage]
  /// Screen points per thumbnail pixel.
  let scale: Int
  let columns: Int
  @Binding var selection: Option
  let accent: Color

  var body: some View {
    let rows = stride(from: 0, to: options.count, by: columns).map { Array(options[$0..<min($0 + columns, options.count)]) }
    VStack(spacing: 8) {
      ForEach(rows.indices, id: \.self) { r in
        HStack(spacing: 8) {
          ForEach(rows[r], id: \.option) { item in
            tile(item.option, name: item.name)
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
  }

  private var pictureHeight: CGFloat {
    CGFloat((images.values.map(\.height).max() ?? 0) * scale)
  }

  private func tile(_ option: Option, name: String) -> some View {
    let selected = option == selection
    return Button { selection = option } label: {
      VStack(spacing: 6) {
        Group {
          if let image = images[option] {
            Image(decorative: image, scale: 1)
              .resizable()
              .interpolation(.none)
              .frame(width: CGFloat(image.width * scale), height: CGFloat(image.height * scale))
          }
        }
        .frame(height: pictureHeight)
        Text(name)
          .font(.system(size: 11, weight: selected ? .semibold : .regular))
          .foregroundStyle(selected ? SettingsTheme.text : SettingsTheme.secondaryText)
          .lineLimit(1)
      }
      .padding(.top, 8)
      .padding(.bottom, 6)
      .frame(maxWidth: .infinity)
      .background(SettingsTheme.well)
      .overlay(
        RoundedRectangle(cornerRadius: SettingsTheme.cornerRadius)
          .strokeBorder(selected ? accent : SettingsTheme.line, lineWidth: selected ? 2 : 1))
      .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.cornerRadius))
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(name)
    .accessibilityValue(selected ? "Selected" : "Not selected")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// Darkens a plain button a little while it is held down.
private struct PressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.brightness(configuration.isPressed ? -0.08 : 0)
  }
}

// MARK: - Trail color swatches

/// The preset trail colors as square swatches; the chosen one is ringed.
struct TrailSwatches: View {
  static let presets: [(name: String, color: TrailColor)] = [
    ("Fire", .fire), ("Pink", .pink), ("Cyan", .cyan), ("Lime", .lime), ("Violet", .violet),
  ]

  @Binding var trailColor: TrailColor

  var body: some View {
    HStack(spacing: 6) {
      ForEach(Self.presets, id: \.name) { preset in
        swatch(preset.color, name: preset.name)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Trail color presets")
  }

  private func swatch(_ color: TrailColor, name: String) -> some View {
    let selected = trailColor == color
    return Button { trailColor = color } label: {
      RoundedRectangle(cornerRadius: 2)
        .fill(Color(rgba: ColorRamp(color).main))
        .frame(width: 18, height: 18)
        .padding(3)
        .overlay(
          RoundedRectangle(cornerRadius: SettingsTheme.cornerRadius)
            .strokeBorder(selected ? SettingsTheme.text : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel("\(name) trail")
    .accessibilityValue(selected ? "Selected" : "Not selected")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
