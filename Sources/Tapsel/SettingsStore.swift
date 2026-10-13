import AppKit
import ServiceManagement

/// Persisted user preferences - kept separate from `PetSaveData` (hunger/mood/kind)
/// so resetting one never touches the other.
struct AppSettings: Codable, Equatable {
    var feedShortcut: KeyboardShortcut? = .feedDefault
    var petShortcut: KeyboardShortcut? = .petDefault
    var speedMultiplier: Double = 1.0
    /// `NSScreen.stableID` of the screen the pet should spawn on at next launch.
    /// `nil` means "whatever `NSScreen.main` is".
    var preferredScreenID: String?

    static let defaultsKey = "Tapsel.Settings.v1"

    static func load() -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

/// Owns the persisted settings and notifies listeners (the menu, the hotkeys, the
/// engine) whenever something changes.
final class SettingsStore {
    private(set) var settings: AppSettings
    private var listeners: [(AppSettings) -> Void] = []

    init() { settings = AppSettings.load() }

    func addListener(_ callback: @escaping (AppSettings) -> Void) { listeners.append(callback) }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        guard copy != settings else { return }
        settings = copy
        settings.save()
        listeners.forEach { $0(settings) }
    }

    /// Bridges to `SMAppService` rather than storing a bool: the OS is the source
    /// of truth here (the user can remove the login item in System Settings
    /// without this app knowing), so this always reflects live status.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Tapsel: launch-at-login toggle failed: \(error)")
            }
        }
    }
}

extension NSScreen {
    /// A stable-enough identifier for "which physical display is this", used to
    /// remember a preferred starting screen across launches. `CGDirectDisplayID`
    /// can in principle change after a GPU/driver change, but is stable across
    /// ordinary app restarts, which is all this needs.
    var stableID: String? {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
        return String(id)
    }
}
