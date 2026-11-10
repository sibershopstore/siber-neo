import SwiftUI

enum NotchTab: String, CaseIterable {
    case media, focus, todo, agenda, habits, shelf, prayer, security, weather

    /// Tabs shown as icons in the header. Weather opens from the temperature chip.
    static var tabBarCases: [NotchTab] { allCases.filter { $0 != .weather } }

    var icon: String {
        switch self {
        case .media: return "music.note"
        case .focus: return "timer"
        case .todo: return "checklist"
        case .agenda: return "calendar"
        case .habits: return "drop"
        case .shelf: return "tray.full"
        case .prayer: return "moon.stars"
        case .security: return "shield.lefthalf.filled"
        case .weather: return "cloud.sun"
        }
    }

    var title: String {
        switch self {
        case .media: return tr("Musik", "Music")
        case .focus: return tr("Fokus", "Focus")
        case .todo: return "To-do"
        case .agenda: return "Agenda"
        case .habits: return tr("Harian", "Daily")
        case .shelf: return "Shelf"
        case .prayer: return tr("Sholat", "Prayer")
        case .security: return tr("Keamanan", "Security")
        case .weather: return tr("Cuaca", "Weather")
        }
    }
}

enum NotchMode: Equatable {
    case closed, live, activity, open
}

enum LiveKind: Equatable {
    case media, focus, mascot, privacy
}

struct NotchActivity: Equatable {
    let id = UUID()
    var icon: String
    var tint: Color
    var title: String
    var detail: String
    var level: Double? = nil
    var charging = false
}

final class NotchState: ObservableObject {
    @Published var isOpen = false
    @Published var tab: NotchTab = .media {
        didSet {
            let all = NotchTab.allCases
            tabForward = (all.firstIndex(of: tab) ?? 0) >= (all.firstIndex(of: oldValue) ?? 0)
        }
    }
    /// Direction of the last tab change, used for the slide animation.
    private(set) var tabForward = true
    @Published var activity: NotchActivity?
    @Published var live: LiveKind?
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var hasNotch = true
    @Published var isDropTargeted = false
    @Published var keepOpen = false
    /// Presentation mode: the notch stays closed and notifications are hidden.
    @Published var quiet = false
    /// Width of the left/right notch wings while showing a notification, sized to the text.
    @Published var activityWing: CGFloat = 145
    /// Width of the left/right notch wings in live view, widening while Neo shows a message.
    @Published var liveWing: CGFloat = 52

    @Published private(set) var confetti: [ConfettiParticle] = []
    @Published private(set) var confettiStart = Date()

    /// Confetti falling from the notch for a few seconds.
    func launchConfetti() {
        guard !quiet, !EnergyMode.shared.isSaving else { return }
        confettiStart = Date()
        confetti = ConfettiParticle.burst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { [weak self] in
            self?.confetti = []
        }
    }

    /// Opens the settings menu (same as the shield icon in the menu bar) from inside the notch.
    var openSettingsMenu: (() -> Void)?

    private var activityWork: DispatchWorkItem?

    var mode: NotchMode {
        if isOpen { return .open }
        if quiet { return .closed }
        if activity != nil { return .activity }
        if live != nil { return .live }
        return .closed
    }

    var currentSize: CGSize {
        let notch = notchSize
        switch mode {
        case .open:
            return CGSize(width: max(notch.width + 520, 730), height: 274)
        case .activity:
            return CGSize(width: notch.width + activityWing * 2 + 12, height: notch.height)
        case .live:
            return CGSize(width: notch.width + liveWing * 2, height: notch.height)
        case .closed:
            return CGSize(width: notch.width + 12, height: notch.height)
        }
    }

    func show(_ activity: NotchActivity, for seconds: Double = 4) {
        guard !quiet else { return }
        activityWork?.cancel()

        let left = 12 + 16 + 7 + Fmt.textWidth(activity.title, size: 12, weight: .semibold)
        let right: CGFloat
        if activity.charging {
            right = 12 + 34 + 7 + 36
        } else if activity.level != nil {
            right = 12 + 72 + 7 + 24
        } else {
            right = 12 + Fmt.textWidth(activity.detail, size: 12, weight: .regular)
        }
        activityWing = min(max(max(left, right) + 10, 120), 300)
        self.activity = activity
        let work = DispatchWorkItem { [weak self] in
            self?.activity = nil
        }
        activityWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
