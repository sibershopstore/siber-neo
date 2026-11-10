import AppKit

/// Neo greets the user by name based on the time of day (morning, noon, afternoon, evening) when the Mac
/// is opened or wakes from sleep. At most one greeting per part of the day. On special occasions such as
/// Ramadan, Eid al-Fitr, Eid al-Adha, New Year, Lunar New Year, Christmas, and August 17, the greeting includes a message.
final class GreetingService {
    struct Greeting {
        let icon: String
        let title: String
        let detail: String
    }

    var onGreeting: ((Greeting) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var started = false

    private static let lastKey = "greetingLastSlot"

    func start() {
        guard !started else { return }
        started = true

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self?.greetIfNeeded()
                }
            })
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.greetIfNeeded()
        }
    }

    /// Shows a greeting if none has been shown for the current part of the day.
    func greetIfNeeded(force: Bool = false) {
        let now = Date()
        let part = Daypart(date: now)
        let slot = "\(Self.dayKey(now))-\(part.rawValue)"
        let defaults = UserDefaults.standard
        guard force || defaults.string(forKey: Self.lastKey) != slot else { return }
        defaults.set(slot, forKey: Self.lastKey)

        let occasion = Self.occasion(on: now)
        onGreeting?(Greeting(
            icon: occasion?.icon ?? part.icon,
            title: "\(part.greeting), \(Self.firstName)",
            detail: occasion?.text ?? Fmt.day(now)
        ))
    }

    // MARK: - Parts of day

    enum Daypart: String {
        case morning, midday, afternoon, evening

        init(date: Date) {
            let hour = Calendar.current.component(.hour, from: date)
            if Lang.isIndonesian {
                switch hour {
                case 4..<10: self = .morning
                case 10..<15: self = .midday
                case 15..<18: self = .afternoon
                default: self = .evening
                }
            } else {
                switch hour {
                case 4..<12: self = .morning
                case 12..<17: self = .afternoon
                default: self = .evening
                }
            }
        }

        var greeting: String {
            switch self {
            case .morning: return tr("Selamat pagi", "Good morning")
            case .midday: return tr("Selamat siang", "Good afternoon")
            case .afternoon: return tr("Selamat sore", "Good afternoon")
            case .evening: return tr("Selamat malam", "Good evening")
            }
        }

        var icon: String {
            switch self {
            case .morning: return "sunrise.fill"
            case .midday: return "sun.max.fill"
            case .afternoon: return "sunset.fill"
            case .evening: return "moon.stars.fill"
            }
        }
    }

    // MARK: - Occasions

    private static func occasion(on date: Date) -> (icon: String, text: String)? {
        if UserProfile.isBirthday(date) {
            return ("birthday.cake.fill", tr("Selamat ulang tahun!", "Happy birthday!"))
        }
        let islamic = Calendar(identifier: .islamicUmmAlQura).dateComponents([.month, .day], from: date)
        switch (islamic.month ?? 0, islamic.day ?? 0) {
        case (10, 1...2): return ("sparkles", tr("Selamat Idul Fitri", "Eid Mubarak"))
        case (12, 10): return ("sparkles", tr("Selamat Idul Adha", "Eid al-Adha Mubarak"))
        case (1, 1): return ("moon.stars.fill", tr("Tahun Baru Islam", "Islamic New Year"))
        case (3, 12): return ("moon.stars.fill", tr("Maulid Nabi", "Mawlid an-Nabi"))
        case (9, _): return ("moon.stars.fill", "Ramadan Kareem")
        default: break
        }

        let chinese = Calendar(identifier: .chinese).dateComponents([.month, .day], from: date)
        if chinese.month == 1, chinese.day == 1 {
            return ("sparkles", tr("Selamat Tahun Baru Imlek", "Happy Lunar New Year"))
        }

        let gregorian = Calendar(identifier: .gregorian).dateComponents([.month, .day, .weekday], from: date)
        switch (gregorian.month ?? 0, gregorian.day ?? 0) {
        case (1, 1): return ("sparkles", tr("Selamat Tahun Baru", "Happy New Year"))
        case (8, 17): return ("flag.fill", tr("Dirgahayu Republik Indonesia", "Indonesian Independence Day"))
        case (12, 25): return ("gift.fill", tr("Selamat Natal", "Merry Christmas"))
        default: break
        }

        if Lang.isIndonesian, gregorian.weekday == 6 {
            return ("sparkles", "Jumat berkah")
        }
        return nil
    }

    // MARK: - Helpers

    static var firstName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        if let first = full.split(separator: " ").first, !first.isEmpty {
            return String(first)
        }
        return NSUserName()
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
