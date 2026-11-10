import Foundation

/// Bridge to the private MediaRemote framework for players other than Spotify and Apple Music
/// (for example YouTube in a browser). Since macOS 15.4 Apple restricts read access to "Now Playing"
/// information for third-party apps, so this source is best-effort.
final class MediaRemoteBridge {
    enum Command: UInt32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case next = 4
        case previous = 5
    }

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFn = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias SetElapsedFn = @convention(c) (Double) -> Void

    var onUpdate: (([String: Any]?) -> Void)?

    private var getInfo: GetInfoFn?
    private var register: RegisterFn?
    private var sendCommand: SendCommandFn?
    private var setElapsed: SetElapsedFn?
    private var observers: [NSObjectProtocol] = []

    init() {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL) else { return }

        func pointer(_ name: String) -> UnsafeMutableRawPointer? {
            CFBundleGetFunctionPointerForName(bundle, name as CFString)
        }

        if let p = pointer("MRMediaRemoteGetNowPlayingInfo") {
            getInfo = unsafeBitCast(p, to: GetInfoFn.self)
        }
        if let p = pointer("MRMediaRemoteRegisterForNowPlayingNotifications") {
            register = unsafeBitCast(p, to: RegisterFn.self)
        }
        if let p = pointer("MRMediaRemoteSendCommand") {
            sendCommand = unsafeBitCast(p, to: SendCommandFn.self)
        }
        if let p = pointer("MRMediaRemoteSetElapsedTime") {
            setElapsed = unsafeBitCast(p, to: SetElapsedFn.self)
        }
    }

    func start() {
        guard let register else { return }
        register(DispatchQueue.main)

        let names = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
            observers.append(token)
        }
        refresh()
    }

    func refresh() {
        guard let getInfo else { return }
        getInfo(DispatchQueue.main) { [weak self] dictionary in
            var info: [String: Any]?
            if let dictionary {
                info = (dictionary as NSDictionary) as? [String: Any]
            }
            self?.onUpdate?(info)
        }
    }

    func send(_ command: Command) {
        _ = sendCommand?(command.rawValue, nil)
    }

    func seek(to seconds: Double) {
        setElapsed?(seconds)
    }
}
