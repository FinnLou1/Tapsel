import AppKit

/// Owns the borderless, transparent, always-on-top window the pet lives in.
final class PetWindowController: NSObject {
    let engine: PetEngine
    private var window: NSWindow!
    private var petView: PetView!
    private var lastOrigin: CGPoint = .zero
    private var lastFrameRevision = -1
    private var tickCount = 0

    init(settingsStore: SettingsStore) {
        engine = PetEngine(settings: settingsStore.settings)
        super.init()
    }

    func setup(menuBuilder: PetMenuBuilder) {
        let rect = NSRect(origin: engine.windowOrigin, size: engine.windowSize)
        let win = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        win.isMovableByWindowBackground = false
        win.ignoresMouseEvents = false

        let view = PetView(frame: NSRect(origin: .zero, size: engine.windowSize))
        view.engine = engine
        view.menuBuilder = menuBuilder
        win.contentView = view

        window = win
        petView = view

        engine.addFrameListener { [weak self] in
            guard let self else { return }

            self.tickCount &+= 1

            // Only touch the window/view when something actually changed - this
            // runs 60x a second.
            if self.engine.needsPreciseTracking || self.tickCount % 2 == 0 {
                let origin = self.engine.windowOrigin
                if origin != self.lastOrigin {
                    self.lastOrigin = origin
                    self.window.setFrameOrigin(origin)
                }
            }
            if self.engine.frameRevision != self.lastFrameRevision {
                self.lastFrameRevision = self.engine.frameRevision
                self.petView.needsDisplay = true
            }

            // Hit-testing the cursor queries the window server, and 15x a second is
            // plenty responsive - no need to do it on every physics frame.
            if self.tickCount % 4 == 0 { self.updateClickThrough() }
        }
        engine.addStatsListener { [weak self] in
            self?.petView.needsDisplay = true
        }

        win.orderFrontRegardless()
        engine.start()
    }

    /// The window is a square box that is mostly empty, so let clicks through
    /// unless the cursor is actually over the pet. Polling at the frame rate keeps
    /// this permission-free (a global event monitor would be overkill here).
    private func updateClickThrough() {
        guard !engine.isDragging else {
            if window.ignoresMouseEvents { window.ignoresMouseEvents = false }
            return
        }
        let overPet = petView.isSolidPixel(atScreenPoint: NSEvent.mouseLocation)
        if window.ignoresMouseEvents == overPet {
            window.ignoresMouseEvents = !overPet
        }
    }

    func teardown() {
        engine.stop()
    }
}
