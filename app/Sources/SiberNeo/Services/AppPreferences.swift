import Foundation

/// Preferences changed from inside the notch that must update the UI immediately.
final class AppPreferences: ObservableObject {
    @Published var screenshotShelf: Bool {
        didSet { UserDefaults.standard.set(screenshotShelf, forKey: "screenshotShelf") }
    }

    init() {
        screenshotShelf = UserDefaults.standard.object(forKey: "screenshotShelf") as? Bool ?? true
    }
}
