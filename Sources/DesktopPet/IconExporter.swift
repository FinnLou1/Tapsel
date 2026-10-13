import AppKit

/// Renders a pixel-art frame to a big PNG, used only to generate the app icon
/// at build time (`DesktopPet --export-icon <path>`). Keeps the icon visually
/// consistent with the pet itself instead of needing separate artwork.
enum IconExporter {
    static func export(to path: String, kind: PetKind = .cat, behavior: BehaviorState = .idle, mood: MoodLevel = .happy, tick: Int = 1) {
        let canvas = SpriteBuilder.buildFrame(kind: kind, behavior: behavior, mood: mood, tick: tick)
        let size = 1024

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            FileHandle.standardError.write("IconExporter: could not create bitmap context\n".data(using: .utf8)!)
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.setAllowsAntialiasing(false)
        ctx.cgContext.interpolationQuality = .none
        NSColor.clear.setFill()
        CGRect(x: 0, y: 0, width: size, height: size).fill()

        let scale = Double(size) / Double(max(canvas.width, canvas.height))
        let renderedHeight = Double(canvas.height) * scale
        let yOffset = (Double(size) - renderedHeight) / 2.0
        let palette = kind.palette

        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                let idx = canvas.get(x, y)
                guard idx >= 0, Int(idx) < palette.count else { continue }
                let x0 = (Double(x) * scale).rounded()
                let x1 = (Double(x + 1) * scale).rounded()
                let rowFromTop = canvas.height - 1 - y
                let y0 = (yOffset + Double(rowFromTop) * scale).rounded()
                let y1 = (yOffset + Double(rowFromTop + 1) * scale).rounded()
                let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                palette[Int(idx)].setFill()
                rect.fill()
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        print("Icon written to \(path)")
    }
}
