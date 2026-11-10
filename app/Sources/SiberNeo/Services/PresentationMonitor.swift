import AppKit
import CoreGraphics

/// Presentation mode: hides notifications, live view, and notch sounds while presenting.
/// Enabled automatically when the display is mirrored to a projector or when the frontmost app shows a
/// full-screen window (Keynote, PowerPoint, or Google Slides slideshows, full-screen video). Can also be enabled manually.
final class PresentationMonitor: ObservableObject {
    @Published var manual = false {
        didSet { updateActive() }
    }
    @Published var autoEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoEnabled, forKey: "presentationAuto")
            updateActive()
        }
    }
    @Published private(set) var autoReason: String?
    @Published private(set) var isActive = false

    private var timer: Timer?

    init() {
        autoEnabled = UserDefaults.standard.object(forKey: "presentationAuto") as? Bool ?? true
    }

    func start() {
        poll()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let reason: String?
        if Self.isMirroring() {
            reason = tr("Layar dicerminkan", "Display mirrored")
        } else if let app = Self.fullScreenFrontApp() {
            reason = app
        } else {
            reason = nil
        }
        if reason != autoReason {
            autoReason = reason
        }
        updateActive()
    }

    private func updateActive() {
        let active = manual || (autoEnabled && autoReason != nil)
        if active != isActive {
            isActive = active
        }
    }

    // MARK: - Detection

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    /// Display mirrored to a projector or TV.
    static func isMirroring() -> Bool {
        let displays = activeDisplays()
        guard displays.count > 1 else { return false }
        return displays.contains { CGDisplayIsInMirrorSet($0) != 0 }
    }

    /// Name of the frontmost app if one of its windows covers the entire screen.
    static func fullScreenFrontApp() -> String? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier,
              front.bundleIdentifier != "com.apple.finder",
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let screens = activeDisplays().map { CGDisplayBounds($0) }
        let pid = front.processIdentifier

        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int32, owner == pid,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { continue }

            let coversScreen = screens.contains { screen in
                abs(bounds.minX - screen.minX) < 2 &&
                abs(bounds.minY - screen.minY) < 2 &&
                bounds.width >= screen.width - 2 &&
                bounds.height >= screen.height - 2
            }
            if coversScreen {
                return front.localizedName ?? tr("Layar penuh", "Full screen")
            }
        }
        return nil
    }
}
