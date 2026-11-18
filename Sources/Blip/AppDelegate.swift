import AppKit
import BlipCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private var store: SettingsStore?
  private var settingsWindow: SettingsWindowController?
  private var onboarding: OnboardingWindowController?
  private var summon: SummonController?
  private var pool: BrainPool?
  /// The chat of the summon in progress, if any.
  private var conversation: Conversation?
  private var sounds: SoundPlayer?
  private var hotKeys: HotKeyCenter?
  /// Debug aids: `kill -USR1 <pid>` does what the shortcut does; `kill -USR2 <pid>` opens Settings.
  private var signalSources: [DispatchSourceSignal] = []
  /// A pending `BrainPool.settingsChanged()`, held back while the owner is still typing.
  private var brainRestart: DispatchWorkItem?
  /// Seconds of quiet after a change to the assistant's settings before the standby restarts with them.
  private static let brainRestartDelay: TimeInterval = 0.6

  func applicationDidFinishLaunching(_ notification: Notification) {
    let store = SettingsStore()
    self.store = store
    let settings = { [store] in store.settings }
    let pool = BrainPool(settings: settings)
    self.pool = pool
    let summon = SummonController(settings: settings)
    self.summon = summon
    let sounds = SoundPlayer(settings: settings)
    self.sounds = sounds
    summon.onSummoned = { [weak self, weak summon] screen in
      guard let self else { return }
      sounds.play(Chiptune.launch)
      let conversation = Conversation(pool: pool, settings: settings(), screen: screen)
      conversation.onThinkingChanged = { [weak self, weak summon, weak conversation] thinking in
        guard let conversation, self?.conversation === conversation else { return }
        summon?.thinking = thinking
      }
      conversation.onReplyStarted = { [weak self, weak conversation] in
        guard let conversation, self?.conversation === conversation else { return }
        sounds.play(Chiptune.reply)
      }
      self.conversation = conversation
      SummonTiming.log(String(format: "summon: chat ready %.1f ms after the shortcut",
                              (CACurrentMediaTime() - (summon?.pressedAt ?? 0)) * 1000))
    }
    summon.onArrived = { [weak self, weak summon] screen, anchor in
      self?.conversation?.shipArrived(on: screen, anchor: anchor, shipHalfWidth: summon?.shipHalfWidth ?? 0)
    }
    summon.onAnchorMoved = { [weak self, weak summon] screen, anchor in
      self?.conversation?.shipMoved(on: screen, anchor: anchor, shipHalfWidth: summon?.shipHalfWidth ?? 0)
    }
    // The chat leaves with the fly-off; a summon replaced without one is closed when it ends.
    summon.onFlyOff = { [weak self, weak summon] in
      sounds.play(Chiptune.flyOff)
      summon?.thinking = false  // a reply cut off by the fly-off is no longer being thought about
      self?.endConversation()
    }
    summon.onDismissed = { [weak self] in self?.endConversation() }
    hotKeys = HotKeyCenter(hotKey: store.settings.hotKey) { [weak self] in
      MainActor.assumeIsolated { self?.summonPressed() }
    }
    let shortcut = ShortcutHooks(
      recordingChanged: { [weak self] recording in
        guard let self, let store = self.store else { return }
        if recording { self.hotKeys?.suspend() } else { self.hotKeys?.update(store.settings.hotKey) }
      },
      register: { [weak self] hotKey in self?.hotKeys?.update(hotKey) ?? false })
    settingsWindow = SettingsWindowController(store: store, shortcut: shortcut)
    store.onChange = { [weak self] old, new in self?.settingsChanged(from: old, to: new) }
    LoginItem.matchAtFirstLaunch(store.settings.launchAtLogin)

    onSignal(SIGUSR1) { [weak self] in self?.summonPressed() }
    onSignal(SIGUSR2) { [weak self] in self?.openSettings() }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Blip")
    let menu = NSMenu()
    let summonItem = NSMenuItem(title: "Summon", action: #selector(summonPressed), keyEquivalent: "")
    summonItem.target = self
    menu.addItem(summonItem)
    let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    menu.addItem(settingsItem)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit Blip",
                            action: #selector(NSApplication.terminate(_:)),
                            keyEquivalent: "q"))
    item.menu = menu
    statusItem = item

    let onboarding = OnboardingWindowController(store: store)
    self.onboarding = onboarding
    onboarding.showIfFirstLaunch()
  }

  func applicationWillTerminate(_ notification: Notification) {
    MainActor.assumeIsolated {
      // Shut the pool first, so ending the conversation does not start a standby only to kill it.
      pool?.shutdown()
      endConversation()
    }
  }

  @MainActor @objc private func summonPressed() {
    let pressedAt = CACurrentMediaTime()
    flushBrainRestart()  // so a summon right after a name or personality change already uses it
    summon?.shortcutPressed(at: pressedAt)
    SummonTiming.log(String(format: "shortcut: main thread held %.1f ms", (CACurrentMediaTime() - pressedAt) * 1000))
  }

  /// Runs a pending standby restart now instead of after the quiet period.
  @MainActor private func flushBrainRestart() {
    guard let restart = brainRestart, !restart.isCancelled else { return }
    restart.cancel()
    brainRestart = nil
    pool?.settingsChanged()
  }

  @MainActor @objc private func openSettings() {
    settingsWindow?.show()
  }

  /// Applies a settings change at once. Look and motion need nothing here: the next summon reads them.
  @MainActor private func settingsChanged(from old: BlipSettings, to new: BlipSettings) {
    if new.hotKey != old.hotKey { hotKeys?.update(new.hotKey) }
    if new.launchAtLogin != old.launchAtLogin { LoginItem.set(new.launchAtLogin) }
    if new.name != old.name || new.personality != old.personality || new.answers != old.answers
      || new.model != old.model || new.claudePath != old.claudePath {
      brainRestart?.cancel()
      let restart = DispatchWorkItem { [weak self] in
        self?.brainRestart = nil
        self?.pool?.settingsChanged()
      }
      brainRestart = restart
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.brainRestartDelay, execute: restart)
    }
  }

  private func onSignal(_ number: Int32, _ handler: @escaping @MainActor () -> Void) {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler { MainActor.assumeIsolated { handler() } }
    source.resume()
    signalSources.append(source)
  }

  @MainActor private func endConversation() {
    conversation?.close()
    conversation = nil
  }
}

