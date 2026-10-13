import Foundation

/// A tiny grid of palette indices that we render as chunky "pixel art".
/// `-1` means transparent, everything else indexes into a pet's color palette.
struct PixelCanvas: Equatable {
    let width: Int
    let height: Int
    private(set) var pixels: [Int8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = [Int8](repeating: -1, count: width * height)
    }

    mutating func set(_ x: Int, _ y: Int, _ color: Int8) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        pixels[y * width + x] = color
    }

    func get(_ x: Int, _ y: Int) -> Int8 {
        guard x >= 0, x < width, y >= 0, y < height else { return -1 }
        return pixels[y * width + x]
    }

    mutating func fillRect(x0: Int, y0: Int, x1: Int, y1: Int, color: Int8) {
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                set(x, y, color)
            }
        }
    }

    /// Filled ellipse using the standard normalized-distance test, rasterized to whole pixels.
    mutating func fillEllipse(cx: Double, cy: Double, rx: Double, ry: Double, color: Int8) {
        guard rx > 0, ry > 0 else { return }
        let xMin = Int((cx - rx).rounded(.down))
        let xMax = Int((cx + rx).rounded(.up))
        let yMin = Int((cy - ry).rounded(.down))
        let yMax = Int((cy + ry).rounded(.up))
        guard xMin <= xMax, yMin <= yMax else { return }
        for y in yMin...yMax {
            for x in xMin...xMax {
                let nx = (Double(x) + 0.5 - cx) / rx
                let ny = (Double(y) + 0.5 - cy) / ry
                if nx * nx + ny * ny <= 1.0 {
                    set(x, y, color)
                }
            }
        }
    }

    /// Filled triangle via barycentric sign test - used for ears etc.
    mutating func fillTriangle(_ p0: (Double, Double), _ p1: (Double, Double), _ p2: (Double, Double), color: Int8) {
        let xMin = Int(min(p0.0, p1.0, p2.0).rounded(.down))
        let xMax = Int(max(p0.0, p1.0, p2.0).rounded(.up))
        let yMin = Int(min(p0.1, p1.1, p2.1).rounded(.down))
        let yMax = Int(max(p0.1, p1.1, p2.1).rounded(.up))
        guard xMin <= xMax, yMin <= yMax else { return }

        func sign(_ p: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> Double {
            (p.0 - b.0) * (a.1 - b.1) - (a.0 - b.0) * (p.1 - b.1)
        }

        for y in yMin...yMax {
            for x in xMin...xMax {
                let p = (Double(x) + 0.5, Double(y) + 0.5)
                let d1 = sign(p, p0, p1)
                let d2 = sign(p, p1, p2)
                let d3 = sign(p, p2, p0)
                let hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0)
                let hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0)
                if !(hasNeg && hasPos) {
                    set(x, y, color)
                }
            }
        }
    }

    /// Returns a copy with `color` painted onto every transparent pixel that is
    /// orthogonally adjacent to a non-transparent one - a uniform 1px silhouette
    /// outline that (unlike nesting bigger/smaller ellipses) stays 1px thick even
    /// at the "poles" of a flattened shape.
    func addingOutline(color: Int8) -> PixelCanvas {
        var copy = self
        for y in 0..<height {
            for x in 0..<width {
                guard get(x, y) < 0 else { continue }
                if get(x - 1, y) >= 0 || get(x + 1, y) >= 0 || get(x, y - 1) >= 0 || get(x, y + 1) >= 0 {
                    copy.set(x, y, color)
                }
            }
        }
        return copy
    }

    /// Returns a copy rotated by 90°, used when the pet clings to a screen edge.
    /// Requires a square canvas so the sprite keeps its window size.
    func rotated(clockwise: Bool) -> PixelCanvas {
        guard width == height else { return self }
        var copy = self
        for y in 0..<height {
            for x in 0..<width {
                let source = clockwise
                    ? get(y, height - 1 - x)
                    : get(width - 1 - y, x)
                copy.set(x, y, source)
            }
        }
        return copy
    }

    /// Returns a copy mirrored horizontally (used when the pet turns around).
    func mirrored() -> PixelCanvas {
        var copy = self
        for y in 0..<height {
            for x in 0..<width {
                copy.pixels[y * width + x] = pixels[y * width + (width - 1 - x)]
            }
        }
        return copy
    }
}
