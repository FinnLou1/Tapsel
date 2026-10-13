import AppKit

/// Builds the menu used both by the menu bar item and by right-clicking the pet,
/// so the two can never drift apart.
final class PetMenuBuilder: NSObject {
    // Strong on purpose: the engine never references the builder back, so there's
    // no cycle, and this keeps the builder usable without an owning controller.
    private let engine: PetEngine
    private let settingsStore: SettingsStore

    var onQuit: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(engine: PetEngine, settingsStore: SettingsStore) {
        self.engine = engine
        self.settingsStore = settingsStore
        super.init()
    }

    /// Fills an existing menu - used by the status item, which reuses one menu
    /// and refreshes it right before it opens.
    func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(headerItem())
        menu.addItem(statItem("Hunger", percent: engine.hungerPercent))
        menu.addItem(statItem("Laune", percent: engine.happinessPercent))
        menu.addItem(statItem("Energie", percent: engine.energyPercent))
        menu.addItem(.separator())

        menu.addItem(actionItem("Füttern", #selector(feedAction), shortcut: settingsStore.settings.feedShortcut, symbol: "fork.knife"))
        menu.addItem(actionItem("Streicheln", #selector(petAction), shortcut: settingsStore.settings.petShortcut, symbol: "hand.raised.fill"))
        menu.addItem(.separator())

        menu.addItem(kindItem())
        menu.addItem(.separator())

        menu.addItem(actionItem("Einstellungen…", #selector(openSettings), key: ",", symbol: "gearshape"))
        menu.addItem(actionItem("Über Tapsel", #selector(showAbout), key: "", symbol: nil))
        menu.addItem(actionItem("Tapsel beenden", #selector(quitAction), key: "q", symbol: nil))
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu)
        return menu
    }

    // MARK: - Items

    private func headerItem() -> NSMenuItem {
        let item = NSMenuItem()
        let title = NSMutableAttributedString(
            string: engine.kind.displayName,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        title.append(NSAttributedString(
            string: "  ·  " + engine.statusDescription,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        item.attributedTitle = title
        item.isEnabled = false
        return item
    }

    /// A read-only "Hunger    72 %" row, value right-aligned on a tab stop.
    private func statItem(_ label: String, percent: Int) -> NSMenuItem {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 160)]

        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(
            string: "\(label)\t\(percent) %",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String, symbol: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    /// Same as above, but for actions whose shortcut comes from the settings
    /// window instead of being hard-coded - the menu hint always matches whatever
    /// is actually registered as the global hotkey.
    private func actionItem(_ title: String, _ action: Selector, shortcut: KeyboardShortcut?, symbol: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut?.displayCharacters.lowercased() ?? "")
        item.target = self
        item.keyEquivalentModifierMask = shortcut?.cocoaModifierFlags ?? []
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    private func kindItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Haustier", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for kind in PetKind.allCases {
            let sub = NSMenuItem(title: kind.displayName, action: #selector(selectKind(_:)), keyEquivalent: "")
            sub.target = self
            sub.representedObject = kind.rawValue
            sub.state = (kind == engine.kind) ? .on : .off
            sub.image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil)
            submenu.addItem(sub)
        }
        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    @objc private func feedAction() { engine.feed() }
    @objc private func petAction() { engine.pet() }
    @objc private func quitAction() { onQuit?() }
    @objc private func openSettings() { onOpenSettings?() }

    @objc private func selectKind(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = PetKind(rawValue: raw) else { return }
        engine.changeKind(kind)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Tapsel",
            .applicationVersion: "0.6.0",
            .credits: NSAttributedString(
                string: "Ein kleines Pixel-Haustier für deinen Schreibtisch.",
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ),
        ])
    }
}
