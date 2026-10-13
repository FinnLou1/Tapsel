import AppKit

/// The top edge of some other app's window - a ledge the pet can stand on.
struct Ledge {
    let windowID: CGWindowID
    let rect: CGRect // AppKit screen coordinates (origin bottom-left)

    var topY: CGFloat { rect.maxY }
    var minX: CGFloat { rect.minX }
    var maxX: CGFloat { rect.maxX }
}

/// Reads the on-screen window list to find ledges.
///
/// Only window *geometry* is used, which macOS exposes to any app; window titles
/// would require the Screen Recording permission, so we deliberately never read them.
enum WindowScanner {
    private static let minWidth: CGFloat = 140
    private static let minHeight: CGFloat = 60

    /// Current frame of a single window, in AppKit coordinates. Much cheaper than a
    /// full scan (~0.07ms), so the pet can track the window it rides every frame.
    /// Returns nil once that window is gone, minimised or hidden.
    static func frame(of windowID: CGWindowID) -> CGRect? {
        guard
            let primary = NSScreen.screens.first,
            let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
            let info = list.first,
            (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
            let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
            let x = bounds["X"], let y = bounds["Y"],
            let width = bounds["Width"], let height = bounds["Height"]
        else { return nil }

        return CGRect(x: x, y: primary.frame.maxY - y - height, width: width, height: height)
    }

    static func scan(excluding ownPID: pid_t) -> WindowSurfaces {
        guard
            let primary = NSScreen.screens.first,
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return WindowSurfaces(ledges: [])
        }

        // Quartz window coordinates are top-left based; AppKit's are bottom-left based.
        let flip = primary.frame.maxY

        // CGWindowListCopyWindowInfo returns windows front-to-back, which is exactly
        // the order WindowSurfaces needs for its occlusion checks.
        let ledges: [Ledge] = list.compactMap { info in
            guard
                info[kCGWindowLayer as String] as? Int == 0,
                info[kCGWindowOwnerPID as String] as? pid_t != ownPID,
                (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                let id = info[kCGWindowNumber as String] as? CGWindowID,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                let x = bounds["X"], let y = bounds["Y"],
                let width = bounds["Width"], let height = bounds["Height"],
                width >= minWidth, height >= minHeight
            else { return nil }

            let rect = CGRect(x: x, y: flip - y - height, width: width, height: height)
            return Ledge(windowID: id, rect: rect)
        }

        return WindowSurfaces(ledges: ledges)
    }
}

/// A snapshot of the ledges currently on screen, front-to-back.
struct WindowSurfaces {
    /// Front-to-back: earlier entries are drawn on top of later ones.
    let ledges: [Ledge]

    /// How far from a window's corner the pet has to stay to still look supported.
    static let edgeMargin: CGFloat = 10

    func ledge(_ id: CGWindowID) -> Ledge? {
        ledges.first { $0.windowID == id }
    }

    /// True if the window's top edge is actually visible at `x` - standing on an
    /// edge that's hidden behind another window would look like standing on nothing.
    func isExposed(_ ledge: Ledge, at x: CGFloat) -> Bool {
        guard let index = ledges.firstIndex(where: { $0.windowID == ledge.windowID }) else { return false }
        let probe = CGPoint(x: x, y: ledge.topY - 2)
        for front in ledges[..<index] where front.rect.contains(probe) {
            return false
        }
        return true
    }

    /// True if the pet can stand at `x` on this ledge.
    func canStand(_ ledge: Ledge, at x: CGFloat) -> Bool {
        x >= ledge.minX + Self.edgeMargin
            && x <= ledge.maxX - Self.edgeMargin
            && isExposed(ledge, at: x)
    }

    /// The highest surface crossed while falling from `fromY` down to `toY` at `x`.
    func landing(fallingFrom fromY: CGFloat, to toY: CGFloat, at x: CGFloat, floorY: CGFloat) -> (y: CGFloat, support: PetSupport)? {
        var best: (y: CGFloat, support: PetSupport)?

        if floorY <= fromY, floorY >= toY {
            best = (floorY, .floor)
        }

        for ledge in ledges {
            let top = ledge.topY
            guard top <= fromY, top >= toY, canStand(ledge, at: x) else { continue }
            if best == nil || top > best!.y {
                best = (top, .ledge(ledge.windowID))
            }
        }
        return best
    }

    /// A window edge that is level with a pet climbing a screen edge at `wallX`,
    /// close enough to step across onto. This is how the pet gets up high: walk to
    /// the screen border, climb it, then move onto a window.
    func ledgeFromWall(side: WallSide, wallX: CGFloat, atHeight y: CGFloat, reach: CGFloat) -> (ledge: Ledge, x: CGFloat)? {
        for ledge in ledges {
            guard abs(ledge.topY - y) < 14 else { continue }

            let x: CGFloat
            switch side {
            case .left: x = max(ledge.minX + Self.edgeMargin, wallX + Self.edgeMargin)
            case .right: x = min(ledge.maxX - Self.edgeMargin, wallX - Self.edgeMargin)
            }

            guard abs(x - wallX) <= reach, canStand(ledge, at: x) else { continue }
            return (ledge, x)
        }
        return nil
    }

    /// Ledges the pet could plausibly jump onto from `origin`, with the landing spot.
    func jumpTargets(from origin: CGPoint, maxUp: CGFloat, maxSide: CGFloat) -> [CGPoint] {
        ledges.compactMap { ledge in
            let rise = ledge.topY - origin.y
            guard rise > 40, rise < maxUp else { return nil }
            guard ledge.rect.width > 3 * WindowSurfaces.edgeMargin else { return nil }

            let x = min(max(origin.x, ledge.minX + Self.edgeMargin), ledge.maxX - Self.edgeMargin)
            guard abs(x - origin.x) < maxSide, canStand(ledge, at: x) else { return nil }
            return CGPoint(x: x, y: ledge.topY)
        }
    }
}
