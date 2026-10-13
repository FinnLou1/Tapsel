import AppKit

/// Draws the current pixel-art frame and handles dragging / the right-click menu.
final class PetView: NSView {
    static let pixelScale = 8

    var engine: PetEngine!
    var menuBuilder: PetMenuBuilder?

    private var dragStartScreenPoint: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero
    private var didDragSignificantly = false

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let engine else { return }
        NSColor.clear.set()
        dirtyRect.fill(using: .sourceOver)

        let canvas = engine.currentFrame()
        let palette = engine.kind.palette
        let scale = CGFloat(Self.pixelScale)

        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                let idx = canvas.get(x, y)
                guard idx >= 0, Int(idx) < palette.count else { continue }
                let rectY = CGFloat(canvas.height - 1 - y) * scale
                let rect = NSRect(x: CGFloat(x) * scale, y: rectY, width: scale, height: scale)
                palette[Int(idx)].setFill()
                rect.fill()
            }
        }
    }

    // MARK: - Dragging (left click picks the pet up; a small click instead pets it)

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStartScreenPoint = NSEvent.mouseLocation
        dragStartWindowOrigin = window.frame.origin
        didDragSignificantly = false
        engine.beginDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStartScreenPoint.x
        let dy = current.y - dragStartScreenPoint.y
        if abs(dx) > 3 || abs(dy) > 3 { didDragSignificantly = true }
        let newOrigin = NSPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy)
        window.setFrameOrigin(newOrigin)
        engine.dragTo(windowOrigin: newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        guard let window else { return }
        engine.endDrag(windowOrigin: window.frame.origin)
        if !didDragSignificantly {
            engine.pet()
        }
        needsDisplay = true
    }

    // MARK: - Context menu

    override func rightMouseDown(with event: NSEvent) {
        guard let menuBuilder else { return }
        NSMenu.popUpContextMenu(menuBuilder.makeMenu(), with: event, for: self)
    }

    // MARK: - Hit testing

    /// Is there actually a pet pixel under this screen point? The window is a
    /// square box that is mostly transparent, so clicks on empty space must fall
    /// through to whatever is underneath.
    func isSolidPixel(atScreenPoint screenPoint: NSPoint) -> Bool {
        guard let window, engine != nil else { return false }
        let viewPoint = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        guard bounds.contains(viewPoint) else { return false }

        let canvas = engine.currentFrame()
        let scale = CGFloat(Self.pixelScale)
        let cellX = Int(viewPoint.x / scale)
        let cellY = canvas.height - 1 - Int(viewPoint.y / scale)

        // Accept a one-cell halo so the pet stays easy to grab.
        for dy in -1...1 {
            for dx in -1...1 where canvas.get(cellX + dx, cellY + dy) >= 0 {
                return true
            }
        }
        return false
    }
}
