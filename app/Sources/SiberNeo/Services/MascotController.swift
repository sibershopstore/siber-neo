import CoreGraphics
import Foundation

/// Color options for Neo.
enum MascotPalette: String, CaseIterable {
    case navy, crimson, graphite, frost, violet

    var title: String {
        switch self {
        case .navy: return "Navy"
        case .crimson: return tr("Merah", "Red")
        case .graphite: return tr("Grafit", "Graphite")
        case .frost: return tr("Putih Es", "Frost")
        case .violet: return tr("Ungu", "Violet")
        }
    }
}

/// Neo mascot behavior: blinking, glancing, following the cursor, getting sleepy when idle, falling asleep,
/// looking tired on low battery, greeting, celebrating focus sessions, "eating" files dragged onto the notch,
/// drinking along when water or coffee is logged, yawning late at night, enjoying being petted,
/// and getting dizzy when clicked repeatedly.
final class MascotController: ObservableObject {
    enum Mood: Equatable {
        case awake, sleepy, asleep, happy, tired, eating, yawning, dizzy, loved
    }

    /// Neo's outfit, following the weather in the selected city.
    enum WeatherOutfit: Equatable {
        case none, umbrella, sunglasses, scarf
    }

    /// Automatic seasonal accessory.
    enum SeasonalHat: Equatable {
        case peci, party, merahPutih
    }

    /// Neo's activity: working at a laptop during focus sessions, or stretching.
    enum ActivityMode: Equatable {
        case none, working, stretching
    }

    static let stretchAfter: TimeInterval = 60 * 60

    static let sleepyAfter: TimeInterval = 60
    static let asleepAfter: TimeInterval = 150

    @Published private(set) var mood: Mood = .awake
    @Published private(set) var isBlinking = false
    @Published private(set) var look: CGFloat = 0
    @Published private(set) var breathe = false
    @Published private(set) var hops = 0
    @Published private(set) var message: String?
    /// Symbol of the item Neo is holding (glass, cup), or nil.
    @Published private(set) var prop: String?
    @Published var weatherOutfit: WeatherOutfit = .none
    @Published private(set) var seasonal: SeasonalHat?
    /// Collectible accessory currently worn.
    @Published var accessory: NeoAccessory?
    @Published private(set) var activityMode: ActivityMode = .none
    @Published private(set) var isBirthday = UserProfile.isBirthday()

