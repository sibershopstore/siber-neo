import AppKit

enum PrayerName: String, CaseIterable, Codable {
    case imsak, subuh, terbit, dzuhur, ashar, maghrib, isya

    var title: String {
        switch self {
        case .imsak: return "Imsak"
        case .subuh: return tr("Subuh", "Fajr")
        case .terbit: return tr("Terbit", "Sunrise")
        case .dzuhur: return tr("Dzuhur", "Dhuhr")
        case .ashar: return tr("Ashar", "Asr")
        case .maghrib: return "Maghrib"
        case .isya: return tr("Isya", "Isha")
        }
    }

    var isPrayer: Bool {
        switch self {
        case .subuh, .dzuhur, .ashar, .maghrib, .isya: return true
        case .imsak, .terbit: return false
        }
    }

    /// Ihtiyat (safety margin) in minutes, following Indonesian Ministry of Religious Affairs practice.
    var ihtiyat: Double {
        switch self {
        case .terbit: return -2
        case .imsak: return 0
        default: return 2
        }
    }
}

struct PrayerTime: Identifiable, Equatable {
    let name: PrayerName
    let date: Date
    var id: String { name.rawValue }
}

struct City: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
    let zone: String

    var timeZone: TimeZone { TimeZone(identifier: zone) ?? .current }

    static let all: [City] = [
        City(name: "Bekasi", latitude: -6.2383, longitude: 106.9756, zone: "Asia/Jakarta"),
        City(name: "Jakarta", latitude: -6.2088, longitude: 106.8456, zone: "Asia/Jakarta"),
        City(name: "Bogor", latitude: -6.5950, longitude: 106.8166, zone: "Asia/Jakarta"),
        City(name: "Depok", latitude: -6.4025, longitude: 106.7942, zone: "Asia/Jakarta"),
        City(name: "Tangerang", latitude: -6.1783, longitude: 106.6319, zone: "Asia/Jakarta"),
        City(name: "Bandung", latitude: -6.9175, longitude: 107.6191, zone: "Asia/Jakarta"),
        City(name: "Semarang", latitude: -6.9667, longitude: 110.4167, zone: "Asia/Jakarta"),
        City(name: "Yogyakarta", latitude: -7.7956, longitude: 110.3695, zone: "Asia/Jakarta"),
        City(name: "Surabaya", latitude: -7.2575, longitude: 112.7521, zone: "Asia/Jakarta"),
        City(name: "Malang", latitude: -7.9666, longitude: 112.6326, zone: "Asia/Jakarta"),
        City(name: "Medan", latitude: 3.5952, longitude: 98.6722, zone: "Asia/Jakarta"),
        City(name: "Padang", latitude: -0.9471, longitude: 100.4172, zone: "Asia/Jakarta"),
        City(name: "Pekanbaru", latitude: 0.5071, longitude: 101.4478, zone: "Asia/Jakarta"),
        City(name: "Palembang", latitude: -2.9761, longitude: 104.7754, zone: "Asia/Jakarta"),
        City(name: "Pontianak", latitude: -0.0263, longitude: 109.3425, zone: "Asia/Pontianak"),
        City(name: "Denpasar", latitude: -8.6705, longitude: 115.2126, zone: "Asia/Makassar"),
        City(name: "Banjarmasin", latitude: -3.3186, longitude: 114.5944, zone: "Asia/Makassar"),
        City(name: "Balikpapan", latitude: -1.2379, longitude: 116.8529, zone: "Asia/Makassar"),
        City(name: "Makassar", latitude: -5.1477, longitude: 119.4327, zone: "Asia/Makassar"),
        City(name: "Manado", latitude: 1.4748, longitude: 124.8421, zone: "Asia/Makassar"),
        City(name: "Jayapura", latitude: -2.5916, longitude: 140.6690, zone: "Asia/Jayapura")
    ]

    static let fallback = all[0]
}

/// Prayer times are calculated entirely on the device (no internet connection).
final class PrayerService: ObservableObject {
    @Published private(set) var today: [PrayerTime] = []
    @Published var city: City {
        didSet {
            UserDefaults.standard.set(city.name, forKey: "prayerCity")
            refresh()
        }
    }
    @Published var remindersEnabled: Bool {
        didSet { UserDefaults.standard.set(remindersEnabled, forKey: "prayerReminders") }
    }
    @Published var pauseMediaOnAdhan: Bool {
        didSet { UserDefaults.standard.set(pauseMediaOnAdhan, forKey: "prayerPauseMedia") }
    }

    var onPrayerTime: ((PrayerTime) -> Void)?

    private var prayerTimer: Timer?
    private var dayTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        let savedName = defaults.string(forKey: "prayerCity")
        city = City.all.first(where: { $0.name == savedName }) ?? City.fallback
        remindersEnabled = defaults.object(forKey: "prayerReminders") as? Bool ?? true
        pauseMediaOnAdhan = defaults.object(forKey: "prayerPauseMedia") as? Bool ?? true

        refresh()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    func next(after date: Date) -> PrayerTime? {
        if let upcoming = today.first(where: { $0.name.isPrayer && $0.date > date }) {
            return upcoming
        }
        let tomorrow = date.addingTimeInterval(86_400)
        let times = PrayerCalculator.compute(date: tomorrow, city: city)
        return times[.subuh].map { PrayerTime(name: .subuh, date: $0) }
    }

