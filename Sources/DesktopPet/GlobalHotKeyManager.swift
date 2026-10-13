import AppKit
import Carbon

/// System-wide keyboard shortcuts via Carbon's `RegisterEventHotKey` - the
/// classic, permission-free way to do this. A global `NSEvent` monitor would work
/// too, but only after the user grants Input Monitoring access; registering a
/// specific hotkey needs no entitlement at all, which fits this app's "no special
/// permissions" approach (see the README).
final class GlobalHotKeyManager {
    enum Slot: UInt32 {
        case feed = 1
        case pet = 2
    }

    private static let signature: OSType = 0x4450_6574 // "DPet"
    private static var refs: [Slot: EventHotKeyRef] = [:]
    private static var actions: [UInt32: () -> Void] = [:]
    private static var eventHandler: EventHandlerRef?

    private init() {}

    /// Registers `shortcut` for `slot`, replacing whatever was registered before.
    /// Pass `shortcut: nil` to leave the slot unregistered (the user cleared it).
    static func register(_ slot: Slot, shortcut: KeyboardShortcut?, action: @escaping () -> Void) {
        installHandlerIfNeeded()

        if let existing = refs[slot] {
            UnregisterEventHotKey(existing)
            refs[slot] = nil
        }
        actions[slot.rawValue] = action

        guard let shortcut else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: slot.rawValue)
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref {
            refs[slot] = ref
        }
    }

    private static func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            GlobalHotKeyManager.actions[hotKeyID.id]?()
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
