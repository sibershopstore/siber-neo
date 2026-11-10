import Foundation

/// Pomodoro: 4 focus sessions per cycle, 5-minute short breaks, 15-minute long break.
final class FocusTimer: ObservableObject {
    enum Phase: Equatable {
        case focus, shortBreak, longBreak

        var title: String {
            switch self {
            case .focus: return tr("Fokus", "Focus")
            case .shortBreak: return tr("Istirahat", "Break")
            case .longBreak: return tr("Istirahat panjang", "Long break")
            }
        }
    }

    static let sessionsPerCycle = 4

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var remaining: Int
    @Published private(set) var isRunning = false
    @Published private(set) var completedFocus = 0
    @Published var focusMinutes: Int {
        didSet {
            UserDefaults.standard.set(focusMinutes, forKey: "focusMinutes")
            if !isRunning, phase == .focus {
                remaining = totalSeconds(for: .focus)
            }
        }
    }

    var onPhaseEnd: ((Phase) -> Void)?

    private var endDate: Date?
    private var timer: Timer?

    init() {
        let stored = UserDefaults.standard.integer(forKey: "focusMinutes")
        let minutes = stored > 0 ? stored : 25
        focusMinutes = minutes
        remaining = minutes * 60
    }

    var sessionNumber: Int {
        min(completedFocus + 1, Self.sessionsPerCycle)
    }

    var progress: Double {
        let total = Double(totalSeconds(for: phase))
        guard total > 0 else { return 0 }
        return 1 - Double(remaining) / total
    }

    func totalSeconds(for phase: Phase) -> Int {
        switch phase {
        case .focus: return focusMinutes * 60
        case .shortBreak: return 5 * 60
        case .longBreak: return 15 * 60
        }
    }

    func start() {
        guard !isRunning else { return }
        if remaining <= 0 { remaining = totalSeconds(for: phase) }
        endDate = Date().addingTimeInterval(TimeInterval(remaining))
        isRunning = true
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        tick()
        stopTimer()
    }

    func reset() {
        stopTimer()
        phase = .focus
        completedFocus = 0
        remaining = totalSeconds(for: .focus)
    }

    func skip() {
        stopTimer()
        advance(notify: false)
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        if remaining == 0 {
            stopTimer()
            advance(notify: true)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        isRunning = false
    }

    private func advance(notify: Bool) {
        let ended = phase
        if ended == .focus {
            completedFocus += 1
            phase = completedFocus >= Self.sessionsPerCycle ? .longBreak : .shortBreak
        } else {
            if ended == .longBreak { completedFocus = 0 }
            phase = .focus
        }
        remaining = totalSeconds(for: phase)
        if notify {
            onPhaseEnd?(ended)
            if ended == .focus { start() }
        }
    }
}
