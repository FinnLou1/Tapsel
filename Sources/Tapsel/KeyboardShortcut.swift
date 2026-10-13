import AppKit
import Carbon

/// A user-configurable keyboard shortcut: a hardware key code plus modifier flags,
/// stored in Carbon's shape (`RegisterEventHotKey` wants exactly this) so
/// `GlobalHotKeyManager` can hand it over unchanged.
struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier mask: cmdKey / optionKey / controlKey / shiftKey
    /// The character shown to the user, captured once at record time (upper-cased).
    /// Carbon shortcuts match by key code, not character, so this exists purely for display.
    var displayCharacters: String

    static let feedDefault = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey), displayCharacters: "F")
    static let petDefault = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey), displayCharacters: "S")

    init(keyCode: UInt32, modifiers: UInt32, displayCharacters: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayCharacters = displayCharacters
    }

    /// Builds a shortcut from a raw key-down while recording in the settings window.
    /// Requires at least one modifier and a real character, so it can never collide
    /// with normal typing elsewhere in the system.
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }

        var carbon: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        guard carbon != 0 else { return nil }

        let characters = (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !characters.isEmpty else { return nil }

        keyCode = UInt32(event.keyCode)
        modifiers = carbon
        displayCharacters = characters
    }

    /// e.g. "⌃⇧⌘F" — used by the recorder control.
    var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + displayCharacters
    }

    /// For wiring the same shortcut into an `NSMenuItem`'s `keyEquivalent`, so the
    /// hint shown in the menu always matches what's actually registered.
    var cocoaModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }
}
