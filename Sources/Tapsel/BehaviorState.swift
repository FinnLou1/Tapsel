import Foundation

/// What the pet is currently *doing*. Drives animation + movement.
enum BehaviorState {
    case idle
    case walk
    case eating
    case sleeping
    case falling  // airborne: jumped, stepped off a ledge, or was dropped
    case climbing // clinging to a screen edge, moving upwards
    case held     // being dragged by the user
}

/// How the pet *feels*, derived from its stats. Drives face/tail expression.
enum MoodLevel {
    case happy
    case neutral
    case sad
    case hungry

    static func from(hunger: Double, happiness: Double) -> MoodLevel {
        if hunger < 25 { return .hungry }
        if happiness >= 65 { return .happy }
        if happiness <= 30 { return .sad }
        return .neutral
    }
}

/// Which way is "down" for the pet - it clings sideways while climbing a screen edge.
enum PetOrientation {
    case upright
    case wallLeft  // feet against the left screen edge
    case wallRight // feet against the right screen edge
}
