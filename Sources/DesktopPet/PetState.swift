import Foundation

/// Persisted "tamagotchi" stats. Decay is time-based so the pet is still hungrier
/// after the app was closed for a while, not just while it's running.
struct PetStats: Codable {
    var hunger: Double     // 0 = starving, 100 = full
    var happiness: Double  // 0 = miserable, 100 = delighted
    var energy: Double     // 0 = exhausted, 100 = fully rested
    var lastUpdate: Date

    static let initial = PetStats(hunger: 80, happiness: 80, energy: 100, lastUpdate: Date())

    // Per-hour rates.
    static let hungerDecayPerHour: Double = 7.0
    static let energyDecayPerHour: Double = 6.0
    static let energyRegenPerHourAsleep: Double = 25.0

    mutating func applyDecay(elapsedSeconds: Double, isSleeping: Bool) {
        guard elapsedSeconds > 0 else { return }
        let hours = elapsedSeconds / 3600.0

        hunger = (hunger - Self.hungerDecayPerHour * hours).clamped(0, 100)

        if isSleeping {
            energy = (energy + Self.energyRegenPerHourAsleep * hours).clamped(0, 100)
        } else {
            energy = (energy - Self.energyDecayPerHour * hours).clamped(0, 100)
        }

        // Happiness drifts toward a target implied by hunger/energy - feeding and
        // petting give it direct boosts elsewhere; this just models "neglect".
        let target = min(hunger, 40 + energy * 0.4)
        let driftPerHour = 10.0
        let delta = (target - happiness).clamped(-driftPerHour * hours, driftPerHour * hours)
        happiness = (happiness + delta).clamped(0, 100)
    }

    mutating func feed() {
        hunger = (hunger + 32).clamped(0, 100)
        happiness = (happiness + 8).clamped(0, 100)
        energy = (energy + 3).clamped(0, 100)
    }

    mutating func pet() {
        happiness = (happiness + 14).clamped(0, 100)
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double {
        min(max(self, lo), hi)
    }
}

/// A save file: which pet skin is selected + its stats.
struct PetSaveData: Codable {
    var kind: PetKind
    var stats: PetStats

    static let defaultsKey = "DesktopPet.SaveData.v1"

    static func load() -> PetSaveData {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(PetSaveData.self, from: data)
        else {
            return PetSaveData(kind: .cat, stats: .initial)
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
