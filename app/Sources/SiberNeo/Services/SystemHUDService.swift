import AppKit
import AudioToolbox
import Carbon
import CoreAudio

/// Monitors volume, display brightness, Caps Lock, and keyboard input source for display in the notch.
/// No Accessibility permission required: volume uses a CoreAudio listener, while Caps Lock and
/// brightness are polled periodically at very low cost.
final class SystemHUDService {
    var onVolume: ((Float, Bool) -> Void)?
    var onBrightness: ((Float) -> Void)?
    var onCapsLock: ((Bool) -> Void)?
    var onInputSource: ((String) -> Void)?

    private typealias BrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

    private var outputDevice = AudioObjectID(0)
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var lastVolume: Float?
    private var lastMuted: Bool?

    private var getBrightness: BrightnessFn?
    private var lastBrightness: Float?

    private var capsLock = false
    private var timer: Timer?
    private var tickCount = 0
    private var keyMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    func start() {
        setupVolume()
        setupBrightness()
        capsLock = Self.isCapsLockOn()

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handleSystemKey(event)
        }

        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let name = Self.currentInputSourceName() {
                self?.onInputSource?(name)
            }
        })
    }

    // MARK: - Volume

    private static let volumeAddresses: [AudioObjectPropertyAddress] = [
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        ),
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    ]

    private func setupVolume() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { [weak self] _, _ in
            self?.attachVolumeListener()
        }
        attachVolumeListener()
    }

    private func attachVolumeListener() {
        if outputDevice != 0, let listener = volumeListener {
            for var address in Self.volumeAddresses {
                AudioObjectRemovePropertyListenerBlock(outputDevice, &address, DispatchQueue.main, listener)
            }
        }

        outputDevice = Self.defaultOutputDevice()
        lastVolume = readVolume()
        lastMuted = readMuted()

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.volumeChanged()
        }
        volumeListener = listener
        for var address in Self.volumeAddresses {
            if AudioObjectHasProperty(outputDevice, &address) {
                AudioObjectAddPropertyListenerBlock(outputDevice, &address, DispatchQueue.main, listener)
            }
        }
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    private func readVolume() -> Float? {
        var address = Self.volumeAddresses[0]
        guard outputDevice != 0, AudioObjectHasProperty(outputDevice, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(outputDevice, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func readMuted() -> Bool {
        var address = Self.volumeAddresses[1]
        guard outputDevice != 0, AudioObjectHasProperty(outputDevice, &address) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(outputDevice, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private func volumeChanged() {
        guard let volume = readVolume() else { return }
        let muted = readMuted()
        if let last = lastVolume, abs(last - volume) < 0.001, muted == lastMuted { return }
        lastVolume = volume
        lastMuted = muted
        onVolume?(volume, muted)
    }

    // MARK: - Brightness

    private func setupBrightness() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return }
        getBrightness = unsafeBitCast(symbol, to: BrightnessFn.self)
        lastBrightness = readBrightness()
    }

    private func readBrightness() -> Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(CGMainDisplayID(), &value) == 0 else { return nil }
        return value
    }

    /// Small gradual changes (auto-brightness) are ignored; changes from keys are always shown.
    private func checkBrightness(fromKey: Bool) {
        guard let value = readBrightness() else { return }
        defer { lastBrightness = value }
        guard let last = lastBrightness else { return }
        let delta = abs(value - last)
        if delta >= 0.04 || (fromKey && delta > 0.001) {
            onBrightness?(value)
        }
    }

    private func handleSystemKey(_ event: NSEvent) {
        guard event.subtype.rawValue == 8 else { return }
        let keyCode = (event.data1 & 0xFFFF0000) >> 16
        let keyState = (event.data1 & 0xFF00) >> 8
        guard keyState == 0x0A, keyCode == 2 || keyCode == 3 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.checkBrightness(fromKey: true)
        }
    }

    // MARK: - Caps Lock & keyboard

    private func tick() {
        tickCount += 1
        if EnergyMode.shared.shouldSkip(tick: tickCount, factor: 4) { return }
        let caps = Self.isCapsLockOn()
        if caps != capsLock {
            capsLock = caps
            onCapsLock?(caps)
        }
        if tickCount % 2 == 0 {
            checkBrightness(fromKey: false)
        }
    }

    static func isCapsLockOn() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    static func currentInputSourceName() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
