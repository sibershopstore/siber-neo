import Foundation

enum HabitKind: String, CaseIterable, Codable, Identifiable {
    case water, coffee, snack, smoke

    var id: String { rawValue }

    var title: String {
        switch self {
        case .water: return tr("Air putih", "Water")
        case .coffee: return tr("Kopi", "Coffee")
        case .snack: return tr("Camilan", "Snacks")
        case .smoke: return tr("Rokok", "Cigarettes")
        }
    }

    var unit: String {
        switch self {
        case .water: return tr("gelas", "glasses")
        case .coffee: return tr("cangkir", "cups")
        case .snack: return tr("kali", "times")
        case .smoke: return tr("batang", "cigarettes")
        }
    }

    var icon: String {
        switch self {
        case .water: return "drop.fill"
        case .coffee: return "cup.and.saucer.fill"
        case .snack: return "takeoutbag.and.cup.and.straw.fill"
        case .smoke: return "smoke.fill"
        }
    }
}

/// Daily habit tracker. Water has a goal and periodic reminders; snacks have reminders
/// at 10:00 and 15:00; coffee and cigarettes have daily limits with alerts when exceeded.
/// Data is stored locally in habits.json with 30 days of history.
final class HabitStore: ObservableObject {
    @Published private(set) var days: [String: [String: Int]] = [:]
    @Published private(set) var lastReminder: Date?

    @Published var waterGoal: Int {
        didSet { UserDefaults.standard.set(waterGoal, forKey: "habitWaterGoal") }
    }
    /// Water reminder interval in minutes; 0 means off.
    @Published var waterInterval: Int {
        didSet { UserDefaults.standard.set(waterInterval, forKey: "habitWaterInterval") }
    }
    @Published var coffeeLimit: Int {
        didSet { UserDefaults.standard.set(coffeeLimit, forKey: "habitCoffeeLimit") }
    }
    /// Daily cigarette limit; 0 means no limit.
    @Published var smokeLimit: Int {
        didSet { UserDefaults.standard.set(smokeLimit, forKey: "habitSmokeLimit") }
    }
    @Published var snackReminders: Bool {
        didSet { UserDefaults.standard.set(snackReminders, forKey: "habitSnackReminders") }
    }

    static let activeHours = 8..<21
    static let snackHours = [10, 15]

    var onReminder: ((HabitKind, String) -> Void)?
    var onLimit: ((HabitKind, Int, Int) -> Void)?
    var onAdd: ((HabitKind) -> Void)?

    private let fileName = "habits.json"
    private var timer: Timer?
    private var lastWaterAt = Date()
    private var lastWaterReminder = Date.distantPast
    private var firedSnackSlots = Set<String>()

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        let defaults = UserDefaults.standard
        waterGoal = defaults.object(forKey: "habitWaterGoal") as? Int ?? 8
        waterInterval = defaults.object(forKey: "habitWaterInterval") as? Int ?? 60
        coffeeLimit = defaults.object(forKey: "habitCoffeeLimit") as? Int ?? 3
        smokeLimit = defaults.object(forKey: "habitSmokeLimit") as? Int ?? 0
        snackReminders = defaults.object(forKey: "habitSnackReminders") as? Bool ?? true
        days = Storage.load([String: [String: Int]].self, from: fileName) ?? [:]

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Reading

    static func key(for date: Date) -> String {
        keyFormatter.string(from: date)
    }

    func count(_ kind: HabitKind, on date: Date = Date()) -> Int {
        days[Self.key(for: date)]?[kind.rawValue] ?? 0
    }

    /// Goal for water, limit for coffee and cigarettes, nil for snacks.
    func target(for kind: HabitKind) -> Int? {
        switch kind {
        case .water: return waterGoal
        case .coffee: return coffeeLimit > 0 ? coffeeLimit : nil
        case .smoke: return smokeLimit > 0 ? smokeLimit : nil
        case .snack: return nil
        }
    }

    /// The water goal is a minimum target; coffee and cigarettes are maximum limits.
    func isLimit(_ kind: HabitKind) -> Bool {
        kind == .coffee || kind == .smoke
    }

    func history(_ kind: HabitKind, days count: Int = 7) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { offset -> (date: Date, count: Int)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date: date, count: self.count(kind, on: date))
        }
    }

    // MARK: - Writing

    func add(_ kind: HabitKind) {
        let key = Self.key(for: Date())
        var day = days[key] ?? [:]
        let value = (day[kind.rawValue] ?? 0) + 1
        day[kind.rawValue] = value
        days[key] = day
        persist()

        if kind == .water {
            lastWaterAt = Date()
        }
        onAdd?(kind)
        if isLimit(kind), let limit = target(for: kind), value >= limit {
            onLimit?(kind, value, limit)
        }
    }

    func remove(_ kind: HabitKind) {
        let key = Self.key(for: Date())
        guard var day = days[key], let value = day[kind.rawValue], value > 0 else { return }
        day[kind.rawValue] = value - 1
        days[key] = day
        persist()
    }

    private func persist() {
        let calendar = Calendar.current
        if let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) {
            let cutoffKey = Self.key(for: cutoff)
            days = days.filter { $0.key >= cutoffKey }
        }
        Storage.save(days, to: fileName)
    }

    // MARK: - Reminders

    private func tick() {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)

        if waterInterval > 0, Self.activeHours.contains(hour) {
            let current = count(.water)
            let reference = max(lastWaterAt, lastWaterReminder)
            if current < waterGoal, now.timeIntervalSince(reference) >= Double(waterInterval) * 60 {
                lastWaterReminder = now
                lastReminder = now
                onReminder?(.water, tr("\(current)/\(waterGoal) gelas", "\(current)/\(waterGoal) glasses"))
            }
        }

        if snackReminders {
            let dayKey = Self.key(for: now)
            for slot in Self.snackHours {
                let slotKey = "\(dayKey)-\(slot)"
                guard !firedSnackSlots.contains(slotKey),
                      let start = calendar.date(bySettingHour: slot, minute: 0, second: 0, of: now) else { continue }
                if now >= start, now.timeIntervalSince(start) < 10 * 60 {
                    firedSnackSlots.insert(slotKey)
                    lastReminder = now
                    onReminder?(.snack, String(format: Lang.isIndonesian ? "%02d.00" : "%02d:00", slot))
                }
            }
        }
    }
}
