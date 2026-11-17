import AppKit
import BlipCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private var summon: SummonController?
  private var hotKeys: HotKeyCenter?
  /// Debug aid: `kill -USR1 <pid>` does what the shortcut does.
  private var usr1Source: DispatchSourceSignal?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let summon = SummonController(settings: { BlipSettings() })
    self.summon = summon
    hotKeys = HotKeyCenter(hotKey: .commandEscape) { [weak self] in
      MainActor.assumeIsolated { self?.summonPressed() }
    }

    signal(SIGUSR1, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.summonPressed() }
    }
    source.resume()
    usr1Source = source

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Blip")
    let menu = NSMenu()
    let summonItem = NSMenuItem(title: "Summon", action: #selector(summonPressed), keyEquivalent: "")
    summonItem.target = self
    menu.addItem(summonItem)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit Blip",
                            action: #selector(NSApplication.terminate(_:)),
                            keyEquivalent: "q"))
    item.menu = menu
    statusItem = item
  }

  @MainActor @objc private func summonPressed() {
    summon?.shortcutPressed()
  }
}
