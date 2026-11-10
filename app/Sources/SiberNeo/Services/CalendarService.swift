import AppKit
import EventKit
import SwiftUI

struct AgendaEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    let joinURL: URL?
    let location: String?
}

/// Events from the macOS Calendar app (including Google, iCloud, and Exchange accounts
/// already added to Calendar), with a reminder 5 minutes before each event starts.
final class CalendarService: ObservableObject {
    enum Access: Equatable {
        case notDetermined, granted, denied
    }

    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var events: [AgendaEvent] = []

    var onSoon: ((AgendaEvent) -> Void)?

    private let store = EKEventStore()
    private var refreshTimer: Timer?
    private var reminderTimer: Timer?
    private var notified = Set<String>()
    private var observer: NSObjectProtocol?

    private static let meetingHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com"
    ]

    init() {
        updateAccess()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.reload()
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        reload()
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.reload()
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let next: Access
        switch status {
        case .fullAccess: next = .granted
        case .notDetermined: next = .notDetermined
        default: next = .denied
        }
        if next != access { access = next }
    }

    func reload() {
        updateAccess()
        guard access == .granted else {
            if !events.isEmpty { events = [] }
            return
        }

        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-6 * 3600),
            end: now.addingTimeInterval(24 * 3600),
            calendars: nil
        )
        let list: [AgendaEvent] = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { event in
                AgendaEvent(
                    id: (event.eventIdentifier ?? UUID().uuidString) + "-\(Int(event.startDate.timeIntervalSince1970))",
                    title: event.title ?? tr("Tanpa judul", "Untitled"),
                    start: event.startDate,
                    end: event.endDate,
                    color: Color(nsColor: event.calendar?.color ?? .systemBlue),
                    joinURL: Self.meetingURL(for: event),
                    location: event.location
                )
            }

        if list != events { events = list }
        scheduleReminder()
    }

    private func scheduleReminder() {
        reminderTimer?.invalidate()
        reminderTimer = nil

        let now = Date()
        guard let next = events.first(where: { $0.start > now && !notified.contains($0.id) }) else { return }
        let fireDate = next.start.addingTimeInterval(-5 * 60)

        if fireDate <= now {
            notified.insert(next.id)
            onSoon?(next)
            scheduleReminder()
            return
        }

        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.notified.insert(next.id)
            self.onSoon?(next)
            self.scheduleReminder()
        }
        RunLoop.main.add(timer, forMode: .common)
        reminderTimer = timer
    }

    /// Finds meeting links (Zoom, Google Meet, Teams, and others) in the event URL, location, or notes.
    static func meetingURL(for event: EKEvent) -> URL? {
        var candidates: [URL] = []
        if let url = event.url {
            candidates.append(url)
        }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        if !text.isEmpty,
           let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, options: [], range: range) {
                if let url = match.url {
                    candidates.append(url)
                }
            }
        }
        return candidates.first { url in
            guard let host = url.host?.lowercased() else { return false }
            return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }
}
