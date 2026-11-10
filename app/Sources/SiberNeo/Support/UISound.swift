import AppKit

/// Subtle, optional interface sounds. Muted automatically while presentation mode is active.
enum UISound {
    case open, drop, unlock

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "uiSounds") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "uiSounds") }
    }

    private var name: String {
        switch self {
        case .open: return "Tink"
        case .drop: return "Pop"
        case .unlock: return "Hero"
        }
    }

    private var volume: Float {
        switch self {
        case .open: return 0.12
        case .drop: return 0.25
        case .unlock: return 0.3
        }
    }

    func play() {
        guard Self.enabled, !Notifier.isMuted,
              let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }
}
