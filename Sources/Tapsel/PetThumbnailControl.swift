import AppKit

/// A clickable preview tile showing one `PetKind`'s actual pixel sprite (the same
/// frame data `PetView` draws on the desktop, just smaller) plus its name - used
/// by the settings window so picking a pet is a visual choice, not a text menu.
final class PetThumbnailControl: NSView {
    let kind: PetKind
    var onSelect: ((PetKind) -> Void)?

    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }

    private let canvas: PixelCanvas
    private static let pixelScale: CGFloat = 3
    private static let cardSize = NSSize(width: 92, height: 104)

    init(kind: PetKind) {
        self.kind = kind
        canvas = SpriteBuilder.buildFrame(kind: kind, behavior: .idle, mood: .happy, tick: 0)
        super.init(frame: NSRect(origin: .zero, size: Self.cardSize))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var intrinsicContentSize: NSSize { Self.cardSize }

    override func draw(_ dirtyRect: NSRect) {
        let cardPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
        (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.quaternaryLabelColor.withAlphaComponent(0.18)).setFill()
        cardPath.fill()
        if isSelected {
            NSColor.controlAccentColor.setStroke()
            cardPath.lineWidth = 2
            cardPath.stroke()
        }

        let palette = kind.palette
        let scale = Self.pixelScale
        let spriteWidth = CGFloat(canvas.width) * scale
        let spriteHeight = CGFloat(canvas.height) * scale
        let originX = (bounds.width - spriteWidth) / 2
        let originY = (bounds.height - spriteHeight) / 2 + 9 // leaves room for the label below

        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                let value = canvas.get(x, y)
                guard value >= 0, Int(value) < palette.count else { continue }
                let rectY = originY + CGFloat(canvas.height - 1 - y) * scale
                let rect = NSRect(x: originX + CGFloat(x) * scale, y: rectY, width: scale, height: scale)
                palette[Int(value)].setFill()
                rect.fill()
            }
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: isSelected ? .semibold : .regular),
            .foregroundColor: isSelected ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let labelSize = kind.displayName.size(withAttributes: attrs)
        kind.displayName.draw(at: NSPoint(x: (bounds.width - labelSize.width) / 2, y: 8), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(kind)
    }
}
