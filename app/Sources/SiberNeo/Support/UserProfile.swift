import Foundation

/// Simple personal data stored locally: the mascot's name and the user's birthday.
enum UserProfile {
    static let defaultMascotName = "Neo"

    static var mascotName: String {
        get {
            let stored = UserDefaults.standard.string(forKey: "mascotName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? defaultMascotName : stored
        }
        set {
            let trimmed = String(newValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
            UserDefaults.standard.set(trimmed, forKey: "mascotName")
        }
    }

    /// Birthday month and day (without year), or nil if not set.
    static var birthday: (month: Int, day: Int)? {
        get {
            let month = UserDefaults.standard.integer(forKey: "birthdayMonth")
            let day = UserDefaults.standard.integer(forKey: "birthdayDay")
            return (1...12).contains(month) && (1...31).contains(day) ? (month, day) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.month ?? 0, forKey: "birthdayMonth")
            UserDefaults.standard.set(newValue?.day ?? 0, forKey: "birthdayDay")
        }
    }

    static func isBirthday(_ date: Date = Date()) -> Bool {
        guard let birthday else { return false }
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        return parts.month == birthday.month && parts.day == birthday.day
    }
}
