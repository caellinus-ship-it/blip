import AppKit
import BlipCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private var summon: SummonController?
  private var pool: BrainPool?
  /// The chat of the summon in progress, if any.
  private var conversation: Conversation?
  private var hotKeys: HotKeyCenter?
  /// Debug aid: `kill -USR1 <pid>` does what the shortcut does.
  private var usr1Source: DispatchSourceSignal?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let settings = { BlipSettings() }
    let pool = BrainPool(settings: settings)
    self.pool = pool
    let summon = SummonController(settings: settings)
    self.summon = summon
    summon.onSummoned = { [weak self, weak summon] screen in
      guard let self else { return }
      let conversation = Conversation(pool: pool, settings: settings(), screen: screen)
      conversation.onThinkingChanged = { [weak self, weak summon, weak conversation] thinking in
        guard let conversation, self?.conversation === conversation else { return }
        summon?.thinking = thinking
      }
      self.conversation = conversation
    }
    summon.onArrived = { [weak self, weak summon] screen, anchor in
      self?.conversation?.shipArrived(on: screen, anchor: anchor, shipHalfWidth: summon?.shipHalfWidth ?? 0)
    }
    summon.onAnchorMoved = { [weak self, weak summon] screen, anchor in
      self?.conversation?.shipMoved(on: screen, anchor: anchor, shipHalfWidth: summon?.shipHalfWidth ?? 0)
    }
    // The chat leaves with the fly-off; a summon replaced without one is closed when it ends.
    summon.onFlyOff = { [weak self] in self?.endConversation() }
    summon.onDismissed = { [weak self] in self?.endConversation() }
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

  func applicationWillTerminate(_ notification: Notification) {
    MainActor.assumeIsolated {
      endConversation()
      pool?.shutdown()
    }
  }

  @MainActor @objc private func summonPressed() {
    summon?.shortcutPressed()
  }

  @MainActor private func endConversation() {
    conversation?.close()
    conversation = nil
  }
}
