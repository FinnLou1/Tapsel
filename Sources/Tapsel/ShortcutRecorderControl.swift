import AppKit

/// A small "click, then press a key combo" control, like the hotkey recorders in
/// System Settings. AppKit has no built-in version of this, so it's a from-scratch
/// `NSView`: clicking starts recording, the next key-down (with at least one
/// modifier) becomes the new shortcut, Esc cancels, Delete/Backspace clears to
/// "no shortcut".
final class ShortcutRecorderControl: NSView {
    var shortcut: KeyboardShortcut? {
        didSet { needsDisplay = true }
    }
    var onChange: ((KeyboardShortcut?) -> Void)?

    private var isRecording = false {
        didSet { needsDisplay = true }
    }
    private var localMonitor: Any?

    override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 24) }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.quaternaryLabelColor.withAlphaComponent(0.25)).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording ? "Taste drücken…" : (shortcut?.displayString ?? "Kein Kürzel")
        let color: NSColor = isRecording ? .controlAccentColor : (shortcut == nil ? .tertiaryLabelColor : .labelColor)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: isRecording ? .regular : .medium),
            .foregroundColor: color,
        ]
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        text.draw(at: point, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return true
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.handle(event)
            return nil // consumed by the recorder, never reaches the rest of the app
        }
    }

    private func endRecording() {
        isRecording = false
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        defer { endRecording() }

        if event.keyCode == 53 { return } // Esc: cancel, keep the old value
        if event.keyCode == 51 || event.keyCode == 117 { // Delete / Forward Delete
            shortcut = nil
            onChange?(nil)
            return
        }
        guard let new = KeyboardShortcut(event: event) else { return } // no modifier / no character: ignore
        shortcut = new
        onChange?(new)
    }
}