    /// Set while a focus session is running: Neo works and does not fall asleep.
    var isFocusing = false {
        didSet {
            if isFocusing != oldValue { updateActivityMode() }
        }
    }
    /// Called when Neo suggests a stretch after one hour of continuous activity.
    var onStretch: (() -> Void)?
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "mascotEnabled") }
    }
    @Published var palette: MascotPalette {
        didSet { UserDefaults.standard.set(palette.rawValue, forKey: "mascotPalette") }
    }

    /// Set from battery status: Neo looks tired when the battery is below 20%.
    var lowBattery = false
    /// Energy saving mode: the breathing animation stops and blinking is reduced.
    var reducedMotion = false
    /// Called once per night when the user is still active after 23:00.
    var onLateNight: (() -> Void)?

    private var timer: Timer?
    private var lastActivity = Date()
    private var nextBlink = Date().addingTimeInterval(3)
    private var nextGlance = Date().addingTimeInterval(6)
    private var moodUntil: Date?
    private var isEating = false
    private var pokeTimes: [Date] = []
    private var pettingWork: DispatchWorkItem?
    private var lastLateNight: String?
    private var seasonCheckedHour = -1
    private var activeSince: Date?
    private var stretchUntil: Date?

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: "mascotEnabled") as? Bool ?? true
        palette = MascotPalette(rawValue: defaults.string(forKey: "mascotPalette") ?? "") ?? .navy

        seasonal = Self.season(for: Date())

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Outfits

    /// Umbrella when raining, sunglasses when sunny and hot, scarf when cold.
    static func outfit(for weather: WeatherSnapshot?) -> WeatherOutfit {
        guard let weather else { return .none }
        let rainSoon = (weather.hours.first?.rainChance ?? 0) >= 70
        if WeatherCode.isRain(weather.code) || rainSoon { return .umbrella }
        if weather.isDay, weather.code <= 1, weather.temperature >= 31 { return .sunglasses }
        if weather.temperature <= 20 { return .scarf }
        return .none
    }

    /// Peci during Ramadan, Eid al-Fitr, and Eid al-Adha; party hat at New Year; red and white ribbon around August 17.
    static func season(for date: Date) -> SeasonalHat? {
        let islamic = Calendar(identifier: .islamicUmmAlQura).dateComponents([.month, .day], from: date)
        switch (islamic.month ?? 0, islamic.day ?? 0) {
        case (9, _), (10, 1...7), (12, 10...13): return .peci
        default: break
        }
        let gregorian = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
        switch (gregorian.month ?? 0, gregorian.day ?? 0) {
        case (12, 31), (1, 1): return .party
        case (8, 14...18): return .merahPutih
        default: return nil
        }
    }

    // MARK: - Input

    /// Called whenever the cursor moves. `position` ranges from -1 (left of screen) to 1 (right of screen).
    func noteActivity(position: CGFloat) {
        lastActivity = Date()

        if mood == .asleep || mood == .sleepy {
            greet()
            return
        }
        guard mood == .awake || mood == .tired else { return }
        let target = min(max(position, -1), 1)
        if abs(target - look) > 0.08 {
            look = target
        }
    }

    /// Greeting when the user returns.
    func greet() {
        express(
            [tr("Hai!", "Hi!"), tr("Halo!", "Hello!"), tr("Selamat datang!", "Welcome back!")].randomElement(),
            mood: .happy,
            duration: 1.8
        )
    }

    /// Reaction when Neo is clicked. Five quick clicks make Neo dizzy.
    func poke() {
        let now = Date()
        pokeTimes = pokeTimes.filter { now.timeIntervalSince($0) < 2 } + [now]
        if pokeTimes.count >= 5 {
            pokeTimes.removeAll()
            express(tr("Pusing...", "Dizzy..."), mood: .dizzy, duration: 2.6)
            return
        }
        express(
            [tr("Hehe!", "Hehe!"), tr("Siap!", "On it!"), tr("Aman!", "All good!"), tr("Semangat!", "You got this!"), tr("Hai!", "Hi!")].randomElement(),
            mood: .happy,
            duration: 1.6
        )
    }

    /// Celebration after a focus session ends.
    func celebrate() {
        express(tr("Mantap!", "Nice work!"), mood: .happy, duration: 3)
    }

    /// Neo opens its mouth while a file is dragged over the notch.
    func setEating(_ active: Bool) {
        guard enabled else { return }
        isEating = active
        if active {
            lastActivity = Date()
            moodUntil = nil
            message = nil
            prop = nil
            look = 0
            mood = .eating
        } else if mood == .eating {
            mood = restingMood(idle: 0)
        }
    }

    /// File dropped on the notch: Neo "swallows" the file into the Shelf.
    func chomp() {
        isEating = false
        express(tr("Nyam!", "Yum!"), mood: .happy, duration: 1.8)
    }

    /// Neo drinks or eats along when a habit is logged. Cigarettes are intentionally not celebrated.
    func react(to kind: HabitKind) {
        switch kind {
        case .water:
            express(tr("Segar!", "Refreshing!"), mood: .happy, duration: 2.4, prop: "drop.fill")
        case .coffee:
            express(tr("Kopinya mantap!", "Good coffee!"), mood: .happy, duration: 2.4, prop: "cup.and.saucer.fill")
        case .snack:
            express(tr("Nyam!", "Yum!"), mood: .happy, duration: 2.0, prop: "takeoutbag.and.cup.and.straw.fill")
        case .smoke:
            break
        }
    }

    /// Cursor resting over Neo: Neo feels petted.
    func startPetting() {
        guard enabled, mood != .eating else { return }
        pettingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastActivity = Date()
            self.message = tr("Hehe...", "Hehe...")
            self.prop = nil
            self.look = 0
            self.mood = .loved
            self.moodUntil = .distantFuture
        }
        pettingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    func stopPetting() {
        pettingWork?.cancel()
        pettingWork = nil
        if mood == .loved {
            moodUntil = Date().addingTimeInterval(0.8)
        }
    }

    private func express(_ text: String?, mood: Mood, duration: TimeInterval, prop: String? = nil) {
        guard enabled else { return }
        lastActivity = Date()
        message = text
        self.prop = prop
        self.mood = mood
        look = 0
        if mood == .happy {
            hops += 1
        }
        moodUntil = Date().addingTimeInterval(duration)
    }

    // MARK: - Timeline

    // MARK: - Focus & stretching

    /// Neo stretches. Used during Pomodoro breaks and after one hour of activity.
    func startStretch(duration: TimeInterval) {
        guard enabled else { return }
        stretchUntil = Date().addingTimeInterval(duration)
        updateActivityMode()
        express(tr("Ayo peregangan!", "Let's stretch!"), mood: .happy, duration: duration)
    }

    func refreshBirthday() {
        let today = UserProfile.isBirthday()
        if today != isBirthday { isBirthday = today }
    }

    private func updateActivityMode() {
        let next: ActivityMode
        if stretchUntil != nil {
            next = .stretching
        } else if isFocusing {
            next = .working
        } else {
            next = .none
        }
        if next != activityMode { activityMode = next }
    }

    private func checkStretch(now: Date, idle: TimeInterval) {
        if let until = stretchUntil, now >= until {
            stretchUntil = nil
            activeSince = now
            updateActivityMode()
            express(tr("Segar lagi!", "Feeling fresh!"), mood: .happy, duration: 1.6)
            return
        }

        if idle > 5 * 60 {
            activeSince = nil
        } else if activeSince == nil {
            activeSince = now
        }

        guard !isFocusing, stretchUntil == nil, moodUntil == nil,
              let since = activeSince, now.timeIntervalSince(since) >= Self.stretchAfter else { return }
        activeSince = now
        startStretch(duration: 30)
        onStretch?()
    }

    private func restingMood(idle: TimeInterval) -> Mood {
        if isFocusing { return lowBattery ? .tired : .awake }
        if idle > Self.asleepAfter { return .asleep }
        if idle > Self.sleepyAfter { return .sleepy }
        return lowBattery ? .tired : .awake
    }

    private func tick() {
        guard enabled else { return }
        let now = Date()
        let idle = now.timeIntervalSince(lastActivity)

        if let until = moodUntil {
            if now >= until {
                moodUntil = nil
                message = nil
                prop = nil
                mood = restingMood(idle: idle)
            }
        } else if !isEating {
            let target = restingMood(idle: idle)
            if target != mood {
                mood = target
                if target == .sleepy || target == .asleep { look = 0 }
            }
        }

        if !reducedMotion {
            breathe.toggle()
        }

        if mood == .awake || mood == .sleepy || mood == .tired, now >= nextBlink {
            isBlinking = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.isBlinking = false
            }
            let range: ClosedRange<Double> = reducedMotion ? 6...12 : 2.5...6
            nextBlink = now.addingTimeInterval(Double.random(in: range))
        }

        if !reducedMotion, mood == .awake || mood == .tired, idle > 4, now >= nextGlance {
            look = [-0.9, -0.5, 0, 0.5, 0.9].randomElement() ?? 0
            nextGlance = now.addingTimeInterval(Double.random(in: 3...7))
        }

        checkLateNight(now: now, idle: idle)
        checkStretch(now: now, idle: idle)

        let hour = Calendar.current.component(.hour, from: now)
        if hour != seasonCheckedHour {
            seasonCheckedHour = hour
            let current = Self.season(for: now)
            if current != seasonal { seasonal = current }
            refreshBirthday()
        }
    }

    /// Yawns once per night if the user is still active between 23:00 and 03:00.
    private func checkLateNight(now: Date, idle: TimeInterval) {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        guard hour >= 23 || hour < 3, idle < 30, moodUntil == nil, !isEating else { return }
        let night = now.addingTimeInterval(-4 * 3600)
        let parts = calendar.dateComponents([.year, .month, .day], from: night)
        let key = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        guard key != lastLateNight else { return }
        lastLateNight = key
        express(tr("Sudah larut...", "It's late..."), mood: .yawning, duration: 3)
        onLateNight?()
    }
}
