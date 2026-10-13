import AppKit

/// The "real" preferences window: shortcuts, walk speed, which screen to start
/// on, and launch-at-login. Opened from the status bar / pet context menu - this
/// is still a menu-bar-only app with no Dock icon, just one extra window now.
final class SettingsWindowController: NSWindowController {
    private let store: SettingsStore
    private let engine: PetEngine

    private var petThumbnails: [PetThumbnailControl] = []
    private var feedRecorder: ShortcutRecorderControl!
    private var petRecorder: ShortcutRecorderControl!
    private var conflictLabel: NSTextField!
    private var speedSlider: NSSlider!
    private var speedValueLabel: NSTextField!
    private var screenPopup: NSPopUpButton!
    private var loginCheckbox: NSButton!

    init(store: SettingsStore, engine: PetEngine) {
        self.store = store
        self.engine = engine
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "DesktopPet – Einstellungen"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
        refresh()
        // Keeps the highlighted thumbnail in sync if the pet is changed from the
        // status bar / right-click menu while this window happens to be open.
        engine.addStatsListener { [weak self] in self?.refreshPetSelection() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func buildUI() {
        guard let content = window?.contentView else { return }

        petThumbnails = PetKind.allCases.map { kind in
            let control = PetThumbnailControl(kind: kind)
            control.onSelect = { [weak self] selected in
                self?.engine.changeKind(selected)
                self?.refreshPetSelection()
            }
            return control
        }
        let petRow = NSStackView(views: petThumbnails)
        petRow.spacing = 10

        feedRecorder = ShortcutRecorderControl()
        petRecorder = ShortcutRecorderControl()
        feedRecorder.onChange = { [weak self] in self?.apply(feedShortcut: $0) }
        petRecorder.onChange = { [weak self] in self?.apply(petShortcut: $0) }

        conflictLabel = NSTextField(labelWithString: "")
        conflictLabel.font = .systemFont(ofSize: 11)
        conflictLabel.textColor = .systemRed

        speedSlider = NSSlider(value: 1, minValue: 0.5, maxValue: 2.0, target: self, action: #selector(speedChanged))
        speedSlider.widthAnchor.constraint(equalToConstant: 170).isActive = true
        speedValueLabel = NSTextField(labelWithString: "1.0×")
        speedValueLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
        let speedRow = NSStackView(views: [speedSlider, speedValueLabel])
        speedRow.spacing = 8

        screenPopup = NSPopUpButton()
        screenPopup.target = self
        screenPopup.action = #selector(screenChanged)
        let screenHint = NSTextField(labelWithString: "Wirkt beim nächsten Start.")
        screenHint.font = .systemFont(ofSize: 11)
        screenHint.textColor = .secondaryLabelColor
        let screenColumn = NSStackView(views: [screenPopup, screenHint])
        screenColumn.orientation = .vertical
        screenColumn.alignment = .leading
        screenColumn.spacing = 2

        loginCheckbox = NSButton(checkboxWithTitle: "DesktopPet bei der Anmeldung starten", target: self, action: #selector(loginChanged))

        let stack = NSStackView(views: [
            sectionLabel("Haustier"),
            petRow,
            NSBox.separatorRow(),
            sectionLabel("Tastenkürzel"),
            labeledRow("Füttern", feedRecorder),
            labeledRow("Streicheln", petRecorder),
            conflictLabel,
            NSBox.separatorRow(),
            sectionLabel("Verhalten"),
            labeledRow("Lauf-Tempo", speedRow),
            labeledRow("Startbildschirm", screenColumn),
            NSBox.separatorRow(),
            loginCheckbox,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func labeledRow(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .firstBaseline
        return row
    }

    // MARK: - State

    private func refreshPetSelection() {
        for control in petThumbnails {
            control.isSelected = (control.kind == engine.kind)
        }
    }

    private func refresh() {
        refreshPetSelection()
        feedRecorder.shortcut = store.settings.feedShortcut
        petRecorder.shortcut = store.settings.petShortcut
        conflictLabel.stringValue = ""

        speedSlider.doubleValue = store.settings.speedMultiplier
        speedValueLabel.stringValue = String(format: "%.1f×", store.settings.speedMultiplier)

        loginCheckbox.state = store.launchAtLogin ? .on : .off

        screenPopup.removeAllItems()
        for screen in NSScreen.screens {
            guard let id = screen.stableID else { continue }
            let item = NSMenuItem(title: screen.settingsDisplayName, action: nil, keyEquivalent: "")
            item.representedObject = id
            screenPopup.menu?.addItem(item)
        }
        if let preferred = store.settings.preferredScreenID,
           let index = screenPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == preferred }) {
            screenPopup.selectItem(at: index)
        } else {
            screenPopup.selectItem(at: 0)
        }
    }

    // MARK: - Actions

    private func apply(feedShortcut: KeyboardShortcut?) {
        if let feedShortcut, feedShortcut == store.settings.petShortcut {
            conflictLabel.stringValue = "Kürzel wird schon für „Streicheln“ benutzt."
            feedRecorder.shortcut = store.settings.feedShortcut
            return
        }
        conflictLabel.stringValue = ""
        store.update { $0.feedShortcut = feedShortcut }
    }

    private func apply(petShortcut: KeyboardShortcut?) {
        if let petShortcut, petShortcut == store.settings.feedShortcut {
            conflictLabel.stringValue = "Kürzel wird schon für „Füttern“ benutzt."
            petRecorder.shortcut = store.settings.petShortcut
            return
        }
        conflictLabel.stringValue = ""
        store.update { $0.petShortcut = petShortcut }
    }

    @objc private func speedChanged() {
        let value = (speedSlider.doubleValue * 10).rounded() / 10
        speedValueLabel.stringValue = String(format: "%.1f×", value)
        store.update { $0.speedMultiplier = value }
    }

    @objc private func screenChanged() {
        guard let id = screenPopup.selectedItem?.representedObject as? String else { return }
        store.update { $0.preferredScreenID = id }
    }

    @objc private func loginChanged() {
        store.launchAtLogin = loginCheckbox.state == .on
    }
}

private extension NSScreen {
    var settingsDisplayName: String {
        self === NSScreen.main ? "\(localizedName) (Haupt)" : localizedName
    }
}

private extension NSBox {
    static func separatorRow() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
