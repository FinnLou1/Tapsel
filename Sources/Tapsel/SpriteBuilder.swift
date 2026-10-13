import Foundation

/// Builds a `PixelCanvas` frame for a pet procedurally (no image assets needed).
/// Palette indices match `PetKind.palette`: 0 outline, 1 main, 2 shade, 3 belly, 4 pink, 5 pupil.
///
/// Strategy: paint the silhouette (body + ears + tail + feet) in flat color, derive a
/// uniform 1px outline from it via `addingOutline`, *then* add face details on top.
/// Deriving the outline this way (instead of nesting bigger/smaller ellipses) avoids
/// uneven "thick at the poles" borders that flattened ellipses produce.
enum SpriteBuilder {
    /// Square so the sprite can be rotated 90° (wall climbing) without resizing the window.
    static let width = 24
    static let height = 24
    /// Empty cells between the pet's feet and the bottom of the canvas.
    static let bottomPadding = 1

    static func buildFrame(kind: PetKind, behavior: BehaviorState, mood: MoodLevel, tick: Int) -> PixelCanvas {
        var c = PixelCanvas(width: width, height: height)

        let sleeping = behavior == .sleeping
        let eating = behavior == .eating
        let airborne = behavior == .falling
        let climbing = behavior == .climbing
        let moving = behavior == .walk || climbing
        let bounce: Double = (moving && tick % 4 < 2) ? 1 : 0
        let stepLeft = tick % 2 == 0
        let wag = mood == .happy ? (tick % 2 == 0 ? -1.0 : 1.0) : 0.0
        let blink = !sleeping && (tick % 14 == 0)

        let cx = 11.0
        let cy = 15.0 - bounce

        // --- Silhouette: body, ears, tail, feet (flat colors only - no outline yet) ---
        c.fillEllipse(cx: cx, cy: cy, rx: 8.0, ry: 6.5, color: 1)
        c.fillEllipse(cx: cx, cy: cy + 3.0, rx: 6.0, ry: 3.2, color: 2)   // lower-body shadow
        c.fillEllipse(cx: cx, cy: cy + 3.2, rx: 3.2, ry: 2.2, color: 3)  // belly patch

        switch kind {
        case .cat:
            drawTriangleEar(&c, base: (4, 12 + bounce), tip: (6, 6 + bounce))
            drawTriangleEar(&c, base: (18, 12 + bounce), tip: (16, 6 + bounce))
            c.fillEllipse(cx: 17.6, cy: cy + 2.0, rx: 1.9, ry: 1.6, color: 1)
            c.fillEllipse(cx: 19.6, cy: cy + 0.3, rx: 1.6, ry: 1.4, color: 1)
            c.fillEllipse(cx: 20.6, cy: cy - 2.0 + wag * 0.6, rx: 1.2, ry: 1.1, color: 2)
        case .dog:
            c.fillEllipse(cx: 3.0, cy: cy - 0.5, rx: 2.2, ry: 4.2, color: 2)
            c.fillEllipse(cx: 19.0, cy: cy - 0.5, rx: 2.2, ry: 4.2, color: 2)
            c.fillEllipse(cx: 18.4, cy: cy + 1.8, rx: 1.6, ry: 1.9, color: 1)
            c.fillEllipse(cx: 20.4, cy: cy + 0.3 + wag * 0.8, rx: 1.2, ry: 1.4, color: 1)
        case .bunny:
            drawLongEar(&c, cx: 8.0, bounce: bounce, cy: cy)
            drawLongEar(&c, cx: 14.0, bounce: bounce, cy: cy)
            c.fillEllipse(cx: 18.6, cy: cy + 3.0, rx: 1.6, ry: 1.4, color: 3)
        }

        // Feet: alternating steps while moving, splayed out while falling.
        let leftFootDrop = (moving && stepLeft) ? 1 : 0
        let rightFootDrop = (moving && !stepLeft) ? 1 : 0
        let splay = airborne ? 2 : 0
        c.fillRect(x0: 6 - splay, y0: 20 + leftFootDrop - splay, x1: 8 - splay, y1: 21 + leftFootDrop - splay, color: 1)
        c.fillRect(x0: 13 + splay, y0: 20 + rightFootDrop - splay, x1: 15 + splay, y1: 21 + rightFootDrop - splay, color: 1)

        c = c.addingOutline(color: 0)

        // --- Eyes ---
        let eyeY = Int((cy - 1.0).rounded())
        if sleeping || (blink && !airborne) {
            c.fillRect(x0: 7, y0: eyeY, x1: 9, y1: eyeY, color: 0)
            c.fillRect(x0: 13, y0: eyeY, x1: 15, y1: eyeY, color: 0)
        } else {
            let widen = airborne ? 1 : 0 // eyes go wide mid-air
            c.fillRect(x0: 7, y0: eyeY - 1 - widen, x1: 8, y1: eyeY, color: 5)
            c.fillRect(x0: 14, y0: eyeY - 1 - widen, x1: 15, y1: eyeY, color: 5)
        }

        // --- Mouth ---
        let mouthY = Int((cy + 3.5).rounded())
        if eating {
            let openness = tick % 2 == 0 ? 1 : 2
            c.fillRect(x0: 10, y0: mouthY, x1: 12, y1: mouthY + openness, color: 0)
        } else if sleeping {
            c.fillRect(x0: 10, y0: mouthY, x1: 12, y1: mouthY, color: 0)
        } else if airborne {
            c.fillRect(x0: 10, y0: mouthY, x1: 12, y1: mouthY + 1, color: 0) // surprised "o"
        } else {
            switch mood {
            case .happy:
                c.set(9, mouthY, 0); c.set(10, mouthY + 1, 0)
                c.set(11, mouthY + 1, 0); c.set(12, mouthY + 1, 0); c.set(13, mouthY, 0)
            case .sad, .hungry:
                c.set(9, mouthY + 1, 0); c.set(10, mouthY, 0)
                c.set(11, mouthY, 0); c.set(12, mouthY, 0); c.set(13, mouthY + 1, 0)
            case .neutral:
                c.fillRect(x0: 10, y0: mouthY, x1: 12, y1: mouthY, color: 0)
            }
        }

        // --- Zzz while asleep (drawn after outlining so it stays crisp dots) ---
        if sleeping {
            let zOffset = (tick % 20) / 10
            c.set(16, 7 - zOffset, 0)
            c.set(17, 6 - zOffset, 0)
            c.set(18, 5 - zOffset, 0)
        }

        return c
    }

    private static func drawTriangleEar(_ c: inout PixelCanvas, base: (Double, Double), tip: (Double, Double)) {
        let mirrored = tip.0 < base.0
        let dx = mirrored ? -4.4 : 4.4
        let p0 = base
        let p1 = (base.0 + dx, base.1)
        let p2 = tip
        c.fillTriangle(p0, p1, p2, color: 1)
        let innerP0 = (p0.0 * 0.30 + p2.0 * 0.70, p0.1 * 0.30 + p2.1 * 0.70)
        let innerP1 = (p1.0 * 0.30 + p2.0 * 0.70, p1.1 * 0.30 + p2.1 * 0.70)
        c.fillTriangle(innerP0, innerP1, p2, color: 4)
    }

    private static func drawLongEar(_ c: inout PixelCanvas, cx: Double, bounce: Double, cy: Double) {
        c.fillEllipse(cx: cx, cy: 5.6 + bounce, rx: 1.5, ry: 4.9, color: 1)
        c.fillEllipse(cx: cx, cy: 6.0 + bounce, rx: 0.7, ry: 3.6, color: 4)
    }
}
