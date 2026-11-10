import AppKit
import UserNotifications

/// Local storage in ~/Library/Application Support/SiberNeo.
enum Storage {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SiberNeo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}

/// macOS system notifications. Active only when running as an .app bundle.
enum Notifier {
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Disabled while presentation mode is active.
    static var isMuted = false

    static func post(title: String, body: String) {
        guard isAvailable, !isMuted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func chime() {
        guard !isMuted else { return }
        NSSound(named: "Glass")?.play()
    }
}

/// AppleScript execution for controlling Spotify and Apple Music.
enum AppleScript {
    @discardableResult
    static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

enum Fmt {
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Lang.locale
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Lang.locale
        formatter.dateFormat = Lang.isIndonesian ? "EEEE, d MMMM" : "EEEE, MMMM d"
        return formatter
    }()

    static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        clockFormatter.timeZone = timeZone
        return clockFormatter.string(from: date)
    }

    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// Text width in points for the system font, used to size the notch to its content.
    static func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func mmss(_ seconds: Int) -> String {
        let value = max(seconds, 0)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func countdown(_ interval: TimeInterval) -> String {
        let minutes = Int(ceil(max(interval, 0) / 60))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 {
            return rest > 0 ? tr("\(hours) jam \(rest) menit", "\(hours) h \(rest) min") : tr("\(hours) jam", "\(hours) h")
        }
        return tr("\(rest) menit", "\(rest) min")
    }
}
