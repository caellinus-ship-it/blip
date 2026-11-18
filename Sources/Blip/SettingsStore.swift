import BlipCore
import Foundation

/// The one source of truth for the owner's settings. Loads them from `UserDefaults` (JSON under the
/// key `settings`) and saves them on every change.
@MainActor final class SettingsStore: ObservableObject {
  static let key = "settings"

  @Published var settings: BlipSettings {
    didSet {
      guard settings != oldValue else { return }
      save()
      onChange?(oldValue, settings)
    }
  }

  /// Called after every change with the old and the new settings.
  var onChange: ((_ old: BlipSettings, _ new: BlipSettings) -> Void)?

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    settings = Self.load(from: defaults)
  }

  /// The saved settings, or the defaults when nothing is saved or what is saved cannot be read.
  private static func load(from defaults: UserDefaults) -> BlipSettings {
    guard let data = defaults.data(forKey: key) else { return BlipSettings() }
    do {
      return try JSONDecoder().decode(BlipSettings.self, from: data)
    } catch {
      NSLog("Blip: saved settings could not be read, using the defaults (\(error))")
      return BlipSettings()
    }
  }

  private func save() {
    do {
      defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
    } catch {
      NSLog("Blip: settings could not be saved (\(error))")
    }
  }
}
