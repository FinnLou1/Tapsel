import AppKit

enum PetKind: String, CaseIterable, Codable, Identifiable {
    case cat, dog, bunny

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cat: return "Katze"
        case .dog: return "Hund"
        case .bunny: return "Hase"
        }
    }

    /// SF Symbol used for the menu bar item and the "Haustier" submenu.
    var symbolName: String {
        switch self {
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        case .bunny: return "hare.fill"
        }
    }

    /// Palette indices used by SpriteBuilder: [outline, main, shade, belly, pink, pupil]
    var palette: [NSColor] {
        switch self {
        case .cat:
            return [
                NSColor(calibratedRed: 0.20, green: 0.13, blue: 0.08, alpha: 1),
                NSColor(calibratedRed: 0.91, green: 0.64, blue: 0.24, alpha: 1),
                NSColor(calibratedRed: 0.79, green: 0.49, blue: 0.12, alpha: 1),
                NSColor(calibratedRed: 0.98, green: 0.93, blue: 0.85, alpha: 1),
                NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.60, alpha: 1),
                NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.05, alpha: 1),
            ]
        case .dog:
            return [
                NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.07, alpha: 1),
                NSColor(calibratedRed: 0.66, green: 0.45, blue: 0.29, alpha: 1),
                NSColor(calibratedRed: 0.49, green: 0.32, blue: 0.19, alpha: 1),
                NSColor(calibratedRed: 0.98, green: 0.93, blue: 0.85, alpha: 1),
                NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.60, alpha: 1),
                NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.05, alpha: 1),
            ]
        case .bunny:
            return [
                NSColor(calibratedRed: 0.35, green: 0.32, blue: 0.34, alpha: 1),
                NSColor(calibratedRed: 0.95, green: 0.93, blue: 0.92, alpha: 1),
                NSColor(calibratedRed: 0.82, green: 0.79, blue: 0.80, alpha: 1),
                NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
                NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.60, alpha: 1),
                NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.10, alpha: 1),
            ]
        }
    }
}
