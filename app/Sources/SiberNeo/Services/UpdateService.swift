import AppKit

/// Latest version information from the official site (latest.json).
struct UpdateInfo: Decodable, Equatable {
    struct Notes: Decodable, Equatable {
        let id: [String]?
        let en: [String]?
    }

    let version: String
    let url: String
    let notes: Notes?
    let minimumSystem: String?

    var localizedNotes: [String] {
        (Lang.isIndonesian ? notes?.id : notes?.en) ?? notes?.en ?? notes?.id ?? []
    }
}

/// Checks for updates from the official Siber Group site at launch and every 12 hours.
/// Download links are accepted only from the official Siber Neo domain over HTTPS.
final class UpdateService: ObservableObject {
    enum CheckResult {
        case upToDate, available(UpdateInfo), failed
    }

    static let feedURL = URL(string: "https://neo.sibershopstore.com/latest.json")!
    static let trustedHosts: Set<String> = ["neo.sibershopstore.com"]

    @Published private(set) var available: UpdateInfo?

    var onAvailable: ((UpdateInfo) -> Void)?

    private var timer: Timer?
    private var started = false

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func start() {
        guard !started else { return }
        started = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.check(userInitiated: false)
        }
        let timer = Timer(timeInterval: 12 * 3600, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// `userInitiated` shows previously skipped versions and does not trigger automatic notifications.
    func check(userInitiated: Bool, completion: ((CheckResult) -> Void)? = nil) {
        var request = URLRequest(url: Self.feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("SiberNeo/\(Self.currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let info: UpdateInfo? = {
                guard let data,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(UpdateInfo.self, from: data),
                      Self.isTrusted(decoded.url) else { return nil }
                return decoded
            }()

            DispatchQueue.main.async {
                guard let self else { return }
                guard let info else {
                    completion?(.failed)
                    return
                }
                guard Self.isNewer(info.version, than: Self.currentVersion), Self.systemSupports(info.minimumSystem) else {
                    self.available = nil
                    completion?(.upToDate)
                    return
                }
                let skipped = UserDefaults.standard.string(forKey: "skippedUpdateVersion")
                if !userInitiated, skipped == info.version {
                    completion?(.upToDate)
                    return
                }
                let isNew = self.available != info
                self.available = info
                if isNew, !userInitiated {
                    self.onAvailable?(info)
                }
                completion?(.available(info))
            }
        }.resume()
    }

    func openDownload() {
        guard let info = available, let url = URL(string: info.url) else { return }
        NSWorkspace.shared.open(url)
    }

    func skipCurrent() {
        guard let info = available else { return }
        UserDefaults.standard.set(info.version, forKey: "skippedUpdateVersion")
        available = nil
    }

    // MARK: - Helpers

    static func isTrusted(_ address: String) -> Bool {
        guard let url = URL(string: address), url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return trustedHosts.contains(host)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    static func systemSupports(_ minimum: String?) -> Bool {
        guard let minimum else { return true }
        let parts = minimum.split(separator: ".").map { Int($0) ?? 0 }
        let required = OperatingSystemVersion(
            majorVersion: parts.count > 0 ? parts[0] : 0,
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0
        )
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(required)
    }
}
