import Foundation

/// Energy saving mode: enabled automatically when Low Power Mode is on, or when the battery is below 20%
/// and not charging. Idle animations stop and monitoring frequency is reduced.
final class EnergyMode: ObservableObject, @unchecked Sendable {
    static let shared = EnergyMode()

    @Published private(set) var isSaving = false
    @Published var autoEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoEnabled, forKey: "energySaverAuto")
            recompute()
        }
    }

    var onChange: ((Bool) -> Void)?

    private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var lowBattery = false
    private var observer: NSObjectProtocol?

    private init() {
        autoEnabled = UserDefaults.standard.object(forKey: "energySaverAuto") as? Bool ?? true
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            self?.recompute()
        }
        recompute()
    }

    func updateBattery(percent: Int?, onAC: Bool) {
        lowBattery = !onAC && (percent ?? 100) <= 20
        recompute()
    }

    /// Used by periodic services: in energy saving mode, only one in every `factor` cycles runs.
    func shouldSkip(tick: Int, factor: Int) -> Bool {
        isSaving && tick % factor != 0
    }

    private func recompute() {
        let saving = autoEnabled && (lowPowerMode || lowBattery)
        guard saving != isSaving else { return }
        isSaving = saving
        onChange?(saving)
    }
}
