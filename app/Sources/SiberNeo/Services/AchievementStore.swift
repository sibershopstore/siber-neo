import Foundation

/// Neo accessories unlocked through good-habit achievements.
enum NeoAccessory: String, CaseIterable, Codable {
    case glasses, flower, graduation, crown

    var symbol: String {
        switch self {
        case .glasses: return "eyeglasses"
        case .flower: return "camera.macro"
        case .graduation: return "graduationcap.fill"
        case .crown: return "crown.fill"
        }
    }

    var title: String {
        switch self {
        case .glasses: return tr("Kacamata", "Glasses")
        case .flower: return tr("Bunga", "Flower")
        case .graduation: return tr("Topi wisuda", "Graduation cap")
        case .crown: return tr("Mahkota", "Crown")
        }
    }
}

/// Records achievements (completed focus sessions and days the water goal was met)
/// and unlocks new accessories for Neo. Data is stored locally.
final class AchievementStore: ObservableObject {
    @Published private(set) var focusSessions: Int
    @Published private(set) var waterDays: Set<String>
    @Published var equipped: NeoAccessory? {
        didSet { UserDefaults.standard.set(equipped?.rawValue, forKey: "neoAccessory") }
    }

    var onUnlock: ((NeoAccessory) -> Void)?

    init() {
        let defaults = UserDefaults.standard
        focusSessions = defaults.integer(forKey: "achievementFocusSessions")
        waterDays = Set(defaults.stringArray(forKey: "achievementWaterDays") ?? [])
        equipped = defaults.string(forKey: "neoAccessory").flatMap { NeoAccessory(rawValue: $0) }
    }

    func target(for accessory: NeoAccessory) -> Int {
        switch accessory {
        case .glasses: return 10
        case .flower: return 7
        case .graduation: return 25
        case .crown: return 50
        }
    }

    func progress(for accessory: NeoAccessory) -> Int {
        accessory == .flower ? waterDays.count : focusSessions
    }

    func isUnlocked(_ accessory: NeoAccessory) -> Bool {
        progress(for: accessory) >= target(for: accessory)
    }

    func requirementText(_ accessory: NeoAccessory) -> String {
        let current = min(progress(for: accessory), target(for: accessory))
        let goal = target(for: accessory)
        if accessory == .flower {
            return tr("\(accessory.title): capai target air putih \(goal) hari (\(current)/\(goal))",
                      "\(accessory.title): hit your water goal on \(goal) days (\(current)/\(goal))")
        }
        return tr("\(accessory.title): selesaikan \(goal) sesi fokus (\(current)/\(goal))",
                  "\(accessory.title): finish \(goal) focus sessions (\(current)/\(goal))")
    }

    func recordFocusSession() {
        let before = unlockedSet()
        focusSessions += 1
        UserDefaults.standard.set(focusSessions, forKey: "achievementFocusSessions")
        announce(since: before)
    }

    func recordWaterGoal(dayKey: String) {
        guard !waterDays.contains(dayKey) else { return }
        let before = unlockedSet()
        waterDays.insert(dayKey)
        UserDefaults.standard.set(Array(waterDays), forKey: "achievementWaterDays")
        announce(since: before)
    }

    private func unlockedSet() -> Set<NeoAccessory> {
        Set(NeoAccessory.allCases.filter { isUnlocked($0) })
    }

    private func announce(since before: Set<NeoAccessory>) {
        for accessory in NeoAccessory.allCases where isUnlocked(accessory) && !before.contains(accessory) {
            onUnlock?(accessory)
        }
    }
}
