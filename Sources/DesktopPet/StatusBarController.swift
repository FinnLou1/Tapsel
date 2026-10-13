import AppKit

/// The menu bar item: a monochrome species icon (template image, so it adapts to
/// light/dark menu bars) plus the shared pet menu.
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menuBuilder: PetMenuBuilder!
    private weak var engine: PetEngine?
    private var currentSymbolName: String?

    func setup(engine: PetEngine, menuBuilder: PetMenuBuilder) {
        self.engine = engine
        self.menuBuilder = menuBuilder

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        engine.addStatsListener { [weak self] in self?.refreshButton() }
        refreshButton()
    }

    /// Rebuild right before the menu opens, so hunger/mood are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menuBuilder.populate(menu)
    }

    private func refreshButton() {
        guard let engine, let button = statusItem.button else { return }

        button.toolTip = "\(engine.kind.displayName) · \(engine.statusDescription)"

        let symbolName = engine.kind.symbolName
        guard symbolName != currentSymbolName else { return }
        currentSymbolName = symbolName

        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: engine.kind.displayName)
            ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "DesktopPet")

        if let image = image?.withSymbolConfiguration(configuration) {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.title = "Pet"
        }
    }
}