/// Blip as a login item of the owner's account.
enum LoginItem {
  /// Whether Blip is set to start at login right now, as macOS sees it. Waiting for the owner's
  /// approval in System Settings counts as on.
  static var isOn: Bool {
    let status = SMAppService.mainApp.status
    return status == .enabled || status == .requiresApproval
  }

  /// macOS holds the login item until the owner allows it in System Settings.
  static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

  /// Set once registration has been made to match the setting, so a later launch never undoes a
  /// change the owner made in System Settings.
  private static let matchedKey = "loginItemMatched"

  /// On the first launch, registers or unregisters Blip to match the setting.
  static func matchAtFirstLaunch(_ on: Bool) {
    guard !UserDefaults.standard.bool(forKey: matchedKey) else { return }
    set(on)
    UserDefaults.standard.set(true, forKey: matchedKey)
  }

  /// Registers or unregisters Blip. A failure is logged, never shown.
  static func set(_ on: Bool) {
    let service = SMAppService.mainApp
    do {
      if on {
        if service.status != .enabled { try service.register() }
      } else {
        if service.status != .notRegistered { try service.unregister() }
      }
    } catch {
      NSLog("Blip: could not \(on ? "register" : "unregister") the login item (\(error))")
    }
    if on && service.status == .requiresApproval {
      NSLog("Blip: the login item waits for approval in System Settings > General > Login Items")
    }
  }
}
