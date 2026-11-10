import AppKit

/// App entry point. Uses pure AppKit (no SwiftUI App) so no default window
/// appears; all UI lives in the notch, the menu bar, and the onboarding window.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
