import Foundation

/// Watches the macOS screenshot folder and forwards each new screenshot to the Shelf.
/// The folder follows the macOS Screenshot setting (default: Desktop).
/// Runs on the main thread only.
final class ScreenshotWatcher: @unchecked Sendable {
    var onScreenshot: ((URL) -> Void)?

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "screenshotShelf") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "screenshotShelf") }
    }

    private var source: DispatchSourceFileSystemObject?
    private var directory = URL(fileURLWithPath: NSHomeDirectory())
    private var known = Set<String>()
    private var pendingScan: DispatchWorkItem?

    func start() {
        guard source == nil else { return }
        directory = Self.screenshotDirectory()
        known = Set(listFiles())

        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            self?.scheduleScan()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    static func screenshotDirectory() -> URL {
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !custom.isEmpty {
            let expanded = (custom as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    private func listFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
            .filter { !$0.hasPrefix(".") } ?? []
    }

    private func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scan()
        }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func scan() {
        let current = listFiles()
        let added = current.filter { !known.contains($0) }
        known = Set(current)
        guard enabled, !added.isEmpty else { return }

        let now = Date()
        for name in added {
            let url = directory.appendingPathComponent(name)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let created = attributes[.creationDate] as? Date,
                  now.timeIntervalSince(created) < 30,
                  Self.isScreenshot(url) else { continue }
            onScreenshot?(url)
        }
    }

    /// macOS screenshots carry the Spotlight attribute kMDItemIsScreenCapture; the file name is used as a fallback.
    static func isScreenshot(_ url: URL) -> Bool {
        let attribute = "com.apple.metadata:kMDItemIsScreenCapture"
        if getxattr(url.path, attribute, nil, 0, 0, 0) > 0 {
            return true
        }
        let ext = url.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "heic", "mov", "tiff", "pdf"].contains(ext) else { return false }
        let name = url.lastPathComponent.lowercased()
        let prefixes = ["screenshot", "screen shot", "cuplikan layar", "rekaman layar", "screen recording"]
        return prefixes.contains { name.hasPrefix($0) }
    }
}
