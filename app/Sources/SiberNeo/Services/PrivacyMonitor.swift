import AppKit
import CoreAudio
import CoreMediaIO

/// Privacy indicator: detects the camera and microphone in use by any app.
/// Only reads device status from the system; Siber Neo never accesses the camera or microphone.
final class PrivacyMonitor: ObservableObject {
    @Published private(set) var cameraActive = false
    @Published private(set) var micActive = false
    @Published private(set) var micApps: [String] = []
    @Published private(set) var isActive = false

    var onCameraChange: ((Bool) -> Void)?
    var onMicChange: ((Bool, [String]) -> Void)?

    private var timer: Timer?
    private var tickCount = 0

    func start() {
        cameraActive = Self.isCameraRunning()
        let mic = Self.microphoneStatus()
        micActive = mic.active
        micApps = mic.apps
        isActive = cameraActive || micActive

        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        tickCount += 1
        if EnergyMode.shared.shouldSkip(tick: tickCount, factor: 3) { return }
        let camera = Self.isCameraRunning()
        if camera != cameraActive {
            cameraActive = camera
            onCameraChange?(camera)
        }

        let mic = Self.microphoneStatus()
        if mic.active != micActive {
            micActive = mic.active
            micApps = mic.apps
            onMicChange?(mic.active, mic.apps)
        } else if mic.apps != micApps {
            micApps = mic.apps
        }

        let active = cameraActive || micActive
        if active != isActive { isActive = active }
    }

    // MARK: - Camera (CoreMediaIO)

    private static func fourCC(_ code: String) -> UInt32 {
        code.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func isCameraRunning() -> Bool {
        let system = CMIOObjectID(1)
        var address = CMIOObjectPropertyAddress(
            mSelector: fourCC("dev#"),
            mScope: fourCC("glob"),
            mElement: 0
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else { return false }

        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == 0 else { return false }

        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: fourCC("gone"),
                mScope: fourCC("glob"),
                mElement: 0
            )
            var running = UInt32(0)
            var runningUsed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                device,
                &runningAddress,
                0,
                nil,
                UInt32(MemoryLayout<UInt32>.size),
                &runningUsed,
                &running
            )
            if status == 0, running != 0 { return true }
        }
        return false
    }

    // MARK: - Microphone (CoreAudio)

    static func microphoneStatus() -> (active: Bool, apps: [String]) {
        if let apps = microphoneApps() {
            return (!apps.isEmpty, apps.filter { !$0.isEmpty })
        }
        return (isInputDeviceRunning(), [])
    }

    /// Apps currently recording audio (CoreAudio process API, macOS 14).
    /// Returns nil if the API is unavailable.
    private static func microphoneApps() -> [String]? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: fourCC("prs#"),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        guard size > 0 else { return [] }

        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ignored: Set<String> = ["corespeechd", "heard", "siriactionsd", "assistantd", "localspeechrecognition", "SpeechRecognitionCore", "voicememod"]
        var names: [String] = []
        for process in processes {
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: fourCC("piri"),
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var running = UInt32(0)
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(process, &inputAddress, 0, nil, &runningSize, &running) == noErr,
                  running != 0 else { continue }

            var pidAddress = AudioObjectPropertyAddress(
                mSelector: fourCC("ppid"),
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var pid = pid_t(0)
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var name = tr("Aplikasi", "App")
            if AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr {
                if pid == ownPID { continue }
                let executable = Self.executableName(pid: pid)
                if let executable, ignored.contains(executable) { continue }
                if let app = NSRunningApplication(processIdentifier: pid), let localized = app.localizedName {
                    name = localized
                } else if let executable {
                    name = executable
                }
            }
            if let range = name.range(of: " Helper") {
                name = String(name[..<range.lowerBound])
            }
            if !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    /// Executable name of a process, for example "zoom.us" or "corespeechd".
    private static func executableName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private static func isInputDeviceRunning() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return false }

        for device in devices {
            var streams = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { continue }

            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var running = UInt32(0)
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }
}
