import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let petWindowController: PetWindowController
    private let statusBarController = StatusBarController()
    private var menuBuilder: PetMenuBuilder!
    private var settingsWindowController: SettingsWindowController!

    override init() {
        petWindowController = PetWindowController(settingsStore: settingsStore)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, no app menu, just the pet + status item.
        NSApp.setActivationPolicy(.accessory)

        let engine = petWindowController.engine
        menuBuilder = PetMenuBuilder(engine: engine, settingsStore: settingsStore)
        menuBuilder.onQuit = { NSApp.terminate(nil) }

        settingsWindowController = SettingsWindowController(store: settingsStore, engine: engine)
        menuBuilder.onOpenSettings = { [weak self] in self?.settingsWindowController.show() }

        petWindowController.setup(menuBuilder: menuBuilder)
        statusBarController.setup(engine: engine, menuBuilder: menuBuilder)

        applySettings(settingsStore.settings, engine: engine)
        settingsStore.addListener { [weak self] settings in self?.applySettings(settings, engine: engine) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        petWindowController.teardown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Re-registers the global hotkeys and pushes the walk speed into the engine -
    /// called once at launch and again every time the settings window changes
    /// something, so changes apply immediately without a restart.
    private func applySettings(_ settings: AppSettings, engine: PetEngine) {
        GlobalHotKeyManager.register(.feed, shortcut: settings.feedShortcut) { engine.feed() }
        GlobalHotKeyManager.register(.pet, shortcut: settings.petShortcut) { engine.pet() }
        engine.setSpeedMultiplier(settings.speedMultiplier)
    }
}