    func refresh() {
        let times = PrayerCalculator.compute(date: Date(), city: city)
        today = PrayerName.allCases.compactMap { name in
            times[name].map { PrayerTime(name: name, date: $0) }
        }
        schedule()
    }

    private func schedule() {
        prayerTimer?.invalidate()
        dayTimer?.invalidate()

        if let upcoming = next(after: Date()) {
            let timer = Timer(fire: upcoming.date, interval: 0, repeats: false) { [weak self] _ in
                self?.fire(upcoming)
            }
            RunLoop.main.add(timer, forMode: .common)
            prayerTimer = timer
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = city.timeZone
        if let midnight = calendar.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 5), matchingPolicy: .nextTime) {
            let timer = Timer(fire: midnight, interval: 0, repeats: false) { [weak self] _ in
                self?.refresh()
            }
            RunLoop.main.add(timer, forMode: .common)
            dayTimer = timer
        }
    }

    private func fire(_ time: PrayerTime) {
        if remindersEnabled, Date().timeIntervalSince(time.date) < 300 {
            onPrayerTime?(time)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refresh()
        }
    }
}

/// Astronomical calculation based on the PrayTimes algorithm with Indonesian Ministry of Religious Affairs parameters:
/// Fajr 20°, Isha 18°, Asr per the Shafi'i school, 2-minute ihtiyat, Imsak 10 minutes before Fajr.
enum PrayerCalculator {
    static func compute(date: Date, city: City) -> [PrayerName: Date] {
        compute(date: date, latitude: city.latitude, longitude: city.longitude, timeZone: city.timeZone)
    }

    static func compute(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone) -> [PrayerName: Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return [:] }

        let jDate = julian(year, month, day) - longitude / (15 * 24)
        let offset = Double(timeZone.secondsFromGMT(for: date)) / 3600

        func sun(_ jd: Double) -> (declination: Double, equation: Double) {
            let d = jd - 2_451_545.0
            let g = fixAngle(357.529 + 0.98560028 * d)
            let q = fixAngle(280.459 + 0.98564736 * d)
            let l = fixAngle(q + 1.915 * dsin(g) + 0.020 * dsin(2 * g))
            let e = 23.439 - 0.00000036 * d
            let ra = darctan2(dcos(e) * dsin(l), dcos(l)) / 15
            let equation = q / 15 - fixHour(ra)
            let declination = darcsin(dsin(e) * dsin(l))
            return (declination, equation)
        }

        func midDay(_ t: Double) -> Double {
            fixHour(12 - sun(jDate + t).equation)
        }

        func angleTime(_ angle: Double, _ t: Double, counterClockwise: Bool) -> Double {
            let declination = sun(jDate + t).declination
            let noon = midDay(t)
            var x = (-dsin(angle) - dsin(declination) * dsin(latitude)) / (dcos(declination) * dcos(latitude))
            x = min(max(x, -1), 1)
            let value = darccos(x) / 15
            return noon + (counterClockwise ? -value : value)
        }

        func asr(_ factor: Double, _ t: Double) -> Double {
            let declination = sun(jDate + t).declination
            let angle = -darccot(factor + dtan(abs(latitude - declination)))
            return angleTime(angle, t, counterClockwise: false)
        }

        let raw: [PrayerName: Double] = [
            .subuh: angleTime(20, 5.0 / 24, counterClockwise: true),
            .terbit: angleTime(0.833, 6.0 / 24, counterClockwise: true),
            .dzuhur: midDay(12.0 / 24),
            .ashar: asr(1, 13.0 / 24),
            .maghrib: angleTime(0.833, 18.0 / 24, counterClockwise: false),
            .isya: angleTime(18, 18.0 / 24, counterClockwise: false)
        ]

        let start = calendar.startOfDay(for: date)
        var result: [PrayerName: Date] = [:]
        for (name, hours) in raw {
            let local = hours + offset - longitude / 15
            let base = start.addingTimeInterval(local * 3600)
            result[name] = roundUpToMinute(base.addingTimeInterval(name.ihtiyat * 60))
        }
        if let subuh = result[.subuh] {
            result[.imsak] = subuh.addingTimeInterval(-600)
        }
        return result
    }

    private static func julian(_ year: Int, _ month: Int, _ day: Int) -> Double {
        var y = year
        var m = month
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = floor(Double(y) / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + Double(day) + b - 1524.5
    }

    private static func roundUpToMinute(_ date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: ceil(seconds / 60) * 60)
    }

    private static func dsin(_ d: Double) -> Double { sin(d * .pi / 180) }
    private static func dcos(_ d: Double) -> Double { cos(d * .pi / 180) }
    private static func dtan(_ d: Double) -> Double { tan(d * .pi / 180) }
    private static func darcsin(_ x: Double) -> Double { asin(x) * 180 / .pi }
    private static func darccos(_ x: Double) -> Double { acos(x) * 180 / .pi }
    private static func darctan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) * 180 / .pi }
    private static func darccot(_ x: Double) -> Double { atan(1 / x) * 180 / .pi }
    private static func fixAngle(_ a: Double) -> Double { a - 360 * floor(a / 360) }
    private static func fixHour(_ a: Double) -> Double { a - 24 * floor(a / 24) }
}
